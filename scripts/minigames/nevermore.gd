extends Minigame
## Nevermore: the soul sits in the middle and LEFT and RIGHT turn it. The enemy's target
## circles round it erratically. Press or hold ACCEPT to fire crows out of the soul's
## point, one after another. They fly straight, curve a little toward the target once
## they're close, and every crow that hits is one lot of the special's damage. Crows tilt
## to follow their flight but face left or right, so they're never upside down.

const CAWS := ["res://sounds/crow/caw_1.wav", "res://sounds/crow/caw_2.wav", "res://sounds/crow/caw_3.wav", "res://sounds/crow/caw_echo.mp3"]
const SPREAD := 22.0 # degrees either side of where the soul points that a crow can fly off at
const SPEED_SPREAD := 0.2 # crows fly up to this much faster or slower
const SOUL = preload("res://sprites/candy_soul.png")
const CROW_FRAMES := 4
const CROW_SCALE := 2.0
const FLAP_SPEED := 14.0 # frames a second
const HOMING_RANGE := 130.0 # pixels from the target where crows start to curve in
const HOMING_TURN := 5.0 # radians a second they can curve
const HIT_RADIUS := 18.0
const TARGET_COLOR := Color(0.85, 0.25, 0.75)

var _aim := 0.0 # where the soul's point faces (at the target, to start)
var _crows: Array = [] # {"pos", "vel", "age"}
var _fired := 0
var _hits := 0
var _cooldown := 0.0
var _left := 0.0 # seconds left to fire
var _target_angle := 0.0
var _target_spin := 0.0 # still for a moment at the start
var _next_turn := 0.0
var _clock := 0.0
var _target_flash := 0.0
var _done_for := 0.0
var _result := ""
var _soul_texture: Texture2D = SOUL
var _sheet: Texture2D
var _soul_size := Vector2(16, 16)


func begin() -> void:
	_sheet = custom_texture() # loaded now, not mid-draw, or it shows as white squares at first
	_left = settings["fire_time"]
	_target_angle = randf() * TAU
	_aim = _target_angle # the soul starts out pointing right at it
	_next_turn = 0.6 # and it holds still a moment before it starts darting about
	var battle := get_tree().current_scene as Battle
	if battle != null and battle.soul.sprite.texture != null:
		_soul_texture = battle.soul.sprite.texture
		_soul_size = battle.soul.frame_size()
	else:
		_soul_size = Vector2(SOUL.get_width() / 2.0, SOUL.get_height())


func interrupted_multiplier() -> float:
	return float(_hits)


func _middle() -> Vector2:
	return size / 2.0 + Vector2(0, 8)


func _target() -> Vector2:
	var radius: float = settings["target_distance"] * (1.0 + 0.2 * sin(_clock * 2.3) + 0.08 * sin(_clock * 7.1))
	return _middle() + Vector2.from_angle(_target_angle) * radius


func _point() -> Vector2:
	return _middle() + Vector2.from_angle(_aim) * (_soul_size.y * 0.6 + 2.0)


func tapped() -> void:
	_fire()


func _fire() -> void:
	if not running or _cooldown > 0.0 or _fired >= int(settings["max_crows"]) or _left <= 0.0:
		return
	_cooldown = 1.0 / maxf(settings["fire_rate"], 0.1)
	_fired += 1
	var speed: float = settings["crow_speed"]
	# Not every crow goes quite where it's sent, or quite as fast
	var off := deg_to_rad(randf_range(-SPREAD, SPREAD) * randf_range(0.3, 1.0))
	speed *= 1.0 + randf_range(-SPEED_SPREAD, SPEED_SPREAD)
	_crows.append({"pos": _point(), "vel": Vector2.from_angle(_aim + off) * speed, "age": randf()})
	var caw := asset("caw_sound")
	_play(caw if caw != "" else CAWS.pick_random(), -7.0, randf_range(0.9, 1.15))
	_play(asset("flap_sound"), -2.0, randf_range(0.9, 1.1))


## A sound that overlaps itself, a little quieter and at its own pitch.
func _play(path: String, volume: float, pitch: float) -> void:
	var stream := ChartDefs.load_audio(path) if path != "" else null
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = pitch
	player.bus = &"SFX"
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.play()


func tick(delta: float) -> void:
	_clock += delta
	_target_flash = maxf(_target_flash - delta * 6.0, 0.0)
	_cooldown = maxf(_cooldown - delta, 0.0)
	# The target darts about: speeding up, slowing down, turning back
	_next_turn -= delta
	if _next_turn <= 0.0:
		_next_turn = randf_range(0.25, 0.75)
		var fastest: float = settings["target_speed"]
		_target_spin = randf_range(0.4, 1.0) * fastest * (1.0 if randf() < 0.5 else -1.0)
	_target_angle += _target_spin * delta
	if running:
		_left = maxf(_left - delta, 0.0)
		var turn := 0.0
		if Input.is_action_pressed("LEFT"):
			turn -= 1.0
		if Input.is_action_pressed("RIGHT"):
			turn += 1.0
		_aim += turn * deg_to_rad(settings["turn_speed"]) * delta
		if Input.is_action_pressed("ACCEPT"):
			_fire()
	_move_crows(delta)
	if not running:
		return
	var out_of_crows: bool = _fired >= int(settings["max_crows"]) or _left <= 0.0
	if out_of_crows and _crows.is_empty():
		_done_for += delta
		if _done_for > 0.4:
			_result = "%d HIT%s" % [_hits, "" if _hits == 1 else "S"]
			perfect = _hits >= int(settings["max_crows"])
			end(float(_hits))


func _move_crows(delta: float) -> void:
	var target := _target()
	var bounds := Rect2(Vector2(-24, -24), size + Vector2(48, 48))
	var still: Array = []
	for crow in _crows:
		crow["age"] += delta
		var to_target: Vector2 = target - crow["pos"]
		var distance := to_target.length()
		if distance < HOMING_RANGE:
			# Close: curve a little toward it, harder the closer it is
			var vel: Vector2 = crow["vel"]
			var wanted := vel.angle_to(to_target)
			var pull := HOMING_TURN * (1.0 - distance / HOMING_RANGE) * delta
			crow["vel"] = vel.rotated(clampf(wanted, -pull, pull))
		crow["pos"] += crow["vel"] * delta
		if crow["pos"].distance_to(target) < HIT_RADIUS:
			_hits += 1
			_target_flash = 1.0
			continue
		if bounds.has_point(crow["pos"]):
			still.append(crow)
	_crows = still


func _draw() -> void:
	draw_title()
	var limit := int(settings["max_crows"])
	var status := _result if _result != "" else "CROWS %d   HITS %d   %.1f" % [limit - _fired, _hits, _left]
	draw_string(font, Vector2(0, 36), status, HORIZONTAL_ALIGNMENT_LEFT, size.x, 16, Color.YELLOW if _target_flash > 0.0 else Color.WHITE)
	var hint := "%s %s TURN   %s FIRE" % [GameSettings.prompt("LEFT"), GameSettings.prompt("RIGHT"), GameSettings.prompt("ACCEPT")]
	draw_string(font, Vector2(0, size.y - 4), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 8, Color(1, 1, 1, 0.5))

	# The target
	var target := _target()
	var ring := TARGET_COLOR.lerp(Color.WHITE, _target_flash)
	draw_arc(target, HIT_RADIUS, 0.0, TAU, 24, ring, 2.0)
	for side in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(target + side * (HIT_RADIUS - 5.0), target + side * (HIT_RADIUS + 5.0), ring, 2.0)
	draw_circle(target, 2.0, ring)

	# The soul, its point toward where it's aiming
	var middle := _middle()
	draw_set_transform(middle, _aim - PI / 2.0, Vector2(2, 2))
	draw_texture_rect_region(_soul_texture, Rect2(-_soul_size / 2.0, _soul_size), Rect2(Vector2.ZERO, _soul_size))
	draw_set_transform(Vector2.ZERO)
	# A faint line showing where crows will go
	var point := _point()
	draw_dashed_line(point, point + Vector2.from_angle(_aim) * 40.0, Color(1, 1, 1, 0.25), 1.0, 4.0)

	# The crows, flapping, always the right way up
	var sheet := _sheet
	if sheet == null:
		return
	var frame_size := Vector2(sheet.get_width() / float(CROW_FRAMES), sheet.get_height())
	for crow in _crows:
		var frame := int(crow["age"] * FLAP_SPEED) % CROW_FRAMES
		var facing := -1.0 if crow["vel"].x < 0.0 else 1.0
		# Tilted along its flight, but turned to face left or right so it's never upside down
		var heading: float = crow["vel"].angle() if facing > 0.0 else crow["vel"].angle() - PI
		draw_set_transform(crow["pos"].round(), heading, Vector2(CROW_SCALE * facing, CROW_SCALE))
		draw_texture_rect_region(sheet, Rect2(-frame_size / 2.0, frame_size), Rect2(Vector2(frame * frame_size.x, 0), frame_size))
	draw_set_transform(Vector2.ZERO)
