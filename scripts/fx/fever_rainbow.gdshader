shader_type canvas_item;
render_mode blend_add;
// FEVER 的彩色滤镜：色相绕着屏幕中心转，叠加在画面上，只压边缘（中间要看音符，留着不动）。
// 来自《力量涌现出来了》的 fever_rainbow.gdshader；这里呼吸不再自己按时间走，而是由 FeverFx 按音乐的拍子给（pulse），
// 多了一圈往外扩的彩虹波纹（wave，进 fever 和每个拍手那一下）和进场的一下白闪（flash）。

// 整体多亮（0 = 没有）
uniform float opacity : hint_range(0.0, 1.0) = 0.0;
// 这一拍亮到哪（0~1，拍点上是 1，然后落回去）
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
// 每秒转多少圈
uniform float speed = 0.18;
// 绕一圈重复几遍彩虹
uniform float bands = 1.0;
// 从多靠里开始有颜色、到多靠外全亮（离中心的距离，0.5 = 短边的边上）
uniform float inner = 0.28;
uniform float outer = 0.85;
// 画面宽 / 高
uniform float aspect = 1.333;
// 往外扩的一圈波纹：走到哪了（0 = 中心，1 = 出了屏幕）和多亮
uniform float wave = 2.0;
uniform float wave_strength = 0.0;
// 进场白闪
uniform float flash = 0.0;

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	vec2 pos = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float r = length(pos);
	float h = atan(pos.y, pos.x) / TAU * bands + TIME * speed + r * 0.35;
	vec3 rainbow = mix(hue(h), vec3(1.0), 0.15);
	float edge = smoothstep(inner, outer, r);
	float glow = edge * opacity * (0.7 + 0.3 * pulse);
	// 波纹：一圈细的彩虹往外扩，越往外越淡
	float ring = smoothstep(0.07, 0.0, abs(r - wave * 0.95)) * wave_strength * (1.0 - clamp(wave, 0.0, 1.0));
	COLOR = vec4(rainbow * (glow + ring) + vec3(1.0, 0.92, 1.0) * flash, 1.0);
}
