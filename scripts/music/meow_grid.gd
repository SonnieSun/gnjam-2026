extends Control
## 喵谱子的格子（Tab 面板"Meow"页里用）：一格 = 一个 16 分音符，横着是时间，所有小节排成一行。
##   猫鼓：每行一种声音，左键点一格 = 响 / 不响（可以按住拖）。
##   旋律：每行一个音高（小钢琴卷帘）。左键在空格上点 = 放一个音，按住往右拖 = 拉长；
##         左键点已有的音再拖 = 改长度；右键 = 删掉。同一时刻只有一个音（放新的会顶掉旧的）。

signal edited
## 点了一格，要试听：猫鼓给行号，旋律给 midi 音高
signal poked(value: int)

const LABEL_W := 74.0
const TOP := 16.0
const DRUM_ROW_H := 26.0
const LOW := 57      # A3
const HIGH := 88     # E6
const NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const ROW_COLORS := [Color(1.0, 0.82, 0.2), Color(1.0, 0.45, 0.7), Color(0.4, 0.9, 1.0), Color(0.55, 1.0, 0.65), Color(0.7, 0.55, 1.0)]

## 一格多宽、旋律每行多高（全屏的工作室里画大一点）
var step_w := 17.0
var note_row_h := 8.0

var pattern: Dictionary = {}
## 现在播到第几格（-1 = 不画）
var playhead := -1.0

var _paint := -1          # 猫鼓拖动时在涂的状态：1 = 涂上，0 = 擦掉
var _drag_note := -1      # 旋律拖动时在改的音符下标


func set_pattern(p: Dictionary) -> void:
	pattern = p
	_resize()
	queue_redraw()


func is_drums() -> bool:
	return pattern.get("kind", "") == "drums"


func steps() -> int:
	return maxi(int(pattern.get("bars", 1)), 1) * 16


func _rows() -> int:
	return pattern.get("rows", []).size() if is_drums() else HIGH - LOW + 1


func _row_h() -> float:
	return DRUM_ROW_H if is_drums() else note_row_h


func _resize() -> void:
	custom_minimum_size = Vector2(LABEL_W + steps() * step_w + 8.0, TOP + _rows() * _row_h() + 4.0)


## 鼠标位置 -> (第几格, 第几行)；不在格子里返回 (-1, -1)
func _cell_at(pos: Vector2) -> Vector2i:
	var x := floori((pos.x - LABEL_W) / step_w)
	var y := floori((pos.y - TOP) / _row_h())
	if pos.x < LABEL_W or x >= steps() or y < 0 or y >= _rows():
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func _note_at(step: int) -> int:
	var notes: Array = pattern.get("notes", [])
	for i in notes.size():
		if step >= int(notes[i][0]) and step < int(notes[i][0]) + int(notes[i][2]):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if pattern.is_empty():
		return
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	if mb and not mb.pressed:
		if _drag_note >= 0:
			_tidy_notes()
		_paint = -1
		_drag_note = -1
		return
	var pos: Vector2 = mb.position if mb else (mm.position if mm else Vector2(-1, -1))
	var cell := _cell_at(pos)
	if is_drums():
		if cell.x < 0:
			return
		var row: Dictionary = pattern.rows[cell.y]
		if mb and mb.button_index == MOUSE_BUTTON_LEFT:
			_paint = 0 if _drum_on(row, cell.x) else 1
			if _paint == 1:
				poked.emit(cell.y)
		elif mb and mb.button_index == MOUSE_BUTTON_RIGHT:
			_paint = 0
		if _paint >= 0 and (mb or mm) and _drum_on(row, cell.x) != (_paint == 1):
			_set_drum(row, cell.x, _paint == 1)
			edited.emit()
			queue_redraw()
		return
	# 旋律
	var notes: Array = pattern.get("notes", [])
	if mb and mb.button_index == MOUSE_BUTTON_RIGHT and cell.x >= 0:
		var hit := _note_at(cell.x)
		if hit >= 0 and int(notes[hit][1]) == HIGH - cell.y:
			notes.remove_at(hit)
			edited.emit()
			queue_redraw()
	elif mb and mb.button_index == MOUSE_BUTTON_LEFT and cell.x >= 0:
		var midi := HIGH - cell.y
		var hit := _note_at(cell.x)
		if hit >= 0 and int(notes[hit][1]) == midi:
			_drag_note = hit                      # 点在已有的音上：拖它的长度
		else:
			if hit >= 0:                          # 这一格已经有别的音：从这里把它截断（或整个顶掉）
				if int(notes[hit][0]) == cell.x:
					notes.remove_at(hit)
				else:
					notes[hit][2] = cell.x - int(notes[hit][0])
			notes.append([cell.x, midi, 1])
			pattern["notes"] = notes
			_drag_note = notes.size() - 1
			edited.emit()
		poked.emit(midi)
		queue_redraw()
	elif mm and _drag_note >= 0 and _drag_note < notes.size():
		var x := clampi(floori((pos.x - LABEL_W) / step_w), 0, steps() - 1)
		var length := maxi(1, x - int(notes[_drag_note][0]) + 1)
		if length != int(notes[_drag_note][2]):
			notes[_drag_note][2] = length
			edited.emit()
			queue_redraw()


## 排好顺序；后一个音开始的地方把前一个音截断
func _tidy_notes() -> void:
	var notes: Array = pattern.get("notes", [])
	notes.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var out: Array = []
	for n: Array in notes:
		if not out.is_empty():
			var prev: Array = out[-1]
			if int(prev[0]) == int(n[0]):
				out.pop_back()
			elif int(prev[0]) + int(prev[2]) > int(n[0]):
				prev[2] = int(n[0]) - int(prev[0])
		out.append([int(n[0]), int(n[1]), mini(int(n[2]), steps() - int(n[0]))])
	pattern["notes"] = out
	edited.emit()
	queue_redraw()


func _drum_on(row: Dictionary, step: int) -> bool:
	var bars: Array = row.get("bars", [])
	var bar := step / 16
	return bar < bars.size() and (step % 16) < String(bars[bar]).length() and String(bars[bar])[step % 16] != "."


func _set_drum(row: Dictionary, step: int, on: bool) -> void:
	var bars: Array = row.get("bars", [])
	while bars.size() <= step / 16:
		bars.append("................")
	var line := String(bars[step / 16]).rpad(16, ".")
	var i := step % 16
	line = line.substr(0, i) + ("x" if on else ".") + line.substr(i + 1)
	bars[step / 16] = line
	row["bars"] = bars


func _draw() -> void:
	if pattern.is_empty():
		return
	var font := get_theme_default_font()
	var n := steps()
	var rh := _row_h()
	var rows := _rows()
	# 小节号和底色：每拍一条细线，每小节一条粗线
	for bar in n / 16:
		draw_string(font, Vector2(LABEL_W + bar * 16 * step_w + 3, 12), str(bar + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))
	for r in rows:
		var y := TOP + r * rh
		var shade := 0.10
		if is_drums():
			shade = 0.12 if r % 2 == 0 else 0.09
			draw_string(font, Vector2(4, y + rh * 0.68), str(pattern.rows[r].get("name", "row %d" % (r + 1))), HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 8, 12, ROW_COLORS[r % ROW_COLORS.size()])
		else:
			var midi := HIGH - r
			shade = 0.07 if NAMES[midi % 12].length() == 2 else 0.12          # 黑键的行暗一点
			if midi % 12 == 0:
				draw_string(font, Vector2(4, y + rh), "C%d" % (midi / 12 - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))
		draw_rect(Rect2(LABEL_W, y, n * step_w, rh - 1.0), Color(1, 1, 1, shade))
	for s in n + 1:
		var x := LABEL_W + s * step_w
		var a := 0.45 if s % 16 == 0 else (0.18 if s % 4 == 0 else 0.05)
		draw_line(Vector2(x, TOP), Vector2(x, TOP + rows * rh), Color(1, 1, 1, a), 2.0 if s % 16 == 0 else 1.0)
	if is_drums():
		for r in rows:
			for s in n:
				if _drum_on(pattern.rows[r], s):
					draw_rect(Rect2(LABEL_W + s * step_w + 2, TOP + r * rh + 3, step_w - 4, rh - 7), ROW_COLORS[r % ROW_COLORS.size()])
	else:
		for note: Array in pattern.get("notes", []):
			var r := HIGH - int(note[1])
			if r < 0 or r >= rows:
				continue
			var rect := Rect2(LABEL_W + int(note[0]) * step_w + 1, TOP + r * rh, int(note[2]) * step_w - 2, rh - 1.0)
			draw_rect(rect, Color(1.0, 0.45, 0.7))
			draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), Color(1, 1, 1, 0.9))
	if playhead >= 0.0:
		var px := LABEL_W + fposmod(playhead, float(n)) * step_w
		draw_line(Vector2(px, TOP - 4), Vector2(px, TOP + rows * rh), Color(1, 1, 1, 0.9), 2.0)
