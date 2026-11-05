extends CharacterBody2D
## The soul. Can only move during the enemy's turn, and checks for bullets
## every physics frame so standing inside one keeps hurting after i-frames.
## Keeping a bullet within the graze outline, 130% of the soul's size, gives TP
## every half of the soul's i-frame time, with a sound and a little "+2" each time.
## The soul is held inside the board by geometry, not physics walls, so a turning
## board can't sweep past it and leave it outside.

const GRAZE_SCALE := 1.3 # the graze range and its outline, compared to the soul
const OUTLINE_THICKNESS := 1.5
const FASTEST_GRAZE := 0.05 # seconds, if i-frames are turned right down
const BOARD_BORDER := Vector2(1, 1)
const OUTLINE_FADE := 4.0 # per second

@onready var battle: Battle = owner
@onready var hitbox: Area2D = $"bullet collision"
@onready var sprite: Sprite2D = $Soul

var invincible_time := 0.0
var graze_area := Area2D.new()
var _graze_shape := CircleShape2D.new()
var outline := Sprite2D.new()
var _graze_wait := 0.0 # seconds until a graze can pay out again
var _graze_radius := 0.0
var _half_size := Vector2.ZERO
var _default_texture: Texture2D
var _look := "" # the sprite and frames the outlines were traced from
@onready var _collider: CollisionShape2D = $"bullet collision/collider"
var _outlines: Array[Texture2D] = [] # one per soul frame


func _ready() -> void:
	var shape := CollisionShape2D.new()
	shape.shape = _graze_shape
	graze_area.add_child(shape)
	add_child(graze_area)
	collision_mask = 0 # _keep_in_board does this job
	_default_texture = sprite.texture
	_collider.shape = _collider.shape.duplicate() # the rules can resize it
	_build_outlines()
	outline.position = sprite.position
	outline.z_index = sprite.z_index
	outline.modulate.a = 0.0
	add_child(outline)


## Puts the sprite and hitbox from the rules into effect.
func set_look(rules: Dictionary) -> void:
	var look := "%s/%d" % [rules["soul_sprite"], rules["soul_hframes"]]
	if look != _look:
		_look = look
		sprite.frame = 0
		sprite.texture = ChartDefs.load_texture(rules["soul_sprite"]) if rules["soul_sprite"] != "" else _default_texture
		sprite.hframes = maxi(int(rules["soul_hframes"]), 1)
		_build_outlines()
	_collider.shape.size = Vector2(rules["soul_hitbox_w"], rules["soul_hitbox_h"])
	_collider.position = Vector2(rules["soul_hitbox_x"], rules["soul_hitbox_y"])


func frame_size() -> Vector2:
	return sprite.texture.get_size() / Vector2(sprite.hframes, 1)


## Traces each soul frame's silhouette at the size of the graze range.
func _build_outlines() -> void:
	var image := sprite.texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var size := Vector2i(frame_size())
	var longest := float(maxi(size.x, size.y))
	_graze_radius = longest * GRAZE_SCALE / 2.0
	_half_size = frame_size() / 2.0 + BOARD_BORDER
	var reach := (GRAZE_SCALE - 1.0) * longest / 2.0 # pixels out from the art
	var margin := ceili(reach) + 1
	_outlines.clear()
	for f in sprite.hframes:
		var width := size.x + margin * 2
		var height := size.y + margin * 2
		var distances := _distances_to_art(image, f, size, margin)
		var traced := Image.create(width, height, false, Image.FORMAT_RGBA8)
		for y in height:
			for x in width:
				var distance: float = distances[y * width + x]
				if distance <= reach and distance > reach - OUTLINE_THICKNESS:
					traced.set_pixel(x, y, Color.WHITE)
		_outlines.append(ImageTexture.create_from_image(traced))


## How far every pixel is from the art, worked out in one sweep each way so a big
## sprite doesn't take long.
func _distances_to_art(image: Image, frame_index: int, size: Vector2i, margin: int) -> PackedFloat32Array:
	var width := size.x + margin * 2
	var height := size.y + margin * 2
	var distances := PackedFloat32Array()
	distances.resize(width * height)
	for y in height:
		for x in width:
			distances[y * width + x] = 0.0 if _solid(image, frame_index, size, x - margin, y - margin) else INF
	var diagonal := sqrt(2.0)
	var before := [[-1, 0, 1.0], [0, -1, 1.0], [-1, -1, diagonal], [1, -1, diagonal]]
	var after := [[1, 0, 1.0], [0, 1, 1.0], [1, 1, diagonal], [-1, 1, diagonal]]
	for sweep in [[before, range(height), range(width)], [after, range(height - 1, -1, -1), range(width - 1, -1, -1)]]:
		for y in sweep[1]:
			for x in sweep[2]:
				var best: float = distances[y * width + x]
				for step in sweep[0]:
					var nx: int = x + step[0]
					var ny: int = y + step[1]
					if nx >= 0 and ny >= 0 and nx < width and ny < height:
						best = minf(best, distances[ny * width + nx] + step[2])
				distances[y * width + x] = best
	return distances


func _solid(image: Image, frame_index: int, size: Vector2i, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return false
	return image.get_pixel(frame_index * size.x + x, y).a > 0.5


func _process(delta: float) -> void:
	outline.texture = _outlines[sprite.frame]
	outline.modulate.a = maxf(outline.modulate.a - OUTLINE_FADE * delta, 0.0)


## Holds the soul inside the board, however it's turned, sized or moving.
func _keep_in_board() -> void:
	var runtime: AttackRuntime = battle.board.runtime
	if runtime == null:
		return
	var box := runtime.board_transform()
	var local := box.affine_inverse() * global_position
	var half: Vector2 = (battle.board.current_size() / 2 - _half_size).max(Vector2.ZERO)
	var inside := local.clamp(-half, half)
	if inside != local:
		global_position = box * inside


func _physics_process(delta: float) -> void:
	# Stay put until the board has finished opening, so the walls can't shut you out
	if battle.phase != Battle.Phase.ENEMY or not battle.board.is_open():
		return

	var direction := Input.get_vector("LEFT", "RIGHT", "UP", "DOWN")
	velocity = direction * battle.rules["soul_speed"] * battle.mod("soul_speed")
	_graze_shape.radius = _graze_radius * battle.mod("graze_radius")
	outline.scale = Vector2.ONE * battle.mod("graze_radius")
	_graze_wait = maxf(_graze_wait - delta, 0.0)
	move_and_slide()
	_keep_in_board()
	var moving := direction != Vector2.ZERO

	var touching := hitbox.get_overlapping_areas()
	if invincible_time > 0.0:
		invincible_time -= delta
		# Flicker between the two soul frames while invincible
		sprite.frame = 1 if sprite.hframes > 1 and invincible_time > 0.0 and fmod(invincible_time, 0.2) >= 0.1 else 0
	else:
		for area in touching:
			if _is_bullet(area) and _hurts(area, moving):
				battle.damage_party(area.damage, area.source_name)
				battle.get_node("AudioStreamPlayer2D").play()
				invincible_time = battle.rules["invincibility"] * battle.mod("invincibility")
				return

	for area in graze_area.get_overlapping_areas():
		if _is_bullet(area) and area not in touching:
			_graze()
			break


## Something's in range: the outline shows, and it pays out every half i-frame time.
func _graze() -> void:
	outline.modulate.a = 1.0
	if _graze_wait > 0.0:
		return
	_graze_wait = maxf(battle.rules["invincibility"] * battle.mod("invincibility") / 2.0, FASTEST_GRAZE)
	battle.earn_tp(battle.rules["graze_tp"])
	battle.get_node("Txt").play()
	sprite.self_modulate = Color(3, 3, 3) # bright flash
	create_tween().tween_property(sprite, "self_modulate", Color.WHITE, 0.2)
	if battle.rules["tp_enabled"]:
		_tp_popup(battle.rules["graze_tp"] * battle.mod("tp_gain"))


## A little "+2" floating off the soul.
func _tp_popup(amount: float) -> void:
	var popup := Label.new()
	popup.text = "+%d" % roundi(amount)
	popup.add_theme_font_override("font", preload("res://fonts/PixelOperator.ttf"))
	popup.add_theme_color_override("font_color", Color.YELLOW)
	popup.add_theme_constant_override("outline_size", 4)
	popup.add_theme_color_override("font_outline_color", Color.BLACK)
	popup.position = global_position + Vector2(8, -22)
	popup.z_index = 6
	battle.add_child(popup)
	var t := popup.create_tween().set_parallel()
	t.tween_property(popup, "position:y", popup.position.y - 16, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(popup, "modulate:a", 0.0, 0.5).set_delay(0.15)
	t.chain().tween_callback(popup.queue_free)


func _is_bullet(area: Area2D) -> bool:
	return "damage" in area and area.get("harmful") != false and area.is_visible_in_tree()


## Blue objects only hurt if you're moving; orange only if you're standing still.
func _hurts(area: Area2D, moving: bool) -> bool:
	match area.get("mode"):
		"blue": return moving
		"orange": return not moving
	return true


func reset(at := Vector2.ZERO) -> void:
	position = at
	velocity = Vector2.ZERO
	invincible_time = 0.0
	_graze_wait = 0.0
	sprite.frame = 0
