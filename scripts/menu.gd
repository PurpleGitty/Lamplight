extends Control
## The main menu. Up/down moves the soul between the options; ACCEPT picks one.
## The title and options are placeholder text until the menu art is made.

const TITLE_FONT = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
const OPTION_FONT = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
const SOUL = preload("res://sprites/candy_soul.png")
const OPTIONS := [
	["CAMPAIGN", "res://node_2d.tscn"],
	["CHART MAKER", "res://editor/attack_editor.tscn"],
	["QUIT", ""],
]
const FIRST_OPTION_Y := 270.0
const OPTION_GAP := 40.0

var selected := 0
var labels: Array[Label] = []
var soul := Sprite2D.new()
var move_sound := AudioStreamPlayer.new()
var select_sound := AudioStreamPlayer.new()
var _soul_tween: Tween
var _leaving := false


func _ready() -> void:
	# The editor switches the window to full resolution; put the game's scaling back
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.title = ProjectSettings.get_setting("application/config/name")
	Engine.max_fps = ProjectSettings.get_setting("application/run/max_fps")

	set_anchors_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var title := _label("LAMPLIGHT", TITLE_FONT, 48, 110)
	title.add_theme_color_override("font_color", Color("b48cff"))
	for i in OPTIONS.size():
		labels.append(_label(OPTIONS[i][0], OPTION_FONT, 16, FIRST_OPTION_Y + i * OPTION_GAP))

	soul.texture = SOUL
	soul.hframes = 2
	soul.scale = Vector2(2, 2)
	add_child(soul)
	move_sound.stream = preload("res://sounds/lightningbulb-spacebar-click-keyboard-199448.mp3")
	select_sound.stream = preload("res://sounds/creatorshome-video-game-select-337214.mp3")
	add_child(move_sound)
	add_child(select_sound)
	_select(0, false)


func _label(text: String, font: Font, font_size: int, y: float) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.size = Vector2(640, font_size + 8)
	label.position = Vector2(0, y - label.size.y / 2)
	add_child(label)
	return label


func _select(index: int, animate := true) -> void:
	selected = wrapi(index, 0, OPTIONS.size())
	for i in labels.size():
		labels[i].add_theme_color_override("font_color", Color.YELLOW if i == selected else Color.WHITE)
	# The soul sits just left of the chosen option
	var label := labels[selected]
	var text_width := OPTION_FONT.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var target := Vector2(320 - text_width / 2 - 22, label.position.y + label.size.y / 2)
	if _soul_tween:
		_soul_tween.kill()
	if animate:
		_soul_tween = create_tween()
		_soul_tween.tween_property(soul, "position", target, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		soul.position = target


func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	if event.is_action_pressed("ui_down"):
		move_sound.play()
		_select(selected + 1)
	elif event.is_action_pressed("ui_up"):
		move_sound.play()
		_select(selected - 1)
	elif event.is_action_pressed("ACCEPT"):
		_choose()


func _choose() -> void:
	_leaving = true
	select_sound.play()
	var scene: String = OPTIONS[selected][1]
	# Flash the soul before leaving
	var t := create_tween()
	for i in 3:
		t.tween_callback(func(): soul.frame = 1)
		t.tween_interval(0.06)
		t.tween_callback(func(): soul.frame = 0)
		t.tween_interval(0.06)
	await t.finished
	if scene == "":
		get_tree().quit()
	else:
		get_tree().change_scene_to_file(scene)
