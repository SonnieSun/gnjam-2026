shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// 仅在灯带内外边缘各延伸几毫米，形成柔和的淡灰光晕。
uniform float quad_size = 0.414;
uniform float inner_radius = 0.16173;
uniform float outer_radius = 0.19172;
uniform float halo_width = 0.006;
uniform vec4 halo_color : source_color = vec4(0.65, 0.62, 0.68, 0.20);

void fragment() {
	float radius = length((UV - vec2(0.5)) * quad_size);
	float edge_distance = max(max(inner_radius - radius, radius - outer_radius), 0.0);
	float outside_band = 1.0 - step(inner_radius, radius) * (1.0 - step(outer_radius, radius));
	float falloff = 1.0 - smoothstep(0.0, halo_width, edge_distance);
	ALBEDO = halo_color.rgb;
	ALPHA = halo_color.a * falloff * falloff * outside_band;
}
