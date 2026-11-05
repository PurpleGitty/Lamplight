class_name MainMenu
extends Control
## The main menu. The arrows move the soul between the options, ACCEPT picks one
## and BACK goes up a page. Scrap O' Matic leads to the editor, or to a list of
## every fight there is to play; Settings holds sound, graphics and controls. The
## title and options are placeholder text until the menu art is made.

enum Page { MAIN, SCRAP, PLAY, SETTINGS, SOUND, GRAPHICS, CONTROLS, LOCALE, LOCALE_PLAY, LOCALE_SAVES }

const TITLE_FONT = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
const OPTION_FONT = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
const SOUL = preload("res://sprites/candy_soul.png")
const ICON_CREATE = preload("res://sprites/menu/scrap_create.png")
const ICON_PLAY = preload("res://sprites/menu/scrap_play.png")
const BATTLE_SCENE := "res://node_2d.tscn"
const EDITOR_SCENE := "res://editor/attack_editor.tscn"
const LOCALE_EDITOR_SCENE := "res://editor/locale_editor.tscn"
const CHARTS_FOLDER := "res://charts/"
## The story's fights, in order. They're listed first in Play.
const CAMPAIGN_FIGHTS := ["res://charts/testicina.json"]
const TITLE_COLOR := Color("b48cff")
const DIM := Color(0.6, 0.6, 0.65)
const BAD := Color(0.9, 0.35, 0.35)
const FIRST_OPTION_Y := 230.0
const OPTION_GAP := 40.0
const SUB_FIRST_Y := 130.0
const SUB_GAP := 40.0
const CONTROL_GAP := 32.0
const ICON_SCALE := 4.0
const ICON_Y := 150.0
const ICON_CENTERS := [180.0, 460.0]
const FIRST_ROW_Y := 96.0
const ROW_GAP := 44.0
const VISIBLE_ROWS := 7
const VOLUME_STEP := 5
const BIND_NAME_WIDTH := 7
const BIND_WIDTH := 11
const AFTER_REBIND_PAUSE_MS := 250
## Which page and option BACK goes to from each page.
const PARENTS := {
	Page.SCRAP: [Page.MAIN, 1], Page.PLAY: [Page.SCRAP, 1], Page.LOCALE: [Page.MAIN, 2], Page.LOCALE_PLAY: [Page.LOCALE, 1], Page.LOCALE_SAVES: [Page.LOCALE_PLAY, 0], Page.SETTINGS: [Page.MAIN, 3],
	Page.SOUND: [Page.SETTINGS, 0], Page.GRAPHICS: [Page.SETTINGS, 1], Page.CONTROLS: [Page.SETTINGS, 2],
}

## The phone's menu has no editor pages in the way.
const MOBILE_PARENTS := {Page.PLAY: [Page.MAIN, 1], Page.LOCALE_PLAY: [Page.MAIN, 2], Page.SETTINGS: [Page.MAIN, 3]}

## The page to come back to from a fight or the editor.
static var page := Page.MAIN
## The overworld whose saves are listed.
static var locale_path := ""

var selected := 0
## Each is {"label", "action", "leaves"}, and can have "note", "icon", "adjust" (for
## left/right), "text" (a function giving its current text), "bind" (an action name).
var options: Array = []
var soul := Sprite2D.new()
var move_sound := AudioStreamPlayer.new()
var select_sound := AudioStreamPlayer.new()
var back_sound := AudioStreamPlayer.new()
var page_root := Control.new()
var _hint_label: Label
var _hint_pairs: Array = []
var _rows_top := 0 # first row showing on a page too long to fit
var _soul_tween: Tween
var _leaving := false
var _bind_column := 0 # controls page: 0 = keyboard, 1 = controller
var _rebinding := "" # the action waiting for a new control
var _ignore_input_until := 0


func _ready() -> void:
	Battle.chart_to_play = "" # the campaign plays its own charts
	Battle.return_scene = ""
	Battle.overworld_party = {}
	Overworld.resume = null
	ScrapFile.clear_cache() # nothing's playing or being edited now
	# The editor switches the window to full resolution; put the game's view back
	GameSettings.apply_game_view()
	var window := get_window()
	window.title = ProjectSettings.get_setting("application/config/name")

	set_anchors_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	add_child(page_root)

	soul.texture = SOUL
	soul.hframes = 2
	soul.scale = Vector2(2, 2)
	soul.z_index = 1
	add_child(soul)
	move_sound.stream = preload("res://sounds/lightningbulb-spacebar-click-keyboard-199448.mp3")
	select_sound.stream = preload("res://sounds/creatorshome-video-game-select-337214.mp3")
	back_sound.stream = preload("res://sounds/freesound_community-cancel-36118.mp3")
	add_child(move_sound)
	add_child(select_sound)
	add_child(back_sound)
	_add_version_label()
	GameSettings.device_changed.connect(_refresh_prompts)
	_open_page(page)


## The version, in the bottom right corner of every page.
func _add_version_label() -> void:
	var label := Label.new()
	label.text = ProjectSettings.get_setting("application/config/version", "")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_override("font", OPTION_FONT)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", DIM)
	label.size = Vector2(160, 16)
	label.position = Vector2(632 - label.size.x, 464)
	add_child(label)


# --- pages ---

func _open_page(new_page: Page, start_on := 0) -> void:
	page = new_page
	for child in page_root.get_children():
		child.queue_free()
	options = []
	_rows_top = 0
	_hint_label = null
	_rebinding = ""
	match page:
		Page.MAIN: _build_main()
		Page.SCRAP: _build_scrap()
		Page.PLAY: _build_play()
		Page.SETTINGS: _build_settings()
		Page.SOUND: _build_sound()
		Page.GRAPHICS: _build_graphics()
		Page.CONTROLS: _build_controls()
		Page.LOCALE: _build_locale()
		Page.LOCALE_PLAY: _build_locale_play()
		Page.LOCALE_SAVES: _build_locale_saves()
	_select(start_on, false)


func _build_main() -> void:
	_title("LAMPLIGHT", 48, 110)
	var picks := [
		["CAMPAIGN", func(): GameSettings.go_to(BATTLE_SCENE), true],
		["SCRAPS", func(): _open_page(Page.PLAY), false],
		["OVERWORLDS", func(): _open_page(Page.LOCALE_PLAY), false],
		["SETTINGS", func(): _open_page(Page.SETTINGS), false],
		["QUIT", func(): get_tree().quit(), true],
	] if GameSettings.mobile else [
		["CAMPAIGN", func(): GameSettings.go_to(BATTLE_SCENE), true],
		["SCRAP O' MATIC", func(): _open_page(Page.SCRAP), false],
		["LOCALE-INATOR", func(): _open_page(Page.LOCALE), false],
		["SETTINGS", func(): _open_page(Page.SETTINGS), false],
		["QUIT", func(): get_tree().quit(), true],
	]
	for i in picks.size():
		var label := _label(picks[i][0], OPTION_FONT, 16, FIRST_OPTION_Y + i * OPTION_GAP)
		_add_option(label, picks[i][1], picks[i][2])


func _build_scrap() -> void:
	_title("SCRAP O' MATIC", 32, 70)
	_icon_option(0, "CREATE + EDIT", ICON_CREATE, func(): GameSettings.go_to(EDITOR_SCENE), true)
	_icon_option(1, "PLAY", ICON_PLAY, func(): _open_page(Page.PLAY), false)
	_hint([["ACCEPT", "PICK"], ["BACK", "BACK"]])


func _build_locale() -> void:
	_title("LOCALE-INATOR", 32, 70)
	_icon_option(0, "CREATE + EDIT", ICON_CREATE, func(): GameSettings.go_to(LOCALE_EDITOR_SCENE), true)
	_icon_option(1, "PLAY", ICON_PLAY, func(): _open_page(Page.LOCALE_PLAY), false)
	_hint([["ACCEPT", "PICK"], ["BACK", "BACK"]])


func _build_locale_play() -> void:
	_title("PLAY", 32, 40)
	for path in LocaleFile.list():
		var chosen: String = path
		_add_row(chosen.get_file().get_basename().to_upper(), "OVERWORLD", DIM, func(): _pick_locale(chosen), false)
	if GameSettings.mobile:
		_add_row("IMPORT A FILE", "Pick a .scrp or .lcal from your phone", DIM, _import_file, false)
	else:
		_add_row("OPEN LOCALES FOLDER", "Put .lcal files here to play them", DIM, func(): OS.shell_open(ProjectSettings.globalize_path(LocaleFile.folder())), false)
	_add_row("BACK", "", DIM, _go_back, false)
	_hint([["ACCEPT", "PLAY"], ["BACK", "BACK"]])


## With saves to continue from, lists them. Otherwise, starts right away.
func _pick_locale(path: String) -> void:
	locale_path = path
	if SaveGame.has_any(LocaleFile.peek(path)):
		_open_page(Page.LOCALE_SAVES)
	else:
		_start_locale(-1)


func _build_locale_saves() -> void:
	_title(locale_path.get_file().get_basename().to_upper(), 32, 40)
	var locale := LocaleFile.peek(locale_path)
	_add_row("NEW GAME", "From the very start", DIM, func(): _start_locale(-1), true)
	for slot in [SaveGame.AUTOSAVE_SLOT] + SaveGame.SLOTS:
		if not SaveGame.read(locale, slot).is_empty():
			var chosen: int = slot
			_add_row(SaveGame.describe(locale, slot), "Continue", DIM, func(): _start_locale(chosen), true)
	_add_row("BACK", "", DIM, _go_back, false)
	_hint([["ACCEPT", "PICK"], ["BACK", "BACK"]])


func _start_locale(slot: int) -> void:
	Overworld.return_scene = "res://menu.tscn"
	Overworld.test_room = -1
	Overworld.test_spawn = Vector2.INF
	var scene := Overworld.play(locale_path)
	Overworld.load_slot = slot
	GameSettings.go_to(scene)


func _icon_option(index: int, text: String, texture: Texture2D, action: Callable, leaves: bool) -> void:
	var center: float = ICON_CENTERS[index]
	var icon := TextureRect.new()
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = texture.get_size() * ICON_SCALE
	icon.position = Vector2(center - icon.size.x / 2.0, ICON_Y)
	page_root.add_child(icon)
	var label := _label(text, OPTION_FONT, 16, ICON_Y + icon.size.y + 34.0)
	label.size.x = 280.0
	label.position.x = center - 140.0
	var option := _add_option(label, action, leaves)
	option["icon"] = icon


func _build_play() -> void:
	_title("PLAY", 32, 40)
	for fight in _all_fights():
		_add_fight_row(fight)
	if GameSettings.mobile:
		_add_row("IMPORT A FILE", "Pick a .scrp or .lcal from your phone", DIM, _import_file, false)
	else:
		_add_row("OPEN SCRAPS FOLDER", "Put .scrp files here to play them", DIM, func(): OS.shell_open(ProjectSettings.globalize_path(ScrapFile.folder())), false)
	_add_row("BACK", "", DIM, _go_back, false)
	_hint([["ACCEPT", "PLAY"], ["BACK", "BACK"]])


## Everything to play: the campaign first, then charts from the game's folder,
## then the player's scraps.
func _all_fights() -> Array:
	var fights := []
	for path in CAMPAIGN_FIGHTS:
		fights.append({"path": path, "tag": "CAMPAIGN", "chart": ChartDefs.load_chart(path)})
	for file_name in DirAccess.get_files_at(CHARTS_FOLDER):
		var path: String = CHARTS_FOLDER + file_name
		if path.get_extension() != "json" or path in CAMPAIGN_FIGHTS:
			continue
		var chart := ChartDefs.load_chart(path)
		# Blank starter charts have nothing to play
		if not chart.is_empty() and not chart["turn_events"].is_empty():
			fights.append({"path": path, "tag": "", "chart": chart})
	for path in ScrapFile.list():
		var chart := ScrapFile.peek(path)
		fights.append({"path": path, "tag": "", "chart": chart, "error": ScrapFile.last_error})
	return fights


func _add_fight_row(fight: Dictionary) -> void:
	var path: String = fight["path"]
	var chart: Dictionary = fight["chart"]
	var title := path.get_file().get_basename().capitalize().to_upper()
	if chart.is_empty():
		_add_row(title, fight.get("error", "Couldn't read this file."), BAD, func(): pass, false)
		return
	var foes: Array = chart["enemies"].map(func(e): return e["name"])
	var detail := "VS %s" % ", ".join(foes) if not foes.is_empty() else "NO ENEMIES"
	if fight["tag"] != "":
		detail = "%s - %s" % [fight["tag"], detail]
	_add_row(title, detail, DIM, func(): _play(path), true)


func _add_row(text: String, detail: String, detail_color: Color, action: Callable, leaves: bool) -> void:
	var label := _label(_fit(text, 30), OPTION_FONT, 16, 0.0)
	var note := _label(_fit(detail, 60), OPTION_FONT, 8, 0.0)
	note.add_theme_color_override("font_color", detail_color)
	var option := _add_option(label, action, leaves)
	option["note"] = note


func _fit(text: String, limit: int) -> String:
	return text if text.length() <= limit else text.left(limit - 3) + "..."


func _play(path: String) -> void:
	Battle.chart_to_play = path
	GameSettings.go_to(BATTLE_SCENE)


## The phone's own file picker. Copies what's picked in; the game only ever reads it.
func _import_file() -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.use_native_dialog = true
	dialog.file_selected.connect(func(path):
		var placed := LocaleFile.import_file(path)
		_open_page(page)
		_set_hint(placed.get_file() + " added" if placed != "" else LocaleFile.last_error))
	add_child(dialog)
	dialog.popup_centered()


func _build_settings() -> void:
	_title("SETTINGS", 32, 60)
	var picks := [["SOUND", Page.SOUND], ["GRAPHICS", Page.GRAPHICS], ["CONTROLS", Page.CONTROLS]]
	for i in picks.size():
		var label := _label(picks[i][0], OPTION_FONT, 16, SUB_FIRST_Y + i * SUB_GAP)
		var target: Page = picks[i][1]
		_add_option(label, func(): _open_page(target), false)
	_add_option(_label("BACK", OPTION_FONT, 16, SUB_FIRST_Y + picks.size() * SUB_GAP), _go_back, false)
	_hint([["ACCEPT", "PICK"], ["BACK", "BACK"]])


func _build_sound() -> void:
	_title("SOUND", 32, 60)
	var rows := [["MASTER", "master_volume"], ["MUSIC", "music_volume"], ["EFFECTS", "sfx_volume"]]
	for i in rows.size():
		var key: String = rows[i][1]
		var text: String = rows[i][0]
		_setting_row(i, func(): return "%s  %d%%" % [text, GameSettings.values[key]], func(step: int):
			GameSettings.change(key, clampi(GameSettings.values[key] + step * VOLUME_STEP, 0, 100)))
	var extra := 0
	if GameSettings.mobile:
		# The beat can be nudged to match what's heard: Bluetooth headphones need much more
		extra = 1
		_setting_row(rows.size(), func(): return "AUDIO DELAY  %d MS" % GameSettings.audio_delay_ms(), func(step: int):
			GameSettings.change("audio_delay_ms", clampi(GameSettings.audio_delay_ms() + step * 10, 0, 500)))
	_add_option(_label("BACK", OPTION_FONT, 16, SUB_FIRST_Y + (rows.size() + extra) * SUB_GAP), _go_back, false)
	_hint([["LEFT", ""], ["RIGHT", "CHANGE"], ["BACK", "BACK"]])


## Phones: fewer settings, and effects can be turned off to read better and run faster.
func _build_mobile_graphics() -> void:
	_title("GRAPHICS", 32, 60)
	_setting_row(0, func(): return "FPS LIMIT  %d" % GameSettings.values["fps"], func(step: int):
		GameSettings.change("fps", _cycled(GameSettings.FPS_LIMITS.filter(func(f): return f <= 60), GameSettings.values["fps"], step)))
	var toggles := [["PIXEL PERFECT", "pixel_perfect"], ["SHAKING", "screen_shake"], ["SHADOWS", "fx_shadows"], ["BACKGROUNDS", "fx_backgrounds"], ["DUST + TRAILS", "fx_trails"]]
	for i in toggles.size():
		var words: String = toggles[i][0]
		var key: String = toggles[i][1]
		_setting_row(i + 1, func(): return "%s  %s" % [words, _on_off(key)], func(_step: int):
			GameSettings.change(key, not GameSettings.values[key]))
	_add_option(_label("BACK", OPTION_FONT, 16, SUB_FIRST_Y + 6 * SUB_GAP), _go_back, false)
	_hint([["LEFT", ""], ["RIGHT", "CHANGE"], ["BACK", "BACK"]])


## Phones: how the on-screen controls work. A controller just works, with no setup.
func _build_mobile_controls() -> void:
	_title("CONTROLS", 32, 60)
	_setting_row(0, func(): return "STICK  %s" % GameSettings.values["touch_stick"], func(step: int):
		GameSettings.change("touch_stick", _cycled(GameSettings.TOUCH_STICKS, GameSettings.values["touch_stick"], step)))
	_setting_row(1, func(): return "BUTTON SIZE  %s" % GameSettings.values["touch_size"], func(step: int):
		GameSettings.change("touch_size", _cycled(GameSettings.TOUCH_SIZES, GameSettings.values["touch_size"], step)))
	_setting_row(2, func(): return "BUTTON OPACITY  %d%%" % GameSettings.values["touch_opacity"], func(step: int):
		GameSettings.change("touch_opacity", clampi(GameSettings.values["touch_opacity"] + step * 25, 25, 100)))
	_setting_row(3, func(): return "TAP MENUS  %s" % _on_off("finger_ui"), func(_step: int):
		GameSettings.change("finger_ui", not GameSettings.values["finger_ui"]))
	_setting_row(4, func(): return "AUTO RUN  %s" % _on_off("auto_run"), func(_step: int):
		GameSettings.change("auto_run", not GameSettings.values["auto_run"]))
	_add_option(_label("BACK", OPTION_FONT, 16, SUB_FIRST_Y + 5 * SUB_GAP), _go_back, false)
	_hint([["LEFT", ""], ["RIGHT", "CHANGE"], ["BACK", "BACK"]])


func _build_graphics() -> void:
	if GameSettings.mobile:
		_build_mobile_graphics()
		return
	_title("GRAPHICS", 32, 60)
	_setting_row(0, func(): return "WINDOW  %s" % GameSettings.values["window_mode"], func(step: int):
		GameSettings.change("window_mode", _cycled(GameSettings.WINDOW_MODES, GameSettings.values["window_mode"], step)))
	_setting_row(1, func(): return "VSYNC  %s" % _on_off("vsync"), func(_step: int):
		GameSettings.change("vsync", not GameSettings.values["vsync"]))
	_setting_row(2, func(): return "FPS LIMIT  %d" % GameSettings.values["fps"], func(step: int):
		GameSettings.change("fps", _cycled(GameSettings.FPS_LIMITS, GameSettings.values["fps"], step)))
	_setting_row(3, func(): return "PIXEL PERFECT  %s" % _on_off("pixel_perfect"), func(_step: int):
		GameSettings.change("pixel_perfect", not GameSettings.values["pixel_perfect"]))
	_setting_row(4, func(): return "SHAKING  %s" % _on_off("screen_shake"), func(_step: int):
		GameSettings.change("screen_shake", not GameSettings.values["screen_shake"]))
	_add_option(_label("BACK", OPTION_FONT, 16, SUB_FIRST_Y + 5 * SUB_GAP), _go_back, false)
	_hint([["LEFT", ""], ["RIGHT", "CHANGE"], ["BACK", "BACK"]])


func _on_off(key: String) -> String:
	return "ON" if GameSettings.values[key] else "OFF"


func _cycled(list: Array, current: Variant, step: int) -> Variant:
	return list[wrapi(list.find(current) + step, 0, list.size())]


## A row whose value changes with left and right.
func _setting_row(index: int, text: Callable, adjust: Callable) -> void:
	var label := _label(text.call(), OPTION_FONT, 16, SUB_FIRST_Y + index * SUB_GAP)
	var option := _add_option(label, func(): pass, false)
	option["text"] = text
	option["adjust"] = adjust


func _build_controls() -> void:
	if GameSettings.mobile:
		_build_mobile_controls()
		return
	_title("CONTROLS", 32, 40)
	var y := 84.0
	var heading := _label(_bind_line("", "KEYBOARD", "CONTROLLER"), OPTION_FONT, 16, y)
	heading.add_theme_color_override("font_color", DIM)
	y += CONTROL_GAP
	for action in GameSettings.ACTIONS:
		var name_text: String = action
		var option := _add_option(_label("", OPTION_FONT, 16, y), func(): _start_rebind(name_text), false)
		option["bind"] = name_text
		option["text"] = _bind_text.bind(name_text)
		y += CONTROL_GAP
	var auto_run := func(_step := 0):
		GameSettings.change("auto_run", not GameSettings.values["auto_run"])
		_refresh_texts()
	var auto_text := func(): return "AUTO RUN  %s" % _on_off("auto_run")
	var auto_option := _add_option(_label(auto_text.call(), OPTION_FONT, 16, y), auto_run, false)
	auto_option["text"] = auto_text
	auto_option["adjust"] = auto_run
	y += CONTROL_GAP
	_add_option(_label("RESET CONTROLS", OPTION_FONT, 16, y), _reset_controls, false)
	y += CONTROL_GAP
	_add_option(_label("BACK", OPTION_FONT, 16, y), _go_back, false)
	_controls_hint()
	_refresh_texts()


func _controls_hint() -> void:
	if _rebinding != "":
		_hint_pairs = []
		_set_hint("[ESC] CANCEL")
		return
	_hint([["ACCEPT", "CHANGE"], ["LEFT", ""], ["RIGHT", "SWITCH COLUMN"], ["BACK", "BACK"]])


func _bind_line(action: String, key_name: String, pad_name: String) -> String:
	return "%s %s %s" % [action.rpad(BIND_NAME_WIDTH), _fit(key_name, BIND_WIDTH).rpad(BIND_WIDTH), _fit(pad_name, BIND_WIDTH).rpad(BIND_WIDTH)]


## A control row, with arrows around the column being edited on the chosen row.
func _bind_text(action: String) -> String:
	var names: Array = []
	for i in GameSettings.COLUMNS.size():
		var shown: String = GameSettings.binding_name(action, GameSettings.COLUMNS[i])
		if options[selected].get("bind", "") == action and i == _bind_column:
			shown = "PRESS..." if _rebinding == action else ">" + shown
		names.append(shown)
	return _bind_line(action, names[0], names[1])


func _start_rebind(action: String) -> void:
	_rebinding = action
	_controls_hint()
	_refresh_texts()


func _finish_rebind() -> void:
	_rebinding = ""
	_ignore_input_until = Time.get_ticks_msec() + AFTER_REBIND_PAUSE_MS
	_controls_hint()
	_refresh_texts()


func _reset_controls() -> void:
	GameSettings.reset_controls()
	_refresh_prompts()
	_refresh_texts()


## A finger on a row picks it. On a setting, the left half lowers it and the right raises it.
func _menu_tap(tap: Vector2) -> void:
	if _leaving:
		return
	for i in options.size():
		var option: Dictionary = options[i]
		var hit: bool = GameSettings.tap_hits(option["label"], tap)
		if option.has("icon"):
			hit = hit or GameSettings.tap_hits(option["icon"], tap)
		if not hit:
			continue
		_select(i, false)
		if option.has("adjust"):
			_adjust(1 if tap.x > 320.0 else -1)
		else:
			_choose()
		return


## The press after choosing a control to change.
func _input(event: InputEvent) -> void:
	var tap := GameSettings.tap_at(event)
	if tap != Vector2.INF:
		_menu_tap(tap)
		get_viewport().set_input_as_handled()
		return
	if _rebinding == "":
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_finish_rebind()
		return
	var binding: Variant = GameSettings.binding_from(event, GameSettings.COLUMNS[_bind_column])
	if binding == null:
		if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled() # the other column's controls do nothing here
		return
	get_viewport().set_input_as_handled()
	GameSettings.rebind(_rebinding, GameSettings.COLUMNS[_bind_column], binding)
	select_sound.play()
	_finish_rebind()


func _title(text: String, font_size: int, y: float) -> void:
	_label(text, TITLE_FONT, font_size, y).add_theme_color_override("font_color", TITLE_COLOR)


func _add_option(label: Label, action: Callable, leaves: bool) -> Dictionary:
	var option := {"label": label, "action": action, "leaves": leaves}
	options.append(option)
	return option


func _label(text: String, font: Font, font_size: int, y: float) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.size = Vector2(640, font_size + 8)
	label.position = Vector2(0, y - label.size.y / 2)
	page_root.add_child(label)
	return label


## Control prompts along the bottom. They follow whichever device is in use.
func _hint(pairs: Array) -> void:
	_hint_pairs = pairs
	_set_hint(_hint_text())


func _set_hint(text: String) -> void:
	if _hint_label == null:
		_hint_label = _label("", OPTION_FONT, 8, 456.0)
		_hint_label.add_theme_color_override("font_color", DIM)
	_hint_label.text = text


## A pair with no words runs straight on to the next: [LEFT] [RIGHT] CHANGE
func _hint_text() -> String:
	return GameSettings.hint(_hint_pairs).replace("    [", "  [") if _hint_pairs.size() <= 1 else _joined_hint()


func _joined_hint() -> String:
	var text := ""
	for pair in _hint_pairs:
		text += GameSettings.prompt(pair[0])
		text += " " if pair[1] == "" else " %s    " % pair[1]
	return text.strip_edges()


func _refresh_prompts() -> void:
	if _hint_label and not _hint_pairs.is_empty():
		_set_hint(_hint_text())


func _update_texts() -> void:
	for option in options:
		if option.has("text"):
			option["label"].text = option["text"].call()


func _refresh_texts() -> void:
	_update_texts()
	_place_soul(false)


# --- selecting ---

func _select(index: int, animate := true) -> void:
	selected = wrapi(index, 0, options.size())
	_scroll_rows()
	for i in options.size():
		var option: Dictionary = options[i]
		option["label"].add_theme_color_override("font_color", Color.YELLOW if i == selected else Color.WHITE)
		if option.has("icon"):
			option["icon"].modulate = Color.WHITE if i == selected else Color(0.5, 0.5, 0.55)
	_update_texts()
	_place_soul(animate)


## The soul sits just left of the chosen option, clear of any note under it, and
## level with the middle of its text.
func _place_soul(animate: bool) -> void:
	var option: Dictionary = options[selected]
	var label: Label = option["label"]
	var text_width := OPTION_FONT.get_string_size(label.text.strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	if option.has("note"):
		text_width = maxf(text_width, OPTION_FONT.get_string_size(option["note"].text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
	var center := label.position.x + label.size.x / 2.0
	var full_width := OPTION_FONT.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var left := center - maxf(text_width, full_width) / 2.0
	var target := Vector2(left - 22.0, label.position.y + label.size.y / 2.0)
	if _soul_tween:
		_soul_tween.kill()
	if animate:
		_soul_tween = create_tween()
		_soul_tween.tween_property(soul, "position", target, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		soul.position = target


## Lays out a long list so the chosen row is always showing.
func _scroll_rows() -> void:
	if page not in [Page.PLAY, Page.LOCALE_PLAY, Page.LOCALE_SAVES]:
		return
	_rows_top = clampi(_rows_top, selected - VISIBLE_ROWS + 1, selected)
	_rows_top = clampi(_rows_top, 0, maxi(options.size() - VISIBLE_ROWS, 0))
	for i in options.size():
		var row := i - _rows_top
		var showing := row >= 0 and row < VISIBLE_ROWS
		var label: Label = options[i]["label"]
		var note: Label = options[i]["note"]
		label.visible = showing
		note.visible = showing
		label.position.y = FIRST_ROW_Y + row * ROW_GAP - label.size.y / 2.0
		note.position.y = label.position.y + label.size.y - 2.0


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or _rebinding != "" or Time.get_ticks_msec() < _ignore_input_until:
		return
	var sideways := page in [Page.SCRAP, Page.LOCALE]
	var forward := GameSettings.pressed(event, "DOWN") or (sideways and GameSettings.pressed(event, "RIGHT"))
	var backward := GameSettings.pressed(event, "UP") or (sideways and GameSettings.pressed(event, "LEFT"))
	if forward:
		move_sound.play()
		_select(selected + 1)
	elif backward:
		move_sound.play()
		_select(selected - 1)
	elif GameSettings.pressed(event, "LEFT"):
		_adjust(-1)
	elif GameSettings.pressed(event, "RIGHT"):
		_adjust(1)
	elif GameSettings.pressed(event, "ACCEPT"):
		_choose()
	elif GameSettings.pressed(event, "BACK"):
		_go_back()


## Left or right: changes the chosen setting, or the controls column.
func _adjust(step: int) -> void:
	var option: Dictionary = options[selected]
	if option.has("bind"):
		_bind_column = wrapi(_bind_column + step, 0, GameSettings.COLUMNS.size())
	elif option.has("adjust"):
		option["adjust"].call(step)
	else:
		return
	move_sound.play()
	_refresh_texts()


func _go_back() -> void:
	if not PARENTS.has(page):
		return
	back_sound.play()
	var parent: Array = PARENTS[page]
	if GameSettings.mobile and MOBILE_PARENTS.has(page):
		parent = MOBILE_PARENTS[page]
	_open_page(parent[0], parent[1])


func _choose() -> void:
	var option: Dictionary = options[selected]
	if option["action"] == _go_back:
		_go_back()
		return
	select_sound.play()
	if option.has("adjust"):
		option["adjust"].call(1)
		_refresh_texts()
		return
	if not option["leaves"]:
		option["action"].call()
		return
	_leaving = true
	# Flash the soul before leaving
	var t := create_tween()
	for i in 3:
		t.tween_callback(func(): soul.frame = 1)
		t.tween_interval(0.06)
		t.tween_callback(func(): soul.frame = 0)
		t.tween_interval(0.06)
	await t.finished
	option["action"].call()
