extends SceneTree

## Deterministic local Town / NPC / ready-check / arena transition gate.
var _net: Node
var _checks: int = 0
var _failures: int = 0
var _errors: Array[String] = []
var _events: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)

func _on_error(message: String) -> void:
	_errors.append(message)

func _on_event(event: Dictionary) -> void:
	_events.append(event)

func _steps(count: int, dt: float = 0.05) -> void:
	for i: int in range(count):
		_net._step_practice(dt)

func _at_old_man() -> Dictionary:
	var player: Dictionary = _net.local_player()
	player.x = 0.0
	player.z = -5.0
	player.y = 0.0
	player.grounded = true
	return player

func _land() -> void:
	for i: int in range(300):
		_net._step_practice(0.02)
		if bool(_net.local_player().grounded):
			return
	_check(false, "Fall completes within bounded simulation")

func _run() -> void:
	await create_timer(0.1).timeout
	_net = root.get_node("Net")
	_net.set_process(false)
	_net.failure.connect(_on_error)
	_net.combat_event.connect(_on_event)
	_net.start_practice()
	var p: Dictionary = _net.local_player()
	_check(_net.in_town() and _net.room.phase == "lobby", "Single player enters the Town first")
	_check(_net.room.safe_zone and _net.snapshot.safe_zone, "Room and snapshot both mark Town as a safe zone")
	_check(_net.room["match"].phase == "town" and _net.snapshot["match"].round_number == 0, "Initial Town match metadata is reset")
	_check(float(p.x) == -3.0 and float(p.z) == 2.0, "Player uses the Town spawn area")
	_check(_net.can_control(), "Town permits player movement")
	_net.move_axis = Vector2.RIGHT
	_steps(10)
	_check(float(p.x) > -1.0, "Existing movement works inside Town")
	_net.move_axis = Vector2.ZERO
	_check(not _net.near_old_man(), "Interaction prompt stays hidden outside NPC range")
	_net.send({"type": "start"})
	_check(_errors.size() == 1 and _net.room.phase == "lobby", "Starting battle outside NPC range is rejected")
	_net.set_god_options({"fall_damage": true, "fall_damage_threshold": 0, "fall_damage_multiplier": 100, "god_mode": false, "ready_check_seconds": 3, "starting_health": 40})
	p.y = 5.0
	p.fall_peak = 5.0
	p.grounded = false
	_land()
	_check(float(p.health) == 100.0 and float(p.respawn_in) == 0.0, "Town prevents lethal fall damage even when battle God mode is off")
	_check(not _events.any(func(event: Dictionary): return event.kind in ["hit", "defeat"]), "Town emits no damage or knockout events")
	_check(_net.god_options().god_mode == false, "Town safety does not overwrite the selected battle God mode")
	p = _at_old_man()
	p.y = 3.1
	_check(not _net.near_old_man(), "NPC interaction range includes height")
	p.y = 0.0
	p.x = 3.0
	_check(_net.near_old_man(), "Exact three-meter interaction boundary is usable")
	p = _at_old_man()
	_net.send({"type": "start"})
	_check(_net.room.phase == "ready_check" and _net.in_town(), "Start Battle opens a ready check without teleporting")
	_check(_net.room["match"].ready_time_left == 3.0 and not _net.room.players[0].ready, "Single player must explicitly confirm Ready with a visible countdown")
	_check(not _net.can_control() and not _net.jump() and not _net.punch(), "Ready check freezes movement and combat inputs")
	_net.move_axis = Vector2.RIGHT
	_steps(40)
	_check(float(p.x) == 0.0 and float(p.z) == -5.0, "Waiting for readiness does not move or teleport players")
	_check(absf(float(_net.snapshot["match"].ready_time_left) - 1.0) < 0.001, "Ready countdown is published in snapshots")
	_net.send({"type": "ready", "ready": false})
	_check(_net.room.phase == "ready_check", "Not-ready does not start the battle")
	_steps(20)
	_check(_net.room.phase == "lobby" and _net.can_control(), "Ready timeout cancels the start and restores Town control")
	_check(_net.room["match"].phase == "town" and _net.snapshot.safe_zone, "Timeout resets match metadata and preserves Town safety")
	p = _at_old_man()
	_net.send({"type": "start"})
	_steps(10)
	_net.set_god_options({"ready_check_seconds": 5})
	_check(absf(float(_net.snapshot["match"].ready_time_left) - 4.5) < 0.001, "Increasing the ready timer preserves time already elapsed")
	_net.set_god_options({"ready_check_seconds": 3})
	_check(absf(float(_net.snapshot["match"].ready_time_left) - 2.5) < 0.001, "Decreasing the ready timer preserves time already elapsed")
	_net.set_party(1)
	_check(int(_net.room.players[0].party) == 0, "Team changes are rejected during the ready check")
	_net.send({"type": "cancel_start"})
	_check(_net.room.phase == "lobby" and _net.in_town() and float(p.z) == -5.0, "Host can cancel a ready check without teleporting players")
	p = _at_old_man()
	var old_round: int = int(_net.room.round_id)
	_net.send({"type": "start"})
	_net.send({"type": "ready", "ready": true})
	p = _net.local_player()
	_check(_net.room.phase == "playing" and not _net.in_town() and _net.can_control(), "Ready confirmation transitions into the arena")
	_check(not _net.room.players[0].ready, "Consumed ready confirmation is cleared for the next battle")
	_check(not _net.snapshot.safe_zone and _net.snapshot.zone == "arena", "Arena restores normal damage rules")
	_check(float(p.x) == -4.0 and float(p.z) == 0.0, "Battle uses separate arena spawn points")
	_check(float(p.health) == 40.0 and float(p.stamina) == float(p.max_stamina), "Arena spawn resets health and stamina using configured rules")
	_check(int(_net.room.round_id) > old_round, "Arena transition creates a new authoritative round identity")
	_check(_net.room["match"].phase == "round" and _net.room["match"].round_number == 1 and _net.room["match"].time_left == 150.0, "Battle starts with first-round metadata and configured duration")
	_check(_net.snapshot["match"].round_scores.get("local") == 0 and _net.snapshot["match"].score_entries.size() == 1, "Battle publishes initialized score structures")
	_net.set_god_options({"fall_damage_multiplier": 10})
	p.y = 2.0
	p.fall_peak = 2.0
	p.grounded = false
	_land()
	_check(absf(float(p.health) - 20.0) < 0.001, "The same fall becomes damaging after leaving Town")
	_net.send({"type": "restart"})
	p = _net.local_player()
	_check(_net.room.phase == "playing" and float(p.health) == 40.0 and _net.room["match"].round_number == 1, "Arena restart begins a fresh first round with reset players")
	_net.send({"type": "lobby"})
	p = _net.local_player()
	_check(_net.in_town() and _net.snapshot.safe_zone and _net.can_control(), "Return to Town restores the safe lobby")
	_check(float(p.x) == -3.0 and float(p.z) == 2.0 and float(p.health) == 40.0, "Return to Town heals to configured starting health and uses the Town spawn")
	_check(_net.room["match"].round_number == 0 and _net.room["match"].round_scores.is_empty(), "Town clears previous match scores")
	_net.send({"type": "restart"})
	_check(_net.in_town() and _net.room.phase == "lobby", "Restart cannot bypass Town and the NPC ready flow")
	_net.send({"type": "ready", "ready": true})
	_check(_net.in_town() and _net.room.phase == "lobby", "Ready outside an active check cannot enter the arena")
	_net.failure.disconnect(_on_error)
	_net.combat_event.disconnect(_on_event)
	_net.leave()
	_check(not _net.in_town() and not _net.can_control() and not _net.near_old_man(), "Leaving clears world-control and interaction helpers")
	root.get_node("Sound").shutdown()
	await create_timer(0.15).timeout
	print("TOWN05 RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
