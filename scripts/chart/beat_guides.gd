class_name BeatGuides
extends RefCounted
## 节拍辅助线的统一规则。所有关卡（不管音符长什么样、从哪飞过来）和谱面编辑器的表现方式都用这一套：
##   不用按的拍子：淡淡的白色虚线，只用来数拍子（每 step 拍一条）；
##   要按的拍子（有音符，包括不在整拍上的音符）：音符颜色的实线，比虚线粗，越靠近判定越亮、越粗、越偏白；
##   判定点「预亮」：离下一个要按的音符不到一拍时，判定圈 / 判定线染上那个音符的颜色、越来越亮。
## 每个关卡只要回答一件事：远近为 a（1 = 刚出现，0 = 判定点）的那一拍在画面上哪里，再按 look() 给的颜色粗细画出来。

## 辅助线列表，从远到近。每项：
##   beat 第几拍  a 远近（1 = 刚出现，0 = 判定点）  solid 是不是要按的拍子  color 颜色
##   k 有多近（0 远 ~ 1 到了）  notes 这一拍的音符（虚线是空的）
## lead = 提前几拍出现；color_of(note) -> Color；lead_of(note) -> float（每个音符可以有自己的出现时间，不给就用 lead）
static func compute(notes: Array, beat: float, lead: float, step := 1.0,
		color_of := Callable(), lead_of := Callable()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var solid := {}
	for n: NoteData in notes:
		if n.judged:
			continue
		var l: float = lead_of.call(n) if lead_of.is_valid() else lead
		var a := (n.beat - beat) / maxf(l, 0.01)
		if a > 1.0:
			if not lead_of.is_valid():
				break
			continue
		if a < -0.1:
			continue
		var key := roundi(n.beat * 100.0)
		if solid.has(key):
			(solid[key].notes as Array).append(n)
			continue
		var c: Color = color_of.call(n) if color_of.is_valid() else Color.WHITE
		var g := {"beat": n.beat, "a": a, "solid": true, "color": c, "k": 1.0 - clampf(a, 0.0, 1.0), "notes": [n]}
		solid[key] = g
		out.append(g)
	step = maxf(step, 0.125)
	var b := ceilf(beat / step) * step
	while b <= beat + lead:
		if not solid.has(roundi(b * 100.0)):
			out.append({"beat": b, "a": (b - beat) / maxf(lead, 0.01), "solid": false, "color": Color.WHITE,
					"k": 0.0, "notes": []})
		b += step
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.a > y.a)
	return out


## 一条辅助线的样子：{color, width（粗细倍数，实线 1 ~ 2.2，虚线 0.5）, dashed}
static func look(g: Dictionary) -> Dictionary:
	var a: float = clampf(g.a, 0.0, 1.0)
	if g.solid:
		var k: float = g.k
		var c: Color = (g.color as Color).lerp(Color.WHITE, k * k * 0.35)
		c.a = 0.3 + 0.7 * k * k
		return {"color": c, "width": 1.0 + k * 1.2, "dashed": false}
	# 远处也要看得清（原来远处几乎看不见）：基础更亮，远处只淡一点
	return {"color": Color(1, 1, 1, 0.42 * (1.0 - a * 0.3)), "width": 0.7, "dashed": true}


## 判定点预亮：{k: 0~1（0 = 一拍内没有要按的）, color}。filter(note) -> bool 可以只看一部分音符（比如某条轨道）
static func anticipation(notes: Array, beat: float, color_of := Callable(), filter := Callable()) -> Dictionary:
	for n: NoteData in notes:
		if n.judged or (filter.is_valid() and not filter.call(n)):
			continue
		var ahead := n.beat - beat
		if ahead < -0.1:
			continue
		if ahead > 1.0:
			break
		var k := 1.0 - clampf(ahead, 0.0, 1.0)
		return {"k": k * k, "color": color_of.call(n) if color_of.is_valid() else Color.WHITE}
	return {"k": 0.0, "color": Color.WHITE}


## 预亮后的判定圈 / 判定线：{color（从 base 往音符颜色变）, width（粗细倍数）, k}
static func target_look(ant: Dictionary, base := Color.WHITE) -> Dictionary:
	var k: float = ant.k
	return {"color": base.lerp(ant.color, k * 0.85), "width": 1.0 + k * 1.3, "k": k}


# ---- 2D 画法小工具 ----

## 画一圈辅助线（squash < 1 = 压扁成透视的椭圆）。base_width = 实线的基础粗细
static func draw_ring(ci: CanvasItem, center: Vector2, radius: float, l: Dictionary,
		base_width := 3.0, squash := 1.0, scale_x := 1.0) -> void:
	var pts := PackedVector2Array()
	var count := 96
	for i in count + 1:
		var ang := i * TAU / count
		pts.append(center + Vector2(cos(ang) * radius * scale_x, sin(ang) * radius * scale_x * squash))
	if l.dashed:
		for i in range(0, count, 3):
			ci.draw_line(pts[i], pts[i + 1], l.color, 2.5, true)
	else:
		ci.draw_polyline(pts, l.color, base_width * l.width, true)


## 判定圈预亮时外面加一圈光晕
static func draw_target_glow(ci: CanvasItem, center: Vector2, radius: float, t: Dictionary,
		squash := 1.0, scale_x := 1.0) -> void:
	if t.k <= 0.01:
		return
	for k in 3:
		draw_ring(ci, center, radius, {"color": Color(t.color, t.k * 0.25 / (k + 1)), "width": 1.0, "dashed": false},
				6.0 + k * 6.0, squash, scale_x)
