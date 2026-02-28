class_name SessionPreferences
extends RefCounted
## Bundled client preferences sent to the
## server during matchmaking.
##
## Combines level selection preferences with
## gameplay toggles (critters, cheats) into a
## single object for the session request flow.


var level_preferences: LevelPreferences
var are_critters_enabled: bool = true
var are_cheats_enabled: bool = true


## Convert all preferences to a flat dictionary
## for serialization.
func to_dict() -> Dictionary:
	var d := {}
	if level_preferences != null:
		d.merge(level_preferences.to_dict())
	d["critters_enabled"] = are_critters_enabled
	d["cheats_enabled"] = are_cheats_enabled
	return d


## Create preferences from a dictionary.
static func from_dict(
	data: Dictionary,
) -> SessionPreferences:
	var prefs := SessionPreferences.new()
	prefs.level_preferences = \
		LevelPreferences.from_dict(data)
	prefs.are_critters_enabled = \
		data.get("critters_enabled", true)
	prefs.are_cheats_enabled = \
		data.get("cheats_enabled", true)
	return prefs


## Check if any non-default preferences are set.
func has_preferences() -> bool:
	if level_preferences != null \
			and level_preferences \
				.has_preferences():
		return true
	if not are_critters_enabled:
		return true
	if not are_cheats_enabled:
		return true
	return false
