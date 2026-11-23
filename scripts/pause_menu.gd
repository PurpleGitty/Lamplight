class_name PauseMenu
extends CanvasLayer
## MENU or Escape in a fight: everything stops, the song too unless the scrap's rules
## keep it going, and this comes up to carry on, start again, change settings or leave.

const FONT = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
const MENU_SCENE := "res://scenes/menu.tscn"
const TEXT_SIZE := 16
const ROW_GAP := 32.0
const PANEL := Rect2(176, 108, 288, 264)
const PICKED := Color.YELLOW
const UNPICKED := Color.WHITE
const DIM := Color(0.6, 0.6, 0.65)

var battle: Battle
var _open := false
var _rows: Array = [] # {"id", "text", "label"}
var _at := 0
var _confirming := "" # a quit that needs pressing twice
var _settings: Control
var _settings_layer: CanvasLayer
var _root := Control.new()
var _hint: Label
var _music_was := PROCESS_MODE_INHERIT
var _menu_page_was := 0
var _sounds := {} # "move", "select", "back" -> a player that works while paused


func _ready() -> void:
	layer = 50
	process_mode = PROCESS_MODE_ALWAYS
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.hide()
	add_child(_root)
	for sound in ["move", "select", "back"]:
		var player := AudioStreamPlayer.new()
		_sounds[sound] = player
		add_child(player)


## The fight's own menu sounds, which a scrap can change.
func _play(sound: String) -> void:
	var player: AudioStreamPlayer = _sounds[sound]
	var node_name: String = {"move": "LightningbulbSpacebarClickKeyboard199448", "select": "Select", "back": "Deselect"}[sound]
	var source := battle.get_node_or_null(NodePath(node_name)) as AudioStreamPlayer
	if source != null:
		player.stream = source.stream
		player.bus = source.bus
		player.volume_db = source.volume_db
	player.play()


func is_open() -> bool:
	return _open


func _can_pause() -> bool:
	return battle != null and battle.phase != Battle.Phase.OVER and not get_tree().paused


func _unhandled_input(event: InputEvent) -> void:
	if _settings != null:
		return # the settings pages handle their own controls
	var pause_key: bool = GameSettings.pressed(event, "MENU") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE)
	if not _open:
		if pause_key and _can_pause():
			get_viewport().set_input_as_handled()
			open()
		return
	get_viewport().set_input_as_handled()
	var tap := GameSettings.tap_at(event)
	if tap != Vector2.INF:
		for i in _rows.size():
			if GameSettings.tap_hits(_rows[i]["label"], tap):
				_at = i
				_choose()
				return
		return
	if pause_key or GameSettings.pressed(event, "BACK"):
		_play("back")
		if _confirming != "":
			_confirming = ""
			_refresh()
		else:
			close()
	elif GameSettings.pressed(event, "UP"):
		_move(-1)
	elif GameSettings.pressed(event, "DOWN"):
		_move(1)
	elif GameSettings.pressed(event, "ACCEPT"):
		_choose()


func open() -> void:
	_open = true
	_at = 0
	_confirming = ""
	get_tree().paused = true
	# The song can keep going, if the scrap says so
	var music := battle.conductor.player
	if music != null:
		_music_was = music.process_mode
		if bool(battle.rules.get("music_while_paused", false)):
			music.process_mode = PROCESS_MODE_ALWAYS
	_build()
	_root.show()
	_play("select")


func close() -> void:
	_open = false
	_root.hide()
	var music := battle.conductor.player
	if music != null:
		music.process_mode = _music_was
	# A frame later, so the press that closed this doesn't also count in the fight
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false


func _build() -> void:
	for child in _root.get_children():
		child.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK
	style.border_color = Color.WHITE
	style.set_border_width_all(4)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.position = PANEL.position
	panel.size = PANEL.size
	_root.add_child(panel)
	_label(panel, "PAUSED", 24.0, Color("b48cff"), 24)
	_rows = [{"id": "resume", "text": "RESUME"}, {"id": "restart", "text": "RESTART"}, {"id": "settings", "text": "SETTINGS"}, {"id": "menu", "text": "QUIT TO MENU"}]
	if not GameSettings.mobile:
		_rows.append({"id": "quit", "text": "QUIT GAME"})
	for i in _rows.size():
		_rows[i]["label"] = _label(panel, _rows[i]["text"], 72.0 + i * ROW_GAP, UNPICKED)
	_hint = _label(panel, "", PANEL.size.y - 30.0, DIM, 8)
	_refresh()


func _label(parent: Control, text: String, y: float, color: Color, font_size := TEXT_SIZE) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.position = Vector2(0, y)
	label.size = Vector2(PANEL.size.x, font_size + 8)
	parent.add_child(label)
	return label


func _refresh() -> void:
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var label: Label = row["label"]
		label.text = "PRESS AGAIN" if row["id"] == _confirming else row["text"]
		label.add_theme_color_override("font_color", PICKED if i == _at else UNPICKED)
	if _hint != null:
		_hint.text = GameSettings.hint([["ACCEPT", "PICK"], ["MENU", "RESUME"]])


func _move(step: int) -> void:
	_at = wrapi(_at + step, 0, _rows.size())
	_confirming = ""
	_play("move")
	_refresh()


func _choose() -> void:
	var id: String = _rows[_at]["id"]
	_play("back" if id == "resume" else "select")
	match id:
		"resume":
			close()
		"restart":
			get_tree().paused = false
			GameSettings.reload_scene()
		"settings":
			_open_settings()
		"menu", "quit":
			# Leaving loses the fight (and an overworld's unsaved progress), so it's asked twice
			if _confirming != id:
				_confirming = id
				_refresh()
				return
			get_tree().paused = false
			if id == "quit":
				get_tree().quit()
			else:
				GameSettings.go_to(MENU_SCENE)


## The main menu's own Settings pages, over the paused fight.
func _open_settings() -> void:
	_root.hide()
	_menu_page_was = MainMenu.page
	_settings_layer = CanvasLayer.new()
	_settings_layer.layer = 60
	_settings_layer.process_mode = PROCESS_MODE_ALWAYS
	add_child(_settings_layer)
	var menu: MainMenu = load(MENU_SCENE).instantiate()
	menu.embedded = true
	menu.closed.connect(_close_settings)
	_settings = menu
	_settings_layer.add_child(menu)


func _close_settings() -> void:
	MainMenu.page = _menu_page_was
	_settings_layer.queue_free()
	_settings_layer = null
	get_viewport().set_input_as_handled() # the BACK that left Settings shouldn't also close this
	_settings = null
	_build()
	_at = 2
	_refresh()
	_root.show()
