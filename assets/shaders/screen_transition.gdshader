shader_type canvas_item;

// Main animation progress (0.0 = fully visible, 1.0 = fully transitioned).
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// Tile size in pixels. Square tiles are computed from
// this and the screen dimensions.
uniform float tile_size = 18.0;

// Transition color (what tiles snap to) - used when not using captured screen.
uniform vec4 transition_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// Captured screen texture for wipe transitions.
uniform sampler2D captured_screen : hint_default_white;
uniform bool use_captured_screen = false;

// Delay pattern: 0=radial, 1=diagonal_tl, 2=diagonal_tr, 3=horizontal,
// 4=vertical, 5=random.
uniform int delay_pattern : hint_range(0, 5) = 5;

// Controls how much time is allocated to per-tile delays vs animation.
// Higher values = more staggered animation.
uniform float delay_spread : hint_range(0.0, 1.0) = 0.7;

// Tile animation style: 0=smooth_fade, 1=snap.
uniform int tile_style : hint_range(0, 1) = 1;

// Direction: false=transition_out (reveal->cover), true=transition_in
// (cover->reveal).
uniform bool reverse_direction = false;

// Random seed for random delay pattern.
uniform float random_seed = 0.0;

// Amount of random jitter to add to the base pattern (0.0 = pure pattern).
uniform float pattern_randomness : hint_range(0.0, 1.0) = 0.3;

// Ease-out-in: fast at start and end, slow in middle (opposite of smoothstep).
// Blended with linear for smoother transition at the midpoint.
float ease_out_in(float t) {
	float curved;
	if (t < 0.5) {
		// First half: ease-out (fast start, slows down).
		float t2 = t * 2.0;
		curved = 0.5 * (1.0 - (1.0 - t2) * (1.0 - t2));
	} else {
		// Second half: ease-in (slow start, speeds up).
		float t2 = (t - 0.5) * 2.0;
		curved = 0.5 + 0.5 * t2 * t2;
	}
	// Blend 70% curve with 30% linear for smoother middle.
	return mix(curved, t, 0.3);
}

void fragment() {
	// Apply ease-out-in to progress (fast at edges, slow in middle).
	float eased_progress = ease_out_in(progress);

	// Compute square tile grid from screen dimensions.
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 tile_count = ceil(screen_size / tile_size);

	// Determine which tile this pixel belongs to.
	vec2 tile_pos = floor(UV * tile_count);

	// Normalize tile position to 0-1 range.
	vec2 normalized = tile_pos / (tile_count - 1.0);

	// Calculate random offset for this tile (-0.5 to 0.5).
	float random_offset = fract(
		sin(dot(tile_pos + random_seed, vec2(12.9898, 78.233))) * 43758.5453
	) - 0.5;

	// Calculate this tile's delay (0.0 to 1.0) based on pattern.
	float tile_delay = 0.0;
	if (delay_pattern == 0) {
		// Radial from center (aspect-corrected for
		// circular shape with square tiles).
		vec2 diff = normalized - vec2(0.5, 0.5);
		float ar = tile_count.x / tile_count.y;
		diff.x *= ar;
		tile_delay = length(diff)
			/ length(vec2(0.5 * ar, 0.5));
	} else if (delay_pattern == 1) {
		// Diagonal from top-left.
		tile_delay = (normalized.x + normalized.y) / 2.0;
	} else if (delay_pattern == 2) {
		// Diagonal from top-right.
		tile_delay = ((1.0 - normalized.x) + normalized.y) / 2.0;
	} else if (delay_pattern == 3) {
		// Horizontal (left to right).
		tile_delay = normalized.x;
	} else if (delay_pattern == 4) {
		// Vertical (top to bottom).
		tile_delay = normalized.y;
	} else {
		// Pure random.
		tile_delay = random_offset + 0.5;
	}

	// Add random jitter to the base pattern.
	if (delay_pattern != 5) {
		tile_delay = clamp(tile_delay + random_offset * pattern_randomness, 0.0, 1.0);
	}

	// Apply reverse direction if needed.
	if (reverse_direction) {
		tile_delay = 1.0 - tile_delay;
	}

	// Map global progress to per-tile progress.
	float tile_animation_duration = 1.0 - delay_spread;
	float tile_start_time = tile_delay * delay_spread;

	// Calculate this tile's local progress (0.0 to 1.0).
	float tile_progress = 0.0;
	if (tile_animation_duration > 0.0) {
		tile_progress = clamp(
			(eased_progress - tile_start_time) / tile_animation_duration,
			0.0,
			1.0
		);
	} else {
		// If no animation duration, snap based on whether we passed the delay.
		tile_progress = eased_progress > tile_start_time ? 1.0 : 0.0;
	}

	// Apply style.
	float final_progress = tile_progress;
	if (tile_style == 0) {
		// Smooth fade with easing (smoothstep).
		final_progress = tile_progress * tile_progress * (3.0 - 2.0 * tile_progress);
	} else {
		// Snap: threshold at 0.5.
		final_progress = tile_progress > 0.5 ? 1.0 : 0.0;
	}

	// Output color based on mode.
	if (use_captured_screen) {
		// Wipe mode: fade out the captured screen to reveal new content.
		// Alpha goes from 1 (visible) to 0 (transparent) as tiles complete.
		COLOR = texture(captured_screen, UV);
		COLOR.a = 1.0 - final_progress;
	} else {
		// Solid color mode: tiles fade in to cover the screen.
		COLOR = transition_color;
		COLOR.a = final_progress;
	}
}
