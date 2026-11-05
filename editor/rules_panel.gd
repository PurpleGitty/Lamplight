extends "res://editor/inspector.gd"
## The chart maker's Rules tab: how this fight works, in folding sections. A
## Change Rules node can alter these mid-fight.

const LABELS := {
	"tp_enabled": "use TP", "start_tp": "starting TP", "max_tp": "maximum TP", "graze_tp": "per graze",
	"perfect_tp": "per PERFECT", "auto_revive": "auto revive",
	"revive_seconds": "seconds to revive", "defend_factor": "defending damage x", "invincibility": "safe seconds after hit",
	"soul_speed": "soul speed", "soul_sprite": "sprite", "soul_hframes": "frames across", "soul_hitbox_w": "hitbox width",
	"soul_hitbox_h": "hitbox height", "soul_hitbox_x": "hitbox x", "soul_hitbox_y": "hitbox y", "background_hframes": "frames across", "background_vframes": "frames down",
	"background_frames": "frames to loop", "background_beats": "beats per loop", "speech_font": "speech font", "menu_font": "menu font",
	"hurt_sound": "party hurt", "enemy_hurt_sound": "enemy hurt", "menu_move_sound": "menu move", "menu_select_sound": "menu select",
	"menu_back_sound": "menu back", "text_sound": "text blip",
}
const TYPE_NOTES := {
	"timed": "Turns follow the song. Lose when it ends.",
	"traditional": "The song loops with no time limit. The timeline counts frames (60 a second), and attacks start when the player finishes their turn.",
}


func _ready() -> void:
	show_hints = false # help stays in tooltips, to keep this tab readable


func refresh() -> void:
	_clear()
	var rules: Dictionary = editor.chart["rules"]

	_card("Battle type", Color("c8ff6b"))
	var row := HBoxContainer.new()
	_into().add_child(row)
	for type in TYPE_NOTES:
		var b := Button.new()
		b.text = type.capitalize()
		b.toggle_mode = true
		b.button_pressed = rules["battle_type"] == type
		b.focus_mode = FOCUS_NONE
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(func():
			editor.set_param(rules, "battle_type", type, false)
			refresh.call_deferred())
		row.add_child(b)
	_note(TYPE_NOTES[rules["battle_type"]])
	if ChartDefs.uses_frames(editor.chart):
		_note("Nodes keep their numbers when you switch: beat 32 becomes frame 32, so an existing chart needs re-timing.")

	_card("TP", Color("ffd24f"))
	_rule(rules, "tp_enabled", true)
	if rules["tp_enabled"]:
		_rule(rules, "start_tp")
		_rule(rules, "max_tp")
		_section("Earning TP")
		_rule(rules, "graze_tp")
		_rule(rules, "perfect_tp")

	_card("Getting back up", Color("8bffb0"))
	_rule(rules, "auto_revive", true)
	if rules["auto_revive"]:
		_rule(rules, "revive_seconds")

	_card("Soul and defense", Color("ff9ecb"))
	_rule(rules, "soul_speed")
	for key in ["soul_sprite", "soul_hframes", "soul_hitbox_w", "soul_hitbox_h", "soul_hitbox_x", "soul_hitbox_y"]:
		_rule(rules, key)
	_rule(rules, "invincibility")
	_rule(rules, "defend_factor")

	_card("Background", Color("7fd4ff"))
	_rule(rules, "background", true)
	if rules["background"] != "":
		_rule(rules, "background_hframes")
		_rule(rules, "background_vframes")
		_rule(rules, "background_frames")
		_rule(rules, "background_beats")

	_card("Fonts", Color("e0b0ff"))
	_rule(rules, "speech_font")
	_rule(rules, "menu_font")

	_card("Sounds", Color("ffb03b"))
	for key in ["hurt_sound", "enemy_hurt_sound", "menu_move_sound", "menu_select_sound", "menu_back_sound", "text_sound"]:
		_rule(rules, key)
	container = null


## `reshapes`: this setting shows or hides others, so redraw the tab.
func _rule(rules: Dictionary, key: String, reshapes := false) -> void:
	for p in ChartDefs.RULE_PARAMS:
		if p["name"] == key:
			_row(p.merged({"label": LABELS.get(key, key)}, true), rules[key], func(v):
				editor.set_param(rules, key, v, false)
				if reshapes:
					refresh.call_deferred())
