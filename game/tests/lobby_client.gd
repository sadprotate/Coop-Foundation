extends SceneTree

## Four real Godot/main clients. Files coordinate ordinary input only; no state injection.
## All player positions, hits and health come from the real WebSocket server.
## One-PC integration does not verify four-PC internet play.
var role: String = "host"
var address: String = "ws://127.0.0.1:18787"
var coordination: String = ""
var command_path: String = ""
var app: Control
var net: Node
var failures: int = 0
var finished: bool = false
var serial: int = 0
var applied_serial: int = -1
var room_code: String = ""
var initial_host: String = ""
var victim_id: String = ""
var command: Dictionary = {}
var observed_full: bool = false
var observed_departure: bool = false
var observed_return: bool = false
var saw_playing: bool = false
var saw_lobby_return: bool = false
var saw_jump: bool = false
var saw_yaw: bool = false
var saw_block: bool = false
var saw_defeat: bool = false
var saw_respawn: bool = false
var saw_block_event: bool = false
var saw_normal_hit_event: bool = false
var saw_critical_hit_event: bool = false
var health_values: Dictionary = {}
var first_positions: Dictionary = {}
var moved_players: Dictionary = {}
var started_at: int = 0
var ready_sent: bool = false
var ready_connection: String = ""
var previous_phase: String = ""
var saw_god_mode: bool = false
var saw_tuned_rules: bool = false
var saw_rules_reset: bool = false
var saw_teams: bool = false
var saw_ffa_after_teams: bool = false
var expected_error: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--server="):
			address = arg.trim_prefix("--server=")
		elif arg.begins_with("--coord="):
			coordination = arg.trim_prefix("--coord=")
	command_path = coordination.get_base_dir().path_join("combat-command.json")
	call_deferred("run")

func run() -> void:
	started_at = Time.get_ticks_msec()
	net = root.get_node("Net")
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	# Replace physical device polling only. UI and arena still receive real states.
	app.set_process(false)
	net.failure.connect(func(message: String):
		if not expected_error.is_empty() and message.to_lower().contains(expected_error):
			check(true, "Server rejected invalid live team change: " + message)
			expected_error = ""
		else:
			check(false, "Network error: " + message)
	)
	net.room_changed.connect(on_room)
	net.state_changed.connect(on_state)
	net.combat_event.connect(on_combat)
	worker_loop()
	if role == "host":
		net.connect_room(address, {"type": "create", "name": "Test Host"})
		await host_sequence()
	else:
		if not await until(func(): return FileAccess.file_exists(coordination), "host code file", 15.0):
			finish(false, "No room code")
			return
		room_code = FileAccess.get_file_as_string(coordination).strip_edges()
		join_room()

func join_room() -> void:
	net.connect_room(address, {"type": "join", "name": role, "code": room_code})

func worker_loop() -> void:
	while not finished:
		await create_timer(0.04).timeout
		if Time.get_ticks_msec() - started_at > 130000:
			finish(false, "Watchdog in " + str(command.get("label", "joining")))
			return
		if FileAccess.file_exists(command_path):
			# The writer can be between truncate and flush. Keep the last complete
			# command until parsing succeeds; JSON.parse does not log partial reads.
			var decoder := JSON.new()
			if decoder.parse(FileAccess.get_file_as_string(command_path)) == OK and decoder.data is Dictionary:
				command = decoder.data
		if command.is_empty():
			continue
		var actions: Dictionary = command.get("players", {})
		var intent: Dictionary = actions.get(role, {})
		var next_serial := int(command.get("serial", 0))
		var new_command := next_serial != applied_serial
		if new_command:
			applied_serial = next_serial
			if intent.has("expect_error"):
				expected_error = str(intent.expect_error)
			if intent.has("god_options"):
				net.set_god_options(intent.god_options)
			if bool(intent.get("reset_god_options", false)):
				net.reset_god_options()
			if intent.has("party"):
				net.set_party(int(intent.party))
			if intent.has("mode"):
				net.set_mode(str(intent.mode))
			if bool(intent.get("ready", false)):
				net.send({"type": "ready", "ready": true})
			if intent.get("session") == "leave":
				observed_departure = true
				net.leave()
			elif intent.get("session") == "join":
				join_room()
		if net.room.get("phase") == "playing":
			var p := player(net.player_id)
			if not p.is_empty():
				net.move_axis = Vector2.ZERO
				net.blocking = bool(intent.get("block", false))
				if intent.has("yaw"):
					net.facing_yaw = float(intent.yaw)
				if intent.has("target"):
					var target := Vector2(float(intent.target[0]), float(intent.target[1]))
					var displacement := target - Vector2(float(p.x), float(p.z))
					# Slow approach avoids oscillation from snapshot delay.
					if displacement.length() > 0.10:
						net.move_axis = displacement.limit_length(1.0)
				if new_command:
					if bool(intent.get("jump", false)):
						net.jump()
					if bool(intent.get("punch", false)):
						net.punch()
		if command.get("label") == "finish" and role != "host":
			if net.room.get("host_id", initial_host) != initial_host and net.room.get("players", []).size() <= 3:
				finish(common_evidence(), "four present / leave-rejoin / movement-yaw-jump / 10-20 damage / block / defeat-respawn / restart-lobby / host transfer")

func host_sequence() -> void:
	if not await until(func(): return net.room.get("players", []).size() == 4, "Four players joined", 15.0):
		finish(false, "Four joins")
		return
	await capture("lobby.png")
	issue("leave", {"guest3": {"session": "leave"}})
	if not await until(func(): return net.room.get("players", []).size() == 3, "Guest departure visible"):
		finish(false, "Guest departure")
		return
	await create_timer(0.25).timeout
	issue("rejoin", {"guest3": {"session": "join"}})
	if not await until(func(): return net.room.get("players", []).size() == 4 and everyone_ready(), "Guest rejoins and four ready"):
		finish(false, "Guest rejoin")
		return
	net.send({"type": "start"})
	if not await until(func(): return net.room.get("phase") == "playing" and net.snapshot.get("players", []).size() == 4, "Host starts 3D arena"):
		finish(false, "Start")
		return
	check(app.page == "game" and is_instance_valid(app.arena), "Real game arena loads")
	issue("positions", formation())
	if not await until(formation_ready, "All four move to arranged positions", 12.0):
		finish(false, "Movement")
		return
	await create_timer(0.3).timeout
	issue("punch_facing_away", formation({"yaw": PI / 2.0, "punch": true}))
	await create_timer(0.65).timeout
	check(health(victim_id) == 100, "Punch cannot hit an opponent behind the attacker's character")
	issue("ground_punch", formation({"punch": true}))
	if not await until(func(): return health(victim_id) == 90, "Grounded punch deals exactly 10"):
		finish(false, "Ground damage")
		return
	await create_timer(0.65).timeout
	issue("jump", formation({"jump": true}))
	if not await until(func(): return not bool(player(initial_host).get("grounded", true)), "Jump synchronized"):
		finish(false, "Jump")
		return
	issue("critical_punch", formation({"punch": true}))
	if not await until(func(): return health(victim_id) == 70, "Airborne punch deals exactly 20"):
		finish(false, "Critical damage")
		return
	await create_timer(0.8).timeout
	issue("front_block", formation({}, {"block": true, "yaw": PI / 2.0}))
	await until(func(): return bool(player(victim_id).get("block", false)), "Defender blocks toward attacker")
	issue("front_block_hit", formation({"punch": true}, {"block": true, "yaw": PI / 2.0}))
	await create_timer(0.65).timeout
	check(health(victim_id) == 70, "Frontal block prevents all normal damage")
	check(saw_block_event, "Server confirms the blocked hit with combat feedback")
	issue("rear_block", formation({}, {"block": true, "yaw": -PI / 2.0}))
	await create_timer(0.3).timeout
	issue("rear_hit", formation({"punch": true}, {"block": true, "yaw": -PI / 2.0}))
	if not await until(func(): return health(victim_id) == 60, "Block leaves rear vulnerable to exactly 10"):
		finish(false, "Rear damage")
		return
	await capture("arena.png")
	for expected in [50, 40, 30, 20, 10, 0]:
		await create_timer(0.65).timeout
		issue("damage_%d" % expected, formation({"punch": true}))
		if not await until(func(): return health(victim_id) == expected, "Repeated 10 damage leaves health %d" % expected):
			finish(false, "Defeat sequence")
			return
	var defeated_at := Time.get_ticks_msec()
	check(float(player(victim_id).get("respawn_in", 0.0)) > 0.0, "Defeated player has respawn countdown")
	issue("dead_input", formation({}, {"target": [8, 8], "jump": true, "punch": true}))
	var dead_position := position(victim_id)
	await create_timer(0.5).timeout
	check(health(victim_id) == 0 and position(victim_id).distance_to(dead_position) < 0.05, "Defeated player cannot move or fight")
	issue("wait_respawn", {})
	if not await until(func(): return health(victim_id) == 100, "Defeated player respawns at full health", 5.0):
		finish(false, "Respawn")
		return
	check(Time.get_ticks_msec() - defeated_at >= 2600, "Respawn respects the three-second delay")
	check(position(victim_id).distance_to(spawn_position(victim_id)) < 0.1, "Respawn restores player spawn")
	check(bool(player(victim_id).get("invulnerable", false)), "Respawn grants temporary protection")
	await until(func(): return not bool(player(victim_id).get("invulnerable", true)), "Respawn protection expires", 2.0)
	issue("stop_before_restart", {})
	net.send({"type": "restart"})
	await until(func(): return position(initial_host).distance_to(Vector2(-4, 0)) < 0.1 and health(victim_id) == 100, "Host restart resets position and health")
	issue("guest_tunes_rules", {"guest2": {"god_options": {"god_mode": true, "attack_damage": 25, "attack_speed": 8, "move_speed": 7, "max_jumps": 3, "jump_height": 3, "jump_speed": 1.5}}})
	await until(func(): return bool(net.room.get("god_options", {}).get("god_mode", false)) and float(net.room.god_options.get("attack_damage", 0)) == 25, "Guest can enable shared god mode and tune the room")
	issue("god_formation", formation())
	await until(formation_ready, "All four position under shared move-speed rule", 12.0)
	await create_timer(0.3).timeout
	issue("god_punch", formation({"punch": true}))
	await create_timer(0.5).timeout
	check(health(victim_id) == 100, "God mode prevents damage to the defender")
	issue("guest_disables_god", {"guest3": {"god_options": {"god_mode": false}}})
	await until(func(): return not bool(net.room.get("god_options", {}).get("god_mode", true)), "Another guest can turn shared god mode off")
	issue("tuned_damage", formation({"punch": true}))
	await until(func(): return health(victim_id) == 75, "Tuned attack damage is applied by the server")
	await create_timer(0.2).timeout
	issue("tuned_attack_speed", formation({"punch": true}))
	await until(func(): return health(victim_id) == 50, "Tuned attack speed permits the next attack before the original cooldown")
	issue("guest_resets_rules", {"guest1": {"reset_god_options": true}})
	await until(func(): return float(net.room.get("god_options", {}).get("attack_damage", 0)) == 10 and float(net.room.god_options.get("move_speed", 0)) == 5.5 and int(net.room.god_options.get("max_jumps", 0)) == 1, "Guest can restore default gameplay rules")
	net.send({"type": "lobby"})
	await until(func(): return net.room.get("phase") == "lobby" and app.page == "lobby", "Return to lobby updates real UI")
	issue("choose_teams", {"host": {"party": 0}, "guest1": {"party": 0}, "guest2": {"party": 1}, "guest3": {"party": 1}})
	await until(teams_balanced, "Players select exactly two Red and two Blue players")
	net.set_mode("teams")
	await until(func(): return net.room.get("mode") == "teams", "2v2 mode reaches the lobby")
	issue("teams_ready", {"guest1": {"ready": true}, "guest2": {"ready": true}, "guest3": {"ready": true}})
	await until(everyone_ready, "Balanced teams ready for 2v2")
	net.send({"type": "start"})
	await until(func(): return net.room.get("phase") == "playing" and app.page == "game", "2v2 round starts")
	issue("team_positions", formation())
	await until(formation_ready, "Teammates approach each other", 12.0)
	await create_timer(0.3).timeout
	issue("friendly_punch", formation({"punch": true}))
	await create_timer(0.65).timeout
	check(health(victim_id) == 100, "A forward punch cannot damage a teammate in 2v2")
	var enemy_id := id_for_name("guest2")
	var enemies := formation()
	enemies.guest1.target = [-5, -5]
	enemies.guest2.target = [0.7, 0]
	issue("enemy_positions", enemies)
	await until(func(): return position(enemy_id).distance_to(Vector2(0.7, 0)) < 0.16 and position(victim_id).distance_to(Vector2(-5, -5)) < 0.16, "Opposing team member enters punch range", 12.0)
	await create_timer(0.3).timeout
	enemies.host.punch = true
	issue("enemy_punch", enemies)
	await until(func(): return health(enemy_id) == 90, "Forward punch damages the opposing team")
	await capture("teams.png")
	issue("active_unbalance_rejected", {"guest1": {"party": 1, "expect_error": "balanced"}})
	await create_timer(0.4).timeout
	check(teams_balanced(), "Running 2v2 refuses a team change that would make the roster uneven")
	issue("guest_switches_live_ffa", {"guest2": {"mode": "ffa"}})
	await until(func(): return net.room.get("mode") == "ffa" and net.room.get("phase") == "playing", "Guest switches the running arena to free-for-all")
	issue("live_ffa_positions", formation())
	await until(formation_ready, "Former teammates approach during the live free-for-all switch", 12.0)
	await create_timer(0.3).timeout
	issue("live_ffa_hit", formation({"punch": true}))
	await until(func(): return health(victim_id) == 90, "Live free-for-all immediately permits former teammates to damage each other")
	issue("guest_restores_live_teams", {"guest3": {"mode": "teams"}})
	await until(func(): return net.room.get("mode") == "teams" and net.room.get("phase") == "playing", "Another guest restores balanced 2v2 without leaving the arena")
	await create_timer(0.65).timeout
	issue("live_teams_guard", formation({"punch": true}))
	await create_timer(0.65).timeout
	check(health(victim_id) == 90, "Switching back to 2v2 immediately restores teammate immunity")
	net.send({"type": "lobby"})
	await until(func(): return net.room.get("phase") == "lobby", "Second return to lobby")
	net.set_mode("ffa")
	await until(func(): return net.room.get("mode") == "ffa", "Free-for-all mode restores in lobby")
	issue("ffa_ready", {"guest1": {"ready": true}, "guest2": {"ready": true}, "guest3": {"ready": true}})
	await until(everyone_ready, "Players ready for free-for-all")
	net.send({"type": "start"})
	await until(func(): return net.room.get("phase") == "playing", "Third round starts in free-for-all")
	issue("ffa_positions", formation())
	await until(formation_ready, "Former teammates approach in free-for-all", 12.0)
	await create_timer(0.3).timeout
	issue("ffa_punch", formation({"punch": true}))
	await until(func(): return health(victim_id) == 90, "Free-for-all allows damage between former teammates")
	net.send({"type": "lobby"})
	await until(func(): return net.room.get("phase") == "lobby", "Third return to lobby")
	await create_timer(0.4).timeout
	var passed := common_evidence()
	net.leave()
	issue("finish", {})
	finish(passed, "four present / leave-rejoin / movement-yaw-jump / 10-20 damage / frontal-rear block / defeat-respawn / restart-lobby")

func formation(host_extra: Dictionary = {}, victim_extra: Dictionary = {}) -> Dictionary:
	var attacker := {"target": [-0.7, 0], "yaw": -PI / 2.0}
	var defender := {"target": [0.7, 0], "yaw": PI / 2.0}
	attacker.merge(host_extra, true)
	defender.merge(victim_extra, true)
	return {"host": attacker, "guest1": defender, "guest2": {"target": [-5, -5], "yaw": 0.3}, "guest3": {"target": [5, 5], "yaw": -0.3}}

func formation_ready() -> bool:
	for p: Dictionary in net.snapshot.get("players", []):
		var player_label: String = player_name(str(p.id))
		var key := "host" if str(p.id) == initial_host else player_label
		var goal: Array = formation().get(key, {}).get("target", [])
		if goal.is_empty() or Vector2(float(p.x), float(p.z)).distance_to(Vector2(float(goal[0]), float(goal[1]))) > 0.16:
			return false
	return net.snapshot.get("players", []).size() == 4

func issue(label: String, intents: Dictionary) -> void:
	serial += 1
	var file := FileAccess.open(command_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"serial": serial, "label": label, "players": intents}))
	file.close()
	print("STAGE: " + label)

func on_room(data: Dictionary) -> void:
	if finished or data.is_empty():
		return
	var phase := str(data.get("phase", ""))
	var rules: Dictionary = data.get("god_options", {})
	saw_god_mode = saw_god_mode or bool(rules.get("god_mode", false))
	saw_tuned_rules = saw_tuned_rules or (float(rules.get("attack_damage", 0)) == 25 and int(rules.get("max_jumps", 0)) == 3)
	saw_rules_reset = saw_rules_reset or (saw_tuned_rules and float(rules.get("attack_damage", 0)) == 10 and int(rules.get("max_jumps", 0)) == 1)
	saw_teams = saw_teams or (phase == "playing" and data.get("mode") == "teams")
	saw_ffa_after_teams = saw_ffa_after_teams or (saw_teams and phase == "playing" and data.get("mode") == "ffa")
	# Room broadcasts can contain an old not-ready value until our request is
	# acknowledged. Send once per lobby entry/connection, not once per broadcast.
	if phase != previous_phase or net.player_id != ready_connection:
		ready_sent = false
		previous_phase = phase
		ready_connection = net.player_id
	room_code = str(data.code)
	if initial_host.is_empty():
		initial_host = str(data.host_id)
		if role == "host":
			var file := FileAccess.open(coordination, FileAccess.WRITE)
			file.store_string(room_code)
			file.close()
	var players: Array = data.get("players", [])
	if players.size() == 4:
		observed_full = true
		if observed_departure:
			observed_return = true
	elif players.size() == 3 and observed_full:
		observed_departure = true
	if data.phase == "playing":
		saw_playing = true
	elif data.phase == "lobby":
		if saw_playing:
			saw_lobby_return = true
		for p: Dictionary in players:
			if str(p.id) == net.player_id and not bool(p.ready) and not ready_sent:
				ready_sent = true
				net.send({"type": "ready", "ready": true})
				break
	for p: Dictionary in players:
		if str(p.name) == "guest1":
			victim_id = str(p.id)

func on_state(data: Dictionary) -> void:
	if data.get("phase") != "playing":
		return
	for p: Dictionary in data.get("players", []):
		var id := str(p.id)
		var pos := Vector2(float(p.x), float(p.z))
		if not first_positions.has(id):
			first_positions[id] = pos
		elif pos.distance_to(first_positions[id]) > 1.0:
			moved_players[id] = true
		if id == initial_host:
			saw_jump = saw_jump or (not bool(p.grounded) and float(p.y) > 0.1)
			saw_yaw = saw_yaw or absf(wrapf(float(p.yaw) + PI / 2.0, -PI, PI)) < 0.05
		if id == victim_id:
			health_values[int(p.health)] = true
			saw_block = saw_block or bool(p.block)
			saw_defeat = saw_defeat or int(p.health) == 0
			saw_respawn = saw_respawn or (saw_defeat and int(p.health) == 100 and bool(p.invulnerable))

func on_combat(data: Dictionary) -> void:
	if str(data.get("target", "")) != victim_id:
		return
	saw_block_event = saw_block_event or data.get("kind") == "blocked"
	if data.get("kind") == "hit":
		saw_normal_hit_event = saw_normal_hit_event or (int(data.get("damage", 0)) == 10 and not bool(data.get("critical", false)))
		saw_critical_hit_event = saw_critical_hit_event or (int(data.get("damage", 0)) == 20 and bool(data.get("critical", false)))

func common_evidence() -> bool:
	check(observed_full and observed_departure and observed_return, "Observed four-player presence and leave/rejoin")
	check(moved_players.size() == 4 and saw_yaw and saw_jump, "Observed all four move and host rotate/jump")
	check(health_values.has(90) and health_values.has(70) and health_values.has(60), "Observed matching 10/20/rear-hit health snapshots")
	check(saw_block and saw_defeat and saw_respawn, "Observed block, defeat and protected respawn")
	check(saw_block_event and saw_normal_hit_event and saw_critical_hit_event, "Observed server block, normal-hit and critical feedback")
	check(saw_lobby_return, "Observed shared return to lobby")
	check(saw_god_mode and saw_tuned_rules and saw_rules_reset, "Observed guest changes to shared god mode, tuning and defaults")
	check(saw_teams and saw_ffa_after_teams, "Observed 2v2 and subsequent free-for-all rounds")
	check(expected_error.is_empty(), "Expected invalid team-change response arrived")
	return failures == 0

func id_for_name(label: String) -> String:
	for p: Dictionary in net.room.get("players", []):
		if str(p.name) == label:
			return str(p.id)
	return ""

func teams_balanced() -> bool:
	var reds: int = 0
	var blues: int = 0
	for p: Dictionary in net.room.get("players", []):
		if int(p.get("party", -1)) == 0:
			reds += 1
		elif int(p.get("party", -1)) == 1:
			blues += 1
	return reds == 2 and blues == 2 and int(player_party(initial_host)) == int(player_party(victim_id))

func player_party(id: String) -> int:
	for p: Dictionary in net.room.get("players", []):
		if str(p.id) == id:
			return int(p.get("party", -1))
	return -1

func player(id: String) -> Dictionary:
	for p: Dictionary in net.snapshot.get("players", []):
		if str(p.id) == id:
			return p
	return {}

func player_name(id: String) -> String:
	for p: Dictionary in net.room.get("players", []):
		if str(p.id) == id:
			return str(p.name)
	return ""

func position(id: String) -> Vector2:
	var p := player(id)
	return Vector2(float(p.get("x", -999)), float(p.get("z", -999)))

func health(id: String) -> int:
	return int(player(id).get("health", -1))

func spawn_position(id: String) -> Vector2:
	var spawns: Array[Vector2] = [Vector2(-4, 0), Vector2(4, 0), Vector2(0, -5), Vector2(0, 5)]
	for p: Dictionary in net.room.get("players", []):
		if str(p.id) == id:
			return spawns[int(p.slot)]
	return Vector2(-999, -999)

func everyone_ready() -> bool:
	if net.room.get("players", []).is_empty():
		return false
	for p: Dictionary in net.room.players:
		if not bool(p.ready):
			return false
	return true

func until(condition: Callable, description: String, timeout: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline and not finished:
		await create_timer(0.03).timeout
	return check(bool(condition.call()), description)

func check(condition: bool, description: String) -> bool:
	print("%s %s: %s" % ["PASS" if condition else "FAIL", role, description])
	if not condition:
		failures += 1
	return condition

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(coordination.get_base_dir().path_join(filename))

func finish(passed: bool, detail: String) -> void:
	if finished:
		return
	finished = true
	var ok := passed and failures == 0
	print("LOBBY_TEST %s %s: %s (failures=%d)" % [role, "PASS" if ok else "FAIL", detail, failures])
	if net != null:
		net.leave()
	root.get_node("Sound").shutdown()
	await create_timer(0.2).timeout
	quit(0 if ok else 1)
