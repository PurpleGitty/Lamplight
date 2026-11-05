extends Control
## The middle of the Locale-Inator: the room as the game draws it (see RoomView), or
## the map of every room, with the tools and invisible things on top.

const FONT = preload("res://fonts/PixelOperator.ttf")
const ToolWheel = preload("res://editor/tool_wheel.gd")
const HINT_INDENT := 270.0 # clear of the tool wheel
const SHAPE_LIMIT := 256 # tiles across or down
const ZOOM_LEVELS := [0.25, 0.5, 1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0] # whole numbers keep pixels even
const MAP_SCALE := 0.25 # the map draws rooms this much smaller than they are
const GRID_COLOR := Color(1, 1, 1, 0.08)
const LIMIT_COLOR := Color(1.0, 0.25, 0.25, 0.9)
const SELECT_COLOR := Color.YELLOW
const LINK_COLOR := Color(0.25, 0.85, 1.0, 0.8)
const STEP_LINK_COLOR := Color(1.0, 0.5, 0.8, 0.8)
const HANDLE := 7.0
const GRID_MIN_ZOOM := 0.75
const FILL_LIMIT := 8192
const DOUBLE_CLICK_MS := 350
const POINT_GRAB := 8.0 # screen pixels
const LINE_GRAB := 7.0

var editor
var pan := Vector2.ZERO
var zoom := 3.0
var container := SubViewportContainer.new()
var viewport := SubViewport.new()
var camera := Camera2D.new()
var world := Node2D.new()
var view := RoomView.new()
var objects := ObjectLayer.new()
var object_shadows := ObjectShadows.new()
var overlay := Overlay.new()
var wheel := ToolWheel.new()

var _panning := false
var _pan_from := Vector2.ZERO
var _stroke := 0 # 1 painting, -1 erasing, 0 not
var _last_cell := Vector2i.ZERO
var _dragging := "" # "object", "resize", "room"
var _grab := Vector2.ZERO
var _moved := false
var _map_room: Variant = null
var _last_click_room: Variant = null
var _last_click_time := 0
var _mouse := Vector2.ZERO
var _drawing_path: Variant = null # the path clicks add to
var _freehand := false
var _point_at := -1
var _shape_from := Vector2i.ZERO
var _shape_to := Vector2i.ZERO
var _shape_on := true
var _contour: PackedVector2Array = []


## Draws the room's sprites between the floor and anything above the player.
class ObjectLayer extends Node2D:
	var owner_view

	func _draw() -> void:
		if owner_view != null:
			owner_view.draw_objects(self)


class ObjectShadows extends Node2D:
	var owner_view

	func _draw() -> void:
		if owner_view != null:
			owner_view.draw_object_shadows(self)


## Draws on top of the room, in screen pixels, so text stays crisp at any zoom.
class Overlay extends Control:
	var owner_view

	func _draw() -> void:
		if owner_view != null:
			owner_view.draw_overlay(self)


func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_CLICK
	container.stretch = true
	container.set_anchors_preset(PRESET_FULL_RECT)
	container.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(container)
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	container.add_child(viewport)
	viewport.add_child(world)
	world.add_child(view)
	objects.owner_view = self
	view.add_child(objects)
	view.move_child(objects, view.above.get_index()) # over the floors and walls
	object_shadows.owner_view = self
	view.shadow_group.add_child(object_shadows)
	viewport.add_child(camera)
	camera.make_current()
	overlay.owner_view = self
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(overlay)
	wheel.editor = editor
	add_child(wheel)


func show_room() -> void:
	view.show_room(editor.room, int(editor.locale["rules"]["tile_size"]))
	refresh_sun()
	refresh()


func refresh_sun() -> void:
	var rules: Dictionary = editor.locale["rules"]
	view.set_sun(LocaleDefs.sun_on(editor.room, rules), rules)


func frame_room() -> void:
	var drawn := view.drawn_rect()
	pan = drawn.get_center() if drawn.has_area() else Vector2.ZERO


func refresh() -> void:
	queue_redraw()
	overlay.queue_redraw()
	objects.queue_redraw()
	object_shadows.queue_redraw()


func _process(_delta: float) -> void:
	camera.position = pan
	camera.zoom = Vector2(zoom, zoom)
	container.visible = not editor.map_mode
	wheel.visible = not editor.map_mode
	queue_redraw()
	overlay.queue_redraw()


func to_screen(point: Vector2) -> Vector2:
	return size / 2.0 + (point - pan) * zoom


func to_world(point: Vector2) -> Vector2:
	return pan + (point - size / 2.0) / zoom


func _cell_at(screen: Vector2) -> Vector2i:
	return Vector2i((to_world(screen) / float(view.tile_size)).floor())


# --- drawing ---

func _draw() -> void:
	# What's behind the tiles, under the see-through room
	var rules: Dictionary = editor.locale["rules"]
	var source: Dictionary = editor.room if editor.room["own_background"] else rules
	draw_rect(Rect2(Vector2.ZERO, size), Color(str(source["background_color"])) if not editor.map_mode else Color(0.05, 0.05, 0.07))
	if editor.map_mode:
		return
	var image := str(source["background"])
	if image != "":
		draw_texture_rect(ChartDefs.load_texture(image), Rect2(Vector2.ZERO, size), false, Color(0.7, 0.7, 0.7))


func draw_object_shadows(canvas: CanvasItem) -> void:
	var rules: Dictionary = editor.locale["rules"]
	for obj in editor.room["objects"]:
		if LocaleDefs.OBJECT_TYPES[obj["type"]]["visible"] and obj.get("shadow", false):
			var look := _look_of(obj)
			LocaleDefs.draw_shadow(canvas, Transform2D.IDENTITY, look["texture"], look["region"], Vector2(obj["x"], obj["y"]), float(obj["scale"]), rules, look["mirrored"], LocaleDefs.bottom_gap(look["texture"], look["region"]))


func draw_objects(canvas: CanvasItem) -> void:
	var shown: Array = editor.room["objects"].filter(func(o): return LocaleDefs.OBJECT_TYPES[o["type"]]["visible"])
	shown.sort_custom(func(a, b): return a["y"] < b["y"])
	for obj in shown:
		var look := _look_of(obj)
		var box := _sprite_box(obj, look)
		if look["mirrored"]:
			# Mirrored about its middle (a negative rectangle would land somewhere else)
			canvas.draw_set_transform_matrix(Transform2D(Vector2.LEFT, Vector2.DOWN, Vector2(box.get_center().x * 2.0, 0)))
		canvas.draw_texture_rect_region(look["texture"], box, look["region"])
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


func _look_of(obj: Dictionary) -> Dictionary:
	var path := str(obj["sprite"])
	var texture: Texture2D = ChartDefs.load_texture(path) if path != "" else preload("res://sprites/pellet.png")
	var frame := int(obj.get("frame", 0))
	var mirrored := false
	if obj["type"] == "npc":
		var shown := LocaleDefs.direction_frame(obj, str(obj["facing"]), -1.0)
		frame = shown["frame"]
		mirrored = shown["mirrored"]
	return {"texture": texture, "region": LocaleDefs.frame_region(texture, int(obj["hframes"]), int(obj["vframes"]), frame), "mirrored": mirrored}


func _sprite_box(obj: Dictionary, look: Dictionary) -> Rect2:
	var drawn: Vector2 = look["region"].size * float(obj["scale"])
	var gap := LocaleDefs.bottom_gap(look["texture"], look["region"]) * float(obj["scale"])
	return Rect2(Vector2(obj["x"], obj["y"]) - Vector2(drawn.x / 2.0, drawn.y - gap), drawn)


## Where to click to pick this object, and what's outlined when it's selected.
func _object_rect(obj: Dictionary) -> Rect2:
	var def: Dictionary = LocaleDefs.OBJECT_TYPES[obj["type"]]
	if def.get("box", false):
		return Rect2(Vector2(obj["x"], obj["y"]), Vector2(obj["w"], obj["h"]))
	if obj["type"] == "path":
		var points := LocaleDefs.path_points(obj)
		var box := Rect2(points[0], Vector2.ZERO)
		for point in points:
			box = box.expand(point)
		return box.grow(4.0)
	if def["visible"]:
		return _sprite_box(obj, _look_of(obj))
	return Rect2(Vector2(obj["x"], obj["y"]) - Vector2(6, 6), Vector2(12, 12))


func draw_overlay(canvas: Control) -> void:
	if editor.map_mode:
		_draw_map(canvas)
	else:
		_draw_room_overlay(canvas)
	var hints := "[WHEEL] ZOOM      [MMB DRAG] PAN"
	if editor.map_mode:
		hints = "[LMB] SELECT ROOM      [LMB DRAG] MOVE ROOM      [DOUBLE LMB] OPEN ROOM      " + hints
	elif _drawing_path != null or editor.placing == "path":
		hints = "[LMB DRAG] DRAW PATH      [LMB] ADD A POINT      [RMB] FINISH      " + hints
	elif editor.placing != "":
		hints = "[LMB] PLACE %s      [RMB] CANCEL      " % str(LocaleDefs.OBJECT_TYPES[editor.placing]["label"]).to_upper() + hints
	else:
		match editor.tool:
			"paint": hints = "[LMB DRAG] DRAW TILES      [RMB DRAG] RUB OUT      " + hints
			"erase": hints = "[LMB DRAG] RUB OUT      " + hints
			"fill": hints = "[LMB] FILL      [RMB] CLEAR A FILLED AREA      " + hints
			"eyedropper": hints = "[LMB] PICK THE LAYER UNDER THE MOUSE      " + hints
			"shape": hints = "[LMB DRAG] DRAW A SHAPE      [RMB DRAG] RUB ONE OUT      [SHIFT] HOLLOW      [ALT] ROUND      " + hints
			"contour": hints = "[LMB DRAG] AROUND AN AREA TO FILL IT      [RMB DRAG] TO CLEAR IT      " + hints
			"select":
				hints = "[LMB] SELECT      [LMB DRAG] MOVE      [CTRL+LMB DRAG] MOVE WITHOUT SNAPPING      [DEL] DELETE      " + hints
				if editor.selected != null and editor.selected["type"] == "path":
					hints = "[LMB DRAG] A POINT: MOVE IT      [RMB] A POINT: DELETE IT      " + hints
	canvas.draw_rect(Rect2(0, canvas.size.y - 24, canvas.size.x, 24), Color(0, 0, 0, 0.6))
	var indent := 8.0 if editor.map_mode else HINT_INDENT
	canvas.draw_string(FONT, Vector2(indent, canvas.size.y - 8), hints, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.75))


func _draw_room_overlay(canvas: Control) -> void:
	var tile := float(view.tile_size)
	if editor.show_grid and zoom >= GRID_MIN_ZOOM:
		var first := to_world(Vector2.ZERO)
		var last := to_world(canvas.size)
		var x := floorf(first.x / tile) * tile
		while x <= last.x:
			var sx := to_screen(Vector2(x, 0)).x
			canvas.draw_line(Vector2(sx, 0), Vector2(sx, canvas.size.y), GRID_COLOR)
			x += tile
		var y := floorf(first.y / tile) * tile
		while y <= last.y:
			var sy := to_screen(Vector2(0, y)).y
			canvas.draw_line(Vector2(0, sy), Vector2(canvas.size.x, sy), GRID_COLOR)
			y += tile
	if editor.show_invisible:
		_draw_camera_limits(canvas)
		_draw_links(canvas)
		for obj in editor.room["objects"]:
			if not LocaleDefs.OBJECT_TYPES[obj["type"]]["visible"]:
				_draw_invisible(canvas, obj)
	if editor.selected != null:
		var box := _object_rect(editor.selected)
		var corner := to_screen(box.position)
		canvas.draw_rect(Rect2(corner, box.size * zoom), SELECT_COLOR, false, 2.0)
		canvas.draw_string(FONT, corner + Vector2(0, -4), str(editor.selected["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, SELECT_COLOR)
		if LocaleDefs.OBJECT_TYPES[editor.selected["type"]].get("box", false):
			canvas.draw_rect(_handle_rect(editor.selected), SELECT_COLOR)
	_draw_tool_preview(canvas)
	if editor.placing == "" and editor.tool in ["paint", "erase", "fill", "eyedropper", "shape"] and _dragging == "" and Rect2(Vector2.ZERO, canvas.size).has_point(_mouse):
		var cell := Vector2(_cell_at(_mouse)) * tile
		canvas.draw_rect(Rect2(to_screen(cell), Vector2(tile, tile) * zoom), Color(1, 1, 1, 0.6), false, 1.0)


## What a shape or contour will do, while it's being dragged.
func _draw_tool_preview(canvas: Control) -> void:
	var tile := float(view.tile_size)
	var color := Color(1, 1, 1, 0.5) if _shape_on else Color(1, 0.3, 0.3, 0.5)
	if _dragging == "shape":
		for cell in _shape_cells(_shape_from, _shape_to):
			canvas.draw_rect(Rect2(to_screen(Vector2(cell) * tile), Vector2(tile, tile) * zoom), color)
	elif _dragging == "contour" and _contour.size() > 1:
		for i in range(1, _contour.size()):
			canvas.draw_line(to_screen(_contour[i - 1]), to_screen(_contour[i]), Color(color, 1.0), 2.0)
		canvas.draw_line(to_screen(_contour[-1]), to_screen(_contour[0]), Color(color, 0.4), 1.0)


## The red lines from the room's drawn edges: the camera stops there, and a room smaller
## than the screen doesn't scroll on that side at all.
func _draw_camera_limits(canvas: Control) -> void:
	var drawn := view.drawn_rect()
	if not drawn.has_area():
		return
	var corner := to_screen(drawn.position)
	canvas.draw_rect(Rect2(corner, drawn.size * zoom), LIMIT_COLOR, false, 1.0)
	var screen := Overworld.SCREEN / maxf(roundf(float(editor.locale["rules"]["zoom"])), 1.0)
	var note := "camera stops at this line"
	if drawn.size.x <= screen.x and drawn.size.y <= screen.y:
		note = "camera doesn't move: this room fits the screen"
	elif drawn.size.x <= screen.x:
		note = "camera only moves up and down"
	elif drawn.size.y <= screen.y:
		note = "camera only moves left and right"
	canvas.draw_string(FONT, corner + Vector2(2, -4), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LIMIT_COLOR)


func _draw_invisible(canvas: Control, obj: Dictionary) -> void:
	var color: Color = LocaleDefs.OBJECT_TYPES[obj["type"]]["color"]
	if obj["type"] == "path":
		_draw_path(canvas, obj, color)
		return
	var box := _object_rect(obj)
	var corner := to_screen(box.position)
	if LocaleDefs.OBJECT_TYPES[obj["type"]].get("box", false):
		canvas.draw_rect(Rect2(corner, box.size * zoom), Color(color, 0.2))
		canvas.draw_rect(Rect2(corner, box.size * zoom), color, false, 1.0)
	else:
		var middle := to_screen(Vector2(obj["x"], obj["y"]))
		var diamond := PackedVector2Array([middle + Vector2(0, -8), middle + Vector2(8, 0), middle + Vector2(0, 8), middle + Vector2(-8, 0)])
		canvas.draw_colored_polygon(diamond, color)
		var ahead: Vector2 = LocaleDefs.DIRECTION_VECTORS.get(obj.get("facing", "down"), Vector2.DOWN)
		canvas.draw_line(middle, middle + ahead * 14.0, color, 2.0)
	canvas.draw_string(FONT, corner + Vector2(3, 14), str(obj["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)


## The line, numbered points, and a ring on any point with a cue.
func _draw_path(canvas: Control, path: Dictionary, color: Color) -> void:
	var points := LocaleDefs.path_points(path)
	var active: bool = path == editor.selected or path == _drawing_path
	for i in range(1, points.size()):
		canvas.draw_line(to_screen(points[i - 1]), to_screen(points[i]), color, 2.0 if active else 1.0)
	if points.size() > 1:
		_arrow(canvas, to_screen(points[-2]), to_screen(points[-1]), color)
	var cued := {}
	for cue in path["cues"]:
		cued[int(cue["point"])] = true
	# With many points close together (drawn by hand), only some can have a number
	var spacing := 0.0
	for i in points.size():
		var at := to_screen(points[i])
		if active or i == 0 or i == points.size() - 1 or cued.has(i):
			canvas.draw_circle(at, 3.0 if active else 2.0, color)
		if cued.has(i):
			canvas.draw_arc(at, 7.0, 0.0, TAU, 16, Color.WHITE, 2.0)
		if i > 0:
			spacing += at.distance_to(to_screen(points[i - 1]))
		if active and (i == 0 or spacing > 28.0 or cued.has(i)):
			spacing = 0.0
			canvas.draw_string(FONT, at + Vector2(5, -5), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	canvas.draw_string(FONT, to_screen(points[0]) + Vector2(6, 14), str(path["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)


## What's connected to what: warps to where they lead, and events to whatever they move.
func _draw_links(canvas: Control) -> void:
	for obj in editor.room["objects"]:
		var from := to_screen(_object_rect(obj).get_center())
		if obj["type"] == "warp":
			_draw_warp_link(canvas, from, int(obj["room"]), int(obj["spawn"]))
		for step in obj.get("steps", []):
			if step["type"] == "warp":
				_draw_warp_link(canvas, from, int(step["room"]), int(step["spawn"]))
			for key in ["who", "at", "path"]:
				if step.has(key) and int(step[key]) >= 0:
					var other: Variant = LocaleDefs.find_object(editor.room, int(step[key]))
					if other != null and other != obj:
						_arrow(canvas, from, to_screen(_object_rect(other).get_center()), STEP_LINK_COLOR)


func _draw_warp_link(canvas: Control, from: Vector2, room_id: int, spawn_id: int) -> void:
	if room_id == editor.room["id"]:
		var spawn: Variant = LocaleDefs.find_object(editor.room, spawn_id)
		if spawn != null:
			_arrow(canvas, from, to_screen(Vector2(spawn["x"], spawn["y"])), LINK_COLOR)
		return
	var target: Variant = LocaleDefs.find_room(editor.locale, room_id)
	var text: String = "to %s" % target["name"] if target != null else "leads nowhere yet"
	canvas.draw_string(FONT, from + Vector2(6, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LINK_COLOR if target != null else LIMIT_COLOR)


func _arrow(canvas: Control, from: Vector2, to: Vector2, color: Color) -> void:
	canvas.draw_line(from, to, color, 2.0)
	var back := (from - to).normalized() * 10.0
	canvas.draw_line(to, to + back.rotated(0.5), color, 2.0)
	canvas.draw_line(to, to + back.rotated(-0.5), color, 2.0)


func _handle_rect(obj: Dictionary) -> Rect2:
	var box := _object_rect(obj)
	return Rect2(to_screen(box.end) - Vector2(HANDLE, HANDLE) / 2.0, Vector2(HANDLE, HANDLE))


# --- the map of every room ---

func _room_map_rect(room: Dictionary) -> Rect2:
	var tile := float(editor.locale["rules"]["tile_size"]) * MAP_SCALE
	var found := false
	var low := Vector2.ZERO
	var high := Vector2.ZERO
	for layer in room["layers"]:
		var flat: Array = layer["cells"]
		for i in range(0, flat.size() - 1, 2):
			var at := Vector2(flat[i], flat[i + 1])
			low = at if not found else low.min(at)
			high = at if not found else high.max(at)
			found = true
	if not found:
		return Rect2(Vector2(room["map_x"], room["map_y"]), Vector2(tile, tile) * 8.0)
	return Rect2(Vector2(room["map_x"], room["map_y"]) + low * tile, (high - low + Vector2.ONE) * tile)


func _draw_map(canvas: Control) -> void:
	var tile := float(editor.locale["rules"]["tile_size"]) * MAP_SCALE
	for room in editor.locale["rooms"]:
		var origin := Vector2(room["map_x"], room["map_y"])
		var box := _room_map_rect(room)
		canvas.draw_rect(Rect2(to_screen(box.position), box.size * zoom), Color(0.16, 0.16, 0.2))
		for layer in room["layers"]:
			var color := Color(0.75, 0.75, 0.8) if not layer["solid"] else Color(0.45, 0.45, 0.55)
			var flat: Array = layer["cells"]
			for i in range(0, flat.size() - 1, 2):
				var at := origin + Vector2(flat[i], flat[i + 1]) * tile
				canvas.draw_rect(Rect2(to_screen(at), Vector2(tile, tile) * zoom), color)
		var is_current: bool = room == editor.room
		canvas.draw_rect(Rect2(to_screen(box.position), box.size * zoom), SELECT_COLOR if is_current else Color(1, 1, 1, 0.3), false, 2.0 if is_current else 1.0)
		canvas.draw_string(FONT, to_screen(box.position) + Vector2(2, -4), str(room["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, SELECT_COLOR if is_current else Color.WHITE)
	if not editor.show_invisible:
		return
	for room in editor.locale["rooms"]:
		var origin := Vector2(room["map_x"], room["map_y"])
		for obj in room["objects"]:
			if obj["type"] != "warp":
				continue
			var target: Variant = LocaleDefs.find_room(editor.locale, int(obj["room"]))
			if target == null:
				continue
			var from := to_screen(origin + Vector2(obj["x"], obj["y"]) * MAP_SCALE)
			var to := to_screen(_room_map_rect(target).get_center())
			var spawn: Variant = LocaleDefs.find_object(target, int(obj["spawn"]))
			if spawn != null:
				to = to_screen(Vector2(target["map_x"], target["map_y"]) + Vector2(spawn["x"], spawn["y"]) * MAP_SCALE)
			_arrow(canvas, from, to, LINK_COLOR)


func _map_room_at(screen: Vector2) -> Variant:
	var point := to_world(screen)
	var rooms: Array = editor.locale["rooms"]
	for i in range(rooms.size() - 1, -1, -1):
		if _room_map_rect(rooms[i]).has_point(point):
			return rooms[i]
	return null


# --- mouse ---

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		overlay.queue_redraw()
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			_zoom_at(event.position, 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			_pan_from = event.position
			return
	if _panning and event is InputEventMouseMotion:
		pan -= (event.position - _pan_from) / zoom
		_pan_from = event.position
		refresh()
		return
	if editor.map_mode:
		_map_input(event)
	else:
		_room_input(event)


func _zoom_at(screen: Vector2, step: int) -> void:
	var before := to_world(screen)
	var at := 0
	for i in ZOOM_LEVELS.size():
		if ZOOM_LEVELS[i] <= zoom:
			at = i
	zoom = ZOOM_LEVELS[clampi(at + step, 0, ZOOM_LEVELS.size() - 1)]
	pan += before - to_world(screen)
	refresh()


func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			var room: Variant = _map_room_at(event.position)
			if room == null:
				return
			var now := Time.get_ticks_msec()
			if room == _last_click_room and now - _last_click_time < DOUBLE_CLICK_MS:
				editor.open_room(room)
				editor.set_map_mode(false)
				return
			_last_click_room = room
			_last_click_time = now
			editor.open_room(room)
			_map_room = room
			_dragging = "room"
			_moved = false
			_grab = to_world(event.position) - Vector2(room["map_x"], room["map_y"])
			editor.push_undo()
		else:
			_dragging = ""
			if _moved:
				editor.changed()
	elif event is InputEventMouseMotion and _dragging == "room":
		var spot: Vector2 = (to_world(event.position) - _grab).round()
		_map_room["map_x"] = spot.x
		_map_room["map_y"] = spot.y
		_moved = true
		overlay.queue_redraw()


func _room_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				grab_focus()
				_left_down(event)
			else:
				_end_action()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_right_down(event)
			else:
				_end_action()
	elif event is InputEventMouseMotion:
		if _freehand and _drawing_path != null:
			var last: Array = _drawing_path["points"][-1]
			var from := Vector2(_drawing_path["x"], _drawing_path["y"]) + Vector2(last[0], last[1])
			var world_point := to_world(event.position)
			if world_point.distance_to(from) >= float(view.tile_size) / 2.0:
				_add_path_point(world_point.round())
		elif _stroke != 0:
			_stroke_to(_cell_at(event.position))
		elif _dragging == "shape":
			_shape_to = _cell_at(event.position)
		elif _dragging == "contour":
			var world_at := to_world(event.position)
			if world_at.distance_to(_contour[-1]) >= 2.0:
				_contour.append(world_at)
		elif _dragging != "":
			_drag_to(event)


func _left_down(event: InputEventMouseButton) -> void:
	if _drawing_path != null:
		editor.push_undo()
		_add_path_point(_snapped(to_world(event.position), event.ctrl_pressed))
		_freehand = true
		return
	if editor.placing == "path":
		var at := _snapped(to_world(event.position), event.ctrl_pressed)
		editor.place_object("path", at)
		_drawing_path = editor.selected
		_freehand = true
		return
	if editor.placing != "":
		editor.place_object(editor.placing, _snapped(to_world(event.position), event.ctrl_pressed))
		return
	match editor.tool:
		"paint": _start_stroke(1, event.position)
		"erase": _start_stroke(-1, event.position)
		"fill": _fill(_cell_at(event.position), true)
		"select": _select_at(event.position)
		"eyedropper": _pick_layer_at(event.position)
		"shape": _start_shape(event.position, true)
		"contour": _start_contour(event.position, true)


func _right_down(event: InputEventMouseButton) -> void:
	if _drawing_path != null:
		finish_path()
		return
	if editor.tool == "select" and editor.selected != null and editor.selected["type"] == "path":
		var at := _point_under(editor.selected, event.position)
		if at >= 0 and editor.selected["points"].size() > 1:
			_delete_path_point(editor.selected, at)
		return
	if editor.placing != "":
		editor.placing = ""
		refresh()
		return
	match editor.tool:
		"paint", "erase": _start_stroke(-1, event.position)
		"fill": _fill(_cell_at(event.position), false)
		"shape": _start_shape(event.position, false)
		"contour": _start_contour(event.position, false)


## The top layer with a tile here becomes the one being drawn on.
func _pick_layer_at(screen: Vector2) -> void:
	var cell := _cell_at(screen)
	var layers: Array = editor.room["layers"]
	for i in range(layers.size() - 1, -1, -1):
		if view.has_tile(layers[i], cell):
			editor.pick_layer(layers[i])
			return
	editor.set_status("There's no tile there to pick.")


func _start_shape(screen: Vector2, on: bool) -> void:
	if editor.layer == null:
		editor.set_status("Pick a layer to draw on first.")
		return
	_dragging = "shape"
	_shape_on = on
	_shape_from = _cell_at(screen)
	_shape_to = _shape_from
	_moved = false


## Every tile in a shape: a rectangle, hollow with [SHIFT], round with [ALT].
func _shape_cells(from: Vector2i, to: Vector2i) -> Array:
	var low := Vector2i(mini(from.x, to.x), mini(from.y, to.y))
	var high := Vector2i(mini(maxi(from.x, to.x), low.x + SHAPE_LIMIT), mini(maxi(from.y, to.y), low.y + SHAPE_LIMIT))
	var hollow := Input.is_key_pressed(KEY_SHIFT)
	var round_shape := Input.is_key_pressed(KEY_ALT)
	var middle := (Vector2(low) + Vector2(high) + Vector2.ONE) / 2.0
	var radii := Vector2(high - low + Vector2i.ONE) / 2.0
	var inside := func(x: int, y: int) -> bool:
		if x < low.x or x > high.x or y < low.y or y > high.y:
			return false
		if not round_shape:
			return true
		var off := (Vector2(x, y) + Vector2(0.5, 0.5) - middle) / radii
		return off.length_squared() <= 1.0
	var cells := []
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			if not inside.call(x, y):
				continue
			if hollow and inside.call(x - 1, y) and inside.call(x + 1, y) and inside.call(x, y - 1) and inside.call(x, y + 1):
				continue
			cells.append(Vector2i(x, y))
	return cells


func _start_contour(screen: Vector2, on: bool) -> void:
	if editor.layer == null:
		editor.set_status("Pick a layer to draw on first.")
		return
	_dragging = "contour"
	_shape_on = on
	_contour = PackedVector2Array([to_world(screen)])


## Every tile inside the line that was drawn, and those it went through.
func _contour_cells() -> Array:
	var tile := float(view.tile_size)
	var cells := {}
	var low := _contour[0]
	var high := _contour[0]
	for i in _contour.size():
		low = low.min(_contour[i])
		high = high.max(_contour[i])
		var from := _contour[i]
		var to := _contour[(i + 1) % _contour.size()]
		var steps := ceili(from.distance_to(to) / (tile / 2.0)) + 1
		if i < _contour.size() - 1:
			for k in steps + 1:
				cells[Vector2i((from.lerp(to, float(k) / steps) / tile).floor())] = true
	var first := Vector2i((low / tile).floor())
	var last := Vector2i((high / tile).floor())
	if _contour.size() >= 3:
		for y in range(first.y, mini(last.y, first.y + SHAPE_LIMIT) + 1):
			for x in range(first.x, mini(last.x, first.x + SHAPE_LIMIT) + 1):
				if Geometry2D.is_point_in_polygon((Vector2(x, y) + Vector2(0.5, 0.5)) * tile, _contour):
					cells[Vector2i(x, y)] = true
	return cells.keys()


## Puts what a shape or contour covered onto the layer.
func _paint_cells(cells: Array, on: bool) -> void:
	editor.push_undo()
	for cell in cells:
		view.paint(editor.layer, cell, on)
	view.store_cells(editor.layer)
	editor.changed(false)


func _start_stroke(mode: int, screen: Vector2) -> void:
	if editor.layer == null:
		editor.set_status("Pick a layer to draw on first.")
		return
	editor.push_undo()
	_stroke = mode
	_last_cell = _cell_at(screen)
	view.paint(editor.layer, _last_cell, mode > 0)
	overlay.queue_redraw()


## Paints in a line from the last cell, so a fast mouse doesn't leave gaps.
func _stroke_to(cell: Vector2i) -> void:
	var from := _last_cell
	var steps := maxi(absi(cell.x - from.x), absi(cell.y - from.y))
	for i in range(1, steps + 1):
		var at := Vector2i((Vector2(from).lerp(Vector2(cell), float(i) / steps)).round())
		view.paint(editor.layer, at, _stroke > 0)
	_last_cell = cell
	overlay.queue_redraw()


## Fills the connected area around a cell: empty tiles if drawing, or drawn ones if not.
func _fill(start: Vector2i, on: bool) -> void:
	if editor.layer == null:
		editor.set_status("Pick a layer to draw on first.")
		return
	var layer: Dictionary = editor.layer
	if view.has_tile(layer, start) == on:
		return
	editor.push_undo()
	var open := [start]
	var seen := {start: true}
	var filled := 0
	while not open.is_empty() and filled < FILL_LIMIT:
		var cell: Vector2i = open.pop_back()
		view.paint(layer, cell, on)
		filled += 1
		for near in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + near
			if not seen.has(next) and view.has_tile(layer, next) != on:
				seen[next] = true
				open.append(next)
	if filled >= FILL_LIMIT:
		editor.set_status("Stopped filling at %d tiles: the area's open on some side." % FILL_LIMIT)
	view.store_cells(layer)
	editor.changed()


## Adds a point, in the path's own coordinates.
func _add_path_point(world_point: Vector2) -> void:
	var path: Dictionary = _drawing_path
	var local := world_point - Vector2(path["x"], path["y"])
	var last: Array = path["points"][-1]
	if local != Vector2(last[0], last[1]):
		path["points"].append([local.x, local.y])
	overlay.queue_redraw()


func finish_path() -> void:
	_drawing_path = null
	_freehand = false
	editor.changed()


func start_drawing_path(path: Dictionary) -> void:
	_drawing_path = path
	editor.viewport.refresh()


func _point_under(path: Dictionary, screen: Vector2) -> int:
	var points := LocaleDefs.path_points(path)
	for i in range(points.size() - 1, -1, -1):
		if to_screen(points[i]).distance_to(screen) <= POINT_GRAB:
			return i
	return -1


## Takes out a point, keeping every cue on the point it was on.
func _delete_path_point(path: Dictionary, at: int) -> void:
	editor.push_undo()
	path["points"].remove_at(at)
	for cue in path["cues"]:
		if int(cue["point"]) > at or int(cue["point"]) >= path["points"].size():
			cue["point"] = maxi(int(cue["point"]) - 1, 0)
	editor.changed()


func _near_path(path: Dictionary, screen: Vector2) -> bool:
	var points := LocaleDefs.path_points(path)
	if points.size() == 1:
		return to_screen(points[0]).distance_to(screen) <= POINT_GRAB
	for i in range(1, points.size()):
		var closest := Geometry2D.get_closest_point_to_segment(screen, to_screen(points[i - 1]), to_screen(points[i]))
		if closest.distance_to(screen) <= LINE_GRAB:
			return true
	return false


func _select_at(screen: Vector2) -> void:
	var picked: Variant = null
	if editor.selected != null and editor.selected["type"] == "path":
		var at := _point_under(editor.selected, screen)
		if at >= 0:
			_dragging = "point"
			_point_at = at
			_moved = false
			editor.push_undo()
			return
	if editor.selected != null and LocaleDefs.OBJECT_TYPES[editor.selected["type"]].get("box", false) and _handle_rect(editor.selected).grow(3.0).has_point(screen):
		_dragging = "resize"
		editor.push_undo()
		return
	var point := to_world(screen)
	var list: Array = editor.room["objects"]
	# The smallest under the mouse first, so a big trigger doesn't hide what's in it
	var smallest := INF
	for obj in list:
		if not LocaleDefs.OBJECT_TYPES[obj["type"]]["visible"] and not editor.show_invisible:
			continue
		if obj["type"] == "path":
			# Only its line counts, so a path across a room doesn't get in the way
			if _near_path(obj, screen):
				smallest = 0.0
				picked = obj
			continue
		var box := _object_rect(obj)
		if box.has_point(point) and box.get_area() < smallest:
			smallest = box.get_area()
			picked = obj
	editor.select(picked)
	if picked != null:
		_dragging = "object"
		_moved = false
		_grab = point - Vector2(picked["x"], picked["y"])
		editor.push_undo()


func _drag_to(event: InputEventMouseMotion) -> void:
	var obj: Dictionary = editor.selected
	var point := to_world(event.position)
	if _dragging == "point":
		var spot := _snapped(point, event.ctrl_pressed) - Vector2(obj["x"], obj["y"])
		obj["points"][_point_at] = [spot.x, spot.y]
		_moved = true
		refresh()
		return
	if _dragging == "resize":
		var far := _snapped(point, event.ctrl_pressed)
		obj["w"] = maxf(far.x - float(obj["x"]), 4.0)
		obj["h"] = maxf(far.y - float(obj["y"]), 4.0)
	else:
		var spot := _snapped(point - _grab, event.ctrl_pressed)
		obj["x"] = spot.x
		obj["y"] = spot.y
	_moved = true
	refresh()


## To the nearest half tile, unless told not to.
func _snapped(point: Vector2, free: bool) -> Vector2:
	if free:
		return point.round()
	var half := float(view.tile_size) / 2.0
	return (point / half).round() * half


func _end_action() -> void:
	_freehand = false
	if _dragging == "shape":
		_dragging = ""
		_paint_cells(_shape_cells(_shape_from, _shape_to), _shape_on)
		return
	if _dragging == "contour":
		_dragging = ""
		_paint_cells(_contour_cells(), _shape_on)
		_contour = PackedVector2Array()
		return
	if _stroke != 0:
		_stroke = 0
		view.store_cells(editor.layer)
		editor.changed(false)
	if _dragging != "":
		_dragging = ""
		if _moved:
			editor.changed()
		_moved = false
