extends Control
## 喵谱子工作室（scenes/tools/meow_studio.tscn）：全屏写猫鼓和鬼畜猫旋律的地方。
## 两个入口：游戏里按 Tab 调出编辑面板，点最上面一排的 "Meow"；或者在编辑器里打开这个场景按 F6。
##
## 最上面一排选伴奏：某个大关的音乐（Gauge 滑条 = 假装积累条打到这么满，伴奏就叠到那一层），
## 或者不带关卡的基础伴奏（160 / 120）。PLAY 之后谱子跟着伴奏循环，边改边听。
## 下面就是谱子编辑（meow_pattern_tab.gd）：新建 / 选谱子、格子或卷帘、Listen、Save、Add to lane。
## Add to lane 会把谱子作为新片段加进所选大关的轨道，并马上写进它的 levels/music/<大关>.json
## （之后在游戏的 Tab 面板 Music 页里按进度切换到它）。选的是基础伴奏时不能加，因为它不属于哪一关。
## Space = 播放 / 停，Esc = 回主菜单。

const THEME := preload("res://assets/ui/theme.tres")
const PatternTab := preload("res://scripts/music/meow_pattern_tab.gd")
const S1 := "res://assets/audio/music/scene1/"
const S120 := "res://assets/audio/music/scene1_120/s120_"

var _backing: OptionButton
var _play_btn: Button
var _gauge: HSlider
var _lcd: Label
var _tab: VBoxContainer
var _data: Dictionary = {}
var _level := -1                       # 选的是第几个大关（-1 = 基础伴奏）


func _ready() -> void:
	Conductor.stop()
	theme = THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var top := HFlowContainer.new()        # 窗口窄的时候自己换行
	top.add_theme_constant_override("h_separation", 10)
	root.add_child(top)
	var title := Label.new()
	title.text = "MEOW STUDIO"
	title.theme_type_variation = "Header"
	top.add_child(title)
	_backing = OptionButton.new()
	_backing.focus_mode = Control.FOCUS_NONE
	_backing.tooltip_text = "伴奏：某个大关的音乐，或者不带关卡的基础伴奏"
	for i in Levels.count():
		var chart := load(Levels.paths()[i]) as SongChart
		var t: String = chart.title if chart and chart.title != "" else "LEVEL %d" % (i + 1)
		var note := "" if Music.enabled_for(i) else "（没有叠轨音乐）"
		_backing.add_item("%d  %s%s" % [i + 1, t, note])
		_backing.set_item_metadata(_backing.item_count - 1, i)
		_backing.set_item_disabled(_backing.item_count - 1, not Music.enabled_for(i))
	_backing.add_item("基础伴奏 160")
	_backing.set_item_metadata(_backing.item_count - 1, -160)
	_backing.add_item("基础伴奏 120")
	_backing.set_item_metadata(_backing.item_count - 1, -120)
	_backing.item_selected.connect(_on_backing)
	top.add_child(_backing)
	_play_btn = _button(top, "PLAY", _toggle_play, "Hot")
	_lcd = Label.new()
	_lcd.theme_type_variation = "Lcd"
	_lcd.custom_minimum_size.x = 190
	top.add_child(_lcd)
	var gl := Label.new()
	gl.text = "Gauge"
	top.add_child(gl)
	_gauge = HSlider.new()
	_gauge.max_value = 100
	_gauge.value = 60
	_gauge.step = 1
	_gauge.custom_minimum_size.x = 150
	_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gauge.focus_mode = Control.FOCUS_NONE
	_gauge.tooltip_text = "假装积累条打到这么满：伴奏叠到这一层"
	_gauge.value_changed.connect(_on_gauge)
	top.add_child(_gauge)
	_button(top, "回游戏", _back_to_game)
	_button(top, "回主菜单 (Esc)", _back_to_menu)

	_tab = PatternTab.new()
	_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab.has_lanes = _has_lanes
	_tab.added_to_lane.connect(_on_added)
	root.add_child(_tab)
	_tab.set_cell_size(24.0, 13.0)       # 全屏，格子画大一点

	# 从游戏里过来的：默认选刚才那一关；它没有叠轨音乐就用基础伴奏
	var start := _backing.item_count - 2
	if Levels.selected < Levels.count() and Music.enabled_for(Levels.selected):
		start = Levels.selected
	_backing.selected = start
	_on_backing(start)


func _button(parent: Control, text: String, action: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## 不带关卡的基础伴奏：鼓、低音、和声一直响，积累条过半加旋律
func _basic(bpm: int) -> Dictionary:
	var files := {
		"groove": S1 + "skeleton/s1_L1_groove_4b.wav", "bass": S1 + "skeleton/s1_L2_bass_4b.wav",
		"keys": S1 + "style_futurebass/s1_fb_L0_keys_4b.wav", "hook": S1 + "style_futurebass/s1_fb_L3_hook_4b.wav"}
	if bpm == 120:
		files = {"groove": S120 + "L1_groove_4b.wav", "bass": S120 + "L2_bass_4b.wav",
			"keys": S120 + "fb_L0_keys_4b.wav", "hook": S120 + "fb_L3_hook_4b.wav"}
	var lanes: Array = []
	var cues := {}
	for id: String in files:
		lanes.append({"id": id, "name": id, "gain_db": 0.0, "clips": [{"id": id, "file": files[id]}]})
		cues[id] = [[0.5 if id == "hook" else 0.0, id]]
	return {"title": "basic", "bpm": bpm, "use_in_game": false, "quantize_beats": 4, "lanes": lanes,
		"sections": [{"title": "basic", "cues": cues}]}


func _on_backing(index: int) -> void:
	var was_playing := Conductor.playing
	_stop()
	var meta: int = _backing.get_item_metadata(index)
	if meta >= 0:
		_level = meta
		Levels.selected = meta
		_data = Music.read(Music.path_for(meta))
	else:
		_level = -1
		_data = _basic(-meta)
	Music.build(_data)                    # 轨道列表马上可用（Add to lane 的下拉框）
	_tab.refresh_lanes()
	if was_playing:
		_play()


func _has_lanes() -> bool:
	return _level >= 0


## 谱子加进了轨道：马上写进这一关的音乐配置
func _on_added(_lane: String, _clip: String) -> void:
	if _level < 0:
		return
	var err := Music.write(Music.path_for(_level), Music.data)
	_tab.say("Added and saved to %s: switch to it on the Music page of the game's Tab panel" % Music.path_for(_level).get_file()
			if err == OK else "Could not write the level's music file: " + error_string(err))


func _toggle_play() -> void:
	if Conductor.playing:
		_stop()
	else:
		_play()


func _play() -> void:
	var chart := SongChart.new()
	chart.stream = Music.build(_data)
	chart.bpm = Music.bpm()
	chart.beats_per_bar = 4
	# 一个很长的空小关：伴奏一直循环，不出音符
	var hold := SectionDef.new()
	var empty := PackedStringArray()
	empty.resize(512)
	hold.bars = empty
	chart.sections.append(hold)
	chart.recompute()
	if "looping" in Conductor:
		Conductor.looping = true
	Conductor.load_chart(chart)
	Music.section = 0
	Music.progress = _gauge.value / 100.0
	Music.apply_now()
	Conductor.play(0.0)
	_play_btn.text = "STOP"
	_tab.refresh_listen()


func _stop() -> void:
	Conductor.stop()
	_play_btn.text = "PLAY"


func _on_gauge(v: float) -> void:
	if Conductor.playing:
		Music.set_progress(v / 100.0)


func _back_to_game() -> void:
	_stop()
	get_tree().change_scene_to_file(Levels.GAME_SCENE)


func _back_to_menu() -> void:
	_stop()
	get_tree().change_scene_to_file(Levels.MENU_SCENE)


func _process(_delta: float) -> void:
	if Conductor.playing:
		var b := maxf(Conductor.song_beat, 0.0)
		_lcd.text = "%d BPM  BAR %3d  BEAT %d" % [int(Music.bpm()), int(b / 4.0) + 1, int(b) % 4 + 1]
	else:
		_lcd.text = "%d BPM  STOPPED" % int(Music.bpm())


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if k.keycode == KEY_SPACE:
		_toggle_play()
	elif k.keycode == KEY_ESCAPE:
		_back_to_menu()
	else:
		return
	get_viewport().set_input_as_handled()
