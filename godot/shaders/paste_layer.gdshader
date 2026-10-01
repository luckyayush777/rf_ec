shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;
// One paste layer per contact face. paste_map RGBA = dried crust, residue film, fresh paste
// thickness (normalized for display), hard glaze; gum_map R = pasty gum. Dried layers are
// divided by gpu_paste.gd's STACK_DISPLAY. Must match gpu_paste.gd's refresh() packing.
uniform sampler2D paste_map : filter_linear, repeat_disable;
uniform sampler2D gum_map : filter_linear, repeat_disable;
// Fraction of the layer (per side) that lies over the die rather than the package margin.
uniform float margin_fraction = 0.1667;
// Local drop that seats margin cells on the package, below the die's top face.
uniform float margin_drop = 0.0;
uniform float bead_height = 0.06;
// Local height of a full (normalized 1.0) dried stack.
uniform float stack_height = 0.03;
// The layer's local size and grid resolution, for smooth relief normals.
uniform vec2 layer_size = vec2(1.0);
uniform float cells = 28.0;
varying float dried;
varying float slope;

float surface_height(vec2 uv) {
	vec4 layers = textureLod(paste_map, uv, 0.0);
	return layers.b * bead_height + (layers.r + layers.a + textureLod(gum_map, uv, 0.0).r) * stack_height;
}

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
	vec4 layers = textureLod(paste_map, UV, 0.0);
	dried = layers.r + layers.a + textureLod(gum_map, UV, 0.0).r;
	VERTEX.y += layers.b * bead_height + dried * stack_height;
	if (in_margin(UV)) VERTEX.y -= margin_drop;
	// Smooth normals from the height map: ridges, torn peaks and scraped terraces catch light.
	float step_uv = 0.5 / cells;
	float dx = (surface_height(UV + vec2(step_uv, 0.0)) - surface_height(UV - vec2(step_uv, 0.0))) / (2.0 * step_uv * layer_size.x);
	float dz = (surface_height(UV + vec2(0.0, step_uv)) - surface_height(UV - vec2(0.0, step_uv))) / (2.0 * step_uv * layer_size.y);
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
	slope = 1.0 - NORMAL.y;
}

void fragment() {
	vec4 layers = texture(paste_map, UV);
	float crust = layers.r;
	float film = layers.g;
	float glaze = layers.a;
	float gum = texture(gum_map, UV).r;
	float paste = smoothstep(0.015, 0.09, layers.b);
	// Glaze: hard, darker skin crazed with fine cracks. Crust: chalky and mottled.
	// Gum: wet, glossy and dark, like toothpaste gone grey.
	float cracks = smoothstep(0.018, 0.0, abs(value_noise(UV * 26.0) - 0.5)) * step(0.45, value_noise(UV * 9.0 + 3.7));
	vec3 glaze_color = mix(vec3(0.44, 0.43, 0.4), vec3(0.34, 0.33, 0.31), value_noise(UV * 70.0));
	glaze_color = mix(glaze_color, vec3(0.16, 0.16, 0.15), cracks * 0.85);
	vec3 crust_color = mix(vec3(0.66, 0.65, 0.61), vec3(0.5, 0.49, 0.46), value_noise(UV * 90.0));
	vec3 gum_color = mix(vec3(0.33, 0.34, 0.36), vec3(0.41, 0.42, 0.44), value_noise(UV * 55.0));
	vec3 film_color = vec3(0.46, 0.47, 0.49);
	vec3 paste_color = mix(vec3(0.5, 0.52, 0.55), vec3(0.66, 0.68, 0.71), clamp(layers.b * 1.4, 0.0, 1.0));
	float gum_alpha = smoothstep(0.004, 0.03, gum);
	float crust_alpha = smoothstep(0.004, 0.04, crust);
	float glaze_alpha = smoothstep(0.003, 0.025, glaze);
	float film_alpha = smoothstep(0.02, 0.5, film) * 0.62;
	vec3 color = mix(film_color, gum_color, gum_alpha);
	color = mix(color, crust_color, crust_alpha);
	color = mix(color, glaze_color, glaze_alpha);
	// Cut slopes show the stack in bands, like a sliced cake; valleys sit in shadow.
	float band = smoothstep(0.38, 0.48, abs(fract(dried * 12.0) - 0.5));
	color *= 1.0 - 0.3 * band * smoothstep(0.08, 0.35, slope) * step(0.01, dried);
	color *= mix(0.78, 1.05, smoothstep(0.0, 0.6, dried));
	color = mix(color, paste_color, paste);
	ALBEDO = color;
	float dry_rough = mix(mix(0.72, 0.3, gum_alpha), 0.95, crust_alpha);
	ROUGHNESS = mix(mix(dry_rough, 0.55, glaze_alpha), 0.24, paste);
	METALLIC = mix(0.05 + 0.12 * gum_alpha * (1.0 - crust_alpha), 0.3, paste);
	// A thin smear lets the die show through; a thick stack is opaque.
	float dried_alpha = max(max(crust_alpha, glaze_alpha), gum_alpha) * mix(0.45, 1.0, smoothstep(0.0, 0.14, dried));
	ALPHA = max(max(dried_alpha, film_alpha), paste);
	if (ALPHA < 0.01) discard;
}
