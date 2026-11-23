class_name Tutorial
extends Node
## The campaign tutorial. It runs inside a real fight (so the soul, board, command box,
## TP and minigames are the game's own), but this script decides everything that
## happens, step by step, instead of a chart. ACCEPT moves the talking on.
##
## Lines in quotes above the board are the narrator talking over the board; lines in the
## command box are the narrator talking through it, the way flavor text would.

signal _accepted
signal _stage_done
signal _turn_done

const ENEMY_NAME := "Candy"
const SOUL_ART := "res://sprites/tutorial/blank_soul.png"
const DRUM := "res://sounds/tutorial/kick_60bpm.wav"
const APPEAR_SOUND = preload("res://sounds/tutorial/soul_appears.mp3")
const HEAL_SOUND := "res://sounds/tutorial/heal.mp3"
const SLAP_SOUND := "res://sounds/tutorial/slap.mp3"
const MENU_SCENE := "res://scenes/menu.tscn"
const HUD = preload("res://scripts/hud.gd")
const BOARD_SIZE := Vector2(128, 128)
const DODGES_NEEDED := 10
const FIREBALL_DAMAGE := 25
const FIREBALL_SPEED := 100.0 # pixels a second
const WALL_DAMAGE := 100
const WALL_SPEED := 150.0
const HEAL_AFTER := 1.0 # seconds after a hit while earning TP
const SPAWN_ABOVE := 12.0 # fireballs start this far above the board's top
const FIGHT_TAB := 0
const SPECIAL_TAB := 1
const MANEUVER_TAB := 2
const DEFEND_TAB := 3
const CAPTION_SPEED := 0.03 # seconds per letter
const BOX_LETTERS := 115 # longer lines are split across pages, so they fit the command box
const SHARDS := 6
const SHARD_GRAVITY := 500.0

var battle: Battle
var hud
var _member: PartyMember
var _enemy: Enemy
var _caption := RichTextLabel.new()
var _caption_writer := TextMarkup.Typewriter.new()
var _waiting := false
var _stage := "" # "dodge" or "tp" while fireballs are falling, "wall" for DEFEND's attack
var _spawning := false
var _fireballs: Array[Fireball] = []
var _streak := 0 # fireballs dodged in a row
var _hurt_yet := false
var _last_hp := 0
var _heal_in := -1.0
var _breaking := false
var _shards: Array = [] # [{"sprite", "velocity"}]
var _beat_was := 0.0 # how far through the beat it was last frame


## The tutorial's fight: one of you, Candy (unseen), and a drum loop at 60 BPM. Everything
## else comes in as it's taught.
static func make_chart() -> Dictionary:
	var chart := ChartDefs.new_chart()
	chart["song"] = DRUM
	chart["bpm"] = 60.0
	chart["offset"] = 0.0
	var rules: Dictionary = chart["rules"]
	rules["battle_type"] = "traditional"
	rules["game_art"] = false
	rules["soul_sprite"] = SOUL_ART
	rules["soul_hframes"] = 2
	rules["tp_enabled"] = false # the TP box comes in once it's explained
	rules["auto_revive"] = false
	rules["graze_tp"] = 10.0
	var you := ChartDefs.new_character(player_name(), true)
	you["sprite"] = ""
	you["bob"] = ""
	you["max_hp"] = 100
	you["fight_damage"] = 300
	you["attack_sound"] = SLAP_SOUND
	you["x"] = -276.0
	you["y"] = 168.0
	chart["party"] = [you]
	var candy := ChartDefs.new_character(ENEMY_NAME, false)
	candy["sprite"] = ""
	candy["max_hp"] = 999999
	candy["acts"] = []
	chart["enemies"] = [candy]
	return chart


## Whoever owns this computer or phone.
static func player_name() -> String:
	var found := ""
	if OS.has_feature("mobile"):
		found = OS.get_model_name()
	else:
		found = OS.get_environment("USERNAME")
		if found == "":
			found = OS.get_environment("USER")
	found = found.strip_edges()
	if found == "" or found == "GenericDevice":
		found = "You"
	return found.left(10)


func _ready() -> void:
	hud = battle.hud
	_member = battle.party[0]
	_enemy = battle.enemies[0]
	_last_hp = _member.hp
	battle.soul.hide()
	hud.shown_tabs = []
	hud.allowed_tabs = []
	hud.update_tab_visuals()
	hud.position.y = 248.0 # right off the bottom until it's brought in
	battle.get_node("CanvasLayer/timerbox").hide()
	battle.get_node("CanvasLayer/energybox/clock").hide()

	_caption.bbcode_enabled = true
	_caption.add_theme_font_override("normal_font", battle.speech_font())
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.scroll_active = false
	_caption.clip_contents = false
	_caption.size = Vector2(500, 96)
	_caption.position = Vector2(-250, -BOARD_SIZE.y / 2.0 - 12.0 - _caption.size.y)
	_caption.z_index = 6
	battle.layer.add_child(_caption)
	_run()


# --- the lesson, in order ---

func _run() -> void:
	await _seconds(1.0)
	await _soul_appears()
	_open_board()
	await _seconds(0.4)
	battle.phase = Battle.Phase.ENEMY # the soul can move now

	await _say("This is your SOUL.")
	await _say("Or, at least, a loose representation of it.")
	await _say("Go ahead and move it around with the arrow keys. You may also hold [%s] to slow down your movement for precise bullet-dodging." % GameSettings.binding_name("BACK", "key"))
	await _say("If you're on mobile or gamepad, you'll be using the joystick/d-pad for movement and [%s] for precise dodging." % GameSettings.binding_name("BACK", "pad"))
	_show_caption("")

	# The command box comes up, with just your name and HP for now
	await _seconds(0.8)
	hud.state = HUD.MenuState.WAITING
	hud.update_tab_visuals()
	hud._slide(HUD.OPEN_POS)
	await _seconds(0.5)
	await _tell("This yellow bar by your name shows your HP, or \"Hit Points\". For your personal safety, I'd recommend not letting it reach zero.")
	await _tell("Oh, don't worry! You aren't the protagonist for this campaign. Your party members will appear here during a real fight.")
	await _tell("Speaking of which...")
	hud._show_text("")
	battle.conductor.start() # the drum, at 60 BPM, and everything pulses along with it
	await _seconds(1.0)

	await _say("This game, at least the campaign, is entirely driven by music!")
	await _say("Time between turns, turn length, attack patterns... just about all of it.")
	await _say("It's time to start catching strays!")
	_show_caption("")
	await _dodging()
	await _say("Nicely done. Moving on.")
	_show_caption("")

	await _grazing()
	await _tell("Excellent.")
	await _attacking()
	await _timer()
	await _free_shot()
	await _maneuvers()
	await _checking()
	await _defending()
	await _last_words()


## Fades in, then pulses into place in the middle.
func _soul_appears() -> void:
	var soul = battle.soul
	soul.reset(Vector2.ZERO)
	soul.modulate.a = 0.0
	soul.show()
	_play(APPEAR_SOUND)
	var t := create_tween()
	t.tween_property(soul, "modulate:a", 1.0, 0.6)
	t.tween_property(soul.sprite, "scale", Vector2(1.7, 1.7), 0.06)
	t.tween_property(soul.sprite, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
	await _seconds(0.4)


func _open_board() -> void:
	var params := {"width": BOARD_SIZE.x, "height": BOARD_SIZE.y, "board_x": 0.0, "board_y": 0.0, "soul_x": 0.0, "soul_y": 0.0, "clip": true}
	var attack := {"begin": {"params": params}, "start": 0.0, "end": INF}
	battle.board.open(AttackRuntime.new(battle.chart, attack, func(): return battle.soul.global_position))


func _close_board() -> void:
	battle.phase = Battle.Phase.PLAYER
	battle.board.close()
	battle.soul.hide()


## Ten in a row without a scratch.
func _dodging() -> void:
	_streak = 0
	_stage = "dodge"
	_spawning = true
	await _stage_done
	_stage = ""


## Fill the TP bar by skimming past fireballs. Hits heal up after a moment.
func _grazing() -> void:
	_heal_up()
	battle.tp = 0.0
	battle.rules["tp_enabled"] = true # the TP box shows itself
	await _seconds(0.6)
	await _tell("This is your TP, or \"Tension\". The main way to accrue TP is by \"grazing\".")
	await _tell("In other words, you must just barely miss getting hit by bullets.")
	await _tell("We'll look at what TP does in a few moments. For now, simply reach 100% TP.")
	hud._show_text("")
	_show_caption("Don't get hit.")
	_stage = "tp"
	_spawning = true
	await _stage_done
	_stage = ""
	_heal_in = -1.0
	_heal_up()
	_show_caption("")
	await _seconds(0.5)
	_close_board()
	await _seconds(0.4)


func _attacking() -> void:
	_bring_in_tab(FIGHT_TAB)
	await _tell("Now it's time to learn why it's called a \"scrap\". Hit the [ATTACK] tab to begin your assault.")
	await _tell("Don't worry about me! I can take it.")
	await _tell("At the end of your party's turn, you'll begin the attack minigames and aftermath.")
	await _tell("Try to land the reticle directly on the iris for a perfect hit.")
	# A miss goes straight back to the menu to try again
	while true:
		await _player_turn()
		if hud.last_multiplier > 0.0:
			break
	if hud.last_perfect:
		await _tell("We got a showboat over here!")
	else:
		await _tell("Timing is key. Practice.")


func _timer() -> void:
	battle.get_node("CanvasLayer/timerbox").show()
	battle.get_node("CanvasLayer/energybox/clock").show()
	await _tell("That timer would normally show remaining time for a song.")
	await _tell("Since this is just a looping beat though, we have all the time in the world.")
	await _tell("BUT, it'll take a lot more than nice reflexes to win a timed battle.")


func _free_shot() -> void:
	var shot := {
		"name": "Free Shot", "description": "Sink it. Uses up all your TP.", "cost": battle.rules["max_tp"],
		"damage": 500.0, "minigame": "free_shot", "settings": {"box_width": FreeShot.BOX.x, "box_height": FreeShot.BOX.y},
	}
	ChartDefs.fill_move(shot, true)
	# (The chart maker doesn't know this minigame, so filling it in swaps it out: put it back)
	shot["minigame"] = "free_shot"
	shot["settings"] = {"box_width": FreeShot.BOX.x, "box_height": FreeShot.BOX.y}
	_member.data["specials"] = [shot]
	_bring_in_tab(SPECIAL_TAB)
	await _tell("You'll be using your TP to unleash [SPECIALS], which are drastically more potent.")
	await _tell("In turn though, they can be tricky to execute and may have unintended side effects.")
	await _tell("Contrary to the name, \"Free Shot\" in your [SPECIALS] will actually cost all your TP.")
	var attempts := 0
	while true:
		battle.tp = battle.rules["max_tp"] # a miss gets it all back
		await _player_turn()
		attempts += 1
		if hud.last_multiplier > 0.0:
			break
	await _tell("%s time's the charm!" % _ordinal(attempts))


func _maneuvers() -> void:
	_bring_in_tab(MANEUVER_TAB)
	await _tell("Alright, now we will discuss [MANEUVERS]. They're really quite simple.")
	await _tell("Let's say I... I dunno...")
	_member.set_hp(1)
	_last_hp = 1
	battle.tp = 25.0
	battle.get_node("AudioStreamPlayer2D").play()
	battle.get_node("Damage").play()
	await _tell("Break all your bones viciously? And then give you some TP!")
	await _tell("Instead of screaming in agony, you can just heal yourself.")
	var placebo := {
		"name": "Placebo", "description": "Heals you to full. Uses up all your TP.", "cost": 25.0,
		"text": "* {user} takes a placebo.\n* Somehow, it works!", "sound": HEAL_SOUND,
		"effects": [{"kind": "heal", "value": 100.0, "target": "self", "turns": 1}],
	}
	ChartDefs.fill_move(placebo, false)
	_member.data["maneuvers"] = [placebo]
	await _player_turn()
	_last_hp = _member.hp
	await _tell("Not everyone can un-cripple themselves, but there are many [MANEUVERS] that a character can have.")
	await _tell("Not all of them will cost TP, thankfully.")
	await _tell("Anyway, are you going to \"check\" me out or what?")


func _checking() -> void:
	_member.data["maneuvers"] = []
	_enemy.data["acts"] = [{"name": "Check", "text": "* Candy\n* ??? AT   ??? DF   ??? HP\n* It's not immediately apparent to you if this is actually happening."}]
	await _player_turn(false)
	await _accept() # the check stays up until they've read it


func _defending() -> void:
	_bring_in_tab(DEFEND_TAB)
	await _tell("'Kay, and finally we have [DEFEND].")
	await _tell("Let's say my next attack does 100 base damage.")
	await _player_turn()
	# The attack: one big wall of fire, with no way round it
	hud.end_turn()
	battle.soul.reset(Vector2.ZERO)
	battle.soul.modulate.a = 1.0
	battle.soul.show()
	_open_board()
	await _seconds(0.4)
	battle.phase = Battle.Phase.ENEMY
	await _seconds(0.6)
	_stage = "wall"
	var wall := Fireball.wall(BOARD_SIZE.x + 48.0, WALL_DAMAGE, WALL_SPEED)
	wall.position = Vector2(0, -BOARD_SIZE.y / 2.0 - 20.0)
	_add_fireball(wall)
	await _stage_done
	_stage = ""
	await _seconds(0.6)
	_close_board()
	hud.state = HUD.MenuState.WAITING
	hud.update_tab_visuals()
	hud._slide(HUD.OPEN_POS)
	await _seconds(0.4)
	await _tell("Yeah.")
	await _tell("It helps if you wanna tank for the party or wait out an effect.")


## The wrap-up, then a choice: ATTACK starts the real fight with Candy, DEFEND leaves.
func _last_words() -> void:
	await _tell("Alright, that mostly covers everything.")
	await _tell("Do be aware that in a real scrap, you will lose automatically if you don't meet the winning criteria by the end of the song. This usually means killing your enemy.")
	await _tell("In this campaign, there really is no way to settle fights peacefully. Only really with interludes and custom scraps, which we won't cover here.")
	await _tell("Also, you have limited time to complete actions before your enemy's turn begins, so pick your moves and attack as quickly as possible.")
	await _tell("(You'll usually get informative or entertaining banter from the two parties if you finish your turn early!)")
	await _tell("So that's everything. Surely you aren't gonna quit back to the main menu before beating me in a real scrap right?")
	hud.shown_tabs = [FIGHT_TAB, SPECIAL_TAB, MANEUVER_TAB, DEFEND_TAB]
	hud.allowed_tabs = [FIGHT_TAB, DEFEND_TAB]
	hud.pulsing_tab = -1
	var picked := [-1]
	hud.tab_hook = func(tab: int) -> bool:
		picked[0] = tab
		hud.state = HUD.MenuState.WAITING
		hud.update_tab_visuals()
		_turn_done.emit()
		return true
	hud.begin_turn({"flavor": "* Attack to stay, defend to leave.", "dialogue": [], "status": ""})
	await _turn_done
	hud.tab_hook = Callable()
	if picked[0] == DEFEND_TAB:
		await _tell("Wuss.")
		_finish()
		return
	# The real thing
	TutorialEncounter.pending = true
	TutorialEncounter.from_name = _member.display_name
	Battle.tutorial = false
	Battle.chart_to_play = TutorialEncounter.CHART
	GameSettings.go_to("res://scenes/battle.tscn")


## Done for now: back to the main menu.
func _finish() -> void:
	hud._show_text("")
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.position = Vector2(-400, -300)
	black.size = Vector2(800, 600)
	black.z_index = 50
	black.modulate.a = 0.0
	battle.layer.add_child(black)
	var t := create_tween().set_parallel()
	t.tween_property(black, "modulate:a", 1.0, 1.0)
	t.tween_property(battle.get_node("Music"), "volume_db", -40.0, 1.0)
	await t.finished
	Battle.tutorial = false
	MainMenu.page = MainMenu.Page.MAIN
	GameSettings.go_to(MENU_SCENE)


# --- turns ---

## A new tab pops up: it's the only one that can be picked, and it pulses until it's used.
func _bring_in_tab(tab: int) -> void:
	if tab not in hud.shown_tabs:
		hud.shown_tabs.append(tab)
	hud.allowed_tabs = [tab]
	hud.pulsing_tab = tab
	hud.selected_tab = tab
	hud.state = HUD.MenuState.WAITING
	hud.update_tab_visuals()
	battle.get_node("Select").play()


## The player picks their move; it plays out; then back here.
func _player_turn(pulse := true) -> void:
	hud.last_multiplier = 0.0
	hud.last_perfect = false
	if not pulse:
		hud.pulsing_tab = -1
	hud.begin_turn({"flavor": "* %s blocks the way." % ENEMY_NAME, "dialogue": [], "status": ""})
	await _turn_done
	hud.pulsing_tab = -1


## The command box calls this (through the fight) once the player's move has played out.
func player_done() -> void:
	_turn_done.emit()


# --- talking ---

## Above the board. Waits for ACCEPT.
func _say(text: String) -> void:
	_show_caption(text)
	await _accept()


func _show_caption(text: String) -> void:
	_caption_writer.start(_caption, text, CAPTION_SPEED)


## In the command box, as flavor text. Waits for ACCEPT. Too long for the box, it goes
## over more than one page, split between sentences.
func _tell(text: String) -> void:
	for page in _pages(text):
		hud._show_text("* " + page)
		await _accept()


static func _pages(text: String) -> PackedStringArray:
	var pages := PackedStringArray()
	var page := ""
	for sentence in _sentences(text):
		if page != "" and (page + " " + sentence).length() > BOX_LETTERS:
			pages.append(page)
			page = sentence
		else:
			page = sentence if page == "" else page + " " + sentence
	pages.append(page)
	return pages


static func _sentences(text: String) -> PackedStringArray:
	var found := PackedStringArray()
	var start := 0
	for i in text.length():
		if text[i] in ".!?" and i + 1 < text.length() and text[i + 1] == " ":
			found.append(text.substr(start, i + 1 - start))
			start = i + 2
	found.append(text.substr(start))
	return found


func _accept() -> void:
	_waiting = true
	await _accepted


## The first press finishes the typing; the next moves on.
func _pressed_accept() -> void:
	if _caption_writer.is_typing():
		_caption_writer.finish()
		return
	if hud.writer.is_typing():
		hud.writer.finish()
		return
	_waiting = false
	_accepted.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _waiting and GameSettings.pressed(event, "ACCEPT"):
		get_viewport().set_input_as_handled()
		_pressed_accept()


func _input(event: InputEvent) -> void:
	if _waiting and GameSettings.tap_at(event) != Vector2.INF:
		get_viewport().set_input_as_handled()
		_pressed_accept()


# --- every frame ---

func _process(delta: float) -> void:
	if _caption_writer.update(delta):
		battle.get_node("Txt").play()
	if _member.hp < _last_hp and not _member.is_down:
		_hurt()
	_last_hp = _member.hp
	if _heal_in >= 0.0:
		_heal_in -= delta
		if _heal_in < 0.0 and not _member.is_down:
			_member.set_hp(_member.max_hp)
			_last_hp = _member.hp
			battle.play_sound(HEAL_SOUND)
	if _stage == "tp" and battle.tp >= battle.rules["max_tp"] and _spawning:
		_spawning = false
		_end_stage_when_clear()
	_update_shards(delta)
	# The drum loop is one beat long, so the song's beat count never goes up: a beat is
	# when the position in the beat wraps round
	var song := battle.conductor
	if song.playing:
		var through := fposmod(song.song_beat, 1.0)
		if through < _beat_was:
			_on_beat()
		_beat_was = through


func _hurt() -> void:
	match _stage:
		"dodge":
			_streak = 0
			for f in _fireballs:
				f.counts = false # a fireball already falling when you were hit doesn't count
			if not _hurt_yet:
				_hurt_yet = true
				_show_caption("Christ, I didn't mean literally! You need to weave between them!")
		"tp":
			_heal_in = HEAL_AFTER


# --- fireballs ---

## One falls on every beat, from somewhere along the top of the board.
func _on_beat() -> void:
	if not _spawning or _breaking:
		return
	var half := BOARD_SIZE.x / 2.0 - 8.0
	var x := randf_range(-half, half)
	if _stage == "tp" and randf() < 0.6:
		x = clampf(battle.soul.position.x + randf_range(-16.0, 16.0), -half, half) # near the soul, to graze
	var fireball := Fireball.new()
	fireball.damage = FIREBALL_DAMAGE
	fireball.speed = FIREBALL_SPEED
	fireball.position = Vector2(x, -BOARD_SIZE.y / 2.0 - SPAWN_ABOVE)
	_add_fireball(fireball)


func _add_fireball(fireball: Fireball) -> void:
	fireball.floor_y = BOARD_SIZE.y / 2.0 + 20.0
	fireball.landed.connect(_fireball_gone.bind(fireball))
	_fireballs.append(fireball)
	battle.board.contents.add_child(fireball)


func _fireball_gone(fireball: Fireball) -> void:
	_fireballs.erase(fireball)
	fireball.queue_free()
	match _stage:
		"dodge":
			if fireball.counts and not _breaking:
				_streak += 1
				if _streak >= DODGES_NEEDED and _spawning:
					_spawning = false
					_end_stage_when_clear()
		"wall":
			_stage_done.emit()


func _end_stage_when_clear() -> void:
	while not _fireballs.is_empty():
		await get_tree().process_frame
	_stage_done.emit()


func _clear_fireballs() -> void:
	for f in _fireballs:
		f.queue_free()
	_fireballs.clear()


# --- breaking ---

## HP hit zero: the soul breaks, then you're put back together to try again.
func soul_broke() -> void:
	if _breaking:
		return
	_breaking = true
	var was_spawning := _spawning
	_spawning = false
	_clear_fireballs()
	battle.phase = Battle.Phase.PLAYER
	var soul = battle.soul
	var at: Vector2 = soul.global_position
	soul.hide()
	await _shatter(at)
	_member.revive_now(1.0)
	_last_hp = _member.hp
	_heal_in = -1.0
	_show_caption("")
	await _tell("Ooooookay... Press %s to try again." % GameSettings.prompt("ACCEPT"))
	hud._show_text("")
	_streak = 0
	await _soul_appears() # just like the very start
	battle.phase = Battle.Phase.ENEMY
	_breaking = false
	if _stage == "tp" and battle.tp >= battle.rules["max_tp"]:
		_stage_done.emit()
	else:
		_spawning = was_spawning or _stage in ["dodge", "tp"]
		if _stage == "wall":
			_stage_done.emit()


## Cracks in two, then bursts into pieces (like a game over, but quicker).
func _shatter(at: Vector2) -> void:
	var texture: Texture2D = battle.soul.sprite.texture
	var frame: Vector2 = battle.soul.frame_size()
	var halves: Array[Sprite2D] = []
	for side in 2:
		var half := Sprite2D.new()
		half.texture = texture
		half.region_enabled = true
		half.region_rect = Rect2(Vector2(side * frame.x / 2.0, 0), Vector2(frame.x / 2.0, frame.y))
		half.position = at + Vector2((side - 0.5) * frame.x / 2.0, 1)
		half.z_index = 6
		battle.add_child(half)
		halves.append(half)
	await _seconds(0.5)
	battle.get_node("Break").play()
	halves[0].position.x -= 2
	halves[1].position.x += 2
	halves[0].rotation_degrees = -8
	halves[1].rotation_degrees = 8
	await _seconds(0.8)
	battle.get_node("GigaTalk").play()
	for half in halves:
		half.queue_free()
	for i in SHARDS:
		var shard := Sprite2D.new()
		shard.texture = texture
		shard.region_enabled = true
		shard.region_rect = Rect2(Vector2(randf_range(0.2, 0.6) * frame.x, randf_range(0.2, 0.6) * frame.y).floor(), (frame / 4.0).ceil())
		shard.position = at
		shard.z_index = 6
		battle.add_child(shard)
		_shards.append({"sprite": shard, "velocity": Vector2(randf_range(-140, 140), randf_range(-260, -80)), "age": 0.0})
	await _seconds(1.2)


func _update_shards(delta: float) -> void:
	for s in _shards:
		s["velocity"].y += SHARD_GRAVITY * delta
		s["sprite"].position += s["velocity"] * delta
		s["sprite"].rotation += delta * 8.0
		s["age"] += delta
		if s["age"] > 2.0:
			s["sprite"].queue_free()
	_shards = _shards.filter(func(s): return s["age"] <= 2.0)


# --- helpers ---

func _heal_up() -> void:
	if not _member.is_down:
		_member.set_hp(_member.max_hp)
		_last_hp = _member.hp


func _seconds(time: float) -> void:
	await get_tree().create_timer(time, false).timeout


func _play(stream: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


static func _ordinal(n: int) -> String:
	var ending := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: ending = "st"
			2: ending = "nd"
			3: ending = "rd"
	return "%d%s" % [n, ending]
