extends Control
## The attack editor. Open editor/attack_editor.tscn and press F6 (Run Current
## Scene). It edits a chart (charts/*.json) that the fight plays: when the
## enemy attacks and everything that happens during each attack.
##
## This file is the window: toolbar, playback, selection, undo and files.
## The timeline, preview and context panel live in their own scripts.

const Timeline = preload("res://editor/timeline.gd")
const Preview = preload("res://editor/preview.gd")
const Inspector = preload("res://editor/inspector.gd")
const TextEditorWindow = preload("res://editor/text_editor.gd")
const FONT = preload("res://fonts/PixelOperator.ttf")
const DEFAULT_CHART := "res://charts/testicina.json"
const AUTOSAVE_PATH := "user://attack_editor_autosave.json"
const SNAPS := [[1.0, "Snap: 1 beat"], [0.5, "Snap: 1/2"], [1.0 / 3.0, "Snap: 1/3"], [0.25, "Snap: 1/4"], [0.125, "Snap: 1/8"], [0.0, "Snap: off"]]
const SPEEDS := [0.25, 0.5, 0.75, 1.0, 1.5, 2.0]
const UNDO_LIMIT := 200
const HELP := """MOUSE
- Pick a node type in the palette, then click a lane to place it. Right-click (or Esc) to put the tool down.
- Click a node to select it; Ctrl+click to select several.
- Drag a node to move it (drag an object node onto another object lane to move it there).
- Drag a node's right edge to stretch it.
- Right-click a node to delete it.
- Click a lane's name to edit that object (sprite, hitbox, damage...).
- Click or drag the beat numbers to move the playhead. Clicking an empty spot also moves it.
- Mouse wheel: scroll the timeline. Ctrl+wheel: zoom. Shift+wheel: scroll lanes. Middle-drag: pan.
- In the preview: drag the soul to move it, and drag yellow markers to set positions.

KEYS (when you're not typing in a box)
- Space: play / pause      Home: back to the start
- Left / Right: step one snap (Shift: one bar)
- Delete: delete selected      Ctrl+Z / Ctrl+Y: undo / redo
- Ctrl+C / Ctrl+V: copy / paste at the playhead      Ctrl+D: duplicate
- Ctrl+S: save      Esc: put the tool down / deselect

PLAYTEST
Tick Playtest and press play to dodge with the arrow keys, like in the fight.

NODE ICONS
Drop a PNG named after a node type (e.g. random_point.png) into editor/icons/
and it shows up on the timeline and palette."""

var chart: Dictionary
var chart_path := DEFAULT_CHART
var dirty := false

var beat := 0.0
var playing := false
var direction := 1.0 # 1 = forward, -1 = backwards (silent)
var rate := 1.0 # current playback rate (speed, doubled while fast-forwarding)
var speed := 1.0
var snap := 0.25
var song_length_beats := 760.0
var playtest := false
var show_hitboxes := true
var follow := true

var selected: Array = [] # selected node dictionaries
var selected_object: Variant = null # object whose lane name was clicked
var armed_type := "" # the palette tool: clicking a lane places this node
var clipboard: Array = []

var player := AudioStreamPlayer.new()
var timeline: Timeline
var preview: Preview
var inspector: Inspector
var text_editor: TextEditorWindow
var status_label: Label
var time_label: Label
var title_label: Label
var play_button: Button
var file_dialog := FileDialog.new()
var _file_callback: Callable
var _palette_buttons := {}
var _undo: Array[String] = []
var _redo: Array[String] = []
var _last_edit_key := ""
var _last_edit_time := 0
var _autosave_in := -1.0


func _ready() -> void:
	# The game scales its 640x480 view to fit the window; the editor turns that
	# off so it uses the whole screen at full resolution.
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	if window.mode == Window.MODE_WINDOWED:
		window.mode = Window.MODE_MAXIMIZED
	window.title = "Lamplight Attack Editor"
	Engine.max_fps = 60
	set_anchors_preset(PRESET_FULL_RECT)
	var editor_theme := Theme.new()
	editor_theme.default_font = FONT
	editor_theme.default_font_size = 16
	theme = editor_theme
	add_child(player)
	_build_ui()

	var loaded := ChartDefs.load_chart(DEFAULT_CHART)
	set_chart(loaded if not loaded.is_empty() else ChartDefs.new_chart(), DEFAULT_CHART)


# --- UI ---

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	root.offset_left = 6
	root.offset_top = 6
	root.offset_right = -6
	root.offset_bottom = -4
	add_child(root)

	# Toolbar
	var top := HBoxContainer.new()
	root.add_child(top)
	_button(top, "Menu", _back_to_menu, "Back to the main menu (unsaved changes are kept in the autosave)")
	_button(top, "New", _confirm_new)
	_button(top, "Open", func(): _browse("Open chart", ["*.json ; Attack charts"], FileDialog.FILE_MODE_OPEN_FILE, _open_file))
	_button(top, "Save", save)
	_button(top, "Save As", func(): _browse("Save chart as", ["*.json ; Attack charts"], FileDialog.FILE_MODE_SAVE_FILE, _save_as))
	title_label = Label.new()
	title_label.custom_minimum_size.x = 220
	top.add_child(title_label)
	top.add_child(VSeparator.new())
	_button(top, "|<", func(): seek(0.0), "Back to the start (Home)")
	_button(top, "<<", func(): play(-1.0), "Play backwards (silent)")
	play_button = _button(top, ">", toggle_play, "Play / pause (Space)")
	_button(top, ">>", func(): play(1.0, true), "Fast forward (2x)")
	var speeds := OptionButton.new()
	speeds.focus_mode = FOCUS_NONE
	for s in SPEEDS:
		speeds.add_item("%sx" % s)
	speeds.select(SPEEDS.find(1.0))
	speeds.item_selected.connect(func(i):
		speed = SPEEDS[i]
		if playing:
			play(direction))
	top.add_child(speeds)
	time_label = Label.new()
	time_label.custom_minimum_size.x = 210
	top.add_child(time_label)
	top.add_child(VSeparator.new())
	var snaps := OptionButton.new()
	snaps.focus_mode = FOCUS_NONE
	for s in SNAPS:
		snaps.add_item(s[1])
	snaps.select(3)
	snaps.item_selected.connect(func(i): snap = SNAPS[i][0])
	top.add_child(snaps)
	_toggle(top, "Playtest", playtest, func(on): playtest = on, "Dodge with the arrow keys while it plays")
	_toggle(top, "Hitboxes", show_hitboxes, func(on): show_hitboxes = on)
	_toggle(top, "Follow", follow, func(on): follow = on, "Keep the playhead in view while playing")
	_button(top, "Help", _show_help)

	# Preview + context panel on top, palette + timeline below; the split can be dragged
	var split := VSplitContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(split)
	var middle := HSplitContainer.new()
	middle.custom_minimum_size.y = 280
	middle.size_flags_vertical = SIZE_EXPAND_FILL
	split.add_child(middle)
	preview = Preview.new()
	preview.editor = self
	preview.size_flags_horizontal = SIZE_EXPAND_FILL
	middle.add_child(preview)
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 380
	middle.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	inspector = Inspector.new()
	inspector.editor = self
	inspector.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(inspector)

	var bottom := VBoxContainer.new()
	bottom.custom_minimum_size.y = 300
	split.add_child(bottom)
	bottom.add_child(_build_palette())
	timeline = Timeline.new()
	timeline.editor = self
	timeline.size_flags_vertical = SIZE_EXPAND_FILL
	bottom.add_child(timeline)

	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	root.add_child(status_label)

	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.use_native_dialog = false
	file_dialog.file_selected.connect(func(path): _file_callback.call(path))
	file_dialog.size = Vector2i(800, 520)
	add_child(file_dialog)

	text_editor = TextEditorWindow.new()
	text_editor.editor = self
	add_child(text_editor)


func _build_palette() -> Control:
	var palette := HFlowContainer.new()
	var last_lane := ""
	for type in ChartDefs.TYPES:
		var def: Dictionary = ChartDefs.TYPES[type]
		if def["lane"] != last_lane:
			last_lane = def["lane"]
			var group := Label.new()
			group.text = "  %s:" % last_lane.capitalize()
			palette.add_child(group)
		var b := Button.new()
		b.text = def["label"]
		b.toggle_mode = true
		b.focus_mode = FOCUS_NONE
		b.tooltip_text = def["help"]
		b.icon = icon_for(type)
		b.expand_icon = false
		b.add_theme_color_override("font_color", def["color"])
		b.add_theme_color_override("font_pressed_color", Color.BLACK)
		var pressed_box := StyleBoxFlat.new()
		pressed_box.bg_color = def["color"]
		b.add_theme_stylebox_override("pressed", pressed_box)
		b.pressed.connect(arm.bind(type))
		palette.add_child(b)
		_palette_buttons[type] = b
	palette.add_child(VSeparator.new())
	_button(palette, "+ Object", add_object, "New object lane (with a Spawn node at the playhead)")
	_button(palette, "Duplicate Object", duplicate_object)
	_button(palette, "Delete Object", delete_object)
	_button(palette, "Lane Up", func(): move_object(-1))
	_button(palette, "Lane Down", func(): move_object(1))
	return palette


func _button(parent: Control, text: String, action: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _toggle(parent: Control, text: String, on: bool, action: Callable, tip := "") -> void:
	var b := CheckButton.new()
	b.text = text
	b.button_pressed = on
	b.focus_mode = FOCUS_NONE
	b.tooltip_text = tip
	b.toggled.connect(action)
	parent.add_child(b)


var _icons := {}
## The timeline/palette icon for a node type: editor/icons/<type>.png, if you've made one.
func icon_for(type: String) -> Texture2D:
	if not _icons.has(type):
		var path := "res://editor/icons/%s.png" % type
		_icons[type] = load(path) if ResourceLoader.exists(path) else null
	return _icons[type]


func open_text_editor(ev: Dictionary) -> void:
	text_editor.open(ev)


func set_status(text: String) -> void:
	status_label.text = text


func _update_title() -> void:
	title_label.text = "%s%s" % [chart_path.get_file(), " *" if dirty else ""]


func _show_help() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Attack editor help"
	dialog.dialog_text = HELP
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


# --- playback ---

func spb() -> float:
	return 60.0 / chart["bpm"]


func beat_to_seconds(b: float) -> float:
	return chart["offset"] + b * spb()


func _process(delta: float) -> void:
	if playing:
		if direction > 0.0 and player.playing:
			beat = (player.get_playback_position() + AudioServer.get_time_since_last_mix() - chart["offset"]) / spb()
		else:
			beat += direction * rate * delta / spb()
		if beat <= 0.0 or beat >= song_length_beats:
			beat = clampf(beat, 0.0, song_length_beats)
			stop_playback()
		if follow:
			timeline.follow(beat)
		timeline.queue_redraw()
	time_label.text = "beat %.2f   %s / %s" % [beat, _clock(beat_to_seconds(beat)), _clock(beat_to_seconds(song_length_beats))]

	if _autosave_in > 0.0:
		_autosave_in -= delta
		if _autosave_in <= 0.0:
			ChartDefs.save_chart(chart, AUTOSAVE_PATH)


func _clock(seconds: float) -> String:
	seconds = maxf(seconds, 0.0)
	return "%d:%05.2f" % [floori(seconds) / 60, fmod(seconds, 60.0)]


func play(dir: float, fast := false) -> void:
	playing = true
	direction = dir
	rate = speed * (2.0 if fast else 1.0)
	player.stop()
	if dir > 0.0 and player.stream:
		player.pitch_scale = rate
		player.play(maxf(beat_to_seconds(beat), 0.0))
	play_button.text = "||"


func stop_playback() -> void:
	playing = false
	player.stop()
	play_button.text = ">"


func toggle_play() -> void:
	if playing:
		stop_playback()
	else:
		play(1.0)


func seek(b: float) -> void:
	beat = clampf(b, 0.0, song_length_beats)
	if playing and direction > 0.0 and player.stream:
		player.play(maxf(beat_to_seconds(beat), 0.0))
	timeline.queue_redraw()


func snap_beat(b: float) -> float:
	return b if snap <= 0.0 else roundf(b / snap) * snap


func _load_song() -> void:
	var path: String = chart["song"]
	player.stream = load(path) if path != "" and ResourceLoader.exists(path) else null
	if player.stream:
		song_length_beats = (player.stream.get_length() - chart["offset"]) / spb()
	else:
		song_length_beats = 760.0
		set_status("No song loaded - pick one in the chart settings (click an empty spot, then the panel on the right).")


# --- chart, lanes, selection ---

func set_chart(new_chart: Dictionary, path: String) -> void:
	stop_playback()
	chart = new_chart
	chart_path = path
	selected = []
	selected_object = null
	_undo.clear()
	_redo.clear()
	dirty = false
	_load_song()
	preview.invalidate()
	inspector.refresh()
	timeline.queue_redraw()
	_update_title()


## [{"kind": "turn"|"board"|"object", "label": String, "object": Dictionary (object lanes)}]
func lane_list() -> Array:
	var lanes := [{"kind": "turn", "label": "Turns"}, {"kind": "text", "label": "Text"}, {"kind": "board", "label": "Board"}]
	for obj in chart["objects"]:
		lanes.append({"kind": "object", "label": ChartDefs.lane_label(obj), "object": obj})
	return lanes


func lane_events(lane: Dictionary) -> Array:
	match lane["kind"]:
		"turn": return chart["turn_events"]
		"text": return chart["text_events"]
		"board": return chart["board_events"]
	return lane["object"]["events"]


## The events array an event lives in (and its object, for object lanes).
func find_event(ev: Dictionary) -> Dictionary:
	for key in ["turn_events", "text_events", "board_events"]:
		if chart[key].has(ev):
			return {"events": chart[key], "object": null}
	for obj in chart["objects"]:
		if obj["events"].has(ev):
			return {"events": obj["events"], "object": obj}
	return {}


## The object being worked on: the one whose lane was clicked, or the one the selected node belongs to.
func current_object() -> Variant:
	if selected_object != null:
		return selected_object
	if not selected.is_empty():
		return find_event(selected[0]).get("object")
	return null


func select(events: Array) -> void:
	selected = events
	selected_object = null
	inspector.refresh()
	timeline.queue_redraw()


func select_object(obj: Dictionary) -> void:
	selected = []
	selected_object = obj
	inspector.refresh()
	timeline.queue_redraw()


func arm(type: String) -> void:
	armed_type = "" if armed_type == type else type
	for t in _palette_buttons:
		_palette_buttons[t].set_pressed_no_signal(t == armed_type)
	if armed_type != "":
		set_status("Click the %s lane to place %s. Right-click or Esc to stop." % [ChartDefs.TYPES[type]["lane"], ChartDefs.TYPES[type]["label"]])


# --- editing ---

func push_undo() -> void:
	_undo.append(JSON.stringify(chart))
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()


## Call after any change to the chart.
func changed(refresh_inspector := true) -> void:
	dirty = true
	_autosave_in = 2.0
	preview.invalidate()
	timeline.queue_redraw()
	if refresh_inspector:
		inspector.refresh()
	_update_title()


func undo() -> void:
	if _undo.is_empty():
		set_status("Nothing to undo")
		return
	_redo.append(JSON.stringify(chart))
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		set_status("Nothing to redo")
		return
	_undo.append(JSON.stringify(chart))
	_restore(_redo.pop_back())


func _restore(text: String) -> void:
	var selected_ids := selected.map(func(ev): return ev["id"])
	var object_id: int = selected_object["id"] if selected_object != null else -1
	chart = ChartDefs.parse_chart(text)
	text_editor.hide() # it was editing a node from the old copy
	selected = []
	selected_object = null
	for lane in lane_list():
		if lane["kind"] == "object" and lane["object"]["id"] == object_id:
			selected_object = lane["object"]
		for ev in lane_events(lane):
			if ev["id"] in selected_ids:
				selected.append(ev)
	_last_edit_key = ""
	_load_song()
	changed()


## Changes one setting. Quick repeated changes to the same setting (typing,
## dragging a number) share one undo step.
func set_param(target: Dictionary, key: String, value, in_params: bool) -> void:
	var edit_key := "%s/%s" % [target.get("id", "chart"), key]
	var now := Time.get_ticks_msec()
	if edit_key != _last_edit_key or now - _last_edit_time > 800:
		push_undo()
	_last_edit_key = edit_key
	_last_edit_time = now
	if in_params:
		target["params"][key] = value
	else:
		target[key] = value
	if key in ["song", "bpm", "offset"]:
		_load_song()
	changed(false)


func place(type: String, lane: Dictionary, at: float) -> void:
	var def: Dictionary = ChartDefs.TYPES[type]
	if def["lane"] != lane["kind"]:
		set_status("%s goes on the %s lane." % [def["label"], def["lane"]])
		return
	push_undo()
	var ev := ChartDefs.new_event(chart, type, maxf(at, 0.0))
	lane_events(lane).append(ev)
	# A new attack gets an End Attack 24 beats later, unless something already follows it
	if type == "begin_attack" and not chart["turn_events"].any(func(e): return e != ev and e["beat"] > at):
		chart["turn_events"].append(ChartDefs.new_event(chart, "end_attack", at + 24.0))
	select([ev])
	changed()


func delete_events(events: Array) -> void:
	if events.is_empty():
		return
	push_undo()
	for ev in events:
		var home := find_event(ev)
		if not home.is_empty():
			home["events"].erase(ev)
	selected = selected.filter(func(ev): return ev not in events)
	changed()


func copy() -> void:
	clipboard = []
	for ev in selected:
		var home := find_event(ev)
		var obj = home.get("object")
		clipboard.append({"ev": ev.duplicate(true), "events": home["events"], "object_id": obj["id"] if obj != null else -1})
	set_status("Copied %d node(s)" % clipboard.size())


func paste(at: float) -> void:
	if clipboard.is_empty():
		return
	push_undo()
	var first: float = clipboard.map(func(c): return c["ev"]["beat"]).min()
	var pasted := []
	for item in clipboard:
		var ev: Dictionary = item["ev"].duplicate(true)
		ev["id"] = ChartDefs.take_id(chart)
		ev["beat"] = at + ev["beat"] - first
		var target: Array = item["events"]
		if item["object_id"] != -1 and not chart["objects"].any(func(o): return o["id"] == item["object_id"]):
			var obj = current_object() # the original lane is gone; use the current one
			if obj == null:
				continue
			target = obj["events"]
		target.append(ev)
		pasted.append(ev)
	select(pasted)
	changed()


func duplicate_selected() -> void:
	if selected.is_empty():
		return
	copy()
	var start: float = selected.map(func(ev): return ev["beat"]).min()
	var end: float = selected.map(func(ev): return maxf(ChartDefs.event_end(ev), ev["beat"] + snap)).max()
	paste(start + snap_beat(end - start))


func add_object() -> void:
	push_undo()
	var obj := ChartDefs.new_object(chart, "pellet")
	obj["lane_label"] = "object %d" % (chart["objects"].size() + 1)
	obj["events"].append(ChartDefs.new_event(chart, "spawn", snap_beat(beat)))
	chart["objects"].append(obj)
	selected = [obj["events"][0]]
	selected_object = null
	changed()
	timeline.show_lane(chart["objects"].size() + 2)


func duplicate_object() -> void:
	var obj = current_object()
	if obj == null:
		set_status("Click an object lane's name first")
		return
	push_undo()
	var copy_obj: Dictionary = obj.duplicate(true)
	copy_obj["id"] = ChartDefs.take_id(chart)
	copy_obj["lane_label"] = ChartDefs.lane_label(obj) + " copy"
	for ev in copy_obj["events"]:
		ev["id"] = ChartDefs.take_id(chart)
	chart["objects"].insert(chart["objects"].find(obj) + 1, copy_obj)
	select_object(copy_obj)
	changed()


func delete_object() -> void:
	var obj = current_object()
	if obj == null:
		set_status("Click an object lane's name first")
		return
	push_undo()
	chart["objects"].erase(obj)
	selected = []
	selected_object = null
	changed()


func move_object(step: int) -> void:
	var obj = current_object()
	if obj == null:
		return
	var i: int = chart["objects"].find(obj)
	var j := clampi(i + step, 0, chart["objects"].size() - 1)
	if i == j:
		return
	push_undo()
	chart["objects"].remove_at(i)
	chart["objects"].insert(j, obj)
	changed()


# --- files ---

func _browse(title: String, filters: Array, mode: FileDialog.FileMode, on_pick: Callable) -> void:
	file_dialog.title = title
	file_dialog.file_mode = mode
	file_dialog.filters = PackedStringArray(filters)
	_file_callback = on_pick
	file_dialog.popup_centered()


## For the context panel's Browse buttons.
func browse_file(kind: String, on_pick: Callable) -> void:
	var filters := ["*.png ; Images"] if kind == "texture" else ["*.mp3, *.ogg, *.wav ; Audio"]
	_browse("Pick a file", filters, FileDialog.FILE_MODE_OPEN_FILE, on_pick)


func save() -> void:
	var err := ChartDefs.save_chart(chart, chart_path)
	if err == OK:
		dirty = false
		_update_title()
		set_status("Saved %s" % chart_path)
	else:
		set_status("Couldn't save %s (error %d)" % [chart_path, err])


func _save_as(path: String) -> void:
	chart_path = path
	save()


func _open_file(path: String) -> void:
	var loaded := ChartDefs.load_chart(path)
	if loaded.is_empty():
		set_status("Couldn't read %s" % path)
		return
	set_chart(loaded, path)
	set_status("Opened %s" % path)


func _confirm_new() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Start a new, empty chart?%s" % ("\nUnsaved changes will be lost." if dirty else "")
	dialog.confirmed.connect(func():
		set_chart(ChartDefs.new_chart(), "res://charts/new_chart.json")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


# --- keys ---

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var ctrl := key.ctrl_pressed or key.meta_pressed
	var handled := true
	if ctrl:
		match key.keycode:
			KEY_Z:
				if key.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y:
				redo()
			KEY_C:
				copy()
			KEY_V:
				paste(snap_beat(beat))
			KEY_D:
				duplicate_selected()
			KEY_S:
				save()
			_:
				handled = false
	else:
		match key.keycode:
			KEY_SPACE:
				toggle_play()
			KEY_HOME:
				seek(0.0)
			KEY_LEFT, KEY_RIGHT:
				if playtest and playing:
					handled = false # the arrows are moving the soul
				else:
					var step := 4.0 if key.shift_pressed else maxf(snap, 0.25)
					seek(snap_beat(beat) + (step if key.keycode == KEY_RIGHT else -step))
					timeline.follow(beat)
			KEY_DELETE, KEY_BACKSPACE:
				delete_events(selected.duplicate())
			KEY_ESCAPE:
				if armed_type != "":
					arm(armed_type)
				else:
					select([])
			_:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _back_to_menu() -> void:
	stop_playback()
	if dirty:
		ChartDefs.save_chart(chart, AUTOSAVE_PATH)
	get_tree().change_scene_to_file("res://menu.tscn") # the menu restores the game's scaling
