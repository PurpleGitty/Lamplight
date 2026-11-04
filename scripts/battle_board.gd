extends UIBox
## The bullet board during the enemy's turn. An AttackRuntime (built from the
## fight's chart) works out where the board and every object should be; this
## node shows that, owns the walls the soul bumps into, and plays the open and
## retract animations.

const OPEN_TIME := 0.3
const RETRACT_TIME := 0.25
const GHOST_TIME := 0.3
const GHOST_COLOR := Color(0.25, 1.0, 0.45)

@onready var battle: Battle = owner
@onready var dim: ColorRect = $"../Background/ColorRect"

var runtime: AttackRuntime
var contents := Node2D.new() # holds the objects, placed in the attack's content frame
var ghosts := Ghosts.new()
var _objects := {} # AttackRuntime.ObjectState -> AttackObject
var _open := 0.0 # goes 0 -> 1 while the board opens
var _last_center := Vector2.ZERO
var _last_angle := 0.0
var _last_size := Vector2.ZERO


## Fading green copies of the board's outline, left behind as it retracts.
class Ghosts extends Node2D:
	var items: Array = [] # [{"xf": Transform2D, "size": Vector2, "age": float}]

	func add(xf: Transform2D, size: Vector2) -> void:
		items.append({"xf": xf, "size": size, "age": 0.0})

	func _process(delta: float) -> void:
		for g in items:
			g["age"] += delta
		items = items.filter(func(g): return g["age"] < GHOST_TIME)
		queue_redraw()

	func _draw() -> void:
		for g in items:
			var color := GHOST_COLOR
			color.a = 0.8 * (1.0 - g["age"] / GHOST_TIME)
			draw_set_transform_matrix(g["xf"])
			draw_rect(Rect2(-g["size"] / 2, g["size"]), color, false, 2.0)


func _ready() -> void:
	pulse = false
	border_inset = 1.0
	clip_contents = false
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW # objects are masked to the board's shape, even rotated
	add_child(contents)
	ghosts.z_index = z_index
	get_parent().add_child.call_deferred(ghosts)
	hide()
	dim.show()
	dim.modulate.a = 0


func _process(_delta: float) -> void:
	if runtime == null:
		return
	runtime.advance(battle.clock())
	_sync()


func is_open() -> bool:
	return runtime != null and _open >= 1.0


func open(attack: AttackRuntime) -> void:
	_clear_objects()
	runtime = attack
	for o in attack.objects:
		var node := AttackObject.new()
		node.setup(o.data, battle.enemy.display_name)
		node.hide()
		_objects[o] = node
		contents.add_child(node)

	# Clipped objects live inside the board; unclipped ones beside it
	var parent: Node = self if attack.clip else get_parent()
	if contents.get_parent() != parent:
		contents.reparent(parent, false)
	contents.z_index = 0 if attack.clip else z_index

	_open = 0.0
	show()
	var t := create_tween().set_parallel()
	t.tween_property(self, "_open", 1.0, OPEN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(dim, "modulate:a", 0.5, OPEN_TIME)
	_sync()


func close() -> void:
	_clear_objects()
	if runtime == null:
		return
	runtime = null
	var t := create_tween().set_parallel()
	t.tween_method(_retract_step, 1.0, 0.0, RETRACT_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_property(dim, "modulate:a", 0.0, RETRACT_TIME * 2)
	t.chain().tween_callback(hide)


func _retract_step(amount: float) -> void:
	var s := _last_size * amount
	_place(_last_center, s, _last_angle)
	ghosts.add(Transform2D(deg_to_rad(_last_angle), _last_center), s)


func _sync() -> void:
	_last_center = runtime.board_center + runtime.shake
	_last_angle = runtime.board_angle
	_last_size = runtime.board_size
	_place(_last_center, runtime.board_size * _open, _last_angle)

	contents.global_transform = runtime.content_transform()
	for o in runtime.objects:
		var node: AttackObject = _objects[o]
		node.visible = o.active and not o.blink_hidden
		node.harmful = o.active and o.harmful
		node.position = o.pos
		node.rotation_degrees = o.angle
		node.scale = Vector2.ONE * maxf(o.scale * o.data["sprite_scale"], 0.001)
		node.modulate.a = o.alpha
		node.damage = o.damage
		node.set_look(o.mode, o.tint)
		node.sprite.frame = clampi(ChartDefs.anim_frame(int(o.data["frame"]), int(o.data["anim_frames"]), o.data["anim_beats"], battle.clock()), 0, node.sprite.hframes - 1)
		if o.spawn_count > o.sounded:
			o.sounded = o.spawn_count
			battle.play_sound(o.data["spawn_sound"])


func _place(center: Vector2, board_size: Vector2, angle: float) -> void:
	size = board_size
	pivot_offset = board_size / 2
	position = center - board_size / 2
	rotation_degrees = angle
	update_collision()


func _clear_objects() -> void:
	for node in _objects.values():
		node.queue_free()
	_objects.clear()


func update_collision() -> void:
	$collision/upcoll.shape.size = Vector2(size.x, 2)
	$collision/upcoll.position = Vector2(size.x / 2, -1)

	$collision/downcoll.shape.size = Vector2(size.x, 2)
	$collision/downcoll.position = Vector2(size.x / 2, size.y + 1)

	$collision/rightcoll.shape.size = Vector2(2, size.y)
	$collision/rightcoll.position = Vector2(size.x + 1, size.y / 2)

	$collision/leftcoll.shape.size = Vector2(2, size.y)
	$collision/leftcoll.position = Vector2(-1, size.y / 2)
