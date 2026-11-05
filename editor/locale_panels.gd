extends "res://editor/inspector.gd"
## The Locale-Inator's panels on the right: whatever's selected, the room, the
## overworld's rules, the party, cutscenes and items. Built from the lists in LocaleDefs.

## Which tab this one is.
var mode := "selection"
var _cutscene_at := 0
static var _open_steps: Array = [] # steps showing their settings


func _ready() -> void:
	show_hints = true


func refresh() -> void:
	_clear()
	match mode:
		"selection": _show_selection()
		"room": _show_room()
		"rules": _show_rules()
		"party": _show_party()
		"cutscenes": _show_cutscenes()
		"items": _show_items()


func _rows(params: Array, target: Dictionary) -> void:
	for def in params:
		_any_row(def, target)


## One setting, including the kinds that pick from what's in the locale.
func _any_row(def: Dictionary, target: Dictionary) -> void:
	var key: String = def["name"]
	var on_change := func(value): _edit(target, key, value)
	match def["type"]:
		"room":
			_pick_row(def, _rooms_list(), int(target[key]), on_change, true)
		"spawn":
			_pick_row(def, _spawns_in(LocaleDefs.find_room(editor.locale, int(target.get("room", -1)))), int(target[key]), on_change)
		"object":
			_pick_row(def, _objects_here(), int(target[key]), on_change)
		"path":
			_pick_row(def, _paths_here(), int(target[key]), on_change)
		"item":
			_pick_row(def, editor.locale["items"].map(func(it): return [it["id"], it["name"]]), int(target[key]), on_change)
		"cutscene":
			_pick_row(def, editor.locale["cutscenes"].map(func(c): return [c["id"], c["name"]]), int(target[key]), on_change)
		"fight":
			_row(def.merged({"type": "fight"}), target[key], on_change)
		_:
			_row(def, target[key], on_change)


func _edit(target: Dictionary, key: String, value: Variant) -> void:
	editor.set_param(target, key, value, false)
	if key in ["sheet", "plain_tile", "edge_color", "above", "solid", "tile_size"]:
		editor.viewport.show_room()
	if key in ["sun", "sun_angle", "sun_length", "sun_strength", "wall_height"]:
		editor.viewport.refresh_sun()
	if key in ["name", "solid", "above"]:
		editor.refresh_lists()
	editor.viewport.refresh()


## A drop-down of [id, name] pairs. `blank_label` is what no choice is called.
func _pick_row(def: Dictionary, entries: Array, current: int, on_change: Callable, refreshes := false) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = def.get("label", def["name"].replace("_", " "))
	label.custom_minimum_size.x = 130
	label.tooltip_text = def.get("help", "")
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var options := OptionButton.new()
	options.focus_mode = FOCUS_NONE
	options.size_flags_horizontal = SIZE_EXPAND_FILL
	options.add_item("(player)" if def["type"] == "object" else "(none)")
	options.set_item_metadata(0, -1)
	for entry in entries:
		options.add_item(str(entry[1]))
		options.set_item_metadata(options.item_count - 1, int(entry[0]))
		if int(entry[0]) == current:
			options.select(options.item_count - 1)
	options.item_selected.connect(func(i):
		on_change.call(options.get_item_metadata(i))
		if refreshes:
			refresh.call_deferred())
	row.add_child(options)
	_into().add_child(row)


func _rooms_list() -> Array:
	return editor.locale["rooms"].map(func(r): return [r["id"], r["name"]])


func _spawns_in(room: Variant) -> Array:
	if room == null:
		return []
	return room["objects"].filter(func(o): return o["type"] == "spawn").map(func(o): return [o["id"], o["name"]])


## Whoever can be told what to do: the rest of the party, then what's in this room.
func _objects_here() -> Array:
	var found := []
	var party: Array = editor.locale["party"]
	for i in range(1, party.size()):
		found.append([-(i + 1), "(party: %s)" % party[i]["name"]])
	for obj in editor.room["objects"]:
		if LocaleDefs.OBJECT_TYPES[obj["type"]]["visible"]:
			found.append([obj["id"], obj["name"]])
	return found


func _paths_here() -> Array:
	return editor.room["objects"].filter(func(o): return o["type"] == "path").map(func(o): return [o["id"], o["name"]])


func _field(def: Dictionary, value, on_change: Callable) -> Control:
	if def["type"] != "fight":
		return super(def, value, on_change)
	var box := HBoxContainer.new()
	var shown := Label.new()
	shown.text = str(value).get_file() if str(value) != "" else "(none)"
	shown.size_flags_horizontal = SIZE_EXPAND_FILL
	shown.clip_text = true
	var browse := Button.new()
	browse.text = "..."
	browse.focus_mode = FOCUS_NONE
	browse.pressed.connect(func(): editor.browse_file("fight", func(picked):
		on_change.call(picked)
		refresh()))
	box.add_child(shown)
	box.add_child(browse)
	return box


# --- selection ---

func _show_selection() -> void:
	var obj: Variant = editor.selected
	if obj != null:
		var def: Dictionary = LocaleDefs.OBJECT_TYPES[obj["type"]]
		_title(str(def["label"]), def["color"])
		_rows(LocaleDefs.object_params(obj["type"]), obj)
		if obj["type"] == "warp":
			_section("Connecting rooms")
			_action("Make it two-way (adds a way back)", func(): editor.make_two_way(obj))
			_action("Lead to a new room", func(): editor.warp_to_new_room(obj))
			if LocaleDefs.find_room(editor.locale, int(obj["room"])) != null:
				_action("Go to that room", func(): editor.follow_warp(obj))
		if obj.has("steps"):
			_section("What happens")
			_steps(obj["steps"])
		if obj["type"] == "path":
			_path_tools(obj)
		_action("Delete", editor.delete_selected)
		return
	var layer: Variant = editor.layer
	if layer != null and not editor.map_mode:
		_title("Layer: %s" % layer["name"], Color("c8ff6b"))
		_note("Draw with the fully filled tile, rub out with an empty one. Sheets follow TileMapDual's 4 x 4 layout, or turn on plain tile and pick any one tile.")
		_rows(LocaleDefs.LAYER_PARAMS, layer)
		return
	_title("Nothing selected", Color.WHITE)
	_note("Pick a tool at the top, or place something from the left.")


## A path's points, and the cues that go off when someone reaches them.
func _path_tools(path: Dictionary) -> void:
	_note("%d points. Walk someone along it with a Follow Path step." % path["points"].size())
	_action("Keep drawing", func(): editor.keep_drawing_path(path))
	_section("Cues")
	_note("These go off as they reach a point: animations, sounds, lines, shakes. A number's shown on each point in the room.")
	var cues: Array = path["cues"]
	for cue in cues:
		var chosen: Dictionary = cue
		_card("Cue at point %d" % int(cue["point"]), Color("ffa060"))
		_row({"name": "point", "type": "int", "min": 0.0, "max": path["points"].size() - 1.0}, int(cue["point"]), func(v):
			editor.set_param(chosen, "point", clampi(int(v), 0, path["points"].size() - 1), false)
			editor.viewport.refresh())
		_steps(cue["steps"], true)
		_action("Delete cue", func():
			editor.push_undo()
			cues.erase(chosen)
			editor.changed())
		container = null
	_action("New cue", func():
		editor.push_undo()
		cues.append({"point": path["points"].size() - 1, "steps": []})
		editor.changed())


# --- room, rules ---

func _show_room() -> void:
	_title("Room", Color("3fd0ff"))
	_rows(LocaleDefs.ROOM_PARAMS, editor.room)
	var drawn: Rect2 = editor.viewport.view.drawn_rect()
	_note("Drawn area: %d x %d. The camera shows %d x %d, and it stops at the drawn edges." % [drawn.size.x, drawn.size.y, Overworld.SCREEN.x / editor.locale["rules"]["zoom"], Overworld.SCREEN.y / editor.locale["rules"]["zoom"]])
	_action("Start the game in this room", func(): editor.set_start_here())


func _show_rules() -> void:
	_title("Overworld rules", Color("c8ff6b"))
	_note("For the whole overworld. A Set Rule step can change most of these during play.")
	_rows(LocaleDefs.RULE_PARAMS, editor.locale["rules"])


# --- party ---

func _show_party() -> void:
	_title("Party", Color("ffb03b"))
	_note("The first is who you play as. The rest follow, up to the rules' party size. Standing uses each direction's first frame.")
	var party: Array = editor.locale["party"]
	for member in party:
		_card(str(member["name"]), Color("ffb03b"))
		_rows(LocaleDefs.CHARACTER_PARAMS, member)
		_moves_list(member, "specials", "Specials", ChartDefs.SPECIAL_PRESETS)
		_moves_list(member, "maneuvers", "Maneuvers", ChartDefs.MANEUVER_PRESETS)
		_stats_list(member)
		var chosen: Dictionary = member
		_action("Move up", func():
			var at := party.find(chosen)
			if at > 0:
				editor.push_undo()
				party.remove_at(at)
				party.insert(at - 1, chosen)
				editor.changed())
		if party.size() > 1:
			_action("Remove", func():
				editor.push_undo()
				party.erase(chosen)
				editor.changed())
		container = null
	_action("Add someone", func():
		editor.push_undo()
		party.append(LocaleDefs.new_character("New member"))
		editor.changed())


## Which moves they have. The rules choose whether the menu shows these.
func _moves_list(member: Dictionary, key: String, heading: String, presets: Dictionary) -> void:
	_section(heading)
	var moves: Array = member[key]
	for id in moves:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(presets[id]["name"])
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		label.tooltip_text = str(presets[id].get("description", ""))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)
		var remove := Button.new()
		remove.text = "x"
		remove.focus_mode = FOCUS_NONE
		var chosen_id: String = id
		remove.pressed.connect(func():
			editor.push_undo()
			moves.erase(chosen_id)
			editor.changed())
		row.add_child(remove)
		_into().add_child(row)
	var adding := OptionButton.new()
	adding.focus_mode = FOCUS_NONE
	adding.add_item("Add a move...")
	var ids: Array = presets.keys().filter(func(id): return id not in moves)
	for id in ids:
		adding.add_item(str(presets[id]["name"]))
	adding.item_selected.connect(func(i):
		if i > 0:
			editor.push_undo()
			moves.append(ids[i - 1])
			editor.changed())
	_into().add_child(adding)


## Extra lines on their menu page: anything you like, fixed or read from a flag.
func _stats_list(member: Dictionary) -> void:
	_section("Extra stats")
	var stats: Array = member["stats"]
	for stat in stats:
		var chosen: Dictionary = stat
		_row({"name": "name", "type": "string"}, stat["name"], func(v): editor.set_param(chosen, "name", v, false))
		_row({"name": "value", "type": "string", "help": "What it says"}, stat["value"], func(v): editor.set_param(chosen, "value", v, false))
		_row({"name": "flag", "type": "string", "help": "Show this flag's value instead, so it can change during play"}, stat["flag"], func(v): editor.set_param(chosen, "flag", v, false))
		_action("Remove stat", func():
			editor.push_undo()
			stats.erase(chosen)
			editor.changed())
	_action("Add a stat", func():
		editor.push_undo()
		stats.append({"name": "LV", "value": "1", "flag": ""})
		editor.changed())


# --- cutscenes ---

func _show_cutscenes() -> void:
	_title("Cutscenes", Color("ff80c0"))
	_note("Reusable lists of steps. Run them with a Run Cutscene step, or from an item.")
	var scenes: Array = editor.locale["cutscenes"]
	if not scenes.is_empty():
		_cutscene_at = clampi(_cutscene_at, 0, scenes.size() - 1)
		add_child(_options(scenes.map(func(c): return c["name"]), scenes[_cutscene_at]["name"], func(picked):
			for i in scenes.size():
				if scenes[i]["name"] == picked:
					_cutscene_at = i
			refresh()))
		var scene: Dictionary = scenes[_cutscene_at]
		_row({"name": "name", "type": "string"}, scene["name"], func(v): editor.set_param(scene, "name", v, false))
		_steps(scene["steps"])
		_action("Delete this cutscene", func():
			editor.push_undo()
			scenes.erase(scene)
			editor.changed())
	_action("New cutscene", func():
		editor.push_undo()
		scenes.append({"id": LocaleDefs.take_id(editor.locale), "name": "Cutscene %d" % (scenes.size() + 1), "steps": []})
		_cutscene_at = scenes.size() - 1
		editor.changed())


# --- items ---

func _show_items() -> void:
	_title("Items", Color("8bdcff"))
	_note("What the player can carry. Give them with a Give Item step.")
	var items: Array = editor.locale["items"]
	for item in items:
		var chosen: Dictionary = item
		_card(str(item["name"]), Color("8bdcff"))
		_row({"name": "name", "type": "string"}, item["name"], func(v): editor.set_param(chosen, "name", v, false))
		_row({"name": "description", "type": "multiline"}, item["description"], func(v): editor.set_param(chosen, "description", v, false))
		_pick_row({"name": "use", "type": "cutscene", "help": "The cutscene it runs when used"}, editor.locale["cutscenes"].map(func(c): return [c["id"], c["name"]]), int(item["use"]), func(v): editor.set_param(chosen, "use", v, false))
		_action("Delete", func():
			editor.push_undo()
			items.erase(chosen)
			editor.changed())
		container = null
	_action("New item", func():
		editor.push_undo()
		items.append({"id": LocaleDefs.take_id(editor.locale), "name": "Item %d" % (items.size() + 1), "description": "", "use": -1})
		editor.changed())


# --- steps ---

func _is_open(step: Dictionary) -> bool:
	return _open_steps.any(func(s): return is_same(s, step))


func _steps(steps: Array, in_cue := false) -> void:
	var depth := 0
	for i in steps.size():
		var step: Dictionary = steps[i]
		var kind: String = step["type"]
		if kind in ["else", "end"]:
			depth = maxi(depth - 1, 0)
		_step_row(steps, i, depth)
		if kind in LocaleDefs.BLOCK_STARTS or kind == "else":
			depth += 1
	var adding := OptionButton.new()
	adding.focus_mode = FOCUS_NONE
	adding.add_item("Add a step...")
	var keys: Array = LocaleDefs.STEP_TYPES.keys()
	if in_cue:
		keys.erase("battle") # nothing could pick a cue back up afterwards
	for key in keys:
		adding.add_item(LocaleDefs.STEP_TYPES[key]["label"])
	adding.item_selected.connect(func(i):
		if i == 0:
			return
		editor.push_undo()
		var kind: String = keys[i - 1]
		var made := LocaleDefs.new_step(kind)
		steps.append(made)
		if kind in LocaleDefs.BLOCK_STARTS:
			steps.append(LocaleDefs.new_step("end"))
		_open_steps.append(made)
		editor.changed())
	_into().add_child(adding)


func _step_row(steps: Array, i: int, depth: int) -> void:
	var step: Dictionary = steps[i]
	var row := HBoxContainer.new()
	var indent := Control.new()
	indent.custom_minimum_size.x = depth * 14.0
	row.add_child(indent)
	var title := Button.new()
	title.text = _summary(step)
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.clip_text = true
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title.focus_mode = FOCUS_NONE
	title.add_theme_color_override("font_color", Color("ffd24f") if step["type"] in LocaleDefs.BLOCK_STARTS + ["else", "end"] else Color.WHITE)
	title.pressed.connect(func():
		if _is_open(step):
			_open_steps = _open_steps.filter(func(s): return not is_same(s, step))
		else:
			_open_steps.append(step)
		refresh())
	row.add_child(title)
	for tool_button in [["^", -1], ["v", 1]]:
		var move := Button.new()
		move.text = tool_button[0]
		move.focus_mode = FOCUS_NONE
		var by: int = tool_button[1]
		move.pressed.connect(func():
			var to := i + by
			if to >= 0 and to < steps.size():
				editor.push_undo()
				steps.remove_at(i)
				steps.insert(to, step)
				editor.changed())
		row.add_child(move)
	var remove := Button.new()
	remove.text = "x"
	remove.focus_mode = FOCUS_NONE
	remove.pressed.connect(func():
		editor.push_undo()
		steps.remove_at(i)
		editor.changed())
	row.add_child(remove)
	_into().add_child(row)
	if _is_open(step):
		_rows(LocaleDefs.STEP_TYPES[step["type"]]["params"], step)


## A step in a few words, for the list.
func _summary(step: Dictionary) -> String:
	var label: String = LocaleDefs.STEP_TYPES[step["type"]]["label"]
	match step["type"]:
		"say":
			return "%s: %s" % [step["speaker"] if str(step["speaker"]) != "" else "Say", str(step["text"]).replace("\n", " ")]
		"choice":
			return "Ask: %s (%s)" % [str(step["text"]).replace("\n", " "), step["options"]]
		"if":
			return "If %s %s %s" % [step["flag"], step["compare"], step["value"]]
		"set_flag":
			return "%s %s %s %s" % [step["how"].capitalize(), step["flag"], "to" if step["how"] == "set" else "by", step["value"]]
		"wait":
			return "Wait %s s" % step["seconds"]
		"set_rule":
			return "Rule: %s = %s" % [step["rule"], step["value"]]
		"battle":
			return "Fight: %s" % str(step["fight"]).get_file()
		"follow":
			var path: Variant = LocaleDefs.find_object(editor.room, int(step["path"]))
			return "Follow %s" % (path["name"] if path != null else "...")
		"animate":
			return "Animate frames %s to %s" % [step["first"], int(step["first"]) + int(step["count"]) - 1]
		"has_item":
			var item: Variant = LocaleDefs.find_item(editor.locale, int(step["item"]))
			return "If they have %s" % (item["name"] if item != null else "...")
		"give":
			var item: Variant = LocaleDefs.find_item(editor.locale, int(step["item"]))
			return "Give %s x%s" % [item["name"] if item != null else "...", step["count"]]
	return label
