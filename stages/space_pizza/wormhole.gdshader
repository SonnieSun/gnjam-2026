// SPACE PIZZA 结尾的虫洞：一根很长的管子，只画内壁。螺旋彩带 + 往后冲的亮环 + 细星线，尽头发白。
// 由 scripts/sections/kisa/space_pizza_section.gd 建出来、改下面这些值。管子的轴是模型的 y（节点转了 90° 朝前）。
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

// 已经往前冲了多远（花纹按这个往后退）
uniform float scroll = 0.0;
// 整体浓度：0 = 看不见，1 = 全开
uniform float amount : hint_range(0.0, 1.0) = 1.0;
// 蓄力蓄了多少（0~1）：越高越亮、越白、彩带拧得越紧
uniform float heat : hint_range(0.0, 1.0) = 0.0;
// 管子多长（米），和网格的 height 一致
uniform float tube_length = 160.0;

varying vec3 model_pos;

vec3 hue_rgb(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	float a = atan(model_pos.x, model_pos.z) / TAU;        // 绕一圈 -0.5..0.5
	float v = model_pos.y / tube_length + 0.5;              // 0 = 入口，1 = 尽头
	float along = model_pos.y * 0.05 + scroll;
	// 螺旋彩带
	float band = sin((a * 5.0 + along * (0.8 + heat * 0.8)) * TAU) * 0.5 + 0.5;
	vec3 col = mix(vec3(0.05, 0.01, 0.16), hue_rgb(fract(along * 0.35 + a)) * mix(1.0, 0.75, heat), smoothstep(0.25, 0.9, band));
	col = mix(col, vec3(1.0), heat * 0.25 * band);
	// 一圈圈往后冲的亮环
	float ring = pow(sin(along * 2.0 * TAU) * 0.5 + 0.5, 14.0);
	col += vec3(1.0, 0.95, 0.85) * ring * (0.5 + heat * 0.9);
	// 细星线
	float cell = floor((a + 0.5) * 140.0);
	float pick = step(0.82, hash(cell));
	float dash = pow(sin((along * (1.5 + hash(cell + 7.0) * 2.0) + hash(cell + 3.0)) * TAU) * 0.5 + 0.5, 6.0);
	col += vec3(1.0) * pick * dash * (0.6 + heat);
	// 尽头发白（出口的光）；入口淡出一小段，不是一刀切
	col = mix(col, vec3(1.0, 0.98, 0.92), smoothstep(0.45, 1.0, v) * (0.55 + 0.45 * heat));
	float mouth = smoothstep(0.0, 0.04, v);
	ALBEDO = col;
	ALPHA = amount * mouth;
}
