extends Minigame
## Mash ACCEPT before time runs out. Every tap adds damage, and hitting the goal
## counts as PERFECT. If the enemy's turn interrupts it, what's built up lands.

var _tap_count := 0
var _left := 0.0
var _flash := 0.0
var _result := ""


func begin() -> void:
	_left = settings.get("duration", 2.5)


func _progress() -> float:
	return minf(float(_tap_count) / maxf(settings.get("taps_for_full", 16.0), 1.0), 1.0)


func _multiplier() -> float:
	return lerpf(settings.get("minimum", 0.2), settings.get("maximum", 1.5), _progress())


func interrupted_multiplier() -> float:
	return _multiplier() if _tap_count > 0 else 0.0


func tapped() -> void:
	_tap_count += 1
	_flash = 1.0
	fire_sound(asset("tap_sound"))


func tick(delta: float) -> void:
	_flash = maxf(_flash - delta * 10.0, 0.0)
	if not running:
		return
	_left -= delta
	if _left <= 0.0:
		perfect = _progress() >= 1.0
		_result = "%d TAPS" % _tap_count
		end(_multiplier())


func _draw() -> void:
	draw_title()
	var label := _result if _result != "" else "MASH!  %.1f" % maxf(_left, 0.0)
	draw_string(font, Vector2(0, 16), label, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, Color.YELLOW if _flash > 0.0 else Color.WHITE)
	var bar := Rect2(4, size.y * 0.5, size.x - 8, 24)
	draw_rect(bar, Color(1, 1, 1, 0.12))
	var fill := bar
	fill.size.x *= _progress()
	draw_rect(fill, Color.YELLOW.lerp(Color.WHITE, _flash))
	draw_rect(bar, Color.WHITE, false, 2.0)
