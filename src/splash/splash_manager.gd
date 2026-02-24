class_name SplashManager
extends Node2D
## Spawns splash effects at world positions. Each
## splash plays its one-shot animation and frees
## itself.


var _splash_scene: PackedScene


func _ready() -> void:
	_splash_scene = preload(
		"res://src/splash/splash.tscn")


func spawn_splash(
	pos: Vector2,
	animation_name: StringName,
) -> void:
	var splash: Splash = (
		_splash_scene.instantiate()
	)
	splash.global_position = pos
	add_child(splash)
	splash.play(animation_name)
