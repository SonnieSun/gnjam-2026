class_name HoldJudge
extends RefCounted
## 一个长按从开头打中到结束的过程（Judge 内部用，关卡只通过 Judge.begin_hold 用它）。
## 时间都是判定时钟的拍数（Conductor.input_beat()）。规则见 JudgeRules 的「长按」一栏：
##   按到尾巴 → 成功；松手时已经按够（宽限 / 比例）→ 成功；
##   没按够就松手 → 先等 hold_regrab_seconds，期间按回去就接着按，没按回去才算失败。

var note: NoteData
var start_beat := 0.0
var end_beat := 0.0
## 结束了（已经回调过）
var done := false

var _rules: JudgeRules
var _on_done := Callable()  # on_done(success: bool, release_beat: float)
var _released_at := -1.0  # 中途松开的那一拍；-1 = 正按着


func _init(hold_note: NoteData, end: float, rules: JudgeRules, on_done: Callable) -> void:
	note = hold_note
	start_beat = hold_note.beat
	end_beat = end
	_rules = rules
	_on_done = on_done


## 正松着手、等按回去
func is_released() -> bool:
	return _released_at >= 0.0


## 松手
func release(beat: float) -> void:
	if done or is_released():
		return
	if _rules.hold_ok(start_beat, end_beat, beat):
		_finish(true, beat)
	else:
		_released_at = beat


## 松手后又按回去
func regrab() -> void:
	_released_at = -1.0


## 每帧调：按到尾巴算成功；松手超过重按时限算失败（失败的那一拍记成松手那一拍）
func update(beat: float) -> void:
	if done:
		return
	if is_released():
		if (beat - _released_at) * Conductor.sec_per_beat() > _rules.hold_regrab_seconds:
			_finish(false, _released_at)
	elif beat >= end_beat:
		_finish(true, end_beat)


func _finish(success: bool, release_beat: float) -> void:
	done = true
	if _on_done.is_valid():
		_on_done.call(success, release_beat)
