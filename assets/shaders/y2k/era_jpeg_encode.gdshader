// Era output, pass 1 (low-res): JPEG encode. Each pixel of an 8x8 block computes the one DCT
// coefficient for its (u, v) slot from the block's 64 pixels of the 3D image, in YCbCr with
// optional 4:2:0 chroma, then quantises it with the standard tables at `quality`.
shader_type canvas_item;

#include "era_jpeg.gdshaderinc"

uniform sampler2D source : filter_nearest;
uniform sampler2D source_smooth : filter_linear;  // same texture: 2x2 chroma averages
uniform float quality = 35.0;
uniform bool chroma_420 = true;

void fragment() {
	vec2 res = vec2(textureSize(source, 0));
	vec2 p = floor(UV * res);
	vec2 block = floor(p / 8.0) * 8.0;
	vec2 uv = p - block;
	vec3 sum = vec3(0.0);
	for (int y = 0; y < 8; y++) {
		float by = cos((2.0 * float(y) + 1.0) * uv.y * PI_16);
		for (int x = 0; x < 8; x++) {
			vec2 c = block + vec2(float(x), float(y));
			vec3 ycc = rgb_to_ycc(texture(source, (c + 0.5) / res).rgb);
			if (chroma_420) {
				ycc.yz = rgb_to_ycc(texture(source_smooth, (floor(c / 2.0) * 2.0 + 1.0) / res).rgb).yz;
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
}
