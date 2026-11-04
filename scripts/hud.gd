extends UIBox
## The command box. During the player's turn, each standing party member picks
## a move (FIGHT / SPECIAL / MANEUVER / DEFEND), then the moves play out, then
## any leftover time goes to the turn's dialogue.
## The enemy's turn starts on the beat no matter what, so every step that
## waits checks `turn_token` afterwards to see if it was interrupted.

enum MenuState { HIDDEN, TAB_SELECT, LIST_SELECT, TARGET_SELECT, EXECUTING, DIALOGUE, WAITING }

const OPEN_POS := Vector2(4, 96)
const PEEK_POS := Vector2(4, 200) # enemy turn: only the names and HP bars stay on screen
const TYPE_SPEED := 0.02 # seconds per character
const HIT_DELAY := 0.3 # pause between stopping the bar and the hit landing (weapon animations go here)

@onready var battle: Battle = owner
@onready var tabs: Array[Control] = [$fight, $special, $maneuver, $defend]
@onready var flavortext: RichTextLabel = $flavortext
@onready var menucontent: VBoxContainer = $menucontent
@onready var menu_font: Font = $mc1.get_theme_font("font")
var meter := AttackMeter.new()
var bubble := SpeechBubble.new()

var state := MenuState.HIDDEN
var selected_tab := 0
var selected_index := 0 # highlighted row in a SPECIAL/MANEUVER list
var list_kind := "" # "special" or "act"
var list_items: Array = []
var pending_choice = null # a FIGHT/SPECIAL waiting for its target
var target_options: Array[Enemy] = [] # enemies to choose from on the target screen
var target_index := 0
var party_rows: Array[Label] = []
var order: Array[PartyMember] = [] # who picks a move this turn, in order
var picker := 0 # index into `order`
var choices := {} # PartyMember -> chosen move
var flavor := ""
var dialogue: Array = []
var dialogue_index := 0
var turn_token := 0
var slide_tween: Tween
var tab_tween: Tween
var writer := TextMarkup.Typewriter.new() # types the menu text (with formatting)
var status := "" # replaces "* X is about to attack!" this turn, if set


func _ready() -> void:
	flavortext.bbcode_enabled = true
	flavortext.clip_contents = false # wavy/shaky letters may poke out a little
	meter.position = flavortext.position
	meter.size = flavortext.size
	meter.hide()
	add_child(meter)
	$mc1.hide() # the template the party's name and HP rows are copied from
	get_parent().add_child.call_deferred(bubble)


## Lays out one name + HP bar per party member, however many there are.
func layout_party() -> void:
	for row in party_rows:
		row.queue_free()
	party_rows.clear()
	var column := 291.0 / maxi(battle.party.size(), 1)
	for i in battle.party.size():
		var member: PartyMember = battle.party[i]
		var row: Label = $mc1.duplicate()
		row.text = member.display_name
		row.show()
		add_child(row)
		row.position = Vector2(25 + i * column, 12)
		var bar: TextureProgressBar = row.get_child(0)
		var name_width := menu_font.get_string_size(member.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		bar.position = Vector2(name_width + 6, 0)
		bar.size = Vector2(maxf(minf(50.0, column - name_width - 12), 8.0), 15)
		member.set_hud(row, bar)
		party_rows.append(row)


func _process(delta: float) -> void:
	# Type the menu text, with a blip for each new letter
	if writer.update(delta) and flavortext.visible:
		_sfx("Txt")

	var picking := current_member()
	for member in battle.party:
		if member == picking:
			member.name_label.self_modulate = Color.YELLOW
		elif member.is_down:
			member.name_label.self_modulate = Color.DIM_GRAY
		else:
			member.name_label.self_modulate = Color.WHITE


func current_member() -> PartyMember:
	if state in [MenuState.TAB_SELECT, MenuState.LIST_SELECT, MenuState.TARGET_SELECT]:
		return order[picker]
	return null


# --- TURN START / END (called by battle.gd) ---

func begin_turn(turn: Dictionary) -> void:
	turn_token += 1
	order = battle.living_members()
	picker = 0
	choices.clear()
	pending_choice = null
	for member in battle.party:
		member.defending = false
	flavor = turn["flavor"]
	dialogue = turn.get("dialogue", [])
	status = turn.get("status", "")
	selected_tab = 0
	enter_tab_select()
	_slide(OPEN_POS)


func end_turn() -> void:
	turn_token += 1
	state = MenuState.HIDDEN
	meter.cancel()
	bubble.hide()
	menucontent.hide()
	_show_text("")
	update_tab_visuals()
	_slide(PEEK_POS)


# --- PICKING MOVES ---

func _unhandled_input(event: InputEvent) -> void:
	match state:
		MenuState.TAB_SELECT: _tab_input(event)
		MenuState.LIST_SELECT: _list_input(event)
		MenuState.TARGET_SELECT: _target_input(event)
		MenuState.DIALOGUE: _dialogue_input(event)


func enter_tab_select() -> void:
	state = MenuState.TAB_SELECT
	menucontent.hide()
	_show_text(flavor)
	update_tab_visuals()


func _tab_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right") and selected_tab < tabs.size() - 1:
		selected_tab += 1
		_sfx("LightningbulbSpacebarClickKeyboard199448")
		update_tab_visuals()
	elif event.is_action_pressed("ui_left") and selected_tab > 0:
		selected_tab -= 1
		_sfx("LightningbulbSpacebarClickKeyboard199448")
		update_tab_visuals()
	elif event.is_action_pressed("ACCEPT"):
		_sfx("Select")
		match selected_tab:
			0: # FIGHT
				pending_choice = {"type": "fight"}
				enter_target_select()
			1: # SPECIAL
				open_list("special", current_member().data["specials"])
			2: # MANEUVER
				open_list("act", battle.all_acts())
			3: # DEFEND
				lock_choice({"type": "defend"})
	elif event.is_action_pressed("BACK") and picker > 0:
		# Undo the previous character's pick
		_sfx("Deselect")
		picker -= 1
		choices.erase(order[picker])
		enter_tab_select()


func open_list(kind: String, items: Array, index := 0) -> void:
	list_kind = kind
	list_items = items
	selected_index = index
	state = MenuState.LIST_SELECT
	var rows := []
	for item in items:
		if kind == "special":
			var cost := "%d TP" % item["cost"] if battle.rules["tp_enabled"] else ""
			rows.append({"text": "%s   %s" % [item["name"], cost], "enabled": item["cost"] <= available_tp()})
		else:
			rows.append({"text": item["name"], "enabled": true})
	_show_rows(rows, selected_index)


func _list_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down") and selected_index < list_items.size() - 1:
		selected_index += 1
		_sfx("LightningbulbSpacebarClickKeyboard199448")
		_highlight_row(selected_index)
	elif event.is_action_pressed("ui_up") and selected_index > 0:
		selected_index -= 1
		_sfx("LightningbulbSpacebarClickKeyboard199448")
		_highlight_row(selected_index)
	elif event.is_action_pressed("ACCEPT"):
		var item: Dictionary = list_items[selected_index]
		if list_kind == "special":
			if item["cost"] > available_tp():
				_sfx("Deselect") # can't afford it
				return
			_sfx("Select")
			pending_choice = {"type": "special", "move": item}
			enter_target_select()
		else:
			_sfx("Select")
			lock_choice({"type": "act", "act": item})
	elif event.is_action_pressed("BACK"):
		_sfx("Deselect")
		enter_tab_select()


func enter_target_select() -> void:
	state = MenuState.TARGET_SELECT
	target_options = battle.living_enemies()
	target_index = 0
	var rows := []
	for enemy in target_options:
		rows.append({"text": "* %s" % enemy.display_name, "enabled": true, "hp": enemy.hp_percent()})
	_show_rows(rows, 0)


func _target_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down") and target_index < target_options.size() - 1:
		target_index += 1
		_sfx("LightningbulbSpacebarClickKeyboard199448")
		_highlight_row(target_index)
	elif event.is_action_pressed("ui_up") and target_index > 0:
		target_index -= 1
		_sfx("LightningbulbSpacebarClickKeyboard199448")
		_highlight_row(target_index)
	elif event.is_action_pressed("ACCEPT"):
		_sfx("Select")
		pending_choice["target"] = target_options[target_index]
		lock_choice(pending_choice)
	elif event.is_action_pressed("BACK"):
		_sfx("Deselect")
		if pending_choice["type"] == "special":
			open_list("special", list_items, selected_index)
		else:
			enter_tab_select()


func lock_choice(choice: Dictionary) -> void:
	choices[order[picker]] = choice
	pending_choice = null
	picker += 1
	if picker < order.size():
		selected_tab = 0
		enter_tab_select()
	else:
		execute_choices()


## TP left after the specials already picked this turn are paid for
func available_tp() -> float:
	if not battle.rules["tp_enabled"]:
		return INF # specials are free
	var reserved := 0.0
	for choice in choices.values():
		if choice["type"] == "special":
			reserved += choice["move"]["cost"]
	return battle.tp - reserved


# --- PLAYING OUT THE MOVES ---

func execute_choices() -> void:
	state = MenuState.EXECUTING
	var token := turn_token
	menucontent.hide()
	update_tab_visuals()

	for member in order:
		var choice: Dictionary = choices[member]
		match choice["type"]:
			"defend":
				member.defending = true
				_show_text("* %s braces for impact." % member.display_name)
				await _wait(1.0)
			"act":
				_show_text(choice["act"]["text"])
				await _wait(2.5)
			"fight", "special":
				var damage: float = member.data["fight_damage"]
				var title := "%s attacks!" % member.display_name
				if choice["type"] == "special":
					if battle.rules["tp_enabled"]:
						battle.spend_tp(choice["move"]["cost"])
					damage = choice["move"]["damage"]
					title = "%s uses %s!" % [member.display_name, choice["move"]["name"]]
				flavortext.hide()
				meter.start(title)
				var multiplier: float = await meter.finished
				if token != turn_token:
					return
				if meter.perfect and choice["type"] == "fight":
					battle.add_tp(battle.rules["perfect_tp"])
				if int(member.data["attack_count"]) > 0:
					member.play_anim(int(member.data["attack_first"]), int(member.data["attack_count"]), member.data["attack_seconds"])
				await _wait(HIT_DELAY)
				if token != turn_token:
					return
				if multiplier > 0.0:
					var target: Enemy = choice["target"]
					if target.is_dead() and battle.enemy:
						target = battle.enemy # someone else got them first
					target.take_damage(roundi(damage * multiplier))
				await _wait(0.6)
				if token != turn_token:
					return
				meter.hide()
		if token != turn_token:
			return

	start_dialogue()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# --- DIALOGUE (only reached if the player was quick) ---

func start_dialogue() -> void:
	dialogue_index = 0
	if dialogue.is_empty():
		enter_waiting()
		return
	state = MenuState.DIALOGUE
	_show_text("")
	_show_dialogue_line()


func _show_dialogue_line() -> void:
	var line: Dictionary = dialogue[dialogue_index]
	var speaker: String = line["speaker"]
	var who := battle.find_character(speaker)
	if who is Enemy:
		# Bubble to the left of the enemy's head, tail pointing right
		bubble.say(line["text"], who.position + Vector2(-who.half_width() - 4, -16), SIDE_RIGHT, who.voice)
		return
	if who != null:
		# Bubble above their head, tail pointing down
		bubble.say(line["text"], Vector2(who.position.x, who.top_y() - 4), SIDE_BOTTOM, who.voice)
		return
	push_warning("No speech bubble spot for speaker '%s'" % speaker)
	bubble.say(line["text"], Vector2(0, -60), SIDE_BOTTOM)


func _dialogue_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ACCEPT"):
		return
	if bubble.is_typing():
		# First press finishes the line, second press moves on
		bubble.finish_typing()
		return
	dialogue_index += 1
	if dialogue_index < dialogue.size():
		_show_dialogue_line()
	else:
		enter_waiting()


func enter_waiting() -> void:
	state = MenuState.WAITING
	bubble.hide()
	_show_text(status if status != "" else "* %s is about to attack!" % battle.enemy.display_name)
	battle.player_done()


# --- VISUALS ---

func update_tab_visuals() -> void:
	if tab_tween:
		tab_tween.kill()
	tab_tween = create_tween().set_parallel()
	for i in tabs.size():
		var y := 32.0 # tucked behind the box
		if state != MenuState.HIDDEN:
			y = -40.0 if i == selected_tab else -32.0
		tabs[i].modulate = Color.YELLOW if i == selected_tab and state != MenuState.HIDDEN else Color.WHITE
		tab_tween.tween_property(tabs[i], "position:y", y, 0.1)


func _slide(target: Vector2) -> void:
	if slide_tween:
		slide_tween.kill()
	slide_tween = create_tween()
	slide_tween.tween_property(self, "position", target, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _show_text(text: String) -> void:
	menucontent.hide()
	flavortext.show()
	writer.start(flavortext, text, TYPE_SPEED)


## rows: [{"text": String, "enabled": bool, "hp": optional percent}, ...]
func _show_rows(rows: Array, highlighted: int) -> void:
	flavortext.hide()
	menucontent.show()
	for child in menucontent.get_children():
		menucontent.remove_child(child)
		child.queue_free()
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.set_meta("enabled", row["enabled"])
		line.add_child(_make_label(row["text"]))
		if row.has("hp"):
			line.add_child(_make_hp_bar(row["hp"]))
			line.add_child(_make_label("%d%%" % row["hp"]))
		menucontent.add_child(line)
	_highlight_row(highlighted)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", menu_font)
	return label


## Deltarune-style enemy HP bar: green over red
func _make_hp_bar(percent: int) -> Control:
	var back := ColorRect.new()
	back.color = Color(0.5, 0, 0)
	back.custom_minimum_size = Vector2(90, 14)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := ColorRect.new()
	fill.color = Color(0, 0.85, 0.2)
	fill.size = Vector2(90 * percent / 100.0, 14)
	back.add_child(fill)
	return back


func _highlight_row(index: int) -> void:
	var rows := menucontent.get_children()
	for i in rows.size():
		var color := Color.YELLOW if i == index else Color.WHITE
		if not rows[i].get_meta("enabled"):
			color = color.darkened(0.6)
		for child in rows[i].get_children():
			if child is Label:
				child.add_theme_color_override("font_color", color)


func _sfx(player_name: String) -> void:
	battle.get_node(player_name).play()
