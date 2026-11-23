shader_type canvas_item;

// Recolours a sprite (keeping its shading) so blue and orange objects read clearly,
// whatever colour their art started as.
uniform vec4 mode_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float shade = max(tex.r, max(tex.g, tex.b));
	COLOR = vec4(mode_color.rgb * (0.65 + 0.5 * shade), tex.a * tint.a);
}
