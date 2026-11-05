extends Window
## The attack editor's window for Math Attack nodes: the formula, what's wrong with
## it (if anything), a slider for every number you've given a name, a live preview
## and a list of everything a formula can use.

const FONT = preload("res://fonts/PixelOperator.ttf")
const NUMBER_LINE := "^\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(-?\\d*\\.?\\d+)\\s*((#|//).*)?$"
const SLIDER_STEPS := 400.0
const GOOD := Color(0.5, 1.0, 0.6)
const BAD := Color(1.0, 0.45, 0.45)
const REFERENCE := """WHAT TO WRITE
One per line:  name = maths
It runs for every bullet, top to bottom, every frame. # starts a note.

THE GAME GIVES YOU
i  which bullet this is (0, 1, 2...)
n  how many bullets there are
u  how far through the bullets (0 to 1)
t  beats since the node started
p  how far through the node (0 to 1)
sec  seconds since the node started
soul_x, soul_y  the soul, from the board's centre
w, h  the board's size
prev_x  x of the bullet before this one
(prev_ works on any name)
pi, tau, e

YOU CAN SET
x, y  position, from the board's centre
size  how wide it's drawn (8)
angle  rotation in degrees
sx, sy  stretch (1)
r, g, b  colour, 0 to 1
hue, sat, val  colour another way
alpha  see-through, 0 to 1
show  0 hides it and turns it off
hit  hitbox width (3/4 of size)
harm  0 means it can't hurt
link  1 draws a harmful line from the last bullet
width  how thick that line is (2)

MATHS
+ - * / ^ %  and  2x  means  2 * x
< <= > >= == !=  and  or  not  give 1 or 0
when(test, yes, no)
sin cos tan asin acos atan atan2(y, x)
sinh cosh tanh sqrt abs sign exp
ln log pow(a, b) mod(a, b) fract
floor ceil round min max clamp(x, lo, hi)
lerp(a, b, f) step(edge, x) smoothstep(a, b, x)
rad deg dist(x1, y1, x2, y2)
tri square saw  (waves, like sin)
rand(x)  the same x always gives the same result
noise(x)  noise(x, y)
mandel(x, y, steps)
julia(x, y, cx, cy, steps)"""

var editor
var event: Dictionary
var edit := CodeEdit.new()
var status := Label.new()
var sliders := VBoxContainer.new()
var examples := OptionButton.new()
var preview := FormulaPreview.new()
var _number_line := RegEx.create_from_string(NUMBER_LINE)
var _slider_rows := {} # a name -> {"slider": HSlider, "value": Label, "line": int}
var _setting_text := false


## Plays the formula on a loop. Move the mouse over it to move the soul.
class FormulaPreview extends Control:
	var attack: MathAttack
	var length := 1.0
	var units_per_second := 1.0
	var bpm := 120.0
	var board := Vector2(128, 128)
	var elapsed := 0.0
	var soul := Vector2.ZERO

	func _ready() -> void:
		clip_contents = true
		mouse_filter = MOUSE_FILTER_PASS

	func _process(delta: float) -> void:
		if not is_visible_in_tree() or attack == null:
			return
		elapsed = fmod(elapsed + delta * units_per_second, maxf(length, 0.0001))
		var mouse := get_local_mouse_position()
		if Rect2(Vector2.ZERO, size).has_point(mouse):
			soul = (mouse - size / 2.0) / _zoom()
		if attack.can_run():
			attack.evaluate(elapsed, units_per_second, bpm, soul, board)
		queue_redraw()

	func _zoom() -> float:
		return minf(size.x / (board.x + 24.0), size.y / (board.y + 24.0))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		var zoom := _zoom()
		var middle := Transform2D(0.0, Vector2(zoom, zoom), 0.0, size / 2.0)
		if attack != null and attack.can_run():
			attack.draw(self, middle)
		draw_set_transform_matrix(middle)
		draw_rect(Rect2(-board / 2.0, board), Color.WHITE, false, 2.0)
		draw_circle(soul, 4.0, Color(1.0, 0.3, 0.5))


func _init() -> void:
	title = "Math Attack"
	size = Vector2i(1180, 720)
	visible = false
	wrap_controls = true
	close_requested.connect(_close)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.3
	root.add_child(left)
	var tools := HBoxContainer.new()
	left.add_child(tools)
	var example_label := Label.new()
	example_label.text = "Start from:"
	tools.add_child(example_label)
	examples.focus_mode = Control.FOCUS_NONE
	examples.add_item("Pick an example...")
	for example in MathFormula.EXAMPLES:
		examples.add_item(example["name"])
	examples.item_selected.connect(_use_example)
	tools.add_child(examples)
	var done := Button.new()
	done.text = "Done"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(_close)
	tools.add_child(done)

	var highlighter := CodeHighlighter.new()
	highlighter.add_color_region("#", "", Color(0.5, 0.6, 0.5), true)
	highlighter.add_color_region("//", "", Color(0.5, 0.6, 0.5), true)
	highlighter.number_color = Color(0.6, 0.85, 1.0)
	highlighter.symbol_color = Color(0.8, 0.8, 0.85)
	highlighter.function_color = Color(1.0, 0.75, 0.45)
	highlighter.member_variable_color = Color.WHITE
	for word in MathFormula.OUTPUTS:
		highlighter.add_keyword_color(word, Color(1.0, 0.5, 0.8))
	for word in MathFormula.COLOR_INPUTS:
		highlighter.add_keyword_color(word, Color(1.0, 0.5, 0.8))
	for word in MathFormula.INPUTS:
		highlighter.add_keyword_color(word, Color(0.7, 0.9, 0.5))
	edit.syntax_highlighter = highlighter
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_override("font", FONT)
	edit.add_theme_font_size_override("font_size", 16)
	edit.gutters_draw_line_numbers = true
	edit.text_changed.connect(_on_text_changed)
	left.add_child(edit)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 170
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sliders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sliders)
	left.add_child(scroll)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size.y = 300
	right.add_child(preview)
	var reference := Label.new()
	reference.text = REFERENCE
	reference.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reference.add_theme_font_override("font", FONT)
	reference.add_theme_font_size_override("font_size", 16)
	reference.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	reference.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reference_scroll := ScrollContainer.new()
	reference_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reference_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	reference_scroll.add_child(reference)
	right.add_child(reference_scroll)


func open(ev: Dictionary) -> void:
	event = ev
	_setting_text = true
	edit.text = str(ev["params"]["formula"])
	_setting_text = false
	examples.select(0)
	var attack: Dictionary = editor.attack_containing(ev["beat"])
	preview.board = Vector2(128, 128)
	if not attack.is_empty():
		var p: Dictionary = attack["begin"]["params"]
		preview.board = Vector2(p["width"], p["height"])
	preview.soul = Vector2.ZERO
	preview.elapsed = 0.0
	_refresh()
	popup_centered()
	edit.grab_focus()


func _close() -> void:
	hide()
	editor.inspector.refresh()


func _on_text_changed() -> void:
	if _setting_text:
		return
	editor.set_param(event, "formula", edit.text, true)
	_refresh()


func _use_example(index: int) -> void:
	if index <= 0:
		return
	var example: Dictionary = MathFormula.EXAMPLES[index - 1]
	editor.set_param(event, "count", example["count"], true)
	edit.text = example["formula"]
	editor.set_param(event, "formula", edit.text, true)
	_refresh()


func _refresh() -> void:
	preview.attack = MathAttack.new(event)
	preview.length = preview.attack.end - preview.attack.start
	preview.units_per_second = ChartDefs.units_per_second(editor.chart)
	preview.bpm = float(editor.chart["bpm"])
	_show_status(preview.attack)
	_refresh_sliders()
	for line in edit.get_line_count():
		edit.set_line_background_color(line, Color(0, 0, 0, 0))
	for problem in preview.attack.formula.errors:
		var line: int = problem["line"] - 1
		if line < edit.get_line_count():
			edit.set_line_background_color(line, Color(1.0, 0.2, 0.2, 0.25))


func _show_status(attack: MathAttack) -> void:
	var words := status_text(attack)
	status.text = words
	status.add_theme_color_override("font_color", GOOD if attack.can_run() else BAD)


## What's wrong with a formula, or how many bullets it's running.
static func status_text(attack: MathAttack) -> String:
	if not attack.formula.errors.is_empty():
		var lines := PackedStringArray()
		var problems: Array = attack.formula.errors.duplicate()
		problems.sort_custom(func(a, b): return a["line"] < b["line"])
		for problem in problems.slice(0, 3):
			lines.append("Line %d: %s" % [problem["line"], problem["message"]])
		return "\n".join(lines)
	if MathFormula.too_heavy(attack.formula, attack.count):
		return "Too heavy to run: use fewer bullets or simpler maths."
	return "OK: %d bullets." % attack.count


## A slider for every line that just gives a name a number. They only get rebuilt
## when those names change, so typing or dragging doesn't lose your place.
func _refresh_sliders() -> void:
	var found := {}
	for line in edit.get_line_count():
		var match_result := _number_line.search(edit.get_line(line))
		if match_result != null:
			found[match_result.get_string(1)] = {"line": line, "value": match_result.get_string(2).to_float()}
	if found.keys() != _slider_rows.keys():
		for child in sliders.get_children():
			sliders.remove_child(child)
			child.queue_free()
		_slider_rows.clear()
		for slider_name in found:
			_add_slider(slider_name, found[slider_name]["value"])
	for slider_name in found:
		var row: Dictionary = _slider_rows[slider_name]
		row["line"] = found[slider_name]["line"]
		row["slider"].set_value_no_signal(found[slider_name]["value"])
		row["value"].text = str(snappedf(found[slider_name]["value"], 0.001))


func _add_slider(slider_name: String, value: float) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = slider_name
	label.custom_minimum_size.x = 100
	row.add_child(label)
	var slider := HSlider.new()
	var reach := maxf(absf(value) * 3.0, 10.0 if value == 0.0 else 1.0)
	slider.min_value = -reach if value < 0.0 or value == 0.0 else 0.0
	slider.max_value = reach
	slider.step = (slider.max_value - slider.min_value) / SLIDER_STEPS
	slider.allow_greater = true
	slider.allow_lesser = true
	slider.value = value
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_slider.bind(slider_name))
	row.add_child(slider)
	var shown := Label.new()
	shown.custom_minimum_size.x = 70
	row.add_child(shown)
	sliders.add_child(row)
	_slider_rows[slider_name] = {"slider": slider, "value": shown, "line": 0}


## Writes a slider's new value back into its line of the formula.
func _on_slider(value: float, slider_name: String) -> void:
	var line: int = _slider_rows[slider_name]["line"]
	var match_result := _number_line.search(edit.get_line(line))
	if match_result == null:
		return
	var text := edit.get_line(line)
	var number := String.num(value, 3)
	_setting_text = true
	edit.set_line(line, text.substr(0, match_result.get_start(2)) + number + text.substr(match_result.get_end(2)))
	_setting_text = false
	editor.set_param(event, "formula", edit.text, true)
	_refresh()
