extends Control
## Music Director：看、听、编辑每个大关的叠轨音乐。打开 scenes/tools/music_director.tscn 按 F6。
##
##   上面：选大关、选小关、PLAY、当前小节、SAVE、EXPORT MIX、“在游戏里用”。
##   中间：每条 track 一行：静音 / 独奏 / 增益，右边是它在积累条进度 0-100% 上的响的区间（可以拖着改，
##         见 range_lane.gd）。粉色虚线是积累条事件分数线，白线是当前进度。
##   下面：进度滑条（= 积累条有多满）；AUTO 让进度随音乐在 N 小节里从 0 走到 100%，模拟玩一遍这个小关；
##         SNAP 开着时进度变化排到下一个小节线生效（和游戏里一样），关掉则马上生效。
##
## 快捷键：Space 播放 / 停止，← → 进度 ±5%，↑ ↓ 换小关，Ctrl+S 保存。
## 配置存在 levels/music/level_<n>.json；游戏里由 Music autoload 读（打开“在游戏里用”之后）。

const THEME := preload("res://assets/ui/theme.tres")
const RangeLane := preload("res://scripts/music/range_lane.gd")
const GROUP_COLORS := {
	"groove": Color("7fd1ff"), "bass": Color("b38cff"), "bed": Color("ffd23f"), "hook": Color("ff5d8f"),
	"peak": Color("ff9f43"), "cat": Color("86ffa3"), "event": Color("ffffff"),
}
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
var _rows: VBoxContainer
var _progress: HSlider
var _progress_lcd: Label
var _auto: CheckBox
var _auto_bars: SpinBox
var _snap: CheckBox
var _lanes := {}       # id -> RangeLane
var _meters := {}      # id -> ColorRect (level bar)
var _dirty := false
var _recording := false
var _rec_end_beat := 0.0
var _rec: AudioEffectRecord


func _ready() -> void:
	theme = THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	Music.track_toggled.connect(func(_id, _on): _refresh_lanes())
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

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)
	var title := Label.new()
	title.text = "MUSIC DIRECTOR"
	title.theme_type_variation = "Header"
	top.add_child(title)
	_level_pick = OptionButton.new()
	for l in Levels.LIST:
		_level_pick.add_item(l.title)
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
	_use_in_game.tooltip_text = "打开后，游戏里这一大关用这套叠轨音乐（并改成它的 BPM）"
	_use_in_game.toggled.connect(_on_use_in_game)
	top.add_child(_use_in_game)
	_button(top, "SAVE", _save, "Big")
	_button(top, "EXPORT MIX", _export_mix, "Big")

	_status = Label.new()
	_status.theme_type_variation = "Hint"
	root.add_child(_status)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	root.add_child(header)
	var hl := Label.new()
	hl.text = "TRACK"
	hl.custom_minimum_size.x = 430
	hl.theme_type_variation = "Hint"
	header.add_child(hl)
	var ruler := HBoxContainer.new()
	ruler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(ruler)
	for k in 5:
		var s := Label.new()
		s.text = "%d%%" % (k * 25)
		s.theme_type_variation = "Hint"
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.horizontal_alignment = [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT][k]
		ruler.add_child(s)
	var pad := Control.new()
	pad.custom_minimum_size.x = 30
	header.add_child(pad)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
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
	_snap.tooltip_text = "进度变化排到下一个小节线才生效（游戏里就是这样）"
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
	_button(bottom, "+ TRACK", _add_track_dialog)
	_button(bottom, "COPY PREV SECTION", _copy_prev_section)


func _button(parent: Control, text: String, on_press: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _rebuild_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()
	_lanes.clear()
	_meters.clear()
	var rules := _rules()
	for t in data.get("tracks", []):
		var id: String = t.id
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_rows.add_child(row)
		var col: Color = GROUP_COLORS.get(t.get("group", ""), Color.GRAY)
		var sw := ColorRect.new()
		sw.color = col
		sw.custom_minimum_size = Vector2(8, 26)
		row.add_child(sw)
		var lbl := Label.new()
		lbl.text = id
		lbl.tooltip_text = t.file
		lbl.custom_minimum_size.x = 150
		lbl.clip_text = true
		row.add_child(lbl)
		var grp := Label.new()
		grp.text = t.get("group", "")
		grp.theme_type_variation = "Hint"
		grp.custom_minimum_size.x = 56
		row.add_child(grp)
		var m := _toggle(row, "M", Music.muted.get(id, false), func(on: bool) -> void:
			Music.muted[id] = on
			Music.apply_now())
		m.tooltip_text = "静音（只在面板里，不存）"
		var s := _toggle(row, "S", Music.soloed.get(id, false), func(on: bool) -> void:
			Music.soloed[id] = on
			Music.apply_now())
		s.tooltip_text = "独奏（只在面板里，不存）"
		var gain := SpinBox.new()
		gain.min_value = -24
		gain.max_value = 6
		gain.step = 0.5
		gain.value = t.get("gain_db", 0.0)
		gain.suffix = "dB"
		gain.custom_minimum_size.x = 92
		gain.value_changed.connect(func(v: float) -> void:
			t["gain_db"] = v
			Music.set_track_gain(id, v)
			_mark_dirty())
		row.add_child(gain)
		var lane := RangeLane.new()
		lane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lane.color = col
		if not rules.has(id):
			rules[id] = []
		lane.ranges = rules[id]
		lane.markers = PackedFloat32Array(section_markers[section] if section < section_markers.size() else DEFAULT_MARKERS)
		lane.changed.connect(_on_lane_changed)
		row.add_child(lane)
		_lanes[id] = lane
		var meter := ColorRect.new()
		meter.custom_minimum_size = Vector2(10, 26)
		meter.color = Color(0.2, 0.2, 0.2)
		row.add_child(meter)
		_meters[id] = meter
		var del := Button.new()
		del.text = "×"
		del.focus_mode = Control.FOCUS_NONE
		del.tooltip_text = "从这一大关拿掉这条 track"
		del.pressed.connect(func(): _remove_track(id))
		row.add_child(del)
	_refresh_lanes()


func _toggle(parent: Control, text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.x = 30
	b.toggled.connect(cb)
	parent.add_child(b)
	return b


func _refresh_lanes() -> void:
	var p := _progress.value / 100.0 if _progress else 0.0
	for id in _lanes:
		var lane = _lanes[id]
		lane.playhead = p
		lane.sounding = Music.rule_on(section, id, Music.progress)
		lane.queue_redraw()


# ---------------------------------------------------------------- data

func _load_level(index: int) -> void:
	if Conductor.playing:
		_stop()
	level = index
	_level_pick.selected = index
	data = Music.read(Music.path_for(index))
	if data.is_empty():
		data = {"title": Levels.LIST[index].title, "bpm": 160, "use_in_game": false, "quantize_beats": 4, "tracks": [], "sections": []}
	# section names and gauge lines come from the level's own chart
	section_titles = PackedStringArray()
	section_markers = []
	var chart: SongChart = load(Levels.LIST[index].chart).build()
	for def in chart.sections:
		section_titles.append(def.title)
		var marks := DEFAULT_MARKERS.duplicate()
		if def.use_gauge_events and def.gauge_max > 0:
			marks = []
			for v in def.gauge_events:
				marks.append(float(v) / def.gauge_max)
		section_markers.append(marks)
	var secs: Array = data.get("sections", [])
	while secs.size() < section_titles.size():
		secs.append({"title": section_titles[secs.size()], "rules": {}})
	data["sections"] = secs
	_section_pick.clear()
	for i in section_titles.size():
		_section_pick.add_item("%d  %s" % [i + 1, section_titles[i]])
	_use_in_game.set_pressed_no_signal(data.get("use_in_game", false))
	Music.muted.clear()
	Music.soloed.clear()
	Music.build(data)
	_dirty = false
	_select_section(0)
	_set_status("%s：%d 条 track，%d 个小关。%s" % [data.title, data.tracks.size(), section_titles.size(), Music.path_for(index)])


func _select_section(i: int) -> void:
	section = clampi(i, 0, maxi(section_titles.size() - 1, 0))
	_section_pick.selected = section
	Music.section = section
	_rebuild_rows()
	_on_progress(_progress.value)


func _rules() -> Dictionary:
	var secs: Array = data.get("sections", [])
	if section >= secs.size():
		return {}
	if not secs[section].has("rules"):
		secs[section]["rules"] = {}
	return secs[section]["rules"]


func _on_use_in_game(on: bool) -> void:
	data["use_in_game"] = on
	_mark_dirty()


func _on_lane_changed() -> void:
	# empty range lists stay until SAVE drops them (the lanes hold these very arrays)
	_mark_dirty()
	if Conductor.playing and _snap.button_pressed:
		Music.set_progress(_progress.value / 100.0)
	else:
		Music.apply_now()
	_refresh_lanes()


func _mark_dirty() -> void:
	_dirty = true
	_set_status("有改动，记得 SAVE（Ctrl+S）")


func _save() -> void:
	var out := data.duplicate(true)
	for sec in out.sections:
		var rules: Dictionary = sec.get("rules", {})
		for id in rules.keys():
			if rules[id].is_empty():
				rules.erase(id)
			else:
				for r in rules[id]:
					r[0] = snappedf(r[0], 0.001)
					r[1] = snappedf(r[1], 0.001)
	var err := Music.write(Music.path_for(level), out)
	_dirty = err != OK
	_set_status("已保存 %s" % Music.path_for(level) if err == OK else "保存失败：%s" % error_string(err))


func _add_track_dialog() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.current_dir = "res://assets/audio/music"
	fd.filters = PackedStringArray(["*.wav ; WAV loops"])
	fd.files_selected.connect(func(paths: PackedStringArray):
		for p in paths:
			_add_track(p)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.6)


func _add_track(path: String) -> void:
	var tracks: Array = data.tracks
	if tracks.size() >= AudioStreamSynchronized.MAX_STREAMS:
		_set_status("一大关最多 %d 条 track" % AudioStreamSynchronized.MAX_STREAMS)
		return
	var id := path.get_file().get_basename()
	for t in tracks:
		if t.id == id:
			_set_status("已经有 %s 了" % id)
			return
	tracks.append({"id": id, "file": path, "group": _guess_group(id), "gain_db": 0.0})
	_after_tracks_changed()


func _guess_group(id: String) -> String:
	for key in [["L1", "groove"], ["groove", "groove"], ["L2", "bass"], ["bass", "bass"], ["L0", "bed"], ["keys", "bed"],
			["stabs", "bed"], ["L3", "hook"], ["lead", "hook"], ["hook", "hook"], ["L4", "peak"], ["peak", "peak"],
			["drums", "cat"], ["X_", "event"]]:
		if key[0] in id:
			return key[1]
	return "bed"


func _remove_track(id: String) -> void:
	var tracks: Array = data.tracks
	for i in tracks.size():
		if tracks[i].id == id:
			tracks.remove_at(i)
			break
	for sec in data.sections:
		sec.get("rules", {}).erase(id)
	_after_tracks_changed()


func _after_tracks_changed() -> void:
	var was_playing := Conductor.playing
	if was_playing:
		_stop()
	Music.build(data)
	Music.section = section
	_rebuild_rows()
	_mark_dirty()
	if was_playing:
		_play()


func _copy_prev_section() -> void:
	if section == 0:
		return
	var src: Dictionary = data.sections[section - 1].get("rules", {})
	data.sections[section]["rules"] = src.duplicate(true)
	_rebuild_rows()
	_mark_dirty()
	Music.apply_now()


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
	Conductor.looping = true
	Conductor.load_chart(chart)
	Music.section = section
	Music.progress = _progress.value / 100.0
	Music.apply_now()
	Conductor.play(0.0)
	_play_btn.text = "STOP"


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
	_refresh_lanes()


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
	for id in _meters:
		var i := Music.track_ids.find(id)
		var lv := Music.level_of(i)
		_meters[id].color = Color(0.2, 0.2, 0.2).lerp(Color("86ffa3"), lv)
	if _recording and b >= _rec_end_beat:
		_finish_export()


# ---------------------------------------------------------------- export mix

## Records the master bus for one AUTO sweep (the section built up from 0 to 100%) into
## res://levels/music/exports/<level>_<section>.wav, so a build-up can be shared and listened to.
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
	var bpb := 4.0
	var start := (floorf(Conductor.song_beat / (_auto_bars.value * bpb)) + 1.0) * _auto_bars.value * bpb
	# start recording from now; the file is trimmed to the sweep when it is saved
	_rec.set_recording_active(true)
	_recording = true
	_rec_end_beat = start + _auto_bars.value * bpb
	_rec.set_meta("start_beat", start)
	_rec.set_meta("begin_beat", Conductor.song_beat)
	_set_status("录制中：从第 %d 小节开始录一遍 %d 小节的 AUTO…" % [int(start / 4) + 1, int(_auto_bars.value)])


func _finish_export() -> void:
	_recording = false
	_rec.set_recording_active(false)
	var wav := _rec.get_recording()
	if wav == null:
		_set_status("录制失败")
		return
	var spb := 60.0 / Music.bpm()
	var skip_sec: float = (_rec.get_meta("start_beat") - _rec.get_meta("begin_beat")) * spb
	var frames_skip := maxi(0, int(skip_sec * wav.mix_rate))
	var bytes := 4 if wav.stereo else 2
	var d := wav.data
	if frames_skip * bytes < d.size():
		wav.data = d.slice(frames_skip * bytes)
	DirAccess.make_dir_recursive_absolute("res://levels/music/exports")
	var path := "res://levels/music/exports/level_%d_%s.wav" % [level + 1, section_titles[section].replace(" ", "_")]
	var err := wav.save_to_wav(path)
	_set_status("已导出 %s" % path if err == OK else "导出失败：%s" % error_string(err))


# ---------------------------------------------------------------- input

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
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
