extends Minigame
## A sniper's scope: a ring shrinks onto the target. Tap when it lines up with
## the target's edge. Closer means more damage; too far off is a miss.

const START_RADIUS := 34.0
const TARGET_RADIUS := 8.0

var _time := 0.0
var _ring := START_RADIUS
var _result := ""
var _color := Color.WHITE


func _centre() -> Vector2:
	return Vector2(size.x / 2, 26.0 + (size.y - 26.0) / 2)


func tick(delta: float) -> void:
	if not running:
		return
	_time += delta
	_ring = lerpf(START_RADIUS, 0.0, _time / settings.get("shrink_time", 1.1))
	if _ring <= 0.0:
		_finish("MISS", 0.0, Color.RED)


func tapped() -> void:
	var off := absf(_ring - TARGET_RADIUS)
	var leeway: float = settings.get("leeway", 3.0)
	if off <= leeway:
		perfect = true
		_finish("PERFECT", settings.get("perfect_multiplier", 2.0), Color.YELLOW)
	elif off <= leeway * 2.5:
		_finish("GOOD", 1.0, Color.CYAN)
	elif off <= leeway * 4.5:
		_finish("GRAZED", 0.4, Color.WHITE)
	else:
		_finish("MISS", 0.0, Color.RED)


func _finish(text: String, multiplier: float, color: Color) -> void:
	_result = text
	_color = color
	if multiplier > 0.0:
		fire_sound(asset("shot_sound"))
	end(multiplier)


func _draw() -> void:
	draw_title()
	if _result != "":
		draw_string(font, Vector2(0, 16), _result, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, _color)
	var c := _centre()
	draw_line(c - Vector2(46, 0), c + Vector2(46, 0), Color(1, 1, 1, 0.25))
	draw_line(c - Vector2(0, 32), c + Vector2(0, 32), Color(1, 1, 1, 0.25))
	draw_arc(c, TARGET_RADIUS, 0.0, TAU, 32, Color.RED, 2.0)
	draw_arc(c, maxf(_ring, 0.5), 0.0, TAU, 48, _color if _result != "" else Color.WHITE, 2.0)
