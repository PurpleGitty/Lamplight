extends RichTextLabel
## Press the DEBUG key (F10) to toggle.

var debug := false


func _ready() -> void:
	visible = debug


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("DEBUG"):
		debug = !debug
		visible = debug
	if not debug:
		return

	var battle: Battle = owner
	var soul: Node2D = battle.soul
	text = "beat = %.2f  (song %.1fs)  clock = %.2f" % [battle.conductor.song_beat, battle.conductor.song_position, battle.clock()] + \
		"\nphase = %s, turn %d, ends at %.0f" % [Battle.Phase.keys()[battle.phase], battle.turn_number + 1, battle.phase_end_beat] + \
		"\nsoul = (%d, %d)  invincible = %s" % [soul.position.x, soul.position.y, soul.invincible_time > 0.0] + \
		"\ntp = %d" % battle.tp
	for member in battle.party:
		text += "\n%s hp = %d%s" % [member.display_name, member.hp, "  (DOWN %.0fs)" % member.revive_progress if member.is_down else ""]
	for foe in battle.enemies:
		text += "\n%s hp = %d / %d" % [foe.display_name, foe.hp, foe.max_hp]
