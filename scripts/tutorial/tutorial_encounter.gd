class_name TutorialEncounter
extends Node
## Candy's fight at the end of the tutorial. Whenever her chart plays, this puts her rig in
## place of her (blank) sprite, with a reflection on the ground, and the music visualizer
## behind the arena. Straight out of the tutorial it also plays the intro first: your name
## is backspaced into Crow's, Crow slides in from the right, Candy and the visualizer fade
## in out of the dark, a title card flashes, and then the song starts the fight.

const CHART := "res://charts/tutorial/candy.json"
const HUD = preload("res://scripts/hud.gd")
const REFLECTION = preload("res://shaders/ground_reflection.gdshader")
const TITLE_FONT = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
const GROUND_Y := 100.0 # where Candy stands and the visualizer's lowest point
const CANDY_SCALE := 2.0
const ERASE_TIME := 0.07 # seconds per letter
const TYPE_TIME := 0.12
const SLIDE_TIME := 0.9
const FADE_IN := 1.6

## Set by the tutorial just before it starts this fight.
static var pending := false
## The name the player had in the tutorial, to backspace.
static var from_name := ""

var battle: Battle
var play_intro := false
var _candy_holder := Node2D.new() # her rig and its reflection, which fade in together
var _visualizer := MusicVisualizer.new()


func _ready() -> void:
	_visualizer.ground_y = GROUND_Y
	var candy: Enemy = battle.find_character("Candy")
	if candy != null:
		# Her rig stands on the visualizer's ground where she is; her own sprite's an
		# invisible box for speech bubbles and hits
		_candy_holder.position = Vector2(0, _visualizer.ground_at(candy.position.x) - candy.position.y)
		candy.add_child(_candy_holder)
		var rig := CandySprite.new()
		rig.scale = Vector2.ONE * CANDY_SCALE
		_candy_holder.add_child(rig)
		var mirror := CanvasGroup.new()
		var flipped := CandySprite.new()
		flipped.scale = Vector2(CANDY_SCALE, -CANDY_SCALE)
		mirror.add_child(flipped)
		var fade := ShaderMaterial.new()
		fade.shader = REFLECTION
		mirror.material = fade
		_candy_holder.add_child(mirror)
		mirror.set_meta("fade", fade)
		_candy_holder.set_meta("mirror", mirror)
	battle.add_child(_visualizer)
	if play_intro:
		_intro()


func _process(_delta: float) -> void:
	# The reflection fades out going down from her feet, measured on screen
	if _candy_holder.has_meta("mirror"):
		var mirror: CanvasGroup = _candy_holder.get_meta("mirror")
		var ground := mirror.get_global_transform_with_canvas() * Vector2.ZERO
		var fade: ShaderMaterial = mirror.get_meta("fade")
		fade.set_shader_parameter("ground_y", ground.y)
		fade.set_shader_parameter("fade_length", 60.0 * mirror.get_global_transform_with_canvas().get_scale().y)


func _intro() -> void:
	var hud = battle.hud
	var crow: PartyMember = battle.party[0]
	var home := crow.position
	battle.set_process(false) # no turns until the song starts
	var song: AudioStream = battle.get_node("Music").stream
	if song != null:
		battle.conductor.song_length = song.get_length() # so the timer's right before it starts
	hud.position = HUD.OPEN_POS
	hud.state = HUD.MenuState.WAITING
	hud.update_tab_visuals()
	crow.position.x = 380.0
	_candy_holder.modulate.a = 0.0
	_visualizer.modulate.a = 0.0
	var label: Label = hud.party_rows[0]
	_show_name(label, from_name)
	await _seconds(0.6)

	# Backspaced, then retyped
	var typed := from_name
	while typed != "":
		typed = typed.left(-1)
		_show_name(label, typed)
		battle.get_node("Txt").play()
		await _seconds(ERASE_TIME)
	await _seconds(0.3)
	for letter in crow.display_name:
		typed += letter
		_show_name(label, typed)
		battle.get_node("Txt").play()
		await _seconds(TYPE_TIME)
	hud.layout_party()
	await _seconds(0.3)

	# Crow slides in from the right
	var slide := create_tween()
	slide.tween_property(crow, "position", home, SLIDE_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await slide.finished
	await _seconds(0.5)

	# Candy and the visualizer come out of the dark
	var fade := create_tween().set_parallel()
	fade.tween_property(_candy_holder, "modulate:a", 1.0, FADE_IN)
	fade.tween_property(_visualizer, "modulate:a", 1.0, FADE_IN)
	await fade.finished
	await _seconds(0.4)
	await _title_card()

	battle.conductor.start()
	battle.set_process(true)
	battle.start_player_turn()


## The player's name, kept in the middle with its HP bar beside it.
func _show_name(label: Label, text: String) -> void:
	var hud = battle.hud
	var bar: Control = label.get_child(0)
	var width: float = hud.menu_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	label.text = text
	bar.position.x = width + 6.0
	label.position.x = roundf((hud.size.x - width - 6.0 - bar.size.x) / 2.0)


func _title_card() -> void:
	var card := CanvasLayer.new()
	card.layer = 40
	battle.add_child(card)
	var flash := ColorRect.new()
	flash.color = Color.WHITE
	flash.size = Vector2(640, 480)
	card.add_child(flash)
	var title := Label.new()
	title.text = "CANDY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_constant_override("outline_size", 16)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.size = Vector2(640, 480)
	card.add_child(title)
	battle.get_node("Select").play()
	var t := create_tween()
	t.tween_property(flash, "modulate:a", 0.0, 0.35)
	for i in 3:
		t.tween_callback(func(): title.visible = false)
		t.tween_interval(0.08)
		t.tween_callback(func(): title.visible = true)
		t.tween_interval(0.16)
	t.tween_interval(0.5)
	t.tween_property(title, "modulate:a", 0.0, 0.4)
	await t.finished
	card.queue_free()


func _seconds(time: float) -> void:
	await get_tree().create_timer(time, false).timeout
