class_name PlayerAttributeGenerator
extends RefCounted


static func generate_random_attributes() -> Dictionary:
	var is_soft := randf() > 0.5
	var adjective_list := (
		BunnyWords.SOFT_ADJECTIVES if is_soft
		else BunnyWords.HARD_ADJECTIVES
	)

	return {
		"bunny_name": BunnyWords.NAMES.pick_random(),
		"adjective": adjective_list.pick_random(),
		"body_type_index": 0,
		"costume_index": 0,
		"is_soft": is_soft
	}


## Calculates outline colors based on player count.
static func calculate_outline_colors(player_count: int) -> Array[Color]:
	var colors: Array[Color] = []

	if player_count <= 4:
		# Evenly divide hue space (0°, 90°, 180°, 270° for 4 players).
		for i in range(player_count):
			var hue := float(i) / float(player_count)
			colors.append(Color.from_hsv(hue, 1.0, 1.0))

	elif player_count <= 8:
		# Use 4 base hues + alternating saturation/lightness variants.
		var base_player_count := 4
		for i in range(player_count):
			var base_idx := i % base_player_count
			var variation := i / base_player_count
			var hue := float(base_idx) / float(base_player_count)

			if variation == 0:
				# Normal: full saturation and value.
				colors.append(Color.from_hsv(hue, 1.0, 1.0))
			else:
				# Desaturated and lightened.
				colors.append(Color.from_hsv(hue, 0.6, 0.9))

	elif player_count <= 12:
		# Use 4 base hues + 3 variations (normal, desat/light, sat/dark).
		var base_player_count := 4
		for i in range(player_count):
			var base_idx := i % base_player_count
			var variation := i / base_player_count
			var hue := float(base_idx) / float(base_player_count)

			match variation:
				0:
					# Normal: full saturation and value.
					colors.append(Color.from_hsv(hue, 1.0, 1.0))
				1:
					# Desaturated and lightened.
					colors.append(Color.from_hsv(hue, 0.6, 0.9))
				2:
					# Saturated and darkened.
					colors.append(Color.from_hsv(hue, 1.0, 0.6))

	else:
		# 13+ players: random colors, no collision avoidance.
		for i in range(player_count):
			var hue := randf()
			var sat := randf_range(0.6, 1.0)
			var val := randf_range(0.7, 1.0)
			colors.append(Color.from_hsv(hue, sat, val))

	return colors
