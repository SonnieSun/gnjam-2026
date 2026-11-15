shader_type spatial;
// 迪斯科关卡的长路地板：一张很大的平面，按世界坐标画格子。
//   方格地板（和房间一样的粉白砖）-> 跟拍变色的舞池地板 -> 深色底上的霓虹网格线
// 路只画中间 half_width 宽的一条（往前只画到 reveal 那么远，做「地板变长」）；
// 到了终点画一个大圆台。travel = 猫已经往前滑了多远（格子跟着往后流）。
render_mode cull_disabled;

uniform float tile = 4.8;           // 一格多大（和房间地砖一样）
uniform float half_width = 19.2;    // 路的半宽
uniform float reveal = 0.0;         // 路往前铺了多远（从猫脚下算）
uniform float travel = 0.0;         // 已经滑了多远
uniform float beat = 0.0;           // 当前拍数（舞池变色用）
uniform float dance = 0.0;          // 0 = 方格地板，1 = 舞池地板
uniform float grid = 0.0;           // 0 = 舞池，1 = 霓虹网格
uniform float plaza = 0.0;          // 0 = 没有圆台，1 = 有
uniform float plaza_dist = 1000.0;  // 圆台中心在前面多远（从猫脚下算，随着滑行变小）
uniform float plaza_radius = 46.0;
uniform float dance_saturation = 0.6;  // 舞池格子颜色多鲜
uniform float dance_brightness = 0.6;  // 舞池格子多亮
uniform vec3 tile_a : source_color = vec3(0.96, 0.62, 0.72);
uniform vec3 tile_b : source_color = vec3(0.99, 0.90, 0.86);
uniform vec3 grid_color : source_color = vec3(0.35, 0.75, 1.0);
uniform vec3 grid_color2 : source_color = vec3(1.0, 0.35, 0.85);
// 远处的格子挤成一片会闪（晃眼）：格子在屏幕上小到这个程度就开始化成一片均匀的暗光（数越小化得越早）
uniform float far_soften = 0.1;
// 化开以后远处还剩多亮（相对近处格线的亮度）
uniform float far_glow = 0.1;
// 从多远开始暗下去、到多远全黑
uniform float fade_start = 60.0;
uniform float fade_end = 260.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 前进方向是 -z：ahead = 在猫前面多远
	float ahead = -world_pos.z;
	vec2 p = vec2(world_pos.x, world_pos.z - travel);  // 跟着滑行往后流的坐标
	vec2 cell = floor(p / tile);
	vec2 f = fract(p / tile);
	// 一个像素跨了多少格：近处很小，越远越大。大到一定程度格子就画不清了，只会闪，这时把细节化掉
	vec2 px = fwidth(p / tile);
	float blur = max(px.x, px.y);
	float detail = 1.0 - smoothstep(far_soften, far_soften * 4.0, blur);

	// 方格
	float checker = mod(cell.x + cell.y, 2.0);
	vec3 base = mix(tile_a, tile_b, checker);
	float seam = step(f.x, 0.04) + step(f.y, 0.04);
	base *= 1.0 - clamp(seam, 0.0, 1.0) * 0.12;
	base = mix((tile_a + tile_b) * 0.5, base, detail);

	// 舞池：每格一个颜色，每拍换一批，格子中间亮、边上暗
	float step_beat = floor(beat);
	float pick = hash(cell + step_beat * 0.37);
	vec3 dance_col = hue(pick + beat * 0.03);
	dance_col = mix(vec3(dot(dance_col, vec3(0.299, 0.587, 0.114))), dance_col, dance_saturation) * dance_brightness;
	float lit = step(0.35, hash(cell * 1.7 + step_beat));  // 一部分格子这一拍不亮
	vec2 d = abs(f - 0.5) * 2.0;
	float pad = 1.0 - smoothstep(0.75, 0.98, max(d.x, d.y));
	float pulse = exp(-fract(beat) * 3.0);
	vec3 dance_emit = dance_col * pad * (0.25 + lit * (0.55 + pulse * 0.6));
	// 远处的舞池格子不再一格一格地闪，化成一片跟拍微微起伏的暗色
	vec3 dance_far = hue(beat * 0.03) * dance_brightness * mix(1.0, dance_saturation, 0.5) * (0.22 + pulse * 0.08);
	dance_emit = mix(dance_far, dance_emit, detail);

	// 霓虹网格：只留格线发光
	// 两个方向的线分开算，各自按屏幕上的粗细抗锯齿；细到不到一个像素的线不再硬画（那样会一闪一闪）
	vec2 edge = min(f, 1.0 - f);
	vec2 lines = 1.0 - smoothstep(vec2(0.0), vec2(0.06) + px, edge);
	lines *= clamp(0.06 / max(px, vec2(0.0001)), 0.0, 1.0);
	float line = max(lines.x, lines.y);
	vec3 line_col = mix(grid_color, grid_color2, 0.5 + 0.5 * sin(ahead * 0.02 + beat * 0.5));
	vec3 grid_emit = line_col * mix(far_glow, line, detail) * (1.2 + pulse * 0.8);

	// 哪些地方有地板：路 + 圆台
	float side = 1.0 - smoothstep(half_width - 0.3, half_width, abs(world_pos.x));
	float front = 1.0 - smoothstep(reveal - 2.0, reveal, ahead);
	float road_end = mix(1.0, 1.0 - step(plaza_dist, ahead), plaza);  // 有圆台时路只到圆台中心为止
	float road = side * front * road_end * step(-30.0, ahead);
	float disc_d = length(vec2(world_pos.x, ahead - plaza_dist));
	float disc = plaza * (1.0 - smoothstep(plaza_radius - 0.5, plaza_radius, disc_d));
	float rim = plaza * smoothstep(plaza_radius - 2.5, plaza_radius - 1.0, disc_d) * disc;
	float mask = max(road, disc);
	if (mask < 0.5) {
		discard;
	}

	vec3 albedo = mix(base, vec3(0.03, 0.03, 0.06), max(dance * 0.85, grid));
	vec3 emit = base * 0.22 * (1.0 - dance);
	emit = mix(emit, dance_emit, dance * (1.0 - grid));
	emit += grid_emit * grid;
	emit += line_col * rim * 2.0;
	// 远处渐渐暗下去，地平线不刺眼
	float fog = 1.0 - smoothstep(fade_start, fade_end, ahead);
	ALBEDO = albedo;
	EMISSION = emit * fog;
	ROUGHNESS = mix(0.6, 0.25, dance);
}
