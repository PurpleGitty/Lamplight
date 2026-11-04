extends UIBox
## Shows the party's shared TP, which specials cost. TP comes from grazing
## bullets and PERFECT hits.

@onready var battle: Battle = owner
@onready var bar: TextureProgressBar = $"current energy"
@onready var label: Label = $"energy left"


func _process(_delta: float) -> void:
	visible = battle.rules["tp_enabled"]
	bar.max_value = battle.rules["max_tp"]
	bar.value = battle.tp
	label.text = str(floori(battle.tp))
