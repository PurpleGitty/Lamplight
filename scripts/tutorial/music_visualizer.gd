class_name MusicVisualizer
extends Node2D
## The song's spectrum as a white skyline behind the arena: low notes on the left, high on
## the right, running flat across the back as if it's painted round the inside of a giant
## cylinder you're standing in the middle of. Toward the sides of the screen the wall's
## closer, so the peaks grow and lean outward, above the ground and in its reflection, and
## it looks like it's all around you. The reflection is grey near the ground and brighter
## toward the tips.
## It listens to the Music bus, so it shows whatever song the fight's playing.

const BANDS := 56
const LOWEST := 40.0 # Hz
const HIGHEST := 12000.0
const QUIETEST := -50.0 # dB that counts as nothing
const LOUDEST := -8.0 # dB that reaches the top
const TALLEST := 75.0 # pixels, in the middle
const REFLECTION := 0.7 # the reflection's length, compared to what's above
const SAG := 8.0 # how much lower the ground is in the middle than at the edges
const EDGE_GROW := 1.0 # peaks at the screen's edges are this much taller again
const WALL_LEAN := 0.7 # how far the peaks at the edges lean outward
const HALF_WIDTH := 330.0
const RISE_SPEED := 18.0 # per second, toward a louder level
const FALL_SPEED := 5.0
const QUIET_HEIGHT := 2.0 # pixels, so the line's still there in a silence

## Where the ground is in the middle of the screen.
var ground_y := 100.0
## How tall the loudest peaks get in the middle.
var tallest := TALLEST
## Low notes on the right instead of the left.
var mirrored := false
## Multiplies the white (and the reflection's greys).
var tint := Color.WHITE
## Another visualizer to copy the levels from, instead of listening to the bus itself.
var source: MusicVisualizer
var _levels := PackedFloat32Array()
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _bus := -1
var _effect := -1


func _ready() -> void:
	z_index = -1 # over the background (drawn after it), under the enemies, board and soul
	_levels.resize(BANDS)
	if source != null:
		return
	_bus = AudioServer.get_bus_index(&"Music")
	if _bus < 0:
		return
	var effect := AudioEffectSpectrumAnalyzer.new()
	effect.buffer_length = 0.1
	_effect = AudioServer.get_bus_effect_count(_bus)
	AudioServer.add_bus_effect(_bus, effect, _effect)
	_analyzer = AudioServer.get_bus_effect_instance(_bus, _effect)


func _exit_tree() -> void:
	if _bus >= 0 and _effect >= 0 and _effect < AudioServer.get_bus_effect_count(_bus):
		AudioServer.remove_bus_effect(_bus, _effect)


func _process(delta: float) -> void:
	if source != null:
		_levels = source._levels
		queue_redraw()
		return
	for i in BANDS:
		var target := 0.0
		if _analyzer != null:
			var from := LOWEST * pow(HIGHEST / LOWEST, float(i) / BANDS)
			var to := LOWEST * pow(HIGHEST / LOWEST, float(i + 1) / BANDS)
			var loudness := _analyzer.get_magnitude_for_frequency_range(from, to).length()
			# High notes are quieter: lift them so the right side moves too
			var db := linear_to_db(maxf(loudness, 0.000001)) + 12.0 * float(i) / BANDS
			target = clampf((db - QUIETEST) / (LOUDEST - QUIETEST), 0.0, 1.0)
			target *= target # quiet parts stay low, so the loud peaks stand out
		var speed := RISE_SPEED if target > _levels[i] else FALL_SPEED
		_levels[i] = lerpf(_levels[i], target, minf(speed * delta, 1.0))
	queue_redraw()


## A smooth outline through the levels, as many points as there are columns of pixels.
func _heights(points: int) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(points)
	for p in points:
		var along := float(p) / (points - 1)
		if mirrored:
			along = 1.0 - along
		var at := along * (BANDS - 1)
		var i := floori(at)
		var j := mini(i + 1, BANDS - 1)
		var t := at - i
		t = t * t * (3.0 - 2.0 * t)
		var across := float(p) / (points - 1) * 2.0 - 1.0
		heights[p] = (QUIET_HEIGHT + lerpf(_levels[i], _levels[j], t) * tallest) * (1.0 + EDGE_GROW * across * across)
	return heights


## Where the ground is at this x.
func ground_at(x: float) -> float:
	return _ground(x)


func _ground(x: float) -> float:
	var across := x / HALF_WIDTH
	return ground_y - SAG * across * across


func _draw() -> void:
	paint(self, Transform2D())


## Draws it onto any canvas item, with `xf` taking the arena to that canvas (the editor's
## preview draws it this way).
func paint(canvas: CanvasItem, xf: Transform2D, dim := Color.WHITE) -> void:
	canvas.draw_set_transform_matrix(xf)
	var points := 120
	var heights := _heights(points)
	var top := PackedVector2Array()
	var base := PackedVector2Array()
	var under := PackedVector2Array()
	for p in points:
		var x := -HALF_WIDTH + 2.0 * HALF_WIDTH * p / (points - 1)
		var foot := Vector2(x, _ground(x))
		var up := _outward(x)
		var down := Vector2(up.x, -up.y) # mirrored in the floor: leans outward too
		base.append(foot)
		top.append(foot + up * heights[p])
		under.append(foot + down * heights[p] * REFLECTION)
	# Above the ground: solid white
	var shape := top.duplicate()
	var back := base.duplicate()
	back.reverse()
	shape.append_array(back)
	canvas.draw_colored_polygon(shape, tint * dim)
	# The reflection: a strip of quads, grey at the ground and lighter toward the tips
	for p in points - 1:
		var quad := PackedVector2Array([base[p], base[p + 1], under[p + 1], under[p]])
		var near := Color(0.2, 0.2, 0.2) * tint
		var far := Color(0.85, 0.85, 0.85) * tint
		canvas.draw_polygon(quad, PackedColorArray([near * dim, near * dim, far * dim, far * dim]))


## Up the cylinder's wall from here: straight up in the middle, leaning out toward the sides.
func _outward(x: float) -> Vector2:
	var across := x / HALF_WIDTH
	return Vector2(WALL_LEAN * across * absf(across), -1.0).normalized()
