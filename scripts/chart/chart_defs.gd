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
	"change_objects": {
		"lane": "board", "label": "Change Objects", "color": Color("9fe0ff"), "length": 1.0,
		"help": "Changes any number of objects at once on this beat: blue/orange, see-through, tint, size, damage. With an easing other than instant, alpha and scale fade over the node's length.",
		"params": [
			{"name": "objects", "type": "object_list", "default": [], "help": "Tick the objects to change (only ones used in this attack are listed)"},
			{"name": "changes", "type": "object_changes", "default": []},
			{"name": "easing", "type": "enum", "default": "instant", "options": EASINGS},
		]},
	"math_attack": {
		"lane": "board", "label": "Math Attack", "color": Color("ff6bd6"), "length": 8.0,
		"help": "Bullets placed by formulas, like a graphing calculator: patterns, waves, fractals and line drawings. Runs for the node's length. Overlap as many as you like.",
		"params": [
			{"name": "formula", "type": "formula", "default": "# Every bullet runs these lines, every frame\nradius = 50\nspeed = 0.5\na = u * tau + t * speed\nx = radius * cos(a)\ny = radius * sin(a)\nsize = 8\nhue = u\n"},
			{"name": "count", "type": "int", "default": 24, "min": 1, "max": 2000, "help": "How many bullets"},
			{"name": "sprite", "type": "texture", "default": "", "help": "What each bullet looks like, coloured by the formula (blank = a plain circle)"},
			{"name": "damage", "type": "int", "default": 20, "min": 0, "max": 999},
			{"name": "mode", "type": "enum", "default": "normal", "options": OBJECT_MODES, "help": "blue: only hurts if you move. orange: only hurts if you stay still"},
			{"name": "name", "type": "string", "default": "math", "help": "Shown as the cause of death: \"Testicina's math\""},
		]},

	# --- META LANE ---
	"change_rules": {
		"lane": "meta", "label": "Change Rules", "color": Color("c8ff6b"), "instant": true,
		"help": "Changes rules or character stats mid-fight, on this beat: phase changes, someone joining or leaving the fight, and so on.",
		"params": [
			{"name": "changes", "type": "rule_changes", "default": []},
		]},
	"play_anim": {
		"lane": "meta", "label": "Play Animation", "color": Color("a8e060"), "length": 2.0,
		"help": "Plays frames of a character's sprite sheet across the node's length, then goes back to idle.",
		"params": [
			{"name": "character", "type": "character", "default": ""},
			{"name": "first_frame", "type": "int", "default": 0, "min": 0, "max": 255},
			{"name": "frame_count", "type": "int", "default": 1, "min": 1, "max": 255},
		]},
	"soul_teleport": {
		"lane": "meta", "label": "Move Soul", "color": Color("ff80c0"), "instant": true,
		"help": "Puts the soul somewhere on this beat, measured from the board's centre.",
		"params": [
			{"name": "x", "type": "float", "default": 0.0, "min": -310.0, "max": 310.0},
			{"name": "y", "type": "float", "default": 0.0, "min": -230.0, "max": 230.0},
		]},
	"soul_speed": {
		"lane": "meta", "label": "Soul Speed", "color": Color("ff60a0"), "instant": true,
		"help": "Changes how fast the soul moves from this beat on.",
		"params": [
			{"name": "speed", "type": "float", "default": 128.0, "min": 0.0, "max": 1000.0, "help": "Pixels per second (normal is 128)"},
		]},
	"play_sound": {
		"lane": "meta", "label": "Play Sound", "color": Color("ffd24f"), "instant": true,
		"help": "Plays a sound on this beat.",
		"params": [
			{"name": "sound", "type": "audio", "default": ""},
			{"name": "volume", "type": "float", "default": 1.0, "min": 0.0, "max": 2.0},
		]},
	"music_volume": {
		"lane": "meta", "label": "Music Volume", "color": Color("ffb82f"), "length": 4.0,
		"help": "Fades the song's volume over the node's length.",
		"params": [
			{"name": "volume", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0},
		]},
}

## The drop-up tabs in the editor. A plain string is a node; a {"group", "items"}
## row opens a side column of its own.
const TABS := [
	{"name": "Soul", "color": Color("ff60a0"), "items": ["soul_teleport", "soul_speed"]},
	{"name": "Music", "color": Color("ffd24f"), "items": ["play_sound", "music_volume"]},
	{"name": "Attack", "color": Color("ff5c5c"), "items": [
		"begin_attack", "end_attack", "change_objects", "math_attack",
		{"group": "Spawning", "items": ["spawn", "despawn", "telegraph", "set_harmful"]},
		{"group": "Movement", "items": ["move_to", "move_by", "random_point", "target_soul", "launch", "stop", "orbit"]},
		{"group": "Looks", "items": ["spin", "face_soul", "scale_to", "fade_to"]},
	]},
	{"name": "Board", "color": Color("3fd0ff"), "items": ["rotate_board", "resize_board", "move_board", "shake_board"]},
	{"name": "Meta", "color": Color("c8ff6b"), "items": ["text", "change_rules", "play_anim"]},
]

## Settings every object (lane) has. Shown when you click a lane's name.
const OBJECT_MODES := ["normal", "blue", "orange"]
const OBJECT_PARAMS := [
	{"name": "name", "type": "string", "default": "pellet", "help": "Shown as the cause of death: \"Testicina's pellet\""},
	{"name": "lane_label", "type": "string", "default": "", "help": "Name on the timeline (blank = same as name)"},
	{"name": "sprite", "type": "texture", "default": "res://sprites/pellet.png", "help": "A sprite or sprite sheet (imports from anywhere on your PC)"},
	{"name": "hframes", "type": "int", "default": 1, "min": 1, "max": 64, "help": "Frames across in the sprite sheet"},
	{"name": "frame", "type": "int", "default": 0, "min": 0, "max": 255},
	{"name": "anim_frames", "type": "int", "default": 1, "min": 1, "max": 255, "help": "How many frames to loop through, starting at frame"},
	{"name": "anim_beats", "type": "float", "default": 1.0, "min": 0.01, "max": 1000.0, "help": "How long one loop takes"},
	{"name": "sprite_scale", "type": "float", "default": 0.5, "min": 0.05, "max": 16.0},
	{"name": "tint", "type": "color", "default": "ffffff"},
	{"name": "mode", "type": "enum", "default": "normal", "options": OBJECT_MODES, "help": "blue: only hurts if you move. orange: only hurts if you stay still"},
	{"name": "spawn_sound", "type": "audio", "default": "", "help": "Plays each time it spawns"},
	{"name": "hitbox_w", "type": "float", "default": 12.0, "min": 0.0, "max": 640.0},
	{"name": "hitbox_h", "type": "float", "default": 12.0, "min": 0.0, "max": 480.0},
	{"name": "hitbox_x", "type": "float", "default": 0.0, "min": -640.0, "max": 640.0, "help": "From the object's centre. [LMB DRAG] its hitbox in the preview to move it"},
	{"name": "hitbox_y", "type": "float", "default": 0.0, "min": -480.0, "max": 480.0},
	{"name": "damage", "type": "int", "default": 20, "min": 0, "max": 999},
]

## What Change Objects can change.
const OBJECT_CHANGE_KEYS := [
	{"name": "sprite", "type": "texture", "default": ""},
	{"name": "mode", "type": "enum", "default": "blue", "options": OBJECT_MODES},
	{"name": "alpha", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0},
	{"name": "scale", "type": "float", "default": 1.0, "min": 0.0, "max": 20.0},
	{"name": "tint", "type": "color", "default": "ffffff"},
	{"name": "harmful", "type": "bool", "default": true},
	{"name": "damage", "type": "int", "default": 20, "min": 0, "max": 999},
]

## Settings for the whole chart. Shown when nothing is selected.
const CHART_PARAMS := [
	{"name": "song", "type": "audio", "default": "res://sounds/Phonky Tribu - Funk Tribu.mp3"},
	{"name": "bpm", "type": "float", "default": 160.0, "min": 20.0, "max": 400.0},
	{"name": "offset", "type": "float", "default": 0.0, "min": -10.0, "max": 10.0, "help": "Seconds from the start of the audio to beat 0"},
]

## The fight's rules (the Rules tab). Change Rules nodes can alter all but battle_type.
const RULE_PARAMS := [
	{"name": "battle_type", "type": "enum", "default": "timed", "options": ["timed", "traditional"], "help": "timed: turns follow the song and you lose when it ends. traditional: the song loops, no time limit, and attacks are measured in frames (60 a second) and start when the player finishes their turn"},
	{"name": "tp_enabled", "type": "bool", "default": true, "help": "Off: no TP box, and specials are free"},
	{"name": "start_tp", "type": "float", "default": 0.0, "min": 0.0, "max": 1000.0},
	{"name": "max_tp", "type": "float", "default": 100.0, "min": 1.0, "max": 1000.0},
	{"name": "graze_tp", "type": "float", "default": 2.0, "min": 0.0, "max": 100.0, "help": "TP each time a graze pays out: every half of the soul's i-frame time while a bullet is in range"},
	{"name": "perfect_tp", "type": "float", "default": 10.0, "min": 0.0, "max": 100.0, "help": "TP for a PERFECT basic attack"},
	{"name": "auto_revive", "type": "bool", "default": true, "help": "Downed characters get back up while someone's still standing"},
	{"name": "revive_seconds", "type": "float", "default": 60.0, "min": 0.1, "max": 600.0},
	{"name": "defend_factor", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "help": "Damage is multiplied by this while defending"},
	{"name": "invincibility", "type": "float", "default": 1.0, "min": 0.0, "max": 10.0, "help": "Seconds of safety after a hit"},
	{"name": "soul_speed", "type": "float", "default": 128.0, "min": 0.0, "max": 1000.0},
	{"name": "soul_sprite", "type": "texture", "default": "", "help": "The soul's art (blank = the game's). The second frame flickers while it's safe after a hit"},
	{"name": "soul_hframes", "type": "int", "default": 2, "min": 1, "max": 2, "help": "Frames across in the soul's sprite"},
	{"name": "soul_hitbox_w", "type": "float", "default": 8.0, "min": 0.0, "max": 200.0, "help": "What bullets have to touch to hurt"},
	{"name": "soul_hitbox_h", "type": "float", "default": 8.0, "min": 0.0, "max": 200.0},
	{"name": "soul_hitbox_x", "type": "float", "default": 0.0, "min": -100.0, "max": 100.0, "help": "From the soul's centre"},
	{"name": "soul_hitbox_y", "type": "float", "default": 0.0, "min": -100.0, "max": 100.0},
	{"name": "background", "type": "texture", "default": "", "help": "A still image or sprite sheet, stretched to cover the screen (blank = the game's). When a Change Rules node swaps it, change its frames too"},
	{"name": "background_video", "type": "video", "default": "", "help": "A looping video instead of the image. MP4s get converted when you pick them"},
	{"name": "background_hframes", "type": "int", "default": 1, "min": 1, "max": 64, "help": "Frames across in the sprite sheet"},
	{"name": "background_vframes", "type": "int", "default": 1, "min": 1, "max": 64, "help": "Frames down in the sprite sheet"},
	{"name": "background_frames", "type": "int", "default": 0, "min": 0, "max": 4096, "help": "How many frames to loop through (0 = all of them)"},
	{"name": "background_beats", "type": "float", "default": 4.0, "min": 0.01, "max": 1000.0, "help": "Beats one loop takes"},
	{"name": "speech_font", "type": "font", "default": "", "help": "Speech bubbles and captions (blank = the game's)"},
	{"name": "menu_font", "type": "font", "default": "", "help": "The command box, names and minigame titles (blank = the game's)"},
	{"name": "hurt_sound", "type": "audio", "default": "", "help": "The party takes a hit (blank = the game's)"},
	{"name": "enemy_hurt_sound", "type": "audio", "default": "", "help": "An enemy takes a hit (blank = the game's)"},
	{"name": "menu_move_sound", "type": "audio", "default": "", "help": "Moving around the command box (blank = the game's)"},
	{"name": "menu_select_sound", "type": "audio", "default": "", "help": "Picking something in the command box (blank = the game's)"},
	{"name": "menu_back_sound", "type": "audio", "default": "", "help": "Going back in the command box (blank = the game's)"},
	{"name": "text_sound", "type": "audio", "default": "", "help": "Menu text and grazes (blank = the game's)"},
]

## Settings shared by player characters and enemies (the Characters tab).
const CHARACTER_PARAMS := [
	{"name": "name", "type": "string", "default": "Character"},
	{"name": "present", "type": "bool", "default": true, "help": "In the fight from the start (Change Rules can bring them in later)"},
	{"name": "sprite", "type": "texture", "default": "res://sprites/purplecina.png"},
	{"name": "hframes", "type": "int", "default": 1, "min": 1, "max": 64, "help": "Frames across in the sprite sheet"},
	{"name": "sprite_scale", "type": "float", "default": 4.0, "min": 0.05, "max": 16.0},
	{"name": "x", "type": "float", "default": 0.0, "min": -320.0, "max": 320.0, "help": "From the middle of the screen"},
	{"name": "y", "type": "float", "default": 0.0, "min": -240.0, "max": 240.0},
	{"name": "max_hp", "type": "int", "default": 100, "min": 1, "max": 999999},
	{"name": "defense", "type": "float", "default": 0.0, "min": 0.0, "max": 100.0, "help": "Percent less damage from every hit"},
	{"name": "voice", "type": "audio", "default": "", "help": "Sound byte per letter of speech (blank = default blip)"},
	{"name": "idle_first", "type": "int", "default": 0, "min": 0, "max": 255, "help": "First frame of the idle animation"},
	{"name": "idle_count", "type": "int", "default": 1, "min": 1, "max": 255},
	{"name": "idle_beats", "type": "float", "default": 4.0, "min": 0.25, "max": 256.0, "help": "Beats one idle loop takes"},
	{"name": "bob", "type": "string", "default": "1, 2", "help": "Hop height per beat, in sprite pixels, repeating. Blank = no bobbing"},
]
## Extra settings for player characters.
const PARTY_PARAMS := [
	{"name": "fight_damage", "type": "int", "default": 300, "min": 0, "max": 999999},
	{"name": "attack_sound", "type": "audio", "default": "", "help": "Plays when their FIGHT connects"},
	{"name": "fight_minigame", "type": "enum", "default": "timing_bar", "options": ["timing_bar", "guitar_swing", "boomerang", "rapid_tap", "scope"], "help": "What plays when they use FIGHT"},
	{"name": "attack_first", "type": "int", "default": 0, "min": 0, "max": 255, "help": "First frame of the attack animation"},
	{"name": "attack_count", "type": "int", "default": 0, "min": 0, "max": 255, "help": "0 = no attack animation"},
	{"name": "attack_seconds", "type": "float", "default": 0.4, "min": 0.01, "max": 10.0},
]

## The attack minigames a special (or a basic attack) can use, each with its own
## settings. To add one: write a script extending Minigame and list it here.
const MINIGAMES := {
	"timing_bar": {
		"label": "Timing bar", "script": "res://scripts/attack_meter.gd",
		"help": "Stop the bar on the target line (Undertale's attack).",
		"params": [
			{"name": "cross_time", "type": "float", "default": 0.9, "min": 0.1, "max": 10.0, "help": "Seconds for the bar to reach the target"},
		]},
	"guitar_swing": {
		"label": "Axe swing", "script": "res://scripts/minigames/guitar_swing.gd",
		"help": "The axe swings round a full circle. Tap as it passes the red point and it bounces back the other way, faster, toward a point further round. Damage builds until a miss or the enemy's turn, and the attack still lands either way.",
		"params": [
			{"name": "box_width", "type": "float", "default": 320.0, "min": 120.0, "max": 632.0, "help": "Size of the box it plays in"},
			{"name": "box_height", "type": "float", "default": 256.0, "min": 80.0, "max": 472.0},
			{"name": "sprite", "type": "texture", "default": "res://sprites/weapons/guitar_axe.png", "help": "The axe, pointing up and to the right with its handle's end in the bottom left corner"},
			{"name": "bounce_sound", "type": "audio", "default": "res://sounds/axe_bounce.mp3", "help": "Plays on each hit, higher the faster it's going"},
			{"name": "hit_sound", "type": "audio", "default": "res://sounds/axe_clang.mp3", "help": "Plays just before the enemy's hurt sound"},
			{"name": "start_speed", "type": "float", "default": 110.0, "min": 10.0, "max": 1000.0, "help": "Degrees per second"},
			{"name": "speed_up", "type": "float", "default": 1.15, "min": 1.0, "max": 3.0, "help": "Speed multiplier per hit"},
			{"name": "first_arc", "type": "float", "default": 70.0, "min": 5.0, "max": 320.0, "help": "How far round the first point is, in degrees"},
			{"name": "arc_step", "type": "float", "default": 25.0, "min": 0.0, "max": 180.0, "help": "Each swing is this much longer"},
			{"name": "tolerance", "type": "float", "default": 10.0, "min": 1.0, "max": 45.0, "help": "Degrees of leeway on a tap"},
			{"name": "damage_per_hit", "type": "float", "default": 0.4, "min": 0.0, "max": 10.0, "help": "Damage multiplier added per hit. No hits, no damage"},
		]},
	"boomerang": {
		"label": "Boomerang throw", "script": "res://scripts/minigames/boomerang.gd",
		"help": "The crosshair moves up and down while the blade's oval path grows and shrinks. Tap to throw: the blade flies round the oval and back, and has to hit the crosshair. Dead centre is maximum damage.",
		"params": [
			{"name": "box_width", "type": "float", "default": 420.0, "min": 120.0, "max": 632.0, "help": "Size of the box it plays in"},
			{"name": "box_height", "type": "float", "default": 216.0, "min": 80.0, "max": 472.0},
			{"name": "sprite", "type": "texture", "default": "res://sprites/weapons/crucible.png", "help": "The thrown weapon"},
			{"name": "spin_sound", "type": "audio", "default": "res://sounds/crucible_spin.ogg", "help": "Loops while it flies: faster and higher as it spins faster, a little quieter far from the soul"},
			{"name": "hit_sound", "type": "audio", "default": "res://sounds/crucible_slash.ogg", "help": "Plays just before the enemy's hurt sound"},
			{"name": "crosshair_speed", "type": "float", "default": 0.5, "min": 0.05, "max": 10.0, "help": "Trips up and down per second"},
			{"name": "low_hp_speed", "type": "float", "default": 1.5, "min": 0.0, "max": 10.0, "help": "How much faster it gets as the target's HP runs out. 1.5 = 2.5x speed at no HP, 0 = always the same"},
			{"name": "crosshair_size", "type": "float", "default": 16.0, "min": 3.0, "max": 60.0, "help": "How forgiving it is, in pixels. Its dot is maximum damage"},
			{"name": "oval_speed", "type": "float", "default": 0.3, "min": 0.0, "max": 5.0, "help": "Times per second the path grows and shrinks"},
			{"name": "oval_smallest", "type": "float", "default": 0.3, "min": 0.05, "max": 1.0, "help": "The path's height at its smallest, compared to its biggest"},
			{"name": "flight_time", "type": "float", "default": 1.3, "min": 0.2, "max": 10.0, "help": "Seconds for the whole throw, out and back"},
			{"name": "auto_throw", "type": "float", "default": 5.0, "min": 0.5, "max": 30.0, "help": "It throws itself after this many seconds"},
			{"name": "max_damage", "type": "float", "default": 2.0, "min": 0.0, "max": 10.0, "help": "Damage multiplier for a dead centre hit. A miss does no damage"},
		]},
	"rapid_tap": {
		"label": "Rapid tap", "script": "res://scripts/minigames/rapid_tap.gd",
		"help": "Mash to build damage before time runs out.",
		"params": [
			{"name": "tap_sound", "type": "audio", "default": "", "help": "Plays on every tap"},
			{"name": "duration", "type": "float", "default": 2.5, "min": 0.5, "max": 20.0, "help": "Seconds to mash"},
			{"name": "taps_for_full", "type": "float", "default": 16.0, "min": 1.0, "max": 200.0, "help": "Taps for full damage (and a PERFECT)"},
			{"name": "minimum", "type": "float", "default": 0.2, "min": 0.0, "max": 10.0, "help": "Damage multiplier with no taps"},
			{"name": "maximum", "type": "float", "default": 1.5, "min": 0.0, "max": 10.0, "help": "Damage multiplier at full"},
		]},
	"scope": {
		"label": "Sniper scope", "script": "res://scripts/minigames/scope.gd",
		"help": "A ring shrinks onto the target. Tap when it lines up.",
		"params": [
			{"name": "shot_sound", "type": "audio", "default": "", "help": "Plays when the shot connects"},
			{"name": "shrink_time", "type": "float", "default": 1.1, "min": 0.2, "max": 10.0, "help": "Seconds for the ring to close"},
			{"name": "leeway", "type": "float", "default": 3.0, "min": 0.5, "max": 20.0, "help": "Pixels of leeway for a PERFECT"},
			{"name": "perfect_multiplier", "type": "float", "default": 2.0, "min": 0.0, "max": 10.0},
		]},
}

## What specials and maneuvers can do. Timed effects last `turns` enemy turns
## (1 = through the next enemy turn); the others happen once, on use.
const EFFECTS := {
	"focus": {"label": "Draw enemy focus", "timed": true, "target": "self", "value": 1.0, "help": "Share of each hit aimed at the target (1 = all of it)"},
	"damage_taken": {"label": "Damage taken x", "timed": true, "target": "party", "value": 0.75, "help": "Multiplies damage the target takes"},
	"shield": {"label": "Blocks hits", "timed": true, "target": "party", "value": 1.0, "help": "This many hits do nothing"},
	"attack_power": {"label": "Attack power x", "timed": true, "target": "party", "value": 1.25, "help": "Multiplies the target's attack damage"},
	"enemy_defense": {"label": "Enemy damage taken x", "timed": true, "target": "", "value": 1.25, "help": "Multiplies all damage to enemies"},
	"tp_gain": {"label": "TP earned x", "timed": true, "target": "", "value": 2.0, "help": "Multiplies TP from grazes and PERFECTs"},
	"graze_radius": {"label": "Graze range x", "timed": true, "target": "", "value": 1.5, "help": "Multiplies how close counts as a graze"},
	"soul_speed": {"label": "Soul speed x", "timed": true, "target": "", "value": 1.3, "help": "Multiplies the soul's speed"},
	"bullet_size": {"label": "Bullet hitboxes x", "timed": true, "target": "", "value": 0.75, "help": "Multiplies the size of every bullet's hitbox"},
	"board_size": {"label": "Board size x", "timed": true, "target": "", "value": 1.3, "help": "Multiplies the board's size"},
	"invincibility": {"label": "Safe time x", "timed": true, "target": "", "value": 1.5, "help": "Multiplies the safe time after a hit"},
	"revive_speed": {"label": "Revive speed x", "timed": true, "target": "party", "value": 3.0, "help": "Multiplies how fast the target gets back up"},
	"heal": {"label": "Heal HP", "timed": false, "target": "lowest_hp", "value": 30.0, "help": "HP restored"},
	"hurt": {"label": "Lose HP", "timed": false, "target": "self", "value": 20.0, "help": "HP lost (never downs them)"},
	"gain_tp": {"label": "Gain TP", "timed": false, "target": "", "value": 20.0, "help": "TP gained right away"},
	"revive": {"label": "Revive now", "timed": false, "target": "downed", "value": 50.0, "help": "Brings a downed ally back with this % of their HP"},
}
const EFFECT_TARGETS := ["self", "allies", "party", "lowest_hp", "downed"]

const SPECIAL_PRESETS := {
	"crucible": {"name": "Crucible", "description": "Throw the blade round its path. Hit the crosshair for max damage.", "cost": 15.0, "damage": 500.0, "minigame": "boomerang"},
	"guitar": {"name": "Guitar", "description": "Keep the swing going to build huge damage.", "cost": 70.0, "damage": 1200.0, "minigame": "guitar_swing"},
	"p90": {"name": "P90", "description": "Mash to empty the magazine.", "cost": 20.0, "damage": 700.0, "minigame": "rapid_tap", "settings": {"tap_sound": "res://sounds/p90.ogg"}},
	"awp": {"name": "AWP", "description": "One careful shot for massive damage.", "cost": 80.0, "damage": 1600.0, "minigame": "scope", "settings": {"shot_sound": "res://sounds/awp.ogg"}},
	"heavy_slam": {"name": "Heavy Slam", "description": "A big, simple hit.", "cost": 30.0, "damage": 800.0, "minigame": "timing_bar"},
	"twin_strike": {"name": "Twin Strike", "description": "Two attacks in a row.", "cost": 25.0, "damage": 350.0, "hits": 2, "minigame": "timing_bar"},
	"sweep": {"name": "Sweep", "description": "Hits every enemy.", "cost": 35.0, "damage": 450.0, "hits_all": true, "minigame": "guitar_swing"},
	"siphon": {"name": "Siphon", "description": "Steals some health back.", "cost": 25.0, "damage": 350.0, "minigame": "timing_bar",
		"effects": [{"kind": "heal", "value": 25.0, "target": "self", "turns": 1}]},
	"sunder": {"name": "Sunder", "description": "Enemies take more damage for two turns.", "cost": 30.0, "damage": 300.0, "minigame": "timing_bar",
		"effects": [{"kind": "enemy_defense", "value": 1.3, "target": "", "turns": 2}]},
	"flashbang": {"name": "Flashbang", "description": "Blinds the enemy: smaller bullet hitboxes next turn.", "cost": 25.0, "damage": 150.0, "minigame": "boomerang",
		"effects": [{"kind": "bullet_size", "value": 0.7, "target": "", "turns": 1}]},
	"overdrive": {"name": "Overdrive", "description": "Mash for damage, and get some TP back.", "cost": 15.0, "damage": 400.0, "minigame": "rapid_tap",
		"effects": [{"kind": "gain_tp", "value": 10.0, "target": "", "turns": 1}]},
	"hype_riff": {"name": "Hype Riff", "description": "The whole party hits harder next turn.", "cost": 40.0, "damage": 400.0, "minigame": "guitar_swing",
		"effects": [{"kind": "attack_power", "value": 1.3, "target": "party", "turns": 1}]},
}

const MANEUVER_PRESETS := {
	"taunt": {"name": "Taunt", "description": "Draw the enemy's attacks onto you.", "text": "* {user} gets in the enemy's face.\n* All eyes on {user}!", "cost": 0.0,
		"effects": [{"kind": "focus", "value": 1.0, "target": "self", "turns": 1}]},
	"cover": {"name": "Cover", "description": "Take every hit for the party, but take them well.", "text": "* {user} steps in front of everyone.", "cost": 10.0,
		"effects": [{"kind": "focus", "value": 1.0, "target": "self", "turns": 1}, {"kind": "damage_taken", "value": 0.75, "target": "self", "turns": 1}]},
	"back_up": {"name": "Back Up", "description": "Bullets hurt more, but you earn far more TP.", "text": "* {user} backs up to get a better look.", "cost": 0.0,
		"effects": [{"kind": "damage_taken", "value": 1.25, "target": "party", "turns": 1}, {"kind": "tp_gain", "value": 2.0, "target": "", "turns": 1}]},
	"brace": {"name": "Brace", "description": "Take much less damage next turn.", "text": "* {user} braces.", "cost": 0.0,
		"effects": [{"kind": "damage_taken", "value": 0.5, "target": "self", "turns": 1}]},
	"intimidate": {"name": "Intimidate", "description": "The whole party takes less damage next turn.", "text": "* {user} stares the enemy down.", "cost": 15.0,
		"effects": [{"kind": "damage_taken", "value": 0.75, "target": "party", "turns": 1}]},
	"barrier": {"name": "Barrier", "description": "The next hit on the party does nothing.", "text": "* {user} throws up a barrier.", "cost": 25.0,
		"effects": [{"kind": "shield", "value": 1.0, "target": "party", "turns": 1}]},
	"first_aid": {"name": "First Aid", "description": "Heals whoever's most hurt.", "text": "* {user} patches someone up.", "cost": 15.0,
		"effects": [{"kind": "heal", "value": 30.0, "target": "lowest_hp", "turns": 1}]},
	"group_heal": {"name": "Group Heal", "description": "Heals everyone a little.", "text": "* {user} looks after everyone.", "cost": 30.0,
		"effects": [{"kind": "heal", "value": 20.0, "target": "party", "turns": 1}]},
	"second_wind": {"name": "Second Wind", "description": "Downed allies get back up three times as fast.", "text": "* {user} yells for them to get up!", "cost": 10.0,
		"effects": [{"kind": "revive_speed", "value": 3.0, "target": "party", "turns": 2}]},
	"pull_up": {"name": "Pull Up", "description": "Revive a downed ally right now.", "text": "* {user} drags them back up.", "cost": 60.0,
		"effects": [{"kind": "revive", "value": 50.0, "target": "downed", "turns": 1}]},
	"rally": {"name": "Rally", "description": "The party hits harder for two turns.", "text": "* {user} fires everyone up.", "cost": 20.0,
		"effects": [{"kind": "attack_power", "value": 1.3, "target": "party", "turns": 2}]},
	"expose": {"name": "Expose", "description": "Enemies take more damage for two turns.", "text": "* {user} spots a weak point.", "cost": 15.0,
		"effects": [{"kind": "enemy_defense", "value": 1.25, "target": "", "turns": 2}]},
	"sidestep": {"name": "Sidestep", "description": "The soul moves faster next turn.", "text": "* {user} calls out the openings.", "cost": 10.0,
		"effects": [{"kind": "soul_speed", "value": 1.4, "target": "", "turns": 1}]},
	"steady": {"name": "Steady", "description": "Bullet hitboxes are smaller next turn.", "text": "* {user} takes a breath. Everything slows down.", "cost": 20.0,
		"effects": [{"kind": "bullet_size", "value": 0.75, "target": "", "turns": 1}]},
	"make_room": {"name": "Make Room", "description": "The board is bigger next turn.", "text": "* {user} shoves the walls back.", "cost": 10.0,
		"effects": [{"kind": "board_size", "value": 1.35, "target": "", "turns": 1}]},
	"bait": {"name": "Bait", "description": "Grazing is easier and pays more next turn.", "text": "* {user} dances close to the danger.", "cost": 0.0,
		"effects": [{"kind": "graze_radius", "value": 1.6, "target": "", "turns": 1}, {"kind": "tp_gain", "value": 1.25, "target": "", "turns": 1}]},
	"blood_pact": {"name": "Blood Pact", "description": "Trade HP for TP right now.", "text": "* {user} gives up a little to get a lot.", "cost": 0.0,
		"effects": [{"kind": "hurt", "value": 20.0, "target": "self", "turns": 1}, {"kind": "gain_tp", "value": 30.0, "target": "", "turns": 1}]},
	"adrenaline": {"name": "Adrenaline", "description": "Longer safety after each hit next turn.", "text": "* {user}'s heart is racing.", "cost": 10.0,
		"effects": [{"kind": "invincibility", "value": 1.5, "target": "", "turns": 1}]},
}

## The rest of what a special or maneuver can have.
const MOVE_DEFAULTS := {
	"preset": "", "name": "New move", "description": "", "cost": 0.0, "text": "", "sprite": "", "sound": "",
	"use_first": 0, "use_count": 0, "use_seconds": 0.4, "effects": [],
}
const SPECIAL_DEFAULTS := {"damage": 500.0, "hits": 1, "hits_all": false, "minigame": "timing_bar", "settings": {}}


## A new special or maneuver from a preset, ready to customize.
static func new_move(is_special: bool, preset_id: String) -> Dictionary:
	var presets: Dictionary = SPECIAL_PRESETS if is_special else MANEUVER_PRESETS
	var move: Dictionary = presets[preset_id].duplicate(true)
	move["preset"] = preset_id
	fill_move(move, is_special)
	return move


## Makes sure a move has everything, whatever older chart it came from.
static func fill_move(move: Dictionary, is_special: bool) -> void:
	var base: Dictionary = MOVE_DEFAULTS.duplicate(true)
	if is_special:
		base.merge(SPECIAL_DEFAULTS.duplicate(true), true)
	base.merge(move, true)
	move.merge(base, true)
	for effect in move["effects"]:
		var info: Dictionary = EFFECTS[effect["kind"]]
		effect["target"] = effect.get("target", info["target"])
		effect["turns"] = effect.get("turns", 1)
	if is_special:
		fill_special(move)


static func new_effect() -> Dictionary:
	return {"kind": "damage_taken", "value": EFFECTS["damage_taken"]["value"], "target": EFFECTS["damage_taken"]["target"], "turns": 1}

const SONG_LOOP_FRAMES := 36000.0 # how far the timeline runs in a traditional battle

## What Change Rules can change about a character.
const CHARACTER_CHANGE_KEYS := [
	{"name": "present", "type": "bool", "default": true, "help": "In the fight or not"},
	{"name": "sprite", "type": "texture", "default": ""},
	{"name": "hframes", "type": "int", "default": 1, "min": 1, "max": 64},
	{"name": "voice", "type": "audio", "default": ""},
	{"name": "hp", "type": "int", "default": 100, "min": 0, "max": 999999},
	{"name": "max_hp", "type": "int", "default": 100, "min": 1, "max": 999999},
	{"name": "fight_damage", "type": "int", "default": 300, "min": 0, "max": 999999},
	{"name": "defense", "type": "float", "default": 0.0, "min": 0.0, "max": 100.0},
]


## Makes sure a special has a minigame and a value for each of its settings.
static func fill_special(special: Dictionary) -> void:
	if not MINIGAMES.has(special.get("minigame", "")):
		special["minigame"] = {"Guitar": "guitar_swing", "Crucible": "boomerang", "P90": "rapid_tap", "AWP": "scope"}.get(special.get("name", ""), "timing_bar")
	var settings := defaults(MINIGAMES[special["minigame"]]["params"])
	settings.merge(SPECIAL_PRESETS.get(special.get("preset", ""), {}).get("settings", {}), true)
	settings.merge(special.get("settings", {}), true)
	special["settings"] = settings


static func new_character(character_name: String, is_party: bool) -> Dictionary:
	var c := defaults(CHARACTER_PARAMS)
	c["name"] = character_name
	if is_party:
		c.merge(defaults(PARTY_PARAMS), true)
		c["specials"] = []
		c["maneuvers"] = []
	else:
		c["sprite"] = "res://sprites/purple_head.png"
		c["max_hp"] = 10000
		c["bob"] = ""
		c["x"] = 176.0
		c["y"] = -32.0
		c["acts"] = [{"name": "Check", "text": "* %s - Placeholder check text." % character_name}]
	return c


## The first fight's cast, so charts made before characters lived in charts still work.
static func default_party() -> Array:
	var purple := new_character("Purple", true)
	purple["x"] = -276.0
	purple["y"] = 168.0
	purple["voice"] = "res://sounds/voice_purple.wav"
	purple["attack_sound"] = "res://sounds/p_attack.ogg"
	# The distraction: hits hard, takes hits well, draws fire
	purple["max_hp"] = 120
	purple["fight_damage"] = 400
	purple["defense"] = 25.0
	purple["specials"] = [new_move(true, "crucible"), new_move(true, "guitar")]
	purple["maneuvers"] = [new_move(false, "taunt"), new_move(false, "brace"), new_move(false, "cover")]
	var violet := new_character("Violet", true)
	violet["sprite"] = "res://sprites/violetcina.png"
	violet["attack_sound"] = "res://sounds/v_attack.mp3"
	violet["x"] = -112.0
	violet["y"] = 168.0
	violet["fight_damage"] = 250
	violet["specials"] = [new_move(true, "p90"), new_move(true, "awp")]
	violet["maneuvers"] = [new_move(false, "back_up"), new_move(false, "first_aid"), new_move(false, "expose")]
	return [purple, violet]


static func default_enemies() -> Array:
	var enemy := new_character("Testicina", false)
	enemy["hframes"] = 8
	enemy["idle_first"] = 6
	enemy["acts"] = [
		{"name": "Check", "text": "* TESTICINA - Placeholder check text."},
		{"name": "Taunt", "text": "* You make a face at Testicina.\n* It doesn't seem to care."},
	]
	return [enemy]


static func new_chart() -> Dictionary:
	var chart := {"version": VERSION, "next_id": 1, "turn_events": [], "text_events": [], "meta_events": [], "board_events": [], "objects": []}
	for p in CHART_PARAMS:
		chart[p["name"]] = p["default"]
	chart["rules"] = defaults(RULE_PARAMS)
	chart["party"] = default_party()
	chart["enemies"] = default_enemies()
	return chart


## The settings Change Rules can change on a target ("rules" or a character's name).
static func change_keys(_chart: Dictionary, target: String) -> Array:
	if target == "rules":
		return RULE_PARAMS.filter(func(p): return p["name"] != "battle_type")
	return CHARACTER_CHANGE_KEYS


## In a traditional battle the timeline counts frames instead of beats.
static func uses_frames(chart: Dictionary) -> bool:
	return chart["rules"]["battle_type"] == "traditional"


## Timeline units per second.
static func units_per_second(chart: Dictionary) -> float:
	return 60.0 if uses_frames(chart) else chart["bpm"] / 60.0


## Which frame of a looping animation to show.
static func anim_frame(first: int, count: int, loop_length: float, now: float) -> int:
	if count <= 1 or loop_length <= 0.0:
		return first
	return first + posmod(floori(now / loop_length * count), count)


## A bob string ("1, 2") as a list of hop heights.
static func parse_bob(text: String) -> Array[float]:
	var heights: Array[float] = []
	for part in text.split(",", false):
		heights.append(part.strip_edges().to_float())
	return heights


static func lane_label(obj: Dictionary) -> String:
	return obj["lane_label"] if obj["lane_label"] != "" else obj["name"]


static func take_id(chart: Dictionary) -> int:
	var id: int = int(chart["next_id"])
	chart["next_id"] = id + 1
	return id


static func new_event(chart: Dictionary, type: String, beat: float) -> Dictionary:
	var def: Dictionary = TYPES[type]
	var length: float = def.get("length", 1.0)
	if chart.has("rules") and uses_frames(chart):
		length *= 15.0 # a default-length node shouldn't be a blink in frames
	return {"id": take_id(chart), "type": type, "beat": beat, "length": length, "params": defaults(def["params"])}


static func new_object(chart: Dictionary, object_name: String) -> Dictionary:
	var obj := defaults(OBJECT_PARAMS)
	obj["id"] = take_id(chart)
	obj["name"] = object_name
	obj["events"] = []
	return obj


static func defaults(param_defs: Array) -> Dictionary:
	var values := {}
	for p in param_defs:
		var value = p["default"]
		values[p["name"]] = value.duplicate(true) if value is Array else value
	return values


static func is_instant(type: String) -> bool:
	return TYPES[type].get("instant", false)


static func event_end(ev: Dictionary) -> float:
	return ev["beat"] + (0.0 if is_instant(ev["type"]) else ev["length"])


## The enemy's turns: [{"begin": event, "start": beat, "end": beat}, ...] in order.
## An attack with no End Attack after it lasts 24 beats (or 360 frames).
static func attacks(chart: Dictionary) -> Array:
	var turn_events: Array = chart["turn_events"].duplicate()
	turn_events.sort_custom(func(a, b): return a["beat"] < b["beat"])
	var result := []
	for i in turn_events.size():
		var ev: Dictionary = turn_events[i]
		if ev["type"] != "begin_attack":
			continue
		var end: float = ev["beat"] + (360.0 if uses_frames(chart) else 24.0)
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
	if ScrapFile.is_scrap(path):
		return ScrapFile.read(path)
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
	for ev in chart["turn_events"] + chart["text_events"] + chart["meta_events"] + chart["board_events"]:
		_fill_event(ev)
	chart["next_id"] = int(chart["next_id"])
	var rules := defaults(RULE_PARAMS)
	rules.merge(chart["rules"], true)
	chart["rules"] = rules
	for list in [[chart["party"], true], [chart["enemies"], false]]:
		for i in list[0].size():
			var full := new_character(list[0][i].get("name", "Character"), list[1])
			# Charts from before maneuvers and defense get the first fight's setup
			var had_maneuvers: bool = list[0][i].has("maneuvers")
			var had_defense: bool = list[0][i].has("defense")
			var had_attack_sound: bool = list[0][i].has("attack_sound")
			full.merge(list[0][i], true)
			list[0][i] = full
			for k in default_party():
				if k["name"] == full["name"]:
					if not had_maneuvers:
						full["maneuvers"] = k["maneuvers"]
					if not had_defense:
						full["defense"] = k["defense"]
					if not had_attack_sound:
						full["attack_sound"] = k["attack_sound"]
			for special in full.get("specials", []):
				fill_move(special, true)
			for maneuver in full.get("maneuvers", []):
				fill_move(maneuver, false)
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
	if ScrapFile.is_scrap(path):
		return ScrapFile.write(chart, path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(chart, "\t"))
	return OK


static var _loaded_files := {} # files read directly (from a scrap, or not yet seen by Godot)


static func forget_loaded_files() -> void:
	_loaded_files.clear()


## Loads a font from anywhere, or null if there isn't one. Fonts stay crisp, like
## the game's own pixel fonts.
static func load_font(path: String) -> Font:
	if path == "":
		return null
	if SafeFiles.is_game_file(path, SafeFiles.GAME_FONTS):
		var res = load(path)
		return res if res is Font else null
	if not SafeFiles.is_media_file(path, SafeFiles.FONTS):
		return null
	if not _loaded_files.has(path):
		var font := FontFile.new()
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_loaded_files[path] = font if font.load_dynamic_font(ProjectSettings.globalize_path(path)) == OK else null
	return _loaded_files[path]


## Loads a sprite. Files from a scrap or just imported from the chart maker aren't
## in Godot's import system, so they're read directly.
static func load_texture(path: String) -> Texture2D:
	if SafeFiles.is_game_file(path, SafeFiles.IMAGES):
		var res = load(path)
		if res is Texture2D:
			return res
	if SafeFiles.is_media_file(path, SafeFiles.IMAGES):
		if not _loaded_files.has(path):
			var image := Image.load_from_file(ProjectSettings.globalize_path(path))
			_loaded_files[path] = ImageTexture.create_from_image(image) if image else null
		if _loaded_files[path]:
			return _loaded_files[path]
	return preload("res://sprites/pellet.png")


## Loads a sound or song the same way. Returns null if there isn't one.
static func load_audio(path: String) -> AudioStream:
	if path == "":
		return null
	if SafeFiles.is_game_file(path, SafeFiles.SOUNDS):
		return load(path) as AudioStream
	if not SafeFiles.is_media_file(path, SafeFiles.SOUNDS):
		return null
	if not _loaded_files.has(path):
		var full := ProjectSettings.globalize_path(path)
		match path.get_extension().to_lower():
			"mp3": _loaded_files[path] = AudioStreamMP3.load_from_file(full)
			"ogg": _loaded_files[path] = AudioStreamOggVorbis.load_from_file(full)
			"wav": _loaded_files[path] = AudioStreamWAV.load_from_file(full)
			_: _loaded_files[path] = null
	return _loaded_files[path]


## Loads a video (only ever an .ogv), or null if there isn't one.
static func load_video(path: String) -> VideoStream:
	if path == "":
		return null
	if SafeFiles.is_game_file(path, SafeFiles.VIDEOS):
		return load(path) as VideoStream
	if not SafeFiles.is_media_file(path, SafeFiles.VIDEOS):
		return null
	var stream := VideoStreamTheora.new()
	stream.file = path
	return stream


## Makes a song or sound loop, whatever kind of file it is.
static func set_looping(stream: AudioStream, on: bool) -> void:
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = on


## Text nodes from `start` (inclusive) to `end` (exclusive), in order.
static func texts_between(chart: Dictionary, start: float, end: float) -> Array:
	var found: Array = chart["text_events"].filter(func(ev): return ev["beat"] >= start and ev["beat"] < end)
	found.sort_custom(func(a, b): return a["beat"] < b["beat"] or (a["beat"] == b["beat"] and a["id"] < b["id"]))
	return found
