class_name MockGamePanel
extends GamePanel
## Mock GamePanel for testing.


func _ready() -> void:
	# Default to level fully loaded for tests to avoid PerfTracker errors.
	is_level_fully_loaded = true


func on_level_added(_level: Level) -> void:
	pass


func on_level_removed(_level: Level) -> void:
	pass
