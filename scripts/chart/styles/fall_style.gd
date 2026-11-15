extends NoteStyle
## 2D 下落式：几条竖着的轨道，音符从上面落到底下的判定线，落到线上时按。
## 轨道 = 第几条道。音符是横条，大小 / 旋转 / 发光都作用在横条上；长按带一条尾巴。

## 判定线在画面多高的位置（0 顶 ~ 1 底）
var judge_ratio := 0.82
## 一条道多宽（像素，最大值）
var lane_width := 120.0


func _lane_w() -> float:
	return minf(lane_width, area().x * 0.7 / lanes())


func lane_x(i: int) -> float:
	var w := _lane_w()
	return area().x / 2.0 + (i - (lanes() - 1) / 2.0) * w


func _y(a: float) -> float:
	return lerpf(area().y * judge_ratio, -30.0, a)


## 辅助线：横跨所有轨道的一条线，在这一拍落到的高度
func _draw_guide(g: Dictionary) -> void:
	var look := guide_look(g)
	var w := _lane_w()
	var y := _y(clampf(g.a, -0.1, 1.0))
	var from := Vector2(lane_x(0) - w / 2.0, y)
	var to := Vector2(lane_x(lanes() - 1) + w / 2.0, y)
	if look.dashed:
		draw_dashed_line(from, to, look.color, 1.5, 8.0)
	else:
		draw_line(from, to, look.color, 3.0 * look.width)


func _draw() -> void:
	var s := area()
	var w := _lane_w()
	var jy := s.y * judge_ratio
	for i in lanes():
		var x := lane_x(i)
		draw_rect(Rect2(x - w / 2.0 + 2.0, 0.0, w - 4.0, s.y), Color(0.05, 0.03, 0.1, 0.55))
	_draw_guides()
	var t := target_look()
	var x0 := lane_x(0) - w / 2.0
	var x1 := lane_x(lanes() - 1) + w / 2.0
	if t.k > 0.01:
		draw_line(Vector2(x0, jy), Vector2(x1, jy), Color(t.color, t.k * 0.35), 18.0 * t.k)
	draw_line(Vector2(x0, jy), Vector2(x1, jy), Color(t.color, 0.95), 4.0 * t.width)
	for n: NoteData in notes:
		if not showing(n):
			continue
		var f := fx(n)
		var x := lane_x(lane_of(n))
		var y := _y(maxf(approach(n), 0.0) if n.length > 0.0 else approach(n))
		var c: Color = Color(f.color, f.alpha)
		if n.length > 0.0:
			var y_end := _y(clampf((n.beat + n.length - beat) / lead_of(n), 0.0, 1.0))
			draw_rect(Rect2(x - w * 0.18, y_end, w * 0.36, maxf(y - y_end, 0.0)), Color(c, c.a * 0.5))
		var size: Vector2 = Vector2(w * 0.82, 20.0) * f.scale
		draw_set_transform(Vector2(x, y), f.angle, Vector2.ONE)
		if f.glow > 0.01:
			for k in 3:
				var grow: float = (k + 1) * 6.0 * minf(f.glow, 2.0)
				draw_rect(Rect2(-size / 2.0 - Vector2(grow, grow), size + Vector2(grow, grow) * 2.0),
						Color(c, clampf(f.glow * 0.2 / (k + 1), 0.0, 0.5)))
		draw_rect(Rect2(-size / 2.0, size), c)
		draw_rect(Rect2(-size / 2.0, size), Color(1, 1, 1, c.a * 0.8), false, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for fl in flashes:
		var k: float = fl.age / HIT_FLASH_SECONDS
		var x := lane_x(clampi(fl.lane, 0, lanes() - 1))
		draw_rect(Rect2(x - w / 2.0, jy - 30.0 * (1.0 - k), w, 60.0 * (1.0 - k)), Color(fl.color, (1.0 - k) * 0.7))
