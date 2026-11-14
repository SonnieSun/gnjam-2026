// 选中光柱：从碟片中心往外发散的扇形光，叠加发光。
// 网格是一张平放的 PlaneMesh，节点原点放在碟片中心。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.48, 0.16);
uniform vec3 core_color : source_color = vec3(1.0, 0.8, 0.55);
uniform float intensity = 0.85;
// 扇形半张角（度）
uniform float half_angle_deg = 17.0;
// 边缘软化（0~1，占扇形宽度的比例）
uniform float edge_softness = 0.45;
// 中间亮芯的宽度（0~1）
uniform float core_width = 0.25;
// 光到多远完全消失
uniform float beam_length = 22.0;
uniform float falloff = 0.9;
// 离中心多近开始出现（避免中心一个亮点）
uniform float start_radius = 1.5;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float r = length(local_pos.xz);
	float ang = degrees(atan(local_pos.x, -local_pos.z));
	float t = abs(ang) / half_angle_deg;
	float edge = 1.0 - smoothstep(1.0 - edge_softness, 1.0, t);
	float core = exp(-(t * t) / max(core_width * core_width, 0.0001));
	float radial = smoothstep(0.0, start_radius, r) * pow(1.0 - clamp(r / beam_length, 0.0, 1.0), falloff);
	vec3 c = mix(color, core_color, core * 0.6);
	float k = (edge * 0.55 + core * 0.45) * radial;
	ALBEDO = c * intensity * k;
	ALPHA = clamp(k, 0.0, 1.0);
}
