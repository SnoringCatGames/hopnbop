class_name SnailSpawner
extends RefCounted
## Utility for finding interior tile surfaces,
## interior empty cells, and spawning snails in
## networked match levels.


const SNAIL_SCENE_PATH := (
	"res://src/objects/snail/snail.tscn")

const _NEIGHBOR_OFFSETS := [
	Vector2i(0, -1), # TOP
	Vector2i(1, 0),  # RIGHT
	Vector2i(0, 1),  # BOTTOM
	Vector2i(-1, 0), # LEFT
]

## The face index that corresponds to each
## neighbor offset. If the neighbor at offset
## (0, -1) is empty, the tile's TOP face is
## exposed.
const _OFFSET_TO_FACE := {
	Vector2i(0, -1): Snail.Face.TOP,
	Vector2i(1, 0): Snail.Face.RIGHT,
	Vector2i(0, 1): Snail.Face.BOTTOM,
	Vector2i(-1, 0): Snail.Face.LEFT,
}


## Returns all interior tile surfaces in the
## given tilemap. An interior surface is a tile
## face that borders empty space inside the
## tilemap's enclosed area (not exterior).
## Returns an array of {tile: Vector2i,
## face: Snail.Face}.
static func find_interior_surfaces(
	tiles: TileMapLayer,
	extra_cells: Dictionary = {},
) -> Array:
	var used_cells := tiles.get_used_cells()
	if (used_cells.is_empty()
			and extra_cells.is_empty()):
		return []

	# Build occupied set for O(1) lookup.
	var occupied := {}
	for cell in used_cells:
		occupied[cell] = true
	for cell in extra_cells:
		occupied[cell] = true

	# Compute bounding rect expanded by 1.
	var min_cell := used_cells[0]
	var max_cell := used_cells[0]
	for cell in used_cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	var bounds := Rect2i(
		min_cell - Vector2i.ONE,
		max_cell - min_cell + Vector2i(3, 3),
	)

	# Flood-fill from top-left corner to find
	# all exterior empty cells.
	var exterior := _flood_fill_exterior(
		occupied, bounds)

	# Collect interior surfaces.
	var surfaces: Array = []
	for cell in used_cells:
		# Skip water tiles.
		var tile_data := (
			tiles.get_cell_tile_data(cell))
		if tile_data == null:
			continue
		if (tile_data.get_terrain_set()
				== Level.TERRAIN_SET_WATER):
			continue

		for offset: Vector2i in _NEIGHBOR_OFFSETS:
			var neighbor: Vector2i = cell + offset
			# Face is interior if neighbor is
			# empty and NOT exterior.
			if (not occupied.has(neighbor)
					and not exterior.has(
						neighbor)):
				surfaces.append({
					"tile": cell,
					"face": _OFFSET_TO_FACE[offset],
				})

	# Also collect surfaces from scene-based
	# extra cells (e.g. Spring tiles).
	for cell: Vector2i in extra_cells:
		for offset: Vector2i in _NEIGHBOR_OFFSETS:
			var neighbor: Vector2i = cell + offset
			if (not occupied.has(neighbor)
					and not exterior.has(
						neighbor)):
				surfaces.append({
					"tile": cell,
					"face": _OFFSET_TO_FACE[offset],
				})

	return surfaces


## Returns a random interior surface, or an
## empty dictionary if none found.
static func find_random_interior_surface(
	tiles: TileMapLayer,
	extra_cells: Dictionary = {},
) -> Dictionary:
	var surfaces := find_interior_surfaces(
		tiles, extra_cells)
	if surfaces.is_empty():
		return {}
	return surfaces.pick_random()


## Returns all interior empty cells in the
## tilemap. An interior empty cell is one that
## is not occupied by any tile and is not
## reachable from the exterior (i.e. it's inside
## the enclosed play area).
static func find_interior_empty_cells(
	tiles: TileMapLayer,
	extra_cells: Dictionary = {},
) -> Array[Vector2i]:
	var used_cells := tiles.get_used_cells()
	if (used_cells.is_empty()
			and extra_cells.is_empty()):
		return []

	# Build occupied set for O(1) lookup.
	var occupied := {}
	for cell in used_cells:
		occupied[cell] = true
	for cell in extra_cells:
		occupied[cell] = true

	# Compute bounding rect expanded by 1.
	var min_cell := used_cells[0]
	var max_cell := used_cells[0]
	for cell in used_cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	var bounds := Rect2i(
		min_cell - Vector2i.ONE,
		max_cell - min_cell + Vector2i(3, 3),
	)

	# Flood-fill exterior.
	var exterior := _flood_fill_exterior(
		occupied, bounds)

	# Collect interior empty cells: within
	# bounds, not occupied, not exterior.
	var interior: Array[Vector2i] = []
	for y in range(
			bounds.position.y,
			bounds.position.y + bounds.size.y):
		for x in range(
				bounds.position.x,
				bounds.position.x
				+ bounds.size.x):
			var cell := Vector2i(x, y)
			if (not occupied.has(cell)
					and not exterior.has(cell)):
				interior.append(cell)

	return interior


## Flood-fills from the expanded bounding rect
## corner through all 4-connected empty cells
## to identify exterior empty space.
static func _flood_fill_exterior(
	occupied: Dictionary,
	bounds: Rect2i,
) -> Dictionary:
	var exterior := {}
	var queue: Array[Vector2i] = []

	var start := bounds.position
	if not occupied.has(start):
		queue.append(start)
		exterior[start] = true

	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset: Vector2i in _NEIGHBOR_OFFSETS:
			var neighbor: Vector2i = cell + offset
			if (not exterior.has(neighbor)
					and not occupied.has(neighbor)
					and bounds.has_point(neighbor)):
				exterior[neighbor] = true
				queue.append(neighbor)

	return exterior
