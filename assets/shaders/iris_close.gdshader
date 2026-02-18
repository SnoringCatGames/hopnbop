shader_type canvas_item;

// Animation progress (0.0 = fully open, 1.0 = fully closed).
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// Screen-space center of the iris in UV coordinates.
uniform vec2 center = vec2(0.5, 0.5);

// Softness of the circle edge.
uniform float edge_softness : hint_range(0.0, 0.1) = 0.02;

// Screen aspect ratio (width / height).
uniform float aspect_ratio = 1.777;

void fragment() {
	// Fully closed: solid black, no hole.
	if (progress >= 0.999) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		// Correct UV to physical proportions so the
		// circle isn't stretched into an ellipse.
		vec2 corrected_uv = vec2(
			UV.x * aspect_ratio, UV.y);
		vec2 corrected_center = vec2(
			center.x * aspect_ratio, center.y);

		// Maximum radius needed to cover the entire
		// screen from the given center point.
		vec2 corner_dist = max(
			corrected_center,
			vec2(aspect_ratio, 1.0) - corrected_center
		);
		float max_radius = length(corner_dist);
		float current_radius = (
			max_radius * (1.0 - progress));
		float dist = length(
			corrected_uv - corrected_center);
		float alpha = smoothstep(
			current_radius - edge_softness,
			current_radius + edge_softness,
			dist
		);
		COLOR = vec4(0.0, 0.0, 0.0, alpha);
	}
}
