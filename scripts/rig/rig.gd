class_name Rig
extends RefCounted
## A character built from pieces, and the keyframes that move them. Shared by the game
## (RigSprite) and the Scrap O' Matic's preview and Keyframer, so they always agree.
##
## A rig is plain chart data, kept in a character's "rig":
##   pieces: drawn in list order. Each has an id, a name, a sprite sheet (blank = an
##     invisible joint that only carries other pieces), frames across and the frame it
##     shows, its parent's id (-1 = none), and where it sits: x, y is where its pivot is,
##     measured from its parent's pivot (or the character's spot for a piece with no
##     parent), rotation in degrees, and pivot_x, pivot_y, the pixel in its frame that it
##     turns around. Pieces only ever turn and move, so the art stays pixel for pixel.
##   animations: each has a name, a length in beats, whether it loops, and tracks: for a
##     piece id, a list of keys per property (x, y, rotation, frame). A key has a beat,
##     a value and an ease, which says how it gets from this key to the next.
## "idle" plays on a loop all fight; others play once when something asks for them.

const PROPERTIES := ["rotation", "x", "y", "frame"]
const EASES := ["smooth", "linear", "ease in", "ease out", "ease in-out", "hold"]
const IDLE := "idle"

static var _textures := {}


static func new_rig() -> Dictionary:
	return {"pieces": [], "animations": [new_animation(IDLE)], "next_id": 1}


static func new_animation(anim_name: String) -> Dictionary:
	return {"name": anim_name, "beats": 2.0, "loop": anim_name == IDLE, "tracks": {}}


static func new_piece(rig: Dictionary, piece_name: String, sprite := "") -> Dictionary:
	var piece := {
		"id": int(rig.get("next_id", 1)), "name": piece_name, "sprite": sprite, "hframes": 1, "frame": 0,
		"parent": -1, "x": 0.0, "y": 0.0, "rotation": 0.0, "pivot_x": 0.0, "pivot_y": 0.0,
	}
	rig["next_id"] = piece["id"] + 1
	return piece


static func has_pieces(rig: Variant) -> bool:
	return rig is Dictionary and not rig.get("pieces", []).is_empty()


## Fills in anything missing (older files, hand edits) and makes numbers the right kind.
static func fill(rig: Dictionary) -> Dictionary:
	var base := new_rig()
	for key in base:
		if not rig.has(key):
			rig[key] = base[key]
	rig["next_id"] = int(rig["next_id"])
	var next := int(rig["next_id"])
	for piece in rig["pieces"]:
		var full := new_piece({"next_id": 0}, "Piece")
		full.merge(piece, true)
		piece.merge(full, true)
		for key in ["id", "hframes", "frame", "parent"]:
			piece[key] = int(piece[key])
		next = maxi(next, piece["id"] + 1)
	rig["next_id"] = next
	for anim in rig["animations"]:
		var full := new_animation(str(anim.get("name", IDLE)))
		full.merge(anim, true)
		anim.merge(full, true)
		for id in anim["tracks"]:
			for property in anim["tracks"][id]:
				for key in anim["tracks"][id][property]:
					key["beat"] = float(key["beat"])
					key["value"] = float(key["value"])
					if not key.has("ease"):
						key["ease"] = default_ease(property)
	return rig


static func default_ease(property: String) -> String:
	return "hold" if property == "frame" else "smooth"


static func find_animation(rig: Dictionary, anim_name: String) -> Dictionary:
	for anim in rig.get("animations", []):
		if anim["name"] == anim_name:
			return anim
	return {}


static func find_piece(rig: Dictionary, id: int) -> Dictionary:
	for piece in rig["pieces"]:
		if piece["id"] == id:
			return piece
	return {}


static func texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not _textures.has(path):
		_textures[path] = ChartDefs.load_texture(path)
	return _textures[path]


## Forget loaded sprites, so a changed file shows its new look.
static func forget_textures() -> void:
	_textures.clear()


static func frame_size(piece: Dictionary) -> Vector2:
	var tex := texture(piece["sprite"])
	if tex == null:
		return Vector2.ZERO
	return Vector2(tex.get_width() / float(maxi(piece["hframes"], 1)), tex.get_height())


# --- keys ---

## A property's value at this time (in beats into the animation), between its keys.
static func value_at(keys: Array, time: float, length: float, looping: bool, fallback: float) -> float:
	if keys.is_empty():
		return fallback
	var count := keys.size()
	if count == 1:
		return keys[0]["value"]
	# The key at or before the time (-1 = before the first: the last one, a loop back)
	var j := -1
	for k in count:
		if keys[k]["beat"] <= time:
			j = k
	if not looping:
		if j < 0:
			return keys[0]["value"]
		if j >= count - 1:
			return keys[count - 1]["value"]
	var b0 := _beat(keys, j, length, looping)
	var b1 := _beat(keys, j + 1, length, looping)
	var v0 := _value(keys, j, looping)
	var v1 := _value(keys, j + 1, looping)
	var span := maxf(b1 - b0, 0.0001)
	var u := clampf((time - b0) / span, 0.0, 1.0)
	match _key(keys, j, looping)["ease"]:
		"hold":
			return v0
		"linear":
			return lerpf(v0, v1, u)
		"ease in":
			return lerpf(v0, v1, u * u)
		"ease out":
			return lerpf(v0, v1, 1.0 - (1.0 - u) * (1.0 - u))
		"ease in-out":
			return lerpf(v0, v1, u * u * (3.0 - 2.0 * u))
	# Smooth: a curve that also looks at the keys either side, so it flows through them
	var b_prev := _beat(keys, j - 1, length, looping)
	var b_next := _beat(keys, j + 2, length, looping)
	var slope0 := (v1 - _value(keys, j - 1, looping)) / maxf(b1 - b_prev, 0.0001)
	var slope1 := (_value(keys, j + 2, looping) - v0) / maxf(b_next - b0, 0.0001)
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * v0 + (u3 - 2.0 * u2 + u) * span * slope0 		+ (-2.0 * u3 + 3.0 * u2) * v1 + (u3 - u2) * span * slope1


## Key number i, counting on round the loop (or stopping at the ends if it doesn't loop).
static func _key(keys: Array, i: int, looping: bool) -> Dictionary:
	return keys[posmod(i, keys.size())] if looping else keys[clampi(i, 0, keys.size() - 1)]


static func _value(keys: Array, i: int, looping: bool) -> float:
	return _key(keys, i, looping)["value"]


static func _beat(keys: Array, i: int, length: float, looping: bool) -> float:
	var count := keys.size()
	if looping:
		return keys[posmod(i, count)]["beat"] + floorf(float(i) / count) * length
	# Past the ends: carry on as far again, so the curve flattens out there
	if i < 0:
		return keys[0]["beat"] - (keys[1]["beat"] - keys[0]["beat"])
	if i >= count:
		return keys[count - 1]["beat"] + (keys[count - 1]["beat"] - keys[count - 2]["beat"])
	return keys[i]["beat"]


## Where an animation is, this many beats after it started.
static func local_time(anim: Dictionary, beats_in: float) -> float:
	var length := maxf(float(anim["beats"]), 0.0001)
	return fposmod(beats_in, length) if anim["loop"] else clampf(beats_in, 0.0, length)


## Every piece's place (in the rig's own space) and frame, `time` beats into `anim`.
## Returns piece id -> {"xf": Transform2D, "frame": int}.
static func pose(rig: Dictionary, anim: Dictionary, time: float) -> Dictionary:
	var local := {}
	for piece in rig["pieces"]:
		var values := {}
		var tracks: Dictionary = anim.get("tracks", {}).get(str(piece["id"]), {}) if not anim.is_empty() else {}
		for property in PROPERTIES:
			values[property] = value_at(tracks.get(property, []), time, float(anim.get("beats", 1.0)), anim.get("loop", true), float(piece[property]))
		local[piece["id"]] = values
	var placed := {}
	for piece in rig["pieces"]:
		_place(rig, piece, local, placed, 0)
	return placed


static func _place(rig: Dictionary, piece: Dictionary, local: Dictionary, placed: Dictionary, depth: int) -> Transform2D:
	var id: int = piece["id"]
	if placed.has(id):
		return placed[id]["xf"]
	var values: Dictionary = local[id]
	var xf := Transform2D(deg_to_rad(values["rotation"]), Vector2(values["x"], values["y"]))
	var parent := find_piece(rig, piece["parent"]) if piece["parent"] != id else {}
	if not parent.is_empty() and depth < 64:
		xf = _place(rig, parent, local, placed, depth + 1) * xf
	var frames := maxi(piece["hframes"], 1)
	placed[id] = {"xf": xf, "frame": clampi(roundi(values["frame"]), 0, frames - 1)}
	return xf


## Draws the rig onto a canvas item, with `base` taking the rig's space to the canvas.
static func draw(canvas: CanvasItem, rig: Dictionary, placed: Dictionary, base: Transform2D, tint := Color.WHITE) -> void:
	for piece in rig["pieces"]:
		var tex := texture(piece["sprite"])
		if tex == null or not placed.has(piece["id"]):
			continue
		var size := frame_size(piece)
		var spot: Dictionary = placed[piece["id"]]
		canvas.draw_set_transform_matrix(base * spot["xf"])
		var pivot := Vector2(piece["pivot_x"], piece["pivot_y"])
		canvas.draw_texture_rect_region(tex, Rect2(-pivot, size), Rect2(Vector2(spot["frame"] * size.x, 0), size), tint)
	canvas.draw_set_transform_matrix(Transform2D())


## The box round everything drawn, in the rig's space.
static func bounds(rig: Dictionary, placed: Dictionary) -> Rect2:
	var box := Rect2()
	var first := true
	for piece in rig["pieces"]:
		var size := frame_size(piece)
		if size == Vector2.ZERO or not placed.has(piece["id"]):
			continue
		var xf: Transform2D = placed[piece["id"]]["xf"]
		var corner := -Vector2(piece["pivot_x"], piece["pivot_y"])
		for c in [corner, corner + Vector2(size.x, 0), corner + size, corner + Vector2(0, size.y)]:
			var p: Vector2 = xf * c
			if first:
				box = Rect2(p, Vector2.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box if not first else Rect2(-24, -48, 48, 48)


## The piece drawn on top at this point (in the rig's space), or {} if none.
static func piece_at(rig: Dictionary, placed: Dictionary, point: Vector2) -> Dictionary:
	var pieces: Array = rig["pieces"]
	for i in range(pieces.size() - 1, -1, -1):
		var piece: Dictionary = pieces[i]
		var size := frame_size(piece)
		if size == Vector2.ZERO or not placed.has(piece["id"]):
			continue
		var inside: Vector2 = placed[piece["id"]]["xf"].affine_inverse() * point + Vector2(piece["pivot_x"], piece["pivot_y"])
		if not Rect2(Vector2.ZERO, size).has_point(inside):
			continue
		var tex := texture(piece["sprite"])
		var image := tex.get_image() if tex != null else null
		if image == null:
			return piece
		var pixel := Vector2i(inside) + Vector2i(int(placed[piece["id"]]["frame"] * size.x), 0)
		if pixel.x < image.get_width() and pixel.y < image.get_height() and image.get_pixelv(pixel).a > 0.1:
			return piece
	return {}


# --- editing keys ---

static func keys_of(anim: Dictionary, id: int, property: String, create := false) -> Array:
	var tracks: Dictionary = anim["tracks"]
	var key := str(id)
	if not tracks.has(key):
		if not create:
			return []
		tracks[key] = {}
	if not tracks[key].has(property):
		if not create:
			return []
		tracks[key][property] = []
	return tracks[key][property]


## Sets a key (making one, or changing the one already on this beat).
static func set_key(anim: Dictionary, id: int, property: String, beat: float, value: float) -> void:
	var keys := keys_of(anim, id, property, true)
	for key in keys:
		if absf(key["beat"] - beat) < 0.001:
			key["value"] = value
			return
	keys.append({"beat": beat, "value": value, "ease": default_ease(property)})
	keys.sort_custom(func(a, b): return a["beat"] < b["beat"])


static func sort_keys(anim: Dictionary) -> void:
	for id in anim["tracks"]:
		for property in anim["tracks"][id]:
			anim["tracks"][id][property].sort_custom(func(a, b): return a["beat"] < b["beat"])


## Drops a piece and everything about it; its children keep their place on screen
## as well as they can by moving to its parent.
static func remove_piece(rig: Dictionary, id: int) -> void:
	var piece := find_piece(rig, id)
	if piece.is_empty():
		return
	for other in rig["pieces"]:
		if other["parent"] == id:
			other["parent"] = piece["parent"]
	rig["pieces"].erase(piece)
	for anim in rig["animations"]:
		anim["tracks"].erase(str(id))
