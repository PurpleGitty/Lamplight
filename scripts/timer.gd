extends UIBox
## Shows how much song is left. When it hits 0:00 you lose.

@onready var battle: Battle = owner
@onready var clock_label: Label = $"time left"


func _process(_delta: float) -> void:
	var time_left := ceili(battle.conductor.time_left())
	clock_label.text = "%d:%02d" % [time_left / 60, time_left % 60]
