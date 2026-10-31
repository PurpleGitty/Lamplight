class_name PartyMember
extends Sprite2D
## Purple or Violet. When knocked down they slowly revive, but only while
## their partner is still standing. If both are down, the fight is lost.

signal downed
signal revived

@export var display_name := "Purple"
@export var max_hp := 100
@export var revive_seconds := 60.0
@export var hp_bar: TextureProgressBar
@export var name_label: Label
## How high they hop on each beat, in sprite pixels. Cycles: beat 1 uses the
## first entry, beat 2 the second, then repeats.
@export var bob_pattern: Array[float] = [1.0, 2.0]
## Played once per letter when they talk in a speech bubble (empty = default blip).
@export var voice: AudioStream

var hp := 100
var is_down := false
var defending := false # halves damage until the next player turn
var revive_progress := 0.0
var partner: PartyMember

var _shake_strength := 0.0
var _shake_time := 0.0
var _shake_length := 0.0
var _lift := 0.0 # extra upward offset while reviving, before snapping into place

@onready var battle: Battle = owner


func _ready() -> void:
	hp = max_hp
	_show_hp()


func _process(delta: float) -> void:
	_update_offset(delta)

	if not is_down or partner.is_down or battle.phase == Battle.Phase.OVER:
		return
	revive_progress += delta
	hp_bar.value = revive_progress
	if revive_progress >= revive_seconds:
		_revive()


func take_damage(amount: int) -> void:
	if is_down or amount <= 0:
		return
	if defending:
		amount = ceili(amount / 2.0)
	hp = maxi(hp - amount, 0)
	_show_hp()

	if hp == 0:
		_go_down()
		return
	shake(2.0, 0.3)
	modulate = Color.RED
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.3)


func shake(strength: float, seconds: float) -> void:
	_shake_strength = strength
	_shake_time = seconds
	_shake_length = seconds


func _update_offset(delta: float) -> void:
	var bob := 0.0
	var song := battle.conductor
	if not is_down and song.playing and not bob_pattern.is_empty():
		var height: float = bob_pattern[posmod(floori(song.song_beat), bob_pattern.size())]
		bob = -height * sin(PI * fposmod(song.song_beat, 1.0))

	var jitter := Vector2.ZERO
	if _shake_time > 0.0:
		_shake_time -= delta
		var s := _shake_strength * maxf(_shake_time / _shake_length, 0.0)
		jitter = Vector2(randf_range(-s, s), randf_range(-s, s) * 0.3) # mostly side to side

	# Whole sprite pixels only, so it stays crisp
	offset = (Vector2(0, bob - _lift) + jitter).round()


func _go_down() -> void:
	is_down = true
	revive_progress = 0.0
	battle.get_node("Spanked").play()

	# The HP bar turns into a green revive bar while down
	hp_bar.self_modulate = Color.GREEN
	hp_bar.max_value = revive_seconds
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
	hp_bar.self_modulate = Color.WHITE
	hp_bar.max_value = max_hp
	hp_bar.value = hp
