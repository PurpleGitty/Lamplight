class_name ChartDefs
extends RefCounted
## The attack chart format, shared by the attack editor and the game.
##
## A chart covers a whole song. Everything is laid out on beats:
##   turn lane    - Begin Attack / End Attack mark when the enemy's turn is
##   text lane    - dialogue, flavor text and status messages
##   board lane   - things that happen to the bullet board
##   object lanes - one per attack object, holding everything it does
##
## Every node (event) looks like:
##   {"id": 12, "type": "move_to", "beat": 120.0, "length": 2.0, "params": {...}}
## Positions are in pixels. Unless a setting says otherwise they're relative to
## the centre of the board, with +x right and +y down. Angles are in degrees,
## clockwise, with 0 pointing right.

const VERSION := 1
const EASINGS := ["linear", "ease_in", "ease_out", "ease_in_out", "instant"]

## Every kind of node. "lane" is the lane it goes on; "instant" nodes happen on
## their beat and can't be stretched; the others take `length` beats.
const TYPES := {
	# --- TURN LANE ---
	"begin_attack": {
		"lane": "turn", "label": "Begin Attack", "color": Color("e04848"), "instant": true,
		"help": "The enemy's turn starts here. Sets up the board and where the soul starts.",
		"params": [
			{"name": "width", "type": "float", "default": 128.0, "min": 16.0, "max": 620.0},
			{"name": "height", "type": "float", "default": 128.0, "min": 16.0, "max": 460.0},
			{"name": "board_x", "type": "float", "default": 0.0, "min": -320.0, "max": 320.0, "help": "Board centre, from the middle of the screen"},
			{"name": "board_y", "type": "float", "default": 0.0, "min": -240.0, "max": 240.0},
			{"name": "soul_x", "type": "float", "default": 0.0, "min": -310.0, "max": 310.0, "help": "Where the soul starts, from the board centre"},
			{"name": "soul_y", "type": "float", "default": 0.0, "min": -230.0, "max": 230.0},
			{"name": "clip", "type": "bool", "default": true, "help": "Hide objects while they're outside the board"},
		]},
	"end_attack": {
		"lane": "turn", "label": "End Attack", "color": Color("8c2f2f"), "instant": true,
		"help": "The enemy's turn ends here: the board retracts and every object disappears.",
		"params": []},

	# --- TEXT LANE ---
	"text": {
		"lane": "text", "label": "Text", "color": Color("e8e8e8"), "instant": true,
		"help": "Words on screen. Between attacks: dialogue (shown in order, if the player's quick), the menu's flavor text, or a status message (replaces \"X is about to attack!\"). During an attack: a status caption above the board, at this beat.",
		"params": [
			{"name": "kind", "type": "enum", "default": "dialogue", "options": ["dialogue", "flavor", "status"]},
			{"name": "speaker", "type": "string", "default": "Testicina", "help": "Dialogue: who says it (Purple, Violet, or the enemy's name)"},
			{"name": "text", "type": "richtext", "default": "..."},
		]},

	# --- BOARD LANE ---
	"rotate_board": {
		"lane": "board", "label": "Rotate Board", "color": Color("3fd0ff"), "length": 1.0,
		"help": "Turns the board over the node's length.",
		"params": [
			{"name": "degrees", "type": "float", "default": 90.0, "min": -3600.0, "max": 3600.0, "help": "+ clockwise, - counter-clockwise"},
			{"name": "rotate_contents", "type": "bool", "default": false, "help": "Objects inside turn with the board (positions AND trajectories)"},
			{"name": "include_outside", "type": "bool", "default": false, "help": "With rotate_contents: also turn objects outside the board"},
			{"name": "easing", "type": "enum", "default": "ease_in_out", "options": EASINGS},
		]},
	"resize_board": {
		"lane": "board", "label": "Resize Board", "color": Color("3fa8ff"), "length": 1.0,
		"help": "Changes the board's size over the node's length.",
		"params": [
			{"name": "width", "type": "float", "default": 128.0, "min": 16.0, "max": 620.0},
			{"name": "height", "type": "float", "default": 128.0, "min": 16.0, "max": 460.0},
			{"name": "easing", "type": "enum", "default": "ease_in_out", "options": EASINGS},
		]},
	"move_board": {
		"lane": "board", "label": "Move Board", "color": Color("3f80ff"), "length": 1.0,
		"help": "Slides the board somewhere else over the node's length.",
		"params": [
			{"name": "x", "type": "float", "default": 0.0, "min": -320.0, "max": 320.0, "help": "New centre, from the middle of the screen"},
			{"name": "y", "type": "float", "default": 0.0, "min": -240.0, "max": 240.0},
			{"name": "contents_follow", "type": "bool", "default": true, "help": "Objects move along with the board"},
			{"name": "easing", "type": "enum", "default": "ease_in_out", "options": EASINGS},
		]},
	"shake_board": {
		"lane": "board", "label": "Shake Board", "color": Color("6f6fff"), "length": 1.0,
		"help": "Rattles the board (and everything in it), fading out over the node's length.",
		"params": [
			{"name": "strength", "type": "float", "default": 4.0, "min": 0.0, "max": 64.0, "help": "In pixels"},
		]},

	# --- OBJECT LANES ---
	"spawn": {
		"lane": "object", "label": "Spawn", "color": Color("ffe066"), "instant": true,
		"help": "The object appears (or reappears, so one lane can be reused).",
		"params": [
			{"name": "mode", "type": "enum", "default": "fixed", "options": ["fixed", "random_in_board", "random_on_edge", "relative_to_soul"]},
			{"name": "x", "type": "float", "default": 0.0, "min": -640.0, "max": 640.0, "help": "fixed / relative_to_soul only"},
			{"name": "y", "type": "float", "default": -80.0, "min": -480.0, "max": 480.0},
			{"name": "margin", "type": "float", "default": 8.0, "min": -200.0, "max": 200.0, "help": "random modes: distance in from (or out from, on_edge) the board's edge"},
			{"name": "angle", "type": "float", "default": 0.0, "min": -360.0, "max": 360.0, "help": "The object's starting rotation"},
			{"name": "fade_in", "type": "float", "default": 0.0, "min": 0.0, "max": 16.0, "help": "Beats to fade in over (0 = pop in)"},
		]},
	"despawn": {
		"lane": "object", "label": "Despawn", "color": Color("8a7a3a"), "instant": true,
		"help": "The object disappears.",
		"params": []},
	"move_to": {
		"lane": "object", "label": "Move To", "color": Color("ffb03b"), "length": 2.0,
		"help": "Moves to a point over the node's length.",
		"params": [
			{"name": "x", "type": "float", "default": 0.0, "min": -640.0, "max": 640.0},
			{"name": "y", "type": "float", "default": 0.0, "min": -480.0, "max": 480.0},
			{"name": "easing", "type": "enum", "default": "ease_out", "options": EASINGS},
		]},
	"move_by": {
		"lane": "object", "label": "Move By", "color": Color("ffa33b"), "length": 1.0,
		"help": "Moves by an offset from wherever it is, over the node's length.",
		"params": [
			{"name": "dx", "type": "float", "default": 32.0, "min": -640.0, "max": 640.0},
			{"name": "dy", "type": "float", "default": 0.0, "min": -480.0, "max": 480.0},
			{"name": "easing", "type": "enum", "default": "ease_out", "options": EASINGS},
		]},
	"random_point": {
		"lane": "object", "label": "Random Position in Board", "color": Color("ff9a1f"), "length": 3.0,
		"help": "Flies to a random spot inside the board, arriving at the end of the node. Longer node = slower.",
		"params": [
			{"name": "margin", "type": "float", "default": 12.0, "min": 0.0, "max": 200.0, "help": "Keep this far from the board's edge"},
			{"name": "easing", "type": "enum", "default": "ease_out", "options": EASINGS},
		]},
	"target_soul": {
		"lane": "object", "label": "Target Soul", "color": Color("ff7a1f"), "length": 1.0,
		"help": "Aims at where the soul is when this node starts and covers that distance in the node's length. Short node = very fast.",
		"params": [
			{"name": "mode", "type": "enum", "default": "fling", "options": ["fling", "stop_at_soul"], "help": "fling: keeps flying past the soul"},
			{"name": "easing", "type": "enum", "default": "ease_in", "options": EASINGS, "help": "stop_at_soul only"},
		]},
	"launch": {
		"lane": "object", "label": "Launch", "color": Color("ff5f1f"), "instant": true,
		"help": "Starts it flying at a steady speed until something else moves it.",
		"params": [
			{"name": "aim", "type": "enum", "default": "angle", "options": ["angle", "at_soul", "away_from_board_centre", "facing"]},
			{"name": "angle", "type": "float", "default": 90.0, "min": -360.0, "max": 360.0, "help": "aim = angle: 0 right, 90 down"},
			{"name": "speed", "type": "float", "default": 48.0, "min": -2000.0, "max": 2000.0, "help": "Pixels per beat"},
		]},
	"stop": {
		"lane": "object", "label": "Stop", "color": Color("b05a2a"), "instant": true,
		"help": "Stops any movement right where it is.",
		"params": []},
	"orbit": {
		"lane": "object", "label": "Orbit", "color": Color("ff8f6b"), "length": 4.0,
		"help": "Circles around a point, keeping its current distance, over the node's length.",
		"params": [
			{"name": "around", "type": "enum", "default": "board_centre", "options": ["board_centre", "soul"]},
			{"name": "degrees", "type": "float", "default": 360.0, "min": -7200.0, "max": 7200.0, "help": "+ clockwise"},
			{"name": "easing", "type": "enum", "default": "linear", "options": EASINGS},
		]},
	"spin": {
		"lane": "object", "label": "Spin", "color": Color("c98bff"), "length": 1.0,
		"help": "Rotates the object itself.",
		"params": [
			{"name": "degrees", "type": "float", "default": 360.0, "min": -7200.0, "max": 7200.0},
			{"name": "easing", "type": "enum", "default": "linear", "options": EASINGS},
		]},
	"face_soul": {
		"lane": "object", "label": "Face Soul", "color": Color("b07bff"), "length": 1.0,
		"help": "Turns to point at the soul (where it is when the node starts).",
		"params": [
			{"name": "offset", "type": "float", "default": 0.0, "min": -360.0, "max": 360.0, "help": "Add this to the angle (if the sprite doesn't point right)"},
			{"name": "easing", "type": "enum", "default": "ease_out", "options": EASINGS},
		]},
	"scale_to": {
		"lane": "object", "label": "Scale", "color": Color("8bffb0"), "length": 1.0,
		"help": "Grows or shrinks the object (and its hitbox).",
		"params": [
			{"name": "scale", "type": "float", "default": 2.0, "min": 0.0, "max": 20.0},
			{"name": "easing", "type": "enum", "default": "ease_out", "options": EASINGS},
		]},
	"fade_to": {
		"lane": "object", "label": "Fade", "color": Color("8bdcff"), "length": 1.0,
		"help": "Fades the object in or out. It still hurts while faded unless you also use Set Harmful.",
		"params": [
			{"name": "alpha", "type": "float", "default": 0.0, "min": 0.0, "max": 1.0},
			{"name": "easing", "type": "enum", "default": "linear", "options": EASINGS},
		]},
	"telegraph": {
		"lane": "object", "label": "Telegraph", "color": Color("ffffff"), "length": 2.0,
		"help": "Blinks as a warning and can't hurt you until the node ends.",
		"params": [
			{"name": "blinks_per_beat", "type": "float", "default": 4.0, "min": 0.5, "max": 16.0},
		]},
	"set_harmful": {
		"lane": "object", "label": "Set Harmful", "color": Color("ff4f9a"), "instant": true,
		"help": "Turns the object's hitbox on or off.",
		"params": [
			{"name": "harmful", "type": "bool", "default": true},
		]},
}

## Settings every object (lane) has. Shown when you click a lane's name.
const OBJECT_PARAMS := [
	{"name": "name", "type": "string", "default": "pellet", "help": "Shown as the cause of death: \"Testicina's pellet\""},
	{"name": "lane_label", "type": "string", "default": "", "help": "Name on the timeline (blank = same as name)"},
	{"name": "sprite", "type": "texture", "default": "res://sprites/pellet.png"},
	{"name": "hframes", "type": "int", "default": 1, "min": 1, "max": 64, "help": "Frames across in the sprite sheet"},
	{"name": "frame", "type": "int", "default": 0, "min": 0, "max": 255},
	{"name": "sprite_scale", "type": "float", "default": 0.5, "min": 0.05, "max": 16.0},
	{"name": "tint", "type": "color", "default": "ffffff"},
	{"name": "hitbox_w", "type": "float", "default": 12.0, "min": 0.0, "max": 640.0},
	{"name": "hitbox_h", "type": "float", "default": 12.0, "min": 0.0, "max": 480.0},
	{"name": "damage", "type": "int", "default": 20, "min": 0, "max": 999},
]

## Settings for the whole chart. Shown when nothing is selected.
const CHART_PARAMS := [
	{"name": "song", "type": "audio", "default": "res://sounds/Phonky Tribu - Funk Tribu.mp3"},
	{"name": "bpm", "type": "float", "default": 160.0, "min": 20.0, "max": 400.0},
	{"name": "offset", "type": "float", "default": 0.0, "min": -10.0, "max": 10.0, "help": "Seconds from the start of the audio to beat 0"},
]


static func new_chart() -> Dictionary:
	var chart := {"version": VERSION, "next_id": 1, "turn_events": [], "text_events": [], "board_events": [], "objects": []}
	for p in CHART_PARAMS:
		chart[p["name"]] = p["default"]
	return chart


static func lane_label(obj: Dictionary) -> String:
	return obj["lane_label"] if obj["lane_label"] != "" else obj["name"]


static func take_id(chart: Dictionary) -> int:
	var id: int = int(chart["next_id"])
	chart["next_id"] = id + 1
	return id


static func new_event(chart: Dictionary, type: String, beat: float) -> Dictionary:
	var def: Dictionary = TYPES[type]
	return {"id": take_id(chart), "type": type, "beat": beat, "length": def.get("length", 1.0), "params": defaults(def["params"])}


static func new_object(chart: Dictionary, object_name: String) -> Dictionary:
	var obj := defaults(OBJECT_PARAMS)
	obj["id"] = take_id(chart)
	obj["name"] = object_name
	obj["events"] = []
	return obj


static func defaults(param_defs: Array) -> Dictionary:
	var values := {}
	for p in param_defs:
		values[p["name"]] = p["default"]
	return values


static func is_instant(type: String) -> bool:
	return TYPES[type].get("instant", false)


static func event_end(ev: Dictionary) -> float:
	return ev["beat"] + (0.0 if is_instant(ev["type"]) else ev["length"])


## The enemy's turns: [{"begin": event, "start": beat, "end": beat}, ...] in order.
## An attack with no End Attack after it lasts 24 beats.
static func attacks(chart: Dictionary) -> Array:
	var turn_events: Array = chart["turn_events"].duplicate()
	turn_events.sort_custom(func(a, b): return a["beat"] < b["beat"])
	var result := []
	for i in turn_events.size():
		var ev: Dictionary = turn_events[i]
		if ev["type"] != "begin_attack":
			continue
		var end: float = ev["beat"] + 24.0
		for j in range(i + 1, turn_events.size()):
			end = turn_events[j]["beat"]
			break
		result.append({"begin": ev, "start": ev["beat"], "end": end})
	return result


static func ease_value(p: float, mode: String) -> float:
	p = clampf(p, 0.0, 1.0)
	match mode:
		"ease_in": return p * p
		"ease_out": return 1.0 - (1.0 - p) * (1.0 - p)
		"ease_in_out": return p * p * (3.0 - 2.0 * p)
		"instant": return 1.0 if p > 0.0 else 0.0
	return p


static func load_chart(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var chart := parse_chart(FileAccess.get_file_as_string(path))
	if chart.is_empty():
		push_error("Couldn't read chart %s" % path)
	return chart


static func parse_chart(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	var chart: Dictionary = parsed
	# Fill in anything missing (older files, hand edits) so nothing downstream breaks
	var base := new_chart()
	for key in base:
		if not chart.has(key):
			chart[key] = base[key]
	for ev in chart["turn_events"] + chart["text_events"] + chart["board_events"]:
		_fill_event(ev)
	chart["next_id"] = int(chart["next_id"])
	for obj in chart["objects"]:
		obj["id"] = int(obj["id"])
		for p in OBJECT_PARAMS:
			if not obj.has(p["name"]):
				obj[p["name"]] = p["default"]
		for ev in obj["events"]:
			_fill_event(ev)
	return chart


static func _fill_event(ev: Dictionary) -> void:
	if not TYPES.has(ev["type"]):
		return
	var full := defaults(TYPES[ev["type"]]["params"])
	full.merge(ev.get("params", {}), true)
	ev["params"] = full
	ev["id"] = int(ev["id"])


static func save_chart(chart: Dictionary, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(chart, "\t"))
	return OK


static func load_texture(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	return preload("res://sprites/pellet.png")


## Text nodes from `start` (inclusive) to `end` (exclusive), in order.
static func texts_between(chart: Dictionary, start: float, end: float) -> Array:
	var found: Array = chart["text_events"].filter(func(ev): return ev["beat"] >= start and ev["beat"] < end)
	found.sort_custom(func(a, b): return a["beat"] < b["beat"] or (a["beat"] == b["beat"] and a["id"] < b["id"]))
	return found
