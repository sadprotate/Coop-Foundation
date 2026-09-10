extends Control

const Arena = preload("res://scripts/combat_arena.gd")
const SessionUI = preload("res://scripts/session_ui.gd")
const Scoreboard = preload("res://scripts/scoreboard.gd")
const HealthHUD = preload("res://scripts/health_hud.gd")
const ControlsSettings = preload("res://scripts/controls_settings.gd")
const INK := Color("0b111c")
const PANEL := Color("121e2d")
const TEXT := Color("e2edf4")
const MUTED := Color("8ca3b6")
const ACCENT := Color("61e5d4")
const COLORS := [Color("61e5d4"), Color("ffbb79"), Color("a9a2ff"), Color("f28bb6")]
const TEAM_COLORS := [Color("ff8585"), Color("83baff")]
const OptionsCatalog = preload("res://scripts/gameplay_options.gd")
const GOD_FIELDS = OptionsCatalog.FIELDS

var page: String = "home"
var previous_page: String = "home"
var content: VBoxContainer
var footer: Label
var status_text: String = "Enter a shared server address to play online, or try local practice."
var status_error: bool = false
var name_field: LineEdit
var server_field: LineEdit
var code_field: LineEdit
var join_code: String = ""
var arena: Control
var session_ui: Control
var scoreboard: Control
var scoreboard_held: bool = false
var fps_label: Label
var health_hud: Control
var controls_settings: Control
var _last_local_state: Dictionary = {}
var attack_hold: bool = false
var attack_repeat_timer: float = 0.0
var completion_seen: bool = false
var focused: bool = true
var quitting: bool = false
var options_overlay: Control
var god_label: Label
var options_status: Label
var team_mode: OptionButton
var player_team: OptionButton
var god_toggle: CheckButton
var god_controls: Dictionary = {}
var syncing_options: bool = false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_quit_game)
	_build_theme()
	Net.room_changed.connect(_on_room)
	Net.state_changed.connect(_on_state)
	Net.status_changed.connect(_set_status)
	Net.notice.connect(_on_notice)
	Net.failure.connect(_on_failure)
	Net.combat_event.connect(_on_combat)
	_show_home()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		_release_controls()
		if page == "game" and not is_instance_valid(options_overlay) and (not is_instance_valid(session_ui) or not session_ui.is_modal()):
			_show_options.call_deferred()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true

func _process(delta: float) -> void:
	if is_instance_valid(fps_label):
		fps_label.visible = Prefs.show_fps and page == "game"
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
		fps_label.position = Vector2(20, 18) if Prefs.fps_position == 0 else Vector2(0, 18)
	if is_instance_valid(scoreboard):
		scoreboard.visible = scoreboard_held and page == "game" and focused and not Net.practice and not Net.room.is_empty() and (not is_instance_valid(session_ui) or not session_ui.is_modal())
	var axis := Vector2.ZERO
	var active: bool = page == "game" and focused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Net.can_control() and (not is_instance_valid(session_ui) or not session_ui.is_modal())
	if active:
		axis = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	Net.move_axis = arena.get_world_movement(axis.normalized()) if active and is_instance_valid(arena) else Vector2.ZERO
	Net.blocking = active and Input.is_action_pressed("block")
	Net.sprinting = active and Input.is_action_pressed("sprint")
	Net.crouching = active and Input.is_action_pressed("crouch")
	if is_instance_valid(arena):
		Net.facing_yaw = arena.get_facing_yaw()
		arena.set_local_input(Net.move_axis, Net.blocking, Net.sprinting, Net.crouching)
		arena.mouse_sensitivity = 0.0028 * Prefs.mouse_sensitivity
	if active and attack_hold:
		attack_repeat_timer -= delta
		if attack_repeat_timer <= 0.0:
			Net.facing_yaw = arena.get_facing_yaw()
			Net.punch()
			attack_repeat_timer = 1.0 / maxf(0.2, float(Net.god_options().get("attack_speed", 2.0)))
	else:
		attack_repeat_timer = 0.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB) and page == "game":
		scoreboard_held = event.pressed
		if is_instance_valid(scoreboard):
			scoreboard.visible = scoreboard_held and focused and not Net.practice and not session_ui.is_modal()
			if scoreboard.visible:
				scoreboard.refresh()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(controls_settings) and controls_settings.consume_event(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and event.keycode == KEY_ESCAPE:
		if is_instance_valid(session_ui) and session_ui.is_modal():
			session_ui.escape()
		elif page == "options" or is_instance_valid(options_overlay):
			_back_from_options()
		elif page in ["game", "home", "lobby"]:
			_show_options()
		get_viewport().set_input_as_handled()
		return
	if page != "game" or not focused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("interact", false) and is_instance_valid(session_ui):
		if Net.in_town():
			session_ui.talk()
		else:
			Net.pickup_sword()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jump", false):
		if Net.jump() and is_instance_valid(arena):
			arena.predict_jump()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("block", false) or event.is_action_released("block"):
		Net.blocking = event.is_action_pressed("block", false)
		Net.flush_input()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("punch", false) or event.is_action_released("punch"):
		attack_hold = event.is_action_pressed("punch", false)
		if attack_hold:
			Net.facing_yaw = arena.get_facing_yaw()
			Net.punch()
			attack_repeat_timer = 1.0 / maxf(0.2, float(Net.god_options().get("attack_speed", 2.0)))
		get_viewport().set_input_as_handled()

func _release_controls() -> void:
	scoreboard_held = false
	if is_instance_valid(scoreboard):
		scoreboard.visible = false
	Net.move_axis = Vector2.ZERO
	Net.blocking = false
	Net.sprinting = false
	Net.crouching = false
	attack_hold = false
	attack_repeat_timer = 0.0
	Net.flush_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(arena):
		arena.release_mouse()
		arena.set_local_input(Vector2.ZERO, false)

func _build_theme() -> void:
	var theme_resource := Theme.new()
	theme_resource.default_font_size = 18
	theme_resource.set_color("font_color", "Label", TEXT)
	theme_resource.set_color("font_color", "Button", TEXT)
	theme_resource.set_color("font_hover_color", "Button", Color.WHITE)
	theme_resource.set_color("font_disabled_color", "Button", Color("607488"))
	theme_resource.set_stylebox("normal", "Button", _style(Color("1b3044"), Color("304b61"), 10, 16, 13))
	theme_resource.set_stylebox("hover", "Button", _style(Color("26455b"), ACCENT, 10, 16, 13))
	theme_resource.set_stylebox("pressed", "Button", _style(Color("31576a"), ACCENT, 10, 16, 13))
	theme_resource.set_stylebox("focus", "Button", _style(Color.TRANSPARENT, ACCENT, 10, 16, 13, 2))
	theme_resource.set_stylebox("disabled", "Button", _style(Color("172331"), Color("253649"), 10, 16, 13))
	theme_resource.set_stylebox("normal", "LineEdit", _style(INK, Color("345064"), 8, 14, 13))
	theme_resource.set_stylebox("focus", "LineEdit", _style(INK, ACCENT, 8, 14, 13, 2))
	theme_resource.set_color("font_color", "LineEdit", TEXT)
	theme_resource.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme_resource.set_color("caret_color", "LineEdit", ACCENT)
	theme_resource.set_stylebox("background", "ProgressBar", _style(INK, Color("23384b"), 5, 0, 0))
	theme_resource.set_stylebox("fill", "ProgressBar", _style(ACCENT, ACCENT, 5, 0, 0))
	theme = theme_resource

func _style(color: Color, border: Color, radius: int = 12, horizontal: int = 20, vertical: int = 20, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style

func _clear(next_page: String, with_shell: bool = true) -> void:
	_release_controls()
	page = next_page
	arena = null
	health_hud = null
	session_ui = null
	scoreboard = null
	fps_label = null
	controls_settings = null
	_last_local_state.clear()
	god_label = null
	options_overlay = null
	options_status = null
	team_mode = null
	player_team = null
	god_toggle = null
	god_controls.clear()
	attack_hold = false
	attack_repeat_timer = 0.0
	footer = null
	content = null
	name_field = null
	server_field = null
	code_field = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if not with_shell:
		return
	var backdrop := ColorRect.new()
	backdrop.color = INK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 14)
	margin.add_child(shell)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	shell.add_child(header)
	_label(header, "◈", 30, ACCENT)
	_label(header, "CO-OP  /  FOUNDATION", 21, TEXT).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(header, "COMBAT 06     •     UP TO 4 PLAYERS", 14, MUTED)
	var line := HSeparator.new()
	shell.add_child(line)
	var scroller := ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	shell.add_child(scroller)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroller.add_child(content)
	footer = _label(shell, status_text, 15, Color("ffbb79") if status_error else MUTED)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.custom_minimum_size.y = 34

func _label(parent: Node, text_value: String, font_size: int = 18, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, title: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = title
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func():
		Sound.click()
		action.call()
	)
	if primary:
		button.add_theme_stylebox_override("normal", _style(Color("174c4b"), Color("3a9188"), 10, 18, 13))
	parent.add_child(button)
	return button

func _card(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL, Color("293d50"), 16, 26, 20))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return box

func _field(parent: Node, title: String, placeholder: String, value: String, limit: int = 200) -> LineEdit:
	_label(parent, title, 15, MUTED)
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.text = value
	field.max_length = limit
	parent.add_child(field)
	return field

func _show_home() -> void:
	_clear("home")
	Sound.set_context("menu")
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var menu := VBoxContainer.new()
	menu.custom_minimum_size.x = 340
	menu.add_theme_constant_override("separation", 16)
	center.add_child(menu)
	var title := _label(menu, "CO-OP FOUNDATION", 30, ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(menu, "Singleplayer", func(): Net.start_practice(), true)
	_button(menu, "Multiplayer", _show_multiplayer)
	_button(menu, "Settings", _show_options)
	_button(menu, "Quit", _quit_game)
	footer.visible = status_error

func _show_multiplayer() -> void:
	_clear("multiplayer")
	_label(content, "Multiplayer", 36)
	var menu := _card(content)
	server_field = _field(menu, "Server address", "wss://your-server.example/ws", Prefs.server_url)
	_button(menu, "SAVE SERVER", _save_server, true)
	_button(menu, "Host", func(): _show_connection(false), true)
	_button(menu, "Join", func(): _show_connection(true))
	_button(menu, "Back", _show_home)
	if Net.connecting:
		_button(menu, "Cancel connection", func():
			Net.leave()
			_set_status("Connection cancelled.")
			_show_multiplayer())

func _show_connection(joining: bool) -> void:
	_clear("join" if joining else "host")
	_label(content, "Join a room" if joining else "Host a room", 36)
	var form := _card(content)
	name_field = _field(form, "Your name", "Player name", Prefs.player_name, 20)
	if joining:
		code_field = _field(form, "Room code", "6-character room code", join_code, 6)
		code_field.text_submitted.connect(func(_value): _connect_online(true))
	_button(form, "Join room" if joining else "Create room", func(): _connect_online(joining), true).disabled = Net.connecting
	_button(form, "Back", func():
		_save_connection_fields()
		_show_multiplayer())

func _show_server() -> void:
	_clear("server")
	_label(content, "WSS Server", 36)
	var form := _card(content)
	server_field = _field(form, "Shared server address", "wss://your-server.example/ws", Prefs.server_url)
	var help := _label(form, "Use the same server address as your friends. Local testing also supports ws://.", 16, MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(form, "Save", _save_server, true)
	_button(form, "Back", _show_multiplayer)

func _valid_server_address(value: String) -> bool:
	var validator := RegEx.new()
	validator.compile("^wss?://(localhost|[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?|\\[[0-9A-Fa-f:]+\\])(?::([0-9]{1,5}))?(?:/[^\\s#]*)?$")
	var found := validator.search(value)
	if found == null:
		return false
	var port: String = found.get_string(2)
	return port.is_empty() or (int(port) >= 1 and int(port) <= 65535)

func _save_server() -> void:
	var address: String = server_field.text.strip_edges()
	if not _valid_server_address(address):
		_set_status("Enter a valid wss:// address (or ws:// for local testing), without spaces.")
		return
	Prefs.server_url = address
	Prefs.save()
	_set_status("Server address saved.")

func _save_connection_fields() -> void:
	if is_instance_valid(name_field):
		Prefs.player_name = name_field.text.strip_edges().left(20)
		if Prefs.player_name.is_empty():
			Prefs.player_name = "Player"
	if is_instance_valid(server_field):
		Prefs.server_url = server_field.text.strip_edges()
	if is_instance_valid(code_field):
		join_code = code_field.text.strip_edges().to_upper()
	Prefs.save()

func _connect_online(joining: bool) -> void:
	_save_connection_fields()
	if joining and join_code.length() != 6:
		_on_failure("Enter the six-character code from the room host.")
		return
	completion_seen = false
	var request := {"type": "join" if joining else "create", "name": Prefs.player_name}
	if joining:
		request["code"] = join_code
	Net.connect_room(Prefs.server_url, request)
	_show_multiplayer()

func _on_room(data: Dictionary) -> void:
	if data.is_empty() or str(data.get("code", "")).is_empty():
		if page != "home":
			_show_home()
		return
	if page not in ["game", "options"]:
		_show_game()
	_sync_mode_team_controls()
	_sync_god_controls()
	_refresh_session_ui()

func _show_game() -> void:
	_clear("game", false)
	Sound.set_context("menu" if Net.in_town() else "game")
	arena = Arena.new()
	arena.name = "CombatArena"
	arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(arena)
	var hud := Control.new()
	hud.name = "CombatHUD"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	health_hud = HealthHUD.new()
	health_hud.name = "PlayerHUD"
	health_hud.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_hud.offset_left = 28.0
	health_hud.offset_top = -126.0
	health_hud.offset_right = 352.0
	health_hud.offset_bottom = -28.0
	hud.add_child(health_hud)
	fps_label = Label.new()
	fps_label.name = "FPSCounter"
	fps_label.text = "FPS: 0"
	fps_label.add_theme_font_size_override("font_size", 13)
	fps_label.add_theme_color_override("font_color", Color("d3e2e8"))
	fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fps_label.position = Vector2(20, 18)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fps_label)
	session_ui = SessionUI.new()
	session_ui.name = "SessionUI"
	session_ui.modal_opened.connect(_release_controls)
	session_ui.modal_closed.connect(_resume_session_controls)
	session_ui.settings_requested.connect(_show_options)
	add_child(session_ui)
	scoreboard = Scoreboard.new()
	add_child(scoreboard)
	_on_state(Net.snapshot)
	if DisplayServer.get_name() != "headless" and focused and Net.can_control():
		_capture_session_mouse.call_deferred()
	_set_status("Single-player town" if Net.practice else "Room %s · %s" % [str(Net.room.get("code", "")), _mode_title()])

func _on_state(data: Dictionary) -> void:
	if page not in ["game", "options"] or data.is_empty():
		return
	if data.has("mode"):
		Net.room["mode"] = data.mode
	if data.has("god_options"):
		Net.room["god_options"] = data.god_options
	if is_instance_valid(arena):
		var visual := data.duplicate(true)
		for p: Dictionary in visual.get("players", []):
			for member: Dictionary in Net.room.get("players", []):
				if p.get("id") == member.get("id"):
					p["name"] = member.get("name", "Player")
		arena.update_snapshot(visual, Net.player_id)
	var player := Net.local_player()
	if not player.is_empty():
		var same_round: bool = _last_local_state.get("round_id", -1) == data.get("round_id", 0)
		if same_round and not bool(_last_local_state.get("grounded", true)) and bool(player.get("grounded", true)) and float(player.get("health", 0)) > 0.0 and float(_last_local_state.get("health", 0)) > 0.0:
			Sound.landing(clampf(absf(float(_last_local_state.get("vy", -7.0))) / 7.0, 0.4, 1.5))
		_last_local_state = player.duplicate()
		_last_local_state["round_id"] = data.get("round_id", 0)
	if is_instance_valid(health_hud):
		var color: Color = TEAM_COLORS[_local_party()] if Net.room.get("mode", "ffa") == "teams" else ACCENT
		health_hud.update_health(player, Net.in_town() or bool(Net.god_options().get("god_mode", false)), color)
	_sync_mode_team_controls()
	_sync_god_controls()
	_refresh_session_ui()

func _refresh_session_ui() -> void:
	if not is_instance_valid(session_ui):
		return
	var phase: String = str(Net.room.get("match", {}).get("phase", "town"))
	if phase in ["ready_check", "round_end", "victory"] and is_instance_valid(options_overlay):
		_back_from_options()
	session_ui.refresh()
	Sound.set_context("menu" if Net.in_town() else "game")

func _resume_session_controls() -> void:
	_capture_session_mouse.call_deferred()

func _capture_session_mouse() -> void:
	if page == "game" and focused and not is_instance_valid(options_overlay) and Net.can_control() and is_instance_valid(arena) and DisplayServer.get_name() != "headless" and (not is_instance_valid(session_ui) or not session_ui.is_modal()):
		arena.capture_mouse()

func _on_combat(data: Dictionary) -> void:
	if page not in ["game", "options"]:
		return
	if is_instance_valid(arena):
		arena.handle_combat_event(data)
	Sound.combat_event(data)

func _show_options() -> void:
	if page == "game":
		_open_game_options()
		return
	if page == "home":
		_save_connection_fields()
	previous_page = page
	_clear("options")
	_build_options(content, false)


func _option_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title.replace(" ", "") + "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	tabs.set_tab_title(tabs.get_tab_count() - 1, title)
	var box := VBoxContainer.new()
	box.name = title.replace(" ", "") + "Settings"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	return box


func _build_options(parent: Node, in_game: bool) -> void:
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 14)
	parent.add_child(heading)
	_label(heading, "Options", 34).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if in_game:
		_button(heading, "Resume", _back_from_options, true)
	options_status = _label(parent, status_text if status_error else "", 14, Color("ffbb79") if status_error else MUTED)
	options_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tabs := TabContainer.new()
	tabs.name = "OptionsTabs"
	tabs.custom_minimum_size = Vector2(0, 450)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(tabs)

	var audio_tab := _option_tab(tabs, "Audio")
	_label(audio_tab, "AUDIO", 15, ACCENT)
	_volume_row(audio_tab, "Master volume", Prefs.master, func(value: float): Prefs.master = value)
	_volume_row(audio_tab, "Music", Prefs.music, func(value: float): Prefs.music = value)
	_volume_row(audio_tab, "Sound effects", Prefs.effects, func(value: float): Prefs.effects = value)
	_button(audio_tab, "Test sound", func(): Sound.success())

	var graphics_tab := _option_tab(tabs, "Graphics")
	_label(graphics_tab, "GRAPHICS", 15, ACCENT)
	var fullscreen := CheckButton.new()
	fullscreen.name = "Graphics_Fullscreen"
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = Prefs.fullscreen
	graphics_tab.add_child(fullscreen)
	fullscreen.toggled.connect(func(enabled: bool):
		Prefs.fullscreen = enabled
		Prefs.apply_display()
		Prefs.save()
	)
	var vsync := CheckButton.new()
	vsync.name = "Graphics_VSync"
	vsync.text = "VSync (reduce screen tearing)"
	vsync.button_pressed = Prefs.vsync
	graphics_tab.add_child(vsync)
	vsync.toggled.connect(func(enabled: bool):
		Prefs.vsync = enabled
		Prefs.apply_display()
		Prefs.save()
	)
	var fps := CheckButton.new()
	fps.name = "Graphics_ShowFPS"
	fps.text = "Show FPS"
	fps.button_pressed = Prefs.show_fps
	graphics_tab.add_child(fps)
	fps.toggled.connect(func(enabled: bool): Prefs.show_fps = enabled; Prefs.save())
	var fps_position := OptionButton.new()
	fps_position.name = "Graphics_FPSPosition"
	for item: String in ["Top Left", "Top Right", "Bottom Left", "Bottom Right"]: fps_position.add_item(item)
	fps_position.select(Prefs.fps_position)
	graphics_tab.add_child(fps_position)
	fps_position.item_selected.connect(func(index: int): Prefs.fps_position = index; Prefs.save())

	var gameplay_tab := _option_tab(tabs, "Gameplay")
	_label(gameplay_tab, "GAMEPLAY", 15, ACCENT)
	controls_settings = ControlsSettings.new()
	controls_settings.name = "ControlsSettings"
	gameplay_tab.add_child(controls_settings)
	_label(gameplay_tab, "Mouse sensitivity", 16, MUTED)
	var sensitivity := HSlider.new()
	sensitivity.name = "Gameplay_MouseSensitivity"
	sensitivity.min_value = 0.25
	sensitivity.max_value = 3.0
	sensitivity.step = 0.05
	sensitivity.value = Prefs.mouse_sensitivity
	sensitivity.custom_minimum_size.y = 28
	gameplay_tab.add_child(sensitivity)
	var sensitivity_value := _label(gameplay_tab, "%.2fx" % Prefs.mouse_sensitivity, 13, MUTED)
	sensitivity.value_changed.connect(func(value: float):
		Prefs.mouse_sensitivity = value
		sensitivity_value.text = "%.2fx" % value
		Prefs.save()
	)
	var camera_distance := HSlider.new()
	camera_distance.name = "Gameplay_CameraDistance"
	camera_distance.min_value = 8.0
	camera_distance.max_value = 20.0
	camera_distance.step = 0.1
	camera_distance.value = Prefs.camera_distance
	gameplay_tab.add_child(camera_distance)
	camera_distance.value_changed.connect(func(value: float): Prefs.camera_distance = value; Prefs.save())
	var invert_x := CheckButton.new()
	invert_x.name = "Gameplay_InvertX"
	invert_x.text = "Invert X-axis"
	invert_x.button_pressed = Prefs.invert_x
	gameplay_tab.add_child(invert_x)
	invert_x.toggled.connect(func(enabled: bool): Prefs.invert_x = enabled; Prefs.save())
	var invert_y := CheckButton.new()
	invert_y.name = "Gameplay_InvertY"
	invert_y.text = "Invert Y-axis"
	invert_y.button_pressed = Prefs.invert_y
	gameplay_tab.add_child(invert_y)
	invert_y.toggled.connect(func(enabled: bool): Prefs.invert_y = enabled; Prefs.save())
	# Match selection remains available through the Old Man in Town, not normal settings.

	var god_tab := _option_tab(tabs, "God options")
	_label(god_tab, "GOD OPTIONS", 15, Color("ffcf78"))
	god_label = _label(god_tab, "God mode: " + ("ON" if bool(Net.god_options().get("god_mode", false)) else "OFF"), 14, MUTED)
	god_label.name = "GodStatus"
	_add_god_controls(god_tab, _can_edit_rules())
	tabs.current_tab = 2 if in_game else 0
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	parent.add_child(bottom)
	if in_game:
		_button(bottom, "Resume", _back_from_options, true)
		if not Net.in_town() and Net.player_id == str(Net.room.get("host_id", "")):
			_button(bottom, "Restart match", func(): Net.send({"type": "restart"}))
			_button(bottom, "Return to town", func(): Net.send({"type": "lobby"}))
		_button(bottom, "Main menu", _leave_room)
	else:
		_button(bottom, "Back", _back_from_options, true)


func _add_mode_team_controls(parent: Node) -> void:
	var match_card := _card(parent)
	match_card.name = "GameplayMatchType"
	_label(match_card, "MATCH TYPE", 15, ACCENT)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	match_card.add_child(mode_row)
	_label(mode_row, "Mode", 15, MUTED).custom_minimum_size.x = 110
	team_mode = OptionButton.new()
	team_mode.name = "Gameplay_Mode"
	team_mode.add_item("Free-for-all")
	team_mode.set_item_metadata(0, "ffa")
	team_mode.add_item("Red versus Blue  /  2v2")
	team_mode.set_item_metadata(1, "teams")
	team_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(team_mode)
	team_mode.item_selected.connect(func(index: int):
		Net.set_mode(str(team_mode.get_item_metadata(index)))
	)
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 12)
	match_card.add_child(team_row)
	_label(team_row, "Your team", 15, MUTED).custom_minimum_size.x = 110
	player_team = OptionButton.new()
	player_team.name = "Gameplay_Team"
	player_team.add_item("Red")
	player_team.add_item("Blue")
	player_team.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_row.add_child(player_team)
	player_team.item_selected.connect(func(index: int):
		Net.set_party(index)
	)
	_label(match_card, "Choose your team in town. Match type is set by the host. Teams stay fixed during a match.", 13, MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sync_mode_team_controls()


func _add_god_controls(parent: Node, enabled: bool) -> void:
	god_toggle = CheckButton.new()
	god_toggle.name = "God_god_mode"
	god_toggle.text = "Battle God mode  ·  damage off for every character"
	god_toggle.button_pressed = bool(Net.god_options().get("god_mode", false))
	god_toggle.disabled = not enabled
	parent.add_child(god_toggle)
	god_toggle.toggled.connect(func(value: bool):
		if not syncing_options and _can_edit_rules():
			Net.set_god_options({"god_mode": value})
	)
	for category: String in OptionsCatalog.GROUPS:
		_label(parent, category, 15, ACCENT)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 28)
		grid.add_theme_constant_override("v_separation", 8)
		parent.add_child(grid)
		for spec: Array in GOD_FIELDS:
			if str(spec[0]) not in OptionsCatalog.GROUPS[category]:
				continue
			var key: String = str(spec[0])
			var row := HBoxContainer.new()
			row.name = "GodRow_" + key
			row.add_theme_constant_override("separation", 8)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(row)
			_label(row, str(spec[1]), 13, MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if key == "fall_damage":
				var toggle := CheckButton.new()
				toggle.name = "God_fall_damage"
				toggle.button_pressed = bool(Net.god_options().get(key, false))
				toggle.disabled = not enabled
				row.add_child(toggle)
				god_controls[key] = toggle
				toggle.toggled.connect(func(on: bool):
					if not syncing_options and _can_edit_rules():
						Net.set_god_options({"fall_damage": on})
				)
				continue
			var value := SpinBox.new()
			value.name = "God_" + key
			value.min_value = float(spec[2])
			value.max_value = float(spec[3])
			value.step = float(spec[4])
			value.value = float(Net.god_options().get(key, spec[5]))
			value.suffix = str(spec[6])
			value.allow_greater = false
			value.allow_lesser = false
			value.custom_minimum_size.x = 150
			value.get_line_edit().add_theme_font_size_override("font_size", 16)
			value.get_line_edit().add_theme_stylebox_override("normal", _style(INK, Color("345064"), 8, 10, 6))
			value.get_line_edit().add_theme_stylebox_override("focus", _style(INK, ACCENT, 8, 10, 6, 2))
			value.editable = enabled
			value.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
			row.add_child(value)
			god_controls[key] = value
			var field_key := key
			value.value_changed.connect(func(new_value: float):
				if not syncing_options and _can_edit_rules():
					Net.set_god_options({field_key: new_value})
			)
	var reset := _button(parent, "Reset God options to defaults", func(): Net.reset_god_options())
	reset.name = "God_Reset"
	reset.disabled = not enabled


func _open_game_options() -> void:
	if is_instance_valid(options_overlay):
		return
	previous_page = "game"
	_release_controls()
	page = "options"
	options_overlay = Control.new()
	options_overlay.name = "OptionsOverlay"
	options_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	options_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(options_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.035, 0.055, 0.76)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	options_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "OptionsPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24.0
	panel.offset_top = 24.0
	panel.offset_right = -24.0
	panel.offset_bottom = -24.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _style(Color("101c2a"), Color("385467"), 16, 24, 18))
	options_overlay.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	scroll.add_child(inner)
	_build_options(inner, true)
	_sync_god_controls()


func _sync_mode_team_controls() -> void:
	if is_instance_valid(team_mode):
		team_mode.disabled = not _can_edit_rules() or Net.room.get("phase", "") != "lobby"
		var current_mode: String = str(Net.room.get("mode", "ffa")).to_lower()
		var wanted_mode: int = 1 if current_mode == "teams" else 0
		if team_mode.selected != wanted_mode:
			team_mode.select(wanted_mode)
	if is_instance_valid(player_team):
		var party: int = _local_party()
		if player_team.selected != party:
			player_team.select(party)
		player_team.add_theme_color_override("font_color", TEAM_COLORS[party])
		player_team.disabled = Net.room.get("phase", "") != "lobby"


func _local_party() -> int:
	for member: Dictionary in Net.room.get("players", []):
		if str(member.get("id", "")) == Net.player_id:
			return clampi(int(member.get("party", 0)), 0, 1)
	var local := Net.local_player()
	return clampi(int(local.get("party", 0)), 0, 1)


func _can_edit_rules() -> bool:
	return not Net.room.is_empty() and (Net.practice or Net.player_id == str(Net.room.get("host_id", "")))

func _sync_god_controls() -> void:
	if god_controls.is_empty() and not is_instance_valid(god_toggle):
		return
	var rules := Net.god_options()
	var editable := _can_edit_rules()
	syncing_options = true
	if is_instance_valid(god_toggle):
		god_toggle.set_pressed_no_signal(bool(rules.get("god_mode", false)))
		god_toggle.disabled = not editable
	for key: String in god_controls:
		if not is_instance_valid(god_controls[key]):
			continue
		var control: Control = god_controls[key]
		if control is CheckButton:
			control.set_pressed_no_signal(bool(rules.get(key, false)))
			control.disabled = not editable
		elif control is SpinBox:
			control.editable = editable
			control.mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
			if not control.get_line_edit().has_focus():
				control.set_value_no_signal(float(rules.get(key, control.value)))
	var reset := find_child("God_Reset", true, false) as Button
	if is_instance_valid(reset):
		reset.disabled = not editable
	if is_instance_valid(god_label):
		god_label.text = ("Host controls" if editable else "View only · controlled by the host") + "  ·  God mode " + ("ON" if bool(rules.get("god_mode", false)) else "OFF")
	syncing_options = false


func _mode_title() -> String:
	return "RED vs BLUE  ·  2v2" if str(Net.room.get("mode", "ffa")).to_lower() == "teams" else "FREE-FOR-ALL"


func _format_health(value: float) -> String:
	var formatted := String.num(value, 2)
	while formatted.contains(".") and formatted.ends_with("0"):
		formatted = formatted.left(formatted.length() - 1)
	if formatted.ends_with("."):
		formatted = formatted.left(formatted.length() - 1)
	return formatted

func _volume_row(parent: Node, title: String, value: float, setter: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	parent.add_child(row)
	_label(row, title, 18).custom_minimum_size.x = 135
	var slider := HSlider.new()
	var audio_key := title.to_lower().replace(" ", "_")
	if title == "Master volume":
		slider.name = "Audio_Master"
	elif title == "Music":
		slider.name = "Audio_Music"
	elif title == "Sound effects":
		slider.name = "Audio_Effects"
	else:
		slider.name = "Audio_" + audio_key
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = roundf(value * 100)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 120
	slider.custom_minimum_size.y = 32
	row.add_child(slider)
	var amount := _label(row, "%d%%" % int(slider.value), 18, ACCENT)
	amount.custom_minimum_size.x = 55
	slider.value_changed.connect(func(new_value: float):
		setter.call(new_value / 100.0)
		amount.text = "%d%%" % int(new_value)
		Sound.apply()
		Prefs.save()
	)

func _back_from_options() -> void:
	if is_instance_valid(options_overlay):
		if is_instance_valid(controls_settings):
			controls_settings.cancel_capture()
		controls_settings = null
		options_overlay.queue_free()
		options_overlay = null
		god_controls.clear()
		god_toggle = null
		god_label = null
		team_mode = null
		player_team = null
		options_status = null
		syncing_options = false
		page = "game"
		if is_instance_valid(arena) and DisplayServer.get_name() != "headless" and focused and Net.can_control() and (not is_instance_valid(session_ui) or not session_ui.is_modal()):
			_capture_session_mouse.call_deferred()
		return
	if Net.room.is_empty():
		_show_home()
	else:
		_show_game()

func _leave_room() -> void:
	Net.leave()
	completion_seen = false
	_set_status("You left the room. Use the code to rejoin while it remains open in the lobby.")
	_show_home()

func _quit_game() -> void:
	if quitting:
		return
	quitting = true
	Net.leave()
	Sound.shutdown()
	# Let the audio thread release active playback before the engine shuts down.
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()

func _on_notice(message: String) -> void:
	if is_instance_valid(session_ui):
		session_ui.show_notice(message)

func _set_status(message: String) -> void:
	status_text = message
	status_error = false
	if is_instance_valid(footer):
		footer.text = message
		footer.add_theme_color_override("font_color", MUTED)
	if is_instance_valid(options_status):
		options_status.text = message

func _on_failure(message: String) -> void:
	status_text = message
	status_error = true
	if page == "home":
		_show_home()
	elif is_instance_valid(footer):
		footer.text = message
		footer.add_theme_color_override("font_color", Color("ffbb79"))
	if is_instance_valid(options_status):
		options_status.text = message
		options_status.add_theme_color_override("font_color", Color("ffbb79"))
	if page == "game":
		_show_options.call_deferred()
