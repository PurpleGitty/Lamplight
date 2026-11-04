extends "res://editor/inspector.gd"
## The chart maker's Characters tab: who's in this fight and their stats, sprites,
## animations, specials and ACTs. Pick a character, edit them, add or remove them.

var current := 0


func refresh() -> void:
	_clear()
	var everyone: Array = _everyone()
	current = clampi(current, 0, maxi(everyone.size() - 1, 0))
	_title("Characters", Color("c8ff6b"))
	var names: Array = everyone.map(func(entry): return "%s (%s)" % [entry["data"]["name"], "party" if entry["party"] else "enemy"])
	if not names.is_empty():
		var picker := _options(names, names[current], func(picked):
			current = names.find(picked)
			refresh())
		add_child(picker)
	var buttons := HBoxContainer.new()
	add_child(buttons)
	_small_button(buttons, "+ Party member", func(): _add(true))
	_small_button(buttons, "+ Enemy", func(): _add(false))
	_small_button(buttons, "Remove", _remove_current)
	if everyone.is_empty():
		_note("No characters yet.")
		return

	var entry: Dictionary = everyone[current]
	var data: Dictionary = entry["data"]
	_timing_note(data)
	for p in ChartDefs.CHARACTER_PARAMS:
		_row(p, data[p["name"]], func(v): editor.set_param(data, p["name"], v, false))
	if entry["party"]:
		for p in ChartDefs.PARTY_PARAMS:
			_row(p, data[p["name"]], func(v): editor.set_param(data, p["name"], v, false))
		_list_section(data, "specials", "Specials", {"name": "New special", "cost": 10.0, "damage": 500.0}, [
			{"name": "name", "type": "string"},
			{"name": "cost", "type": "float", "min": 0.0, "max": 1000.0, "help": "TP"},
			{"name": "damage", "type": "float", "min": 0.0, "max": 999999.0},
		])
	else:
		_list_section(data, "acts", "ACTs (Maneuver)", {"name": "New act", "text": "* Nothing happens."}, [
			{"name": "name", "type": "string"},
			{"name": "text", "type": "string"},
		])


func _everyone() -> Array:
	var everyone := []
	for data in editor.chart["party"]:
		everyone.append({"data": data, "party": true})
	for data in editor.chart["enemies"]:
		everyone.append({"data": data, "party": false})
	return everyone


## The numbers needed to draw an idle animation that lands on the beat.
func _timing_note(data: Dictionary) -> void:
	var seconds_per_beat: float = 60.0 / editor.chart["bpm"]
	_note("At %s BPM, one beat is %.3f seconds, or %.1f frames at 60 FPS." % [editor.chart["bpm"], seconds_per_beat, seconds_per_beat * 60.0])
	var count: int = maxi(int(data["idle_count"]), 1)
	var beats: float = float(data["idle_beats"]) / count
	_note("This idle: %d sprite frames over %s beats, so each one shows for %.2f beats (%.1f frames at 60 FPS)." % [count, data["idle_beats"], beats, beats * seconds_per_beat * 60.0])


func _list_section(data: Dictionary, key: String, heading: String, blank: Dictionary, fields: Array) -> void:
	_section(heading)
	var items: Array = data[key]
	for item in items:
		for f in fields:
			_row(f, item[f["name"]], func(v): editor.set_param(item, f["name"], v, false))
		_action("Remove %s" % item["name"], func():
			editor.push_undo()
			items.erase(item)
			editor.changed())
	_action("Add", func():
		editor.push_undo()
		items.append(blank.duplicate())
		editor.changed())


func _small_button(parent: Control, text: String, action: Callable) -> void:
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
	current = _everyone().size() - 1 if not is_party else list.size() - 1
	editor.changed()


func _remove_current() -> void:
	var everyone := _everyone()
	if everyone.is_empty():
		return
	var entry: Dictionary = everyone[current]
	editor.push_undo()
	(editor.chart["party"] if entry["party"] else editor.chart["enemies"]).erase(entry["data"])
	editor.changed()
