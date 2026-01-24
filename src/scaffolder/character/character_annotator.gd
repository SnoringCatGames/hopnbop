class_name CharacterAnnotator
extends Node2D

# FIXME: LEFT OFF HERE

@export var character: Character

# func _draw() -> void:
#     if not Engine.is_editor_hint() and not G.settings.draw_annotations:
#         return

#     var bounds := _get_bounds_local()
#     var points := PackedVector2Array(
#         [
#             bounds.position,
#             bounds.position + bounds.size.x * Vector2.RIGHT,
#             bounds.end,
#             bounds.position + bounds.size.y * Vector2.DOWN,
#             bounds.position,
#         ],
#     )
#     draw_polyline(points, Color(1, .7, .1, 0.4), 4)
