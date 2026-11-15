// 片尾字幕的星空背景：一格一颗随机的小星星，轻轻闪。
shader_type canvas_item;

uniform vec4 sky : source_color = vec4(0.0, 0.0, 0.02, 1.0);
// 星星有多密（一格多大，像素）和多亮
uniform float cell = 26.0;
uniform float brightness = 0.9;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 px = UV / SCREEN_PIXEL_SIZE;
	vec2 id = floor(px / cell);
	vec2 at = (vec2(hash(id), hash(id + 7.3)) * 0.8 + 0.1) * cell;
	float d = length(px - id * cell - at);
	float has = step(0.72, hash(id + 3.1));  // 不是每一格都有星星
	float size = 0.6 + hash(id + 9.7) * 1.2;
	float twinkle = 0.7 + 0.3 * sin(TIME * (1.0 + hash(id) * 3.0) + hash(id + 1.0) * 6.28);
	float star = has * smoothstep(size + 0.8, size * 0.3, d) * twinkle * brightness;
	COLOR = vec4(sky.rgb + vec3(star), 1.0);
}
