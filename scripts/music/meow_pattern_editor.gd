extends VBoxContainer
## 喵谱子的编辑区（喵谱子工作室 scenes/tools/meow_studio.tscn 的下半部分）：
## 猫鼓（每行一种喵，点格子）和鬼畜猫旋律（小钢琴卷帘），存成 levels/music/patterns/<名字>.json。
##
## 这里只管写和存。存了的谱子会出现在曲库里；要用进某一关，是游戏里 Tab 面板 Music 页的事
## （每条轨道右边的 "+ meow" 把一个谱子加成那条轨道的片段）。
## 工作室在播的时候（PLAY），正在编辑的谱子就跟着循环，改了马上能听到。
##
## MIDI 键盘：插着的话，按键就试听那个音；工作室在播的时候按，音符会录进旋律（对齐到 16 分音符，
## 松手决定长度）。猫鼓谱子里，从中央 C 起的几个白键 / 黑键依次对应每一行。

const Grid := preload("res://scripts/music/meow_grid.gd")
const EDIT_KEY := "__meow_edit__"

var pattern: Dictionary = {}
var path := ""

var _pick: OptionButton
var _name: LineEdit
var _cat: OptionButton
var _bars: Label
var _status: Label
var _scroll: ScrollContainer
var _grid: Control
var _held := {}                        # MIDI 键盘按着的键：音高 -> [音符下标, 按下时是第几格（不取模）]


func _init() -> void:
	add_theme_constant_override("separation", 4)
	var row := HFlowContainer.new()
	add_child(row)
	_pick = OptionButton.new()
	_pick.custom_minimum_size.x = 150
	_pick.focus_mode = Control.FOCUS_NONE
	_pick.tooltip_text = "存好的喵谱子（levels/music/patterns/）"
	_pick.item_selected.connect(_on_pick)
	row.add_child(_pick)
	_btn(row, "New drums", new_pattern.bind("drums"), "新的猫鼓：每行一种喵，点格子")
	_btn(row, "New melody", new_pattern.bind("melody"), "新的鬼畜猫旋律：小钢琴卷帘")
	_name = LineEdit.new()
	_name.custom_minimum_size.x = 130
	_name.placeholder_text = "name"
	row.add_child(_name)
	_btn(row, "Save", save, "存成 levels/music/patterns/<name>.json（存了就出现在曲库里）")
	row.add_child(VSeparator.new())
	_btn(row, "- Bar", _resize_bars.bind(-1))
	_bars = Label.new()
	row.add_child(_bars)
	_btn(row, "+ Bar", _resize_bars.bind(1))
	var cat_label := Label.new()
	cat_label.text = "   Cat"
	row.add_child(cat_label)
	_cat = OptionButton.new()
	_cat.focus_mode = Control.FOCUS_NONE
	_cat.tooltip_text = "旋律：哪只猫唱。auto = 每 4 小节挑原本音高最近的那只"
	_cat.item_selected.connect(_on_cat)
	row.add_child(_cat)
	_status = Label.new()
	_status.modulate.a = 0.7
	row.add_child(_status)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_grid = Grid.new()
	_grid.edited.connect(_changed)
	_grid.poked.connect(_poke)
	_scroll.add_child(_grid)


func _ready() -> void:
	_cat.add_item("auto")
	for id: String in Music.meow.cats:
		_cat.add_item(id)
	_fill_patterns()
	if _pick.item_count > 0:
		open(_pick.get_item_metadata(0))
	else:
		_say("No patterns yet: New drums or New melody")
	OS.open_midi_inputs()                # 有 MIDI 键盘就能收到按键（见 _input）


func _exit_tree() -> void:
	var empty: Dictionary = {}
	Music.meow.set_active(EDIT_KEY, empty)
	OS.close_midi_inputs()


func _btn(parent: Control, text: String, action: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _say(text: String) -> void:
	_status.text = "   " + text


func _on_pick(i: int) -> void:
	open(_pick.get_item_metadata(i))


func _on_cat(i: int) -> void:
	if not pattern.is_empty() and not _grid.is_drums():
		pattern["cat"] = _cat.get_item_text(i)
		_changed()


func _fill_patterns() -> void:
	_pick.clear()
	for p in MeowPlayer.list_patterns():
		_pick.add_item(p.get_file().get_basename())
		_pick.set_item_metadata(_pick.item_count - 1, p)
		if p == path:
			_pick.selected = _pick.item_count - 1


## 打开一个存好的谱子
func open(p: String) -> void:
	var d := MeowPlayer.read_pattern(p)
	if d.is_empty():
		_say("Could not read " + p)
		return
	path = p
	pattern = d
	_name.text = p.get_file().get_basename()
	for i in _pick.item_count:
		if _pick.get_item_metadata(i) == p:
			_pick.selected = i
	_show()


## 新建一个谱子（kind = "drums" 或 "melody"），还没存
func new_pattern(kind: String) -> void:
	path = ""
	if kind == "drums":
		# 三行：低喵、高喵、"mi"（只用喵开头那一下，当踩镲）；猫按原本音高从低到高挑
		var by_pitch: Array = Music.meow.cats.keys()
		by_pitch.sort_custom(_lower_cat)
		var low: String = by_pitch[mini(1, by_pitch.size() - 1)] if not by_pitch.is_empty() else ""
		var high: String = by_pitch[by_pitch.size() / 2] if not by_pitch.is_empty() else ""
		var top: String = by_pitch[-1] if not by_pitch.is_empty() else ""
		pattern = {"kind": "drums", "bars": 2, "rows": [
			{"name": "meow low", "cat": low, "midi": _own(low), "steps": 3, "gain_db": 0.0, "tick": false,
				"bars": ["x.......x.......", "x.......x......."]},
			{"name": "meow high", "cat": high, "midi": _own(high), "steps": 2, "gain_db": -2.0, "tick": false,
				"bars": ["....x.......x...", "....x.......x.x."]},
			{"name": "mi", "cat": top, "midi": _own(top), "steps": 1, "gain_db": -6.0, "tick": true,
				"bars": ["..x...x...x...x.", "..x...x...x...x."]}]}
		_name.text = _free_name("meow_drums")
	else:
		pattern = {"kind": "melody", "bars": 4, "cat": "auto", "gain_db": 0.0, "notes": []}
		_name.text = _free_name("cat_melody")
	_show()
	_say("New pattern (not saved yet)")


func _lower_cat(a: String, b: String) -> bool:
	return Music.meow.cats[a].midi < Music.meow.cats[b].midi


func _own(cat: String) -> float:
	return roundf(Music.meow.cats[cat].midi) if Music.meow.cats.has(cat) else 60.0


func _free_name(base: String) -> String:
	var i := 1
	while FileAccess.file_exists("%s%s_%d.json" % [MeowPlayer.PATTERN_DIR, base, i]):
		i += 1
	return "%s_%d" % [base, i]


func _show() -> void:
	_held.clear()
	_grid.set_pattern(pattern)
	_bars.text = " %d bars " % int(pattern.get("bars", 1))
	_cat.disabled = _grid.is_drums()
	for i in _cat.item_count:
		if _cat.get_item_text(i) == str(pattern.get("cat", "auto")):
			_cat.selected = i
	if _grid.is_drums():
		_say("drums: left click = on / off, drag to paint")
	else:
		_say("melody: click = note, drag right = longer, right click = delete")
	Music.meow.set_active(EDIT_KEY, pattern)       # 工作室在播的时候它就跟着循环
	_center.call_deferred()


## 旋律：把卷帘滚到音符所在的那几行（没有音符就滚到中间）
func _center() -> void:
	if _grid.is_drums():
		_scroll.scroll_vertical = 0
		return
	var mid := 72.0
	var notes: Array = pattern.get("notes", [])
	if not notes.is_empty():
		var lo := 200.0
		var hi := 0.0
		for n: Array in notes:
			lo = minf(lo, float(n[1]))
			hi = maxf(hi, float(n[1]))
		mid = (lo + hi) / 2.0
	var y: float = _grid.TOP + (_grid.HIGH - mid) * _grid.note_row_h
	_scroll.scroll_vertical = int(maxf(0.0, y - _scroll.size.y / 2.0))


func set_cell_size(step_w: float, note_row_h: float) -> void:
	_grid.step_w = step_w
	_grid.note_row_h = note_row_h
	_grid.set_pattern(pattern)
	_center.call_deferred()


func _resize_bars(d: int) -> void:
	if pattern.is_empty():
		return
	var n := clampi(int(pattern.get("bars", 1)) + d, 1, 16)
	pattern["bars"] = n
	if _grid.is_drums():
		for row: Dictionary in pattern.rows:
			var bars: Array = row.get("bars", [])
			while bars.size() < n:
				bars.append(bars[bars.size() - 1] if not bars.is_empty() else "................")
			bars.resize(n)
			row["bars"] = bars
	else:
		var kept: Array = []
		for note: Array in pattern.get("notes", []):
			if int(note[0]) < n * 16:
				kept.append([int(note[0]), int(note[1]), mini(int(note[2]), n * 16 - int(note[0]))])
		pattern["notes"] = kept
	_show()
	_changed()


func _changed() -> void:
	_say("● Unsaved pattern")
	Music.meow.set_active(EDIT_KEY, pattern)       # 重新交给播放器（它会重新挑每一句的猫）


## 点格子时试听那一声
func _poke(value: int) -> void:
	if _grid.is_drums():
		var row: Dictionary = pattern.rows[value]
		Music.meow.preview(str(row.get("cat", "")), float(row.get("midi", 60)), row.get("tick", false), 0.35)
	else:
		Music.meow.preview(_melody_cat(value), value, false, 0.3)


## 旋律试听用哪只猫：谱子指定的那只，auto 就挑原本音高最近的
func _melody_cat(midi: float) -> String:
	var cat := str(pattern.get("cat", "auto"))
	if Music.meow.cats.has(cat):
		return cat
	var best := ""
	for c: String in Music.meow.cats:
		if best == "" or absf(Music.meow.cats[c].midi - midi) < absf(Music.meow.cats[best].midi - midi):
			best = c
	return best


## 存成文件（名字框里的名字）。存了就出现在曲库里；已经用进关卡的同名谱子也就跟着变了。
func save() -> bool:
	if pattern.is_empty():
		return false
	var clean := _name.text.strip_edges().to_lower().replace(" ", "_").validate_filename()
	if clean == "":
		_say("Give the pattern a name first")
		return false
	_name.text = clean
	path = MeowPlayer.PATTERN_DIR + clean + ".json"
	var err := MeowPlayer.write_pattern(path, pattern)
	if err != OK:
		_say("Save failed: " + error_string(err))
		return false
	_fill_patterns()
	_say("Saved %s: it is in the jukebox now; add it to a level on the game's Tab panel, Music page (+ meow)" % path.get_file())
	return true


func _process(_delta: float) -> void:
	if pattern.is_empty():
		return
	var head := -1.0
	if Music.meow.running() and Music.meow.now_beat() >= 0.0:
		head = Music.meow.now_beat() * 4.0
	if head != _grid.playhead:
		_grid.playhead = head
		_grid.queue_redraw()


# ---------------------------------------------------------------- MIDI 键盘

func _input(event: InputEvent) -> void:
	var midi := event as InputEventMIDI
	if midi == null or pattern.is_empty() or not is_visible_in_tree():
		return
	if midi.message == MIDI_MESSAGE_NOTE_ON and midi.velocity > 0:
		_key_down(midi.pitch)
	elif midi.message == MIDI_MESSAGE_NOTE_OFF or midi.message == MIDI_MESSAGE_NOTE_ON:
		_key_up(midi.pitch)


## 现在是第几格（不取模；没在播返回 -1）
func _now_step() -> int:
	return roundi(Music.meow.now_beat() * 4.0) if Music.meow.running() else -1


func _key_down(pitch: int) -> void:
	var total: int = _grid.steps()
	var step := _now_step()
	if _grid.is_drums():
		# 从中央 C（60）起，一个键一行
		var rows: Array = pattern.rows
		var r := posmod(pitch - 60, maxi(rows.size(), 1))
		_poke(r)
		if step >= 0:
			_grid._set_drum(rows[r], step % total, true)
			_grid.queue_redraw()
			_changed()
		return
	while pitch > _grid.HIGH:                      # 键盘上弹得太高 / 太低：挪八度放进猫的音区
		pitch -= 12
	while pitch < _grid.LOW:
		pitch += 12
	Music.meow.preview(_melody_cat(pitch), pitch, false, 0.3)
	if step < 0:
		return
	# 在播：录进旋律。这一格原来有音就顶掉 / 截断
	var at := step % total
	var notes: Array = pattern.get("notes", [])
	for i in range(notes.size() - 1, -1, -1):
		var s := int(notes[i][0])
		if s == at:
			notes.remove_at(i)
		elif s < at and s + int(notes[i][2]) > at:
			notes[i][2] = at - s
	notes.append([at, pitch, 1])
	pattern["notes"] = notes
	_held[pitch] = [notes.size() - 1, step]
	_grid.queue_redraw()
	_changed()


func _key_up(pitch: int) -> void:
	while pitch > _grid.HIGH:
		pitch -= 12
	while pitch < _grid.LOW:
		pitch += 12
	if not _held.has(pitch):
		return
	var info: Array = _held[pitch]
	_held.erase(pitch)
	var notes: Array = pattern.get("notes", [])
	var step := _now_step()
	if step >= 0 and int(info[0]) < notes.size() and int(notes[info[0]][1]) == pitch:
		var at := int(notes[info[0]][0])
		notes[info[0]][2] = clampi(step - int(info[1]), 1, _grid.steps() - at)
	if _held.is_empty():
		_grid._tidy_notes()                        # 排好顺序、截掉重叠
	_grid.queue_redraw()
