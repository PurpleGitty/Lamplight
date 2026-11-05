extends HBoxContainer
## The chart maker's node tabs, like Game Builder Garage's. Hover a tab and a
## column of its nodes rises from it; the mouse wheel scrolls the column. Rows
## that are groups open a second column to the side when hovered. Click a node
## to add it right after the latest one, or drag it onto the timeline.

const TAB_WIDTH := 200.0
const ROW_HEIGHT := 30.0
const STAY_OPEN_MARGIN := 6.0

var editor
var _tab_buttons: Array[Button] = []
var _column := _make_column()
var _flyout := _make_column()
var _open_tab := -1


func _ready() -> void:
	for i in ChartDefs.TABS.size():
		var tab: Dictionary = ChartDefs.TABS[i]
		var b := Button.new()
		b.text = tab["name"]
		b.custom_minimum_size = Vector2(TAB_WIDTH, ROW_HEIGHT)
		b.focus_mode = FOCUS_NONE
		_style(b, tab["color"])
		b.mouse_entered.connect(_open.bind(i))
		add_child(b)
		_tab_buttons.append(b)
	add_child(_column)
	add_child(_flyout)


func _make_column() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.top_level = true
	panel.z_index = 50
	panel.hide()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.05, 0.06)
	box.border_color = Color.BLACK
	box.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	return panel


func _rows_of(column: PanelContainer) -> VBoxContainer:
	return column.get_child(0).get_child(0)


func _process(_delta: float) -> void:
	if _open_tab < 0 or get_viewport().gui_is_dragging():
		return
	var mouse := get_global_mouse_position()
	var inside := _tab_buttons[_open_tab].get_global_rect().grow(STAY_OPEN_MARGIN).has_point(mouse)
	for column in [_column, _flyout]:
		if column.visible and column.get_global_rect().grow(STAY_OPEN_MARGIN).has_point(mouse):
			inside = true
	if not inside:
		close()


func close() -> void:
	_open_tab = -1
	_column.hide()
	_flyout.hide()


func _open(index: int) -> void:
	if index == _open_tab:
		return
	_open_tab = index
	_flyout.hide()
	var tab: Dictionary = ChartDefs.TABS[index]
	_fill(_column, tab["items"], tab["color"])
	var button := _tab_buttons[index]
	_place(_column, Vector2(button.global_position.x, button.global_position.y), tab["items"].size(), true)


func _fill(column: PanelContainer, items: Array, color: Color) -> void:
	var rows := _rows_of(column)
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for item in items:
		rows.add_child(_make_group_row(item, color) if item is Dictionary else _make_node_row(item))


## Puts a column with its bottom-left at `corner`, tall enough for its rows but
## no taller than the room above it (the rest scrolls).
func _place(column: PanelContainer, corner: Vector2, row_count: int, _is_tab: bool) -> void:
	var height := minf(row_count * ROW_HEIGHT + 4.0, corner.y - 8.0)
	column.size = Vector2(TAB_WIDTH, height)
	column.global_position = corner - Vector2(0, height)
	column.show()


func _make_node_row(type: String) -> Button:
	var def: Dictionary = ChartDefs.TYPES[type]
	var row := Button.new()
	row.text = def["label"]
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.icon = editor.icon_for(type)
	row.expand_icon = false
	row.tooltip_text = def["help"] + "\n\n[LMB] ADD AFTER THE LATEST NODE   [LMB DRAG] PLACE ON THE TIMELINE"
	row.custom_minimum_size.y = ROW_HEIGHT
	row.focus_mode = FOCUS_NONE
	_style(row, def["color"])
	row.pressed.connect(func():
		close()
		editor.add_after_latest(type))
	row.set_drag_forwarding(func(_pos): return _start_drag(type), Callable(), Callable())
	row.mouse_entered.connect(func():
		if row.get_parent() == _rows_of(_column):
			_flyout.hide())
	return row


func _make_group_row(group: Dictionary, color: Color) -> Button:
	var row := Button.new()
	row.text = "%s  >" % group["group"]
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.custom_minimum_size.y = ROW_HEIGHT
	row.focus_mode = FOCUS_NONE
	_style(row, color.darkened(0.25))
	row.mouse_entered.connect(func():
		_fill(_flyout, group["items"], color)
		var corner := Vector2(row.global_position.x + TAB_WIDTH, row.global_position.y + ROW_HEIGHT)
		_place(_flyout, corner, group["items"].size(), false))
	return row


func _start_drag(type: String) -> Dictionary:
	var def: Dictionary = ChartDefs.TYPES[type]
	var tag := Label.new()
	tag.text = def["label"]
	tag.add_theme_color_override("font_color", def["color"])
	set_drag_preview(tag)
	close()
	return {"node_type": type}


## Coloured row with black text; brighter under the mouse.
func _style(button: Button, color: Color) -> void:
	for state in [["normal", color], ["hover", color.lightened(0.3)], ["pressed", color.lightened(0.45)]]:
		var box := StyleBoxFlat.new()
		box.bg_color = state[1]
		box.border_color = Color.BLACK
		box.set_border_width_all(1)
		box.content_margin_left = 8.0
		button.add_theme_stylebox_override(state[0], box)
	for font_state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(font_state, Color.BLACK)
