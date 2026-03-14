shader_type canvas_item;

void fragment() {
	float dist = distance(UV, vec2(0.5));
	if (dist > 0.5) {
		COLOR.a = 0.0;
	}
}
