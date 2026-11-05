class_name GameOver
extends CanvasLayer
## Undertale-style game over. Everything goes black except the soul, which
## cracks in half, then shatters into pieces. Then GAME OVER is spelled out
## letter by letter, and the stats fade in.

const FONT = preload("res://fonts/PixelOperatorMono8-Bold.ttf")
const SHARD_COUNT := 6
const GRAVITY := 500.0
const TITLE_SIZE := 48 # the font is drawn at 8px, so keep sizes multiples of 8
const LETTER_DELAY := 0.12
const STATS_TOP := -20.0
const STATS_ROOM := 170.0 # stats can use this much height before the controls
const STATS_GAP := 32.0 # closer together if there are lots of enemies

var _shards: Array[Sprite2D] = []
var _shard_velocity: Array[Vector2] = []
var _letters: Array[Label] = []
var _letter_home: Array[Vector2] = []
var _shake_timer := 0.0


func play(soul_position: Vector2, stats: Array[String], break_sound: AudioStreamPlayer, shatter_sound: AudioStreamPlayer, soul_texture: Texture2D, soul_size: Vector2) -> void:
	layer = 10
	follow_viewport_enabled = true # same coordinates as the battle

	var black := ColorRect.new()
	black.color = Color.BLACK
	black.position = Vector2(-2000, -2000)
	black.size = Vector2(4000, 4000)
	add_child(black)

	# The soul, as two halves that start out touching
	var halves: Array[Sprite2D] = []
	for side in 2:
		var half := Sprite2D.new()
		half.texture = soul_texture
		half.region_enabled = true
		half.region_rect = Rect2(Vector2(side * soul_size.x / 2.0, 0), Vector2(soul_size.x / 2.0, soul_size.y))
		half.position = soul_position + Vector2((side - 0.5) * soul_size.x / 2.0, 1)
		add_child(half)
		halves.append(half)

	await _wait(1.0)
	break_sound.play()
	halves[0].position.x -= 2
	halves[1].position.x += 2
	halves[0].rotation_degrees = -8
	halves[1].rotation_degrees = 8

	await _wait(1.3)
	shatter_sound.play()
	for half in halves:
		half.queue_free()
	for i in SHARD_COUNT:
		var shard := Sprite2D.new()
		shard.texture = soul_texture
		shard.region_enabled = true
		shard.region_rect = Rect2(Vector2(randf_range(0.2, 0.6) * soul_size.x, randf_range(0.2, 0.6) * soul_size.y).floor(), (soul_size / 4.0).ceil())
		shard.position = soul_position
		add_child(shard)
		_shards.append(shard)
		_shard_velocity.append(Vector2(randf_range(-140, 140), randf_range(-260, -80)))

	await _wait(1.6)

	# GAME OVER is spelled out one crooked, shaking letter at a time
	var title := "GAME OVER"
	var letter_width := TITLE_SIZE * 1.0 # the font is monospaced: every letter is as wide as it is tall
	var left := -letter_width * (title.length() - 1) / 2.0
	for i in title.length():
		if title[i] == " ":
			continue
		var letter := _add_label(title[i], TITLE_SIZE, Vector2(left + i * letter_width, -140))
		letter.pivot_offset = letter.size / 2
		letter.rotation_degrees = randf_range(-9, 9)
		_letters.append(letter)
		_letter_home.append(letter.position)
		await _wait(LETTER_DELAY)

	await _wait(0.5)
	var lines: Array[Label] = []
	var gap := minf(STATS_GAP, STATS_ROOM / stats.size())
	for i in stats.size():
		lines.append(_add_label(stats[i].to_upper(), 16, Vector2(0, STATS_TOP + i * gap)))
	lines.append(_add_label(GameSettings.hint([["ACCEPT", "TRY AGAIN"], ["BACK", "MAIN MENU"]]), 16, Vector2(0, 170)))
	for i in lines.size():
		var label := lines[i]
		label.modulate.a = 0.0
		create_tween().tween_property(label, "modulate:a", 1.0, 0.6).set_delay(i * 0.3)
	await _wait(lines.size() * 0.3 + 0.3)


func _process(delta: float) -> void:
	for i in _shards.size():
		_shard_velocity[i].y += GRAVITY * delta
		_shards[i].position += _shard_velocity[i] * delta
		_shards[i].rotation += delta * 8.0

	# Light jitter on the title letters, a few times a second
	_shake_timer -= delta
	if _shake_timer <= 0.0:
		_shake_timer = 0.06
		for i in _letters.size():
			_letters[i].position = _letter_home[i] + Vector2(randi_range(-1, 1), randi_range(-1, 1))


func _add_label(text: String, font_size: int, center: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.size = Vector2(620 if text.length() > 1 else font_size + 8, font_size + 12)
	label.position = center - label.size / 2
	add_child(label)
	return label


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
