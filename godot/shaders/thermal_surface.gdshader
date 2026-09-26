shader_type spatial;
render_mode unshaded;
uniform float temperature = 24.0;
vec3 palette(float t) {
	if (t < 0.25) return mix(vec3(0.025,0.015,0.14), vec3(0.28,0.04,0.55), t * 4.0);
	if (t < 0.50) return mix(vec3(0.28,0.04,0.55), vec3(0.92,0.12,0.10), (t-0.25)*4.0);
	if (t < 0.75) return mix(vec3(0.92,0.12,0.10), vec3(1.0,0.72,0.08), (t-0.50)*4.0);
	return mix(vec3(1.0,0.72,0.08), vec3(1.0,0.98,0.82), (t-0.75)*4.0);
}
void fragment() {
	ALBEDO = palette(clamp((temperature - 20.0) / 80.0, 0.0, 1.0));
}
