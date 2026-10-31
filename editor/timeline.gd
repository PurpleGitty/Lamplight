extends Control
## The editor's timeline: one column per beat of the song, one lane per object
## (plus the Turns and Board lanes at the top). Nodes are drawn as blocks as
## long as the beats they span. Nodes that overlap on one lane stack into rows.

const HEADER := 170.0 # width of the lane names on the left
const RULER := 24.0
const LANE_H := 30.0 # a lane with one row of nodes; lanes with stacked nodes grow
const ROW_H := 14.0 # height per extra row of stacked nodes
const EDGE := 7.0 # grab this close to a node's right edge to stretch it
const FONT = preload("res://fonts/PixelOperator.ttf")

var editor
var ppb := 32.0 # pixels per beat (zoom)
var scroll := 0.0 # the beat at the left edge
var first_lane := 0 # the lane at the top (vertical scroll)

var _drag := "" # "", "move", "resize", "scrub", "pan"
var _drag_from := Vector2.ZERO
var _drag_origin: Array = [] # [[event, its beat or length when the drag started], ...]
var _drag_pushed_undo := false
var _mouse := Vector2(-1, -1)
var _tops: Array[float] = [] # top of each lane from first_lane down
var _heights: Array[float] = []
var _layouts: Array = []


func _ready() -> void:
	focus_mode = FOCUS_CLICK
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP


func beat_to_x(b: float) -> float:
	return HEADER + (b - scroll) * ppb


func x_to_beat(x: float) -> float:
	return scroll + (x - HEADER) / ppb


## Works out every lane's height (taller when its nodes stack) and position.
func _measure() -> void:
	_tops.clear()
	_heights.clear()
	_layouts.clear()
	var lanes: Array = editor.lane_list()
	var y := RULER
	for i in range(first_lane, lanes.size()):
		var layout := _layout(editor.lane_events(lanes[i]))
		var h := maxf(LANE_H, layout["rows"] * ROW_H + 4.0)
		_tops.append(y)
		_heights.append(h)
		_layouts.append(layout)
		y += h


func _last_shown_lane() -> int:
	var last := first_lane
	for k in _tops.size():
		if _tops[k] < size.y:
			last = first_lane + k
	return last


## -2 = the ruler, -1 = below the last lane
func lane_index_at(y: float) -> int:
	if y < RULER:
		return -2
	for k in _tops.size():
		if y < _tops[k] + _heights[k]:
			return first_lane + k
	return -1


func lane_top(i: int) -> float:
	var k := i - first_lane
	return _tops[k] if k >= 0 and k < _tops.size() else RULER + k * LANE_H


func lane_height(i: int) -> float:
	var k := i - first_lane
	return _heights[k] if k >= 0 and k < _heights.size() else LANE_H


func show_lane(i: int) -> void:
	_measure()
	if i < first_lane:
		first_lane = i
	while first_lane < i and lane_top(i) + lane_height(i) > size.y:
		first_lane += 1
		_measure()
	queue_redraw()


func follow(b: float) -> void:
	if b < scroll or beat_to_x(b) > size.x - 40:
		scroll = maxf(0.0, b - (size.x - HEADER) * 0.25 / ppb)
		queue_redraw()


## How wide a node looks, in beats. Instant nodes get a small fixed width
## (text nodes a wider one, so a bit of the line fits on them).
func _visual_length(ev: Dictionary) -> float:
	if ev["type"] == "text":
		return maxf(3.0, 40.0 / ppb)
	if ChartDefs.is_instant(ev["type"]):
		return maxf(0.5, 14.0 / ppb)
	return maxf(ev["length"], 4.0 / ppb)


## What's written on a node: its type, or for text, who says what.
func _node_label(ev: Dictionary, def: Dictionary) -> String:
	if ev["type"] != "text":
		return def["label"]
	var p: Dictionary = ev["params"]
	var who: String = p["speaker"] if p["kind"] == "dialogue" else p["kind"].to_upper()
	return "%s: %s" % [who, TextMarkup.plain(p["text"]).replace("\n", " ")]


## Packs a lane's nodes into rows so overlapping ones don't hide each other.
## Returns {"rows": count, "items": [[event, row], ...]}
func _layout(events: Array) -> Dictionary:
	var sorted := events.duplicate()
	sorted.sort_custom(func(a, b): return a["beat"] < b["beat"] or (a["beat"] == b["beat"] and a["id"] < b["id"]))
	var row_ends: Array[float] = []
	var items := []
	for ev in sorted:
		var row := -1
		for r in row_ends.size():
			if row_ends[r] <= ev["beat"] + 0.0001:
				row = r
				break
		if row == -1:
			row = row_ends.size()
			row_ends.append(0.0)
		row_ends[row] = ev["beat"] + _visual_length(ev)
		items.append([ev, row])
	return {"rows": maxi(row_ends.size(), 1), "items": items}


func _node_rect(ev: Dictionary, lane_i: int, row: int, rows: int) -> Rect2:
	var row_h := (lane_height(lane_i) - 4.0) / rows
	var x := beat_to_x(ev["beat"])
	return Rect2(x, lane_top(lane_i) + 2.0 + row * row_h, _visual_length(ev) * ppb, row_h - 1.0)


func _event_at(pos: Vector2) -> Dictionary:
	var i := lane_index_at(pos.y)
	if i < 0 or pos.x < HEADER:
		return {}
	var layout: Dictionary = _layouts[i - first_lane]
	for item in layout["items"]:
		if _node_rect(item[0], i, item[1], layout["rows"]).has_point(pos):
			return item[0]
	return {}


# --- drawing ---

func _draw() -> void:
	_measure()
	var lanes: Array = editor.lane_list()
	var last_lane := _last_shown_lane()
	var right_beat := x_to_beat(size.x)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.11, 0.11, 0.13))

	# Lane backgrounds
	for i in range(first_lane, last_lane + 1):
		var shade := 0.15 if i % 2 == 0 else 0.13
		draw_rect(Rect2(HEADER, lane_top(i), size.x - HEADER, lane_height(i)), Color(shade, shade, shade + 0.02))

	# Enemy turns (Begin Attack -> End Attack) shaded red
	for a in ChartDefs.attacks(editor.chart):
		var x1 := maxf(beat_to_x(a["start"]), HEADER)
		var x2 := beat_to_x(a["end"])
		if x2 > HEADER and x1 < size.x:
			draw_rect(Rect2(x1, 0, x2 - x1, size.y), Color(1, 0.2, 0.2, 0.08))
			draw_rect(Rect2(x1, 0, x2 - x1, 4), Color(1, 0.3, 0.3, 0.6))

	# Beat grid and numbers. Every beat is a step; bars (4 beats) are brighter.
	var label_step := 1
	while label_step * ppb < 30:
		label_step *= 2
	var line_step := 1 if ppb >= 6 else 4
	for b in range(maxi(floori(scroll), 0), ceili(right_beat) + 1):
		if b % line_step != 0:
			continue
		var x := beat_to_x(b)
		if x < HEADER:
			continue
		var bar := b % 4 == 0
		draw_line(Vector2(x, RULER), Vector2(x, size.y), Color(1, 1, 1, 0.16 if bar else 0.06))
		if b % label_step == 0:
			draw_string(FONT, Vector2(x + 2, 17), str(b), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9 if bar else 0.55))
	var end_x := beat_to_x(editor.song_length_beats)
	if end_x < size.x:
		draw_rect(Rect2(end_x, 0, size.x - end_x, size.y), Color(0, 0, 0, 0.5))

	# Nodes
	var current = editor.current_object()
	for i in range(first_lane, last_lane + 1):
		var lane: Dictionary = lanes[i]
		var layout: Dictionary = _layouts[i - first_lane]
		for item in layout["items"]:
			var ev: Dictionary = item[0]
			var r := _node_rect(ev, i, item[1], layout["rows"])
			if r.end.x < HEADER or r.position.x > size.x:
				continue
			_draw_node(ev, r)

		# Lane name (drawn over the nodes so it covers anything scrolled under it)
		var header := Rect2(0, lane_top(i), HEADER, lane_height(i))
		var is_current: bool = lane["kind"] == "object" and lane["object"] == current
		draw_rect(header, Color(0.24, 0.22, 0.12) if is_current else Color(0.17, 0.17, 0.2))
		var strip: Color = {"turn": Color("e04848"), "text": Color("e8e8e8"), "board": Color("3fd0ff"), "object": Color("ffb03b")}[lane["kind"]]
		draw_rect(Rect2(0, header.position.y, 4, header.size.y), strip)
		draw_string(FONT, Vector2(10, header.position.y + 20), _fit(lane["label"], HEADER - 14), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_line(Vector2(0, header.end.y), Vector2(size.x, header.end.y), Color(0, 0, 0, 0.5))

	draw_rect(Rect2(0, 0, HEADER, RULER), Color(0.17, 0.17, 0.2))
	draw_string(FONT, Vector2(8, 17), "beat", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.5))
	draw_line(Vector2(HEADER, 0), Vector2(HEADER, size.y), Color(0, 0, 0, 0.8), 2.0)
	draw_line(Vector2(0, RULER), Vector2(size.x, RULER), Color(1, 1, 1, 0.3))

	# Ghost of the node about to be placed
	if editor.armed_type != "" and _mouse.x > HEADER:
		var i := lane_index_at(_mouse.y)
		if i >= 0 and lanes[i]["kind"] == ChartDefs.TYPES[editor.armed_type]["lane"]:
			var ghost := ChartDefs.new_event({"next_id": -1}, editor.armed_type, editor.snap_beat(x_to_beat(_mouse.x)))
			var r := _node_rect(ghost, i, 0, 1)
			var c: Color = ChartDefs.TYPES[editor.armed_type]["color"]
			draw_rect(r, Color(c, 0.4))
			draw_rect(r, c, false, 1.0)

	# Playhead
	var px := beat_to_x(editor.beat)
	if px >= HEADER:
		draw_line(Vector2(px, 0), Vector2(px, size.y), Color(1, 0.25, 0.25), 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(px - 6, 0), Vector2(px + 6, 0), Vector2(px, 9)]), Color(1, 0.25, 0.25))

	if lanes.size() <= 3:
		draw_string(FONT, Vector2(HEADER + 12, lane_top(3) + 22), "Press \"+ Object\" to add an object lane.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.5))


func _draw_node(ev: Dictionary, r: Rect2) -> void:
	var def: Dictionary = ChartDefs.TYPES.get(ev["type"], {"color": Color.MAGENTA, "label": ev["type"]})
	var is_selected: bool = ev in editor.selected
	var color: Color = def["color"]
	draw_rect(r, color if is_selected else color.darkened(0.15))
	var text_x := r.position.x + 3
	var icon: Texture2D = editor.icon_for(ev["type"])
	if icon and r.size.y >= 10:
		var s := r.size.y - 2
		draw_texture_rect(icon, Rect2(r.position.x + 1, r.position.y + 1, s, s), false)
		text_x += s + 2
	var room := r.end.x - text_x - 2
	if room > 10 and r.size.y >= 11:
		var font_size := 16 if r.size.y >= 16 else 8
		draw_string(FONT, Vector2(text_x, r.position.y + r.size.y / 2 + font_size * 0.35), _fit(_node_label(ev, def), room, font_size), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	if is_selected:
		draw_rect(r.grow(1), Color.YELLOW, false, 2.0)
		if not ChartDefs.is_instant(ev["type"]):
			draw_line(Vector2(r.end.x - 3, r.position.y + 3), Vector2(r.end.x - 3, r.end.y - 3), Color.BLACK, 2.0)
	else:
		draw_rect(r, Color(0, 0, 0, 0.6), false, 1.0)


func _fit(text: String, width: float, font_size := 16) -> String:
	if FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	while text.length() > 1 and FONT.get_string_size(text + ".", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		text = text.left(-1)
	return text + "." if text.length() > 1 else ""


# --- mouse ---

func _gui_input(event: InputEvent) -> void:
	_measure()
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			_wheel(mb)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = "pan" if mb.pressed else ""
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb)
			else:
				_release()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var hit := _event_at(mb.position)
			if not hit.is_empty():
				editor.delete_events([hit])
			elif editor.armed_type != "":
				editor.arm(editor.armed_type)
		accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion:
		_mouse = event.position
		_motion(event)
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_mouse = Vector2(-1, -1)
		queue_redraw()


func _wheel(mb: InputEventMouseButton) -> void:
	var dir := -1.0 if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1.0
	if mb.ctrl_pressed:
		# Zoom around the mouse
		var anchor := x_to_beat(mb.position.x)
		ppb = clampf(ppb * (1.15 if dir < 0 else 1.0 / 1.15), 2.0, 240.0)
		scroll = maxf(0.0, anchor - (mb.position.x - HEADER) / ppb)
	elif mb.shift_pressed:
		first_lane = clampi(first_lane + int(dir), 0, maxi(editor.lane_list().size() - 1, 0))
	else:
		scroll = maxf(0.0, scroll + dir * 90.0 / ppb)


func _press(mb: InputEventMouseButton) -> void:
	grab_focus()
	var pos := mb.position
	var i := lane_index_at(pos.y)
	if i == -2:
		_drag = "scrub"
		editor.seek(maxf(x_to_beat(pos.x), 0.0))
		return
	if i == -1:
		editor.select([])
		return
	var lane: Dictionary = editor.lane_list()[i]
	if pos.x < HEADER:
		if lane["kind"] == "object":
			editor.select_object(lane["object"])
		else:
			editor.select([])
		return

	var hit := _event_at(pos)
	if not hit.is_empty():
		if mb.ctrl_pressed:
			var sel: Array = editor.selected.duplicate()
			if hit in sel:
				sel.erase(hit)
			else:
				sel.append(hit)
			editor.select(sel)
			return
		if hit not in editor.selected:
			editor.select([hit])
		_drag_from = pos
		_drag_pushed_undo = false
		var r := Rect2()
		var layout := _layout(editor.lane_events(lane))
		for item in layout["items"]:
			if item[0] == hit:
				r = _node_rect(hit, i, item[1], layout["rows"])
		if editor.selected.size() == 1 and not ChartDefs.is_instant(hit["type"]) and pos.x > r.end.x - EDGE:
			_drag = "resize"
			_drag_origin = [[hit, hit["length"]]]
		else:
			_drag = "move"
			_drag_origin = editor.selected.map(func(ev): return [ev, ev["beat"]])
		return

	var b: float = editor.snap_beat(x_to_beat(pos.x))
	if editor.armed_type != "":
		editor.place(editor.armed_type, lane, b)
	else:
		editor.select([])
		editor.seek(maxf(b, 0.0))


func _release() -> void:
	if _drag in ["move", "resize"] and _drag_pushed_undo:
		editor.changed()
	_drag = ""


func _motion(e: InputEventMouseMotion) -> void:
	match _drag:
		"scrub":
			editor.seek(maxf(x_to_beat(e.position.x), 0.0))
		"pan":
			scroll = maxf(0.0, scroll - e.relative.x / ppb)
		"move":
			var delta := x_to_beat(e.position.x) - x_to_beat(_drag_from.x)
			delta = delta if editor.snap <= 0.0 else roundf(delta / editor.snap) * editor.snap
			if not _drag_pushed_undo:
				if delta == 0.0 and lane_index_at(e.position.y) == lane_index_at(_drag_from.y):
					return
				editor.push_undo()
				_drag_pushed_undo = true
			for pair in _drag_origin:
				pair[0]["beat"] = maxf(0.0, pair[1] + delta)
			_maybe_change_lane(e.position)
			editor.changed(false)
		"resize":
			var ev: Dictionary = _drag_origin[0][0]
			var min_len: float = editor.snap if editor.snap > 0.0 else 0.0625
			var new_len := maxf(min_len, editor.snap_beat(x_to_beat(e.position.x)) - ev["beat"])
			if new_len != ev["length"]:
				if not _drag_pushed_undo:
					editor.push_undo()
					_drag_pushed_undo = true
				ev["length"] = new_len
				editor.changed(false)
		_:
			var hover := _event_at(e.position)
			if not hover.is_empty():
				var def: Dictionary = ChartDefs.TYPES[hover["type"]]
				var span := "" if ChartDefs.is_instant(hover["type"]) else ", %s beats" % snappedf(hover["length"], 0.001)
				editor.set_status("%s at beat %s%s - %s" % [def["label"], snappedf(hover["beat"], 0.001), span, def["help"]])


## Dragging a single object node onto another object's lane moves it there.
func _maybe_change_lane(pos: Vector2) -> void:
	if _drag_origin.size() != 1:
		return
	var ev: Dictionary = _drag_origin[0][0]
	var i := lane_index_at(pos.y)
	if i < 0:
		return
	var target: Dictionary = editor.lane_list()[i]
	if target["kind"] != "object" or ChartDefs.TYPES[ev["type"]]["lane"] != "object":
		return
	var home: Dictionary = editor.find_event(ev)
	if home.is_empty() or home["object"] == target["object"]:
		return
	home["events"].erase(ev)
	target["object"]["events"].append(ev)
