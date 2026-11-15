shader_type spatial;
// 四芒星发光材质：中心亮白偏粉，往尖角过渡到外光颜色。
// 外围的大范围光晕交给 WorldEnvironment 的 Glow（后期），这里只负责让星星本体足够亮。

uniform vec4 body_color : source_color = vec4(1.0, 0.90, 0.95, 1.0); // 主体：亮白偏粉
uniform vec4 glow_color : source_color = vec4(0.35, 0.60, 1.0, 1.0);  // 外光颜色（彩色，随意换）
uniform float body_energy : hint_range(0.0, 16.0) = 1.0;  // 中心自发光强度
uniform float glow_energy : hint_range(0.0, 16.0) = 3.0;  // 边缘/尖角自发光强度（越大光晕越大）
uniform float edge_start : hint_range(0.0, 1.0) = 0.12;   // 从半径的多少开始变成外光颜色
uniform float edge_end : hint_range(0.0, 1.0) = 0.72;     // 到半径的多少完全是外光颜色

varying float v_rad;

void vertex() {
	// 模型在 XY 平面、尖角半径 0.5
	v_rad = length(VERTEX.xy) / 0.5;
}

void fragment() {
	float f = smoothstep(edge_start, edge_end, v_rad);
	vec3 c = mix(body_color.rgb, glow_color.rgb, f);
	ALBEDO = c;
	ROUGHNESS = 0.4;
	EMISSION = c * mix(body_energy, glow_energy, f);
}
