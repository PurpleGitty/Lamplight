extends CharacterBody2D
## The soul. Can only move during the enemy's turn, and checks for bullets
## every physics frame so standing inside one keeps hurting after i-frames.
## Passing close to a bullet without touching it (grazing) gives TP.

const GRAZE_RADIUS := 16.0

@onready var battle: Battle = owner
@onready var hitbox: Area2D = $"bullet collision"
@onready var sprite: Sprite2D = $Soul

var invincible_time := 0.0
var graze_area := Area2D.new()


func _ready() -> void:
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = GRAZE_RADIUS
	graze_area.add_child(shape)
	add_child(graze_area)


func _physics_process(delta: float) -> void:
	# Stay put until the board has finished opening, so the walls can't shut you out
	if battle.phase != Battle.Phase.ENEMY or not battle.board.is_open():
		return

	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * battle.rules["soul_speed"]
	move_and_slide()
	var moving := direction != Vector2.ZERO

	var touching := hitbox.get_overlapping_areas()
	if invincible_time > 0.0:
		invincible_time -= delta
		# Flicker between the two soul frames while invincible
		sprite.frame = 1 if invincible_time > 0.0 and fmod(invincible_time, 0.2) >= 0.1 else 0
	else:
		for area in touching:
			if _is_bullet(area) and _hurts(area, moving):
				battle.damage_party(area.damage, area.source_name)
				battle.get_node("AudioStreamPlayer2D").play()
				invincible_time = battle.rules["invincibility"]
				return

	for area in graze_area.get_overlapping_areas():
		if not _is_bullet(area) or area in touching:
			continue
		if not area.has_meta("grazed"):
			area.set_meta("grazed", true)
			battle.add_tp(battle.rules["graze_tp"])
			battle.get_node("Txt").play()
			sprite.self_modulate = Color(3, 3, 3) # bright flash
			create_tween().tween_property(sprite, "self_modulate", Color.WHITE, 0.2)
		else:
			battle.add_tp(battle.rules["graze_tp_per_second"] * delta)


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
	sprite.frame = 0
