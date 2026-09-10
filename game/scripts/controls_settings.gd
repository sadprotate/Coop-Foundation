extends VBoxContainer

## The parent calls consume_event() before its own input handling so a remap
## never triggers gameplay or closes the options menu.
var waiting_action: String = ""
var binding_buttons: Dictionary = {}
var feedback: Label


func _ready() -> void:
	name = "ControlsSettings"
	add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "CONTROLS"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("5ce0bf"))
	add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	for action: String in Prefs.CONTROL_ACTIONS:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		grid.add_child(row)
		var label := Label.new()
		label.text = str(Prefs.CONTROL_LABELS[action])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 14)
		row.add_child(label)
		var button := Button.new()
		button.name = "Bind_" + action
		button.custom_minimum_size = Vector2(145, 36)
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_begin_capture.bind(action))
		row.add_child(button)
		binding_buttons[action] = button
	var reset := Button.new()
	reset.name = "Bindings_Reset"
	reset.text = "Reset controls"
	reset.custom_minimum_size.y = 36
	reset.add_theme_font_size_override("font_size", 14)
	reset.pressed.connect(func():
		cancel_capture()
		Prefs.reset_bindings()
		_set_feedback("Default controls restored.", false)
	)
	grid.add_child(reset)
	feedback = Label.new()
	feedback.name = "Bindings_Feedback"
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 13)
	feedback.custom_minimum_size.y = 20
	add_child(feedback)
	Prefs.bindings_changed.connect(_refresh_labels)
	_refresh_labels()


func _begin_capture(action: String) -> void:
	waiting_action = action
	_refresh_labels()
	_set_feedback("Press a key%s for %s. Esc cancels." % [" or mouse button" if action in ["punch", "block"] else "", str(Prefs.CONTROL_LABELS[action]).to_lower()], false)
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()


func is_capturing() -> bool:
	return not waiting_action.is_empty()


func consume_event(event: InputEvent) -> bool:
	if not is_capturing():
		return false
	if not is_visible_in_tree():
		cancel_capture()
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			cancel_capture()
			return true
		_capture(event)
	elif event is InputEventMouseButton and event.pressed:
		_capture(event)
	return true


func _capture(event: InputEvent) -> void:
	var action: String = waiting_action
	var problem: String = Prefs.set_binding_from_event(action, event)
	if not problem.is_empty():
		_set_feedback(problem + " Esc cancels.", true)
		return
	waiting_action = ""
	_refresh_labels()
	_set_feedback("%s set to %s." % [Prefs.CONTROL_LABELS[action], Prefs.binding_label(action)], false)


func cancel_capture() -> void:
	if waiting_action.is_empty():
		return
	waiting_action = ""
	_refresh_labels()
	_set_feedback("Binding unchanged.", false)


func _refresh_labels() -> void:
	for action: String in binding_buttons:
		var button: Button = binding_buttons[action]
		button.text = "Press an input…" if action == waiting_action else Prefs.binding_label(action)


func _set_feedback(message: String, failed: bool) -> void:
	if feedback == null:
		return
	feedback.text = message
	feedback.add_theme_color_override("font_color", Color("ffa795") if failed else Color("a6b6c8"))
