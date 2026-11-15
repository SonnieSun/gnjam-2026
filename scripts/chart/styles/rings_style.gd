extends NoteStyle
## 圆圈往中心收：每个目标一个白色判定圈，音符是从外面收过来的圆环，和判定圈重合时按。
## 轨道 = 第几个目标（几个目标在画面上横着排开）。自转用虚线环表现出来。

## 判定圈半径（占画面短边的比例）
var target_ratio := 0.11
## 圆环最远从多大开始收（占画面长边的比例）
var start_ratio := 0.75


func target(i: int) -> Vector2:
	var s := area()
	return Vector2(s.x * (i + 1) / (lanes() + 1), s.y * 0.5)


func _r() -> float:
	var s := area()
	return minf(s.x, s.y) * target_ratio / sqrt(float(lanes()))


func _far() -> float:
	var s := area()
	return maxf(s.x, s.y) * start_ratio


## 辅助线：和音符一样大小的一圈；实线只画在这一拍有音符的目标上，虚线每个目标都画
func _draw_guide(g: Dictionary) -> void:
	var look := guide_look(g)
	var radius := lerpf(_r(), _far(), clampf(g.a, 0.0, 1.0))
	for i in lanes():
		if g.solid and not (g.lanes as Array).has(i):
			continue
		if look.dashed:
			draw_dashed_ring(target(i), radius, look.color, 2.0, 0.0, 36)
		else:
			draw_arc(target(i), radius, 0.0, TAU, 96, look.color, 3.0 * look.width, true)


func _draw() -> void:
	var r := _r()
	var far := _far()
	_draw_guides()
	for i in lanes():
		var t := target_look(i)
		draw_glow_ring(target(i), r, t.color, t.k * 1.5, 3.0)
		draw_arc(target(i), r, 0.0, TAU, 72, Color(t.color, 0.9), 3.0 * t.width, true)
	for n: NoteData in notes:
		if not showing(n):
			continue
		var f := fx(n)
		var a := maxf(approach(n), 0.0)
		var center := target(lane_of(n))
		var radius: float = lerpf(r, far, a) * f.scale
		var c: Color = f.color
		c.a = f.alpha
		draw_glow_ring(center, radius, c, f.glow, 6.0)
		draw_dashed_ring(center, radius, c, 6.0 * f.scale, f.angle)
		if n.length > 0.0:
			# 长按：尾巴是一圈细环，收到判定圈时松手
			var tail := (n.beat + n.length - beat) / lead_of(n)
			if tail > 0.0:
				draw_arc(center, lerpf(r, far, minf(tail, 1.0)), 0.0, TAU, 72, Color(c, c.a * 0.5), 2.0, true)
	for fl in flashes:
		var k: float = fl.age / HIT_FLASH_SECONDS
		draw_arc(target(clampi(fl.lane, 0, lanes() - 1)), r * (1.0 + k * 0.8), 0.0, TAU, 72,
				Color(fl.color, 1.0 - k), 8.0 * (1.0 - k) + 1.0, true)


## 音符本身就是一圈：不画实线，只补空拍的虚线
func _solid_guides() -> bool:
	return false
