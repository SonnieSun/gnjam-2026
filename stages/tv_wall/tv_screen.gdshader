// 电视墙关卡的屏幕：雪花 ↔ 猫脸画面（power 0~1），砸坏后黑屏加裂纹，砸中瞬间白闪
shader_type spatial;
render_mode unshaded;

uniform sampler2D feed : source_color, filter_linear;
uniform vec3 tint : source_color = vec3(0.55, 1.0, 0.85);
uniform float zoom = 1.0;
uniform vec2 offset = vec2(0.0);
uniform float energy = 2.5;
uniform float roll = 0.0;
uniform float vignette = 1.2;
uniform float lines = 120.0;
// 0 = 雪花，1 = 猫脸画面
uniform float power = 0.0;
// 雪花亮度
uniform float static_level = 0.3;
// 1 = 砸坏了（黑屏 + 裂纹）
uniform float broken = 0.0;
// 白闪（砸中那一下 1，代码里衰减）
uniform float flash = 0.0;
// 裂纹的随机种子
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 d = UV - 0.5;
	float scan = 0.75 + 0.25 * sin(UV.y * lines * 6.2832);
	float vig = clamp(1.0 - dot(d, d) * vignette, 0.0, 1.0);
	float band = 1.0 + 0.35 * exp(-pow((fract(UV.y + roll + TIME * 0.15) - 0.5) * 9.0, 2.0));

	vec2 uv = (UV - 0.5) / zoom + 0.5 + offset;
	vec3 face = texture(feed, uv).rgb;
	float l = dot(face, vec3(0.299, 0.587, 0.114));
	face = mix(vec3(l), face, 0.45) * tint;
	float n = hash(floor(UV * vec2(90.0, 70.0)) + floor(TIME * 24.0));
	vec3 snow = vec3(n) * static_level * mix(vec3(1.0), tint, 0.5);
	vec3 c = mix(snow, face, power) * scan * vig * band * energy;

	// 砸坏：黑屏 + 从中心裂开的几道裂纹
	float r = length(d * vec2(1.3, 1.0));
	float a = atan(d.y, d.x);
	float aj = a + sin(r * 45.0 + seed * 20.0) * 0.06;  // 裂纹抖一点，不要太直
	float rays = pow(abs(sin(aj * 3.0 + seed * 6.0)), 600.0) + pow(abs(sin(aj * 2.0 + seed * 11.0)), 900.0);
	float crack = clamp(rays * step(0.04, r) * (1.0 - smoothstep(0.35, 0.5, r)), 0.0, 1.0);
	crack += (1.0 - smoothstep(0.0, 0.012, abs(r - 0.07)));
	vec3 dead = vec3(0.01, 0.015, 0.02) + vec3(0.55, 0.85, 1.0) * clamp(crack, 0.0, 1.0) * 0.3;
	c = mix(c, dead, broken);

	c += vec3(1.0, 0.95, 0.85) * flash * 3.0;
	ALBEDO = c;
}
