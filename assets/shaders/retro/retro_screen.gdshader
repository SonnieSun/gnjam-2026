// 全屏 retro 滤镜（测试）：照 runway-tm-sequel 的 era 输出（docs/ART_DIRECTION.md "Era render"、
// docs/UI_DIRECTION.md "Era output"），但不另开视口，直接读屏幕（hint_screen_texture），
// 所以 3D、2D、HUD、菜单一起过滤，哪一关都不用改。
//   一个 era 像素 = px × px 个窗口像素（px 取整，让画面接近 480 线），取样都取 era 像素中心 → 方像素、没有抗锯齿
//   mode 0：直接切色深 + 4x4 有序抖动（16 位 VGA、256 色）
//   mode 1：JPEG 编码（8x8 DCT、YCbCr 4:2:0、按 quality 量化），系数写回屏幕
//   mode 2：读上一步写回屏幕的系数，解码，再切色深（前面要有一个 BackBufferCopy）
// JPEG 数学和 runway 一样，在 assets/shaders/y2k/era_jpeg.gdshaderinc。
shader_type canvas_item;
render_mode unshaded;

#include "res://assets/shaders/y2k/era_jpeg.gdshaderinc"

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform int mode = 0;
uniform float px = 2.0;
uniform vec3 bits = vec3(5.0, 6.0, 5.0);
uniform float dither : hint_range(0.0, 1.0) = 1.0;
uniform float quality = 35.0;
uniform bool chroma_420 = true;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

// era 像素 c 的中心在屏幕上的 UV
vec2 era_uv(vec2 c, vec2 pixel_size) {
	return (c + 0.5) * px * pixel_size;
}

vec3 era_rgb(vec2 c, vec2 pixel_size) {
	return texture(screen, era_uv(c, pixel_size)).rgb;
}

vec3 cut(vec3 col, vec2 p) {
	vec3 levels = exp2(bits) - 1.0;
	float d = (bayer4(p) - 0.5) * dither;
	return clamp(floor(clamp(col, 0.0, 1.0) * levels + 0.5 + d) / levels, 0.0, 1.0);
}

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE;
	vec2 p = floor(FRAGCOORD.xy / px);  // 这个窗口像素属于哪个 era 像素
	if (mode == 0) {
		COLOR = vec4(cut(era_rgb(p, ps), p), 1.0);
	} else if (mode == 1) {
		vec2 block = floor(p / 8.0) * 8.0;
		vec2 uv = p - block;
		vec3 sum = vec3(0.0);
		for (int y = 0; y < 8; y++) {
			float by = cos((2.0 * float(y) + 1.0) * uv.y * PI_16);
			for (int x = 0; x < 8; x++) {
				vec2 c = block + vec2(float(x), float(y));
				vec3 ycc = rgb_to_ycc(era_rgb(c, ps));
				if (chroma_420) {
					vec2 c2 = floor(c / 2.0) * 2.0;
					vec3 avg = (era_rgb(c2, ps) + era_rgb(c2 + vec2(1.0, 0.0), ps)
							+ era_rgb(c2 + vec2(0.0, 1.0), ps) + era_rgb(c2 + vec2(1.0, 1.0), ps)) * 0.25;
					ycc.yz = rgb_to_ycc(avg).yz;
				}
				ycc.x -= 0.5;
				sum += ycc * by * cos((2.0 * float(x) + 1.0) * uv.x * PI_16);
			}
		}
		vec3 coef = sum * 0.25 * dct_c(uv.x) * dct_c(uv.y);
		int i = int(uv.y) * 8 + int(uv.x);
		float s = jpeg_scale(quality);
		vec3 q = max(vec3(Q_LUMA[i], Q_CHROMA[i], Q_CHROMA[i]) * s, vec3(1.0)) / 255.0;
		coef = round(coef / q) * q;
		COLOR = vec4(encode_coef(coef, i == 0), 1.0);
	} else {
		vec2 block = floor(p / 8.0) * 8.0;
		vec2 xy = p - block;
		vec3 ycc = vec3(0.0);
		for (int v = 0; v < 8; v++) {
			float bv = dct_c(float(v)) * cos((2.0 * xy.y + 1.0) * float(v) * PI_16);
			for (int u = 0; u < 8; u++) {
				vec3 e = era_rgb(block + vec2(float(u), float(v)), ps);
				ycc += decode_coef(e, u == 0 && v == 0) * bv * dct_c(float(u)) * cos((2.0 * xy.x + 1.0) * float(u) * PI_16);
			}
		}
		ycc *= 0.25;
		ycc.x += 0.5;
		COLOR = vec4(cut(ycc_to_rgb(ycc), p), 1.0);
	}
}
