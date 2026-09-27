shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;
// One paste layer per contact face. R = dried crust, G = residue film, B = fresh paste
// thickness (normalized for display). Must match gpu_paste.gd's texture packing.
uniform sampler2D paste_map : filter_linear, repeat_disable;
// Fraction of the layer (per side) that lies over the die rather than the package margin.
uniform float margin_fraction = 0.1667;
// Local drop that seats margin cells on the package, below the die's top face.
uniform float margin_drop = 0.0;
uniform float bead_height = 0.06;
varying float thickness;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

bool in_margin(vec2 uv) {
	return uv.x < margin_fraction || uv.x > 1.0 - margin_fraction || uv.y < margin_fraction || uv.y > 1.0 - margin_fraction;
}

void vertex() {
	thickness = textureLod(paste_map, UV, 0.0).b;
	VERTEX.y += thickness * bead_height;
	if (in_margin(UV)) VERTEX.y -= margin_drop;
}

void fragment() {
	vec4 layers = texture(paste_map, UV);
	float crust = layers.r;
	float film = layers.g;
	float paste = smoothstep(0.015, 0.09, layers.b);
	// Dried compound: chalky, cracked and mottled.
	float cracks = smoothstep(0.035, 0.0, abs(value_noise(UV * 38.0) - 0.5));
	vec3 crust_color = mix(vec3(0.74, 0.73, 0.68), vec3(0.52, 0.51, 0.47), value_noise(UV * 90.0));
	crust_color = mix(crust_color, vec3(0.2, 0.2, 0.19), cracks * 0.8);
	vec3 film_color = vec3(0.46, 0.47, 0.49);
	vec3 paste_color = mix(vec3(0.5, 0.52, 0.55), vec3(0.66, 0.68, 0.71), clamp(layers.b * 1.4, 0.0, 1.0));
	float crust_alpha = smoothstep(0.03, 0.25, crust);
	float film_alpha = smoothstep(0.02, 0.5, film) * 0.62;
	vec3 color = mix(film_color, crust_color, crust_alpha);
	color = mix(color, paste_color, paste);
	ALBEDO = color;
	ROUGHNESS = mix(mix(0.72, 0.95, crust_alpha), 0.24, paste);
	METALLIC = mix(0.05, 0.3, paste);
	ALPHA = max(max(crust_alpha, film_alpha), paste);
	if (ALPHA < 0.01) discard;
}
