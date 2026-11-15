shader_type spatial;
// 星云粒子：永远朝着镜头的发光小片，叠加混合。
// 普通粒子 = 柔光点；亮星 = 亮核 + 光晕 + 十字星芒；柔光团 = 一大片很淡的光。
// 每颗的参数放在 INSTANCE_CUSTOM：x = 星芒强度（0 = 普通粒子），y = 相位，z = 漂动幅度，w = 柔光团（1）
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// 每拍闪一下的强度（脚本每帧给）
uniform float pulse = 0.0;
// 跟拍多亮多少
uniform float pulse_gain = 0.6;
// 平时自己闪烁的幅度
uniform float twinkle = 0.3;
// 漂动快慢
uniform float drift_speed = 0.4;
// 星芒有多细（越大越细）
uniform float flare_thin = 55.0;
// 星芒有多长（越小越长）
uniform float flare_falloff = 3.2;
// 整体亮度
uniform float brightness = 1.0;

varying vec4 star;

void vertex() {
	star = INSTANCE_CUSTOM;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 pos = MODEL_MATRIX[3].xyz;
	// 慢慢漂动：每颗相位不同
	float t = TIME * drift_speed + star.y;
	pos += vec3(sin(t), cos(t * 0.8), sin(t * 0.6 + 1.3)) * star.z;
	// 朝向镜头，保留每颗自己的大小
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, vec4(pos, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float edge = smoothstep(1.0, 0.7, r);  // 小片边缘淡出，看不到方块
	float speed = 1.5 + fract(star.y * 7.13) * 3.5;
	float blink = 1.0 + twinkle * sin(TIME * speed + star.y) + pulse * pulse_gain;
	vec3 tint = COLOR.rgb;
	vec3 col;
	if (star.w > 0.5) {
		col = tint * exp(-r * r * 5.5) * smoothstep(1.0, 0.25, r) * 0.4 * (1.0 + pulse * pulse_gain * 0.4);
	} else if (star.x > 0.0) {
		float core = exp(-r * r * 90.0);
		float halo = exp(-r * r * 7.0) * 0.45;
		float cross = exp(-abs(p.x) * flare_thin) * exp(-abs(p.y) * flare_falloff)
				+ exp(-abs(p.y) * flare_thin) * exp(-abs(p.x) * flare_falloff);
		col = (mix(tint, vec3(1.0), 0.75) * core * 1.6 + tint * (halo + cross * star.x * 0.9)) * blink;
	} else {
		// 普通粒子：中心亮一点的柔光点，像云里的尘
		col = mix(tint, vec3(1.0), 0.3) * (exp(-r * r * 9.0) + exp(-r * r * 30.0) * 0.6) * blink;
	}
	ALBEDO = col * edge * brightness * COLOR.a;
}
