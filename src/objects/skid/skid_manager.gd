class_name SkidManager
extends Node2D
## Spawns skid effects at world positions. Each skid
## plays its one-shot animation and frees itself.


var _skid_scene: PackedScene


func _ready() -> void:
	_skid_scene = G.settings.skid_scene


func spawn_skid(
	pos: Vector2,
	animation_name: StringName,
	flip_h: bool,
) -> void:
	var skid: Skid = _skid_scene.instantiate()
	skid.global_position = pos
	skid.flip_h = flip_h
	add_child(skid)
	skid.play(animation_name)
