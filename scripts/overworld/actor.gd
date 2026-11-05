class_name Actor
extends Node2D
## Something standing in the overworld: the player, a party member, an NPC or a
## sprite. Its position is its feet, so sorting by y puts it in front of or behind
## other things properly.

var data: Dictionary # a character from the party, or an object
var is_directional := false
var facing := "down"
var sprite := Sprite2D.new()
var moving_time := -1.0 # how long it's been walking; below 0, it's standing
var speed_up := 1.0
var anim_time := 0.0
var sliding_to := Vector2.ZERO
var slide_speed := 0.0
var running := false
var foot_gap := 0 # empty rows under the art in its frames
var on_path := false # a cutscene's walking them, so don't follow the leader
var _anim_on := false
var _anim_first := 0
var _anim_count := 1
var _anim_fps := 8.0
var _anim_loop := false
var _anim_hold := false
var _anim_time := 0.0


func setup(new_data: Dictionary, directional: bool, tile_size := 16) -> void:
	data = new_data
	is_directional = directional
	add_child(sprite)
	sprite.centered = false
	var path := str(data.get("sprite", ""))
	if path != "":
		sprite.texture = ChartDefs.load_texture(path)
	elif data.has("blank_color"):
		sprite.texture = _blank_block(Color(str(data["blank_color"])), tile_size)
	else:
		sprite.texture = preload("res://sprites/pellet.png")
	sprite.hframes = maxi(int(data.get("hframes", 1)), 1)
	sprite.vframes = maxi(int(data.get("vframes", 1)), 1)
	sprite.scale = Vector2.ONE * float(data.get("scale", 1.0))
	if data.has("facing"):
		facing = str(data["facing"])
	var size: Vector2 = sprite.texture.get_size() / Vector2(sprite.hframes, sprite.vframes) * sprite.scale
	_show_frame()
	foot_gap = LocaleDefs.bottom_gap(sprite.texture, LocaleDefs.frame_region(sprite.texture, sprite.hframes, sprite.vframes, sprite.frame))
	sprite.position = Vector2(-size.x / 2.0, -size.y + foot_gap * sprite.scale.y)


## A character with no sprite: a plain block, one tile wide and two tall.
static func _blank_block(color: Color, tile_size: int) -> Texture2D:
	var image := Image.create(tile_size, tile_size * 2, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


## Plays frames instead of whatever it'd normally show.
func play_frames(first: int, count: int, fps: float, loop: bool, hold: bool) -> void:
	_anim_on = true
	_anim_first = first
	_anim_count = maxi(count, 1)
	_anim_fps = maxf(fps, 0.1)
	_anim_loop = loop
	_anim_hold = hold
	_anim_time = 0.0


func stop_frames() -> void:
	_anim_on = false


## Whether a one-off animation's still going.
func is_animating() -> bool:
	return _anim_on and not _anim_loop and _anim_time * _anim_fps < _anim_count


func face(direction: String) -> void:
	if direction in LocaleDefs.DIRECTIONS:
		facing = direction


func face_toward(point: Vector2) -> void:
	var off := point - position
	if absf(off.x) > absf(off.y):
		facing = "right" if off.x > 0.0 else "left"
	elif off.y != 0.0:
		facing = "down" if off.y > 0.0 else "up"


## Walks over `distance` this frame: only for showing the animation.
func set_walking(walking: bool, delta: float, fast := 1.0, is_running := false) -> void:
	speed_up = fast
	running = is_running
	moving_time = (maxf(moving_time, 0.0) + delta) if walking else -1.0


func _process(delta: float) -> void:
	if slide_speed > 0.0:
		var before := position
		position = position.move_toward(sliding_to, slide_speed * delta)
		face_toward(position + (position - before))
		set_walking(true, delta)
		if position.is_equal_approx(sliding_to):
			slide_speed = 0.0
			set_walking(false, delta)
	if not is_directional:
		anim_time += delta
	if _anim_on:
		_anim_time += delta
		if not _anim_loop and not _anim_hold and _anim_time * _anim_fps >= _anim_count:
			_anim_on = false
	_show_frame()


func is_sliding() -> bool:
	return slide_speed > 0.0


func slide_to(point: Vector2, speed: float) -> void:
	sliding_to = point
	slide_speed = maxf(speed, 1.0)


func _show_frame() -> void:
	if sprite.texture == null:
		return
	if _anim_on:
		var step := floori(_anim_time * _anim_fps)
		var along := posmod(step, _anim_count) if _anim_loop else mini(step, _anim_count - 1)
		sprite.frame = posmod(_anim_first + along, sprite.hframes * sprite.vframes)
	elif is_directional:
		var shown := LocaleDefs.direction_frame(data, facing, moving_time, speed_up, running)
		sprite.frame = posmod(int(shown["frame"]), sprite.hframes * sprite.vframes)
		sprite.flip_h = shown["mirrored"]
	else:
		var count := maxi(int(data.get("anim_count", 1)), 1)
		var first := int(data.get("frame", 0))
		var frame := first + (posmod(floori(anim_time * float(data.get("fps", 0.0))), count) if count > 1 else 0)
		sprite.frame = posmod(frame, sprite.hframes * sprite.vframes)


## The box it blocks and can be reached from, in world coordinates.
func hit_box() -> Rect2:
	var box := Vector2(float(data.get("hit_w", 16.0)), float(data.get("hit_h", 8.0)))
	return Rect2(position - box / 2.0, box)


## Draws its shadow, if it has one and it's showing.
func draw_shadow_on(canvas: CanvasItem, rules: Dictionary) -> void:
	if not visible or not data.get("shadow", false) or sprite.texture == null:
		return
	var region := LocaleDefs.frame_region(sprite.texture, sprite.hframes, sprite.vframes, sprite.frame)
	LocaleDefs.draw_shadow(canvas, Transform2D.IDENTITY, sprite.texture, region, position, sprite.scale.x, rules, sprite.flip_h, foot_gap)


## How wide it is for bumping into walls.
func body_width() -> float:
	var set_width := float(data.get("box_width", 0.0))
	if set_width > 0.0:
		return set_width
	return sprite.texture.get_width() / float(sprite.hframes) * sprite.scale.x
