shader_type spatial;
// The valley lake: deep teal water that mirrors the sky more at grazing angles, slow ripples and
// a sun glint, hazed with distance like the rest of the outdoor scenery. Lit by the day cycle.
render_mode unshaded, shadows_disabled, cull_disabled;

uniform vec3 light_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 light_color : source_color = vec3(1.0);
uniform vec3 ambient_color : source_color = vec3(0.5, 0.6, 0.65);
uniform vec3 haze_color : source_color = vec3(0.8, 0.86, 0.84);
uniform vec3 zenith_color : source_color = vec3(0.3, 0.6, 0.75);
uniform vec3 horizon_color : source_color = vec3(0.9, 0.93, 0.88);
uniform vec3 deep_color : source_color = vec3(0.12, 0.33, 0.38);
uniform float night = 0.0;
uniform float haze_distance = 520.0;
uniform float haze_amount = 0.72;

varying vec3 world_position;

float hash1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(dot(i, vec2(1.0, 57.0))), hash1(dot(i + vec2(1.0, 0.0), vec2(1.0, 57.0))), u.x),
		mix(hash1(dot(i + vec2(0.0, 1.0), vec2(1.0, 57.0))), hash1(dot(i + vec2(1.0, 1.0), vec2(1.0, 57.0))), u.x), u.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 to_eye = CAMERA_POSITION_WORLD - world_position;
	vec3 view = normalize(to_eye);
	vec2 p = world_position.xz;
	// Two drifting ripple layers, stretched across the view like wind lines on a lake.
	float a = noise2(p * vec2(0.25, 0.9) + vec2(TIME * 0.12, TIME * 0.05)) - 0.5;
	float b = noise2(p * vec2(0.6, 1.8) - vec2(TIME * 0.08, TIME * 0.15) + 9.0) - 0.5;
	vec3 n = normalize(vec3(a * 0.10 + b * 0.05, 1.0, b * 0.14 + a * 0.04));
	float fresnel = pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 3.0);
	vec3 water = deep_color * (ambient_color * 0.8 + light_color * 0.35);
	vec3 sky = mix(horizon_color, zenith_color, 0.35);
	vec3 color = mix(water, sky, 0.25 + 0.6 * fresnel);
	float glint = pow(max(dot(reflect(-view, n), light_dir), 0.0), 180.0);
	color += light_color * glint * 1.5 * (1.0 - night);
	float haze = 1.0 - exp(-pow(length(to_eye) / haze_distance, 2.0));
	ALBEDO = mix(color, haze_color, haze * haze_amount);
}
