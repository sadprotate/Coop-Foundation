extends SceneTree

## Run from the project folder:
## godot --headless --path . --script tests/smoke.gd
## Omit --headless and append -- --screenshots=C:/path/to/screenshots for UI captures.
## This is a local client smoke test. It does not verify internet multiplayer.
## The existing settings file is backed up and restored before the process exits.

var _failures: Array[String] = []
var _checks: int = 0
var _done: bool = false
var _settings_existed: bool = false
var _settings_backed_up: bool = false
var _original_settings := PackedByteArray()
var _capture_directory: String = ""
var _expected_user_root: String = ""
var _main: Control
var _net: Node
var _prefs: Node
var _events: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(30.0).timeout.connect(func():
		if not _done:
			_check(false, "Smoke test finished before the 30-second watchdog")
			_finish()
	)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshots="):
			_capture_directory = argument.trim_prefix("--screenshots=").replace("\\", "/")
		elif argument.begins_with("--expected-user-root="):
			_expected_user_root = argument.trim_prefix("--expected-user-root=").replace("\\", "/").to_lower()
	if not _expected_user_root.is_empty():
		if not _check(OS.get_user_data_dir().replace("\\", "/").to_lower().begins_with(_expected_user_root + "/"), "Settings use the isolated test profile: " + OS.get_user_data_dir()):
			_done = true
			quit(1)
			return
	if not _capture_directory.is_empty():
		if not _check(DisplayServer.get_name() != "headless", "Screenshot mode uses a rendering display"):
			_finish()
			return
		if not _check(DirAccess.make_dir_recursive_absolute(_capture_directory) == OK, "Screenshot directory is writable"):
			_finish()
			return
	_net = root.get_node_or_null("Net")
	_prefs = root.get_node_or_null("Prefs")
	if not _check(_net != null and _prefs != null and root.get_node_or_null("Sound") != null, "Project autoloads are present"):
		_finish()
		return
	var settings_path: String = _prefs.PATH
	_settings_existed = FileAccess.file_exists(settings_path)
	if _settings_existed:
		var original := FileAccess.open(settings_path, FileAccess.READ)
		if not _check(original != null, "Existing settings can be backed up"):
			_finish()
			return
		_original_settings = original.get_buffer(original.get_length())
		original.close()
	_settings_backed_up = true
	var scene: PackedScene = load("res://scenes/main.tscn")
	if not _check(scene != null, "Main scene loads"):
		_finish()
		return
	_main = scene.instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	_check(_main.page == "home", "Main menu is the startup page")
	_check(_find_button("Singleplayer") != null and _find_button("Multiplayer") != null and _find_button("Settings") != null and _find_button("Quit") != null, "Main menu offers the four requested actions")
	_check(_find_button("Create room") == null and _find_button("Join room") == null, "Room forms stay off the main menu")
	await _capture("01-main-menu.png")
	await _test_menu06()
	if not _tap("Settings"):
		_finish()
		return
	await process_frame
	_check(_main.page == "options", "Options opens from the main menu")
	var options_tabs := _named("OptionsTabs") as TabContainer
	_check(options_tabs != null and options_tabs.get_tab_count() == 4, "Options separates Audio, Graphics, Gameplay and God options into four tabs")
	var sliders: Array[Node] = []
	_collect(_main, "HSlider", sliders)
	var volumes: Array[Node] = []
	for slider: Range in sliders:
		if is_equal_approx(slider.max_value, 100.0):
			volumes.append(slider)
	if not _check(volumes.size() == 3, "Options has master, music, and effects controls"):
		_finish()
		return
	volumes[0].value = 43
	volumes[1].value = 17
	volumes[2].value = 62
	options_tabs.current_tab = 2
	await process_frame
	var bindings: Control = _main.controls_settings
	_check(is_instance_valid(bindings) and bindings.binding_buttons.size() == _prefs.CONTROL_ACTIONS.size(), "Settings exposes all individual movement, combat and interaction bindings")
	bindings.binding_buttons.move_forward.pressed.emit()
	var remap := InputEventKey.new()
	remap.keycode = KEY_I
	remap.physical_keycode = KEY_I
	remap.pressed = true
	_main._input(remap)
	_check(_prefs.binding_label("move_forward") == "I" and not bindings.is_capturing(), "Choosing a key updates its movement binding through the settings UI")
	bindings.binding_buttons.jump.pressed.emit()
	_open_escape()
	_check(_main.page == "options" and not bindings.is_capturing() and _prefs.binding_label("jump") == "Space", "Esc cancels a binding capture without closing settings or changing jump")
	var sensitivity := _named("Gameplay_MouseSensitivity") as Range
	if _check(sensitivity != null, "Gameplay includes mouse sensitivity"):
		sensitivity.value = 1.75
	var fullscreen := _find_button("Fullscreen") as CheckButton
	var vsync := _find_button("VSync (reduce screen tearing)") as CheckButton
	if not _check(fullscreen != null and vsync != null, "Options has fullscreen and VSync controls"):
		_finish()
		return
	fullscreen.button_pressed = true
	var full_config := ConfigFile.new()
	full_config.load(settings_path)
	_check(full_config.get_value("video", "fullscreen", false) == true, "Fullscreen selection persists")
	fullscreen.button_pressed = false
	vsync.button_pressed = true
	vsync.button_pressed = false
	var saved := ConfigFile.new()
	if _check(saved.load(settings_path) == OK, "Options writes a readable settings file"):
		_check(is_equal_approx(float(saved.get_value("audio", "master", -1.0)), 0.43), "Master volume persists")
		_check(is_equal_approx(float(saved.get_value("audio", "music", -1.0)), 0.17), "Music volume persists")
		_check(is_equal_approx(float(saved.get_value("audio", "effects", -1.0)), 0.62), "Effects volume persists")
		_check(saved.get_value("controls", "bindings", {}).get("move_forward", []) == [{"key": KEY_I}], "Custom movement binding persists")
		_check(is_equal_approx(float(saved.get_value("gameplay", "mouse_sensitivity", -1)), 1.75), "Mouse sensitivity persists")
		_check(saved.get_value("video", "fullscreen", true) == false and saved.get_value("video", "vsync", true) == false, "Windowed mode and VSync choices persist")
	var reloaded: Node = load("res://scripts/settings.gd").new()
	root.add_child(reloaded)
	_check(is_equal_approx(reloaded.master, 0.43) and reloaded.binding_label("move_forward") == "I" and not reloaded.fullscreen and not reloaded.vsync and is_equal_approx(reloaded.mouse_sensitivity, 1.75), "A fresh settings instance loads saved choices and the custom key")
	reloaded.queue_free()
	await _capture("02-options.png")
	_tap("Reset controls")
	if not _tap("Back"):
		_finish()
		return
	_check(_main.page == "home", "Back returns to the main menu")
	if not _tap("Singleplayer"):
		_finish()
		return
	await process_frame
	_check(_net.practice and _main.page == "game", "Single-player starts local practice")
	_check(_net.room.get("code") == "PRACTICE", "Local practice is explicitly identified")
	_check(_net.room.players.size() == 1, "Local practice contains one player")
	_check(_net.in_town() and _net.room.phase == "lobby" and bool(_net.snapshot.safe_zone), "Single-player initially enters the safe Town Lobby")
	_check(is_instance_valid(_main.health_hud) and _main.health_hud.health == 100.0, "The combat health display receives current player health")
	await process_frame
	_check(_main.arena.get_global_rect().is_equal_approx(_main.get_global_rect()), "Arena fills the entire game viewport")
	_check(_find_button("Reset arena") == null and _find_button("Main menu") == null, "Arena only shows game and HUD; room buttons live in Escape options")
	_check(_named("ControlsHUD") == null and _named("SessionHUD") == null and _named("CombatFeedback") == null, "Play screen has no instruction strip, session panel or combat text feed")
	await _capture("03-practice.png")
	if DisplayServer.get_name() != "headless":
		_test_camera_and_pointer()
	await _test_options_overlay()
	await _test_town_ready_flow()
	# Advance the real practice controller deterministically through its public input state.
	_main.set_process(false)
	_net.set_process(false)
	var player: Dictionary = _net.snapshot.players[0]
	var start := Vector3(float(player.x), float(player.y), float(player.z))
	_net.combat_event.connect(func(event: Dictionary): _events.append(event))
	_net.move_axis = Vector2.LEFT
	_net.facing_yaw = 1.2
	_net._step_practice(0.05)
	player = _net.snapshot.players[0]
	_check(float(player.x) < start.x, "Movement input changes the player position")
	_check(is_equal_approx(float(player.yaw), 1.2), "Facing direction reaches the practice snapshot")
	_check(int(player.health) == 100 and int(player.max_health) == 100, "Practice starts at 100 health")
	var before_block: float = float(player.x)
	_net.blocking = true
	_net._step_practice(0.05)
	_check(bool(player.block) and is_equal_approx(before_block - float(player.x), 0.125), "Blocking pose applies reduced movement speed")
	_check(not _net.punch(), "Punch is unavailable while blocking")
	_net.move_axis = Vector2.ZERO
	_net.blocking = false
	_net._step_practice(0.05)
	_check(_net.punch() and float(player.punch_t) > 0.0, "Ground punch triggers a visible attack pose")
	_check(_events.size() == 1 and _events[0].kind == "miss" and not bool(_events[0].critical), "Empty practice arena reports a normal miss")
	_check(_main.arena._feedback.is_empty(), "Misses produce no floating text or numbers")
	_net.punch()
	_check(_events.size() == 1, "Punch cooldown prevents immediate repeat attacks")
	for step in range(12):
		_net._step_practice(0.05)
	_check(_net.jump(), "Jump accepts a grounded player")
	_net._step_practice(0.05)
	_check(float(player.y) > 0.0 and not bool(player.grounded), "Jump lifts the player above the floor")
	_check(not _net.jump(), "Jump cannot be repeated in midair")
	_check(_net.punch(), "Airborne punch is available")
	_check(bool(_events.back().critical) and _events.back().kind == "miss", "Airborne practice punch is marked critical without inventing a target")
	await process_frame
	await _capture("04-airborne-punch.png")
	for step in range(20):
		_net._step_practice(0.05)
	_check(bool(player.grounded) and is_zero_approx(float(player.y)), "Jump lands back on the floor")
	await _test_god_controls()
	if DisplayServer.get_name() != "headless":
		await _test_remapped_gameplay()
	await _test_clean_combat_display()
	_open_escape()
	if not _tap("Restart match"):
		_finish()
		return
	player = _net.snapshot.players[0]
	_check(_net.room.phase == "playing" and int(player.health) == 100 and bool(player.grounded) and not bool(player.block) and is_zero_approx(float(player.punch_t)), "Reset restores health and clears combat poses")
	_check(Vector3(float(player.x), float(player.y), float(player.z)).is_equal_approx(Vector3(-4, 0, 0)), "Reset restores the 3D player spawn")
	if not _tap("Main menu"):
		_finish()
		return
	_check(_main.page == "home" and not _net.practice and _net.room.is_empty(), "Leaving clears the session and returns home")
	_finish()


func _test_menu06() -> void:
	_tap("Multiplayer")
	await process_frame
	_check(_main.page == "multiplayer" and _find_button("Host") != null and _find_button("Join") != null and _find_button("SAVE SERVER") != null, "Multiplayer submenu contains server save, Host and Join")
	await _capture("11-multiplayer.png")
	_tap("Host")
	_check(_main.page == "host" and _main.name_field != null and _find_button("Create room") != null, "Host opens the existing room creation form")
	_tap("Back")
	_tap("Join")
	_check(_main.page == "join" and _main.code_field != null and _find_button("Join room") != null, "Join opens name and room-code fields")
	_tap("Back")
	var saved_address: String = _prefs.server_url
	_check(_main.server_field.text == saved_address, "Server editor preserves the saved address")
	_main.server_field.text = "this is not a server"
	_tap("SAVE SERVER")
	_check(_prefs.server_url == saved_address, "Invalid addresses cannot replace the saved server")
	_main.server_field.text = "wss://example.com:443/ws"
	_tap("SAVE SERVER")
	var config := ConfigFile.new()
	config.load(_prefs.PATH)
	var fresh: Node = load("res://scripts/settings.gd").new()
	root.add_child(fresh)
	_check(fresh.server_url == "wss://example.com:443/ws", "WSS changes save and reload")
	fresh.queue_free()
	_check(_main._valid_server_address("ws://127.0.0.1:8787/ws") and _main._valid_server_address("wss://[::1]:443/ws") and not _main._valid_server_address("wss://host:99999") and not _main._valid_server_address("https://example.com"), "Server validation accepts local/secure WebSockets and rejects wrong schemes or ports")
	_main.server_field.text = saved_address
	_tap("SAVE SERVER")
	_tap("Back")
	_check(_main.page == "home", "Multiplayer Back returns to the four-option menu")

func _test_town_ready_flow() -> void:
	_main.set_process(false)
	_net.set_process(false)
	# Walk through the normal practice movement controller to the interaction area.
	for step in range(100):
		var player: Dictionary = _net.local_player()
		var remaining := Vector2(-float(player.x), -3.0 - float(player.z))
		if remaining.length() < 0.15:
			break
		_net.move_axis = remaining.normalized()
		_net._step_practice(0.025)
	_net.move_axis = Vector2.ZERO
	_net._step_practice(0.05)
	_check(_net.near_old_man(), "Walking toward the Old Man reaches his interaction range")
	if DisplayServer.get_name() != "headless":
		_main.focused = true
		_main.arena.capture_mouse()
		var talk := InputEventKey.new()
		talk.keycode = KEY_F
		talk.physical_keycode = KEY_F
		talk.pressed = true
		_main._input(talk)
	else:
		_main.session_ui.talk()
	await process_frame
	_check(_main.session_ui.dialog_kind == "npc", "Talk opens the Old Man's dialogue")
	if not _tap("Match, teams & settings"):
		return
	await process_frame
	await process_frame
	_check(_main.page == "options" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Old Man settings keeps the cursor free after deferred dialog close")
	_main._back_from_options()
	await process_frame
	_main.session_ui.talk()
	await process_frame
	await _capture("08-old-man.png")
	if not _tap("START BATTLE"):
		return
	await process_frame
	_check(_net.room.phase == "ready_check" and _net.in_town() and _main.session_ui.dialog_kind == "ready", "Start Battle opens Ready and keeps the player in town")
	_check(not _net.can_control() and _net.move_axis.is_zero_approx(), "Ready check releases movement controls")
	await _capture("09-ready-check.png")
	if not _tap("READY"):
		return
	await process_frame
	_check(_net.room.phase == "playing" and not _net.in_town() and not bool(_net.snapshot.safe_zone), "Ready teleports the player into the grass battle arena")
	_check(_main.session_ui.dialog_kind.is_empty() and _main.arena.zone == "arena", "The dialogue closes and the battle scenery appears")
	await _capture("10-battle-arena.png")


func _test_camera_and_pointer() -> void:
	var view: Control = _main.arena
	view.capture_mouse()
	var original_yaw: float = view.camera_yaw
	var original_pitch: float = view.camera_pitch
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(70, -30)
	view._input(motion)
	_check(not is_equal_approx(float(view.camera_yaw), original_yaw) and not is_equal_approx(float(view.camera_pitch), original_pitch), "Mouse motion adjusts camera orbit and pitch")
	motion.relative = Vector2(0, 10000)
	view._input(motion)
	_check(is_equal_approx(float(view.camera_pitch), deg_to_rad(75.0)), "Camera pitch stops at 75 degrees")
	motion.relative = Vector2(0, -10000)
	view._input(motion)
	_check(is_equal_approx(float(view.camera_pitch), deg_to_rad(35.0)), "Camera pitch stops at 35 degrees")
	var distance_before: float = view.camera_distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	view._input(wheel)
	_check(float(view.camera_distance) > distance_before, "Mouse wheel adjusts camera distance")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	_net.move_axis = Vector2.ONE
	_net.blocking = true
	_main._input(tab)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _main.page == "game", "Tab leaves the pointer captured and does not open a menu")
	view.camera_pitch = original_pitch


func _open_escape() -> void:
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_main._input(escape)


func _test_options_overlay() -> void:
	var original_arena: Control = _main.arena
	var yaw: float = original_arena.camera_yaw
	var pitch: float = original_arena.camera_pitch
	_net.move_axis = Vector2.ONE
	_net.blocking = true
	_open_escape()
	await process_frame
	_check(_main.page == "options" and is_instance_valid(_main.options_overlay), "Escape opens an options overlay above the arena")
	_check(_main.arena == original_arena and original_arena.is_visible_in_tree(), "Options preserves the visible arena instance")
	_check(_net.move_axis == Vector2.ZERO and not _net.blocking, "Opening options stops local movement and block intent")
	if DisplayServer.get_name() != "headless":
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape releases the pointer")
	await _capture("05-escape-options.png")
	_open_escape()
	await process_frame
	_check(_main.page == "game" and _main.arena == original_arena, "Escape resumes the same arena")
	_check(is_equal_approx(float(original_arena.camera_yaw), yaw) and is_equal_approx(float(original_arena.camera_pitch), pitch), "Closing options preserves camera orbit and pitch")
	if DisplayServer.get_name() != "headless":
		_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Resuming recaptures the pointer")


func _test_god_controls() -> void:
	_open_escape()
	await process_frame
	var original_arena: Control = _main.arena
	var tabs := _named("OptionsTabs") as TabContainer
	if tabs != null:
		tabs.current_tab = 3
	await process_frame
	if not _check(_main.god_controls.size() == _main.GOD_FIELDS.size() and _main.god_toggle != null, "Host options exposes the toggle and every categorized gameplay control"):
		return
	_main.god_toggle.button_pressed = true
	_check(bool(_net.god_options().god_mode), "God mode UI applies the shared damage-off flag")
	var changes := {"attack_speed": 8.0, "attack_damage": 25.0, "move_speed": 7.0, "jump_speed": 1.5, "jump_height": 3.0, "max_jumps": 3, "max_health": 200, "attack_range": 3.5, "air_damage_multiplier": 3.0, "block_speed_multiplier": 0.5, "respawn_seconds": 1.0}
	for key: String in changes:
		_main.god_controls[key].value = changes[key]
	var all_values := true
	for key: String in changes:
		all_values = all_values and is_equal_approx(float(_net.god_options()[key]), float(changes[key]))
	_check(all_values, "Every God option control applies its value to the practice rules")
	_check(_main.arena == original_arena and is_instance_valid(_main.options_overlay), "Live rule changes keep the options overlay and arena intact")
	_check(float(_net.local_player().max_health) == 200 and float(_net.local_player().health) == 200, "Maximum health option updates character health capacity")
	# Simulate a room broadcast while the overlay remains open.
	_net.set_god_options({"attack_damage": 30.0})
	_check(is_equal_approx(float(_main.god_controls.attack_damage.value), 30.0), "An incoming shared rule change refreshes the displayed God control")
	await _capture("06-god-options.png")
	_open_escape()
	await process_frame
	var player: Dictionary = _net.local_player()
	_net.move_axis = Vector2.RIGHT
	var before_x: float = player.x
	_net._step_practice(0.1)
	_check(is_equal_approx(float(player.x) - before_x, 0.7), "Tuned move speed changes distance travelled")
	_net.move_axis = Vector2.ZERO
	_check(_net.jump(), "Tuned first jump is accepted")
	_net._step_practice(0.05)
	_check(_net.jump(), "Second jump is accepted while airborne")
	_net._step_practice(0.05)
	_check(_net.jump() and not _net.jump(), "Third jump is allowed and a fourth is rejected")
	for step in range(200):
		_net._step_practice(0.01)
	_check(bool(player.grounded) and int(player.jumps_used) == 0, "Landing replenishes the configured jump allowance")
	# Measure single-jump apex and airtime through the real practice controller.
	_net.set_god_options({"max_jumps": 1, "jump_speed": 1.0, "jump_height": 3.0})
	var normal := _measure_jump()
	_net.set_god_options({"jump_speed": 2.0})
	var faster := _measure_jump()
	_check(absf(float(normal.height) - 3.0) < 0.03 and absf(float(faster.height) - 3.0) < 0.03, "Jump height reaches the configured apex at different jump speeds")
	_check(float(faster.airtime) < float(normal.airtime) * 0.6, "Higher jump speed shortens airtime while preserving height")
	_net.set_god_options({"jump_height": 5.0})
	var higher := _measure_jump()
	_check(float(higher.height) > float(faster.height) + 1.9, "Increasing jump height raises the measured apex")
	var events_before: int = _events.size()
	_net.punch()
	_net._step_practice(0.13)
	_net.punch()
	_check(_events.size() == events_before + 2, "Tuned attack speed accepts attacks faster than the default cooldown")
	if DisplayServer.get_name() != "headless":
		_net._step_practice(0.2)
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = true
		var prior_focus: bool = _main.focused
		_main.focused = true
		var held_start: int = _events.size()
		_main._input(mouse)
		for step in range(4):
			_net._step_practice(0.05)
			_main._process(0.05)
		_check(_events.size() == held_start + 2, "Holding left mouse repeats punches at the tuned attack speed")
		_open_escape()
		var stopped_at: int = _events.size()
		for step in range(6):
			_net._step_practice(0.05)
			_main._process(0.05)
		_check(not _main.attack_hold and _events.size() == stopped_at, "Escape cancels held attacks while options are open")
		_main.focused = prior_focus
	else:
		_open_escape()
	_tap("Reset God options to defaults")
	var reset_matches := true
	for key: String in _net.DEFAULT_GOD_OPTIONS:
		reset_matches = reset_matches and _net.god_options()[key] == _net.DEFAULT_GOD_OPTIONS[key]
	_check(reset_matches and not _main.god_toggle.button_pressed, "Reset God options restores all defaults and turns God mode off")
	_open_escape()
	await process_frame


func _test_remapped_gameplay() -> void:
	var prior_focus: bool = _main.focused
	_main.focused = true
	_main.arena.capture_mouse()
	for binding: Array in [["move_forward", KEY_I], ["jump", KEY_J], ["punch", KEY_K], ["block", KEY_G]]:
		var key := InputEventKey.new()
		key.keycode = binding[1]
		key.physical_keycode = binding[1]
		key.pressed = true
		_prefs.set_binding_from_event(binding[0], key)
	var movement := InputEventKey.new()
	movement.keycode = KEY_I
	movement.physical_keycode = KEY_I
	movement.pressed = true
	Input.parse_input_event(movement)
	await process_frame
	_main._process(0.01)
	_check(_net.move_axis.length() > 0.9, "The customized movement key drives the live game input controller")
	movement.pressed = false
	Input.parse_input_event(movement)
	await process_frame
	_main._process(0.01)
	_check(_net.move_axis.is_zero_approx(), "Releasing the customized movement key stops movement")
	var jump_key := InputEventKey.new()
	jump_key.keycode = KEY_J
	jump_key.physical_keycode = KEY_J
	jump_key.pressed = true
	_main._input(jump_key)
	_check(not bool(_net.local_player().grounded), "The customized jump key launches the player")
	for step in range(100):
		_net._step_practice(0.02)
	var attack := InputEventKey.new()
	attack.keycode = KEY_K
	attack.physical_keycode = KEY_K
	attack.pressed = true
	var start: int = _events.size()
	_main._input(attack)
	for step in range(12):
		_net._step_practice(0.05)
		_main._process(0.05)
	_check(_main.attack_hold and _events.size() >= start + 2, "Holding a customized attack key repeats punches")
	attack.pressed = false
	_main._input(attack)
	_check(not _main.attack_hold, "Releasing the customized attack key stops repeat attacks")
	var block := InputEventKey.new()
	block.keycode = KEY_G
	block.physical_keycode = KEY_G
	block.pressed = true
	Input.parse_input_event(block)
	await process_frame
	_main._process(0.01)
	_check(_net.blocking, "The customized block key holds guard through the input controller")
	_open_escape()
	_check(not _net.blocking and not _main.attack_hold, "Escape clears remapped combat inputs")
	block.pressed = false
	Input.parse_input_event(block)
	await process_frame
	_prefs.reset_bindings()
	_open_escape()
	await process_frame
	_main.focused = prior_focus


func _test_clean_combat_display() -> void:
	var view: Control = _main.arena
	var fixture: Dictionary = _net.snapshot.duplicate(true)
	var local: Dictionary = fixture.players[0]
	var other: Dictionary = local.duplicate(true)
	other.id = "display-opponent"
	other.name = "Rook"
	other.slot = 1
	other.x = float(local.x) + 1.6
	other.z = float(local.z) - 1.5
	other.health = 65.0
	var ally: Dictionary = local.duplicate(true)
	ally.id = "display-ally"
	ally.name = "Nova"
	ally.slot = 2
	ally.x = float(local.x) - 1.6
	ally.z = float(local.z) - 1.5
	fixture.players.append(other)
	fixture.players.append(ally)
	view.update_snapshot(fixture, _net.player_id)
	view._feedback.clear()
	for kind: String in ["miss", "blocked", "defeat", "respawn"]:
		view.handle_combat_event({"kind": kind, "attacker": _net.player_id, "target": other.id, "damage": 0})
	_check(view._feedback.is_empty(), "Miss, block, defeat and respawn events produce no combat words or counters")
	view.handle_combat_event({"kind": "hit", "attacker": _net.player_id, "target": other.id, "damage": 0})
	_check(view._feedback.is_empty(), "Zero-damage hits produce no numbers")
	view.handle_combat_event({"kind": "hit", "attacker": _net.player_id, "target": other.id, "damage": 20, "critical": true})
	_check(view._feedback.size() == 1 and view._feedback[0].text == "20", "A confirmed critical hit shows only its damage number")
	_check(view._actors[other.id].state.name == "Rook" and view._actors[other.id].state.health == 65.0, "Other-player names and current health reach overhead rendering")
	_main.health_hud.update_health({"health": 35, "max_health": 100}, false, Color("61e5d4"))
	_check(_main.health_hud.health == 35 and _main.health_hud.maximum == 100, "Health HUD handles a damaged player")
	await process_frame
	await _capture("07-combat-display-fixture.png")
	view.update_snapshot(_net.snapshot, _net.player_id)
	view._feedback.clear()
	_main._on_state(_net.snapshot)


func _measure_jump() -> Dictionary:
	_net.jump()
	var peak: float = 0.0
	var time: float = 0.0
	while not bool(_net.local_player().grounded) and time < 5.0:
		_net._step_practice(0.005)
		peak = maxf(peak, float(_net.local_player().y))
		time += 0.005
	return {"height": peak, "airtime": time}


func _named(node_name: String) -> Node:
	return _main.find_child(node_name, true, false)


func _collect(node: Node, kind: String, found: Array[Node]) -> void:
	if node.is_class(kind):
		found.append(node)
	for child: Node in node.get_children():
		_collect(child, kind, found)


func _find_button(text: String) -> BaseButton:
	if not is_instance_valid(_main):
		return null
	var buttons: Array[Node] = []
	_collect(_main, "Button", buttons)
	for button: Button in buttons:
		if button.text == text:
			return button
	return null


func _tap(text: String) -> bool:
	var button := _find_button(text)
	if not _check(button != null and not button.disabled, "Action available: " + text):
		return false
	button.pressed.emit()
	return true


func _capture(filename: String) -> void:
	if _capture_directory.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	_check_layout(filename)
	var screenshot := root.get_texture().get_image()
	_check(screenshot.save_png(_capture_directory.path_join(filename)) == OK, "Saved screenshot " + filename)


func _check_layout(page_name: String) -> void:
	var controls: Array[Node] = []
	_collect(_main, "Control", controls)
	var bounds := _main.get_global_rect().grow(1.0)
	var overflow: Array[String] = []
	for control: Control in controls:
		if not control.is_visible_in_tree():
			continue
		var ancestor := control.get_parent()
		var scroll_content := false
		while ancestor != null and ancestor != _main:
			if ancestor is ScrollContainer:
				scroll_content = true
				break
			ancestor = ancestor.get_parent()
		if scroll_content:
			continue
		var rect := control.get_global_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0 and not bounds.encloses(rect):
			overflow.append("%s %s" % [control.get_path(), rect])
	_check(overflow.is_empty(), "All visible controls fit the window: " + page_name)
	if not overflow.is_empty():
		print("Overflowing controls: ", overflow)
	print("Captured window size: ", root.size, "; logical content: ", bounds.size)


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
		push_error("FAIL: " + description)
	return condition


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_net):
		_net.leave()
	if _settings_backed_up:
		if _settings_existed:
			var restored := FileAccess.open(_prefs.PATH, FileAccess.WRITE)
			if _check(restored != null, "Original settings file can be restored"):
				restored.store_buffer(_original_settings)
				restored.close()
		else:
			var settings_absolute := ProjectSettings.globalize_path(_prefs.PATH)
			if FileAccess.file_exists(settings_absolute):
				_check(DirAccess.remove_absolute(settings_absolute) == OK, "Temporary settings file is removed")
	print("SMOKE RESULT: %d checks, %d failures. Local client only; internet multiplayer unverified." % [_checks, _failures.size()])
	root.get_node("Sound").shutdown()
	await create_timer(0.1).timeout
	if is_instance_valid(_main):
		_main.queue_free()
	for _i in 6:
		await process_frame
	quit(0 if _failures.is_empty() else 1)
