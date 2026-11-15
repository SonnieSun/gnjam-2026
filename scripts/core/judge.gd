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

## 判定窗口（秒，按早 / 晚的绝对值）。在 main.tscn 里选中 Judge 节点调。
@export var perfect_window := 0.045
@export var great_window := 0.09
## Good 的窗口早晚分开：人更容易按晚，晚的一侧稍宽
@export var good_window_early := 0.12
@export var good_window_late := 0.14
const HIT_ACTION := "hit"
const COMBO_MILESTONES: Array[int] = [10, 20, 50, 100, 200, 300, 400, 500]

var notes: Array[NoteData] = []
var score := 0
var combo := 0
var max_combo := 0
var counts := {}
## 打中的音符各偏了多少秒（正 = 晚），结算时算平均偏差用
var hit_offsets: Array[float] = []

var _next := 0  # 第一个还没判定的音符

## 音符提前铺多少拍（要比任何关卡“提前显示音符”的拍数都长）
const LOOKAHEAD_BEATS := 16.0
var _pattern: Array[Dictionary] = []  # 当前小关循环的鼓谱
var _pattern_len := 0.0
var _pattern_origin := 0.0
var _pattern_k := 0
var _section_index := 0
var _section_notes: Array[NoteData] = []


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
	reset()


## 成绩清零、音符清空
func reset(_from_beat: float = 0.0) -> void:
	score = 0
	combo = 0
	max_combo = 0
	counts = {NoteData.Result.PERFECT: 0, NoteData.Result.GREAT: 0, NoteData.Result.GOOD: 0, NoteData.Result.MISS: 0}
	hit_offsets = []
	notes = []
	_next = 0
	_pattern = []
	_section_notes = []
	stats_changed.emit()


## 开始一个小关：从 first_note_beat 起把它的鼓谱一遍遍循环铺下去（只提前铺 LOOKAHEAD_BEATS 拍）。
## 上一个小关在 start_beat 之后还没到的音符会被丢掉。
## 返回这个小关的音符列表——之后新铺出来的音符会不断加到这同一个列表里。
func begin_section(index: int, def: SectionDef, beats_per_bar: int,
		start_beat: float, first_note_beat: float) -> Array[NoteData]:
	_drop_notes_from(start_beat)
	_section_index = index
	_pattern = def.parse_notes(beats_per_bar)
	_pattern_len = def.length_beats(beats_per_bar)
	_pattern_origin = first_note_beat
	_pattern_k = 0
	_section_notes = []
	_generate()
	return _section_notes


## 不再出新音符，还没到的也都丢掉（大关打完时用）
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
		if beat > horizon:
			break
		var n := NoteData.new()
		n.beat = beat
		n.sound = d.sound
		n.section_index = _section_index
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
	# 过了判定窗口还没按的算 Miss（可能有后面的音符已经先被判掉了，跳过它们）
	var now := Conductor.input_time()
	while _next < notes.size():
		var n := notes[_next]
		if n.judged:
			_next += 1
			continue
		if now - Conductor.beat_to_sec(n.beat) <= good_window_late:
			break
		_apply(n, NoteData.Result.MISS, good_window_late)


func _unhandled_input(event: InputEvent) -> void:
	if not Conductor.playing or not event.is_action_pressed(HIT_ACTION):
		return
	var now := Conductor.input_time()
	pressed.emit(_sound_for_press(now))
	var n := _nearest_note(now)
	if n:
		var diff := now - Conductor.beat_to_sec(n.beat)
		var r := _result_for(diff)
		if r != NoteData.Result.NONE:
			_apply(n, r, diff)
			return
	empty_hit.emit()


## 离 now 最近的音符（包括刚判过的上一个）。最近的是已经判过的 = 这一下算多按的，不去抢下一个音符。
## 这样一个音符的判定窗口最多延伸到和相邻音符间隔的一半，密的时候也不会吃错音符。
func _nearest_note(now: float) -> NoteData:
	var best: NoteData = null
	var best_d := INF
	for i in range(maxi(_next - 1, 0), notes.size()):
		var n := notes[i]
		var d := now - Conductor.beat_to_sec(n.beat)
		if d < -good_window_early:
			break  # 后面的更远
		if absf(d) < best_d:
			best_d = absf(d)
			best = n
	if best == null or best.judged:
		return null
	return best


func _result_for(diff: float) -> int:
	var a := absf(diff)
	if a <= perfect_window:
		return NoteData.Result.PERFECT
	if a <= great_window:
		return NoteData.Result.GREAT
	if diff >= -good_window_early and diff <= good_window_late:
		return NoteData.Result.GOOD
	return NoteData.Result.NONE


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
	if result == NoteData.Result.MISS:
		combo = 0
	else:
		combo += 1
		max_combo = maxi(max_combo, combo)
		hit_offsets.append(diff)
		match result:
			NoteData.Result.PERFECT: score += 100
			NoteData.Result.GREAT: score += 80
			_: score += 50
	note_judged.emit(n, result, diff)
	if result != NoteData.Result.MISS and combo in COMBO_MILESTONES:
		combo_milestone.emit(combo)
	stats_changed.emit()
