shader_type spatial;
// Lit, felt-like dust. The mask stores thickness: thin film reads as a grey haze, thick
// deposits as opaque, lighter, lumpy felt with a soft sheen at grazing angles.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D dust_map : filter_linear, repeat_disable;
uniform sampler2D dust_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 dust_min;
uniform vec3 dust_size;
// World units per mesh-local unit, so clumps keep one physical size on every part.
uniform float unit_scale = 0.25;

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
	vec2 w;
	if (n.x > n.y && n.x > n.z) {
		face = dust_normal.x < 0.0 ? 1.0 : 0.0;
		q = p.zy;
		w = dust_position.zy;
	} else if (n.y > n.z) {
		face = dust_normal.y < 0.0 ? 3.0 : 2.0;
		q = p.xz;
		w = dust_position.xz;
	} else {
		face = dust_normal.z < 0.0 ? 5.0 : 4.0;
		q = p.xy;
		w = dust_position.xy;
	}
	w *= unit_scale;
	float clumps = texture(dust_noise, w * 4.0).r;
	float fibres = texture(dust_noise, w * 22.0 + vec2(0.37, 0.71)).r;
	// Warp the lookup by a texel so patch borders break up like settled cloud, not squares.
	vec2 warp = (vec2(clumps, texture(dust_noise, w * 7.0 + vec2(0.53, 0.19)).r) - 0.5) * 1.8;
	vec2 tile = clamp(q * 62.0 + warp, vec2(0.0), vec2(62.0));
	vec2 texel = tile + vec2(1.0) + vec2(mod(face, 3.0), floor(face / 3.0)) * 64.0;
	vec2 uv = texel / vec2(192.0, 128.0);
	float dust = texture(dust_map, uv).r;
	if (dust < 0.002) discard;
	// Any dust left in this texel, however thin, keeps a findable minimum opacity.
	bool dusty = texelFetch(dust_map, ivec2(texel), 0).r > 0.0;
	float body = clamp(dust * (0.6 + 0.8 * clumps) * 1.4 + (fibres - 0.5) * 0.18, 0.0, 1.0);
	// Felt relief: bump the lighting normal by the dust height (screen-space derivative bump).
	float height = body * 0.012 * (0.7 + 0.6 * fibres);
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
	vec3 film = vec3(0.27, 0.26, 0.24);
	vec3 felt = vec3(0.52, 0.49, 0.44);
	ALBEDO = mix(film, felt, smoothstep(0.1, 0.85, body)) * (0.75 + 0.5 * fibres);
	ROUGHNESS = 1.0;
	RIM = 0.35 * smoothstep(0.15, 0.8, body);
	RIM_TINT = 0.8;
	// Feather the filtered fringe so patch edges fade like settled cloud, but keep almost-clean
	// texels findable until their mask reaches zero.
	float alpha = mix(0.2, 0.95, smoothstep(0.1, 0.85, body)) * (0.85 + 0.3 * fibres) * smoothstep(0.0, 0.12, dust);
	ALPHA = clamp(dusty ? max(alpha, 0.16) : alpha, 0.0, 1.0);
}
