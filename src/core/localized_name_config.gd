class_name LocalizedNameConfig
extends RefCounted
## Loads per-locale name and adjective CSV files.
## Falls back to English if a locale file is
## missing. Caches loaded data per locale.


static var _names_cache := {}
static var _adj_cache := {}


## Returns the names array for the current locale.
static func get_names() -> Array:
	var locale := TranslationServer.get_locale()
	if _names_cache.has(locale):
		return _names_cache[locale]

	var names := _load_names(locale)
	if names.is_empty() and locale != "en":
		names = _load_names("en")
	if names.is_empty():
		# Final fallback to built-in NAMES.
		return DynamicAdjectiveConfig.NAMES

	_names_cache[locale] = names
	return names


## Returns the adjective list for a given
## AdjectiveListType for the current locale.
static func get_adjectives(
	list_id: int,
) -> Array:
	var locale := TranslationServer.get_locale()
	var cache_key := "%s_%d" % [locale, list_id]
	if _adj_cache.has(cache_key):
		return _adj_cache[cache_key]

	var all_adj := _load_adjectives(locale)
	if all_adj.is_empty() and locale != "en":
		all_adj = _load_adjectives("en")

	var category := _list_id_to_category(list_id)
	var result: Array = all_adj.get(
		category, [])

	if result.is_empty():
		# Fall back to built-in list.
		return DynamicAdjectiveConfig \
			.ADJ_LISTS_BY_ID.get(
				list_id,
				DynamicAdjectiveConfig
					.SOFT_ADJECTIVES)

	_adj_cache[cache_key] = result
	return result


## Clears cached data. Call when locale changes.
static func clear_cache() -> void:
	_names_cache.clear()
	_adj_cache.clear()


static func _load_names(locale: String) -> Array:
	var path := (
		"res://translations/names/names_%s.csv"
		% locale)
	if not FileAccess.file_exists(path):
		return []

	var names: Array = []
	var file := FileAccess.open(
		path, FileAccess.READ)
	if file == null:
		return []

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if not line.is_empty():
			names.append(line)
	return names


static func _load_adjectives(
	locale: String,
) -> Dictionary:
	var path := (
		"res://translations/adjectives/"
		+"adjectives_%s.csv" % locale)
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(
		path, FileAccess.READ)
	if file == null:
		return {}

	var result := {}
	# Skip header line.
	file.get_line()

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parts := line.split(",", true, 1)
		if parts.size() < 2:
			continue
		var category := parts[0].strip_edges()
		var adjective := parts[1].strip_edges()
		if not result.has(category):
			result[category] = []
		result[category].append(adjective)

	return result


static func _list_id_to_category(
	list_id: int,
) -> String:
	match list_id:
		DynamicAdjectiveConfig.AdjectiveListType.SOFT:
			return "soft"
		DynamicAdjectiveConfig.AdjectiveListType.HARD:
			return "hard"
		DynamicAdjectiveConfig \
				.AdjectiveListType.CROWN_UPPER:
			return "crown_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.REGICIDE_UPPER:
			return "regicide_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.BUMPS_UPPER:
			return "bumps_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.KILLS_UPPER:
			return "kills_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.KILLS_LOWER:
			return "kills_lower"
		DynamicAdjectiveConfig \
				.AdjectiveListType.DEATHS_UPPER:
			return "deaths_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.DEATHS_LOWER:
			return "deaths_lower"
		DynamicAdjectiveConfig \
				.AdjectiveListType.JUMPS_UPPER:
			return "jumps_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.JUMPS_LOWER:
			return "jumps_lower"
		DynamicAdjectiveConfig \
				.AdjectiveListType.WATER_TIME_UPPER:
			return "water_time_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.WATER_JUMP_UPPER:
			return "water_jump_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.ICE_TIME_UPPER:
			return "ice_time_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.SPRINGS_UPPER:
			return "springs_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.DIRECTION_CHANGES_UPPER:
			return "direction_changes_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.DIRECTION_CHANGES_LOWER:
			return "direction_changes_lower"
		DynamicAdjectiveConfig \
				.AdjectiveListType.HEIGHT_UPPER:
			return "height_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.CRITTER_DISRUPTOR_UPPER:
			return "critter_disruptor_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.FLY_PROXIMITY_UPPER:
			return "fly_proximity_upper"
		DynamicAdjectiveConfig \
				.AdjectiveListType.POOP_UPPER:
			return "poop_upper"
		_:
			return "soft"
