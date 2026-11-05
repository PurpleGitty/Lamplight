extends Control
## The Locale-Inator: makes overworlds. The room takes up the middle, tools run along
## the top, rooms and layers are on the left and every setting's on the right.

const LocaleViewport = preload("res://editor/locale_viewport.gd")
const Panels = preload("res://editor/locale_panels.gd")
const FONT = preload("res://fonts/PixelOperator.ttf")
const OPEN_FILTERS := ["*.lcal;Overworlds"]
const FIGHT_FILTERS := ["*.scrp;Scraps"]
const UNDO_LIMIT := 100
const AUTOSAVE_SECONDS := 15.0
const AUTOSAVE_PATH := "user://locale_autosave.lcal"
const AUTOSAVE_NOTE := "user://locale_autosave.txt" # which file it's an unsaved copy of
const BROWSE_KINDS := {
	"texture": ["*.png,*.jpg,*.jpeg,*.webp;Images"],
	"audio": ["*.mp3,*.ogg,*.wav;Audio"],
	"font": ["*.ttf,*.otf,*.woff,*.woff2;Fonts"],
	"video": VideoImport.FILTERS,
	"fight": FIGHT_FILTERS,
}
const TOOL_KEYS := {KEY_V: "select", KEY_B: "paint", KEY_E: "erase", KEY_I: "eyedropper", KEY_G: "fill", KEY_U: "shape", KEY_C: "contour"}
const HELP := """DRAWING
TOOL WHEEL (BOTTOM LEFT): [WHEEL] OVER IT TO SPIN IT      [LMB] A TOOL TO PICK IT
[V] SELECTOR      [B] PENCIL      [E] ERASER      [I] EYEDROPPER      [G] BUCKET      [U] SHAPE      [C] CONTOUR
[LMB] USES THE TOOL      [RMB] USES IT TO RUB OUT
Shape: [LMB DRAG] A RECTANGLE      [SHIFT] HOLLOW      [ALT] ROUND
Contour: [LMB DRAG] AROUND AN AREA TO FILL IT IN
Each layer is one kind of tile. Edges and corners get worked out as you draw.

OBJECTS
Pick a kind on the left, then [LMB] to place it.
[LMB] SELECT      [LMB DRAG] MOVE      [CTRL+LMB DRAG] MOVE WITHOUT SNAPPING      [DEL] DELETE      [CTRL+D] DUPLICATE
Sprite and NPC show in the game. Trigger, Warp and Spawn are invisible.

MOVING AROUND
[WHEEL] ZOOM      [MMB DRAG] PAN      [M] MAP OF ALL ROOMS      [H] SHOW OR HIDE INVISIBLE THINGS      [1] TO [9] PICK A LAYER

CUTSCENES
Place a Path, then [LMB DRAG] to draw it or [LMB] to add points, and [RMB] to finish. A Follow Path step walks someone along it. Cues on its points set off animations, sounds and lines as they get there. Play Animation steps work anywhere.

THE CAMERA
The camera stops at the drawn edge of a room (the red line). A room that fits the screen doesn't scroll at all, so a long corridor scrolls one way and a big area scrolls both.

CONNECTING ROOMS
Select a warp and use Make It Two-way or Lead To A New Room. The Map shows every room and arrows for each warp.

KEYS
[CTRL+Z] UNDO      [CTRL+Y] REDO      [CTRL+S] SAVE"""

static var last_path := ""

var locale: Dictionary
var path := ""
var room: Dictionary
var layer: Variant = null
var selected: Variant = null
var tool := "paint"
var placing := ""
var show_invisible := true
var show_grid := true
var map_mode := false
var dirty := false

var viewport: LocaleViewport
var rooms_list := ItemList.new()
var layers_list := ItemList.new()
var side_tabs := TabContainer.new()
var panels := {}
var place_buttons := {}
var title_label := Label.new()
var status_label := Label.new()
var file_dialog := FileDialog.new()
var _file_callback: Callable
var _undo: Array[String] = []
var _redo: Array[String] = []
var _last_edit_key := ""
var _last_edit_time := 0
var _invisible_toggle: CheckButton
var _map_toggle: CheckButton
var _autosave_in := -1.0


func _ready() -> void:
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	if window.mode == Window.MODE_WINDOWED:
		window.mode = Window.MODE_MAXIMIZED
	window.title = "Lamplight Locale-Inator"
	Engine.max_fps = 60
	set_anchors_preset(PRESET_FULL_RECT)
	var editor_theme := Theme.new()
	editor_theme.default_font = FONT
	editor_theme.default_font_size = 16
	theme = editor_theme
	_build_ui()
	if _recover_autosave():
		return
	var loaded := LocaleFile.read(last_path) if last_path != "" and LocaleFile.is_locale(last_path) else {}
	if loaded.is_empty():
		_use_locale(LocaleDefs.new_locale(), "")
	else:
		_use_locale(loaded, last_path)


## Which Place button's lit: what's being placed, or the path still being drawn.
func _light_place_button() -> void:
	var lit := placing
	if viewport._drawing_path != null:
		lit = "path"
	for type in place_buttons:
		if place_buttons[type].button_pressed != (type == lit):
			place_buttons[type].set_pressed_no_signal(type == lit)


func _process(delta: float) -> void:
	_light_place_button()
	if _autosave_in > 0.0:
		_autosave_in -= delta
		if _autosave_in <= 0.0:
			_write_autosave()


## Unsaved work goes in a copy of its own, in case of a crash.
func _write_autosave() -> void:
	if not dirty:
		return
	if LocaleFile.write(locale, AUTOSAVE_PATH) == OK:
		FileAccess.open(AUTOSAVE_NOTE, FileAccess.WRITE).store_string(path)


func _clear_autosave() -> void:
	_autosave_in = -1.0
	DirAccess.remove_absolute(AUTOSAVE_PATH)
	DirAccess.remove_absolute(AUTOSAVE_NOTE)


## If work was left unsaved last time, brings it back.
func _recover_autosave() -> bool:
	if not FileAccess.file_exists(AUTOSAVE_PATH) or not FileAccess.file_exists(AUTOSAVE_NOTE):
		return false
	var recovered := LocaleFile.read(AUTOSAVE_PATH)
	if recovered.is_empty():
		_clear_autosave()
		return false
	_use_locale(recovered, FileAccess.get_file_as_string(AUTOSAVE_NOTE))
	dirty = true
	_update_title()
	set_status("Brought back your unsaved work. Save to keep it.")
	return true


# --- building ---

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

	var top := HBoxContainer.new()
	root.add_child(top)
	_button(top, "Menu", _back_to_menu)
	_button(top, "New", func(): _use_locale(LocaleDefs.new_locale(), ""))
	_button(top, "Open", func(): _browse("Open overworld", OPEN_FILTERS, FileDialog.FILE_MODE_OPEN_FILE, _open_file, LocaleFile.folder()))
	_button(top, "Save", save)
	_button(top, "Save As", func(): _browse("Save overworld as", OPEN_FILTERS, FileDialog.FILE_MODE_SAVE_FILE, _save_as, LocaleFile.folder()))
	title_label.custom_minimum_size.x = 200
	title_label.clip_text = true
	top.add_child(title_label)
	top.add_child(VSeparator.new())
	_invisible_toggle = _toggle(top, "Invisible things", show_invisible, func(on):
		show_invisible = on
		viewport.refresh(), "[H] Show triggers, warps, spawns, what's connected to what and where the camera stops")
	_toggle(top, "Grid", show_grid, func(on):
		show_grid = on
		viewport.refresh())
	_map_toggle = _toggle(top, "Map", map_mode, func(on): set_map_mode(on), "[M] See and arrange every room")
	top.add_child(VSeparator.new())
	_button(top, "Test", _test_play, "Save and play from this room")
	_button(top, "Help", _show_help)

	var middle := HSplitContainer.new()
	middle.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(middle)
	var left := _build_left()
	middle.add_child(left)
	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = SIZE_EXPAND_FILL
	middle.add_child(right_split)
	viewport = LocaleViewport.new()
	viewport.editor = self
	viewport.size_flags_horizontal = SIZE_EXPAND_FILL
	right_split.add_child(viewport)
	side_tabs.custom_minimum_size.x = 420
	right_split.add_child(side_tabs)
	for tab in [["selection", "Selection"], ["room", "Room"], ["rules", "Rules"], ["party", "Party"], ["cutscenes", "Cutscenes"], ["items", "Items"]]:
		_add_panel(tab[0], tab[1])

	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	root.add_child(status_label)

	add_child(file_dialog)
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.file_selected.connect(func(picked): _file_callback.call(picked))


func _build_left() -> Control:
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 210
	_heading(left, "Rooms")
	rooms_list.custom_minimum_size.y = 170
	rooms_list.size_flags_vertical = SIZE_EXPAND_FILL
	rooms_list.item_selected.connect(func(i): open_room(locale["rooms"][i]))
	left.add_child(rooms_list)
	var room_row := HBoxContainer.new()
	left.add_child(room_row)
	_button(room_row, "+", add_room, "New room")
	_button(room_row, "Copy", duplicate_room, "Copy this room")
	_button(room_row, "Delete", delete_room)
	_heading(left, "Layers")
	layers_list.custom_minimum_size.y = 130
	layers_list.item_selected.connect(func(i):
		layer = room["layers"][i]
		selected = null
		if tool == "select":
			set_tool("paint")
		_refresh_panels())
	left.add_child(layers_list)
	var layer_row := HBoxContainer.new()
	left.add_child(layer_row)
	_button(layer_row, "+", add_layer, "New layer")
	_button(layer_row, "^", func(): _move_layer(-1), "Draw under the layers above it")
	_button(layer_row, "v", func(): _move_layer(1))
	_button(layer_row, "Delete", delete_layer)
	_heading(left, "Place")
	for type in LocaleDefs.OBJECT_TYPES:
		var def: Dictionary = LocaleDefs.OBJECT_TYPES[type]
		var b := _button(left, str(def["label"]), func(): start_placing(type))
		b.add_theme_color_override("font_color", def["color"])
		b.add_theme_color_override("font_hover_color", def["color"])
		# Lit up with its own colour while it's the one being placed
		var lit := StyleBoxFlat.new()
		lit.bg_color = Color(def["color"], 0.35)
		lit.border_color = def["color"]
		lit.set_border_width_all(2)
		b.add_theme_stylebox_override("pressed", lit)
		b.add_theme_stylebox_override("hover_pressed", lit)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.toggle_mode = true
		place_buttons[type] = b
	return left


func _heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	parent.add_child(label)


func _add_panel(id: String, tab_name: String) -> void:
	var panel := Panels.new()
	panel.editor = self
	panel.mode = id
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(panel)
	side_tabs.add_child(scroll)
	panels[id] = panel


func _button(parent: Control, text: String, action: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _toggle(parent: Control, text: String, on: bool, action: Callable, tip := "") -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.button_pressed = on
	b.focus_mode = FOCUS_NONE
	b.tooltip_text = tip
	b.toggled.connect(action)
	parent.add_child(b)
	return b


# --- what's open ---

func _use_locale(new_locale: Dictionary, new_path: String) -> void:
	locale = new_locale
	path = new_path
	last_path = new_path
	dirty = false
	_undo.clear()
	_redo.clear()
	selected = null
	placing = ""
	var first: Variant = LocaleDefs.find_room(locale, int(locale["start_room"]))
	open_room(first if first != null else locale["rooms"][0])
	viewport.frame_room()
	set_tool("paint")
	_update_title()


func open_room(new_room: Dictionary) -> void:
	room = new_room
	selected = null
	layer = room["layers"][0] if not room["layers"].is_empty() else null
	viewport.show_room()
	viewport.frame_room()
	refresh_lists()
	_refresh_panels()


func refresh_lists() -> void:
	rooms_list.clear()
	for i in locale["rooms"].size():
		var entry: Dictionary = locale["rooms"][i]
		var mark := " (start)" if entry["id"] == locale["start_room"] else ""
		rooms_list.add_item(str(entry["name"]) + mark)
		if entry == room:
			rooms_list.select(i)
	layers_list.clear()
	for i in room["layers"].size():
		var entry: Dictionary = room["layers"][i]
		var tags := ("  solid" if entry["solid"] else "") + ("  above" if entry["above"] else "")
		layers_list.add_item(str(entry["name"]) + tags)
		if entry == layer:
			layers_list.select(i)


func _refresh_panels() -> void:
	for id in panels:
		panels[id].refresh()


func set_tool(id: String) -> void:
	tool = id
	placing = ""
	if viewport.wheel.current_id() != id:
		viewport.wheel.turn_to(id)
	viewport.refresh()


func set_map_mode(on: bool) -> void:
	map_mode = on
	if _map_toggle.button_pressed != on:
		_map_toggle.set_pressed_no_signal(on)
	if on:
		selected = null
		var centre := Vector2(room["map_x"], room["map_y"])
		viewport.pan = centre
		viewport.zoom = 1.0
	else:
		viewport.frame_room()
		viewport.zoom = maxf(viewport.zoom, 2.0)
	viewport.refresh()
	_refresh_panels()


func set_status(text: String) -> void:
	status_label.text = text


func _update_title() -> void:
	title_label.text = "%s%s" % [path.get_file() if path != "" else "(not saved yet)", " *" if dirty else ""]


# --- editing ---

func push_undo() -> void:
	_undo.append(JSON.stringify(locale))
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()


func undo() -> void:
	if _undo.is_empty():
		set_status("Nothing to undo")
		return
	_redo.append(JSON.stringify(locale))
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		set_status("Nothing to redo")
		return
	_undo.append(JSON.stringify(locale))
	_restore(_redo.pop_back())


func _restore(text: String) -> void:
	var room_id: int = room["id"]
	var layer_id: int = layer["id"] if layer != null else -1
	var selected_id: int = selected["id"] if selected != null else -1
	locale = LocaleDefs.clean(JSON.parse_string(text))
	var back: Variant = LocaleDefs.find_room(locale, room_id)
	room = back if back != null else locale["rooms"][0]
	layer = null
	for entry in room["layers"]:
		if entry["id"] == layer_id:
			layer = entry
	if layer == null and not room["layers"].is_empty():
		layer = room["layers"][0]
	selected = LocaleDefs.find_object(room, selected_id)
	_last_edit_key = ""
	viewport.show_room()
	changed()


## Call after any change.
func changed(refresh_panels := true) -> void:
	dirty = true
	viewport.refresh()
	refresh_lists()
	if refresh_panels:
		_refresh_panels()
	_update_title()
	_autosave_in = AUTOSAVE_SECONDS


## Changes one setting. Quick repeated changes to the same one share an undo step.
func set_param(target: Dictionary, key: String, value: Variant, in_params: bool) -> void:
	var edit_key := "%s/%s" % [target.get("id", target.get("name", "rules")), key]
	var now := Time.get_ticks_msec()
	if edit_key != _last_edit_key or now - _last_edit_time > 800:
		push_undo()
	_last_edit_key = edit_key
	_last_edit_time = now
	if in_params:
		target["params"][key] = value
	else:
		target[key] = value
	dirty = true
	_autosave_in = AUTOSAVE_SECONDS
	_update_title()
	viewport.refresh()


func select(obj: Variant) -> void:
	selected = obj
	if obj != null:
		side_tabs.current_tab = 0
	panels["selection"].refresh()
	viewport.refresh()


func start_placing(type: String) -> void:
	if map_mode:
		set_map_mode(false)
	if viewport._drawing_path != null:
		viewport.finish_path()
	placing = type
	selected = null
	viewport.refresh()
	panels["selection"].refresh()


func place_object(type: String, at: Vector2) -> void:
	push_undo()
	var obj := LocaleDefs.new_object(locale, type, at.x, at.y)
	room["objects"].append(obj)
	placing = ""
	set_tool("select")
	selected = obj
	side_tabs.current_tab = 0
	changed()


## Picks a layer, as the eyedropper does.
func pick_layer(new_layer: Dictionary) -> void:
	layer = new_layer
	selected = null
	set_tool("paint")
	refresh_lists()
	_refresh_panels()
	set_status("Drawing on %s." % new_layer["name"])


func keep_drawing_path(path_object: Dictionary) -> void:
	placing = ""
	set_tool("select")
	viewport.start_drawing_path(path_object)


func delete_selected() -> void:
	if selected == null:
		return
	push_undo()
	room["objects"].erase(selected)
	selected = null
	changed()


func duplicate_selected() -> void:
	if selected == null:
		return
	push_undo()
	var copy: Dictionary = selected.duplicate(true)
	copy["id"] = LocaleDefs.take_id(locale)
	copy["x"] = float(copy["x"]) + float(locale["rules"]["tile_size"])
	room["objects"].append(copy)
	selected = copy
	changed()


# --- rooms and layers ---

func add_room() -> void:
	push_undo()
	var made := _new_room_beside("Room %d" % (locale["rooms"].size() + 1))
	open_room(made)
	changed()


## A new room on the map, to the right of everything else.
func _new_room_beside(room_name: String) -> Dictionary:
	var made := LocaleDefs.new_room(locale, room_name)
	var right := 0.0
	var top := 0.0
	for entry in locale["rooms"]:
		var box: Rect2 = viewport._room_map_rect(entry)
		if box.end.x > right:
			right = box.end.x
			top = box.position.y
	made["map_x"] = right + 40.0
	made["map_y"] = top
	# Starts with the same art as the room you're in
	if not room.is_empty():
		for new_layer in made["layers"]:
			for existing in room["layers"]:
				if existing["name"] == new_layer["name"]:
					for key in ["sheet", "plain_tile", "edge_color"]:
						new_layer[key] = existing[key]
	locale["rooms"].append(made)
	return made


func duplicate_room() -> void:
	push_undo()
	var copy: Dictionary = room.duplicate(true)
	copy["id"] = LocaleDefs.take_id(locale)
	copy["name"] = "%s copy" % room["name"]
	copy["map_y"] = float(copy["map_y"]) + 60.0
	for entry in copy["layers"]:
		entry["id"] = LocaleDefs.take_id(locale)
	for entry in copy["objects"]:
		entry["id"] = LocaleDefs.take_id(locale)
	locale["rooms"].append(copy)
	open_room(copy)
	changed()


func delete_room() -> void:
	if locale["rooms"].size() <= 1:
		set_status("An overworld needs at least one room.")
		return
	push_undo()
	var gone_id: int = room["id"]
	locale["rooms"].erase(room)
	if locale["start_room"] == gone_id:
		locale["start_room"] = locale["rooms"][0]["id"]
		locale["start_spawn"] = -1
	open_room(locale["rooms"][0])
	changed()


func set_start_here() -> void:
	push_undo()
	locale["start_room"] = room["id"]
	locale["start_spawn"] = -1
	for obj in room["objects"]:
		if obj["type"] == "spawn":
			locale["start_spawn"] = obj["id"]
			if obj == selected:
				break
	changed()
	set_status("The game starts in %s." % room["name"])


func add_layer() -> void:
	push_undo()
	var made := LocaleDefs.new_layer(locale, "Layer %d" % (room["layers"].size() + 1))
	room["layers"].append(made)
	layer = made
	viewport.show_room()
	changed()


func delete_layer() -> void:
	if layer == null or room["layers"].size() <= 1:
		set_status("A room needs at least one layer.")
		return
	push_undo()
	room["layers"].erase(layer)
	layer = room["layers"][0]
	viewport.show_room()
	changed()


func _move_layer(by: int) -> void:
	if layer == null:
		return
	var at: int = room["layers"].find(layer)
	var to: int = at + by
	if to < 0 or to >= room["layers"].size():
		return
	push_undo()
	room["layers"].remove_at(at)
	room["layers"].insert(to, layer)
	viewport.show_room()
	changed()


# --- warps ---

## Makes sure a warp lands somewhere, and adds a warp back with its own arrival spot.
func make_two_way(warp: Dictionary) -> void:
	var target: Variant = LocaleDefs.find_room(locale, int(warp["room"]))
	if target == null:
		set_status("Pick which room it leads to first.")
		return
	push_undo()
	_link(warp, target)
	changed()
	set_status("Linked %s and %s both ways." % [room["name"], target["name"]])


func warp_to_new_room(warp: Dictionary) -> void:
	push_undo()
	var made := _new_room_beside("Room %d" % (locale["rooms"].size() + 1))
	warp["room"] = made["id"]
	_link(warp, made)
	changed()
	set_status("Made %s and linked it both ways. Use Go To That Room to draw it." % made["name"])


func _link(warp: Dictionary, target: Dictionary) -> void:
	var tile := float(locale["rules"]["tile_size"])
	var arrive: Variant = LocaleDefs.find_object(target, int(warp["spawn"]))
	if arrive == null:
		arrive = LocaleDefs.new_object(locale, "spawn", tile / 2.0, tile / 2.0)
		arrive["name"] = "From %s" % room["name"]
		target["objects"].append(arrive)
		warp["spawn"] = arrive["id"]
	# Back here: you land just outside the warp you came through
	var here := LocaleDefs.new_object(locale, "spawn", float(warp["x"]) + float(warp["w"]) / 2.0, float(warp["y"]) - tile)
	here["name"] = "From %s" % target["name"]
	here["facing"] = "up"
	room["objects"].append(here)
	var back := LocaleDefs.new_object(locale, "warp", float(arrive["x"]) - tile / 2.0, float(arrive["y"]) + tile)
	back["name"] = "To %s" % room["name"]
	back["w"] = tile
	back["h"] = tile
	back["room"] = room["id"]
	back["spawn"] = here["id"]
	target["objects"].append(back)


func follow_warp(warp: Dictionary) -> void:
	var target: Variant = LocaleDefs.find_room(locale, int(warp["room"]))
	if target != null:
		open_room(target)


# --- files ---

func _browse(title_text: String, filters: Array, file_mode: FileDialog.FileMode, on_pick: Callable, folder := "") -> void:
	file_dialog.title = title_text
	file_dialog.filters = PackedStringArray(filters)
	file_dialog.file_mode = file_mode
	if folder != "":
		file_dialog.current_dir = folder
	_file_callback = on_pick
	file_dialog.popup_centered()


## For the Browse buttons. Everything's packed into the .lcal when it's saved.
func browse_file(kind: String, on_pick: Callable, _for_new_scrap := false) -> void:
	_browse("Pick a file", BROWSE_KINDS[kind], FileDialog.FILE_MODE_OPEN_FILE, func(picked):
		if kind != "video":
			on_pick.call(ProjectSettings.localize_path(picked))
			return
		set_status("Converting %s..." % picked.get_file())
		VideoImport.convert_video(picked, func(result):
			if result["error"] != "":
				set_status(result["error"])
				return
			set_status("Video ready: %s" % result["path"].get_file())
			on_pick.call(result["path"])))


func save() -> void:
	if path == "":
		path = LocaleFile.unused_path("My Overworld")
		last_path = path
	var err := LocaleFile.write(locale, path)
	if err != OK:
		set_status("Couldn't save %s (error %d)" % [path, err])
		return
	dirty = false
	_clear_autosave()
	_update_title()
	if LocaleFile.last_missing.is_empty():
		set_status("Saved %s" % path)
	else:
		set_status("Saved %s, but couldn't find: %s" % [path, ", ".join(LocaleFile.last_missing.map(func(m): return m.get_file()))])


func _save_as(picked: String) -> void:
	if picked.get_extension() == "":
		picked += "." + LocaleFile.EXTENSION
	path = picked
	last_path = picked
	save()


func _open_file(picked: String) -> void:
	var loaded := LocaleFile.read(picked)
	if loaded.is_empty():
		set_status(LocaleFile.last_error)
		return
	_use_locale(loaded, picked)
	set_status("Opened %s" % picked)


func _test_play() -> void:
	save()
	if path == "" or dirty:
		return
	Overworld.return_scene = "res://editor/locale_editor.tscn"
	Overworld.test_room = room["id"]
	Overworld.test_spawn = _test_spot()
	get_tree().change_scene_to_file(Overworld.play(path))


## Starts from the selected spawn, then the game's start, then any spawn, then the middle.
func _test_spot() -> Vector2:
	if selected != null and selected["type"] == "spawn":
		return Vector2(selected["x"], selected["y"])
	var start: Variant = LocaleDefs.find_object(room, int(locale["start_spawn"]))
	if start != null:
		return Vector2(start["x"], start["y"])
	for obj in room["objects"]:
		if obj["type"] == "spawn":
			return Vector2(obj["x"], obj["y"])
	var drawn: Rect2 = viewport.view.drawn_rect()
	var tile := float(locale["rules"]["tile_size"])
	return ((drawn.get_center() / tile).floor() + Vector2(0.5, 0.5)) * tile


func _back_to_menu() -> void:
	if dirty:
		var dialog := ConfirmationDialog.new()
		dialog.title = "Unsaved changes"
		dialog.dialog_text = "Save before going back to the menu?"
		dialog.ok_button_text = "Save"
		dialog.add_button("Don't save", true, "discard")
		dialog.confirmed.connect(func():
			save()
			_leave())
		dialog.custom_action.connect(func(_action):
			_clear_autosave()
			_leave())
		add_child(dialog)
		dialog.popup_centered()
		return
	_leave()


func _leave() -> void:
	MainMenu.page = MainMenu.Page.LOCALE
	get_tree().change_scene_to_file("res://menu.tscn")


func _show_help() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Locale-Inator help"
	dialog.dialog_text = HELP
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	var key: Key = event.keycode
	if event.ctrl_pressed:
		match key:
			KEY_Z: undo()
			KEY_Y: redo()
			KEY_S: save()
			KEY_D: duplicate_selected()
		return
	match key:
		KEY_V, KEY_B, KEY_E, KEY_I, KEY_G, KEY_U, KEY_C:
			if not map_mode:
				set_tool(TOOL_KEYS[key])
		KEY_H: _invisible_toggle.button_pressed = not show_invisible
		KEY_M: set_map_mode(not map_mode)
		KEY_DELETE: delete_selected()
		KEY_ESCAPE:
			if viewport._drawing_path != null:
				viewport.finish_path()
			placing = ""
			select(null)
		KEY_ENTER, KEY_KP_ENTER:
			if viewport._drawing_path != null:
				viewport.finish_path()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var at: int = key - KEY_1
			if at < room["layers"].size():
				layer = room["layers"][at]
				selected = null
				if tool == "select":
					set_tool("paint")
				refresh_lists()
				_refresh_panels()
