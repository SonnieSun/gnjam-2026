shader_type canvas_item;
// 全屏 VHS / CRT 效果：降分辨率、色彩错位、扫描线、逐行抖动、滚动干扰带、噪点颗粒、暗角。
// 用在 AbductionStage 显示 3D 画面的那张 Sprite2D 上，参数在 Stage 节点的 screen_material 里调。

// 像素块大小（1 = 不降分辨率）
uniform float pixel_size : hint_range(1.0, 8.0) = 2.0;
// 红蓝通道左右错开几个像素
uniform float chroma_px : hint_range(0.0, 8.0) = 2.5;
// 扫描线深浅和条数
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_count = 260.0;
// 逐行左右抖动（像素）
uniform float wobble_px : hint_range(0.0, 8.0) = 1.5;
// 滚动干扰带：强度、速度
uniform float tracking_strength : hint_range(0.0, 1.0) = 0.5;
uniform float tracking_speed = 0.07;
// 噪点颗粒
uniform float grain : hint_range(0.0, 0.5) = 0.1;
// 饱和度、整体色调
uniform float saturation : hint_range(0.0, 2.0) = 0.85;
uniform vec3 tint = vec3(1.0, 0.94, 1.06);
// 暗角
uniform float vignette : hint_range(0.0, 3.0) = 0.9;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 uv = UV;
	float ps = max(pixel_size, 1.0);
	float line = floor(uv.y / px.y / ps);
	float frame = floor(TIME * 24.0);
	// 逐行抖动
	uv.x += (hash(vec2(line, frame)) - 0.5) * wobble_px * px.x;
	// 滚动干扰带：一条横带从下往上慢慢滚，带里抖得更厉害、更亮
	float band_y = 1.0 - fract(TIME * tracking_speed);
	float band = smoothstep(0.05, 0.0, abs(uv.y - band_y));
	uv.x += band * tracking_strength * 10.0 * px.x * (hash(vec2(frame, line)) - 0.3);
	// 降分辨率
	vec2 cell = px * ps;
	uv = (floor(uv / cell) + 0.5) * cell;
	// 色彩错位
	float r = texture(TEXTURE, uv + vec2(chroma_px * px.x, 0.0)).r;
	float g = texture(TEXTURE, uv).g;
	float b = texture(TEXTURE, uv - vec2(chroma_px * px.x, 0.0)).b;
	vec3 c = vec3(r, g, b);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * tint;
	// 扫描线
	float s = 0.5 + 0.5 * sin(UV.y * scanline_count * 3.14159);
	c *= 1.0 - scanline_strength * (1.0 - s);
	// 颗粒和干扰带亮度
	c += (hash(UV * 913.0 + fract(TIME) * 37.0) - 0.5) * grain;
	c += band * tracking_strength * 0.12;
	// 暗角
	vec2 d = UV - 0.5;
	c *= clamp(1.0 - dot(d, d) * vignette, 0.0, 1.0);
	COLOR = vec4(c, 1.0);
}
