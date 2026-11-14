shader_type spatial;
// 猫转圈时从脚下扩散出去的一圈光波（平放在地上，叠加发光）
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 wave_color : source_color = vec4(1.0, 0.8, 0.95, 1.0);
uniform float strength = 1.0;
// 0 = 刚发出，1 = 扩散完
uniform float progress = 0.0;
// 光环的粗细（占半径的比例）
uniform float width = 0.12;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;  // 0 = 中心，1 = 边
	float ring = 1.0 - smoothstep(0.0, width, abs(d - 0.85));
	float inner = smoothstep(0.85, 0.0, d) * 0.15;  // 里面带一点淡淡的光
	float fade = 1.0 - progress;
	ALBEDO = wave_color.rgb * (ring + inner) * strength * fade * fade;
}
