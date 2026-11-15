class_name ResultWidget
extends Control
## Static settlement. Denominator uses judged notes because charts loop.
const GRADES := {
	"S": preload("res://assets/ui/result_grades/S.png"),
	"A": preload("res://assets/ui/result_grades/A.png"),
	"B": preload("res://assets/ui/result_grades/B.png"),
	"C": preload("res://assets/ui/result_grades/C.png"),
}
var grade := "C"
var accuracy := 0.0
@onready var grade_art: TextureRect = $Panel/Grade
@onready var percent_label: Label = $Panel/Accuracy
@onready var stats: Label = $Panel/Stats

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
	grade = rank_for(judge.score, total)
	accuracy = clampf(float(judge.score) / float(total * 100), 0.0, 1.0) if total > 0 else 0.0
	grade_art.texture = GRADES[grade]
	percent_label.text = "ACCURACY  %.2f%%" % (accuracy * 100.0)
	var ms: float = judge.mean_offset() * 1000.0
	var lean := ("LATE" if ms > 0 else "EARLY") if absf(ms) >= 1.0 else ""
	stats.text = "SCORE  %d\nMAX COMBO  %d\n\nPERFECT  %d       GREAT  %d\nGOOD  %d              MISS  %d\n\nAVG  %+.0f ms  %s" % [
		judge.score, judge.max_combo,
		judge.counts.get(NoteData.Result.PERFECT,0), judge.counts.get(NoteData.Result.GREAT,0),
		judge.counts.get(NoteData.Result.GOOD,0), judge.counts.get(NoteData.Result.MISS,0), ms, lean]
	visible = true
