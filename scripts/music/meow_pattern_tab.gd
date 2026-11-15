extends VBoxContainer
## Tab 面板里的"Meow"页：在游戏里写喵谱子 —— 猫鼓（每行一种喵，点格子）和鬼畜猫旋律（小钢琴卷帘）。
## 谱子存成 levels/music/patterns/<名字>.json，是运行时按格子触发的（见 meow_player.gd），不用渲染，改了马上能听。
##
## 用法：选一个谱子或新建 → 点格子改 → Listen 勾上就跟着音乐循环试听 → Save 存文件 →
## "Add to lane" 把它作为一个新片段放进这一关的某条轨道，然后到 Music 页像别的片段一样按进度切换到它。
## 它不会替换原来预渲染的猫鼓 / 猫旋律，只是多一个可以选的片段。

const Grid := preload("res://scripts/music/meow_grid.gd")
const EDIT_KEY := "__meow_edit__"

var editor: Node                      # Tab 面板（game_editor.gd），用它的 _fill_music / _mark_dirty
var pattern: Dictionary = {}
var path := ""

var _pick: OptionButton
var _name: LineEdit
var _lane: OptionButton
var _listen: CheckBox
var _cat: OptionButton
var _bars: Label
var _status: Label
var _grid: Control
var _scroll: ScrollContainer


func _init(tab_editor: Node = null) -> void:
	editor = tab_editor
	name = "Meow"
	add_theme_constant_override("separation", 4)
	var row := HFlowContainer.new()
	add_child(row)
	_pick = OptionButton.new()
	_pick.custom_minimum_size.x = 150
	_pick.focus_mode = Control.FOCUS_NONE
	_pick.tooltip_text = "The meow patterns in levels/music/patterns/"
	_pick.item_selected.connect(_on_pick)
	row.add_child(_pick)
	_btn(row, "New drums", _new.bind("drums"), "A new meow drum pattern: one row per meow, click the steps")
	_btn(row, "New melody", _new.bind("melody"), "A new kichiku cat melody: a small piano roll")
	_name = LineEdit.new()
	_name.custom_minimum_size.x = 130
	_name.placeholder_text = "name"
	row.add_child(_name)
	_btn(row, "Save", _save, "Write this pattern to levels/music/patterns/<name>.json")
	row.add_child(VSeparator.new())
	_lane = OptionButton.new()
	_lane.focus_mode = Control.FOCUS_NONE
	_lane.tooltip_text = "The lane of this level's music the pattern goes into"
	row.add_child(_lane)
	_btn(row, "Add to lane", _add_to_lane, "Save, then add this pattern to the lane as a new clip; pick it on the Music page like any other clip")
	row.add_child(VSeparator.new())
	_listen = CheckBox.new()
	_listen.text = "Listen"
	_listen.focus_mode = Control.FOCUS_NONE
	_listen.tooltip_text = "Loop this pattern over the music while you edit it"
	_listen.toggled.connect(_on_listen)
	row.add_child(_listen)

	var row2 := row
	row.add_child(VSeparator.new())
	_btn(row2, "- Bar", _resize_bars.bind(-1))
	_bars = Label.new()
	row2.add_child(_bars)
	_btn(row2, "+ Bar", _resize_bars.bind(1))
	var cat_label := Label.new()
	cat_label.text = "   Cat"
	row2.add_child(cat_label)
	_cat = OptionButton.new()
	_cat.focus_mode = Control.FOCUS_NONE
	_cat.tooltip_text = "Melody: which cat sings. auto = for every 4 bars the cat whose own pitch is nearest"
	_cat.item_selected.connect(_on_cat)
	row2.add_child(_cat)
	_status = Label.new()
	_status.modulate.a = 0.7
	row2.add_child(_status)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	var scroll := _scroll
	_grid = Grid.new()
	_grid.edited.connect(_changed)
	_grid.poked.connect(_poke)
	scroll.add_child(_grid)


func _ready() -> void:
	_cat.add_item("auto")
	for id: String in Music.meow.cats:
		_cat.add_item(id)
	_fill_lanes()
	_fill_patterns()
	if _pick.item_count > 0:
		_open(_pick.get_item_metadata(0))
	else:
		_status.text = "   No patterns yet: New drums or New melody"
	visibility_changed.connect(_on_visibility)


func _on_pick(i: int) -> void:
	_open(_pick.get_item_metadata(i))


func _on_listen(_on: bool) -> void:
	_update_listen()


func _on_cat(i: int) -> void:
	if not pattern.is_empty() and not _grid.is_drums():
		pattern["cat"] = _cat.get_item_text(i)
		_changed()


func _on_visibility() -> void:
	_fill_lanes()
	_update_listen()


func _btn(parent: Control, text: String, action: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _fill_patterns() -> void:
	_pick.clear()
	for p in MeowPlayer.list_patterns():
		_pick.add_item(p.get_file().get_basename())
		_pick.set_item_metadata(_pick.item_count - 1, p)
		if p == path:
			_pick.selected = _pick.item_count - 1


func _fill_lanes() -> void:
	var keep := _lane.get_item_text(_lane.selected) if _lane.selected >= 0 else ""
	_lane.clear()
	var ids: Array[String] = []
	for lane: Dictionary in Music.data.get("lanes", []):
		ids.append(lane.id)
	for extra: String in ["meow", "kiai"]:
		if not ids.has(extra):
			ids.append(extra)
	for id in ids:
		_lane.add_item(id)
		if id == keep:
			_lane.selected = _lane.item_count - 1


func _open(p: String) -> void:
	var d := MeowPlayer.read_pattern(p)
	if d.is_empty():
		_status.text = "   Could not read " + p
		return
	path = p
	pattern = d
	_name.text = p.get_file().get_basename()
	for i in _pick.item_count:
		if _pick.get_item_metadata(i) == p:
			_pick.selected = i
	_show()


func _new(kind: String) -> void:
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
	_status.text = "   New pattern (not saved yet)"


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
	_grid.set_pattern(pattern)
	_bars.text = " %d bars " % int(pattern.get("bars", 1))
	_cat.disabled = _grid.is_drums()
	for i in _cat.item_count:
		if _cat.get_item_text(i) == str(pattern.get("cat", "auto")):
			_cat.selected = i
	_lane.selected = maxi(0, _lane_index("meow" if _grid.is_drums() else "kiai"))
	if _grid.is_drums():
		_status.text = "   drums: left click = on / off, drag to paint"
	else:
		_status.text = "   melody: click = note, drag right = longer, right click = delete"
	_update_listen()
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
	var y: float = _grid.TOP + (_grid.HIGH - mid) * _grid.NOTE_ROW_H
	_scroll.scroll_vertical = int(maxf(0.0, y - _scroll.size.y / 2.0))


func _lane_index(id: String) -> int:
	for i in _lane.item_count:
		if _lane.get_item_text(i) == id:
			return i
	return -1


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
	_status.text = "   ● Unsaved pattern"
	_update_listen()


## 点格子时试听那一声
func _poke(value: int) -> void:
	if _grid.is_drums():
		var row: Dictionary = pattern.rows[value]
		Music.meow.preview(str(row.get("cat", "")), float(row.get("midi", 60)), row.get("tick", false), 0.35)
	else:
		var cat := str(pattern.get("cat", "auto"))
		if not Music.meow.cats.has(cat):
			cat = _nearest_cat(value)
		Music.meow.preview(cat, value, false, 0.3)


func _nearest_cat(midi: float) -> String:
	var best := ""
	for c: String in Music.meow.cats:
		if best == "" or absf(Music.meow.cats[c].midi - midi) < absf(Music.meow.cats[best].midi - midi):
			best = c
	return best


func _update_listen() -> void:
	var on := _listen.button_pressed and is_visible_in_tree() and not pattern.is_empty()
	var empty: Dictionary = {}
	Music.meow.set_active(EDIT_KEY, pattern if on else empty)


func _save() -> bool:
	if pattern.is_empty():
		return false
	var clean := _name.text.strip_edges().to_lower().replace(" ", "_").validate_filename()
	if clean == "":
		_status.text = "   Give the pattern a name first"
		return false
	_name.text = clean
	path = MeowPlayer.PATTERN_DIR + clean + ".json"
	var err := MeowPlayer.write_pattern(path, pattern)
	if err != OK:
		_status.text = "   Save failed: " + error_string(err)
		return false
	_fill_patterns()
	Music.reload_patterns()               # 这个谱子已经是某条轨道的片段的话，马上换成新的
	_status.text = "   Saved " + path.get_file()
	return true


func _add_to_lane() -> void:
	if Music.stream == null or not Music.enabled_for(Levels.selected):
		_status.text = "   This level does not use layered music, so it has no lanes"
		return
	if not _save():
		return
	var lane := _lane.get_item_text(_lane.selected)
	var clip := Music.add_pattern_clip(lane, path)
	if editor:
		editor._fill_music()
		editor._mark_dirty()
	_fill_lanes()
	_status.text = "   Added '%s' to lane %s: pick it on the Music page, then Save (top right) to keep it in the level" % [clip, lane]


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or pattern.is_empty():
		return
	var head := -1.0
	if Conductor.playing and Conductor.song_beat >= 0.0:
		head = Conductor.song_beat * 4.0
	if head != _grid.playhead:
		_grid.playhead = head
		_grid.queue_redraw()
