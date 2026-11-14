extends Control
## Music Director：给每个大关配叠轨音乐。打开 scenes/tools/music_director.tscn 按 F6。
##
## 一关的音乐是几条轨道（节奏、低音、和声、旋律……），每条轨道里放几段 loop，同一时刻只响一段。
##   · 点一段 = 从当前进度起，这条轨道换成它；再点正在响的那段 = 从这里起静音。
##   · 下面的 PROGRESS 就是积累条有多满：先拖到某个进度再点，就是"进度到这里时换成它"。
##   · 每条轨道下的细条是切换点：拖动改位置，右键删掉。
##   · + 片段 往轨道里放 WAV，+ 轨道 加一条新轨道，右键一段 = 从轨道里拿掉。
## 快捷键：Space 播放 / 停止，← → 进度 ±5%，↑ ↓ 换小关，Ctrl+S 保存。
## 配置存在 levels/music/<大关文件名>.json（如 level_1.json）；游戏里由 Music autoload 读（打开 USE IN GAME 之后）。

const THEME := preload("res://assets/ui/theme.tres")
const CueStrip := preload("res://scripts/music/cue_strip.gd")
const Jukebox := preload("res://scripts/music/jukebox.gd")
const PALETTE := [Color("ffd23f"), Color("ff5d8f"), Color("7fd1ff"), Color("86ffa3"), Color("b38cff"),
	Color("ff9f43"), Color("f8f4e3"), Color("5ce1e6")]
const DEFAULT_MARKERS := [20.0 / 60.0, 40.0 / 60.0]

var level := 0
var section := 0
var data: Dictionary = {}
var section_titles: PackedStringArray = []
var section_markers: Array = []

var _level_pick: OptionButton
var _section_pick: OptionButton
var _play_btn: Button
var _lcd: Label
var _status: Label
var _use_in_game: CheckBox
var _lanes_box: VBoxContainer
var _progress: HSlider
var _progress_lcd: Label
var _auto: CheckBox
var _auto_bars: SpinBox
var _snap: CheckBox
var _chips := {}       # lane id -> {clip id: Button}
var _strips := {}      # lane id -> CueStrip
var _recording := false
var _edit_page: VBoxContainer
var _jukebox: VBoxContainer
var _tab_buttons: Array[Button] = []
var _rec_end_beat := 0.0
var _rec: AudioEffectRecord


func _ready() -> void:
	theme = THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_show_page(0)
	Music.lane_switched.connect(func(_lane, _clip): _refresh())
	_load_level(0)


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.12, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	# two pages: 编辑 (this level's tracks and cues) and 曲库 (just listen to everything we have)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	root.add_child(tabs)
	var title := Label.new()
	title.text = "MUSIC DIRECTOR"
	title.theme_type_variation = "Header"
	tabs.add_child(title)
	_tab_buttons = [_button(tabs, "编辑", _show_page.bind(0), "Big"), _button(tabs, "曲库", _show_page.bind(1), "Big")]
	_edit_page = VBoxContainer.new()
	_edit_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit_page.add_theme_constant_override("separation", 10)
	root.add_child(_edit_page)
	_jukebox = Jukebox.new()
	_jukebox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_jukebox)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_edit_page.add_child(top)
	_level_pick = OptionButton.new()
	for i in Levels.count():
		var t: String = _level_chart(i).title
		_level_pick.add_item(t if t != "" else "LEVEL %d" % (i + 1))
	_level_pick.item_selected.connect(_load_level)
	top.add_child(_level_pick)
	_section_pick = OptionButton.new()
	_section_pick.custom_minimum_size.x = 160
	_section_pick.item_selected.connect(_select_section)
	top.add_child(_section_pick)
	_play_btn = _button(top, "PLAY", _toggle_play, "Hot")
	_lcd = Label.new()
	_lcd.theme_type_variation = "Lcd"
	_lcd.custom_minimum_size.x = 150
	top.add_child(_lcd)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_use_in_game = CheckBox.new()
	_use_in_game.text = "USE IN GAME"
	_use_in_game.tooltip_text = "打开后，游戏里这一大关用这套音乐（BPM 也改成它的）"
	_use_in_game.toggled.connect(_on_use_in_game)
	top.add_child(_use_in_game)
	_button(top, "SAVE", _save, "Big")
	_button(top, "EXPORT MIX", _export_mix, "Big")

	_status = Label.new()
	_status.theme_type_variation = "Hint"
	_edit_page.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_edit_page.add_child(scroll)
	_lanes_box = VBoxContainer.new()
	_lanes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lanes_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_lanes_box)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	_edit_page.add_child(bottom)
	_button(bottom, "+ 轨道", _add_lane, "Big")
	var pl := Label.new()
	pl.text = "PROGRESS"
	pl.theme_type_variation = "Header"
	bottom.add_child(pl)
	_progress = HSlider.new()
	_progress.min_value = 0
	_progress.max_value = 100
	_progress.step = 1
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.value_changed.connect(_on_progress)
	bottom.add_child(_progress)
	_progress_lcd = Label.new()
	_progress_lcd.theme_type_variation = "Lcd"
	_progress_lcd.custom_minimum_size.x = 70
	bottom.add_child(_progress_lcd)
	_snap = CheckBox.new()
	_snap.text = "SNAP"
	_snap.button_pressed = true
	_snap.tooltip_text = "变化等到下一个小节线才生效（游戏里就是这样）"
	bottom.add_child(_snap)
	_auto = CheckBox.new()
	_auto.text = "AUTO"
	_auto.tooltip_text = "进度随音乐在 N 小节里从 0 走到 100%，模拟玩一遍这个小关"
	bottom.add_child(_auto)
	_auto_bars = SpinBox.new()
	_auto_bars.min_value = 4
	_auto_bars.max_value = 64
	_auto_bars.step = 4
	_auto_bars.value = 16
	_auto_bars.suffix = "bars"
	bottom.add_child(_auto_bars)


## 0 = 编辑, 1 = 曲库. Leaving a page stops what it was playing.
func _show_page(page: int) -> void:
	if page == 1 and Conductor.playing:
		_stop()
	if page == 0:
		_jukebox.stop_all()
	_edit_page.visible = page == 0
	_jukebox.visible = page == 1
	for i in _tab_buttons.size():
		_tab_buttons[i].theme_type_variation = "Hot" if i == page else "Big"


func _button(parent: Control, text: String, on_press: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _clip_color(lane: Dictionary, clip_id: String) -> Color:
	var ids := []
	for c in lane.clips:
		ids.append(c.id)
	return PALETTE[maxi(ids.find(clip_id), 0) % PALETTE.size()]


func _rebuild() -> void:
	for c in _lanes_box.get_children():
		c.queue_free()
	_chips.clear()
	_strips.clear()
	var cues := _cues()
	for lane in data.get("lanes", []):
		var lid: String = lane.id
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		_lanes_box.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		v.add_child(row)
		var name_edit := LineEdit.new()
		name_edit.text = lane.get("name", lid)
		name_edit.custom_minimum_size.x = 90
		name_edit.text_changed.connect(func(t: String) -> void:
			lane["name"] = t
			_mark_dirty())
		row.add_child(name_edit)
		var mute := Button.new()
		mute.text = "M"
		mute.toggle_mode = true
		mute.button_pressed = Music.muted.get(lid, false)
		mute.focus_mode = Control.FOCUS_NONE
		mute.tooltip_text = "静音这条轨道（只在面板里，不存）"
		mute.toggled.connect(func(on: bool) -> void:
			Music.muted[lid] = on
			Music.apply_now())
		row.add_child(mute)
		var gain := SpinBox.new()
		gain.min_value = -24
		gain.max_value = 6
		gain.step = 0.5
		gain.value = lane.get("gain_db", 0.0)
		gain.suffix = "dB"
		gain.custom_minimum_size.x = 92
		gain.value_changed.connect(func(db: float) -> void:
			lane["gain_db"] = db
			Music.set_lane_gain(lid, db)
			_mark_dirty())
		row.add_child(gain)
		var chips := HFlowContainer.new()
		chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chips.add_theme_constant_override("h_separation", 6)
		row.add_child(chips)
		_chips[lid] = {}
		for clip in lane.clips:
			var cid: String = clip.id
			var b := Button.new()
			b.text = cid
			b.tooltip_text = clip.file + "\n左键：从当前进度起换成这段（再点一次 = 静音）\n右键：从轨道里拿掉"
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_color_override("font_color", _clip_color(lane, cid))
			b.pressed.connect(func() -> void: _cue(lid, cid))
			b.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
					_remove_clip(lid, cid))
			chips.add_child(b)
			_chips[lid][cid] = b
		var add := Button.new()
		add.text = "+ 片段"
		add.focus_mode = Control.FOCUS_NONE
		add.pressed.connect(func() -> void: _add_clip_dialog(lid))
		chips.add_child(add)
		var del := Button.new()
		del.text = "×"
		del.focus_mode = Control.FOCUS_NONE
		del.tooltip_text = "删掉这条轨道"
		del.pressed.connect(func() -> void: _remove_lane(lid))
		row.add_child(del)
		var strip := CueStrip.new()
		strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not cues.has(lid):
			cues[lid] = []
		strip.cues = cues[lid]
		for clip in lane.clips:
			strip.colors[clip.id] = _clip_color(lane, clip.id)
		strip.markers = PackedFloat32Array(section_markers[section] if section < section_markers.size() else DEFAULT_MARKERS)
		strip.changed.connect(func() -> void:
			_tidy(lid)
			_mark_dirty()
			_reapply())
		v.add_child(strip)
		_strips[lid] = strip
	_refresh()


func _refresh() -> void:
	var p := _progress.value / 100.0
	for lid in _chips:
		var on := Music.playing_clip(lid)
		for cid in _chips[lid]:
			var b: Button = _chips[lid][cid]
			b.theme_type_variation = "Hot" if cid == on else ""
		if _strips.has(lid):
			_strips[lid].playhead = p
			_strips[lid].queue_redraw()


# ---------------------------------------------------------------- data

## 第 index 个大关的谱面（levels/ 里的 .tres），算好每个小关的位置
func _level_chart(index: int) -> SongChart:
	var c := (load(Levels.paths()[index]) as SongChart).duplicate(true) as SongChart
	c.recompute()
	return c


func _load_level(index: int) -> void:
	if Conductor.playing:
		_stop()
	level = index
	_level_pick.selected = index
	data = Music.read(Music.path_for(index))
	if data.is_empty():
		data = {"title": _level_pick.get_item_text(index), "bpm": 160, "use_in_game": false, "quantize_beats": 4,
			"lanes": [{"id": "lane1", "name": "轨道1", "gain_db": 0.0, "clips": []}], "sections": []}
	section_titles = PackedStringArray()
	section_markers = []
	var chart := _level_chart(index)
	for def in chart.sections:
		section_titles.append(def.title)
		var marks := DEFAULT_MARKERS.duplicate()
		# gauge lines (older SectionDefs have no gauge fields: then the defaults)
		if def.get("use_gauge_events") and int(def.get("gauge_max")) > 0:
			marks = []
			for g in def.gauge_events:
				marks.append(float(g) / def.gauge_max)
		section_markers.append(marks)
	var secs: Array = data.get("sections", [])
	while secs.size() < section_titles.size():
		secs.append({"title": section_titles[secs.size()], "cues": {}})
	data["sections"] = secs
	_section_pick.clear()
	for i in section_titles.size():
		_section_pick.add_item("%d  %s" % [i + 1, section_titles[i]])
	_use_in_game.set_pressed_no_signal(data.get("use_in_game", false))
	Music.muted.clear()
	Music.build(data)
	_select_section(0)
	_set_status("%s：%d 条轨道，%d 个小关。点一段 = 从当前进度起换成它。%s" % [data.title, data.lanes.size(), section_titles.size(), Music.path_for(index)])


func _select_section(i: int) -> void:
	section = clampi(i, 0, maxi(section_titles.size() - 1, 0))
	_section_pick.selected = section
	Music.section = section
	_rebuild()
	_on_progress(_progress.value)


func _cues() -> Dictionary:
	var secs: Array = data.get("sections", [])
	if section >= secs.size():
		return {}
	if not secs[section].has("cues"):
		secs[section]["cues"] = {}
	return secs[section]["cues"]


## This section's switch points of one lane (made empty if it has none yet).
func _lane_cues(lid: String) -> Array:
	var c := _cues()
	if not c.has(lid):
		c[lid] = []
	return c[lid]


func _lane(lid: String) -> Dictionary:
	for lane in data.lanes:
		if lane.id == lid:
			return lane
	return {}


## Clicking a clip: from the current progress on, this lane plays it (or goes quiet, if it is
## already the one playing there).
func _cue(lid: String, cid: String) -> void:
	var p := snappedf(_progress.value / 100.0, 0.05)
	var now := Music.clip_at(section, lid, p)
	var list: Array = _lane_cues(lid)
	for i in range(list.size() - 1, -1, -1):
		if absf(list[i][0] - p) < 0.001:
			list.remove_at(i)
	list.append([p, "" if now == cid else cid])
	_tidy(lid)
	_mark_dirty()
	_reapply()
	_strips[lid].queue_redraw()


## Sorted, and no cue that repeats what was already playing.
func _tidy(lid: String) -> void:
	var list: Array = _lane_cues(lid)
	list.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	var last := ""
	for c in list:
		if c[1] != last:
			out.append(c)
			last = c[1]
	list.clear()
	list.append_array(out)


func _reapply() -> void:
	if Conductor.playing and _snap.button_pressed:
		Music.set_progress(_progress.value / 100.0)
	else:
		Music.apply_now()
	_refresh()


func _on_use_in_game(on: bool) -> void:
	data["use_in_game"] = on
	_mark_dirty()


func _mark_dirty() -> void:
	_set_status("有改动，记得 SAVE（Ctrl+S）")


func _save() -> void:
	var out := data.duplicate(true)
	for sec in out.sections:
		var cues: Dictionary = sec.get("cues", {})
		for lid in cues.keys():
			if cues[lid].is_empty():
				cues.erase(lid)
	var err := Music.write(Music.path_for(level), out)
	_set_status("已保存 %s" % Music.path_for(level) if err == OK else "保存失败：%s" % error_string(err))


func _clip_count() -> int:
	var n := 0
	for lane in data.lanes:
		n += lane.clips.size()
	return n


func _add_lane() -> void:
	var n: int = data.lanes.size() + 1
	var lid := "lane%d" % n
	while not _lane(lid).is_empty():
		n += 1
		lid = "lane%d" % n
	data.lanes.append({"id": lid, "name": "轨道%d" % n, "gain_db": 0.0, "clips": []})
	_structure_changed()


func _remove_lane(lid: String) -> void:
	for i in data.lanes.size():
		if data.lanes[i].id == lid:
			data.lanes.remove_at(i)
			break
	for sec in data.sections:
		sec.get("cues", {}).erase(lid)
	_structure_changed()


func _add_clip_dialog(lid: String) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.current_dir = "res://assets/audio/music"
	fd.filters = PackedStringArray(["*.wav ; WAV loops"])
	fd.files_selected.connect(func(paths: PackedStringArray) -> void:
		for path in paths:
			_add_clip(lid, path)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.6)


func _add_clip(lid: String, path: String) -> void:
	if _clip_count() >= AudioStreamSynchronized.MAX_STREAMS:
		_set_status("一大关最多 %d 段" % AudioStreamSynchronized.MAX_STREAMS)
		return
	var lane := _lane(lid)
	var cid := path.get_file().get_basename()
	for c in lane.clips:
		if c.id == cid:
			_set_status("这条轨道里已经有 %s 了" % cid)
			return
	lane.clips.append({"id": cid, "file": path})
	_structure_changed()


func _remove_clip(lid: String, cid: String) -> void:
	var lane := _lane(lid)
	for i in lane.clips.size():
		if lane.clips[i].id == cid:
			lane.clips.remove_at(i)
			break
	for sec in data.sections:
		var list: Array = sec.get("cues", {}).get(lid, [])
		for i in range(list.size() - 1, -1, -1):
			if list[i][1] == cid:
				list.remove_at(i)
	_structure_changed()


func _structure_changed() -> void:
	var was_playing := Conductor.playing
	if was_playing:
		_stop()
	Music.build(data)
	Music.section = section
	Music.progress = _progress.value / 100.0
	Music.apply_now()
	_rebuild()
	_mark_dirty()
	if was_playing:
		_play()


# ---------------------------------------------------------------- playback

func _toggle_play() -> void:
	if Conductor.playing:
		_stop()
	else:
		_play()


func _play() -> void:
	var chart := SongChart.new()
	chart.bpm = Music.bpm()
	chart.beats_per_bar = 4
	chart.stream = Music.build(data)
	# one long empty section, so a Conductor that stops at the end of the chart keeps going
	var hold := SectionDef.new()
	var empty := PackedStringArray()
	empty.resize(512)
	hold.bars = empty
	chart.sections.append(hold)
	chart.recompute()
	if "looping" in Conductor:
		Conductor.looping = true
	Conductor.load_chart(chart)
	Music.section = section
	Music.progress = _progress.value / 100.0
	Music.apply_now()
	Conductor.play(0.0)
	_play_btn.text = "STOP"
	_refresh()


func _stop() -> void:
	Conductor.stop()
	_play_btn.text = "PLAY"
	_recording = false


func _on_progress(v: float) -> void:
	_progress_lcd.text = "%d%%" % roundi(v)
	if Conductor.playing and _snap.button_pressed:
		Music.set_progress(v / 100.0)
	else:
		Music.progress = v / 100.0
		Music.apply_now()
	_refresh()


func _process(_delta: float) -> void:
	if not Conductor.playing:
		_lcd.text = "STOPPED"
		return
	var b := Conductor.song_beat
	_lcd.text = "BAR %3d  BEAT %d" % [int(b / 4.0) + 1, int(b) % 4 + 1]
	if _auto.button_pressed:
		var span: float = _auto_bars.value * 4.0
		var p := fmod(maxf(b, 0.0), span) / span * 100.0
		if absf(p - _progress.value) >= 1.0:
			_progress.value = p
	if _recording and b >= _rec_end_beat:
		_finish_export()


# ---------------------------------------------------------------- export mix

## Records one AUTO sweep (this section building up from 0 to 100%) into
## res://levels/music/exports/level_<n>_<section>.wav, to send around and listen to.
func _export_mix() -> void:
	if _recording:
		return
	_auto.button_pressed = true
	_progress.value = 0
	if not Conductor.playing:
		_play()
	if _rec == null:
		_rec = AudioEffectRecord.new()
		AudioServer.add_bus_effect(0, _rec)
	var span: float = _auto_bars.value * 4.0
	var start := (floorf(Conductor.song_beat / span) + 1.0) * span
	_rec.set_recording_active(true)
	_recording = true
	_rec_end_beat = start + span
	_rec.set_meta("start_beat", start)
	_rec.set_meta("begin_beat", Conductor.song_beat)
	_set_status("录制中：从第 %d 小节起录一遍 %d 小节的 AUTO…" % [int(start / 4) + 1, int(_auto_bars.value)])


func _finish_export() -> void:
	_recording = false
	_rec.set_recording_active(false)
	var wav := _rec.get_recording()
	if wav == null:
		_set_status("录制失败")
		return
	var skip_sec: float = (_rec.get_meta("start_beat") - _rec.get_meta("begin_beat")) * 60.0 / Music.bpm()
	var bytes := 4 if wav.stereo else 2
	var skip := maxi(0, int(skip_sec * wav.mix_rate)) * bytes
	if skip < wav.data.size():
		wav.data = wav.data.slice(skip)
	DirAccess.make_dir_recursive_absolute("res://levels/music/exports")
	var path := "res://levels/music/exports/level_%d_%s.wav" % [level + 1, section_titles[section].replace(" ", "_")]
	var err := wav.save_to_wav(path)
	_set_status("已导出 %s" % path if err == OK else "导出失败：%s" % error_string(err))


# ---------------------------------------------------------------- input

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if _jukebox.visible:                       # 曲库: Space stops, nothing else
		if k.keycode == KEY_SPACE:
			_jukebox.stop_all()
			get_viewport().set_input_as_handled()
		return
	match k.keycode:
		KEY_SPACE:
			_toggle_play()
		KEY_LEFT:
			_progress.value -= 5
		KEY_RIGHT:
			_progress.value += 5
		KEY_UP:
			_select_section(section - 1)
		KEY_DOWN:
			_select_section(section + 1)
		KEY_S:
			if k.ctrl_pressed or k.meta_pressed:
				_save()
		_:
			return
	get_viewport().set_input_as_handled()


func _set_status(text: String) -> void:
	if _status:
		_status.text = text
