extends Node
## The player's settings (autoload: GameSettings): controls, volume and graphics,
## saved between sessions. Everything that reads input goes through the actions
## set up here, so keyboard and controller both work and both can be remapped.

signal device_changed

const PATH := "user://settings.cfg"
const ACTIONS := ["UP", "DOWN", "LEFT", "RIGHT", "ACCEPT", "BACK", "MENU"]
const COLUMNS := ["key", "pad"]
const DEFAULT_KEYS := {"UP": KEY_UP, "DOWN": KEY_DOWN, "LEFT": KEY_LEFT, "RIGHT": KEY_RIGHT, "ACCEPT": KEY_Z, "BACK": KEY_X, "MENU": KEY_C}
const DEFAULT_PAD := {
	"UP": {"button": JOY_BUTTON_DPAD_UP}, "DOWN": {"button": JOY_BUTTON_DPAD_DOWN},
	"LEFT": {"button": JOY_BUTTON_DPAD_LEFT}, "RIGHT": {"button": JOY_BUTTON_DPAD_RIGHT},
	"ACCEPT": {"button": JOY_BUTTON_A}, "BACK": {"button": JOY_BUTTON_B}, "MENU": {"button": JOY_BUTTON_Y},
}
## The left stick always moves, whatever the d-pad is remapped to.
const STICK := {
	"UP": [JOY_AXIS_LEFT_Y, -1.0], "DOWN": [JOY_AXIS_LEFT_Y, 1.0],
	"LEFT": [JOY_AXIS_LEFT_X, -1.0], "RIGHT": [JOY_AXIS_LEFT_X, 1.0],
}
const STICK_DEADZONE := 0.5
const BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "VIEW", JOY_BUTTON_GUIDE: "HOME", JOY_BUTTON_START: "MENU",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "DPAD UP", JOY_BUTTON_DPAD_DOWN: "DPAD DOWN",
	JOY_BUTTON_DPAD_LEFT: "DPAD LEFT", JOY_BUTTON_DPAD_RIGHT: "DPAD RIGHT",
}
const AXIS_NAMES := {
	JOY_AXIS_LEFT_X: ["LS LEFT", "LS RIGHT"], JOY_AXIS_LEFT_Y: ["LS UP", "LS DOWN"],
	JOY_AXIS_RIGHT_X: ["RS LEFT", "RS RIGHT"], JOY_AXIS_RIGHT_Y: ["RS UP", "RS DOWN"],
	JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"], JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"],
}
const BUSES := {"master_volume": "Master", "music_volume": "Music", "sfx_volume": "SFX"}
const WINDOW_MODES := ["FULLSCREEN", "WINDOWED"]
const FPS_LIMITS := [30, 60, 120]
const WINDOWED_SIZE := Vector2i(1280, 960)

var values := {
	"master_volume": 100, "music_volume": 100, "sfx_volume": 100,
	"window_mode": "FULLSCREEN", "vsync": true, "fps": 30, "pixel_perfect": false, "screen_shake": true,
}
var bindings := {"key": DEFAULT_KEYS.duplicate(), "pad": DEFAULT_PAD.duplicate(true)}
## "key" or "pad": what the player last pressed, so prompts name the right thing.
var device := "key"
var _latched := {} # actions a stick is holding, so one push counts as one press
var _window_mode_saved := false


func _enter_tree() -> void:
	_make_buses()
	_load()
	apply_bindings()
	apply_volumes()
	get_tree().node_added.connect(_sort_sound)


func _ready() -> void:
	apply_game_view()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
	if _window_mode_saved:
		apply_window()


# --- input ---

func apply_bindings() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, STICK_DEADZONE)
		InputMap.action_set_deadzone(action, STICK_DEADZONE)
		InputMap.action_erase_events(action)
		var key := InputEventKey.new()
		key.physical_keycode = bindings["key"][action]
		InputMap.action_add_event(action, key)
		InputMap.action_add_event(action, _pad_event(bindings["pad"][action]))
		if STICK.has(action):
			InputMap.action_add_event(action, _pad_event({"axis": STICK[action][0], "direction": STICK[action][1]}))


func _pad_event(binding: Dictionary) -> InputEvent:
	if binding.has("axis"):
		var motion := InputEventJoypadMotion.new()
		motion.axis = int(binding["axis"]) as JoyAxis
		motion.axis_value = binding["direction"]
		return motion
	var button := InputEventJoypadButton.new()
	button.button_index = int(binding["button"]) as JoyButton
	return button


## True when this event is a fresh press of the action. Use it instead of
## event.is_action_pressed: a stick sends events all the time while held.
func pressed(event: InputEvent, action: String) -> bool:
	if not event.is_action_pressed(action):
		return false
	if event is InputEventJoypadMotion:
		if _latched.has(action):
			return false
		_latched[action] = true
	return true


func _input(event: InputEvent) -> void:
	for action in _latched.keys():
		if not event.is_action(action):
			continue
		if not event.is_action_pressed(action):
			_latched.erase(action)
	var now := device
	if event is InputEventKey and event.pressed:
		now = "key"
	elif event is InputEventJoypadButton and event.pressed:
		now = "pad"
	elif event is InputEventJoypadMotion and absf(event.axis_value) > STICK_DEADZONE:
		now = "pad"
	if now != device:
		device = now
		device_changed.emit()


## Changes one binding. If another action already uses it they swap, so nothing
## ever ends up with no control.
func rebind(action: String, column: String, binding: Variant) -> void:
	var old: Variant = bindings[column][action]
	for other in ACTIONS:
		if other != action and bindings[column][other] == binding:
			bindings[column][other] = old
	bindings[column][action] = binding
	apply_bindings()
	save()


func reset_controls() -> void:
	bindings = {"key": DEFAULT_KEYS.duplicate(), "pad": DEFAULT_PAD.duplicate(true)}
	apply_bindings()
	save()


## An event as a binding, or null if it isn't one for that column.
func binding_from(event: InputEvent, column: String) -> Variant:
	if column == "key" and event is InputEventKey and event.pressed and not event.echo:
		return int(event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode)
	if column == "pad" and event is InputEventJoypadButton and event.pressed:
		return {"button": int(event.button_index)}
	if column == "pad" and event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		return {"axis": int(event.axis), "direction": signf(event.axis_value)}
	return null


func binding_name(action: String, column: String) -> String:
	var binding: Variant = bindings[column][action]
	if column == "key":
		return OS.get_keycode_string(int(binding)).to_upper()
	if binding.has("axis"):
		var names: Array = AXIS_NAMES.get(int(binding["axis"]), ["AXIS", "AXIS"])
		return names[0] if binding["direction"] < 0.0 else names[1]
	return BUTTON_NAMES.get(int(binding["button"]), "BUTTON %d" % int(binding["button"]))


## A control written the game's way: [X]
func prompt(action: String) -> String:
	return "[%s]" % binding_name(action, device)


## Control prompts in a row: [["BACK", "MAIN MENU"]] gives "[X] MAIN MENU".
func hint(pairs: Array) -> String:
	var parts := PackedStringArray()
	for pair in pairs:
		parts.append("%s %s" % [prompt(pair[0]), pair[1]])
	return "    ".join(parts)


# --- sound ---

func _make_buses() -> void:
	for bus_name in BUSES.values():
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


func apply_volumes() -> void:
	for key in BUSES:
		var index := AudioServer.get_bus_index(BUSES[key])
		var amount: float = values[key] / 100.0
		AudioServer.set_bus_mute(index, amount <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(amount, 0.0001)))


## Every sound counts as a sound effect unless it's put on the Music bus.
func _sort_sound(node: Node) -> void:
	if (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D) and node.bus == &"Master":
		node.bus = &"SFX"


# --- graphics ---

## The game's fixed 640x480 view, scaled to the window. The editor turns this off.
func apply_game_view() -> void:
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if values["pixel_perfect"] else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	Engine.max_fps = values["fps"]


func apply_window() -> void:
	var window := get_window()
	if values["window_mode"] == "FULLSCREEN":
		window.mode = Window.MODE_FULLSCREEN
		return
	window.mode = Window.MODE_WINDOWED
	window.borderless = false
	window.size = WINDOWED_SIZE
	window.move_to_center()


## Sets a setting, puts it into effect and saves it.
func change(key: String, value: Variant) -> void:
	values[key] = value
	match key:
		"window_mode":
			_window_mode_saved = true
			apply_window()
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		"fps", "pixel_perfect":
			apply_game_view()
		"master_volume", "music_volume", "sfx_volume":
			apply_volumes()
	save()


func shake_scale() -> float:
	return 1.0 if values["screen_shake"] else 0.0


# --- saving ---

func save() -> void:
	var config := ConfigFile.new()
	for key in values:
		if key != "window_mode" or _window_mode_saved:
			config.set_value("settings", key, values[key])
	config.set_value("controls", "key", bindings["key"])
	config.set_value("controls", "pad", bindings["pad"])
	config.save(PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for key in values:
		var saved: Variant = config.get_value("settings", key, values[key])
		if typeof(saved) == typeof(values[key]):
			values[key] = saved
	_window_mode_saved = config.has_section_key("settings", "window_mode")
	for column in COLUMNS:
		var saved: Variant = config.get_value("controls", column, {})
		if not saved is Dictionary:
			continue
		for action in ACTIONS:
			if _binding_ok(saved.get(action), column):
				bindings[column][action] = saved[action]


func _binding_ok(binding: Variant, column: String) -> bool:
	if column == "key":
		return binding is int
	if not binding is Dictionary:
		return false
	return binding.get("button") is int or (binding.get("axis") is int and binding.get("direction") is float)
