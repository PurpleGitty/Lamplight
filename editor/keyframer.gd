extends Window
## The Keyframer: builds a character out of pieces (legs, body, arm, hair, a guitar...)
## and animates them with keys on a timeline measured in beats, so everything moves to
## the music at whatever tempo the fight's song has. Pieces only turn and move (and
## change frame), never stretch, so the art stays pixel for pixel.
##   Left: the pieces, top to bottom in drawing order, and the chosen piece's settings.
##   Middle: the character at the playhead. Drag pieces to move or turn them; that sets
##     a key at the playhead (or, with Rest Pose ticked, changes where they sit normally).
##   Bottom: the timeline. Each piece has a row; the chosen piece opens out into a row
##     per property. Drag keys along it, double-click a row to add one.
## "idle" loops all fight. Other animations play once, from a Play Animation node (or
## "attack" when a party member uses FIGHT).

const FONT = preload("res://fonts/PixelOperator.ttf")
const SNAPS := [["1 beat", 1.0], ["1/2", 0.5], ["1/4", 0.25], ["1/8", 0.125], ["1/16", 0.0625], ["free", 0.0]]
const PROPERTY_NAMES := {"rotation": "turn", "x": "x", "y": "y", "frame": "frame"}
const KEY_COLOR := Color(1.0, 0.85, 0.3)
const CHOSEN_COLOR := Color(0.4, 0.9, 1.0)
const HELP := "[LMB] PICK PIECE   [LMB DRAG] MOVE   [RMB DRAG] TURN   [SHIFT+LMB DRAG] MOVE PIVOT (rest pose)   [Q] [E] FRAME   [WHEEL] ZOOM   [MMB DRAG] PAN   [SPACE] PLAY   [DEL] DELETE KEY   [CTRL+Z] UNDO"

var editor
## The character being edited (found again by place after an undo swaps the chart).
var data: Dictionary
var anim: Dictionary
var selected_id := -1
var playhead := 0.0
var playing := false
var snap := 0.25
var rest_pose := false
var selected_key: Dictionary = {} # {"id", "property", "key"}

var _is_party := false
var _index := 0
var _chart_seen: Dictionary
var _filling := false
var _last_undo_key := ""
var _last_undo_time := 0

var _anim_picker := OptionButton.new()
var _anim_name := LineEdit.new()
var _length := SpinBox.new()
var _loop := CheckBox.new()
var _play := Button.new()
var _snap_picker := OptionButton.new()
var _rest := CheckBox.new()
var _pieces := ItemList.new()
var _piece_box := VBoxContainer.new()
var _stage := Stage.new()
var _lanes := Lanes.new()
var _key_bar := HBoxContainer.new()
var _status := Label.new()


func _init() -> void:
	title = "Keyframer"
	size = Vector2i(1360, 860)
	min_size = Vector2i(900, 600)
	visible = false
	close_requested.connect(hide)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)

	# Animation bar
	var bar := HBoxContainer.new()
	root.add_child(bar)
	_label(bar, "Animation:")
	_anim_picker.focus_mode = Control.FOCUS_NONE
	_anim_picker.item_selected.connect(func(i): _pick_animation(_anim_picker.get_item_text(i)))
	bar.add_child(_anim_picker)
	_button(bar, "New", _new_animation, "A new animation, played once when something asks for it by name")
	_anim_name.custom_minimum_size.x = 140
	_anim_name.placeholder_text = "name"
	_anim_name.tooltip_text = "Its name. \"idle\" loops all fight; \"attack\" plays when a party member uses FIGHT"
	_anim_name.text_submitted.connect(func(_t): _rename_animation())
	_anim_name.focus_exited.connect(_rename_animation)
	bar.add_child(_anim_name)
	_button(bar, "Delete", _delete_animation, "Delete this animation")
	_label(bar, "   Beats:")
	_length.min_value = 0.25
	_length.max_value = 256.0
	_length.step = 0.25
	_length.value_changed.connect(func(v):
		if _filling or anim.is_empty():
			return
		_undo_point("length")
		anim["beats"] = v
		_changed())
	bar.add_child(_length)
	_loop.text = "Loop"
	_loop.focus_mode = Control.FOCUS_NONE
	_loop.toggled.connect(func(on):
		if _filling or anim.is_empty():
			return
		_undo_point("loop")
		anim["loop"] = on
		_changed())
	bar.add_child(_loop)
	_play.text = "Play"
	_play.focus_mode = Control.FOCUS_NONE
	_play.custom_minimum_size.x = 80
	_play.pressed.connect(toggle_play)
	bar.add_child(_play)
	_label(bar, "   Snap:")
	_snap_picker.focus_mode = Control.FOCUS_NONE
	for s in SNAPS:
		_snap_picker.add_item(s[0])
	_snap_picker.select(2)
	_snap_picker.item_selected.connect(func(i): snap = SNAPS[i][1])
	bar.add_child(_snap_picker)
	_rest.text = "Rest pose"
	_rest.focus_mode = Control.FOCUS_NONE
	_rest.tooltip_text = "Edit where pieces sit when nothing's moving them, instead of setting keys"
	_rest.toggled.connect(func(on):
		rest_pose = on
		_stage.queue_redraw())
	bar.add_child(_rest)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_button(bar, "Done", hide, "")

	# Pieces | stage
	var middle := HSplitContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(middle)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 330
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left)
	_label(left, "Pieces (top of the list is drawn first):")
	_pieces.custom_minimum_size.y = 170
	_pieces.focus_mode = Control.FOCUS_NONE
	_pieces.item_selected.connect(func(i): _select_piece(anim_piece_ids()[i]))
	left.add_child(_pieces)
	var piece_buttons := HFlowContainer.new()
	left.add_child(piece_buttons)
	_button(piece_buttons, "Add piece", _add_piece, "A piece from an image (a sprite sheet with its frames side by side)")
	_button(piece_buttons, "Add joint", _add_joint, "An invisible piece that carries others, to turn a group of them together")
	_button(piece_buttons, "Up", func(): _move_piece(-1), "Draw it sooner (behind more)")
	_button(piece_buttons, "Down", func(): _move_piece(1), "Draw it later (in front of more)")
	_button(piece_buttons, "Remove", _remove_piece, "")
	_button(piece_buttons, "Crop all", _crop_all, "Crop every piece's frames to the art in them, so selecting one only outlines that piece. Nothing moves")
	left.add_child(_piece_box)
	_stage.window = self
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(_stage)

	# The key being edited, then the timeline
	root.add_child(_key_bar)
	_lanes.window = self
	_lanes.custom_minimum_size.y = 230
	root.add_child(_lanes)
	_status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_status.text = HELP
	_status.clip_text = true
	_status.custom_minimum_size.x = 100
	root.add_child(_status)


## Opens it on a character from the chart.
func open(character: Dictionary) -> void:
	_is_party = editor.chart["party"].has(character)
	var list: Array = editor.chart["party"] if _is_party else editor.chart["enemies"]
	_index = list.find(character)
	_chart_seen = editor.chart
	data = character
	if not character.has("rig"):
		character["rig"] = Rig.new_rig()
	Rig.fill(character["rig"])
	title = "Keyframer - %s" % character["name"]
	_pick_animation(Rig.IDLE)
	var pieces: Array = character["rig"]["pieces"]
	selected_id = pieces[0]["id"] if not pieces.is_empty() else -1
	playhead = 0.0
	playing = false
	_refresh_all()
	popup_centered()


func rig() -> Dictionary:
	return data["rig"]


func anim_piece_ids() -> Array:
	return rig()["pieces"].map(func(p): return p["id"])


func selected_piece() -> Dictionary:
	return Rig.find_piece(rig(), selected_id) if not data.is_empty() else {}


func bpm() -> float:
	return float(editor.chart["bpm"])


func _process(delta: float) -> void:
	if not visible or data.is_empty():
		return
	# An undo in the editor swaps the whole chart: find the character again
	if not is_same(editor.chart, _chart_seen):
		_chart_seen = editor.chart
		var list: Array = editor.chart["party" if _is_party else "enemies"]
		if _index >= list.size():
			hide()
			return
		data = list[_index]
		Rig.fill(data["rig"])
		var name_now: String = anim.get("name", Rig.IDLE)
		anim = {}
		_pick_animation(name_now)
		selected_key = {}
		_refresh_all()
	if playing:
		playhead += delta * bpm() / 60.0
		var length := float(anim["beats"])
		if playhead >= length:
			if anim["loop"]:
				playhead = fmod(playhead, length)
			else:
				playhead = length
				playing = false
				_play.text = "Play"
	_stage.queue_redraw()
	_lanes.queue_redraw()


func toggle_play() -> void:
	playing = not playing
	if playing and not anim.get("loop", true) and playhead >= float(anim["beats"]):
		playhead = 0.0
	_play.text = "Pause" if playing else "Play"


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var handled := true
	if event.ctrl_pressed and event.keycode == KEY_Z:
		editor.undo()
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		editor.redo()
	else:
		match event.keycode:
			KEY_SPACE:
				toggle_play()
			KEY_DELETE, KEY_BACKSPACE:
				_delete_key()
			KEY_Q:
				_step_frame(-1)
			KEY_E:
				_step_frame(1)
			KEY_HOME:
				playhead = 0.0
			_:
				handled = false
	if handled:
		set_input_as_handled()


# --- values ---

## A property of a piece as it is at the playhead (or at rest, editing the rest pose).
func value_now(piece: Dictionary, property: String) -> float:
	if rest_pose:
		return float(piece[property])
	var keys := Rig.keys_of(anim, piece["id"], property)
	return Rig.value_at(keys, playhead, float(anim["beats"]), anim["loop"], float(piece[property]))


## Changes a property: a key at the playhead, or the rest pose.
func set_value(piece: Dictionary, property: String, value: float) -> void:
	if rest_pose:
		piece[property] = value
	else:
		Rig.set_key(anim, piece["id"], property, snapped_beat(playhead), value)
	_changed()


func snapped_beat(b: float) -> float:
	return clampf(snappedf(b, snap) if snap > 0.0 else b, 0.0, float(anim["beats"]))


func pose_now() -> Dictionary:
	if rest_pose:
		return Rig.pose(rig(), {}, 0.0)
	return Rig.pose(rig(), anim, playhead)


## Makes an undo point, once per burst of the same kind of change.
func _undo_point(what: String) -> void:
	var now := Time.get_ticks_msec()
	if what != _last_undo_key or now - _last_undo_time > 800:
		editor.push_undo()
		_chart_seen = editor.chart
	_last_undo_key = what
	_last_undo_time = now


func _changed() -> void:
	editor.changed(false)
	_chart_seen = editor.chart
	_stage.queue_redraw()
	_lanes.queue_redraw()
	_refresh_key_bar()


func _step_frame(step: int) -> void:
	var piece := selected_piece()
	if piece.is_empty():
		return
	_undo_point("frame %d" % piece["id"])
	var frames: int = maxi(piece["hframes"], 1)
	set_value(piece, "frame", posmod(roundi(value_now(piece, "frame")) + step, frames))


# --- animations ---

func _pick_animation(anim_name: String) -> void:
	var found := Rig.find_animation(rig(), anim_name)
	if found.is_empty():
		found = Rig.find_animation(rig(), Rig.IDLE)
	if found.is_empty():
		found = Rig.new_animation(Rig.IDLE)
		rig()["animations"].push_front(found)
	anim = found
	playhead = minf(playhead, float(anim["beats"]))
	selected_key = {}
	_refresh_animation_bar()
	_refresh_key_bar()


func _new_animation() -> void:
	editor.push_undo()
	var number := 1
	while not Rig.find_animation(rig(), "animation %d" % number).is_empty():
		number += 1
	var made := Rig.new_animation("animation %d" % number)
	rig()["animations"].append(made)
	_changed()
	_pick_animation(made["name"])


func _rename_animation() -> void:
	if anim.is_empty() or _filling:
		return
	var wanted := _anim_name.text.strip_edges()
	if wanted == anim["name"]:
		return
	if anim["name"] == Rig.IDLE:
		_status.text = "\"idle\" keeps its name: it's the one that loops all fight."
		_anim_name.text = Rig.IDLE
		return
	if wanted == "" or not Rig.find_animation(rig(), wanted).is_empty():
		_status.text = "Pick a name no other animation has."
		_anim_name.text = anim["name"]
		return
	editor.push_undo()
	anim["name"] = wanted
	_changed()
	_refresh_animation_bar()


func _delete_animation() -> void:
	if anim.is_empty() or anim["name"] == Rig.IDLE:
		_status.text = "\"idle\" can't be deleted: it's the one that loops all fight."
		return
	editor.push_undo()
	rig()["animations"].erase(anim)
	_changed()
	_pick_animation(Rig.IDLE)


func _refresh_animation_bar() -> void:
	_filling = true
	_anim_picker.clear()
	var animations: Array = rig()["animations"]
	for i in animations.size():
		_anim_picker.add_item(animations[i]["name"])
		if animations[i] == anim:
			_anim_picker.select(i)
	_anim_name.text = anim["name"]
	_anim_name.editable = anim["name"] != Rig.IDLE
	_length.value = float(anim["beats"])
	_loop.button_pressed = anim["loop"]
	_filling = false


# --- pieces ---

func _select_piece(id: int) -> void:
	selected_id = id
	_refresh_pieces()
	_refresh_piece_box()
	_stage.queue_redraw()
	_lanes.queue_redraw()


func _add_piece() -> void:
	editor.browse_file("texture", func(path: String):
		editor.push_undo()
		var piece := Rig.new_piece(rig(), path.get_file().get_basename().capitalize(), path)
		var size := Rig.frame_size(piece)
		piece["pivot_x"] = roundf(size.x / 2.0)
		piece["pivot_y"] = size.y
		var chosen := selected_piece()
		if not chosen.is_empty():
			piece["parent"] = chosen["parent"]
		rig()["pieces"].append(piece)
		_changed()
		_select_piece(piece["id"])
		_refresh_all())


func _add_joint() -> void:
	editor.push_undo()
	var piece := Rig.new_piece(rig(), "Joint")
	var chosen := selected_piece()
	if not chosen.is_empty():
		piece["parent"] = chosen["id"]
	rig()["pieces"].append(piece)
	_changed()
	_select_piece(piece["id"])
	_refresh_all()


func _move_piece(step: int) -> void:
	var pieces: Array = rig()["pieces"]
	var piece := selected_piece()
	var at := pieces.find(piece)
	if at < 0 or at + step < 0 or at + step >= pieces.size():
		return
	editor.push_undo()
	pieces.remove_at(at)
	pieces.insert(at + step, piece)
	_changed()
	_refresh_pieces()


func _remove_piece() -> void:
	var piece := selected_piece()
	if piece.is_empty():
		return
	editor.push_undo()
	Rig.remove_piece(rig(), piece["id"])
	selected_key = {}
	var pieces: Array = rig()["pieces"]
	selected_id = pieces[0]["id"] if not pieces.is_empty() else -1
	_changed()
	_refresh_all()


func _refresh_all() -> void:
	_refresh_animation_bar()
	_refresh_pieces()
	_refresh_piece_box()
	_refresh_key_bar()


func _refresh_pieces() -> void:
	_pieces.clear()
	var pieces: Array = rig()["pieces"]
	for piece in pieces:
		var depth := 0
		var up: Dictionary = piece
		while up["parent"] != -1 and depth < 8:
			up = Rig.find_piece(rig(), up["parent"])
			if up.is_empty():
				break
			depth += 1
		var label: String = "  ".repeat(depth) + piece["name"] + ("" if piece["sprite"] != "" else "  (joint)")
		_pieces.add_item(label)
		_pieces.set_item_icon(_pieces.item_count - 1, null)
		if piece["id"] == selected_id:
			_pieces.select(_pieces.item_count - 1)


## The chosen piece's settings.
func _refresh_piece_box() -> void:
	for child in _piece_box.get_children():
		child.queue_free()
	var piece := selected_piece()
	if piece.is_empty():
		_label(_piece_box, "No pieces yet. Add a piece for each layer of the character, from the bottom up.")
		return
	_label(_piece_box, " ")
	var name_edit := LineEdit.new()
	name_edit.text = piece["name"]
	name_edit.text_changed.connect(func(t):
		_undo_point("name")
		piece["name"] = t
		editor.changed(false)
		_refresh_pieces())
	_row("name", name_edit)
	if piece["sprite"] != "":
		var sprite_row := HBoxContainer.new()
		var path := Label.new()
		path.text = piece["sprite"].get_file()
		path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		path.clip_text = true
		sprite_row.add_child(path)
		_button(sprite_row, "Browse", func():
			editor.browse_file("texture", func(chosen: String):
				editor.push_undo()
				piece["sprite"] = chosen
				piece["crops"] = []
				Rig.forget_textures()
				_changed()
				_refresh_piece_box()), "")
		_row("sprite", sprite_row)
		_number(piece, "hframes", "frames across", 1, 64, 1)
		var crop_row := HBoxContainer.new()
		var cropped := Label.new()
		cropped.text = "cropped to the art" if not piece["crops"].is_empty() else "whole frame"
		cropped.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crop_row.add_child(cropped)
		_button(crop_row, "Crop to art", func(): _crop([piece]), "Crop each of its frames to the art in it, so it's picked and outlined by just that. Nothing moves")
		_button(crop_row, "Uncrop", func():
			editor.push_undo()
			piece["crops"] = []
			_changed()
			_refresh_piece_box(), "")
		_row("crop", crop_row)
	var parent := OptionButton.new()
	parent.focus_mode = Control.FOCUS_NONE
	parent.add_item("(none)", -1)
	for other in rig()["pieces"]:
		if other["id"] != piece["id"] and not _is_inside(other, piece["id"]):
			parent.add_item(other["name"], other["id"])
	parent.select(parent.get_item_index(piece["parent"]) if parent.get_item_index(piece["parent"]) >= 0 else 0)
	parent.item_selected.connect(func(i):
		editor.push_undo()
		_reparent(piece, parent.get_item_id(i))
		_changed()
		_refresh_pieces())
	parent.tooltip_text = "What it's attached to: it moves and turns with that piece"
	_row("attached to", parent)
	_number(piece, "pivot_x", "pivot x", -2048, 2048, 1, "The pixel in its frame it turns around")
	_number(piece, "pivot_y", "pivot y", -2048, 2048, 1)
	_label(_piece_box, "Rest pose (where it sits when nothing's moving it):")
	_number(piece, "x", "x", -2048, 2048, 1, "Where its pivot is, from what it's attached to's pivot (or from where the character stands)")
	_number(piece, "y", "y", -2048, 2048, 1)
	_number(piece, "rotation", "turn", -3600, 3600, 0.5, "Degrees, clockwise")
	if piece["sprite"] != "":
		_number(piece, "frame", "frame", 0, 63, 1)


func _crop_all() -> void:
	_crop(rig()["pieces"].filter(func(p): return p["sprite"] != ""))


func _crop(pieces: Array) -> void:
	editor.push_undo()
	var failed := 0
	for piece in pieces:
		if not Rig.crop_to_art(piece):
			failed += 1
	_changed()
	_refresh_piece_box()
	_status.text = "Cropped." if failed == 0 else "Couldn't read %d of the images." % failed


func _is_inside(piece: Dictionary, ancestor: int) -> bool:
	var up := piece
	for depth in 64:
		if up["parent"] == -1:
			return false
		if up["parent"] == ancestor:
			return true
		up = Rig.find_piece(rig(), up["parent"])
		if up.is_empty():
			return false
	return true


## Attaches a piece to another, keeping it where it is on screen (at rest).
func _reparent(piece: Dictionary, new_parent: int) -> void:
	var placed := Rig.pose(rig(), {}, 0.0)
	var world: Transform2D = placed[piece["id"]]["xf"]
	var parent_world := Transform2D()
	if new_parent != -1:
		parent_world = placed[new_parent]["xf"]
	var local := parent_world.affine_inverse() * world
	piece["parent"] = new_parent
	piece["x"] = roundf(local.origin.x)
	piece["y"] = roundf(local.origin.y)
	piece["rotation"] = snappedf(rad_to_deg(local.get_rotation()), 0.5)


func _number(piece: Dictionary, key: String, label: String, low: float, high: float, step: float, tip := "") -> void:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value = float(piece[key])
	spin.tooltip_text = tip
	spin.value_changed.connect(func(v):
		_undo_point("%d %s" % [piece["id"], key])
		piece[key] = int(v) if key == "hframes" else v
		if key == "hframes":
			piece["frame"] = clampi(piece["frame"], 0, int(v) - 1)
			piece["crops"] = [] # the frames changed shape
		_changed())
	_row(label, spin)


func _row(label: String, field: Control) -> void:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size.x = 110
	name_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	row.add_child(name_label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	_piece_box.add_child(row)


# --- keys ---

func select_key(id: int, property: String, key: Dictionary) -> void:
	selected_key = {"id": id, "property": property, "key": key} if not key.is_empty() else {}
	if id != selected_id and id != -1:
		_select_piece(id)
	_refresh_key_bar()


func _delete_key() -> void:
	if selected_key.is_empty():
		return
	var keys := Rig.keys_of(anim, selected_key["id"], selected_key["property"])
	if not keys.has(selected_key["key"]):
		return
	editor.push_undo()
	keys.erase(selected_key["key"])
	selected_key = {}
	_changed()


## The chosen key's beat, value and ease.
func _refresh_key_bar() -> void:
	for child in _key_bar.get_children():
		child.queue_free()
	if selected_key.is_empty() or not Rig.keys_of(anim, selected_key["id"], selected_key["property"]).has(selected_key["key"]):
		selected_key = {}
		_label(_key_bar, "Double-click a row on the timeline to add a key there, or drag a piece at the playhead.")
		return
	var key: Dictionary = selected_key["key"]
	var piece := Rig.find_piece(rig(), selected_key["id"])
	_label(_key_bar, "Key:  %s's %s   at beat" % [piece.get("name", "?"), PROPERTY_NAMES[selected_key["property"]]])
	var at := SpinBox.new()
	at.min_value = 0.0
	at.max_value = float(anim["beats"])
	at.step = 0.0625
	at.value = key["beat"]
	at.value_changed.connect(func(v):
		_undo_point("key beat")
		key["beat"] = v
		Rig.sort_keys(anim)
		editor.changed(false)
		_lanes.queue_redraw())
	_key_bar.add_child(at)
	_label(_key_bar, "  value")
	var value := SpinBox.new()
	value.min_value = -4096
	value.max_value = 4096
	value.step = 1.0 if selected_key["property"] in ["x", "y", "frame"] else 0.5
	value.value = key["value"]
	value.value_changed.connect(func(v):
		_undo_point("key value")
		key["value"] = v
		editor.changed(false))
	_key_bar.add_child(value)
	_label(_key_bar, "  then")
	var ease := OptionButton.new()
	ease.focus_mode = Control.FOCUS_NONE
	for e in Rig.EASES:
		ease.add_item(e)
	ease.select(Rig.EASES.find(key["ease"]))
	ease.tooltip_text = "How it gets from this key to the next: smooth flows through the keys around it; hold jumps at the next key"
	ease.item_selected.connect(func(i):
		editor.push_undo()
		key["ease"] = Rig.EASES[i]
		editor.changed(false))
	_key_bar.add_child(ease)
	_button(_key_bar, "Delete key", _delete_key, "")


# --- helpers ---

func _label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	if parent is VBoxContainer:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 300 # a wrapping label needs a width, or it grows very tall
	parent.add_child(label)


func _button(parent: Control, text: String, action: Callable, tip: String) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)


## The character at the playhead, big, to drag pieces about.
class Stage extends Control:
	var window
	var zoom := 3.0
	var pan := Vector2.ZERO
	var _drag := "" # "", "move", "turn", "pivot", "pan"
	var _start_mouse := Vector2.ZERO
	var _start := {}

	func _ready() -> void:
		clip_contents = true
		focus_mode = FOCUS_CLICK
		texture_filter = TEXTURE_FILTER_NEAREST

	## Screen to the rig's own space: the character stands at the origin.
	func view() -> Transform2D:
		return Transform2D(0.0, Vector2(zoom, zoom), 0.0, (size * Vector2(0.5, 0.8) + pan).round())

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.07))
		if window.data.is_empty():
			return
		var xf := view()
		# Where they stand
		draw_line(Vector2(0, xf.origin.y), Vector2(size.x, xf.origin.y), Color(1, 1, 1, 0.12))
		draw_line(xf.origin + Vector2(0, -6), xf.origin + Vector2(0, 6), Color(1, 1, 1, 0.3))
		var placed: Dictionary = window.pose_now()
		Rig.draw(self, window.rig(), placed, xf)
		var piece: Dictionary = window.selected_piece()
		if piece.is_empty() or not placed.has(piece["id"]):
			return
		var piece_xf: Transform2D = xf * placed[piece["id"]]["xf"]
		if Rig.frame_size(piece) != Vector2.ZERO:
			var part := Rig.frame_rect(piece, placed[piece["id"]]["frame"])
			var box := part.size
			var corner := part.position - Vector2(piece["pivot_x"], piece["pivot_y"])
			var outline := PackedVector2Array()
			for c in [corner, corner + Vector2(box.x, 0), corner + box, corner + Vector2(0, box.y), corner]:
				outline.append(piece_xf * c)
			draw_polyline(outline, CHOSEN_COLOR, 1.0)
		var pivot := piece_xf.origin
		draw_circle(pivot, 4.0, Color.BLACK)
		draw_circle(pivot, 3.0, Color.YELLOW if window.rest_pose else CHOSEN_COLOR)
		var note := "REST POSE" if window.rest_pose else "beat %s" % snappedf(window.playhead, 0.01)
		draw_string(FONT, Vector2(8, 20), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))

	func _gui_input(event: InputEvent) -> void:
		if window.data.is_empty():
			return
		var xf := view()
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_zoom_at(event.position, 1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_zoom_at(event.position, -1)
			elif not event.pressed:
				_drag = ""
			elif event.button_index == MOUSE_BUTTON_MIDDLE:
				_begin("pan", event.position)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				var point: Vector2 = xf.affine_inverse() * event.position
				var placed: Dictionary = window.pose_now()
				var hit := Rig.piece_at(window.rig(), placed, point)
				if event.shift_pressed and window.rest_pose and not window.selected_piece().is_empty():
					_begin("pivot", event.position)
				elif not hit.is_empty():
					if hit["id"] != window.selected_id:
						window._select_piece(hit["id"])
					_begin("move", event.position)
			elif event.button_index == MOUSE_BUTTON_RIGHT and not window.selected_piece().is_empty():
				_begin("turn", event.position)
			accept_event()
		elif event is InputEventMouseMotion and _drag != "":
			_dragged(event.position)
			accept_event()

	func _zoom_at(at: Vector2, step: int) -> void:
		var before := view().affine_inverse() * at
		zoom = clampf(zoom + step, 1.0, 16.0)
		pan += at - view() * before
		queue_redraw()

	func _begin(kind: String, mouse: Vector2) -> void:
		_drag = kind
		_start_mouse = mouse
		_start = {"pan": pan}
		var piece: Dictionary = window.selected_piece()
		if kind == "pan" or piece.is_empty():
			return
		window.editor.push_undo()
		_start["x"] = window.value_now(piece, "x")
		_start["y"] = window.value_now(piece, "y")
		_start["rotation"] = window.value_now(piece, "rotation")
		_start["pivot"] = Vector2(piece["pivot_x"], piece["pivot_y"])
		var placed: Dictionary = window.pose_now()
		_start["piece_xf"] = view() * placed[piece["id"]]["xf"]
		var parent: Dictionary = Rig.find_piece(window.rig(), piece["parent"])
		_start["parent_xf"] = view() * (placed[parent["id"]]["xf"] if not parent.is_empty() else Transform2D())
		_start["children"] = {}
		for other in window.rig()["pieces"]:
			if other["parent"] == piece["id"]:
				_start["children"][other["id"]] = Vector2(other["x"], other["y"])

	func _dragged(mouse: Vector2) -> void:
		if _drag == "pan":
			pan = _start["pan"] + mouse - _start_mouse
			queue_redraw()
			return
		var piece: Dictionary = window.selected_piece()
		if piece.is_empty():
			return
		var parent_xf: Transform2D = _start["parent_xf"]
		match _drag:
			"move":
				# The mouse's movement, in what it's attached to's own pixels
				var moved: Vector2 = parent_xf.basis_xform_inv(mouse - _start_mouse)
				window.set_value(piece, "x", roundf(_start["x"] + moved.x))
				window.set_value(piece, "y", roundf(_start["y"] + moved.y))
			"turn":
				var pivot: Vector2 = _start["piece_xf"].origin
				var turned := (mouse - pivot).angle() - (_start_mouse - pivot).angle()
				var degrees := snappedf(_start["rotation"] + rad_to_deg(wrapf(turned, -PI, PI)), 0.5)
				window.set_value(piece, "rotation", degrees)
			"pivot":
				# The pivot moves under the mouse; the art stays where it is on screen
				var piece_xf: Transform2D = _start["piece_xf"]
				var shift: Vector2 = (piece_xf.basis_xform_inv(mouse - _start_mouse)).round()
				var pivot: Vector2 = _start["pivot"] + shift
				piece["pivot_x"] = pivot.x
				piece["pivot_y"] = pivot.y
				var along := shift.rotated(deg_to_rad(_start["rotation"]))
				piece["x"] = roundf(_start["x"] + along.x)
				piece["y"] = roundf(_start["y"] + along.y)
				for child_id in _start["children"]:
					var child: Dictionary = Rig.find_piece(window.rig(), child_id)
					child["x"] = _start["children"][child_id].x - shift.x
					child["y"] = _start["children"][child_id].y - shift.y
				window._changed()
				window._refresh_piece_box()
		queue_redraw()


## The timeline: a row per piece, opening out into a row per property for the chosen one.
class Lanes extends Control:
	const NAME_WIDTH := 150.0
	const ROW := 20.0
	const RULER := 20.0
	var window
	var _dragging: Dictionary = {} # the key being dragged
	var _scrubbing := false
	var _scroll := 0.0

	func _ready() -> void:
		clip_contents = true
		focus_mode = FOCUS_CLICK

	## Rows, top to bottom: [piece id, property or "" for the piece's own row].
	func rows() -> Array:
		var list := []
		for piece in window.rig()["pieces"]:
			list.append([piece["id"], ""])
			if piece["id"] == window.selected_id:
				for property in Rig.PROPERTIES:
					if property == "frame" and piece["sprite"] == "":
						continue
					list.append([piece["id"], property])
		return list

	func _beat_x(b: float) -> float:
		var length := maxf(float(window.anim["beats"]), 0.0001)
		return NAME_WIDTH + b / length * (size.x - NAME_WIDTH - 12.0)

	func _x_beat(x: float) -> float:
		var length := float(window.anim["beats"])
		return clampf((x - NAME_WIDTH) / maxf(size.x - NAME_WIDTH - 12.0, 1.0) * length, 0.0, length)

	func _row_y(i: int) -> float:
		return RULER + i * ROW - _scroll

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.07, 0.09))
		if window.data.is_empty() or window.anim.is_empty():
			return
		var length := float(window.anim["beats"])
		# Beat lines, with the snap's in between
		var step: float = window.snap if window.snap > 0.0 else 0.25
		var count := int(length / step) + 1
		for i in count:
			var b := i * step
			var x := _beat_x(b)
			var whole := is_equal_approx(b, roundf(b))
			draw_line(Vector2(x, RULER), Vector2(x, size.y), Color(1, 1, 1, 0.12 if whole else 0.04))
		var list := rows()
		for i in list.size():
			var y := _row_y(i)
			if y < RULER - ROW or y > size.y:
				continue
			var id: int = list[i][0]
			var property: String = list[i][1]
			var piece: Dictionary = Rig.find_piece(window.rig(), id)
			var chosen: bool = id == window.selected_id
			if property == "":
				draw_rect(Rect2(0, y, size.x, ROW), Color(1, 1, 1, 0.06 if chosen else 0.02))
				draw_string(FONT, Vector2(6, y + 15), piece["name"], HORIZONTAL_ALIGNMENT_LEFT, NAME_WIDTH - 10, 16, CHOSEN_COLOR if chosen else Color(0.85, 0.85, 0.9))
				for p in Rig.PROPERTIES:
					for key in Rig.keys_of(window.anim, id, p):
						_diamond(Vector2(_beat_x(key["beat"]), y + ROW / 2), 4.0, Color(KEY_COLOR, 0.5))
			else:
				draw_string(FONT, Vector2(22, y + 15), PROPERTY_NAMES[property], HORIZONTAL_ALIGNMENT_LEFT, NAME_WIDTH - 26, 14, Color(0.65, 0.65, 0.7))
				var keys := Rig.keys_of(window.anim, id, property)
				for k in keys.size():
					var key: Dictionary = keys[k]
					var at := Vector2(_beat_x(key["beat"]), y + ROW / 2)
					if k + 1 < keys.size() and key["ease"] != "hold":
						draw_line(at, Vector2(_beat_x(keys[k + 1]["beat"]), at.y), Color(KEY_COLOR, 0.25))
					var picked: bool = not window.selected_key.is_empty() and window.selected_key["key"] == key
					_diamond(at, 6.0, Color.WHITE if picked else KEY_COLOR)
		# The ruler and playhead over it all
		draw_rect(Rect2(0, 0, size.x, RULER), Color(0.12, 0.12, 0.15))
		draw_string(FONT, Vector2(6, 15), "beats", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.4))
		for whole in int(length) + 1:
			draw_string(FONT, Vector2(_beat_x(whole) + 3, 15), str(whole), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
		var head := _beat_x(window.playhead)
		draw_line(Vector2(head, 0), Vector2(head, size.y), Color(1.0, 0.35, 0.35), 2.0)

	func _diamond(at: Vector2, r: float, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), color)

	## [piece id, property, key] under the mouse, or an empty array.
	func _key_at(point: Vector2) -> Array:
		var list := rows()
		for i in list.size():
			var y := _row_y(i)
			if point.y < y or point.y >= y + ROW or list[i][1] == "":
				continue
			for key in Rig.keys_of(window.anim, list[i][0], list[i][1]):
				if absf(_beat_x(key["beat"]) - point.x) <= 7.0:
					return [list[i][0], list[i][1], key]
		return []

	func _row_at(point: Vector2) -> Array:
		var list := rows()
		var i := floori((point.y - RULER + _scroll) / ROW)
		return list[i] if point.y >= RULER and i >= 0 and i < list.size() else []

	func _gui_input(event: InputEvent) -> void:
		if window.data.is_empty():
			return
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
				var most := maxf(rows().size() * ROW - (size.y - RULER), 0.0)
				_scroll = clampf(_scroll + (-ROW if event.button_index == MOUSE_BUTTON_WHEEL_UP else ROW) * 2.0, 0.0, most)
				queue_redraw()
			elif not event.pressed:
				_dragging = {}
				_scrubbing = false
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				var hit := _key_at(event.position)
				if not hit.is_empty():
					window.select_key(hit[0], hit[1], hit[2])
					window._delete_key()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				var hit := _key_at(event.position)
				var row := _row_at(event.position)
				if event.double_click and not row.is_empty() and row[1] != "" and hit.is_empty():
					_add_key(row, event.position.x)
				elif not hit.is_empty():
					window.select_key(hit[0], hit[1], hit[2])
					window.editor.push_undo()
					_dragging = hit[2]
				elif event.position.x < NAME_WIDTH and not row.is_empty():
					window._select_piece(row[0])
				else:
					_scrubbing = true
					window.playhead = window.snapped_beat(_x_beat(event.position.x))
			accept_event()
		elif event is InputEventMouseMotion:
			if not _dragging.is_empty():
				_dragging["beat"] = window.snapped_beat(_x_beat(event.position.x))
				Rig.sort_keys(window.anim)
				window._changed()
			elif _scrubbing:
				window.playhead = window.snapped_beat(_x_beat(event.position.x))
			accept_event()

	func _add_key(row: Array, x: float) -> void:
		var piece: Dictionary = Rig.find_piece(window.rig(), row[0])
		var b: float = window.snapped_beat(_x_beat(x))
		window.editor.push_undo()
		var keys := Rig.keys_of(window.anim, row[0], row[1])
		var value := Rig.value_at(keys, b, float(window.anim["beats"]), window.anim["loop"], float(piece[row[1]]))
		Rig.set_key(window.anim, row[0], row[1], b, value)
		window.playhead = b
		for key in Rig.keys_of(window.anim, row[0], row[1]):
			if is_equal_approx(key["beat"], b):
				window.select_key(row[0], row[1], key)
		window._changed()
