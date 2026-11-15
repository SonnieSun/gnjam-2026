// 电视墙开场结尾用的屏幕：显示一张图（铺满屏幕），或者一路实时画面。
// 实时画面 fit 0 = 裁掉左右铺满屏幕，fit 1 = 按画面自己的宽高比完整放进屏幕（上下留黑边，不拉伸）。
// live_mix 0 = 图片，1 = 实时画面；crt 1 = 带扫描线和暗角的电视感，0 = 画面原样（镜头钻进屏幕时要原样才接得上）。
shader_type spatial;
render_mode unshaded;

uniform sampler2D image : source_color, filter_linear;
uniform sampler2D live : source_color, filter_linear;
uniform float live_mix = 0.0;
// 屏幕的宽高比、实时画面的宽高比
uniform float screen_aspect = 1.32;
uniform float live_aspect = 1.7778;
// 0 = 裁边铺满，1 = 完整放进屏幕
uniform float fit = 0.0;
uniform float crt = 1.0;
uniform float energy = 1.6;
uniform float lines = 120.0;
// 闪烁时整块屏幕的亮度（1 = 正常）
uniform float dim = 1.0;
uniform float flash = 0.0;

void fragment() {
	vec2 d = UV - 0.5;
	vec3 img = texture(image, UV).rgb;
	// 实时画面：在「裁边铺满」和「完整放进屏幕」之间过渡
	vec2 luv = vec2(0.5 + d.x * mix(screen_aspect / live_aspect, 1.0, fit), 0.5 + d.y * mix(1.0, live_aspect / screen_aspect, fit));
	vec3 lv = texture(live, luv).rgb;
	if (luv.y < 0.0 || luv.y > 1.0) {
		lv = vec3(0.0);
	}
	vec3 c = mix(img, lv, live_mix);
	float scan = 0.75 + 0.25 * sin(UV.y * lines * 6.2832);
	float vig = clamp(1.0 - dot(d, d) * 1.2, 0.0, 1.0);
	c *= mix(1.0, scan * vig * energy, crt) * dim;
	c += vec3(1.0, 0.95, 0.85) * flash * 3.0;
	ALBEDO = c;
}
