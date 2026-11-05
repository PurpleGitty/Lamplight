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
signal tp_gained(amount: float)

enum Phase { PLAYER, ENEMY, OVER }

const FALLBACK_CHART := "res://charts/testicina.json"
const TRADITIONAL_PAUSE := 1.0 # seconds of "about to attack" before a traditional enemy turn
const SCREEN_SIZE := Vector2(640, 480)
const SPEECH_FONT = preload("res://fonts/PixelOperator.ttf")
## Which sound node each rule replaces.
const SOUND_RULES := {
	"hurt_sound": "Spanked", "enemy_hurt_sound": "Damage", "menu_move_sound": "LightningbulbSpacebarClickKeyboard199448",
	"menu_select_sound": "Select", "menu_back_sound": "Deselect", "text_sound": "Txt",
}
## Rules that change how the fight looks or sounds, and so need putting into effect.
const LOOK_RULES := ["background", "background_video", "background_hframes", "background_vframes", "speech_font", "menu_font",
	"soul_sprite", "soul_hframes", "soul_hitbox_w", "soul_hitbox_h", "soul_hitbox_x", "soul_hitbox_y"]

## Which chart to play next. The chart maker's Test Fight sets this.
static var chart_to_play := ""
## Where to go when the fight's over, when it started from an overworld ("" = stay here).
static var return_scene := ""
static var last_fight_won := false
## What BACK does on the game over screen, when an overworld started the fight.
static var give_up_label := "CARRY ON"
## From an overworld: name -> {"hp", "max_hp", "fight_damage", "defense", "specials", "maneuvers"}.
## Anyone here with the same name as someone in the fight brings these along, and their HP
## gets written back afterwards.
static var overworld_party := {}

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
var _focus_deal := {} # PartyMember -> shares dealt to them at the start of this player turn
var _shares := {} # PartyMember -> how much of each hit they take: the deal, plus focus effects
var _captions_shown := 0 # status captions of the current attack already shown
var _meta: Array = [] # meta nodes in order
var _next_meta := 0
var _leaving: Array[Node] = [] # characters who left, freed at the next player turn
var _player_turn_id := 0
var _mods: Array = [] # timed effects in play: {"kind", "value", "turns", "targets"}
var _default_background: Texture2D
var _background_video: VideoStreamPlayer
var _background_video_path := ""
var _default_background_scale := Vector2.ONE
var _default_sounds := {} # rule -> the stream its node started with


func _ready() -> void:
	var path := chart_to_play if chart_to_play != "" else FALLBACK_CHART
	chart = ChartDefs.load_chart(path)
	if chart.is_empty():
		push_error("Couldn't load a chart from %s - make one in the Scrap O' Matic" % path)
		chart = ChartDefs.new_chart()
	_bring_overworld_party()
	rules = chart["rules"].duplicate()
	traditional = ChartDefs.uses_frames(chart)
	tp = rules["start_tp"]
	attacks = ChartDefs.attacks(chart)
	_meta = chart["meta_events"].duplicate()
	_meta.sort_custom(func(a, b): return a["beat"] < b["beat"] or (a["beat"] == b["beat"] and a["id"] < b["id"]))
	_default_background = $Background.texture
	_default_background_scale = $Background.scale
	for rule in SOUND_RULES:
		_default_sounds[rule] = get_node(SOUND_RULES[rule]).stream
	_apply_look()
	_apply_sounds()
	var reticle := FocusReticle.new()
	reticle.battle = self
	reticle.z_index = 4
	layer.add_child(reticle) # the party are on this layer, and it goes over them

	for entry in chart["enemies"]:
		if entry["present"]:
			_add_enemy(entry)
	for entry in chart["party"]:
		if entry["present"]:
			var member := _add_member(entry)
			if overworld_party.has(entry["name"]):
				member.set_hp(clampi(int(overworld_party[entry["name"]]["hp"]), 1, member.max_hp))
	hud.layout_party()

	conductor.bpm = chart["bpm"]
	conductor.offset = chart["offset"]
	conductor.looping = traditional
	conductor.song_finished.connect(lose.bind("The song ran out"))
	$Music.bus = &"Music"
	$Music.stream = ChartDefs.load_audio(chart["song"])
	ChartDefs.set_looping($Music.stream, traditional)
	conductor.start()
	start_player_turn()


func _bring_overworld_party() -> void:
	for entry in chart["party"]:
		if not overworld_party.has(entry["name"]):
			continue
		var from: Dictionary = overworld_party[entry["name"]]
		for key in ["max_hp", "fight_damage", "defense"]:
			entry[key] = from[key]
		# Someone with no moves set keeps the fight's own
		if not from["specials"].is_empty():
			entry["specials"] = from["specials"].map(func(id): return ChartDefs.new_move(true, id))
		if not from["maneuvers"].is_empty():
			entry["maneuvers"] = from["maneuvers"].map(func(id): return ChartDefs.new_move(false, id))


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
	_animate_background()
	if phase == Phase.OVER:
		if can_restart and return_scene != "" and last_fight_won and Input.is_action_just_pressed("ACCEPT"):
			_go_back_to_overworld()
		elif can_restart and Input.is_action_just_pressed("ACCEPT"):
			GameSettings.reload_scene()
		elif can_restart and Input.is_action_just_pressed("BACK"):
			if return_scene != "":
				_go_back_to_overworld()
			else:
				GameSettings.go_to("res://menu.tscn")
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
		_tick_mods()
		start_player_turn()
	else:
		_show_due_captions(beat)


func _process_traditional(delta: float) -> void:
	if phase != Phase.ENEMY:
		return
	attack_time += delta * 60.0
	if attack_time >= current_attack["end"]:
		turn_number += 1
		_tick_mods()
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
	caption.add_theme_font_override("normal_font", speech_font())
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
	_roll_focus() # now, so the player can see it coming
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
	_update_shares()
	var runtime := AttackRuntime.new(chart, attack, func(): return soul.global_position)
	soul.reset(runtime.soul_start)
	soul.show()
	board.open(runtime)
	phase_changed.emit(phase)


func win() -> void:
	if not _end_battle():
		return
	last_fight_won = true
	var choices := [["ACCEPT", "CONTINUE"]] if return_scene != "" else [["ACCEPT", "PLAY AGAIN"], ["BACK", "MAIN MENU"]]
	_show_banner("YOU WON\n* %s was defeated!\n\n%s" % [enemies[0].display_name, GameSettings.hint(choices)])
	can_restart = true


func _go_back_to_overworld() -> void:
	for member in party:
		if overworld_party.has(member.display_name):
			overworld_party[member.display_name]["hp"] = maxi(member.hp, 1)
	var scene := return_scene
	return_scene = ""
	chart_to_play = ""
	GameSettings.go_to(scene)


func lose(cause: String) -> void:
	# The soul breaks where it was; if it wasn't out (player's turn), in the middle
	var soul_position: Vector2 = soul.global_position if soul.visible else Vector2.ZERO
	if not _end_battle():
		return
	last_fight_won = false
	conductor.stop()
	var lasted := _clock(_fight_seconds)
	if not traditional:
		lasted += " / " + _clock(conductor.song_length)
	var stats: Array[String] = []
	for foe in living_enemies():
		stats.append("%s had %d%% HP left" % [foe.display_name, foe.hp_percent()])
	stats.append("Cause of death: %s" % cause)
	stats.append("You lasted %s" % lasted)
	var screen := GameOver.new()
	add_child(screen)
	await screen.play(soul_position, stats, $Break, $GigaTalk, soul.sprite.texture, soul.frame_size())
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


## Each player turn, four shares of the next enemy turn's damage get dealt out at
## random, for the reticles to show.
func _roll_focus() -> void:
	_focus_deal.clear()
	var able: Array = living_members() if not living_members().is_empty() else party
	for member in party:
		_focus_deal[member] = 0.0
	if not able.is_empty():
		for i in 4:
			_focus_deal[able[randi() % able.size()]] += 1.0
	_update_shares()


## The deal, with any focus effects (Taunt and the like) pulling some or all of it
## onto their targets.
func _update_shares() -> void:
	_shares.clear()
	for member in party:
		_shares[member] = _focus_deal.get(member, 0.0)
	if party.is_empty():
		return
	for m in _mods:
		if m["kind"] != "focus":
			continue
		var targets: Array = m["targets"].filter(func(t): return t in party and not t.is_down)
		if targets.is_empty():
			continue
		var pull: float = clampf(m["value"], 0.0, 1.0)
		for member in party:
			_shares[member] *= 1.0 - pull
		for t in targets:
			_shares[t] += 4.0 * pull / targets.size()


## How much of each hit lands on this character, 0 to 1. If everyone it was aiming
## at is down, whoever's left shares it evenly.
func focus_share(member: PartyMember) -> float:
	if member.is_down:
		return 0.0
	var alive := living_members()
	var total := 0.0
	for other in alive:
		total += _shares.get(other, 0.0)
	return _shares.get(member, 0.0) / total if total > 0.0 else 1.0 / alive.size()


## Whether the enemy is mostly aiming at this character right now.
func is_focused(member: PartyMember) -> bool:
	var most := 0.0
	for s in _shares.values():
		most = maxf(most, s)
	return phase == Phase.ENEMY and most > 0.0 and _shares.get(member, 0.0) >= most


# --- effects from specials and maneuvers ---

## Does everything on a move's effect list.
func apply_effects(effects: Array, user: PartyMember) -> void:
	for effect in effects:
		var info: Dictionary = ChartDefs.EFFECTS.get(effect["kind"], {})
		if info.is_empty():
			continue
		var targets := _effect_targets(effect.get("target", ""), user)
		if info["timed"]:
			_mods.append({"kind": effect["kind"], "value": float(effect["value"]), "turns": int(effect.get("turns", 1)), "targets": targets})
			continue
		match effect["kind"]:
			"heal":
				for t in targets:
					if not t.is_down:
						t.set_hp(t.hp + roundi(effect["value"]))
			"hurt":
				for t in targets:
					if not t.is_down:
						t.set_hp(maxi(t.hp - roundi(effect["value"]), 1))
			"gain_tp":
				add_tp(float(effect["value"]))
			"revive":
				for t in targets:
					t.revive_now(float(effect["value"]) / 100.0)
	_update_shares()


func _effect_targets(target: String, user: PartyMember) -> Array:
	match target:
		"self":
			return [user]
		"allies":
			return party.filter(func(m): return m != user)
		"party":
			return party.duplicate()
		"downed":
			return party.filter(func(m): return m.is_down)
		"lowest_hp":
			var worst: PartyMember = null
			for m in living_members():
				if worst == null or float(m.hp) / m.max_hp < float(worst.hp) / worst.max_hp:
					worst = m
			return [worst] if worst else []
	return []


## All the timed effects of a kind multiplied together. Pass a character for
## effects aimed at someone; leave it out for effects on the whole fight.
func mod(kind: String, member: PartyMember = null) -> float:
	var total := 1.0
	for m in _mods:
		if m["kind"] == kind and (member == null or member in m["targets"]):
			total *= m["value"]
	return total


## A shield on this character eats the hit, if there is one.
func block_hit(member: PartyMember) -> bool:
	for m in _mods:
		if m["kind"] == "shield" and member in m["targets"] and m["value"] >= 1.0:
			m["value"] -= 1.0
			return true
	return false


## Earned TP (grazes, PERFECTs), which effects like Back Up multiply.
func earn_tp(amount: float) -> void:
	add_tp(amount * mod("tp_gain"))


## An enemy turn just ended: timed effects count down.
func _tick_mods() -> void:
	for m in _mods:
		m["turns"] -= 1
	_mods = _mods.filter(func(m): return m["turns"] > 0)


## Splits a hit between the party based on who the enemy is focusing this turn.
func damage_party(amount: int, source := "") -> void:
	last_hit_by = source
	var split := {}
	for member in living_members():
		split[member] = focus_share(member) # worked out first: a hit can down someone
	for member in split:
		member.take_damage(floori(amount * split[member]))


func add_tp(amount: float) -> void:
	var before := tp
	tp = clampf(tp + amount, 0, rules["max_tp"])
	if tp > before:
		tp_gained.emit(tp - before)


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
		if key in LOOK_RULES:
			_apply_look()
		elif SOUND_RULES.has(key):
			_apply_sounds()
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
		"sprite":
			if value != "":
				who.data[key] = value
				who.texture = ChartDefs.load_texture(value)
		"hframes":
			who.data[key] = value
			who.frame = 0
			who.hframes = maxi(int(value), 1)
		"voice":
			who.data[key] = value
			who.voice = ChartDefs.load_audio(value)
		_:
			who.data[key] = value # fight_damage and the like are read when they're used


## Puts the background and fonts from the rules into effect.
func _apply_look() -> void:
	var background: Sprite2D = $Background
	background.frame = 0
	background.visible = true
	background.self_modulate.a = 1.0
	var path: String = rules["background"]
	if path == "":
		background.texture = _default_background
		background.hframes = 1
		background.vframes = 1
		background.scale = _default_background_scale
	else:
		background.texture = ChartDefs.load_texture(path)
		background.hframes = maxi(int(rules["background_hframes"]), 1)
		background.vframes = maxi(int(rules["background_vframes"]), 1)
		var frame_size := background.texture.get_size() / Vector2(background.hframes, background.vframes)
		# Covers the whole screen, whatever shape it is
		var cover := maxf(SCREEN_SIZE.x / frame_size.x, SCREEN_SIZE.y / frame_size.y)
		background.scale = Vector2(cover, cover)
	if GameSettings.values["fx_backgrounds"]:
		_apply_background_video(background)
	else:
		background.self_modulate.a = 0.0 # plain black: easier to read, and less to draw
	hud.set_menu_font(ChartDefs.load_font(rules["menu_font"]))
	hud.bubble.label.add_theme_font_override("normal_font", speech_font())
	soul.set_look(rules)


## A video plays behind everything, and the image goes see-through (not hidden, since
## the dim during enemy turns hangs off it).
func _apply_background_video(background: Sprite2D) -> void:
	var path: String = rules["background_video"]
	background.self_modulate.a = 0.0 if path != "" else 1.0
	if path == _background_video_path:
		return
	_background_video_path = path
	if _background_video == null:
		var behind := CanvasLayer.new()
		behind.layer = -10
		add_child(behind)
		_background_video = VideoStreamPlayer.new()
		_background_video.expand = true
		_background_video.size = SCREEN_SIZE
		_background_video.volume = 0.0
		_background_video.finished.connect(func(): _background_video.play())
		behind.add_child(_background_video)
	_background_video.stop()
	_background_video.stream = ChartDefs.load_video(path)
	background.self_modulate.a = 0.0 if _background_video.stream != null else 1.0
	if _background_video.stream != null:
		_background_video.play()


func _apply_sounds() -> void:
	for rule in SOUND_RULES:
		var chosen := ChartDefs.load_audio(rules[rule])
		get_node(SOUND_RULES[rule]).stream = chosen if chosen else _default_sounds[rule]


func _animate_background() -> void:
	var background: Sprite2D = $Background
	var total := background.hframes * background.vframes
	if total <= 1:
		return
	var count: int = int(rules["background_frames"])
	if count <= 0 or count > total:
		count = total
	background.frame = ChartDefs.anim_frame(0, count, rules["background_beats"], maxf(conductor.song_beat, 0.0)) % total


func speech_font() -> Font:
	var chosen := ChartDefs.load_font(rules["speech_font"])
	return chosen if chosen else SPEECH_FONT


## Brings a character into the fight or takes them out, mid-fight.
func _set_present(character_name: String, present: bool) -> void:
	var who := find_character(character_name)
	if present == (who != null):
		return
	if present:
		for entry in chart["party"]:
			if entry["name"] == character_name:
				_add_member(entry)
				_focus_deal[party[-1]] = 1.0
				_update_shares()
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
	banner.add_theme_font_size_override("font_size", 16) # the bold font is wide: 16 keeps every line on screen
	banner.add_theme_constant_override("outline_size", 8)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.position = Vector2(-300, -120)
	banner.size = Vector2(600, 200)
	banner.z_index = 10
	layer.add_child(banner)
