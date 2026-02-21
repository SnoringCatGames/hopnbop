shader_type canvas_item;

// Animation progress (0.0 = fully open, 1.0 = fully closed).
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// Screen-space center of the iris in UV coordinates.
uniform vec2 center = vec2(0.5, 0.5);

// Screen aspect ratio (width / height).
uniform float aspect_ratio = 1.777;

// Tile size in pixels. Square tiles are computed from
// this and the screen dimensions.
uniform float tile_size = 18.0;

// Random seed for per-tile jitter.
uniform float random_seed = 0.0;

// Amount of random jitter added to each tile's distance
// threshold (0.0 = perfectly circular, 1.0 = maximum fuzz).
uniform float pattern_randomness : hint_range(0.0, 1.0) = 0.1;

void fragment() {
	// Fully closed: solid black, skip tile math.
	if (progress >= 0.999) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		// Compute square tile grid from screen
		// dimensions.
		vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
		vec2 tile_count = ceil(screen_size / tile_size);

		// Determine which tile this pixel belongs to.
		vec2 tile_pos = floor(UV * tile_count);

		// Compute the center UV of this tile.
		vec2 tile_center_uv =
			(tile_pos + 0.5) / tile_count;

		// Aspect-correct the tile center and iris center
		// so the closing shape is circular, not
		// elliptical.
		vec2 corrected_tile = vec2(
			tile_center_uv.x * aspect_ratio,
			tile_center_uv.y);
		vec2 corrected_center = vec2(
			center.x * aspect_ratio, center.y);

		// Maximum radius needed to cover the entire
		// screen from the given center point.
		vec2 corner_dist = max(
			corrected_center,
			vec2(aspect_ratio, 1.0) - corrected_center
		);
		float max_radius = length(corner_dist);

		// Current closing radius (shrinks as progress
		// increases).
		float current_radius =
			max_radius * (1.0 - progress);

		// Distance from this tile's center to the iris
		// center.
		float dist = length(
			corrected_tile - corrected_center);

		// Per-tile random jitter (-0.5 to 0.5), using
		// the same hash as screen_transition.gdshader.
		float jitter = fract(
			sin(dot(
				tile_pos + random_seed,
				vec2(12.9898, 78.233)))
			* 43758.5453
		) - 0.5;

		// Apply jitter scaled by pattern_randomness and
		// max_radius so the fuzz is proportional to the
		// iris size.
		dist += jitter * pattern_randomness * max_radius;

		// Snap: tile is black if outside the closing
		// radius.
		float alpha =
			dist > current_radius ? 1.0 : 0.0;

		COLOR = vec4(0.0, 0.0, 0.0, alpha);
	}
}
