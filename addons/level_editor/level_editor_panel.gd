@tool
extends MarginContainer
## 关卡编辑器的面板。
## 上面一排选大关、改大关的设置；左边是这个大关里的小关列表和所有可用的小关场景；
## 右边是选中那个小关的设置和谱子格子，可以试听。
## 数据就是 levels/ 文件夹里的 .tres（SongChart），这里只是换一种更顺手的方式编辑它；
## 改完要点“保存”（试玩前会自动保存）。

signal play_requested(level_path: String, section: int)
signal open_scene_requested(path: String)
signal inspect_requested(res: Resource)
signal files_changed

const Grid := preload("res://addons/level_editor/pattern_grid.gd")
const LOOKS := ["OFF", "HALFTONE", "HATCH", "FLAT", "PRINT", "Y2K", "Y2K_JPEG"]
const BRUSHES := ["底鼓 K", "军鼓 S", "踩镲 H", "橡皮"]
const DEFAULT_BAR := "k...s...k...s..."

var chart: SongChart
var chart_path := ""
var dirty := false
var _sel := -1          # 选中的小关
var _loading := false   # 正在把数据填进控件（这时控件的变化不算用户编辑）

# 控件
var _level_pick: OptionButton
var _status: Label
var _title: LineEdit
var _look: OptionButton
var _bpm: SpinBox
var _bpb: SpinBox
var _rest: SpinBox
var _music: Label
var _sections: ItemList
var _scenes: ItemList
var _detail: VBoxContainer
var _s_title: LineEdit
var _s_scene: OptionButton
var _s_transition: OptionButton
var _s_rev: SpinBox
var _s_gauge: SpinBox
var _s_use_events: CheckBox
var _s_events: LineEdit
var _s_info: Label
var _grid: Control
var _play_btn: Button
var _with_music: CheckBox

# 试听
var _players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _auditioning := false
var _audition_time := 0.0


func _ready() -> void:
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		add_theme_constant_override(m, 10)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	for i in 3:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -6.0
	add_child(_music_player)
	refresh_lists()
	if _level_pick.item_count > 0:
		_open(_level_pick.get_item_metadata(0))


# ---------------------------------------------------------------- 界面

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# 第一排：选大关
	var top := HBoxContainer.new()
	root.add_child(top)
	top.add_child(_label("大关"))
	_level_pick = OptionButton.new()
	_level_pick.custom_minimum_size.x = 200
	_level_pick.item_selected.connect(func(i: int): _open(_level_pick.get_item_metadata(i)))
	top.add_child(_level_pick)
	top.add_child(_button("新建大关", _new_level, "照着现在这个大关的歌和鼓声新建一个空的大关"))
	top.add_child(_button("保存", save, "把改动写进 .tres 文件"))
	top.add_child(VSeparator.new())
	top.add_child(_button("▶ 试玩大关", func(): _play(0), "保存，然后从第一个小关开始运行游戏"))
	top.add_child(_button("▶ 从选中的小关试玩", func(): _play(maxi(_sel, 0)), "保存，然后直接从左边选中的小关开始运行游戏"))
	top.add_child(_button("在检查器里打开", func(): inspect_requested.emit(chart), "换歌、换鼓声这些不常改的项目在检查器里改"))
	_status = _label("")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_status)

	# 第二排：大关的设置
	var meta := HBoxContainer.new()
	root.add_child(meta)
	meta.add_child(_label("名字"))
	_title = LineEdit.new()
	_title.custom_minimum_size.x = 160
	_title.text_changed.connect(func(t: String): _edit_chart("title", t))
	meta.add_child(_title)
	meta.add_child(_label("  画面风格"))
	_look = OptionButton.new()
	for l in LOOKS:
		_look.add_item(l)
	_look.item_selected.connect(func(i: int): _edit_chart("look", LOOKS[i]))
	meta.add_child(_look)
	meta.add_child(_label("  BPM"))
	_bpm = _spin(30, 300, 0.5, func(v: float): _edit_chart("bpm", v))
	meta.add_child(_bpm)
	meta.add_child(_label("  每小节几拍"))
	_bpb = _spin(1, 12, 1, func(v: float): _edit_chart("beats_per_bar", int(v)))
	meta.add_child(_bpb)
	meta.add_child(_label("  进小关先空几小节"))
	_rest = _spin(0, 8, 1, func(v: float): _edit_chart("rest_bars_on_switch", int(v)))
	meta.add_child(_rest)
	_music = _label("")
	_music.modulate.a = 0.6
	meta.add_child(_music)

	root.add_child(HSeparator.new())
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	# 左边：小关列表 + 可用场景
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	split.add_child(left)
	left.add_child(_label("小关（从上到下是闯关顺序）"))
	_sections = ItemList.new()
	_sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sections.item_selected.connect(_select)
	_sections.item_activated.connect(func(i: int): _open_scene_of(i))
	left.add_child(_sections)
	var ops := HBoxContainer.new()
	left.add_child(ops)
	ops.add_child(_button("↑", func(): _move(-1), "往前挪"))
	ops.add_child(_button("↓", func(): _move(1), "往后挪"))
	ops.add_child(_button("复制", _duplicate_section, "复制选中的小关"))
	ops.add_child(_button("删除", _remove_section, "删掉选中的小关"))
	ops.add_child(_button("打开场景", func(): _open_scene_of(_sel), "在编辑器里打开这个小关的场景（双击列表也行）"))
	left.add_child(HSeparator.new())
	var head := HBoxContainer.new()
	left.add_child(head)
	var scenes_label := _label("可用的小关场景（双击添加）")
	scenes_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(scenes_label)
	head.add_child(_button("刷新", refresh_lists, "重新扫描小关场景文件夹"))
	_scenes = ItemList.new()
	_scenes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scenes.item_activated.connect(func(i: int): _add_section(_scenes.get_item_text(i)))
	left.add_child(_scenes)
	left.add_child(_button("添加到小关列表", func():
		var picked := _scenes.get_selected_items()
		if picked.size() > 0:
			_add_section(_scenes.get_item_text(picked[0])), "把选中的场景加成一个新的小关，放在选中的小关后面"))

	# 右边：选中小关的设置和谱子
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	split.add_child(_detail)

	var row1 := HBoxContainer.new()
	_detail.add_child(row1)
	row1.add_child(_label("小关名字"))
	_s_title = LineEdit.new()
	_s_title.custom_minimum_size.x = 160
	_s_title.text_changed.connect(func(t: String): _edit_section("title", t))
	row1.add_child(_s_title)
	row1.add_child(_label("  场景"))
	_s_scene = OptionButton.new()
	_s_scene.custom_minimum_size.x = 180
	_s_scene.item_selected.connect(func(i: int): _edit_section("scene_file", _s_scene.get_item_text(i)))
	row1.add_child(_s_scene)
	row1.add_child(_label("  转场"))
	_s_transition = OptionButton.new()
	_s_transition.add_item("放大淡入")
	_s_transition.add_item("硬切 + 白闪")
	_s_transition.item_selected.connect(func(i: int): _edit_section("transition", i))
	row1.add_child(_s_transition)
	row1.add_child(_label("  转一圈几拍"))
	_s_rev = _spin(0.25, 64, 0.25, func(v: float): _edit_section("beats_per_rev", v))
	row1.add_child(_s_rev)

	var row2 := HBoxContainer.new()
	_detail.add_child(row2)
	row2.add_child(_label("积累条满条值"))
	_s_gauge = _spin(0, 2000, 5, func(v: float): _edit_section("gauge_max", int(v)))
	_s_gauge.tooltip_text = "0 = 用场景里填的值，场景也没填就是 60"
	row2.add_child(_s_gauge)
	_s_use_events = CheckBox.new()
	_s_use_events.text = "自己定事件分数线"
	_s_use_events.tooltip_text = "不勾 = 用场景里填的。勾上后右边留空 = 这个小关没有事件"
	_s_use_events.toggled.connect(func(on: bool): _edit_section("use_gauge_events", on))
	row2.add_child(_s_use_events)
	_s_events = LineEdit.new()
	_s_events.placeholder_text = "比如 20, 40"
	_s_events.custom_minimum_size.x = 140
	_s_events.text_changed.connect(func(t: String): _edit_section("gauge_events", _parse_events(t)))
	row2.add_child(_s_events)
	_s_info = _label("")
	_s_info.modulate.a = 0.7
	row2.add_child(_s_info)

	_detail.add_child(HSeparator.new())
	var tools := HBoxContainer.new()
	_detail.add_child(tools)
	tools.add_child(_label("谱子   画笔"))
	var group := ButtonGroup.new()
	for i in BRUSHES.size():
		var b := Button.new()
		b.text = BRUSHES[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.pressed.connect(func(): _grid.brush = i if i < 3 else -1)
		if i < 3:
			b.add_theme_color_override("font_color", Grid.COLORS[i])
			b.add_theme_color_override("font_pressed_color", Grid.COLORS[i])
		tools.add_child(b)
	tools.add_child(VSeparator.new())
	tools.add_child(_button("＋ 小节", _add_bar, "在最后加一小节"))
	tools.add_child(_button("－ 小节", _remove_bar, "删掉最后一小节"))
	tools.add_child(_button("清空", _clear_bars, "所有格子清空"))
	tools.add_child(VSeparator.new())
	_play_btn = _button("▶ 试听", _toggle_audition, "循环播放这几小节的鼓")
	tools.add_child(_play_btn)
	_with_music = CheckBox.new()
	_with_music.text = "带伴奏"
	_with_music.button_pressed = true
	tools.add_child(_with_music)
	var hint := _label("   左键涂 / 再点一下擦掉，右键擦，可以拖。这几小节会一直循环到积累条满")
	hint.modulate.a = 0.5
	tools.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(scroll)
	_grid = Grid.new()
	_grid.edited.connect(_on_grid_edited)
	scroll.add_child(_grid)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(text: String, action: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	return b


func _spin(lo: float, hi: float, step: float, action: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value_changed.connect(action)
	return s


# ---------------------------------------------------------------- 大关

## 重新扫描大关文件夹和小关场景文件夹
func refresh_lists() -> void:
	if _level_pick == null:
		return
	Levels.rescan()
	_loading = true
	_level_pick.clear()
	for path in Levels.paths():
		_level_pick.add_item(path.get_file().get_basename())
		_level_pick.set_item_metadata(_level_pick.item_count - 1, path)
		if path == chart_path:
			_level_pick.select(_level_pick.item_count - 1)
	var scenes := SectionDef.available_scenes()
	_scenes.clear()
	_s_scene.clear()
	for s in scenes:
		_scenes.add_item(s)
		_s_scene.add_item(s)
	_loading = false
	_show_section()


func _open(path: String) -> void:
	if dirty:
		save()
	stop_audition()
	chart_path = path
	chart = load(path) as SongChart
	_sel = 0 if chart and chart.sections.size() > 0 else -1
	_loading = true
	for i in _level_pick.item_count:
		if _level_pick.get_item_metadata(i) == path:
			_level_pick.select(i)
	_title.text = chart.title
	_look.select(maxi(LOOKS.find(chart.look), 0))
	_bpm.value = chart.bpm
	_bpb.value = chart.beats_per_bar
	_rest.value = chart.rest_bars_on_switch
	_music.text = "   伴奏：" + (chart.stream.resource_path.get_file() if chart.stream else "（没有）")
	_loading = false
	_set_dirty(false)
	_fill_sections()


func _edit_chart(prop: String, value: Variant) -> void:
	if _loading or chart == null:
		return
	chart.set(prop, value)
	_set_dirty(true)
	_update_info()


func save() -> void:
	if chart == null:
		return
	var err := ResourceSaver.save(chart, chart_path)
	if err != OK:
		_status.text = "保存失败：" + error_string(err)
		return
	_set_dirty(false)


func _set_dirty(value: bool) -> void:
	dirty = value
	_status.text = (chart_path.get_file() + ("  ● 有改动还没保存" if dirty else "  已保存")) if chart else ""


func _new_level() -> void:
	var n := Levels.count() + 1
	var folder: String = ProjectSettings.get_setting(Levels.LEVELS_FOLDER_SETTING, Levels.LEVELS_FOLDER_DEFAULT)
	var path := folder.path_join("level_%d.tres" % n)
	while ResourceLoader.exists(path):
		n += 1
		path = folder.path_join("level_%d.tres" % n)
	var c := SongChart.new()
	c.title = "LEVEL %d" % n
	if chart:  # 歌和鼓声先照抄现在这个大关的
		for prop in ["stream", "bpm", "beats_per_bar", "first_beat_offset_sec", "drum_kick", "drum_snare", "drum_hat", "rest_bars_on_switch"]:
			c.set(prop, chart.get(prop))
	if ResourceSaver.save(c, path) != OK:
		_status.text = "新建失败"
		return
	files_changed.emit()
	chart_path = path
	refresh_lists()
	_open(path)
	_status.text += "   （主菜单转盘上的格子也要加一格）"


func _play(section: int) -> void:
	if chart == null or chart.sections.is_empty():
		_status.text = "这个大关还没有小关，先在左下角双击一个场景加进来"
		return
	stop_audition()
	save()
	play_requested.emit(chart_path, section)


# ---------------------------------------------------------------- 小关列表

func _fill_sections() -> void:
	_sections.clear()
	for i in chart.sections.size():
		var s := chart.sections[i]
		var file: String = s.get("scene_file")
		_sections.add_item("%d.  %s    —  %s  ·  %d 小节" % [i + 1, s.title if s.title != "" else "（没名字）",
				file if file != "" else "没选场景", s.bars.size()])
	if _sel >= chart.sections.size():
		_sel = chart.sections.size() - 1
	if _sel >= 0:
		_sections.select(_sel)
	_show_section()


func _select(index: int) -> void:
	stop_audition()
	_sel = index
	_show_section()


func _current() -> SectionDef:
	return chart.sections[_sel] if chart and _sel >= 0 and _sel < chart.sections.size() else null


func _add_section(scene_file: String) -> void:
	if chart == null:
		return
	var s := SectionDef.new()
	s.set("scene_file", scene_file)
	s.title = scene_file.get_file().get_basename().to_upper()
	s.beats_per_rev = 8.0
	s.bars = PackedStringArray([DEFAULT_BAR, DEFAULT_BAR])
	_sel = clampi(_sel + 1, 0, chart.sections.size())
	chart.sections.insert(_sel, s)
	_changed_sections()


func _duplicate_section() -> void:
	var s := _current()
	if s == null:
		return
	_sel += 1
	chart.sections.insert(_sel, s.duplicate(true))
	_changed_sections()


func _remove_section() -> void:
	if _current() == null:
		return
	stop_audition()
	chart.sections.remove_at(_sel)
	_changed_sections()


func _move(by: int) -> void:
	var to := _sel + by
	if _current() == null or to < 0 or to >= chart.sections.size():
		return
	var s := chart.sections[_sel]
	chart.sections[_sel] = chart.sections[to]
	chart.sections[to] = s
	_sel = to
	_changed_sections()


func _changed_sections() -> void:
	_set_dirty(true)
	_fill_sections()


func _open_scene_of(index: int) -> void:
	if chart and index >= 0 and index < chart.sections.size() and chart.sections[index].scene:
		open_scene_requested.emit(chart.sections[index].scene.resource_path)


# ---------------------------------------------------------------- 选中的小关

func _show_section() -> void:
	if _detail == null:
		return
	var s := _current()
	_detail.modulate.a = 1.0 if s else 0.35
	if s == null:
		_grid.set_bars(PackedStringArray())
		return
	_loading = true
	_s_title.text = s.title
	var file: String = s.get("scene_file")
	var found := -1
	for i in _s_scene.item_count:
		if _s_scene.get_item_text(i) == file:
			found = i
	if found < 0 and file != "":  # 用的是文件夹外面的场景，也显示出来
		_s_scene.add_item(file)
		found = _s_scene.item_count - 1
	_s_scene.select(found)
	_s_transition.select(s.transition)
	_s_rev.value = s.beats_per_rev
	_s_gauge.value = s.gauge_max
	_s_use_events.button_pressed = s.use_gauge_events
	_s_events.text = ", ".join(Array(s.gauge_events).map(func(v): return str(v)))
	_s_events.editable = s.use_gauge_events
	_grid.beats_per_bar = chart.beats_per_bar
	_grid.set_bars(s.bars)
	_loading = false
	_update_info()


func _edit_section(prop: String, value: Variant) -> void:
	var s := _current()
	if _loading or s == null:
		return
	s.set(prop, value)
	_set_dirty(true)
	if prop == "use_gauge_events":
		_s_events.editable = value
	if prop in ["title", "scene_file"]:
		var keep := _sel
		_fill_sections()
		_sel = keep
	_update_info()


func _parse_events(text: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for part in text.replace("，", ",").replace(" ", ",").split(",", false):
		if part.is_valid_int() and int(part) > 0:
			out.append(int(part))
	out.sort()
	return out


## 这个小关实际的满条值：谱面里填了用谱面的，否则看场景根节点上填的，都没有就是 60
func effective_gauge_max(s: SectionDef) -> int:
	if s.gauge_max > 0:
		return s.gauge_max
	if s.scene:
		var state := s.scene.get_state()
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == &"gauge_max_override" and int(state.get_node_property_value(0, i)) > 0:
				return int(state.get_node_property_value(0, i))
	return 60


## 全中的话这个小关大概要打多少秒（不算刚进来空的那几小节）
func estimate_seconds(s: SectionDef) -> float:
	var notes := s.parse_notes(chart.beats_per_bar)
	if notes.is_empty() or s.bars.is_empty():
		return -1.0
	var need := ceili(effective_gauge_max(s) / 5.0)  # 每个 Perfect +5
	var loop_beats := float(s.bars.size() * chart.beats_per_bar)
	var full_loops := (need - 1) / notes.size()
	var last: float = notes[(need - 1) % notes.size()].beat
	return (full_loops * loop_beats + last) * 60.0 / chart.bpm


func _update_info() -> void:
	var s := _current()
	if s == null or _s_info == null:
		return
	var sec := estimate_seconds(s)
	var count := s.parse_notes(chart.beats_per_bar).size()
	if sec < 0.0:
		_s_info.text = "   谱子是空的，这个小关永远打不满"
	else:
		_s_info.text = "   满条 %d 分 · 一遍 %d 个音符 · 全中大约 %.0f 秒打满" % [effective_gauge_max(s), count, sec]


# ---------------------------------------------------------------- 谱子

func _on_grid_edited() -> void:
	var s := _current()
	if s == null:
		return
	s.bars = _grid.bars.duplicate()
	_set_dirty(true)
	_update_info()


func _set_bars(bars: PackedStringArray) -> void:
	var s := _current()
	if s == null:
		return
	s.bars = bars
	_grid.set_bars(bars)
	_set_dirty(true)
	var keep := _sel
	_fill_sections()
	_sel = keep


func _add_bar() -> void:
	var s := _current()
	if s:
		var bars := s.bars.duplicate()
		bars.append(".".repeat(bars[-1].length() if bars.size() > 0 and bars[-1] != "" else 16))
		_set_bars(bars)


func _remove_bar() -> void:
	var s := _current()
	if s and s.bars.size() > 1:
		var bars := s.bars.duplicate()
		bars.remove_at(bars.size() - 1)
		_set_bars(bars)


func _clear_bars() -> void:
	var s := _current()
	if s:
		var bars := PackedStringArray()
		for b in s.bars:
			bars.append(".".repeat(b.length() if b != "" else 16))
		_set_bars(bars)


# ---------------------------------------------------------------- 试听

func _toggle_audition() -> void:
	if _auditioning:
		stop_audition()
	elif _current():
		_auditioning = true
		_audition_time = 0.0
		_play_btn.text = "■ 停"
		var kit: Array[AudioStream] = [chart.drum_kick, chart.drum_snare, chart.drum_hat]
		for i in 3:
			_players[i].stream = kit[i]
		if _with_music.button_pressed and chart.stream:
			_music_player.stream = chart.stream
			_music_player.play(chart.first_beat_offset_sec)
		_hit_between(-1.0, 0.0)


func stop_audition() -> void:
	if not _auditioning:
		return
	_auditioning = false
	_music_player.stop()
	_play_btn.text = "▶ 试听"
	_grid.playhead = -1.0
	_grid.queue_redraw()


func _process(delta: float) -> void:
	if not _auditioning:
		return
	var s := _current()
	if s == null or not is_visible_in_tree():
		stop_audition()
		return
	var before := _audition_time * chart.bpm / 60.0
	_audition_time += delta
	_hit_between(before, _audition_time * chart.bpm / 60.0)
	var loop := float(s.bars.size() * chart.beats_per_bar)
	_grid.playhead = fposmod(_audition_time * chart.bpm / 60.0, loop) / chart.beats_per_bar
	_grid.queue_redraw()


## 把 (from, to] 这段拍子里的鼓敲出来（谱子循环）
func _hit_between(from: float, to: float) -> void:
	var s := _current()
	var loop := float(s.bars.size() * chart.beats_per_bar)
	if loop <= 0.0:
		return
	for n in s.parse_notes(chart.beats_per_bar):
		var k := ceilf((from - n.beat) / loop + 0.000001)
		if n.beat + k * loop <= to and _players[n.sound].stream:
			_players[n.sound].play()
