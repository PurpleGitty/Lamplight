class_name BootScreen
extends Control
## What shows when the game starts, before the main menu: a brief note that it's best
## with headphones. Any press skips it. An intro can go here later.

const HEADPHONES = preload("res://sprites/menu/headphones.png")
const FONT = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
const MENU_SCENE := "res://menu.tscn"
const ART_SCALE := 5.0
const FADE_IN := 0.6
const LETTER_TIME := 0.07 # seconds per letter, typing the words out
const HOLD := 1.0 # once they've finished typing
const FADE_OUT := 0.6
const SKIP_AFTER_MS := 150 # so a press left over from opening the game doesn't count

var _leaving := false
var _started := 0


func _ready() -> void:
	_started = Time.get_ticks_msec()
	set_anchors_preset(PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(PRESET_FULL_RECT)
	add_child(black)
	var group := Control.new()
	group.set_anchors_preset(PRESET_FULL_RECT)
	group.modulate.a = 0.0
	add_child(group)

	var art := TextureRect.new()
	art.texture = HEADPHONES
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.size = HEADPHONES.get_size() * ART_SCALE
	art.position = Vector2((640.0 - art.size.x) / 2.0, 130.0)
	group.add_child(art)

	var words := Label.new()
	words.text = "BEST EXPERIENCED\nWITH HEADPHONES"
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_theme_font_override("font", FONT)
	words.add_theme_font_size_override("font_size", 16)
	words.add_theme_constant_override("line_spacing", 8)
	words.size = Vector2(640, 48)
	words.position = Vector2(0, 310)
	group.add_child(words)

	# Everything fades in while the words type out, then it all fades away together
	words.visible_characters = 0
	var letters := words.get_total_character_count()
	var typing := letters * LETTER_TIME
	var t := create_tween()
	t.set_parallel()
	t.tween_property(group, "modulate:a", 1.0, FADE_IN)
	t.tween_property(words, "visible_characters", letters, typing)
	t.chain().tween_interval(HOLD)
	t.chain().tween_property(group, "modulate:a", 0.0, FADE_OUT)
	t.chain().tween_callback(_leave)


func _input(event: InputEvent) -> void:
	if Time.get_ticks_msec() - _started < SKIP_AFTER_MS:
		return
	var is_press: bool = (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventAction) and event.is_pressed()
	if is_press and not event.is_echo():
		_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(MENU_SCENE)
