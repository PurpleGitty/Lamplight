extends ConfirmationDialog
## The prompt for starting a new chart: its file name, the song and its BPM, and
## who's in the fight.

var editor
var file_name := LineEdit.new()
var song := LineEdit.new()
var bpm := SpinBox.new()
var enemies := LineEdit.new()
var party := LineEdit.new()


func _ready() -> void:
	title = "New chart"
	ok_button_text = "Create"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	add_child(box)

	file_name.text = "new_fight"
	_row(box, "Chart name", file_name)

	song.placeholder_text = "Pick the song..."
	var song_row := HBoxContainer.new()
	song.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	song_row.add_child(song)
	var browse := Button.new()
	browse.text = "Browse..."
	browse.pressed.connect(func(): editor.browse_file("audio", func(picked): song.text = picked, true))
	song_row.add_child(browse)
	_row(box, "Song", song_row)

	bpm.min_value = 20.0
	bpm.max_value = 400.0
	bpm.step = 0.01
	bpm.value = 120.0
	_row(box, "BPM", bpm)

	enemies.text = "Testicina"
	_row(box, "Enemies", enemies)
	party.text = "Purple, Violet"
	_row(box, "Party", party)
	var hint := Label.new()
	hint.text = "Separate names with commas. Sprites, stats and everything else are on the Characters tab."
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	box.add_child(hint)
	confirmed.connect(_create)


func _row(box: Control, text: String, field: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 110
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	box.add_child(row)


func _names(text: String) -> PackedStringArray:
	var names := PackedStringArray()
	for part in text.split(",", false):
		if part.strip_edges() != "":
			names.append(part.strip_edges())
	return names


func _create() -> void:
	var chart := ChartDefs.new_chart()
	if song.text != "":
		chart["song"] = song.text
	chart["bpm"] = bpm.value

	# Names matching the first fight's cast keep their sprites and stats
	var known: Array = ChartDefs.default_party() + ChartDefs.default_enemies()
	var new_party := []
	for character_name in _names(party.text):
		var entry := ChartDefs.new_character(character_name, true)
		entry["x"] = -276.0 + new_party.size() * 164.0
		entry["y"] = 168.0
		for k in known:
			if k["name"] == character_name:
				entry = k
		new_party.append(entry)
	var new_enemies := []
	for character_name in _names(enemies.text):
		var entry := ChartDefs.new_character(character_name, false)
		entry["x"] = 176.0 - new_enemies.size() * 130.0
		for k in known:
			if k["name"] == character_name:
				entry = k
		new_enemies.append(entry)
	chart["party"] = new_party
	chart["enemies"] = new_enemies

	var clean := file_name.text.strip_edges().validate_filename()
	editor.create_chart(chart, ScrapFile.unused_path(clean if clean != "" else "new_fight"))
