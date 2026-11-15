extends Control
## 简单版配拍编辑器（scenes/tools/kisa/beat_editor.tscn，F6 运行）。
## 选一关 → 选小关和音乐阶段（听到的就是游戏里那一段的叠轨音乐）→ 在时间线上点出每一下打击，给它选颜色。
## 存的格式和 Sonnie 的谱面编辑器一样（ChartPattern，levels/charts/<大关>_<第几个小关>.tres，挂到小关的 chart 上），
## 所以两个编辑器可以换着用，游戏里直接生效。
##
##   点空白       放一个打击（类型和颜色 = 上面选中的）；长按 / 连击放下后接着往右拖 = 拉长度
##   点打击       选中，拖动 = 挪位置；拖长条的右头 = 改长度；选中后点类型 / 颜色按钮 = 改它
##   右键打击     删掉
##   点每行顶上的细条   把播放头挪过去
##   空格 播放 / 暂停    1 / 2 / 3 点按 / 长按 / 连击    Delete 删    Ctrl+Z 撤销    Ctrl+Y 重做    Ctrl+S 保存
##
## 一份谱子对应一个小关（整个小关循环这一段）。小关里中途会换玩法的（比如迪斯科：房间 → 水果路 → 圆台 → 吸猫），
## 每个「玩法阶段」各有一份谱子（关卡脚本里的 static func chart_phases() 列出来的）。旁边「这一段里的音乐」列的是这个玩法阶段里游戏会经过的几段（名字是积累条事件的名字），只是换着听。

const THEME := preload("res://assets/ui/theme.tres")
const CHARTS_DIR := "res://levels/charts/"
const SPEEDS := {"1x": 1.0, "0.75x": 0.75, "0.5x": 0.5, "0.25x": 0.25}
const SNAPS :={"1 拍": 1.0, "半拍": 0.5, "1/4 拍": 0.25}
const KIND_NAMES := ["点按", "长按", "连击"]
const KIND_COLORS: Array[Color] = [Color(1.0, 0.85, 0.2), Color(1.0, 0.15, 0.7), Color(1.0, 0.55, 0.1)]
## 颜色按钮：第一个 = 默认（不写进谱子，游戏里按关卡自己的颜色）
const PALETTE: Array[Color] = [Color(0, 0, 0, 0), Color(1.0, 0.3, 0.3), Color(1.0, 0.6, 0.15), Color(1.0, 0.9, 0.25),
	Color(0.4, 0.95, 0.45), Color(0.35, 0.9, 1.0), Color(0.4, 0.5, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.5, 0.8), Color.WHITE]
## 缩放 1 倍时一屏放几拍（拍子多了不换行，用下面的滚动条左右拖）
const BEATS_PER_ROW := 16.0
const PAD := 24.0
const RULER := 16.0
const HEAD := 11.0

var pattern: ChartPattern

var _level := 0
var _section := 0
var _song: SongChart
var _music_on := false
var _phase := ""  # 现在编辑的是这个小关的哪个玩法阶段（"" = 开头的主谱）
var _phases: Array = []  # 这个小关的玩法阶段：[{id, name, at 积累条进度 0-1}]
var _event_at: Array[float] = []  # 这个小关积累条的每条事件线在进度的多少（0-1）
var _event_names := PackedStringArray()  # 每条事件线叫什么（大关文件里的 gauge_event_names）
var _patterns := {}  # "小关序号/阶段 id" -> ChartPattern（这次打开后改过 / 看过的）
var _dirty := {}  # "小关序号/阶段 id" -> true（改了还没存）
var _kind := 0
var _color := Color(0, 0, 0, 0)
var _snap := 0.5
var _sel: Dictionary = {}
var _undo: Array = []
var _redo: Array = []
var _before: Array = []  # 鼠标按下时的样子：真的改了才记成一步撤销
var _playing := false
var _beat := 0.0  # 播放头：这一段里的第几拍
var _drag := ""  # "", "move", "len", "seek"
var _drums: DrumKit

var _level_pick := OptionButton.new()
var _stage_box := HBoxContainer.new()
var _tier_box := HBoxContainer.new()
var _phase_box := HBoxContainer.new()
var _phase_label: Label
var _kind_btns: Array[Button] = []
var _color_btns: Array[Button] = []
var _play_btn := Button.new()
var _bars := SpinBox.new()
var _status := Label.new()
var _tl := Control.new()
var _scroll_bar := HScrollBar.new()
var _scroll := 0.0  # 时间线最左边是第几拍
var _zoom := 1.0
var _loading := false


func _ready() -> void:
	theme = THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_drums = DrumKit.new()
	add_child(_drums)
	_build_ui()
	Levels.rescan()
	for i in Levels.count():
		_level_pick.add_item("%d  %s" % [i + 1, Levels.paths()[i].get_file().get_basename()], i)
	_open_level(clampi(Levels.selected, 0, Levels.count() - 1))


func _exit_tree() -> void:
	Conductor.stop()
	Conductor.speed = 1.0
	Music.clear()


# ================================================================ 打开 / 保存

func _open_level(level: int) -> void:
	_stop()
	_level = level
	_patterns.clear()
	_dirty.clear()
	_song = (load(Levels.paths()[_level]) as SongChart).duplicate(true) as SongChart
	# 叠轨音乐：和游戏里一样，这一关开了就用它，BPM 也跟着它走
	var cfg := Music.read(Music.MUSIC_DIR + Levels.paths()[_level].get_file().get_basename() + ".json")
	_music_on = cfg.get("use_in_game", false)
	if _music_on:
		_song.stream = Music.build(cfg)
		_song.bpm = Music.bpm()
		_song.first_beat_offset_sec = 0.0
	else:
		Music.clear()
	_song.recompute()
	Conductor.load_chart(_song)
	_loading = true
	_level_pick.select(_level)
	_loading = false
	for c in _stage_box.get_children():
		_stage_box.remove_child(c)
		c.queue_free()
	for i in _song.sections.size():
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, _song.sections[i].title]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_open_section.bind(i))
		_stage_box.add_child(b)
	_open_section(0)


func _key(section: int, phase: String) -> String:
	return "%d/%s" % [section, phase]


func _chart_file(section: int, phase: String) -> String:
	var base := Levels.paths()[_level].get_file().get_basename()
	return CHARTS_DIR + ("%s_%d.tres" % [base, section] if phase == "" else "%s_%d_%s.tres" % [base, section, phase])


## 这一份谱子（没打开过就读进来：存过的读文件，没存过的阶段先照抄主谱——游戏里现在就是这样）
func _pattern_for(section: int, phase: String) -> ChartPattern:
	var key := _key(section, phase)
	if not _patterns.has(key):
		var src := _song.sections[section]
		if phase != "" and ResourceLoader.exists(_chart_file(section, phase)):
			_patterns[key] = (load(_chart_file(section, phase)) as ChartPattern).duplicate(true)
		elif phase != "":
			_patterns[key] = _pattern_for(section, "").duplicate(true)
		else:
			_patterns[key] = src.chart.duplicate(true) if src.chart \
					else ChartPattern.from_bars(src.bars, _song.beats_per_bar)
	return _patterns[key]


## 这个小关有哪些玩法阶段：小关场景的脚本里有 static func chart_phases() 就照它列，没有就只有一份主谱。
## at = 这个阶段从积累条的多少开始（场景根节点的 gauge_events / gauge_max_override 算出来的），用来挑该听哪一档音乐
func _read_phases(def: SectionDef) -> Array:
	var out := [{"id": "", "name": "整段", "at": 0.0}]
	_event_at.clear()
	_event_names = def.gauge_event_names
	if def.scene == null:
		return out
	var state := def.scene.get_state()
	var script: Script = null
	var events := PackedInt32Array()
	var gauge_max := 0
	for i in state.get_node_property_count(0):
		match String(state.get_node_property_name(0, i)):
			"script": script = state.get_node_property_value(0, i)
			"gauge_events": events = state.get_node_property_value(0, i)
			"gauge_max_override": gauge_max = state.get_node_property_value(0, i)
	if gauge_max > 0:
		for v in events:
			_event_at.append(float(v) / gauge_max)
	if script == null:
		return out
	var has := false
	for m in script.get_script_method_list():
		has = has or m.name == "chart_phases"
	if not has:
		return out
	out = []
	for p: Dictionary in script.call("chart_phases"):
		var e := int(p.get("event", 0))
		var at := float(events[e - 1]) / gauge_max if e > 0 and e <= events.size() and gauge_max > 0 else 0.0
		out.append({"id": p.id, "name": p.name, "at": at})
	return out


func _open_section(section: int) -> void:
	_stop()
	_section = section
	for i in _stage_box.get_child_count():
		(_stage_box.get_child(i) as Button).button_pressed = i == section
	_phases = _read_phases(_song.sections[section])
	for c in _phase_box.get_children():
		_phase_box.remove_child(c)
		c.queue_free()
	for p: Dictionary in _phases:
		var b := Button.new()
		b.text = p.name
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "这个阶段单独一份谱子（积累条 %d%% 起）" % roundi(float(p.at) * 100.0)
		b.pressed.connect(_open_phase.bind(p.id))
		_phase_box.add_child(b)
	_phase_box.visible = _phases.size() > 1
	_phase_label.visible = _phases.size() > 1
	_open_phase(_phases[0].id)


## 进度 at 这条线在游戏里叫什么：正好是积累条的某条事件线就用它的名字，不是就写百分比
func _line_name(at: float) -> String:
	if at <= 0.0:
		return "开头"
	for i in _event_at.size():
		if absf(_event_at[i] - at) < 0.006:
			return _event_names[i] if i < _event_names.size() and _event_names[i] != "" else "事件 %d" % (i + 1)
	if _music_on:
		for r: Array in Music.fever_ranges(_section):
			if absf(float(r[0]) - at) < 0.006:
				return "Fever"
	return "%d%%" % roundi(at * 100.0)


## 这个玩法阶段里游戏会经过的几段音乐（进度从 from 到 to 之间的档位线），一段一个按钮
func _build_tiers(from: float, to: float) -> void:
	for c in _tier_box.get_children():
		_tier_box.remove_child(c)
		c.queue_free()
	var ats: Array[float] = [from]
	if _music_on:
		for line in Music.tier_lines(_section):
			if line > from + 0.006 and line < to - 0.006:
				ats.append(line)
	for i in ats.size():
		var b := Button.new()
		b.text = _line_name(ats[i])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "游戏里积累条到 %d%% 起的这一段，点了听这一段的音乐" % roundi(ats[i] * 100.0)
		b.pressed.connect(_set_tier.bind(i, ats[i] + 0.01 if ats[i] > 0.0 else 0.0))
		_tier_box.add_child(b)


## 换到这个小关的另一个玩法阶段：换成它的那份谱子，音乐也跳到这个阶段开始时的那一档
func _open_phase(phase: String) -> void:
	_stop()
	_phase = phase
	pattern = _pattern_for(_section, phase)
	_sel = {}
	_undo.clear()
	_redo.clear()
	_beat = 0.0
	_loading = true
	_bars.value = pattern.length_beats / _song.beats_per_bar
	_loading = false
	var at := 0.0
	var name := ""
	for i in _phases.size():
		(_phase_box.get_child(i) as Button).button_pressed = _phases[i].id == phase
		if _phases[i].id == phase:
			at = _phases[i].at
			name = _phases[i].name
	var to := 1.0
	for p: Dictionary in _phases:
		if float(p.at) > at + 0.006:
			to = minf(to, float(p.at))
	_build_tiers(at, to)
	_set_tier(0, at + 0.01 if at > 0.0 else 0.0)
	_scroll_bar.value = 0.0
	_update_scroll()
	var saved := phase == "" or ResourceLoader.exists(_chart_file(_section, phase))
	_say("%s · 第 %d 个小关%s · %d BPM%s%s" % [Levels.paths()[_level].get_file().get_basename(), _section + 1,
			(" · " + name) if _phases.size() > 1 else "", roundi(_song.bpm),
			"" if _music_on else " · 这关没开叠轨音乐，放的是节拍器",
			"" if saved else " · 这个阶段还没单独存过谱子，现在显示的是照抄主谱（游戏里也是这样），改了保存后才分开"])
	_tl.queue_redraw()


## 换着听这个小关的第几个音乐阶段
func _set_tier(tier: int, progress: float) -> void:
	for i in _tier_box.get_child_count():
		(_tier_box.get_child(i) as Button).button_pressed = i == tier
	if not _music_on:
		return
	Music.section = _section
	Music.progress = progress
	Music.effective = progress
	Music.apply_now()


func _save() -> void:
	if _dirty.is_empty():
		_say("没有要存的改动")
		return
	var path: String = Levels.paths()[_level]
	DirAccess.make_dir_recursive_absolute(CHARTS_DIR)
	var src := load(path) as SongChart
	var err := OK
	for key: String in _dirty:
		var section := int(key.get_slice("/", 0))
		var phase := key.get_slice("/", 1)
		var file := _chart_file(section, phase)
		var out := (_patterns[key] as ChartPattern).duplicate(true) as ChartPattern
		err = ResourceSaver.save(out, file)
		if err != OK:
			break
		out.take_over_path(file)
		if phase == "":
			src.sections[section].chart = load(file) as ChartPattern  # 主谱挂到小关上；阶段谱子关卡自己按文件名找
	if err == OK:
		err = ResourceSaver.save(src, path)
	if err == OK:
		_dirty.clear()
		_say("保存好了，游戏里这一关直接用新的谱子")
	else:
		_say("保存失败（错误 %d）" % err)


# ================================================================ 播放

func _toggle_play() -> void:
	if _playing:
		_stop()
		return
	_playing = true
	Conductor.play(_beat)


func _stop() -> void:
	_playing = false
	Conductor.stop()


func _process(_delta: float) -> void:
	_play_btn.text = "暂停" if _playing else "播放"
	if pattern == null or not _playing:
		return
	var L := maxf(pattern.length_beats, 0.001)
	var now := fposmod(Conductor.song_beat, L)
	# 播放头扫过的打击响一下鼓，方便对着音乐听
	for d in pattern.notes:
		var b: float = d.beat
		if (_beat < now and b > _beat and b <= now) or (now < _beat and (b > _beat or b <= now)):
			_drums.play(int(d.get("sound", 0)))
	_beat = now
	if _beat < _scroll or _beat > _scroll + _page() - 0.5:
		_scroll_bar.value = _beat  # 播放头跑出画面了：翻过去
	_tl.queue_redraw()


# ================================================================ 编辑

func _kind_of(d: Dictionary) -> int:
	if d.get("mash", false):
		return 2
	return 1 if float(d.get("length", 0.0)) > 0.0 else 0


func _apply_kind(d: Dictionary, kind: int) -> void:
	match kind:
		0:
			d.erase("length")
			d.erase("mash")
		1:
			d.erase("mash")
			if float(d.get("length", 0.0)) <= 0.0:
				d["length"] = 1.0
		2:
			d["mash"] = true
			if float(d.get("length", 0.0)) <= 0.0:
				d["length"] = 2.0


func _apply_color(d: Dictionary, c: Color) -> void:
	if c.a <= 0.0:
		d.erase("color")
	else:
		d["color"] = c


func _set_kind(kind: int) -> void:
	_kind = kind
	for i in _kind_btns.size():
		_kind_btns[i].button_pressed = i == kind
	if not _sel.is_empty() and _kind_of(_sel) != kind:
		_remember()
		_apply_kind(_sel, kind)
		_changed()


func _set_color(index: int) -> void:
	_color = PALETTE[index]
	for i in _color_btns.size():
		_color_btns[i].button_pressed = i == index
	if not _sel.is_empty():
		_remember()
		_apply_color(_sel, _color)
		_changed()


func _snapshot() -> Array:
	return [pattern.notes.duplicate(true), pattern.length_beats]


## 改之前记一步撤销
func _remember() -> void:
	_undo.append(_snapshot())
	if _undo.size() > 200:
		_undo.pop_front()
	_redo.clear()


## 拖动：按下时先存着（_before），第一次真的改了才记一步
func _remember_drag() -> void:
	if not _before.is_empty():
		_undo.append(_before)
		_before = []
		_redo.clear()


func _changed() -> void:
	_dirty[_key(_section, _phase)] = true
	_tl.queue_redraw()
	_say("● 有改动没存（Ctrl+S 保存）")


func _undo_step(redo := false) -> void:
	var from := _redo if redo else _undo
	if from.is_empty():
		_say("没有可以重做的了" if redo else "没有可以撤销的了")
		return
	(_undo if redo else _redo).append(_snapshot())
	var s: Array = from.pop_back()
	pattern.notes.assign(s[0])
	pattern.length_beats = s[1]
	_loading = true
	_bars.value = pattern.length_beats / _song.beats_per_bar
	_loading = false
	_sel = {}
	_changed()
	_say("重做了一步" if redo else "撤销了一步（Ctrl+Y 重做）")


func _delete(d: Dictionary) -> void:
	if d.is_empty():
		return
	_remember()
	pattern.notes.erase(d)
	if is_same(_sel, d):
		_sel = {}
	_changed()


## 选中一个打击：上面的类型 / 颜色按钮跟着它亮
func _select(d: Dictionary) -> void:
	_sel = d
	_kind = _kind_of(d)
	for i in _kind_btns.size():
		_kind_btns[i].button_pressed = i == _kind
	_color = d.get("color", Color(0, 0, 0, 0))
	for i in _color_btns.size():
		_color_btns[i].button_pressed = PALETTE[i].is_equal_approx(_color)


# ================================================================ 时间线

func _rows() -> int:
	return 1  # 只有一行，左右滚动


func _row_h() -> float:
	return minf(_tl.size.y - 8.0, 150.0)


func _ppb() -> float:
	return (_tl.size.x - PAD * 2.0) / BEATS_PER_ROW * _zoom


## 一屏能放下几拍
func _page() -> float:
	return (_tl.size.x - PAD * 2.0) / maxf(_ppb(), 0.001)


## 谱子长度、窗口大小、缩放变了：滚动条跟着更新
func _update_scroll() -> void:
	if pattern == null:
		return
	_scroll_bar.max_value = pattern.length_beats
	_scroll_bar.page = minf(_page(), pattern.length_beats)
	_scroll_bar.value = clampf(_scroll_bar.value, 0.0, maxf(pattern.length_beats - _scroll_bar.page, 0.0))
	_scroll = _scroll_bar.value
	_tl.queue_redraw()


func _set_zoom(z: float, around_beat := -1.0) -> void:
	var keep := around_beat if around_beat >= 0.0 else _scroll + _page() / 2.0
	var offset := (keep - _scroll) * _ppb()  # 这一拍离左边多少像素，缩放后保持不动
	_zoom = clampf(z, 0.5, 8.0)
	_update_scroll()
	_scroll_bar.value = keep - offset / _ppb()


## 第几拍 -> 画面上的位置（这一行中线上）
func _pos(b: float) -> Vector2:
	return Vector2(PAD + (b - _scroll) * _ppb(), RULER + (_row_h() - RULER) / 2.0)


func _beat_at(p: Vector2) -> float:
	return clampf(_scroll + (p.x - PAD) / _ppb(), 0.0, pattern.length_beats)


func _snapped(b: float) -> float:
	var r := roundf(b / _snap) * _snap
	if r >= pattern.length_beats - 0.0001:
		return 0.0  # 最后那条线 = 循环回到开头的第 1 拍
	return maxf(r, 0.0)


func _note_at(p: Vector2) -> Dictionary:
	var b := _beat_at(p)
	var slack := (HEAD + 3.0) / _ppb()
	for i in range(pattern.notes.size() - 1, -1, -1):
		var d: Dictionary = pattern.notes[i]
		if b >= float(d.beat) - slack and b <= float(d.beat) + float(d.get("length", 0.0)) + slack:
			return d
	return {}


func _draw_tl() -> void:
	_tl.draw_rect(Rect2(Vector2.ZERO, _tl.size), Color(0.07, 0.05, 0.11))
	if pattern == null:
		return
	var font := get_theme_default_font()
	var L := pattern.length_beats
	var rh := _row_h()
	var bpb := _song.beats_per_bar
	for row in _rows():
		var y := row * rh
		var from := 0.0
		var to := L
		var x0 := PAD - _scroll * _ppb()
		_tl.draw_rect(Rect2(x0, y + RULER, L * _ppb(), rh - RULER - 6.0), Color(1, 1, 1, 0.04))
		_tl.draw_rect(Rect2(x0, y, L * _ppb(), RULER - 2.0), Color(1, 1, 1, 0.09))
		var b := from
		while b <= to + 0.001:
			var x := x0 + (b - from) * _ppb()
			var bar := is_zero_approx(fposmod(b, bpb))
			var on_beat := is_zero_approx(fposmod(b, 1.0))
			_tl.draw_line(Vector2(x, y + RULER), Vector2(x, y + rh - 6.0),
					Color(1, 1, 1, 0.4 if bar else (0.16 if on_beat else 0.06)), 2.0 if bar else 1.0)
			if bar and b < to:
				_tl.draw_string(font, Vector2(x + 3.0, y + 12.0), "第 %d 小节" % (int(b / bpb) + 1),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))
			b += _snap
	for d in pattern.notes:
		if float(d.beat) >= L:
			continue
		var kind := _kind_of(d)
		var col: Color = d.get("color", Color(0, 0, 0, 0))
		if col.a <= 0.0:
			col = KIND_COLORS[kind]
		var at := _pos(d.beat)
		if kind > 0:
			# 长条：跨行的时候一行一段
			var b0: float = d.beat
			var b1 := minf(b0 + float(d.length), L)
			while b0 < b1 - 0.0001:
				var seg := b1
				var p0 := _pos(b0)
				var r := Rect2(p0.x, p0.y - HEAD * 0.6, (seg - b0) * _ppb(), HEAD * 1.2)
				_tl.draw_rect(r, Color(col, 0.55))
				if kind == 2:
					var sx := r.position.x + 6.0
					while sx < r.end.x:
						_tl.draw_line(Vector2(sx, r.position.y), Vector2(sx, r.end.y), Color(0, 0, 0, 0.5), 2.0)
						sx += 7.0
				b0 = seg
			var tail := _pos(minf(float(d.beat) + float(d.length), L - 0.0001))
			_tl.draw_rect(Rect2(tail.x - 3.0, tail.y - HEAD, 6.0, HEAD * 2.0), col)  # 右头：拖它改长度
		_tl.draw_circle(at, HEAD, col)
		if is_zero_approx(float(d.beat)):
			_tl.draw_circle(_pos(L), HEAD, Color(col, 0.35))  # 循环：开头这一下也淡淡地画在最后那条线上
		if kind == 2:
			_tl.draw_string(font, at + Vector2(-6.0, 5.0), "连", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
		if is_same(d, _sel):
			_tl.draw_arc(at, HEAD + 4.0, 0.0, TAU, 32, Color.WHITE, 2.0, true)
	# 播放头
	var ph := _pos(minf(_beat, L - 0.0001))
	var top := floorf(ph.y / rh) * rh
	_tl.draw_line(Vector2(ph.x, top), Vector2(ph.x, top + rh - 4.0), Color(1.0, 0.35, 0.35), 2.0)


func _tl_input(event: InputEvent) -> void:
	if pattern == null:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# 滚轮 = 左右滚，Ctrl + 滚轮 = 缩放（鼠标指着的那一拍不动）
		var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		if mb.ctrl_pressed or mb.meta_pressed:
			_set_zoom(_zoom * (1.0 - dir * 0.15), _beat_at(mb.position))
		else:
			_scroll_bar.value += dir * _page() * 0.15
		accept_event()
		return
	if mb and mb.pressed:
		get_viewport().gui_release_focus()
		var hit := _note_at(mb.position)
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_delete(hit)
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if fposmod(mb.position.y, _row_h()) < RULER:
			_drag = "seek"
			_seek(_beat_at(mb.position))
			return
		if hit.is_empty():
			# 空白处：放一个新的
			var d := {"beat": _snapped(_beat_at(mb.position)), "sound": NoteData.Sound.KICK}
			_remember()
			_apply_kind(d, _kind)
			_apply_color(d, _color)
			pattern.notes.append(d)
			_sel = d
			_drag = "len" if _kind > 0 else "move"
			_changed()
			return
		_select(hit)
		_before = _snapshot()
		var end_beat := float(hit.beat) + float(hit.get("length", 0.0))
		_drag = "len" if _kind_of(hit) > 0 and _beat_at(mb.position) >= end_beat - 6.0 / _ppb() else "move"
		_tl.queue_redraw()
	elif mb and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_drag = ""
		_before = []
	var mm := event as InputEventMouseMotion
	if mm == null or _drag == "":
		return
	var b := _beat_at(mm.position)
	match _drag:
		"seek":
			_seek(b)
		"move":
			if not is_equal_approx(float(_sel.beat), _snapped(b)):
				_remember_drag()
				_sel.beat = _snapped(b)
				_changed()
		"len":
			var length := maxf(roundf((b - float(_sel.beat)) / _snap) * _snap, _snap)
			if not is_equal_approx(float(_sel.get("length", 0.0)), length):
				_remember_drag()
				_sel["length"] = length
				_changed()


func _seek(b: float) -> void:
	_beat = clampf(b, 0.0, maxf(pattern.length_beats - 0.001, 0.0))
	if _playing:
		Conductor.play(_beat)
	_tl.queue_redraw()


# ================================================================ 按键

func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var cmd := k.ctrl_pressed or k.meta_pressed
	if get_viewport().gui_get_focus_owner() is LineEdit and not cmd:
		return  # 正在「循环几小节」里打字：数字键、空格留给它，Ctrl 组合键照常
	var handled := true
	match k.keycode:
		KEY_SPACE: _toggle_play()
		KEY_1: _set_kind(0)
		KEY_2: _set_kind(1)
		KEY_3: _set_kind(2)
		KEY_DELETE, KEY_BACKSPACE: _delete(_sel)
		KEY_S when cmd: _save()
		KEY_Z when cmd: _undo_step(k.shift_pressed)
		KEY_Y when cmd: _undo_step(true)
		_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


# ================================================================ 界面

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# 第一排：哪一关、哪个小关、听第几个音乐阶段
	var row1 := HFlowContainer.new()
	root.add_child(row1)
	row1.add_child(_label("关卡"))
	_level_pick.focus_mode = Control.FOCUS_NONE
	_level_pick.item_selected.connect(func(i: int) -> void:
		if not _loading:
			_open_level(i))
	_level_pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row1.add_child(_level_pick)
	row1.add_child(_label("   小关"))
	row1.add_child(_stage_box)
	_phase_label = _label("   玩法阶段")
	row1.add_child(_phase_label)
	row1.add_child(_phase_box)
	row1.add_child(_label("   这一段里的音乐"))
	row1.add_child(_tier_box)

	# 第二排：播放、类型、颜色、网格、长度、保存
	var row2 := HFlowContainer.new()
	root.add_child(row2)
	_play_btn.text = "播放"
	_play_btn.custom_minimum_size.x = 70
	_play_btn.focus_mode = Control.FOCUS_NONE
	_play_btn.pressed.connect(_toggle_play)
	row2.add_child(_play_btn)
	row2.add_child(_label(" 速度"))
	var speed := OptionButton.new()
	speed.focus_mode = Control.FOCUS_NONE
	speed.tooltip_text = "放慢了听（音调会跟着变低）。只影响这个编辑器，不影响游戏"
	for key: String in SPEEDS:
		speed.add_item(key)
	speed.item_selected.connect(func(i: int) -> void: Conductor.speed = SPEEDS[speed.get_item_text(i)])
	row2.add_child(speed)
	row2.add_child(_label("   类型"))
	for i in KIND_NAMES.size():
		var b := Button.new()
		b.text = "%s (%d)" % [KIND_NAMES[i], i + 1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.modulate = KIND_COLORS[i].lightened(0.35)
		b.pressed.connect(_set_kind.bind(i))
		row2.add_child(b)
		_kind_btns.append(b)
	row2.add_child(_label("   颜色"))
	for i in PALETTE.size():
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(30, 30)
		if i == 0:
			b.text = "默认"
			b.tooltip_text = "不指定颜色：游戏里用关卡自己的颜色"
		else:
			var sw := ColorRect.new()
			sw.color = PALETTE[i]
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sw.set_anchors_preset(Control.PRESET_FULL_RECT)
			sw.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
			b.add_child(sw)
		b.pressed.connect(_set_color.bind(i))
		row2.add_child(b)
		_color_btns.append(b)
	row2.add_child(_label("   网格"))
	var snap := OptionButton.new()
	snap.focus_mode = Control.FOCUS_NONE
	for key: String in SNAPS:
		snap.add_item(key)
	snap.select(1)
	snap.item_selected.connect(func(i: int) -> void:
		_snap = SNAPS[snap.get_item_text(i)]
		_tl.queue_redraw())
	row2.add_child(snap)
	row2.add_child(_label("   循环几小节"))
	_bars.min_value = 1
	_bars.max_value = 64
	_bars.value_changed.connect(func(v: float) -> void:
		if _loading or pattern == null:
			return
		_remember()
		pattern.length_beats = v * _song.beats_per_bar
		_beat = 0.0
		_update_scroll()
		_changed())
	row2.add_child(_bars)
	row2.add_child(_label("   缩放"))
	for z: Array in [["−", 1.0 / 1.4], ["+", 1.4]]:
		var zb := Button.new()
		zb.text = z[0]
		zb.custom_minimum_size.x = 30
		zb.focus_mode = Control.FOCUS_NONE
		zb.tooltip_text = "时间线放大 / 缩小（也可以 Ctrl + 滚轮）"
		zb.pressed.connect(func() -> void: _set_zoom(_zoom * float(z[1])))
		row2.add_child(zb)
	var undo := Button.new()
	undo.text = "撤销 (Ctrl+Z)"
	undo.focus_mode = Control.FOCUS_NONE
	undo.pressed.connect(_undo_step)
	row2.add_child(undo)
	var save := Button.new()
	save.text = "保存 (Ctrl+S)"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save)
	row2.add_child(save)

	_tl.custom_minimum_size = Vector2(0, 170)
	_tl.clip_contents = true
	_tl.draw.connect(_draw_tl)
	_tl.gui_input.connect(_tl_input)
	_tl.resized.connect(_update_scroll)
	root.add_child(_tl)
	# 时间线下面的滚动条：左右拖
	_scroll_bar.custom_minimum_size = Vector2(0, 18)
	_scroll_bar.focus_mode = Control.FOCUS_NONE
	_scroll_bar.value_changed.connect(func(v: float) -> void:
		_scroll = v
		_tl.queue_redraw())
	root.add_child(_scroll_bar)
	var gap := Control.new()  # 剩下的地方空着
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(gap)

	var help := _label("下面的滚动条 / 滚轮左右拖 · Ctrl+滚轮缩放 · 点空白放打击 · 拖动挪位置 · 长按 / 连击拖右头改长度 · 右键删 · 点顶上的细条挪播放头 · 空格播放")
	help.modulate.a = 0.6
	root.add_child(help)
	root.add_child(_status)
	_set_kind(0)
	_set_color(0)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	return l


func _say(text: String) -> void:
	_status.text = text
