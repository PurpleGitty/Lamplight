class_name TouchControls
extends Control
## The on-screen controls on phones: A, B and Y, and a d-pad and/or joystick. They sit in
## the space beside the game on a wide screen and go see-through over it on a narrow one.
## Sized in real millimetres, so they fit a thumb however many pixels the screen has. A
## connected controller hides them all.

const BUTTONS := [["ACCEPT", "A"], ["BACK", "B"], ["MENU", "Y"]]
const BUTTON_MM := 12.0
const STICK_MM := 24.0
const EDGE_MM := 3.0
const MAX_BUTTON_SHARE := 0.2 # of the screen's height, on small screens
const MAX_STICK_SHARE := 0.42
const FALLBACK_DPI := 300.0 # for a phone that reports something silly
const SIZES := {"SMALL": 0.8, "MEDIUM": 1.0, "LARGE": 1.25}
const DEAD_ZONE := 0.22
const PRESS_AT := 0.5 # how far a joystick goes before it counts as a direction
const FILL := Color(1, 1, 1, 0.14)
const LINE := Color(1, 1, 1, 0.55)
const HELD := Color(1, 1, 0.3, 0.45)

## For testing screen sizes on a PC, where the monitor's own size would be misleading.
static var test_dpi := 0.0

var game_area := Rect2() # where the game is on screen, set by MobileRoot
var button_spots := {} # action -> centre
var button_radius := 40.0
var stick_center := Vector2.ZERO
var stick_radius := 80.0
var knob := Vector2.ZERO # -1 to 1 on each axis
var _fingers := {} # finger -> what it's on: an action name, "stick" or "dpad"
var _held := {} # direction actions down right now


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	Input.joy_connection_changed.connect(func(_device, _connected): _refresh())
	GameSettings.settings_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	# Auto swaps between d-pad and joystick when the scene changes
	var kind := _stick_kind()
	if kind != _last_kind:
		_release_directions()
		_last_kind = kind
		queue_redraw()

var _last_kind := ""


## d-pad or joystick, for what's on screen now.
func _stick_kind() -> String:
	match str(GameSettings.values["touch_stick"]):
		"DPAD": return "dpad"
		"JOYSTICK": return "stick"
	return "stick" if GameSettings.in_action_scene() else "dpad"


func _dpi() -> float:
	if test_dpi > 0.0:
		return test_dpi
	var dpi := float(DisplayServer.screen_get_dpi())
	return dpi if dpi >= 100.0 else FALLBACK_DPI


func _shown() -> bool:
	return Input.get_connected_joypads().is_empty()


## Works out where everything goes, for this screen.
func _refresh() -> void:
	visible = _shown()
	if not visible:
		_release_all()
	var mm := _dpi() / 25.4
	var scaled: float = SIZES.get(str(GameSettings.values["touch_size"]), 1.0)
	var height := size.y
	button_radius = minf(BUTTON_MM * mm * scaled, height * MAX_BUTTON_SHARE) / 2.0
	stick_radius = minf(STICK_MM * mm * scaled, height * MAX_STICK_SHARE) / 2.0
	var edge := EDGE_MM * mm
	stick_center = Vector2(edge + stick_radius, height - edge - stick_radius)
	# A, B and Y: a triangle if there's room beside the game, or a zigzag up the edge
	var bar := maxf(size.x - game_area.end.x, 0.0)
	var d := button_radius * 2.0
	var a := Vector2(size.x - edge - button_radius, height - edge - button_radius)
	var gap := button_radius * 0.3
	if bar >= d * 2.0 + gap + edge:
		button_spots = {"ACCEPT": a, "BACK": a + Vector2(-d - gap, button_radius * 0.3), "MENU": a + Vector2(-button_radius * 0.5, -d - gap)}
	else:
		button_spots = {"ACCEPT": a, "BACK": a + Vector2(-button_radius * 0.9, -d - gap * 0.3), "MENU": a + Vector2(0, (-d - gap * 0.3) * 2.0)}
	queue_redraw()


# --- fingers ---

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var on := _control_at(event.position)
			if on != "":
				_fingers[event.index] = on
				_press(on, event.position)
				get_viewport().set_input_as_handled()
		elif _fingers.has(event.index):
			_lift(_fingers[event.index])
			_fingers.erase(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _fingers.has(event.index):
		var on: String = _fingers[event.index]
		if on == "stick" or on == "dpad":
			_aim(event.position)
		get_viewport().set_input_as_handled()


func _control_at(point: Vector2) -> String:
	for action in button_spots:
		if point.distance_to(button_spots[action]) <= button_radius * 1.15:
			return action
	if point.distance_to(stick_center) <= stick_radius * 1.3:
		return _stick_kind()
	return ""


func _press(on: String, point: Vector2) -> void:
	if on == "stick" or on == "dpad":
		_aim(point)
	else:
		GameSettings.send_action(on, true)
	queue_redraw()


func _lift(on: String) -> void:
	if on == "stick" or on == "dpad":
		_release_directions()
	else:
		GameSettings.send_action(on, false)
	queue_redraw()


## Turns where the finger is into directions. A d-pad is all or nothing; a joystick also
## says how far, so a light push walks slowly.
func _aim(point: Vector2) -> void:
	var off := (point - stick_center) / stick_radius
	if off.length() > 1.0:
		off = off.normalized()
	knob = off
	var wanted := {}
	if off.length() >= DEAD_ZONE:
		if _last_kind == "dpad":
			# Eight directions, so a diagonal needs a real diagonal
			var aim := off.normalized()
			wanted = {"LEFT": aim.x < -0.38, "RIGHT": aim.x > 0.38, "UP": aim.y < -0.38, "DOWN": aim.y > 0.38}
			for key in wanted:
				wanted[key] = 1.0 if wanted[key] else 0.0
		else:
			wanted = {"LEFT": maxf(-off.x, 0.0), "RIGHT": maxf(off.x, 0.0), "UP": maxf(-off.y, 0.0), "DOWN": maxf(off.y, 0.0)}
	for action in ["LEFT", "RIGHT", "UP", "DOWN"]:
		_set_direction(action, float(wanted.get(action, 0.0)))
	queue_redraw()


func _set_direction(action: String, amount: float) -> void:
	var down: bool = _held.has(action)
	# A little stickier letting go than pressing, so it doesn't flicker on the line
	if amount >= PRESS_AT or (down and amount >= PRESS_AT * 0.7):
		if not down:
			_held[action] = true
			GameSettings.send_action(action, true, amount)
		else:
			Input.action_press(action, amount) # just how far: not a new press
	elif down:
		_held.erase(action)
		GameSettings.send_action(action, false)


func _release_directions() -> void:
	knob = Vector2.ZERO
	for action in _held.keys():
		GameSettings.send_action(action, false)
	_held.clear()
	queue_redraw()


func _release_all() -> void:
	for finger in _fingers:
		_lift(_fingers[finger])
	_fingers.clear()


# --- drawing ---

func _draw() -> void:
	var fade := clampf(float(GameSettings.values["touch_opacity"]) / 100.0, 0.1, 1.0)
	var fill := Color(FILL, FILL.a * fade)
	var line := Color(LINE, LINE.a * fade)
	var held := Color(HELD, HELD.a * fade)
	var font: Font = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
	for entry in BUTTONS:
		var action: String = entry[0]
		var spot: Vector2 = button_spots[action]
		var down: bool = _fingers.values().has(action)
		draw_circle(spot, button_radius, held if down else fill)
		draw_arc(spot, button_radius, 0.0, TAU, 40, line, 2.0, true)
		var letter_size := int(button_radius * 0.9) - int(button_radius * 0.9) % 8 # that font's crisp at multiples of 8
		letter_size = maxi(letter_size, 8)
		var letter := font.get_string_size(entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, letter_size)
		draw_string(font, spot + Vector2(-letter.x / 2.0, letter_size * 0.45), entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, letter_size, Color(1, 1, 1, 0.85 * fade))
	if _last_kind == "dpad":
		_draw_dpad(fill, line, held)
	else:
		draw_circle(stick_center, stick_radius, fill)
		draw_arc(stick_center, stick_radius, 0.0, TAU, 48, line, 2.0, true)
		draw_circle(stick_center + knob * stick_radius * 0.65, stick_radius * 0.42, held if not _held.is_empty() else Color(1, 1, 1, 0.3 * fade))


func _draw_dpad(fill: Color, line: Color, held: Color) -> void:
	var arm := stick_radius * 0.36 # half an arm's width
	var r := stick_radius
	for entry in [["UP", Vector2.UP], ["DOWN", Vector2.DOWN], ["LEFT", Vector2.LEFT], ["RIGHT", Vector2.RIGHT]]:
		var dir: Vector2 = entry[1]
		var side := Vector2(dir.y, -dir.x) * arm
		var corners := PackedVector2Array([stick_center + dir * arm + side, stick_center + dir * r + side, stick_center + dir * r - side, stick_center + dir * arm - side])
		draw_colored_polygon(corners, held if _held.has(entry[0]) else fill)
		corners.append(corners[0])
		draw_polyline(corners, line, 2.0)
	var middle := Rect2(stick_center - Vector2(arm, arm), Vector2(arm, arm) * 2.0)
	draw_rect(middle, fill)
