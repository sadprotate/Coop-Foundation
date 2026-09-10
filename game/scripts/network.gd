extends Node

signal room_changed(data: Dictionary)
signal state_changed(data: Dictionary)
signal status_changed(message: String)
signal notice(message: String)
signal failure(message: String)
signal combat_event(data: Dictionary)

const PROTOCOL := 4

const PRACTICE_MATCH_SCRIPT = preload("res://scripts/practice_match.gd")
const DEFAULT_GOD_OPTIONS := {
	"god_mode": false, "attack_speed": 2.0, "attack_damage": 10.0,
	"move_speed": 5.5, "jump_speed": 1.0, "jump_height": 1.225, "max_jumps": 1,
	"max_health": 100, "attack_range": 2.2, "air_damage_multiplier": 2.0,
	"block_speed_multiplier": 2.5 / 5.5, "respawn_seconds": 3.0,
	"starting_health": 100, "sprint_speed": 9.0, "max_stamina": 100,
	"stamina_drain": 25.0, "stamina_regen": 20.0, "stamina_regen_delay": 1.0,
	"gravity": 20.0, "max_fall_speed": 30.0, "fall_damage": false,
	"fall_damage_threshold": 4.0, "fall_damage_multiplier": 10.0,
	"sword_objective_enabled": true, "crystal_max_health": 100, "crystal_damage_per_punch": 10, "crystal_break_stages": 4, "sword_accessibility_threshold": 0.25, "sword_pickup_range": 2.2, "sword_pickup_hold_time": 0, "sword_damage": 30, "sword_range": 3.4, "sword_swing_arc": 1.2, "sword_swing_speed": 1.0, "sword_attack_recovery": 1.2, "sword_knockback": 4.0, "sword_blockable": true, "sword_block_damage_reduction": 0.8, "sword_movement_speed_multiplier": 1.0, "sword_jump_critical_enabled": true, "sword_critical_damage_multiplier": 2.0,
	"crouch_speed": 2.5, "damage_multiplier": 1.0, "knockback_strength": 2.0,
	"round_duration": 150, "knockouts_to_win": 4, "total_rounds": 10, "ready_check_seconds": 15, "camera_fov": 55.0, "camera_distance": 11.5, "camera_height": 11.0, "camera_vertical_offset": 1.0, "camera_min_pitch": 35.0, "camera_max_pitch": 75.0, "camera_rotation_speed": 1.0, "camera_smoothing": 0.85, "camera_follow_speed": 16.0, "camera_zoom_min": 8.0, "camera_zoom_max": 20.0
}
const GOD_RANGES := {
	"crystal_max_health": Vector2(10, 1000), "crystal_damage_per_punch": Vector2(1, 100), "crystal_break_stages": Vector2(2, 8), "sword_accessibility_threshold": Vector2(0, 1), "sword_pickup_range": Vector2(0.5, 5), "sword_pickup_hold_time": Vector2(0, 5), "sword_damage": Vector2(1, 200), "sword_range": Vector2(1, 8), "sword_swing_arc": Vector2(0.2, 3.14), "sword_swing_speed": Vector2(0.2, 5), "sword_attack_recovery": Vector2(0.2, 5), "sword_knockback": Vector2(0, 20), "sword_block_damage_reduction": Vector2(0, 1), "sword_movement_speed_multiplier": Vector2(0.2, 2), "sword_critical_damage_multiplier": Vector2(1, 5),
	"attack_speed": Vector2(0.2, 10), "attack_damage": Vector2(0, 100),
	"move_speed": Vector2(1, 20), "jump_speed": Vector2(0.25, 3),
	"jump_height": Vector2(0.25, 10), "max_jumps": Vector2(1, 10),
	"max_health": Vector2(10, 1000), "attack_range": Vector2(0.5, 5),
	"air_damage_multiplier": Vector2(1, 5), "block_speed_multiplier": Vector2(0, 1),
	"respawn_seconds": Vector2(0.5, 10), "starting_health": Vector2(1, 1000),
	"sprint_speed": Vector2(1, 30), "max_stamina": Vector2(1, 1000),
	"stamina_drain": Vector2(0, 200), "stamina_regen": Vector2(0, 200),
	"stamina_regen_delay": Vector2(0, 10), "gravity": Vector2(1, 80),
	"max_fall_speed": Vector2(1, 100), "fall_damage_threshold": Vector2(0, 50),
	"fall_damage_multiplier": Vector2(0, 100), "crouch_speed": Vector2(0.1, 15),
	"damage_multiplier": Vector2(0, 10), "knockback_strength": Vector2(0, 15),
	"round_duration": Vector2(10, 1800), "knockouts_to_win": Vector2(1, 50),
	"total_rounds": Vector2(1, 50), "ready_check_seconds": Vector2(3, 120), "camera_fov": Vector2(35, 90), "camera_distance": Vector2(8, 20), "camera_height": Vector2(5, 30), "camera_vertical_offset": Vector2(-3, 8), "camera_min_pitch": Vector2(20, 85), "camera_max_pitch": Vector2(20, 89), "camera_rotation_speed": Vector2(0.1, 5), "camera_smoothing": Vector2(0, 1), "camera_follow_speed": Vector2(1, 30), "camera_zoom_min": Vector2(4, 20), "camera_zoom_max": Vector2(10, 40)
}
const INTEGER_GOD_OPTIONS := ["max_health", "starting_health", "max_jumps", "max_stamina", "round_duration", "knockouts_to_win", "total_rounds", "ready_check_seconds", "arena_start_countdown"]

var socket: WebSocketPeer
var player_id: String = ""
var room: Dictionary = {}
var snapshot: Dictionary = {}
var practice: bool = false
var connecting: bool = false
var pending: Dictionary = {}
var elapsed: float = 0.0
var last_packet: float = 0.0
var ping_timer: float = 0.0
var send_timer: float = 0.0
var move_axis := Vector2.ZERO
var facing_yaw: float = 0.0
var blocking: bool = false
var sprinting: bool = false
var crouching: bool = false
var sequence: int = 0
var action_sequence: int = 0
var latency_ms: int = 0
var practice_cooldown: float = 0.0
var practice_event_id: int = 0
var pending_jumps: Array[int] = []
var practice_match: RefCounted = PRACTICE_MATCH_SCRIPT.new()

func connect_room(address: String, request: Dictionary) -> void:
	leave()
	var url := address.strip_edges()
	if url.begins_with("https://"):
		url = "wss://" + url.substr(8)
	elif url.begins_with("http://"):
		url = "ws://" + url.substr(7)
	if not (url.begins_with("wss://") or url.begins_with("ws://")):
		failure.emit("Enter the shared server URL first (wss://your-server.onrender.com).")
		return
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 262144
	socket.outbound_buffer_size = 65536
	var result := socket.connect_to_url(url)
	if result != OK:
		socket = null
		failure.emit("Could not connect: " + error_string(result))
		return
	pending = request.duplicate()
	pending["protocol"] = PROTOCOL
	connecting = true
	elapsed = 0.0
	last_packet = 0.0
	ping_timer = 0.0
	status_changed.emit("Connecting… A sleeping free server can take about a minute.")

func _process(delta: float) -> void:
	if practice:
		_step_practice(minf(delta, 0.1))
		return
	if socket == null:
		return
	elapsed += delta
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count() > 0:
			var raw := socket.get_packet().get_string_from_utf8()
			var data = JSON.parse_string(raw)
			if typeof(data) == TYPE_DICTIONARY:
				last_packet = elapsed
				_receive(data)
			if socket == null:
				return
		ping_timer += delta
		if ping_timer >= 5.0:
			ping_timer = 0.0
			send({"type": "ping", "t": Time.get_ticks_msec()})
		send_timer += delta
		if send_timer >= 0.05 and can_control():
			send_timer = 0.0
			flush_input()
		if elapsed - last_packet > 20.0:
			_disconnect_error("The server stopped responding. Return to the menu and reconnect.")
	elif state == WebSocketPeer.STATE_CLOSED:
		_disconnect_error("Connection closed. Check the server address and internet connection, then try again.")
	elif connecting and elapsed > 90.0:
		_disconnect_error("Connection timed out. Open the server's https:// address to wake it, then try again.")

func _receive(data: Dictionary) -> void:
	match str(data.get("type", "")):
		"welcome":
			if int(data.get("protocol", 0)) != PROTOCOL:
				_disconnect_error("Server update needed: this game requires protocol 4. Deploy its matching server files to your existing Render service, then reconnect.")
				return
			player_id = str(data.get("id", ""))
			connecting = false
			send(pending)
			pending = {}
			status_changed.emit("Connected to the shared server.")
		"room":
			if int(data.get("round_id", 0)) != int(room.get("round_id", 0)):
				pending_jumps.clear()
			room = data
			room_changed.emit(room)
		"state":
			if int(data.get("round_id", 0)) != int(room.get("round_id", 0)):
				pending_jumps.clear()
			snapshot = data
			for key: String in ["phase", "zone", "safe_zone", "match", "round_id"]:
				if data.has(key):
					room[key] = data[key]
			if data.has("god_options"):
				room["god_options"] = data.god_options
			if data.has("mode"):
				room["mode"] = data.mode
			var acknowledged: int = int(local_player().get("action_seq", 0))
			while not pending_jumps.is_empty() and pending_jumps[0] <= acknowledged:
				pending_jumps.pop_front()
			state_changed.emit(snapshot)
		"combat":
			combat_event.emit(data)
		"pong":
			latency_ms = maxi(0, Time.get_ticks_msec() - int(data.get("t", Time.get_ticks_msec())))
		"error":
			failure.emit(str(data.get("message", "The server could not complete that action.")))
		"info", "notice":
			var message: String = str(data.get("message", ""))
			status_changed.emit(message)
			notice.emit(message)

func send(data: Dictionary) -> void:
	if practice:
		_practice_command(data)
	elif socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if socket.get_current_outbound_buffered_amount() < 32768:
			socket.send_text(JSON.stringify(data))

func leave() -> void:
	if socket != null:
		socket.close(1000, "Left room")
		socket = null
	practice = false
	connecting = false
	player_id = ""
	room = {}
	snapshot = {}
	pending = {}
	move_axis = Vector2.ZERO
	facing_yaw = 0.0
	blocking = false
	sprinting = false
	crouching = false
	sequence = 0
	action_sequence = 0
	pending_jumps.clear()
	latency_ms = 0

func _disconnect_error(message: String) -> void:
	leave()
	room_changed.emit({})
	failure.emit(message)

func start_practice() -> void:
	leave()
	practice = true
	player_id = "local"
	room = {"code": "PRACTICE", "host_id": "local", "phase": "lobby", "level": 3, "round_id": 0,
		"mode": "ffa", "god_options": DEFAULT_GOD_OPTIONS.duplicate(),
		"players": [{"id": "local", "name": Prefs.player_name, "slot": 0, "party": 0, "ready": false}]}
	practice_match.initialize(self)
	status_changed.emit("Welcome to town. Talk to the Old Man when you are ready for battle.")

func _reset_practice(zone: String = "arena") -> void:
	practice_cooldown = 0.0
	room["phase"] = "lobby" if zone == "town" else "playing"
	room["zone"] = zone
	room["safe_zone"] = zone == "town"
	move_axis = Vector2.ZERO
	blocking = false
	sprinting = false
	crouching = false
	pending_jumps.clear()
	var rules: Dictionary = god_options()
	snapshot = {"tick": 0, "phase": room.phase, "zone": zone, "safe_zone": zone == "town",
		"round_id": int(room.get("round_id", 0)), "match": room.get("match", {}).duplicate(true),
		"level": 3, "mode": room.get("mode", "ffa"), "god_options": rules.duplicate(),
		"players": [{"id": "local", "x": -3.0 if zone == "town" else -4.0, "y": 0.0, "z": 2.0 if zone == "town" else 0.0, "slot": 0,
		"name": Prefs.player_name, "party": int(room.players[0].get("party", 0)),
		"yaw": 0.0, "health": mini(int(rules.starting_health), int(rules.max_health)), "max_health": rules.max_health, "grounded": true, "block": false,
		"sprinting": false, "crouching": false, "body_height": 1.8,
		"stamina": rules.max_stamina, "max_stamina": rules.max_stamina, "stamina_regen_in": 0.0, "sprint_exhausted": false,
		"fall_peak": 0.0, "invulnerable_for": 0.0,
		"jumps_used": 0, "action_seq": action_sequence,
		"punch_t": 0.0, "hurt_t": 0.0, "respawn_in": 0.0, "invulnerable": false, "vy": 0.0}]}

func _step_practice(delta: float) -> void:
	if snapshot.is_empty():
		return
	if practice_match.tick(self, delta) or not can_control():
		return
	var p: Dictionary = snapshot.players[0]
	var rules: Dictionary = god_options()
	practice_cooldown = maxf(0.0, practice_cooldown - delta)
	p.punch_t = maxf(0.0, float(p.punch_t) - delta)
	p.hurt_t = maxf(0.0, float(p.hurt_t) - delta)
	p.invulnerable_for = maxf(0.0, float(p.invulnerable_for) - delta)
	p.invulnerable = float(p.invulnerable_for) > 0.0
	if float(p.health) <= 0.0:
		p.respawn_in = maxf(0.0, float(p.respawn_in) - delta)
		if float(p.respawn_in) <= 0.000001:
			_respawn_practice(p, rules)
		_publish_practice_step()
		return
	p.block = blocking
	p.yaw = facing_yaw
	var axis := move_axis.limit_length(1.0)
	p.crouching = crouching
	p.body_height = 0.95 if crouching else 1.8
	if not sprinting:
		p.sprint_exhausted = false
	p.sprinting = sprinting and axis.length_squared() > 0.0001 and not crouching and not blocking and not bool(p.sprint_exhausted) and float(p.stamina) > 0.0
	if bool(p.sprinting):
		p.stamina = maxf(0.0, float(p.stamina) - float(rules.stamina_drain) * delta)
		p.stamina_regen_in = rules.stamina_regen_delay
		if float(p.stamina) <= 0.0:
			p.sprint_exhausted = true
			p.sprinting = false
	else:
		var regen_delta: float = maxf(0.0, delta - float(p.stamina_regen_in))
		p.stamina_regen_in = maxf(0.0, float(p.stamina_regen_in) - delta)
		p.stamina = minf(float(rules.max_stamina), float(p.stamina) + float(rules.stamina_regen) * regen_delta)
	var speed: float = float(rules.move_speed)
	if crouching:
		speed = float(rules.crouch_speed)
	elif blocking:
		speed *= float(rules.block_speed_multiplier)
	elif bool(p.sprinting):
		speed = float(rules.sprint_speed)
	p.x = clampf(float(p.x) + axis.x * speed * delta, -18.0, 18.0)
	p.z = clampf(float(p.z) + axis.y * speed * delta, -18.0, 18.0)
	if not bool(p.grounded):
		var gravity: float = float(rules.gravity) * pow(float(rules.jump_speed), 2.0)
		var terminal: float = float(rules.max_fall_speed)
		var initial_vy: float = maxf(-terminal, float(p.vy))
		var accelerated_time: float = clampf((initial_vy + terminal) / gravity, 0.0, delta)
		p.y = maxf(0.0, float(p.y) + initial_vy * accelerated_time - 0.5 * gravity * accelerated_time * accelerated_time - terminal * (delta - accelerated_time))
		p.vy = maxf(-terminal, initial_vy - gravity * delta)
		p.fall_peak = maxf(float(p.fall_peak), float(p.y))
		if float(p.y) <= 0.0:
			p.grounded = true
			p.vy = 0.0
			p.jumps_used = 0
			if bool(rules.fall_damage) and not bool(rules.god_mode) and not in_town() and not bool(p.invulnerable):
				var damage: float = maxf(0.0, float(p.fall_peak) - float(rules.fall_damage_threshold)) * float(rules.fall_damage_multiplier) * float(rules.damage_multiplier)
				if damage > 0.0:
					p.health = maxf(0.0, float(p.health) - damage)
					p.hurt_t = 0.28
					_emit_practice_target_event("hit", damage)
					if float(p.health) <= 0.0:
						p.respawn_in = rules.respawn_seconds
						p.block = false
						p.sprinting = false
						p.punch_t = 0.0
						_emit_practice_target_event("defeat", damage)
			p.fall_peak = 0.0
	_publish_practice_step()

func _publish_practice_step() -> void:
	snapshot.tick = int(snapshot.tick) + 1
	state_changed.emit(snapshot)

func _respawn_practice(p: Dictionary, rules: Dictionary) -> void:
	p.merge({"x": -4.0, "z": 0.0, "y": 0.0, "vy": 0.0, "yaw": 0.0,
		"health": mini(int(rules.starting_health), int(rules.max_health)), "max_health": rules.max_health,
		"grounded": true, "jumps_used": 0, "fall_peak": 0.0, "block": false,
		"sprinting": false, "crouching": false, "body_height": 1.8,
		"stamina": rules.max_stamina, "max_stamina": rules.max_stamina,
		"stamina_regen_in": 0.0, "sprint_exhausted": false,
		"punch_t": 0.0, "hurt_t": 0.0, "respawn_in": 0.0,
		"invulnerable_for": 1.0, "invulnerable": true}, true)
	practice_cooldown = 0.0
	_emit_practice_target_event("respawn")

func _emit_practice_target_event(kind: String, damage: float = 0.0) -> void:
	practice_event_id += 1
	combat_event.emit({"type": "combat", "event_id": practice_event_id, "kind": kind,
		"attacker": "", "target": player_id, "damage": damage, "critical": false, "source": "fall"})

func _practice_command(data: Dictionary) -> void:
	if practice_match.handle_command(self, data):
		return
	if data.get("type") == "god_options":
		_apply_practice_options(data)
	elif data.get("type") == "set_party":
		if room.get("phase") != "lobby":
			failure.emit("Choose teams in town before starting the ready check.")
			return
		var party: int = clampi(int(data.get("party", 0)), 0, 1)
		room.players[0].party = party
		snapshot.players[0].party = party
		room_changed.emit(room)
		state_changed.emit(snapshot)
	elif data.get("type") == "set_mode":
		if room.get("phase") != "lobby":
			failure.emit("Choose the game mode in town before starting the ready check.")
		elif data.get("mode") != "ffa":
			failure.emit("2v2 needs four online players: two on Red and two on Blue.")
	elif data.get("type") == "jump":
		if not can_control():
			return
		var p: Dictionary = snapshot.players[0]
		var rules: Dictionary = god_options()
		p.action_seq = int(data.get("action_seq", 0))
		if float(p.health) > 0.0 and int(p.jumps_used) < int(rules.max_jumps):
			p.vy = sqrt(2.0 * float(rules.gravity) * float(rules.jump_height)) * float(rules.jump_speed)
			p.jumps_used = int(p.jumps_used) + 1
			p.grounded = false
			_practice_event("jump", false)
	elif data.get("type") == "punch":
		if not can_control():
			return
		var p: Dictionary = snapshot.players[0]
		p.action_seq = int(data.get("action_seq", 0))
		if float(p.health) > 0.0 and not blocking and practice_cooldown <= 0.0:
			practice_cooldown = 1.0 / float(god_options().attack_speed)
			p.punch_t = minf(0.25, practice_cooldown)
			p.invulnerable_for = 0.0
			p.invulnerable = false
			var objective: Dictionary = room.get("match", {}).get("objective", {})
			if objective.get("enabled", false) and room.get("match", {}).get("phase", "") in ["round", "overtime"] and Vector2(float(p.get("x", 0)), float(p.get("z", 0))).length() <= float(god_options().get("attack_range", 2.2)) and not objective.get("sword_accessible", false):
				objective.crystal_health = maxf(0.0, float(objective.crystal_health) - float(god_options().get("crystal_damage_per_punch", 10)))
				var ratio := float(objective.crystal_health) / maxf(1.0, float(objective.crystal_max_health))
				objective.break_stage = mini(int(god_options().get("crystal_break_stages", 4)), int((1.0 - ratio) * float(god_options().get("crystal_break_stages", 4))))
				objective.sword_accessible = ratio <= float(god_options().get("sword_accessibility_threshold", 0.25)) or objective.crystal_health <= 0.0
				_publish_practice_step()
			else:
				_practice_event("miss", not bool(p.grounded))

func _practice_event(kind: String, critical: bool) -> void:
	practice_event_id += 1
	combat_event.emit({"type": "combat", "event_id": practice_event_id, "kind": kind,
		"attacker": player_id, "target": "", "damage": 0, "critical": critical})

func local_player() -> Dictionary:
	for player: Dictionary in snapshot.get("players", []):
		if str(player.get("id", "")) == player_id:
			return player
	return {}

func in_town() -> bool:
	return not room.is_empty() and str(room.get("zone", "")) == "town"

func can_control() -> bool:
	if room.is_empty():
		return false
	if str(room.get("phase", "")) == "lobby":
		return true
	return room.get("phase") == "playing" and str(room.get("match", {}).get("phase", "round")) in ["countdown", "round", "overtime"]

func near_old_man() -> bool:
	var player: Dictionary = local_player()
	if not in_town() or room.get("phase") != "lobby" or player.is_empty() or float(player.get("health", 0)) <= 0.0:
		return false
	return Vector3(float(player.get("x", 0)), float(player.get("y", 0)), float(player.get("z", 0))).distance_to(Vector3(0, 0, -5)) <= 3.0

func flush_input() -> void:
	if practice or not can_control():
		return
	sequence += 1
	send({"type": "input", "x": move_axis.x, "z": move_axis.y,
		"yaw": facing_yaw, "block": blocking, "sprint": sprinting, "crouch": crouching, "seq": sequence})

func jump() -> bool:
	var player := local_player()
	var used: int = int(player.get("jumps_used", 0)) + pending_jumps.size()
	if not can_control() or str(room.get("match", {}).get("phase", "round")) == "countdown" or float(player.get("health", 0)) <= 0.0 or used >= int(god_options().max_jumps):
		return false
	flush_input()
	action_sequence += 1
	if not practice:
		pending_jumps.append(action_sequence)
	send({"type": "jump", "action_seq": action_sequence})
	return true

func punch() -> bool:
	if not can_control() or str(room.get("match", {}).get("phase", "round")) == "countdown" or blocking or float(local_player().get("health", 0)) <= 0.0:
		return false
	flush_input()
	action_sequence += 1
	send({"type": "punch", "action_seq": action_sequence})
	return true

func pickup_sword() -> void:
	if practice:
		_practice_command({"type": "pickup_sword"})
		return
	if not can_control() or str(room.get("match", {}).get("phase", "round")) == "countdown":
		return
	send({"type": "pickup_sword"})

func god_options() -> Dictionary:
	var rules: Dictionary = DEFAULT_GOD_OPTIONS.duplicate()
	rules.merge(room.get("god_options", {}), true)
	return rules

func set_party(party: int) -> void:
	send({"type": "set_party", "party": party})

func set_mode(mode: String) -> void:
	send({"type": "set_mode", "mode": mode})

func set_god_options(changes: Dictionary) -> void:
	send({"type": "god_options", "options": changes})

func reset_god_options() -> void:
	send({"type": "god_options", "reset": true})

func _apply_practice_options(data: Dictionary) -> void:
	var previous: Dictionary = god_options()
	var rules: Dictionary = DEFAULT_GOD_OPTIONS.duplicate() if data.get("reset") == true else god_options()
	var changes = data.get("options", {})
	if changes is Dictionary:
		for key: String in changes:
			var value = changes[key]
			if key in ["god_mode", "fall_damage"] and value is bool:
				rules[key] = value
			elif GOD_RANGES.has(key) and (value is float or value is int) and is_finite(float(value)):
				var bounds: Vector2 = GOD_RANGES[key]
				rules[key] = clampf(float(value), bounds.x, bounds.y)
				if key in INTEGER_GOD_OPTIONS:
					rules[key] = roundi(float(rules[key]))
	room["god_options"] = rules
	snapshot["god_options"] = rules.duplicate()
	var p: Dictionary = local_player()
	if not p.is_empty():
		if int(previous.max_health) != int(rules.max_health):
			var damage_taken: float = float(p.max_health) - float(p.health)
			p.health = maxf(1.0, float(rules.max_health) - damage_taken) if float(p.health) > 0.0 else 0.0
		p.max_health = rules.max_health
		if int(previous.max_stamina) != int(rules.max_stamina):
			p.stamina = clampf(float(rules.max_stamina) - (float(previous.max_stamina) - float(p.stamina)), 0.0, float(rules.max_stamina))
		p.max_stamina = rules.max_stamina
		p.stamina_regen_in = minf(float(p.stamina_regen_in), float(rules.stamina_regen_delay))
		if float(p.respawn_in) > 0.0:
			p.respawn_in = float(p.respawn_in) * float(rules.respawn_seconds) / float(previous.respawn_seconds)
		if not bool(p.grounded):
			p.vy = float(p.vy) * float(rules.jump_speed) / float(previous.jump_speed)
	practice_cooldown *= float(previous.attack_speed) / float(rules.attack_speed)
	practice_match.options_changed(self, previous)
	room_changed.emit(room)
	state_changed.emit(snapshot)
