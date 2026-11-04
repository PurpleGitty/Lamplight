extends Window
## The attack editor's text editor, for Text nodes. Highlight part of the text
## and press a button to format it (wavy, shaky, tiny, coloured...). The tags
## it adds are shown in blue; the preview below types the text out exactly as
## the game will. See TextMarkup for every tag.

const FONT = preload("res://fonts/PixelOperator.ttf")
const MENU_FONT = preload("res://fonts/Mojang-Regular.ttf")
const TXT_SOUND = preload("res://sounds/snd_txt2.wav")
const PREVIEW_SCALE := 2.0

var editor
var event: Dictionary
var edit := TextEdit.new()
var pause_amount := SpinBox.new()
var type_time := SpinBox.new()
var color_picker := ColorPickerButton.new()
var preview := Control.new()
var bubble := SpeechBubble.new()
var menu_box := ColorRect.new()
var menu_text := RichTextLabel.new()
var menu_writer := TextMarkup.Typewriter.new()
var blip := AudioStreamPlayer.new()
var _replay_in := -1.0


func _init() -> void:
	title = "Text editor"
	size = Vector2i(1000, 680)
	visible = false
	wrap_controls = true
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

	var hint := Label.new()
	hint.text = "Highlight some text, then press a button. Pause goes before the highlighted part. Type [lb] / [rb] for a literal [ or ]."
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	root.add_child(hint)

	var tools := HFlowContainer.new()
	root.add_child(tools)
	pause_amount.min_value = 0.05
	pause_amount.max_value = 10.0
	pause_amount.step = 0.05
	pause_amount.value = 0.5
	pause_amount.suffix = "s"
	_tool(tools, "Pause", func(): _insert_before("[pause=%s]" % _num(pause_amount.value)), "Wait this long before the highlighted part")
	tools.add_child(pause_amount)
	type_time.min_value = 0.0
	type_time.max_value = 30.0
	type_time.step = 0.05
	type_time.value = 1.5
	type_time.suffix = "s"
	_tool(tools, "Type over", func(): _wrap("[time=%s]" % _num(type_time.value), "[/time]"), "The highlighted part takes this long to type out (0 = appears instantly)")
	tools.add_child(type_time)
	tools.add_child(VSeparator.new())
	for effect in [["Astral", "astral"], ["Wave", "wave"], ["Shake", "shake"], ["Swirl", "swirl"], ["Rainbow", "rainbow"], ["Pulse", "pulse"],
			["Tiny", "tiny"], ["Big", "big"], ["Spaced", "spaced"], ["Underline", "u"], ["Strike", "s"], ["Quiet", "quiet"]]:
		var tag: String = effect[1]
		_tool(tools, effect[0], func(): _wrap("[%s]" % tag, "[/%s]" % tag))
	tools.add_child(VSeparator.new())
	color_picker.color = Color("ff5050")
	color_picker.edit_alpha = false
	color_picker.custom_minimum_size = Vector2(40, 24)
	tools.add_child(color_picker)
	_tool(tools, "Color", func(): _wrap("[color=#%s]" % color_picker.color.to_html(false), "[/color]"))
	tools.add_child(VSeparator.new())
	_tool(tools, "Clear formatting", _clear_formatting, "Remove every tag inside the highlighted part")

	var highlighter := CodeHighlighter.new()
	highlighter.add_color_region("[", "]", Color(0.45, 0.75, 1.0))
	# Everything that isn't a tag stays plain white (the code colours would hide punctuation)
	highlighter.symbol_color = Color.WHITE
	highlighter.number_color = Color.WHITE
	highlighter.function_color = Color.WHITE
	highlighter.member_variable_color = Color.WHITE
	edit.syntax_highlighter = highlighter
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.custom_minimum_size.y = 170
	edit.add_theme_font_override("font", FONT)
	edit.add_theme_font_size_override("font_size", 16)
	edit.text_changed.connect(_on_text_changed)
	root.add_child(edit)

	var row := HBoxContainer.new()
	root.add_child(row)
	var replay := Button.new()
	replay.text = "Replay preview"
	replay.pressed.connect(_replay)
	row.add_child(replay)
	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(hide)
	row.add_child(done)

	# Preview, drawn at 2x like the game window
	var frame := ColorRect.new()
	frame.color = Color.BLACK
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.clip_contents = true
	root.add_child(frame)
	preview.scale = Vector2.ONE * PREVIEW_SCALE
	preview.position = Vector2(20, 16)
	frame.add_child(preview)
	bubble.bounds = Rect2(-1000, -1000, 4000, 4000)
	preview.add_child(bubble)
	menu_box.color = Color.BLACK
	menu_box.size = Vector2(316, 94)
	preview.add_child(menu_box)
	var border := ReferenceRect.new()
	border.border_color = Color.WHITE
	border.border_width = 2.0
	border.editor_only = false
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_box.add_child(border)
	menu_text.add_theme_font_override("normal_font", MENU_FONT)
	menu_text.position = Vector2(10, 6)
	menu_text.size = Vector2(296, 84)
	menu_text.scroll_active = false
	menu_text.clip_contents = false
	menu_box.add_child(menu_text)
	blip.stream = TXT_SOUND
	add_child(blip)


func open(ev: Dictionary) -> void:
	event = ev
	title = "Text editor - %s" % ev["params"]["kind"]
	edit.text = ev["params"]["text"]
	popup_centered()
	edit.grab_focus()
	_replay()


func _process(delta: float) -> void:
	if not visible:
		return
	if _replay_in > 0.0:
		_replay_in -= delta
		if _replay_in <= 0.0:
			_replay()
	if menu_writer.update(delta) and menu_box.visible:
		blip.play()


func _tool(parent: Control, text: String, action: Callable, tip := "") -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)


func _num(value: float) -> String:
	return str(snappedf(value, 0.01))


## Puts tags around the highlighted text (or at the cursor, with the cursor between them).
func _wrap(open: String, close: String) -> void:
	if edit.has_selection():
		var selected := edit.get_selected_text()
		edit.delete_selection()
		edit.insert_text_at_caret(open + selected + close)
	else:
		edit.insert_text_at_caret(open + close)
		edit.set_caret_column(edit.get_caret_column() - close.length())
	edit.grab_focus()


## Puts a tag just before the highlighted text (or at the cursor).
func _insert_before(tag: String) -> void:
	if edit.has_selection():
		var line := edit.get_selection_from_line()
		var column := edit.get_selection_from_column()
		edit.deselect()
		edit.set_caret_line(line)
		edit.set_caret_column(column)
	edit.insert_text_at_caret(tag)
	edit.grab_focus()


func _clear_formatting() -> void:
	if not edit.has_selection():
		return
	var tags := RegEx.create_from_string("\\[/?(%s|pause)(=[^\\]]*)?\\]" % "|".join(TextMarkup.TAGS))
	var cleaned := tags.sub(edit.get_selected_text(), "", true)
	edit.delete_selection()
	edit.insert_text_at_caret(cleaned)
	edit.grab_focus()


func _on_text_changed() -> void:
	editor.set_param(event, "text", edit.text, true)
	_replay_in = 0.4 # replay shortly after typing stops


func _replay() -> void:
	_replay_in = -1.0
	var text: String = event["params"]["text"]
	if event["params"]["kind"] == "dialogue":
		menu_box.hide()
		menu_writer.finish()
		bubble.say(text, Vector2(4, 70), SIDE_LEFT)
	else:
		bubble.hide()
		menu_box.show()
		menu_writer.start(menu_text, text, 0.02)
