import test from 'node:test';
import assert from 'node:assert/strict';
import { DEFAULT_GOD_OPTIONS } from '../combat.mjs';
import { newBattleMatch, damageCrystal, pickupSword, dropSword } from '../match.mjs';

const options = { ...DEFAULT_GOD_OPTIONS, arena_start_countdown: 0, crystal_max_health: 40, crystal_damage_per_punch: 10, sword_accessibility_threshold: 0.25 };
const players = [{ id: 'a', slot: 0, party: 0, x: 0, z: 0, health: 100 }, { id: 'b', slot: 1, party: 1, x: 1, z: 0, health: 100 }];

test('crystal damage is authoritative and unlocks at the configured threshold', () => {
  const match = newBattleMatch(players, 'ffa', options);
  assert.equal(damageCrystal(match, players[0], options), true);
  assert.equal(match.objective.crystal_health, 30);
  assert.equal(match.objective.sword_accessible, false);
  damageCrystal(match, players[0], options); damageCrystal(match, players[0], options);
  assert.equal(match.objective.sword_accessible, true);
});

test('only one player can win a contested sword pickup and knockout drops it', () => {
  const match = newBattleMatch(players, 'ffa', options);
  match.objective.sword_accessible = true;
  assert.equal(pickupSword(match, players[0], options), true);
  assert.equal(pickupSword(match, players[1], options), false);
  assert.equal(match.objective.sword_owner, 'a');
  assert.equal(dropSword(match, players[0]), true);
  assert.equal(match.objective.sword_owner, '');
  assert.equal(match.objective.sword_dropped, true);
});
