shader_type spatial;
// 迪斯科灯球的小镜片：每一片是一面小平镜，各自朝不同方向反光。
// 房间里没有环境反射（背景是纯色），真的金属材质只会发黑，所以这里自己“画”一个被反射的环境：
// 暗的底色 + 几盏彩色的灯。镜片朝着哪盏灯就亮成哪个颜色，朝着暗处就是黑的；灯球一转，亮片就跟着扫过去。
// 真的灯（射灯、点光）照上去仍然有金属高光。参数在 disco_ball_mirror.tres 里调。

// 镜片本身的颜色（金属色）
uniform vec3 tint : source_color = vec3(0.92, 0.88, 0.97);
uniform float metallic : hint_range(0.0, 1.0) = 1.0;
uniform float roughness : hint_range(0.02, 1.0) = 0.12;
// 假环境反射整体多亮
uniform float reflection : hint_range(0.0, 4.0) = 1.0;
// 朝着暗处的镜片有多亮（0 = 全黑）
uniform vec3 dark_color : source_color = vec3(0.1, 0.09, 0.13);
// 被反射的“房间”：一块块深浅不一的银灰，让镜片之间有碎碎的明暗差别
uniform vec3 room_color : source_color = vec3(0.62, 0.6, 0.7);
uniform float room_detail = 4.0;
// 被反射的四盏灯：方向（世界坐标，不用归一化）、颜色、光斑多大（越大越集中）
uniform vec3 light_a_dir = vec3(0.6, 0.5, 0.7);
uniform vec3 light_a_color : source_color = vec3(1.0, 0.98, 0.95);
uniform float light_a_focus = 2.6;
uniform vec3 light_b_dir = vec3(0.5, 0.9, -0.2);
uniform vec3 light_b_color : source_color = vec3(1.0, 0.45, 0.12);
uniform float light_b_focus = 4.5;
uniform vec3 light_c_dir = vec3(-0.8, 0.4, 0.3);
uniform vec3 light_c_color : source_color = vec3(1.0, 0.35, 0.8);
uniform float light_c_focus = 4.5;
uniform vec3 light_d_dir = vec3(0.1, -0.7, 0.6);
uniform vec3 light_d_color : source_color = vec3(0.75, 0.8, 1.0);
uniform float light_d_focus = 2.2;
// 每片镜子亮度随机差多少（0 = 都一样，1 = 有的全黑）
uniform float tile_variation : hint_range(0.0, 1.0) = 0.6;
// 整体自发光（脚本跟着拍子改这个，让灯球一闪一闪）
uniform float glow = 0.0;
uniform vec3 glow_color : source_color = vec3(0.85, 0.72, 0.98);
// 彩色镜片：每片带一点不同的颜色（粉 / 青 / 紫 / 金），0 = 都一样
uniform float rainbow : hint_range(0.0, 1.0) = 0.6;
// 闪烁：每片镜子隔一会儿“叮”地亮一下，像参考图里镜片上的星星点点
uniform float sparkle : hint_range(0.0, 12.0) = 5.0;
// 每片平均每秒闪几下
uniform float sparkle_rate = 0.45;
// 每次闪多短（越小越像一下子的闪光）
uniform float sparkle_sharp : hint_range(0.005, 0.3) = 0.05;
// 有多少比例的镜片会闪
uniform float sparkle_share : hint_range(0.0, 1.0) = 0.7;
uniform vec3 sparkle_color : source_color = vec3(1.0, 0.95, 1.0);
// 脚本跟着拍子改这个：每拍开头所有镜片的闪光一起变强
uniform float sparkle_boost = 0.0;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 lamp(vec3 r, vec3 dir, vec3 color, float focus) {
	return color * pow(max(dot(r, normalize(dir)), 0.0), focus * focus);
}

void fragment() {
	// 用屏幕导数算出这一片的平面法线：不管模型的法线是不是平滑过的，每片镜子都是一个平面
	vec3 n = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	if (dot(n, NORMAL) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	vec3 r = normalize((INV_VIEW_MATRIX * vec4(reflect(normalize(VERTEX), n), 0.0)).xyz);
	// 这一片在模型上的朝向，当成它的编号：同一片上处处一样，灯球转的时候跟着转
	vec3 n_model = normalize(transpose(mat3(MODEL_MATRIX)) * (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float id = hash(floor(n_model * 23.0 + 0.5));
	float vary = mix(1.0, id * id * 1.6, tile_variation);

	vec3 env = dark_color * (0.6 + 0.8 * id);
	float patch = hash(floor(r * room_detail) + 7.0);
	env += room_color * patch * patch * (0.35 + 0.65 * id);
	env += lamp(r, light_a_dir, light_a_color, light_a_focus) * 3.0;
	env += lamp(r, light_b_dir, light_b_color, light_b_focus) * 2.0;
	env += lamp(r, light_c_dir, light_c_color, light_c_focus) * 1.6;
	env += lamp(r, light_d_dir, light_d_color, light_d_focus) * 0.9;

	// 每片的颜色：粉紫青金之间挑一个，和银色按 rainbow 混
	float hue = hash(floor(n_model * 23.0 + 0.5) + 3.1);
	vec3 tile_tint = 0.55 + 0.45 * cos(6.2832 * (hue * 0.8 + vec3(0.0, 0.33, 0.67)));
	tile_tint = mix(vec3(1.0), tile_tint * 1.15, rainbow);
	env *= tile_tint;

	// 闪光：每片有自己的节奏和相位，周期开头亮一下就灭
	float seed_a = hash(floor(n_model * 23.0 + 0.5) + 11.7);
	float seed_b = hash(floor(n_model * 23.0 + 0.5) + 29.3);
	float t = fract(TIME * sparkle_rate * (0.6 + seed_a * 0.8) + seed_b);
	float flash = exp(-t / sparkle_sharp) * step(1.0 - sparkle_share, seed_a);
	// 朝着镜头的镜片闪得更亮（正对着看的那面才“晃眼”）
	float facing = pow(clamp(dot(n, normalize(-VERTEX)), 0.0, 1.0), 2.0);
	vec3 twinkle = sparkle_color * flash * (sparkle + sparkle_boost) * (0.3 + 0.7 * facing);

	ALBEDO = tint;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = env * tint * vary * reflection * metallic + glow_color * glow * tile_tint + twinkle;
}
