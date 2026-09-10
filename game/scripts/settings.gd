extends Node

signal bindings_changed

const PATH := "user://settings.cfg"
const LEGACY_CONTROL_ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "jump", "punch", "block"]
const CONTROL_ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "jump", "punch", "block", "sprint", "crouch", "interact"]
const CONTROL_LABELS := {
	"move_forward": "Move forward", "move_back": "Move backward",
	"move_left": "Move left", "move_right": "Move right",
	"jump": "Jump", "punch": "Attack", "block": "Block",
	"sprint": "Sprint", "crouch": "Crouch", "interact": "Talk",
}
var player_name: String = "Player"
var server_url: String = ""
var master: float = 0.75
var music: float = 0.22
var effects: float = 0.65
var fullscreen: bool = false
var vsync: bool = true
var show_names: bool = true
var movement_keys: int = 0
var mouse_sensitivity: float = 1.0
var invert_x: bool = false
var invert_y: bool = false
var show_fps: bool = false
var fps_position: int = 0
var camera_distance: float = 11.5
var bindings: Dictionary = {}

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		player_name = str(cfg.get_value("player", "name", "Player")).left(20)
		server_url = str(cfg.get_value("network", "server", ""))
		master = clampf(float(cfg.get_value("audio", "master", 0.75)), 0.0, 1.0)
		music = clampf(float(cfg.get_value("audio", "music", 0.22)), 0.0, 1.0)
		effects = clampf(float(cfg.get_value("audio", "effects", 0.65)), 0.0, 1.0)
		fullscreen = bool(cfg.get_value("video", "fullscreen", false))
		vsync = bool(cfg.get_value("video", "vsync", true))
		show_names = bool(cfg.get_value("gameplay", "show_names", true))
		movement_keys = clampi(int(cfg.get_value("gameplay", "movement_keys", 0)), 0, 2)
		mouse_sensitivity = clampf(float(cfg.get_value("gameplay", "mouse_sensitivity", 1.0)), 0.25, 3.0)
		invert_x = bool(cfg.get_value("gameplay", "invert_x", false))
		invert_y = bool(cfg.get_value("gameplay", "invert_y", false))
		show_fps = bool(cfg.get_value("video", "show_fps", false))
		fps_position = clampi(int(cfg.get_value("video", "fps_position", 0)), 0, 3)
		camera_distance = clampf(float(cfg.get_value("gameplay", "camera_distance", 11.5)), 8.0, 20.0)
	load_bindings(cfg)
	apply_display()

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("network", "server", server_url)
	cfg.set_value("audio", "master", master)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "effects", effects)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("gameplay", "show_names", show_names)
	cfg.set_value("gameplay", "movement_keys", movement_keys)
	cfg.set_value("gameplay", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("gameplay", "invert_x", invert_x)
	cfg.set_value("gameplay", "invert_y", invert_y)
	cfg.set_value("gameplay", "camera_distance", camera_distance)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("video", "fps_position", fps_position)
	cfg.set_value("controls", "bindings", bindings)
	var result := cfg.save(PATH)
	if result != OK:
		push_warning("Could not save settings: %s" % error_string(result))

func apply_display() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func default_bindings(preset: int = 0) -> Dictionary:
	var result: Dictionary = {
		"move_forward": [{"key": KEY_W}], "move_back": [{"key": KEY_S}],
		"move_left": [{"key": KEY_A}], "move_right": [{"key": KEY_D}],
		"jump": [{"key": KEY_SPACE}], "punch": [{"mouse": MOUSE_BUTTON_LEFT}],
		"block": [{"mouse": MOUSE_BUTTON_RIGHT}],
		"sprint": [{"key": KEY_SHIFT}], "crouch": [{"key": KEY_CTRL}],
		"interact": [{"key": KEY_F}],
	}
	var arrow_keys := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
	for index: int in range(4):
		var action: String = CONTROL_ACTIONS[index]
		if preset == 2:
			result[action] = [{"key": arrow_keys[index]}]
		elif preset == 0:
			result[action].append({"key": arrow_keys[index]})
	return result


func load_bindings(cfg: ConfigFile) -> void:
	# Old movement presets retain their behavior until a player changes a binding.
	var saved: Variant = cfg.get_value("controls", "bindings", {})
	bindings = _migrate_bindings(saved)
	if bindings.is_empty():
		bindings = default_bindings(movement_keys)
	apply_bindings()


func _migrate_bindings(candidate: Variant) -> Dictionary:
	if not candidate is Dictionary:
		return {}
	for action: String in LEGACY_CONTROL_ACTIONS:
		if not candidate.has(action):
			return {}
	var present_actions: Array[String] = []
	for action: String in CONTROL_ACTIONS:
		if candidate.has(action):
			present_actions.append(action)
	if not _valid_bindings(candidate, present_actions):
		return {}
	var migrated: Dictionary = {}
	var used: Array[String] = []
	for action: String in present_actions:
		migrated[action] = candidate[action].duplicate(true)
		for spec: Dictionary in migrated[action]:
			used.append(_binding_identity(spec))
	# New actions never replace an older custom key. Pick the first free fallback,
	# including for partially migrated profiles that already saved a new action.
	var choices := {
		"sprint": [KEY_SHIFT, KEY_ALT, KEY_R, KEY_E, KEY_C, KEY_V, KEY_B, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L, KEY_U, KEY_O, KEY_P, KEY_X, KEY_Z, KEY_T, KEY_Y],
		"crouch": [KEY_CTRL, KEY_C, KEY_ALT, KEY_V, KEY_X, KEY_Z, KEY_B, KEY_R, KEY_E, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L, KEY_U, KEY_O, KEY_P, KEY_T, KEY_Y],
		"interact": [KEY_F, KEY_E, KEY_R, KEY_G, KEY_T, KEY_V, KEY_C, KEY_X, KEY_Z, KEY_B, KEY_H, KEY_J, KEY_K, KEY_L, KEY_I, KEY_O, KEY_P, KEY_ALT, KEY_U, KEY_Y],
	}
	for action: String in CONTROL_ACTIONS:
		if migrated.has(action):
			continue
		for code: int in choices[action]:
			var spec := {"key": code}
			var identity: String = _binding_identity(spec)
			if identity not in used:
				migrated[action] = [spec]
				used.append(identity)
				break
	return migrated if _valid_bindings(migrated) else {}


func _valid_bindings(candidate: Variant, actions: Array = CONTROL_ACTIONS) -> bool:
	if not candidate is Dictionary:
		return false
	var assigned: Array[String] = []
	for action: String in actions:
		var events: Variant = candidate.get(action, [])
		if not events is Array or events.is_empty() or events.size() > 2:
			return false
		for spec: Variant in events:
			if not spec is Dictionary or spec.size() != 1:
				return false
			var identity: String = _binding_identity(spec)
			if identity.is_empty() or identity in assigned:
				return false
			if spec.has("mouse") and action not in ["punch", "block"]:
				return false
			assigned.append(identity)
	return true


func _binding_identity(spec: Dictionary) -> String:
	if spec.has("key") and spec.key is int and int(spec.key) > 0 and int(spec.key) not in [KEY_ESCAPE, KEY_TAB]:
		return "key:%d" % int(spec.key)
	if spec.has("mouse") and spec.mouse is int and int(spec.mouse) in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		return "mouse:%d" % int(spec.mouse)
	return ""


func apply_bindings() -> void:
	for action: String in CONTROL_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		Input.action_release(action)
		for spec: Dictionary in bindings.get(action, []):
			var event: InputEvent
			if spec.has("key"):
				var key := InputEventKey.new()
				key.physical_keycode = int(spec.key)
				event = key
			else:
				var mouse := InputEventMouseButton.new()
				mouse.button_index = int(spec.mouse)
				event = mouse
			InputMap.action_add_event(action, event)
	bindings_changed.emit()


func binding_label(action: String) -> String:
	var labels: PackedStringArray = []
	for spec: Dictionary in bindings.get(action, []):
		if spec.has("key"):
			labels.append(OS.get_keycode_string(int(spec.key)))
		else:
			var mouse_labels := {MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse", MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5"}
			labels.append(str(mouse_labels.get(int(spec.mouse), "Mouse")))
	return " / ".join(labels)


func set_binding_from_event(action: String, event: InputEvent) -> String:
	if action not in CONTROL_ACTIONS:
		return "Unknown control."
	var spec: Dictionary = {}
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code == KEY_ESCAPE:
			return "Esc is reserved for opening and closing options."
		if code == KEY_TAB:
			return "Tab is reserved for the player scoreboard."
		spec = {"key": code}
	elif event is InputEventMouseButton:
		if action not in ["punch", "block"]:
			return "Choose a keyboard key for this control."
		spec = {"mouse": int(event.button_index)}
	var identity: String = _binding_identity(spec)
	if identity.is_empty():
		return "Choose a key or mouse button. The mouse wheel is reserved for zoom."
	for other_action: String in CONTROL_ACTIONS:
		if other_action == action:
			continue
		for existing: Dictionary in bindings.get(other_action, []):
			if _binding_identity(existing) == identity:
				return "Already used by %s. Choose another input, or change that control first." % str(CONTROL_LABELS[other_action]).to_lower()
	bindings[action] = [spec]
	apply_bindings()
	save()
	return ""


func reset_bindings() -> void:
	movement_keys = 0
	bindings = default_bindings()
	apply_bindings()
	save()
