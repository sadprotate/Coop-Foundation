extends SceneTree

## Deterministic phase 1/2 checks. Run with an isolated APPDATA profile and an absolute log path.
var _checks: int = 0
var _failures: int = 0
var _net: Node
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

func _near(value: float, expected: float, description: String, tolerance: float = 0.001) -> void:
	_check(absf(value - expected) <= tolerance, "%s (%.4f, expected %.4f)" % [description, value, expected])

func _fresh(options: Dictionary = {}) -> Dictionary:
	_net.start_practice()
	_net.set_god_options(options)
	var town_player: Dictionary = _net.local_player()
	town_player.x = 0.0
	town_player.y = 0.0
	town_player.z = -3.0
	_net.send({"type": "start"})
	_net.send({"type": "ready", "ready": true})
	_events.clear()
	return _net.local_player()

func _steps(count: int, dt: float = 0.05) -> void:
	for i: int in range(count):
		_net._step_practice(dt)

func _land() -> void:
	for i: int in range(600):
		_net._step_practice(0.02)
		if bool(_net.local_player().grounded):
			return
	_check(false, "Airborne player lands within bounded simulation")

func _run() -> void:
	await create_timer(0.1).timeout
	root.get_node("Sound").shutdown()
	await create_timer(0.15).timeout
	_net = root.get_node("Net")
	_net.set_process(false)
	_net.combat_event.connect(func(data: Dictionary): _events.append(data))
	_check(_net.PROTOCOL == 4, "Expanded movement uses protocol 4")
	var p: Dictionary = _fresh()
	_near(float(p.stamina), 100.0, "Players spawn with full stamina")
	_net.move_axis = Vector2.RIGHT
	_steps(20)
	_near(float(p.x), 1.5, "Normal movement retains 5.5 m/s")
	_near(float(p.stamina), 100.0, "Walking consumes no stamina")
	p = _fresh()
	_net.move_axis = Vector2.RIGHT
	_net.sprinting = true
	_steps(20)
	_near(float(p.x), 5.0, "Sprint moves at 9 m/s")
	_near(float(p.stamina), 75.0, "Sprint drains configured stamina per second")
	_check(bool(p.sprinting), "Actual sprint state is published")
	_net.move_axis = Vector2.ZERO
	_steps(10)
	_check(not bool(p.sprinting), "Holding sprint while stationary stops consumption")
	_near(float(p.stamina), 75.0, "Regeneration respects its delay")
	_steps(10)
	_near(float(p.stamina), 75.0, "Delay expires without granting extra regeneration time")
	_steps(10)
	_near(float(p.stamina), 85.0, "Stamina regenerates at configured rate")
	p = _fresh({"max_stamina": 10, "stamina_drain": 20, "stamina_regen": 10, "stamina_regen_delay": 0.2})
	_net.move_axis = Vector2.RIGHT
	_net.sprinting = true
	_steps(10)
	_near(float(p.stamina), 0.0, "Stamina reaches zero")
	_check(bool(p.sprint_exhausted) and not bool(p.sprinting), "Depletion immediately disables sprint")
	var before: float = float(p.x)
	_steps(10)
	_near(float(p.x) - before, 2.75, "Depleted sprint returns to normal movement speed")
	_check(float(p.stamina) > 0.0 and not bool(p.sprinting), "Holding exhausted sprint regenerates without stuttering back into sprint")
	_net.sprinting = false
	_steps(1)
	_net.sprinting = true
	_steps(1)
	_check(bool(p.sprinting) and not bool(p.sprint_exhausted), "Releasing and pressing sprint permits another sprint")
	p = _fresh({"stamina_regen_delay": 0.07, "stamina_regen": 20})
	p.stamina = 50.0
	p.stamina_regen_in = 0.07
	_steps(2)
	_near(float(p.stamina), 50.6, "Only time after the regeneration delay restores stamina")
	p = _fresh()
	_net.move_axis = Vector2.RIGHT
	_net.sprinting = true
	_net.crouching = true
	_net.blocking = true
	_steps(20)
	_near(float(p.x), -1.5, "Crouch speed takes precedence over sprint and block")
	_near(float(p.stamina), 100.0, "Crouching consumes no sprint stamina")
	_near(float(p.body_height), 0.95, "Crouch publishes reduced physical height")
	_check(bool(p.crouching) and not bool(p.sprinting), "Crouch state is synchronized independently from sprint input")
	_net.crouching = false
	_steps(1)
	_near(float(p.body_height), 1.8, "Standing restores physical height")
	_check(not bool(p.sprinting), "Blocking prevents sprint")
	p = _fresh({"gravity": 32, "jump_height": 4, "jump_speed": 2, "max_jumps": 2})
	_check(_net.jump(), "First jump is accepted")
	_near(float(p.vy), 32.0, "Jump launch scales with height, gravity, and jump speed")
	_steps(5)
	_check(_net.jump(), "Configured second jump is accepted in midair")
	_check(not _net.jump(), "Jump limit rejects a third jump")
	_land()
	_check(int(p.jumps_used) == 0, "Landing restores available jumps")
	p = _fresh({"gravity": 80, "max_fall_speed": 3})
	p.y = 10.0
	p.fall_peak = 10.0
	p.vy = -2.0
	p.grounded = false
	_steps(1)
	_near(float(p.vy), -3.0, "Falling velocity is capped")
	_near(float(p.y), 9.85625, "Terminal-speed crossing is integrated for only the correct part of a step")
	_land()
	_near(float(p.health), 100.0, "Fall damage defaults to disabled")
	p = _fresh({"fall_damage": true, "fall_damage_threshold": 4, "fall_damage_multiplier": 10, "damage_multiplier": 2})
	p.y = 5.0
	p.fall_peak = 5.0
	p.grounded = false
	_land()
	_near(float(p.health), 80.0, "Fall damage uses excess drop height and damage multiplier")
	_check(_events.any(func(event: Dictionary): return event.kind == "hit" and event.target == "local" and event.source == "fall"), "Fall damage produces a normal confirmed damage event")
	p = _fresh({"god_mode": true, "fall_damage": true, "fall_damage_threshold": 0})
	p.y = 8.0
	p.fall_peak = 8.0
	p.grounded = false
	_land()
	_near(float(p.health), 100.0, "God mode prevents environmental damage")
	p = _fresh({"max_health": 50, "starting_health": 70, "fall_damage": true, "fall_damage_threshold": 0, "fall_damage_multiplier": 100, "respawn_seconds": 0.5})
	_net._reset_practice()
	p = _net.local_player()
	_near(float(p.health), 50.0, "Starting health is bounded by maximum health")
	p.y = 2.0
	p.fall_peak = 2.0
	p.grounded = false
	_land()
	_check(float(p.health) == 0 and float(p.respawn_in) > 0, "Lethal fall starts the respawn timer")
	_check(not _net.jump() and not _net.punch(), "Defeated players cannot jump or punch")
	_steps(10)
	_near(float(p.health), 50.0, "Respawn restores configured starting health")
	_check(bool(p.invulnerable), "Respawn retains temporary protection")
	_near(float(p.stamina), float(p.max_stamina), "Respawn restores stamina")
	p = _fresh({"starting_health": 40})
	_net._reset_practice()
	p = _net.local_player()
	_near(float(p.health), 40.0, "Starting health can be lower than maximum health")
	_net.set_god_options({"starting_health": 70, "sprint_speed": 15})
	_near(float(p.health), 40.0, "Live starting-health changes do not heal existing players")
	p.stamina = 60.0
	_net.set_god_options({"max_stamina": 120})
	_near(float(p.stamina), 80.0, "Live maximum stamina preserves stamina already spent")
	_net.set_god_options({"max_stamina": 10})
	_near(float(p.stamina), 0.0, "Reducing maximum stamina clamps safely to zero")
	_net.set_god_options({"gravity": -20, "max_fall_speed": 999, "total_rounds": 3.8, "fall_damage": "yes", "technical_internal": 9})
	_near(float(_net.god_options().gravity), 1.0, "Gravity is safely clamped")
	_near(float(_net.god_options().max_fall_speed), 100.0, "Fall speed is safely clamped")
	_check(int(_net.god_options().total_rounds) == 4, "Match count options are integers")
	_check(_net.god_options().fall_damage == false and not _net.god_options().has("technical_internal"), "Invalid boolean and unknown options are ignored")
	_net.reset_god_options()
	_check(_net.god_options() == _net.DEFAULT_GOD_OPTIONS, "Reset restores every expanded gameplay option")
	var arena: Control = load("res://scripts/combat_arena.gd").new()
	arena.size = Vector2(1280, 800)
	root.add_child(arena)
	arena.set_process(false)
	arena.update_snapshot(_net.snapshot, "local")
	arena.set_local_input(Vector2.ZERO, false, false, true)
	for i: int in range(10):
		arena._process(0.05)
	var model: Node3D = arena._actors.local.model
	_near(model.scale.y * 1.97, 1.8, "Crouch preserves full model scale", 0.01)
	_near(arena._actors.local.waist.rotation.x, PI * 0.5, "Crouch bends backward at the hips", 0.01)
	arena.set_local_input(Vector2.ZERO, false)
	for i: int in range(10):
		arena._process(0.05)
	_near(model.scale.y * 1.97, 1.8, "Standing smoothly restores authoritative visual height", 0.01)
	_near(arena._actors.local.waist.rotation.x, 0.0, "Standing smoothly restores the waist rotation", 0.01)
	arena.god_options.gravity = 32.0
	arena.god_options.jump_height = 4.0
	arena.god_options.jump_speed = 2.0
	arena.predict_jump()
	_near(float(arena._predicted_jump_velocity), 32.0, "Local prediction uses the same configurable jump formula")
	_net.sprinting = true
	_net.crouching = true
	_net.leave()
	_check(not _net.sprinting and not _net.crouching, "Leaving a session clears new input flags")
	arena.queue_free()
	root.get_node("Sound").shutdown()
	await process_frame
	await create_timer(0.12).timeout
	print("MOVEMENT05 RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
