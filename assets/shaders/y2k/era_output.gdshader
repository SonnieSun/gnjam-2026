// Era output, pass 2 (low-res): decode the JPEG blocks (inverse DCT) when `jpeg` is on, then
// cut the colour depth to `bits` per channel with an optional 4x4 ordered dither. The result
// is upscaled to the window with nearest filtering: sharp, square pixels.
shader_type canvas_item;

#include "era_jpeg.gdshaderinc"

uniform sampler2D plain : filter_nearest;  // the 3D image
uniform sampler2D coefs : filter_nearest;  // pass 1 output
uniform bool jpeg = true;
uniform vec3 bits = vec3(5.0, 6.0, 5.0);
uniform float dither : hint_range(0.0, 1.0) = 0.0;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

void fragment() {
	vec2 res = vec2(textureSize(plain, 0));
	vec2 p = floor(UV * res);
	vec3 col;
	if (jpeg) {
		vec2 block = floor(p / 8.0) * 8.0;
		vec2 xy = p - block;
		vec3 ycc = vec3(0.0);
		for (int v = 0; v < 8; v++) {
			float bv = dct_c(float(v)) * cos((2.0 * xy.y + 1.0) * float(v) * PI_16);
			for (int u = 0; u < 8; u++) {
				vec3 e = texture(coefs, (block + vec2(float(u), float(v)) + 0.5) / res).rgb;
				ycc += decode_coef(e, u == 0 && v == 0) * bv * dct_c(float(u)) * cos((2.0 * xy.x + 1.0) * float(u) * PI_16);
			}
		}
		ycc *= 0.25;
		ycc.x += 0.5;
		col = ycc_to_rgb(ycc);
	} else {
		col = texture(plain, (p + 0.5) / res).rgb;
	}
	vec3 levels = exp2(bits) - 1.0;
	float d = (bayer4(p) - 0.5) * dither;
	col = floor(clamp(col, 0.0, 1.0) * levels + 0.5 + d) / levels;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
