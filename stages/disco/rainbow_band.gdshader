shader_type spatial;
// 背景里斜着的一道彩虹：一张很大的平面，沿宽度方向排开七色，两边柔和地淡掉，带一点颗粒。
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// 整体多亮（脚本淡入淡出、跟拍子亮一下都改这个）
uniform float strength = 1.0;
// 颜色多鲜
uniform float saturation : hint_range(0.0, 1.0) = 0.85;
// 两边淡出的宽度（占彩虹宽度的几成）
uniform float edge_soft : hint_range(0.01, 0.5) = 0.22;
// 颗粒感
uniform float grain : hint_range(0.0, 0.5) = 0.08;
// 颜色沿彩虹流动的速度（跟拍数走）
uniform float beat = 0.0;
uniform float flow = 0.02;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	// UV.y 横跨彩虹的宽度：红在一边，紫在另一边
	float t = UV.y;
	vec3 col = hue(t * 0.78 + beat * flow);
	col = mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, saturation);
	float band = smoothstep(0.0, edge_soft, t) * smoothstep(1.0, 1.0 - edge_soft, t);
	float ends = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x);
	float g = 1.0 - grain + grain * 2.0 * hash(floor(UV * vec2(900.0, 160.0)));
	ALBEDO = col * band * ends * g * strength;
}
