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
	text = "beat = %.2f  (song %.1fs)" % [battle.conductor.song_beat, battle.conductor.song_position] + \
		"\nphase = %s, turn %d, ends on beat %.0f" % [Battle.Phase.keys()[battle.phase], battle.turn_number + 1, battle.phase_end_beat] + \
		"\nsoul = (%d, %d)  invincible = %s" % [soul.position.x, soul.position.y, soul.invincible_time > 0.0] + \
		"\npurple hp = %d%s" % [battle.purple.hp, "  (DOWN %.0fs)" % battle.purple.revive_progress if battle.purple.is_down else ""] + \
		"\nviolet hp = %d%s" % [battle.violet.hp, "  (DOWN %.0fs)" % battle.violet.revive_progress if battle.violet.is_down else ""] + \
		"\nfocus = %d/4 on purple" % battle.enemy.focus + \
		"\ntp = %d" % battle.tp + \
		"\nenemy hp = %d / %d" % [battle.enemy.hp, battle.enemy.max_hp]
