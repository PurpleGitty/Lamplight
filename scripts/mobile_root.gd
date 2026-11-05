class_name MobileRoot
extends Control
## The phone version's first scene. Normally the game's view fills the window, and
## anything outside 640 x 480 is black bars nothing can draw on. Here, the game runs inside
## a 640 x 480 view of its own in the middle, so the real screen's edges are free for
## the touch controls.

const SIZE := Vector2(640, 480)

var container := SubViewportContainer.new()
var game_view := SubViewport.new()
var controls := TouchControls.new()


func _ready() -> void:
	GameSettings.mobile = true
	GameSettings.device = "touch"
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	# Fingers stay fingers, so two at once work and a thumb on a button doesn't click the menu
	Input.emulate_mouse_from_touch = false
	get_tree().quit_on_go_back = false
	Engine.max_fps = GameSettings.values["fps"]

	set_anchors_preset(PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(PRESET_FULL_RECT)
	black.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(black)

	game_view.size = Vector2i(SIZE)
	game_view.disable_3d = true
	game_view.audio_listener_enable_2d = true
	game_view.handle_input_locally = false
	game_view.canvas_item_default_texture_filter = int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1)) as Viewport.DefaultCanvasItemTextureFilter
	container.mouse_filter = MOUSE_FILTER_STOP
	container.size = SIZE
	container.add_child(game_view)
	add_child(container)
	add_child(controls)

	resized.connect(_fit)
	GameSettings.settings_changed.connect(_fit)
	_fit()
	GameSettings.game_holder = game_view
	GameSettings.go_to("res://boot_screen.tscn")


## Scales the game to the screen's height, in whole numbers if pixel perfect's on.
func _fit() -> void:
	var fits := minf(size.x / SIZE.x, size.y / SIZE.y)
	if fits <= 0.0:
		return
	if GameSettings.values["pixel_perfect"] and fits >= 1.0:
		fits = floorf(fits)
	var shown := SIZE * fits
	container.scale = Vector2(fits, fits)
	container.size = SIZE
	container.position = ((size - shown) / 2.0).floor()
	controls.game_area = Rect2(container.position, shown)
	controls.position = Vector2.ZERO
	controls.size = size
	controls._refresh()
