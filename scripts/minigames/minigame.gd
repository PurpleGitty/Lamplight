class_name Minigame
extends Control
## Base for attack minigames: what plays in the menu box when someone attacks.
## A chart picks one per special (and per character's basic attack) by id, with
## settings from ChartDefs.MINIGAMES. To add one: write a script here that
## extends this, list it in ChartDefs.MINIGAMES, and it's in the chart maker.
##
## Minigames run on real time, not the song's BPM. They end by emitting
## `finished` with a damage multiplier. If the enemy's turn interrupts one,
## `interrupted_multiplier()` decides how much of the attack still lands.

signal finished(multiplier: float)

const DEFAULT_FONT = preload("res://fonts/mojang_spaced.tres")
const TRAIL_LENGTH := 6
const TRAIL_ALPHA := 0.5

var title := ""
var id := ""
var settings: Dictionary
var font: Font = DEFAULT_FONT
var target_health := 1.0 # how much HP the one being attacked has left, 0 to 1
var _trail: Array[Transform2D] = [] # newest last
var _white := {} # textures -> all-white copies, for afterimages
var running := false
var perfect := false # earns TP on a basic attack


## Makes the minigame with this id.
static func create(game_id: String) -> Minigame:
	var known: String = game_id if ChartDefs.MINIGAMES.has(game_id) else "timing_bar"
	var game: Minigame = load(ChartDefs.MINIGAMES[known]["script"]).new()
	game.id = known
	return game


## The size of box it asks for (zero = it fits in the command box).
static func box_size(game_id: String, chosen_settings: Dictionary) -> Vector2:
	var full := full_settings(game_id, chosen_settings)
	return Vector2(full.get("box_width", 0.0), full.get("box_height", 0.0))


## A value for every setting, using the defaults for anything that wasn't chosen.
static func full_settings(game_id: String, chosen_settings: Dictionary) -> Dictionary:
	var full := ChartDefs.defaults(ChartDefs.MINIGAMES.get(game_id, ChartDefs.MINIGAMES["timing_bar"])["params"])
	full.merge(chosen_settings, true)
	return full


func start(text: String, chosen_settings: Dictionary) -> void:
	title = text
	settings = full_settings(id, chosen_settings)
	perfect = false
	running = true
	show()
	begin()


## Called once when the minigame starts.
func begin() -> void:
	pass


## The player pressed ACCEPT while it's running.
func tapped() -> void:
	pass


## What still lands if the enemy's turn starts mid-minigame.
func interrupted_multiplier() -> float:
	return 0.0


## Ends it with this damage multiplier.
func end(multiplier: float) -> void:
	if not running:
		return
	running = false
	finished.emit(multiplier)


## The enemy's turn started.
func cancel() -> void:
	hide()
	end(interrupted_multiplier())


func _input(event: InputEvent) -> void:
	if running and GameSettings.pressed(event, "ACCEPT"):
		get_viewport().set_input_as_handled()
		tapped()


func _process(delta: float) -> void:
	if visible:
		tick(delta)
		queue_redraw()


## Called every frame while shown.
func tick(_delta: float) -> void:
	pass


func draw_title() -> void:
	draw_string(font, Vector2(0, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)


## A sprite or sound setting. Left blank, it's the game's own.
func asset(key: String) -> String:
	var path: String = settings.get(key, "")
	if path != "":
		return path
	for param in ChartDefs.MINIGAMES[id]["params"]:
		if param["name"] == key:
			return param["default"]
	return ""


## The sprite for this minigame, if it has one.
func custom_texture() -> Texture2D:
	var path := asset("sprite")
	return ChartDefs.load_texture(path) if path != "" else null


## Plays a sound that carries on after the minigame closes, and can overlap itself.
func fire_sound(path: String) -> void:
	var stream := ChartDefs.load_audio(path)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.play()


## Remembers where the weapon is, for its afterimages. Call once a frame.
func trail_add(where: Transform2D) -> void:
	_trail.append(where)
	if _trail.size() > TRAIL_LENGTH:
		_trail.pop_front()


## Call once a frame when the weapon's stopped, so its afterimages catch up.
func trail_fade() -> void:
	if not _trail.is_empty():
		_trail.pop_front()


## Draws the afterimages: white, fading out with age.
func draw_trail(art: Texture2D, offset: Vector2) -> void:
	var white := _white_copy(art)
	for i in _trail.size():
		var age := float(i + 1) / (TRAIL_LENGTH + 1)
		draw_set_transform_matrix(_trail[i])
		draw_texture(white, offset, Color(1, 1, 1, age * TRAIL_ALPHA))
	draw_set_transform(Vector2.ZERO)


func _white_copy(art: Texture2D) -> Texture2D:
	if not _white.has(art):
		var image := art.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				image.set_pixel(x, y, Color(1, 1, 1, image.get_pixel(x, y).a))
		_white[art] = ImageTexture.create_from_image(image)
	return _white[art]
