extends RefCounted

## Local practice uses the same Town -> ready check -> arena contract as the server.
## It owns match flow only; Network retains the established player simulation.

func initialize(net: Node) -> void:
	_enter_town(net)

func _empty_match(rules: Dictionary) -> Dictionary:
	return {"phase": "town", "round_number": 0, "total_rounds": int(rules.total_rounds),
		"time_left": 0.0, "ready_time_left": 0.0, "transition_time_left": 0.0,
		"round_scores": {}, "round_wins": {}, "round_winner": "",
		"winner_ids": [], "winner_names": [], "score_entries": [],
		"objective": {"enabled": bool(rules.get("sword_objective_enabled", true)), "crystal_health": float(rules.get("crystal_max_health", 100)), "crystal_max_health": float(rules.get("crystal_max_health", 100)), "break_stage": 0, "sword_accessible": false, "sword_owner": "", "sword_dropped": false, "sword_x": 0.0, "sword_z": 0.0}}

func _sync(net: Node, publish_room: bool = true, publish_state: bool = true) -> void:
	net.room["match"].score_entries = [{"id": net.player_id, "name": str(net.room.players[0].name),
		"party": int(net.room.players[0].party), "knockouts": int(net.room["match"].round_scores.get(net.player_id, 0)),
		"round_wins": int(net.room["match"].round_wins.get(net.player_id, 0))}]
	for key: String in ["phase", "zone", "safe_zone", "round_id"]:
		net.snapshot[key] = net.room.get(key)
	net.snapshot["match"] = net.room["match"].duplicate(true)
	if publish_room:
		net.room_changed.emit(net.room)
	if publish_state:
		net.state_changed.emit(net.snapshot)

func _enter_town(net: Node) -> void:
	net.room["match"] = _empty_match(net.god_options())
	net.room["round_id"] = int(net.room.get("round_id", 0)) + 1
	for player: Dictionary in net.room.players:
		player.ready = false
	net._reset_practice("town")
	_sync(net)

func _cancel_ready(net: Node, message: String = "Battle cancelled. Everyone must be ready before the countdown ends.") -> void:
	net.room.phase = "lobby"
	net.room["match"] = _empty_match(net.god_options())
	for player: Dictionary in net.room.players:
		player.ready = false
	_sync(net)
	net.status_changed.emit(message)
	net.notice.emit(message)

func _begin_battle(net: Node) -> void:
	var rules: Dictionary = net.god_options()
	var state: Dictionary = _empty_match(rules)
	state.phase = "round"
	state.countdown_time_left = float(rules.get("arena_start_countdown", 10))
	state.fight_time_left = 0.0
	if state.countdown_time_left <= 0.0:
		state.phase = "round"
	state.round_number = 1
	state.time_left = float(rules.round_duration)
	state.round_scores[net.player_id] = 0
	state.round_wins[net.player_id] = 0
	state.score_entries = [{"id": net.player_id, "name": str(net.room.players[0].name),
		"party": int(net.room.players[0].party), "knockouts": 0, "round_wins": 0}]
	net.room["match"] = state
	for player: Dictionary in net.room.players:
		player.ready = false
	net.room["round_id"] = int(net.room.get("round_id", 0)) + 1
	net._reset_practice("arena")
	_sync(net)

func _freeze_player(net: Node) -> void:
	net.move_axis = Vector2.ZERO
	net.blocking = false
	net.sprinting = false
	net.crouching = false
	var player: Dictionary = net.local_player()
	player.block = false
	player.sprinting = false
	player.punch_t = 0.0

func _end_round(net: Node) -> void:
	# Practice has one participant. Winning on time does not invent any knockouts.
	var state: Dictionary = net.room["match"]
	state.round_winner = net.player_id
	state.round_wins[net.player_id] = int(state.round_wins.get(net.player_id, 0)) + 1
	state.phase = "round_end"
	state.time_left = 0.0
	state.transition_time_left = 3.0
	_freeze_player(net)
	_sync(net)

func _next_round(net: Node) -> void:
	var state: Dictionary = net.room["match"]
	state.phase = "round"
	state.round_number = int(state.round_number) + 1
	state.round_scores = {net.player_id: 0}
	state.round_winner = ""
	state.time_left = float(net.god_options().round_duration)
	state.transition_time_left = 0.0
	state.objective = _empty_match(net.god_options()).objective
	net.room["round_id"] = int(net.room.get("round_id", 0)) + 1
	net._reset_practice("arena")
	_sync(net)

func _begin_victory(net: Node) -> void:
	var state: Dictionary = net.room["match"]
	state.phase = "victory"
	state.transition_time_left = 6.0
	state.winner_ids = [net.player_id]
	state.winner_names = [str(net.room.players[0].name)]
	_freeze_player(net)
	_sync(net)

func handle_command(net: Node, data: Dictionary) -> bool:
	var command: String = str(data.get("type", ""))
	if command == "start":
		if net.room.get("phase") != "lobby":
			net.failure.emit("Talk to the Old Man in town to start a battle.")
		elif not net.near_old_man():
			net.failure.emit("Move closer to the Old Man to start a battle.")
		else:
			for player: Dictionary in net.room.players:
				player.ready = false
			net.room.phase = "ready_check"
			net.room["match"] = _empty_match(net.god_options())
			net.room["match"].phase = "ready_check"
			net.room["match"].ready_time_left = float(net.god_options().ready_check_seconds)
			net.move_axis = Vector2.ZERO
			net.blocking = false
			net.sprinting = false
			net.crouching = false
			var player: Dictionary = net.local_player()
			player.block = false
			player.sprinting = false
			_sync(net)
		return true
	if command == "ready":
		if net.room.get("phase") != "ready_check":
			net.failure.emit("Wait for the Old Man's ready check before choosing Ready.")
		elif not data.get("ready") is bool:
			net.failure.emit("Ready must be on or off.")
		else:
			net.room.players[0].ready = data.ready
			if bool(data.ready):
				_begin_battle(net)
			else:
				_sync(net)
		return true
	if command == "pickup_sword":
		var objective: Dictionary = net.room["match"].get("objective", {})
		if objective.get("enabled", false) and net.room["match"].phase in ["round", "overtime"] and objective.get("sword_accessible", false) and not objective.get("sword_owner", ""):
			var player: Dictionary = net.local_player()
			if Vector2(float(player.get("x", 0)) - float(objective.get("sword_x", 0)), float(player.get("z", 0)) - float(objective.get("sword_z", 0))).length() <= float(net.god_options().get("sword_pickup_range", 2.2)):
				objective.sword_owner = net.player_id
				objective.sword_dropped = false
				_sync(net)
		return true
	if command == "restart":
		if net.room.get("phase") == "playing":
			_begin_battle(net)
		else:
			net.failure.emit("Talk to the Old Man and complete the ready check before starting a battle.")
		return true
	if command == "lobby":
		_enter_town(net)
		return true
	if command == "cancel_start":
		if net.room.get("phase") == "ready_check":
			_cancel_ready(net, "Battle cancelled by the host.")
		return true
	return false

func tick(net: Node, delta: float) -> bool:
	# Returning true consumes this step: ready screens and transitions must not
	# also advance movement, regeneration, attacks, or the freshly reset round.
	if net.room.get("phase") == "ready_check":
		var state: Dictionary = net.room["match"]
		state.ready_time_left = maxf(0.0, float(state.ready_time_left) - delta)
		if float(state.ready_time_left) <= 0.000001:
			_cancel_ready(net)
		else:
			_sync(net, false)
		return true
	if net.room.get("phase") == "playing":
		var state: Dictionary = net.room["match"]
		if state.phase == "countdown":
			state.countdown_time_left = maxf(0.0, float(state.countdown_time_left) - delta)
			if state.countdown_time_left <= 0.000001:
				state.phase = "round"
				state.time_left = float(net.god_options().round_duration)
				state.fight_time_left = 1.0
			_sync(net, false, false)
			return false
		if state.phase in ["round", "overtime"]:
			if state.phase == "round":
				state.time_left = maxf(0.0, float(state.time_left) - delta)
			var reached_knockouts: bool = int(state.round_scores.get(net.player_id, 0)) >= int(net.god_options().knockouts_to_win)
			if reached_knockouts or float(state.time_left) <= 0.000001:
				_end_round(net)
				return true
			_sync(net, false, false)
			return false
		if state.phase in ["round_end", "victory"]:
			state.transition_time_left = maxf(0.0, float(state.transition_time_left) - delta)
			if float(state.transition_time_left) <= 0.000001:
				if state.phase == "victory":
					_enter_town(net)
				elif int(state.round_number) >= int(net.god_options().total_rounds):
					_begin_victory(net)
				else:
					_next_round(net)
			else:
				_sync(net, false)
			return true
	return false

func options_changed(net: Node, previous: Dictionary) -> void:
	var rules: Dictionary = net.god_options()
	net.room["match"].total_rounds = int(rules.total_rounds)
	if net.room.get("phase") == "ready_check":
		net.room["match"].ready_time_left = maxf(0.0, float(net.room["match"].ready_time_left) + float(rules.ready_check_seconds) - float(previous.ready_check_seconds))
	elif net.room["match"].phase == "round":
		net.room["match"].time_left = maxf(0.0, float(net.room["match"].time_left) + float(rules.round_duration) - float(previous.round_duration))
	net.snapshot["match"] = net.room["match"].duplicate(true)
