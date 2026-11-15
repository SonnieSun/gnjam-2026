// 片尾字幕：把一张竖长的字幕图铺在一块往远处倒下去的平面上（星球大战那种），越远越小、越淡。
// 挂在 scenes/credits.tscn 的 Crawl 上，scroll 由 scripts/credits.gd 推着走。
shader_type canvas_item;

// 字幕滚到哪了：0 = 第一行刚从画面底边冒出来，越大越往远处走
uniform float scroll = 0.0;
// 地平线（字幕消失的地方）在画面多高：0 = 顶边，1 = 底边
uniform float horizon : hint_range(0.0, 0.9) = 0.2;
// 平面有多“深”：越大，远处的字挤得越密
uniform float depth = 0.31;
// 画面底边处字幕占多宽（1 = 正好铺满画面宽度）
uniform float near_width = 1.0;
// 靠近地平线多大一段淡出
uniform float fade = 0.35;

void fragment() {
	float t = (UV.y - horizon) / (1.0 - horizon);  // 0 = 地平线，1 = 画面底边
	if (t <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		float z = 1.0 / t;  // 离镜头多远：底边 = 1
		vec2 uv = vec2(0.5 + (UV.x - 0.5) * z / near_width, scroll - (z - 1.0) * depth);
		vec4 c = vec4(0.0);
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			c = texture(TEXTURE, uv);
		}
		c.a *= smoothstep(0.0, fade, t);
		COLOR = c;
	}
}
