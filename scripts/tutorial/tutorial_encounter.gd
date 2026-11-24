class_name TutorialEncounter
extends Node
## Candy's fight at the end of the tutorial. Her pieces, the music visualizer and her
## reflection all come from her chart (the Keyframer and the rules); this adds what's
## special to her fight: from beat 63, a second visualizer and a meteor shower, and,
## straight out of the tutorial, the intro: your name is backspaced into Crow's, Crow
## slides in from the right, Candy and the visualizer fade in out of the dark, a title
## card flashes, and then the song starts the fight.

const CHART := "res://charts/tutorial/candy.json"
const HUD = preload("res://scripts/hud.gd")
const TITLE_FONT = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
const ERASE_TIME := 0.07 # seconds per letter
const TYPE_TIME := 0.12
const SLIDE_TIME := 0.9
const FADE_IN := 1.6
const SKY_BEAT := 63.0 # when the second visualizer and the meteor shower come in
const SKY_FADE := 2.0 # seconds

## Set by the tutorial just before it starts this fight.
static var pending := false
## The name the player had in the tutorial, to backspace.
static var from_name := ""

var battle: Battle
var play_intro := false
var _sky_started := false


func _ready() -> void:
	if play_intro:
		_intro()


func _process(_delta: float) -> void:
	if not _sky_started and battle.visualizer != null and battle.conductor.playing and battle.conductor.song_beat >= SKY_BEAT:
		_start_sky()


## Beat 63: a bigger copy of the visualizer rises up behind the first, the other way
## round, and a faint meteor shower starts overhead.
func _start_sky() -> void:
	_sky_started = true
	var front := battle.visualizer
	var behind := MusicVisualizer.new()
	behind.source = front
	behind.ground_y = front.ground_y
	behind.tallest = MusicVisualizer.TALLEST * 1.7
	behind.mirrored = true
	behind.tint = Color(0.4, 0.4, 0.42)
	behind.modulate.a = 0.0
	var stars := MeteorShower.new()
	stars.ground = front.ground_at
	var stars_on_floor := MeteorShower.new()
	stars_on_floor.source = stars
	stars_on_floor.ground = front.ground_at
	# Stars, then the big one, behind the visualizer; the floor's stars over its reflection
	var at := front.get_index()
	battle.add_child(stars)
	battle.move_child(stars, at)
	battle.add_child(behind)
	battle.move_child(behind, at + 1)
	battle.add_child(stars_on_floor)
	battle.move_child(stars_on_floor, front.get_index() + 1)
	create_tween().tween_property(behind, "modulate:a", 1.0, SKY_FADE)


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
	var candy: Enemy = battle.find_character("Candy")
	var dark: Array[CanvasItem] = []
	if candy != null:
		dark.append(candy)
	if battle.visualizer != null:
		dark.append(battle.visualizer)
	for thing in dark:
		thing.modulate.a = 0.0
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
	for thing in dark:
		fade.tween_property(thing, "modulate:a", 1.0, FADE_IN)
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
