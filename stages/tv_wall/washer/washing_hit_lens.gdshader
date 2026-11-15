shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 lens_center = vec2(0.5);
uniform float lens_radius = 0.62;
uniform float aspect = 1.777778;
uniform vec2 screen_offset = vec2(0.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

void fragment() {
	vec2 axis = vec2(aspect, 1.0);
	vec2 delta = (SCREEN_UV - lens_center) * axis;
	float distance_from_center = length(delta) / lens_radius;
	float falloff = exp(-distance_from_center * distance_from_center * 2.5);
	// 非线性径向折射：中心鼓起，周边弯曲，不是整体等比缩放。
	vec2 warped = lens_center + delta / (1.0 + strength * falloff) / axis;
	warped += screen_offset;
	vec2 fringe = delta / axis * strength * falloff * 0.018;
	vec2 safe_min = vec2(0.001);
	vec2 safe_max = vec2(0.999);
	vec3 color;
	color.r = texture(screen_texture, clamp(warped + fringe, safe_min, safe_max)).r;
	color.g = texture(screen_texture, clamp(warped, safe_min, safe_max)).g;
	color.b = texture(screen_texture, clamp(warped - fringe, safe_min, safe_max)).b;
	ALBEDO = color;
	ALPHA = 1.0;
}
