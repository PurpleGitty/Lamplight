shader_type canvas_item;
render_mode unshaded;
// A reflection on the floor: what's drawn into the group, see-through and fading out the
// further it is below the ground line.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength = 0.35;
uniform float ground_y = 0.0; // the ground, in screen pixels
uniform float fade_length = 120.0; // screen pixels until it's gone

void fragment() {
	vec4 drawn = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (drawn.a > 0.0001) {
		drawn.rgb /= drawn.a;
	}
	float below = clamp((FRAGCOORD.y - ground_y) / fade_length, 0.0, 1.0);
	COLOR *= vec4(drawn.rgb, drawn.a * strength * (1.0 - below));
}
