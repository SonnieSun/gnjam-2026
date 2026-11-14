// 黑胶碟面：一圈圈纹路 + 散落的小星点（跟着碟片转）+ 固定不动的高光（像真唱片转动时高光不动）
shader_type spatial;

uniform vec3 vinyl_color : source_color = vec3(0.045, 0.04, 0.065);
uniform vec3 groove_color : source_color = vec3(0.17, 0.16, 0.22);
// 每单位半径有几圈纹路
uniform float groove_density = 14.0;
uniform float groove_strength = 0.55;
// 中心标签
uniform float label_radius = 2.6;
uniform vec3 label_color : source_color = vec3(1.0, 0.36, 0.56);
// 小星点
uniform vec3 speck_color : source_color = vec3(1.0, 0.85, 0.4);
uniform float speck_density = 2.2;
uniform float speck_amount = 0.12;
uniform float speck_energy = 1.4;
// 高光
uniform vec3 sheen_color : source_color = vec3(0.6, 0.62, 1.0);
uniform float sheen_strength = 0.1;
uniform float sheen_sharpness = 30.0;
// 两道高光偏离正前方的角度（弧度）
uniform float sheen_angle = 0.7;

varying vec3 local_pos;
varying vec3 world_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float r = length(local_pos.xz);
	float phase = r * groove_density;
	float g = sin(phase * 6.2831) * 0.5 + 0.5;
	float bands = sin(phase * 0.23 * 6.2831) * 0.5 + 0.5;
	float aa = clamp(fwidth(phase) * 1.5, 0.0, 1.0);
	g = mix(g, 0.5, aa);
	vec3 col = mix(vinyl_color, groove_color, g * mix(0.5, 1.0, bands) * groove_strength);

	vec2 sp = local_pos.xz * speck_density;
	vec2 cell = floor(sp);
	vec2 f = fract(sp) - 0.5;
	vec2 off = vec2(hash(cell + 1.7), hash(cell + 4.3)) - 0.5;
	float speck = step(1.0 - speck_amount, hash(cell)) * smoothstep(0.09, 0.03, length(f - off * 0.6));

	float is_label = 1.0 - smoothstep(label_radius - 0.03, label_radius, r);
	col = mix(col, label_color, is_label);

	float a = atan(world_pos.x, -world_pos.z);
	float sheen = pow(abs(cos(a - sheen_angle)), sheen_sharpness) + pow(abs(cos(a + sheen_angle)), sheen_sharpness);

	ALBEDO = col;
	ROUGHNESS = mix(0.3, 0.65, g);
	METALLIC = 0.0;
	SPECULAR = 0.35;
	EMISSION = speck_color * speck * speck_energy * (1.0 - is_label)
		+ sheen_color * sheen * sheen_strength * (0.35 + 0.65 * g) * (1.0 - is_label);
}
