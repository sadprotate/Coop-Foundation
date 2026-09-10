extends SceneTree

## Accelerates simulation time, not game rules: exercises the full default ten-round match.
var _net: Node
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)

func _advance(seconds: float) -> void:
	var steps: int = roundi(seconds / 0.05)
	for i: int in range(steps):
		_net._step_practice(0.05)

func _start_battle() -> void:
	var player: Dictionary = _net.local_player()
	player.x = 0.0
	player.y = 0.0
	player.z = -3.0
	_net.send({"type": "start"})
	_net.send({"type": "ready", "ready": true})

func _run() -> void:
	await create_timer(0.1).timeout
	# This long synchronous simulation does not exercise audio. Let its queued
	# startup/shutdown finish before accelerating 25 minutes of match time.
	root.get_node("Sound").shutdown()
	await create_timer(0.15).timeout
	_net = root.get_node("Net")
	_net.set_process(false)
	_net.start_practice()
	_start_battle()
	_check(_net.god_options().round_duration == 150 and _net.god_options().total_rounds == 10 and _net.god_options().knockouts_to_win == 4, "Defaults remain ten rounds, 150 seconds each, and four knockouts")
	var previous_round_id: int = int(_net.room.round_id) - 1
	for round_number: int in range(1, 11):
		var state: Dictionary = _net.room["match"]
		var player: Dictionary = _net.local_player()
		_check(state.phase == "round" and int(state.round_number) == round_number and float(state.time_left) == 150.0, "Round %d starts with a fresh full timer" % round_number)
		_check(int(_net.room.round_id) > previous_round_id, "Round %d receives a new identity for network/prediction reset" % round_number)
		previous_round_id = int(_net.room.round_id)
		_check(float(player.health) == 100.0 and float(player.stamina) == 100.0 and float(player.x) == -4.0 and float(player.z) == 0.0, "Round %d resets health, stamina and spawn position" % round_number)
		_check(int(state.round_scores.local) == 0 and int(state.round_wins.local) == round_number - 1, "Round %d clears knockouts while retaining earned round wins" % round_number)
		_advance(149.95)
		_check(_net.room["match"].phase == "round" and absf(float(_net.snapshot["match"].time_left) - 0.05) < 0.001, "Round %d remains playable until its timer expires" % round_number)
		player.health = 35.0
		player.stamina = 7.0
		player.x = 7.0
		_net.move_axis = Vector2.RIGHT
		_net._step_practice(0.05)
		state = _net.room["match"]
		_check(state.phase == "round_end" and state.round_winner == _net.player_id and int(state.round_wins.local) == round_number, "Round %d records the sole participant as timeout winner" % round_number)
		_check(int(state.round_scores.local) == 0 and int(_net.snapshot["match"].score_entries[0].knockouts) == 0 and int(_net.snapshot["match"].score_entries[0].round_wins) == round_number, "Round %d publishes its win without inventing knockouts" % round_number)
		_check(not _net.can_control() and not _net.jump() and not _net.punch(), "Round %d break disables movement and combat" % round_number)
		_net.move_axis = Vector2.RIGHT
		_advance(2.95)
		_check(_net.room["match"].phase == "round_end" and float(player.x) == 7.0 and float(player.health) == 35.0 and float(player.stamina) == 7.0, "Round %d break lasts three seconds and freezes player simulation" % round_number)
		_net._step_practice(0.05)
	_check(_net.room["match"].phase == "victory" and _net.room.phase == "playing", "The tenth completed round leads to a victory screen in the arena")
	_check(_net.room["match"].winner_ids == [_net.player_id] and _net.room["match"].winner_names == [_net.room.players[0].name], "Victory identifies the winner by player ID and display name")
	_check(_net.room["match"].round_wins.local == 10 and _net.room["match"].round_number == 10, "Victory retains the full ten-round result")
	_check(not _net.can_control() and not _net.jump() and not _net.punch(), "Victory freezes player movement and combat")
	_advance(5.95)
	_check(_net.room["match"].phase == "victory" and not _net.in_town(), "Victory remains visible for its six-second display interval")
	_net._step_practice(0.05)
	_check(_net.in_town() and _net.can_control() and _net.snapshot.safe_zone and _net.room.phase == "lobby", "Victory automatically returns the player to the safe Town")
	_check(_net.room["match"].round_wins.is_empty() and _net.room["match"].round_scores.is_empty() and _net.room["match"].winner_ids.is_empty(), "Returning to Town clears match wins, knockouts and winner data")
	_check(float(_net.local_player().health) == 100.0 and float(_net.local_player().stamina) == 100.0 and float(_net.local_player().x) == -3.0 and float(_net.local_player().z) == 2.0, "Town return resets health, stamina and Town spawn position")
	_start_battle()
	_check(_net.room["match"].phase == "round" and _net.room["match"].round_number == 1 and _net.room["match"].round_wins.local == 0, "A second NPC ready check starts a completely fresh match")
	_advance(10.0)
	_net.set_god_options({"round_duration": 160})
	_check(absf(float(_net.snapshot["match"].time_left) - 150.0) < 0.001, "Increasing round duration preserves elapsed time")
	_net.set_god_options({"round_duration": 50, "total_rounds": 1, "knockouts_to_win": 1})
	_check(absf(float(_net.snapshot["match"].time_left) - 40.0) < 0.001 and _net.room["match"].total_rounds == 1, "Live match limits update remaining time and advertised round count")
	_net._step_practice(0.05)
	_check(_net.room["match"].phase == "round" and _net.room["match"].round_scores.local == 0, "Lowering the knockout goal does not invent a knockout for the solo player")
	_advance(39.95)
	_check(_net.room["match"].phase == "round_end", "Current round finishes before a reduced total-round limit ends the match")
	_advance(3.0)
	_check(_net.room["match"].phase == "victory" and _net.room["match"].round_number == 1, "Reduced total rounds applies at the next completed-round transition")
	_net.send({"type": "restart"})
	_check(_net.room["match"].phase == "round" and _net.room["match"].round_wins.local == 0 and _net.room["match"].time_left == 50.0, "Host restart during victory resets the match immediately")
	_net.send({"type": "lobby"})
	_check(_net.in_town() and _net.room["match"].round_wins.is_empty(), "Returning to Town during a match clears all progress")
	_net.leave()
	root.get_node("Sound").shutdown()
	await create_timer(0.15).timeout
	print("MATCH05 RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
