class_name UIBox
extends ColorRect
## Base for every bordered box (menu, tabs, timer, TP, bullet board).
## Draws the white border, and on every beat a copy of the border starts on top
## of it, then shrinks inward while fading out (the Deltarune pulse).

const ECHO_INSET := 8.0 # how far inward the echo travels, in pixels
const ECHO_BEATS := 0.6 # how much of a beat the echo lasts
const BORDER_WIDTH := 2.0

## Moves the border inward. The board uses 1 so clipping doesn't cut it in half.
var border_inset := 0.0
## Set false for boxes that shouldn't pulse on the beat (the bullet board).
var pulse := true


func _notification(what: int) -> void:
	# _notification runs for every script in the inheritance chain, so this keeps
	# working even when a box script has its own _ready/_process.
	if what == NOTIFICATION_ENTER_TREE:
		get_tree().process_frame.connect(queue_redraw)
	elif what == NOTIFICATION_EXIT_TREE:
		get_tree().process_frame.disconnect(queue_redraw)
	elif what == NOTIFICATION_DRAW:
		_draw_border()


func _draw_border() -> void:
	var inner := Rect2(Vector2.ONE * border_inset, size - Vector2.ONE * border_inset * 2)
	draw_rect(inner, Color.WHITE, false, BORDER_WIDTH)

	var song := Conductor.current
	if not pulse or song == null or not song.playing:
		return
	var t := fposmod(song.song_beat, 1.0) / ECHO_BEATS
	if t >= 1.0:
		return
	# Smaller boxes (the tabs) get a smaller pulse so it doesn't swallow them
	var travel := minf(ECHO_INSET, minf(size.x, size.y) * 0.15)
	var inset := travel * (1.0 - pow(1.0 - t, 2.0)) # ease out
	var echo := inner.grow(-inset)
	draw_rect(echo, Color(1, 1, 1, 0.8 * (1.0 - t)), false, BORDER_WIDTH)
