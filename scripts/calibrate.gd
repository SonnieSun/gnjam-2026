extends Control
## 延迟校准（主菜单按 O 进来）。两步：
##   1. 按键延迟：闭上眼睛只听，跟着节拍器每拍按一下，按够 TAPS_NEEDED 下取中位数。
##      这个值决定判定，最重要。
##   2. 画面提前量：看圆圈闪光和节拍器的声音对不对得上，用 ← / → 调到对齐。
## 结果存在 user://settings.cfg（Conductor.save_offsets）。

const BPM := 80.0  # 慢一点：蓝牙耳机三四百毫秒的延迟也不会被算到隔壁那一拍
const TAPS_NEEDED := 16
## 前几拍不算（让玩家先找到节奏）
const WARMUP_BEATS := 4
const VISUAL_STEP := 0.005

enum Step { AUDIO, VISUAL }

var _step := Step.AUDIO
var _diffs: Array[float] = []
var _old_input := 0.0
var _old_visual := 0.0
var _title: Label
var _info: Label
var _flash := 0.0
var _last_flash_beat := -1


func _ready() -> void:
	Judge.ensure_input()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_title = _label(40, 0.12)
	_info = _label(22, 0.72)

	_old_input = Conductor.input_offset_sec
	_old_visual = Conductor.visual_offset_sec
	var chart := SongChart.new()
	chart.bpm = BPM
	chart.beats_per_bar = 4
	chart.stream = MetronomeStream.build(BPM, 16, 4)  # 4 小节，循环放
	Conductor.load_chart(chart)
	Conductor.play(0.0)
	_start_audio()


func _label(font_size: int, y: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = y
	l.anchor_bottom = y
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(l)
	return l


func _start_audio() -> void:
	_step = Step.AUDIO
	_diffs = []
	_title.text = "STEP 1/2  -  INPUT LATENCY"
	_refresh()


func _start_visual() -> void:
	_step = Step.VISUAL
	_title.text = "STEP 2/2  -  VISUAL OFFSET"
	_refresh()


func _refresh() -> void:
	if _step == Step.AUDIO:
		_info.text = "Close your eyes. Tap SPACE on every click.\n%d / %d taps    current %+.0f ms\n\n[Esc] cancel" % [
			_diffs.size(), TAPS_NEEDED, Conductor.input_offset_sec * 1000.0]
	else:
		_info.text = "Does the flash land on the click?\n[<] / [>] adjust    visual %+.0f ms    input %+.0f ms\n\n[Enter] save    [R] redo step 1    [Esc] cancel" % [
			Conductor.visual_offset_sec * 1000.0, Conductor.input_offset_sec * 1000.0]


func _process(delta: float) -> void:
	# 闪光按画面时间（含画面提前量）走：拍点上亮，之后衰减
	var b := floori(Conductor.song_beat)
	if b != _last_flash_beat and Conductor.song_beat >= 0.0:
		_last_flash_beat = b
		_flash = 1.0
	_flash = maxf(_flash - delta * 6.0, 0.0)
	queue_redraw()


func _draw() -> void:
	if _step != Step.VISUAL:
		return
	var c := size / 2.0
	draw_circle(c, 70.0 + 30.0 * _flash, Color(1.0, 0.9, 0.2, 0.25 + 0.75 * _flash))
	# 绕一圈 = 一小节，指针扫到顶上 = 小节第一拍
	var phase := fposmod(Conductor.song_beat, 4.0) / 4.0
	var tip := c + Vector2.from_angle(phase * TAU - PI / 2.0) * 160.0
	draw_line(c, tip, Color.WHITE, 4.0)
	for i in 4:
		draw_circle(c + Vector2.from_angle(i * TAU / 4.0 - PI / 2.0) * 160.0, 8.0, Color(1, 1, 1, 0.6))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("ui_cancel"):
		Conductor.input_offset_sec = _old_input
		Conductor.visual_offset_sec = _old_visual
		_leave()
	elif _step == Step.AUDIO and event.is_action_pressed(Judge.HIT_ACTION):
		_tap()
	elif _step == Step.VISUAL:
		if event.is_action_pressed("ui_left"):
			Conductor.visual_offset_sec -= VISUAL_STEP
			_refresh()
		elif event.is_action_pressed("ui_right"):
			Conductor.visual_offset_sec += VISUAL_STEP
			_refresh()
		elif event.is_action_pressed("ui_accept"):
			Conductor.save_offsets()
			_leave()
		elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
			_start_audio()


func _tap() -> void:
	# 不扣旧的按键延迟，量的是原始偏差
	var t := Conductor.input_time() + Conductor.input_offset_sec
	var spb := Conductor.sec_per_beat()
	var beat := roundf(t / spb)
	if beat < WARMUP_BEATS:
		return
	var d := t - beat * spb
	if absf(d) > spb * 0.45:
		return  # 离哪一拍都远，当成乱按
	_diffs.append(d)
	if _diffs.size() >= TAPS_NEEDED:
		var sorted := _diffs.duplicate()
		sorted.sort()
		Conductor.input_offset_sec = sorted[sorted.size() / 2]
		_start_visual()
	else:
		_refresh()


func _leave() -> void:
	Conductor.stop()
	get_tree().change_scene_to_file(Levels.MENU_SCENE)
