@tool
extends Control
## 谱子格子：每一行是一小节，每一格是这一小节里的一个位置。
## 左键 = 用当前选的鼓涂（点在同一种鼓上 = 擦掉），右键 = 擦掉，可以按住拖。

signal edited

const CELL := Vector2(30, 30)
const GAP := 3.0
const LABEL_W := 64.0
const TOP := 22.0
const CHARS := ["k", "s", "h"]
const COLORS := [Color(1.0, 0.82, 0.2), Color(1.0, 0.45, 0.7), Color(0.4, 0.9, 1.0)]

var bars := PackedStringArray()
var beats_per_bar := 4
## 现在用哪种鼓涂：0 底鼓 1 军鼓 2 踩镲，-1 = 橡皮
var brush := 0
## 试听时的播放位置（单位：小节，-1 = 不显示）
var playhead := -1.0

var _painting := ""  # 拖动时正在涂的字符（"" = 没在拖）


func set_bars(value: PackedStringArray) -> void:
	bars = value.duplicate()
	_resize()
	queue_redraw()


func _resize() -> void:
	var cols := 16
	for b in bars:
		cols = maxi(cols, b.length())
	custom_minimum_size = Vector2(LABEL_W + cols * (CELL.x + GAP) + 8.0, TOP + bars.size() * (CELL.y + GAP) + 8.0)


func _cols(bar: int) -> int:
	return maxi(bars[bar].length(), 1)


func _cell_rect(bar: int, i: int) -> Rect2:
	return Rect2(Vector2(LABEL_W + i * (CELL.x + GAP), TOP + bar * (CELL.y + GAP)), CELL)


func _cell_at(pos: Vector2) -> Vector2i:
	var bar := int((pos.y - TOP) / (CELL.y + GAP))
	var i := int((pos.x - LABEL_W) / (CELL.x + GAP))
	if pos.y < TOP or pos.x < LABEL_W or bar < 0 or bar >= bars.size() or i < 0 or i >= _cols(bar):
		return Vector2i(-1, -1)
	return Vector2i(i, bar)


static func sound_of(ch: String) -> int:
	return 0 if ch == "x" else CHARS.find(ch)


func _put(cell: Vector2i, ch: String) -> void:
	var s := bars[cell.y]
	if s == "":
		s = ".".repeat(16)  # 空行 = 整小节休止，第一次点的时候展开成 16 格
		if cell.x >= 16:
			return
	if s[cell.x] == ch:
		return
	bars[cell.y] = s.substr(0, cell.x) + ch + s.substr(cell.x + 1)
	queue_redraw()
	edited.emit()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb:
		if not mb.pressed:
			_painting = ""
			return
		var cell := _cell_at(mb.position)
		if cell.x < 0:
			return
		var cur := bars[cell.y][cell.x] if cell.x < bars[cell.y].length() else "."
		if mb.button_index == MOUSE_BUTTON_RIGHT or brush < 0:
			_painting = "."
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = "." if sound_of(cur) == brush else CHARS[brush]
		else:
			return
		_put(cell, _painting)
		accept_event()
	var mm := event as InputEventMouseMotion
	if mm and _painting != "":
		var cell := _cell_at(mm.position)
		if cell.x >= 0:
			_put(cell, _painting)


func _draw() -> void:
	var font := get_theme_default_font()
	var dim := Color(1, 1, 1, 0.55)
	for bar in bars.size():
		var cols := _cols(bar) if bars[bar] != "" else 16
		var per_beat := float(cols) / beats_per_bar
		draw_string(font, Vector2(0, TOP + bar * (CELL.y + GAP) + 20.0), "Bar %d" % (bar + 1),
				HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, 14, dim)
		for i in cols:
			var r := _cell_rect(bar, i)
			var on_beat := is_zero_approx(fmod(i, per_beat))
			if bar == 0 and on_beat:
				draw_string(font, Vector2(r.position.x + 2.0, 14.0), str(int(i / per_beat) + 1),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 13, dim)
			var ch := bars[bar][i] if i < bars[bar].length() else "."
			var snd := sound_of(ch)
			var col := Color(1, 1, 1, 0.16 if on_beat else 0.07)
			if snd >= 0:
				col = COLORS[snd]
			draw_rect(r, col, true)
			if snd >= 0:
				draw_string(font, r.position + Vector2(9, 21), CHARS[snd].to_upper(),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.75))
	if playhead >= 0.0 and bars.size() > 0:
		var bar := clampi(int(playhead), 0, bars.size() - 1)
		var cols := _cols(bar) if bars[bar] != "" else 16
		var x := LABEL_W + (playhead - bar) * cols * (CELL.x + GAP)
		var y := TOP + bar * (CELL.y + GAP)
		draw_line(Vector2(x, y - 2.0), Vector2(x, y + CELL.y + 2.0), Color.WHITE, 3.0)
