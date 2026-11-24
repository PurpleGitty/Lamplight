class_name RigSprite
extends Node2D
## Draws a character built from pieces (see Rig), moving on the beat: "idle" on a loop,
## or another of its animations played once. Its origin is the rig's origin.

## The rig, straight from the character's chart entry.
var rig: Dictionary
## The tempo when no fight's playing (a preview, say).
var bpm := 120.0
var _clock := 0.0
var _once: Dictionary = {} # the animation playing once, if any
var _once_start := 0.0 # in beats
var _once_rate := 1.0 # beats of the animation per beat of the song


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # stays pixel sharp when turned


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func beat() -> float:
	var song := Conductor.current
	if song != null and song.playing:
		return song.song_beat
	return _clock * bpm / 60.0


func has_animation(anim_name: String) -> bool:
	return not Rig.find_animation(rig, anim_name).is_empty()


## Plays one of its animations once, then goes back to idle. Given seconds, it's
## stretched to fit them; otherwise it takes its own length in beats.
func play(anim_name: String, seconds := -1.0) -> void:
	var anim := Rig.find_animation(rig, anim_name)
	if anim.is_empty():
		return
	_once = anim
	_once_start = beat()
	_once_rate = 1.0
	if seconds > 0.0:
		var beats := seconds * _bpm() / 60.0
		_once_rate = float(anim["beats"]) / maxf(beats, 0.0001)


func _bpm() -> float:
	var song := Conductor.current
	return song.bpm if song != null and song.playing else bpm


## Where everyone is right now.
func current_pose() -> Dictionary:
	var now := beat()
	if not _once.is_empty():
		var into := (now - _once_start) * _once_rate
		if into < float(_once["beats"]):
			return Rig.pose(rig, _once, maxf(into, 0.0))
		_once = {}
	var idle := Rig.find_animation(rig, Rig.IDLE)
	return Rig.pose(rig, idle, Rig.local_time(idle, maxf(now, 0.0)) if not idle.is_empty() else 0.0)


## The box round her (in this node's space), as she stands now.
func bounds() -> Rect2:
	return Rig.bounds(rig, current_pose())


func _draw() -> void:
	if Rig.has_pieces(rig):
		Rig.draw(self, rig, current_pose(), Transform2D())
