// 彩虹玻璃：正对着看几乎透明，边缘发亮，颜色随视角在粉、青、紫之间流动（肥皂泡 / 镭射膜的感觉）。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.7, 0.95);
uniform float face_alpha = 0.10;
uniform float edge_alpha = 0.85;
// 边缘发光的强度
uniform float rim_glow = 0.8;
// 彩虹色有多浓（0 = 只有 tint 的颜色）
uniform float iridescence = 0.7;

void fragment() {
	float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, 2.5);
	vec3 rainbow = 0.5 + 0.5 * cos(TAU * (ndv * 1.5 + vec3(0.0, 0.33, 0.67)) + TIME * 0.6);
	vec3 col = mix(tint, rainbow, iridescence * (0.4 + 0.6 * fresnel));
	ALBEDO = col;
	ALPHA = mix(face_alpha, edge_alpha, fresnel);
	ROUGHNESS = 0.03;
	SPECULAR = 1.0;
	EMISSION = col * fresnel * rim_glow;
}
