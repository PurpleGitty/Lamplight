class_name FreeShot
extends Minigame
## The tutorial's special: a free throw. A whistle blows, then the shot's path swings
## higher and lower (like the crucible's oval); press ACCEPT to shoot. The ball flies under
## gravity, bounces off the floor (squishing a little), the backboard and the front of
## the rim, and has to drop through the hoop. The net is loose strands that swing when
## the ball goes through. Nothing but net is a PERFECT.

const BOX := Vector2(600, 360)
const BALL = preload("res://sprites/tutorial/basketball.png")
const HOOP = preload("res://sprites/tutorial/hoop.png")
const SOUL = preload("res://sprites/tutorial/blank_soul.png")
const WHISTLE := "res://sounds/tutorial/whistle.wav"
const BOUNCE = preload("res://sounds/tutorial/ball_bounce.wav")
const TOP := 24.0 # room for the title
const HOOP_SCALE := 4.0
const BALL_SCALE := 2.0
const BALL_RADIUS := 16.0
const GRAVITY := 700.0
const ANGLE := 58.0 # degrees above level
const SWING := 0.1 # how far the shot's power swings either side of a perfect one
const SWING_TIME := 2.4 # seconds for a full swing
const WHISTLE_WAIT := 0.6 # can't shoot until the whistle's gone
const AUTO_SHOOT := 10.0
const GIVE_UP := 6.0 # seconds after the shot with nothing going in
const AFTER_SCORE := 1.2
const FLOOR_BOUNCE := 0.62
const WALL_BOUNCE := 0.55
const STEPS := 6
const MAKE := 2.0 # damage for a basket
const SWISH := 2.5 # and for nothing but net
## Hoop sprite pixels: the front of the rim, the backboard, the head on its post, the
## post and the base, as [x, y, w, h].
const RIM_TIP := Vector2(1.0, 17.5) # its middle
const RIM_TIP_RADIUS := 1.5
const RIM_Y := 17.5
const SOLID := [[16, 0, 5, 21], [22, 10, 7, 7], [24, 18, 4, 41], [16, 60, 16, 4]]
## The net's strands, along the rim (sprite pixels): where each hangs from and how long it is.
const STRANDS := [[1.5, 7], [3.5, 10], [5.5, 13], [7.5, 13], [9.5, 13], [11.5, 10], [13.5, 7]]
const NET_TOP := 19.0
const NET_TAPER := 0.45 # how far in the strands' ends pull toward the middle
const NET_SPRING := 140.0
const NET_DAMP := 9.0

var _floor := 0.0
var _hoop := Vector2.ZERO # the sprite's top left corner
var _launch := Vector2.ZERO
var _ideal := 0.0 # the launch speed that drops straight through
var _clock := 0.0
var _swing := 0.0
var _shot := false
var _since_shot := 0.0
var _ball := Vector2.ZERO
var _velocity := Vector2.ZERO
var _spin := 0.0
var _squash := 0.0
var _touched := false # hit the rim or backboard before going in
var _scored := false
var _since_score := 0.0
var _result := ""
var _result_color := Color.WHITE
var _net_offset: Array[Vector2] = []
var _net_velocity: Array[Vector2] = []


func begin() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_floor = size.y - 2.0
	_hoop = Vector2(size.x - HOOP.get_width() * HOOP_SCALE - 4.0, _floor - HOOP.get_height() * HOOP_SCALE)
	_launch = Vector2(64.0, _floor - 70.0)
	_ball = _launch
	for i in STRANDS.size():
		_net_offset.append(Vector2.ZERO)
		_net_velocity.append(Vector2.ZERO)
	_ideal = _speed_to(_hoop_point(Vector2((RIM_TIP.x + SOLID[0][0]) / 2.0, RIM_Y)))
	fire_sound(WHISTLE)


func _hoop_point(sprite_pixel: Vector2) -> Vector2:
	return _hoop + sprite_pixel * HOOP_SCALE


## How fast to throw at ANGLE to fall through this point on the way down.
func _speed_to(target: Vector2) -> float:
	var angle := deg_to_rad(ANGLE)
	var across := target.x - _launch.x
	var up := _launch.y - target.y
	var drop := across * tan(angle) - up
	return sqrt(GRAVITY * across * across / (2.0 * cos(angle) * cos(angle) * maxf(drop, 1.0)))


func _launch_velocity() -> Vector2:
	var speed := _ideal * (1.0 + SWING * sin(_swing))
	var angle := deg_to_rad(ANGLE)
	return Vector2(cos(angle), -sin(angle)) * speed


func tapped() -> void:
	if not _shot and _clock >= WHISTLE_WAIT:
		_shoot()


func _shoot() -> void:
	_shot = true
	_velocity = _launch_velocity()


func tick(delta: float) -> void:
	_clock += delta
	_squash = move_toward(_squash, 0.0, delta * 2.5)
	_update_net(delta)
	if not _shot:
		_swing += delta * TAU / SWING_TIME
		if running and _clock >= AUTO_SHOOT:
			_shoot()
		return
	_since_shot += delta
	for i in STEPS:
		_step(delta / STEPS)
	_spin += _velocity.x / BALL_RADIUS * delta
	if not running:
		return
	if _scored:
		_since_score += delta
		if _since_score >= AFTER_SCORE:
			_finish()
	elif _since_shot >= GIVE_UP or (_on_floor() and _velocity.length() < 25.0):
		_finish()


func _on_floor() -> bool:
	return _ball.y >= _floor - BALL_RADIUS - 0.5


func _step(dt: float) -> void:
	var before := _ball
	_velocity.y += GRAVITY * dt
	_ball += _velocity * dt

	# Through the hoop, from above
	var rim_y := _hoop_point(Vector2(0, RIM_Y)).y
	if not _scored and before.y < rim_y and _ball.y >= rim_y and _velocity.y > 0.0:
		var tip := _hoop_point(RIM_TIP)
		var board := _hoop_point(Vector2(SOLID[0][0], 0)).x
		if _ball.x > tip.x and _ball.x < board:
			_scored = true
			_kick_net()

	# Dropping through the net slows it down
	if _scored and _in_net():
		_velocity *= pow(0.25, dt)

	# The floor: bounce, squish and thud
	if _ball.y > _floor - BALL_RADIUS:
		_ball.y = _floor - BALL_RADIUS
		if _velocity.y > 0.0:
			var impact := _velocity.y
			_velocity.y = -impact * FLOOR_BOUNCE
			_velocity.x *= 0.85
			if impact > 90.0:
				_squash = minf(impact / 1400.0, 0.35)
				_bounce_sound(clampf(impact / 700.0, 0.15, 1.0))
			if absf(_velocity.y) < 40.0:
				_velocity.y = 0.0
		_velocity.x *= pow(0.5, dt) # rolling to a stop
	# The sides and the top of the box
	if _ball.x < BALL_RADIUS:
		_ball.x = BALL_RADIUS
		_velocity.x = absf(_velocity.x) * WALL_BOUNCE
	elif _ball.x > size.x - BALL_RADIUS:
		_ball.x = size.x - BALL_RADIUS
		_velocity.x = -absf(_velocity.x) * WALL_BOUNCE
	if _ball.y < TOP + BALL_RADIUS:
		_ball.y = TOP + BALL_RADIUS
		_velocity.y = absf(_velocity.y) * WALL_BOUNCE

	# The front of the rim
	var tip := _hoop_point(RIM_TIP)
	var reach := BALL_RADIUS + RIM_TIP_RADIUS * HOOP_SCALE
	if _ball.distance_to(tip) < reach:
		_bounce_off((_ball - tip).normalized(), tip + (_ball - tip).normalized() * reach)
	# The backboard, the head, the post and the base
	for part in SOLID:
		var rect := Rect2(_hoop_point(Vector2(part[0], part[1])), Vector2(part[2], part[3]) * HOOP_SCALE)
		var closest := _ball.clamp(rect.position, rect.end)
		var away := _ball - closest
		if away.length() < BALL_RADIUS and away != Vector2.ZERO:
			_bounce_off(away.normalized(), closest + away.normalized() * BALL_RADIUS)


func _bounce_off(normal: Vector2, outside: Vector2) -> void:
	_ball = outside
	var into := _velocity.dot(normal)
	if into < 0.0:
		_velocity -= (1.0 + WALL_BOUNCE) * into * normal
		if not _scored:
			_touched = true
		if -into > 120.0:
			_bounce_sound(clampf(-into / 900.0, 0.1, 0.6))


func _finish() -> void:
	if _scored:
		perfect = not _touched
		_result = "SWISH!" if perfect else "SCORE!"
		_result_color = Color.YELLOW if perfect else Color.CYAN
		end(SWISH if perfect else MAKE)
	else:
		_result = "MISS"
		_result_color = Color.RED
		end(0.0)


func _bounce_sound(volume: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = BOUNCE
	player.volume_db = linear_to_db(volume)
	player.bus = &"SFX"
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.play()


# --- the net ---

func _strand_top(i: int) -> Vector2:
	return _hoop_point(Vector2(STRANDS[i][0], NET_TOP))


func _strand_bottom(i: int) -> Vector2:
	var top := _strand_top(i)
	var middle := _hoop_point(Vector2(7.5, 0)).x
	return Vector2(lerpf(top.x, middle, NET_TAPER * STRANDS[i][1] / 13.0), top.y + STRANDS[i][1] * HOOP_SCALE)


func _in_net() -> bool:
	var top := _strand_top(0).y
	return _ball.y > top - BALL_RADIUS and _ball.y < top + 13.0 * HOOP_SCALE + BALL_RADIUS \
		and _ball.x > _strand_top(0).x - BALL_RADIUS and _ball.x < _strand_top(STRANDS.size() - 1).x + BALL_RADIUS


## The ball's gone in: every strand gets flung down and out.
func _kick_net() -> void:
	var middle := _hoop_point(Vector2(7.5, 0)).x
	for i in STRANDS.size():
		_net_velocity[i] += Vector2((_strand_top(i).x - middle) * 3.0, 140.0)


func _update_net(delta: float) -> void:
	for i in STRANDS.size():
		# The ball pushes strands aside as it goes through
		if _in_net():
			var top := _strand_top(i)
			var bottom := _strand_bottom(i) + _net_offset[i]
			var along := clampf((_ball.y - top.y) / maxf(bottom.y - top.y, 1.0), 0.0, 1.0)
			var strand_x := lerpf(top.x, bottom.x, along)
			var gap := strand_x - _ball.x
			if absf(gap) < BALL_RADIUS and _ball.y > top.y:
				_net_offset[i].x += signf(gap if gap != 0.0 else 1.0) * (BALL_RADIUS - absf(gap)) * 0.5
				_net_offset[i].y += maxf(_velocity.y, 0.0) * delta * 0.4
		var pull := -NET_SPRING * _net_offset[i] - NET_DAMP * _net_velocity[i]
		_net_velocity[i] += pull * delta
		_net_offset[i] += _net_velocity[i] * delta
		_net_offset[i] = _net_offset[i].limit_length(18.0)


## Strands drawn a sprite pixel at a time, so they match the hoop's art.
func _draw_net() -> void:
	var pixel := Vector2.ONE * HOOP_SCALE
	for i in STRANDS.size():
		var top := _strand_top(i)
		var bottom := _strand_bottom(i) + _net_offset[i]
		var middle := top.lerp(_strand_bottom(i), 0.5) + _net_offset[i] * 0.6
		var steps := int(STRANDS[i][1])
		for s in steps:
			var t := float(s) / maxf(steps - 1, 1)
			var point := _bend(top, middle, bottom, t)
			var snapped := _hoop + ((point - _hoop) / HOOP_SCALE).floor() * HOOP_SCALE
			draw_rect(Rect2(snapped, pixel), Color.WHITE)


## A point along a strand bent through its middle.
func _bend(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


# --- drawing ---

func _draw() -> void:
	draw_title()
	if _result != "":
		draw_string(font, Vector2(0, 16), _result, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, _result_color)
	elif not _shot and _clock >= WHISTLE_WAIT:
		draw_string(font, Vector2(0, 16), GameSettings.hint([["ACCEPT", "SHOOT"]]), HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, Color.WHITE)
	draw_line(Vector2(0, _floor + 1.0), Vector2(size.x, _floor + 1.0), Color(1, 1, 1, 0.5), 2.0)

	# Where the shot would go, if it were taken now
	if not _shot:
		var where := _launch
		var going := _launch_velocity()
		var color := Color(0.2, 1.0, 0.25, 1.0 if _clock >= WHISTLE_WAIT else 0.35)
		for i in 48:
			for s in 4:
				going.y += GRAVITY * 0.0125
				where += going * 0.0125
			if where.y > _floor or where.x > size.x:
				break
			if i % 2 == 1:
				draw_circle(where, 2.5, color)

	draw_texture_rect(HOOP, Rect2(_hoop, HOOP.get_size() * HOOP_SCALE), false)
	draw_texture_rect_region(SOUL, Rect2(_launch + Vector2(-48, -8), Vector2(16, 16) * BALL_SCALE * 0.75), Rect2(0, 0, 16, 16))

	# The ball, squished against the floor when it lands
	var squish := Vector2(1.0 + _squash, 1.0 - _squash)
	var center := _ball + Vector2(0, BALL_RADIUS * _squash) if _on_floor() else _ball
	draw_set_transform_matrix(Transform2D(0.0, squish * BALL_SCALE, 0.0, center) * Transform2D(_spin, Vector2.ZERO))
	draw_texture(BALL, -BALL.get_size() / 2.0)
	draw_set_transform(Vector2.ZERO)

	_draw_net() # in front of the ball, so it drops through it
