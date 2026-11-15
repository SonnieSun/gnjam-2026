extends Control
## 喵谱子工作室（scenes/tools/meow_studio.tscn）：全屏写猫鼓和鬼畜猫旋律的地方。
## 一般从曲库过来：曲库里每个存好的喵谱子旁边有 ✎，点了就在这里打开；"+ 新猫鼓 / + 新旋律"也在曲库里。
## 也可以从游戏的 Tab 面板点 "Meow"，或者在编辑器里打开这个场景按 F6。
##
## 它是独立的：PLAY 默认**只放谱子本身**，按上面的 BPM 自己走，不需要选关、不放曲子；想要拍子就勾"节拍器"。
## 想配着别的音轨听：在"伴奏"里选曲库里的任意一首，下面一排就是它的每条音轨，点亮哪条就加哪条进试听
## （这时速度跟那首曲子走）。
## 下面是谱子编辑（meow_pattern_editor.gd）：格子或卷帘、Save（存了就出现在曲库里）。
## 这里只管写和存；把谱子用进某一关，是游戏里 Tab 面板 Music 页的事（轨道右边的 "+ meow"）。
## 插着 MIDI 键盘的话：按键试听，播放时按键就录进去。
## Space = 播放 / 停，Esc = 回曲库。

const THEME := preload("res://assets/ui/theme.tres")
const PatternEditor := preload("res://scripts/music/meow_pattern_editor.gd")
const Jukebox := preload("res://scripts/music/jukebox.gd")
const CLICK := preload("res://assets/audio/sfx/kick.wav")
const JUKEBOX_SCENE := "res://scenes/tools/jukebox.tscn"

var _backing: OptionButton
var _play_btn: Button
var _bpm: SpinBox
var _click: CheckBox
var _lcd: Label
var _stems_row: HBoxContainer
var _juke: VBoxContainer               # 精简模式的曲库：只当伴奏用
var _tab: VBoxContainer
var _click_player: AudioStreamPlayer
var _last_click_beat := -1
var _playing := false


func _ready() -> void:
	Conductor.stop()
	theme = THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.12, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = CLICK
	_click_player.volume_db = -10.0
	add_child(_click_player)
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
	_play_btn = _button(top, "PLAY", _toggle_play, "Hot")
	_bpm = SpinBox.new()
	_bpm.min_value = 60
	_bpm.max_value = 220
	_bpm.step = 1
	_bpm.value = 160
	_bpm.suffix = "BPM"
	_bpm.custom_minimum_size.x = 130       # 不然三位数会被裁掉一位
	_bpm.tooltip_text = "只听谱子时的速度（选了伴奏就跟伴奏的速度走）"
	_bpm.value_changed.connect(_on_bpm)
	top.add_child(_bpm)
	_click = CheckBox.new()
	_click.text = "节拍器"
	_click.focus_mode = Control.FOCUS_NONE
	_click.tooltip_text = "每拍响一下，写谱子时好对拍子"
	top.add_child(_click)
	_lcd = Label.new()
	_lcd.theme_type_variation = "Lcd"
	_lcd.custom_minimum_size.x = 130
	top.add_child(_lcd)
	top.add_child(VSeparator.new())
	var bl := Label.new()
	bl.text = "伴奏"
	top.add_child(bl)
	_backing = OptionButton.new()
	_backing.focus_mode = Control.FOCUS_NONE
	_backing.tooltip_text = "不选 = 只听谱子。选曲库里的一首，下面一排开关它的每条音轨"
	_backing.item_selected.connect(_on_backing)
	top.add_child(_backing)
	top.add_child(VSeparator.new())
	_button(top, "回曲库 (Esc)", _go.bind(JUKEBOX_SCENE))
	_button(top, "回游戏", _go.bind(Levels.GAME_SCENE))

	# 伴奏的音轨开关（就是曲库里"这首曲子的音轨"那一排）
	_stems_row = HBoxContainer.new()
	_stems_row.add_theme_constant_override("separation", 10)
	_stems_row.visible = false
	root.add_child(_stems_row)
	var sl := Label.new()
	sl.text = "试听里的音轨"
	sl.theme_type_variation = "Hint"
	_stems_row.add_child(sl)
	_juke = Jukebox.new()
	_juke.compact = true
	_juke.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stems_row.add_child(_juke)
	_backing.add_item("无（只听谱子）")
	for n in _juke.song_names():
		_backing.add_item(n)

	_tab = PatternEditor.new()
	_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tab)
	_tab.set_cell_size(24.0, 13.0)       # 全屏，格子画大一点

	# 曲库让打开的谱子
	var request: String = Music.meow.edit_request
	Music.meow.edit_request = ""
	if request.begins_with("new:"):
		_tab.new_pattern(request.trim_prefix("new:"))
	elif request != "":
		_tab.open(request)


func _button(parent: Control, text: String, action: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## 选的是曲库里第几首（-1 = 不要伴奏）
func _song() -> int:
	return _backing.selected - 1


func _on_backing(_index: int) -> void:
	var was := _playing
	_stop()
	_stems_row.visible = _song() >= 0
	_bpm.editable = _song() < 0
	if _song() >= 0:
		_juke.play_song(_song(), false)             # 先把音轨开关摆出来，不放
		_bpm.set_value_no_signal(_juke.song_bpm())
	if was:
		_play()


func _on_bpm(v: float) -> void:
	if _playing and _song() < 0:
		Music.meow.start_free(v)
		_last_click_beat = -1


func _toggle_play() -> void:
	if _playing:
		_stop()
	else:
		_play()


func _play() -> void:
	if _song() >= 0:
		_juke._player.play()                        # 伴奏和谱子一起从头
		Music.meow.start_free(_juke.song_bpm())
	else:
		Music.meow.start_free(_bpm.value)           # 只放谱子：喵播放器自己走
	_playing = true
	_last_click_beat = -1
	_play_btn.text = "STOP"


func _stop() -> void:
	Music.meow.stop_free()
	_juke.stop_all()
	_playing = false
	_play_btn.text = "PLAY"


func _go(scene: String) -> void:
	_stop()
	get_tree().change_scene_to_file(scene)


func _process(_delta: float) -> void:
	if not _playing or not Music.meow.running():
		_lcd.text = "STOPPED"
		return
	var b := maxf(Music.meow.now_beat(), 0.0)
	_lcd.text = "BAR %3d  BEAT %d" % [int(b / 4.0) + 1, int(b) % 4 + 1]
	if _click.button_pressed and int(b) != _last_click_beat:
		_click_player.pitch_scale = 1.6 if int(b) % 4 == 0 else 1.2     # 每小节第一拍高一点
		_click_player.play()
	_last_click_beat = int(b)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if k.keycode == KEY_SPACE:
		_toggle_play()
	elif k.keycode == KEY_ESCAPE:
		_go(JUKEBOX_SCENE)
	else:
		return
	get_viewport().set_input_as_handled()
