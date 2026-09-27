shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	// Only the room behind this layer is sampled; the close-up renders afterwards.
	vec3 blurred = textureLod(scene_color, SCREEN_UV, 4.0).rgb;
	COLOR = vec4(blurred * 0.82, 1.0);
}
