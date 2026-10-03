shader_type spatial;
// The view out of the window beyond the near scenery, drawn on the inside of a dome by view
// direction (so it sits at infinity without a long camera far plane): sky gradient, sun, moon,
// stars and clouds, then connected distant ridgelines above valley mist, with village lights
// on the valley floor at night. Azimuth 0 looks straight out of the window (+X).
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
uniform vec3 rock_color : source_color = vec3(0.52, 0.62, 0.62);
uniform vec3 leaf_color : source_color = vec3(0.24, 0.38, 0.32);
uniform vec3 valley_color : source_color = vec3(0.24, 0.42, 0.4);
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

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Lambert from the sun or moon plus a sky/valley ambient, as for the near scenery.
vec3 lit(vec3 albedo, vec3 n) {
	float lambert = max(dot(n, light_dir), 0.0);
	vec3 ambient = mix(valley_color * 0.6, ambient_color, n.y * 0.5 + 0.5);
	return albedo * (ambient + light_color * lambert);
}

// Piecewise linear ridges: uneven summits joined by saddles, with a slower underlying
// massif. The distant ranges are silhouettes; all nearer rock faces are actual triangles.
float ridge_height(float az, float layer) {
	float p = az * (7.0 + layer * 2.0) + layer * 19.0;
	float cell = floor(p);
	float peaks = mix(hash1(cell + layer * 31.0), hash1(cell + 1.0 + layer * 31.0), fract(p));
	float broad = az * 2.5 + layer * 7.0;
	float shoulder = mix(hash1(floor(broad) + 81.0), hash1(floor(broad) + 82.0), fract(broad));
	return 0.035 + 0.10 * shoulder + 0.085 * peaks - layer * 0.025;
}

void fragment() {
	vec3 d = normalize(world_position - CAMERA_POSITION_WORLD);
	float e = asin(clamp(d.y, -1.0, 1.0));
	float az = atan(d.z, d.x);
	float up = clamp(d.y, 0.0, 1.0);

	// Sky.
	vec3 sky = mix(horizon_color, zenith_color, pow(up, 0.5));
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
	// Soft clouds on a flat layer, lit warm by day and dark grey-blue by night.
	vec2 layer = d.xz / (d.y + 0.12);
	float cloud = smoothstep(0.52, 0.78, fbm(layer * 1.3 + vec2(cloud_shift, 0.0))) * smoothstep(0.02, 0.25, d.y);
	vec3 cloud_lit = mix(horizon_color * 1.05 + light_color * 0.15, vec3(0.16, 0.19, 0.27), night);
	sky = mix(sky, cloud_lit, cloud * 0.7);

	vec3 color = sky;
	// The valley floor far below: forest under drifting mist; village lights come on at night.
	if (e < 0.0) {
		float depth = smoothstep(0.0, -0.25, e);
		vec3 forest = lit(valley_color * (0.6 + 0.8 * fbm(vec2(az * 45.0, e * 120.0))), vec3(0.0, 1.0, 0.0));
		vec3 ground = mix(haze_color, forest, 0.3 + 0.55 * depth);
		float mist = smoothstep(0.4, 0.75, fbm(vec2(az * 3.5 + cloud_shift * 0.3, e * 30.0)));
		color = mix(ground, mix(haze_color, vec3(1.0), 0.2 * (1.0 - night)), mist * 0.75);
		vec2 lamp_cell = floor(vec2(az * 260.0, e * 260.0));
		float lamp = step(0.93, hash1(dot(lamp_cell, vec2(1.0, 113.0)))) * step(abs(az + 0.15), 0.55) * step(-0.24, e) * step(e, -0.07);
		color += vec3(1.0, 0.72, 0.38) * lamp * night * 1.4;
	}
	// Two subdued, connected ranges behind the geometric mountains.
	for (int L = 1; L >= 0; L--) {
		float fl = float(L);
		float ridge = ridge_height(az, fl);
		if (e >= ridge) continue;
		float slope = (ridge_height(az + 0.002, fl) - ridge) / 0.002;
		vec3 facing = -vec3(cos(az), 0.0, sin(az));
		vec3 across = vec3(-sin(az), 0.0, cos(az));
		vec3 n = normalize(facing + across * clamp(slope, -0.7, 0.7) + vec3(0.0, 0.65, 0.0));
		vec3 mountain = lit(mix(leaf_color, rock_color, 0.7), n);
		float haze = mix(0.62, 0.82, fl);
		color = mix(mountain, haze_color, haze);
		float mist = 1.0 - smoothstep(-0.10, 0.015, e);
		color = mix(color, haze_color, mist * 0.5);
	}
	ALBEDO = color;
}
