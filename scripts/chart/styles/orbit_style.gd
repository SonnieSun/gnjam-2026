extends NoteStyle
## 沿轨道对虚影：一个物体沿圆形轨道匀速转（转一圈 = pattern.beats_per_rev 拍），
## 每个音符在“那一拍物体会转到的位置”放一个虚影，物体和虚影重合时按。
## 轨道 = 第几圈（一圈一个物体，从外往里）。音符的大小 / 旋转 / 发光作用在虚影上。

## 最外圈半径（占画面短边的比例）
var orbit_ratio := 0.36
## 物体半径（像素）
var body_radius := 26.0


func _orbit_radius(i: int) -> float:
	var s := area()
	return minf(s.x, s.y) * orbit_ratio * (1.0 - i * 0.22)


func _rev() -> float:
	return pattern.beats_per_rev if pattern else 8.0


## 第 b 拍时物体在轨道上的位置（第 0 拍在正上方，顺时针转）
func pos_at(b: float, lane: int) -> Vector2:
	var ang := b / _rev() * TAU - PI / 2.0
	return area() / 2.0 + Vector2.from_angle(ang) * _orbit_radius(lane)


## 辅助线：轨道上一道径向的刻度，在这一拍物体会转到的角度。实线横跨所有轨道圈
func _draw_guide(g: Dictionary) -> void:
	var look := guide_look(g)
	var center := area() / 2.0
	var dir := Vector2.from_angle(float(g.beat) / _rev() * TAU - PI / 2.0)
	var outer := _orbit_radius(0) + body_radius * 1.2
	var inner := _orbit_radius(lanes() - 1) - body_radius * 1.2
	if look.dashed:
		draw_line(center + dir * (outer - body_radius * 0.8), center + dir * outer, look.color, 2.0, true)
	else:
		draw_line(center + dir * inner, center + dir * outer, look.color, 3.0 * look.width, true)


func _draw() -> void:
	var center := area() / 2.0
	for i in lanes():
		draw_arc(center, _orbit_radius(i), 0.0, TAU, 128, Color(1, 1, 1, 0.18), 2.0, true)
	_draw_guides()
	# 虚影
	for n: NoteData in notes:
		if not showing(n):
			continue
		var f := fx(n)
		var p := pos_at(n.beat, lane_of(n))
		var rad: float = body_radius * f.scale
		var c: Color = f.color
		var near := clampf(1.0 - absf(approach(n)) * 3.0, 0.0, 1.0)  # 快到了虚影变实
		draw_glow_dot(p, rad, c, f.glow)
		draw_circle(p, rad, Color(c, f.alpha * (0.18 + 0.3 * near)))
		draw_dashed_ring(p, rad, Color(c, f.alpha * 0.9), 3.0, f.angle, 8)
		if n.length > 0.0:
			var a0 := n.beat / _rev() * TAU - PI / 2.0
			var a1 := (n.beat + n.length) / _rev() * TAU - PI / 2.0
			draw_arc(center, _orbit_radius(lane_of(n)), a0, a1, 32, Color(c, f.alpha * 0.45), rad * 1.2, true)
	# 物体（每圈一个）
	for i in lanes():
		var p := pos_at(beat, i)
		var t := target_look(i)
		draw_glow_dot(p, body_radius, t.color, t.k * 1.5)
		draw_circle(p, body_radius, Color(1, 1, 1, 0.95))
		draw_arc(p, body_radius + 2.0, 0.0, TAU, 40, t.color, 3.0 * t.width, true)
		draw_circle(p, body_radius * 0.45, Color(0.15, 0.1, 0.25))
	for fl in flashes:
		var k: float = fl.age / HIT_FLASH_SECONDS
		var n: NoteData = fl.note
		draw_arc(pos_at(n.beat, lane_of(n)), body_radius * (1.2 + k * 1.5), 0.0, TAU, 48,
				Color(fl.color, 1.0 - k), 6.0 * (1.0 - k) + 1.0, true)
