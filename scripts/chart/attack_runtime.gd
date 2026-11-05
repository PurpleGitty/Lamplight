class_name AttackRuntime
extends RefCounted
## Plays one enemy turn of a chart: works out where the board and every object
## are at any beat. The game and the attack editor's preview both use this, so
## what you see in the editor is what happens in the fight.
##
## Objects live in the board's "content frame": positions relative to the
## board's centre, turned by content_angle. Rotating the board with
## rotate_contents turns that frame, which swings every object's position AND
## trajectory along with it.
##
## Random nodes are seeded by their id, so they land in the same place every
## time (in the editor and in the game).

const STEP := 1.0 / 16.0 # longest simulation step, in beats

class ObjectState:
	var data: Dictionary
	var active := false
	var pos := Vector2.ZERO # content frame
	var vel := Vector2.ZERO # pixels per beat, content frame
	var angle := 0.0 # degrees, relative to the content frame
	var scale := 1.0 # on top of the object's sprite_scale; scales the hitbox too
	var alpha := 1.0
	var harmful := true
	var blink_hidden := false # in the "off" half of a telegraph blink
	var sprite := ""
	var mode := "normal" # normal, blue (hurts if you move), orange (hurts if you stay still)
	var tint := "ffffff"
	var damage := 0
	var spawn_count := 0 # goes up each time it spawns, so sound can follow along
	var sounded := 0
	var move_op = null # the op currently steering its position, if any

var start_beat := 0.0
var end_beat := 0.0
var t := 0.0
var soul_position: Callable # () -> Vector2, the soul in world coordinates

var board_center := Vector2.ZERO
var board_size := Vector2(128, 128)
var board_angle := 0.0 # degrees, the box itself
var content_angle := 0.0 # degrees, the frame objects live in
var shake := Vector2.ZERO
var clip := true
var soul_start := Vector2.ZERO

var objects: Array[ObjectState] = []
var maths: Array[MathAttack] = []
var _units_per_second := 1.0
var _bpm := 120.0
var _step := STEP
var _by_id := {} # object id -> ObjectState
var _queue: Array = [] # [{"ev": event, "obj": ObjectState or null}], in firing order
var _next := 0
var _ops: Array = [] # things in progress (tweens), as dictionaries


func _init(chart: Dictionary, attack: Dictionary, soul: Callable) -> void:
	start_beat = attack["start"]
	end_beat = attack["end"]
	t = start_beat
	soul_position = soul
	_step = 1.0 if ChartDefs.uses_frames(chart) else STEP

	var p: Dictionary = attack["begin"]["params"]
	board_size = Vector2(p["width"], p["height"])
	board_center = Vector2(p["board_x"], p["board_y"])
	soul_start = board_center + Vector2(p["soul_x"], p["soul_y"])
	clip = p["clip"]

	_units_per_second = ChartDefs.units_per_second(chart)
	_bpm = float(chart["bpm"])
	for ev in chart["board_events"]:
		if _in_range(ev):
			if ev["type"] == "math_attack":
				maths.append(MathAttack.new(ev))
			else:
				_queue.append({"ev": ev, "obj": null})
	for data in chart["objects"]:
		var state := ObjectState.new()
		state.data = data
		var used := false
		for ev in data["events"]:
			if _in_range(ev):
				_queue.append({"ev": ev, "obj": state})
				used = true
		if used:
			objects.append(state)
			_by_id[int(data["id"])] = state
	_queue.sort_custom(_fires_before)
	_fire_due()
	_run_maths()


func _in_range(ev: Dictionary) -> bool:
	return ev["beat"] >= start_beat and ev["beat"] < end_beat


## Same beat: spawns first, then in the order they were made.
func _fires_before(a: Dictionary, b: Dictionary) -> bool:
	if a["ev"]["beat"] != b["ev"]["beat"]:
		return a["ev"]["beat"] < b["ev"]["beat"]
	var a_spawn: bool = a["ev"]["type"] == "spawn"
	var b_spawn: bool = b["ev"]["type"] == "spawn"
	if a_spawn != b_spawn:
		return a_spawn
	return a["ev"]["id"] < b["ev"]["id"]


## Moves the simulation forward to `to_beat` (it never goes backwards; make a
## new AttackRuntime to rewind).
func advance(to_beat: float) -> void:
	to_beat = minf(to_beat, end_beat)
	while t < to_beat:
		var next_t := minf(to_beat, t + _step)
		if _next < _queue.size():
			next_t = minf(next_t, _queue[_next]["ev"]["beat"])
		var dt := next_t - t
		for o in objects:
			if o.active and o.move_op == null and o.vel != Vector2.ZERO:
				o.pos += o.vel * dt
		t = next_t
		_apply_ops()
		_fire_due()
	_run_maths()


## Works out every Math Attack playing now. There's a limit on how much can run in
## one frame, however many are stacked up, so nothing in a chart can freeze the game.
func _run_maths() -> void:
	var allowance := MathFormula.MAX_COST
	for m in maths:
		m.active = false
		if t >= m.start and t < m.end and m.can_run() and m.cost() <= allowance:
			allowance -= m.cost()
			m.evaluate(t - m.start, _units_per_second, _bpm, _soul_local(), board_size)


## The Math Attack hurting this rectangle (the soul's hitbox, in world coordinates), or null.
func math_hurting(rect: Rect2, moving: bool, size_scale := 1.0) -> MathAttack:
	var content := content_transform()
	for m in maths:
		if (m.mode == "normal" or (m.mode == "blue") == moving) and m.touches(rect, content, 0.0, size_scale):
			return m
	return null


## Whether any Math Attack is within this distance of a point, for grazing.
func math_near(point: Vector2, reach: float, size_scale := 1.0) -> bool:
	var content := content_transform()
	for m in maths:
		if m.touches(Rect2(point, Vector2.ZERO), content, reach, size_scale):
			return true
	return false


# --- for whoever draws it ---

func board_transform() -> Transform2D:
	return Transform2D(deg_to_rad(board_angle), board_center + shake)


func content_transform() -> Transform2D:
	return Transform2D(deg_to_rad(content_angle), board_center + shake)


## Where the object is on screen; scale is the object's sprite_scale times its Scale node.
func object_transform(o: ObjectState) -> Transform2D:
	var s: float = o.scale * o.data["sprite_scale"]
	return content_transform() * Transform2D(deg_to_rad(o.angle), Vector2(s, s), 0.0, o.pos)


func is_shown(o: ObjectState) -> bool:
	return o.active and not o.blink_hidden and o.alpha > 0.001


func is_inside_board(content_pos: Vector2) -> bool:
	var b := _content_to_box(content_pos)
	return absf(b.x) <= board_size.x / 2 and absf(b.y) <= board_size.y / 2


# --- firing nodes ---

func _fire_due() -> void:
	while _next < _queue.size() and _queue[_next]["ev"]["beat"] <= t:
		_fire(_queue[_next]["ev"], _queue[_next]["obj"])
		_next += 1


func _fire(ev: Dictionary, o: ObjectState) -> void:
	var p: Dictionary = ev["params"]
	var length := maxf(ev["length"], 0.0001)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ev["id"]) * 7919 + 1
	if o != null and not o.active and ev["type"] not in ["spawn", "despawn"]:
		_spawn(o, {}, rng) # an object with no Spawn node appears at the board's centre

	match ev["type"]:
		"rotate_board":
			var op := _op("board_angle", null, ev["beat"], length, p["easing"], false)
			op["degrees"] = p["degrees"]
			op["last"] = 0.0
			op["contents"] = p["rotate_contents"]
			op["excluded"] = []
			if p["rotate_contents"] and not p["include_outside"]:
				for other in objects:
					if other.active and not is_inside_board(other.pos):
						op["excluded"].append(other)
		"resize_board":
			var op := _op("board_size", null, ev["beat"], length, p["easing"])
			op["from"] = board_size
			op["to"] = Vector2(p["width"], p["height"])
		"move_board":
			var op := _op("board_move", null, ev["beat"], length, p["easing"])
			op["from"] = board_center
			op["to"] = Vector2(p["x"], p["y"])
			op["follow"] = p["contents_follow"]
		"shake_board":
			var op := _op("shake", null, ev["beat"], length, "linear")
			op["strength"] = p["strength"]
		"spawn":
			_spawn(o, p, rng)
			if p["fade_in"] > 0.0:
				o.alpha = 0.0
				var op := _op("alpha", o, ev["beat"], p["fade_in"], "linear")
				op["from"] = 0.0
				op["to"] = 1.0
		"despawn":
			_clear_ops(o)
			o.active = false
		"move_to":
			_move(o, ev, Vector2(p["x"], p["y"]))
		"move_by":
			_move(o, ev, o.pos + Vector2(p["dx"], p["dy"]))
		"random_point":
			_move(o, ev, _random_in_board(rng, p["margin"]))
		"target_soul":
			var target := _soul_local()
			if p["mode"] == "fling":
				_stop_moving(o)
				o.vel = (target - o.pos) / length
			else:
				_move(o, ev, target)
		"launch":
			_stop_moving(o)
			var dir: Vector2
			match p["aim"]:
				"at_soul":
					dir = (_soul_local() - o.pos).normalized()
				"away_from_board_centre":
					dir = o.pos.normalized() if o.pos != Vector2.ZERO else Vector2.DOWN
				"facing":
					dir = Vector2.RIGHT.rotated(deg_to_rad(o.angle))
				_:
					dir = Vector2.RIGHT.rotated(deg_to_rad(p["angle"]))
			o.vel = dir * p["speed"]
		"stop":
			_stop_moving(o)
			o.vel = Vector2.ZERO
		"orbit":
			_stop_moving(o)
			o.vel = Vector2.ZERO
			var center := Vector2.ZERO if p["around"] == "board_centre" else _soul_local()
			var op := _op("orbit", o, ev["beat"], length, p["easing"])
			op["center"] = center
			op["offset"] = o.pos - center
			op["degrees"] = p["degrees"]
			o.move_op = op
		"spin":
			var op := _op("angle", o, ev["beat"], length, p["easing"])
			op["from"] = o.angle
			op["to"] = o.angle + p["degrees"]
		"face_soul":
			var target_angle: float = rad_to_deg((_soul_local() - o.pos).angle()) + p["offset"]
			var op := _op("angle", o, ev["beat"], length, p["easing"])
			op["from"] = o.angle
			op["to"] = o.angle + wrapf(target_angle - o.angle, -180.0, 180.0)
		"scale_to":
			var op := _op("scale", o, ev["beat"], length, p["easing"])
			op["from"] = o.scale
			op["to"] = p["scale"]
		"fade_to":
			var op := _op("alpha", o, ev["beat"], length, p["easing"])
			op["from"] = o.alpha
			op["to"] = p["alpha"]
		"telegraph":
			var op := _op("telegraph", o, ev["beat"], length, "linear")
			op["rate"] = p["blinks_per_beat"]
			op["restore"] = o.harmful
			o.harmful = false
		"set_harmful":
			o.harmful = p["harmful"]
		"change_objects":
			for id in p["objects"]:
				if _by_id.has(int(id)):
					_change_object(_by_id[int(id)], p["changes"], ev["beat"], length, p["easing"])


func _change_object(o: ObjectState, changes: Array, start: float, length: float, easing: String) -> void:
	for change in changes:
		var value = change["value"]
		match change["key"]:
			"sprite":
				o.sprite = value if value != "" else o.data["sprite"]
			"mode":
				o.mode = value
			"tint":
				o.tint = value
			"harmful":
				o.harmful = value
			"damage":
				o.damage = int(value)
			"alpha":
				var op := _op("alpha", o, start, length, easing)
				op["from"] = o.alpha
				op["to"] = float(value)
			"scale":
				var op := _op("scale", o, start, length, easing)
				op["from"] = o.scale
				op["to"] = float(value)


func _spawn(o: ObjectState, p: Dictionary, rng: RandomNumberGenerator) -> void:
	_clear_ops(o)
	o.active = true
	o.spawn_count += 1
	o.mode = o.data["mode"]
	o.sprite = o.data["sprite"]
	o.tint = o.data["tint"]
	o.damage = int(o.data["damage"])
	o.vel = Vector2.ZERO
	o.scale = 1.0
	o.alpha = 1.0
	o.harmful = true
	o.blink_hidden = false
	o.angle = p.get("angle", 0.0)
	match p.get("mode", "fixed"):
		"random_in_board":
			o.pos = _random_in_board(rng, p["margin"])
		"random_on_edge":
			o.pos = _random_on_edge(rng, p["margin"])
		"relative_to_soul":
			o.pos = _soul_local() + Vector2(p["x"], p["y"])
		_:
			o.pos = Vector2(p.get("x", 0.0), p.get("y", 0.0))


func _move(o: ObjectState, ev: Dictionary, target: Vector2) -> void:
	_stop_moving(o)
	o.vel = Vector2.ZERO
	var op := _op("pos", o, ev["beat"], maxf(ev["length"], 0.0001), ev["params"]["easing"])
	op["from"] = o.pos
	op["to"] = target
	o.move_op = op


## Starts something that plays out over time. A new one replaces an older one
## of the same kind on the same object (except board rotations, which stack).
func _op(kind: String, o: ObjectState, start: float, length: float, easing: String, replace := true) -> Dictionary:
	if replace:
		for old in _ops.duplicate():
			if old["kind"] == kind and old["obj"] == o:
				_ops.erase(old)
	var op := {"kind": kind, "obj": o, "start": start, "end": start + length, "ease": easing}
	_ops.append(op)
	return op


func _stop_moving(o: ObjectState) -> void:
	if o.move_op != null:
		_ops.erase(o.move_op)
		o.move_op = null


func _clear_ops(o: ObjectState) -> void:
	for op in _ops.duplicate():
		if op["obj"] == o:
			_ops.erase(op)
	o.move_op = null
	o.blink_hidden = false


# --- ops in progress ---

func _apply_ops() -> void:
	for op in _ops.duplicate():
		_apply(op)
		if t >= op["end"]:
			_ops.erase(op)
			_finish(op)


func _apply(op: Dictionary) -> void:
	var raw := clampf((t - op["start"]) / maxf(op["end"] - op["start"], 0.0001), 0.0, 1.0)
	var e := ChartDefs.ease_value(raw, op["ease"])
	var o: ObjectState = op["obj"]
	match op["kind"]:
		"pos":
			o.pos = op["from"].lerp(op["to"], e)
		"orbit":
			o.pos = op["center"] + op["offset"].rotated(deg_to_rad(op["degrees"] * e))
		"angle":
			o.angle = lerpf(op["from"], op["to"], e)
		"scale":
			o.scale = lerpf(op["from"], op["to"], e)
		"alpha":
			o.alpha = lerpf(op["from"], op["to"], e)
		"telegraph":
			o.blink_hidden = fmod((t - op["start"]) * op["rate"], 1.0) >= 0.5
		"board_angle":
			var value: float = op["degrees"] * e
			var delta: float = value - op["last"]
			op["last"] = value
			board_angle += delta
			if op["contents"]:
				content_angle += delta
				# Objects left out of the turn get turned back, so they don't move on screen
				for other: ObjectState in op["excluded"]:
					other.pos = other.pos.rotated(-deg_to_rad(delta))
					other.vel = other.vel.rotated(-deg_to_rad(delta))
					other.angle -= delta
		"board_size":
			board_size = op["from"].lerp(op["to"], e)
		"board_move":
			var new_center: Vector2 = op["from"].lerp(op["to"], e)
			var moved := new_center - board_center
			board_center = new_center
			if not op["follow"]:
				for other in objects:
					other.pos -= moved.rotated(-deg_to_rad(content_angle))
		"shake":
			var s: float = op["strength"] * (1.0 - raw)
			shake = Vector2(randf_range(-s, s), randf_range(-s, s))


func _finish(op: Dictionary) -> void:
	var o: ObjectState = op["obj"]
	match op["kind"]:
		"telegraph":
			o.blink_hidden = false
			o.harmful = op["restore"]
		"shake":
			shake = Vector2.ZERO
	if o != null and o.move_op == op:
		o.move_op = null


# --- coordinates ---

func _soul_local() -> Vector2:
	return (soul_position.call() - board_center - shake).rotated(-deg_to_rad(content_angle))


func _box_to_content(v: Vector2) -> Vector2:
	return v.rotated(deg_to_rad(board_angle - content_angle))


func _content_to_box(v: Vector2) -> Vector2:
	return v.rotated(deg_to_rad(content_angle - board_angle))


func _random_in_board(rng: RandomNumberGenerator, margin: float) -> Vector2:
	var half := (board_size / 2 - Vector2(margin, margin)).max(Vector2.ZERO)
	return _box_to_content(Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y)))


func _random_on_edge(rng: RandomNumberGenerator, margin: float) -> Vector2:
	var half := board_size / 2 + Vector2(margin, margin)
	var point: Vector2
	match rng.randi() % 4:
		0: point = Vector2(rng.randf_range(-half.x, half.x), -half.y)
		1: point = Vector2(half.x, rng.randf_range(-half.y, half.y))
		2: point = Vector2(rng.randf_range(-half.x, half.x), half.y)
		_: point = Vector2(-half.x, rng.randf_range(-half.y, half.y))
	return _box_to_content(point)
