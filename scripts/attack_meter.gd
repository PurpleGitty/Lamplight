class_name AttackMeter
extends Minigame
## The basic FIGHT minigame, modelled on Undertale's: a bar slides across the
## left half of the "eye" toward the target line on its flat edge. Press ACCEPT
## as close to the line as you can. Runs on real time, not the song's BPM.

const OVERSHOOT := 20.0 # pixels past the target before it counts as a miss
# [max distance from the target line in pixels, label, damage multiplier, colour]
## (The bar moves ~11px per frame at 30 FPS, so PERFECT's full width, both sides of
## the line, must be at least that: then exactly one frame of it is always catchable.)
const GRADES := [
	[6.0, "PERFECT", 1.5, Color.YELLOW],
	[16.0, "GREAT", 1.0, Color.CYAN],
	[40.0, "OK", 0.6, Color.WHITE],
	[INF, "BAD", 0.3, Color.GRAY],
]
const EYE_TOP := 26.0 # leaves room for the title
const RING_COLORS := [Color(0.02, 0.02, 0.02), Color(0.0, 0.22, 0.16), Color(0.0, 0.38, 0.27), Color(0.05, 0.6, 0.42)]

var bar_x := 0.0
var _elapsed := 0.0
var _flash_time := 0.0
var _result_text := ""
var _result_color := Color.WHITE


func begin() -> void:
	_elapsed = 0.0
	_flash_time = 0.0
	bar_x = 0.0
	_result_text = ""


func target_x() -> float:
	return size.x - 6.0


func tick(delta: float) -> void:
	if running:
		_elapsed += delta
		bar_x = _elapsed / settings.get("cross_time", 0.9) * target_x()
		if bar_x > target_x() + OVERSHOOT:
			_resolve("MISS", 0.0, Color.RED)
	else:
		_flash_time += delta


func tapped() -> void:
	# Once it's gone past the line it's too late, however close it still is
	if bar_x - target_x() > GRADES[0][0]:
		_resolve("MISS", 0.0, Color.RED)
		return
	var distance := absf(bar_x - target_x())
	for grade in GRADES:
		if distance <= grade[0]:
			perfect = grade[1] == "PERFECT"
			_resolve(grade[1], grade[2], grade[3])
			return


func _resolve(text: String, multiplier: float, color: Color) -> void:
	_result_text = text
	_result_color = color
	end(multiplier)


## Outline of half an eye: pointed at the left, widest at the target line.
## `scale` shrinks it toward the target line for the inner rings.
func _half_eye(scale: float) -> PackedVector2Array:
	var tx := target_x()
	var cy := EYE_TOP + (size.y - EYE_TOP) / 2.0
	var half_height := (size.y - EYE_TOP) / 2.0 * scale
	var width := tx * scale
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in 25:
		var u := i / 24.0
		var h := half_height * (1.0 - pow(1.0 - u, 2.0))
		var x := tx - width + width * u
		top.append(Vector2(x, cy - h))
		bottom.append(Vector2(x, cy + h))
	bottom.reverse()
	return top + bottom


func _draw() -> void:
	draw_string(font, Vector2(0, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	if _result_text:
		draw_string(font, Vector2(0, 16), _result_text, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, _result_color)

	# The eye: nested rings, brighter toward the target
	for i in RING_COLORS.size():
		var ring := _half_eye(1.0 - i * 0.24)
		draw_colored_polygon(ring, RING_COLORS[i])
		ring.append(ring[0])
		draw_polyline(ring, Color.WHITE if i == 0 else Color(0.3, 1.0, 0.75, 0.6), 2.0 if i == 0 else 1.0)
	var tx := target_x()
	draw_line(Vector2(tx, EYE_TOP), Vector2(tx, size.y), Color.WHITE, 2.0)

	# The bar: white with a black outline, flashing after it's been stopped
	var bar := Rect2(bar_x - 4, EYE_TOP - 2, 8, size.y - EYE_TOP + 4)
	var fill := Color.WHITE
	if not running and _result_text and int(_flash_time / 0.06) % 2 == 1:
		fill = Color.BLACK
	draw_rect(bar, fill)
	draw_rect(bar, Color.BLACK if fill == Color.WHITE else Color.WHITE, false, 2.0)
