extends Sprite2D
## Testicina, the first fight. HP, voice and ACT options live here. Everything
## timed to the song lives in her chart, made with the attack editor
## (editor/attack_editor.tscn): when she attacks, what the attacks are, and
## the flavor text, dialogue and status messages (Text nodes).

signal died

@export var display_name := "Testicina"
@export var max_hp := 10000
@export_file("*.json") var chart_path := "res://charts/testicina.json"
## Played once per letter when she talks in a speech bubble (empty = default blip).
@export var voice: AudioStream

var hp := 10000
var focus := 2 # who the attacks aim at: 0 = all Violet, 4 = all Purple (re-rolled every enemy turn)

# Used for any player turn the chart has no Text nodes for (loops if there are several).
var turn_data := [
	{"flavor": "* Testicina blocks the way.", "dialogue": []},
]

# MANEUVER options
var acts := [
	{"name": "Check", "text": "* TESTICINA - Placeholder check text.\n* Write this in testicina.gd."},
	{"name": "Taunt", "text": "* You make a face at Testicina.\n* It doesn't seem to care."},
]


func _ready() -> void:
	hp = max_hp


func hp_percent() -> int:
	return ceili(100.0 * hp / max_hp)


func roll_focus() -> void:
	focus = randi() % 5


func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	owner.get_node("Damage").play()
	_damage_popup(amount)

	modulate = Color.RED
	var t := create_tween()
	t.tween_property(self, "modulate", Color.WHITE, 0.3)
	t.parallel().tween_property(self, "offset:x", 2.0, 0.05)
	t.tween_property(self, "offset:x", -2.0, 0.05)
	t.tween_property(self, "offset:x", 0.0, 0.05)

	if hp == 0:
		create_tween().tween_property(self, "modulate:a", 0.0, 1.0)
		died.emit()


func _damage_popup(amount: int) -> void:
	var popup := Label.new()
	popup.text = str(amount)
	popup.add_theme_font_override("font", preload("res://fonts/Mojang-Regular.ttf"))
	popup.add_theme_font_size_override("font_size", 20)
	popup.add_theme_constant_override("outline_size", 6)
	popup.add_theme_color_override("font_outline_color", Color.BLACK)
	popup.position = position + Vector2(-20, -70)
	get_parent().add_child(popup)
	var t := popup.create_tween()
	t.tween_property(popup, "position:y", popup.position.y - 30, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(popup, "modulate:a", 0.0, 0.8).set_delay(0.4)
	t.tween_callback(popup.queue_free)
