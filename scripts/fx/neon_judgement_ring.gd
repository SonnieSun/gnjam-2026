class_name NeonJudgementRing
extends RefCounted
## 所有层从传入的音符色派生，不引入参考图的蓝紫色。
static func draw(ci: CanvasItem, center: Vector2, radius: float, color: Color,
		time: float, weight: float = 1.0, impact: float = 0.0) -> void:
	var alpha := color.a
	var glow := color
	for layer in [3, 2, 1]:
		glow.a = alpha * 0.085 * float(4 - layer)
		ci.draw_arc(center, radius, 0.0, TAU, 160, glow, (4.0 + layer * 5.0) * weight, true)
	var rim := color
	rim.a = alpha * 0.95
	ci.draw_arc(center, radius, 0.0, TAU, 160, rim, 6.0 * weight, true)
	var core := color.lerp(Color.WHITE, 0.68)
	core.a = alpha
	ci.draw_arc(center, radius, 0.0, TAU, 160, core, 1.6 * weight, true)
	# 两条沿圆周缠绕的波带，摆幅受限，不遮挡舱门中央。
	for band in 2:
		var points := PackedVector2Array()
		for i in 161:
			var angle := TAU * float(i) / 160.0
			var wave := sin(angle * 7.0 + time * 2.4 + band * PI)
			var envelope := 0.45 + 0.55 * pow(absf(sin(angle * 2.0 - time * 0.7)), 3.0)
			var offset := (3.0 + wave * (6.0 + impact * 5.0) * envelope) * weight
			points.append(center + Vector2.from_angle(angle) * (radius + offset))
		glow.a = alpha * 0.1
		ci.draw_polyline(points, glow, 8.0 * weight, true)
		rim.a = alpha * (0.65 if band == 0 else 0.4)
		ci.draw_polyline(points, rim, 2.4 * weight, true)
	# 左上和右下的短条故障装饰，保持位置稳定，仅小幅呼吸。
	for side in 2:
		var angle := -0.5 if side == 0 else PI - 0.5
		var anchor := center + Vector2.from_angle(angle) * radius
		for bar in 3:
			var length := (19.0 + float((bar * 7 + side * 11) % 17)) * weight
			var offset := Vector2((bar - 1) * 5.0, (bar - 1) * 6.0) * weight
			var start := anchor + offset - Vector2(length * 0.5, 0.0)
			glow.a = alpha * 0.16
			ci.draw_line(start, start + Vector2(length, 0), glow, 7.0 * weight, true)
			rim.a = alpha * 0.8
			ci.draw_line(start, start + Vector2(length, 0), rim, 2.8 * weight, true)
			ci.draw_circle(start + Vector2(length * 0.3, 0), weight, core, true, -1.0, true)

static func draw_impact(ci: CanvasItem, center: Vector2, radius: float,
		_color: Color, age: float) -> void:
	if age >= 0.5:
		return
	var t := clampf(age / 0.5, 0.0, 1.0)
	var fade := 1.0 - smoothstep(0.12, 1.0, t)
	var expansion := 1.0 - pow(1.0 - t, 3.0)
	var ring_radius := radius + expansion * 85.0
	var white := Color(1.0, 1.0, 1.0, fade)
	# 成功瞬间的白色能量裙边：四片旋转镰形弧由门框撑开。
	# 中心留空，轮廓参照手绘断环与四向旋涡星芒。
	var spin := expansion * 0.55
	var blade_width := (18.0 + radius * 0.045) * (1.0 - t * 0.8)
	for blade in 4:
		var start_angle := TAU * blade / 4.0 + spin - 0.2
		var shape := PackedVector2Array()
		for j in 33:
			var u := float(j) / 32.0
			var a := start_angle + u * 1.18
			var bulge := pow(sin(u * PI), 0.7)
			shape.append(center + Vector2.from_angle(a) * (ring_radius + bulge * blade_width))
		for j in range(32, -1, -1):
			var u := float(j) / 32.0
			var a := start_angle + u * 1.18
			var bulge := pow(sin(u * PI), 0.7)
			shape.append(center + Vector2.from_angle(a) * (ring_radius - bulge * blade_width * 0.25))
		ci.draw_colored_polygon(shape, white)
		ci.draw_arc(center, ring_radius + blade_width + 12.0, start_angle + 0.1,
			start_angle + 0.85, 32, Color(1, 1, 1, fade * 0.65), 1.8, true)
	# 命中的前 80ms 给出贴合门框的硬闪，不靠全屏闪白。
	var snap := maxf(0.0, 1.0 - age / 0.08)
	if snap > 0.0:
		ci.draw_arc(center, radius, 0.0, TAU, 160, Color(1, 1, 1, snap), 18.0 * snap + 2.0, true)
	# 不均匀的断续亮环：细线骨架上有几段粗亮的能量弧。
	for i in 9:
		var start := TAU * i / 9.0 + 0.07
		var end := start + TAU / 9.0 - (0.035 if i % 3 == 0 else 0.012)
		var width := (3.0 + float(i % 3) * 2.0) * (1.0 - t * 0.5)
		ci.draw_arc(center, ring_radius, start, end, 32, Color(1, 1, 1, fade * 0.08), width + 14.0, true)
		ci.draw_arc(center, ring_radius, start, end, 32, Color(1, 1, 1, fade * 0.16), width + 6.0, true)
		ci.draw_arc(center, ring_radius, start, end, 32, white, width, true)
	# 五颗大小不同的四尖星，落在冲击环上；曲线内凹，尖端细长。
	for i in 5:
		var angle := ([-2.42, -2.02, -0.24, 0.9, 2.55][i] as float) + spin * 0.5
		var direction := Vector2.from_angle(angle)
		var pos := center + direction * ring_radius
		var star_size := [76.0, 42.0, 59.0, 78.0, 56.0][i] as float
		star_size *= (0.55 + sin(minf(t * 5.0, PI * 0.5)) * 0.45) * (1.0 - t * 0.55)
		var points := PackedVector2Array()
		for j in 64:
			var a := TAU * j / 64.0
			var x := pow(absf(cos(a)), 3.0) * signf(cos(a)) * star_size
			var y := pow(absf(sin(a)), 3.0) * signf(sin(a)) * star_size * 0.65
			points.append(pos + Vector2(x, y).rotated(angle + 0.22))
		var halo := PackedVector2Array()
		for p in points:
			halo.append(pos + (p - pos) * 1.18)
		ci.draw_colored_polygon(halo, Color(1, 1, 1, fade * 0.1))
		ci.draw_colored_polygon(points, white)
	# 音游式碎片：成簇的菱形、短条在命中后径向飞散。
	for i in 20:
		var angle := TAU * i / 20.0 + 0.22
		var direction := Vector2.from_angle(angle)
		var pos := center + direction * (radius + expansion * (100.0 + float(i % 4) * 15.0))
		var half_size := (3.0 + float(i % 3)) * (1.0 - t)
		var diamond := PackedVector2Array()
		for corner in 4:
			diamond.append(pos + Vector2.from_angle(TAU * corner / 4.0 + angle + t * 3.0) * half_size)
		ci.draw_colored_polygon(diamond, Color(1, 1, 1, fade * 0.9))
	# 细长的放射光刺，主要位于光环外侧，不覆盖猫脸。
	for i in 26:
		var angle := TAU * i / 26.0 + sin(float(i * 17)) * 0.07
		var direction := Vector2.from_angle(angle)
		var tangent := direction.orthogonal()
		var start := center + direction * (ring_radius + 8.0 + float(i % 4) * 5.0)
		var length := (24.0 + float((i * 19) % 53)) * (1.0 - t * 0.65)
		var points := PackedVector2Array([start - tangent * 0.9, start + direction * length, start + tangent * 0.9])
		ci.draw_colored_polygon(points, Color(1, 1, 1, fade * (0.9 if i % 3 == 0 else 0.6)))

static func draw_charge(ci: CanvasItem, center: Vector2, radius: float,
		color: Color, ahead: float, time: float) -> void:
	var charge := clampf(1.0 - ahead / 0.8, 0.0, 1.0)
	if charge <= 0.0:
		return
	var c := color
	c.a *= charge * 0.8
	for i in 8:
		var angle := TAU * i / 8.0 + time * 0.35
		var direction := Vector2.from_angle(angle)
		var distance := radius + (1.0 - charge) * 45.0
		ci.draw_line(center + direction * distance, center + direction * (distance + 8.0 + charge * 10.0), c, 2.5, true)
	# 贴近判定线时出现局部电弧，命中后由爆发效果接替。
	for i in 3:
		var start := time * 2.0 + TAU * i / 3.0
		ci.draw_arc(center, radius + 4.0, start, start + 0.3 + charge * 0.5, 24, c, 3.0 + charge * 2.0, true)
