shader_type spatial;
// 虎斑猫的发光材质，用的是发光四芒星（star_glow.gdshader）那套颜色：
// 中心亮白偏粉（body_color），越往外越变成外光颜色（glow_color），自发光从 body_energy 渐变到 glow_energy。
// 星星是按“离星星中心多远”渐变，这里按“离猫身体中心多远”渐变（中心和半径见 center / radius）。
// glow = 0 时就是猫原来的贴图；glow 越大越变成发光星星的样子（1 = 完全是星星的颜色和亮度）。
// 外围的大范围光晕交给 WorldEnvironment 的 Glow（后期）。

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 body_color : source_color = vec4(1.0, 0.90, 0.95, 1.0); // 主体：亮白偏粉
uniform vec4 glow_color : source_color = vec4(0.35, 0.60, 1.0, 1.0);  // 外光颜色
uniform float body_energy : hint_range(0.0, 16.0) = 1.0;  // 中心自发光强度
uniform float glow_energy : hint_range(0.0, 16.0) = 3.0;  // 外围自发光强度
uniform float edge_start : hint_range(0.0, 1.0) = 0.12;   // 从半径的多少开始变成外光颜色
uniform float edge_end : hint_range(0.0, 1.0) = 0.72;     // 到半径的多少完全是外光颜色
uniform vec3 center = vec3(0.0, 0.5, 0.0);                // 猫身体中心（模型坐标）
uniform float radius = 0.75;                              // 从中心到最远的尾巴尖 / 爪子大约多远
uniform float glow = 0.0;                                 // 现在亮到几（0~1，脚本调）

varying float v_rad;

void vertex() {
	v_rad = length(VERTEX - center) / radius;
}

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	float f = smoothstep(edge_start, edge_end, v_rad);
	vec3 star = mix(body_color.rgb, glow_color.rgb, f);
	ALBEDO = mix(tex, star, glow);
	ROUGHNESS = 0.4;
	EMISSION = star * mix(body_energy, glow_energy, f) * glow;
}
