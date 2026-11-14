// 梦幻天穹：套在一个很大的球的内侧。上深下亮的渐变 + 细细的经纬网格线。
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;

uniform vec3 top_color : source_color = vec3(0.01, 0.01, 0.10);
uniform vec3 mid_color : source_color = vec3(0.03, 0.05, 0.36);
uniform vec3 horizon_color : source_color = vec3(0.26, 0.10, 0.50);
// 网格线的颜色和亮度
uniform vec3 line_color : source_color = vec3(0.6, 0.75, 1.0);
uniform float line_strength = 0.16;
// 一圈分成多少格（经线）/ 从底到顶多少格（纬线）
uniform float grid_u = 36.0;
uniform float grid_v = 18.0;
uniform float line_width = 0.03;
// 整体亮度（脚本在打中时会把它闪一下）
uniform float boost = 1.0;

varying vec3 dir;

void vertex() {
	dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(dir);
	float h = d.y * 0.5 + 0.5;
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.42, 0.62, h));
	col = mix(col, top_color, smoothstep(0.6, 0.95, h));
	col = mix(col, horizon_color * 0.6, smoothstep(0.45, 0.2, h) * 0.6);
	float u = atan(d.z, d.x) / TAU * grid_u;
	float v = acos(clamp(d.y, -1.0, 1.0)) / PI * grid_v;
	float gu = 1.0 - smoothstep(0.0, line_width, min(fract(u), 1.0 - fract(u)));
	float gv = 1.0 - smoothstep(0.0, line_width, min(fract(v), 1.0 - fract(v)));
	float g = max(gu, gv);
	col += line_color * g * line_strength;
	ALBEDO = col * boost;
}
