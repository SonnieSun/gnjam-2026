shader_type spatial;
// 灯球表面一闪一闪的十字星光（参考图里的 ✦）：永远正对镜头，叠加发光。
// 脚本按实例改 glint（0 = 看不见，1 = 最亮）、glint_color 和 spin（光芒转的角度）。
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform vec4 glint_color : source_color = vec4(1.0);
instance uniform float glint = 0.0;
instance uniform float spin = 0.0;
// 光芒有多细（越大越细）
uniform float ray_thin = 38.0;

void vertex() {
	// 面向镜头，但保留节点的缩放
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float cross_rays(vec2 p, float thin, float len) {
	float a = exp(-abs(p.x) * thin * (1.0 + abs(p.y) * 4.0)) * (1.0 - smoothstep(0.0, len, abs(p.y)));
	float b = exp(-abs(p.y) * thin * (1.0 + abs(p.x) * 4.0)) * (1.0 - smoothstep(0.0, len, abs(p.x)));
	return a + b;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float c = cos(spin);
	float s = sin(spin);
	p = mat2(vec2(c, -s), vec2(s, c)) * p;
	float r = length(p);
	float core = exp(-r * r * 90.0);
	float halo = exp(-r * 7.0) * 0.3;
	float rays = cross_rays(p, ray_thin, 1.0);
	vec2 q = mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071)) * p;
	float diag = cross_rays(q, ray_thin * 1.3, 0.45) * 0.45;
	float shape = core * 2.5 + halo + rays + diag;
	vec3 col = mix(glint_color.rgb, vec3(1.0), clamp(core * 2.0 + rays * 0.3, 0.0, 1.0));
	ALBEDO = col * shape * glint * 2.2;
}
