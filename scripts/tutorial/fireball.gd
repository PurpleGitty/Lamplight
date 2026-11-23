class_name Fireball
extends Area2D
## A falling fireball in the tutorial. It hurts and grazes like any bullet (the soul goes
## by `damage`, `harmful` and `mode`), falls straight down, and says when it's dropped
## out of the bottom of the board. A wall is a row of them that can't be dodged.

signal landed

const ART = preload("res://sprites/tutorial/fireball.png")
const FRAMES := 4 # one loop a beat
const FLAME_WIDTH := 8.0
const HITBOX := Vector2(6, 6)
const HITBOX_OFFSET := Vector2(0, 4) # the ball of fire, not the flames trailing off it

var damage := 25
var harmful := true
var mode := "normal"
var source_name := "a fireball"
var speed := 100.0
## Where it's left the board, in the board's own frame.
var floor_y := 84.0
## Whether getting past it counts toward a dodging streak.
var counts := true
var _sprites: Array[Sprite2D] = []


func _init() -> void:
	_add_flame(Vector2.ZERO)
	var shape := RectangleShape2D.new()
	shape.size = HITBOX
	var hitbox := CollisionShape2D.new()
	hitbox.shape = shape
	hitbox.position = HITBOX_OFFSET
	add_child(hitbox)


## A row of fireballs as wide as this, all one hit.
static func wall(width: float, wall_damage: int, wall_speed: float) -> Fireball:
	var row := Fireball.new()
	row.damage = wall_damage
	row.speed = wall_speed
	row.source_name = "a wall of fire"
	for child in row.get_children():
		if child is CollisionShape2D:
			child.shape.size = Vector2(width, 8)
	var count := ceili(width / FLAME_WIDTH)
	for i in count:
		row._add_flame(Vector2(-width / 2.0 + FLAME_WIDTH / 2.0 + i * FLAME_WIDTH, 0))
	row._sprites[0].hide() # the middle one's replaced by the row
	return row


func _add_flame(at: Vector2) -> void:
	var flame := Sprite2D.new()
	flame.texture = ART
	flame.hframes = FRAMES
	flame.position = at
	flame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(flame)
	_sprites.append(flame)


func _physics_process(delta: float) -> void:
	position.y += speed * delta
	var song := Conductor.current
	var frame := floori(fposmod(song.song_beat, 1.0) * FRAMES) if song != null and song.playing else 0
	for i in _sprites.size():
		_sprites[i].frame = (frame + i) % FRAMES
	if position.y > floor_y:
		set_physics_process(false)
		landed.emit()
