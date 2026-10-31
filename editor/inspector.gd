extends VBoxContainer
## The editor's context panel: every setting of whatever is selected (a node,
## an object lane, or the chart itself when nothing is). Built from the
## parameter lists in ChartDefs, so new node types show up here automatically.

var editor


func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if editor.selected.size() == 1:
		_show_event(editor.selected[0])
	elif editor.selected.size() > 1:
		_title("%d nodes selected" % editor.selected.size(), Color.WHITE)
		_note("Drag any of them to move them all. Delete removes them all. Ctrl+C / Ctrl+V copies them.")
	elif editor.selected_object != null:
		_show_object(editor.selected_object)
	else:
		_show_chart()


func _show_event(ev: Dictionary) -> void:
	var def: Dictionary = ChartDefs.TYPES[ev["type"]]
	_title(def["label"], def["color"])
	_note(def["help"])
	var home: Dictionary = editor.find_event(ev)
	if home.get("object") != null:
		_note("Object: %s" % ChartDefs.lane_label(home["object"]))
	var number := {"type": "float", "min": 0.0, "max": 100000.0}
	_row(number.merged({"name": "beat"}), ev["beat"], func(v): editor.set_param(ev, "beat", v, false))
	if not ChartDefs.is_instant(ev["type"]):
		_row(number.merged({"name": "length", "help": "In beats"}), ev["length"], func(v): editor.set_param(ev, "length", maxf(v, 0.01), false))
	for p in def["params"]:
		if p["type"] == "richtext":
			_richtext_row(ev, p["name"])
		else:
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


func _show_object(obj: Dictionary) -> void:
	_title("Object: %s" % ChartDefs.lane_label(obj), Color("ffb03b"))
	_note("%d nodes on this lane. These settings apply every time it spawns." % obj["events"].size())
	for p in ChartDefs.OBJECT_PARAMS:
		_row(p, obj[p["name"]], func(v): editor.set_param(obj, p["name"], v, false))
	_action("Duplicate object", editor.duplicate_object)
	_action("Delete object", editor.delete_object)


func _show_chart() -> void:
	_title("Chart", Color.WHITE)
	_note(editor.chart_path)
	for p in ChartDefs.CHART_PARAMS:
		_row(p, editor.chart[p["name"]], func(v): editor.set_param(editor.chart, p["name"], v, false))
	var attack_count: int = ChartDefs.attacks(editor.chart).size()
	_note("%d attacks, %d object lanes." % [attack_count, editor.chart["objects"].size()])
	_note("Select a node to edit it, or click a lane's name to edit that object. Press Help for all the controls.")


# --- building rows ---

func _title(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", color)
	add_child(label)


func _note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 300
	label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	add_child(label)


func _action(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.pressed.connect(action)
	add_child(b)


func _row(def: Dictionary, value, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = def["name"].replace("_", " ")
	label.custom_minimum_size.x = 130
	label.tooltip_text = def.get("help", "")
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)

	var field: Control
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
			field = spin
		"bool":
			var check := CheckBox.new()
			check.button_pressed = value
			check.toggled.connect(on_change)
			field = check
		"enum":
			var options := OptionButton.new()
			for o in def["options"]:
				options.add_item(o.replace("_", " "))
			options.select(maxi(def["options"].find(value), 0))
			options.item_selected.connect(func(i): on_change.call(def["options"][i]))
			field = options
		"color":
			var picker := ColorPickerButton.new()
			picker.color = Color(value)
			picker.edit_alpha = false
			picker.custom_minimum_size = Vector2(60, 24)
			picker.color_changed.connect(func(c): on_change.call(c.to_html(false)))
			field = picker
		"texture", "audio":
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
			field = box
		_:
			var line := LineEdit.new()
			line.text = str(value)
			line.text_changed.connect(on_change)
			field = line
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	field.tooltip_text = def.get("help", "")
	row.add_child(field)
	add_child(row)
	if def.has("help"):
		var help := Label.new()
		help.text = "   " + def["help"]
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.custom_minimum_size.x = 300
		help.add_theme_font_size_override("font_size", 16)
		help.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		add_child(help)
