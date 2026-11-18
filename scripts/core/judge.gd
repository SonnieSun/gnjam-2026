class_name Judge
extends Node
## 统一的输入 + 判定。段落场景不自己判定，只接收结果做表现。

signal note_judged(note: NoteData, result: int, diff_sec: float)
## 玩家每次按下都会发出（在判定之前），sound 是该发哪种鼓声（NoteData.Sound）
signal pressed(sound: int)
## 按了但附近没有音符
signal empty_hit
signal stats_changed
## 连击数刚好达到 COMBO_MILESTONES 里的某个值
signal combo_milestone(combo: int)

## 判定规则（点按窗口、长按、连击）都在这份资源里，调松 / 调严改它
@export var rules: JudgeRules = preload("res://scripts/core/default_judge_rules.tres")
## 计分（按阶段入账）：每个大关满分 level_max。阶段 = 小关，它的满分 = level_max × 它的占比
## （占比由 main.gd 按各小关的满条值算好传进来）。一个阶段打完时，
## 加上「这个阶段的满分 × 这个阶段的准确率」，分数只在这时跳一次，打的过程中不动。
## 准确率 = 各档权重之和 ÷ 这个阶段判定过的音符数。连击不加分，只在结算里显示最大连击。
## 某一关要留一部分满分给别的玩法（比如飞船关打星球），就把 accuracy_share 设小，剩下的用 add_bonus() 加。
@export_group("计分")
@export var level_max := 1000000
@export var perfect_weight := 1.0
@export var great_weight := 0.8
@export var good_weight := 0.5
## 结算评级：得分占满分的比例到这些线分别是 S / A / B，其余 C
@export_range(0.0, 1.0, 0.01) var rank_s := 0.95
@export_range(0.0, 1.0, 0.01) var rank_a := 0.85
@export_range(0.0, 1.0, 0.01) var rank_b := 0.70
@export_group("")
const HIT_ACTION := "hit"
const COMBO_MILESTONES: Array[int] = [10, 20, 50, 100, 200, 300, 400, 500]

var notes: Array[NoteData] = []
var score := 0
var combo := 0
var max_combo := 0
var counts := {}
## 打中的音符各偏了多少秒（正 = 晚），结算时算平均偏差用
var hit_offsets: Array[float] = []
## 这一关准确率部分占满分的比例（进大关时回到 1；飞船关这类自己设 0.8，剩下的用 add_bonus 加）
var accuracy_share := 1.0
## 到现在为止已经入账的满分（算评级比例用）
var possible := 0.0
## 当前阶段（小关）各档的个数
var stage_counts := {}
## 已废弃（以前的“按关覆盖实时算分”钩子），现在不再使用，留着免得旧代码报错
var score_rule := Callable()
var _stage_weight := 0.0
## 当前阶段预计要按多少下（main.gd 按谱子和满条值估的，和分配满分用的是同一个数）；实时显示分数用
var _stage_expected := 0.0

var _next := 0  # 第一个还没判定的音符

## 音符提前铺多少拍（要比任何关卡“提前显示音符”的拍数都长）
const LOOKAHEAD_BEATS := 16.0
var _pattern: Array[Dictionary] = []  # 当前小关循环的鼓谱
var _pattern_len := 0.0
var _pattern_origin := 0.0
var _pattern_k := 0
var _section_index := 0
var _section_notes: Array[NoteData] = []

# 正在盯的长按（见 begin_hold）：开头那一下照常当普通音符判，按住的部分交给它，用的是同一个判定时钟
var _hold: HoldJudge


func _ready() -> void:
	ensure_input()


## 在代码里注册按键，省得手改 project.godot；之后想改键可以挪到项目设置里
static func ensure_input() -> void:
	if not InputMap.has_action(HIT_ACTION):
		InputMap.add_action(HIT_ACTION)
		for code in [KEY_SPACE, KEY_Z, KEY_X, KEY_J, KEY_K]:
			var k := InputEventKey.new()
			k.physical_keycode = code
			InputMap.action_add_event(HIT_ACTION, k)
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(HIT_ACTION, m)


## 换一个大关时调用（清空音符和成绩）
func load_chart(_chart: SongChart) -> void:
	accuracy_share = 1.0
	reset()


## 成绩清零、音符清空
func reset(_from_beat: float = 0.0) -> void:
	score = 0
	combo = 0
	max_combo = 0
	counts = {NoteData.Result.PERFECT: 0, NoteData.Result.GREAT: 0, NoteData.Result.GOOD: 0, NoteData.Result.MISS: 0}
	stage_counts = counts.duplicate()
	possible = 0.0
	_stage_weight = 0.0
	hit_offsets = []
	notes = []
	_next = 0
	_pattern = []
	_section_notes = []
	cancel_hold()
	stats_changed.emit()


## 开始一个小关：从 first_note_beat 起把它的鼓谱一遍遍循环铺下去（只提前铺 LOOKAHEAD_BEATS 拍）。
## 上一个小关在 start_beat 之后还没到的音符会被丢掉。
## 返回这个小关的音符列表——之后新铺出来的音符会不断加到这同一个列表里。
## 现在这一段谱子的样子（ChartPattern.skin），铺出来的音符都带上
var _skin: NoteSkin
var _skin_from := 0.0  # 谱子里第几拍起才带样子（ChartPattern.skin_from_beat）


func begin_section(index: int, def: SectionDef, beats_per_bar: int,
		start_beat: float, first_note_beat: float) -> Array[NoteData]:
	_drop_notes_from(start_beat)
	cancel_hold()
	_section_index = index
	_pattern = def.parse_notes(beats_per_bar)
	_skin = def.chart.skin if def.chart else null
	_skin_from = def.chart.skin_from_beat if def.chart else 0.0
	_pattern_len = def.length_beats(beats_per_bar)
	_pattern_origin = first_note_beat
	_pattern_k = 0
	_notes_end = INF
	_section_notes = []
	_generate()
	_skip_before = -INF
	return _section_notes


## 临时加一个不在谱里的音符（比如换段音符，见 scripts/fx/note_accents.gd）：插进还没判定的音符里，按拍子排好，
## 和谱里的音符一样判定、一样画。返回它；那一拍已经过了、或者还没铺到那么远（LOOKAHEAD_BEATS 拍以外）就不加，返回 null。
func add_note(beat: float, sound: int = NoteData.Sound.KICK) -> NoteData:
	_generate()
	if beat <= Conductor.song_beat or beat > Conductor.song_beat + LOOKAHEAD_BEATS:
		return null
	for old in _section_notes:   # 那一拍上已经有音符了（刚铺出来的）：就用它
		if not old.judged and absf(old.beat - beat) < 0.001:
			return old
	var n := NoteData.new()
	n.beat = beat
	n.sound = sound
	n.section_index = _section_index
	n.skin = _skin
	var i := notes.size()
	while i > _next and notes[i - 1].beat > beat:
		i -= 1
	notes.insert(i, n)
	var j := _section_notes.size()
	while j > 0 and _section_notes[j - 1].beat > beat:
		j -= 1
	_section_notes.insert(j, n)
	return n


## 不再出新音符，还没到的也都丢掉（大关打完时用）
## 下一次 begin_section 铺谱时，这一拍之前的音符不铺（谱面的循环照样从它给的起点算）。
## 用在「旧谱最后一个音符还留着、新谱从同一拍算起」的时候，免得那一拍上有两个音符。只管那一次。
var _skip_before := -INF

func skip_before(beat: float) -> void:
	_skip_before = beat


## 谱面打到第 beat 拍为止（这一拍上的还算）：之后已经铺出来的去掉，也不再往后铺。之前的照常打。
var _notes_end := INF

func end_notes_at(beat: float) -> void:
	_notes_end = beat
	_drop_notes_from(beat + 0.01)


func stop_notes() -> void:
	_pattern = []
	_drop_notes_from(Conductor.song_beat)


## 鼓谱循环一遍的拍数是 _pattern_len；第 _pattern_k 个音符 = 第几遍 + 这一遍里的第几个
func _generate() -> void:
	if _pattern.is_empty() or _pattern_len <= 0.0:
		return
	var horizon := Conductor.song_beat + LOOKAHEAD_BEATS
	while true:
		var d: Dictionary = _pattern[_pattern_k % _pattern.size()]
		var beat: float = _pattern_origin + (_pattern_k / _pattern.size()) * _pattern_len + d.beat
		if beat > horizon or beat > _notes_end + 0.001:
			break
		if beat < _skip_before - 0.001:
			_pattern_k += 1
			continue
		var n := NoteData.new()
		n.beat = beat
		n.sound = d.sound
		n.section_index = _section_index
		n.apply_props(d)  # 谱面编辑器里给的表现属性（不影响判定）
		n.skin = _skin if d.beat >= _skin_from - 0.001 else null
		notes.append(n)
		_section_notes.append(n)
		_pattern_k += 1


func _drop_notes_from(beat: float) -> void:
	while notes.size() > _next and notes[-1].beat >= beat - 0.001:
		notes[-1].judged = true  # 让还拿着它的旧关卡不再画它
		notes.pop_back()


func _process(_delta: float) -> void:
	if not Conductor.playing:
		return
	_generate()
	# 长按：按到尾巴 / 松手太久没按回去
	if _hold:
		_step_hold(_hold.update.bind(Conductor.input_beat()))
	# 过了判定窗口还没按的算 Miss（可能有后面的音符已经先被判掉了，跳过它们）
	var now := Conductor.input_time()
	while _next < notes.size():
		var n := notes[_next]
		if n.judged:
			_next += 1
			continue
		if now - Conductor.beat_to_sec(n.beat) <= rules.good_window_late:
			break
		if n.free:  # 不判定的音符：过了就过了，不算 Miss
			n.judged = true
			_next += 1
			continue
		_apply(n, NoteData.Result.MISS, rules.good_window_late)


func _unhandled_input(event: InputEvent) -> void:
	if not Conductor.playing:
		return
	if event.is_action_released(HIT_ACTION):
		# 松手的那一刻（不是下一帧）按判定时钟算；绑了好几个键时，全松开才算松手
		if _hold and not Input.is_action_pressed(HIT_ACTION):
			_step_hold(_hold.release.bind(Conductor.input_beat()))
		return
	if not event.is_action_pressed(HIT_ACTION):
		return
	if _hold and _hold.is_released():
		# 长按中途松了手又按回去：接着按，这一下不当普通按键
		_hold.regrab()
		return
	var now := Conductor.input_time()
	pressed.emit(_sound_for_press(now))
	var n := _nearest_note(now)
	if n:
		var diff := now - Conductor.beat_to_sec(n.beat)
		var r := rules.tap_result(diff)
		if r != NoteData.Result.NONE:
			if n.free:
				# 不判定的音符：这一下被它吃掉，当成空按交给关卡自己数（连按蓄力）
				n.judged = true
				while _next < notes.size() and notes[_next].judged:
					_next += 1
			else:
				_apply(n, r, diff)
				return
	empty_hit.emit()


## 开始盯一个长按：开头那一下已经判成打中之后，由关卡调用（一般在 note_judged 的处理里）。
## 什么时候算按完、中途松手能不能按回去，都按 rules 的「长按」一栏（见 HoldJudge）。
## 结束时调 on_done(success: bool, release_beat: float)（按到尾巴时 release_beat = end_beat）。
## 时间都用判定时钟（Conductor.input_beat()：扣了按键延迟，不含画面提前量），和按下的判定是同一把尺子。
## 同一时间只盯一个长按；新的会顶掉旧的（旧的不回调）。换小关、重开时自动取消。
func begin_hold(note: NoteData, end_beat: float, on_done: Callable) -> void:
	_hold = HoldJudge.new(note, end_beat, rules, on_done)
	if not Input.is_action_pressed(HIT_ACTION):
		# 开头那一下判完就已经松开了（比如点得特别快）
		_step_hold(_hold.release.bind(Conductor.input_beat()))


## 不再盯现在这个长按（不回调）
func cancel_hold() -> void:
	_hold = null


## 正在盯的长按音符（没有就是 null）
func holding() -> NoteData:
	return _hold.note if _hold else null


## 让现在这个长按走一步（step 是它的 release / update），结束了就放掉。
## 回调里可能已经开始了下一个长按，所以只放掉自己这个。
func _step_hold(step: Callable) -> void:
	var h := _hold
	step.call()
	if h.done and _hold == h:
		_hold = null


## 离 now 最近的音符（包括刚判过的上一个）。最近的是已经判过的 = 这一下算多按的，不去抢下一个音符。
## 这样一个音符的判定窗口最多延伸到和相邻音符间隔的一半，密的时候也不会吃错音符。
func _nearest_note(now: float) -> NoteData:
	var best: NoteData = null
	var best_d := INF
	for i in range(maxi(_next - 1, 0), notes.size()):
		var n := notes[i]
		var d := now - Conductor.beat_to_sec(n.beat)
		if d < -rules.good_window_early:
			break  # 后面的更远
		if absf(d) < best_d:
			best_d = absf(d)
			best = n
	if best == null or best.judged:
		return null
	return best


## 打中的平均偏差（秒，正 = 偏晚）。没打中过返回 0。
func mean_offset() -> float:
	if hit_offsets.is_empty():
		return 0.0
	var sum := 0.0
	for d in hit_offsets:
		sum += d
	return sum / hit_offsets.size()


## 按下时该发哪种鼓：取时间上离现在最近的那个音符的音色（空按也一样会响）
func _sound_for_press(now: float) -> int:
	if notes.is_empty():
		return NoteData.Sound.KICK
	var i := mini(_next, notes.size() - 1)
	if i > 0:
		var to_next := absf(Conductor.beat_to_sec(notes[i].beat) - now)
		var to_prev := absf(Conductor.beat_to_sec(notes[i - 1].beat) - now)
		if to_prev < to_next:
			i -= 1
	return notes[i].sound


func _apply(n: NoteData, result: int, diff: float) -> void:
	n.judged = true
	n.result = result
	while _next < notes.size() and notes[_next].judged:
		_next += 1
	counts[result] += 1
	stage_counts[result] += 1
	if result == NoteData.Result.MISS:
		combo = 0
	else:
		combo += 1
		max_combo = maxi(max_combo, combo)
		hit_offsets.append(diff)
	note_judged.emit(n, result, diff)
	if result != NoteData.Result.MISS and combo in COMBO_MILESTONES:
		combo_milestone.emit(combo)
	stats_changed.emit()


## 给一个“不判定的音符”（NoteData.free）补一个结果：连按这类玩法由关卡自己数按了几下，
## 数完告诉这里算 Perfect / Good / Miss，照常计分、算连击、弹判定文字。
func judge_free(n: NoteData, result: int) -> void:
	if n == null or result == NoteData.Result.NONE:
		return
	_apply(n, result, 0.0)


## 按得分占满分的比例给评级（阈值见上面“计分”一栏）
func rank() -> String:
	var r := float(score) / possible if possible > 0.0 else 0.0
	if r >= rank_s:
		return "S"
	if r >= rank_a:
		return "A"
	if r >= rank_b:
		return "B"
	return "C"


## 开始一个新阶段（小关）：weight = 它占这一大关满分的比例（0~1）。main.gd 在进小关时调。
func begin_stage(weight: float, expected_notes: float = 0.0) -> void:
	stage_counts = {NoteData.Result.PERFECT: 0, NoteData.Result.GREAT: 0, NoteData.Result.GOOD: 0, NoteData.Result.MISS: 0}
	_stage_weight = weight
	_stage_expected = expected_notes


## 当前阶段（小关）的满分 = level_max × 它的占比（不乘 accuracy_share）。
## 阶段入账之后（切到下一个小关之前那一下）会变成 0。
## 某个阶段想把分数全换成别的玩法（比如打星球）时用：accuracy_share 设 0，再按这个满分用 add_bonus 加。
func stage_max() -> float:
	return level_max * _stage_weight


## 当前阶段的准确率（0~1，还没判定过音符 = 0）
func stage_accuracy() -> float:
	var c := stage_counts
	var total: int = c[NoteData.Result.PERFECT] + c[NoteData.Result.GREAT] + c[NoteData.Result.GOOD] + c[NoteData.Result.MISS]
	if total <= 0:
		return 0.0
	return (c[NoteData.Result.PERFECT] * perfect_weight + c[NoteData.Result.GREAT] * great_weight
			+ c[NoteData.Result.GOOD] * good_weight) / total


## 实时显示用的分数：已经入账的 + 当前阶段一路打下来的估计值
## （阶段满分 × 打中的权重之和 ÷ 预计要按的下数，越打越多，最多到阶段满分；阶段结束入账时差不多就是这个数）。
## 真正的成绩、评级还是按 bank_stage 入账的来算
func live_score() -> int:
	if _stage_weight <= 0.0 or stage_counts.is_empty():
		return score
	var c := stage_counts
	var judged: int = c[NoteData.Result.PERFECT] + c[NoteData.Result.GREAT] + c[NoteData.Result.GOOD] + c[NoteData.Result.MISS]
	var hits: float = c[NoteData.Result.PERFECT] * perfect_weight + c[NoteData.Result.GREAT] * great_weight \
			+ c[NoteData.Result.GOOD] * good_weight
	var expected := maxf(_stage_expected, float(judged))
	if expected <= 0.0:
		return score
	return score + roundi(level_max * accuracy_share * _stage_weight * minf(hits / expected, 1.0))


## 当前阶段打完：按准确率入账（分数在这里跳一次）。main.gd 在切小关和通关时调；同一阶段只入账一次。
func bank_stage() -> void:
	if _stage_weight <= 0.0:
		return
	var stage_max := level_max * accuracy_share * _stage_weight
	score += roundi(stage_max * stage_accuracy())
	possible += stage_max
	_stage_weight = 0.0
	stats_changed.emit()


## 加一笔准确率以外的分（可以是负数），max_points = 这一项本来最多能拿多少（算评级比例用）
func add_bonus(points: int, max_points: float = 0.0) -> void:
	score = maxi(score + points, 0)
	possible += max_points
	stats_changed.emit()


## 已废弃：以前按关覆盖实时算分时用，现在分数只在阶段结束时入账，这里只刷新一下显示
func refresh_score() -> void:
	stats_changed.emit()
