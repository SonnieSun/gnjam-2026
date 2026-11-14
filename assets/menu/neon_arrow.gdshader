// 以原箭头轮廓绘制圆截面霓虹灯管；光晕直接在 2D 绘制，不依赖 3D Glow。
shader_type canvas_item;
render_mode unshaded;

uniform float direction = 1.0;
uniform vec4 glow_color : source_color = vec4(0.56, 0.08, 1.0, 1.0);
uniform vec4 tube_color : source_color = vec4(0.82, 0.38, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.91, 1.0, 1.0);
uniform float tube_radius : hint_range(1.0, 5.0, 0.1) = 2.3;
uniform float glow_strength : hint_range(0.0, 2.0, 0.05) = 1.0;
varying vec2 local_position;

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 edge = b - a;
	float t = clamp(dot(p - a, edge) / dot(edge, edge), 0.0, 1.0);
	return length(p - a - edge * t);
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec4 tint = COLOR;
	vec2 p = vec2(local_position.x * direction, local_position.y);
	vec2 a = vec2(-42.0, 0.0);
	vec2 b = vec2(30.0, -48.0);
	vec2 c = vec2(12.0, 0.0);
	vec2 d = vec2(30.0, 48.0);
	float distance_to_tube = min(
		min(segment_distance(p, a, b), segment_distance(p, b, c)),
		min(segment_distance(p, c, d), segment_distance(p, d, a))
	);
	float aa = max(fwidth(distance_to_tube), 0.5);
	float tube = 1.0 - smoothstep(tube_radius - aa, tube_radius + aa, distance_to_tube);
	float core = 1.0 - smoothstep(0.5, 1.2 + aa * 0.4, distance_to_tube);
	float halo = glow_strength * (
		0.38 * exp(-distance_to_tube * distance_to_tube / 60.0)
		+ 0.18 * exp(-distance_to_tube * distance_to_tube / 230.0)
	);
	vec3 light_color = mix(glow_color.rgb, tube_color.rgb, tube);
	light_color = mix(light_color, core_color.rgb, core);
	float alpha = clamp(halo + tube * 0.8 + core * 0.5, 0.0, 1.0);
	alpha *= 1.0 - smoothstep(20.0, 28.0, distance_to_tube);
	COLOR = vec4(light_color, alpha) * tint;
}
