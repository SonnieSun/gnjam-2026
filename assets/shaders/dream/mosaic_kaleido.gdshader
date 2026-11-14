// 整个画面的后期：九宫格（把同一个画面缩小平铺）和万花筒（绕屏幕中心对折成花瓣）。
// 挂在 3D 关卡的 View 节点上，由关卡脚本改 tiles / kaleido 两个值来切换。
shader_type canvas_item;

// 每边铺几格：1 = 原样，3 = 九宫格（中间值是缩小铺开的过程）
uniform float tiles = 1.0;
// 万花筒的浓度：0 = 关，1 = 全开
uniform float kaleido : hint_range(0.0, 1.0) = 0.0;
// 万花筒第一圈分成几瓣（往外每一圈翻倍、再翻倍）
uniform float segments = 6.0;
// 一圈和下一圈隔多远，占屏幕高度的比例
uniform float ring_spacing = 0.42;
// 万花筒转到的角度（脚本每帧改）
uniform float spin = 0.0;
// 万花筒取景的缩放：越大，每片花瓣里看到的范围越广（猫越小）
uniform float kaleido_zoom = 1.7;
// 白闪（切换镜头的一瞬间）
uniform float flash = 0.0;
// 格子之间的缝，占一格的比例
uniform float gap = 0.012;

void fragment() {
	vec2 uv = UV;
	float aspect = TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x;
	// 九宫格：以屏幕中心为基准缩小，铺满
	vec2 cell = (uv - 0.5) * tiles + 0.5;
	vec2 f = fract(cell);
	vec4 grid_col = texture(TEXTURE, f);
	if (tiles > 1.01) {
		vec2 edge = min(f, 1.0 - f);
		float line = 1.0 - smoothstep(gap * 0.5, gap, min(edge.x, edge.y));
		grid_col.rgb = mix(grid_col.rgb, vec3(0.02, 0.01, 0.08), line * clamp((tiles - 1.0) * 2.0, 0.0, 1.0));
	}
	// 万花筒：中间一只，外面一圈圈对折成花瓣，每片花瓣里都是同一个画面
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
	vec2 kuv = local * kaleido_zoom / vec2(aspect, 1.0) + 0.5;
	// 超出画面就镜像回来，边上不会出现黑块
	kuv = abs(mod(kuv + 1.0, 2.0) - 1.0);
	vec4 k_col = texture(TEXTURE, kuv);
	COLOR = mix(grid_col, k_col, kaleido);
	COLOR.rgb += flash;
	COLOR.a = 1.0;
}
