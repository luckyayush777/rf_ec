shader_type spatial;
// Old grease and dust on the fan shaft. gunk_map columns wrap around the shaft and rows run
// along it from top to bottom; gpu_bearing.gd maps hit points with the same convention.
uniform sampler2D gunk_map : filter_linear, repeat_enable;
uniform float half_length = 0.055;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float along = clamp((half_length - local_position.y) / (2.0 * half_length), 0.02, 0.98);
	vec2 cell = vec2(atan(local_position.z, local_position.x) / TAU + 0.5, along);
	float gunk = texture(gunk_map, cell).r;
	float coat = smoothstep(0.02, 0.35, gunk);
	vec3 grime = mix(vec3(0.24, 0.16, 0.07), vec3(0.08, 0.06, 0.04), gunk);
	ALBEDO = mix(vec3(0.74, 0.76, 0.78), grime, coat);
	METALLIC = mix(0.95, 0.0, coat);
	ROUGHNESS = mix(0.18, 0.85, coat);
}
