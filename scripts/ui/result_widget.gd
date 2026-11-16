class_name ResultWidget
extends Control
## Static settlement. Denominator uses judged notes because charts loop.
const GRADES := {
	"S": preload("res://assets/ui/result_grades/S.png"),
	"A": preload("res://assets/ui/result_grades/A.png"),
	"B": preload("res://assets/ui/result_grades/B.png"),
	"C": preload("res://assets/ui/result_grades/C.png"),
}
## Next 被点了（鼠标点按钮，或者键盘打击键按两下：第一下高亮、第二下确认）
signal next_pressed
## 结算出来后多久才收 Next 的按键（免得打最后几个音符时连按的空格直接把结算跳过）
@export var next_input_delay := 0.6
var grade := "C"
var accuracy := 0.0
@onready var grade_art: TextureRect = $Panel/Grade
@onready var percent_label: Label = $Panel/Accuracy
@onready var stats: Label = $Panel/Stats
@onready var next_button: Button = $Panel/Next
var _next_armed := false
var _next_done := false
var _shown_at := 0.0

func _ready() -> void:
	next_button.pressed.connect(_fire_next)

static func rank_for(score: int, judged_count: int) -> String:
	if judged_count <= 0: return "C"
	# Integer comparisons avoid precision changes at exact thresholds.
	if score >= judged_count * 95: return "S"
	if score >= judged_count * 85: return "A"
	if score >= judged_count * 70: return "B"
	return "C"

func show_result(judge) -> void:
	var total := 0
	for result in [NoteData.Result.PERFECT, NoteData.Result.GREAT, NoteData.Result.GOOD, NoteData.Result.MISS]:
		total += int(judge.counts.get(result, 0))
	# Current scoring banks weighted stages; judged-note count is not its maximum.
	var possible: float = float(judge.get("possible")) if judge.get("possible") != null else 0.0
	if possible > 0.0:
		grade = judge.rank()
		accuracy = clampf(float(judge.score) / possible,0.0,1.0)
	else:
		grade = rank_for(judge.score,total)
		accuracy = clampf(float(judge.score) / float(total*100),0.0,1.0) if total > 0 else 0.0
	grade_art.texture = GRADES[grade]
	percent_label.text = "ACCURACY  %.2f%%" % (accuracy * 100.0)
	var ms: float = judge.mean_offset() * 1000.0
	var lean := ("LATE" if ms > 0 else "EARLY") if absf(ms) >= 1.0 else ""
	stats.text = "SCORE  %d\nMAX COMBO  %d\n\nPERFECT  %d       GREAT  %d\nGOOD  %d              MISS  %d\n\nAVG  %+.0f ms  %s" % [
		judge.score, judge.max_combo,
		judge.counts.get(NoteData.Result.PERFECT,0), judge.counts.get(NoteData.Result.GREAT,0),
		judge.counts.get(NoteData.Result.GOOD,0), judge.counts.get(NoteData.Result.MISS,0), ms, lean]
	visible = true
	_next_armed = false
	_next_done = false
	_shown_at = Time.get_ticks_msec() / 1000.0
	next_button.modulate = Color.WHITE
	next_button.scale = Vector2.ONE

func _unhandled_input(event: InputEvent) -> void:
	# 只认键盘上的打击键（空格等）：鼠标点别处不算，鼠标只能点按钮本身
	if not visible or not event is InputEventKey or event.is_echo() or not event.is_action_pressed(Judge.HIT_ACTION):
		return
	if Time.get_ticks_msec() / 1000.0 - _shown_at < next_input_delay:
		return
	get_viewport().set_input_as_handled()
	if _next_armed:
		_fire_next()
		return
	# 第一下：高亮 Next
	_next_armed = true
	next_button.modulate = Color(1.6, 1.4, 1.6)
	next_button.scale = Vector2.ONE * 1.18
	next_button.create_tween().tween_property(next_button, "scale", Vector2.ONE * 1.08, 0.15)

func _fire_next() -> void:
	if _next_done or not visible:
		return
	_next_done = true
	next_pressed.emit()
