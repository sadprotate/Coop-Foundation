import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, connect, create, join, expectError, input, action, player, moveTo,
  pause, requestBattle, startBattle } from './helpers.mjs';

async function peers(t, options = {}) {
  const server = await fixture(t);
  const [host, guest] = await Promise.all([connect(server), connect(server)]);
  const room = await create(host, 'Round winner');
  await join(guest, room.code, 'Opponent');
  host.send({ type: 'god_options', options: { total_rounds: 1, knockouts_to_win: 1,
    starting_health: 10, attack_damage: 10, knockback_strength: 0, ...options } });
  await guest.wait(message => message.type === 'room' && message.god_options.starting_health === 10);
  return [host, guest];
}

async function winRound(host, guest) {
  await Promise.all([moveTo(host, 0, 0), moveTo(guest, 0, -1.5)]);
  input(host);
  const from = host.mark();
  action(host, 'punch');
  return host.wait(message => message.type === 'state' && message.match.phase === 'round_end', { from });
}

test('authoritative KO ends round, freezes play, replicates victory, returns safe Town, and requires fresh readiness', async t => {
  const [host, guest] = await peers(t);
  const started = await startBattle(host, [host, guest]);
  const ended = await winRound(host, guest);
  assert.equal(ended.match.round_winner, host.id);
  assert.equal(ended.match.round_scores[host.id], 1);
  assert.equal(ended.match.round_wins[host.id], 1);
  assert.equal(ended.match.round_number, 1);
  assert.equal(ended.match.transition_time_left, 3);
  const endFrom = host.mark(), frozen = { ...player(host) };
  input(host, 1, 0, { sprint: true });
  action(host, 'jump');
  action(host, 'punch');
  host.send({ type: 'defeat', attacker: host.id, target: guest.id, event_id: 999 });
  await host.wait(message => message.type === 'error' && /Unknown message/.test(message.message), { from: endFrom });
  await pause(250);
  assert.equal(player(host).x, frozen.x);
  assert.equal(player(host).y, frozen.y);
  assert.equal(host.latest.match.round_scores[host.id], 1);
  assert.equal(host.messages.slice(endFrom).some(message => message.type === 'combat'), false,
    'Inputs cannot create attacks or jumps during the round break.');
  const victory = await host.wait(message => message.type === 'state' && message.match.phase === 'victory', { from: endFrom, timeout: 4500 });
  assert.deepEqual(victory.match.winner_ids, [host.id]);
  assert.deepEqual(victory.match.winner_names, ['Round winner']);
  await guest.wait(message => message.type === 'state' && message.match.phase === 'victory' && message.match.winner_ids[0] === host.id);
  const victoryAt = Date.now(), victoryFrom = host.mark();
  input(host, -1, 0);
  action(host, 'punch');
  await pause(200);
  assert.equal(player(host).x, frozen.x);
  const returned = await host.wait(message => message.type === 'state' && message.zone === 'town', { from: victoryFrom, timeout: 7000 });
  assert.ok(Date.now() - victoryAt >= 5600, 'Victory remains visible for approximately six seconds.');
  assert.ok(returned.round_id > started.round_id);
  assert.equal(returned.safe_zone, true);
  assert.ok(returned.players.every(p => p.health === 10 && p.stamina === 100));
  assert.deepEqual(returned.match.round_scores, {});
  assert.deepEqual(returned.match.round_wins, {});
  assert.deepEqual(returned.match.winner_ids, []);
  const check = await requestBattle(host);
  assert.ok(check.players.every(p => !p.ready));
  const from = host.mark();
  host.send({ type: 'ready', ready: true });
  await pause(100);
  assert.equal(host.room.phase, 'ready_check', 'Previous readiness cannot start another battle.');
  guest.send({ type: 'ready', ready: true });
  const again = await host.wait(message => message.type === 'state' && message.phase === 'playing', { from });
  assert.equal(again.match.round_number, 1);
  assert.deepEqual(Object.values(again.match.round_wins), [0, 0]);
});

test('next round resets characters and input generation; host restart clears all match progress', async t => {
  const [host, guest] = await peers(t, { total_rounds: 2 });
  const started = await startBattle(host, [host, guest]);
  await winRound(host, guest);
  const next = await host.wait(message => message.type === 'state' && message.match.round_number === 2, { timeout: 4500 });
  assert.equal(next.match.phase, 'round');
  assert.ok(next.round_id > started.round_id);
  assert.equal(next.match.round_wins[host.id], 1);
  assert.deepEqual(Object.values(next.match.round_scores), [0, 0]);
  assert.ok(next.players.every(p => p.health === 10 && p.grounded && p.stamina === 100 && p.action_seq === 0));
  assert.deepEqual(next.players.map(p => [p.x, p.z]), [[-4, 0], [4, 0]]);
  await expectError(guest, { type: 'restart' }, /Only the room host/);
  const from = host.mark();
  host.send({ type: 'restart' });
  const restarted = await host.wait(message => message.type === 'state' && message.match.round_number === 1, { from });
  assert.ok(restarted.round_id > next.round_id);
  assert.deepEqual(Object.values(restarted.match.round_wins), [0, 0]);
  assert.equal(restarted.zone, 'arena');
});

test('real countdown enters overtime on a tie, then an opponent KO resolves the tied round', async t => {
  const [host, guest] = await peers(t, { round_duration: 10, knockouts_to_win: 4 });
  await startBattle(host, [host, guest]);
  const overtime = await host.wait(message => message.type === 'state' && message.match.phase === 'overtime', { timeout: 11500 });
  assert.equal(overtime.match.time_left, 0);
  assert.deepEqual(Object.values(overtime.match.round_scores), [0, 0]);
  const ended = await winRound(host, guest);
  assert.equal(ended.match.round_winner, host.id);
  assert.equal(ended.match.round_scores[host.id], 1, 'Overtime resolves a lead without requiring all four knockouts.');
});
