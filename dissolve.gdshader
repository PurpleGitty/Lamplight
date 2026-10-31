shader_type canvas_item;

uniform sampler2D noise_texture : filter_nearest;
// 0 = fully visible, 1.1 = fully gone
uniform float dissolve_value : hint_range(0.0, 1.1) = 0.0;
// 0 = normal colours, 1 = solid white silhouette
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// Size of the dissolve's blocks, in sprite pixels
uniform float pixel_size = 2.0;
// Higher = finer, more scattered breakup (the noise texture tiles seamlessly)
uniform float noise_scale = 1.0;
uniform vec4 glow_color : source_color = vec4(1.0);

varying vec4 tint; // modulate / self_modulate (in fragment(), COLOR already has the texture baked in)

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Sample the noise in chunky blocks so the sprite breaks apart pixel by pixel
	vec2 texels = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 cell = (floor(UV * texels / pixel_size) + 0.5) * pixel_size / texels;
	float noise = texture(noise_texture, fract(cell * noise_scale)).r;

	float visible = step(dissolve_value - 0.08, noise);
	float edge = visible - step(dissolve_value, noise); // thin rim right before a block vanishes

	vec3 rgb = mix(tex.rgb, vec3(1.0), flash);
	rgb = mix(rgb, glow_color.rgb, edge);
	// Multiply by the tint so modulate (like the red hurt flash) still works
	COLOR = vec4(rgb, tex.a * visible) * tint;
}
