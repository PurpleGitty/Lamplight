class_name PartyMember
extends Character
## A player character. When knocked down they slowly revive (if the rules allow
## it), but only while someone else is still standing. If everyone's down, the
## fight is lost.

signal downed
signal revived

const DISSOLVE_SHADER = preload("res://dissolve.gdshader")
const DISSOLVE_NOISE = preload("res://dissolve_noise.tres")

var hp_bar: TextureProgressBar
var name_label: Label
var is_down := false
var defending := false # takes less damage until the next player turn
var revive_progress := 0.0


func setup(entry: Dictionary, owner_battle: Battle) -> void:
	super(entry, owner_battle)
	var dissolve := ShaderMaterial.new()
	dissolve.shader = DISSOLVE_SHADER
	dissolve.set_shader_parameter("noise_texture", DISSOLVE_NOISE)
	material = dissolve


## Hooks up this character's row in the menu box.
func set_hud(label: Label, bar: TextureProgressBar) -> void:
	name_label = label
	hp_bar = bar
	if is_down:
		hp_bar.self_modulate = Color.GREEN
		hp_bar.max_value = battle.rules["revive_seconds"]
		hp_bar.value = revive_progress
	else:
		_show_hp()


func _process(delta: float) -> void:
	animate(delta, not is_down)

	if not is_down or not battle.rules["auto_revive"] or battle.phase == Battle.Phase.OVER:
		return
	if battle.living_members().is_empty():
		return
	revive_progress += delta
	hp_bar.value = revive_progress
	if revive_progress >= battle.rules["revive_seconds"]:
		_revive()


func take_damage(amount: int) -> void:
	if is_down or amount <= 0:
		return
	if defending:
		amount = ceili(amount * battle.rules["defend_factor"])
	set_hp(hp - amount)
	if is_down:
		return
	shake(2.0, 0.3)
	modulate = Color.RED
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.3)


## Sets HP directly, downing them if it reaches 0.
func set_hp(value: int) -> void:
	hp = clampi(value, 0, max_hp)
	if is_down:
		return
	_show_hp()
	if hp == 0:
		_go_down()


func _go_down() -> void:
	is_down = true
	revive_progress = 0.0
	battle.get_node("Spanked").play()

	# The HP bar turns into a green revive bar while down
	hp_bar.self_modulate = Color.GREEN
	hp_bar.max_value = battle.rules["revive_seconds"]
	hp_bar.value = 0.0

	# Shake hard while turning white, then crumble into dust
	shake(4.0, 0.3)
	var t := create_tween()
	t.tween_property(material, "shader_parameter/flash", 1.0, 0.2)
	t.tween_interval(0.1)
	t.tween_callback(_crumble)
	downed.emit()


func _crumble() -> void:
	var dust := DustEffect.from_sprite(self)
	dust.z_index = z_index + 1
	get_parent().add_child(dust)
	material.set_shader_parameter("dissolve_value", 1.1) # the dust replaces the sprite


func _revive() -> void:
	is_down = false
	hp = max_hp
	_show_hp()

	# Fade back in as a white silhouette, slightly raised, then snap into place
	material.set_shader_parameter("dissolve_value", 0.0)
	material.set_shader_parameter("flash", 1.0)
	self_modulate.a = 0.0
	_lift = 3.0
	var t := create_tween()
	t.tween_property(self, "self_modulate:a", 1.0, 0.6)
	t.tween_callback(func():
		_lift = 0.0
		shake(1.0, 0.15))
	t.tween_property(material, "shader_parameter/flash", 0.0, 0.15)
	revived.emit()


func _show_hp() -> void:
	if hp_bar == null:
		return
	hp_bar.self_modulate = Color.WHITE
	hp_bar.max_value = max_hp
	hp_bar.value = hp
