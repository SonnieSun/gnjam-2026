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
	var ring_radius := radius + expansion * 48.0
	var white := Color(1.0, 1.0, 1.0, fade)
	# 不均匀的断续亮环：细线骨架上有几段粗亮的能量弧。
	for i in 9:
		var start := TAU * i / 9.0 + 0.07
		var end := start + TAU / 9.0 - (0.035 if i % 3 == 0 else 0.012)
		var width := (2.0 + float(i % 3) * 1.4) * (1.0 - t * 0.5)
		ci.draw_arc(center, ring_radius, start, end, 32, Color(1, 1, 1, fade * 0.08), width + 14.0, true)
		ci.draw_arc(center, ring_radius, start, end, 32, Color(1, 1, 1, fade * 0.16), width + 6.0, true)
		ci.draw_arc(center, ring_radius, start, end, 32, white, width, true)
	# 五颗大小不同的四尖星，落在冲击环上；曲线内凹，尖端细长。
	for i in 5:
		var angle := [-2.42, -2.02, -0.24, 0.9, 2.55][i] as float
		var direction := Vector2.from_angle(angle)
		var pos := center + direction * ring_radius
		var star_size := [48.0, 34.0, 29.0, 45.0, 36.0][i] as float
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
