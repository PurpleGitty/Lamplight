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
const HITBOX_GRAB_MARGIN := 2.0
const CHARACTER_TINT := Color(0.8, 0.8, 0.8)
const ABSENT_ALPHA := 0.4 # someone who isn't in the fight at the start
const SELECTED_COLOR := Color.YELLOW
const CHARACTER_BOX_COLOR := Color(0.4, 0.9, 1.0, 0.7)

var editor
var runtime: AttackRuntime
var soul := Vector2.ZERO # world position (0, 0 = middle of the screen)
var hits := 0
var _attack_id := -1
var _invincible := 0.0
var _drag := "" # "", "soul", "marker", "hitbox", "soul_hitbox", "character"
var _drag_character: Dictionary
var _drag_object: Dictionary # the object whose hitbox is being moved
var _drag_inverse: Transform2D # screen to the object's own pixels, fixed for the drag
var _drag_scale := 1.0
var _grab := Vector2.ZERO
var _soul_moved := false
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
	var dir := Input.get_vector("LEFT", "RIGHT", "UP", "DOWN")
	soul += dir * SOUL_SPEED * delta * editor.rate
	# Keep the soul inside the (possibly rotated) board
	var box := runtime.board_transform()
	var local := box.affine_inverse() * soul
	var half := (runtime.board_size / 2 - _soul_size() / 2.0 - Vector2.ONE).max(Vector2.ZERO)
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
	var s: float = maxf(o.data["sprite_scale"], 0.001)
	var rules: Dictionary = editor.chart["rules"]
	var soul_box := _soul_hitbox()
	var local: Vector2 = xf.affine_inverse() * soul_box.get_center() - Vector2(o.data["hitbox_x"], o.data["hitbox_y"]) / s
	var half: Vector2 = Vector2(o.data["hitbox_w"], o.data["hitbox_h"]) / s / 2 + Vector2(rules["soul_hitbox_w"], rules["soul_hitbox_h"]) / 2 / (s * o.scale)
	return absf(local.x) <= half.x and absf(local.y) <= half.y


func _view() -> Transform2D:
	var k := minf(size.x / 680.0, size.y / 520.0)
	return Transform2D(0.0, Vector2(k, k), 0.0, size / 2)


func _soul_texture() -> Texture2D:
	var path: String = editor.chart["rules"]["soul_sprite"]
	return _texture(path) if path != "" else SOUL


func _soul_size() -> Vector2:
	return _soul_texture().get_size() / Vector2(maxi(int(editor.chart["rules"]["soul_hframes"]), 1), 1)


## The soul's hitbox, in world position.
func _soul_hitbox() -> Rect2:
	var rules: Dictionary = editor.chart["rules"]
	var box := Vector2(rules["soul_hitbox_w"], rules["soul_hitbox_h"])
	return Rect2(soul + Vector2(rules["soul_hitbox_x"], rules["soul_hitbox_y"]) - box / 2.0, box)


func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = ChartDefs.load_texture(path)
	return _textures[path]


# --- drawing ---

func _draw() -> void:
	var view := _view()
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	draw_set_transform_matrix(view)
	_draw_background()
	_draw_characters()
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
	var soul_size := _soul_size()
	var flicker: bool = editor.chart["rules"]["soul_hframes"] > 1 and _invincible > 0.0 and fmod(_invincible, 0.2) >= 0.1
	var soul_corner := soul - soul_size / 2.0 + Vector2(0, 1)
	draw_texture_rect_region(_soul_texture(), Rect2(soul_corner, soul_size), Rect2(Vector2(soul_size.x if flicker else 0.0, 0), soul_size))
	if editor.show_hitboxes or editor.soul_selected:
		draw_rect(_soul_hitbox(), Color.YELLOW if editor.soul_selected else Color(0.2, 1.0, 0.4, 0.9), false, 1.0)

	_draw_character_boxes()

	for m in _markers():
		var p: Vector2 = m["world"]
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)]), Color.YELLOW)
		draw_string(FONT, p + Vector2(8, 4), m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.YELLOW)

	draw_set_transform_matrix(Transform2D())
	var info := "[LMB DRAG] MOVE SOUL"
	if editor.selected_character() != null:
		info = "[LMB] SELECT CHARACTER      [LMB DRAG] MOVE SELECTED CHARACTER"
	if editor.playtest:
		info = "PLAYTEST - press play, arrows to dodge.   hits: %d" % hits
	draw_string(FONT, Vector2(8, size.y - 8), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))


func _everyone() -> Array:
	return editor.chart["party"] + editor.chart["enemies"]


## Where a character's sprite sits on the battle screen.
func _character_box(data: Dictionary) -> Rect2:
	var frames := maxi(int(data["hframes"]), 1)
	var box: Vector2 = _texture(data["sprite"]).get_size() / Vector2(frames, 1) * float(data["sprite_scale"])
	return Rect2(Vector2(data["x"], data["y"]) - box / 2.0, box)


func _draw_characters() -> void:
	for data in _everyone():
		var tex := _texture(data["sprite"])
		var frames := maxi(int(data["hframes"]), 1)
		var frame_size := tex.get_size() / Vector2(frames, 1)
		var shown := ChartDefs.anim_frame(int(data["idle_first"]), int(data["idle_count"]), data["idle_beats"], maxf(editor.beat, 0.0))
		var source := Rect2(Vector2(clampi(shown, 0, frames - 1) * frame_size.x, 0), frame_size)
		var tint := Color(CHARACTER_TINT, 1.0 if data["present"] else ABSENT_ALPHA)
		draw_texture_rect_region(tex, _character_box(data), source, tint)


## Their boxes, over everything: faint for everyone, bright for whoever's selected.
func _draw_character_boxes() -> void:
	var chosen = editor.selected_character()
	if chosen == null:
		return
	for data in _everyone():
		if data != chosen:
			draw_rect(_character_box(data), CHARACTER_BOX_COLOR, false, 1.0)
	var box := _character_box(chosen)
	draw_rect(box, SELECTED_COLOR, false, 2.0)
	var label_at := box.position.clamp(SCREEN.position, SCREEN.end - Vector2(120, 0)) + Vector2(3, 14)
	draw_string(FONT, label_at.max(SCREEN.position + Vector2(3, 14)), chosen["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, SELECTED_COLOR)


## The character at this point: whoever's selected first, then the last one drawn.
func _character_at(world: Vector2) -> Variant:
	var chosen = editor.selected_character()
	if chosen != null and _character_box(chosen).has_point(world):
		return chosen
	var everyone := _everyone()
	for i in range(everyone.size() - 1, -1, -1):
		if _character_box(everyone[i]).has_point(world):
			return everyone[i]
	return null


## The chart's background, cropped to cover the screen the way the fight shows it.
func _draw_background() -> void:
	var rules: Dictionary = editor.chart["rules"]
	var path: String = rules["background"]
	var dim := Color(0.4, 0.4, 0.4)
	if path == "":
		draw_texture_rect(BACKGROUND, SCREEN, false, dim)
		return
	var tex := _texture(path)
	var across := maxi(int(rules["background_hframes"]), 1)
	var down := maxi(int(rules["background_vframes"]), 1)
	var total := across * down
	var count: int = int(rules["background_frames"])
	if count <= 0 or count > total:
		count = total
	var shown := ChartDefs.anim_frame(0, count, rules["background_beats"], editor.beat) % total
	var frame_size := tex.get_size() / Vector2(across, down)
	var crop := SCREEN.size * minf(frame_size.x / SCREEN.size.x, frame_size.y / SCREEN.size.y)
	var corner := Vector2(shown % across, shown / across) * frame_size + (frame_size - crop) / 2.0
	draw_texture_rect_region(tex, SCREEN, Rect2(corner, crop), dim)


func _draw_object(view: Transform2D, o, is_current: bool) -> void:
	var data: Dictionary = o.data
	var tex := _texture(o.sprite if o.sprite != "" else data["sprite"])
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
	tint.a *= alpha
	# Same look as the game's recolouring, close enough for a preview
	if o.mode != "normal":
		var mode_color: Color = AttackObject.BLUE if o.mode == "blue" else AttackObject.ORANGE
		mode_color.a = alpha
		draw_circle(Vector2.ZERO, minf(frame_size.x, frame_size.y) / 2.0, mode_color)
		tint = Color(mode_color, alpha * 0.35)
	draw_texture_rect_region(tex, Rect2(-frame_size / 2, frame_size), src, tint)

	var s: float = maxf(data["sprite_scale"], 0.001)
	var hitbox := Vector2(data["hitbox_w"], data["hitbox_h"]) / s
	if editor.show_hitboxes:
		var color := Color(1, 0.2, 0.2, 0.9) if o.harmful else Color(0.4, 0.4, 1, 0.6)
		var hitbox_centre := Vector2(data["hitbox_x"], data["hitbox_y"]) / s
		draw_rect(Rect2(hitbox_centre - hitbox / 2, hitbox), color, false, 1.0 / (s * o.scale))
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
			if _drag in ["marker", "hitbox", "soul_hitbox"]:
				editor.inspector.refresh()
			elif _drag == "character":
				editor.characters_panel.refresh()
			elif _drag == "soul" and not _soul_moved:
				editor.select_soul()
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
		if _start_object_hitbox_drag(event.position, view):
			return
		if editor.soul_selected and _soul_hitbox().grow(HITBOX_GRAB_MARGIN).has_point(world):
			_drag = "soul_hitbox"
			_grab = world - _soul_hitbox().get_center()
			editor.push_undo()
			return
		if world.distance_to(soul) < maxf(12.0, _soul_size().length() / 2.0):
			_drag = "soul"
			_soul_moved = false
			return
		var who = _character_at(world)
		if who == null:
			return
		if who != editor.selected_character():
			editor.select_character(who) # the first click selects, then they can be dragged
			return
		_drag = "character"
		_drag_character = who
		_grab = world - Vector2(who["x"], who["y"])
		editor.push_undo()
	elif event is InputEventMouseMotion and _drag != "":
		var world: Vector2 = (view.affine_inverse() * event.position).round()
		if _drag == "soul":
			soul = world
			_soul_moved = true
			invalidate() # aiming nodes depend on where the soul is
		elif _drag == "hitbox":
			var offset: Vector2 = ((_drag_inverse * event.position) * _drag_scale - _grab).round()
			_drag_object["hitbox_x"] = offset.x
			_drag_object["hitbox_y"] = offset.y
			editor.changed(false)
		elif _drag == "character":
			var spot: Vector2 = (world - _grab).round().clamp(SCREEN.position, SCREEN.end)
			_drag_character["x"] = spot.x
			_drag_character["y"] = spot.y
			editor.changed(false)
		elif _drag == "soul_hitbox":
			var offset: Vector2 = (world - _grab - soul).round()
			editor.chart["rules"]["soul_hitbox_x"] = offset.x
			editor.chart["rules"]["soul_hitbox_y"] = offset.y
			editor.changed(false)
		else:
			var ev: Dictionary = editor.selected[0]
			var value: Vector2 = world - _drag_marker["origin"]
			ev["params"][_drag_marker["keys"][0]] = value.x
			ev["params"][_drag_marker["keys"][1]] = value.y
			editor.changed(false)


## Starts moving the selected object's hitbox, if that's what was clicked.
func _start_object_hitbox_drag(mouse: Vector2, view: Transform2D) -> bool:
	var current = editor.current_object()
	if current == null or runtime == null or not editor.show_hitboxes:
		return false
	for o in runtime.objects:
		if o.data != current or not o.active:
			continue
		var to_object: Transform2D = (view * runtime.object_transform(o)).affine_inverse()
		var s: float = maxf(current["sprite_scale"], 0.001)
		var local: Vector2 = (to_object * mouse) * s # in screen-sized pixels, like the settings
		var centre := Vector2(current["hitbox_x"], current["hitbox_y"])
		var box := Vector2(current["hitbox_w"], current["hitbox_h"])
		if Rect2(centre - box / 2.0, box).grow(HITBOX_GRAB_MARGIN).has_point(local):
			_drag = "hitbox"
			_drag_object = current
			_drag_inverse = to_object
			_drag_scale = s
			_grab = local - centre
			editor.push_undo()
			return true
	return false
