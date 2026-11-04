class_name Enemy
extends Character
## An enemy in a fight. Who it is comes from the chart's Characters tab; when it
## attacks and with what comes from the chart's timeline.

signal died

var focus := 2


func _process(delta: float) -> void:
	animate(delta)


func is_dead() -> bool:
	return hp <= 0


func hp_percent() -> int:
	return ceili(100.0 * hp / max_hp)


func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	battle.get_node("Damage").play()
	_damage_popup(amount)

	modulate = Color.RED
	shake(1.0, 0.2)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.3)

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
