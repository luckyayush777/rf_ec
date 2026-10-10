shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Build view's lot grid: thin world-space lines every `spacing` units (1 m) over a faint tint,
// drawn just above the floors so walls and equipment cover it. The plane's extent is the lot.

uniform vec4 line_color : source_color = vec4(0.6, 0.88, 1.0, 0.22);
uniform vec4 fill_color : source_color = vec4(0.35, 0.6, 0.8, 0.05);
uniform float spacing = 5.0;
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = world.xz / spacing;
	vec2 width = fwidth(cell);
	vec2 distance_to_line = abs(fract(cell - 0.5) - 0.5) / width;
	float line = 1.0 - min(min(distance_to_line.x, distance_to_line.y), 1.0);
	ALBEDO = mix(fill_color.rgb, line_color.rgb, line);
	ALPHA = mix(fill_color.a, line_color.a, line);
}
