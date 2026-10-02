shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
// Monochrome phosphor tube for the shop computer. The page bulges like curved glass, glows,
// shows scanlines, a slow refresh band and a darkened rim. tube_to_page must stay identical
// to shop_computer.gd so clicks land where the page is seen.

uniform sampler2D page : source_color, filter_linear, repeat_disable;
uniform float curvature = 0.08;
uniform vec2 page_size = vec2(800.0, 600.0);
uniform float scanline_strength = 0.34;
uniform float glow = 0.6;
uniform vec3 glass = vec3(0.02, 0.035, 0.025);

vec2 tube_to_page(vec2 uv) {
	vec2 p = uv * 2.0 - 1.0;
	p *= (1.0 + curvature * dot(p, p)) / (1.0 + curvature);
	return p * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = tube_to_page(UV);
	vec2 edge = min(uv, 1.0 - uv);
	float inside = smoothstep(0.0, 0.008, min(edge.x, edge.y));
	vec2 texel = 1.0 / page_size;
	vec3 colour = texture(page, uv).rgb;
	// Phosphor bloom: two rings of taps around the pixel.
	vec3 halo = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.7853982;
		vec2 dir = vec2(cos(angle), sin(angle)) * texel;
		halo += texture(page, uv + dir * 2.0).rgb + texture(page, uv + dir * 5.0).rgb * 0.6;
	}
	colour += halo / 12.8 * glow;
	// One scanline per two page rows, faded where it would alias from across the room.
	float rows = uv.y * page_size.y * 0.5;
	float fade = clamp(1.0 - fwidth(rows) * 1.2, 0.0, 1.0);
	colour *= 1.0 - scanline_strength * fade * (0.5 - 0.5 * cos(rows * 6.2831853));
	// A faint refresh band rolls down the tube; the beam flickers very slightly.
	float band = exp(-pow((fract(TIME * 0.12) * 1.3 - 0.15 - uv.y) * 9.0, 2.0));
	colour *= (1.0 + 0.06 * band) * (0.985 + 0.015 * sin(TIME * 120.0));
	colour *= pow(clamp(16.0 * uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y), 0.0, 1.0), 0.2);
	vec3 tube = mix(glass * 0.4, glass + colour, inside);
	// Soft room reflection across the upper glass.
	float sheen = smoothstep(0.7, 0.0, length((UV - vec2(0.28, 0.18)) * vec2(1.0, 1.7))) * 0.045;
	ALBEDO = tube + sheen;
}
