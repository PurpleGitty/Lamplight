class_name Battle
extends Node2D
## Runs one fight, all from a chart (made in the chart maker): who's in it, the
## rules, when the enemy attacks and what happens on every beat.
##
## In a timed battle, each Begin Attack -> End Attack is an enemy turn and the
## time in between is the player's turn. Turns change on the beat no matter what
## the player was in the middle of, and the song ending loses the fight.
## In a traditional battle the song loops with no time limit, the player's turn
## lasts until they've finished, and attacks are timed in frames.
##
## The fight ends when every enemy is dead or everyone in the party is down.

signal phase_changed(phase: Phase)

enum Phase { PLAYER, ENEMY, OVER }

const FALLBACK_CHART := "res://charts/testicina.json"
const TRADITIONAL_PAUSE := 1.0 # seconds of "about to attack" before a traditional enemy turn

## Which chart to play next. The chart maker's Test Fight sets this.
static var chart_to_play := ""

@onready var conductor: Conductor = $Conductor
@onready var board = $board
@onready var soul = $soul
@onready var hud = $CanvasLayer/hud
@onready var layer: CanvasLayer = $CanvasLayer

var party: Array[PartyMember] = []
var enemies: Array[Enemy] = []
var rules: Dictionary
## The first enemy still fighting (or the first one, if none are).
var enemy: Enemy:
	get:
		for e in enemies:
			if not e.is_dead():
				return e
		return enemies[0] if not enemies.is_empty() else null

var phase := Phase.PLAYER
var turn_number := 0 # counts player turns
var phase_end_beat := 0.0 # when the current phase ends (for the debug overlay)
var chart: Dictionary
var attacks: Array = [] # from ChartDefs.attacks(): [{"begin", "start", "end"}, ...]
var next_attack := 0
var current_attack: Dictionary
var tp := 0.0
var last_hit_by := "" # what landed the last hit, for the game over screen
var can_restart := false
var traditional := false
var attack_time := 0.0 # traditional battles: the current frame of the attack
var _fight_seconds := 0.0
var _shares := {} # PartyMember -> how much of each hit they take this enemy turn
var _captions_shown := 0 # status captions of the current attack already shown
var _meta: Array = [] # meta nodes in order
var _next_meta := 0
var _leaving: Array[Node] = [] # characters who left, freed at the next player turn
var _player_turn_id := 0


func _ready() -> void:
	var path := chart_to_play if chart_to_play != "" else FALLBACK_CHART
	chart = ChartDefs.load_chart(path)
	if chart.is_empty():
		push_error("No chart at %s - make one in the chart maker" % path)
		chart = ChartDefs.new_chart()
	rules = chart["rules"].duplicate()
	traditional = ChartDefs.uses_frames(chart)
	tp = rules["start_tp"]
	attacks = ChartDefs.attacks(chart)
	_meta = chart["meta_events"].duplicate()
	_meta.sort_custom(func(a, b): return a["beat"] < b["beat"] or (a["beat"] == b["beat"] and a["id"] < b["id"]))

	for entry in chart["enemies"]:
		if entry["present"]:
			_add_enemy(entry)
	for entry in chart["party"]:
		if entry["present"]:
			_add_member(entry)
	hud.layout_party()

	conductor.bpm = chart["bpm"]
	conductor.offset = chart["offset"]
	conductor.looping = traditional
	conductor.song_finished.connect(lose.bind("The song ran out"))
	$Music.stream = ChartDefs.load_audio(chart["song"])
	ChartDefs.set_looping($Music.stream, traditional)
	conductor.start()
	start_player_turn()


func _add_member(entry: Dictionary) -> PartyMember:
	var member := PartyMember.new()
	member.setup(entry, self)
	member.downed.connect(_on_member_downed)
	party.append(member)
	layer.add_child(member)
	layer.move_child(member, 0) # behind the menu box
	return member


func _add_enemy(entry: Dictionary) -> Enemy:
	var new_enemy := Enemy.new()
	new_enemy.setup(entry, self)
	new_enemy.died.connect(_on_enemy_died)
	enemies.append(new_enemy)
	layer.add_child(new_enemy)
	layer.move_child(new_enemy, 0)
	return new_enemy


func _process(delta: float) -> void:
	if phase == Phase.OVER:
		if can_restart and Input.is_action_just_pressed("ACCEPT"):
			get_tree().reload_current_scene()
		elif can_restart and Input.is_action_just_pressed("BACK"):
			get_tree().change_scene_to_file("res://menu.tscn")
		return

	_fight_seconds += delta
	if traditional:
		_process_traditional(delta)
	else:
		_process_timed()
	if phase != Phase.OVER:
		_fire_meta(clock())


func _process_timed() -> void:
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


func _process_traditional(delta: float) -> void:
	if phase != Phase.ENEMY:
		return
	attack_time += delta * 60.0
	if attack_time >= current_attack["end"]:
		turn_number += 1
		start_player_turn()
	else:
		_show_due_captions(attack_time)


## The chart's current position: the song's beat, or in a traditional battle the
## attack's frame.
func clock() -> float:
	return attack_time if traditional else conductor.song_beat


## Timeline units to seconds.
func to_seconds(units: float) -> float:
	return units / ChartDefs.units_per_second(chart)


## This player turn's flavor text, dialogue and status, from the chart's Text
## nodes between the last attack and the next one.
func current_turn() -> Dictionary:
	var turn := {"flavor": "* %s blocks the way." % enemy.display_name if enemy else "", "dialogue": [], "status": ""}
	var start: float = attacks[next_attack - 1]["end"] if next_attack > 0 else 0.0
	var end: float = attacks[next_attack]["start"] if next_attack < attacks.size() else INF
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
				turn["dialogue"].append({"speaker": p["speaker"], "text": p["text"]})
	return turn


## Status Text nodes placed during an attack pop up above the board on their beat.
func _show_due_captions(now: float) -> void:
	var due := ChartDefs.texts_between(chart, current_attack["start"], minf(now, current_attack["end"]) + 0.0001)
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
	layer.add_child(caption)
	var writer := TextMarkup.Typewriter.new()
	writer.start(caption, markup, 0.03)
	var typing := func(delta: float) -> void:
		if writer.update(delta):
			$Txt.play()
	var t := caption.create_tween()
	t.tween_method(func(_v): typing.call(get_process_delta_time()), 0.0, 1.0, 2.5)
	t.tween_property(caption, "modulate:a", 0.0, 0.5)
	t.tween_callback(caption.queue_free)


func start_player_turn() -> void:
	phase = Phase.PLAYER
	_player_turn_id += 1
	for gone in _leaving:
		gone.queue_free()
	_leaving.clear()
	if traditional:
		if next_attack >= attacks.size():
			next_attack = 0 # back to the first attack
		# Meta nodes between attacks all happen as this player turn starts
		if next_attack < attacks.size():
			_fire_meta(attacks[next_attack]["start"] - 0.0001)
	phase_end_beat = attacks[next_attack]["start"] if next_attack < attacks.size() else INF
	board.close()
	soul.hide()
	hud.begin_turn(current_turn())
	phase_changed.emit(phase)


## The menu calls this when the player has done everything they can this turn.
## Only traditional battles care: their enemy turn starts now, not on a beat.
func player_done() -> void:
	if not traditional:
		return
	var id := _player_turn_id
	await get_tree().create_timer(TRADITIONAL_PAUSE).timeout
	if id != _player_turn_id or phase != Phase.PLAYER:
		return
	if attacks.is_empty():
		turn_number += 1
		start_player_turn() # nothing to attack with: straight back to the player
		return
	attack_time = attacks[next_attack]["start"]
	start_enemy_turn(attacks[next_attack])
	next_attack += 1


func start_enemy_turn(attack: Dictionary) -> void:
	phase = Phase.ENEMY
	current_attack = attack
	_captions_shown = 0
	phase_end_beat = attack["end"]
	hud.end_turn()
	_roll_focus()
	var runtime := AttackRuntime.new(chart, attack, func(): return soul.global_position)
	soul.reset(runtime.soul_start)
	soul.show()
	board.open(runtime)
	phase_changed.emit(phase)


func win() -> void:
	if not _end_battle():
		return
	_show_banner("YOU WON\n* %s was defeated!\n\n[Z] play again   [X] main menu" % enemies[0].display_name)
	can_restart = true


func lose(cause: String) -> void:
	# The soul breaks where it was; if it wasn't out (player's turn), in the middle
	var soul_position: Vector2 = soul.global_position if soul.visible else Vector2.ZERO
	if not _end_battle():
		return
	conductor.stop()
	var lasted := _clock(_fight_seconds)
	if not traditional:
		lasted += " / " + _clock(conductor.song_length)
	var stats: Array[String] = [
		"%s had %d%% HP left" % [enemy.display_name, enemy.hp_percent()],
		"Cause of death: %s" % cause,
		"You lasted %s" % lasted,
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


func living_enemies() -> Array[Enemy]:
	var alive: Array[Enemy] = []
	for e in enemies:
		if not e.is_dead():
			alive.append(e)
	return alive


## Every enemy's MANEUVER options.
func all_acts() -> Array:
	var acts := []
	for e in living_enemies():
		acts.append_array(e.data["acts"])
	return acts


## Whoever speaks this line, or null if no one by that name is in the fight.
func find_character(character_name: String) -> Character:
	for c in party:
		if c.display_name == character_name:
			return c
	for c in enemies:
		if c.display_name == character_name:
			return c
	return null


## Each enemy turn, four shares of the damage get dealt out at random.
func _roll_focus() -> void:
	_shares.clear()
	for member in party:
		_shares[member] = 0
	if party.is_empty():
		return
	for i in 4:
		_shares[party[randi() % party.size()]] += 1


## Splits a hit between the party based on who the enemy is focusing this turn.
func damage_party(amount: int, source := "") -> void:
	last_hit_by = source
	var alive := living_members()
	var total := 0
	for member in alive:
		total += _shares.get(member, 0)
	for member in alive:
		# If everyone it was aiming at is down, the rest share it evenly
		var share: float = float(_shares.get(member, 0)) / total if total > 0 else 1.0 / alive.size()
		member.take_damage(floori(amount * share))


func add_tp(amount: float) -> void:
	tp = clampf(tp + amount, 0, rules["max_tp"])


func spend_tp(amount: float) -> void:
	tp = clampf(tp - amount, 0, rules["max_tp"])


func _on_member_downed() -> void:
	if living_members().is_empty():
		lose(last_hit_by)


func _on_enemy_died() -> void:
	if living_enemies().is_empty():
		win()


# --- meta nodes ---

func _fire_meta(now: float) -> void:
	while _next_meta < _meta.size() and _meta[_next_meta]["beat"] <= now:
		_run_meta(_meta[_next_meta])
		_next_meta += 1


func _run_meta(ev: Dictionary) -> void:
	var p: Dictionary = ev["params"]
	match ev["type"]:
		"change_rules":
			for change in p["changes"]:
				_apply_change(change)
		"play_anim":
			var who := find_character(p["character"])
			if who:
				who.play_anim(int(p["first_frame"]), int(p["frame_count"]), to_seconds(ev["length"]))
		"soul_teleport":
			var centre: Vector2 = board.runtime.board_center if board.runtime else Vector2.ZERO
			soul.position = centre + Vector2(p["x"], p["y"])
		"soul_speed":
			rules["soul_speed"] = p["speed"]
		"play_sound":
			play_sound(p["sound"], p["volume"])
		"music_volume":
			create_tween().tween_property($Music, "volume_db", linear_to_db(maxf(p["volume"], 0.0001)), to_seconds(ev["length"]))


func _apply_change(change: Dictionary) -> void:
	var key: String = change["key"]
	var value = change["value"]
	if change["target"] == "rules":
		rules[key] = value
		add_tp(0.0) # re-clamps TP if the maximum shrank
		return
	if key == "present":
		_set_present(change["target"], value)
		return
	var who := find_character(change["target"])
	if who == null:
		return
	match key:
		"max_hp":
			who.max_hp = int(value)
			if who is PartyMember:
				who.set_hp(mini(who.hp, who.max_hp))
			else:
				who.hp = mini(who.hp, who.max_hp)
		"hp":
			if who is PartyMember:
				who.set_hp(int(value))
			else:
				who.hp = clampi(int(value), 1, who.max_hp)
		_:
			who.data[key] = value # fight_damage and the like are read when they're used


## Brings a character into the fight or takes them out, mid-fight.
func _set_present(character_name: String, present: bool) -> void:
	var who := find_character(character_name)
	if present == (who != null):
		return
	if present:
		for entry in chart["party"]:
			if entry["name"] == character_name:
				_add_member(entry)
				_shares[party[-1]] = 1
				hud.layout_party()
		for entry in chart["enemies"]:
			if entry["name"] == character_name:
				_add_enemy(entry)
		return
	who.hide()
	_leaving.append(who)
	if who is PartyMember:
		party.erase(who)
		hud.layout_party()
		if living_members().is_empty():
			lose(last_hit_by)
	else:
		enemies.erase(who)
		if living_enemies().is_empty():
			enemies.append(who) # the win screen still needs a name
			win()


var _sound_players: Array[AudioStreamPlayer] = []
## Plays a sound from the chart. Sounds can overlap.
func play_sound(path: String, volume := 1.0) -> void:
	var stream := ChartDefs.load_audio(path)
	if stream == null:
		return
	var player: AudioStreamPlayer = null
	for candidate in _sound_players:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = AudioStreamPlayer.new()
		add_child(player)
		_sound_players.append(player)
	player.stream = stream
	player.volume_db = linear_to_db(maxf(volume, 0.0001))
	player.play()


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
	layer.add_child(banner)
