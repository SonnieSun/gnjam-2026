extends Control
## 谱面编辑器（scenes/tools/chart_editor.tscn，直接 F6 运行；游戏里 Tab 面板的 "Chart" 按钮也能进）。
## 给每个小关写一段循环的谱子（ChartPattern），每个音符可以设出现时间、发光、旋转、大小、轨道、颜色、长按。
## 时间和判定还是全局的 Conductor + Judge：编辑时播放头走的是 Conductor，试玩时就是正式的 Judge 在判。
##
## 画面：上面是预览（真实的关卡画面 + 选中的表现方式叠在上面），右边是属性，下面是时间轴（见 chart_timeline.gd）。
##
##   空格        播放 / 暂停（试玩时空格是打击键）
##   T          试玩开 / 关：从播放头所在那一遍的开头起，用正式的判定打一遍（Esc 也能退出试玩）
##   1 / 2 / 3  笔刷：底鼓 / 军鼓 / 踩镲（在时间轴上点空白处放的音符用这个音色）
##   M          选中的音符 连击 开 / 关（连击 = 这一段里狂按，段长 = 长按那个长度）
##   Delete     删掉选中的音符        Ctrl/Cmd + A  全选
##   Ctrl/Cmd + C / V   复制 / 粘贴选中的音符（贴到播放头位置）
##   Ctrl/Cmd + Z / Shift+Z   撤销 / 重做        Ctrl/Cmd + S  保存
##   Esc        回主菜单
##
## 保存：谱子存成 levels/charts/<大关文件名>_<第几个小关>.tres，再挂到大关 .tres 里那个小关的 chart 上。
## 挂上之后游戏里这个小关就用这份谱子（代替老的鼓谱字符串）；谱子里勾了“游戏里用这个表现”，
## 音符也换成这里选的表现方式画。

const Timeline := preload("res://scripts/tools/chart_timeline.gd")
const THEME := preload("res://assets/ui/theme.tres")
const CHARTS_DIR := "res://levels/charts/"
const SNAPS := {"1/1": 1.0, "1/2": 0.5, "1/3": 1.0 / 3.0, "1/4": 0.25, "1/6": 1.0 / 6.0, "1/8": 0.125}

## 从别处跳进来时指定打开哪一关的哪个小关（Tab 面板用）
static var open_level := -1
static var open_section := 0

var pattern: ChartPattern

var _level := 0
var _section := 0
var _song: SongChart
var _def: SectionDef  # 预览 / 试玩用的副本（chart = pattern）
var _style: NoteStyle
var _scene: SpinSection
var _judge: Judge
var _drums: DrumKit
var _timeline: Timeline
var _viewport: SubViewport
var _beat := 0.0
var _playing := false
var _playtest := false
var _cache := {}
var _live: Array[NoteData] = []
var _undo: Array = []
var _redo: Array = []
var _state: Dictionary
var _clipboard: Array = []
var _dirty := false
var _loading := false

# 界面
var _level_pick := OptionButton.new()
var _section_pick := OptionButton.new()
var _style_pick := OptionButton.new()
var _snap_pick := OptionButton.new()
var _brush_btns: Array[Button] = []
var _play_btn := Button.new()
var _test_btn := Button.new()
var _auto := CheckBox.new()
var _show_level := CheckBox.new()
var _show_style := CheckBox.new()
var _status := Label.new()
var _fields := {}  # 属性名 -> 控件
var _color_default := CheckBox.new()
var _color_pick := ColorPickerButton.new()
var _sel_label := Label.new()
var _music_on := false  # 这一关用的是叠轨音乐（levels/music/*.json 开了 use_in_game）
var _progress := HSlider.new()
var _progress_label := Label.new()
var _mash_check := CheckBox.new()
var _p_fields := {}  # 谱子设置 -> 控件


func _ready() -> void:
	theme = THEME
	Judge.ensure_input()  # 关卡画面里有的东西直接读打击键
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_drums = DrumKit.new()
	add_child(_drums)
	_build_ui()
	Levels.rescan()
	for i in Levels.count():
		_level_pick.add_item("%d  %s" % [i + 1, Levels.paths()[i].get_file().get_basename()], i)
	_open(open_level if open_level >= 0 else Levels.selected, open_section)
	open_level = -1


func _exit_tree() -> void:
	Conductor.stop()
	Music.clear()


# ================================================================ 打开 / 保存

func _open(level: int, section: int) -> void:
	_stop_playtest()
	_level = clampi(level, 0, Levels.count() - 1)
	_song = (load(Levels.paths()[_level]) as SongChart).duplicate(true) as SongChart
	_section = clampi(section, 0, _song.sections.size() - 1)
	# 叠轨音乐：和游戏里（main.gd）一样，这一关开了就用它代替谱面里的伴奏，BPM 也跟着配置走
	var cfg := Music.read(Music.MUSIC_DIR + Levels.paths()[_level].get_file().get_basename() + ".json")
	_music_on = cfg.get("use_in_game", false)
	if _music_on:
		_song.stream = Music.build(cfg)
		_song.bpm = Music.bpm()
		_song.first_beat_offset_sec = 0.0
	else:
		Music.clear()
	_song.recompute()
	_loading = true
	_level_pick.select(_level)
	_section_pick.clear()
	for i in _song.sections.size():
		_section_pick.add_item("%d  %s" % [i + 1, _song.sections[i].title], i)
	_section_pick.select(_section)
	_loading = false
	var src := _song.sections[_section]
	pattern = src.chart.duplicate(true) if src.chart else ChartPattern.from_bars(src.bars, _song.beats_per_bar)
	_def = src.duplicate() as SectionDef
	_def.chart = pattern
	_def.start_beat = 0.0
	_def.length = pattern.length_beats
	Conductor.stop()
	Conductor.load_chart(_song)
	_music_apply()
	_beat = 0.0
	_undo.clear()
	_redo.clear()
	_state = _snapshot()
	_dirty = false
	_timeline.pattern = pattern
	_timeline.beats_per_bar = _song.beats_per_bar
	_timeline.selected.clear()
	_timeline.fit()
	_load_pattern_fields()
	_rebuild_preview()
	_on_selection()
	_set_status("打开了 %s / 第 %d 个小关%s" % [Levels.paths()[_level].get_file(), _section + 1,
			"" if src.chart else "（从老鼓谱导入，保存后才会写成新谱子）"])


func _save() -> void:
	var path: String = Levels.paths()[_level]
	var file := CHARTS_DIR + "%s_%d.tres" % [path.get_file().get_basename(), _section]
	DirAccess.make_dir_recursive_absolute(CHARTS_DIR)
	var out := pattern.duplicate(true) as ChartPattern
	var err := ResourceSaver.save(out, file)
	if err == OK:
		out.take_over_path(file)
		var src := load(path) as SongChart
		src.sections[_section].chart = load(file) as ChartPattern
		err = ResourceSaver.save(src, path)
	if err == OK:
		_dirty = false
		_set_status("保存好了：%s（挂在 %s 第 %d 个小关上）" % [file.get_file(), path.get_file(), _section + 1])
	else:
		_set_status("保存失败（错误 %d）" % err)


## 叠轨音乐：按现在的小关和「进度」滑条，马上换成游戏里那个进度会响的那几轨
func _music_apply() -> void:
	_progress.editable = _music_on
	_progress_label.text = ("进度 %d%%" % roundi(_progress.value * 100.0)) if _music_on else "进度（这关没开叠轨音乐）"
	if not _music_on:
		return
	Music.section = _section
	Music.progress = _progress.value
	Music.effective = _progress.value
	Music.apply_now()


# ================================================================ 预览

func _rebuild_preview() -> void:
	for c in _viewport.get_children():
		c.queue_free()
	_scene = null
	_style = null
	_cache.clear()
	_live.clear()
	if _show_level.button_pressed and _def.scene:
		var inst := _def.scene.instantiate()
		_scene = inst as SpinSection
		if _scene:
			_scene.allow_note_style = false  # 表现方式由编辑器自己叠（下面），关卡别再叠一层
			_scene.setup(_def, _live)
			_viewport.add_child(_scene)
			_scene.enter()
		else:
			inst.queue_free()
	if _scene == null:
		var bg := ColorRect.new()  # 不显示关卡画面时垫一层深色底
		bg.color = Color(0.06, 0.04, 0.1)
		bg.size = Vector2(_viewport.size)
		_viewport.add_child(bg)
	if _show_style.button_pressed:
		var layer := CanvasLayer.new()
		layer.layer = 5
		_viewport.add_child(layer)
		_style = NoteStyle.create(pattern.style)
		_style.pattern = pattern
		layer.add_child(_style)


func _process(_delta: float) -> void:
	if pattern == null:
		return
	if _playing or _playtest:
		_beat = Conductor.song_beat
	else:
		# 暂停时手动把时钟拨到播放头，关卡画面也跟着停在这一拍
		Conductor.song_beat = _beat
		Conductor.song_time = _beat * Conductor.sec_per_beat()
	if not _playtest:
		_update_live()
	if _style:
		_style.update_notes(_beat, _live)
	var L := maxf(pattern.length_beats, 0.001)
	_timeline.playhead = fposmod(_beat, L)
	_timeline.queue_redraw()
	_play_btn.text = "Pause" if _playing else "Play"


## 编辑时的音符：把谱子按循环铺到播放头前后一段（试玩时音符由 Judge 生成）
func _update_live() -> void:
	var L := pattern.length_beats
	if L <= 0.0:
		_live.clear()
		return
	var max_lead := pattern.default_lead
	for d in pattern.notes:
		max_lead = maxf(max_lead, float(d.get("lead", 0.0)))
	var from := _beat - 2.0
	var to := _beat + max_lead + 1.0
	var parsed := pattern.parse_notes()
	var out: Array[NoteData] = []
	for k in range(floori(from / L), floori(to / L) + 1):
		for i in parsed.size():
			var d: Dictionary = parsed[i]
			var b: float = k * L + float(d.beat)
			if b < from or b > to:
				continue
			var key := k * 100000 + i
			var n: NoteData = _cache.get(key)
			if n == null:
				n = NoteData.new()
				_cache[key] = n
			n.beat = b
			n.sound = int(d.sound)
			n.apply_props(d)
			if n.beat > _beat + 0.02:
				n.judged = false  # 往回拖了：重新显示
				n.result = NoteData.Result.NONE
			elif not n.judged and _playing:
				_hit_in_preview(n)
			out.append(n)
	_live.clear()
	_live.append_array(out)


## 播放到了一个音符：自动演奏就当作打中（出命中特效、响鼓）；不自动演奏就安静地让它过去
func _hit_in_preview(n: NoteData) -> void:
	n.judged = true
	if not _auto.button_pressed:
		n.result = NoteData.Result.MISS
		return
	n.result = NoteData.Result.PERFECT
	_drums.play(n.sound)
	if _style:
		_style.judged(n, NoteData.Result.PERFECT)
	if _scene:
		_scene.notify_judged(n, NoteData.Result.PERFECT)


func _toggle_play() -> void:
	if _playtest:
		return
	_playing = not _playing
	if _playing:
		Conductor.play(_beat)
	else:
		Conductor.stop()


func _seek(local_beat: float) -> void:
	var L := pattern.length_beats
	_beat = floorf(_beat / L) * L + local_beat if L > 0.0 else local_beat
	if _playing:
		Conductor.play(_beat)


# ================================================================ 试玩（正式判定）

func _toggle_playtest() -> void:
	if _playtest:
		_stop_playtest()
		return
	_playing = false
	_playtest = true
	_test_btn.text = "Stop test"
	var L := pattern.length_beats
	var start := floorf(_beat / L) * L if L > 0.0 else 0.0
	_judge = Judge.new()
	add_child(_judge)
	_judge.note_judged.connect(_on_test_judged)
	_judge.pressed.connect(_drums.play)
	_judge.add_child(ChartInput.attach(_judge, null, func() -> Node: return _scene))  # 长按 / 连击
	_judge.reset()
	_def.start_beat = start
	var test_notes := _judge.begin_section(0, _def, _song.beats_per_bar, start, start)
	if _scene:
		_scene.setup(_def, test_notes)
	_live = test_notes
	Conductor.play(start - _song.beats_per_bar)  # 先空一小节
	_set_status("试玩中：空格 / Z X J K 打，T 或 Esc 结束")


func _stop_playtest() -> void:
	if not _playtest:
		return
	_playtest = false
	_test_btn.text = "Test"
	Conductor.stop()
	var counts := _judge.counts
	var msg := "试玩结束：PERFECT %d  GREAT %d  GOOD %d  MISS %d  平均偏差 %+.0f ms" % [
		counts[NoteData.Result.PERFECT], counts[NoteData.Result.GREAT], counts[NoteData.Result.GOOD],
		counts[NoteData.Result.MISS], _judge.mean_offset() * 1000.0]
	_judge.queue_free()
	_judge = null
	_live = []
	_def.start_beat = 0.0
	_rebuild_preview()
	_set_status(msg)


func _on_test_judged(note: NoteData, result: int, _diff: float) -> void:
	if _style:
		_style.judged(note, result)
	if _scene:
		_scene.notify_judged(note, result)


# ================================================================ 编辑

func _snapshot() -> Dictionary:
	return {"notes": pattern.notes.duplicate(true), "length": pattern.length_beats, "lanes": pattern.lanes,
			"lead": pattern.default_lead, "rev": pattern.beats_per_rev, "style": pattern.style, "use": pattern.use_style,
		"guides": pattern.beat_guides, "every": pattern.guide_every}


func _restore(s: Dictionary) -> void:
	pattern.notes.assign(s.notes.duplicate(true))
	pattern.length_beats = s.length
	pattern.lanes = s.lanes
	pattern.default_lead = s.lead
	pattern.beats_per_rev = s.rev
	pattern.style = s.style
	pattern.use_style = s.use
	pattern.beat_guides = s.get("guides", true)
	pattern.guide_every = s.get("every", 1.0)
	_timeline.selected.clear()
	_load_pattern_fields()
	_rebuild_preview()
	_on_selection()


## 一次编辑做完了：记一步撤销
func _commit() -> void:
	_undo.append(_state)
	if _undo.size() > 200:
		_undo.pop_front()
	_redo.clear()
	_state = _snapshot()
	_dirty = true
	_cache.clear()


func _undo_step(redo: bool) -> void:
	var from := _redo if redo else _undo
	var to := _undo if redo else _redo
	if from.is_empty():
		return
	to.append(_snapshot())
	_state = from.pop_back()
	_restore(_state)
	_dirty = true


func _on_changed() -> void:
	_cache.clear()
	_on_selection()


func _on_selection() -> void:
	var sel := _timeline.selected
	_sel_label.text = "没选中音符" if sel.is_empty() else ("选中 %d 个音符" % sel.size())
	_loading = true
	for key: String in _fields:
		var ctl: Control = _fields[key]
		ctl.get_parent().modulate.a = 0.4 if sel.is_empty() else 1.0
		if sel.is_empty():
			continue
		var d: Dictionary = sel[0]
		if ctl is SpinBox:
			(ctl as SpinBox).value = float(d.get(key, NoteData.STYLE_DEFAULTS.get(key, 0.0)))
		elif ctl is OptionButton:
			(ctl as OptionButton).select(int(d.get(key, 0)))
	if not sel.is_empty():
		var c: Color = sel[0].get("color", Color(0, 0, 0, 0))
		_mash_check.button_pressed = bool(sel[0].get("mash", false))
		_color_default.button_pressed = c.a <= 0.0
		if c.a > 0.0:
			_color_pick.color = c
	_loading = false
	_timeline.queue_redraw()


## 属性面板改了一个值：选中的音符全改
func _set_prop(key: String, value: Variant) -> void:
	if _loading or _timeline.selected.is_empty():
		return
	for d in _timeline.selected:
		if key == "beat":
			d.beat = clampf(float(value), 0.0, pattern.length_beats - 0.001)
		elif value is float and is_equal_approx(value, float(NoteData.STYLE_DEFAULTS.get(key, INF))) \
				or value is Color and (value as Color).a <= 0.0:
			d.erase(key)  # 和默认值一样就不写进文件
		else:
			d[key] = value
	_commit()
	_on_changed()


func _set_pattern(key: String, value: Variant) -> void:
	if _loading:
		return
	pattern.set(key, value)
	if key == "lanes":
		for d in pattern.notes:
			d.lane = clampi(int(d.get("lane", 0)), 0, pattern.lanes - 1)
	if key in ["style", "lanes"]:
		_rebuild_preview()
	if key == "style":
		_load_pattern_fields()
	if key == "length_beats":
		_def.length = pattern.length_beats
		_timeline.fit()
	_commit()
	_on_changed()


## 选中的音符 连击 开 / 关。开的时候没有长度的先给 2 拍
func _set_mash(on: bool) -> void:
	if _loading or _timeline.selected.is_empty():
		return
	for d in _timeline.selected:
		if on:
			d["mash"] = true
			if float(d.get("length", 0.0)) <= 0.0:
				d["length"] = 2.0
		else:
			d.erase("mash")
	_commit()
	_on_changed()


func _delete_selected() -> void:
	for d in _timeline.selected:
		pattern.notes.erase(d)
	_timeline.selected.clear()
	_commit()
	_on_changed()


func _copy() -> void:
	_clipboard = _timeline.selected.duplicate(true)


## 粘贴：第一个音符对齐到播放头（吸附到网格），其余保持相对位置
func _paste() -> void:
	if _clipboard.is_empty():
		return
	var first := INF
	for d in _clipboard:
		first = minf(first, float(d.beat))
	var at := roundf(_timeline.playhead / _timeline.snap) * _timeline.snap
	_timeline.selected.clear()
	for d in _clipboard:
		var c: Dictionary = d.duplicate(true)
		c.beat = fposmod(at + float(d.beat) - first, pattern.length_beats)
		pattern.notes.append(c)
		_timeline.selected.append(c)
	_commit()
	_on_changed()


func _import_bars() -> void:
	var src := _song.sections[_section]
	var p := ChartPattern.from_bars(src.bars, _song.beats_per_bar)
	pattern.notes.assign(p.notes)
	pattern.length_beats = p.length_beats
	_timeline.selected.clear()
	_load_pattern_fields()
	_timeline.fit()
	_commit()
	_on_changed()
	_set_status("从老鼓谱导入了 %d 个音符" % pattern.notes.size())


func _set_brush(sound: int) -> void:
	_timeline.brush = sound
	for i in _brush_btns.size():
		_brush_btns[i].button_pressed = i == sound


# ================================================================ 按键

func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var cmd := k.ctrl_pressed or k.meta_pressed
	if _playtest:
		if k.keycode == KEY_T or k.keycode == KEY_ESCAPE:
			_stop_playtest()
			get_viewport().set_input_as_handled()
		return  # 试玩时其余按键交给 Judge
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var handled := true
	match k.keycode:
		KEY_SPACE: _toggle_play()
		KEY_T: _toggle_playtest()
		KEY_1: _set_brush(NoteData.Sound.KICK)
		KEY_2: _set_brush(NoteData.Sound.SNARE)
		KEY_3: _set_brush(NoteData.Sound.HAT)
		KEY_M:
			if not _timeline.selected.is_empty():
				_set_mash(not bool(_timeline.selected[0].get("mash", false)))
		KEY_DELETE, KEY_BACKSPACE: _delete_selected()
		KEY_ESCAPE: _back()
		KEY_A when cmd:
			_timeline.selected.assign(pattern.notes)
			_on_selection()
		KEY_C when cmd: _copy()
		KEY_V when cmd: _paste()
		KEY_S when cmd: _save()
		KEY_Z when cmd: _undo_step(k.shift_pressed)
		KEY_Y when cmd: _undo_step(true)
		_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _back() -> void:
	Conductor.stop()
	get_tree().change_scene_to_file(Levels.MENU_SCENE)


# ================================================================ 界面

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	# 顶上一排（放不下自动折到第二行）
	var bar := HFlowContainer.new()
	root.add_child(bar)
	bar.add_child(_level_pick)
	_level_pick.item_selected.connect(func(i: int) -> void: if not _loading: _open(i, 0))
	bar.add_child(_section_pick)
	_section_pick.item_selected.connect(func(i: int) -> void: if not _loading: _open(_level, i))
	for id: String in NoteStyle.STYLES:
		_style_pick.add_item(NoteStyle.STYLE_NAMES[id])
		_style_pick.set_item_metadata(_style_pick.item_count - 1, id)
	_style_pick.item_selected.connect(func(i: int) -> void: _set_pattern("style", _style_pick.get_item_metadata(i)))
	bar.add_child(_style_pick)
	_play_btn.text = "Play"
	_play_btn.pressed.connect(_toggle_play)
	bar.add_child(_play_btn)
	_test_btn.text = "Test"
	_test_btn.tooltip_text = "试玩（T）：用正式的判定打一遍"
	_test_btn.pressed.connect(_toggle_playtest)
	bar.add_child(_test_btn)
	_auto.text = "自动演奏"
	_auto.button_pressed = true
	bar.add_child(_auto)
	_show_level.text = "关卡画面"
	_show_level.button_pressed = true
	_show_level.toggled.connect(func(_on: bool) -> void: _rebuild_preview())
	bar.add_child(_show_level)
	_show_style.text = "表现方式"
	_show_style.button_pressed = true
	_show_style.toggled.connect(func(_on: bool) -> void: _rebuild_preview())
	bar.add_child(_show_style)
	for key: String in SNAPS:
		_snap_pick.add_item(key)
	_snap_pick.select(3)
	_snap_pick.item_selected.connect(func(i: int) -> void:
		_timeline.snap = SNAPS[_snap_pick.get_item_text(i)]
		_timeline.queue_redraw())
	bar.add_child(_snap_pick)
	var names := ["K", "S", "H"]
	for i in 3:
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.modulate = NoteStyle.SOUND_COLORS[i].lightened(0.3)
		b.tooltip_text = ["底鼓 (1)", "军鼓 (2)", "踩镲 (3)"][i]
		b.pressed.connect(_set_brush.bind(i))
		bar.add_child(b)
		_brush_btns.append(b)
	_progress_label.add_theme_font_size_override("font_size", 12)
	bar.add_child(_progress_label)
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.step = 0.01
	_progress.custom_minimum_size = Vector2(140, 0)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.focus_mode = Control.FOCUS_NONE
	_progress.tooltip_text = "积累条进度：听这个小关在不同进度下叠了哪些音轨（只影响试听，不存进谱子）"
	_progress.value_changed.connect(func(_v: float) -> void: _music_apply())
	bar.add_child(_progress)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_save)
	bar.add_child(save)
	var back := Button.new()
	back.text = "Menu"
	back.pressed.connect(_back)
	bar.add_child(back)

	# 中间：预览 + 属性
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.size_flags_stretch_ratio = 2.2
	root.add_child(mid)
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 4.0 / 3.0
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(aspect)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	aspect.add_child(holder)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(960, 720)
	_viewport.handle_input_locally = false
	holder.add_child(_viewport)
	mid.add_child(_build_inspector())

	# 下面：时间轴
	_timeline = Timeline.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.custom_minimum_size = Vector2(0, 150)
	_timeline.changed.connect(_on_changed)
	_timeline.committed.connect(_commit)
	_timeline.selection_changed.connect(_on_selection)
	_timeline.seek.connect(_seek)
	_timeline.resized.connect(_timeline.fit)
	root.add_child(_timeline)
	_status.add_theme_font_size_override("font_size", 12)
	root.add_child(_status)
	_set_brush(0)


func _build_inspector() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(250, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	box.add_child(_heading("这段谱子"))
	_p_spin(box, "length_beats", "循环几拍", 1, 256, 1)
	_p_spin(box, "lanes", "轨道 / 目标数", 1, 8, 1)
	_p_spin(box, "default_lead", "默认提前几拍出现", 0.25, 32, 0.25)
	_p_spin(box, "beats_per_rev", "轨道式：一圈几拍", 1, 64, 0.5)
	var guides := CheckBox.new()
	guides.text = "节拍辅助线"
	guides.tooltip_text = "每拍一条线：要按的拍子是彩色实线（越靠近判定越亮越粗），不用按的拍子是淡虚线"
	guides.toggled.connect(func(on: bool) -> void: _set_pattern("beat_guides", on))
	box.add_child(guides)
	_p_fields["beat_guides"] = guides
	_p_spin(box, "guide_every", "虚线隔几拍一条", 0.25, 4, 0.25)
	var use := CheckBox.new()
	use.text = "游戏里用这个表现方式"
	use.tooltip_text = "勾上：游戏里音符按上面选的表现方式画（叠在关卡画面上），关卡自己画音符的那套关掉"
	use.toggled.connect(func(on: bool) -> void: _set_pattern("use_style", on))
	box.add_child(use)
	_p_fields["use_style"] = use
	var imp := Button.new()
	imp.text = "从老鼓谱导入"
	imp.tooltip_text = "把这个小关原来的鼓谱字符串（bars）转成音符，覆盖现在的谱子"
	imp.pressed.connect(_import_bars)
	box.add_child(imp)

	box.add_child(_heading("选中的音符"))
	_sel_label.add_theme_font_size_override("font_size", 12)
	box.add_child(_sel_label)
	var sound := OptionButton.new()
	for s in ["底鼓 K", "军鼓 S", "踩镲 H"]:
		sound.add_item(s)
	sound.item_selected.connect(func(i: int) -> void: _set_prop("sound", i))
	_row(box, "音色", sound)
	_fields["sound"] = sound
	_spin(box, "beat", "第几拍", 0, 256, 0.125)
	_spin(box, "lane", "轨道", 0, 7, 1)
	_spin(box, "lead", "提前几拍出现（0=默认）", 0, 32, 0.25)
	_spin(box, "length", "长按几拍（0=点按）", 0, 64, 0.25)
	_mash_check.text = "连击（M）：这一段里狂按"
	_mash_check.tooltip_text = "勾上：这个音符变成连击，上面的「长按几拍」就是连击这一段多长，不看节奏只数按了几下"
	_mash_check.toggled.connect(_set_mash)
	box.add_child(_mash_check)
	_spin(box, "size", "大小", 0.1, 5, 0.05)
	_spin(box, "rot", "初始角度（度）", -360, 360, 5)
	_spin(box, "spin", "自转（度 / 拍）", -1440, 1440, 15)
	_spin(box, "glow", "发光", 0, 4, 0.1)
	_spin(box, "pulse", "跟拍闪", 0, 4, 0.1)
	_spin(box, "throb", "跟拍胀缩", 0, 2, 0.05)
	_color_default.text = "默认颜色（按音色）"
	_color_default.toggled.connect(func(on: bool) -> void:
		_set_prop("color", Color(0, 0, 0, 0) if on else _color_pick.color))
	box.add_child(_color_default)
	_color_pick.custom_minimum_size = Vector2(0, 26)
	_color_pick.color = Color(1, 1, 1)
	_color_pick.color_changed.connect(func(c: Color) -> void:
		_color_default.set_pressed_no_signal(false)
		_set_prop("color", c))
	box.add_child(_color_pick)
	var help := Label.new()
	help.text = "时间轴：点空白放音符，拖动移动，右键删，\nAlt+拖 改长按，拖左边小菱形改出现时间。
选中后按 M = 连击（长度同长按）。\n空格 播放  T 试玩  1/2/3 笔刷\nCtrl+Z 撤销  Ctrl+S 保存"
	help.add_theme_font_size_override("font_size", 11)
	help.modulate.a = 0.6
	box.add_child(help)
	return scroll


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	return l


func _row(box: VBoxContainer, label: String, ctl: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 12)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	ctl.custom_minimum_size.x = 90
	row.add_child(ctl)
	box.add_child(row)


func _spin(box: VBoxContainer, key: String, label: String, lo: float, hi: float, step: float) -> void:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value_changed.connect(func(v: float) -> void:
		_set_prop(key, int(v) if key == "lane" else v))
	_row(box, label, s)
	_fields[key] = s


func _p_spin(box: VBoxContainer, key: String, label: String, lo: float, hi: float, step: float) -> void:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value_changed.connect(func(v: float) -> void: _set_pattern(key, int(v) if key == "lanes" else v))
	_row(box, label, s)
	_p_fields[key] = s


func _load_pattern_fields() -> void:
	_loading = true
	for key: String in _p_fields:
		var ctl: Control = _p_fields[key]
		if ctl is SpinBox:
			(ctl as SpinBox).value = float(pattern.get(key))
		elif ctl is CheckBox:
			(ctl as CheckBox).button_pressed = bool(pattern.get(key))
	for i in _style_pick.item_count:
		if _style_pick.get_item_metadata(i) == pattern.style:
			_style_pick.select(i)
	_loading = false


func _set_status(text: String) -> void:
	_status.text = ("● 未保存  " if _dirty else "") + text
