extends UIBox
## Shows the party's shared TP, which specials cost. TP comes from grazing
## bullets and PERFECT hits.

@onready var battle: Battle = owner
@onready var bar: TextureProgressBar = $"current energy"
@onready var label: Label = $"energy left"


func _ready() -> void:
	bar.max_value = Battle.MAX_TP


func _process(_delta: float) -> void:
	bar.value = battle.tp
	label.text = str(floori(battle.tp))
