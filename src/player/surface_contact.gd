class_name SurfaceContact
extends RefCounted


enum {
    UNKNOWN,
    PHYSICS,
    MATCH_ROUNDING_CORNER,
    MATCH_TRAJECTORY,
    INITIAL_ATTACHMENT,
}


## This indicates what mechanism led to the creation of this contact.
var type := UNKNOWN

var contact_position := Vector2.INF
var contact_normal := Vector2.INF
var tile_map: TileMap
var tilemap_coord := Vector2.INF
var tilemap_index := -1
var just_started := false
var _is_still_touching := false
