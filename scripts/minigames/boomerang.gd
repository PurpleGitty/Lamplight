extends Minigame
## The crucible. A crosshair moves up and down, faster the lower the target's HP,
## while the oval the blade will fly grows and shrinks. Press ACCEPT to throw: the
## blade goes round the oval like a boomerang and comes back to the soul, and has
## to hit the crosshair on the way. Dead centre is maximum damage; a miss does none.

const SOUL_TEXTURE = preload("res://sprites/candy_soul.png")
const TOP := 24.0 # room for the title
const SOUL_X := 18.0
const END_MARGIN := 22.0
const CROSSHAIR_ALONG := 0.8 # how far along the oval the crosshair sits
const SLOWEST := 0.6 # flight eases: fast near the soul, slow at the far end
const SPIN_TURNS := 3.0 # turns a second at normal flight speed
const FAR_VOLUME := 0.6 # the spin's volume at the far end
const DOTS := 12
const CURVE_POINTS := 64
const GREEN := Color(0.2, 1.0, 0.25)
const BLADE_SCALE := 2.0

var _thrown := false
var _returned := false
var _waited := 0.0
var _flight := 0.0 # 0 to 1, soul back to soul
var _oval_time := 0.0
var _crosshair_phase := 0.0
var _growth := 0.0 # how big the oval is, 0 to 1; held still once thrown
var _spin := 0.0
var _best := INF # closest the blade has come to the crosshair
var _flash := 0.0
var _result := ""
var _spin_sound := AudioStreamPlayer.new()


func begin() -> void:
	var stream := ChartDefs.load_audio(asset("spin_sound"))
	if stream:
		ChartDefs.set_looping(stream, true)
		_spin_sound.stream = stream
		add_child(_spin_sound)


func _soul_point() -> Vector2:
	return Vector2(SOUL_X, _middle_y())


func _middle_y() -> float:
	return (TOP + size.y) / 2.0


## How far across the oval reaches at its biggest.
func _full_width() -> float:
	return size.x - SOUL_X - END_MARGIN


## The oval's half-width and half-height right now.
func _axes() -> Vector2:
	var half_height := (size.y - TOP) / 2.0 - 6.0
	var low: float = settings["oval_smallest"]
	return Vector2(lerpf(0.8, 1.0, _growth) * _full_width() / 2.0, lerpf(low, 1.0, _growth) * half_height)


## A point on the oval; 0 and 1 are at the soul, 0.5 is the far end, going over the top first.
func _on_oval(along: float) -> Vector2:
	var axes := _axes()
	var angle := PI + TAU * along
	return _soul_point() + Vector2(axes.x, 0.0) + Vector2(cos(angle) * axes.x, sin(angle) * axes.y)


## Where along the oval the blade is at this point in its flight.
func _eased(flight: float) -> float:
	return flight + (1.0 - SLOWEST) * sin(TAU * flight) / TAU


## How fast it's moving compared to average.
func _flight_rate() -> float:
	return 1.0 + (1.0 - SLOWEST) * cos(TAU * _flight)


func _blade() -> Vector2:
	return _on_oval(_eased(_flight)) if _thrown else _soul_point()


func _crosshair() -> Vector2:
	var reach := (size.y - TOP) / 2.0 - float(settings["crosshair_size"]) - 2.0
	return Vector2(SOUL_X + _full_width() * CROSSHAIR_ALONG, _middle_y() + sin(_crosshair_phase) * reach)


func _crosshair_speed() -> float:
	return settings["crosshair_speed"] * (1.0 + settings["low_hp_speed"] * (1.0 - target_health))


func _multiplier() -> float:
	var hit_size: float = settings["crosshair_size"]
	if _best > hit_size:
		return 0.0
	var bullseye := hit_size / 3.0
	if _best <= bullseye:
		return settings["max_damage"]
	return lerpf(settings["max_damage"], 1.0, (_best - bullseye) / (hit_size - bullseye))


func interrupted_multiplier() -> float:
	return _multiplier() if _best <= settings["crosshair_size"] else 0.0


func tapped() -> void:
	if not _thrown:
		_throw()


func _throw() -> void:
	_thrown = true
	if _spin_sound.stream:
		_spin_sound.play()


func tick(delta: float) -> void:
	_flash = maxf(_flash - delta * 4.0, 0.0)
	_crosshair_phase += delta * TAU * _crosshair_speed()
	if not _thrown:
		_oval_time += delta
		_growth = 0.5 - 0.5 * cos(_oval_time * TAU * settings["oval_speed"])
		_waited += delta
		if running and _waited >= settings["auto_throw"]:
			_throw()
	elif not _returned:
		_fly(delta)
	if _returned:
		trail_fade()
	else:
		trail_add(_blade_transform())


func _fly(delta: float) -> void:
	# In small steps, so a fast blade can't jump over the crosshair between frames
	var steps := 6
	for i in steps:
		_flight = minf(_flight + delta / settings["flight_time"] / steps, 1.0)
		var distance := _blade().distance_to(_crosshair())
		if distance <= settings["crosshair_size"] and _best > settings["crosshair_size"]:
			_flash = 1.0
		_best = minf(_best, distance)
	var rate := _flight_rate()
	_spin += delta * TAU * SPIN_TURNS * rate
	_spin_sound.pitch_scale = clampf(0.7 + 0.5 * rate, 0.5, 2.0)
	var far := _blade().distance_to(_soul_point()) / maxf(_full_width(), 1.0)
	_spin_sound.volume_db = linear_to_db(lerpf(1.0, FAR_VOLUME, clampf(far, 0.0, 1.0)))
	if _flight >= 1.0:
		_returned = true
		_spin_sound.stop()
		_finish()


func _finish() -> void:
	perfect = _best <= float(settings["crosshair_size"]) / 3.0
	var total := _multiplier()
	_result = "PERFECT" if perfect else ("MISS" if _best > settings["crosshair_size"] else "x%.1f" % total)
	end(total)


func _blade_transform() -> Transform2D:
	return Transform2D(_spin, Vector2.ONE * BLADE_SCALE, 0.0, _blade())


func _draw() -> void:
	draw_title()
	if _result != "":
		draw_string(font, Vector2(0, 16), _result, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, Color.YELLOW)
	elif not _thrown:
		draw_string(font, Vector2(0, 16), GameSettings.hint([["ACCEPT", "THROW"]]), HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, Color.WHITE)

	# The path it'll fly, leaving a gap at the soul
	var path_color := Color(GREEN, 0.35 if _thrown else 1.0)
	var curve := PackedVector2Array()
	for i in range(1, CURVE_POINTS):
		curve.append(_on_oval(float(i) / CURVE_POINTS))
	draw_polyline(curve, path_color, 2.0)
	for i in range(1, DOTS):
		draw_circle(_on_oval(float(i) / DOTS), 4.0, path_color)

	var aim := _crosshair()
	var hit_size: float = settings["crosshair_size"]
	var color := Color.YELLOW if _flash > 0.0 else Color(1.0, 0.2, 0.2)
	draw_arc(aim, hit_size, 0.0, TAU, 24, color, 3.0)
	draw_circle(aim, hit_size / 3.0, color)
	for side: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(aim + side * (hit_size - 2.0), aim + side * (hit_size + 5.0), color, 3.0)

	var art := custom_texture()
	if art:
		var centered := -art.get_size() / 2.0
		draw_trail(art, centered)
		if not _returned:
			draw_set_transform_matrix(_blade_transform())
			draw_texture(art, centered)
			draw_set_transform(Vector2.ZERO)
	# On top, so the blade waiting at the soul doesn't hide it
	draw_texture_rect_region(SOUL_TEXTURE, Rect2(_soul_point() - Vector2(8, 8), Vector2(16, 16)), Rect2(0, 0, 16, 16))
