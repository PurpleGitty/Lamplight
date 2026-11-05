extends UIBox
## Shows the party's shared TP, which specials cost. TP comes from grazing
## bullets and PERFECT hits.

@onready var battle: Battle = owner
@onready var bar: TextureProgressBar = $"current energy"
@onready var label: Label = $"energy left"


var _flash := 0.0


func _ready() -> void:
	battle.tp_gained.connect.call_deferred(_on_tp_gained)


## Bigger gains flash brighter; the trickle from staying near a bullet glows gently.
func _on_tp_gained(amount: float) -> void:
	_flash = maxf(_flash, minf(amount / 2.0, 1.0))


func _process(delta: float) -> void:
	visible = battle.rules["tp_enabled"]
	bar.max_value = battle.rules["max_tp"]
	bar.value = battle.tp
	label.text = str(floori(battle.tp))
	_flash = maxf(_flash - delta * 3.0, 0.0)
	bar.modulate = Color.WHITE.lerp(Color(2.2, 2.2, 2.2), _flash)
	label.modulate = Color.WHITE.lerp(Color.YELLOW, _flash)
