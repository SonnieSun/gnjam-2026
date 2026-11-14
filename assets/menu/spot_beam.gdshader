// 聚光灯的可编辑光束外形，保留透明菜单背景，底部淡出避免硬切边。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 beam_color : source_color = vec3(1.0, 0.85, 0.62);
uniform float opacity : hint_range(0.0, 0.5, 0.005) = 0.085;
uniform float beam_height = 7.0;
uniform float soft_distance : hint_range(0.1, 3.0) = 1.2;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
varying float beam_progress;

void vertex() {
	beam_progress = clamp(0.5 - VERTEX.y / beam_height, 0.0, 1.0);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft_edge = smoothstep(0.0, 0.5, facing);
	float start_fade = smoothstep(0.0, 0.06, beam_progress);
	float end_fade = 1.0 - smoothstep(0.65, 1.0, beam_progress);
	float falloff = mix(1.0, 0.55, beam_progress);
	float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
	vec4 scene_position = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float distance_to_surface = VERTEX.z - scene_position.z / scene_position.w;
	float contact_fade = smoothstep(0.0, soft_distance, distance_to_surface);
	// 模型和唱片保留真实聚光灯的明暗，光束主要呈现在它们后方的空气里。
	float surface_weight = mix(1.0, 0.2, step(0.000001, depth));
	ALBEDO = beam_color;
	ALPHA = opacity * soft_edge * start_fade * end_fade * falloff * contact_fade * surface_weight;
}
