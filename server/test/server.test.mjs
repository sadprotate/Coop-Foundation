import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { performance } from 'node:perf_hooks';
import WebSocket from 'ws';
import { startServer } from '../server.mjs';

const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

async function fixture(t, options = {}) {
  const server = await startServer({ host: '127.0.0.1', port: 0, ...options });
  t.after(() => server.close());
  return server;
}

async function connect(server, options = {}) {
  const ws = new WebSocket(`ws://127.0.0.1:${server.port}/ws`, options);
  const client = { ws, server, messages: [], receivedAt: new WeakMap(), latest: null, room: null, seq: 0, actionSeq: 0 };
  (server.testClients ??= []).push(client);
  ws.on('message', raw => {
    const message = JSON.parse(raw);
    client.receivedAt.set(message, performance.now());
    client.messages.push(message);
    if (message.type === 'state') client.latest = message;
    if (message.type === 'room') client.room = message;
  });
  // A fixture closes its sockets during cleanup; unexpected transport errors are
  // surfaced by the pending open/wait calls rather than crashing the test runner.
  ws.on('error', () => {});
  client.send = message => ws.send(JSON.stringify(message));
  client.mark = () => client.messages.length;
  client.wait = async (predicate, { from = 0, timeout = 2500 } = {}) => {
    const end = Date.now() + timeout;
    while (Date.now() < end) {
      const found = client.messages.slice(from).find(predicate);
      if (found) return found;
      await pause(10);
    }
    throw new Error(`Timed out waiting for message. Recent messages: ${JSON.stringify(client.messages.slice(-3))}`);
  };
  await once(ws, 'open');
  const welcome = await client.wait(m => m.type === 'welcome');
  assert.equal(welcome.protocol, 4);
  assert.match(welcome.id, /^[a-f0-9-]{36}$/);
  client.id = welcome.id;
  return client;
}

async function create(client, name = 'Host') {
  const from = client.mark();
  client.send({ type: 'create', protocol: 4, name });
  return client.wait(m => m.type === 'room' && m.code, { from });
}

async function join(client, code, name) {
  const from = client.mark();
  client.send({ type: 'join', protocol: 4, code, name });
  return client.wait(m => m.type === 'room' && m.code === code, { from });
}

async function expectError(client, message, expression) {
  const from = client.mark();
  client.send(message);
  const result = await client.wait(m => m.type === 'error', { from });
  assert.match(result.message, expression);
}

async function start(client) {
  await moveTo(client, 0, -4);
  const from = client.mark();
  client.send({ type: 'start' });
  await client.wait(m => m.type === 'room' && m.phase === 'ready_check', { from });
  for (const peer of client.server.testClients) {
    if (peer.room?.code === client.room.code) peer.send({ type: 'ready', ready: true });
  }
  return client.wait(m => m.type === 'state' && m.phase === 'playing', { from });
}

function input(client, x = 0, z = 0, yaw = 0, block = false) {
  client.send({ type: 'input', x, z, yaw, block, seq: client.seq++ });
}

function action(client, type) { client.send({ type, action_seq: ++client.actionSeq }); }
function player(client, id = client.id) { return client.latest?.players.find(p => p.id === id); }

async function moveFor(client, x, z, milliseconds) {
  input(client, x, z);
  const timer = setInterval(() => input(client, x, z), 50);
  try { await pause(milliseconds); } finally { clearInterval(timer); input(client); }
  await pause(100);
}

async function moveTo(client, x, z) {
  const deadline = Date.now() + 6000;
  while (Date.now() < deadline) {
    const p = player(client);
    if (p) {
      const dx = x - p.x, dz = z - p.z;
      if (Math.hypot(dx, dz) <= 0.08) { input(client); await pause(80); return; }
      input(client, dx / 0.55, dz / 0.55);
    }
    await pause(50);
  }
  throw new Error('A client could not reach its requested arena position using movement inputs.');
}

async function punch(client, expectedKind, expectedDamage) {
  const from = client.mark();
  action(client, 'punch');
  const event = await client.wait(m => m.type === 'combat' && m.kind === expectedKind && m.attacker === client.id, { from });
  assert.equal(event.damage, expectedDamage);
  return event;
}

test('health, room codes, four-player capacity, readiness, host controls, leave and rejoin', async t => {
  const server = await fixture(t);
  const health = await fetch(`http://127.0.0.1:${server.port}/health`).then(r => r.json());
  assert.equal(health.ok, true);
  assert.equal(health.protocol, 4);
  assert.equal(health.rooms, 0);
  const clients = await Promise.all(Array.from({ length: 5 }, () => connect(server)));
  const [host, second, third, fourth, extra] = clients;
  const room = await create(host);
  assert.match(room.code, /^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$/);
  assert.equal(room.host_id, host.id);
  assert.equal(room.players[0].ready, false);
  second.send({ type: 'join', protocol: 4, code: room.code.toLowerCase(), name: 'Second' });
  await second.wait(m => m.type === 'room' && m.code === room.code);
  await join(third, room.code, 'Third');
  const full = await join(fourth, room.code, 'Fourth');
  assert.equal(full.players.length, 4);
  assert.deepEqual(full.players.map(p => p.slot), [0, 1, 2, 3]);
  await expectError(extra, { type: 'join', protocol: 4, code: room.code, name: 'Extra' }, /full/i);
  await expectError(host, { type: 'start' }, /closer to the Old Man/);
  await expectError(second, { type: 'start' }, /Only the room host/);
  const playing = await start(host);
  assert.equal(playing.players.length, 4);
  assert.equal(playing.level, 3);
  assert.ok(playing.players.every(p => p.health === 100 && p.y === 0 && p.grounded));
  await expectError(extra, { type: 'join', protocol: 4, code: room.code, name: 'Extra' }, /in a round/);
  await expectError(second, { type: 'restart' }, /Only the room host/);
  await expectError(second, { type: 'lobby' }, /Only the room host/);
  const from = host.mark();
  fourth.send({ type: 'leave' });
  const remaining = await host.wait(m => m.type === 'room' && m.phase === 'lobby' && m.players.length === 3, { from });
  assert.equal(remaining.players.filter(p => p.ready).length, 0);
  await fourth.wait(m => m.type === 'room' && m.code === '');
  const rejoined = await join(fourth, room.code, 'Fourth again');
  assert.equal(rejoined.players.length, 4);
  assert.equal(rejoined.players.find(p => p.id === fourth.id).slot, 3);
  assert.equal(rejoined.players.find(p => p.id === fourth.id).ready, false);
});

test('normalized movement, yaw, jump, stale input stop, old sequences, and world bounds', async t => {
  const server = await fixture(t);
  const client = await connect(server);
  await create(client);
  await start(client);
  const before = { ...player(client) };
  const from = client.mark();
  input(client, 1, 1, 1.25, false);
  const moved = await client.wait(m => m.type === 'state' && m.players[0].x > before.x, { from });
  const distance = Math.hypot(moved.players[0].x - before.x, moved.players[0].z - before.z);
  const movementSteps = distance / 0.275;
  assert.ok(movementSteps >= 0.995 && movementSteps <= 2.005 && Math.abs(movementSteps - Math.round(movementSteps)) < 0.005,
    `One callback travelled ${distance}; expected one or two normalized .275 m steps.`);
  assert.equal(moved.players[0].yaw, 1.25);
  await pause(450);
  const stopped = { ...player(client) };
  assert.ok(Math.hypot(stopped.x - before.x, stopped.z - before.z) <= 1.651);
  await pause(200);
  assert.equal(player(client).x, stopped.x);
  assert.equal(player(client).z, stopped.z);
  client.send({ type: 'input', x: -1, z: 0, yaw: 0, block: true, seq: 0 });
  await pause(100);
  assert.equal(player(client).x, stopped.x, 'An old sequence must not change movement.');
  assert.equal(player(client).yaw, stopped.yaw);
  const jumpFrom = client.mark();
  action(client, 'jump');
  const jumped = await client.wait(m => m.type === 'state' && !m.players[0].grounded && m.players[0].y > 0, { from: jumpFrom });
  assert.ok(jumped.players[0].y <= 0.651, 'One callback can advance at most two jump steps.');
  await client.wait(m => m.type === 'state' && m.tick > jumped.tick && m.players[0].grounded, { from: jumpFrom });
  assert.equal(player(client).y, 0);
  input(client, 0, 0, 0, true);
  await client.wait(m => m.type === 'state' && m.players[0].block, { from: client.mark() });
  await pause(400);
  assert.equal(player(client).block, false, 'Stale blocking must expire too.');
  await moveFor(client, 999999, 0, 5600);
  assert.equal(player(client).x, 18, 'Server clamps untrusted movement and right boundary.');
  await moveFor(client, 0, -999999, 4700);
  assert.equal(player(client).z, -18, 'Server clamps back boundary.');
});

test('four real WebSocket clients: exact combat damage, frontal/rear blocks, defeat/respawn, protection and restart', async t => {
  const server = await fixture(t);
  const clients = await Promise.all(Array.from({ length: 4 }, () => connect(server)));
  const [host, target, third, fourth] = clients;
  const room = await create(host);
  for (const [i, c] of clients.slice(1).entries()) {
    await join(c, room.code, `Player ${i + 2}`);
  }
  host.send({ type: 'god_options', options: { knockback_strength: 0 } });
  await host.wait(m => m.type === 'room' && m.god_options?.knockback_strength === 0);
  const firstRound = (await start(host)).round_id;
  await Promise.all([moveTo(host, 0, 0), moveTo(target, 0, -1.5)]);
  input(host);
  const normal = await punch(host, 'hit', 10);
  assert.equal(normal.target, target.id);
  assert.equal(normal.critical, false);
  await host.wait(m => m.type === 'state' && m.players.find(p => p.id === target.id)?.health === 90);
  for (const observer of [target, third, fourth]) {
    await observer.wait(m => m.type === 'combat' && m.event_id === normal.event_id && m.damage === 10);
    await observer.wait(m => m.type === 'state' && m.players.find(p => p.id === target.id)?.health === 90);
  }
  action(host, 'punch'); // Cooldown rejects even a new sequence.
  host.send({ type: 'punch', action_seq: 1, damage: 999, target: target.id });
  await pause(150);
  assert.equal(player(host, target.id).health, 90);
  await pause(400);
  action(host, 'jump');
  const critical = await punch(host, 'hit', 20);
  assert.equal(critical.critical, true);
  const landedFrom = host.mark();
  await host.wait(m => m.type === 'state' && m.players.find(p => p.id === host.id).grounded, { from: landedFrom, timeout: 2000 });
  assert.equal(player(host, target.id).health, 70);
  let targetYaw = Math.PI;
  input(target, 0, 0, targetYaw, true);
  const blockTimer = setInterval(() => input(target, 0, 0, targetYaw, true), 50);
  try {
    await host.wait(m => m.type === 'state' && m.players.find(p => p.id === target.id)?.block, { from: host.mark() });
    await punch(host, 'blocked', 0);
    assert.equal(player(host, target.id).health, 70);
    targetYaw = 0;
    input(target, 0, 0, targetYaw, true);
    await pause(550);
    await punch(host, 'hit', 10);
  } finally { clearInterval(blockTimer); input(target); }
  await host.wait(m => m.type === 'state' && m.players.find(p => p.id === target.id)?.health === 60);
  for (let hit = 0; hit < 6; hit++) { await pause(550); await punch(host, 'hit', 10); }
  const defeat = await host.wait(m => m.type === 'combat' && m.kind === 'defeat' && m.target === target.id);
  await host.wait(m => m.type === 'state' && m.players.find(p => p.id === target.id)?.health === 0);
  const dead = { ...player(host, target.id) };
  target.send({ type: 'input', x: 1, z: 1, yaw: 0, block: true, seq: target.seq++, health: 100, invulnerable: true });
  action(target, 'jump');
  action(target, 'punch');
  await pause(150);
  assert.equal(player(host, target.id).health, 0, 'Client-provided health is ignored.');
  assert.equal(player(host, target.id).x, dead.x, 'A defeated player cannot move.');
  assert.equal(player(host, target.id).z, dead.z);
  await moveTo(host, 4, 1.5);
  const respawn = await host.wait(m => m.type === 'combat' && m.kind === 'respawn' && m.target === target.id, { timeout: 4000 });
  assert.ok(respawn.event_id > defeat.event_id);
  const respawnElapsedMs = host.receivedAt.get(respawn) - host.receivedAt.get(defeat);
  t.diagnostic(`Measured defeat-to-respawn elapsed time: ${respawnElapsedMs.toFixed(1)} ms (target 3000 ms).`);
  assert.ok(respawnElapsedMs >= 2850 && respawnElapsedMs <= 3300,
    `Respawn took ${respawnElapsedMs.toFixed(1)} ms; normal timer jitter must not turn three seconds into four.`);
  await host.wait(m => m.type === 'state' && m.players.find(p => p.id === target.id)?.health === 100 && m.players.find(p => p.id === target.id)?.invulnerable);
  assert.deepEqual([player(host, target.id).x, player(host, target.id).y, player(host, target.id).z], [4, 0, 0]);
  input(host);
  await punch(host, 'blocked', 0);
  await host.wait(m => m.type === 'state' && !m.players.find(p => p.id === target.id)?.invulnerable, { from: host.mark() });
  await punch(host, 'hit', 10);
  const restartFrom = host.mark();
  host.send({ type: 'restart' });
  const restarted = await host.wait(m => m.type === 'state' && m.players.every(p => p.health === 100), { from: restartFrom });
  assert.ok(restarted.round_id > firstRound, 'Restart advances round_id for client action reconciliation.');
  assert.deepEqual(restarted.players.map(p => [p.x, p.y, p.z]), [[-4, 0, 0], [4, 0, 0], [0, 0, -5], [0, 0, 5]]);
  assert.ok(restarted.players.every(p => !p.invulnerable && p.grounded && !p.block && p.action_seq === 0 && p.vy === 0));
  const lobbyFrom = host.mark();
  host.send({ type: 'lobby' });
  const lobby = await host.wait(m => m.type === 'room' && m.phase === 'lobby', { from: lobbyFrom });
  assert.equal(lobby.players.find(p => p.id === host.id).ready, false);
  assert.ok(lobby.players.filter(p => p.id !== host.id).every(p => !p.ready));
});

test('host disconnect transfers host, resets active round, and final disconnect removes room', async t => {
  const server = await fixture(t);
  const [host, second] = await Promise.all([connect(server), connect(server)]);
  const room = await create(host);
  await join(second, room.code, 'Second');
  await start(host);
  const from = second.mark();
  host.ws.terminate();
  const transferred = await second.wait(m => m.type === 'room' && m.host_id === second.id, { from });
  assert.equal(transferred.phase, 'lobby');
  assert.equal(transferred.players.length, 1);
  assert.equal(transferred.players[0].ready, false);
  await second.wait(m => m.type === 'notice' && /left/.test(m.message), { from });
  second.ws.close();
  await once(second.ws, 'close');
  await pause(40);
  assert.equal(server.stats().rooms, 0);
  assert.equal(server.stats().connections, 0);
});

test('room capacity, validation, pings, and rate limits', async t => {
  const server = await fixture(t, { maxRooms: 1 });
  const [host, other] = await Promise.all([connect(server), connect(server)]);
  await create(host);
  await expectError(other, { type: 'create', protocol: 4, name: 'Other' }, /no free rooms/);
  await expectError(other, { type: 'join', protocol: 4, code: 'AAAAAA', name: 'Other' }, /not found/);
  await expectError(other, { type: 'create', protocol: 4, name: '' }, /player name/);
  await expectError(other, { type: 'join', protocol: 4, code: '<bad>', name: 'Other' }, /six letters/);
  const malformedFrom = other.mark();
  other.ws.send('{');
  await other.wait(m => m.type === 'error' && /Invalid JSON/.test(m.message), { from: malformedFrom });
  await expectError(host, { type: 'ready', ready: 'yes' }, /true or false/);
  host.send({ type: 'ping', t: 12345 });
  await host.wait(m => m.type === 'pong' && m.t === 12345);
  await start(host);
  await expectError(host, { type: 'input', x: '1', z: 0, yaw: 0, block: false, seq: 1 }, /finite/);
  const closed = once(other.ws, 'close');
  for (let i = 0; i < 150; i++) other.send({ type: 'ping', t: i });
  const [code] = await closed;
  assert.equal(code, 1008);
});

test('idle rooms expire and heartbeat removes unresponsive connections', async t => {
  const server = await fixture(t, { idleMs: 150, heartbeatMs: 30 });
  const host = await connect(server);
  await create(host);
  await host.wait(m => m.type === 'room' && m.code === '');
  assert.equal(server.stats().rooms, 0);
  const silent = await connect(server, { autoPong: false });
  await once(silent.ws, 'close');
  await pause(30);
  assert.equal(server.stats().connections, 1, 'Responsive client survives while silent client is removed.');
});

test('protocol mismatch rejects old/missing versions and invalid combat intent cannot set state', async t => {
  const server = await fixture(t);
  const client = await connect(server);
  await expectError(client, { type: 'create', name: 'Old' }, /version mismatch.*protocol 4/);
  await expectError(client, { type: 'join', protocol: 1, code: 'AAAAAA', name: 'Old' }, /version mismatch/);
  await create(client);
  await start(client);
  await expectError(client, { type: 'input', x: 0, z: 0, yaw: null, block: false, seq: 1 }, /finite/);
  await expectError(client, { type: 'punch', action_seq: 0 }, /positive integer/);
  await expectError(client, { type: 'hit', damage: 100, health: 0 }, /Unknown message/);
  const from = client.mark();
  client.send({ type: 'input', x: 0, z: 0, yaw: 0, block: false, seq: 1, y: 999, health: 0, damage: 999 });
  await client.wait(m => m.type === 'state', { from });
  assert.equal(player(client).health, 100);
  assert.equal(player(client).y, 0);
});

test('host stamina settings and crouched body propagate across clients; forged state and guest rules are rejected', async t => {
  const server = await fixture(t);
  const [host, guest] = await Promise.all([connect(server), connect(server)]);
  const room = await create(host);
  await join(guest, room.code, 'Guest');
  await expectError(guest, { type: 'set_options', options: { stamina_drain: 0 } }, /Only the room host/);
  host.send({ type: 'god_options', options: { max_stamina: 10, stamina_drain: 20,
    stamina_regen: 10, stamina_regen_delay: 0.2, sprint_speed: 8, starting_health: 55 } });
  const configured = await guest.wait(m => m.type === 'room' && m.god_options?.max_stamina === 10);
  assert.equal(configured.god_options.starting_health, 55);
  await start(host);
  const startState = await guest.wait(m => m.type === 'state' && m.phase === 'playing');
  assert.ok(startState.players.every(p => p.health === 55 && p.stamina === 10));
  await expectError(guest, { type: 'input', x: 1, z: 0, yaw: 0, block: false, sprint: 'yes', seq: 1 }, /boolean/);
  const sprintInput = () => guest.send({ type: 'input', x: 1, z: 0, yaw: 0, block: false,
    sprint: true, crouch: false, seq: guest.seq++, stamina: 9999, sprinting: true });
  const from = host.mark();
  sprintInput();
  const timer = setInterval(sprintInput, 50);
  try {
    const sprinting = await host.wait(m => m.type === 'state' && m.players.some(p => p.id === guest.id && p.sprinting), { from });
    const observed = sprinting.players.find(p => p.id === guest.id);
    assert.ok(observed.stamina < 10 && observed.stamina >= 0);
    assert.equal(observed.max_stamina, 10);
    await host.wait(m => m.type === 'state' && m.players.some(p => p.id === guest.id && p.sprint_exhausted && !p.sprinting), { from });
    await pause(400);
    assert.equal(player(host, guest.id).sprinting, false);
    assert.ok(player(host, guest.id).stamina > 0);
  } finally { clearInterval(timer); }
  const crouchFrom = host.mark();
  guest.send({ type: 'input', x: 0, z: 0, yaw: 0, block: false, sprint: false, crouch: true,
    seq: guest.seq++, body_height: 999, health: 999 });
  const crouched = await host.wait(m => m.type === 'state' && m.players.some(p => p.id === guest.id && p.crouching), { from: crouchFrom });
  const body = crouched.players.find(p => p.id === guest.id);
  assert.equal(body.body_height, 0.95);
  assert.equal(body.health, 55);
  assert.equal(body.sprint_exhausted, false);
  await host.wait(m => m.type === 'state' && m.tick > crouched.tick && m.players.some(p => p.id === guest.id && !p.crouching), { from: crouchFrom });
});

test('host selects exact 2v2 in Town; friendly fire stays blocked and shared live options remain host-only', async t => {
  const server = await fixture(t);
  const clients = await Promise.all(Array.from({ length: 4 }, () => connect(server)));
  const [host, second, third, fourth] = clients;
  const room = await create(host);
  for (const [i, client] of clients.slice(1).entries()) await join(client, room.code, `Player ${i + 2}`);
  await expectError(second, { type: 'set_mode', mode: 'teams' }, /Only the room host/);
  await expectError(third, { type: 'god_options', options: { god_mode: true } }, /Only the room host/);
  await expectError(fourth, { type: 'god_options', reset: true }, /Only the room host/);
  host.send({ type: 'set_mode', mode: 'teams' });
  await host.wait(m => m.type === 'room' && m.mode === 'teams');
  second.send({ type: 'set_party', party: 0 });
  await host.wait(m => m.type === 'room' && m.players.filter(p => p.party === 0).length === 3);
  await moveTo(host, 0, -4);
  await expectError(host, { type: 'start' }, /four players: two on Red and two on Blue/);
  second.send({ type: 'set_party', party: 1 });
  await host.wait(m => m.type === 'room' && m.players.filter(p => p.party === 0).length === 2);
  const playing = await start(host);
  assert.equal(playing.mode, 'teams');
  assert.deepEqual(Object.keys(playing.match.round_scores), ['red', 'blue']);
  await expectError(second, { type: 'set_party', party: 0 }, /Town Lobby/);
  await expectError(host, { type: 'set_mode', mode: 'ffa' }, /Town Lobby/);
  await Promise.all([moveTo(host, 0, 0), moveTo(third, 0, -1.5)]);
  input(host);
  await punch(host, 'miss', 0);
  assert.equal(player(host, third.id).health, 100);
  const optionsFrom = fourth.mark();
  host.send({ type: 'god_options', options: { god_mode: true, attack_speed: 10,
    attack_damage: 33.5, max_health: 250.7, sprint_speed: 15, max_stamina: 200 } });
  const changed = await fourth.wait(m => m.type === 'state' && m.god_options.god_mode, { from: optionsFrom });
  assert.equal(changed.god_options.max_health, 251);
  assert.ok(changed.players.every(p => p.max_health === 251 && p.max_stamina === 200));
  await expectError(host, { type: 'god_options', options: [] }, /object/);
  await expectError(host, { type: 'god_options', options: null }, /object/);
  await moveTo(third, -5, -5);
  await moveTo(second, 0, -1.5);
  input(host);
  await punch(host, 'blocked', 0);
  const townFrom = host.mark();
  host.send({ type: 'lobby' });
  await host.wait(m => m.type === 'room' && m.phase === 'lobby', { from: townFrom });
  host.send({ type: 'set_mode', mode: 'ffa' });
  host.send({ type: 'god_options', reset: true });
  await host.wait(m => m.type === 'room' && m.mode === 'ffa' && !m.god_options.god_mode, { from: townFrom });
  await start(host);
  await Promise.all([moveTo(host, 0, 0), moveTo(third, 0, -1.5)]);
  input(host);
  await punch(host, 'hit', 10);
});
