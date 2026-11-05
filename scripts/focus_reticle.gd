class_name FocusReticle
extends Node2D
## Faint brackets over each standing party member on the player's turn, showing
## how much of the next enemy turn's damage is aimed at them: one ring per quarter,
## white, yellow, red, then a cyan square at 100%. With only one party member
## they'd always take everything, so nothing's shown.

const RINGS := [Color(1, 1, 1, 0.45), Color(1.0, 0.85, 0.2, 0.45), Color(1.0, 0.2, 0.2, 0.45)]
const CENTRE := Color(0.2, 1.0, 1.0, 0.45)
const WIDTH := 1.0
const SCREEN := Rect2(-320, -240, 640, 480)
const SIZE_OF_SPRITE := 0.85 # of the part of the sprite on screen
const RING_STEP := 0.13 # how far in each ring is, as a share of the reticle's size
const ARM := 0.42 # bracket length, as a share of its ring's size
const CENTRE_SIZE := 0.22
const QUARTERS := 4.0

var battle: Battle


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if battle.phase != Battle.Phase.PLAYER or battle.party.size() < 2:
		return
	for member in battle.party:
		if not member.is_down:
			_draw_reticle(member, battle.focus_share(member))


func _draw_reticle(member: PartyMember, share: float) -> void:
	var box := _box_for(member)
	var count := rings_for(share)
	for i in mini(count, RINGS.size()):
		_draw_brackets(box.grow(-box.size.x * RING_STEP * i), RINGS[i])
	if count > RINGS.size():
		var centre_size := box.size * CENTRE_SIZE
		draw_rect(Rect2(box.get_center() - centre_size / 2.0, centre_size), CENTRE, false, WIDTH)


## How many rings a share of the damage shows (0 only for no damage at all).
static func rings_for(share: float) -> int:
	if share <= 0.0:
		return 0
	return clampi(floori(share * QUARTERS + 0.001), 1, int(QUARTERS))


## A square over the part of their sprite that's on screen.
func _box_for(member: PartyMember) -> Rect2:
	var size: Vector2 = member.texture.get_size() / Vector2(member.hframes, 1) * member.scale
	var home := Vector2(member.data["x"], member.data["y"])
	var shown := Rect2(home - size / 2.0, size).intersection(SCREEN)
	var side := minf(shown.size.x, shown.size.y) * SIZE_OF_SPRITE
	return Rect2(shown.get_center() - Vector2(side, side) / 2.0, Vector2(side, side))


## The top left and bottom right corners.
func _draw_brackets(box: Rect2, color: Color) -> void:
	var arm := box.size.x * ARM
	var corner := box.position
	draw_polyline(PackedVector2Array([corner + Vector2(0, arm), corner, corner + Vector2(arm, 0)]), color, WIDTH)
	corner = box.end
	draw_polyline(PackedVector2Array([corner - Vector2(0, arm), corner, corner - Vector2(arm, 0)]), color, WIDTH)
