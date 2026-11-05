extends Control
## The tool wheel, in the corner of the room view: tools fanned out around a point just
## off screen. With the mouse over it, the wheel spins them smoothly and endlessly, and
## whichever's at the front sticks out the furthest. [LMB] on one picks it directly.
##
## Art goes in sprites/tool_wheel/<tool id>.png, drawn pointing right with the handle end
## on the left. Until then they're coloured bars with their names on.

const FONT = preload("res://fonts/PixelOperator.ttf")
const ART_FOLDER := "res://sprites/tool_wheel/"
## [id, name, colour]
const TOOLS := [
	["select", "selector", Color("5aa0ff")],
	["paint", "pencil", Color("ff2020")],
	["erase", "eraser", Color("ffb8c8")],
	["eyedropper", "eyedrop", Color("ffa000")],
	["fill", "bucket", Color("eeff00")],
	["shape", "shape", Color("00ff30")],
	["contour", "contour", Color("c070ff")],
]
const SPACING := deg_to_rad(20.0)
const FRONT_ANGLE := deg_to_rad(-48.0) # where the chosen tool points
const SHORT := 120.0
const EXTRA := 130.0 # how much further the front one sticks out
const BAR_WIDTH := 38.0
const SPIN_SPEED := 14.0
const CORNER_OFFSET := Vector2(-6, 6)

var editor
var target := 0 # counts up and down forever; the tool's this, wrapped round
var shown := 0.0 # where the wheel's got to, chasing target
var _art := {}


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	for tool_entry in TOOLS:
		var path: String = ART_FOLDER + tool_entry[0] + ".png"
		if ResourceLoader.exists(path):
			_art[tool_entry[0]] = load(path)


func _process(delta: float) -> void:
	if not is_equal_approx(shown, float(target)):
		shown = lerpf(shown, float(target), 1.0 - exp(-SPIN_SPEED * delta))
		if absf(shown - target) < 0.002:
			shown = float(target)
		queue_redraw()


func current_id() -> String:
	return TOOLS[posmod(target, TOOLS.size())][0]


## Turns the shortest way round to a tool.
func turn_to(id: String) -> void:
	for i in TOOLS.size():
		if TOOLS[i][0] == id:
			target += roundi(_wrapped(i - posmod(target, TOOLS.size())))
	queue_redraw()


func _wrapped(steps: float) -> float:
	var count := float(TOOLS.size())
	return wrapf(steps, -count / 2.0, count / 2.0)


func _pivot() -> Vector2:
	return Vector2(0, size.y) + CORNER_OFFSET


## How far round a tool is from the front, in radians.
func _offset_of(index: int) -> float:
	return _wrapped(index - shown) * SPACING


func _length_of(offset: float) -> float:
	var closeness := 1.0 - clampf(absf(offset) / (SPACING * 2.0), 0.0, 1.0)
	return SHORT + EXTRA * smoothstep(0.0, 1.0, closeness)


## Which tool's under a point (-1 if none). The nearest the front wins, since it's on top.
func _tool_at(point: Vector2) -> int:
	var found := -1
	var best := INF
	for i in TOOLS.size():
		var offset := _offset_of(i)
		var local := (point - _pivot()).rotated(-(FRONT_ANGLE + offset))
		if local.x >= 0.0 and local.x <= _length_of(offset) and absf(local.y) <= BAR_WIDTH / 2.0 and absf(offset) < best:
			best = absf(offset)
			found = i
	return found


## Only the wheel itself catches the mouse, so drawing right next to it still works.
func _has_point(point: Vector2) -> bool:
	return visible and _tool_at(point) >= 0


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_spin(1)
		MOUSE_BUTTON_WHEEL_DOWN:
			_spin(-1)
		MOUSE_BUTTON_LEFT:
			var picked := _tool_at(event.position)
			if picked >= 0:
				editor.set_tool(TOOLS[picked][0])
	accept_event()


func _spin(by: int) -> void:
	target += by
	editor.set_tool(current_id())
	queue_redraw()


func _draw() -> void:
	# Furthest from the front first, so the chosen one ends up on top
	var order := range(TOOLS.size())
	order.sort_custom(func(a, b): return absf(_offset_of(a)) > absf(_offset_of(b)))
	for i in order:
		var offset := _offset_of(i)
		var length := _length_of(offset)
		var entry: Array = TOOLS[i]
		draw_set_transform(_pivot(), FRONT_ANGLE + offset)
		var bar := Rect2(0, -BAR_WIDTH / 2.0, length, BAR_WIDTH)
		if _art.has(entry[0]):
			draw_texture_rect(_art[entry[0]], bar, false)
			continue
		draw_rect(bar, entry[2])
		var chosen: bool = entry[0] == current_id()
		draw_rect(bar, Color.WHITE if chosen else Color(0, 0, 0, 0.6), false, 2.0)
		draw_string(FONT, Vector2(length - 8.0 - 120.0, 8), entry[1], HORIZONTAL_ALIGNMENT_RIGHT, 120.0, 24, Color.BLACK)
	draw_set_transform(Vector2.ZERO)
