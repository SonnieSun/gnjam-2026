extends Control
## Music Director 里一条轨道下面的细条：横轴是积累条进度 0-100%，颜色是那段时间响的片段，
## 小竖条是切换点。拖切换点 = 改位置（吸附 5% 和积累条事件线）；右键切换点 = 删掉。

signal changed

const GRAB_PX := 8.0
const SNAP := 0.05

## 这条轨道在当前小关的切换点 [[进度, 片段 id], ...]（和配置是同一份数组）
var cues: Array = []
## 片段 id -> 颜色
var colors := {}
var markers: PackedFloat32Array = []
var playhead := 0.0

var _drag := -1


func _ready() -> void:
	custom_minimum_size = Vector2(200, 14)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _x(p: float) -> float:
	return p * size.x


func _snap(p: float) -> float:
	for m in markers:
		if absf(p - m) < 0.02:
			return m
	return clampf(roundf(p / SNAP) * SNAP, 0.0, 1.0)


func _sorted() -> Array:
	var s := cues.duplicate()
	s.sort_custom(func(a, b): return a[0] < b[0])
	return s


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.05, 0.1))
	var s := _sorted()
	for i in s.size():
		var a: float = s[i][0]
		var b: float = s[i + 1][0] if i + 1 < s.size() else 1.0
		var clip: String = s[i][1]
		if clip != "":
			draw_rect(Rect2(_x(a), 2, maxf(_x(b) - _x(a), 1.0), size.y - 4), colors.get(clip, Color.GRAY))
	for m in markers:
		draw_line(Vector2(_x(m), 0), Vector2(_x(m), size.y), Color(1, 0.36, 0.56, 0.8))
	for c in s:
		var x := _x(c[0])
		draw_rect(Rect2(x - 1.5, 0, 3, size.y), Color.WHITE)
	draw_line(Vector2(_x(playhead), -2), Vector2(_x(playhead), size.y + 2), Color(1, 1, 1, 0.9), 2.0)


func _nearest(x: float) -> int:
	var best := -1
	var dist := GRAB_PX
	for i in cues.size():
		var d := absf(_x(cues[i][0]) - x)
		if d <= dist:
			dist = d
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = _nearest(mb.position.x) if mb.pressed else -1
			if not mb.pressed:
				changed.emit()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var i := _nearest(mb.position.x)
			if i >= 0:
				cues.remove_at(i)
				queue_redraw()
				changed.emit()
	elif event is InputEventMouseMotion:
		if _drag >= 0:
			cues[_drag][0] = _snap(clampf(event.position.x / maxf(size.x, 1.0), 0.0, 1.0))
			queue_redraw()
		else:
			mouse_default_cursor_shape = CURSOR_HSIZE if _nearest(event.position.x) >= 0 else CURSOR_ARROW
