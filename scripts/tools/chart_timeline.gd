extends Control
## 谱面编辑器下面的时间轴：横着是拍子（循环的一遍），竖着一行一条轨道。
##
##   左键点空白         在那里放一个音符（吸附到网格，音色 = 当前笔刷）
##   左键点音符         选中（按住 Shift 加选 / 取消）；拖动 = 移动（左右改拍子，上下换轨道）
##   拖长按音符右边缘 / 按住 Alt 拖音符   改长按长度（拉到 0 = 普通点按）
##   拖选中音符左边的小菱形   改「提前几拍出现」（菱形的位置就是音符出现的那一刻）
##   右键音符           删掉
##   点最上面的刻度条   把播放头挪过去
##   滚轮 横向滚动，Ctrl / Cmd + 滚轮 缩放

signal changed  ## 谱子改了（拖动中也会发，松手时发 committed）
signal committed  ## 一次编辑结束（用来记撤销）
signal selection_changed
signal seek(beat: float)

const RULER := 20.0
const LEFT := 44.0
const EDGE := 7.0

var pattern: ChartPattern
var beats_per_bar := 4
var snap := 0.25
var brush: int = NoteData.Sound.KICK
## 选中的音符（pattern.notes 里的字典）
var selected: Array[Dictionary] = []
## 播放头在这一遍里的第几拍
var playhead := 0.0
var px_per_beat := 48.0
var scroll := 0.0

var _drag := ""  # "", "move", "len", "lead", "seek"
var _drag_from := Vector2.ZERO
var _drag_start: Array = []  # 拖动前每个选中音符的 [beat, lane, length, lead]
var _drag_note: Dictionary


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP


func row_h() -> float:
	return (size.y - RULER) / maxi(_lanes(), 1)


func _lanes() -> int:
	return pattern.lanes if pattern else 1


func beat_x(b: float) -> float:
	return LEFT + b * px_per_beat - scroll


func x_beat(x: float) -> float:
	return (x - LEFT + scroll) / px_per_beat


func lane_y(lane: int) -> float:
	return RULER + lane * row_h()


func note_rect(d: Dictionary) -> Rect2:
	var x := beat_x(d.beat)
	var w := maxf(float(d.get("length", 0.0)) * px_per_beat, 12.0)
	var y := lane_y(clampi(int(d.get("lane", 0)), 0, _lanes() - 1))
	return Rect2(x - 6.0, y + 4.0, w, row_h() - 8.0)


func lead_x(d: Dictionary) -> float:
	var lead := float(d.get("lead", 0.0))
	if lead <= 0.0:
		lead = pattern.default_lead
	return beat_x(d.beat - lead)


func fit() -> void:
	if pattern:
		px_per_beat = maxf((size.x - LEFT - 10.0) / maxf(pattern.length_beats, 1.0), 14.0)
		scroll = 0.0
	queue_redraw()


func _snap(b: float) -> float:
	return clampf(roundf(b / snap) * snap, 0.0, maxf(pattern.length_beats - snap, 0.0))


# ---------------------------------------------------------------- 画

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.05, 0.11))
	if pattern == null:
		return
	var L := pattern.length_beats
	for lane in _lanes():
		var y := lane_y(lane)
		draw_rect(Rect2(LEFT, y, size.x - LEFT, row_h()), Color(1, 1, 1, 0.03 if lane % 2 == 0 else 0.0))
		draw_string(get_theme_default_font(), Vector2(6.0, y + row_h() / 2.0 + 5.0), "道 %d" % (lane + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
	# 网格：吸附线 / 拍线 / 小节线
	var b := 0.0
	while b <= L + 0.001:
		var x := beat_x(b)
		if x >= LEFT - 1.0 and x <= size.x:
			var bar := is_zero_approx(fposmod(b, beats_per_bar))
			var on_beat := is_zero_approx(fposmod(b, 1.0))
			var c := Color(1, 1, 1, 0.35 if bar else (0.13 if on_beat else 0.05))
			draw_line(Vector2(x, RULER), Vector2(x, size.y), c, 2.0 if bar else 1.0)
			if bar:
				draw_string(get_theme_default_font(), Vector2(x + 3.0, 14.0), str(int(b / beats_per_bar) + 1),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
		b += snap
	draw_rect(Rect2(0, 0, size.x, RULER), Color(1, 1, 1, 0.06))
	# 选中音符的出现时间：一条细线从出现那一刻连到音符，左头一个小菱形可以拖
	for d in selected:
		var r := note_rect(d)
		var lx := lead_x(d)
		var cy := r.get_center().y
		draw_line(Vector2(lx, cy), Vector2(r.position.x, cy), Color(1, 1, 1, 0.45), 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(lx, cy - 6), Vector2(lx + 6, cy), Vector2(lx, cy + 6), Vector2(lx - 6, cy)]),
				Color(1, 1, 1, 0.9))
	for d in pattern.notes:
		var r := note_rect(d)
		var col: Color = d.get("color", Color(0, 0, 0, 0))
		if col.a <= 0.0:
			col = NoteStyle.SOUND_COLORS[int(d.sound) % NoteStyle.SOUND_COLORS.size()]
		draw_rect(r, col)
		if float(d.get("length", 0.0)) > 0.0:
			draw_rect(Rect2(r.position + Vector2(10, r.size.y * 0.3), Vector2(r.size.x - 10, r.size.y * 0.4)), col.darkened(0.35))
		var has_fx: bool = float(d.get("glow", 0)) > 0 or float(d.get("pulse", 0)) > 0 or float(d.get("throb", 0)) > 0 \
				or float(d.get("spin", 0)) != 0 or float(d.get("rot", 0)) != 0 or float(d.get("size", 1)) != 1.0
		if has_fx:
			draw_circle(r.position + Vector2(6, 6), 3.0, Color.WHITE)
		if selected.has(d):
			draw_rect(r.grow(2.0), Color.WHITE, false, 2.0)
	# 播放头
	var px := beat_x(playhead)
	draw_line(Vector2(px, 0), Vector2(px, size.y), Color(1.0, 0.35, 0.35), 2.0)


# ---------------------------------------------------------------- 鼠标

func _note_at(pos: Vector2) -> Dictionary:
	for i in range(pattern.notes.size() - 1, -1, -1):
		var d: Dictionary = pattern.notes[i]
		if note_rect(d).grow(2.0).has_point(pos):
			return d
	return {}


func _lead_at(pos: Vector2) -> Dictionary:
	for d in selected:
		var cy := note_rect(d).get_center().y
		if Vector2(lead_x(d), cy).distance_to(pos) <= 8.0:
			return d
	return {}


func _gui_input(event: InputEvent) -> void:
	if pattern == null:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		grab_focus()
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if mb.ctrl_pressed or mb.meta_pressed:
				var at := x_beat(mb.position.x)
				px_per_beat = clampf(px_per_beat * (1.0 - dir * 0.12), 10.0, 400.0)
				scroll = at * px_per_beat - (mb.position.x - LEFT)
			else:
				scroll += dir * 60.0
			scroll = clampf(scroll, 0.0, maxf(pattern.length_beats * px_per_beat - (size.x - LEFT) + 40.0, 0.0))
			queue_redraw()
			accept_event()
			return
		if mb.position.y < RULER and mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = "seek"
			seek.emit(clampf(x_beat(mb.position.x), 0.0, pattern.length_beats))
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			var hit := _note_at(mb.position)
			if not hit.is_empty():
				pattern.notes.erase(hit)
				selected.erase(hit)
				changed.emit()
				committed.emit()
				selection_changed.emit()
				queue_redraw()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_drag_from = mb.position
		var lead_hit := _lead_at(mb.position)
		if not lead_hit.is_empty():
			_drag = "lead"
			_drag_note = lead_hit
			_remember()
			return
		var hit := _note_at(mb.position)
		if hit.is_empty():
			# 空白处：放一个新音符
			var lane := clampi(int((mb.position.y - RULER) / row_h()), 0, _lanes() - 1)
			var d := {"beat": _snap(x_beat(mb.position.x)), "sound": brush, "lane": lane}
			pattern.notes.append(d)
			selected = [d]
			_drag = "move"
			_drag_note = d
			_remember()
			changed.emit()
			selection_changed.emit()
			queue_redraw()
			return
		if mb.shift_pressed:
			if selected.has(hit):
				selected.erase(hit)
			else:
				selected.append(hit)
		elif not selected.has(hit):
			selected = [hit]
		selection_changed.emit()
		_drag_note = hit
		# 抓右边缘（长按音符够宽时）或按住 Alt 拖 = 改长按长度；否则移动
		var r := note_rect(hit)
		var on_edge := r.size.x > 20.0 and mb.position.x >= r.end.x - EDGE
		_drag = "len" if on_edge or mb.alt_pressed else "move"
		_remember()
		queue_redraw()
	elif mb and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if _drag in ["move", "len", "lead"]:
			committed.emit()
		_drag = ""
	var mm := event as InputEventMouseMotion
	if mm and _drag != "":
		_drag_motion(mm.position)


func _remember() -> void:
	_drag_start.clear()
	for d in selected:
		_drag_start.append([d.beat, int(d.get("lane", 0)), float(d.get("length", 0.0)), float(d.get("lead", 0.0))])


func _drag_motion(pos: Vector2) -> void:
	if _drag == "seek":
		seek.emit(clampf(x_beat(pos.x), 0.0, pattern.length_beats))
		return
	var db := (pos.x - _drag_from.x) / px_per_beat
	match _drag:
		"move":
			var dl := roundi((pos.y - _drag_from.y) / row_h())
			for i in selected.size():
				var d := selected[i]
				d.beat = _snap(_drag_start[i][0] + db)
				d.lane = clampi(_drag_start[i][1] + dl, 0, _lanes() - 1)
		"len":
			var i := selected.find(_drag_note)
			if i >= 0:
				var len := maxf(roundf((_drag_start[i][2] + db) / snap) * snap, 0.0)
				if len > 0.0:
					_drag_note["length"] = len
				else:
					_drag_note.erase("length")
		"lead":
			var i := selected.find(_drag_note)
			if i >= 0:
				var cur: float = _drag_start[i][3] if _drag_start[i][3] > 0.0 else pattern.default_lead
				_drag_note["lead"] = maxf(roundf((cur - db) / snap) * snap, snap)
	changed.emit()
	queue_redraw()
