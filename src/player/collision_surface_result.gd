class_name CollisionSurfaceResult
extends RefCounted


# In case the Character is colliding with multiple sides, this should
# indicate which side tilemap_coord corresponds to.
var surface_side := SurfaceSide.NONE

var tilemap_coord := Vector2.INF

var tilemap_index := -1

var flipped_sides_for_nested_call := false

var error_message := ""


func reset() -> void:
    self.surface_side = SurfaceSide.NONE
    self.tilemap_coord = Vector2.INF
    self.tilemap_index = -1
    self.flipped_sides_for_nested_call = false
    self.error_message = ""
