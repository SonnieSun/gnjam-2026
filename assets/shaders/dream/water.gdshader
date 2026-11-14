// 发光的水面：深蓝底色 + 一道道往后流的青色亮纹 + 镜面一样的高光，远处融进天边的颜色。
shader_type spatial;
render_mode blend_mix, cull_back;

uniform vec3 deep_color : source_color = vec3(0.01, 0.05, 0.30);
uniform vec3 shallow_color : source_color = vec3(0.05, 0.32, 0.75);
uniform vec3 glow_color : source_color = vec3(0.45, 1.0, 0.95);
uniform vec3 horizon_color : source_color = vec3(0.26, 0.10, 0.50);
// 中心倒影的颜色（披萨和猫底下那一团亮光）
uniform vec3 core_color : source_color = vec3(1.0, 0.75, 0.95);
uniform float core_radius = 4.0;
uniform float ripple_scale = 1.3;
uniform float ripple_speed = 1.2;
uniform float glow_strength = 0.9;
// 多远开始融进天边
uniform float fade_distance = 45.0;
// 已经往前飞了多远（脚本每帧改），水纹按这个距离往后流
uniform float scroll = 0.0;
// 打中时脚本会推一下，水纹更亮
uniform float boost = 0.0;

varying vec3 wpos;

float waves(vec2 p, float t) {
	float w = sin(p.y * ripple_scale * 1.6 + sin(p.x * 0.35) * 1.2 - t * ripple_speed * 2.0);
	w += sin(p.x * ripple_scale * 0.9 + sin(p.y * 0.6 + t * 0.7) * 1.5 + t * ripple_speed) * 0.8;
	w += sin((p.x + p.y) * ripple_scale * 0.5 - t * ripple_speed * 0.6) * 0.5;
	return w / 2.3;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 fp = p + vec2(0.0, scroll);  // 水纹跟着往后流，看起来像在往前飞
	float t = TIME;
	float w = waves(fp, t);
	float e = 0.08;
	float dx = waves(fp + vec2(e, 0.0), t) - w;
	float dz = waves(fp + vec2(0.0, e), t) - w;
	vec3 n = normalize(vec3(-dx * 3.0, 1.0, -dz * 3.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float dist = length(p);
	float lines = pow(smoothstep(0.55, 1.0, w * 0.5 + 0.5), 3.0);
	vec3 col = mix(deep_color, shallow_color, w * 0.5 + 0.5);
	float core = exp(-dist * dist / (core_radius * core_radius));
	float far = smoothstep(fade_distance * 0.3, fade_distance, dist);
	ALBEDO = mix(col, horizon_color, far);
	ROUGHNESS = 0.06;
	METALLIC = 0.6;
	SPECULAR = 1.0;
	vec3 em = glow_color * lines * (glow_strength + boost * 1.0) * (1.0 - far);
	em += core_color * core * (0.55 + boost * 0.8) * (0.6 + 0.4 * w);
	em += horizon_color * far * 0.5;
	EMISSION = em;
}
