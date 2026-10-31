extends Area2D
## A basic bullet. Its position is worked out from the song's beat rather than
## moved a little each frame, so it stays locked to the music even if the
## frame rate stutters.

var damage := 20
var source_name := "a pellet" # shown as the cause of death on the game over screen
var origin := Vector2.ZERO
var velocity := Vector2.ZERO # pixels per beat
var spawn_beat := 0.0
var lifetime_beats := 16.0
var conductor: Conductor


func _ready() -> void:
	_process(0.0)


func _process(_delta: float) -> void:
	var age := conductor.song_beat - spawn_beat
	position = origin + velocity * age
	if age > lifetime_beats:
		queue_free()
