shader_type canvas_item;

void fragment() {
	// Horizontally flip mirror texture to replicate physical vehicle rear-view reflection
	COLOR = texture(TEXTURE, vec2(1.0 - UV.x, UV.y));
}
