shader_type spatial;
// 猫的轮廓边光：越靠边越亮，叠加在原来的贴图上（不改贴图本身）
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform vec4 rim_color : source_color = vec4(1.0, 0.55, 0.9, 1.0);
// 边光有多宽：越大越只剩最外圈
uniform float rim_power = 3.5;
uniform float strength = 1.0;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb * f * strength;
}
