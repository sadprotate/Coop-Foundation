import test from 'node:test';
import assert from 'node:assert/strict';
import { DEFAULT_GOD_OPTIONS } from '../combat.mjs';
import { newBattleMatch, scoreDefeats, advanceMatch, updateMatchOptions, matchSnapshot } from '../match.mjs';

const roster = () => [
  { id: 'a', name: 'Arin', party: 0, health: 100 }, { id: 'b', name: 'Bryn', party: 1, health: 0 },
  { id: 'c', name: 'Cora', party: 0, health: 0 }, { id: 'd', name: 'Dain', party: 1, health: 0 }
];
const defeat = (event_id, attacker = 'a', target = 'b', extra = {}) => ({ kind: 'defeat', event_id, attacker, target, ...extra });

test('default FFA plays ten rounds at 150 seconds or four knockouts, records wins, then returns Town', () => {
  const options = { ...DEFAULT_GOD_OPTIONS, arena_start_countdown: 0 }, players = roster();
  const match = newBattleMatch(players, 'ffa', options);
  assert.equal(match.total_rounds, 10);
  assert.equal(match.time_left, 150);
  let eventId = 0;
  for (let round = 1; round <= 10; round++) {
    assert.equal(match.round_number, round);
    assert.deepEqual(Object.values(match.round_scores), [0, 0, 0, 0]);
    for (let ko = 1; ko <= 4; ko++) scoreDefeats(match, [defeat(++eventId)], players, 'ffa', options);
    assert.equal(match.phase, 'round_end');
    assert.equal(match.round_winner, 'a');
    assert.equal(match.round_wins.a, round);
    assert.equal(match.transition_time_left, 3);
    scoreDefeats(match, [defeat(++eventId)], players, 'ffa', options);
    assert.equal(match.round_scores.a, 4, 'Round breaks cannot award extra knockouts.');
    const transition = advanceMatch(match, 3, players, 'ffa', options);
    assert.equal(transition, round < 10 ? 'next_round' : null);
  }
  assert.equal(match.phase, 'victory');
  assert.deepEqual(match.winner_ids, ['a']);
  assert.deepEqual(match.winner_names, ['Arin']);
  assert.equal(advanceMatch(match, 5.9, players, 'ffa', options), null);
  assert.equal(advanceMatch(match, 0.1, players, 'ffa', options), 'return_town');
});

test('only actual enemy defeats score; teammates combine four knockouts and event replay is ignored', () => {
  const players = roster(), options = { ...DEFAULT_GOD_OPTIONS, arena_start_countdown: 0 };
  const match = newBattleMatch(players, 'teams', options);
  scoreDefeats(match, [defeat(1, 'a', 'c'), defeat(2, 'a', 'a'), defeat(3, '', 'b', { source: 'fall' }),
    defeat(4, 'missing', 'b'), { ...defeat(5), kind: 'hit' }], players, 'teams', options);
  assert.deepEqual(match.round_scores, { red: 0, blue: 0 });
  scoreDefeats(match, [defeat(6), defeat(6), defeat(7, 'c', 'd'), defeat(8), defeat(9, 'c', 'd')], players, 'teams', options);
  assert.deepEqual(match.round_scores, { red: 4, blue: 0 });
  assert.equal(match.round_winner, 'red');
  assert.equal(match.round_wins.red, 1);
  const snapshot = matchSnapshot({ match, players: new Map(players.map(p => [p.id, p])), mode: 'teams', godOptions: options });
  assert.equal('_scored_events' in snapshot, false);
  assert.equal(snapshot.score_entries[0].name, 'Red Team');
});

test('timeout awards a unique leader; tied scores enter overtime until a unique leader emerges', () => {
  const players = roster(), options = { ...DEFAULT_GOD_OPTIONS, arena_start_countdown: 0 };
  let match = newBattleMatch(players, 'ffa', options);
  scoreDefeats(match, [defeat(1)], players, 'ffa', options);
  advanceMatch(match, 150, players, 'ffa', options);
  assert.equal(match.round_winner, 'a');
  match = newBattleMatch(players, 'ffa', options);
  advanceMatch(match, 150, players, 'ffa', options);
  assert.equal(match.phase, 'overtime');
  assert.equal(match.time_left, 0);
  advanceMatch(match, 500, players, 'ffa', options);
  assert.equal(match.phase, 'overtime', 'Overtime has no random or timeout winner.');
  scoreDefeats(match, [defeat(2, 'c', 'b')], players, 'ffa', options);
  assert.equal(match.round_winner, 'c');
});

test('solo timeout records a zero-knockout win, and equal final round wins produce joint winners', () => {
  const options = { ...DEFAULT_GOD_OPTIONS, arena_start_countdown: 0, total_rounds: 1 };
  const players = roster();
  const solo = newBattleMatch([players[0]], 'ffa', options);
  advanceMatch(solo, 150, [players[0]], 'ffa', options);
  assert.equal(solo.round_winner, 'a');
  assert.equal(solo.round_scores.a, 0);
  advanceMatch(solo, 3, [players[0]], 'ffa', options);
  assert.deepEqual(solo.winner_names, ['Arin']);
  const tiedOptions = { ...options, total_rounds: 2, knockouts_to_win: 1 };
  const tied = newBattleMatch(players, 'teams', tiedOptions);
  scoreDefeats(tied, [defeat(1)], players, 'teams', tiedOptions);
  advanceMatch(tied, 3, players, 'teams', tiedOptions);
  scoreDefeats(tied, [defeat(2, 'b', 'c')], players, 'teams', tiedOptions);
  advanceMatch(tied, 3, players, 'teams', tiedOptions);
  assert.deepEqual(tied.winner_names, ['Red Team', 'Blue Team']);
});

test('live match rules preserve elapsed time, lower knockout threshold, and finish after the active round', () => {
  const players = roster(), options = { ...DEFAULT_GOD_OPTIONS, arena_start_countdown: 0 };
  const match = newBattleMatch(players, 'ffa', options);
  advanceMatch(match, 20, players, 'ffa', options);
  const next = { ...options, round_duration: 200, knockouts_to_win: 1, total_rounds: 1 };
  updateMatchOptions(match, options, next);
  assert.equal(match.time_left, 180);
  scoreDefeats(match, [defeat(1)], players, 'ffa', options);
  assert.equal(match.phase, 'round');
  advanceMatch(match, 0.05, players, 'ffa', next);
  assert.equal(match.phase, 'round_end');
  advanceMatch(match, 3, players, 'ffa', next);
  assert.equal(match.phase, 'victory');
});

test('sword ownership and objective reset at the start of each round', () => {
  const options = { ...DEFAULT_GOD_OPTIONS, arena_start_countdown: 0, total_rounds: 2 };
  const players = roster();
  const match = newBattleMatch(players, 'ffa', options);
  match.objective.sword_accessible = true;
  match.objective.sword_owner = 'a';
  match.phase = 'round_end';
  match.transition_time_left = 0;
  advanceMatch(match, 0, players, 'ffa', options);
  assert.equal(match.phase, 'round');
  assert.equal(match.objective.sword_owner, '');
  assert.equal(match.objective.sword_accessible, false);
  assert.equal(match.objective.crystal_health, options.crystal_max_health);
});
