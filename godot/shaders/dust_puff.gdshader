shader_type spatial;
// Camera-facing dust puffs and flakes drawn from one MultiMesh; each instance's custom data
// carries its tint and fade. Unlit and unsorted to stay cheap.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D puff : source_color, filter_linear_mipmap;

varying vec4 tint;

void vertex() {
	tint = INSTANCE_CUSTOM;
	float scale = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale, INV_VIEW_MATRIX[1] * scale, INV_VIEW_MATRIX[2] * scale, MODEL_MATRIX[3]);
}

void fragment() {
	vec4 shape = texture(puff, UV);
	ALBEDO = tint.rgb * shape.rgb;
	ALPHA = tint.a * shape.a;
}
