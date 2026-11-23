class_name CandySprite
extends Node2D
## Candy, built as a little rig from her layers: legs, then her body and skirt (turning at
## her hips), then her arm, hair and guitar (turning at her shoulders, on top of that).
## She sways to the beat: the two halves turn opposite ways so her body bows like a spine,
## eases through straight, and bows the other way, landing each bow on a beat. At each
## stop she crunches a little further into it (the pieces turn and dip a touch more), then
## bounces back up to go the other way. Her guitar is part of her top half, so it never
## leaves her hand; her legs stay planted. Pieces only turn and move, never stretch.
## The node's origin is between her feet, on the ground.

const GUITAR = preload("res://sprites/candy/guitar.png")
const LEGS = preload("res://sprites/candy/legs.png")
const BODY = preload("res://sprites/candy/skirt.png") # her body and skirt
const ARM = preload("res://sprites/candy/arm.png")
const HAIR = preload("res://sprites/candy/hair.png")
const FRAMES := 3 # leaning left, upright, leaning right
const BODY_OFFSET := Vector2(30, 0) # the body's frames sit this far into the guitar's canvas
## Where everything is, in the guitar's canvas.
const FEET := Vector2(80, 116) # between her feet, on the ground
const HIPS := Vector2(80, 64) # her body and skirt turn here
const SHOULDERS := Vector2(80, 42) # her head, arm and guitar turn here
const LEAN := 5.0 # degrees her body turns at the end of a sway
const COUNTER := 1.7 # her top half turns back this many times as far, so she bows
const CRUNCH_TURN := 0.6 # turns this much further into the bow at each stop
const CRUNCH_DIP := 2.0 # pixels her top half dips at each stop
const CRUNCH_TIME := 0.12 # beats either side of the stop
## The beat when no fight's playing (a preview, say).
@export var bpm := 120.0

var _body := Node2D.new() # turns at her hips
var _top := Node2D.new() # turns at her shoulders, riding on her body
var _swinging: Array[Sprite2D] = [] # hair and skirt, whose frames follow the sway
var _clock := 0.0


func _ready() -> void:
	var legs := _add(self, LEGS, BODY_OFFSET - FEET)
	legs.hframes = FRAMES
	legs.frame = 1
	_body.position = HIPS - FEET
	add_child(_body)
	_swinging.append(_add(_body, BODY, BODY_OFFSET - HIPS))
	_top.position = SHOULDERS - HIPS
	_body.add_child(_top)
	var arm := _add(_top, ARM, BODY_OFFSET - SHOULDERS)
	arm.frame = 1
	_swinging.append(_add(_top, HAIR, BODY_OFFSET - SHOULDERS))
	_add(_top, GUITAR, -SHOULDERS)
	_sway()


func _add(parent: Node, texture: Texture2D, at: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = at
	if texture != GUITAR:
		sprite.hframes = FRAMES
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # stays pixel sharp when turned
	parent.add_child(sprite)
	return sprite


func _process(delta: float) -> void:
	_clock += delta
	_sway()


func _sway() -> void:
	var song := Conductor.current
	var beat := song.song_beat if song != null and song.playing else _clock * bpm / 60.0
	# Counted in beats, so a faster song makes all of it quicker.
	# Bowed one way on each beat, the other way on the next, easing through straight
	var lean := -cos(PI * beat)
	# A quick crunch further into the bow right at each stop, then back up
	var from_stop := absf(beat - roundf(beat))
	var crunch := exp(-pow(from_stop / CRUNCH_TIME, 2.0))
	var turn := lean * LEAN * (1.0 + CRUNCH_TURN * crunch)
	_body.rotation_degrees = turn
	_top.rotation_degrees = -turn * COUNTER
	_top.position = SHOULDERS - HIPS + Vector2(0, roundf(CRUNCH_DIP * crunch))

	var pose := 1
	if lean < -0.35:
		pose = 0
	elif lean > 0.35:
		pose = 2
	for sprite in _swinging:
		sprite.frame = pose
