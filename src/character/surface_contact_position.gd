class_name SurfaceContactPosition
extends RefCounted


var character_position := Vector2.INF

var contact_position := Vector2.INF

var side := SurfaceSide.NONE


func _init(position_to_copy = null) -> void:
    if position_to_copy != null:
        copy(self, position_to_copy)


func reset() -> void:
    self.character_position = Vector2.INF
    self.contact_position = Vector2.INF
    self.side = SurfaceSide.NONE


func get_string(verbose := true) -> String:
    if verbose:
        return (
            "SurfaceContactPosition{ %s, %s, %s }"
        ) % [
            character_position,
            contact_position,
            SurfaceSide.get_string(side),
        ]
    else:
        return "P{%s,%s,%s}" % [
            G.utils.get_vector_string(character_position, 1),
            G.utils.get_vector_string(contact_position, 1),
            SurfaceSide.get_prefix(side),
        ]


static func copy(
        destination: SurfaceContactPosition,
        source: SurfaceContactPosition) -> void:
    destination.character_position = source.character_position
    destination.contact_position = source.contact_position
    destination.side = source.side