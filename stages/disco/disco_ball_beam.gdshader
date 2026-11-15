shader_type spatial;
// 灯球打到地上的彩色光束：从灯球出发越走越粗、越走越淡，叠加发光。
// 每根光束的颜色和亮度按实例改（脚本每帧设 beam_color / strength），所以所有光束共用一份材质。
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform vec4 beam_color : source_color = vec4(1.0);
instance uniform float strength = 0.0;
// 越大边缘越虚
uniform float edge_soft = 1.4;
// 光束里飘的“灰尘”条纹有多明显
uniform float dust = 0.35;

void fragment() {
	// CylinderMesh 的 UV.y：0 = 顶（灯球那头），1 = 底（地面那头）
	float along = smoothstep(0.0, 0.06, UV.y) * (1.0 - smoothstep(0.82, 1.0, UV.y)) * mix(1.0, 0.45, UV.y);
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), edge_soft);
	float streak = 1.0 - dust + dust * (0.5 + 0.5 * sin(UV.y * 40.0 - TIME * 3.0 + UV.x * 12.566));
	ALBEDO = beam_color.rgb * strength * along * edge * streak;
}
