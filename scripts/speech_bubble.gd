class_name SpeechBubble
extends Control
## Undertale-style speech bubble: a rounded white box with black text typed
## out letter by letter (each letter plays the speaker's voice), and a little
## tail pointing at whoever is talking. Text can use TextMarkup formatting.

const FONT = preload("res://fonts/PixelOperator.ttf")
const DEFAULT_VOICE = preload("res://sounds/snd_txt2.wav")
const WIDTH := 132.0
const PADDING := 6.0
const TAIL := 9.0
const RADIUS := 6
const TYPE_SPEED := 0.03 # seconds per character

## Keeps the bubble inside this area (the battle screen by default).
var bounds := Rect2(-316, -236, 632, 472)
var label := RichTextLabel.new()
var tail_side := SIDE_RIGHT
var tail_tip := Vector2.ZERO # in the bubble's own coordinates
var voice_player := AudioStreamPlayer.new()
var writer := TextMarkup.Typewriter.new()
var _box := StyleBoxFlat.new()
var _anchor := Vector2.ZERO


func _init() -> void:
	z_index = 5
	hide()
	label.add_theme_font_override("normal_font", FONT)
	label.add_theme_font_size_override("normal_font_size", 16)
	label.add_theme_color_override("default_color", Color.BLACK)
	label.add_theme_constant_override("line_separation", 1) # so [tiny] lines don't touch
	label.scroll_active = false
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.clip_contents = false # wavy/shaky letters may poke out a little
	label.position = Vector2(PADDING, PADDING - 1)
	add_child(label)
	add_child(voice_player)
	_box.bg_color = Color.WHITE
	_box.set_corner_radius_all(RADIUS)
	_box.anti_aliasing = false # crisp, pixel-art corners


## `anchor` is the point the tail touches, next to the speaker. `side` is which
## side of the bubble the tail comes out of (SIDE_LEFT, SIDE_RIGHT or SIDE_BOTTOM).
## `voice` plays once per letter (null = the default text blip).
func say(text: String, anchor: Vector2, side: Side, voice: AudioStream = null) -> void:
	voice_player.stream = voice if voice else DEFAULT_VOICE
	label.size = Vector2(WIDTH - PADDING * 2, 400)
	writer.start(label, text, TYPE_SPEED)
	_anchor = anchor
	tail_side = side
	_fit()
	show()


## Sizes the bubble to its text and places it by the speaker. Runs again
## whenever the text's height changes (it can't always be measured right away).
func _fit() -> void:
	var height := maxf(label.get_content_height(), 8.0) + PADDING * 2
	label.size.y = height - PADDING * 2
	size = Vector2(WIDTH, height)
	match tail_side:
		SIDE_RIGHT:
			position = _anchor - Vector2(WIDTH + TAIL, height / 2)
		SIDE_LEFT:
			position = _anchor + Vector2(TAIL, -height / 2)
		_:
			position = _anchor - Vector2(WIDTH / 2, height + TAIL)
	position = position.clamp(bounds.position, bounds.end - size)
	tail_tip = _anchor - position
	queue_redraw()


func is_typing() -> bool:
	return writer.is_typing()


func finish_typing() -> void:
	writer.finish()


func _process(delta: float) -> void:
	if not visible:
		return
	if not is_equal_approx(label.get_content_height() + PADDING * 2, size.y):
		_fit()
	if writer.update(delta):
		voice_player.play()


func _draw() -> void:
	_box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	var tail: PackedVector2Array
	match tail_side:
		SIDE_RIGHT, SIDE_LEFT:
			var y := clampf(tail_tip.y, RADIUS + 4, size.y - RADIUS - 4)
			var edge := size.x - 1 if tail_side == SIDE_RIGHT else 1.0
			tail = [Vector2(edge, y - 4), Vector2(edge, y + 4), tail_tip]
		_:
			var x := clampf(tail_tip.x, RADIUS + 4, size.x - RADIUS - 4)
			tail = [Vector2(x - 4, size.y - 1), Vector2(x + 4, size.y - 1), tail_tip]
	draw_colored_polygon(tail, Color.WHITE)
