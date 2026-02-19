shader_type canvas_item;

// Outline shader for CanvasGroup nodes. Uses
// SCREEN_TEXTURE instead of TEXTURE because
// CanvasGroup does not populate TEXTURE with the
// composited children.
//
// The vertex shader computes the effective
// local-to-viewport scale (camera zoom) so the
// outline stays 1 game pixel wide regardless of
// screen resolution or zoom level.

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 10.0) = 1.0;
uniform bool outline_enabled = true;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

varying vec2 world_pixel_scale;

void vertex() {
	// Scale from local space to viewport space,
	// accounting for camera zoom and any transforms.
	mat4 cm = CANVAS_MATRIX * MODEL_MATRIX;
	world_pixel_scale = vec2(
		length(cm[0].xy),
		length(cm[1].xy)
	);
}

void fragment() {
	vec4 color = textureLod(screen_texture, SCREEN_UV, 0.0);

	if (!outline_enabled) {
		COLOR = color;
	} else if (color.a < 0.5) {
		// Check neighboring pixels in a plus pattern.
		float outline = 0.0;
		// Scale by world_pixel_scale so 1 outline_width
		// unit = 1 game pixel, not 1 screen pixel.
		vec2 pixel_size = outline_width * world_pixel_scale * SCREEN_PIXEL_SIZE;

		// Check 4 directions for opaque pixels.
		outline += textureLod(screen_texture, SCREEN_UV + vec2(pixel_size.x, 0.0), 0.0).a;
		outline += textureLod(screen_texture, SCREEN_UV + vec2(-pixel_size.x, 0.0), 0.0).a;
		outline += textureLod(screen_texture, SCREEN_UV + vec2(0.0, pixel_size.y), 0.0).a;
		outline += textureLod(screen_texture, SCREEN_UV + vec2(0.0, -pixel_size.y), 0.0).a;

		if (outline > 0.5) {
			COLOR = outline_color;
		} else {
			COLOR = color;
		}
	} else {
		COLOR = color;
	}
}
