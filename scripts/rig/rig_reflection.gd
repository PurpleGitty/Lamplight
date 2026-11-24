class_name RigReflection
extends CanvasGroup
## A character built from pieces, reflected in a shiny floor: drawn upside down from the
## spot they stand on, see-through, and fading out further down. Add it to the character,
## so it moves, fades and flashes with them.

const FADE = preload("res://shaders/ground_reflection.gdshader")
const FADE_LENGTH := 60.0 # pixels (before the character's scale) until it's gone

var mirrored := RigSprite.new()
var _fade := ShaderMaterial.new()


func _init(rig: Dictionary) -> void:
	mirrored.rig = rig
	mirrored.scale = Vector2(1, -1)
	add_child(mirrored)
	_fade.shader = FADE
	material = _fade


func _process(_delta: float) -> void:
	# The fade's measured on screen, from where they stand
	var on_screen := get_global_transform_with_canvas()
	_fade.set_shader_parameter("ground_y", (on_screen * Vector2.ZERO).y)
	_fade.set_shader_parameter("fade_length", FADE_LENGTH * on_screen.get_scale().y)
