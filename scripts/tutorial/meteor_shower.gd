class_name MeteorShower
extends Node2D
## A faint shower of shooting stars across the sky over the arena. Each one leaves a
## streak that fades away behind it, and the floor reflects them all, squashed and dim,
## the same way it reflects the music visualizer.
## Add two: one for the sky (behind the visualizer) and one in front of the visualizer's
## reflection with `source` set to the first, which draws the same stars on the floor.

const RATE := 3.0 # stars a second, once it's going
const RAMP_UP := 3.0 # seconds to get going
const HEAD := 0.6 # how bright the head is
const TRAIL := 0.3 # how bright the streak is, just behind the head
const FADE := 0.7 # seconds for a streak to fade once its star burns out
const FLOOR_SQUASH := 0.4 # reflections are this tall compared to what's above
const FLOOR_DIM := 0.35

## The stars, shared by the sky and its reflection: each is a Dictionary with the
## start, the direction, speed, how long it burns, its streak length and its age.
var sky: Array = []
## Draws the reflection of this one's stars instead of its own.
var source: MeteorShower
## Where the ground is, at any x (the visualizer's ground_at).
var ground: Callable
var _running := 0.0
var _direction := Vector2(-1.0, 0.55).normalized()


func _ready() -> void:
	if randf() < 0.5:
		_direction.x = -_direction.x


func _process(delta: float) -> void:
	if source == null:
		_running += delta
		var rate := RATE * minf(_running / RAMP_UP, 1.0)
		if randf() < rate * delta:
			_launch()
		for star in sky:
			star["age"] += delta
		sky = sky.filter(func(star): return star["age"] < star["life"] + FADE)
	queue_redraw()


func _launch() -> void:
	# Starts above the screen or off the side it's coming from, high in the sky
	var start := Vector2(randf_range(-360.0, 360.0), randf_range(-300.0, -200.0))
	start.x -= _direction.x * 120.0
	sky.append({
		"start": start,
		"direction": _direction.rotated(randf_range(-0.06, 0.06)),
		"speed": randf_range(420.0, 700.0),
		"life": randf_range(0.35, 0.8),
		"length": randf_range(70.0, 150.0),
		"age": 0.0,
	})


func _draw() -> void:
	var reflection := source != null
	for star in (source.sky if reflection else sky):
		var travelled: float = star["speed"] * minf(star["age"], star["life"])
		var head: Vector2 = star["start"] + star["direction"] * travelled
		var tail: Vector2 = star["start"] + star["direction"] * maxf(travelled - star["length"], 0.0)
		var burnt_out: float = clampf((star["age"] - star["life"]) / FADE, 0.0, 1.0)
		var bright := 1.0 - burnt_out
		if bright <= 0.0:
			continue
		var head_alpha := HEAD * (0.0 if burnt_out > 0.0 else 1.0)
		var colors := PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, TRAIL * bright), Color(1, 1, 1, head_alpha)])
		var points := PackedVector2Array([tail, tail.lerp(head, 0.85), head])
		if reflection:
			for i in points.size():
				points[i] = _reflected(points[i])
				colors[i].a *= FLOOR_DIM
		draw_polyline_colors(points, colors, -1.0, false)
		if head_alpha > 0.0:
			draw_rect(Rect2(points[2].round() - Vector2.ONE, Vector2(2, 2)), Color(1, 1, 1, head_alpha * (FLOOR_DIM if reflection else 1.0)))


func _reflected(point: Vector2) -> Vector2:
	var floor_y: float = ground.call(point.x) if ground.is_valid() else 100.0
	return Vector2(point.x, floor_y + (floor_y - point.y) * FLOOR_SQUASH)
