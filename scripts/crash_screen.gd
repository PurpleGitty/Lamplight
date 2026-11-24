class_name CrashScreen
extends CanvasLayer
## The failsafe for when the game's about to fall over. A script error anywhere freezes
## the game and covers it with this: "Game crashed, check logs or restart." in the
## middle, and a purple fumo who wanders about in the meantime. Grab him with the mouse
## (or a finger) and throw him: he squishes against the window's walls and floor with a
## squeak, sometimes says something, gets back up if he landed badly, and now and then
## sits down to play Lamplight on his tablet.
## GameSettings sets it up at boot with watch(); it only shows itself if something breaks.

const SHEET = preload("res://sprites/crash/fumo.png")
const SQUEAK = preload("res://sounds/crash/squeak.mp3")
const LINES := [
	preload("res://sounds/crash/sam_1.wav"), preload("res://sounds/crash/sam_2.wav"),
	preload("res://sounds/crash/sam_3.wav"), preload("res://sounds/crash/sam_4.wav"),
	preload("res://sounds/crash/sam_5.wav"), preload("res://sounds/crash/sam_6.wav"),
	preload("res://sounds/crash/sam_7.wav"),
]
## What he hears from his tablet: bits of the game.
const TABLET_SOUNDS := [
	"res://sounds/creatorshome-video-game-select-337214.mp3",
	"res://sounds/lightningbulb-spacebar-click-keyboard-199448.mp3",
	"res://sounds/freesound_community-cancel-36118.mp3",
	"res://sounds/snd_txt2.wav", "res://sounds/snd_damage.wav", "res://sounds/snd_hurt1.wav",
	"res://sounds/axe_clang.mp3", "res://sounds/axe_bounce.mp3", "res://sounds/crucible_slash.ogg",
	"res://sounds/p_attack.ogg", "res://sounds/v_attack.mp3",
	"res://sounds/tutorial/slap.mp3", "res://sounds/tutorial/heal.mp3",
	"res://sounds/tutorial/ball_bounce.wav", "res://sounds/tutorial/whistle.wav",
	"res://sounds/tutorial/soul_appears.mp3",
]
const FONT = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
# Frames on the sheet
const STAND := 0
const WALK := [4, 5, 6, 7]
const SIT_DOWN := 12
const TABLET := 9
const FLAIL := [16, 17]
const GET_UP := 20
const HALF := Vector2(22, 32) # half his size on the sheet, for bumping into the window's edges
const GRAVITY := 1400.0 # per second per second, in sheet pixels
const WALK_SPEED := 30.0
const BOUNCE := 0.45
const SQUISH_SPEED := 160.0 # hitting something faster than this squishes him
const LINE_CHANCE := 0.35

enum State { WALK, STAND, SIT, HELD, FLY, LYING, GET_UP }

static var _shown := false
static var _instance: CrashScreen

var _state := State.WALK
var _unit := 2.0 # screen pixels per sheet pixel
var _bounds := Rect2()
var _fumo := Sprite2D.new()
var _pos := Vector2.ZERO # his middle, on screen
var _vel := Vector2.ZERO
var _spin := 0.0
var _facing := 1.0
var _timer := 0.0 # until the next thing he decides to do
var _anim := 0.0
var _squish := Vector2.ZERO # how squashed he is on each axis, easing back to nothing
var _grab_offset := Vector2.ZERO
var _drag_history: Array = [] # [time, position] of the last moments of a drag
var _next_tablet_sound := 0.0
var _squeak := AudioStreamPlayer.new()
var _voice := AudioStreamPlayer.new()
var _tablet := AudioStreamPlayer.new()
var _text := Label.new()
var _hint := Label.new()


## Starts listening for errors. Called once, at boot.
static func watch(owner: Node) -> void:
	if _instance != null:
		return
	_instance = CrashScreen.new()
	owner.add_child(_instance)
	OS.add_logger(_ErrorWatcher.new())


## Freezes the game and shows the screen. Safe to call from any thread, and more than once.
static func crash(reason := "") -> void:
	if _instance != null:
		_instance._show.call_deferred(reason)


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process(false)
	set_process_input(false)


func _show(reason: String) -> void:
	if _shown:
		return
	_shown = true
	push_warning("Showing the crash screen: %s" % reason)
	var tree := get_tree()
	tree.paused = true
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Music"), true)
	_bounds = get_viewport().get_visible_rect()
	_unit = maxf(1.0, roundf(_bounds.size.y / 480.0)) * 2.0
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.position = _bounds.position
	black.size = _bounds.size
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	for label in [_text, _hint]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", FONT)
		label.position = _bounds.position
		label.size = _bounds.size
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
	_text.text = "Game crashed, check logs or restart."
	_text.add_theme_font_size_override("font_size", int(8 * _unit))
	_hint.text = "" if GameSettings.mobile else "[ESC] QUIT"
	_hint.add_theme_font_size_override("font_size", int(4 * _unit))
	_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hint.size.y -= 4 * _unit
	_fumo.texture = SHEET
	_fumo.hframes = 4
	_fumo.vframes = 6
	_fumo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_fumo)
	for player in [_squeak, _voice, _tablet]:
		player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		add_child(player)
	_squeak.stream = SQUEAK
	_tablet.volume_db = -10.0
	# He drops in from the top, somewhere in the middle
	_pos = Vector2(_bounds.get_center().x + randf_range(-0.25, 0.25) * _bounds.size.x, _bounds.position.y - HALF.y * _unit)
	_vel = Vector2(randf_range(-60, 60), 0) * _unit
	_spin = randf_range(-6, 6)
	_state = State.FLY
	visible = true
	set_process(true)
	set_process_input(true)


func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 20.0)
	_anim += delta
	_timer -= delta
	_squish = _squish.lerp(Vector2.ZERO, minf(delta * 14.0, 1.0))
	match _state:
		State.WALK: _walk(delta)
		State.STAND: _stand()
		State.SIT: _sit()
		State.HELD: _fumo.frame = FLAIL[int(_anim * 10.0) % 2]
		State.FLY: _fly(delta)
		State.LYING: _lie()
		State.GET_UP: _fumo.frame = GET_UP
	_draw_fumo()


func _input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled() # the frozen game underneath hears nothing
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
		return
	var point := Vector2.INF
	var pressed := false
	var released := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		point = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenTouch and event.index == 0:
		point = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion or (event is InputEventScreenDrag and event.index == 0):
		point = event.position
	if point == Vector2.INF:
		return
	if pressed and _state != State.HELD and _hits(point):
		_state = State.HELD
		_grab_offset = _pos - point
		_drag_history.clear()
		_vel = Vector2.ZERO
		_spin = 0.0
		_tablet.stop()
	elif released and _state == State.HELD:
		_throw()
	elif _state == State.HELD:
		_pos = _keep_inside(point + _grab_offset)
		_drag_history.append([Time.get_ticks_msec() / 1000.0, _pos])
		while _drag_history.size() > 6:
			_drag_history.pop_front()


func _hits(point: Vector2) -> bool:
	var local := (point - _pos).rotated(-_fumo.rotation) / _unit
	return absf(local.x) <= HALF.x + 4 and absf(local.y) <= HALF.y + 4


## Lets go: off he flies at the speed he was being dragged, spinning that way.
func _throw() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_vel = Vector2.ZERO
	if _drag_history.size() >= 2:
		var first: Array = _drag_history[0]
		var last: Array = _drag_history[-1]
		if now - last[0] < 0.1 and last[0] > first[0]:
			_vel = (last[1] - first[1]) / (last[0] - first[0])
	_vel = _vel.limit_length(2400.0 * _unit / 2.0)
	_spin = clampf(_vel.x / (40.0 * _unit), -14.0, 14.0)
	_state = State.FLY


func _fly(delta: float) -> void:
	_fumo.frame = FLAIL[int(_anim * 10.0) % 2]
	_vel.y += GRAVITY * _unit * delta
	_pos += _vel * delta
	_fumo.rotation += _spin * delta
	var reach := _reach()
	var hit_speed := 0.0
	var squish := Vector2.ZERO
	if _pos.x - reach.x < _bounds.position.x and _vel.x < 0:
		_pos.x = _bounds.position.x + reach.x
		hit_speed = -_vel.x
		squish = Vector2(1, 0)
		_vel.x = -_vel.x * BOUNCE
		_spin = -_spin * 0.6
	elif _pos.x + reach.x > _bounds.end.x and _vel.x > 0:
		_pos.x = _bounds.end.x - reach.x
		hit_speed = _vel.x
		squish = Vector2(1, 0)
		_vel.x = -_vel.x * BOUNCE
		_spin = -_spin * 0.6
	if _pos.y - reach.y < _bounds.position.y and _vel.y < 0:
		_pos.y = _bounds.position.y + reach.y
		hit_speed = maxf(hit_speed, -_vel.y)
		squish = Vector2(0, 1)
		_vel.y = -_vel.y * BOUNCE
	var on_floor := false
	if _pos.y + reach.y >= _bounds.end.y and _vel.y >= 0:
		_pos.y = _bounds.end.y - reach.y
		if _vel.y > hit_speed:
			hit_speed = _vel.y
			squish = Vector2(0, 1)
		_vel.y = -_vel.y * BOUNCE
		_vel.x *= 0.7 # the floor rubs
		_spin *= 0.5
		on_floor = true
	if hit_speed > SQUISH_SPEED * _unit / 2.0:
		_bump(squish, hit_speed)
	# Settled on the floor
	if on_floor and absf(_vel.y) < 60.0 * _unit and absf(_vel.x) < 40.0 * _unit:
		_vel = Vector2.ZERO
		_spin = 0.0
		var tilt := wrapf(_fumo.rotation, -PI, PI)
		if absf(tilt) < deg_to_rad(25):
			_fumo.rotation = 0.0
			_stand_for(randf_range(0.6, 1.5))
		else:
			# Landed badly: he lies there a moment
			_fumo.rotation = PI / 2.0 * signf(tilt) if absf(tilt) < PI * 0.75 else PI
			_state = State.LYING
			_timer = randf_range(0.8, 1.6)


## Squishes him flat against what he hit, with a squeak, and maybe a word or two.
func _bump(axis: Vector2, speed: float) -> void:
	var amount := clampf(speed / (900.0 * _unit / 2.0), 0.15, 0.45)
	_squish = axis * amount
	_squeak.pitch_scale = randf_range(0.9, 1.15)
	_squeak.play()
	if not _voice.playing and randf() < LINE_CHANCE:
		_voice.stream = LINES.pick_random()
		_voice.play()


func _lie() -> void:
	_fumo.frame = FLAIL[0]
	if _timer > 0:
		return
	# Back on his feet with a little hop
	_state = State.GET_UP
	var t := create_tween()
	t.tween_property(_fumo, "rotation", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var lying_y := _pos.y
	t.parallel().tween_method(func(h: float): _pos.y = lerpf(lying_y, _bounds.end.y - HALF.y * _unit, minf(h / (10.0 * _unit) * 2.0, 1.0)) - h, 0.0, 10.0 * _unit, 0.12).set_ease(Tween.EASE_OUT)
	t.tween_method(func(h: float): _pos.y = _bounds.end.y - HALF.y * _unit - h, 10.0 * _unit, 0.0, 0.12).set_ease(Tween.EASE_IN)
	t.tween_interval(0.3)
	t.tween_callback(func():
		if _state == State.GET_UP:
			_stand_for(randf_range(0.4, 1.0)))


func _stand_for(seconds: float) -> void:
	_state = State.STAND
	_timer = seconds


func _stand() -> void:
	_fumo.frame = STAND
	if _timer > 0:
		return
	if randf() < 0.3:
		_state = State.SIT
		_timer = randf_range(6.0, 14.0)
		_next_tablet_sound = randf_range(0.8, 1.6)
	else:
		_state = State.WALK
		_timer = randf_range(3.0, 8.0)
		if randf() < 0.5:
			_facing = -_facing


func _walk(delta: float) -> void:
	_fumo.frame = WALK[int(_anim * 6.0) % WALK.size()]
	_pos.x += _facing * WALK_SPEED * _unit * delta
	var reach := HALF.x * _unit
	if _pos.x - reach < _bounds.position.x:
		_pos.x = _bounds.position.x + reach
		_facing = 1.0
	elif _pos.x + reach > _bounds.end.x:
		_pos.x = _bounds.end.x - reach
		_facing = -1.0
	if _timer <= 0:
		_stand_for(randf_range(1.0, 3.0))


## Sat on the floor, playing Lamplight: the game's sounds come out of his tablet.
func _sit() -> void:
	_fumo.frame = TABLET if _timer > 0.6 else SIT_DOWN
	_next_tablet_sound -= get_process_delta_time()
	if _next_tablet_sound <= 0 and _timer > 0.6:
		_next_tablet_sound = randf_range(0.7, 2.2)
		var path: String = TABLET_SOUNDS.pick_random()
		if ResourceLoader.exists(path):
			_tablet.stream = load(path)
			_tablet.pitch_scale = randf_range(0.95, 1.05)
			_tablet.play()
	if _timer <= 0:
		_tablet.stop()
		_stand_for(randf_range(0.5, 1.2))


## Half his size on screen, turned however he's turned, for bumping into the edges.
func _reach() -> Vector2:
	var c := absf(cos(_fumo.rotation))
	var s := absf(sin(_fumo.rotation))
	return Vector2(HALF.x * c + HALF.y * s, HALF.x * s + HALF.y * c) * _unit


func _keep_inside(point: Vector2) -> Vector2:
	var reach := _reach()
	return Vector2(clampf(point.x, _bounds.position.x + reach.x, _bounds.end.x - reach.x),
		clampf(point.y, _bounds.position.y + reach.y, _bounds.end.y - reach.y))


func _draw_fumo() -> void:
	# Squished flat against what he hit, keeping his size the other way about the same
	var squash := Vector2(1.0 - _squish.x + _squish.y * 0.6, 1.0 - _squish.y + _squish.x * 0.6)
	_fumo.scale = squash * _unit * Vector2(_facing if _state == State.WALK or _state == State.STAND else 1.0, 1.0)
	_fumo.position = (_pos + Vector2(0, (1.0 - squash.y) * HALF.y * _unit * signf(_squish.y))).round()


## Hears about every error. Only a script going wrong counts as a crash; plain warnings
## and the game's own error messages (bad files and the like) don't.
class _ErrorWatcher extends Logger:
	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		CrashScreen.crash("%s (%s:%d)" % [rationale if rationale != "" else code, file, line])

	func _log_message(_message: String, _error: bool) -> void:
		pass
