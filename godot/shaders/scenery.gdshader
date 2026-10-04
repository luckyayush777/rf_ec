shader_type spatial;
// Outdoor geometry from `assets/outdoor-scenery.glb` (terrain, plants, fence, village). Lit by
// the day cycle's sun or moon rather than the workshop lights; albedo is the painted vertex
// colour. Aerial perspective layers the view: the meadow and lake stay clear and saturated, the
// hills soften and the far range fades toward the sky haze. Village windows glow at night.
render_mode unshaded, shadows_disabled, cull_disabled;

uniform vec3 light_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 light_color : source_color = vec3(1.0);
uniform vec3 ambient_color : source_color = vec3(0.5, 0.6, 0.65);
uniform vec3 ground_color : source_color = vec3(0.2, 0.25, 0.22);
uniform vec3 haze_color : source_color = vec3(0.8, 0.86, 0.84);
// Squared falloff: little haze over the valley, most of `haze_amount` by the far range.
uniform float haze_distance = 520.0;
uniform float haze_amount = 0.72;
// 1 = flat faces turned toward the camera (built things); 0 = the exported smooth normals.
uniform float facet_strength = 0.0;
// Soft light wrap for foliage, so canopies read as rounded masses.
uniform float wrap = 0.0;
uniform float wind_strength = 0.0;
// Window glass: dark by day, warm lamplight as night falls.
uniform float glow = 0.0;
uniform float night = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.74, 0.38);
uniform vec3 glass_color : source_color = vec3(0.22, 0.27, 0.32);

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	// Only foliage sways; the base of each leaf clump moves a little less than its top.
	float sway = wind_strength * COLOR.a;
	VERTEX.x += sin(TIME * 0.85 + VERTEX.z * 0.23) * sway;
	VERTEX.z += sin(TIME * 0.65 + VERTEX.x * 0.17) * sway * 0.5;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 to_eye = CAMERA_POSITION_WORLD - world_position;
	vec3 n = normalize(world_normal);
	vec3 face = normalize(cross(dFdx(world_position), dFdy(world_position)));
	if (dot(face, to_eye) < 0.0) face = -face;
	n = normalize(mix(n, face, facet_strength));
	// Soft two-tone light: warm sunlit faces, sky-tinted shadow sides.
	float diffuse = clamp((dot(n, light_dir) + wrap) / (1.0 + wrap), 0.0, 1.0);
	diffuse = smoothstep(0.0, 0.85, diffuse);
	vec3 ambient = mix(ground_color, ambient_color, n.y * 0.5 + 0.5) * 0.75;
	vec3 color = COLOR.rgb * (ambient + light_color * diffuse * 0.9);
	color = mix(color, mix(glass_color * (ambient + light_color * 0.3), glow_color * 1.6, smoothstep(0.15, 0.6, night)), glow);
	float haze = 1.0 - exp(-pow(length(to_eye) / haze_distance, 2.0));
	color = mix(color, haze_color, haze * haze_amount * (1.0 - glow * night * 0.6));
	ALBEDO = color;
}
