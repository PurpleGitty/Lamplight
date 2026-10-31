class_name AttackObject
extends Area2D
## One object from an attack chart (a bullet, a blade, a crescent...). The
## board moves it each frame from the AttackRuntime; this just holds its
## sprite and hitbox and tells the soul how much it hurts.

var damage := 20
var source_name := "a bullet" # shown as the cause of death on the game over screen
var harmful := true
var sprite := Sprite2D.new()
var hitbox := CollisionShape2D.new()


func setup(data: Dictionary, enemy_name: String) -> void:
	sprite.texture = ChartDefs.load_texture(data["sprite"])
	sprite.hframes = maxi(int(data["hframes"]), 1)
	sprite.frame = clampi(int(data["frame"]), 0, sprite.hframes - 1)
	sprite.self_modulate = Color(data["tint"])
	add_child(sprite)

	# The node itself is scaled by sprite_scale, so undo that for the hitbox
	# (hitbox sizes in the chart are in screen pixels)
	var shape := RectangleShape2D.new()
	var s: float = maxf(data["sprite_scale"], 0.001)
	shape.size = Vector2(data["hitbox_w"], data["hitbox_h"]) / s
	hitbox.shape = shape
	add_child(hitbox)

	damage = int(data["damage"])
	source_name = "%s's %s" % [enemy_name, data["name"]]
