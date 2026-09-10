extends PanelContainer

var rows: Array[Dictionary] = []
var _content: VBoxContainer
var _signature: String = ""

func _ready() -> void:
	name = "PlayerScoreboard"
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -370
	offset_right = 370
	offset_top = 110
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.062, 0.086, 0.97)
	style.border_color = Color("877353")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	add_theme_stylebox_override("panel", style)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	visible = false

func _process(_delta: float) -> void:
	if visible:
		refresh()

func refresh() -> void:
	rows = build_rows(Net.room, Net.snapshot, Net.player_id)
	var signature: String = JSON.stringify([Net.in_town(), rows])
	if signature == _signature:
		return
	_signature = signature
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_label(_content, "TOWN PLAYERS" if Net.in_town() else "MATCH SCOREBOARD", 26)
	if not Net.in_town():
		_label(_content, "Ranked by rounds won, then round knockouts" + (" · team totals" if Net.room.get("mode") == "teams" else ""), 15)
	var grid := GridContainer.new()
	grid.columns = 2 if Net.in_town() else 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 16)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(grid)
	var headings: Array = ["PLAYER", "PING"] if Net.in_town() else ["PLAYER", "ROUNDS WON", "ROUND KO", "PING"]
	for heading: String in headings:
		_label(grid, heading, 14)
	for row: Dictionary in rows:
		var title: String = str(row.name) + (" (you)" if row.local else "")
		if Net.room.get("mode") == "teams":
			title += " · " + ("Red" if int(row.party) == 0 else "Blue")
		var label := _label(grid, title, 18)
		label.tooltip_text = title
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.custom_minimum_size.x = 245
		if row.local:
			label.modulate = Color("61e5d4")
		if not Net.in_town():
			_label(grid, str(row.wins), 18)
			_label(grid, str(row.knockouts), 18)
		_label(grid, "—" if row.ping == null else "%d ms" % int(row.ping), 18)

static func build_rows(room: Dictionary, snapshot: Dictionary, local_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var match_data: Dictionary = room.get("match", {})
	for member: Dictionary in room.get("players", []):
		var id: String = str(member.get("id", ""))
		var ping: Variant = member.get("ping_ms")
		for state: Dictionary in snapshot.get("players", []):
			if state.get("id") == id:
				ping = state.get("ping_ms", ping)
		var score_id: String = ("red" if int(member.get("party", 0)) == 0 else "blue") if room.get("mode") == "teams" else id
		result.append({"id": id, "name": str(member.get("name", "Player")), "local": id == local_id,
			"party": int(member.get("party", 0)), "ping": ping,
			"wins": int(match_data.get("round_wins", {}).get(score_id, 0)),
			"knockouts": int(match_data.get("round_scores", {}).get(score_id, 0))})
	if room.get("zone") == "arena":
		result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.wins != b.wins:
				return a.wins > b.wins
			if a.knockouts != b.knockouts:
				return a.knockouts > b.knockouts
			return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return result

func _label(parent: Node, value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
