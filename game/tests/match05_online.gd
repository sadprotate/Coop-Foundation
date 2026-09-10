extends SceneTree

## Four actual Main/Net clients. Coordination requests only ordinary UI/network
## actions; the server alone supplies positions, health, clocks and match scores.
var role := "host"
var address := "ws://127.0.0.1:18805/ws"
var directory := ""
var expected_root := ""
var app: Control
var net: Node
var failures: int = 0
var checks: int = 0
var finished := false
var started_at: int = 0
var serial: int = 0
var applied_serial: int = -1
var command: Dictionary = {}
var expected_error := ""
var rejected_starts: int = 0
var initial_host := ""
var saw_town := false
var saw_timeout := false
var saw_teams := false
var saw_ffa_victory := false
var saw_return := false
var saw_new_host_button := false
var ended_rounds: Dictionary = {}
var previous_phase := ""
var victory_names: Array = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--server="):
			address = argument.trim_prefix("--server=")
		elif argument.begins_with("--directory="):
			directory = argument.trim_prefix("--directory=")
		elif argument.begins_with("--expected-user-root="):
			expected_root = argument.trim_prefix("--expected-user-root=").replace("\\", "/").to_lower()
	call_deferred("run")


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
	print("MATCH05 %s %s: %s" % [role, "PASS" if ok else "FAIL", label])
	return ok


func until(predicate: Callable, label: String, seconds: float = 8.0) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end and not finished:
		if predicate.call():
			return check(true, label)
		await create_timer(0.035).timeout
	return check(false, "Timed out: " + label)


func read_json(filename: String) -> Dictionary:
	var path: String = directory.path_join(filename)
	if not FileAccess.file_exists(path):
		return {}
	var decoder := JSON.new()
	if decoder.parse(FileAccess.get_file_as_string(path)) != OK or not decoder.data is Dictionary:
		return {}
	return decoder.data


func write_json(filename: String, data: Dictionary) -> void:
	var file := FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()


func issue(label: String, players: Dictionary = {}) -> void:
	serial += 1
	write_json("command.json", {"serial": serial, "label": label, "players": players})
	print("MATCH05 STAGE: " + label)


func status(who: String) -> Dictionary:
	return read_json(who + "-status.json")


func all_status(predicate: Callable) -> bool:
	for who: String in ["host", "guest1", "guest2", "guest3"]:
		var data: Dictionary = status(who)
		if data.is_empty() or not predicate.call(data):
			return false
	return true


func player(who: String) -> Dictionary:
	var wanted: String = str(status(who).get("id", ""))
	for item: Dictionary in net.snapshot.get("players", []):
		if item.get("id") == wanted:
			return item
	return {}


func positioned(who: String, target: Vector2, tolerance: float = 0.3) -> bool:
	var p: Dictionary = player(who)
	return not p.is_empty() and Vector2(float(p.x), float(p.z)).distance_to(target) <= tolerance


func match_state() -> Dictionary:
	return net.room.get("match", {})


func run() -> void:
	if expected_root.is_empty() or not OS.get_user_data_dir().replace("\\", "/").to_lower().begins_with(expected_root + "/"):
		push_error("Match test requires an isolated workspace profile.")
		quit(1)
		return
	started_at = Time.get_ticks_msec()
	net = root.get_node("Net")
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	app.set_process(false)
	net.failure.connect(func(message: String):
		if not expected_error.is_empty() and message.to_lower().contains(expected_error):
			rejected_starts += 1
			expected_error = ""
			check(true, "Server rejects unauthorized guest start")
		else:
			check(false, "Unexpected network error: " + message)
	)
	net.state_changed.connect(observe)
	worker()
	if role == "host":
		net.connect_room(address, {"type": "create", "name": role, "mode": "ffa"})
		if not await until(func(): return not net.room.is_empty(), "Host creates room"):
			finish()
			return
		initial_host = net.player_id
		write_json("room.json", {"code": net.room.code, "host": initial_host})
		await host_sequence()
	else:
		if not await until(func(): return not read_json("room.json").is_empty(), "Host room available", 15.0):
			finish()
			return
		var room_data: Dictionary = read_json("room.json")
		initial_host = str(room_data.host)
		net.connect_room(address, {"type": "join", "name": role, "code": room_data.code})


func observe(data: Dictionary) -> void:
	var phase: String = str(data.get("match", {}).get("phase", "town"))
	if data.get("zone") == "town" and bool(data.get("safe_zone", false)):
		saw_town = true
		if previous_phase == "ready_check" and phase == "town":
			saw_timeout = true
		if saw_ffa_victory and data.get("match", {}).get("round_scores", {}).is_empty() and data.get("match", {}).get("round_wins", {}).is_empty() and int(data.get("match", {}).get("round_number", -1)) == 0:
			saw_return = true
	if data.get("mode") == "teams" and phase in ["round", "round_end", "victory"]:
		saw_teams = true
	if data.get("mode") == "ffa" and phase in ["round_end", "victory"]:
		var result: Dictionary = data.get("match", {})
		ended_rounds[str(int(result.get("round_number", 0)))] = true
		if phase == "victory":
			saw_ffa_victory = true
			victory_names = result.get("winner_names", []).duplicate()
	previous_phase = phase


func worker() -> void:
	while not finished:
		await create_timer(0.055).timeout
		if finished:
			return
		if Time.get_ticks_msec() - started_at > 185000:
			check(false, "Watchdog: " + str(command.get("label", "join")))
			finish()
			return
		var next: Dictionary = read_json("command.json")
		if not next.is_empty():
			command = next
		var intent: Dictionary = command.get("players", {}).get(role, {})
		var is_new: bool = int(command.get("serial", -1)) != applied_serial
		if is_new:
			applied_serial = int(command.get("serial", -1))
			if intent.has("expect_error"):
				expected_error = str(intent.expect_error)
			if intent.has("options"):
				net.set_god_options(intent.options)
			if intent.has("mode"):
				net.set_mode(str(intent.mode))
			if intent.has("party"):
				net.set_party(int(intent.party))
			if intent.has("send"):
				net.send(intent.send)
			if bool(intent.get("npc", false)):
				if app.page == "options":
					app._back_from_options()
				app.session_ui.talk()
				check(app.session_ui.dialog_kind == "npc", "Old Man dialogue opens through normal interaction range")
				if bool(intent.get("start", false)):
					var start: Button = app.session_ui.find_child("StartBattle", true, false)
					if check(start != null, "Host sees START BATTLE in Old Man dialogue"):
						start.pressed.emit()
			if bool(intent.get("ready", false)):
				var ready: Button = app.session_ui.find_child("ConfirmReady", true, false)
				if check(ready != null, "Visible READY button is available"):
					ready.pressed.emit()
			if bool(intent.get("close_npc", false)):
				app.session_ui.close_dialog()
			if bool(intent.get("leave", false)):
				net.leave()
		if net.can_control():
			net.move_axis = Vector2.ZERO
			net.blocking = false
			net.sprinting = false
			net.crouching = false
			if intent.has("yaw"):
				net.facing_yaw = float(intent.yaw)
			if intent.has("target"):
				var p: Dictionary = net.local_player()
				if not p.is_empty():
					var difference := Vector2(float(intent.target[0]) - float(p.x), float(intent.target[1]) - float(p.z))
					if difference.length() > 0.08:
						net.move_axis = difference.limit_length(1.0)
			net.flush_input()
			if is_instance_valid(app.arena):
				app.arena.set_local_input(net.move_axis, false)
			if is_new and bool(intent.get("punch", false)):
				net.punch()
		if is_instance_valid(app.session_ui) and app.session_ui.dialog_kind == "npc" and net.room.get("host_id") == net.player_id and net.player_id != initial_host:
			saw_new_host_button = app.session_ui.find_child("StartBattle", true, false) != null
		write_json(role + "-status.json", {"near_elder": net.near_old_man(), "dialog": app.session_ui.dialog_kind if is_instance_valid(app.session_ui) else "", "id": net.player_id, "serial": applied_serial, "phase": net.room.get("phase", ""), "zone": net.room.get("zone", ""), "host": net.room.get("host_id", ""), "match_phase": match_state().get("phase", ""), "round": match_state().get("round_number", 0), "rules": net.god_options(), "safe": bool(net.snapshot.get("safe_zone", false)), "town": saw_town, "timeout": saw_timeout, "teams": saw_teams, "ended_rounds": ended_rounds.keys(), "victory": saw_ffa_victory, "winner_names": victory_names, "returned": saw_return, "rejected": rejected_starts, "promoted_button": saw_new_host_button, "failures": failures})
		if command.get("label") == "finish" and role != "host":
			check(saw_town and saw_timeout and saw_teams and ended_rounds.size() == 10 and saw_ffa_victory and saw_return and victory_names == ["host"], "This client observed town, timeout, teams, all ten FFA round results, shared winner and safe return")
			finish()


func host_sequence() -> void:
	if not await until(func(): return net.room.get("players", []).size() == 4 and all_status(func(s: Dictionary): return bool(s.get("town", false))), "All four real clients spawn in the safe Town Lobby", 18.0):
		finish()
		return
	await capture("01-town.png")
	await until(func(): return net.snapshot.players.all(func(p: Dictionary): return p.get("ping_ms") != null), "Server ping is synchronized for all four real Godot clients")
	await test_scoreboard("08-town-scoreboard.png")
	issue("host options", {"host": {"options": {"attack_damage": 100, "attack_range": 5, "attack_speed": 10, "knockback_strength": 0, "respawn_seconds": 0.5, "move_speed": 10, "knockouts_to_win": 1, "total_rounds": 1, "round_duration": 10, "ready_check_seconds": 3, "god_mode": false}}})
	if not await until(func(): return all_status(func(s: Dictionary): return int(s.get("rules", {}).get("attack_damage", 0)) == 100), "Host rules replicate to every client"):
		finish()
		return
	issue("walk to elder", {"host": {"target": [0, -3]}, "guest1": {"target": [1.5, -3]}})
	if not await until(func(): return net.near_old_man() and positioned("guest1", Vector2(1.5, -3)), "Host and guest reach the elder using actual movement"):
		finish()
		return
	issue("town safe punch", {"host": {"yaw": -PI / 2, "punch": true}, "guest1": {"expect_error": "only the room host", "send": {"type": "start"}}})
	await until(func(): return int(status("guest1").get("rejected", 0)) == 1, "Guest cannot start a battle")
	await create_timer(0.25).timeout
	check(float(player("guest1").get("health", 0)) == 100.0 and net.in_town(), "A lethal configured punch cannot damage a player in town")
	issue("first ready check", {"host": {"npc": true, "start": true}})
	if not await until(func(): return all_status(func(s: Dictionary): return s.get("phase") == "ready_check"), "Every client receives Ready without leaving town"):
		finish()
		return
	await capture("02-ready-check.png")
	issue("withhold one ready", {"host": {"ready": true}, "guest1": {"ready": true}, "guest2": {"ready": true}})
	await create_timer(0.5).timeout
	check(all_status(func(s: Dictionary): return s.get("zone") == "town" and s.get("phase") == "ready_check"), "Three Ready confirmations never teleport the withheld fourth player")
	if not await until(func(): return all_status(func(s: Dictionary): return bool(s.get("timeout", false)) and s.get("phase") == "lobby"), "Withheld readiness expires and restores town for everyone", 6.0):
		finish()
		return
	issue("prepare two teams", {"host": {"party": 0, "mode": "teams"}, "guest1": {"party": 1}, "guest2": {"party": 0}, "guest3": {"party": 1}})
	await until(func(): return net.room.get("mode") == "teams" and net.room.get("players", []).all(func(p: Dictionary): return int(p.party) == (0 if p.name in ["host", "guest2"] else 1)), "Four players choose balanced Red and Blue teams")
	if not await start_ready("team battle"):
		finish()
		return
	issue("team positioning", {"host": {"target": [0, 0], "yaw": 0}, "guest2": {"target": [0, -2]}, "guest1": {"target": [7, 0]}, "guest3": {"target": [8, 8]}})
	if not await until(func(): return positioned("host", Vector2.ZERO) and positioned("guest2", Vector2(0, -2)) and positioned("guest1", Vector2(7, 0)) and positioned("guest3", Vector2(8, 8)), "Team players reach friendly-fire test positions"):
		finish()
		return
	issue("team friendly punch", {"host": {"yaw": 0, "punch": true}})
	await create_timer(0.25).timeout
	check(float(player("guest2").get("health", 0)) == 100.0 and int(match_state().get("round_scores", {}).get("red", -1)) == 0, "A teammate directly in front takes no damage and awards no knockout")
	issue("team enemy approach", {"host": {"target": [4.5, 0], "yaw": -PI / 2}})
	await until(func(): return positioned("host", Vector2(4.5, 0)), "Host approaches the opposing team")
	await capture("03-team-arena.png")
	issue("team enemy knockout", {"host": {"yaw": -PI / 2, "punch": true}})
	if not await until(func(): return match_state().get("phase") in ["round_end", "victory"] and int(match_state().get("round_wins", {}).get("red", 0)) == 1, "Enemy knockout awards the Red Team its round"):
		finish()
		return
	if not await until(func(): return all_status(func(s: Dictionary): return s.get("phase") == "lobby" and bool(s.get("teams", false))), "Team battle completes and returns every player to town", 12.0):
		finish()
		return
	issue("prepare ten FFA rounds", {"host": {"mode": "ffa", "options": {"total_rounds": 10}, "target": [0, -3]}})
	if not await until(func(): return net.near_old_man() and all_status(func(s: Dictionary): return int(s.get("rules", {}).get("total_rounds", 0)) == 10), "Host configures ten rounds and walks back to the Old Man"):
		finish()
		return
	if not await start_ready("ten-round FFA"):
		finish()
		return
	for round_number: int in range(1, 11):
		if not await until(func(): return match_state().get("phase") == "round" and int(match_state().get("round_number", 0)) == round_number, "FFA round %d begins with reset players" % round_number, 10.0):
			finish()
			return
		check(int(match_state().get("round_scores", {}).get(initial_host, -1)) == 0 and float(net.local_player().health) == 100.0, "Round %d begins with zero knockouts and full health" % round_number)
		if round_number == 2:
			await test_scoreboard("09-arena-scoreboard.png")
			check(app.scoreboard.rows[0].id == initial_host and int(app.scoreboard.rows[0].wins) == 1, "Arena scoreboard ranks the real round winner first")
		issue("FFA positioning %d" % round_number, {"host": {"target": [1.5, 0], "yaw": -PI / 2}, "guest1": {"target": [4, 0]}, "guest2": {"target": [-8, -8]}, "guest3": {"target": [8, 8]}})
		if not await until(func(): return positioned("host", Vector2(1.5, 0)) and positioned("guest1", Vector2(4, 0)) and positioned("guest2", Vector2(-8, -8)) and positioned("guest3", Vector2(8, 8)), "Round %d combatants approach through ordinary movement" % round_number, 6.0):
			finish()
			return
		if round_number == 1:
			await capture("04-ffa-arena.png")
		issue("FFA knockout %d" % round_number, {"host": {"yaw": -PI / 2, "punch": true}})
		if not await until(func(): return match_state().get("phase") in ["round_end", "victory"] and int(match_state().get("round_wins", {}).get(initial_host, 0)) == round_number, "Round %d knockout records the host's round win" % round_number):
			finish()
			return
		if round_number == 1:
			await capture("05-round-complete.png")
		if not await until(func(): return all_status(func(s: Dictionary): return str(round_number) in s.get("ended_rounds", [])), "All clients receive round %d result" % round_number, 2.0):
			finish()
			return
	if not await until(func(): return all_status(func(s: Dictionary): return bool(s.get("victory", false)) and s.get("winner_names", []) == ["host"]), "Every client agrees on the ten-round match winner"):
		finish()
		return
	await capture("06-victory.png")
	if not await until(func(): return all_status(func(s: Dictionary): return bool(s.get("returned", false)) and bool(s.get("safe", false)) and s.get("phase") == "lobby"), "Victory returns all players to safe town and clears match scores", 12.0):
		finish()
		return
	await capture("07-return-town.png")
	issue("second battle approach", {"host": {"target": [0, -3]}})
	await until(func(): return net.near_old_man(), "Host can approach the elder for another battle")
	issue("second battle ready", {"host": {"npc": true, "start": true}})
	await until(func(): return all_status(func(s: Dictionary): return s.get("phase") == "ready_check"), "A fresh ready check can begin after a completed match")
	issue("cancel second battle", {"host": {"send": {"type": "cancel_start"}}})
	await until(func(): return all_status(func(s: Dictionary): return s.get("phase") == "lobby"), "Cancelling the next battle leaves everyone safely in town")
	var next_host_role: String = str(net.room.players[1].name)
	issue("guest waits at elder", {next_host_role: {"target": [0, -3]}})
	await until(func(): return positioned(next_host_role, Vector2(0, -3)), "Future host reaches the elder")
	issue("guest opens elder before transfer", {next_host_role: {"npc": true}})
	await until(func(): return int(status(next_host_role).get("serial", -1)) == serial, "Guest opens the NPC dialogue before host transfer")
	issue("host leaves", {"host": {"leave": true}})
	await until(func(): return status(next_host_role).get("host") == status(next_host_role).get("id") and status(next_host_role).get("dialog") == "" and not bool(status(next_host_role).get("near_elder", true)), "Host transfer closes the stale NPC dialog after the Town spawn reset")
	issue("new host approaches elder", {next_host_role: {"target": [0, -3]}})
	await until(func(): return bool(status(next_host_role).get("near_elder", false)), "New host can approach the Old Man after transfer")
	issue("new host opens elder", {next_host_role: {"npc": true}})
	await until(func(): return bool(status(next_host_role).get("promoted_button", false)), "New host receives START BATTLE through the Old Man")
	issue("finish")
	await create_timer(0.35).timeout
	finish()


func test_scoreboard(filename: String) -> void:
	var pointer_before: int = Input.mouse_mode
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.pressed = true
	app._input(event)
	await process_frame
	check(app.scoreboard.visible and app.scoreboard.rows.size() == net.room.players.size(), "Holding Tab shows every connected player")
	check(app.scoreboard.rows.all(func(row: Dictionary): return row.ping != null), "Scoreboard uses server-measured ping for each player")
	check(app.scoreboard.rows.filter(func(row: Dictionary): return row.local).size() == 1, "Scoreboard identifies exactly the local player")
	await capture(filename)
	event.pressed = false
	app._input(event)
	check(not app.scoreboard.visible and Input.mouse_mode == pointer_before, "Releasing Tab hides scoreboard without releasing or changing the pointer")

func start_ready(label: String) -> bool:
	issue(label + " ready check", {"host": {"npc": true, "start": true}})
	if not await until(func(): return all_status(func(s: Dictionary): return s.get("phase") == "ready_check"), label + " reaches every ready dialog"):
		return false
	issue(label + " confirm all", {"host": {"ready": true}, "guest1": {"ready": true}, "guest2": {"ready": true}, "guest3": {"ready": true}})
	return await until(func(): return all_status(func(s: Dictionary): return s.get("zone") == "arena" and s.get("match_phase") == "round"), label + " teleports only after all four confirmations")


func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(filename)) == OK, "Captured " + filename)


func finish() -> void:
	if finished:
		return
	finished = true
	print("MATCH05 RESULT %s: %d checks, %d failures" % [role, checks, failures])
	if is_instance_valid(net):
		net.leave()
	if is_instance_valid(app):
		app.queue_free()
	root.get_node("Sound").shutdown()
	await create_timer(0.2).timeout
	quit(0 if failures == 0 else 1)
