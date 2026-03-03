class_name OneWayCollisionValidator
extends RefCounted
## Validates one-way floor collisions to filter out invalid side collisions.
##
## Godot has a bug where one-way collision tiles can sometimes be collided with
## from the side when a player moves horizontally through the air. This
## validator checks if a collision is truly with the "top face" of a one-way
## tile and should be treated as a floor collision.

# FIXME: Get this from project settings. Update similar usage in the codebase.
const FLOOR_MAX_ANGLE := PI / 4.0
const EDGE_CORNER_TOLERANCE := 2.0 # Pixels of tolerance for edge detection.
const EDGE_CORNER_TOLERANCE_SQUARED := (
	EDGE_CORNER_TOLERANCE * EDGE_CORNER_TOLERANCE
)

# Cache for tile collision data to avoid repeated native API calls.
# Key: Vector2i (tile coords)
# Value: { "is_one_way": bool, "top_face_segments": Array }
var _tile_cache := {}


## Validates whether a tile collision should count as a floor touch.
## For non-one-way tiles, always returns true.
## For one-way tiles, validates that the collision is with the "top face".
## Returns true if valid (keep), false if invalid (discard).
func validate_floor_collision(
	collision: KinematicCollision2D,
	character_velocity: Vector2,
	character_shape: Shape2D,
	character_global_position: Vector2,
) -> bool:
	var collider := collision.get_collider()
	if not collider is TileMapLayer:
		return true  # Non-tilemap collisions are always valid.

	# Get cached tile data (or compute and cache it).
	var tile_data := _get_tile_cache_entry(collider as TileMapLayer, collision)

	# Non-one-way tiles are always valid.
	if not tile_data.is_one_way:
		return true

	# Rule 1: Collision normal must point upward (floor-like).
	var normal := collision.get_normal()
	if not _is_floor_normal(normal):
		return false

	# Get tile collision data from cache.
	var collision_point := collision.get_position()
	var top_face_segments: Array = tile_data.top_face_segments

	# Rule 2: For edge corners, require downward velocity and bottom contact.
	if _is_edge_corner_collision(collision_point, top_face_segments):
		# Edge corner: require positive Y velocity (falling down).
		if character_velocity.y < 0:
			return false

		# Edge corner: require collision to be on bottom of player shape.
		if not _is_collision_on_shape_bottom(
			collision_point,
			character_shape,
			character_global_position
		):
			return false

	return true


## Checks if a collision normal indicates a floor surface.
func _is_floor_normal(normal: Vector2) -> bool:
	var angle_to_up := absf(normal.angle_to(Vector2.UP))
	return angle_to_up <= FLOOR_MAX_ANGLE


## Gets or creates a cache entry for a tile's collision properties.
## Caches both is_one_way status and top_face_segments.
func _get_tile_cache_entry(
	tilemap: TileMapLayer,
	collision: KinematicCollision2D
) -> Dictionary:
	var coords := tilemap.get_coords_for_body_rid(collision.get_collider_rid())

	# Return cached entry if available.
	if _tile_cache.has(coords):
		return _tile_cache[coords]

	# Compute and cache tile properties.
	var entry := {
		"is_one_way": false,
		"top_face_segments": []
	}

	var tile_data := tilemap.get_cell_tile_data(coords)
	if tile_data:
		# Check all physics layers for one-way collision polygons.
		for layer_id in range(3):  # physics_layer_0, 1, 2
			var polygon_count := tile_data.get_collision_polygons_count(layer_id)
			for polygon_id in range(polygon_count):
				if tile_data.is_collision_polygon_one_way(layer_id, polygon_id):
					entry.is_one_way = true
					# Extract top face segments from this one-way polygon.
					var polygon := tile_data.get_collision_polygon_points(
						layer_id, polygon_id
					)
					entry.top_face_segments = _extract_top_face_segments(
						polygon, tilemap, coords
					)
					break
			if entry.is_one_way:
				break

	_tile_cache[coords] = entry
	return entry


## Extracts segments from a polygon that represent the "top face" (floor).
## A top face segment has an outward normal that points upward within the
## floor max angle.
func _extract_top_face_segments(
	polygon: PackedVector2Array,
	tilemap: TileMapLayer,
	tile_coords: Vector2i,
) -> Array:
	var segments := []
	var tile_origin := tilemap.map_to_local(tile_coords)

	for i in range(polygon.size()):
		var p1 := polygon[i] + tile_origin
		var p2 := polygon[(i + 1) % polygon.size()] + tile_origin

		# Calculate the outward normal for this segment.
		# For a clockwise polygon (which is common in Godot), the outward
		# normal points to the right of the segment direction.
		var segment_dir := (p2 - p1).normalized()
		var segment_normal := Vector2(segment_dir.y, -segment_dir.x)

		# Check if this normal points upward (negative Y in Godot coords).
		if segment_normal.y < 0:
			var angle_to_up := absf(segment_normal.angle_to(Vector2.UP))
			if angle_to_up <= FLOOR_MAX_ANGLE:
				segments.append([p1, p2])

	return segments


## Checks if a collision point is near the edge/corner of a top face segment.
func _is_edge_corner_collision(
	collision_point: Vector2,
	top_face_segments: Array,
) -> bool:
	for segment in top_face_segments:
		var p1: Vector2 = segment[0]
		var p2: Vector2 = segment[1]

		var dist_sq_to_p1 := (
			collision_point.distance_squared_to(p1)
		)
		var dist_sq_to_p2 := (
			collision_point.distance_squared_to(p2)
		)

		if (dist_sq_to_p1
				<= EDGE_CORNER_TOLERANCE_SQUARED
				or dist_sq_to_p2
				<= EDGE_CORNER_TOLERANCE_SQUARED):
			return true

	return false


## Checks if a collision point is on the "bottom" portion of a shape.
## Bottom means below 45 degrees from the horizontal center.
func _is_collision_on_shape_bottom(
	collision_point: Vector2,
	shape: Shape2D,
	shape_global_position: Vector2,
) -> bool:
	var relative_point := collision_point - shape_global_position

	if shape is CircleShape2D:
		# For circle: bottom is where angle from center is between 45-135 deg.
		# In Godot's coordinate system (Y down), positive Y is below center.
		# atan2 returns angle from positive X axis, so PI/2 is straight down.
		var angle := relative_point.angle()
		# angle is in radians: 0 = right, PI/2 = down, PI = left, -PI/2 = up.
		# Bottom region: angle between PI/4 (45 deg) and 3*PI/4 (135 deg).
		return angle > PI / 4.0 and angle < 3.0 * PI / 4.0

	elif shape is CapsuleShape2D:
		# For capsule: simple check if point is below center.
		# Note: The bunny's collision shape may be rotated.
		return relative_point.y > 0

	elif shape is RectangleShape2D:
		var rect := shape as RectangleShape2D
		var half_height := rect.size.y / 2.0
		# Bottom 50% of the rectangle.
		return relative_point.y > half_height * 0.5

	# Default: accept collision as valid (conservative).
	return true


## Clears the cache. Call when changing levels.
func clear_cache() -> void:
	_tile_cache.clear()
