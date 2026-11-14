extends CanvasLayer

@onready var score_label: Label = $ScoreLabel
@onready var combo_label: Label = $ComboLabel
@onready var judge_label: Label = $JudgeLabel
@onready var debug_label: Label = $DebugLabel
@onready var result_label: Label = $ResultLabel
@onready var milestone_label: Label = $MilestoneLabel

var _judge_tween: Tween
var _milestone_tween: Tween


func reset() -> void:
	judge_label.text = ""
	result_label.visible = false
	if _milestone_tween:
		_milestone_tween.kill()
	milestone_label.modulate.a = 0.0


func set_stats(score: int, combo: int) -> void:
	score_label.text = "SCORE %d" % score
	combo_label.text = "%d COMBO" % combo if combo > 1 else ""


func show_judgement(result: int, diff_sec: float) -> void:
	match result:
		NoteData.Result.PERFECT: judge_label.text = "PERFECT"
		NoteData.Result.GOOD: judge_label.text = "GOOD  %s" % ("LATE" if diff_sec > 0 else "EARLY")
		NoteData.Result.MISS: judge_label.text = "MISS"
	judge_label.modulate.a = 1.0
	if _judge_tween:
		_judge_tween.kill()
	_judge_tween = create_tween()
	_judge_tween.tween_property(judge_label, "modulate:a", 0.0, 0.5).set_delay(0.2)


## 屏幕右侧弹出 "COMBO XX"，停留一会儿后淡出
func show_combo_milestone(combo: int) -> void:
	milestone_label.text = "COMBO %d" % combo
	milestone_label.pivot_offset = milestone_label.size * Vector2(1.0, 0.5)
	milestone_label.scale = Vector2.ONE * 1.6
	milestone_label.modulate.a = 1.0
	if _milestone_tween:
		_milestone_tween.kill()
	_milestone_tween = create_tween()
	_milestone_tween.tween_property(milestone_label, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_milestone_tween.tween_property(milestone_label, "modulate:a", 0.0, 0.4).set_delay(1.0)


func set_debug(text: String) -> void:
	debug_label.text = text


func show_result(judge: Judge) -> void:
	result_label.text = "FULL CIRCLE!\nSCORE %d   MAX COMBO %d\nPERFECT %d   GOOD %d   MISS %d\n\n[R] restart" % [
		judge.score, judge.max_combo,
		judge.counts[NoteData.Result.PERFECT],
		judge.counts[NoteData.Result.GOOD],
		judge.counts[NoteData.Result.MISS],
	]
	result_label.visible = true
