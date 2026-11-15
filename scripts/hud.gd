extends CanvasLayer

@onready var score_label: ScoreComboWidget = $ScoreLabel
@onready var combo_label: ScoreComboWidget = $ComboLabel
@onready var judge_label: Label = $JudgeLabel
@onready var judgement_art: JudgementWidget = $JudgementArt
@onready var debug_label: Label = $DebugLabel
@onready var result_label: ResultWidget = $ResultLabel
@onready var milestone_label: ComboMilestoneWidget = $MilestoneLabel
## 积累条（样子在 main.tscn 的 HUD/GaugeBar 里调）
@onready var gauge_bar: ProgressBar = get_node_or_null("GaugeBar")

var _gauge_tween: Tween

var _judge_tween: Tween
var _flash_rect: ColorRect


func _ready() -> void:
	# 全屏闪光用的色块（硬切镜头时白闪一下）
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)
	add_child(_flash_rect)
	move_child(_flash_rect, 0)  # 垫在文字下面


## 全屏闪一下
func flash(color: Color = Color.WHITE, strength: float = 0.8, seconds: float = 0.12) -> void:
	_flash_rect.color = Color(color, strength)
	create_tween().tween_property(_flash_rect, "color:a", 0.0, seconds)


func reset() -> void:
	judge_label.text = ""
	judgement_art.clear()
	result_label.visible = false
	milestone_label.clear()


func set_stats(score: int, combo: int) -> void:
	score_label.set_value(score)
	combo_label.set_value(combo)


func show_judgement(result: int, diff_sec: float) -> void:
	if _judge_tween:
		_judge_tween.kill()
	judge_label.text = ""
	judge_label.visible = false
	judgement_art.show_judgement(result, diff_sec)


## 屏幕右侧弹出 "COMBO XX"，停留一会儿后淡出
func show_combo_milestone(combo: int) -> void:
	milestone_label.show_combo(combo)


## 更新积累条
func set_gauge(value: int, max_value: int) -> void:
	if gauge_bar == null:
		return
	gauge_bar.max_value = max_value
	if _gauge_tween:
		_gauge_tween.kill()
	_gauge_tween = create_tween()
	_gauge_tween.tween_property(gauge_bar, "value", float(value), 0.15)


## 积累条触发事件时闪一下（满条时闪得更明显）
func pulse_gauge(is_full: bool) -> void:
	if gauge_bar == null:
		return
	gauge_bar.pivot_offset = gauge_bar.size / 2.0
	gauge_bar.scale = Vector2.ONE * (1.25 if is_full else 1.12)
	gauge_bar.modulate = Color(2.0, 2.0, 1.4) if is_full else Color(1.5, 1.5, 1.5)
	var t := gauge_bar.create_tween().set_parallel()
	t.tween_property(gauge_bar, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(gauge_bar, "modulate", Color.WHITE, 0.35)


## 在判定文字的位置临时显示一句提示（调试用）
func show_note(text: String) -> void:
	judgement_art.clear()
	judge_label.visible = true
	judge_label.text = text
	judge_label.modulate.a = 1.0
	if _judge_tween:
		_judge_tween.kill()
	_judge_tween = create_tween()
	_judge_tween.tween_property(judge_label, "modulate:a", 0.0, 0.5).set_delay(1.0)


func set_debug(text: String) -> void:
	debug_label.text = text


func show_result(judge: Judge) -> void:
	judgement_art.clear()
	judge_label.visible = false
	milestone_label.clear()
	result_label.show_result(judge)
