shader_type spatial;
// 灯球光束打在地上的光斑（代替真的聚光灯，省掉每个像素算灯光）：平放的一片，中间亮、边上虚，叠加发光。
// 颜色和亮度按实例改（脚本每帧设 spot_color / strength），所有光斑共用一份材质。
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform vec4 spot_color : source_color = vec4(1.0);
instance uniform float strength = 0.0;
// 从半径的多少开始变虚
uniform float soft_start : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	// PlaneMesh 的 UV：0..1，中心在 0.5
	float r = length(UV - 0.5) * 2.0;
	float a = 1.0 - smoothstep(soft_start, 1.0, r);
	ALBEDO = spot_color.rgb * strength * a * a;
}
