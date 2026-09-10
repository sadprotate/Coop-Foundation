import http from 'node:http';
import { randomInt, randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { performance } from 'node:perf_hooks';
import WebSocket, { WebSocketServer } from 'ws';
import { DEFAULT_GOD_OPTIONS, resetPlayer, applyInput, performAction, stepPlayers, playerState, sanitizeGodOptions, validGodOptionsPatch, updatePlayerOptions } from './combat.mjs';
import { TOWN_SPAWNS, inOldManRange, newTownMatch, newReadyCheck, newBattleMatch,
  advanceReadyCheck, updateMatchOptions, combatActive, movementActive, scoreDefeats, advanceMatch,
  isTown, effectiveOptions, matchSnapshot, damageCrystal, pickupSword } from './match.mjs';

const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const PROTOCOL = 4;
const LEVEL = 3;
const TICK_MS = 50;
const MAX_BUFFER = 128 * 1024;
const MAX_PLAYERS = 4;

function normalizeMode(value) {
  if (value === 'free_for_all' || value === 'free-for-all') return 'ffa';
  if (value === '2v2' || value === 'team' || value === 'team_battle') return 'teams';
  return value === 'ffa' || value === 'teams' ? value : null;
}

function validParty(value) {
  return Number.isSafeInteger(value) && value >= 0 && value <= 1 ? value : null;
}

function integerSetting(value, fallback, min, max) {
  if (value === undefined || value === '') return fallback;
  const number = Number(value);
  if (!Number.isInteger(number) || number < min || number > max) {
    throw new Error(`Invalid server setting: expected integer ${min}..${max}, received ${value}`);
  }
  return number;
}

/** Start an independent server. Port 0 selects an ephemeral port for tests. */
export async function startServer(options = {}) {
  const port = integerSetting(options.port ?? process.env.PORT, 8787, 0, 65535);
  const host = options.host ?? process.env.HOST ?? '0.0.0.0';
  const maxRooms = integerSetting(options.maxRooms ?? process.env.MAX_ROOMS, 100, 1, 10000);
  const maxConnections = integerSetting(options.maxConnections ?? process.env.MAX_CONNECTIONS, 400, 1, 10000);
  const maxConnectionsPerIp = integerSetting(options.maxConnectionsPerIp ?? process.env.MAX_CONNECTIONS_PER_IP, 128, 1, 10000);
  const heartbeatMs = integerSetting(options.heartbeatMs, 15000, 25, 60000);
  const idleMs = integerSetting(options.idleMs ?? (process.env.ROOM_IDLE_MINUTES ? Number(process.env.ROOM_IDLE_MINUTES) * 60000 : undefined), 30 * 60000, 100, 24 * 60 * 60000);
  const rooms = new Map();
  const clients = new Map();
  const ipConnections = new Map();
  const started = performance.now();
  let stopped = false;
  let ticks = 0;

  const httpServer = http.createServer({ maxHeaderSize: 8192, requestTimeout: 10000, headersTimeout: 10000 }, (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    if (req.method === 'GET' && (req.url === '/health' || req.url === '/healthz')) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: !stopped, version: '0.7.0', protocol: PROTOCOL, rooms: rooms.size, connections: clients.size, uptime_seconds: Math.floor((performance.now() - started) / 1000) }));
    } else if (req.method === 'GET' && req.url === '/') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Co-op Foundation server. WebSocket endpoint: /ws (or /). Health: /health\n');
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found\n');
    }
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 2048, perMessageDeflate: false, maxFragments: 16, maxBufferedChunks: 32 });

  function send(client, data) {
    const ws = client.ws;
    if (ws.readyState !== WebSocket.OPEN) return;
    if (ws.bufferedAmount > MAX_BUFFER) {
      ws.terminate();
      return;
    }
    ws.send(JSON.stringify(data), error => { if (error) ws.terminate(); });
  }
  function error(client, message) { send(client, { type: 'error', message }); }
  function roomData(room) {
    return { type: 'room', code: room.code, host_id: room.hostId, phase: room.phase, level: LEVEL, round_id: room.roundId,
      zone: isTown(room) ? 'town' : 'arena', safe_zone: isTown(room), match: matchSnapshot(room),
      mode: room.mode, god_options: { ...room.godOptions },
      players: [...room.players.values()].map(p => ({ id: p.id, name: p.name, slot: p.slot, party: p.party, team: p.party, ready: p.ready, ping_ms: p.pingMs ?? null })) };
  }
  function stateData(room) {
    return { type: 'state', tick: ticks, phase: room.phase, level: LEVEL, round_id: room.roundId, mode: room.mode, god_options: { ...room.godOptions },
      zone: isTown(room) ? 'town' : 'arena', safe_zone: isTown(room), match: matchSnapshot(room),
      players: [...room.players.values()].map(p => ({ ...playerState(p), ping_ms: p.pingMs ?? null })) };
  }
  function broadcastCombat(room, events) {
    for (const event of events) {
      event.event_id = ++room.eventId;
      broadcast(room, { type: 'combat', ...event });
    }
    const previousPhase = room.match.phase;
    for (const event of events) {
      if (event.kind === 'defeat') {
        const target = room.players.get(event.target);
        if (target) {
          const objective = room.match.objective;
          if (objective?.sword_owner === target.id) {
            objective.sword_owner = '';
            objective.sword_dropped = true;
            objective.sword_accessible = true;
            objective.sword_x = target.x;
            objective.sword_z = target.z;
          }
        }
      }
    }
    scoreDefeats(room.match, events, room.players.values(), room.mode, room.godOptions);
    if (room.match.phase !== previousPhase) {
      stopControls(room);
      broadcastRoom(room);
    }
  }
  function broadcast(room, data) { for (const player of room.players.values()) send(player, data); }
  function broadcastRoom(room) { broadcast(room, roomData(room)); }
  function broadcastState(room) { broadcast(room, stateData(room)); }
  function keepHostReady(room) {
    if (room.phase !== 'lobby') return;
    for (const p of room.players.values()) p.ready = false;
  }
  function stopControls(room) {
    for (const p of room.players.values()) {
      p.inputX = p.inputZ = p.knockbackX = p.knockbackZ = 0;
      p.block = p.sprintInput = p.sprinting = p.crouching = false;
    }
  }
  function cancelReadyCheck(room, message) {
    room.phase = 'lobby';
    room.match = newTownMatch(room.godOptions);
    keepHostReady(room);
    stopControls(room);
    if (message) broadcast(room, { type: 'notice', message });
  }
  function reset(room, phase) {
    room.phase = phase;
    room.roundId += 1;
    room.lastActivity = performance.now();
    for (const p of room.players.values()) {
      resetPlayer(p, true, false, room.godOptions);
      p.ready = false;
      if (phase === 'lobby') [p.x, p.z] = TOWN_SPAWNS[p.slot];
    }
    if (phase === 'lobby') room.match = newTownMatch(room.godOptions);
    else room.match = newBattleMatch(room.players.values(), room.mode, room.godOptions);
  }
  function leave(client, disconnected = false) {
    const room = rooms.get(client.roomCode);
    client.roomCode = '';
    if (!room) return;
    room.players.delete(client.id);
    if (!room.players.size) {
      rooms.delete(room.code);
    } else {
      if (room.hostId === client.id) {
        const newHost = room.players.values().next().value;
        room.hostId = newHost.id;
        newHost.ready = false;
      }
      room.lastActivity = performance.now();
      reset(room, 'lobby');
      broadcast(room, { type: 'notice', message: `${client.name} left. Everyone returned to the Town Lobby.` });
      broadcastRoom(room);
      broadcastState(room);
    }
    if (!disconnected) send(client, { type: 'room', code: '', host_id: '', phase: 'lobby', level: LEVEL, players: [] });
  }
  function validName(value) {
    if (typeof value !== 'string') return null;
    const name = value.replace(/[\u0000-\u001f\u007f]/g, '').trim();
    return [...name].length >= 1 && [...name].length <= 24 ? name : null;
  }
  function joinRoom(client, room, name, requestedParty = null) {
    if (room.phase === 'ready_check') cancelReadyCheck(room, 'A player joined. Talk to the Old Man to start a new ready check.');
    client.name = name;
    client.roomCode = room.code;
    client.slot = Array.from({ length: MAX_PLAYERS }, (_, slot) => slot).find(slot => ![...room.players.values()].some(p => p.slot === slot));
    client.party = requestedParty === null ? client.slot % 2 : requestedParty;
    client.ready = false;
    resetPlayer(client, true, false, room.godOptions);
    [client.x, client.z] = TOWN_SPAWNS[client.slot];
    room.players.set(client.id, client);
    room.lastActivity = performance.now();
    broadcastRoom(room);
    broadcastState(room);
  }
  function takeToken(client, bucket, now, rate, burst) {
    const item = client[bucket];
    item.tokens = Math.min(burst, item.tokens + (now - item.time) * rate / 1000);
    item.time = now;
    if (item.tokens < 1) return false;
    item.tokens -= 1;
    return true;
  }
  function handleMessage(client, raw, binary) {
    const now = performance.now();
    if (!takeToken(client, 'messages', now, 80, 120)) {
      client.ws.close(1008, 'Message rate exceeded');
      return;
    }
    if (binary) return error(client, 'Use UTF-8 JSON text messages.');
    let data;
    try { data = JSON.parse(raw.toString()); } catch { return error(client, 'Invalid JSON.'); }
    if (!data || typeof data !== 'object' || Array.isArray(data) || typeof data.type !== 'string') return error(client, 'A message needs a type.');
    if (data.type === 'ping') {
      if (typeof data.t !== 'number' || !Number.isFinite(data.t)) return error(client, 'Ping t must be a number.');
      return send(client, { type: 'pong', t: data.t });
    }
    if (data.type === 'create' || data.type === 'join') {
      if (data.protocol !== PROTOCOL) return error(client, 'Game/server version mismatch. This server requires combat protocol 4. Install the matching Combat 05 game build and update the server together.');
      if (!takeToken(client, 'attempts', now, 0.5, 8)) return error(client, 'Too many room attempts. Wait a few seconds.');
      if (client.roomCode) return error(client, 'Leave the current room first.');
      const name = validName(data.name);
      if (!name) return error(client, 'Choose a player name of 1 to 24 characters.');
      if (data.type === 'create') {
        if (rooms.size >= maxRooms) return error(client, 'This server has no free rooms. Try again later.');
        const mode = normalizeMode(data.mode ?? 'ffa');
        if (!mode) return error(client, 'Mode must be free-for-all or 2v2 teams.');
        const requestedParty = data.party ?? data.team;
        if (requestedParty !== undefined && validParty(requestedParty) === null) return error(client, 'Choose Red (0) or Blue (1).');
        let code;
        do { code = Array.from({ length: 6 }, () => ALPHABET[randomInt(ALPHABET.length)]).join(''); } while (rooms.has(code));
        const room = { code, hostId: client.id, phase: 'lobby', roundId: 0, mode, godOptions: { ...DEFAULT_GOD_OPTIONS }, match: newTownMatch(DEFAULT_GOD_OPTIONS), players: new Map(), eventId: 0, lastActivity: now };
        rooms.set(code, room);
        return joinRoom(client, room, name, requestedParty ?? null);
      }
      if (typeof data.code !== 'string' || !/^[A-Z2-9]{6}$/.test(data.code.trim().toUpperCase())) return error(client, 'Room codes contain six letters or numbers.');
      const room = rooms.get(data.code.trim().toUpperCase());
      if (!room) return error(client, 'Room not found on this server. Check the code and server address.');
      if (!isTown(room)) return error(client, 'That room is in a round. Ask its host to return to the Town Lobby.');
      if (room.players.size >= MAX_PLAYERS) return error(client, 'That room is full (four players maximum).');
      const requestedParty = data.party ?? data.team;
      if (requestedParty !== undefined && validParty(requestedParty) === null) return error(client, 'Choose Red (0) or Blue (1).');
      return joinRoom(client, room, name, requestedParty ?? null);
    }
    if (data.type === 'leave') return leave(client);
    const room = rooms.get(client.roomCode);
    if (!room) return error(client, 'Create or join a room first.');
    if (data.type === 'input') {
      if (!['playing', 'lobby'].includes(room.phase)) return;
      if (room.phase === 'playing' && !movementActive(room.match)) return;
      if (![data.x, data.z, data.yaw].every(value => typeof value === 'number' && Number.isFinite(value)) ||
          typeof data.block !== 'boolean' || (data.sprint !== undefined && typeof data.sprint !== 'boolean') ||
          (data.crouch !== undefined && typeof data.crouch !== 'boolean') || !Number.isSafeInteger(data.seq) || data.seq < 0) {
        return error(client, 'Input needs finite x/z/yaw numbers, boolean block/sprint/crouch, and a nonnegative integer seq.');
      }
      const previousSeq = client.seq;
      applyInput(client, data, now);
      if (data.seq > previousSeq && client.health > 0 && (client.inputX || client.inputZ || client.block)) room.lastActivity = now;
      return;
    }
    if (data.type === 'jump' || data.type === 'punch') {
      if (!['playing', 'lobby'].includes(room.phase)) return;
      if (room.phase === 'playing' && !combatActive(room.match)) return;
      if (!Number.isSafeInteger(data.action_seq) || data.action_seq < 1) return error(client, 'Actions need a positive integer action_seq.');
      const combatOptions = effectiveOptions(room);
      if (data.type === 'punch' && room.match.objective?.sword_owner === client.id) {
        combatOptions.attack_damage = room.godOptions.sword_damage;
        combatOptions.attack_range = room.godOptions.sword_range;
        combatOptions.attack_speed = 1.0 / Math.max(0.2, room.godOptions.sword_attack_recovery);
        combatOptions.knockback_strength = room.godOptions.sword_knockback;
        combatOptions.sword_arc = room.godOptions.sword_swing_arc;
        combatOptions.sword_blockable = room.godOptions.sword_blockable;
        combatOptions.sword_block_damage_reduction = room.godOptions.sword_block_damage_reduction;
        combatOptions.air_damage_multiplier = room.godOptions.sword_jump_critical_enabled ? room.godOptions.sword_critical_damage_multiplier : 1;
      }
      const events = performAction(client, room.players.values(), data.type, data.action_seq, now, combatOptions, room.mode);
      if (data.type === 'punch' && room.match.objective?.enabled && combatActive(room.match) && !room.match.objective.sword_accessible && Math.hypot(client.x, client.z) <= combatOptions.attack_range + 1.8) {
        damageCrystal(room.match, client, room.godOptions);
      }
      if (events.length) {
        room.lastActivity = now;
        broadcastCombat(room, events);
        broadcastState(room);
      }
      return;
    }
    if (data.type === 'crystal_hit') {
      if (room.phase !== 'playing' || !combatActive(room.match)) return;
      const player = room.players.get(client.id);
      if (!player || !Number.isSafeInteger(data.action_seq) || data.action_seq < 1) return error(client, 'Crystal attacks need a positive action sequence.');
      if (damageCrystal(room.match, player, room.godOptions)) { broadcastState(room); }
      return;
    }
    if (data.type === 'pickup_sword') {
      if (room.phase !== 'playing' || !combatActive(room.match)) return;
      const player = room.players.get(client.id);
      if (player && pickupSword(room.match, player, room.godOptions)) broadcastState(room);
      return;
    }
    if (data.type === 'ready') {
      if (!takeToken(client, 'controls', now, 4, 12)) return error(client, 'Too many room actions. Wait a moment.');
      if (typeof data.ready !== 'boolean') return error(client, 'Ready must be true or false.');
      if (room.phase !== 'ready_check') return error(client, 'Ready can only change during a ready check.');
      client.ready = data.ready;
      room.lastActivity = now;
      if ([...room.players.values()].every(p => p.ready)) reset(room, 'playing');
      broadcastRoom(room);
      return broadcastState(room);
    }
    if (data.type === 'set_party' || data.type === 'set_team') {
      if (!takeToken(client, 'controls', now, 4, 12)) return error(client, 'Too many room actions. Wait a moment.');
      if (room.phase !== 'lobby') return error(client, 'Choose your team in the Town Lobby before the ready check.');
      const requestedParty = data.party ?? data.team;
      const party = validParty(requestedParty);
      if (party === null) return error(client, 'Choose Red (0) or Blue (1).');
      if (room.phase !== 'lobby' && room.mode === 'teams' && client.party !== party) {
        const counts = [0, 0];
        for (const p of room.players.values()) counts[p.party] += 1;
        counts[client.party] -= 1;
        counts[party] += 1;
        if (counts[0] !== counts[1]) return error(client, 'Active 2v2 teams must stay balanced. Choose teams in the lobby.');
      }
      // The lobby is intentionally permissive so players can choose teams in
      // any order. Start validates the final 2v2 arrangement.
      if (client.party === party) {
        room.lastActivity = now;
        return broadcastRoom(room);
      }
      client.party = party;
      keepHostReady(room);
      room.lastActivity = now;
      broadcastRoom(room);
      return broadcastState(room);
    }
    if (data.type === 'set_mode' || data.type === 'mode') {
      if (room.hostId !== client.id) return error(client, 'Only the room host can change the game mode.');
      if (room.phase !== 'lobby') return error(client, 'Choose the game mode in the Town Lobby before the ready check.');
      if (!takeToken(client, 'controls', now, 4, 12)) return error(client, 'Too many room actions. Wait a moment.');
      const mode = normalizeMode(data.mode);
      if (!mode) return error(client, 'Mode must be free-for-all or 2v2 teams.');
      if (room.phase !== 'lobby' && mode === 'teams') {
        const red = [...room.players.values()].filter(p => p.party === 0).length;
        const blue = [...room.players.values()].filter(p => p.party === 1).length;
        if (room.players.size !== MAX_PLAYERS || red !== 2 || blue !== 2) return error(client, 'Active 2v2 mode needs four players: two on Red and two on Blue.');
      }
      if (room.mode === mode) {
        room.lastActivity = now;
        return broadcastRoom(room);
      }
      room.mode = mode;
      keepHostReady(room);
      room.lastActivity = now;
      broadcastRoom(room);
      return broadcastState(room);
    }
    if (data.type === 'god_options' || data.type === 'set_god_options' || data.type === 'set_options') {
      if (room.hostId !== client.id) return error(client, 'Only the room host can change Host / God Options.');
      if (!takeToken(client, 'godOptions', now, 12, 24)) return error(client, 'Too many gameplay option changes. Wait a moment.');
      // The host owns gameplay rules; authoritative values are replicated to everyone.
      const previous = room.godOptions;
      const patch = Object.hasOwn(data, 'options') ? data.options
        : Object.hasOwn(data, 'god_options') ? data.god_options
        : Object.hasOwn(data, 'patch') ? data.patch : data;
      if (data.reset !== true && !validGodOptionsPatch(patch)) {
        return error(client, 'Gameplay options must be an object.');
      }
      const next = data.reset === true ? { ...DEFAULT_GOD_OPTIONS } : sanitizeGodOptions(previous, patch);
      room.godOptions = next;
      updatePlayerOptions(room.players.values(), previous, next, now);
      updateMatchOptions(room.match, previous, next);
      room.lastActivity = now;
      broadcastRoom(room);
      return broadcastState(room);
    }
    if (!takeToken(client, 'controls', now, 4, 12)) return error(client, 'Too many room actions. Wait a moment.');
    if (!['start', 'restart', 'lobby', 'cancel_start'].includes(data.type)) return error(client, 'Unknown message type.');
    if (room.hostId !== client.id) return error(client, 'Only the room host can do that.');
    if (data.type === 'start') {
      if (room.phase !== 'lobby') return error(client, 'A battle or ready check has already started.');
      if (!inOldManRange(client)) return error(client, 'Move closer to the Old Man to start a battle.');
      if (room.mode === 'teams') {
        const red = [...room.players.values()].filter(p => p.party === 0).length;
        const blue = [...room.players.values()].filter(p => p.party === 1).length;
        if (room.players.size !== MAX_PLAYERS || red !== 2 || blue !== 2) return error(client, '2v2 mode needs four players: two on Red and two on Blue.');
      }
      keepHostReady(room);
      stopControls(room);
      room.phase = 'ready_check';
      room.match = newReadyCheck(room.godOptions);
    } else if (data.type === 'restart') {
      if (room.phase !== 'playing') return error(client, 'Talk to the Old Man in Town to start a battle.');
      reset(room, 'playing');
    } else if (data.type === 'cancel_start') {
      if (room.phase !== 'ready_check') return error(client, 'There is no ready check to cancel.');
      cancelReadyCheck(room, 'The host cancelled the ready check.');
    } else {
      reset(room, 'lobby');
    }
    broadcastRoom(room);
    broadcastState(room);
  }

  httpServer.on('upgrade', (req, socket, head) => {
    const ip = req.socket.remoteAddress ?? 'unknown';
    if (stopped || (req.url !== '/' && req.url !== '/ws')) {
      socket.end('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
      return;
    }
    if (clients.size >= maxConnections || (ipConnections.get(ip) ?? 0) >= maxConnectionsPerIp) {
      socket.end('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n');
      return;
    }
    wss.handleUpgrade(req, socket, head, ws => { wss.emit('connection', ws, req); });
  });
  wss.on('connection', (ws, req) => {
    const now = performance.now();
    const ip = req.socket.remoteAddress ?? 'unknown';
    const client = { ws, ip, id: randomUUID(), roomCode: '', alive: true,
      messages: { tokens: 120, time: now }, attempts: { tokens: 8, time: now }, controls: { tokens: 12, time: now }, godOptions: { tokens: 24, time: now } };
    clients.set(ws, client);
    ipConnections.set(ip, (ipConnections.get(ip) ?? 0) + 1);
    ws.on('pong', payload => {
      client.alive = true;
      if (client.pingToken && payload.toString() === client.pingToken) {
        client.pingMs = Math.max(0, Math.round(performance.now() - client.pingSent));
        client.pingToken = null;
      }
    });
    client.pingSent = performance.now();
    client.pingToken = randomUUID();
    ws.ping(client.pingToken);
    ws.on('error', () => { ws.terminate(); });
    ws.on('message', (raw, binary) => { handleMessage(client, raw, binary); });
    ws.on('close', () => {
      leave(client, true);
      clients.delete(ws);
      const remaining = (ipConnections.get(ip) ?? 1) - 1;
      if (remaining > 0) ipConnections.set(ip, remaining); else ipConnections.delete(ip);
    });
    send(client, { type: 'welcome', id: client.id, protocol: PROTOCOL });
  });

  let lastSimulationTime = performance.now();
  let accumulatedMs = 0;
  const simulation = setInterval(() => {
    const now = performance.now();
    // Carry ordinary timer jitter forward instead of treating every callback as
    // exactly 50 ms. Catch up at most two fixed steps after a long server stall.
    accumulatedMs += Math.min(TICK_MS * 2, Math.max(0, now - lastSimulationTime));
    lastSimulationTime = now;
    const steps = Math.floor(accumulatedMs / TICK_MS);
    accumulatedMs -= steps * TICK_MS;
    ticks += steps;
    for (const room of rooms.values()) {
      if (now - room.lastActivity > idleMs) {
        broadcast(room, { type: 'error', message: 'This room expired after inactivity. Create a new room.' });
        for (const player of room.players.values()) {
          player.roomCode = '';
          send(player, { type: 'room', code: '', host_id: '', phase: 'lobby', level: LEVEL, players: [] });
        }
        rooms.delete(room.code);
        continue;
      }
      if (steps === 0) continue;
      if (room.phase === 'ready_check') {
        if (advanceReadyCheck(room.match, steps * TICK_MS / 1000)) {
          cancelReadyCheck(room, 'The ready check expired. Everyone stayed in Town.');
          broadcastRoom(room);
        }
        broadcastState(room);
        continue;
      }
      if (!['playing', 'lobby'].includes(room.phase)) continue;
      for (let step = 0; step < steps; step++) {
        if (room.phase === 'lobby' || movementActive(room.match)) {
          broadcastCombat(room, stepPlayers(room.players.values(), TICK_MS / 1000, now, effectiveOptions(room)));
        }
        if (room.phase === 'playing') {
          const previousPhase = room.match.phase;
          const transition = advanceMatch(room.match, TICK_MS / 1000, room.players.values(), room.mode, room.godOptions);
          if (transition === 'return_town') {
            reset(room, 'lobby');
          } else if (transition === 'next_round') {
            room.roundId += 1;
            for (const player of room.players.values()) resetPlayer(player, true, false, room.godOptions);
          }
          if (room.match.phase !== previousPhase) {
            stopControls(room);
            broadcastRoom(room);
          }
        }
      }
      broadcastState(room);
    }
  }, TICK_MS);
  const heartbeat = setInterval(() => {
    for (const client of clients.values()) {
      if (!client.alive) { client.ws.terminate(); continue; }
      client.alive = false;
      if (client.ws.readyState === WebSocket.OPEN) {
        client.pingSent = performance.now();
        client.pingToken = randomUUID();
        client.ws.ping(client.pingToken);
      }
    }
  }, heartbeatMs);

  async function close() {
    if (stopped) return;
    stopped = true;
    clearInterval(simulation);
    clearInterval(heartbeat);
    for (const ws of wss.clients) ws.terminate();
    await Promise.all([
      new Promise(resolve => wss.close(resolve)),
      new Promise(resolve => { httpServer.close(resolve); httpServer.closeAllConnections(); })
    ]);
    rooms.clear();
    clients.clear();
    ipConnections.clear();
  }
  try {
    await new Promise((resolve, reject) => {
      httpServer.once('error', reject);
      httpServer.listen(port, host, () => { httpServer.removeListener('error', reject); resolve(); });
    });
  } catch (cause) {
    await close();
    throw cause;
  }
  const address = httpServer.address();
  return { port: address.port, host, httpServer, close,
    stats: () => ({ rooms: rooms.size, connections: clients.size, ticks }) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  startServer().then(server => {
    console.log(`Co-op Foundation listening on ${server.host}:${server.port}; protocol 4; health /health`);
    const shutdown = () => { server.close().then(() => process.exit(0)); };
    process.once('SIGINT', shutdown);
    process.once('SIGTERM', shutdown);
  }).catch(cause => { console.error(cause.message); process.exitCode = 1; });
}
