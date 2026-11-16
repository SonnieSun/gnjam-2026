shader_type canvas_item;
// 七彩音符：颜色沿着圈转一圈是一整条彩虹，自己一直在转，从里到外还错开一点（像油膜）。
// 画的时候用白色（透明度照常给）：这里只换颜色，透明度和抗锯齿的边留着。
// 给 fever 里的音符用，见 scripts/fx/note_accents.gd。

// 彩虹的中心（画这些圈的节点自己的坐标，一般就是判定点）
uniform vec2 center = vec2(0.0);
// 每秒转几圈
uniform float speed = 0.6;
// 绕一圈重复几遍彩虹
uniform float bands = 1.0;
// 从里到外错开多少（每 100 像素错开几分之一圈）
uniform float radial = 0.35;
// 往白色提亮多少，再闪一点
uniform float lift = 0.25;
uniform float sparkle = 0.2;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	vec2 d = local - center;
	float h = atan(d.y, d.x) / TAU * bands + length(d) / 100.0 * radial - TIME * speed;
	vec3 c = mix(hue(h), vec3(1.0), lift);
	c += sparkle * pow(0.5 + 0.5 * sin(h * TAU * 6.0 + TIME * 9.0), 4.0);
	COLOR = vec4(c * COLOR.rgb, COLOR.a);
}
