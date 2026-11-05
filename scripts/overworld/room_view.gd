class_name RoomView
extends Node2D
## A room's tile layers, drawn with TileMapDual. The game and the Locale-Inator both
## use this, so the editor shows exactly what the game will.

const BLANK_SHEET_COLOR := Color(0.5, 0.5, 0.55)
const SHEET_COLUMNS := 4
## Which corners of a dual-grid tile are filled, bit 0 top left, 1 top right, 2 bottom
## left, 3 bottom right, and where that tile is on TileMapDual's standard sheet.
const SHEET_LAYOUT := [
	Vector2i(0, 3), Vector2i(3, 3), Vector2i(0, 2), Vector2i(1, 2),
	Vector2i(0, 0), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 1),
	Vector2i(1, 3), Vector2i(0, 1), Vector2i(1, 0), Vector2i(2, 2),
	Vector2i(3, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1),
]
const FILLED_TILE := Vector2i(2, 1)
const EMPTY_TILE := Vector2i(0, 3)
const CORNER_BITS := [TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER]

static var _tile_sets := {} # what a layer draws with -> its TileSet

var below := Node2D.new() # floors
var shadow_group := CanvasGroup.new() # every shadow, merged into one even shade
var walls := Node2D.new() # solid layers: over the shadows, so none fall across their tops
var above := Node2D.new() # layers over the player
var wall_shadows := WallShadows.new()
var room: Dictionary
var tile_size := 16
var _maps := {} # layer id -> TileMapDual
var _cells := {} # layer id -> {Vector2i: true}


## Each solid tile's shadow: the tile dragged away from the sun by the wall's height.
## Only redrawn when something changes, since a room's walls can be a lot of tiles.
class WallShadows extends Node2D:
	var owner_view: RoomView
	var rules: Dictionary

	func _draw() -> void:
		if owner_view == null or rules.is_empty() or owner_view.room.is_empty():
			return
		var size := float(owner_view.tile_size)
		for layer in owner_view.room["layers"]:
			var height := float(layer["wall_height"])
			if not layer["solid"] or layer["above"] or height <= 0.0:
				continue
			var reach := LocaleDefs.shadow_slant(rules) * height * size
			for cell: Vector2i in owner_view._cells[layer["id"]]:
				var at := Vector2(cell) * size
				var corners := PackedVector2Array()
				for corner in [Vector2.ZERO, Vector2(size, 0), Vector2(size, size), Vector2(0, size)]:
					corners.append(at + corner)
					corners.append(at + corner + reach)
				draw_colored_polygon(Geometry2D.convex_hull(corners), Color.BLACK)


func _init() -> void:
	# From the bottom up. Whatever else goes in a room (sprites) goes after walls, before above.
	below.z_index = -3
	shadow_group.z_index = -1
	above.z_index = 1
	wall_shadows.owner_view = self
	add_child(below)
	add_child(shadow_group)
	shadow_group.add_child(wall_shadows)
	add_child(walls)
	add_child(above)


## Shows or hides the sun's shadows.
func set_sun(on: bool, rules: Dictionary) -> void:
	shadow_group.visible = on
	# Not modulate: that also reaches the shadows inside, and it'd count twice
	shadow_group.self_modulate.a = clampf(float(rules["sun_strength"]), 0.0, 1.0)
	wall_shadows.rules = rules
	wall_shadows.queue_redraw()


## Shows a room.
func show_room(new_room: Dictionary, new_tile_size: int) -> void:
	room = new_room
	tile_size = maxi(new_tile_size, 1)
	for holder in [below, walls, above]:
		for child in holder.get_children():
			holder.remove_child(child)
			child.queue_free()
	_maps.clear()
	_cells.clear()
	for layer in room["layers"]:
		_add_layer(layer)
	wall_shadows.queue_redraw()


func _add_layer(layer: Dictionary) -> void:
	var cells := {}
	var flat: Array = layer["cells"]
	for i in range(0, flat.size() - 1, 2):
		cells[Vector2i(flat[i], flat[i + 1])] = true
	_cells[layer["id"]] = cells
	var map := TileMapDual.new()
	map.tile_set = tile_set_for(layer)
	var drawn: Vector2i = map.tile_set.tile_size
	map.scale = Vector2(tile_size, tile_size) / Vector2(drawn)
	for cell in cells:
		map.set_cell(cell, 0, FILLED_TILE)
	_maps[layer["id"]] = map
	if layer["above"]:
		above.add_child(map)
	elif layer["solid"]:
		walls.add_child(map)
	else:
		below.add_child(map)


## Puts a layer's settings back into effect after they change.
func refresh_layer(layer: Dictionary) -> void:
	show_room(room, tile_size)


## Draws or rubs out one tile. Returns whether anything changed.
func paint(layer: Dictionary, cell: Vector2i, on: bool) -> bool:
	var cells: Dictionary = _cells[layer["id"]]
	if cells.has(cell) == on:
		return false
	var map: TileMapDual = _maps[layer["id"]]
	if on:
		cells[cell] = true
		map.set_cell(cell, 0, FILLED_TILE)
	else:
		cells.erase(cell)
		map.erase_cell(cell)
	if layer["solid"]:
		wall_shadows.queue_redraw()
	return true


func has_tile(layer: Dictionary, cell: Vector2i) -> bool:
	return _cells[layer["id"]].has(cell)


## Writes what's been painted back into the layer's list, for saving.
func store_cells(layer: Dictionary) -> void:
	var flat := []
	for cell in _cells[layer["id"]]:
		flat.append(cell.x)
		flat.append(cell.y)
	layer["cells"] = flat


## Whether this tile can't be walked on.
func blocks(cell: Vector2i, edges_block: bool) -> bool:
	var has_floor := false
	for layer in room["layers"]:
		if _cells[layer["id"]].has(cell):
			if layer["solid"]:
				return true
			if not layer["above"]:
				has_floor = true
	return edges_block and not has_floor


## The box around every tile drawn: the camera won't show past this. Empty if nothing's drawn.
func drawn_rect() -> Rect2:
	var found := false
	var low := Vector2i.ZERO
	var high := Vector2i.ZERO
	for layer in room["layers"]:
		for cell: Vector2i in _cells[layer["id"]]:
			if not found:
				low = cell
				high = cell
				found = true
			else:
				low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
				high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	if not found:
		return Rect2()
	return Rect2(Vector2(low * tile_size), Vector2((high - low + Vector2i.ONE) * tile_size))


## Where the camera goes to follow a point. A room narrower than the view stays
## centred on that axis, and a bigger one stops at its drawn edges.
static func camera_spot(follow: Vector2, drawn: Rect2, view: Vector2) -> Vector2:
	if not drawn.has_area():
		return follow
	var spot := follow
	for axis in [0, 1]:
		if drawn.size[axis] <= view[axis]:
			spot[axis] = drawn.get_center()[axis]
		else:
			spot[axis] = clampf(follow[axis], drawn.position[axis] + view[axis] / 2.0, drawn.end[axis] - view[axis] / 2.0)
	return spot


# --- tile sets ---

## A TileSet set up the way TileMapDual's editor plugin would, cached by what it shows.
static func tile_set_for(layer: Dictionary) -> TileSet:
	var key := "%s|%s|%s" % [layer["sheet"], layer["plain_tile"], layer["edge_color"]]
	if _tile_sets.has(key):
		return _tile_sets[key]
	var sheet: Texture2D = _plain_sheet(layer) if layer["plain_tile"] else _dual_sheet(layer)
	var tile := Vector2i(sheet.get_size()) / SHEET_COLUMNS
	var tile_set := TileSet.new()
	tile_set.tile_size = tile
	# What TileMapDual's editor plugin sets up by hand. Its own helper for this uses
	# editor-only types, so it can't be used in a built game.
	tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	tile_set.add_terrain(0) # terrain 0, empty
	tile_set.add_terrain(0) # terrain 1, filled
	var atlas := TileSetAtlasSource.new()
	atlas.texture = sheet
	atlas.texture_region_size = tile
	for corners in SHEET_LAYOUT.size():
		var at: Vector2i = SHEET_LAYOUT[corners]
		atlas.create_tile(at)
		var data: TileData = atlas.get_tile_data(at, 0)
		data.terrain_set = 0
		for bit in CORNER_BITS.size():
			data.set_terrain_peering_bit(CORNER_BITS[bit], (corners >> bit) & 1)
	atlas.get_tile_data(EMPTY_TILE, 0).terrain = 0
	atlas.get_tile_data(FILLED_TILE, 0).terrain = 1
	tile_set.add_source(atlas, 0)
	_tile_sets[key] = tile_set
	return tile_set


static func _dual_sheet(layer: Dictionary) -> Texture2D:
	var texture := _picked_texture(layer)
	if texture != null and Vector2i(texture.get_size()).x >= SHEET_COLUMNS and Vector2i(texture.get_size()).y >= SHEET_COLUMNS:
		return texture
	return _make_sheet(_blank_tile(), Color("1a1020"))


static func _plain_sheet(layer: Dictionary) -> Texture2D:
	var texture := _picked_texture(layer)
	var image: Image = texture.get_image() if texture != null else _blank_tile()
	if image == null:
		image = _blank_tile()
	if image.is_compressed():
		image.decompress()
	return _make_sheet(image, Color(str(layer["edge_color"])))


static func _picked_texture(layer: Dictionary) -> Texture2D:
	var path := str(layer["sheet"])
	if path == "" or not (SafeFiles.is_game_file(path, SafeFiles.IMAGES) or SafeFiles.is_media_file(path, SafeFiles.IMAGES)):
		return null
	return ChartDefs.load_texture(path)


static func _blank_tile() -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(BLANK_SHEET_COLOR)
	return image


## Builds the whole 16-tile sheet from one plain tile: each tile shows the picture in
## the corners that are filled, with an outline along the open sides, square at the corners.
static func _make_sheet(tile: Image, edge: Color) -> Texture2D:
	var source := tile.duplicate() as Image
	source.convert(Image.FORMAT_RGBA8)
	var side := mini(source.get_width(), source.get_height())
	var sheet := Image.create(side * SHEET_COLUMNS, side * SHEET_COLUMNS, false, Image.FORMAT_RGBA8)
	var half := side / 2.0
	for corners in 16:
		var at: Vector2i = SHEET_LAYOUT[corners] * side
		for y in side:
			for x in side:
				var inside := _depth_inside(x + 0.5, y + 0.5, half, corners)
				if inside <= 0.0:
					continue
				var color := edge if inside <= 1.0 else source.get_pixel(x, y)
				sheet.set_pixel(at.x + x, at.y + y, color)
	return ImageTexture.create_from_image(sheet)


## How many pixels inside the filled shape a point is (0 or less: outside it). The
## shape is the filled quarters of the tile.
static func _depth_inside(x: float, y: float, half: float, corners: int) -> float:
	var right := x >= half
	var lower := y >= half
	var quarter := (2 if lower else 0) + (1 if right else 0)
	if not (corners >> quarter) & 1:
		return 0.0
	var side_filled: bool = (corners >> (quarter ^ 1)) & 1 # the quarter beside it
	var other_filled: bool = (corners >> (quarter ^ 2)) & 1 # the one above or below it
	var from_middle_x := absf(x - half) # how far out from the tile's middle
	var from_middle_y := absf(y - half)
	# Distance in from the side of this quarter where it meets nothing
	var in_x: float = INF if side_filled else from_middle_x
	var in_y: float = INF if other_filled else from_middle_y
	return minf(in_x, in_y)
