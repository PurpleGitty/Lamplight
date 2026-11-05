class_name Overworld
extends Node2D
## Plays a locale: walking around, talking, warps, cutscenes. Most of this is the
## event runner, which works through a list of steps one at a time. It keeps its
## place in a plain list, so a fight can interrupt a cutscene and carry on after.

const SCENE := "res://overworld.tscn"
const SCREEN := Vector2(640, 480)
const FONT = preload("res://fonts/PixelOperator.ttf")
const MENU_FONT = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
const BLIP = preload("res://sounds/snd_txt2.wav")
const MOVE_SOUND = preload("res://sounds/lightningbulb-spacebar-click-keyboard-199448.mp3")
const SELECT_SOUND = preload("res://sounds/creatorshome-video-game-select-337214.mp3")
const BACK_SOUND = preload("res://sounds/freesound_community-cancel-36118.mp3")
const FEET_HEIGHT := 8.0 # the player's box goes this far up from their feet
const CORNER_NUDGE := 4 # pixels they'll slip sideways to get round a corner
const TABS := ["ITEMS", "PARTY", "SYSTEM"]
const VOLUME_STEP := 5
const REACH := 14.0 # how far ACCEPT reaches
const STEP_LIMIT := 2000 # steps that can run in one go without waiting: stops a stuck loop
const WARP_FADE := 0.2
const TEXT_SPEED := 0.03
const BOX_TOP := 340.0
const TEXT_SIZE := 32
const PORTRAIT_SIZE := 96.0

## What to play. The menu and the Locale-Inator set this.
static var locale_to_play := ""
## Where Quit goes.
static var return_scene := "res://menu.tscn"
## Which room and spawn to start at, for testing from the editor (-1 = the locale's start).
static var test_room := -1
static var test_spawn := Vector2.INF
## Everything that survives a fight, or null: {"room", "position", "facing", "flags", "items", "done", "shown", "frames", "rules"}.
static var resume: Variant = null
## A save slot to load when this starts (-1 = start from the beginning).
static var load_slot := -1

var locale: Dictionary
var rules: Dictionary
var room: Dictionary
var flags := {}
var items := {} # item id -> how many
var done_once := {} # object id -> it's happened
var shown_override := {} # object id -> visible or not, from Show or Hide steps
var play_seconds := 0.0
var party_hp := {} # a party member's name -> their HP

var view := RoomView.new()
var world_viewport := SubViewport.new() # the world, drawn at its true pixel size
var world_layer := CanvasLayer.new()
var world_image := TextureRect.new() # and scaled up from there, so every pixel's the same size
var things := Node2D.new() # y-sorted actors
var shadows := ShadowLayer.new()
var player: Actor
var followers: Array[Actor] = []
var actors := {} # object id -> Actor
var camera := Camera2D.new()
var overlay := CanvasLayer.new()
var fade_rect := ColorRect.new()
var background_layer := CanvasLayer.new()
var background_fill := ColorRect.new()
var background_image := TextureRect.new()
var background_video := VideoStreamPlayer.new()
var cutscene_video := VideoStreamPlayer.new()
var music := AudioStreamPlayer.new()
var sound := AudioStreamPlayer.new()
var blip := AudioStreamPlayer.new()
var box := Panel.new()
var box_text := RichTextLabel.new()
var box_speaker := Label.new()
var box_portrait := TextureRect.new()
var choice_box := VBoxContainer.new()
var menu_root := Control.new()

var _writer := TextMarkup.Typewriter.new()
var _frames: Array = [] # event running: [{"steps": Array, "at": int}], innermost last
var _running := false
var _trail: Array[Vector2] = []
var _trail_facing: Array[String] = []
var _drawn := Rect2()
var _camera_target: Variant = null # an Actor to look at instead of the player
var _camera_from := Vector2.ZERO
var _camera_blend := 1.0
var _camera_time := 0.0
var _shake := 0.0
var _shake_left := 0.0
var _touching := {} # object id -> the player was on it last frame
var _music_path := "?"
var _background_key := "?"
var _menu_open := false
var _menu_mode := "main" # main, save, load, options or member
var _menu_member: Dictionary # whose stats are showing
var _menu_tab := 0
var _guard_frame := -1 # a press on or before this frame was for what came before
var _menu_from_step := false # a Save step opened it, so leaving it closes it
var _last_player_spot := Vector2.INF
var _menu_rows: Array = []
var _menu_at := 0
var _warping := false
var _rng_shake := RandomNumberGenerator.new()


## Draws every shadow, under the things casting them.
class ShadowLayer extends Node2D:
	var world: Overworld

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if world != null and not world.room.is_empty() and LocaleDefs.sun_on(world.room, world.rules):
			for actor in world.things.get_children():
				actor.draw_shadow_on(self, world.rules)


func _ready() -> void:
	GameSettings.apply_game_view()
	locale = _load_locale()
	rules = locale["rules"].duplicate()
	_build_scene()
	GameSettings.device_changed.connect(_refresh_menu)

	var party_data: Array = locale["party"]
	for member in party_data:
		party_hp[member["name"]] = int(member["max_hp"])
	player = _new_character(party_data[0])
	if resume != null:
		_restore()
		return
	if load_slot >= 0:
		var saved := SaveGame.read(locale, load_slot)
		load_slot = -1
		if _apply_save(saved):
			return
	var start_room := test_room if test_room >= 0 else int(locale["start_room"])
	var first: Variant = LocaleDefs.find_room(locale, start_room)
	if first == null:
		first = locale["rooms"][0]
	var spot := Vector2.ZERO
	var spawn: Variant = LocaleDefs.find_object(first, int(locale["start_spawn"])) if test_room < 0 else null
	if test_spawn != Vector2.INF:
		spot = test_spawn
	elif spawn != null:
		spot = Vector2(spawn["x"], spawn["y"])
		player.face(str(spawn["facing"]))
	_enter_room(first, spot)


static func play(path: String) -> String:
	locale_to_play = path
	resume = null
	load_slot = -1
	return SCENE


func _load_locale() -> Dictionary:
	var loaded := {}
	if LocaleFile.is_locale(locale_to_play):
		loaded = LocaleFile.read(locale_to_play)
	if loaded.is_empty():
		push_error("Couldn't play overworld %s: %s" % [locale_to_play, LocaleFile.last_error])
		loaded = LocaleDefs.new_locale()
	return loaded


# --- building ---

func _build_scene() -> void:
	y_sort_enabled = false
	background_layer.layer = -10
	add_child(background_layer)
	for control: Control in [background_fill, background_image, background_video]:
		control.size = SCREEN
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background_layer.add_child(control)
	background_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background_video.expand = true
	background_video.finished.connect(func():
		if background_video.visible:
			background_video.play())
	background_video.bus = &"SFX"
	background_video.volume = 0.0

	# Rendering at world size, then scaling up, makes everything pixel perfect: tiles,
	# sprites and shadows all land on the same grid and can't be drawn in between.
	world_viewport.transparent_bg = true
	world_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	world_viewport.snap_2d_transforms_to_pixel = true
	world_viewport.snap_2d_vertices_to_pixel = true
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(world_viewport)
	world_layer.layer = -5
	add_child(world_layer)
	world_image.texture = world_viewport.get_texture()
	world_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_layer.add_child(world_image)
	_apply_zoom()

	world_viewport.add_child(view)
	shadows.world = self
	view.shadow_group.add_child(shadows)
	things.y_sort_enabled = true
	view.add_child(things)
	view.move_child(things, view.above.get_index())
	world_viewport.add_child(camera)
	camera.make_current()
	get_window().size_changed.connect(_apply_stretch)
	_apply_stretch()
	music.bus = &"Music"
	add_child(music)
	sound.bus = &"SFX"
	add_child(sound)
	blip.bus = &"SFX"
	blip.stream = BLIP
	add_child(blip)

	overlay.layer = 10
	add_child(overlay)
	# The fade goes under the video and text, so a scene can fade out and still show them
	fade_rect.size = SCREEN
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(fade_rect)
	cutscene_video.expand = true
	cutscene_video.size = SCREEN
	cutscene_video.hide()
	cutscene_video.bus = &"Music"
	overlay.add_child(cutscene_video)
	_build_text_box()
	_build_menu()


## The world's pixels per screen pixel: always a whole number.
func _zoom() -> int:
	return maxi(roundi(float(rules["zoom"])), 1)


func _apply_zoom() -> void:
	var zoom := _zoom()
	world_viewport.size = Vector2i((SCREEN / float(zoom)).ceil())
	world_image.size = Vector2(world_viewport.size) * float(zoom)
	world_image.position = ((SCREEN - world_image.size) / 2.0).floor()


## Rooms scale to the window by a whole number where they can, so pixels stay square
## and even. The window has to fit at least 2x: below that it'd be a tiny picture.
func _apply_stretch() -> void:
	var window := get_window()
	var fits := minf(window.size.x / SCREEN.x, window.size.y / SCREEN.y)
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if fits >= 2.0 else Window.CONTENT_SCALE_STRETCH_FRACTIONAL


func _build_text_box() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK
	style.border_color = Color.WHITE
	style.set_border_width_all(4)
	box.add_theme_stylebox_override("panel", style)
	box.position = Vector2(16, BOX_TOP)
	box.size = Vector2(608, 124)
	box.hide()
	overlay.add_child(box)
	box_portrait.position = Vector2(14, 14)
	box_portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	box_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(box_portrait)
	box_text.add_theme_font_override("normal_font", FONT)
	box_text.add_theme_font_size_override("normal_font_size", TEXT_SIZE)
	box_text.scroll_active = false
	box_text.clip_contents = false
	box_text.position = Vector2(18, 12)
	box_text.size = Vector2(572, 104)
	box.add_child(box_text)
	box_speaker.add_theme_font_override("font", MENU_FONT)
	box_speaker.add_theme_font_size_override("font_size", 8)
	box_speaker.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	box_speaker.position = Vector2(18, -14)
	box.add_child(box_speaker)
	choice_box.position = Vector2(420, 210)
	choice_box.hide()
	overlay.add_child(choice_box)


func _build_menu() -> void:
	menu_root.size = SCREEN
	menu_root.hide()
	overlay.add_child(menu_root)


func _new_character(data: Dictionary) -> Actor:
	var actor := Actor.new()
	actor.setup(data, true, int(rules["tile_size"]))
	things.add_child(actor)
	return actor


# --- rooms ---

func _enter_room(new_room: Dictionary, spot: Vector2) -> void:
	room = new_room
	for id in actors:
		things.remove_child(actors[id])
		actors[id].queue_free()
	actors.clear()
	_touching.clear()
	view.show_room(room, int(rules["tile_size"]))
	_drawn = view.drawn_rect()
	view.set_sun(LocaleDefs.sun_on(room, rules), rules)
	for obj in room["objects"]:
		if LocaleDefs.OBJECT_TYPES[obj["type"]]["visible"]:
			var actor := Actor.new()
			actor.setup(obj, obj["type"] == "npc", int(rules["tile_size"]))
			actor.position = Vector2(obj["x"], obj["y"])
			if not obj.get("y_sort", true):
				actor.z_index = -2
			things.add_child(actor)
			actors[obj["id"]] = actor
	_refresh_shown()
	player.position = spot
	_set_party()
	_reset_trail()
	_apply_background()
	_apply_music()
	_camera_target = null
	_camera_blend = 1.0
	_update_camera(0.0)
	_mark_standing_on()
	_start_room_events()


## Where they're standing already doesn't count as walking onto it, so a warp you
## arrive beside doesn't throw you straight back.
func _mark_standing_on() -> void:
	for obj in room["objects"]:
		if obj["type"] in ["warp", "trigger"] and _player_box().intersects(_box_of(obj)):
			_touching[obj["id"]] = true


func _set_party() -> void:
	var wanted := clampi(int(rules["party_size"]), 1, locale["party"].size()) - 1
	while followers.size() > wanted:
		var last: Actor = followers.pop_back()
		things.remove_child(last)
		last.queue_free()
	while followers.size() < wanted:
		followers.append(_new_character(locale["party"][followers.size() + 1]))


func _reset_trail() -> void:
	_trail.clear()
	_trail_facing.clear()
	for f in followers:
		f.position = player.position
		f.facing = player.facing


func _start_room_events() -> void:
	for obj in room["objects"]:
		if obj.get("starts") == "enter_room" and _can_start(obj):
			_start_event_of(obj)
			return


func _apply_background() -> void:
	var source: Dictionary = room if room["own_background"] else rules
	var key := "%s|%s|%s" % [source["background_color"], source["background"], source["background_video"]]
	if key == _background_key:
		return
	_background_key = key
	background_fill.color = Color(str(source["background_color"]))
	var image := str(source["background"])
	background_image.visible = image != ""
	background_image.texture = ChartDefs.load_texture(image) if image != "" else null
	var video := ChartDefs.load_video(str(source["background_video"]))
	background_video.stop()
	background_video.visible = video != null
	background_video.stream = video
	if video != null:
		background_video.play()


func _apply_music() -> void:
	var wanted := str(room["music"]) if str(room["music"]) != "" else str(rules["music"])
	if wanted != _music_path:
		_play_music(wanted)


func _play_music(path: String) -> void:
	_music_path = path
	var stream := ChartDefs.load_audio(path)
	music.stop()
	music.stream = stream
	if stream != null:
		ChartDefs.set_looping(stream, true)
		music.play()


func _refresh_shown() -> void:
	for id in actors:
		var actor: Actor = actors[id]
		actor.visible = _object_is_there(actor.data)


func _object_is_there(obj: Dictionary) -> bool:
	if shown_override.has(obj["id"]):
		return shown_override[obj["id"]]
	var condition := str(obj.get("show_if", "")).strip_edges()
	if condition == "":
		return true
	if condition.begins_with("!"):
		return float(flags.get(condition.substr(1), 0.0)) == 0.0
	return float(flags.get(condition, 0.0)) != 0.0


func _box_of(obj: Dictionary) -> Rect2:
	var size := Vector2(float(obj.get("w", 0.0)), float(obj.get("h", 0.0)))
	return Rect2(Vector2(obj["x"], obj["y"]), size)


# --- every frame ---

func _process(delta: float) -> void:
	_writer_tick(delta)
	if not _menu_open:
		play_seconds += delta
	if not _running and not _warping and not _menu_open:
		_walk(delta)
		_check_stepping_on()
	else:
		_party_during_cutscene(delta)
	_update_camera(delta)


## When a cutscene walks the leader, the party still follows along.
func _party_during_cutscene(delta: float) -> void:
	var moved := player.position != _last_player_spot
	if moved and player.is_sliding():
		_trail.push_front(player.position)
		_trail_facing.push_front(player.facing)
	_last_player_spot = player.position
	if player.is_sliding():
		_move_followers(delta, true, false)
	else:
		for f in followers:
			if not f.on_path:
				f.set_walking(false, delta)


func _unhandled_input(event: InputEvent) -> void:
	if _menu_open:
		_menu_input(event)
		return
	if _running or _warping:
		return
	if GameSettings.pressed(event, "ACCEPT"):
		_guard_this_press()
		_interact()
	elif GameSettings.pressed(event, "MENU"):
		_open_menu("ITEMS" if bool(rules["can_use_inventory"]) else "PARTY")
	elif event.is_action_pressed("ui_cancel"):
		_open_menu("SYSTEM")


func _walk(delta: float) -> void:
	var direction := Input.get_vector("LEFT", "RIGHT", "UP", "DOWN")
	# With auto run on, BACK walks instead
	var wants_run: bool = Input.is_action_pressed("BACK") != bool(GameSettings.values["auto_run"])
	var running := bool(rules["can_run"]) and wants_run and direction != Vector2.ZERO
	var speed: float = rules["run_speed"] if running else rules["walk_speed"]
	if direction != Vector2.ZERO:
		var step := direction * speed * delta
		var before := player.position
		player.position = _slide(player.position, step)
		if absf(direction.x) > absf(direction.y):
			player.face("right" if direction.x > 0.0 else "left")
		else:
			player.face("down" if direction.y > 0.0 else "up")
		if player.position != before:
			_trail.push_front(player.position)
			_trail_facing.push_front(player.facing)
		player.set_walking(true, delta, float(rules["run_speed"]) / maxf(float(rules["walk_speed"]), 1.0) if running else 1.0, running)
	else:
		player.set_walking(false, delta)
	_move_followers(delta, direction != Vector2.ZERO, running)


## Party members walk where the leader walked, each a little further back along the trail.
func _move_followers(delta: float, leader_moving: bool, leader_running: bool) -> void:
	var gap := float(rules["follow_gap"])
	var most_needed := (followers.size() + 1) * gap
	var travelled := 0.0
	var from := player.position
	var index := 0
	for i in followers.size():
		var wanted_distance := gap * (i + 1)
		while index < _trail.size():
			var hop := from.distance_to(_trail[index])
			if travelled + hop >= wanted_distance:
				break
			travelled += hop
			from = _trail[index]
			index += 1
		var follower := followers[i]
		if follower.on_path:
			continue
		if index < _trail.size():
			var hop := from.distance_to(_trail[index])
			var along := (wanted_distance - travelled) / maxf(hop, 0.001)
			follower.position = from.lerp(_trail[index], clampf(along, 0.0, 1.0))
			follower.facing = _trail_facing[index]
		follower.set_walking(leader_moving, delta, player.speed_up, leader_running)
	# Forget the trail no one will ever reach
	var length := 0.0
	var at := player.position
	for k in _trail.size():
		length += at.distance_to(_trail[k])
		at = _trail[k]
		if length > most_needed:
			_trail.resize(k + 1)
			_trail_facing.resize(k + 1)
			break


## Moves as far as possible, one axis at a time, so walking into a wall at an angle slides along it.
func _slide(from: Vector2, step: Vector2) -> Vector2:
	# Standing in something (placed there by a warp or a cutscene): let them walk out
	if _blocked(from):
		return from + step
	var at := _slide_axis(from, step.x, 0)
	return _slide_axis(at, step.y, 1)


## Goes as far as this axis allows, right up to touching whatever's in the way. Walking
## into a corner by a few pixels slips them round it, so doorways aren't fiddly.
func _slide_axis(from: Vector2, amount: float, axis: int) -> Vector2:
	if amount == 0.0:
		return from
	var wanted := from
	wanted[axis] += amount
	if not _blocked(wanted):
		return wanted
	var direction := signf(amount)
	var at := from
	# Whole pixels from here, since that's what walls are made of
	var next := ceilf(from[axis]) if direction > 0.0 else floorf(from[axis])
	if next == from[axis]:
		next += direction
	while absf(next - from[axis]) <= absf(amount):
		var tried := at
		tried[axis] = next
		if _blocked(tried):
			break
		at = tried
		next += direction
	if at == from:
		return _slip_round_corner(from, direction, axis)
	return at


func _slip_round_corner(from: Vector2, direction: float, axis: int) -> Vector2:
	var other := 1 - axis
	for distance in range(1, CORNER_NUDGE + 1):
		for side in [-1.0, 1.0]:
			var tried := from
			tried[other] = roundf(from[other]) + side * distance
			var through := tried
			through[axis] += direction
			if not _blocked(through) and not _blocked(tried):
				var moved := from
				moved[other] = from[other] + side
				return moved if not _blocked(moved) else from
	return from


func _blocked(feet: Vector2) -> bool:
	var feet_box := _box_at(feet)
	var size := float(view.tile_size)
	var low := Vector2i((feet_box.position / size).floor())
	# A box exactly touching a tile isn't in it
	var high := Vector2i(((feet_box.end - Vector2(0.001, 0.001)) / size).floor())
	var edges: bool = rules["edges_block"]
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			if view.blocks(Vector2i(x, y), edges):
				return true
	for id in actors:
		var actor: Actor = actors[id]
		if actor.visible and actor.data.get("solid", false) and feet_box.intersects(actor.hit_box()):
			return true
	return false


func _box_at(feet: Vector2) -> Rect2:
	var width := player.body_width()
	return Rect2(feet - Vector2(width / 2.0, FEET_HEIGHT), Vector2(width, FEET_HEIGHT))


func _player_box() -> Rect2:
	return _box_at(player.position)


func _check_stepping_on() -> void:
	var feet := _player_box()
	for obj in room["objects"]:
		var kind: String = obj["type"]
		if kind != "warp" and kind != "trigger" and obj.get("starts") != "touch":
			continue
		var id: int = obj["id"]
		var on := false
		if kind == "warp" or kind == "trigger":
			on = feet.intersects(_box_of(obj)) and _object_is_there(obj)
		elif actors.has(id) and actors[id].visible:
			on = feet.grow(1.0).intersects(actors[id].hit_box())
		var was: bool = _touching.get(id, false)
		_touching[id] = on
		if not on or was:
			continue
		if kind == "warp":
			if not obj["needs_interact"]:
				_use_warp(obj)
				return
		elif _can_start(obj):
			_start_event_of(obj)
			return


func _interact() -> void:
	var reach_point: Vector2 = player.position + Vector2(0, -FEET_HEIGHT / 2.0) + LocaleDefs.DIRECTION_VECTORS[player.facing] * REACH
	var reach_box := Rect2(reach_point - Vector2(6, 6), Vector2(12, 12))
	for obj in room["objects"]:
		var id: int = obj["id"]
		if obj["type"] == "warp" and obj["needs_interact"] and _box_of(obj).intersects(reach_box.merge(_player_box())) and _object_is_there(obj):
			_use_warp(obj)
			return
		if obj.get("starts") != "interact" or not _can_start(obj):
			continue
		var target := Rect2()
		if actors.has(id):
			if not actors[id].visible:
				continue
			target = actors[id].hit_box().grow(2.0)
		elif obj["type"] == "trigger":
			target = _box_of(obj)
		else:
			continue
		if target.intersects(reach_box):
			if actors.has(id) and obj.get("turns_to_talk", false):
				actors[id].face_toward(player.position)
			_start_event_of(obj)
			return


func _can_start(obj: Dictionary) -> bool:
	if obj.get("once", false) and done_once.has(obj["id"]):
		return false
	return _object_is_there(obj) and not obj.get("steps", []).is_empty()


func _start_event_of(obj: Dictionary) -> void:
	if obj.get("once", false):
		done_once[obj["id"]] = true
	if _running:
		_frames.append({"steps": obj["steps"], "at": 0}) # entering a room during an event
		return
	_frames = [{"steps": obj["steps"], "at": 0}]
	_run_event()


# --- warps ---

func _use_warp(obj: Dictionary) -> void:
	_warp_to(int(obj["room"]), int(obj["spawn"]))


func _warp_to(room_id: int, spawn_id: int) -> void:
	var target: Variant = LocaleDefs.find_room(locale, room_id)
	if target == null:
		return
	_warping = true
	await _fade_to(Color.BLACK, WARP_FADE)
	var spot := Vector2.ZERO
	var spawn: Variant = LocaleDefs.find_object(target, spawn_id)
	if spawn != null:
		spot = Vector2(spawn["x"], spawn["y"])
		if spawn.has("facing"):
			player.face(str(spawn["facing"]))
	_warping = true
	_enter_room(target, spot)
	if bool(rules["autosave"]) and not _running:
		SaveGame.write(locale, SaveGame.AUTOSAVE_SLOT, _save_state())
	await _fade_to(Color(0, 0, 0, 0), WARP_FADE)
	_warping = false


func _fade_to(color: Color, seconds: float) -> void:
	if seconds <= 0.0:
		fade_rect.color = color
		return
	var tween := create_tween()
	tween.tween_property(fade_rect, "color", color, seconds)
	await tween.finished


# --- camera ---

func _update_camera(delta: float) -> void:
	var view_size := Vector2(world_viewport.size)
	var wanted_point: Vector2 = _camera_target.position if _camera_target != null else player.position
	var wanted := RoomView.camera_spot(wanted_point, _drawn, view_size)
	if _camera_blend < 1.0:
		_camera_blend = minf(_camera_blend + delta / maxf(_camera_time, 0.001), 1.0)
		wanted = _camera_from.lerp(wanted, smoothstep(0.0, 1.0, _camera_blend))
	camera.position = wanted.round()
	if _shake_left > 0.0:
		_shake_left -= delta
		var amount := _shake * GameSettings.shake_scale()
		camera.offset = (Vector2(_rng_shake.randf_range(-amount, amount), _rng_shake.randf_range(-amount, amount)) / float(_zoom())).round()
	else:
		camera.offset = Vector2.ZERO


# --- running events ---

func _writer_tick(delta: float) -> void:
	if box.visible and _writer.label != null and _writer.update(delta):
		blip.play()


func _run_event() -> void:
	if _running:
		return
	_running = true
	var count := 0
	while not _frames.is_empty():
		var frame: Dictionary = _frames[-1]
		if frame["at"] >= frame["steps"].size():
			_frames.pop_back()
			continue
		var step: Dictionary = frame["steps"][frame["at"]]
		frame["at"] += 1
		count += 1
		if count > STEP_LIMIT:
			push_warning("An event ran %d steps in one go, so it was stopped." % STEP_LIMIT)
			break
		if await _do_step(step, frame):
			return # a fight has taken over
	_frames.clear()
	_running = false
	_refresh_shown()


## Does one step. Returns true if the overworld is being left.
func _do_step(step: Dictionary, frame: Dictionary) -> bool:
	match step["type"]:
		"say":
			await _say(step)
		"choice":
			flags[str(step["flag"])] = await _ask(step)
		"if":
			if not _compare(float(flags.get(str(step["flag"]), 0.0)), str(step["compare"]), float(step["value"])):
				_skip_block(frame)
		"has_item":
			if int(items.get(int(step["item"]), 0)) <= 0:
				_skip_block(frame)
		"else":
			_skip_to_end(frame) # only reached by finishing the "if" part
		"end":
			pass
		"set_flag":
			var key := str(step["flag"])
			flags[key] = float(step["value"]) + (float(flags.get(key, 0.0)) if step["how"] == "add" else 0.0)
			_refresh_shown()
		"wait":
			await get_tree().create_timer(float(step["seconds"])).timeout
		"move":
			var who := _actor_for(int(step["who"]))
			if who != null:
				who.slide_to(who.position + Vector2(step["dx"], step["dy"]), float(step["speed"]))
				if step["wait"]:
					while is_instance_valid(who) and who.is_sliding():
						await get_tree().process_frame
		"follow":
			var path: Variant = LocaleDefs.find_object(room, int(step["path"]))
			var who := _actor_for(int(step["who"]))
			if path != null and who != null:
				if step["wait"]:
					await _walk_path(who, path, step)
				else:
					_walk_path(who, path, step)
		"animate":
			var who := _actor_for(int(step["who"]))
			if who != null:
				who.play_frames(int(step["first"]), int(step["count"]), float(step["fps"]), bool(step["loop"]), bool(step["hold"]))
				if step["wait"] and not step["loop"]:
					while is_instance_valid(who) and who.is_animating():
						await get_tree().process_frame
		"stop_anim":
			var who := _actor_for(int(step["who"]))
			if who != null:
				who.stop_frames()
		"save":
			_open_slots("save", true)
			while _menu_open:
				await get_tree().process_frame
		"face":
			var who := _actor_for(int(step["who"]))
			if who != null:
				who.face(str(step["direction"]))
		"show":
			shown_override[int(step["who"])] = bool(step["visible"])
			_refresh_shown()
		"warp":
			await _warp_to(int(step["room"]), int(step["spawn"]))
		"fade":
			await _fade_to(Color.BLACK if step["to"] == "black" else Color(0, 0, 0, 0), float(step["seconds"]))
		"camera":
			_camera_from = camera.position
			_camera_blend = 0.0
			_camera_time = float(step["seconds"])
			_camera_target = _actor_for(int(step["at"])) if int(step["at"]) < -1 or actors.has(int(step["at"])) else null
			await get_tree().create_timer(_camera_time).timeout
		"shake":
			_shake = float(step["strength"])
			_shake_left = float(step["seconds"])
		"sound":
			var stream := ChartDefs.load_audio(str(step["sound"]))
			if stream != null:
				sound.stream = stream
				sound.play()
		"music":
			_play_music(str(step["music"]))
		"video":
			await _play_video(step)
		"battle":
			return _start_fight(step)
		"heal":
			for member in locale["party"]:
				var amount := int(step["amount"])
				var most := int(member["max_hp"])
				var now := int(party_hp.get(member["name"], most))
				party_hp[member["name"]] = most if amount == 0 else clampi(now + amount, 1, most)
		"give":
			var id := int(step["item"])
			items[id] = maxi(int(items.get(id, 0)) + int(step["count"]), 0)
		"set_rule":
			_set_rule(str(step["rule"]), float(step["value"]))
		"cutscene":
			var scene: Variant = LocaleDefs.find_cutscene(locale, int(step["cutscene"]))
			if scene != null and _frames.size() < 32:
				_frames.append({"steps": scene["steps"], "at": 0})
		"stop":
			_frames.clear()
	return false


func _compare(left: float, how: String, right: float) -> bool:
	match how:
		"==": return is_equal_approx(left, right)
		"!=": return not is_equal_approx(left, right)
		">": return left > right
		">=": return left >= right
		"<": return left < right
		"<=": return left <= right
	return false


## The test failed: jump past this block, or into its Else.
func _skip_block(frame: Dictionary) -> void:
	_skip(frame, true)


## The "if" part finished: jump past the Else part.
func _skip_to_end(frame: Dictionary) -> void:
	_skip(frame, false)


func _skip(frame: Dictionary, stop_at_else: bool) -> void:
	var depth := 0
	var steps: Array = frame["steps"]
	while frame["at"] < steps.size():
		var kind: String = steps[frame["at"]]["type"]
		frame["at"] += 1
		if kind in LocaleDefs.BLOCK_STARTS:
			depth += 1
		elif kind == "end":
			if depth == 0:
				return
			depth -= 1
		elif kind == "else" and depth == 0 and stop_at_else:
			return


## -1 is the player, -2 the second in the party and so on, and anything else is an object here.
func _actor_for(id: int) -> Actor:
	if id == -1:
		return player
	if id < -1:
		var follower := -id - 2
		return followers[follower] if follower < followers.size() else null
	return actors.get(id)


## Walks someone along a drawn path, setting off each cue as they reach its point. A
## cue that takes time (talking, waiting) holds up only the one walking.
func _walk_path(who: Actor, path: Dictionary, step: Dictionary) -> void:
	var points := LocaleDefs.path_points(path)
	var speed := float(step["speed"])
	var seconds := float(step["seconds"])
	var here: Dictionary = room
	if step["start_there"]:
		who.position = points[0]
	if seconds > 0.0:
		var length := who.position.distance_to(points[0])
		for i in range(1, points.size()):
			length += points[i - 1].distance_to(points[i])
		speed = length / seconds
	who.on_path = true
	for i in points.size():
		if who.position != points[i]:
			who.slide_to(points[i], speed)
			while is_instance_valid(who) and who.is_sliding() and room == here:
				await get_tree().process_frame
		if not is_instance_valid(who) or room != here:
			break
		for cue in path["cues"]:
			if int(cue["point"]) == i:
				await _run_cue(cue["steps"])
				if not is_instance_valid(who) or room != here:
					break
	if is_instance_valid(who):
		who.on_path = false


## Runs a cue's steps. They can't start a fight, since nothing could pick a cue back up.
func _run_cue(steps: Array) -> void:
	var frame := {"steps": steps, "at": 0}
	while frame["at"] < steps.size():
		var step: Dictionary = steps[frame["at"]]
		frame["at"] += 1
		if step["type"] != "battle":
			await _do_step(step, frame)


func _set_rule(rule: String, value: float) -> void:
	if rule not in LocaleDefs.CHANGEABLE_RULES:
		return
	if rules[rule] is bool:
		rules[rule] = value != 0.0
	elif rules[rule] is int:
		rules[rule] = int(value)
	else:
		rules[rule] = value
	if rule == "party_size":
		_set_party()
		_reset_trail()
	elif rule == "zoom":
		_apply_zoom()
	elif rule.begins_with("sun"):
		view.set_sun(LocaleDefs.sun_on(room, rules), rules)


func _say(step: Dictionary) -> void:
	_open_box(step, str(step["speaker"]), str(step["portrait"]))
	await _wait_for_text()
	await _wait_for_press()
	box.hide()


func _open_box(step: Dictionary, speaker: String, portrait: String) -> void:
	box.show()
	box_speaker.text = speaker.to_upper()
	var has_portrait := portrait != ""
	box_portrait.visible = has_portrait
	box_portrait.texture = ChartDefs.load_texture(portrait) if has_portrait else null
	box_text.position.x = 18.0 + (PORTRAIT_SIZE + 14.0 if has_portrait else 0.0)
	box_text.size.x = 572.0 - (PORTRAIT_SIZE + 14.0 if has_portrait else 0.0)
	_guard_this_press()
	var voice := _voice_of(speaker)
	blip.stream = voice if voice != null else BLIP
	_writer.start(box_text, str(step["text"]), TEXT_SPEED)


func _voice_of(speaker: String) -> AudioStream:
	for member in locale["party"]:
		if member["name"] == speaker:
			return ChartDefs.load_audio(str(member["voice"]))
	for obj in room["objects"]:
		if obj["name"] == speaker and obj.has("voice"):
			return ChartDefs.load_audio(str(obj["voice"]))
	return null


## What started this is still being pressed this frame, so it mustn't count again.
func _guard_this_press() -> void:
	_guard_frame = Engine.get_process_frames() + 1


## A press that's new, not the one that got us here.
func _just(action: String) -> bool:
	return Input.is_action_just_pressed(action) and Engine.get_process_frames() > _guard_frame


func _text_done() -> bool:
	return not _writer.is_typing()


## Types the text out; ACCEPT or BACK shows the rest right away.
func _wait_for_text() -> void:
	while not _text_done():
		await get_tree().process_frame
		if _just("ACCEPT") or _just("BACK"):
			_writer.finish()
			await get_tree().process_frame
			return


func _wait_for_press() -> void:
	while true:
		await get_tree().process_frame
		if _just("ACCEPT"):
			return


func _ask(step: Dictionary) -> float:
	_open_box(step, "", "")
	await _wait_for_text()
	var options := str(step["options"]).split(",", false)
	if options.is_empty():
		box.hide()
		return 0.0
	for child in choice_box.get_children():
		choice_box.remove_child(child)
		child.queue_free()
	for option in options:
		var label := Label.new()
		label.add_theme_font_override("font", FONT)
		label.add_theme_font_size_override("font_size", TEXT_SIZE)
		choice_box.add_child(label)
	var at := 0
	choice_box.position = Vector2(60, BOX_TOP - 8.0 - options.size() * 38.0)
	choice_box.show()
	while true:
		for i in options.size():
			var label: Label = choice_box.get_child(i)
			label.text = ("> " if i == at else "  ") + options[i].strip_edges()
			label.add_theme_color_override("font_color", Color.YELLOW if i == at else Color.WHITE)
		await get_tree().process_frame
		if _just("ACCEPT"):
			break
		var move := int(Input.is_action_just_pressed("DOWN")) - int(Input.is_action_just_pressed("UP"))
		if move != 0:
			at = posmod(at + move, options.size())
			_menu_sound(MOVE_SOUND)
	choice_box.hide()
	box.hide()
	_menu_sound(SELECT_SOUND)
	return float(at + 1)


func _menu_sound(stream: AudioStream) -> void:
	sound.stream = stream
	sound.play()


func _play_video(step: Dictionary) -> void:
	var stream := ChartDefs.load_video(str(step["video"]))
	if stream == null:
		return
	var music_was_playing := music.playing
	music.stream_paused = true
	cutscene_video.stream = stream
	cutscene_video.show()
	cutscene_video.play()
	while cutscene_video.is_playing():
		await get_tree().process_frame
		if step["can_skip"] and _just("ACCEPT"):
			break
	cutscene_video.stop()
	cutscene_video.hide()
	if music_was_playing:
		music.stream_paused = false


func _start_fight(step: Dictionary) -> bool:
	var fight := str(step["fight"])
	var own_fight := fight.begins_with("res://charts/") and not fight.contains("..") and fight.get_extension() == "json"
	if not own_fight and not SafeFiles.is_media_file(fight, SafeFiles.SCRAPS):
		return false
	var saved_frames := []
	for f in _frames:
		saved_frames.append({"steps": f["steps"], "at": f["at"]})
	resume = {"room": room["id"], "position": player.position, "facing": player.facing, "flags": flags, "items": items,
		"done": done_once, "shown": shown_override, "frames": saved_frames, "rules": rules, "locale": locale,
		"seconds": play_seconds, "if_lost": step["if_lost"], "party_hp": party_hp}
	Battle.chart_to_play = fight
	Battle.return_scene = SCENE
	Battle.overworld_party = _party_for_fight() if step["use_party"] else {}
	Battle.give_up_label = "BACK TO LAST SAVE" if step["if_lost"] == "back to last save" else "CARRY ON"
	GameSettings.apply_game_view() # the fight scales the way the settings say
	get_tree().change_scene_to_file("res://node_2d.tscn")
	return true


func _party_for_fight() -> Dictionary:
	var out := {}
	for member in locale["party"]:
		out[member["name"]] = {"hp": party_hp.get(member["name"], member["max_hp"]), "max_hp": member["max_hp"], "fight_damage": member["fight_damage"],
			"defense": member["defense"], "specials": member["specials"], "maneuvers": member["maneuvers"]}
	return out


## Picks up where a fight interrupted.
func _restore() -> void:
	var saved: Dictionary = resume
	resume = null
	locale = saved["locale"]
	flags = saved["flags"]
	items = saved["items"]
	done_once = saved["done"]
	shown_override = saved["shown"]
	rules = saved["rules"]
	play_seconds = saved["seconds"]
	party_hp = saved["party_hp"]
	for member_name in Battle.overworld_party:
		party_hp[member_name] = Battle.overworld_party[member_name]["hp"]
	Battle.overworld_party = {}
	flags["won_fight"] = 1.0 if Battle.last_fight_won else 0.0
	if not Battle.last_fight_won and saved["if_lost"] == "back to last save":
		load_slot = SaveGame.latest(locale)
		get_tree().change_scene_to_file.call_deferred(SCENE)
		return
	player.facing = saved["facing"]
	var back: Variant = LocaleDefs.find_room(locale, int(saved["room"]))
	_frames = saved["frames"]
	var continuing := not _frames.is_empty()
	_enter_room_quietly(back if back != null else locale["rooms"][0], saved["position"])
	if continuing:
		_run_event()


func _enter_room_quietly(new_room: Dictionary, spot: Vector2) -> void:
	var waiting := _frames
	_frames = []
	# Room-enter events shouldn't start over when coming back from a fight
	var was_running := _running
	_running = true
	_enter_room(new_room, spot)
	_running = was_running
	_frames = waiting


# --- saving ---

func _save_state() -> Dictionary:
	# Only rules the game has changed, so changing one in the editor still takes effect
	var changed_rules := {}
	for key in rules:
		if rules[key] != locale["rules"][key]:
			changed_rules[key] = rules[key]
	return {"room": room["id"], "room_name": room["name"], "x": player.position.x, "y": player.position.y, "facing": player.facing,
		"flags": flags, "items": items, "done": done_once, "shown": shown_override, "rules": changed_rules, "seconds": play_seconds, "party_hp": party_hp}


## Puts a save into effect. False if there's nothing usable in it.
func _apply_save(saved: Dictionary) -> bool:
	if saved.is_empty():
		return false
	var saved_room: Variant = LocaleDefs.find_room(locale, int(saved["room"]))
	if saved_room == null:
		return false
	flags = saved["flags"]
	items = saved["items"]
	done_once = saved["done"]
	shown_override = saved["shown"]
	rules.merge(saved["rules"], true)
	play_seconds = saved["seconds"]
	party_hp.merge(saved["party_hp"], true)
	player.face(str(saved["facing"]))
	_enter_room_quietly(saved_room, Vector2(saved["x"], saved["y"]))
	return true


# --- menu ---

func _tabs() -> Array:
	return TABS.filter(func(t): return t != "ITEMS" or bool(rules["can_use_inventory"]))


func _open_menu(tab: String) -> void:
	_menu_open = true
	_menu_from_step = false
	_menu_tab = maxi(_tabs().find(tab), 0)
	_show_tab()
	_menu_sound(SELECT_SOUND)
	menu_root.show()
	_refresh_menu()


func _show_tab() -> void:
	_menu_mode = "main"
	_menu_at = 0
	_menu_rows = []
	match _tabs()[_menu_tab]:
		"ITEMS":
			for item in locale["items"]:
				var have := int(items.get(int(item["id"]), 0))
				if have > 0:
					_menu_rows.append({"kind": "item", "item": item, "count": have})
		"PARTY":
			var out := clampi(int(rules["party_size"]), 1, locale["party"].size())
			for i in locale["party"].size():
				_menu_rows.append({"kind": "member", "data": locale["party"][i], "with_you": i < out})
		"SYSTEM":
			if bool(rules["can_save_anywhere"]):
				_menu_rows.append({"kind": "save"})
			if SaveGame.has_any(locale):
				_menu_rows.append({"kind": "load"})
			_menu_rows.append({"kind": "options"})
			_menu_rows.append({"kind": "quit"})


## One party member's stats and moves.
func _open_member(data: Dictionary) -> void:
	_menu_mode = "member"
	_menu_member = data
	_menu_at = 0
	_menu_rows = []
	if bool(rules["menu_shows_moves"]):
		for pair in [["specials", ChartDefs.SPECIAL_PRESETS], ["maneuvers", ChartDefs.MANEUVER_PRESETS]]:
			for id in data[pair[0]]:
				_menu_rows.append({"kind": "move", "move": pair[1][id]})
	_menu_sound(SELECT_SOUND)
	_refresh_menu()


## Their stats, as the overworld's rules and their own list say to show them.
func _stat_lines(data: Dictionary) -> Array:
	var lines := []
	if bool(rules["menu_shows_hp"]):
		lines.append("HP  %d / %d" % [int(party_hp.get(data["name"], data["max_hp"])), int(data["max_hp"])])
	if bool(rules["menu_shows_attack"]):
		lines.append("ATTACK  %d" % int(data["fight_damage"]))
	if bool(rules["menu_shows_defense"]):
		lines.append("DEFENSE  %d%%" % roundi(float(data["defense"])))
	for stat in data["stats"]:
		var shown: String = str(stat["value"])
		if str(stat["flag"]) != "":
			var value := float(flags.get(str(stat["flag"]), 0.0))
			shown = str(int(value)) if value == floorf(value) else str(snappedf(value, 0.01))
		lines.append("%s  %s" % [str(stat["name"]).to_upper(), shown])
	return lines


## The list of save slots, for saving or loading.
func _open_slots(mode: String, from_step := false) -> void:
	_menu_open = true
	_menu_mode = mode
	_menu_from_step = from_step
	_menu_at = 0
	_menu_rows = []
	var slots: Array = SaveGame.SLOTS if mode == "save" else [SaveGame.AUTOSAVE_SLOT] + SaveGame.SLOTS
	for slot in slots:
		_menu_rows.append({"kind": "slot", "slot": slot})
	_menu_rows.append({"kind": "close"})
	_menu_sound(SELECT_SOUND)
	menu_root.show()
	_refresh_menu()


func _open_options() -> void:
	_menu_mode = "options"
	_menu_at = 0
	_menu_rows = [
		{"kind": "volume", "key": "master_volume", "label": "MASTER"},
		{"kind": "volume", "key": "music_volume", "label": "MUSIC"},
		{"kind": "volume", "key": "sfx_volume", "label": "EFFECTS"},
		{"kind": "toggle", "key": "auto_run", "label": "AUTO RUN"},
		{"kind": "toggle", "key": "screen_shake", "label": "SCREEN SHAKE"},
		{"kind": "close"},
	]
	_refresh_menu()


func _close_menu() -> void:
	_menu_open = false
	menu_root.hide()
	_guard_this_press()


## BACK: out of a list to the tabs, or out of the menu.
func _menu_back() -> void:
	if _menu_mode == "main" or _menu_from_step:
		_close_menu()
		return
	var was_member: Variant = _menu_member if _menu_mode == "member" else null
	_show_tab()
	if was_member != null:
		_menu_at = maxi(locale["party"].find(was_member), 0)
	_refresh_menu()


func _use_slot(slot: int) -> void:
	if _menu_mode == "save":
		var err := SaveGame.write(locale, slot, _save_state())
		_menu_sound(SELECT_SOUND)
		if err != OK:
			push_warning("Couldn't save (error %d)" % err)
		_refresh_menu()
	elif not SaveGame.read(locale, slot).is_empty():
		load_slot = slot
		get_tree().change_scene_to_file(SCENE)


func _row_text(row: Dictionary) -> String:
	match row["kind"]:
		"item": return "%s x%d" % [row["item"]["name"], row["count"]]
		"member": return str(row["data"]["name"])
		"move": return "%s  %d TP" % [row["move"]["name"], int(row["move"].get("cost", 0))]
		"close": return "BACK"
		"quit": return "QUIT TO MENU"
		"save": return "SAVE"
		"load": return "LOAD"
		"options": return "OPTIONS"
		"slot": return SaveGame.describe(locale, row["slot"])
		"volume": return "%s  %d%%" % [row["label"], GameSettings.values[row["key"]]]
		"toggle": return "%s  %s" % [row["label"], "ON" if GameSettings.values[row["key"]] else "OFF"]
	return ""


func _menu_label(text: String, at: Vector2, color: Color, font_size := TEXT_SIZE, font: Font = FONT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.position = at
	return label


func _refresh_menu() -> void:
	if not _menu_open:
		return
	for child in menu_root.get_children():
		menu_root.remove_child(child)
		child.queue_free()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK
	style.border_color = Color.WHITE
	style.set_border_width_all(4)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(40, 40)
	panel.size = Vector2(560, 400)
	menu_root.add_child(panel)
	var top := 18.0
	if _menu_mode == "main":
		var tabs := _tabs()
		for i in tabs.size():
			var chosen: bool = i == _menu_tab
			panel.add_child(_menu_label(tabs[i], Vector2(24 + i * 150, 12), Color.YELLOW if chosen else Color(0.5, 0.5, 0.55), 16, MENU_FONT))
			if chosen:
				var line := ColorRect.new()
				line.color = Color.YELLOW
				line.position = Vector2(24 + i * 150, 32)
				line.size = Vector2(tabs[i].length() * 16, 2)
				panel.add_child(line)
		top = 46.0
		if _menu_rows.is_empty():
			panel.add_child(_menu_label("Nothing here yet.", Vector2(24, top), Color(0.6, 0.6, 0.65)))
	if _menu_mode == "member":
		top = _add_member_header(panel)
	var gap := 34.0
	for i in _menu_rows.size():
		var row: Dictionary = _menu_rows[i]
		var chosen: bool = i == _menu_at
		var row_at := Vector2(24, top + i * gap)
		if row["kind"] == "member":
			gap = 72.0
			row_at = Vector2(24, top + i * gap)
			_add_member_row(panel, row, row_at, chosen)
			continue
		panel.add_child(_menu_label(("> " if chosen else "  ") + _row_text(row), row_at, Color.YELLOW if chosen else Color.WHITE))
	if not _menu_rows.is_empty() and _menu_rows[_menu_at]["kind"] in ["item", "move"]:
		var chosen_row: Dictionary = _menu_rows[_menu_at]
		var words: String = chosen_row["item"]["description"] if chosen_row["kind"] == "item" else chosen_row["move"].get("description", "")
		var about := _menu_label(str(words), Vector2(24, 340), Color(0.75, 0.75, 0.8), 16)
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		about.size = Vector2(512, 30)
		panel.add_child(about)
	var hints := [["ACCEPT", "PICK"], ["BACK", "BACK"]]
	if _menu_mode == "main":
		hints = [["LEFT", ""], ["RIGHT", "TAB"], ["ACCEPT", "PICK"], ["BACK", "CLOSE"]]
	elif _menu_mode == "options":
		hints = [["LEFT", ""], ["RIGHT", "CHANGE"], ["BACK", "BACK"]]
	panel.add_child(_menu_label(GameSettings.hint(hints), Vector2(24, 374), Color(0.6, 0.6, 0.65), 8, MENU_FONT))


## Who's in the party: their picture and whether they're out with you.
func _add_member_row(panel: Control, row: Dictionary, at: Vector2, chosen: bool) -> void:
	var data: Dictionary = row["data"]
	panel.add_child(_member_picture(data, at + Vector2(0, -2)))
	panel.add_child(_menu_label(("> " if chosen else "  ") + str(data["name"]), at + Vector2(52, 0), Color.YELLOW if chosen else Color.WHITE))
	if bool(rules["menu_shows_hp"]):
		var hp := int(party_hp.get(data["name"], data["max_hp"]))
		var most := maxi(int(data["max_hp"]), 1)
		var bar_at := at + Vector2(90, 38)
		var empty := ColorRect.new()
		empty.color = Color(0.3, 0.1, 0.1)
		empty.position = bar_at
		empty.size = Vector2(160, 12)
		panel.add_child(empty)
		var full := ColorRect.new()
		full.color = Color.YELLOW
		full.position = bar_at
		full.size = Vector2(160.0 * clampf(float(hp) / most, 0.0, 1.0), 12)
		panel.add_child(full)
		panel.add_child(_menu_label("HP %d / %d" % [hp, most], at + Vector2(262, 34), Color.WHITE, 16))
	var tag := "WITH YOU" if row["with_you"] else "RESTING"
	panel.add_child(_menu_label(tag, at + Vector2(400, 8), Color(0.6, 0.6, 0.65), 16))


## The top of a member's page. Returns where the list of moves can start.
func _add_member_header(panel: Control) -> float:
	var data: Dictionary = _menu_member
	panel.add_child(_member_picture(data, Vector2(24, 16)))
	panel.add_child(_menu_label(str(data["name"]), Vector2(84, 12), Color.YELLOW))
	var lines := _stat_lines(data)
	for i in lines.size():
		panel.add_child(_menu_label(lines[i], Vector2(84 + (i % 2) * 220, 50 + (i / 2) * 22), Color.WHITE, 16))
	var top := 60.0 + ceilf(lines.size() / 2.0) * 22.0
	if bool(rules["menu_shows_moves"]):
		panel.add_child(_menu_label("MOVES", Vector2(24, top), Color(0.6, 0.6, 0.65), 16))
		top += 22.0
		if _menu_rows.is_empty():
			panel.add_child(_menu_label("None yet.", Vector2(24, top), Color(0.6, 0.6, 0.65)))
	return top


func _member_picture(data: Dictionary, at: Vector2) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.position = at
	picture.size = Vector2(48, 64)
	if str(data["sprite"]) != "":
		var atlas := AtlasTexture.new()
		atlas.atlas = ChartDefs.load_texture(str(data["sprite"]))
		atlas.region = LocaleDefs.frame_region(atlas.atlas, int(data["hframes"]), int(data["vframes"]), int(data["down_first"]))
		picture.texture = atlas
	else:
		picture.texture = Actor._blank_block(Color(str(data["blank_color"])), 16)
	return picture


func _menu_input(event: InputEvent) -> void:
	if GameSettings.pressed(event, "BACK") or GameSettings.pressed(event, "MENU") or event.is_action_pressed("ui_cancel"):
		_menu_sound(BACK_SOUND)
		_menu_back()
	elif GameSettings.pressed(event, "LEFT") or GameSettings.pressed(event, "RIGHT"):
		_menu_sideways(1 if GameSettings.pressed(event, "RIGHT") else -1)
	elif GameSettings.pressed(event, "UP") or GameSettings.pressed(event, "DOWN"):
		if not _menu_rows.is_empty():
			_menu_at = posmod(_menu_at + (1 if GameSettings.pressed(event, "DOWN") else -1), _menu_rows.size())
			_menu_sound(MOVE_SOUND)
			_refresh_menu()
	elif GameSettings.pressed(event, "ACCEPT") and not _menu_rows.is_empty():
		_menu_pick(_menu_rows[_menu_at])


## Left and right change tabs, or the setting that's chosen.
func _menu_sideways(step: int) -> void:
	if _menu_mode == "main":
		_menu_tab = posmod(_menu_tab + step, _tabs().size())
		_show_tab()
	elif _menu_mode == "options":
		var row: Dictionary = _menu_rows[_menu_at]
		if row["kind"] == "volume":
			GameSettings.change(row["key"], clampi(int(GameSettings.values[row["key"]]) + step * VOLUME_STEP, 0, 100))
		elif row["kind"] == "toggle":
			GameSettings.change(row["key"], not GameSettings.values[row["key"]])
	else:
		return
	_menu_sound(MOVE_SOUND)
	_refresh_menu()


func _menu_pick(row: Dictionary) -> void:
	match row["kind"]:
		"close":
			_menu_sound(BACK_SOUND)
			_menu_back()
		"save":
			_open_slots("save")
		"load":
			_open_slots("load")
		"options":
			_menu_sound(SELECT_SOUND)
			_open_options()
		"member":
			_open_member(row["data"])
		"toggle":
			_menu_sideways(1)
		"slot":
			_use_slot(row["slot"])
		"quit":
			get_tree().change_scene_to_file(return_scene)
		"item":
			var scene: Variant = LocaleDefs.find_cutscene(locale, int(row["item"]["use"]))
			if scene != null:
				_close_menu()
				_frames = [{"steps": scene["steps"], "at": 0}]
				_run_event()
