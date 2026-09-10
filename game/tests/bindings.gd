extends SceneTree

var checks: int = 0
var failures: int = 0
var prefs: Node
var original: PackedByteArray
var had_settings: bool = false


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BINDINGS FAIL: " + label)
	else:
		print("BINDINGS PASS: " + label)


func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event


func mouse(button: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


func run() -> void:
	var safe_root := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-user-root="):
			safe_root = argument.trim_prefix("--expected-user-root=").replace("\\", "/").to_lower()
	if safe_root.is_empty() or not OS.get_user_data_dir().replace("\\", "/").to_lower().begins_with(safe_root + "/"):
		push_error("Bindings test requires an isolated workspace profile.")
		quit(1)
		return
	prefs = root.get_node("Prefs")
	had_settings = FileAccess.file_exists(prefs.PATH)
	if had_settings:
		original = FileAccess.get_file_as_bytes(prefs.PATH)
	var cfg := ConfigFile.new()
	prefs.movement_keys = 0
	prefs.load_bindings(cfg)
	check(key(KEY_W).is_action_pressed("move_forward") and key(KEY_UP).is_action_pressed("move_forward"), "Legacy combined preset keeps both forward keys")
	prefs.movement_keys = 1
	prefs.load_bindings(cfg)
	check(key(KEY_W).is_action_pressed("move_forward") and not key(KEY_UP).is_action_pressed("move_forward"), "Legacy WASD-only preset migrates")
	prefs.movement_keys = 2
	prefs.load_bindings(cfg)
	check(not key(KEY_W).is_action_pressed("move_forward") and key(KEY_UP).is_action_pressed("move_forward"), "Legacy arrow-only preset migrates")
	prefs.reset_bindings()
	check(prefs.CONTROL_ACTIONS.size() == 10 and key(KEY_SHIFT).is_action_pressed("sprint") and key(KEY_CTRL).is_action_pressed("crouch") and key(KEY_F).is_action_pressed("interact"), "New profiles have ten controls with Shift sprint, Ctrl crouch and F Talk")
	var old_audio: float = prefs.master
	var old_name: String = prefs.player_name
	check(prefs.set_binding_from_event("move_forward", key(KEY_Q)).is_empty(), "Forward can use a chosen keyboard key")
	check(key(KEY_Q).is_action_pressed("move_forward") and not key(KEY_W).is_action_pressed("move_forward") and not key(KEY_UP).is_action_pressed("move_forward"), "New movement binding replaces its old aliases")
	check(not prefs.set_binding_from_event("jump", key(KEY_Q)).is_empty(), "Duplicate bindings are rejected")
	check(key(KEY_SPACE).is_action_pressed("jump"), "Conflict leaves existing binding intact")
	check(not prefs.set_binding_from_event("jump", key(KEY_ESCAPE)).is_empty(), "Escape remains reserved for options")
	check(not prefs.set_binding_from_event("jump", mouse(MOUSE_BUTTON_MIDDLE)).is_empty(), "Movement and jump require keyboard keys")
	check(not prefs.set_binding_from_event("punch", mouse(MOUSE_BUTTON_WHEEL_UP)).is_empty(), "Mouse wheel remains reserved for camera zoom")
	check(not prefs.set_binding_from_event("sprint", key(KEY_ESCAPE)).is_empty() and not prefs.set_binding_from_event("crouch", mouse(MOUSE_BUTTON_MIDDLE)).is_empty(), "New movement controls keep Escape reserved and require a keyboard key")
	check(prefs.set_binding_from_event("interact", key(KEY_E)).is_empty() and key(KEY_E).is_action_pressed("interact"), "Talk supports a custom keyboard key")
	check(prefs.set_binding_from_event("sprint", key(KEY_ALT)).is_empty() and key(KEY_ALT).is_action_pressed("sprint"), "Sprint supports a custom modifier key")
	check(prefs.set_binding_from_event("punch", key(KEY_F)).is_empty() and key(KEY_F).is_action_pressed("punch"), "Attack supports keyboard binding")
	check(prefs.set_binding_from_event("block", mouse(MOUSE_BUTTON_MIDDLE)).is_empty() and mouse(MOUSE_BUTTON_MIDDLE).is_action_pressed("block"), "Block supports mouse binding")
	check(prefs.set_binding_from_event("jump", key(KEY_SHIFT)).is_empty() and key(KEY_SHIFT).is_action_pressed("jump"), "Jump supports a modifier key used on its own")
	var saved := ConfigFile.new()
	check(saved.load(prefs.PATH) == OK, "Custom controls are saved to the preference file")
	check(is_equal_approx(saved.get_value("audio", "master", -1.0), old_audio) and saved.get_value("player", "name", "") == old_name, "Saving controls preserves player and audio preferences")
	var reloaded: Node = load("res://scripts/settings.gd").new()
	reloaded.load_bindings(saved)
	check(reloaded.binding_label("move_forward") == "Q" and reloaded.binding_label("jump") == "Shift" and reloaded.binding_label("punch") == "F" and reloaded.binding_label("block") == "Middle mouse", "A fresh preferences instance reloads all changed bindings")
	check(reloaded.binding_label("sprint") == "Alt" and reloaded.binding_label("crouch") == "Ctrl" and reloaded.binding_label("interact") == "E", "New custom controls reload with the original controls")
	reloaded.free()
	var legacy: Dictionary = {
		"move_forward": [{"key": KEY_Q}], "move_back": [{"key": KEY_K}],
		"move_left": [{"key": KEY_Z}], "move_right": [{"key": KEY_X}],
		"jump": [{"key": KEY_SHIFT}], "punch": [{"key": KEY_F}],
		"block": [{"mouse": MOUSE_BUTTON_MIDDLE}],
	}
	var legacy_cfg := ConfigFile.new()
	legacy_cfg.set_value("controls", "bindings", legacy)
	legacy_cfg.set_value("player", "name", "Legacy Ranger")
	legacy_cfg.set_value("audio", "master", 0.37)
	legacy_cfg.set_value("audio", "music", 0.19)
	legacy_cfg.set_value("audio", "effects", 0.61)
	legacy_cfg.set_value("network", "server", "wss://saved.example.invalid")
	legacy_cfg.save(prefs.PATH)
	var migrated: Node = load("res://scripts/settings.gd").new()
	root.add_child(migrated)
	check(migrated.player_name == "Legacy Ranger" and is_equal_approx(migrated.master, 0.37) and is_equal_approx(migrated.music, 0.19) and is_equal_approx(migrated.effects, 0.61) and migrated.server_url == "wss://saved.example.invalid", "Loading an old profile preserves player, audio and saved server preferences")
	for action: String in prefs.LEGACY_CONTROL_ACTIONS:
		check(migrated.bindings[action] == legacy[action], "Migration preserves the existing custom " + action + " control")
	check(migrated.binding_label("sprint") == "Alt" and migrated.binding_label("crouch") == "Ctrl" and migrated.binding_label("interact") == "E", "Conflicting Shift and F defaults choose free Alt and E without replacing older controls")
	migrated.save()
	var migrated_cfg := ConfigFile.new()
	check(migrated_cfg.load(prefs.PATH) == OK and migrated_cfg.get_value("controls", "bindings", {}).size() == 10 and migrated_cfg.get_value("player", "name", "") == "Legacy Ranger" and is_equal_approx(migrated_cfg.get_value("audio", "master", -1.0), 0.37), "The migrated profile saves all ten controls and retains player and audio preferences")
	migrated.free()
	var partial: Dictionary = legacy.duplicate(true)
	partial["sprint"] = [{"key": KEY_R}]
	legacy_cfg.set_value("controls", "bindings", partial)
	prefs.load_bindings(legacy_cfg)
	check(prefs.binding_label("sprint") == "R" and prefs.binding_label("interact") == "E" and prefs.bindings["jump"] == legacy["jump"], "A partially upgraded profile preserves its existing sprint binding and original jump")
	legacy_cfg.set_value("controls", "bindings", legacy)
	prefs.load_bindings(legacy_cfg)
	var controls: VBoxContainer = load("res://scripts/controls_settings.gd").new()
	root.add_child(controls)
	await process_frame
	check(controls.binding_buttons.size() == 10 and controls.find_child("Bind_sprint", true, false).text == "Alt" and controls.find_child("Bind_crouch", true, false).text == "Ctrl" and controls.find_child("Bind_interact", true, false).text == "E", "The controls grid shows all ten actions and the actual migrated key labels")
	var guide: String = controls.find_child("Controls_Guide", true, false).text
	check("stamina" in guide and "Hold crouch" in guide and "Talk" in guide, "Sprint, crouch and Talk instructions are available inside settings")
	controls._begin_capture("jump")
	check(controls.is_capturing() and controls.consume_event(key(KEY_ESCAPE)) and not controls.is_capturing(), "Escape cancels remapping and is consumed before options handling")
	check(prefs.binding_label("jump") == "Shift", "Cancel retains the saved binding")
	controls._begin_capture("jump")
	check(controls.consume_event(key(KEY_Q)) and controls.is_capturing() and "Already used" in controls.feedback.text, "Duplicate capture shows helpful feedback and waits for another key")
	check(controls.consume_event(key(KEY_J)) and not controls.is_capturing() and prefs.binding_label("jump") == "J", "Successful capture changes binding and ends input capture")
	controls._begin_capture("sprint")
	check(controls.consume_event(key(KEY_SHIFT)) and not controls.is_capturing() and prefs.binding_label("sprint") == "Shift", "The sprint control can be rebound through the settings grid")
	controls._begin_capture("crouch")
	check(controls.consume_event(key(KEY_C)) and not controls.is_capturing() and prefs.binding_label("crouch") == "C", "The crouch control can be rebound through the settings grid")
	controls._begin_capture("interact")
	check(controls.consume_event(key(KEY_SHIFT)) and controls.is_capturing() and "Already used" in controls.feedback.text, "Talk cannot duplicate the sprint binding")
	check(controls.consume_event(key(KEY_T)) and not controls.is_capturing() and prefs.binding_label("interact") == "T", "The Talk control can be rebound through the settings grid")
	controls._begin_capture("move_left")
	controls.hide()
	check(not controls.consume_event(key(KEY_ESCAPE)) and not controls.is_capturing(), "A hidden controls page releases capture")
	controls.show()
	controls.find_child("Bindings_Reset", true, false).pressed.emit()
	check(key(KEY_W).is_action_pressed("move_forward") and key(KEY_UP).is_action_pressed("move_forward") and key(KEY_SPACE).is_action_pressed("jump") and mouse(MOUSE_BUTTON_LEFT).is_action_pressed("punch") and mouse(MOUSE_BUTTON_RIGHT).is_action_pressed("block"), "Reset restores all default controls")
	check(key(KEY_SHIFT).is_action_pressed("sprint") and key(KEY_CTRL).is_action_pressed("crouch") and key(KEY_F).is_action_pressed("interact"), "Reset also restores sprint, crouch and Talk defaults")
	var invalid := ConfigFile.new()
	var damaged: Dictionary = prefs.bindings.duplicate(true)
	damaged["jump"] = [{"key": KEY_W}]
	invalid.set_value("controls", "bindings", damaged)
	prefs.load_bindings(invalid)
	check(key(KEY_SPACE).is_action_pressed("jump") and key(KEY_W).is_action_pressed("move_forward"), "Invalid saved duplicate controls fall back to working defaults")
	controls.queue_free()
	if had_settings:
		var restore := FileAccess.open(prefs.PATH, FileAccess.WRITE)
		restore.store_buffer(original)
		restore.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs.PATH))
	root.get_node("Sound").shutdown()
	await create_timer(0.12).timeout
	print("BINDINGS RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
