class_name LevelRegistry
extends RefCounted
## Central registry for level metadata and selection.
##
## Maps level IDs to their scenes and metadata. Used for dynamic level
## selection during matchmaking.


# Dictionary<StringName, LevelInfo>
var _levels_by_id: Dictionary = {}

# Ordered list of levels.
var _levels: Array[LevelInfo] = []


## Register a level.
func register_level(info: LevelInfo) -> void:
	if info.id.is_empty():
		push_warning("LevelRegistry: Cannot register level without id")
		return

	if _levels_by_id.has(info.id):
		push_warning("LevelRegistry: Level '%s' already registered" % info.id)
		return

	_levels_by_id[info.id] = info
	_levels.append(info)


## Get level info by ID. Returns null if not found.
func get_level_by_id(id: StringName) -> LevelInfo:
	return _levels_by_id.get(id, null)


## Get level ID for a given scene. Returns empty string if not found.
func get_level_id_for_scene(scene: PackedScene) -> StringName:
	for info in _levels:
		if info.scene == scene:
			return info.id
	return ""


## Get all registered level IDs.
func get_all_level_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for info in _levels:
		ids.append(info.id)
	return ids


## Get all enabled level IDs.
func get_enabled_level_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for info in _levels:
		if info.is_enabled:
			ids.append(info.id)
	return ids


## Get levels available for a given player count.
func get_available_levels(player_count: int) -> Array[LevelInfo]:
	var available: Array[LevelInfo] = []
	for info in _levels:
		if info.is_enabled and \
				player_count >= info.min_players and \
				player_count <= info.max_players:
			available.append(info)
	return available


## Get available level IDs for a given player count.
func get_available_level_ids(player_count: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for info in get_available_levels(player_count):
		ids.append(info.id)
	return ids


## Check if a level ID is valid and enabled.
func is_level_available(id: StringName) -> bool:
	var info := get_level_by_id(id)
	return info != null and info.is_enabled


## Get the total number of registered levels.
func get_level_count() -> int:
	return _levels.size()


## Clear all registered levels.
func clear() -> void:
	_levels_by_id.clear()
	_levels.clear()


## Get the default level (first enabled level).
## Returns null if no levels are registered or none are enabled.
func get_default_level() -> LevelInfo:
	for info in _levels:
		if info.is_enabled:
			return info
	return null


## Get the default level scene.
## Returns null if no default level exists.
func get_default_level_scene() -> PackedScene:
	var info := get_default_level()
	return info.scene if info != null else null
