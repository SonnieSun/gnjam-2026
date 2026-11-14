class_name LevelKitJudge
extends RefCounted
## Timing judgement against a level's chart, in song seconds. Knows nothing
## about input or drawing: press() when a lane is pressed, expire() every
## frame to turn notes nobody pressed into misses.

const PERFECT_MS := 45.0
const GOOD_MS := 100.0
## Presses further than this from any note are ignored (no penalty).
const REACH_MS := 160.0

var level: LevelData
var combo := 0
var best_combo := 0
var counts := {perfect = 0, good = 0, miss = 0}

var _done := {} # chart index -> true once judged
var _first := 0 # chart index before which everything is judged


func _init(lvl: LevelData) -> void:
	level = lvl


## Starts over from `from_beat`; notes before it count as already done.
func reset(from_beat := -INF) -> void:
	combo = 0
	best_combo = 0
	counts = {perfect = 0, good = 0, miss = 0}
	_done.clear()
	_first = 0
	for i in level.chart.size():
		if float(level.chart[i].b) < from_beat:
			_done[i] = true


## Returns { judge = "perfect"/"good"/"miss"/"none", ms = signed offset
## (negative = early), note = the note or {} }.
func press(lane: int, t: float) -> Dictionary:
	var best := -1
	var best_ms := INF
	for i in range(_first, level.chart.size()):
		var n := level.chart[i]
		var ms := (t - level.beat_to_sec(float(n.b))) * 1000.0
		if ms < -REACH_MS:
			break
		if _done.has(i) or int(n.lane) != lane:
			continue
		if absf(ms) <= REACH_MS and absf(ms) < absf(best_ms):
			best = i
			best_ms = ms
	if best < 0:
		return {judge = "none", ms = 0.0, note = {}}
	_done[best] = true
	var j := "perfect" if absf(best_ms) <= PERFECT_MS else ("good" if absf(best_ms) <= GOOD_MS else "miss")
	_count(j)
	return {judge = j, ms = best_ms, note = level.chart[best]}


## Notes that went by unpressed up to time `t`. Each is counted as a miss.
func expire(t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(_first, level.chart.size()):
		var n := level.chart[i]
		var late := (t - level.beat_to_sec(float(n.b))) * 1000.0
		if late <= GOOD_MS:
			break
		if not _done.has(i):
			_done[i] = true
			_count("miss")
			out.append(n)
	while _first < level.chart.size() and _done.has(_first):
		_first += 1
	return out


## 0..1: perfect = 1, good = 0.5, miss = 0.
func accuracy() -> float:
	var total: int = counts.perfect + counts.good + counts.miss
	return 1.0 if total == 0 else (counts.perfect + counts.good * 0.5) / float(total)


func _count(j: String) -> void:
	counts[j] += 1
	if j == "miss":
		combo = 0
	else:
		combo += 1
		best_combo = maxi(best_combo, combo)
