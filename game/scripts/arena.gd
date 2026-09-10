extends Control
class_name CoopArena

## A presentation-only view of the authoritative shared level.
## All movement and completion decisions come from server snapshots.
const WORLD_SIZE := Vector2(1000.0, 620.0)
const PLAYER_COLORS: Array[Color] = [
	Color("61e5d4"), Color("ffbb79"), Color("a9a2ff"), Color("f28bb6")
]
const INK := Color("0c1420")
const FLOOR := Color("111f2d")
const LINE := Color("253a4b")
const MUTED := Color("7690a3")
const TEXT := Color("d9e8ee")
const CYAN := Color("61e5d4")

var snapshot: Dictionary = {}
var local_id: String = ""
var smooth_positions: Dictionary = {}
var show_names: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	queue_redraw()


func update_snapshot(data: Dictionary, my_id: String) -> void:
	snapshot = data
	local_id = my_id
	var present: Dictionary = {}
	for player: Dictionary in snapshot.get("players", []):
		var player_id := str(player.get("id", ""))
		present[player_id] = true
		if not smooth_positions.has(player_id):
			smooth_positions[player_id] = _player_position(player)
	for player_id: String in smooth_positions.keys():
		if not present.has(player_id):
			smooth_positions.erase(player_id)
	queue_redraw()


func _process(delta: float) -> void:
	var blend: float = 1.0 - exp(-20.0 * delta)
	for player: Dictionary in snapshot.get("players", []):
		var player_id := str(player.get("id", ""))
		var target := _player_position(player)
		var current: Vector2 = smooth_positions.get(player_id, target)
		# Large jumps are level resets, so they should not glide across the floor.
		smooth_positions[player_id] = target if current.distance_to(target) > 260.0 else current.lerp(target, blend)
	queue_redraw()


func _player_position(player: Dictionary) -> Vector2:
	return Vector2(float(player.get("x", 500.0)), float(player.get("y", 310.0)))


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	var world_scale: float = maxf(0.001, minf((size.x - 24.0) / WORLD_SIZE.x, (size.y - 24.0) / WORLD_SIZE.y))
	var origin: Vector2 = (size - WORLD_SIZE * world_scale) * 0.5
	draw_set_transform(origin, 0.0, Vector2.ONE * world_scale)
	_draw_floor()
	var pad_index: int = 0
	for pad: Dictionary in snapshot.get("pads", []):
		_draw_pad(pad, pad_index)
		pad_index += 1
	_draw_progress()
	for player: Dictionary in snapshot.get("players", []):
		_draw_player(player)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_floor() -> void:
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), FLOOR)
	for x: int in range(40, 1000, 40):
		var color := Color(0.27, 0.39, 0.48, 0.11 if x % 200 else 0.20)
		draw_line(Vector2(x, 0), Vector2(x, 620), color, 1.0)
	for y: int in range(40, 620, 40):
		var color := Color(0.27, 0.39, 0.48, 0.11 if y % 200 else 0.20)
		draw_line(Vector2(0, y), Vector2(1000, y), color, 1.0)
	draw_rect(Rect2(0, 0, 1000, 620), LINE, false, 2.0)
	draw_rect(Rect2(23, 23, 954, 574), Color(0.26, 0.42, 0.51, 0.23), false, 1.0)
	for corner: Vector2 in [Vector2(0, 0), Vector2(1000, 0), Vector2(0, 620), Vector2(1000, 620)]:
		var inward := Vector2(1.0 if corner.x == 0 else -1.0, 1.0 if corner.y == 0 else -1.0)
		draw_line(corner, corner + Vector2(30.0 * inward.x, 0), MUTED, 3.0)
		draw_line(corner, corner + Vector2(0, 30.0 * inward.y), MUTED, 3.0)
	# Subtle center marks make position changes easy to read at a glance.
	var center := WORLD_SIZE * 0.5
	draw_arc(center, 76.0, 0, TAU, 64, Color(0.30, 0.45, 0.54, 0.13), 1.0, true)
	draw_line(center - Vector2(8, 0), center + Vector2(8, 0), LINE, 1.0)
	draw_line(center - Vector2(0, 8), center + Vector2(0, 8), LINE, 1.0)
	_label("SHARED TEST LEVEL  /  01", Vector2(42, 50), 13, MUTED)
	_label("1000 × 620", Vector2(840, 50), 12, Color("4c6577"))


func _draw_pad(pad: Dictionary, index: int) -> void:
	var center := Vector2(float(pad.get("x", 500.0)), float(pad.get("y", 310.0)))
	var active: bool = bool(pad.get("active", false))
	var ring_color: Color = CYAN if active else Color("577081")
	if active:
		draw_circle(center, 51.0, Color(0.38, 0.90, 0.13, 0.035))
		draw_circle(center, 44.0, Color(0.38, 0.90, 0.13, 0.065))
	draw_circle(center, 36.0, Color("183b3e") if active else Color("192b39"))
	draw_arc(center, 36.0, 0, TAU, 64, ring_color, 2.0, true)
	draw_arc(center, 30.0, -PI * 0.75, PI * 0.75, 48, Color(ring_color, 0.22), 1.0, true)
	for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2.from_angle(angle)
		draw_line(center + direction * 40.0, center + direction * 46.0, ring_color, 2.0, true)
	_center_label("%02d" % (index + 1), center + Vector2(0, 6), 16, ring_color)
	_center_label("ACTIVE" if active else "STAND HERE", center + Vector2(0, 66), 11, ring_color)


func _draw_progress() -> void:
	var target_time: float = maxf(0.001, float(snapshot.get("target_time", 3.0)))
	var progress: float = clampf(float(snapshot.get("progress", 0.0)) / target_time, 0.0, 1.0)
	var complete: bool = bool(snapshot.get("completed", false))
	if complete:
		progress = 1.0
	var bar := Rect2(330, 574, 340, 4)
	draw_rect(bar, Color("293e4b"))
	if progress > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), CYAN)
	var caption: String = "LEVEL COMPLETE" if complete else "HOLD ALL PADS TOGETHER"
	_center_label(caption, Vector2(500, 560), 12, CYAN if complete else MUTED)


func _draw_player(player: Dictionary) -> void:
	var player_id := str(player.get("id", ""))
	var center: Vector2 = smooth_positions.get(player_id, _player_position(player))
	var slot: int = int(player.get("slot", 0))
	var color: Color = PLAYER_COLORS[posmod(slot, PLAYER_COLORS.size())]
	var is_local: bool = player_id == local_id
	draw_circle(center + Vector2(0, 5), 21.0, Color(0.0, 0.02, 0.04, 0.32))
	if is_local:
		draw_arc(center, 25.0, 0, TAU, 64, Color(color, 0.52), 1.5, true)
		draw_circle(center, 29.0, Color(color, 0.025))
	draw_circle(center, 18.0, color)
	draw_arc(center, 17.0, PI * 1.10, PI * 1.82, 24, Color(1, 1, 1, 0.32), 2.0, true)
	_center_label("P%d" % (slot + 1), center + Vector2(0, 5), 13, INK)
	var player_name: String = str(player.get("name", ""))
	if player_name.length() > 18:
		player_name = player_name.left(16) + "…"
	if show_names and not player_name.is_empty():
		_center_label(player_name, center + Vector2(0, 40), 12, TEXT)
	if is_local:
		_center_label("YOU", center - Vector2(0, 34), 11, color)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-3, -30), center + Vector2(3, -30), center + Vector2(0, -26)]), color)


func _label(value: String, at: Vector2, font_size: int, color: Color) -> void:
	draw_string(get_theme_default_font(), at, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _center_label(value: String, at: Vector2, font_size: int, color: Color) -> void:
	var font: Font = get_theme_default_font()
	var text_width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(font, at - Vector2(text_width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
