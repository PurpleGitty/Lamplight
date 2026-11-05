class_name Character
extends Sprite2D
## Anyone in a fight, built from a chart's character entry: sprite, stats, voice,
## idle animation on the beat, one-off animations, bobbing and shaking.

var battle: Battle
var data: Dictionary
var display_name := ""
var max_hp := 100
var hp := 100
var voice: AudioStream
var bob_pattern: Array[float] = []

var _shake_strength := 0.0
var _shake_time := 0.0
var _shake_length := 0.0
var _lift := 0.0 # extra upward offset, in sprite pixels
var _anim_first := 0
var _anim_count := 0
var _anim_length := 0.0
var _anim_time := 0.0


func setup(entry: Dictionary, owner_battle: Battle) -> void:
	battle = owner_battle
	data = entry
	display_name = entry["name"]
	max_hp = int(entry["max_hp"])
	hp = max_hp
	voice = ChartDefs.load_audio(entry["voice"])
	bob_pattern = ChartDefs.parse_bob(entry["bob"])
	texture = ChartDefs.load_texture(entry["sprite"])
	hframes = maxi(int(entry["hframes"]), 1)
	scale = Vector2.ONE * float(entry["sprite_scale"])
	position = Vector2(entry["x"], entry["y"])
	frame = clampi(int(entry["idle_first"]), 0, hframes - 1)


## The sprite's top edge on screen, for placing speech bubbles.
func top_y() -> float:
	return position.y - texture.get_height() * scale.y / 2


func half_width() -> float:
	return texture.get_width() / float(hframes) * scale.x / 2


## Plays frames of the sprite sheet once, then goes back to idle.
func play_anim(first: int, count: int, seconds: float) -> void:
	_anim_first = first
	_anim_count = count
	_anim_length = maxf(seconds, 0.001)
	_anim_time = 0.0


## A move's icon floats up from them when they use it.
func show_icon(path: String) -> void:
	if path == "":
		return
	var icon := Sprite2D.new()
	icon.texture = ChartDefs.load_texture(path)
	icon.position = Vector2(position.x, top_y() - 8)
	icon.z_index = 5
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_parent().add_child(icon)
	var t := icon.create_tween().set_parallel()
	t.tween_property(icon, "position:y", icon.position.y - 24, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(icon, "modulate:a", 0.0, 0.5).set_delay(0.3)
	t.chain().tween_callback(icon.queue_free)


func shake(strength: float, seconds: float) -> void:
	_shake_strength = strength * GameSettings.shake_scale()
	_shake_time = seconds
	_shake_length = seconds


## Call every frame: picks the animation frame and the bob/shake offset.
func animate(delta: float, bobbing := true) -> void:
	var song := battle.conductor
	var wanted := ChartDefs.anim_frame(int(data["idle_first"]), int(data["idle_count"]), data["idle_beats"], maxf(song.song_beat, 0.0))
	if _anim_count > 0:
		_anim_time += delta
		if _anim_time >= _anim_length:
			_anim_count = 0
		else:
			wanted = _anim_first + floori(_anim_time / _anim_length * _anim_count)
	frame = clampi(wanted, 0, hframes - 1)

	var bob := 0.0
	if bobbing and song.playing and not bob_pattern.is_empty():
		var height: float = bob_pattern[posmod(floori(song.song_beat), bob_pattern.size())]
		bob = -height * sin(PI * fposmod(song.song_beat, 1.0))

	var jitter := Vector2.ZERO
	if _shake_time > 0.0:
		_shake_time -= delta
		var s := _shake_strength * maxf(_shake_time / _shake_length, 0.0)
		jitter = Vector2(randf_range(-s, s), randf_range(-s, s) * 0.3) # mostly side to side

	# Whole sprite pixels only, so it stays crisp
	offset = (Vector2(0, bob - _lift) + jitter).round()
