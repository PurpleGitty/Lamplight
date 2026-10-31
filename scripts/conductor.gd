class_name Conductor
extends Node
## The song clock. Everything that has to stay on the music (turn changes,
## bullets, the attack timing bar) reads `song_beat` from here instead of using
## its own timers, so nothing drifts out of sync over a long song.

signal beat(beat_number: int)
signal song_finished

## The conductor of the fight that's running, so UI can find the beat without a node path.
static var current: Conductor

@export var bpm := 160.0
## Seconds from the start of the audio file to the first beat.
@export var offset := 0.0
## Only used when no song is loaded into `player`; otherwise the file's length wins.
@export var song_length := 286.0
@export var player: AudioStreamPlayer

var song_position := 0.0 # seconds into the song
var song_beat := 0.0     # beats into the song (fractional)
var playing := false
var _last_beat := -1


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func seconds_per_beat() -> float:
	return 60.0 / bpm


func time_left() -> float:
	return maxf(song_length - song_position, 0.0)


func start() -> void:
	song_position = 0.0
	song_beat = -offset / seconds_per_beat()
	_last_beat = -1
	playing = true
	if player and player.stream:
		song_length = player.stream.get_length()
		player.play()


func stop() -> void:
	playing = false
	if player:
		player.stop()


func _process(delta: float) -> void:
	if not playing:
		return

	if player and player.playing:
		# The audio hardware is the real clock; correct for mixing delay so the
		# beat lines up with what the player hears.
		var heard := player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		song_position = maxf(song_position, heard)
	else:
		song_position += delta

	song_beat = (song_position - offset) / seconds_per_beat()
	while _last_beat < floori(song_beat):
		_last_beat += 1
		beat.emit(_last_beat)

	if song_position >= song_length:
		playing = false
		song_finished.emit()
