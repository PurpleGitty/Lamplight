extends Control
## A live preview of a character's or object's sprite in the chart maker: the
## frame it's on, animated at the chart's tempo, and the whole sheet underneath
## with the current frame marked. Reads its settings live, so edits show at once.

const FONT = preload("res://fonts/PixelOperator.ttf")
const SPRITE_AREA := 150.0
const STRIP_HEIGHT := 40.0

var editor
var data: Dictionary
var first_key := "idle_first"
var count_key := "idle_count"
var length_key := "idle_beats"
var note: Label # gets the timing explanation, if set
var _time := 0.0
var _one_shot_left := 0.0
var _one_shot_total := 1.0
var _one_shot_first := 0
var _one_shot_count := 0


func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	custom_minimum_size.y = SPRITE_AREA + STRIP_HEIGHT


## Plays a one-off animation (the attack), then back to the loop.
func play_once(first: int, count: int, seconds: float) -> void:
	_one_shot_first = first
	_one_shot_count = count
	_one_shot_total = maxf(seconds, 0.01)
	_one_shot_left = _one_shot_total


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	_one_shot_left = maxf(_one_shot_left - delta, 0.0)
	queue_redraw()
	if note:
		var seconds_per_beat: float = 60.0 / editor.chart["bpm"]
		var count := maxi(int(data[count_key]), 1)
		var each: float = float(data[length_key]) / count
		var text := "At %s BPM, one beat = %.1f frames at 60 FPS. Each sprite frame shows for %.2f beats (%.1f frames)." % [editor.chart["bpm"], seconds_per_beat * 60.0, each, each * seconds_per_beat * 60.0]
		if note.text != text:
			note.text = text


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.07))
	var tex := ChartDefs.load_texture(data["sprite"])
	var frames := maxi(int(data["hframes"]), 1)
	var frame_size := Vector2(tex.get_width() / float(frames), tex.get_height())
	var units: float = _time * ChartDefs.units_per_second(editor.chart) if data.has("frame") else _time * editor.chart["bpm"] / 60.0
	var frame := ChartDefs.anim_frame(int(data[first_key]), int(data[count_key]), data[length_key], units)
	if _one_shot_left > 0.0:
		frame = _one_shot_first + mini(floori((1.0 - _one_shot_left / _one_shot_total) * _one_shot_count), _one_shot_count - 1)
	frame = clampi(frame, 0, frames - 1)

	# The sprite, as big as whole-pixel scaling allows
	var scale_up: float = maxf(floorf(minf((size.x - 8) / frame_size.x, (SPRITE_AREA - 8) / frame_size.y)), 1.0)
	var shown := frame_size * scale_up
	var bob := 0.0
	if data.has("bob"):
		var heights := ChartDefs.parse_bob(data["bob"])
		if not heights.is_empty():
			var beat: float = _time * editor.chart["bpm"] / 60.0
			bob = -heights[posmod(floori(beat), heights.size())] * sin(PI * fposmod(beat, 1.0)) * scale_up
	var at := Vector2((size.x - shown.x) / 2, (SPRITE_AREA - shown.y) / 2 + roundf(bob))
	draw_texture_rect_region(tex, Rect2(at, shown), Rect2(Vector2(frame * frame_size.x, 0), frame_size))

	# The sheet, with the current frame marked
	var strip_scale: float = minf((size.x - 8) / tex.get_width(), (STRIP_HEIGHT - 8) / tex.get_height())
	var strip := Vector2(tex.get_width(), tex.get_height()) * strip_scale
	var strip_at := Vector2((size.x - strip.x) / 2, SPRITE_AREA + 4)
	draw_texture_rect(tex, Rect2(strip_at, strip), false)
	var mark := Rect2(strip_at + Vector2(frame * frame_size.x * strip_scale, 0), frame_size * strip_scale)
	draw_rect(mark, Color.YELLOW, false, 2.0)
	draw_string(FONT, Vector2(6, 16), "frame %d / %d" % [frame, frames - 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
