class_name Battle
extends Node2D
## Runs one fight. The enemy's chart (made in the attack editor) says when the
## enemy attacks: each Begin Attack -> End Attack is an enemy turn, and the
## time in between is the player's turn. Turns change on the beat no matter
## what the player was in the middle of. The fight ends when the enemy dies,
## both party members are down, or the song runs out.
## The chart's Text nodes give each player turn its flavor text, dialogue and
## status message; Text status nodes during an attack show as a caption.

signal phase_changed(phase: Phase)

enum Phase { PLAYER, ENEMY, OVER }

const MAX_TP := 100

@onready var conductor: Conductor = $Conductor
@onready var board = $board
@onready var soul = $soul
@onready var hud = $CanvasLayer/hud
@onready var enemy = $CanvasLayer/testicina
@onready var purple: PartyMember = $CanvasLayer/purple
@onready var violet: PartyMember = $CanvasLayer/violet
@onready var party: Array[PartyMember] = [purple, violet]

var phase := Phase.PLAYER
var turn_number := 0 # counts player turns; the enemy's turn_data (flavor, dialogue) loops
var phase_end_beat := 0.0 # when the current phase ends (for the debug overlay)
var chart: Dictionary
var attacks: Array = [] # from ChartDefs.attacks(): [{"begin", "start", "end"}, ...]
var next_attack := 0
var current_attack: Dictionary
var tp := 0.0
var last_hit_by := "" # what landed the last hit, for the game over screen
var can_restart := false
var _captions_shown := 0 # status captions of the current attack already shown


func _ready() -> void:
	purple.partner = violet
	violet.partner = purple
	for member in party:
		member.downed.connect(_on_member_downed)
	enemy.died.connect(win)
	conductor.song_finished.connect(lose.bind("The song ran out"))

	chart = ChartDefs.load_chart(enemy.chart_path)
	if chart.is_empty():
		push_error("No attack chart at %s - make one in editor/attack_editor.tscn" % enemy.chart_path)
	else:
		conductor.bpm = chart["bpm"]
		conductor.offset = chart["offset"]
		attacks = ChartDefs.attacks(chart)

	conductor.start()
	start_player_turn()


func _process(_delta: float) -> void:
	if phase == Phase.OVER:
		if can_restart and Input.is_action_just_pressed("ACCEPT"):
			get_tree().reload_current_scene()
		elif can_restart and Input.is_action_just_pressed("BACK"):
			get_tree().change_scene_to_file("res://menu.tscn")
		return

	var beat := conductor.song_beat
	if phase == Phase.PLAYER:
		# Skip attacks that are already over (e.g. after a lag spike)
		while next_attack < attacks.size() and attacks[next_attack]["end"] <= beat:
			next_attack += 1
		if next_attack < attacks.size() and attacks[next_attack]["start"] <= beat:
			start_enemy_turn(attacks[next_attack])
			next_attack += 1
	elif beat >= current_attack["end"]:
		turn_number += 1
		start_player_turn()
	else:
		_show_due_captions(beat)


## This player turn's flavor text, dialogue and status, from the chart's Text
## nodes between the last attack and the next one. Anything the chart doesn't
## set comes from the enemy's turn_data.
func current_turn() -> Dictionary:
	var fallback: Dictionary = enemy.turn_data[turn_number % enemy.turn_data.size()]
	var turn := {"flavor": fallback.get("flavor", ""), "dialogue": fallback.get("dialogue", []), "status": ""}
	var start: float = attacks[next_attack - 1]["end"] if next_attack > 0 else 0.0
	var end: float = attacks[next_attack]["start"] if next_attack < attacks.size() else INF
	var lines := []
	var flavor_set := false
	for ev in ChartDefs.texts_between(chart, start, end):
		var p: Dictionary = ev["params"]
		match p["kind"]:
			"flavor":
				if not flavor_set:
					turn["flavor"] = p["text"]
					flavor_set = true
			"status":
				turn["status"] = p["text"]
			_:
				lines.append({"speaker": p["speaker"], "text": p["text"]})
	if not lines.is_empty():
		turn["dialogue"] = lines
	return turn


## Status Text nodes placed during an attack pop up above the board on their beat.
func _show_due_captions(beat: float) -> void:
	var due := ChartDefs.texts_between(chart, current_attack["start"], minf(beat, current_attack["end"]) + 0.0001)
	due = due.filter(func(ev): return ev["params"]["kind"] == "status")
	while _captions_shown < due.size():
		_show_caption(due[_captions_shown]["params"]["text"])
		_captions_shown += 1


func _show_caption(markup: String) -> void:
	var caption := RichTextLabel.new()
	caption.add_theme_font_override("normal_font", preload("res://fonts/PixelOperator.ttf"))
	caption.add_theme_constant_override("outline_size", 6)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.scroll_active = false
	caption.clip_contents = false
	caption.size = Vector2(500, 60)
	var board_top: float = board.runtime.board_center.y - board.runtime.board_size.y / 2 if board.runtime else -64.0
	caption.position = Vector2(-250, board_top - 44)
	caption.z_index = 6
	$CanvasLayer.add_child(caption)
	var writer := TextMarkup.Typewriter.new()
	writer.start(caption, markup, 0.03)
	var typing := func(delta: float) -> void:
		if writer.update(delta):
			$Txt.play()
	var t := caption.create_tween()
	t.tween_method(func(v): typing.call(get_process_delta_time()), 0.0, 1.0, 2.5)
	t.tween_property(caption, "modulate:a", 0.0, 0.5)
	t.tween_callback(caption.queue_free)


func start_player_turn() -> void:
	phase = Phase.PLAYER
	phase_end_beat = attacks[next_attack]["start"] if next_attack < attacks.size() else INF
	board.close()
	soul.hide()
	hud.begin_turn(current_turn())
	phase_changed.emit(phase)


func start_enemy_turn(attack: Dictionary) -> void:
	phase = Phase.ENEMY
	current_attack = attack
	_captions_shown = 0
	phase_end_beat = attack["end"]
	hud.end_turn()
	enemy.roll_focus()
	var runtime := AttackRuntime.new(chart, attack, func(): return soul.global_position)
	soul.reset(runtime.soul_start)
	soul.show()
	board.open(runtime)
	phase_changed.emit(phase)


func win() -> void:
	if not _end_battle():
		return
	_show_banner("YOU WON\n* %s was defeated!\n\n[Z] play again   [X] main menu" % enemy.display_name)
	can_restart = true


func lose(cause: String) -> void:
	# The soul breaks where it was; if it wasn't out (player's turn), in the middle
	var soul_position: Vector2 = soul.global_position if soul.visible else Vector2.ZERO
	if not _end_battle():
		return
	conductor.stop()
	var stats: Array[String] = [
		"%s had %d%% HP left" % [enemy.display_name, ceili(100.0 * enemy.hp / enemy.max_hp)],
		"Cause of death: %s" % cause,
		"You lasted %s / %s" % [_clock(conductor.song_position), _clock(conductor.song_length)],
	]
	var screen := GameOver.new()
	add_child(screen)
	await screen.play(soul_position, stats, $Break, $GigaTalk)
	can_restart = true


## Stops everything; returns false if the battle was already over.
func _end_battle() -> bool:
	if phase == Phase.OVER:
		return false
	phase = Phase.OVER
	hud.end_turn()
	board.close()
	soul.hide()
	phase_changed.emit(phase)
	return true


func _clock(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds) / 60, floori(seconds) % 60]


func living_members() -> Array[PartyMember]:
	var alive: Array[PartyMember] = []
	for member in party:
		if not member.is_down:
			alive.append(member)
	return alive


## Splits a hit between Purple and Violet based on who the enemy is focusing.
## focus 0 = all on Violet, 4 = all on Purple. A lone survivor takes everything.
func damage_party(amount: int, source := "") -> void:
	last_hit_by = source
	var alive := living_members()
	if alive.size() == 2:
		var purple_share: float = enemy.focus / 4.0
		purple.take_damage(floori(amount * purple_share))
		violet.take_damage(floori(amount * (1.0 - purple_share)))
	elif alive.size() == 1:
		alive[0].take_damage(amount)


func add_tp(amount: float) -> void:
	tp = clampf(tp + amount, 0, MAX_TP)


func spend_tp(amount: float) -> void:
	tp = clampf(tp - amount, 0, MAX_TP)


func _on_member_downed() -> void:
	if living_members().is_empty():
		lose(last_hit_by)


func _show_banner(text: String) -> void:
	var banner := Label.new()
	banner.text = text
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_override("font", preload("res://fonts/PixelOperatorMono8-Bold.ttf"))
	banner.add_theme_font_size_override("font_size", 24)
	banner.add_theme_constant_override("outline_size", 8)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.position = Vector2(-300, -120)
	banner.size = Vector2(600, 200)
	banner.z_index = 10
	$CanvasLayer.add_child(banner)
