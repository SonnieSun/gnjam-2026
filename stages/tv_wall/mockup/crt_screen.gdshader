// CRT 屏幕：猫脸画面 + 青绿染色 + 扫描线 + 暗角 + 一条滚动亮带，自发光
shader_type spatial;
render_mode unshaded;

uniform sampler2D feed : source_color, filter_linear;
uniform vec3 tint : source_color = vec3(0.55, 1.0, 0.85);
uniform float zoom = 1.0;
uniform vec2 offset = vec2(0.0);
uniform float energy = 2.0;
uniform float roll = 0.0;
uniform float lines = 120.0;
uniform float vignette = 2.2;

void fragment() {
	vec2 uv = (UV - 0.5) / zoom + 0.5 + offset;
	vec3 c = texture(feed, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 0.45) * tint;
	float scan = 0.75 + 0.25 * sin(UV.y * lines * 6.2832);
	vec2 d = UV - 0.5;
	float vig = clamp(1.0 - dot(d, d) * vignette, 0.0, 1.0);
	float band = 1.0 + 0.35 * exp(-pow((fract(UV.y + roll) - 0.5) * 9.0, 2.0));
	ALBEDO = c * scan * vig * band * energy;
}
