shader_type spatial;
// 从上往下的光柱：上面细、下面粗，中间亮、边缘和顶上渐隐，叠加发光
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float strength = 0.35;
// 越大边缘越虚
uniform float edge_soft = 1.6;

void fragment() {
	// CylinderMesh 的 UV.y：0 = 顶，1 = 底
	float along = smoothstep(0.0, 0.7, UV.y) * (1.0 - smoothstep(0.92, 1.0, UV.y) * 0.6);
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), edge_soft);
	ALBEDO = beam_color.rgb * strength * along * edge;
}
