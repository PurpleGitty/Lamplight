extends "res://editor/inspector.gd"
## The chart maker's Characters tab. Pick someone from the row at the top, see
## their sprite animate, and edit them in folding sections.

const SpritePreview = preload("res://editor/sprite_preview.gd")
const LABELS := {
	"present": "in fight at start", "hframes": "frames across", "sprite_scale": "size", "max_hp": "max HP",
	"fight_damage": "attack damage", "fight_minigame": "attack minigame", "idle_first": "first", "idle_count": "frames", "idle_beats": "beats",
	"attack_first": "first", "attack_count": "frames", "attack_seconds": "seconds",
}

var current := 0


func _ready() -> void:
	show_hints = false # help stays in tooltips, to keep this tab readable


func refresh() -> void:
	_clear()
	var everyone := _everyone()
	current = clampi(current, 0, maxi(everyone.size() - 1, 0))
	_picker(everyone)
	if everyone.is_empty():
		_note("No characters yet.")
		return
	var entry: Dictionary = everyone[current]
	var data: Dictionary = entry["data"]

	var preview := SpritePreview.new()
	preview.editor = editor
	preview.data = data
	add_child(preview)
	var timing := Label.new()
	timing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	timing.custom_minimum_size.x = 300
	timing.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	add_child(timing)
	preview.note = timing

	_card("Basics", Color("c8ff6b"))
	_labeled(data, "name")
	_labeled(data, "present")
	_compact(data, ["max_hp", "defense"])
	if entry["party"]:
		_labeled(data, "fight_damage")
		_labeled(data, "fight_minigame")
	_labeled(data, "voice")

	_card("Sprite", Color("ffd24f"))
	_labeled(data, "sprite")
	_compact(data, ["hframes", "sprite_scale"])
	_compact(data, ["x", "y"])

	_card("Animation", Color("ff9ecb"))
	_section("Idle")
	_compact(data, ["idle_first", "idle_count", "idle_beats"])
	_labeled(data, "bob")
	if entry["party"]:
		_section("Attack")
		_compact(data, ["attack_first", "attack_count", "attack_seconds"])
		_action("Preview attack animation", func():
			preview.play_once(int(data["attack_first"]), int(data["attack_count"]), data["attack_seconds"]))
		_card("Specials", Color("ff5c5c"))
		_moves(data, "specials", true)
		_card("Maneuvers", Color("3fd0ff"))
		_moves(data, "maneuvers", false)
	else:
		_card("ACTs (any party member can use these)", Color("3fd0ff"))
		_acts(data)
	container = null

	var remove := Button.new()
	remove.text = "Remove %s" % data["name"]
	remove.focus_mode = FOCUS_NONE
	remove.pressed.connect(_remove_current)
	add_child(remove)


## The character being edited, for the preview to show (null if there's nobody).
func current_data() -> Variant:
	var everyone := _everyone()
	return everyone[current]["data"] if current >= 0 and current < everyone.size() else null


## Picks a character, as if their button had been pressed.
func pick(data: Dictionary) -> void:
	var everyone := _everyone()
	for i in everyone.size():
		if everyone[i]["data"] == data:
			current = i
	refresh()


func _everyone() -> Array:
	var everyone := []
	for data in editor.chart["party"]:
		everyone.append({"data": data, "party": true})
	for data in editor.chart["enemies"]:
		everyone.append({"data": data, "party": false})
	return everyone


## One button per character, with their sprite, party and enemies apart.
func _picker(everyone: Array) -> void:
	var flow := HFlowContainer.new()
	add_child(flow)
	for was_party in [true, false]:
		var heading := Label.new()
		heading.text = "Party:" if was_party else "  Enemies:"
		heading.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		flow.add_child(heading)
		for i in everyone.size():
			if everyone[i]["party"] != was_party:
				continue
			var data: Dictionary = everyone[i]["data"]
			var b := Button.new()
			b.text = data["name"]
			b.toggle_mode = true
			b.button_pressed = i == current
			b.focus_mode = FOCUS_NONE
			b.icon = _thumbnail(data)
			b.expand_icon = false
			b.add_theme_constant_override("icon_max_width", 24)
			b.texture_filter = TEXTURE_FILTER_NEAREST
			b.pressed.connect(func():
				current = i
				refresh())
			flow.add_child(b)
		var add := Button.new()
		add.text = "+"
		add.tooltip_text = "Add a party member" if was_party else "Add an enemy"
		add.focus_mode = FOCUS_NONE
		add.pressed.connect(_add.bind(was_party))
		flow.add_child(add)


func _thumbnail(data: Dictionary) -> Texture2D:
	var tex := ChartDefs.load_texture(data["sprite"])
	var frames := maxi(int(data["hframes"]), 1)
	var w := tex.get_width() / float(frames)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(clampi(int(data["idle_first"]), 0, frames - 1) * w, 0, w, tex.get_height())
	return atlas


func _def(key: String) -> Dictionary:
	for p in ChartDefs.CHARACTER_PARAMS + ChartDefs.PARTY_PARAMS:
		if p["name"] == key:
			return p.merged({"label": LABELS.get(key, key.replace("_", " "))}, true)
	return {}


func _labeled(data: Dictionary, key: String) -> void:
	_row(_def(key), data[key], func(v):
		editor.set_param(data, key, v, false))


## Several small settings side by side.
func _compact(data: Dictionary, keys: Array) -> void:
	var row := HBoxContainer.new()
	for key in keys:
		var def := _def(key)
		var label := Label.new()
		label.text = def["label"]
		label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		label.tooltip_text = def.get("help", "")
		label.mouse_filter = MOUSE_FILTER_PASS
		row.add_child(label)
		var field := _field(def, data[key], func(v): editor.set_param(data, key, v, false))
		field.size_flags_horizontal = SIZE_EXPAND_FILL
		field.tooltip_text = def.get("help", "")
		row.add_child(field)
	_into().add_child(row)


## A character's specials or maneuvers: each folds open, and new ones come from
## the preset lists and can then be changed however you like.
func _moves(data: Dictionary, key: String, is_special: bool) -> void:
	var items: Array = data[key]
	for item in items:
		var outer: Control = _into()
		_move_entry(outer, items, item, is_special)
		container = outer
	var presets: Dictionary = ChartDefs.SPECIAL_PRESETS if is_special else ChartDefs.MANEUVER_PRESETS
	var ids: Array = presets.keys()
	var labels: Array = ids.map(func(id): return "%s: %s" % [presets[id]["name"], presets[id]["description"]])
	var row := HBoxContainer.new()
	_into().add_child(row)
	var picker := _options(labels, labels[0], func(_picked): pass)
	picker.size_flags_horizontal = SIZE_EXPAND_FILL
	picker.clip_text = true
	row.add_child(picker)
	_button_in(row, "Add", func():
		editor.push_undo()
		items.append(ChartDefs.new_move(is_special, ids[picker.selected]))
		editor.changed())


func _move_entry(outer: Control, items: Array, item: Dictionary, is_special: bool) -> void:
	var key := "move/%s/%s" % [is_special, item["name"]]
	var is_open: bool = folded.get(key, false) # moves start shut
	var header := Button.new()
	var cost_text := " (%d TP)" % item["cost"] if item["cost"] > 0.0 else ""
	header.text = ("-  " if is_open else "+  ") + item["name"] + cost_text
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.focus_mode = FOCUS_NONE
	header.tooltip_text = item["description"]
	outer.add_child(header)
	var box := MarginContainer.new()
	box.add_theme_constant_override("margin_left", 10)
	box.visible = is_open
	outer.add_child(box)
	var inner := VBoxContainer.new()
	box.add_child(inner)
	header.pressed.connect(func():
		folded[key] = not box.visible
		box.visible = not box.visible
		header.text = ("-  " if box.visible else "+  ") + item["name"] + cost_text)
	container = inner

	var set_field := func(field: String): return func(v): editor.set_param(item, field, v, false)
	_row({"name": "name", "type": "string"}, item["name"], set_field.call("name"))
	_row({"name": "description", "type": "string"}, item["description"], set_field.call("description"))
	_row({"name": "cost", "label": "TP cost", "type": "float", "min": 0.0, "max": 1000.0}, item["cost"], set_field.call("cost"))
	if is_special:
		_row({"name": "damage", "type": "float", "min": 0.0, "max": 999999.0}, item["damage"], set_field.call("damage"))
		_row({"name": "hits", "label": "attacks in a row", "type": "int", "min": 1, "max": 20}, item["hits"], set_field.call("hits"))
		_row({"name": "hits_all", "label": "hits every enemy", "type": "bool"}, item["hits_all"], set_field.call("hits_all"))
		_minigame_settings(item)
	else:
		_row({"name": "text", "label": "text ({user} = name)", "type": "multiline"}, item["text"], set_field.call("text"))
	_section("When used")
	_row({"name": "sprite", "label": "icon sprite", "type": "texture"}, item["sprite"], set_field.call("sprite"))
	_row({"name": "sound", "type": "audio"}, item["sound"], set_field.call("sound"))
	var anim := HBoxContainer.new()
	_into().add_child(anim)
	for field in [["use_first", "anim first", "int"], ["use_count", "frames", "int"], ["use_seconds", "seconds", "float"]]:
		var label := Label.new()
		label.text = field[1]
		label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		anim.add_child(label)
		var input := _field({"type": field[2], "min": 0.0, "max": 255.0}, item[field[0]], set_field.call(field[0]))
		input.size_flags_horizontal = SIZE_EXPAND_FILL
		anim.add_child(input)
	_effects(item)

	var buttons := HBoxContainer.new()
	_into().add_child(buttons)
	if is_special:
		_button_in(buttons, "Try it", func(): editor.try_minigame(item["minigame"], item["settings"]))
	_button_in(buttons, "Remove", func():
		editor.push_undo()
		items.erase(item)
		editor.changed())
	_into().add_child(HSeparator.new())


## What the move does: a list of effects, each with its own numbers.
func _effects(item: Dictionary) -> void:
	_section("Effects")
	var kinds: Array = ChartDefs.EFFECTS.keys()
	var labels: Array = kinds.map(func(k): return ChartDefs.EFFECTS[k]["label"])
	var effects: Array = item["effects"]
	for effect in effects:
		var info: Dictionary = ChartDefs.EFFECTS[effect["kind"]]
		var row := HBoxContainer.new()
		_into().add_child(row)
		var kind_picker := _options(labels, info["label"], func(picked):
			editor.push_undo()
			var k: String = kinds[labels.find(picked)]
			effect["kind"] = k
			effect["value"] = ChartDefs.EFFECTS[k]["value"]
			effect["target"] = ChartDefs.EFFECTS[k]["target"]
			editor.changed())
		kind_picker.size_flags_horizontal = SIZE_EXPAND_FILL
		kind_picker.tooltip_text = info["help"]
		row.add_child(kind_picker)
		var value := _field({"type": "float", "min": 0.0, "max": 100000.0}, effect["value"], func(v): editor.set_param(effect, "value", v, false))
		value.tooltip_text = info["help"]
		row.add_child(value)
		_button_in(row, "x", func():
			editor.push_undo()
			effects.erase(effect)
			editor.changed())
		if info["target"] != "" or info["timed"]:
			var extra := HBoxContainer.new()
			_into().add_child(extra)
			if info["target"] != "":
				var who := Label.new()
				who.text = "   on"
				extra.add_child(who)
				var target_picker := _options(ChartDefs.EFFECT_TARGETS, effect["target"], func(picked): editor.set_param(effect, "target", picked, false))
				target_picker.size_flags_horizontal = SIZE_EXPAND_FILL
				extra.add_child(target_picker)
			if info["timed"]:
				var turns := Label.new()
				turns.text = "   enemy turns"
				extra.add_child(turns)
				var turn_field := _field({"type": "int", "min": 1, "max": 99}, effect["turns"], func(v): editor.set_param(effect, "turns", v, false))
				turn_field.size_flags_horizontal = SIZE_EXPAND_FILL
				extra.add_child(turn_field)
	_action("Add an effect", func():
		editor.push_undo()
		effects.append(ChartDefs.new_effect())
		editor.changed())


## Which minigame a special uses, and that minigame's own settings.
func _minigame_settings(item: Dictionary) -> void:
	var ids: Array = ChartDefs.MINIGAMES.keys()
	var labels: Array = ids.map(func(id): return ChartDefs.MINIGAMES[id]["label"])
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "minigame"
	label.custom_minimum_size.x = 130
	row.add_child(label)
	var picker := _options(labels, ChartDefs.MINIGAMES[item["minigame"]]["label"], func(picked):
		editor.push_undo()
		item["minigame"] = ids[labels.find(picked)]
		ChartDefs.fill_special(item)
		editor.changed())
	picker.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(picker)
	_into().add_child(row)
	var def: Dictionary = ChartDefs.MINIGAMES[item["minigame"]]
	picker.tooltip_text = def["help"]
	for p in def["params"]:
		_row(p, item["settings"][p["name"]], func(v): editor.set_param(item["settings"], p["name"], v, false))


func _acts(data: Dictionary) -> void:
	var items: Array = data["acts"]
	for item in items:
		_row({"name": "name", "type": "string"}, item["name"], func(v): editor.set_param(item, "name", v, false))
		_row({"name": "text", "type": "multiline"}, item["text"], func(v): editor.set_param(item, "text", v, false))
		_button_in(_into(), "Remove", func():
			editor.push_undo()
			items.erase(item)
			editor.changed())
		_into().add_child(HSeparator.new())
	_action("Add an ACT", func():
		editor.push_undo()
		items.append({"name": "New act", "text": "* Nothing happens."})
		editor.changed())


func _button_in(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)


func _add(is_party: bool) -> void:
	editor.push_undo()
	var list: Array = editor.chart["party"] if is_party else editor.chart["enemies"]
	var data := ChartDefs.new_character("%s %d" % ["Member" if is_party else "Enemy", list.size() + 1], is_party)
	if is_party:
		data["x"] = -276.0 + list.size() * 164.0
		data["y"] = 168.0
	list.append(data)
	current = list.size() - 1 if is_party else _everyone().size() - 1
	editor.changed()


func _remove_current() -> void:
	var everyone := _everyone()
	if everyone.is_empty():
		return
	var entry: Dictionary = everyone[current]
	editor.push_undo()
	(editor.chart["party"] if entry["party"] else editor.chart["enemies"]).erase(entry["data"])
	editor.changed()
