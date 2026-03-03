class_name LevelPreferences
extends RefCounted
## Client-specified level selection preferences for matchmaking.
##
## Clients can express their level preferences using three mechanisms:
## - inclusion_list: Levels the client wants to play (empty = accept any)
## - exclusion_list: Levels the client does NOT want to play
## - preferred_level: The client's most preferred level (higher priority)
##
## The server uses these preferences as hints when selecting a level for
## a match, but has final authority and can override all preferences.


## Levels the client wants to play. If empty, client accepts any level.
var inclusion_list: Array[StringName] = []

## Levels the client does NOT want to play.
var exclusion_list: Array[StringName] = []

## The client's most preferred level (higher priority than inclusion_list).
var preferred_level: StringName = ""


## Convert preferences to a dictionary for serialization.
func to_dict() -> Dictionary:
	return {
		"inclusion": Array(inclusion_list),
		"exclusion": Array(exclusion_list),
		"preferred": String(preferred_level)
	}


## Create preferences from a dictionary.
static func from_dict(data: Dictionary) -> LevelPreferences:
	var prefs := LevelPreferences.new()

	if data.has("inclusion") and data.inclusion is Array:
		for level_id in data.inclusion:
			prefs.inclusion_list.append(StringName(str(level_id)))

	if data.has("exclusion") and data.exclusion is Array:
		for level_id in data.exclusion:
			prefs.exclusion_list.append(StringName(str(level_id)))

	if data.has("preferred"):
		prefs.preferred_level = StringName(str(data.preferred))

	return prefs


## Check if a level is allowed by these preferences.
func is_level_allowed(level_id: StringName) -> bool:
	# Check exclusion first.
	if level_id in exclusion_list:
		return false

	# If inclusion list is specified, level must be in it.
	if not inclusion_list.is_empty():
		return level_id in inclusion_list

	# No restrictions.
	return true


## Add a level to the inclusion list.
func include_level(level_id: StringName) -> void:
	if level_id not in inclusion_list:
		inclusion_list.append(level_id)
	# Remove from exclusion if present.
	var idx := exclusion_list.find(level_id)
	if idx >= 0:
		exclusion_list.remove_at(idx)


## Add a level to the exclusion list.
func exclude_level(level_id: StringName) -> void:
	if level_id not in exclusion_list:
		exclusion_list.append(level_id)
	# Remove from inclusion if present.
	var idx := inclusion_list.find(level_id)
	if idx >= 0:
		inclusion_list.remove_at(idx)
	# Clear preferred if it's the excluded level.
	if preferred_level == level_id:
		preferred_level = ""


## Set the preferred level.
func set_preferred(level_id: StringName) -> void:
	preferred_level = level_id
	# Ensure preferred is in inclusion list if inclusion is used.
	if not inclusion_list.is_empty() and level_id not in inclusion_list:
		inclusion_list.append(level_id)
	# Remove from exclusion if present.
	var idx := exclusion_list.find(level_id)
	if idx >= 0:
		exclusion_list.remove_at(idx)


## Clear all preferences.
func clear() -> void:
	inclusion_list.clear()
	exclusion_list.clear()
	preferred_level = ""


## Check if any preferences are set.
func has_preferences() -> bool:
	return (
		not inclusion_list.is_empty()
		or not exclusion_list.is_empty()
		or not preferred_level.is_empty()
	)
