// Shared rules live here so the server can be tested without privileged network hooks.
export const SPAWNS = [[-14, -14], [14, -14], [-14, 14], [14, 14]];
export const RULES = Object.freeze({ speed: 5.5, blockSpeed: 2.5, gravity: 20, jumpSpeed: 7,
  range: 2.2, heightRange: 1.6, coneDot: 0.5, punchCooldown: 500, respawnSeconds: 3,
  invulnerabilitySeconds: 1, staleInputMs: 250, boundary: 18 });

export const DEFAULT_GOD_OPTIONS = Object.freeze({ god_mode: false, attack_speed: 2, attack_damage: 10,

  move_speed: 5.5, jump_speed: 1, jump_height: 1.225, max_jumps: 1, max_health: 100,
  attack_range: 2.2, air_damage_multiplier: 2, block_speed_multiplier: 2.5 / 5.5, respawn_seconds: 3,
  starting_health: 100, sprint_speed: 9, max_stamina: 100, stamina_drain: 25,
  stamina_regen: 20, stamina_regen_delay: 1, gravity: 20, max_fall_speed: 30,
  fall_damage: false, fall_damage_threshold: 4, fall_damage_multiplier: 10, crouch_speed: 2.5,
  damage_multiplier: 1, knockback_strength: 2, round_duration: 150, knockouts_to_win: 4,
  total_rounds: 10, ready_check_seconds: 15, arena_start_countdown: 10, sword_objective_enabled: true, crystal_max_health: 100, crystal_damage_per_punch: 10, crystal_break_stages: 4, sword_accessibility_threshold: 0.25, sword_pickup_range: 2.2, sword_pickup_hold_time: 0, sword_damage: 30, sword_range: 3.4, sword_swing_arc: 1.2, sword_swing_speed: 1, sword_attack_recovery: 1.2, sword_knockback: 4, sword_blockable: true, sword_block_damage_reduction: 0.8, sword_movement_speed_multiplier: 1, sword_jump_critical_enabled: true, sword_critical_damage_multiplier: 2, camera_fov: 55, camera_distance: 11.5, camera_height: 11, camera_vertical_offset: 1, camera_min_pitch: 35, camera_max_pitch: 75, camera_rotation_speed: 1, camera_smoothing: 0.85, camera_follow_speed: 16, camera_zoom_min: 8, camera_zoom_max: 20 });
export const GOD_OPTION_LIMITS = Object.freeze({ attack_speed: [0.2, 10], attack_damage: [0, 100],
  move_speed: [1, 20], jump_speed: [0.25, 3], jump_height: [0.25, 10], max_jumps: [1, 10],
  max_health: [10, 1000], attack_range: [0.5, 5], air_damage_multiplier: [1, 5],
  block_speed_multiplier: [0, 1], respawn_seconds: [0.5, 10], starting_health: [1, 1000],
  sprint_speed: [1, 30], max_stamina: [1, 1000], stamina_drain: [0, 200], stamina_regen: [0, 200],
  stamina_regen_delay: [0, 10], gravity: [1, 80], max_fall_speed: [1, 100],
  fall_damage_threshold: [0, 50], fall_damage_multiplier: [0, 100], crouch_speed: [0.1, 15],
  damage_multiplier: [0, 10], knockback_strength: [0, 15], round_duration: [10, 1800],
  knockouts_to_win: [1, 50], total_rounds: [1, 50], ready_check_seconds: [3, 120], arena_start_countdown: [0, 60], camera_fov: [35, 90], camera_distance: [8, 20], camera_height: [5, 30], camera_vertical_offset: [-3, 8], camera_min_pitch: [20, 85], camera_max_pitch: [20, 89], camera_rotation_speed: [0.1, 5], camera_smoothing: [0, 1], camera_follow_speed: [1, 30], camera_zoom_min: [4, 20], camera_zoom_max: [10, 40] });
const INTEGER_OPTIONS = new Set(['max_jumps', 'max_health', 'starting_health', 'max_stamina',
  'round_duration', 'knockouts_to_win', 'total_rounds', 'ready_check_seconds']);
export const BODY = Object.freeze({ standing: 1.8, crouching: 0.95,
  standingAttack: [1.15, 1.75], crouchingAttack: [0.45, 0.9] });

export function sanitizeGodOptions(current, patch) {
  const next = {};
  for (const key of Object.keys(DEFAULT_GOD_OPTIONS)) next[key] = current?.[key] ?? DEFAULT_GOD_OPTIONS[key];
  if (!patch || typeof patch !== 'object' || Array.isArray(patch)) return next;
  for (const key of Object.keys(DEFAULT_GOD_OPTIONS)) {
    if (!Object.hasOwn(patch, key)) continue;
    const value = patch[key];
    if (typeof DEFAULT_GOD_OPTIONS[key] === 'boolean') {
      if (typeof value === 'boolean') next[key] = value;
    } else if (typeof value === 'number' && Number.isFinite(value)) {
      const [min, max] = GOD_OPTION_LIMITS[key];
      next[key] = Math.max(min, Math.min(max,
        INTEGER_OPTIONS.has(key) ? Math.round(value) : value));
    }
  }
  return next;
}

export function validGodOptionsPatch(patch) {
  if (!patch || typeof patch !== 'object' || Array.isArray(patch)) return false;
  for (const key of Object.keys(DEFAULT_GOD_OPTIONS)) {
    if (!Object.hasOwn(patch, key)) continue;
    const value = patch[key];
    if (typeof DEFAULT_GOD_OPTIONS[key] === 'boolean') {
      if (typeof value !== 'boolean') return false;
    } else if (typeof value !== 'number' || !Number.isFinite(value)) {
      return false;
    }
  }
  return true;
}

export function updatePlayerOptions(players, previous, next, now) {
  for (const p of players) {
    if (p.health > 0 && previous.max_health !== next.max_health) {
      // Preserve damage already taken; changing the maximum alone cannot kill or revive.
      p.health = Math.max(1, Math.min(next.max_health, next.max_health - (previous.max_health - p.health)));
    }
    p.max_health = next.max_health;
    if (previous.max_stamina !== next.max_stamina) {
      p.stamina = Math.max(0, Math.min(next.max_stamina, next.max_stamina - (previous.max_stamina - p.stamina)));
    }
    p.max_stamina = next.max_stamina;
    p.stamina_regen_in = Math.min(p.stamina_regen_in, next.stamina_regen_delay);
    if (p.punchReadyAt > now && previous.attack_speed !== next.attack_speed) {
      p.punchReadyAt = now + (p.punchReadyAt - now) * previous.attack_speed / next.attack_speed;
    }
    if (p.respawn_in > 0 && previous.respawn_seconds !== next.respawn_seconds) {
      p.respawn_in *= next.respawn_seconds / previous.respawn_seconds;
    }
    if (!p.grounded && previous.jump_speed !== next.jump_speed) p.vy *= next.jump_speed / previous.jump_speed;
  }
}

export function resetPlayer(p, resetSequences = true, invulnerable = false, options = DEFAULT_GOD_OPTIONS) {
  [p.x, p.z] = SPAWNS[p.slot];
  if (!Number.isInteger(p.party)) p.party = p.slot % 2;
  Object.assign(p, { y: 0, yaw: 0, vy: 0, health: Math.min(options.starting_health, options.max_health), max_health: options.max_health,
    grounded: true, jumps_used: 0, block: false,
    crouching: false, sprinting: false, sprintInput: false, sprint_exhausted: false,
    stamina: options.max_stamina, max_stamina: options.max_stamina, stamina_regen_in: 0,
    fallPeak: 0, knockbackX: 0, knockbackZ: 0,
    inputX: 0, inputZ: 0, lastInput: 0, punch_t: 0, hurt_t: 0, respawn_in: 0,
    invulnerableFor: invulnerable ? RULES.invulnerabilitySeconds : 0, punchReadyAt: 0 });
  if (resetSequences) { p.seq = -1; p.actionSeq = 0; }
}

export function applyInput(p, data, now) {
  if (data.seq <= p.seq) return;
  p.seq = data.seq;
  if (p.health <= 0) return;
  let x = Math.max(-1, Math.min(1, data.x));
  let z = Math.max(-1, Math.min(1, data.z));
  const length = Math.hypot(x, z);
  if (length > 1) { x /= length; z /= length; }
  p.inputX = x;
  p.inputZ = z;
  p.yaw = ((data.yaw + Math.PI) % (2 * Math.PI) + 2 * Math.PI) % (2 * Math.PI) - Math.PI;
  p.block = data.block;
  p.crouching = data.crouch === true;
  p.sprintInput = data.sprint === true;
  if (!p.sprintInput) p.sprint_exhausted = false;
  p.lastInput = now;
}

function expireInput(p, now) {
  if (now - p.lastInput > RULES.staleInputMs) {
    p.inputX = p.inputZ = 0;
    p.block = false;
    p.crouching = false;
    p.sprintInput = false;
    p.sprint_exhausted = false;
  }
}

function faces(p, other) {
  const dx = other.x - p.x, dz = other.z - p.z;
  const distance = Math.hypot(dx, dz);
  // Exactly overlapping centers have no front direction: neither a hit nor a frontal block.
  return distance < 0.001 ? -1 : (-Math.sin(p.yaw) * dx - Math.cos(p.yaw) * dz) / distance;
}

export function performAction(p, players, type, actionSeq, now, options = DEFAULT_GOD_OPTIONS, mode = 'ffa') {
  if (actionSeq <= p.actionSeq) return [];
  p.actionSeq = actionSeq;
  expireInput(p, now);
  if (p.health <= 0) return [];
  const event = (kind, target = '', damage = 0, critical = false) => ({ kind, attacker: p.id, target, damage, critical, weapon: options.sword_arc !== undefined ? 'sword' : 'punch' });
  if (type === 'jump') {
    if (!p.grounded && p.jumps_used >= options.max_jumps) return [];
    p.jumps_used = p.grounded ? 1 : p.jumps_used + 1;
    p.grounded = false;
    p.vy = Math.sqrt(2 * options.gravity * options.jump_height) * options.jump_speed;
    return [event('jump')];
  }
  if (type !== 'punch') return [];
  if (p.block || now < p.punchReadyAt) return [];
  p.punchReadyAt = now + 1000 / options.attack_speed;
  p.punch_t = Math.min(0.25, 1 / options.attack_speed);
  p.invulnerableFor = 0; // Attacking voluntarily ends respawn protection.
  const critical = !p.grounded;
  const events = [event('punch', '', 0, critical)];
  const target = [...players].filter(other => {
    if (other.id === p.id || other.health <= 0 || (mode === 'teams' && other.party === p.party)) return false;
    expireInput(other, now);
    const distance = Math.hypot(other.x - p.x, other.z - p.z);
    const [attackLow, attackHigh] = p.crouching ? BODY.crouchingAttack : BODY.standingAttack;
    const bodyHeight = other.crouching ? BODY.crouching : BODY.standing;
    const verticalOverlap = p.y + attackLow <= other.y + bodyHeight && p.y + attackHigh >= other.y;
    const requiredFacing = options.sword_arc ? Math.cos(Math.min(Math.PI, options.sword_arc) * 0.5) : RULES.coneDot;
    return distance <= options.attack_range && verticalOverlap &&
      faces(p, other) >= requiredFacing;
  }).sort((a, b) => Math.hypot(a.x - p.x, a.z - p.z) - Math.hypot(b.x - p.x, b.z - p.z))[0];
  if (!target) return [...events, event('miss', '', 0, critical)];
  expireInput(target, now);
  if (options.god_mode || target.invulnerableFor > 0 || (target.block && faces(target, p) >= RULES.coneDot && options.sword_arc === undefined)) {
    return [...events, event('blocked', target.id, 0, critical)];
  }
  const blockReduction = target.block && options.sword_arc !== undefined && options.sword_block_damage_reduction !== undefined ? (1 - options.sword_block_damage_reduction) : 1;
  const damage = options.attack_damage * options.damage_multiplier * (critical ? options.air_damage_multiplier : 1) * blockReduction;
  target.health = Math.max(0, target.health - damage);
  target.hurt_t = 0.28;
  events.push(event('hit', target.id, damage, critical));
  if (damage > 0) {
    const distance = Math.hypot(target.x - p.x, target.z - p.z);
    target.knockbackX += (target.x - p.x) / distance * options.knockback_strength;
    target.knockbackZ += (target.z - p.z) / distance * options.knockback_strength;
  }
  if (target.health === 0) {
    target.respawn_in = options.respawn_seconds;
    target.inputX = target.inputZ = target.vy = 0;
    target.block = false;
    target.sprinting = target.crouching = false;
    target.knockbackX = target.knockbackZ = 0;
    target.punch_t = 0;
    events.push(event('defeat', target.id, damage, critical));
  }
  return events;
}

export function stepPlayers(players, dt, now, options = DEFAULT_GOD_OPTIONS) {
  const events = [];
  for (const p of players) {
    p.punch_t = Math.max(0, p.punch_t - dt);
    p.hurt_t = Math.max(0, p.hurt_t - dt);
    p.invulnerableFor = Math.max(0, p.invulnerableFor - dt);
    if (p.health <= 0) {
      p.respawn_in = Math.max(0, p.respawn_in - dt);
      if (p.respawn_in <= 0.000001) {
        resetPlayer(p, false, true, options);
        events.push({ kind: 'respawn', attacker: '', target: p.id, damage: 0, critical: false });
      }
      continue;
    }
    expireInput(p, now);
    const moving = Math.hypot(p.inputX, p.inputZ) > 0.001;
    p.sprinting = moving && p.sprintInput && !p.sprint_exhausted && !p.crouching && !p.block && p.stamina > 0;
    if (p.sprinting) {
      p.stamina = Math.max(0, p.stamina - options.stamina_drain * dt);
      p.stamina_regen_in = options.stamina_regen_delay;
      if (p.stamina <= 0) { p.sprinting = false; p.sprint_exhausted = true; }
    } else {
      const regenTime = Math.max(0, dt - p.stamina_regen_in);
      p.stamina_regen_in = Math.max(0, p.stamina_regen_in - dt);
      p.stamina = Math.min(options.max_stamina, p.stamina + options.stamina_regen * regenTime);
    }
    const speed = p.crouching ? options.crouch_speed
      : p.block ? options.move_speed * options.block_speed_multiplier
      : p.sprinting ? options.sprint_speed : options.move_speed;
    p.x = Math.max(-RULES.boundary, Math.min(RULES.boundary, p.x + (p.inputX * speed + p.knockbackX) * dt));
    p.z = Math.max(-RULES.boundary, Math.min(RULES.boundary, p.z + (p.inputZ * speed + p.knockbackZ) * dt));
    p.knockbackX *= Math.exp(-8 * dt);
    p.knockbackZ *= Math.exp(-8 * dt);
    if (!p.grounded) {
      const gravity = options.gravity * options.jump_speed ** 2;
      p.vy = Math.max(-options.max_fall_speed, p.vy);
      const acceleratingTime = Math.min(dt, Math.max(0, (p.vy + options.max_fall_speed) / gravity));
      p.y += p.vy * acceleratingTime - 0.5 * gravity * acceleratingTime ** 2
        - options.max_fall_speed * (dt - acceleratingTime);
      p.vy = Math.max(-options.max_fall_speed, p.vy - gravity * dt);
      p.fallPeak = Math.max(p.fallPeak, p.y);
      if (p.y <= 0) {
        p.y = 0; p.vy = 0; p.grounded = true; p.jumps_used = 0;
        const fallDamage = options.fall_damage && !options.god_mode && p.invulnerableFor <= 0
          ? Math.max(0, p.fallPeak - options.fall_damage_threshold) * options.fall_damage_multiplier * options.damage_multiplier : 0;
        p.fallPeak = 0;
        if (fallDamage > 0) {
          p.health = Math.max(0, p.health - fallDamage);
          p.hurt_t = 0.28;
          events.push({ kind: 'hit', attacker: '', target: p.id, damage: fallDamage, critical: false, source: 'fall' });
          if (p.health <= 0) {
            p.respawn_in = options.respawn_seconds;
            p.inputX = p.inputZ = p.knockbackX = p.knockbackZ = p.punch_t = 0;
            p.block = p.crouching = p.sprinting = false;
            events.push({ kind: 'defeat', attacker: '', target: p.id, damage: fallDamage, critical: false, source: 'fall' });
          }
        }
      }
    }
  }
  return events;
}

const round = number => Math.round(number * 1000) / 1000;
export function playerState(p) {
  return { id: p.id, slot: p.slot, party: p.party, team: p.party, x: round(p.x), y: round(p.y), z: round(p.z), yaw: round(p.yaw),
    health: p.health, max_health: p.max_health, grounded: p.grounded, jumps_used: p.jumps_used, block: p.block,
    crouching: p.crouching, body_height: p.crouching ? BODY.crouching : BODY.standing,
    sprinting: p.sprinting, stamina: round(p.stamina), max_stamina: p.max_stamina,
    stamina_regen_in: round(p.stamina_regen_in), sprint_exhausted: p.sprint_exhausted,
    action_seq: p.actionSeq, vy: round(p.vy), punch_t: round(p.punch_t), hurt_t: round(p.hurt_t), respawn_in: round(p.respawn_in),
    invulnerable: p.invulnerableFor > 0 };
}
