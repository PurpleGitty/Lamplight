extends VBoxContainer
## The editor's context panel: every setting of whatever is selected (a node,
## an object lane, or the chart itself when nothing is). Built from the
## parameter lists in ChartDefs, so new node types show up here automatically.

const SpritePreviewPanel = preload("res://editor/sprite_preview.gd")
const FormulaEditorWindow = preload("res://editor/formula_editor.gd")

## Which folding sections are shut, remembered across redraws.
static var folded := {}

var editor
var show_hints := true # false: help stays in tooltips only
var container: Control # where new rows go (the open section, or the panel itself)


func refresh() -> void:
	_clear()
	if editor.selected.size() == 1:
		_show_event(editor.selected[0])
	elif editor.selected.size() > 1:
		_title("%d nodes selected" % editor.selected.size(), Color.WHITE)
		_note("[LMB DRAG] MOVE ALL   [DEL] DELETE ALL   [CTRL+C] COPY   [CTRL+V] PASTE")
	elif editor.selected_object != null:
		_show_object(editor.selected_object)
	elif editor.soul_selected:
		_show_soul()
	else:
		_show_chart()


func _clear() -> void:
	container = null
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _show_event(ev: Dictionary) -> void:
	var def: Dictionary = ChartDefs.TYPES[ev["type"]]
	_title(def["label"], def["color"])
	_note(def["help"])
	var home: Dictionary = editor.find_event(ev)
	if home.get("object") != null:
		_note("Object: %s" % ChartDefs.lane_label(home["object"]))
	var number := {"type": "float", "min": 0.0, "max": 100000.0}
	var unit: String = editor.unit_name()
	_row(number.merged({"name": unit}), ev["beat"], func(v): editor.set_param(ev, "beat", v, false))
	if not ChartDefs.is_instant(ev["type"]):
		_row(number.merged({"name": "length", "help": "In %ss" % unit}), ev["length"], func(v): editor.set_param(ev, "length", maxf(v, 0.01), false))
	for p in def["params"]:
		match p["type"]:
			"richtext":
				_richtext_row(ev, p["name"])
			"formula":
				_formula_row(ev)
			"object_list":
				_object_list(ev, p)
			"object_changes":
				_changes_list(ev, p["name"], false)
			"rule_changes":
				_changes_list(ev, p["name"], true)
			"character":
				_character_row(ev, p)
			_:
				_row(p, ev["params"][p["name"]], func(v):
					editor.set_param(ev, p["name"], v, true)
					if ev["type"] == "text":
						refresh.call_deferred()) # text previews follow kind/speaker
	_action("Delete node", func(): editor.delete_events([ev]))


## Formatted text: a preview of it, and a button to open the text editor.
func _richtext_row(ev: Dictionary, key: String) -> void:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE if ev["params"].get("kind") == "dialogue" else Color.BLACK
	style.border_color = Color.WHITE
	style.set_border_width_all(2)
	style.set_content_margin_all(6)
	box.add_theme_stylebox_override("panel", style)
	var text := RichTextLabel.new()
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size.x = 300
	text.add_theme_color_override("default_color", Color.BLACK if ev["params"].get("kind") == "dialogue" else Color.WHITE)
	box.add_child(text)
	add_child(box)
	TextMarkup.build(text, ev["params"][key], 0.0)
	_action("Edit text...", func(): editor.open_text_editor(ev))


## Whether a Math Attack's formula works, and a button to open it.
func _formula_row(ev: Dictionary) -> void:
	var attack := MathAttack.new(ev)
	var words := Label.new()
	words.text = FormulaEditorWindow.status_text(attack)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size.x = 300
	words.add_theme_color_override("font_color", FormulaEditorWindow.GOOD if attack.can_run() else FormulaEditorWindow.BAD)
	add_child(words)
	_action("Edit formula...", func(): editor.open_formula_editor(ev))


## Tick boxes for the objects a Change Objects node affects.
func _object_list(ev: Dictionary, def: Dictionary) -> void:
	_section("Objects")
	if def.has("help"):
		_hint(def["help"])
	var attack: Dictionary = editor.attack_containing(ev["beat"])
	var listed := 0
	for obj in editor.chart["objects"]:
		var used: bool = attack.is_empty()
		for other in obj["events"]:
			if not attack.is_empty() and other["beat"] >= attack["start"] and other["beat"] < attack["end"]:
				used = true
		if not used:
			continue
		listed += 1
		var id := int(obj["id"])
		var check := CheckBox.new()
		check.text = ChartDefs.lane_label(obj)
		check.button_pressed = ev["params"]["objects"].any(func(o): return int(o) == id)
		check.toggled.connect(func(on):
			var ids: Array = ev["params"]["objects"].filter(func(o): return int(o) != id)
			if on:
				ids.append(id)
			editor.set_param(ev, "objects", ids, true))
		add_child(check)
	if listed == 0:
		_hint("No objects in this attack yet.")


## The list of changes on a Change Objects or Change Rules node, each with its
## own controls, and a button to add another.
func _changes_list(ev: Dictionary, key: String, is_rules: bool) -> void:
	_section("Changes")
	var changes: Array = ev["params"][key]
	for change in changes:
		var row := HBoxContainer.new()
		add_child(row)
		var targets: Array = editor.change_targets() if is_rules else []
		if is_rules:
			row.add_child(_options(targets, change["target"], func(picked):
				_edit_change(ev, change, func():
					change["target"] = picked
					var first: Dictionary = ChartDefs.change_keys(editor.chart, picked)[0]
					change["key"] = first["name"]
					change["value"] = first["default"])))
		var keys: Array = ChartDefs.change_keys(editor.chart, change["target"]) if is_rules else ChartDefs.OBJECT_CHANGE_KEYS
		var names: Array = keys.map(func(d): return d["name"])
		row.add_child(_options(names, change["key"], func(picked):
			_edit_change(ev, change, func():
				change["key"] = picked
				for d in keys:
					if d["name"] == picked:
						change["value"] = d["default"])))
		for d in keys:
			if d["name"] == change["key"]:
				var field := _field(d, change["value"], func(v): editor.set_param(change, "value", v, false))
				field.size_flags_horizontal = SIZE_EXPAND_FILL
				row.add_child(field)
		var remove := Button.new()
		remove.text = "x"
		remove.focus_mode = FOCUS_NONE
		remove.pressed.connect(func():
			_edit_change(ev, change, func(): changes.erase(change)))
		row.add_child(remove)
	_action("Add change", func():
		editor.push_undo()
		if is_rules:
			var target: String = editor.change_targets()[0]
			var first: Dictionary = ChartDefs.change_keys(editor.chart, target)[0]
			changes.append({"target": target, "key": first["name"], "value": first["default"]})
		else:
			var first: Dictionary = ChartDefs.OBJECT_CHANGE_KEYS[0]
			changes.append({"key": first["name"], "value": first["default"]})
		editor.changed())


func _edit_change(_ev: Dictionary, _change: Dictionary, edit: Callable) -> void:
	editor.push_undo()
	edit.call()
	editor.changed()


func _character_row(ev: Dictionary, def: Dictionary) -> void:
	var names: Array = editor.character_names()
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = def["name"].replace("_", " ")
	label.custom_minimum_size.x = 130
	row.add_child(label)
	var field := _options(names, ev["params"][def["name"]], func(picked): editor.set_param(ev, def["name"], picked, true))
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(field)
	add_child(row)


func _show_object(obj: Dictionary) -> void:
	_title("Object: %s" % ChartDefs.lane_label(obj), Color("ffb03b"))
	_note("%d nodes on this lane. These settings apply every time it spawns." % obj["events"].size())
	var preview := SpritePreviewPanel.new()
	preview.editor = editor
	preview.data = obj
	preview.first_key = "frame"
	preview.count_key = "anim_frames"
	preview.length_key = "anim_beats"
	add_child(preview)
	for p in ChartDefs.OBJECT_PARAMS:
		_row(p, obj[p["name"]], func(v): editor.set_param(obj, p["name"], v, false))
	_action("Duplicate object", editor.duplicate_object)
	_action("Delete object", editor.delete_object)


func _show_soul() -> void:
	_title("Soul", Color("ff60a0"))
	_note("[LMB DRAG] THE HITBOX: MOVE IT      [LMB DRAG] THE REST OF THE SOUL: MOVE THE SOUL")
	_note("A Change Rules node can change all of these mid-fight.")
	var rules: Dictionary = editor.chart["rules"]
	for p in ChartDefs.RULE_PARAMS:
		if p["name"].begins_with("soul_") and p["name"] != "soul_speed":
			_row(p.merged({"label": p["name"].trim_prefix("soul_").replace("_", " ")}), rules[p["name"]], func(v): editor.set_param(rules, p["name"], v, false))


func _show_chart() -> void:
	_title("Chart", Color.WHITE)
	_note(editor.chart_path)
	for p in ChartDefs.CHART_PARAMS:
		_row(p, editor.chart[p["name"]], func(v): editor.set_param(editor.chart, p["name"], v, false))
	var attack_count: int = ChartDefs.attacks(editor.chart).size()
	_note("%d attacks, %d object lanes." % [attack_count, editor.chart["objects"].size()])
	_note("[LMB] on a node: edit it. [LMB] on a lane's name: edit that object. Help lists all the controls.")


# --- building rows ---

func _into() -> Control:
	return container if container != null else self


## Starts a folding section; rows added after this go inside it.
func _card(heading: String, color: Color) -> void:
	var key := "%s/%s" % [get_script().resource_path.get_file(), heading]
	var is_folded: bool = folded.get(key, false)
	var header := Button.new()
	header.text = ("+  " if is_folded else "-  ") + heading
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.focus_mode = FOCUS_NONE
	header.add_theme_color_override("font_color", color)
	header.add_theme_color_override("font_hover_color", color.lightened(0.3))
	add_child(header)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.visible = not is_folded
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	header.pressed.connect(func():
		folded[key] = margin.visible
		margin.visible = not margin.visible
		header.text = ("+  " if not margin.visible else "-  ") + heading)
	container = box


func _title(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", color)
	_into().add_child(label)


func _section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color.WHITE)
	_into().add_child(label)


func _note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 300
	label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	_into().add_child(label)


func _hint(text: String) -> void:
	var help := Label.new()
	help.text = "   " + text
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 300
	help.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	_into().add_child(help)


func _action(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.pressed.connect(action)
	_into().add_child(b)


func _options(items: Array, current, on_pick: Callable) -> OptionButton:
	var options := OptionButton.new()
	options.focus_mode = FOCUS_NONE
	options.fit_to_longest_item = false
	for item in items:
		options.add_item(str(item).replace("_", " "))
	options.select(maxi(items.find(current), 0))
	options.item_selected.connect(func(i): on_pick.call(items[i]))
	return options


func _row(def: Dictionary, value, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = def.get("label", def["name"].replace("_", " "))
	label.custom_minimum_size.x = 130
	label.tooltip_text = def.get("help", "")
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var field := _field(def, value, on_change)
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	field.tooltip_text = def.get("help", "")
	row.add_child(field)
	_into().add_child(row)
	if show_hints and def.has("help"):
		_hint(def["help"])


## The control for one setting.
func _field(def: Dictionary, value, on_change: Callable) -> Control:
	match def["type"]:
		"float", "int":
			var spin := SpinBox.new()
			spin.min_value = def.get("min", -100000.0)
			spin.max_value = def.get("max", 100000.0)
			spin.allow_greater = true
			spin.allow_lesser = true
			spin.step = 1.0 if def["type"] == "int" else 0.001
			spin.custom_arrow_step = 1.0 if def["type"] == "int" else 0.25
			spin.value = value
			spin.select_all_on_focus = true
			var is_int: bool = def["type"] == "int"
			spin.value_changed.connect(func(v): on_change.call(int(v) if is_int else v))
			return spin
		"multiline":
			var box := TextEdit.new()
			box.text = str(value)
			box.custom_minimum_size.y = 56
			box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			box.text_changed.connect(func(): on_change.call(box.text))
			return box
		"bool":
			var check := CheckBox.new()
			check.button_pressed = value
			check.toggled.connect(on_change)
			return check
		"enum":
			return _options(def["options"], value, on_change)
		"color":
			var picker := ColorPickerButton.new()
			picker.color = Color(value)
			picker.edit_alpha = false
			picker.custom_minimum_size = Vector2(60, 24)
			picker.color_changed.connect(func(c): on_change.call(c.to_html(false)))
			return picker
		"texture", "audio", "font", "video":
			var box := HBoxContainer.new()
			var path := LineEdit.new()
			path.text = value
			path.size_flags_horizontal = SIZE_EXPAND_FILL
			path.text_submitted.connect(on_change)
			var browse := Button.new()
			browse.text = "..."
			browse.focus_mode = FOCUS_NONE
			browse.pressed.connect(func(): editor.browse_file(def["type"], func(picked):
				on_change.call(picked)
				refresh()))
			box.add_child(path)
			box.add_child(browse)
			return box
	var line := LineEdit.new()
	line.text = str(value)
	line.text_changed.connect(on_change)
	return line
