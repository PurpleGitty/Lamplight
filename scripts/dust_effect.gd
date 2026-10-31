class_name DustEffect
extends Node2D
## Turns a sprite into white dust: one particle per pixel of the sprite, starting
## as a solid white silhouette. The top rows drift up and away first, so the
## figure crumbles from the head down.

const CRUMBLE_TIME := 0.3 # time between the top row and the bottom row starting to move
const LIFETIME := 0.45 # how long each particle drifts before vanishing

var _start := PackedVector2Array()
var _velocity := PackedVector2Array()
var _delay := PackedFloat32Array()
var _pixel := 4.0
var _time := 0.0


## Builds the dust from `sprite`'s current frame, in its current place on screen.
static func from_sprite(sprite: Sprite2D) -> DustEffect:
	var dust := DustEffect.new()
	var image := sprite.texture.get_image()
	if image.is_compressed():
		image.decompress()
	var frame_size := Vector2i(image.get_width() / sprite.hframes, image.get_height() / sprite.vframes)
	var frame_origin := Vector2i(sprite.frame % sprite.hframes * frame_size.x, sprite.frame / sprite.hframes * frame_size.y)
	var xf := sprite.get_global_transform()
	dust._pixel = xf.get_scale().x
	for y in frame_size.y:
		for x in frame_size.x:
			if image.get_pixel(frame_origin.x + x, frame_origin.y + y).a < 0.5:
				continue
			var local := Vector2(x, y) + Vector2(0.5, 0.5) + sprite.offset
			if sprite.centered:
				local -= Vector2(frame_size) / 2
			dust._start.append(xf * local)
			dust._velocity.append(Vector2(randf_range(-30, 30), randf_range(-110, -35)))
			dust._delay.append(float(y) / frame_size.y * CRUMBLE_TIME + randf() * 0.06)
	return dust


func _process(delta: float) -> void:
	_time += delta
	if _time > CRUMBLE_TIME + 0.06 + LIFETIME:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var inverse := get_global_transform().affine_inverse()
	for i in _start.size():
		var age := maxf(_time - _delay[i], 0.0)
		var life := age / LIFETIME
		if life >= 1.0:
			continue
		# Particles accelerate upward as they go, and shrink and fade
		var pos := _start[i] + _velocity[i] * age + Vector2(0, -60) * age * age
		var size := lerpf(_pixel, 1.0, minf(life * 1.5, 1.0))
		var alpha := 1.0 - maxf(life - 0.4, 0.0) / 0.6
		draw_rect(Rect2(inverse * pos - Vector2.ONE * size / 2, Vector2.ONE * size), Color(1, 1, 1, alpha))
