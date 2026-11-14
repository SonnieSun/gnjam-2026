// Shared JPEG maths for the era output passes: YCbCr, the 8x8 DCT basis and the standard
// (ITU-T T.81 Annex K) quantisation tables, scaled by quality the way libjpeg does.

const float PI_16 = 0.19634954;  // pi / 16

const float Q_LUMA[64] = float[64](
	16.0, 11.0, 10.0, 16.0, 24.0, 40.0, 51.0, 61.0,
	12.0, 12.0, 14.0, 19.0, 26.0, 58.0, 60.0, 55.0,
	14.0, 13.0, 16.0, 24.0, 40.0, 57.0, 69.0, 56.0,
	14.0, 17.0, 22.0, 29.0, 51.0, 87.0, 80.0, 62.0,
	18.0, 22.0, 37.0, 56.0, 68.0, 109.0, 103.0, 77.0,
	24.0, 35.0, 55.0, 64.0, 81.0, 104.0, 113.0, 92.0,
	49.0, 64.0, 78.0, 87.0, 103.0, 121.0, 120.0, 101.0,
	72.0, 92.0, 95.0, 98.0, 112.0, 100.0, 103.0, 99.0);

const float Q_CHROMA[64] = float[64](
	17.0, 18.0, 24.0, 47.0, 99.0, 99.0, 99.0, 99.0,
	18.0, 21.0, 26.0, 66.0, 99.0, 99.0, 99.0, 99.0,
	24.0, 26.0, 56.0, 99.0, 99.0, 99.0, 99.0, 99.0,
	47.0, 66.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
	99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
	99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
	99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0,
	99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0);

vec3 rgb_to_ycc(vec3 c) {
	float y = dot(c, vec3(0.299, 0.587, 0.114));
	return vec3(y, (c.b - y) * 0.5643, (c.r - y) * 0.7133);
}

vec3 ycc_to_rgb(vec3 ycc) {
	return vec3(ycc.x + 1.402 * ycc.z, ycc.x - 0.3441 * ycc.y - 0.7141 * ycc.z, ycc.x + 1.772 * ycc.y);
}

float dct_c(float k) {
	return k < 0.5 ? 0.70710678 : 1.0;
}

// libjpeg quality scaling: 50 = the table as printed, lower = coarser.
float jpeg_scale(float quality) {
	float q = clamp(quality, 1.0, 100.0);
	return (q < 50.0 ? 5000.0 / q : 200.0 - 2.0 * q) / 100.0;
}

// Coefficients are stored in an 8-bit target: DC in [-4, 4], AC clamped to [-2, 2]. Zero
// sits exactly on byte 128 so flat blocks decode flat (a 0.5 midpoint would bias all 63 AC
// terms and light up every block corner).
const float MID = 128.0 / 255.0;

vec3 encode_coef(vec3 c, bool dc) {
	return clamp(c / (dc ? 8.0 : 4.0) + MID, 0.0, 1.0);
}

vec3 decode_coef(vec3 e, bool dc) {
	return (round(e * 255.0) / 255.0 - MID) * (dc ? 8.0 : 4.0);
}
