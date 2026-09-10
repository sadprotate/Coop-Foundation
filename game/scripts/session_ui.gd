extends Control

signal modal_opened
signal modal_closed
signal settings_requested

var dialog_kind: String = ""
var panel: PanelContainer
var prompt: Label
var match_label: Label
var match_panel: PanelContainer
var countdown: Label
var roster: Label
var ready_button: Button
var latest: Dictionary = {}
var _host_when_built: String = ""
var notice_panel: PanelContainer
var notice_label: Label
var notice_time_left: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prompt = Label.new()
	prompt.name = "TalkPrompt"
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -180
	prompt.offset_right = 180
	prompt.offset_top = -86
	prompt.offset_bottom = -46
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 22)
	prompt.add_theme_color_override("font_outline_color", Color("15202b"))
	prompt.add_theme_constant_override("outline_size", 8)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)
	match_panel = PanelContainer.new()
	match_panel.name = "MatchHUD"
	match_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	match_panel.offset_left = -280
	match_panel.offset_right = 280
	match_panel.offset_top = 20
	match_panel.add_theme_stylebox_override("panel", _style())
	match_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(match_panel)
	match_label = _label(match_panel, "", 17)
	match_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_panel = PanelContainer.new()
	notice_panel.name = "SessionNotice"
	notice_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notice_panel.offset_left = -280
	notice_panel.offset_right = 280
	notice_panel.offset_top = 100
	notice_panel.add_theme_stylebox_override("panel", _style())
	notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_panel.visible = false
	add_child(notice_panel)
	notice_label = _label(notice_panel, "", 17)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh()

func _process(delta: float) -> void:
	notice_time_left = maxf(0.0, notice_time_left - delta)
	if is_instance_valid(notice_panel):
		notice_panel.visible = notice_time_left > 0.0 and not is_modal()
	if is_instance_valid(prompt):
		var objective: Dictionary = latest.get("objective", latest.get("match", {}).get("objective", {}))
		var player: Dictionary = Net.local_player()
		var near_sword: bool = bool(objective.get("enabled", false)) and bool(objective.get("sword_accessible", false)) and str(objective.get("sword_owner", "")).is_empty() and Vector2(float(player.get("x", 0)) - float(objective.get("sword_x", 0)), float(player.get("z", 0)) - float(objective.get("sword_z", 0))).length() <= float(Net.god_options().get("sword_pickup_range", 2.2))
		var interact_label := Prefs.binding_label("interact")
		prompt.text = "%s  —  Grab" % interact_label if near_sword and not Net.in_town() else "%s  —  Talk" % interact_label
		prompt.visible = not is_modal() and ((Net.in_town() and Net.room.get("phase") == "lobby" and Net.near_old_man()) or near_sword) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func show_notice(message: String) -> void:
	if is_instance_valid(notice_label):
		notice_label.text = message
		notice_time_left = 5.0

func refresh() -> void:
	latest = Net.room.get("match", {})
	var phase: String = str(latest.get("phase", "town"))
	var forced: String = "ready" if phase == "ready_check" else "round_end" if phase == "round_end" else "victory" if phase == "victory" else ""
	if forced.is_empty() and dialog_kind == "npc" and not Net.near_old_man():
		close_dialog()
	if not forced.is_empty() and (forced != dialog_kind or _host_when_built != str(Net.room.get("host_id", ""))):
		_open(forced)
	elif forced.is_empty() and dialog_kind == "npc" and Net.in_town() and _host_when_built != str(Net.room.get("host_id", "")):
		_open("npc")
	elif forced.is_empty() and not dialog_kind.is_empty() and (dialog_kind != "npc" or not Net.in_town()):
		close_dialog()
	if is_instance_valid(match_panel):
		match_panel.visible = not Net.in_town() and phase in ["countdown", "round", "overtime"]
		if phase == "countdown":
			match_label.text = "GET READY\n%d" % maxi(0, ceili(float(latest.get("countdown_time_left", 0))))
			return
		if float(latest.get("fight_time_left", 0.0)) > 0.0:
			match_label.text = "FIGHT!"
			return
		var seconds: int = maxi(0, ceili(float(latest.get("time_left", 150))))
		var time_text: String = "OVERTIME" if phase == "overtime" else "%02d:%02d" % [seconds / 60, seconds % 60]
		var score_lines: PackedStringArray = []
		for entry: Dictionary in latest.get("score_entries", []):
			score_lines.append("%s  %d" % [str(entry.get("name", "Player")).left(16), int(entry.get("knockouts", 0))])
		match_label.text = "ROUND %d / %d     %s\n%s" % [int(latest.get("round_number", 1)), int(latest.get("total_rounds", 10)), time_text, "  ·  ".join(score_lines)]
	if dialog_kind == "ready" and is_instance_valid(countdown):
		countdown.text = "%d seconds" % maxi(0, ceili(float(latest.get("ready_time_left", 0))))
		var lines: PackedStringArray = []
		for player: Dictionary in Net.room.get("players", []):
			lines.append("%s   —   %s" % [str(player.get("name", "Player")), "READY" if bool(player.get("ready", false)) else "NOT READY"])
			if player.get("id") == Net.player_id and is_instance_valid(ready_button):
				ready_button.disabled = bool(player.get("ready", false))
				ready_button.text = "READY ✓" if ready_button.disabled else "READY"
		roster.text = "\n".join(lines)
	elif dialog_kind in ["round_end", "victory"] and is_instance_valid(countdown):
		var next_text: String = "Next round in %d"
		if dialog_kind == "victory":
			next_text = "Returning to town in %d"
		elif int(latest.get("round_number", 0)) >= int(latest.get("total_rounds", 10)):
			next_text = "Match results in %d"
		countdown.text = next_text % maxi(0, ceili(float(latest.get("transition_time_left", 0))))

func is_modal() -> bool:
	return not dialog_kind.is_empty()

func talk() -> void:
	if Net.in_town() and Net.room.get("phase") == "lobby" and Net.near_old_man():
		_open("npc")

func escape() -> void:
	if dialog_kind == "npc":
		close_dialog()

func close_dialog() -> void:
	if is_instance_valid(panel):
		remove_child(panel)
		panel.queue_free()
	panel = null
	countdown = null
	roster = null
	ready_button = null
	dialog_kind = ""
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_closed.emit()

func _open(kind: String) -> void:
	if is_instance_valid(panel):
		remove_child(panel)
		panel.queue_free()
	dialog_kind = kind
	_host_when_built = str(Net.room.get("host_id", ""))
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel = PanelContainer.new()
	panel.name = "SessionDialog"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -310
	panel.offset_right = 310
	panel.offset_top = -220
	panel.offset_bottom = 220
	panel.add_theme_stylebox_override("panel", _style())
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var host: bool = Net.player_id == Net.room.get("host_id", "")
	match kind:
		"npc":
			_label(box, "THE OLD MAN", 15, Color("e5c27c"))
			_label(box, "Welcome, traveller.", 32)
			_label(box, "You are safe within these walls. Gather your party when you are ready for battle.", 18)
			_label(box, "Single player" if Net.practice else "Town code: " + str(Net.room.get("code", "")), 16, Color("a5b9c8"))
			if host:
				_button(box, "START BATTLE", func(): Net.send({"type": "start"}), "StartBattle")
			else:
				_label(box, "The host will call everyone when it is time to begin.", 16, Color("a5b9c8"))
			_button(box, "Match, teams & settings", func():
				close_dialog()
				settings_requested.emit(), "TownSettings")
			_button(box, "Back", close_dialog, "CloseTalk")
		"ready":
			_label(box, "BATTLE STARTING", 31, Color("e5c27c"))
			_label(box, "READY?", 24)
			countdown = _label(box, "", 22, Color("78d8e2"))
			roster = _label(box, "", 18)
			ready_button = _button(box, "READY", func(): Net.send({"type": "ready", "ready": true}), "ConfirmReady")
			if host:
				_button(box, "Cancel battle start", func(): Net.send({"type": "cancel_start"}), "CancelReadyCheck")
		"round_end":
			_label(box, "ROUND COMPLETE", 28, Color("e5c27c"))
			var winner: String = str(latest.get("round_winner", ""))
			for entry: Dictionary in latest.get("score_entries", []):
				if str(entry.get("id", "")) == winner:
					winner = str(entry.get("name", winner))
			_label(box, winner, 30)
			countdown = _label(box, "", 18)
		"victory":
			_label(box, "WINNER!!", 42, Color("e5c27c"))
			var winners: PackedStringArray = []
			for winner: Variant in latest.get("winner_names", []):
				winners.append(str(winner))
			_label(box, " & ".join(winners), 28)
			if winners.size() > 1:
				_label(box, "Joint winners — equal rounds won", 17, Color("a5b9c8"))
			countdown = _label(box, "", 18)
	modal_opened.emit()

func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.062, 0.086, 0.96)
	style.border_color = Color("877353")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	return style

func _label(parent: Node, value: String, font_size: int, color: Color = Color("edf2ed")) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, action: Callable, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = value
	button.custom_minimum_size.y = 46
	button.pressed.connect(func():
		Sound.click()
		action.call())
	parent.add_child(button)
	return button
