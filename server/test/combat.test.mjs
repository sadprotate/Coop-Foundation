import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DEFAULT_GOD_OPTIONS,
  resetPlayer,
  applyInput,
  performAction,
  stepPlayers,
  playerState,
  sanitizeGodOptions,
  validGodOptionsPatch,
  updatePlayerOptions
} from '../combat.mjs';

function setup() {
  const a = { id: 'a', slot: 0 }, b = { id: 'b', slot: 1 }, c = { id: 'c', slot: 2 };
  for (const p of [a, b, c]) resetPlayer(p);
  Object.assign(a, { x: 0, z: 0 });
  Object.assign(b, { x: 0, z: -1.5 });
  Object.assign(c, { x: 0, z: -2 });
  return [a, b, c];
}

test('punch uses the closest valid target and server-facing cone/range/height', () => {
  const [a, b, c] = setup();
  assert.equal(performAction(a, [a, b, c], 'punch', 1, 1000).find(e => e.kind === 'hit').target, b.id);
  assert.equal(b.health, 90);
  assert.equal(c.health, 100);
  b.z = -2.201; c.z = -10;
  assert.equal(performAction(a, [a, b, c], 'punch', 2, 1500).at(-1).kind, 'miss');
  b.z = 1.5;
  assert.equal(performAction(a, [a, b], 'punch', 3, 2000).at(-1).kind, 'miss');
  b.z = -1.5; b.x = 2;
  assert.equal(performAction(a, [a, b], 'punch', 4, 2500).at(-1).kind, 'miss');
  b.x = 0; b.y = 1.751;
  assert.equal(performAction(a, [a, b], 'punch', 5, 3000).at(-1).kind, 'miss');
  b.y = 1.75;
  assert.equal(performAction(a, [a, b], 'punch', 6, 3500).at(-1).damage, 10);
});

test('cooldown, replay prevention, immediate airborne critical, grounded jump and landing', () => {
  const [a, b] = setup();
  assert.equal(performAction(a, [a, b], 'punch', 1, 1000).at(-1).damage, 10);
  assert.deepEqual(performAction(a, [a, b], 'punch', 2, 1499), []);
  assert.deepEqual(performAction(a, [a, b], 'punch', 1, 1500), []);
  assert.equal(performAction(a, [a, b], 'jump', 3, 1500)[0].kind, 'jump');
  assert.equal(a.grounded, false);
  assert.equal(a.y, 0, 'Jump state changes before the next simulation tick.');
  assert.deepEqual(performAction(a, [a, b], 'jump', 4, 1501), []);
  assert.equal(performAction(a, [a, b], 'punch', 5, 1501).at(-1).damage, 20);
  assert.equal(b.health, 70);
  let maxHeight = 0;
  for (let tick = 0; tick < 20; tick++) { stepPlayers([a, b], 0.05, 1550 + tick * 50); maxHeight = Math.max(maxHeight, a.y); }
  assert.ok(maxHeight > 1 && maxHeight < 1.6);
  assert.equal(a.grounded, true);
  assert.equal(a.y, 0);
});

test('blocking protects a frontal 120-degree arc, slows movement, forbids punching, expires on stale input', () => {
  const [a, b] = setup();
  applyInput(b, { x: 0, z: 0, yaw: Math.PI, block: true, seq: 0 }, 1000);
  assert.equal(performAction(a, [a, b], 'punch', 1, 1000).at(-1).kind, 'blocked');
  assert.equal(b.health, 100);
  assert.deepEqual(performAction(b, [a, b], 'punch', 1, 1000), []);
  applyInput(b, { x: 0, z: 0, yaw: 0, block: true, seq: 1 }, 1500);
  assert.equal(performAction(a, [a, b], 'punch', 2, 1500).at(-1).damage, 10);
  applyInput(b, { x: 1, z: 0, yaw: Math.PI, block: true, seq: 2 }, 2000);
  const before = b.x;
  stepPlayers([b], 0.05, 2050);
  assert.equal(b.x - before, 0.125);
  b.x = 0;
  assert.equal(performAction(a, [a, b], 'punch', 3, 2251).at(-1).damage, 10, 'A stale block cannot protect indefinitely.');
  assert.equal(b.block, false);
});

test('defeat immobilizes, respawn restores own slot, protection expires and attacking cancels protection', () => {
  const [a, b] = setup();
  for (let hit = 0; hit < 10; hit++) performAction(a, [a, b], 'punch', hit + 1, 1000 + hit * 500);
  assert.equal(b.health, 0);
  assert.equal(b.respawn_in, 3);
  applyInput(b, { x: 1, z: 0, yaw: 0, block: true, seq: 0 }, 5501);
  assert.equal(b.inputX, 0);
  assert.deepEqual(performAction(b, [a, b], 'jump', 1, 5501), []);
  for (let tick = 0; tick < 59; tick++) stepPlayers([b], 0.05, 5550 + tick * 50);
  assert.equal(b.health, 0);
  const events = stepPlayers([b], 0.05, 8500);
  assert.equal(events[0].kind, 'respawn');
  assert.equal(b.health, 100);
  assert.deepEqual([b.x, b.y, b.z], [4, 0, 0]);
  assert.equal(playerState(b).invulnerable, true);
  Object.assign(a, { x: 4, z: 1.5 });
  assert.equal(performAction(a, [a, b], 'punch', 11, 8500).at(-1).kind, 'blocked');
  assert.equal(b.health, 100);
  assert.equal(performAction(b, [a, b], 'punch', 2, 8501)[0].kind, 'punch');
  assert.equal(b.invulnerableFor, 0);
  assert.equal(performAction(a, [a, b], 'punch', 12, 9000).at(-1).damage, 10);
  resetPlayer(b, false, true);
  for (let tick = 0; tick < 20; tick++) stepPlayers([b], 0.05, 9100 + tick * 50);
  assert.equal(playerState(b).invulnerable, false);
});

test('an accepted punch can only select a target inside the attacker frontal cone', () => {
  const [a, b] = setup();
  const now = 1000;
  // yaw 0 faces negative Z. The target is directly in front first.
  assert.equal(performAction(a, [a, b], 'punch', 1, now).at(-1).kind, 'hit');

  // Rear target: in range, but behind the attacker's facing.
  b.health = 100;
  b.x = 0; b.z = 1.5;
  assert.equal(performAction(a, [a, b], 'punch', 2, now + 500).at(-1).kind, 'miss');

  // Side target: in range, but 90 degrees from facing and outside 120 degrees.
  b.x = 1.5; b.z = 0;
  assert.equal(performAction(a, [a, b], 'punch', 3, now + 1000).at(-1).kind, 'miss');

  // The 60-degree boundary is inclusive; a target just past it is not.
  b.x = Math.sin(Math.PI / 3) * 1.5;
  b.z = -Math.cos(Math.PI / 3) * 1.5;
  assert.equal(performAction(a, [a, b], 'punch', 4, now + 1500).at(-1).kind, 'hit');
  b.health = 100;
  b.x = Math.sin(Math.PI / 3 + 0.01) * 1.5;
  b.z = -Math.cos(Math.PI / 3 + 0.01) * 1.5;
  assert.equal(performAction(a, [a, b], 'punch', 5, now + 2000).at(-1).kind, 'miss');
});

test('team mode prevents friendly fire while free-for-all keeps party labels cosmetic', () => {
  const [a, b, c] = setup();
  a.party = 0; b.party = 0; c.party = 1;
  assert.equal(performAction(a, [a, b], 'punch', 1, 1000, DEFAULT_GOD_OPTIONS, 'teams').at(-1).kind, 'miss');
  assert.equal(b.health, 100);
  assert.equal(performAction(a, [a, b], 'punch', 2, 1500, DEFAULT_GOD_OPTIONS, 'ffa').at(-1).kind, 'hit');
  assert.equal(b.health, 90);
});

test('shared God options sanitize and apply live to health, cooldown, movement, and respawn', () => {
  const [a, b] = setup();
  const options = sanitizeGodOptions(DEFAULT_GOD_OPTIONS, {
    god_mode: true, attack_speed: 10, attack_damage: 33.5, move_speed: 20,
    jump_speed: 2, jump_height: 4, max_jumps: 2.6, max_health: 250.4,
    attack_range: 5, air_damage_multiplier: 4, block_speed_multiplier: 0.1, respawn_seconds: 0.5,
    ignored: 123
  });
  assert.equal(validGodOptionsPatch(options), true);
  assert.equal(options.max_jumps, 3);
  assert.equal(options.max_health, 250);
  assert.equal(options.attack_damage, 33.5);
  assert.equal(sanitizeGodOptions(DEFAULT_GOD_OPTIONS, { attack_damage: 999, move_speed: -4 }).attack_damage, 100);
  assert.equal(validGodOptionsPatch({ attack_speed: 'fast' }), false);

  b.health = 60;
  b.max_health = 100;
  b.punchReadyAt = 1200;
  b.respawn_in = 6;
  updatePlayerOptions([a, b], DEFAULT_GOD_OPTIONS, options, 1000);
  assert.equal(b.health, 210, 'Changing max health preserves the amount of damage already taken.');
  assert.equal(b.max_health, 250);
  assert.equal(b.punchReadyAt, 1040, 'Increasing attack speed shortens the remaining cooldown.');
  assert.equal(b.respawn_in, 1, 'Respawn duration changes apply to defeated players too.');

  // God mode blocks damage from both normal and airborne punches globally.
  assert.equal(performAction(a, [a, b], 'punch', 1, 1000, options, 'ffa').at(-1).kind, 'blocked');
  assert.equal(b.health, 210);

  const fractional = { id: 'fractional', slot: 2 };
  resetPlayer(fractional);
  fractional.health = 0.25;
  updatePlayerOptions([fractional], DEFAULT_GOD_OPTIONS, { ...DEFAULT_GOD_OPTIONS, attack_damage: 20 }, 1000);
  assert.equal(fractional.health, 0.25, 'Changing unrelated options does not heal fractional health.');
});

test('tuned jump height, jump speed, and max jumps remain authoritative', () => {
  const measureJump = jumpSpeed => {
    const options = { ...DEFAULT_GOD_OPTIONS, jump_height: 4, jump_speed: jumpSpeed, max_jumps: 1 };
    const p = { id: `jump-${jumpSpeed}`, slot: 0 };
    resetPlayer(p, true, false, options);
    assert.equal(performAction(p, [p], 'jump', 1, 0, options, 'ffa')[0].kind, 'jump');
    let elapsed = 0;
    let peak = p.y;
    while (!p.grounded && elapsed < 3) {
      stepPlayers([p], 0.005, elapsed * 1000 + 5, options);
      elapsed += 0.005;
      peak = Math.max(peak, p.y);
    }
    assert.equal(p.grounded, true);
    assert.equal(p.y, 0);
    return { peak, airtime: elapsed };
  };

  const normal = measureJump(1);
  const fast = measureJump(2);
  assert.ok(normal.peak > 3.95 && normal.peak < 4.01, `Normal jump peak was ${normal.peak}.`);
  assert.ok(fast.peak > 3.95 && fast.peak < 4.01, `Fast jump peak was ${fast.peak}.`);
  assert.ok(Math.abs(normal.peak - fast.peak) < 0.03, 'Jump speed changes airtime without changing jump height.');
  assert.ok(fast.airtime / normal.airtime > 0.48 && fast.airtime / normal.airtime < 0.52,
    `Fast jump airtime ratio was ${fast.airtime / normal.airtime}; expected about one half.`);

  const options = { ...DEFAULT_GOD_OPTIONS, jump_height: 1, jump_speed: 1, max_jumps: 3 };
  const p = { id: 'multi', slot: 0 };
  resetPlayer(p, true, false, options);
  assert.equal(performAction(p, [p], 'jump', 1, 0, options, 'ffa')[0].kind, 'jump');
  assert.equal(performAction(p, [p], 'jump', 2, 1, options, 'ffa')[0].kind, 'jump');
  assert.equal(performAction(p, [p], 'jump', 3, 2, options, 'ffa')[0].kind, 'jump');
  assert.deepEqual(performAction(p, [p], 'jump', 4, 3, options, 'ffa'), [], 'A fourth jump is rejected.');
  assert.equal(p.jumps_used, 3);
  let elapsed = 0;
  while (!p.grounded && elapsed < 3) {
    stepPlayers([p], 0.01, elapsed * 1000 + 10, options);
    elapsed += 0.01;
  }
  assert.equal(p.grounded, true);
  assert.equal(p.jumps_used, 0, 'Landing resets the jump allowance.');
});

test('sprint drains stamina, exhausts into normal movement, regenerates after delay, and needs release', () => {
  const [p] = setup();
  const options = { ...DEFAULT_GOD_OPTIONS, max_stamina: 10, stamina_drain: 20,
    stamina_regen: 10, stamina_regen_delay: 0.2, move_speed: 3, sprint_speed: 8 };
  resetPlayer(p, true, false, options);
  let seq = 0;
  let now = 1000;
  const advance = (dt, sprint = true, extra = {}) => {
    applyInput(p, { x: 1, z: 0, yaw: 0, block: false, sprint, crouch: false, seq: seq++, ...extra }, now);
    stepPlayers([p], dt, now, options);
    now += dt * 1000;
  };
  const initialX = p.x;
  advance(0.25);
  assert.equal(p.x - initialX, 2);
  assert.equal(p.stamina, 5);
  assert.equal(p.sprinting, true);
  advance(0.25);
  assert.equal(p.stamina, 0);
  assert.equal(p.sprinting, false);
  assert.equal(p.sprint_exhausted, true);
  const exhaustedX = p.x;
  advance(0.1);
  assert.equal(p.stamina, 0);
  assert.ok(Math.abs(p.x - exhaustedX - 0.3) < 1e-9);
  advance(0.15);
  assert.ok(Math.abs(p.stamina - 0.5) < 1e-9);
  advance(0.1);
  assert.equal(p.sprinting, false, 'Held Shift must not repeatedly re-sprint as stamina trickles back.');
  assert.equal(p.sprint_exhausted, true);
  advance(0.1, false);
  assert.equal(p.sprint_exhausted, false);
  advance(0.05);
  assert.equal(p.sprinting, true);
  assert.ok(p.stamina > 0);
  advance(0.05, true, { crouch: true });
  assert.equal(p.sprinting, false);
  assert.equal(p.crouching, true);
  const crouchedX = p.x;
  advance(0.05, true, { crouch: true, block: true });
  assert.ok(Math.abs(p.x - crouchedX - options.crouch_speed * 0.05) < 1e-9);
  const state = playerState(p);
  assert.equal(state.body_height, 0.95);
  assert.equal(state.max_stamina, 10);
  assert.equal(typeof state.stamina_regen_in, 'number');
  stepPlayers([p], 0.05, now + 500, options);
  assert.equal(p.crouching, false, 'Lost input releases crouch and sprint.');
  assert.equal(p.sprintInput, false);
});

test('crouching avoids high punches but lower punches and vertically overlapping attacks still hit', () => {
  const [a, b] = setup();
  applyInput(b, { x: 0, z: 0, yaw: 0, block: false, crouch: true, seq: 0 }, 1000);
  assert.equal(performAction(a, [a, b], 'punch', 1, 1000).at(-1).kind, 'miss');
  assert.equal(b.health, 100);
  applyInput(a, { x: 0, z: 0, yaw: 0, block: false, crouch: true, seq: 0 }, 1500);
  applyInput(b, { x: 0, z: 0, yaw: 0, block: false, crouch: true, seq: 1 }, 1500);
  assert.equal(performAction(a, [a, b], 'punch', 2, 1500).at(-1).kind, 'hit');
  assert.equal(b.health, 90, 'Crouching is a smaller body, not invulnerability.');
  applyInput(a, { x: 0, z: 0, yaw: 0, block: false, crouch: false, seq: 1 }, 2000);
  applyInput(b, { x: 0, z: 0, yaw: 0, block: false, crouch: true, seq: 2 }, 2000);
  a.grounded = false; a.y = 0.2;
  assert.equal(performAction(a, [a, b], 'punch', 3, 2000).at(-1).kind, 'miss');
  b.y = 0.5;
  applyInput(b, { x: 0, z: 0, yaw: 0, block: false, crouch: true, seq: 3 }, 2500);
  assert.equal(performAction(a, [a, b], 'punch', 4, 2500).at(-1).damage, 20,
    'A raised crouched body overlaps the jumping punch and takes the airborne critical.');
  a.y = 2;
  applyInput(b, { x: 0, z: 0, yaw: 0, block: false, crouch: false, seq: 4 }, 3000);
  assert.equal(performAction(a, [a, b], 'punch', 5, 3000).at(-1).kind, 'miss');
});

test('expanded options clamp, initial health differs from maximum, and knockback follows actual damage', () => {
  const options = sanitizeGodOptions(DEFAULT_GOD_OPTIONS, { starting_health: 45, max_health: 200,
    max_stamina: 60, damage_multiplier: 2, knockback_strength: 4, gravity: -50,
    max_fall_speed: 1000, total_rounds: 2.6, ready_check_seconds: 1, fall_damage: true });
  assert.equal(options.gravity, 1);
  assert.equal(options.max_fall_speed, 100);
  assert.equal(options.total_rounds, 3);
  assert.equal(options.ready_check_seconds, 3);
  assert.equal(validGodOptionsPatch({ fall_damage: 'yes' }), false);
  const [a, b] = setup();
  resetPlayer(a, true, false, options);
  assert.equal(a.health, 45);
  assert.equal(a.max_health, 200);
  assert.equal(a.stamina, 60);
  a.x = a.z = 0;
  const hit = performAction(a, [a, b], 'punch', 1, 1000, options).at(-1);
  assert.equal(hit.damage, 20);
  assert.equal(b.knockbackZ, -4);
  stepPlayers([b], 0.05, 1050, options);
  assert.equal(b.z, -1.7);
  assert.ok(b.knockbackZ > -4 && b.knockbackZ < 0);
  b.knockbackZ = 0;
  performAction(a, [a, b], 'punch', 2, 1500, { ...options, god_mode: true });
  assert.equal(b.knockbackZ, 0, 'God mode also prevents damaging knockback.');
  resetPlayer(a, true, false, { ...options, starting_health: 999 });
  assert.equal(a.health, 200, 'Starting health never exceeds maximum health.');
});

test('terminal fall speed, fall damage threshold, God protection, defeat, and configured respawn', () => {
  const options = { ...DEFAULT_GOD_OPTIONS, gravity: 50, max_fall_speed: 2,
    fall_damage: true, fall_damage_threshold: 1, fall_damage_multiplier: 20,
    starting_health: 30, respawn_seconds: 0.5 };
  const [p] = setup();
  const fall = godMode => {
    resetPlayer(p, true, false, options);
    p.y = 4; p.fallPeak = 4; p.grounded = false;
    const events = [];
    for (let tick = 0; tick < 50 && !p.grounded; tick++) {
      events.push(...stepPlayers([p], 0.05, tick * 50, { ...options, god_mode: godMode }));
      assert.ok(p.vy >= -2, 'Falling velocity remains bounded.');
    }
    return events;
  };
  assert.deepEqual(fall(true), []);
  assert.equal(p.health, 30);
  const events = fall(false);
  assert.equal(events.find(e => e.kind === 'hit').damage, 60);
  assert.equal(events.at(-1).kind, 'defeat');
  assert.equal(events.at(-1).source, 'fall');
  assert.equal(p.health, 0);
  assert.equal(p.respawn_in, 0.5);
  stepPlayers([p], 0.5, 4000, options);
  assert.equal(p.health, 30);
  assert.equal(p.stamina, 100);
  assert.equal(p.sprint_exhausted, false);
});

test('sword range, arc, recovery and jump critical tuning are authoritative', () => {
  const attacker = { id: 'a', slot: 0 }, target = { id: 'b', slot: 1 };
  resetPlayer(attacker); resetPlayer(target);
  attacker.x = 0; attacker.z = 0; attacker.yaw = 0; attacker.grounded = false; attacker.jumps_used = 1;
  target.x = 0; target.z = -3;
  const options = { ...DEFAULT_GOD_OPTIONS, sword_arc: 1.2, attack_range: 3.5, attack_damage: 30, attack_speed: 1, air_damage_multiplier: 2 };
  const events = performAction(attacker, [attacker, target], 'punch', 1, 1000, options, 'ffa');
  assert.equal(events.some(event => event.kind === 'hit'), true);
  assert.equal(events.find(event => event.kind === 'hit').damage, 60);
  assert.equal(events.find(event => event.kind === 'hit').weapon, 'sword');
});
