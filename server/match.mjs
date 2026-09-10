// Match flow is kept separate from transport and combat so transitions can be tested in isolation.
export const TOWN_SPAWNS = Object.freeze([[-3, 2], [3, 2], [-3, 5], [3, 5]]);
export const OLD_MAN = Object.freeze({ x: 0, y: 0, z: -5, range: 3 });
export const ROUND_BREAK_SECONDS = 3;
export const VICTORY_SECONDS = 6;

export function inOldManRange(player) {
  return player.health > 0 && Math.hypot(player.x - OLD_MAN.x, player.y - OLD_MAN.y,
    player.z - OLD_MAN.z) <= OLD_MAN.range;
}

export function newTownMatch(options) {
  return { phase: 'town', round_number: 0, total_rounds: options.total_rounds,
    time_left: 0, ready_time_left: 0, transition_time_left: 0,
    round_scores: {}, round_wins: {}, round_winner: '', winner_ids: [], winner_names: [] };
}

export function newReadyCheck(options) {
  return { ...newTownMatch(options), phase: 'ready_check', ready_time_left: options.ready_check_seconds };
}

export function newBattleMatch(players, mode, options) {
  const ids = mode === 'teams' ? ['red', 'blue'] : [...players].map(player => player.id);
  return { ...newTownMatch(options), phase: options.arena_start_countdown > 0 ? 'countdown' : 'round', round_number: 1, time_left: options.round_duration, countdown_time_left: options.arena_start_countdown, fight_time_left: 0,
    objective: options.sword_objective_enabled ? { enabled: true, crystal_health: options.crystal_max_health, crystal_max_health: options.crystal_max_health, break_stage: 0, sword_accessible: false, sword_owner: '', sword_dropped: false, sword_x: 0, sword_z: 0 } : { enabled: false },
    round_scores: Object.fromEntries(ids.map(id => [id, 0])), round_wins: Object.fromEntries(ids.map(id => [id, 0])),
    _scored_events: new Set() };
}

export function combatActive(match) { return match.phase === 'round' || match.phase === 'overtime'; }
export function movementActive(match) { return combatActive(match) || match.phase === 'countdown'; }

export function damageCrystal(match, attacker, options) {
  const objective = match.objective;
  if (!objective?.enabled || !combatActive(match) || objective.sword_accessible) return false;
  objective.crystal_health = Math.max(0, objective.crystal_health - options.crystal_damage_per_punch);
  const ratio = objective.crystal_health / Math.max(1, objective.crystal_max_health);
  objective.break_stage = Math.min(options.crystal_break_stages, Math.floor((1 - ratio) * options.crystal_break_stages));
  if (ratio <= options.sword_accessibility_threshold || objective.crystal_health <= 0) {
    objective.sword_accessible = true;
    objective.sword_dropped = false;
    objective.sword_x = 0;
    objective.sword_z = 0;
  }
  return true;
}

export function pickupSword(match, player, options) {
  const objective = match.objective;
  if (!objective?.enabled || !combatActive(match) || !objective.sword_accessible || objective.sword_owner) return false;
  if (Math.hypot(player.x - objective.sword_x, player.z - objective.sword_z) > options.sword_pickup_range) return false;
  objective.sword_owner = player.id;
  objective.sword_dropped = false;
  return true;
}

export function dropSword(match, player) {
  const objective = match.objective;
  if (!objective?.enabled || objective.sword_owner !== player.id) return false;
  objective.sword_owner = '';
  objective.sword_dropped = true;
  objective.sword_accessible = true;
  objective.sword_x = player.x;
  objective.sword_z = player.z;
  return true;
}

function resetObjective(match, options) {
  if (!options.sword_objective_enabled) { match.objective = { enabled: false }; return; }
  match.objective = { enabled: true, crystal_health: options.crystal_max_health, crystal_max_health: options.crystal_max_health,
    break_stage: 0, sword_accessible: false, sword_owner: '', sword_dropped: false, sword_x: 0, sword_z: 0 };
}

function leaders(scores) {
  const entries = Object.entries(scores);
  if (!entries.length) return [];
  const highest = Math.max(...entries.map(([, score]) => score));
  return entries.filter(([, score]) => score === highest).map(([id]) => id);
}

function finishRound(match, winner) {
  if (!combatActive(match) || !Object.hasOwn(match.round_scores, winner)) return;
  match.round_winner = winner;
  match.round_wins[winner] = (match.round_wins[winner] ?? 0) + 1;
  match.phase = 'round_end';
  match.time_left = 0;
  match.transition_time_left = ROUND_BREAK_SECONDS;
}

function checkScoreWinner(match, options) {
  if (!combatActive(match)) return;
  const currentLeaders = leaders(match.round_scores);
  if (currentLeaders.length !== 1) return;
  const winner = currentLeaders[0];
  if (match.phase === 'overtime' || match.round_scores[winner] >= options.knockouts_to_win) finishRound(match, winner);
}

export function scoreDefeats(match, events, players, mode, options) {
  if (!combatActive(match)) return;
  const participants = new Map([...players].map(player => [player.id, player]));
  for (const event of events) {
    if (!combatActive(match)) break;
    if (event.kind !== 'defeat' || event.source === 'fall' || !Number.isSafeInteger(event.event_id) || event.event_id < 1) continue;
    if (match._scored_events.has(event.event_id)) continue;
    match._scored_events.add(event.event_id);
    const attacker = participants.get(event.attacker), target = participants.get(event.target);
    if (!attacker || !target || attacker.id === target.id || target.health > 0) continue;
    if (mode === 'teams' && attacker.party === target.party) continue;
    const id = mode === 'teams' ? (attacker.party === 0 ? 'red' : 'blue') : attacker.id;
    if (!Object.hasOwn(match.round_scores, id)) continue;
    match.round_scores[id] += 1;
    checkScoreWinner(match, options);
  }
}

export function advanceMatch(match, dt, players, mode, options) {
  match.total_rounds = options.total_rounds;
  if (match.phase === 'countdown') {
    match.countdown_time_left = Math.max(0, (match.countdown_time_left ?? options.arena_start_countdown) - dt);
    if (match.countdown_time_left <= 0.000001) { match.phase = 'round'; match.time_left = options.round_duration; match.fight_time_left = 1.0; }
    return null;
  }
  if (combatActive(match)) {
    match.fight_time_left = Math.max(0, (match.fight_time_left ?? 0) - dt);
    checkScoreWinner(match, options);
    if (match.phase === 'round_end') return null;
    if (match.phase === 'round') {
      match.time_left = Math.max(0, match.time_left - dt);
      if (match.time_left <= 0.000001) {
        const currentLeaders = leaders(match.round_scores);
        if (currentLeaders.length === 1) finishRound(match, currentLeaders[0]);
        else { match.phase = 'overtime'; match.time_left = 0; }
      }
    }
    return null;
  }
  if (match.phase !== 'round_end' && match.phase !== 'victory') return null;
  match.transition_time_left = Math.max(0, match.transition_time_left - dt);
  if (match.transition_time_left > 0.000001) return null;
  if (match.phase === 'victory') return 'return_town';
  if (match.round_number >= options.total_rounds) {
    match.phase = 'victory';
    match.transition_time_left = VICTORY_SECONDS;
    match.winner_ids = leaders(match.round_wins);
    const names = new Map([...players].map(player => [player.id, player.name]));
    match.winner_names = match.winner_ids.map(id => mode === 'teams'
      ? (id === 'red' ? 'Red Team' : 'Blue Team') : (names.get(id) ?? 'Player'));
    return null;
  }
  match.round_number += 1;
  match.phase = 'round';
  match.time_left = options.round_duration;
  match.transition_time_left = 0;
  match.round_winner = '';
  for (const id of Object.keys(match.round_scores)) match.round_scores[id] = 0;
  resetObjective(match, options);
  return 'next_round';
}

export function advanceReadyCheck(match, dt) {
  if (match.phase !== 'ready_check') return false;
  match.ready_time_left = Math.max(0, match.ready_time_left - dt);
  return match.ready_time_left <= 0.000001;
}

export function updateMatchOptions(match, previous, next) {
  match.total_rounds = next.total_rounds;
  if (match.phase === 'ready_check') {
    match.ready_time_left = Math.max(0, match.ready_time_left + next.ready_check_seconds - previous.ready_check_seconds);
  } else if (match.phase === 'round') {
    match.time_left = Math.max(0, match.time_left + next.round_duration - previous.round_duration);
  }
}

export function isTown(room) { return room.phase === 'lobby' || room.phase === 'ready_check'; }

export function effectiveOptions(room) {
  // Safe-zone protection is an override; it must not overwrite the host's battle rules.
  return isTown(room) ? { ...room.godOptions, god_mode: true } : room.godOptions;
}

export function matchSnapshot(room) {
  const match = room.match;
  const { _scored_events, ...publicMatch } = match;
  const players = [...room.players.values()];
  const scoreEntries = room.mode === 'teams'
    ? [0, 1].map(party => ({ id: party === 0 ? 'red' : 'blue', name: party === 0 ? 'Red Team' : 'Blue Team', party }))
    : players.map(player => ({ id: player.id, name: player.name, party: player.party }));
  return { ...publicMatch, total_rounds: room.godOptions.total_rounds,
    round_scores: { ...match.round_scores }, round_wins: { ...match.round_wins },
    winner_ids: [...match.winner_ids], winner_names: [...match.winner_names],
    score_entries: scoreEntries.map(entry => ({ ...entry, knockouts: match.round_scores[entry.id] ?? 0,
      round_wins: match.round_wins[entry.id] ?? 0 })) };
}
