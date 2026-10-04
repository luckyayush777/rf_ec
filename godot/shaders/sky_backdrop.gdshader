shader_type spatial;
// The view out of the window beyond the near scenery, drawn on the inside of a dome by view
// direction (so it sits at infinity without a long camera far plane): sky gradient, sun, moon,
// stars and puffy cumulus, then a skyline of three distant ranges beyond the valley, the nearest
// snow-tipped. Azimuth 0 looks straight out of the window (+X).
render_mode unshaded, cull_front, shadows_disabled;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
// Direction and colour of whichever of sun or moon lights the landscape.
uniform vec3 light_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 light_color : source_color = vec3(1.0);
uniform vec3 zenith_color : source_color = vec3(0.3, 0.6, 0.75);
uniform vec3 horizon_color : source_color = vec3(0.9, 0.93, 0.88);
uniform vec3 haze_color : source_color = vec3(0.8, 0.86, 0.84);
uniform vec3 ambient_color : source_color = vec3(0.5, 0.6, 0.65);
uniform vec3 rock_color : source_color = vec3(0.5, 0.56, 0.66);
uniform vec3 valley_color : source_color = vec3(0.3, 0.42, 0.4);
uniform float night = 0.0;
uniform float sun_visible = 1.0;
uniform float cloud_shift = 0.0;

varying vec3 world_position;

float hash1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash1(dot(i, vec2(1.0, 57.0)));
	float b = hash1(dot(i + vec2(1.0, 0.0), vec2(1.0, 57.0)));
	float c = hash1(dot(i + vec2(0.0, 1.0), vec2(1.0, 57.0)));
	float d = hash1(dot(i + vec2(1.0, 1.0), vec2(1.0, 57.0)));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += noise2(p) * amp;
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return sum;
}
// Distance to the nearest jittered cell point: 1 - worley gives round billows.
float worley(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			float h = dot(i + g, vec2(1.0, 57.0));
			vec2 o = vec2(hash1(h), hash1(h + 17.3));
			best = min(best, length(g + o - f));
		}
	}
	return best;
}
// Cumulus: broad patches of sky hold clusters of round billows.
float cloud_density(vec2 uv) {
	float patch = smoothstep(0.42, 0.66, fbm(uv * 0.32 + vec2(3.1, 7.4)));
	float billows = (1.0 - worley(uv * 0.9)) * 0.62 + (1.0 - worley(uv * 2.3 + 5.0)) * 0.30 + fbm(uv * 3.0) * 0.18;
	return patch * billows;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Lambert from the sun or moon plus a sky/valley ambient, as for the near scenery.
vec3 lit(vec3 albedo, vec3 n) {
	float lambert = max(dot(n, light_dir), 0.0);
	vec3 ambient = mix(valley_color * 0.6, ambient_color, n.y * 0.5 + 0.5);
	return albedo * (ambient + light_color * lambert);
}

// Skyline: jagged distant summits for layer L (0 nearest), smooth massifs under sharper peaks.
float ridge_height(float az, float layer) {
	float p = az * (9.0 + layer * 4.0) + layer * 23.0;
	float cell = floor(p);
	float f = fract(p);
	// Each cell holds one summit: a sharp triangle with an uneven shoulder.
	float apex = 0.3 + 0.4 * hash1(cell + layer * 41.0);
	float tent = f < apex ? f / apex : (1.0 - f) / (1.0 - apex);
	float peak = pow(tent, 1.6) * (0.4 + 0.6 * hash1(cell + 7.0 + layer * 13.0));
	float broad = az * 2.0 + layer * 5.0;
	float massif = mix(hash1(floor(broad) + 81.0 + layer), hash1(floor(broad) + 82.0 + layer), smoothstep(0.0, 1.0, fract(broad)));
	float wobble = (fbm(vec2(az * 60.0, layer * 3.0)) - 0.5) * 0.006;
	return 0.012 + (0.03 + 0.05 * massif) * (1.0 - layer * 0.22) + 0.05 * peak * (1.0 - layer * 0.3) + wobble;
}

void fragment() {
	vec3 d = normalize(world_position - CAMERA_POSITION_WORLD);
	float e = asin(clamp(d.y, -1.0, 1.0));
	float az = atan(d.z, d.x);
	float up = clamp(d.y, 0.0, 1.0);

	// Sky.
	vec3 sky = mix(horizon_color, zenith_color, pow(up, 0.45));
	float sd = max(dot(d, sun_dir), 0.0);
	sky += light_color * sun_visible * (pow(sd, 6.0) * 0.18 + pow(sd, 48.0) * 0.4) * (1.0 - night);
	sky = mix(sky, vec3(1.6, 1.45, 1.2), smoothstep(0.99955, 0.99975, sd) * sun_visible);
	float md = max(dot(d, moon_dir), 0.0);
	sky += vec3(0.6, 0.65, 0.8) * pow(md, 80.0) * 0.25 * night;
	sky = mix(sky, vec3(0.92, 0.94, 1.0), smoothstep(0.99965, 0.9998, md) * night);
	// Stars: one candidate per direction cell, drawn as a small dot.
	vec3 cell = floor(d * 240.0);
	vec3 centre = (cell + vec3(hash3(cell), hash3(cell + 3.1), hash3(cell + 7.7))) / 240.0;
	float star = step(0.985, hash3(cell + 11.0)) * smoothstep(0.0022, 0.0007, distance(d, centre));
	sky += vec3(0.9, 0.92, 1.0) * star * night * smoothstep(0.02, 0.2, d.y) * (0.5 + hash3(cell + 5.0));
	// Puffy cumulus on a flat layer: bright crowns, soft blue-grey undersides. A sample a
	// little higher up the sky stands in for the cloud above: where it is denser, this is a base.
	vec2 drift = vec2(cloud_shift * 0.6, cloud_shift * 0.15);
	float density = cloud_density(d.xz / (d.y + 0.07) * 1.4 + drift);
	vec3 above = normalize(d + vec3(0.0, 0.035, 0.0));
	float density_above = cloud_density(above.xz / (above.y + 0.07) * 1.4 + drift);
	float cover = smoothstep(0.30, 0.36, density) * smoothstep(0.015, 0.12, d.y);
	float crown = smoothstep(-0.08, 0.10, density - density_above);
	vec3 cloud_day = mix(mix(zenith_color, horizon_color, 0.55) * 0.92, vec3(1.0, 0.99, 0.96) + light_color * 0.08, crown);
	vec3 cloud_night = mix(vec3(0.08, 0.10, 0.16), vec3(0.18, 0.21, 0.30), crown);
	vec3 cloud = mix(cloud_day, cloud_night, night);
	// Clouds low on the horizon sink into the haze.
	cloud = mix(cloud, horizon_color, smoothstep(0.25, 0.02, d.y) * 0.45);
	sky = mix(sky, cloud, cover);

	vec3 color = sky;
	// Below the horizon only haze shows (the landscape geometry covers it).
	if (e < 0.0) color = mix(haze_color, horizon_color, 0.4);
	// The skyline: three ranges beyond the valley, farthest first, each fading closer to the sky.
	// The nearest catches snow on its upper faces; village-less, they stay dark at night.
	for (int L = 2; L >= 0; L--) {
		float fl = float(L);
		float ridge = ridge_height(az, fl);
		if (e >= ridge) continue;
		float slope = (ridge_height(az + 0.0015, fl) - ridge) / 0.0015;
		vec3 facing = -vec3(cos(az), 0.0, sin(az));
		vec3 across = vec3(-sin(az), 0.0, cos(az));
		vec3 n = normalize(facing + across * clamp(slope * 0.8, -1.2, 1.2) + vec3(0.0, 0.5, 0.0));
		float snow = smoothstep(0.035, 0.012, ridge - e) * step(0.07, ridge) * (1.0 - fl * 0.35);
		vec3 albedo = mix(rock_color, vec3(0.93, 0.95, 1.0), snow);
		color = mix(lit(albedo, n), haze_color, 0.45 + fl * 0.17);
		color = mix(color, haze_color, (1.0 - smoothstep(-0.02, 0.03, e)) * 0.6);
	}
	ALBEDO = color;
}
