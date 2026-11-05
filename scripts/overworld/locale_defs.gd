class_name LocaleDefs
extends RefCounted
## The overworld format, shared by the Locale-Inator and the game.
##
## A locale holds rooms, the party, overworld rules, cutscenes and items. A room has
## tile layers and objects. Every kind of thing is listed here as settings, so the
## editor builds its panels from these lists and new settings show up by themselves.

const VERSION := 1
const FLOOR_SHEET := "res://sprites/tiles/grass.png" # from TileMapDual's examples, so there's something to draw with
const WALL_SHEET := "res://sprites/tiles/fancy_wood.png" # the user's own dual-grid sheet
const SPRINT_STYLES := ["speed up walk", "own frames"]
const DIRECTIONS := ["down", "up", "left", "right"]
const DIRECTION_VECTORS := {"down": Vector2.DOWN, "up": Vector2.UP, "left": Vector2.LEFT, "right": Vector2.RIGHT}

const RULE_PARAMS := [
	{"name": "can_run", "type": "bool", "default": true, "help": "Hold BACK to run"},
	{"name": "can_use_inventory", "type": "bool", "default": true, "help": "Whether the menu has an Items tab"},
	{"name": "can_save_anywhere", "type": "bool", "default": false, "help": "Saving from the menu. Off = only at a Save step, like a save point"},
	{"name": "autosave", "type": "bool", "default": false, "help": "Saves to the autosave slot every time you change rooms"},
	{"name": "menu_shows_hp", "type": "bool", "default": true, "help": "The Party tab shows HP"},
	{"name": "menu_shows_attack", "type": "bool", "default": true},
	{"name": "menu_shows_defense", "type": "bool", "default": true},
	{"name": "menu_shows_moves", "type": "bool", "default": true},
	{"name": "walk_speed", "type": "float", "default": 90.0, "min": 0.0, "max": 1000.0, "help": "World pixels per second"},
	{"name": "run_speed", "type": "float", "default": 160.0, "min": 0.0, "max": 1000.0},
	{"name": "party_size", "type": "int", "default": 2, "min": 1, "max": 8, "help": "How many of the party are out, following the leader"},
	{"name": "follow_gap", "type": "float", "default": 22.0, "min": 4.0, "max": 200.0, "help": "World pixels between party members"},
	{"name": "zoom", "type": "int", "default": 2, "min": 1, "max": 8, "help": "How many screen pixels each world pixel is. The screen is 640 x 480"},
	{"name": "tile_size", "type": "int", "default": 16, "min": 4, "max": 128, "help": "World pixels per tile"},
	{"name": "edges_block", "type": "bool", "default": true, "help": "The player can only walk on drawn tiles, so nothing else needs walls"},
	{"name": "background_color", "type": "color", "default": "000000", "help": "What's behind the tiles"},
	{"name": "background", "type": "texture", "default": "", "help": "An image behind the tiles, stretched to the screen"},
	{"name": "background_video", "type": "video", "default": "", "help": "A looping video behind the tiles. MP4s get converted when you pick them"},
	{"name": "music", "type": "audio", "default": "", "help": "Plays and loops. Rooms can have their own"},
	{"name": "sun", "type": "bool", "default": false, "help": "A fake sun: every sprite that has a shadow casts one"},
	{"name": "sun_angle", "type": "float", "default": 45.0, "min": -360.0, "max": 360.0, "help": "Which way shadows fall. 0 right, 90 down"},
	{"name": "sun_length", "type": "float", "default": 0.7, "min": 0.0, "max": 4.0, "help": "A shadow's length, compared to the sprite's height"},
	{"name": "sun_strength", "type": "float", "default": 0.35, "min": 0.0, "max": 1.0, "help": "How dark shadows are"},
]

## What a Set Rule step can change.
const CHANGEABLE_RULES := ["can_run", "can_use_inventory", "can_save_anywhere", "autosave", "walk_speed", "run_speed", "party_size", "edges_block", "sun", "sun_angle", "sun_length", "sun_strength", "zoom"]

const ROOM_PARAMS := [
	{"name": "name", "type": "string", "default": "Room"},
	{"name": "music", "type": "audio", "default": "", "help": "Blank = the overworld's"},
	{"name": "own_background", "type": "bool", "default": false, "help": "Use this room's background instead of the overworld's"},
	{"name": "background_color", "type": "color", "default": "000000"},
	{"name": "background", "type": "texture", "default": ""},
	{"name": "background_video", "type": "video", "default": ""},
	{"name": "sun", "type": "enum", "default": "same", "options": ["same", "on", "off"], "help": "Indoors? Turn the sun off here"},
]

const LAYER_PARAMS := [
	{"name": "name", "type": "string", "default": "Ground"},
	{"name": "sheet", "type": "texture", "default": "", "help": "A 4 x 4 dual-grid sheet, or one plain tile with \"plain tile\" on"},
	{"name": "plain_tile", "type": "bool", "default": false, "help": "The picture is one tile: the edges get made for you"},
	{"name": "edge_color", "type": "color", "default": "1a1020", "help": "The outline a plain tile gets"},
	{"name": "solid", "type": "bool", "default": false, "help": "The player can't walk through this layer, and shadows go under it"},
	{"name": "above", "type": "bool", "default": false, "help": "Draws over the player: treetops, doorways"},
	{"name": "wall_height", "type": "float", "default": 2.0, "min": 0.0, "max": 32.0, "help": "A solid layer's height in tiles, for the sun's shadows. 0 = no shadow"},
]

const CHARACTER_PARAMS := [
	{"name": "name", "type": "string", "default": "Purple"},
	{"name": "sprite", "type": "texture", "default": "", "help": "Blank = a plain block, one tile wide and two tall"},
	{"name": "blank_color", "type": "color", "default": "b48cff", "help": "The plain block's colour, if there's no sprite"},
	{"name": "hframes", "type": "int", "default": 1, "min": 1, "max": 64, "help": "Frames across in the sheet"},
	{"name": "vframes", "type": "int", "default": 1, "min": 1, "max": 64, "help": "Frames down in the sheet"},
	{"name": "scale", "type": "float", "default": 1.0, "min": 0.05, "max": 16.0},
	{"name": "box_width", "type": "float", "default": 0.0, "min": 0.0, "max": 1000.0, "help": "How wide they are for bumping into walls. 0 = the sprite's width"},
	{"name": "fps", "type": "float", "default": 8.0, "min": 0.0, "max": 60.0, "help": "Walking frames per second. Running plays faster"},
	{"name": "down_first", "type": "int", "default": 0, "min": 0, "max": 4096, "help": "First frame facing down. It's also the standing frame"},
	{"name": "down_count", "type": "int", "default": 1, "min": 1, "max": 256},
	{"name": "up_first", "type": "int", "default": 0, "min": 0, "max": 4096},
	{"name": "up_count", "type": "int", "default": 1, "min": 1, "max": 256},
	{"name": "left_first", "type": "int", "default": 0, "min": 0, "max": 4096},
	{"name": "left_count", "type": "int", "default": 1, "min": 1, "max": 256},
	{"name": "right_first", "type": "int", "default": 0, "min": 0, "max": 4096},
	{"name": "right_count", "type": "int", "default": 1, "min": 1, "max": 256},
	{"name": "mirror_left", "type": "bool", "default": false, "help": "Facing left shows the right frames, flipped"},
	{"name": "sprint_anim", "type": "enum", "default": "speed up walk", "options": SPRINT_STYLES, "help": "Running either plays the walk faster, or its own frames below"},
	{"name": "run_fps", "type": "float", "default": 12.0, "min": 0.0, "max": 60.0, "help": "Own frames only"},
	{"name": "run_down_first", "type": "int", "default": 0, "min": 0, "max": 4096},
	{"name": "run_down_count", "type": "int", "default": 1, "min": 1, "max": 256},
	{"name": "run_up_first", "type": "int", "default": 0, "min": 0, "max": 4096},
	{"name": "run_up_count", "type": "int", "default": 1, "min": 1, "max": 256},
	{"name": "run_left_first", "type": "int", "default": 0, "min": 0, "max": 4096},
	{"name": "run_left_count", "type": "int", "default": 1, "min": 1, "max": 256},
	{"name": "run_right_first", "type": "int", "default": 0, "min": 0, "max": 4096},
	{"name": "run_right_count", "type": "int", "default": 1, "min": 1, "max": 256},
	{"name": "voice", "type": "audio", "default": "", "help": "Sound per letter when they talk"},
	{"name": "shadow", "type": "bool", "default": true},
	{"name": "max_hp", "type": "int", "default": 100, "min": 1, "max": 999999, "help": "Used in fights too, for anyone with the same name in the fight"},
	{"name": "fight_damage", "type": "int", "default": 300, "min": 0, "max": 999999, "label": "attack"},
	{"name": "defense", "type": "float", "default": 0.0, "min": 0.0, "max": 100.0, "help": "Percent less damage from every hit"},
]

## Settings every object has.
const OBJECT_COMMON := [
	{"name": "name", "type": "string", "default": "Object"},
	{"name": "x", "type": "float", "default": 0.0, "min": -100000.0, "max": 100000.0},
	{"name": "y", "type": "float", "default": 0.0, "min": -100000.0, "max": 100000.0},
	{"name": "show_if", "type": "string", "default": "", "help": "Only there if this flag is on. !flag means only if it's off. Blank = always"},
]
const EVENT_PARAMS := [
	{"name": "starts", "type": "enum", "default": "interact", "options": ["interact", "touch", "enter_room", "never"], "help": "What sets off its steps"},
	{"name": "once", "type": "bool", "default": false, "help": "Only ever happens the first time"},
]
const BOX_PARAMS := [
	{"name": "w", "type": "float", "default": 32.0, "min": 1.0, "max": 100000.0},
	{"name": "h", "type": "float", "default": 32.0, "min": 1.0, "max": 100000.0},
]

## Kinds of object. Invisible ones only show in the editor.
const OBJECT_TYPES := {
	"prop": {"label": "Sprite", "color": Color("ffd24f"), "visible": true, "events": true, "params": [
		{"name": "sprite", "type": "texture", "default": ""},
		{"name": "hframes", "type": "int", "default": 1, "min": 1, "max": 64},
		{"name": "vframes", "type": "int", "default": 1, "min": 1, "max": 64},
		{"name": "frame", "type": "int", "default": 0, "min": 0, "max": 4096},
		{"name": "anim_count", "type": "int", "default": 1, "min": 1, "max": 256, "help": "Frames to loop, from frame"},
		{"name": "fps", "type": "float", "default": 6.0, "min": 0.0, "max": 60.0},
		{"name": "scale", "type": "float", "default": 1.0, "min": 0.05, "max": 16.0},
		{"name": "solid", "type": "bool", "default": false, "help": "The player can't walk through it"},
		{"name": "hit_w", "type": "float", "default": 16.0, "min": 0.0, "max": 1000.0, "help": "Solid and reach box, centred on its feet"},
		{"name": "hit_h", "type": "float", "default": 8.0, "min": 0.0, "max": 1000.0},
		{"name": "shadow", "type": "bool", "default": true},
		{"name": "y_sort", "type": "bool", "default": true, "help": "Things in front of it (lower down) draw over it. Off = always under everything, like a rug"},
	]},
	"npc": {"label": "NPC", "color": Color("8bffb0"), "visible": true, "events": true, "params": [
		{"name": "sprite", "type": "texture", "default": ""},
		{"name": "hframes", "type": "int", "default": 1, "min": 1, "max": 64},
		{"name": "vframes", "type": "int", "default": 1, "min": 1, "max": 64},
		{"name": "scale", "type": "float", "default": 1.0, "min": 0.05, "max": 16.0},
		{"name": "fps", "type": "float", "default": 8.0, "min": 0.0, "max": 60.0},
		{"name": "down_first", "type": "int", "default": 0, "min": 0, "max": 4096},
		{"name": "down_count", "type": "int", "default": 1, "min": 1, "max": 256},
		{"name": "up_first", "type": "int", "default": 0, "min": 0, "max": 4096},
		{"name": "up_count", "type": "int", "default": 1, "min": 1, "max": 256},
		{"name": "left_first", "type": "int", "default": 0, "min": 0, "max": 4096},
		{"name": "left_count", "type": "int", "default": 1, "min": 1, "max": 256},
		{"name": "right_first", "type": "int", "default": 0, "min": 0, "max": 4096},
		{"name": "right_count", "type": "int", "default": 1, "min": 1, "max": 256},
		{"name": "mirror_left", "type": "bool", "default": false},
		{"name": "facing", "type": "enum", "default": "down", "options": DIRECTIONS},
		{"name": "turns_to_talk", "type": "bool", "default": true, "help": "Faces the player when they talk to it"},
		{"name": "voice", "type": "audio", "default": ""},
		{"name": "solid", "type": "bool", "default": true},
		{"name": "hit_w", "type": "float", "default": 16.0, "min": 0.0, "max": 1000.0},
		{"name": "hit_h", "type": "float", "default": 8.0, "min": 0.0, "max": 1000.0},
		{"name": "shadow", "type": "bool", "default": true},
	]},
	"trigger": {"label": "Trigger", "color": Color("ff80c0"), "visible": false, "events": true, "box": true, "params": []},
	"warp": {"label": "Warp", "color": Color("3fd0ff"), "visible": false, "box": true, "params": [
		{"name": "room", "type": "room", "default": -1, "help": "The room it leads to"},
		{"name": "spawn", "type": "spawn", "default": -1, "help": "Where in that room you arrive"},
		{"name": "needs_interact", "type": "bool", "default": false, "help": "Press ACCEPT to use it, instead of walking onto it"},
	]},
	"spawn": {"label": "Spawn", "color": Color("c8ff6b"), "visible": false, "params": [
		{"name": "facing", "type": "enum", "default": "down", "options": DIRECTIONS},
	]},
	"path": {"label": "Path", "color": Color("ffa060"), "visible": false, "params": []},
}

## Steps of an event, run in order. if / else / end wrap the steps between them.
const STEP_TYPES := {
	"say": {"label": "Say", "params": [
		{"name": "speaker", "type": "string", "default": "", "help": "A name from the party or an NPC's name picks their voice"},
		{"name": "portrait", "type": "texture", "default": ""},
		{"name": "text", "type": "multiline", "default": "* ..."},
	]},
	"choice": {"label": "Ask a choice", "params": [
		{"name": "text", "type": "multiline", "default": "* Well?"},
		{"name": "options", "type": "string", "default": "Yes, No", "help": "Separated by commas"},
		{"name": "flag", "type": "string", "default": "choice", "help": "Set to which one's picked: 1 for the first, 2 for the second"},
	]},
	"if": {"label": "If", "params": [
		{"name": "flag", "type": "string", "default": "flag"},
		{"name": "compare", "type": "enum", "default": "==", "options": ["==", "!=", ">", ">=", "<", "<="]},
		{"name": "value", "type": "float", "default": 1.0, "min": -100000.0, "max": 100000.0},
	]},
	"else": {"label": "Else", "params": []},
	"end": {"label": "End if", "params": []},
	"set_flag": {"label": "Set flag", "params": [
		{"name": "flag", "type": "string", "default": "flag"},
		{"name": "how", "type": "enum", "default": "set", "options": ["set", "add"]},
		{"name": "value", "type": "float", "default": 1.0, "min": -100000.0, "max": 100000.0},
	]},
	"wait": {"label": "Wait", "params": [{"name": "seconds", "type": "float", "default": 0.5, "min": 0.0, "max": 600.0}]},
	"move": {"label": "Move", "params": [
		{"name": "who", "type": "object", "default": -1, "help": "Blank = the player"},
		{"name": "dx", "type": "float", "default": 0.0, "min": -100000.0, "max": 100000.0},
		{"name": "dy", "type": "float", "default": 0.0, "min": -100000.0, "max": 100000.0},
		{"name": "speed", "type": "float", "default": 60.0, "min": 1.0, "max": 2000.0},
		{"name": "wait", "type": "bool", "default": true, "help": "Wait for it to get there"},
	]},
	"follow": {"label": "Follow path", "params": [
		{"name": "who", "type": "object", "default": -1},
		{"name": "path", "type": "path", "default": -1, "help": "Draw one with Path on the left"},
		{"name": "speed", "type": "float", "default": 60.0, "min": 1.0, "max": 2000.0, "help": "World pixels per second"},
		{"name": "seconds", "type": "float", "default": 0.0, "min": 0.0, "max": 600.0, "help": "Take exactly this long instead (0 = use speed)"},
		{"name": "start_there", "type": "bool", "default": false, "help": "Jump to the start of the path, instead of walking there"},
		{"name": "wait", "type": "bool", "default": true, "help": "Wait for them to finish. Off lets several walk at once"},
	]},
	"animate": {"label": "Play animation", "params": [
		{"name": "who", "type": "object", "default": -1},
		{"name": "first", "type": "int", "default": 0, "min": 0, "max": 4096},
		{"name": "count", "type": "int", "default": 1, "min": 1, "max": 256},
		{"name": "fps", "type": "float", "default": 8.0, "min": 0.1, "max": 60.0},
		{"name": "loop", "type": "bool", "default": false, "help": "Keeps going until a Stop Animation step"},
		{"name": "hold", "type": "bool", "default": false, "help": "Stays on the last frame when it ends, until a Stop Animation step"},
		{"name": "wait", "type": "bool", "default": true, "help": "Wait for it to end (a looping one never waits)"},
	]},
	"stop_anim": {"label": "Stop animation", "params": [{"name": "who", "type": "object", "default": -1}]},
	"face": {"label": "Face", "params": [
		{"name": "who", "type": "object", "default": -1},
		{"name": "direction", "type": "enum", "default": "down", "options": DIRECTIONS},
	]},
	"show": {"label": "Show or hide", "params": [
		{"name": "who", "type": "object", "default": -1},
		{"name": "visible", "type": "bool", "default": false},
	]},
	"warp": {"label": "Warp", "params": [
		{"name": "room", "type": "room", "default": -1},
		{"name": "spawn", "type": "spawn", "default": -1},
	]},
	"fade": {"label": "Fade screen", "params": [
		{"name": "to", "type": "enum", "default": "black", "options": ["black", "clear"]},
		{"name": "seconds", "type": "float", "default": 0.5, "min": 0.0, "max": 60.0},
	]},
	"camera": {"label": "Point camera", "params": [
		{"name": "at", "type": "object", "default": -1, "help": "Blank = back to the player"},
		{"name": "seconds", "type": "float", "default": 0.75, "min": 0.0, "max": 60.0},
	]},
	"shake": {"label": "Shake screen", "params": [
		{"name": "strength", "type": "float", "default": 4.0, "min": 0.0, "max": 64.0},
		{"name": "seconds", "type": "float", "default": 0.5, "min": 0.0, "max": 60.0},
	]},
	"sound": {"label": "Play sound", "params": [{"name": "sound", "type": "audio", "default": ""}]},
	"music": {"label": "Change music", "params": [{"name": "music", "type": "audio", "default": "", "help": "Blank = silence"}]},
	"video": {"label": "Play video", "params": [
		{"name": "video", "type": "video", "default": ""},
		{"name": "can_skip", "type": "bool", "default": true},
	]},
	"battle": {"label": "Start fight", "params": [
		{"name": "fight", "type": "fight", "default": "", "help": "A scrap, or one of the game's fights. Flag won_fight is 1 or 0 afterwards"},
		{"name": "if_lost", "type": "enum", "default": "carry on", "options": ["carry on", "back to last save"], "help": "What happens if they give up after losing"},
		{"name": "use_party", "type": "bool", "default": true, "help": "Party members with the same name as someone in the fight bring their HP, stats and moves. Off = the fight's own"},
	]},
	"heal": {"label": "Heal party", "params": [
		{"name": "amount", "type": "int", "default": 0, "min": -999999, "max": 999999, "help": "0 = all the way. Negative hurts, but never below 1"},
	]},
	"give": {"label": "Give item", "params": [
		{"name": "item", "type": "item", "default": -1},
		{"name": "count", "type": "int", "default": 1, "min": -999, "max": 999, "help": "Negative takes them away"},
	]},
	"has_item": {"label": "If they have an item", "params": [{"name": "item", "type": "item", "default": -1}]},
	"set_rule": {"label": "Set overworld rule", "params": [
		{"name": "rule", "type": "enum", "default": "can_run", "options": CHANGEABLE_RULES},
		{"name": "value", "type": "float", "default": 1.0, "min": -100000.0, "max": 100000.0, "help": "For on/off rules: 1 on, 0 off"},
	]},
	"cutscene": {"label": "Run cutscene", "params": [{"name": "cutscene", "type": "cutscene", "default": -1}]},
	"stop": {"label": "Stop here", "params": []},
	"save": {"label": "Open save menu", "params": []},
}
## Steps that open a block, and so indent what follows.
const BLOCK_STARTS := ["if", "has_item"]


static func defaults(param_defs: Array) -> Dictionary:
	var values := {}
	for p in param_defs:
		values[p["name"]] = p["default"]
	return values


static func take_id(locale: Dictionary) -> int:
	var id := int(locale["next_id"])
	locale["next_id"] = id + 1
	return id


static func new_locale() -> Dictionary:
	var locale := {"version": VERSION, "save_id": _new_save_id(), "next_id": 1, "rules": defaults(RULE_PARAMS), "party": [], "rooms": [], "cutscenes": [], "items": [], "start_room": -1, "start_spawn": -1}
	locale["party"].append(new_character("Purple"))
	var violet := new_character("Violet")
	violet["blank_color"] = "8c64ff"
	locale["party"].append(violet)
	var room := new_room(locale, "First Room")
	locale["rooms"].append(room)
	locale["start_room"] = room["id"]
	var spawn := new_object(locale, "spawn", 8.0, 8.0)
	spawn["name"] = "Start"
	room["objects"].append(spawn)
	locale["start_spawn"] = spawn["id"]
	return locale


static func _new_save_id() -> String:
	return "%x%x" % [randi(), Time.get_ticks_usec()]


static func new_character(character_name: String) -> Dictionary:
	var c := defaults(CHARACTER_PARAMS)
	c["name"] = character_name
	c["specials"] = []
	c["maneuvers"] = []
	c["stats"] = []
	# Purple and Violet start the way they are in the first fight
	for member in ChartDefs.default_party():
		if member["name"] == character_name:
			for key in ["max_hp", "fight_damage", "defense"]:
				c[key] = member[key]
			c["specials"] = member["specials"].map(func(m): return m["preset"])
			c["maneuvers"] = member["maneuvers"].map(func(m): return m["preset"])
	return c


## Moves are kept by name, from the lists of presets. Fights turn them back into moves.
static func _clean_character(raw: Dictionary) -> Dictionary:
	var c := new_character(str(raw.get("name", "Character")))
	c.merge(raw, true)
	for pair in [["specials", ChartDefs.SPECIAL_PRESETS], ["maneuvers", ChartDefs.MANEUVER_PRESETS]]:
		var kept := []
		if c[pair[0]] is Array:
			for id in c[pair[0]]:
				if id is String and pair[1].has(id):
					kept.append(id)
		c[pair[0]] = kept
	var stats := []
	if c["stats"] is Array:
		for stat in c["stats"]:
			if stat is Dictionary:
				stats.append({"name": str(stat.get("name", "Stat")), "value": str(stat.get("value", "")), "flag": str(stat.get("flag", ""))})
	c["stats"] = stats
	return c


static func new_room(locale: Dictionary, room_name: String) -> Dictionary:
	var room := defaults(ROOM_PARAMS)
	room["id"] = take_id(locale)
	room["name"] = room_name
	room["map_x"] = 0.0
	room["map_y"] = 0.0
	var floors := new_layer(locale, "Floors")
	var walls := new_layer(locale, "Walls")
	walls["sheet"] = WALL_SHEET
	walls["solid"] = true
	room["layers"] = [floors, walls]
	room["objects"] = []
	return room


static func new_layer(locale: Dictionary, layer_name: String) -> Dictionary:
	var layer := defaults(LAYER_PARAMS)
	layer["id"] = take_id(locale)
	layer["name"] = layer_name
	layer["sheet"] = FLOOR_SHEET
	layer["cells"] = []
	return layer


static func object_params(type: String) -> Array:
	var def: Dictionary = OBJECT_TYPES[type]
	var params: Array = OBJECT_COMMON + def["params"]
	if def.get("box", false):
		params = params + BOX_PARAMS
	if def.get("events", false):
		params = params + EVENT_PARAMS
	return params


static func new_object(locale: Dictionary, type: String, x: float, y: float) -> Dictionary:
	var obj := defaults(object_params(type))
	obj["id"] = take_id(locale)
	obj["type"] = type
	obj["name"] = str(OBJECT_TYPES[type]["label"])
	obj["x"] = x
	obj["y"] = y
	if OBJECT_TYPES[type].get("events", false):
		obj["steps"] = []
	if type == "trigger":
		obj["starts"] = "touch"
	if type == "path":
		obj["points"] = [[0.0, 0.0]]
		obj["cues"] = []
	return obj


static func new_step(type: String) -> Dictionary:
	var step := defaults(STEP_TYPES[type]["params"])
	step["type"] = type
	return step


# --- reading ---

## Fills in whatever's missing or the wrong shape: a locale can come from anywhere.
static func clean(parsed: Variant) -> Dictionary:
	if not parsed is Dictionary:
		return {}
	var locale: Dictionary = parsed
	var base := new_locale()
	for key in ["party", "rooms", "cutscenes", "items"]:
		if not locale.get(key) is Array:
			locale[key] = base[key]
	var rules := defaults(RULE_PARAMS)
	if locale.get("rules") is Dictionary:
		rules.merge(locale["rules"], true)
	locale["rules"] = rules
	locale["next_id"] = int(locale.get("next_id", 1))
	locale["save_id"] = str(locale.get("save_id", ""))
	locale["start_room"] = int(locale.get("start_room", -1))
	locale["start_spawn"] = int(locale.get("start_spawn", -1))
	locale["party"] = locale["party"].filter(func(c): return c is Dictionary).map(func(c): return _clean_character(c))
	if locale["party"].is_empty():
		locale["party"] = base["party"]
	var rooms := []
	for room in locale["rooms"]:
		if room is Dictionary:
			rooms.append(_clean_room(room))
	locale["rooms"] = rooms
	if rooms.is_empty():
		locale["rooms"] = base["rooms"]
		locale["start_room"] = base["start_room"]
		locale["start_spawn"] = base["start_spawn"]
		locale["next_id"] = maxi(locale["next_id"], base["next_id"])
	var cutscenes := []
	for scene in locale["cutscenes"]:
		if scene is Dictionary:
			cutscenes.append({"id": int(scene.get("id", 0)), "name": str(scene.get("name", "Cutscene")), "steps": _clean_steps(scene.get("steps"))})
	locale["cutscenes"] = cutscenes
	var items := []
	for item in locale["items"]:
		if item is Dictionary:
			items.append({"id": int(item.get("id", 0)), "name": str(item.get("name", "Item")), "description": str(item.get("description", "")), "use": int(item.get("use", -1))})
	locale["items"] = items
	return locale


static func _filled(param_defs: Array, values: Dictionary) -> Dictionary:
	var full := defaults(param_defs)
	full.merge(values, true)
	return full


static func _clean_room(room: Dictionary) -> Dictionary:
	var full := _filled(ROOM_PARAMS, room)
	full["id"] = int(room.get("id", 0))
	full["map_x"] = float(room.get("map_x", 0.0))
	full["map_y"] = float(room.get("map_y", 0.0))
	var layers := []
	var raw_layers: Variant = room.get("layers")
	if raw_layers is Array:
		for layer in raw_layers:
			if layer is Dictionary:
				var filled := _filled(LAYER_PARAMS, layer)
				filled["id"] = int(layer.get("id", 0))
				var cells: Variant = layer.get("cells")
				filled["cells"] = cells.map(func(n): return int(n)) if cells is Array else []
				layers.append(filled)
	full["layers"] = layers
	var objects := []
	var raw_objects: Variant = room.get("objects")
	if raw_objects is Array:
		for obj in raw_objects:
			if obj is Dictionary and OBJECT_TYPES.has(obj.get("type")):
				var filled := _filled(object_params(obj["type"]), obj)
				filled["id"] = int(obj.get("id", 0))
				if OBJECT_TYPES[obj["type"]].get("events", false):
					filled["steps"] = _clean_steps(obj.get("steps"))
				for ref in ["room", "spawn"]:
					if filled.has(ref):
						filled[ref] = int(filled[ref])
				if obj["type"] == "path":
					_clean_path(filled, obj)
				objects.append(filled)
	full["objects"] = objects
	return full


static func _clean_path(path: Dictionary, raw: Dictionary) -> void:
	var points := []
	if raw.get("points") is Array:
		for point in raw["points"]:
			if point is Array and point.size() >= 2 and point[0] is float and point[1] is float and is_finite(point[0]) and is_finite(point[1]):
				points.append([point[0], point[1]])
	path["points"] = points if not points.is_empty() else [[0.0, 0.0]]
	var cues := []
	if raw.get("cues") is Array:
		for cue in raw["cues"]:
			if cue is Dictionary:
				cues.append({"point": int(cue.get("point", 0)), "steps": _clean_steps(cue.get("steps"))})
	path["cues"] = cues


## Where a path's points are in the room.
static func path_points(path: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	var origin := Vector2(path["x"], path["y"])
	for point in path["points"]:
		points.append(origin + Vector2(point[0], point[1]))
	return points


static func _clean_steps(raw: Variant) -> Array:
	var steps := []
	if raw is Array:
		for step in raw:
			if step is Dictionary and STEP_TYPES.has(step.get("type")):
				var filled := _filled(STEP_TYPES[step["type"]]["params"], step)
				filled["type"] = step["type"]
				for p in STEP_TYPES[step["type"]]["params"]:
					if p["type"] in ["object", "room", "spawn", "item", "cutscene", "path"]:
						filled[p["name"]] = int(filled[p["name"]])
				steps.append(filled)
	return steps


# --- looking things up ---

static func find_room(locale: Dictionary, id: int) -> Variant:
	for room in locale["rooms"]:
		if room["id"] == id:
			return room
	return null


static func find_object(room: Dictionary, id: int) -> Variant:
	for obj in room["objects"]:
		if obj["id"] == id:
			return obj
	return null


static func find_cutscene(locale: Dictionary, id: int) -> Variant:
	for scene in locale["cutscenes"]:
		if scene["id"] == id:
			return scene
	return null


static func find_item(locale: Dictionary, id: int) -> Variant:
	for item in locale["items"]:
		if item["id"] == id:
			return item
	return null


## The frame a character or NPC shows: `mirrored` if left is right flipped. Running shows
## its own frames if they have them, or otherwise the walk `speed_up` times faster.
static func direction_frame(data: Dictionary, direction: String, moving_time: float, speed_up := 1.0, running := false) -> Dictionary:
	var mirrored: bool = direction == "left" and data.get("mirror_left", false)
	var used := "right" if mirrored else direction
	var fps := float(data["fps"]) * speed_up
	if running and moving_time >= 0.0 and data.get("sprint_anim", "") == "own frames":
		used = "run_" + used
		fps = float(data["run_fps"])
	var first := int(data[used + "_first"])
	var count := maxi(int(data[used + "_count"]), 1)
	var frame := first
	if moving_time >= 0.0 and count > 1:
		frame = first + posmod(floori(moving_time * fps), count)
	return {"frame": frame, "mirrored": mirrored}


## Which part of a sheet is one frame.
static func frame_region(texture: Texture2D, hframes: int, vframes: int, frame: int) -> Rect2:
	var across := maxi(hframes, 1)
	var down := maxi(vframes, 1)
	var size := texture.get_size() / Vector2(across, down)
	var shown := posmod(frame, across * down)
	return Rect2(Vector2(shown % across, shown / across) * size, size)


## Which way and how long shadows are, for every unit of height.
static func shadow_slant(rules: Dictionary) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(float(rules["sun_angle"]))) * float(rules["sun_length"])


static var _images := {} # a texture -> its picture, for reading pixels
static var _gaps := {}


## How many empty rows are under the art in this part of a sheet. Sprites stand on
## their art, not on the edge of their frame, so nothing looks like it's floating.
static func bottom_gap(texture: Texture2D, region: Rect2) -> int:
	var key := "%d/%s" % [texture.get_instance_id(), region]
	if _gaps.has(key):
		return _gaps[key]
	var id := texture.get_instance_id()
	if not _images.has(id):
		var image := texture.get_image()
		if image != null and image.is_compressed():
			image.decompress()
		_images[id] = image
	var picture: Image = _images[id]
	var gap := 0
	if picture != null:
		var box := Rect2i(region)
		for y in range(box.end.y - 1, box.position.y - 1, -1):
			var found := false
			for x in range(box.position.x, box.end.x):
				if picture.get_pixel(x, y).a > 0.1:
					found = true
					break
			if found:
				break
			gap += 1
		if gap >= box.size.y:
			gap = 0 # nothing in the frame at all
	_gaps[key] = gap
	return gap


## A sprite's slanted black copy lying on the ground from its feet, away from the sun.
## It's drawn solid inside RoomView's shadow group, which makes the whole lot one even
## see-through shade, so where shadows meet doesn't get any darker.
static func draw_shadow(canvas: CanvasItem, base: Transform2D, texture: Texture2D, region: Rect2, feet: Vector2, scale: float, rules: Dictionary, mirrored := false, gap := 0) -> void:
	# A point this far up the sprite lands this far along the ground
	# (Flipped by turning the x axis round: a negative rectangle gets drawn somewhere else)
	var slant := Transform2D(Vector2.LEFT if mirrored else Vector2.RIGHT, -shadow_slant(rules), feet)
	canvas.draw_set_transform_matrix(base * slant)
	var size := region.size * scale
	var box := Rect2(Vector2(-size.x / 2.0, -size.y + gap * scale), size)
	canvas.draw_texture_rect_region(texture, box, region, Color.BLACK)
	canvas.draw_set_transform_matrix(base)


## Whether a room has the sun out.
static func sun_on(room: Dictionary, rules: Dictionary) -> bool:
	match str(room["sun"]):
		"on": return true
		"off": return false
	return bool(rules["sun"])
