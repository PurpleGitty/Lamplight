class_name AttackObject
extends Area2D
## One object from an attack chart (a bullet, a blade, a crescent...). The
## board moves it each frame from the AttackRuntime; this just holds its
## sprite and hitbox and tells the soul how much it hurts.

var damage := 20
var source_name := "a bullet" # shown as the cause of death on the game over screen
var harmful := true
var mode := "normal" # normal, blue (hurts if you move), orange (hurts if you stay still)
var sprite := Sprite2D.new()
var sprite_path := "" # the file it's showing, so Change Objects can swap it
var hitbox := CollisionShape2D.new()


func setup(data: Dictionary, enemy_name: String) -> void:
	sprite_path = data["sprite"]
	sprite.texture = ChartDefs.load_texture(sprite_path)
	sprite.hframes = maxi(int(data["hframes"]), 1)
	sprite.frame = clampi(int(data["frame"]), 0, sprite.hframes - 1)
	sprite.self_modulate = Color(data["tint"])
	add_child(sprite)

	# The node itself is scaled by sprite_scale, so undo that for the hitbox
	# (hitbox sizes in the chart are in screen pixels)
	var s: float = maxf(data["sprite_scale"], 0.001)
	if data.get("hitbox_shape", "box") == "circle":
		var circle := CircleShape2D.new()
		circle.radius = float(data["hitbox_w"]) / 2.0 / s
		hitbox.shape = circle
	else:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(data["hitbox_w"], data["hitbox_h"]) / s
		hitbox.shape = shape
	hitbox.position = Vector2(data["hitbox_x"], data["hitbox_y"]) / s
	add_child(hitbox)

	damage = int(data["damage"])
	source_name = "%s's %s" % [enemy_name, data["name"]]
	afterimages = data.get("afterimages", false) and GameSettings.values["fx_trails"]


const AFTERIMAGE_TIME := 0.2 # seconds a copy takes to fade
const AFTERIMAGE_ALPHA := 0.5
var afterimages := false
var _last_place := Transform2D()


## Afterimages: a fading copy left behind each frame it moves or turns.
func _process(_delta: float) -> void:
	if not afterimages or not is_visible_in_tree():
		_last_place = transform
		return
	if transform.is_equal_approx(_last_place):
		return
	_last_place = transform
	var ghost := Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.hframes = sprite.hframes
	ghost.frame = sprite.frame
	ghost.transform = transform
	ghost.self_modulate = Color(1, 1, 1, AFTERIMAGE_ALPHA * modulate.a)
	get_parent().add_child(ghost)
	get_parent().move_child(ghost, get_index())
	var t := ghost.create_tween()
	t.tween_property(ghost, "self_modulate:a", 0.0, AFTERIMAGE_TIME)
	t.tween_callback(ghost.queue_free)


const MODE_TINT = preload("res://shaders/mode_tint.gdshader")
const BLUE := Color(0.3, 0.7, 1.0)
const ORANGE := Color(1.0, 0.65, 0.2)


## Blue and orange objects are recoloured so the player can tell them apart.
func set_look(new_mode: String, tint: String) -> void:
	sprite.self_modulate = Color(tint)
	if new_mode == mode and (mode == "normal" or sprite.material != null):
		return
	mode = new_mode
	if mode == "normal":
		sprite.material = null
		return
	var recolor := ShaderMaterial.new()
	recolor.shader = MODE_TINT
	recolor.set_shader_parameter("mode_color", BLUE if mode == "blue" else ORANGE)
	sprite.material = recolor
