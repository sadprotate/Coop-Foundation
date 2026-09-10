extends SceneTree

## Two independent Godot WebSocket peers exercise real server authority and remote presentation.
## Usage: godot --headless --path game --script tests/movement05_online.gd -- --server=ws://127.0.0.1:8796/ws
var _checks: int = 0
var _failures: int = 0
var _host: Node
var _guest: Node
var _arena: Control
var _guest_errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
	return condition

func _until(predicate: Callable, description: String, seconds: float = 4.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return _check(true, description)
		await process_frame
	return _check(false, description)

func _run() -> void:
	var address: String = "ws://127.0.0.1:8796/ws"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--server="):
			address = argument.trim_prefix("--server=")
	var network: Script = load("res://scripts/network.gd")
	_host = network.new()
	_guest = network.new()
	root.add_child(_host)
	root.add_child(_guest)
	_guest.failure.connect(func(message: String): _guest_errors.append(message))
	_host.failure.connect(func(message: String): _check(false, "Host network failure: " + message))
	_host.connect_room(address, {"type": "create", "name": "Movement Host", "mode": "ffa"})
	if not await _until(func(): return not _host.room.is_empty(), "Godot host creates a real protocol 4 room"):
		await _finish()
		return
	_guest.connect_room(address, {"type": "join", "name": "Movement Guest", "code": _host.room.code})
	if not await _until(func(): return _guest.room.get("players", []).size() == 2 and _host.room.get("players", []).size() == 2, "Second independent Godot peer joins the same room"):
		await _finish()
		return
	_host.set_god_options({"sprint_speed": 12.0, "max_stamina": 20, "stamina_drain": 20.0, "stamina_regen": 10.0, "stamina_regen_delay": 0.2, "crouch_speed": 1.5})
	await _until(func(): return float(_guest.god_options().sprint_speed) == 12.0 and int(_guest.god_options().max_stamina) == 20, "Host movement and stamina options replicate to the other Godot peer")
	_guest.set_god_options({"sprint_speed": 29.0})
	await _until(func(): return not _guest_errors.is_empty(), "Server rejects guest changes to host gameplay options")
	_check(float(_guest.god_options().sprint_speed) == 12.0, "Rejected guest change cannot replace authoritative sprint speed")
	_guest.send({"type": "ready", "ready": true})
	await _until(func(): return _host.room.players.all(func(player: Dictionary): return bool(player.ready)), "Guest readiness reaches the host")
	_host.send({"type": "start"})
	if not await _until(func(): return _host.room.get("phase") == "playing" and _guest.room.get("phase") == "playing" and not _host.local_player().is_empty() and not _guest.local_player().is_empty(), "Both Godot peers enter the same authoritative arena"):
		await _finish()
		return
	_host.move_axis = Vector2.RIGHT
	_host.sprinting = true
	_host.flush_input()
	await _until(func(): return bool(_host.local_player().get("sprinting", false)) and float(_host.local_player().get("stamina", 20)) < 20, "Godot sprint input produces authoritative sprint and stamina consumption")
	await _until(func(): return _guest.snapshot.get("players", []).any(func(player: Dictionary): return player.id == _host.player_id and bool(player.get("sprinting", false)) and float(player.get("stamina", 20)) < 20), "Remote Godot peer receives the host's actual sprint and stamina state")
	await _until(func(): return bool(_host.local_player().get("sprint_exhausted", false)) and not bool(_host.local_player().get("sprinting", false)), "Server exhaustion stops a held sprint automatically")
	var depleted_x: float = float(_host.local_player().x)
	await create_timer(0.4).timeout
	var normal_distance: float = float(_host.local_player().x) - depleted_x
	_check(normal_distance > 1.2 and normal_distance < 3.1, "Exhausted Godot player moves at ordinary speed while Shift stays held")
	_check(float(_host.local_player().stamina) > 0.0 and not bool(_host.local_player().sprinting), "Regeneration is replicated without restarting held exhausted sprint")
	_host.move_axis = Vector2.ZERO
	_host.sprinting = false
	_host.crouching = true
	_host.flush_input()
	await _until(func(): return _guest.snapshot.get("players", []).any(func(player: Dictionary): return player.id == _host.player_id and bool(player.get("crouching", false)) and is_equal_approx(float(player.get("body_height", 0)), 0.95)), "Crouch input and reduced hitbox height round-trip to the other Godot peer")
	_arena = load("res://scripts/combat_arena.gd").new()
	_arena.size = Vector2(1280, 800)
	root.add_child(_arena)
	_arena.set_process(false)
	_arena.update_snapshot(_guest.snapshot, _guest.player_id)
	for i: int in range(12):
		_arena._process(0.05)
	var remote_model: Node3D = _arena._actors[_host.player_id].model
	_check(absf(remote_model.scale.y * 1.97 - 0.95) < 0.02, "Other Godot peer visibly crouches the remote character to the synchronized hitbox height")
	_host.crouching = false
	_host.flush_input()
	await _until(func(): return _guest.snapshot.get("players", []).any(func(player: Dictionary): return player.id == _host.player_id and not bool(player.get("crouching", true))), "Releasing crouch restores standing state on the other peer")
	_arena.update_snapshot(_guest.snapshot, _guest.player_id)
	for i: int in range(12):
		_arena._process(0.05)
	_check(absf(remote_model.scale.y * 1.97 - 1.8) < 0.02, "Remote visual height returns to the standing hitbox height")
	await _finish()

func _finish() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	for peer: Node in [_host, _guest]:
		if is_instance_valid(peer):
			peer.leave()
			peer.queue_free()
	root.get_node("Sound").shutdown()
	await process_frame
	await create_timer(0.2).timeout
	print("MOVEMENT05 ONLINE RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
