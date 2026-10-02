shader_type canvas_item;
// The jeweller's loupe over the focus view: a round field of view, a dark barrel around it,
// a soft rim and a faint warm fringe at the edge of the glass.

uniform vec2 view_size = vec2(1280.0, 720.0);
uniform float radius = 0.47;

void fragment() {
	vec2 p = (UV - 0.5) * view_size / min(view_size.x, view_size.y);
	float d = length(p);
	float barrel = smoothstep(radius - 0.004, radius + 0.006, d);
	float rim = smoothstep(radius - 0.05, radius, d) * (1.0 - barrel);
	vec3 fringe = vec3(0.35, 0.22, 0.05) * rim;
	COLOR = vec4(mix(fringe, vec3(0.015, 0.016, 0.018), barrel), max(barrel * 0.96, rim * 0.55));
}
