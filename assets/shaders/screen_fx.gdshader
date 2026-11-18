// 全屏镜头特效：把已经画好的整个画面再加工一遍。挂在 Main/ScreenFx 下面的一块全屏矩形上，
// 由 scripts/fx/screen_fx.gd 按积累条进度改下面这些值。全部是中性值时那块矩形会被藏起来，不花性能。
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;

// 每边铺几格：1 = 原样，3 = 九宫格（中间值是缩小铺开的过程）
uniform float tiles = 1.0;
// 万花筒的浓度：0 = 关，1 = 全开
uniform float kaleido : hint_range(0.0, 1.0) = 0.0;
// 万花筒第一圈分成几瓣（往外每一圈成倍增加）
uniform float segments = 6.0;
// 一圈和下一圈隔多远，占屏幕高度的比例
uniform float ring_spacing = 0.42;
// 万花筒取景的缩放：越大，每片花瓣里看到的范围越广
uniform float kaleido_zoom = 1.7;
// 万花筒转到的角度
uniform float spin = 0.0;
// 左右镜像的浓度
uniform float mirror : hint_range(0.0, 1.0) = 0.0;
// 上下镜像的浓度（和左右镜像一起开 = 四向对称）
uniform float mirror_y : hint_range(0.0, 1.0) = 0.0;
// 镜像时把画面往两边挪多少（占屏幕宽 / 高的比例）。0 = 对称轴穿过画面正中间——主角在正中间时几乎看不出镜像；
// 0.25 = 画面正中间的东西落在每一半的正中间：一左一右（或一上一下）两个互为镜像的主角
uniform float mirror_shift = 0.0;
uniform float mirror_shift_y = 0.0;
// 竖着切成几条（1 = 不切）：每一条里都是画面正中间那一条，原大小；两边的条左右翻过来、推近一点，像几台机位并排
uniform float panels = 1.0;
// 红蓝错位的距离（占屏幕宽度的比例）
uniform float rgb_split = 0.0;
// 推近：1 = 原样，1.4 = 放大到 1.4 倍
uniform float zoom = 1.0;
// 反色的浓度
uniform float invert : hint_range(0.0, 1.0) = 0.0;
// 鲜艳程度：1 = 原样，大于 1 更鲜艳（连击高了），小于 1 褪色（连击断了的一瞬间）
uniform float saturation = 1.0;
// 白闪（切换镜头的一瞬间）
uniform float flash = 0.0;
// 宫格里每一格自己再放大多少（打中的瞬间每一格一起胀一下）：0 = 不放大
uniform float tile_pop = 0.0;
// 格子之间的缝，占一格的比例
uniform float gap = 0.012;

vec3 sample_rgb(vec2 uv) {
	uv = abs(mod(uv + 1.0, 2.0) - 1.0);  // 超出画面就镜像回来
	if (rgb_split > 0.0001) {
		vec2 d = vec2(rgb_split, 0.0);
		return vec3(texture(screen, uv + d).r, texture(screen, uv).g, texture(screen, uv - d).b);
	}
	return texture(screen, uv).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	uv = (uv - 0.5) / zoom + 0.5;
	uv.x = mix(uv.x, 0.5 + mirror_shift - abs(uv.x - 0.5), mirror);
	uv.y = mix(uv.y, 0.5 + mirror_shift_y - abs(uv.y - 0.5), mirror_y);
	float panel_line = 0.0;
	if (panels > 1.5) {
		float n = floor(panels + 0.5);
		float idx = floor(uv.x * n);
		float px = fract(uv.x * n);
		float off = idx - (n - 1.0) * 0.5;          // 离正中间那一条几条远（0 = 正中间）
		panel_line = 1.0 - smoothstep(0.0, 0.02, min(px, 1.0 - px));
		if (abs(off) > 0.25) {
			if (mod(abs(off), 2.0) > 0.5) {
				px = 1.0 - px;
			}
			float z = 1.0 + 0.35 * abs(off);
			px = (px - 0.5) / z + 0.5;
			uv.y = (uv.y - 0.5) / z + 0.5;
		}
		uv.x = (px - 0.5) / n + 0.5;
	}
	// 宫格：以屏幕中心为基准缩小，铺满
	// 奇数格（3×3）屏幕正中间是一整格；偶数格（2×2、4×4）要错开半格，
	// 不然屏幕中心落在接缝上，四周各露出半格。中间值平滑过渡。
	float tile_shift = 0.5 * abs(mod(tiles, 2.0) - 1.0);
	vec2 f = fract((uv - 0.5) * tiles + 0.5 + tile_shift);
	vec2 f_in = (f - 0.5) / (1.0 + tile_pop) + 0.5;  // 每一格里的画面以自己的中心放大
	vec3 grid_col = sample_rgb(tiles > 1.01 ? f_in : uv);
	if (tiles > 1.01) {
		vec2 edge = min(f, 1.0 - f);
		float line = 1.0 - smoothstep(gap * 0.5, gap, min(edge.x, edge.y));
		grid_col = mix(grid_col, vec3(0.02, 0.01, 0.08), line * clamp((tiles - 1.0) * 2.0, 0.0, 1.0));
	}
	vec3 col = grid_col;
	if (kaleido > 0.001) {
		// 万花筒：中间一份，外面一圈圈对折成花瓣，每片花瓣里都是同一个画面
		vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
		float r = length(p);
		float row = floor(r / ring_spacing + 0.5);
		vec2 local;
		if (row < 0.5) {
			local = p;
		} else {
			float dir = mod(row, 2.0) < 0.5 ? -1.0 : 1.0;  // 相邻两圈反着转
			float seg = TAU / (segments * row);
			float a = mod(atan(p.x, -p.y) + spin * dir / row, seg) - seg * 0.5;
			local = vec2(r * sin(abs(a)), (row * ring_spacing - r * cos(a)) * dir);
		}
		col = mix(col, sample_rgb(local * kaleido_zoom / vec2(aspect, 1.0) + 0.5), kaleido);
	}
	col = mix(col, vec3(0.02, 0.01, 0.08), panel_line * (1.0 - kaleido));
	col = mix(col, 1.0 - col, invert);
	col = max(mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, saturation), vec3(0.0));
	COLOR = vec4(col + flash, 1.0);
}
