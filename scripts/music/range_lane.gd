extends Control
## Music Director 里一条 track 的进度轨道：横轴是积累条进度 0-100%，色块是这条 track 响的区间。
##   空白处左键拖 = 画一段新区间；拖色块两头 = 改起止；拖色块中间 = 整段平移；
##   右键色块 = 删掉这段；双击 = 整条铺满 / 清空。
## 拖动吸附到 5% 网格和积累条的事件分数线。改完发 changed。

signal changed

const EDGE_PX := 7.0
const SNAP := 0.05

## 这条 track 在当前小关的区间，[[from, to], ...]（直接改这个数组，和配置是同一份）
var ranges: Array = []
var color := Color("ffd23f")
## 积累条事件分数线（0-1），画竖线、吸附用
var markers: PackedFloat32Array = []
## 播放头（当前进度）
var playhead := 0.0
## 现在是不是正在响（画亮一点）
var sounding := false

var _drag := ""          # "", "new", "left", "right", "move"
var _drag_i := -1
var _drag_from := 0.0
var _orig := []


func _ready() -> void:
	custom_minimum_size = Vector2(240, 26)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _x(p: float) -> float:
	return p * size.x


func _p(x: float) -> float:
	return clampf(x / maxf(size.x, 1.0), 0.0, 1.0)


func _snap(p: float) -> float:
	for m in markers:
		if absf(p - m) < 0.02:
			return m
	return clampf(roundf(p / SNAP) * SNAP, 0.0, 1.0)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.09, 0.07, 0.13))
	for k in range(1, 4):
		draw_line(Vector2(_x(k * 0.25), 0), Vector2(_x(k * 0.25), size.y), Color(1, 1, 1, 0.08))
	for m in markers:
		var x := _x(m)
		var y := 0.0
		while y < size.y:
			draw_line(Vector2(x, y), Vector2(x, minf(y + 3, size.y)), Color(1, 0.36, 0.56, 0.7))
			y += 6
	for rg in ranges:
		var a := _x(rg[0])
		var b := _x(rg[1])
		var c := color if sounding else color.darkened(0.35)
		draw_rect(Rect2(a, 3, maxf(b - a, 2.0), size.y - 6), c)
		draw_rect(Rect2(a, 3, 3, size.y - 6), c.lightened(0.4))
		draw_rect(Rect2(b - 3, 3, 3, size.y - 6), c.lightened(0.4))
	var px := _x(playhead)
	draw_line(Vector2(px, 0), Vector2(px, size.y), Color.WHITE, 2.0)


func _hit(x: float) -> Array:
	# [kind, index] of the range under x: its edges first, then its body
	for i in ranges.size():
		var a := _x(ranges[i][0])
		var b := _x(ranges[i][1])
		if absf(x - a) <= EDGE_PX:
			return ["left", i]
		if absf(x - b) <= EDGE_PX:
			return ["right", i]
	for i in ranges.size():
		if x > _x(ranges[i][0]) and x < _x(ranges[i][1]):
			return ["move", i]
	return ["", -1]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.double_click:
			if ranges.is_empty():
				ranges.append([0.0, 1.0])
			else:
				ranges.clear()
			_drag = ""
			_done()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var h := _hit(mb.position.x)
			_drag = h[0]
			_drag_i = h[1]
			_drag_from = _p(mb.position.x)
			if _drag == "":
				var p := _snap(_drag_from)
				ranges.append([p, p])
				_drag = "new"
				_drag_i = ranges.size() - 1
			_orig = ranges[_drag_i].duplicate()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _drag != "":
			var rg: Array = ranges[_drag_i]
			if rg[1] - rg[0] < 0.01:
				ranges.remove_at(_drag_i)
			_drag = ""
			_merge()
			_done()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var h := _hit(mb.position.x)
			if h[1] >= 0:
				ranges.remove_at(h[1])
				_done()
	elif event is InputEventMouseMotion:
		var p := _p(event.position.x)
		if _drag == "":
			var h := _hit(event.position.x)
			mouse_default_cursor_shape = CURSOR_HSIZE if h[0] in ["left", "right"] else (CURSOR_DRAG if h[0] == "move" else CURSOR_IBEAM)
			return
		var rg: Array = ranges[_drag_i]
		match _drag:
			"new":
				var a := _snap(_drag_from)
				var b := _snap(p)
				rg[0] = minf(a, b)
				rg[1] = maxf(a, b)
			"left":
				rg[0] = minf(_snap(p), rg[1])
			"right":
				rg[1] = maxf(_snap(p), rg[0])
			"move":
				var w: float = _orig[1] - _orig[0]
				var a := clampf(_snap(_orig[0] + p - _drag_from), 0.0, 1.0 - w)
				rg[0] = a
				rg[1] = a + w
		queue_redraw()


func _merge() -> void:
	# overlapping ranges become one
	ranges.sort_custom(func(x, y): return x[0] < y[0])
	var out := []
	for rg in ranges:
		if out.size() > 0 and rg[0] <= out[-1][1] + 0.0001:
			out[-1][1] = maxf(out[-1][1], rg[1])
		else:
			out.append([rg[0], rg[1]])
	ranges.clear()
	ranges.append_array(out)


func _done() -> void:
	queue_redraw()
	changed.emit()
