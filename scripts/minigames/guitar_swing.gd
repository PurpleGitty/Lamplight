extends Minigame
## The guitar axe. It swings round a full circle toward a red point; press ACCEPT
## as it passes and it bounces back the other way, faster, toward a point further
## round. Green shows the point after that. Damage builds with every hit until a
## miss or the enemy's turn, and then what's built up lands. No hits, no damage.

const TOP := 22.0 # room for the title
const ART_ANGLE := 45.0 # the axe's art points this far clockwise from straight up
const ART_REACH := 0.9 # the head stops short of the art's corner; this much of the diagonal reaches the circle
const POINT_RED := Color(1.0, 0.2, 0.2)
const POINT_GREEN := Color(0.2, 1.0, 0.25)
const LONGEST_ARC := 320.0

var _angle := 0.0 # degrees from straight up, clockwise; keeps counting past a full turn
var _direction := 1.0
var _speed := 110.0
var _arc := 70.0 # how far this swing is
var _target := 70.0
var _hits := 0
var _flash := 0.0
var _result := ""
var _bounce := AudioStreamPlayer.new()


func begin() -> void:
	_speed = settings["start_speed"]
	_arc = settings["first_arc"]
	_target = _arc
	_bounce.stream = ChartDefs.load_audio(asset("bounce_sound"))
	add_child(_bounce)


func _next_arc() -> float:
	return minf(_arc + settings["arc_step"], LONGEST_ARC)


func _built_up() -> float:
	return _hits * settings["damage_per_hit"]


func interrupted_multiplier() -> float:
	return _built_up()


func tick(delta: float) -> void:
	_flash = maxf(_flash - delta * 4.0, 0.0)
	if running:
		_angle += _direction * _speed * delta
		# Swung past the point: that's a miss
		if (_angle - _target) * _direction > settings["tolerance"]:
			_finish()
	if running:
		trail_add(_axe_transform())
	else:
		trail_fade()


func tapped() -> void:
	if absf(_angle - _target) > settings["tolerance"]:
		_finish()
		return
	_hits += 1
	_flash = 1.0
	_speed *= settings["speed_up"]
	_bounce.pitch_scale = clampf(_speed / settings["start_speed"], 0.5, 3.0)
	if _bounce.stream:
		_bounce.play()
	_direction = -_direction
	_arc = _next_arc()
	_target += _direction * _arc


func _finish() -> void:
	_result = "MISS" if _hits == 0 else "%d HIT%s" % [_hits, "" if _hits == 1 else "S"]
	end(_built_up())


func _pivot() -> Vector2:
	return Vector2(size.x / 2.0, (TOP + size.y) / 2.0)


func _radius() -> float:
	return minf((size.y - TOP) / 2.0, size.x / 2.0) - 8.0


func _on_circle(degrees: float) -> Vector2:
	var angle := deg_to_rad(degrees)
	return _pivot() + Vector2(sin(angle), -cos(angle)) * _radius()


## Turns the axe with its handle's end at the middle and its tip on the circle.
func _axe_transform() -> Transform2D:
	var art := custom_texture()
	var reach := art.get_size().length() * ART_REACH if art else 1.0
	return Transform2D(deg_to_rad(_angle - ART_ANGLE), Vector2.ONE * _radius() / reach, 0.0, _pivot())


func _draw() -> void:
	draw_title()
	var label: String = _result if _result != "" else "x%.1f" % _built_up()
	draw_string(font, Vector2(0, 16), label, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, Color.YELLOW if _flash > 0.0 else Color.WHITE)

	draw_arc(_pivot(), _radius(), 0.0, TAU, 64, Color.WHITE, 3.0)
	draw_circle(_on_circle(_target - _direction * _next_arc()), 6.0, POINT_GREEN)
	draw_circle(_on_circle(_target), 7.0 + _flash * 4.0, Color.YELLOW if _flash > 0.0 else POINT_RED)

	var art := custom_texture()
	if art:
		var handle_at_pivot := Vector2(0.0, -art.get_height())
		draw_trail(art, handle_at_pivot)
		draw_set_transform_matrix(_axe_transform())
		draw_texture(art, handle_at_pivot)
		draw_set_transform(Vector2.ZERO)
