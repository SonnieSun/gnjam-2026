// 效果图用：整屏降到约 480 线方像素 + RGB565 有序抖动 + 分离色调调色（参考 y2k_retro_kit 的 era_ui / theme_grade）
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float lines = 360.0;
uniform vec3 bits = vec3(5.0, 6.0, 5.0);
uniform float dither = 1.0;
uniform vec3 shadow_tint : source_color = vec3(0.35, 0.4, 0.95);
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.85, 0.5);
uniform float shadow_amount = 0.25;
uniform float highlight_amount = 0.08;
uniform float saturation = 1.12;
uniform float contrast = 1.1;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 res = vec2(floor(lines * size.x / size.y), lines);
	vec2 p = floor(SCREEN_UV * res);
	vec3 c = texture(screen, (p + 0.5) / res).rgb;
	// 调色
	float l = dot(c, LUMA);
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	l = clamp(dot(c, LUMA), 0.0, 1.0);
	c += (shadow_tint - dot(shadow_tint, LUMA)) * shadow_amount * (1.0 - l) * (1.0 - l);
	c += (highlight_tint - dot(highlight_tint, LUMA)) * highlight_amount * l * l;
	// 16 位色 + 抖动
	vec3 levels = exp2(bits) - 1.0;
	c = floor(clamp(c, 0.0, 1.0) * levels + 0.5 + (bayer4(p) - 0.5) * dither) / levels;
	COLOR = vec4(c, 1.0);
}
