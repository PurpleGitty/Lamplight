extends Control
## The editor's preview of the battle screen at the playhead: the board, the
## soul and every object, worked out by the same AttackRuntime the game uses.
##   - Drag the soul to move it (Target Soul / Face Soul aim at it).
##   - With one node selected, yellow markers show positions you can drag.
##   - Playtest: press play and dodge with the arrow keys.
## Objects that would be hidden outside a clipped board are drawn faintly.

const SCREEN := Rect2(-320, -240, 640, 480)
const SOUL_SPEED := 128.0
const FONT = preload("res://fonts/PixelOperator.ttf")
const BACKGROUND = preload("res://sprites/background.png")
const SOUL = preload("res://sprites/candy_soul.png")

var editor
var runtime: AttackRuntime
var soul := Vector2.ZERO # world position (0, 0 = middle of the screen)
var hits := 0
var _attack_id := -1
var _invincible := 0.0
var _drag := "" # "", "soul", "marker"
var _drag_marker: Dictionary
var _textures := {}
var _sound: AudioStreamPlayer


func _ready() -> void:
	clip_contents = true
	focus_mode = FOCUS_CLICK
	mouse_filter = MOUSE_FILTER_STOP


## Something in the chart changed: rebuild the simulation next frame.
func invalidate() -> void:
	runtime = null


func attack_at(b: float) -> Dictionary:
	for a in ChartDefs.attacks(editor.chart):
		if a["start"] <= b and b < a["end"]:
			return a
	return {}


func _process(delta: float) -> void:
	var attack := attack_at(editor.beat)
	if attack.is_empty():
		runtime = null
		_attack_id = -1
	else:
		var id: int = attack["begin"]["id"]
		# The simulation only runs forwards, so rebuild it after rewinding or editing
		if runtime == null or id != _attack_id or editor.beat < runtime.t - 0.0001:
			runtime = AttackRuntime.new(editor.chart, attack, func(): return soul)
			if id != _attack_id:
				soul = runtime.soul_start
				hits = 0
			_attack_id = id
		runtime.advance(editor.beat)
		for o in runtime.objects:
			if o.spawn_count > o.sounded:
				o.sounded = o.spawn_count
				if editor.playing and editor.direction > 0.0:
					_play(o.data["spawn_sound"])

	if editor.playtest and editor.playing and runtime != null:
		_playtest(delta)
	queue_redraw()


func _playtest(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	soul += dir * SOUL_SPEED * delta * editor.rate
	# Keep the soul inside the (possibly rotated) board
	var box := runtime.board_transform()
	var local := box.affine_inverse() * soul
	var half := runtime.board_size / 2 - Vector2(5, 5)
	soul = box * local.clamp(-half, half)

	_invincible -= delta
	if _invincible > 0.0:
		return
	for o in runtime.objects:
		var moving := dir != Vector2.ZERO
		if runtime.is_shown(o) and o.harmful and _touches(o) and (o.mode == "normal" or (o.mode == "blue") == moving):
			hits += 1
			_invincible = 1.0
			return


func _play(path: String) -> void:
	var stream := ChartDefs.load_audio(path)
	if stream == null:
		return
	if _sound == null:
		_sound = AudioStreamPlayer.new()
		add_child(_sound)
	_sound.stream = stream
	_sound.play()


func _touches(o) -> bool:
	var xf := runtime.object_transform(o)
	var local := xf.affine_inverse() * soul
	var s: float = maxf(o.data["sprite_scale"], 0.001)
	var half: Vector2 = Vector2(o.data["hitbox_w"], o.data["hitbox_h"]) / s / 2 + Vector2(4, 4) / (s * o.scale)
	return absf(local.x) <= half.x and absf(local.y) <= half.y


func _view() -> Transform2D:
	var k := minf(size.x / 680.0, size.y / 520.0)
	return Transform2D(0.0, Vector2(k, k), 0.0, size / 2)


func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = ChartDefs.load_texture(path)
	return _textures[path]


# --- drawing ---

func _draw() -> void:
	var view := _view()
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	draw_set_transform_matrix(view)
	draw_texture_rect(BACKGROUND, SCREEN, false, Color(0.4, 0.4, 0.4))
	draw_rect(SCREEN, Color(1, 1, 1, 0.3), false, 1.0)

	if runtime != null:
		draw_rect(SCREEN, Color(0, 0, 0, 0.5))
		var board_xf := view * runtime.board_transform()
		var half := runtime.board_size / 2
		draw_set_transform_matrix(board_xf)
		draw_rect(Rect2(-half, runtime.board_size), Color.BLACK)

		var current = editor.current_object()
		for o in runtime.objects:
			if o.active:
				_draw_object(view, o, o.data == current)

		draw_set_transform_matrix(board_xf)
		draw_rect(Rect2(-half, runtime.board_size), Color.WHITE, false, 2.0)
	else:
		draw_set_transform_matrix(view)
		var next := "no more attacks"
		for a in ChartDefs.attacks(editor.chart):
			if a["start"] > editor.beat:
				next = "next attack at %s %s" % [editor.unit_name(), snappedf(a["start"], 0.01)]
				break
		draw_string(FONT, Vector2(-200, 0), "PLAYER'S TURN  (%s)" % next, HORIZONTAL_ALIGNMENT_CENTER, 400, 16, Color(1, 1, 1, 0.6))

	# Soul (second frame flickers while invincible, like in the game)
	draw_set_transform_matrix(view)
	var frame := 16 if _invincible > 0.0 and fmod(_invincible, 0.2) >= 0.1 else 0
	draw_texture_rect_region(SOUL, Rect2(soul - Vector2(8, 7), Vector2(16, 16)), Rect2(frame, 0, 16, 16))

	for m in _markers():
		var p: Vector2 = m["world"]
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)]), Color.YELLOW)
		draw_string(FONT, p + Vector2(8, 4), m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.YELLOW)

	draw_set_transform_matrix(Transform2D())
	var info := "drag the soul to move it"
	if editor.playtest:
		info = "PLAYTEST - press play, arrows to dodge.   hits: %d" % hits
	draw_string(FONT, Vector2(8, size.y - 8), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))


func _draw_object(view: Transform2D, o, is_current: bool) -> void:
	var data: Dictionary = o.data
	var tex := _texture(data["sprite"])
	var frames := maxi(int(data["hframes"]), 1)
	var frame_size := Vector2(tex.get_width() / frames, tex.get_height())
	var shown_frame := ChartDefs.anim_frame(int(data["frame"]), int(data["anim_frames"]), data["anim_beats"], editor.beat)
	var src := Rect2(Vector2(clampi(shown_frame, 0, frames - 1) * frame_size.x, 0), frame_size)
	var alpha: float = o.alpha
	if runtime.clip and not runtime.is_inside_board(o.pos):
		alpha *= 0.3 # would be hidden in the game
	if o.blink_hidden:
		alpha *= 0.2
	draw_set_transform_matrix(view * runtime.object_transform(o))
	var tint := Color(o.tint)
	if o.mode == "blue":
		tint *= AttackObject.BLUE
	elif o.mode == "orange":
		tint *= AttackObject.ORANGE
	tint.a *= alpha
	draw_texture_rect_region(tex, Rect2(-frame_size / 2, frame_size), src, tint)

	var s: float = maxf(data["sprite_scale"], 0.001)
	var hitbox := Vector2(data["hitbox_w"], data["hitbox_h"]) / s
	if editor.show_hitboxes:
		var color := Color(1, 0.2, 0.2, 0.9) if o.harmful else Color(0.4, 0.4, 1, 0.6)
		draw_rect(Rect2(-hitbox / 2, hitbox), color, false, 1.0 / (s * o.scale))
	if is_current:
		var outline: Vector2 = frame_size.max(hitbox) + Vector2(4, 4) / (s * o.scale)
		draw_rect(Rect2(-outline / 2, outline), Color.YELLOW, false, 1.0 / (s * o.scale))


# --- markers: draggable positions for the selected node ---

## [{"label", "world", "keys": [x key, y key], "origin": world point the values are measured from}]
func _markers() -> Array:
	if editor.selected.size() != 1:
		return []
	var ev: Dictionary = editor.selected[0]
	var p: Dictionary = ev["params"]
	var centre := _board_centre_for(ev)
	match ev["type"]:
		"begin_attack":
			var board := Vector2(p["board_x"], p["board_y"])
			return [
				{"label": "board", "world": board, "keys": ["board_x", "board_y"], "origin": Vector2.ZERO},
				{"label": "soul start", "world": board + Vector2(p["soul_x"], p["soul_y"]), "keys": ["soul_x", "soul_y"], "origin": board},
			]
		"spawn":
			if p["mode"] == "fixed":
				return [{"label": "spawn", "world": centre + Vector2(p["x"], p["y"]), "keys": ["x", "y"], "origin": centre}]
		"move_to":
			return [{"label": "move to", "world": centre + Vector2(p["x"], p["y"]), "keys": ["x", "y"], "origin": centre}]
		"move_board":
			return [{"label": "board to", "world": Vector2(p["x"], p["y"]), "keys": ["x", "y"], "origin": Vector2.ZERO}]
	return []


## Positions are relative to the board's centre; for the marker, use where the
## board starts in the attack this node belongs to.
func _board_centre_for(ev: Dictionary) -> Vector2:
	for a in ChartDefs.attacks(editor.chart):
		if a["start"] <= ev["beat"] and ev["beat"] < a["end"]:
			var p: Dictionary = a["begin"]["params"]
			return Vector2(p["board_x"], p["board_y"])
	return Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	var view := _view()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if _drag == "marker":
				editor.inspector.refresh()
			_drag = ""
			return
		grab_focus()
		var world: Vector2 = view.affine_inverse() * event.position
		for m in _markers():
			if world.distance_to(m["world"]) < 10.0:
				_drag = "marker"
				_drag_marker = m
				editor.push_undo()
				return
		if world.distance_to(soul) < 12.0:
			_drag = "soul"
	elif event is InputEventMouseMotion and _drag != "":
		var world: Vector2 = (view.affine_inverse() * event.position).round()
		if _drag == "soul":
			soul = world
			invalidate() # aiming nodes depend on where the soul is
		else:
			var ev: Dictionary = editor.selected[0]
			var value: Vector2 = world - _drag_marker["origin"]
			ev["params"][_drag_marker["keys"][0]] = value.x
			ev["params"][_drag_marker["keys"][1]] = value.y
			editor.changed(false)
