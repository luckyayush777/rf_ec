shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D dust_map : filter_nearest, repeat_disable;
uniform vec3 dust_min;
uniform vec3 dust_size;

varying vec3 dust_position;
varying vec3 dust_normal;

void vertex() {
	dust_position = VERTEX;
	dust_normal = NORMAL;
}

void fragment() {
	vec3 p = clamp((dust_position - dust_min) / dust_size, vec3(0.0), vec3(1.0));
	vec3 n = abs(dust_normal);
	float face;
	vec2 q;
	if (n.x > n.y && n.x > n.z) {
		face = dust_normal.x < 0.0 ? 1.0 : 0.0;
		q = p.zy;
	} else if (n.y > n.z) {
		face = dust_normal.y < 0.0 ? 3.0 : 2.0;
		q = p.xz;
	} else {
		face = dust_normal.z < 0.0 ? 5.0 : 4.0;
		q = p.xy;
	}
	vec2 uv = (q * 46.0 + vec2(1.0) + vec2(mod(face, 3.0), floor(face / 3.0)) * 48.0) / vec2(144.0, 96.0);
	float dust = texture(dust_map, uv).r;
	if (dust < 0.002) discard;
	float grain = fract(sin(dot(floor(dust_position * 260.0), vec3(12.9898, 78.233, 43.71))) * 43758.5453);
	ALBEDO = vec3(0.88, 0.53, 0.17) * (0.85 + grain * 0.3);
	// Keep almost-clean pixels findable until their mask reaches zero.
	ALPHA = max(sqrt(dust) * 0.88, 0.34);
}
