class_name JudgeRules
extends Resource
## 所有判定规则放在一处：点按的时间窗口、长按、连击。
## Judge 节点的 rules 用的是 default_judge_rules.tres，整体调松 / 调严改那一个文件就行，关卡里不再各留一份。

@export_group("点按（秒，按早 / 晚）")
@export var perfect_window := 0.045
@export var great_window := 0.09
## Good 的窗口早晚分开：人更容易按晚，晚的一侧稍宽
@export var good_window_early := 0.12
@export var good_window_late := 0.14

@export_group("长按")
## 离尾巴还差这么多拍以内松手，算按完
@export var hold_release_grace_beats := 0.3
## 按住了长按长度的这个比例，也算按完（和上面取更松的那个）
@export_range(0.0, 1.0, 0.05) var hold_min_ratio := 0.7
## 中途松手后这么多秒内按回去，当作没松过
@export var hold_regrab_seconds := 0.2

@export_group("连击（平均每秒按几下）")
@export var mash_perfect_per_sec := 5.0
@export var mash_great_per_sec := 3.5

@export_group("按够数的连按段（拍地球）")
## 谱面里一串连按音符算一段，要按几下 = 音符个数 × 这个比例（向上取整，至少 1）。调小 = 手慢也能达标
@export_range(0.2, 1.0, 0.05) var mash_count_need_ratio := 0.7
## 段结束时按到要按数的这个比例以上算 Good，不到算 Miss（按够数那一下立刻 Perfect）
@export_range(0.0, 1.0, 0.05) var mash_count_good_ratio := 0.5
## 这一段比第一个音符提前多少拍开始数、最后一个音符之后还数多少拍
@export var mash_zone_lead_beats := 0.25
@export var mash_zone_tail_beats := 0.25
## 下一个要判的音符前留多少拍不数（免得连按的最后一下蹭掉它）
@export var mash_zone_guard_beats := 0.2

@export_group("蓄力重拍（拍地球）")
## 蓄到这个比例以上，重拍才按原判定算；不够只按 Good 算
@export_range(0.0, 1.0) var charge_min_ratio := 0.5


## 点按：按下时离音符差 diff 秒（正 = 晚），返回判定结果；不在窗口里返回 NONE
func tap_result(diff: float) -> int:
	var a := absf(diff)
	if a <= perfect_window:
		return NoteData.Result.PERFECT
	if a <= great_window:
		return NoteData.Result.GREAT
	if diff >= -good_window_early and diff <= good_window_late:
		return NoteData.Result.GOOD
	return NoteData.Result.NONE


## 长按：从 start_beat 按到 end_beat 的长按，在 release_beat 松手算不算按完
func hold_ok(start_beat: float, end_beat: float, release_beat: float) -> bool:
	var by_grace := end_beat - hold_release_grace_beats
	var by_ratio := start_beat + (end_beat - start_beat) * hold_min_ratio
	return release_beat >= minf(by_grace, by_ratio)


## 连击：seconds 秒里按了 presses 下，返回判定结果（一下没按 = MISS）
func mash_result(presses: int, seconds: float) -> int:
	var per_sec := presses / maxf(seconds, 0.001)
	if per_sec >= mash_perfect_per_sec:
		return NoteData.Result.PERFECT
	if per_sec >= mash_great_per_sec:
		return NoteData.Result.GREAT
	if presses >= 1:
		return NoteData.Result.GOOD
	return NoteData.Result.MISS


## 按够数的连按段：谱面里有 note_count 个连按音符，要按几下
func mash_count_need(note_count: int) -> int:
	return maxi(ceili(note_count * mash_count_need_ratio), 1)


## 按够数的连按段：按了 presses 下（要按 need 下）的结果
func mash_count_result(presses: int, need: int) -> int:
	if presses >= need:
		return NoteData.Result.PERFECT
	if presses > 0 and presses >= need * mash_count_good_ratio:
		return NoteData.Result.GOOD
	return NoteData.Result.MISS


## 按够数的连按段从哪拍数到哪拍：first / last = 第一个 / 最后一个连按音符，next = 后面第一个要判的音符
func mash_zone(first: float, last: float, next: float) -> Vector2:
	return Vector2(first - mash_zone_lead_beats,
			maxf(minf(last + mash_zone_tail_beats, next - mash_zone_guard_beats), last))


## 蓄力重拍：蓄了 ratio（0~1）时打出 result，最后算什么
func charged_result(result: int, ratio: float) -> int:
	if result == NoteData.Result.PERFECT and ratio < charge_min_ratio:
		return NoteData.Result.GOOD
	return result
