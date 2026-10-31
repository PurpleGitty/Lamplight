extends Sprite2D
## The stopwatch next to the timer. The long hand goes once around over the
## whole song, ticking 60 times, and is back at 12 when time runs out. The
## short hand ticks a notch every beat (once around every 8 beats). The hands
## are drawn in the sprite's own pixels so they match the art.

const FACE_CENTER := Vector2(-0.5, 2.5) # middle of the clock face, from the sprite's centre
const LONG_HAND := 4.0 # length in sprite pixels
const SHORT_HAND := 2.5
const SONG_TICKS := 60
const BEATS_PER_LAP := 8

@onready var battle: Battle = owner


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var song: Conductor = battle.conductor
	var done := clampf(song.song_position / maxf(song.song_length, 0.001), 0.0, 1.0)
	_hand(floorf(done * SONG_TICKS) / SONG_TICKS * TAU, LONG_HAND, Color.WHITE)
	var beat := floorf(maxf(song.song_beat, 0.0))
	_hand(fmod(beat, BEATS_PER_LAP) / BEATS_PER_LAP * TAU, SHORT_HAND, Color(1.0, 0.35, 0.35))


## Draws a hand pixel by pixel, from the centre outwards (0 = pointing at 12).
func _hand(angle: float, length: float, color: Color) -> void:
	var direction := Vector2(sin(angle), -cos(angle))
	var steps := int(length * 2)
	for i in steps + 1:
		var pixel := (FACE_CENTER + direction * (i / 2.0)).floor()
		draw_rect(Rect2(pixel, Vector2.ONE), color)
