extends Control

## Compact combat HUD. Displayed health always comes from the authoritative snapshot.
var health: float = 100.0
var maximum: float = 100.0
var respawn_in: float = 0.0
var protected: bool = false
var team_color := Color("66efd2")
var _trail: float = 1.0
var _trail_delay: float = 0.0
var _flash: float = 0.0
var _time: float = 0.0
var _initialized: bool = false
var stamina: float = 100.0
var max_stamina: float = 100.0
var stamina_active: bool = false
var _stamina_alpha: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(324, 98)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_health(player: Dictionary, god_mode: bool, color: Color) -> void:
	var next_health: float = maxf(0.0, float(player.get("health", 100.0)))
	var next_maximum: float = maxf(1.0, float(player.get("max_health", 100.0)))
	var ratio: float = clampf(next_health / next_maximum, 0.0, 1.0)
	if not _initialized or next_maximum != maximum or next_health > health:
		_trail = ratio
	elif next_health < health:
		_trail_delay = 0.35
		_flash = 0.6
	health = next_health
	maximum = next_maximum
	respawn_in = maxf(0.0, float(player.get("respawn_in", 0.0)))
	protected = god_mode or bool(player.get("invulnerable", false))
	team_color = color
	stamina = maxf(0.0, float(player.get("stamina", 100.0)))
	max_stamina = maxf(1.0, float(player.get("max_stamina", 100.0)))
	stamina_active = health > 0.0 and (stamina < max_stamina - 0.01 or bool(player.get("sprinting", false)))
	_initialized = true
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	_stamina_alpha = move_toward(_stamina_alpha, 1.0 if stamina_active else 0.0, delta * 3.0)
	_flash = maxf(0.0, _flash - delta)
	_trail_delay = maxf(0.0, _trail_delay - delta)
	if _trail_delay <= 0.0:
		_trail = move_toward(_trail, health / maximum, delta * 0.65)
	queue_redraw()

func _draw() -> void:
	var ratio: float = clampf(health / maximum, 0.0, 1.0)
	var fill := Color("66efd2") if ratio > 0.5 else Color("ffc76c") if ratio > 0.25 else Color("ff667e")
	if protected:
		fill = Color("9addff")
	var outline := team_color.darkened(0.45)
	if _flash > 0.0:
		outline = outline.lerp(Color("ff7585"), _flash / 0.6)
	var shape := PackedVector2Array([Vector2(0, 12), Vector2(12, 0), Vector2(306, 0), Vector2(324, 18), Vector2(324, 86), Vector2(312, 98), Vector2(18, 98), Vector2(0, 80)])
	draw_colored_polygon(shape, Color(0.026, 0.05, 0.074, 0.92))
	var rim := shape.duplicate()
	rim.append(shape[0])
	draw_polyline(rim, outline, 1.5, true)
	draw_line(Vector2(16, 1), Vector2(116, 1), team_color, 3.0, true)
	# A small shield crest identifies the health meter without adding instructions.
	var shield := PackedVector2Array([Vector2(16, 28), Vector2(37, 20), Vector2(58, 28), Vector2(56, 53), Vector2(37, 68), Vector2(18, 53)])
	draw_colored_polygon(shield, fill.darkened(0.77))
	var shield_rim := shield.duplicate()
	shield_rim.append(shield[0])
	draw_polyline(shield_rim, fill, 1.5, true)
	if protected:
		draw_polyline(PackedVector2Array([Vector2(27, 42), Vector2(35, 50), Vector2(48, 34)]), fill, 3.0, true)
	else:
		draw_line(Vector2(37, 33), Vector2(37, 52), fill, 4.0, true)
		draw_line(Vector2(28, 42), Vector2(46, 42), fill, 4.0, true)
	var font := get_theme_default_font()
	draw_string(font, Vector2(74, 22), "HEALTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("9baebc"))
	var number: String = _number(health)
	draw_string(font, Vector2(72, 54), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color("f0fff9"))
	var number_width: float = font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 31).x
	draw_string(font, Vector2(81 + number_width, 52), "/ " + _number(maximum), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("819ba9"))
	var bar := Rect2(74, 67, 229, 12)
	draw_rect(bar.grow(2), Color("020d16"))
	draw_rect(bar, Color("203340"))
	if _trail > ratio:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _trail, bar.size.y)), Color("fff0bd"))
	if ratio > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), fill.darkened(0.2))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, 5)), fill)
	for segment in range(1, 10):
		var x: float = bar.position.x + bar.size.x * segment / 10.0
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0.02, 0.07, 0.10, 0.45), 1.0)
	if health <= 0.0:
		draw_string(font, Vector2(74, 93), "Respawning  %.1fs" % respawn_in, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ffabb7"))
	elif ratio <= 0.25 and not protected:
		draw_circle(Vector2(301, 20), 3, Color(1.0, 0.32, 0.4, 0.5 + 0.4 * sin(_time * 5.0)))
	if _stamina_alpha > 0.0 and health > 0.0:
		draw_rect(Rect2(74, 87, 229, 5), Color(0.12, 0.22, 0.29, _stamina_alpha))
		var stamina_color := Color("7dc7ff") if stamina > 0.0 else Color("ffbd73")
		stamina_color.a = _stamina_alpha
		draw_rect(Rect2(74, 87, 229 * clampf(stamina / max_stamina, 0, 1), 5), stamina_color)
		draw_string(font, Vector2(15, 91), "STAMINA", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, stamina_color)

func _number(value: float) -> String:
	return String.num(value, 2).trim_suffix("0").trim_suffix("0").trim_suffix(".") if not is_equal_approx(value, roundf(value)) else str(int(value))
