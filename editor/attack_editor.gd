extends Control
## The attack editor. Open editor/attack_editor.tscn and press F6 (Run Current
## Scene). It edits a chart (a .scrp file, or charts/*.json) that the fight plays:
## when the enemy attacks and everything that happens during each attack.
##
## This file is the window: toolbar, playback, selection, undo and files.
## The timeline, preview and context panel live in their own scripts.

const Timeline = preload("res://editor/timeline.gd")
const Preview = preload("res://editor/preview.gd")
const Inspector = preload("res://editor/inspector.gd")
const TextEditorWindow = preload("res://editor/text_editor.gd")
const FormulaEditorWindow = preload("res://editor/formula_editor.gd")
const NodeTabs = preload("res://editor/node_tabs.gd")
const CharactersPanel = preload("res://editor/characters_panel.gd")
const RulesPanel = preload("res://editor/rules_panel.gd")
const NewChartDialog = preload("res://editor/new_chart_dialog.gd")
const FONT = preload("res://fonts/PixelOperator.ttf")
const DEFAULT_CHART := "res://charts/testicina.json"
const AUTOSAVE_PATH := "user://attack_editor_autosave.json"
const SNAPS := [[1.0, "Snap: 1 beat"], [0.5, "Snap: 1/2"], [1.0 / 3.0, "Snap: 1/3"], [0.25, "Snap: 1/4"], [0.125, "Snap: 1/8"], [0.0, "Snap: off"]]
const FRAME_SNAPS := [[1.0, "Snap: 1 frame"], [5.0, "Snap: 5"], [10.0, "Snap: 10"], [15.0, "Snap: 15"], [30.0, "Snap: 30"], [0.0, "Snap: off"]]
const ICON_FOLDER := "res://sprites/node_icons/"
## What each kind of file picker shows, and where a plain chart's copies go.
const BROWSE_KINDS := {
	"texture": [["*.png,*.jpg,*.jpeg,*.webp;Images"], "sprites"],
	"audio": [["*.mp3,*.ogg,*.wav;Audio"], "sounds"],
	"font": [["*.ttf,*.otf,*.woff,*.woff2;Fonts"], "fonts"],
	"video": [VideoImport.FILTERS, "videos"],
}
const OPEN_FILTERS := ["*.scrp,*.json;Fights"]
const SAVE_FILTERS := ["*.scrp;Scrap file (the fight and all its files)", "*.json;Plain chart (the fight only)"]
const SPEEDS := [0.25, 0.5, 0.75, 1.0, 1.5, 2.0]
const UNDO_LIMIT := 200
const CHARACTERS_TAB := 1
const HELP := """TABS
[HOVER TAB] SHOW ITS NODES      [HOVER GROUP] OPEN IT      [WHEEL] SCROLL A LONG LIST
[LMB] ON A NODE: ADD AFTER THE LATEST NODE      [LMB DRAG] PLACE ON THE TIMELINE

TIMELINE
[LMB] SELECT NODE      [CTRL+LMB] SELECT SEVERAL      [RMB] DELETE NODE
[LMB DRAG] MOVE NODE, OR ONTO ANOTHER OBJECT LANE      [CTRL+LMB DRAG] MOVE WITHOUT SNAPPING
[LMB DRAG] A NODE'S RIGHT EDGE: STRETCH IT
[LMB] A LANE'S NAME: EDIT THAT OBJECT (SPRITE, SOUND, HITBOX, DAMAGE...)
[LMB] OR [LMB DRAG] THE NUMBERS ALONG THE TOP, OR [LMB] AN EMPTY SPOT: MOVE THE PLAYHEAD
[WHEEL] SCROLL      [CTRL+WHEEL] ZOOM      [SHIFT+WHEEL] SCROLL LANES      [MMB DRAG] PAN

PREVIEW
[LMB DRAG] THE SOUL: MOVE IT      [LMB] THE SOUL: SELECT IT      [LMB DRAG] A YELLOW MARKER: SET ITS POSITION
[LMB DRAG] THE SELECTED OBJECT OR SOUL'S HITBOX: MOVE IT (HITBOXES MUST BE ON)
[LMB] A CHARACTER: SELECT THEM      [LMB DRAG] THE SELECTED CHARACTER: MOVE THEM

KEYS (WHEN YOU'RE NOT TYPING IN A BOX)
[SPACE] PLAY / PAUSE      [HOME] BACK TO THE START
[LEFT] [RIGHT] STEP ONE SNAP      [SHIFT+LEFT] [SHIFT+RIGHT] STEP FURTHER
[DEL] DELETE SELECTED      [CTRL+Z] UNDO      [CTRL+Y] REDO
[CTRL+C] COPY      [CTRL+V] PASTE AT THE PLAYHEAD      [CTRL+D] DUPLICATE
[CTRL+S] SAVE      [ESC] DESELECT

PLAYTEST
Tick Playtest and press play to dodge with the game's controls.
Test Fight saves the chart and plays it for real."""

## The chart that was open, so coming back from a test fight reopens it.
static var last_chart_path := DEFAULT_CHART

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
var soul_selected := false # the soul was clicked in the preview
var latest_event: Dictionary = {} # the node added most recently
var clipboard: Array = []

var player := AudioStreamPlayer.new()
var timeline: Timeline
var preview: Preview
var inspector: Inspector
var characters_panel: CharactersPanel
var rules_panel: RulesPanel
var side_tabs := TabContainer.new()
var node_tabs: NodeTabs
var snap_picker := OptionButton.new()
var text_editor: TextEditorWindow
var formula_editor: FormulaEditorWindow
var status_label: Label
var time_label: Label
var title_label: Label
var play_button: Button
var file_dialog := FileDialog.new()
var _file_callback: Callable
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
	editor_theme.set_icon("unchecked", "CheckBox", _empty_box_icon())
	theme = editor_theme
	add_child(player)
	player.bus = &"Music"
	_build_ui()

	var loaded := ChartDefs.load_chart(last_chart_path)
	set_chart(loaded if not loaded.is_empty() else ChartDefs.new_chart(), last_chart_path)


# --- UI ---

## The default unticked checkbox is nearly invisible on this dark background.
func _empty_box_icon() -> Texture2D:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for i in range(1, 15):
		for edge in [1, 14]:
			image.set_pixel(i, edge, Color.WHITE)
			image.set_pixel(edge, i, Color.WHITE)
	return ImageTexture.create_from_image(image)


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
	_button(top, "Open", func(): _browse("Open fight", OPEN_FILTERS, FileDialog.FILE_MODE_OPEN_FILE, _open_file, ScrapFile.folder()))
	_button(top, "Save", save)
	_button(top, "Save As", func(): _browse("Save fight as", SAVE_FILTERS, FileDialog.FILE_MODE_SAVE_FILE, _save_as, ScrapFile.folder()))
	title_label = Label.new()
	title_label.custom_minimum_size.x = 220
	top.add_child(title_label)
	top.add_child(VSeparator.new())
	_button(top, "|<", func(): seek(0.0), "[HOME] BACK TO THE START")
	_button(top, "<<", func(): play(-1.0), "Play backwards (silent)")
	play_button = _button(top, ">", toggle_play, "[SPACE] PLAY / PAUSE")
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
	snap_picker.focus_mode = FOCUS_NONE
	snap_picker.item_selected.connect(func(i): snap = _snap_list()[i][0])
	top.add_child(snap_picker)
	_toggle(top, "Playtest", playtest, func(on): playtest = on, "Dodge with the game's controls while it plays")
	_toggle(top, "Hitboxes", show_hitboxes, func(on): show_hitboxes = on)
	_toggle(top, "Follow", follow, func(on): follow = on, "Keep the playhead in view while playing")
	_button(top, "Test Fight", _test_fight, "Save this chart and play it for real")
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
	side_tabs.custom_minimum_size.x = 440
	middle.add_child(side_tabs)
	inspector = _add_panel(Inspector.new(), "Selection")
	characters_panel = _add_panel(CharactersPanel.new(), "Characters")
	rules_panel = _add_panel(RulesPanel.new(), "Rules")

	var bottom := VBoxContainer.new()
	bottom.custom_minimum_size.y = 300
	split.add_child(bottom)
	var tool_row := HBoxContainer.new()
	bottom.add_child(tool_row)
	node_tabs = NodeTabs.new()
	node_tabs.editor = self
	tool_row.add_child(node_tabs)
	tool_row.add_child(VSeparator.new())
	_button(tool_row, "+ Object", add_object, "New object lane: pick its sprite in the panel on the right")
	_button(tool_row, "Duplicate Object", duplicate_object)
	_button(tool_row, "Delete Object", delete_object)
	_button(tool_row, "Lane Up", func(): move_object(-1))
	_button(tool_row, "Lane Down", func(): move_object(1))
	timeline = Timeline.new()
	timeline.editor = self
	timeline.size_flags_vertical = SIZE_EXPAND_FILL
	bottom.add_child(timeline)

	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	root.add_child(status_label)

	# Windows' own file picker (Godot only offers it for the whole filesystem)
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.file_selected.connect(func(path): _file_callback.call(path))
	file_dialog.size = Vector2i(800, 520)
	add_child(file_dialog)

	text_editor = TextEditorWindow.new()
	text_editor.editor = self
	add_child(text_editor)
	formula_editor = FormulaEditorWindow.new()
	formula_editor.editor = self
	add_child(formula_editor)


## One tab of the panel on the right.
func _add_panel(panel: Control, tab_name: String) -> Control:
	panel.editor = self
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(panel)
	side_tabs.add_child(scroll)
	return panel


func _refresh_panels() -> void:
	inspector.refresh()
	characters_panel.refresh()
	rules_panel.refresh()


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
func icon_for(type: String) -> Texture2D:
	if not _icons.has(type):
		var path := ICON_FOLDER + type + ".png"
		_icons[type] = load(path) if ResourceLoader.exists(path) else null
	return _icons[type]


func open_text_editor(ev: Dictionary) -> void:
	text_editor.open(ev)


func open_formula_editor(ev: Dictionary) -> void:
	formula_editor.open(ev)


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

func uses_frames() -> bool:
	return ChartDefs.uses_frames(chart)


## What the timeline counts: "beat", or "frame" in a traditional battle.
func unit_name() -> String:
	return "frame" if uses_frames() else "beat"


## How many timeline units make a bar line.
func bar_length() -> int:
	return 60 if uses_frames() else 4


func spb() -> float:
	return 1.0 / ChartDefs.units_per_second(chart)


func beat_to_seconds(b: float) -> float:
	return chart["offset"] + b * spb()


func _process(delta: float) -> void:
	if playing:
		if direction > 0.0 and player.playing and not uses_frames():
			beat = (player.get_playback_position() + AudioServer.get_time_since_last_mix() - chart["offset"]) / spb()
		else:
			beat += direction * rate * delta / spb()
		if beat <= 0.0 or beat >= song_length_beats:
			beat = clampf(beat, 0.0, song_length_beats)
			stop_playback()
		if follow:
			timeline.follow(beat)
		timeline.queue_redraw()
	time_label.text = "%s %.2f   %s / %s" % [unit_name(), beat, _clock(beat_to_seconds(beat)), _clock(beat_to_seconds(song_length_beats))]

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
		# In frames the song just loops along: attacks aren't tied to it
		player.play(0.0 if uses_frames() else maxf(beat_to_seconds(beat), 0.0))
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
	if playing and direction > 0.0 and player.stream and not uses_frames():
		player.play(maxf(beat_to_seconds(beat), 0.0))
	timeline.queue_redraw()


func snap_beat(b: float) -> float:
	return b if snap <= 0.0 else roundf(b / snap) * snap


func _load_song() -> void:
	player.stream = ChartDefs.load_audio(chart["song"])
	ChartDefs.set_looping(player.stream, uses_frames())
	_rebuild_snaps()
	if uses_frames():
		song_length_beats = ChartDefs.SONG_LOOP_FRAMES
	elif player.stream:
		song_length_beats = (player.stream.get_length() - chart["offset"]) / spb()
	else:
		song_length_beats = 760.0
		set_status("No song loaded - pick one in the chart settings (click an empty spot, then the panel on the right).")


func _snap_list() -> Array:
	return FRAME_SNAPS if uses_frames() else SNAPS


## Beats and frames snap to different sizes.
func _rebuild_snaps() -> void:
	var wanted := _snap_list()
	if snap_picker.item_count > 0 and snap_picker.get_item_text(0) == wanted[0][1]:
		return
	snap_picker.clear()
	for entry in wanted:
		snap_picker.add_item(entry[1])
	var pick := 2 if uses_frames() else 3
	snap_picker.select(pick)
	snap = wanted[pick][0]
	if timeline:
		timeline.ppb = 4.0 if uses_frames() else 32.0
		timeline.scroll = 0.0


# --- chart, lanes, selection ---

func set_chart(new_chart: Dictionary, path: String) -> void:
	stop_playback()
	chart = new_chart
	chart_path = path
	last_chart_path = path
	selected = []
	selected_object = null
	latest_event = {}
	_undo.clear()
	_redo.clear()
	dirty = false
	_load_song()
	preview.invalidate()
	_refresh_panels()
	timeline.queue_redraw()
	_update_title()


## [{"kind": "turn"|"text"|"meta"|"board"|"object", "label": String, "object": Dictionary (object lanes)}]
func lane_list() -> Array:
	var lanes := [{"kind": "turn", "label": "Turns"}, {"kind": "text", "label": "Text"}, {"kind": "meta", "label": "Meta"}, {"kind": "board", "label": "Board"}]
	for obj in chart["objects"]:
		lanes.append({"kind": "object", "label": ChartDefs.lane_label(obj), "object": obj})
	return lanes


func lane_events(lane: Dictionary) -> Array:
	match lane["kind"]:
		"turn": return chart["turn_events"]
		"text": return chart["text_events"]
		"meta": return chart["meta_events"]
		"board": return chart["board_events"]
	return lane["object"]["events"]


## The events array an event lives in (and its object, for object lanes).
func find_event(ev: Dictionary) -> Dictionary:
	for key in ["turn_events", "text_events", "meta_events", "board_events"]:
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
	soul_selected = false
	if not events.is_empty():
		side_tabs.current_tab = 0
	inspector.refresh()
	timeline.queue_redraw()


func select_object(obj: Dictionary) -> void:
	selected = []
	selected_object = obj
	soul_selected = false
	side_tabs.current_tab = 0
	inspector.refresh()
	timeline.queue_redraw()


## The attack a beat falls in, or {} if it's between attacks.
func attack_containing(b: float) -> Dictionary:
	for a in ChartDefs.attacks(chart):
		if a["start"] <= b and b < a["end"]:
			return a
	return {}


func character_names() -> Array:
	var names := []
	for entry in chart["party"] + chart["enemies"]:
		names.append(entry["name"])
	return names


## What a Change Rules node can aim at.
func change_targets() -> Array:
	return ["rules"] + character_names()


## The character selected on the Characters tab, or null if that tab isn't open.
func selected_character() -> Variant:
	return characters_panel.current_data() if side_tabs.current_tab == CHARACTERS_TAB else null


func select_character(data: Dictionary) -> void:
	side_tabs.current_tab = CHARACTERS_TAB
	characters_panel.pick(data)


func select_soul() -> void:
	selected = []
	selected_object = null
	soul_selected = true
	side_tabs.current_tab = 0
	inspector.refresh()
	timeline.queue_redraw()


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
		_refresh_panels()
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
	formula_editor.hide()
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
	if key in ["song", "bpm", "offset", "battle_type"]:
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
	latest_event = ev
	# A new attack gets an End Attack after it, unless something already follows it
	if type == "begin_attack" and not chart["turn_events"].any(func(e): return e != ev and e["beat"] > at):
		chart["turn_events"].append(ChartDefs.new_event(chart, "end_attack", at + (360.0 if uses_frames() else 24.0)))
	select([ev])
	changed()


## A tab row was clicked: adds the node right after the latest one on its lane.
func add_after_latest(type: String) -> void:
	var lane_kind: String = ChartDefs.TYPES[type]["lane"]
	var lane := {}
	for candidate in lane_list():
		if candidate["kind"] == lane_kind and (lane_kind != "object" or candidate["object"] == current_object()):
			lane = candidate
			break
	if lane.is_empty() and lane_kind == "object":
		var latest_home: Dictionary = find_event(latest_event) if not latest_event.is_empty() else {}
		if latest_home.get("object") != null:
			lane = {"kind": "object", "object": latest_home["object"]}
	if lane.is_empty():
		set_status("Click an object's lane first, or press + Object.")
		return
	place(type, lane, _after_latest_on(lane))


## Where a clicked-in node goes: right after the newest node if it's on this
## lane, otherwise after the last node at or before the playhead.
func _after_latest_on(lane: Dictionary) -> float:
	var events: Array = lane_events(lane)
	var anchor: Dictionary = latest_event if events.has(latest_event) else {}
	if anchor.is_empty():
		for ev in events:
			if ev["beat"] <= beat and (anchor.is_empty() or ev["beat"] > anchor["beat"]):
				anchor = ev
	if anchor.is_empty():
		return snap_beat(beat)
	var step: float = snap if snap > 0.0 else 1.0
	return anchor["beat"] + (step if ChartDefs.is_instant(anchor["type"]) else anchor["length"])


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
	var spawn := ChartDefs.new_event(chart, "spawn", snap_beat(beat))
	obj["events"].append(spawn)
	chart["objects"].append(obj)
	latest_event = spawn
	select_object(obj) # straight to its settings, to pick a sprite
	changed()
	timeline.show_lane(chart["objects"].size() + 3)


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

func _browse(title: String, filters: Array, mode: FileDialog.FileMode, on_pick: Callable, start_folder := "") -> void:
	file_dialog.title = title
	if start_folder != "":
		file_dialog.current_dir = ProjectSettings.globalize_path(start_folder)
	file_dialog.file_mode = mode
	file_dialog.filters = PackedStringArray(filters)
	_file_callback = on_pick
	file_dialog.popup_centered()


## For the Browse buttons: pick a sprite or sound from anywhere on the PC. Scraps
## pack their files when saved; for a plain chart, files from outside the project
## get copied in so the chart keeps working.
func browse_file(kind: String, on_pick: Callable, for_new_scrap := false) -> void:
	var filters: Array = BROWSE_KINDS[kind][0]
	var folder: String = BROWSE_KINDS[kind][1]
	_browse("Pick a file", filters, FileDialog.FILE_MODE_OPEN_FILE, func(path):
		var packs_itself := for_new_scrap or ScrapFile.is_scrap(chart_path)
		if kind != "video":
			on_pick.call(ProjectSettings.localize_path(path) if packs_itself else _import_file(path, folder))
			return
		set_status("Converting %s..." % path.get_file())
		VideoImport.convert_video(path, func(result):
			if result["error"] != "":
				set_status(result["error"])
				return
			set_status("Video ready: %s" % result["path"].get_file())
			on_pick.call(ProjectSettings.localize_path(result["path"]) if packs_itself else _import_file(result["path"], folder))))


func _import_file(path: String, folder: String) -> String:
	if not OS.has_feature("editor"):
		return path # a built game can't copy into itself; saving packs it into a scrap
	var inside := ProjectSettings.localize_path(path)
	if inside.begins_with("res://"):
		return inside
	var target := "res://%s/imported/%s" % [folder, path.get_file()]
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if DirAccess.copy_absolute(path, ProjectSettings.globalize_path(target)) == OK:
		set_status("Imported %s" % target)
		return target
	set_status("Couldn't copy %s into the project; using it where it is." % path.get_file())
	return path


func save() -> void:
	# A built game can't write inside itself, so its own fights save as a scrap
	if chart_path.begins_with("res://") and not OS.has_feature("editor"):
		chart_path = ScrapFile.unused_path(chart_path.get_file().get_basename())
		last_chart_path = chart_path
	var err := ChartDefs.save_chart(chart, chart_path)
	if err == OK:
		dirty = false
		_update_title()
		var missing: Array = ScrapFile.last_missing if ScrapFile.is_scrap(chart_path) else []
		if missing.is_empty():
			set_status("Saved %s" % chart_path)
		else:
			set_status("Saved %s, but couldn't find: %s" % [chart_path, ", ".join(missing.map(func(m): return m.get_file()))])
	else:
		set_status("Couldn't save %s (error %d)" % [chart_path, err])


func _save_as(path: String) -> void:
	if path.get_extension() == "":
		path += "." + ScrapFile.EXTENSION
	chart_path = ProjectSettings.localize_path(path)
	save()


func _open_file(path: String) -> void:
	path = ProjectSettings.localize_path(path)
	var loaded := ChartDefs.load_chart(path)
	if loaded.is_empty():
		set_status(ScrapFile.last_error if ScrapFile.is_scrap(path) else "Couldn't read %s" % path)
		return
	set_chart(loaded, path)
	set_status("Opened %s" % path)


## Plays a minigame in a little window, to try out its settings. Z to tap, and it
## starts over when it ends.
func try_minigame(id: String, settings: Dictionary) -> void:
	var window := Window.new()
	window.title = "Try it: %s (it restarts when it ends)" % GameSettings.hint([["ACCEPT", "TAP"]])
	var box := Minigame.box_size(id, settings)
	var game_size := box - Vector2(20, 16) if box != Vector2.ZERO else Vector2(296, 94)
	var zoom := 1.5 if box != Vector2.ZERO else 2.0
	window.size = Vector2i(game_size * zoom + Vector2(40, 40))
	window.close_requested.connect(window.queue_free)
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.set_anchors_preset(PRESET_FULL_RECT)
	window.add_child(backdrop)
	add_child(window)
	window.popup_centered()
	var play_again := func(again: Callable) -> void:
		if not is_instance_valid(window):
			return
		var game := Minigame.create(id)
		game.position = Vector2(20, 20)
		game.size = game_size
		game.scale = Vector2(zoom, zoom)
		window.add_child(game)
		game.start(ChartDefs.MINIGAMES[id]["label"], settings)
		var multiplier: float = await game.finished
		set_status("%s: damage x%.2f" % [ChartDefs.MINIGAMES[id]["label"], multiplier])
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(game):
			game.queue_free()
		again.call(again)
	play_again.call(play_again)


func _confirm_new() -> void:
	var dialog := NewChartDialog.new()
	dialog.editor = self
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


## The new chart prompt was filled in.
func create_chart(new_chart: Dictionary, path: String) -> void:
	if dirty:
		ChartDefs.save_chart(chart, AUTOSAVE_PATH)
	set_chart(new_chart, path)
	save()
	side_tabs.current_tab = 1 # next stop: their sprites and stats


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
					var step: float = float(bar_length()) if key.shift_pressed else (snap if snap > 0.0 else 0.25)
					seek(snap_beat(beat) + (step if key.keycode == KEY_RIGHT else -step))
					timeline.follow(beat)
			KEY_DELETE, KEY_BACKSPACE:
				delete_events(selected.duplicate())
			KEY_ESCAPE:
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


func _test_fight() -> void:
	save()
	stop_playback()
	Battle.chart_to_play = chart_path
	GameSettings.apply_game_view()
	get_tree().change_scene_to_file("res://node_2d.tscn")
