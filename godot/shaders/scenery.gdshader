shader_type spatial;
// Outdoor geometry (yard, parapet and flat-shaded mountains). Lit by the day cycle's sun or
// moon rather than the workshop lights, and hazed toward the backdrop with distance. Albedo
// comes from vertex colours.
render_mode unshaded, shadows_disabled, cull_disabled;

uniform vec3 light_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 light_color : source_color = vec3(1.0);
uniform vec3 ambient_color : source_color = vec3(0.5, 0.6, 0.65);
uniform vec3 ground_color : source_color = vec3(0.2, 0.25, 0.22);
uniform vec3 haze_color : source_color = vec3(0.8, 0.86, 0.84);
uniform float haze_distance = 260.0;
uniform float haze_amount = 0.7;
uniform float valley_mist = 0.8;
uniform float detail_strength = 1.0;
uniform float facet_strength = 0.0;

varying vec3 world_position;
varying vec3 world_normal;

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
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	// The mountains retain small facets while softened vertex normals round the edges,
	// like the GPU's bevelled component shapes. The yard keeps its existing shading.
	vec3 face_normal = normalize(cross(dFdx(world_position), dFdy(world_position)));
	if (dot(face_normal, n) < 0.0) face_normal = -face_normal;
	n = normalize(mix(n, face_normal, facet_strength));
	float grain = 0.88 + 0.24 * noise2(world_position.xz * 0.35 + world_position.y * 0.2);
	vec3 albedo = COLOR.rgb * mix(1.0, grain, detail_strength);
	float lambert = max(dot(n, light_dir), 0.0);
	vec3 ambient = mix(ground_color, ambient_color, n.y * 0.5 + 0.5);
	vec3 color = albedo * (ambient + light_color * lambert);
	float distance_to_eye = length(world_position - CAMERA_POSITION_WORLD);
	color = mix(color, haze_color, (1.0 - exp(-distance_to_eye / haze_distance)) * haze_amount);
	// Mountain foothills recede into the valley mist below the yard.
	color = mix(color, haze_color, (1.0 - smoothstep(-65.0, -12.0, world_position.y)) * valley_mist);
	ALBEDO = color;
}
