@tool
extends SpinSection
## 飞碟吸猫关卡：夜里一个飞碟用绿白色光束照着站着的猫。
## 每个音符是一个光圈，从飞碟顺着光束往下套，套到猫身上的那一拍按键；
## 打中猫往上升一格，没打中掉一格，攒满几下猫被吸进飞碟。
## 判定用 Sonnie 的 Judge（不改），这里只把结果转给 AbductionStage 做表现。
## 3D 画面都在 AbductionStage 里，可调参数在 Stage 节点的 Inspector 里。
##
## 编辑器预览里不跑 3D，只显示一行说明；看效果用 F6 运行 abduction_test.tscn。
## 测试用，只在本机 _sandbox 里，不进仓库。

## 光圈提前几拍从飞碟出发
@export var approach_beats := 3.0
## 没打中时整个画面红闪的强度
@export_range(0.0, 1.0) var miss_flash := 0.3
## 调试用：自动在每个音符的时机按键（看演出用，正式玩要关掉）
@export var autoplay := false

var _stage: AbductionStage
var _flash := 0.0
var _auto_next := 0
var _auto_release := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_stage = get_node_or_null("Stage") as AbductionStage
	if _stage == null:
		_stage = AbductionStage.new()
		add_child(_stage)


func hit_position(_note: NoteData = null) -> Vector2:
	return _stage.hit_screen_offset() if _stage else Vector2.ZERO


func hit_radius() -> float:
	return _stage.ring_screen_radius() if _stage else 80.0


func _update_spin(_local_beat: float, _angle: float) -> void:
	center_on_screen()
	if _stage:
		_stage.update(song_beat(), notes, approach_beats)
		if autoplay:
			_autoplay()
	_flash = maxf(_flash - get_process_delta_time() * 2.5, 0.0)
	queue_redraw()


func _on_note_judged(note: NoteData, result: int) -> void:
	if _stage == null:
		return
	_stage.judge(note, result)
	if result == NoteData.Result.MISS:
		_flash = 1.0


## 自动按键：到了音符的拍子就按下，下一帧松开
func _autoplay() -> void:
	if _auto_release:
		_send_hit(false)
		_auto_release = false
	while _auto_next < notes.size() and notes[_auto_next].judged:
		_auto_next += 1
	if _auto_next < notes.size() and beats_until(notes[_auto_next]) <= 0.0:
		_auto_next += 1
		_send_hit(true)
		_auto_release = true


func _send_hit(pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = Judge.HIT_ACTION
	e.pressed = pressed
	Input.parse_input_event(e)


func _draw() -> void:
	if def == null:
		return
	var size := screen_size()
	if Engine.is_editor_hint():
		draw_string(ThemeDB.fallback_font, Vector2(-300.0, 0.0), "飞碟吸猫关卡：3D 画面不在编辑器里预览，F6 运行 abduction_test.tscn",
				HORIZONTAL_ALIGNMENT_CENTER, 600.0, 20)
		return
	if _flash > 0.0:
		draw_rect(Rect2(-size / 2.0, size), Color(1.0, 0.15, 0.2, _flash * miss_flash))
