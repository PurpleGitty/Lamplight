class_name MathAttack
extends RefCounted
## One Math Attack node while it plays: runs its formula for every bullet, draws the
## result, and says whether the soul's touching any of it. Nothing's remembered from
## frame to frame, so any moment of it can be worked out from the time alone, which is
## why it can be scrubbed in the preview. Positions are in the board's content frame,
## like every other object's.

const GRAZE_FAINT := 0.3
const OUTSIDE_FAINT := 0.3
const MAX_DRAW_SIZE := 4096.0
const DEFAULT_HIT := 0.75 # hitbox compared to what's drawn, if the formula doesn't say

## X_ is where each value sits in a bullet's slice of `out`, in MathFormula.OUTPUTS order.
const X_ := 0
const Y_ := 1
const SIZE_ := 2
const ANGLE_ := 3
const SX_ := 4
const SY_ := 5
const R_ := 6
const G_ := 7
const B_ := 8
const ALPHA_ := 9
const SHOW_ := 10
const HIT_ := 11
const HARM_ := 12
const LINK_ := 13
const WIDTH_ := 14

static var _dot: Texture2D # the plain white circle formulas can colour

var event: Dictionary
var formula: MathFormula.Compiled
var count := 1
var start := 0.0
var end := 0.0
var damage := 20
var mode := "normal"
var label := "math"
var active := false
var out := PackedFloat32Array()
var texture: Texture2D
var _half := Vector2(0.5, 0.5) # half a sprite, for a size of 1


func _init(ev: Dictionary) -> void:
	event = ev
	var p: Dictionary = ev["params"]
	start = float(ev["beat"])
	end = start + maxf(float(ev["length"]), 0.0001)
	count = clampi(int(p["count"]), 1, MathFormula.MAX_BULLETS)
	damage = maxi(int(p["damage"]), 0)
	mode = str(p["mode"])
	label = str(p["name"])
	formula = MathFormula.compile(str(p["formula"]))
	out.resize(count * MathFormula.STRIDE)
	var path := str(p["sprite"])
	texture = ChartDefs.load_texture(path) if path != "" else dot()
	var tex_size := texture.get_size()
	_half = tex_size / maxf(maxf(tex_size.x, tex_size.y), 1.0) / 2.0


static func dot() -> Texture2D:
	if _dot == null:
		var side := 32
		var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
		var middle := (side - 1) / 2.0
		for y in side:
			for x in side:
				if Vector2(x, y).distance_to(Vector2(middle, middle)) <= side / 2.0:
					image.set_pixel(x, y, Color.WHITE)
		_dot = ImageTexture.create_from_image(image)
	return _dot


func can_run() -> bool:
	return formula.ok() and not MathFormula.too_heavy(formula, count)


## How much of the frame's allowance this takes.
func cost() -> int:
	return formula.cost * count


## Works out every bullet at this many timeline units after the node starts.
func evaluate(elapsed: float, units_per_second: float, bpm: float, soul: Vector2, board: Vector2) -> void:
	var seconds := elapsed / maxf(units_per_second, 0.0001)
	var length := end - start
	formula.run(out, count, seconds * bpm / 60.0, elapsed / length, seconds, soul.x, soul.y, board.x, board.y)
	active = true


## Draws it. `base` takes the content frame to wherever `canvas` draws.
## `is_inside`, if given, fades whatever's outside the board.
func draw(canvas: CanvasItem, base: Transform2D, is_inside := Callable()) -> void:
	if not active:
		return
	var faint_outside := is_inside.is_valid()
	canvas.draw_set_transform_matrix(base)
	var plain := true # the canvas is at `base`, not turned for a bullet
	var at := 0
	for index in count:
		var bullet := at
		at += MathFormula.STRIDE
		if out[bullet + SHOW_] <= 0.0 or out[bullet + ALPHA_] <= 0.0:
			continue
		var x := out[bullet + X_]
		var y := out[bullet + Y_]
		var size := minf(out[bullet + SIZE_], MAX_DRAW_SIZE)
		var angle := out[bullet + ANGLE_]
		var wide := out[bullet + SX_]
		var tall := out[bullet + SY_]
		if not is_finite(x + y + size + angle + wide + tall):
			continue
		var pos := Vector2(x, y)
		var color := Color(out[bullet + R_], out[bullet + G_], out[bullet + B_], clampf(out[bullet + ALPHA_], 0.0, 1.0))
		if faint_outside and not is_inside.call(pos):
			color.a *= OUTSIDE_FAINT
		if index > 0 and out[bullet + LINK_] > 0.0:
			var thickness := minf(out[bullet + WIDTH_], MAX_DRAW_SIZE)
			var from := Vector2(out[bullet - MathFormula.STRIDE + X_], out[bullet - MathFormula.STRIDE + Y_])
			if thickness > 0.0 and from.is_finite():
				if not plain:
					canvas.draw_set_transform_matrix(base)
					plain = true
				canvas.draw_line(from, pos, color, thickness)
		if size <= 0.0:
			continue
		var half := _half * size * Vector2(wide, tall)
		if angle == 0.0:
			if not plain:
				canvas.draw_set_transform_matrix(base)
				plain = true
			canvas.draw_texture_rect(texture, Rect2(pos - half, half * 2.0), false, color)
		else:
			canvas.draw_set_transform_matrix(base * Transform2D(deg_to_rad(angle), pos))
			plain = false
			canvas.draw_texture_rect(texture, Rect2(-half, half * 2.0), false, color)
	canvas.draw_set_transform_matrix(base)


## The hitboxes, for the editor.
func draw_hitboxes(canvas: CanvasItem, base: Transform2D) -> void:
	if not active:
		return
	canvas.draw_set_transform_matrix(base)
	var hurts := Color(1, 0.2, 0.2, 0.9)
	var at := 0
	for index in count:
		var bullet := at
		at += MathFormula.STRIDE
		if out[bullet + SHOW_] <= 0.0 or out[bullet + HARM_] <= 0.0:
			continue
		var pos := Vector2(out[bullet + X_], out[bullet + Y_])
		if not pos.is_finite():
			continue
		var radius := _radius(bullet)
		if radius > 0.0:
			canvas.draw_circle(pos, radius, hurts, false, 1.0)
		if index > 0 and out[bullet + LINK_] > 0.0 and out[bullet + WIDTH_] > 0.0:
			var from := Vector2(out[bullet - MathFormula.STRIDE + X_], out[bullet - MathFormula.STRIDE + Y_])
			if from.is_finite():
				canvas.draw_line(from, pos, hurts, maxf(out[bullet + WIDTH_] * DEFAULT_HIT, 1.0))


## Whether any harmful bullet or line reaches this rectangle (in world coordinates).
## `reach` is how far off still counts, for grazing.
func touches(rect: Rect2, content: Transform2D, reach: float, size_scale: float) -> bool:
	if not active:
		return false
	var middle := rect.get_center()
	var low := rect.position
	var high := rect.end
	var at := 0
	for index in count:
		var bullet := at
		at += MathFormula.STRIDE
		if out[bullet + SHOW_] <= 0.0 or out[bullet + HARM_] <= 0.0:
			continue
		var local := Vector2(out[bullet + X_], out[bullet + Y_])
		if not local.is_finite():
			continue
		var pos := content * local
		var radius := _radius(bullet) * size_scale
		if radius > 0.0 and radius < INF:
			var off := pos - pos.clamp(low, high)
			if off.length_squared() <= (radius + reach) * (radius + reach):
				return true
		if index > 0 and out[bullet + LINK_] > 0.0 and out[bullet + WIDTH_] > 0.0:
			var from_local := Vector2(out[bullet - MathFormula.STRIDE + X_], out[bullet - MathFormula.STRIDE + Y_])
			if from_local.is_finite():
				var closest := Geometry2D.get_closest_point_to_segment(middle, content * from_local, pos)
				var line_radius := out[bullet + WIDTH_] * DEFAULT_HIT / 2.0 * size_scale + reach
				if (closest - closest.clamp(low, high)).length_squared() <= line_radius * line_radius:
					return true
	return false


## A bullet's hitbox radius: what `hit` says, or based on what's drawn.
func _radius(bullet: int) -> float:
	var hit := out[bullet + HIT_]
	if hit < 0.0:
		hit = out[bullet + SIZE_] * DEFAULT_HIT
	return hit / 2.0 if is_finite(hit) else 0.0
