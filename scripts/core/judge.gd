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

const PERFECT_WINDOW := 0.08
const GOOD_WINDOW := 0.2
const HIT_ACTION := "hit"
const COMBO_MILESTONES: Array[int] = [10, 20, 50, 100, 200, 300, 400, 500]

var notes: Array[NoteData] = []
var score := 0
var combo := 0
var max_combo := 0
var counts := {}

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
	# 在代码里注册按键，省得手改 project.godot；之后想改键可以挪到项目设置里
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
	counts = {NoteData.Result.PERFECT: 0, NoteData.Result.GOOD: 0, NoteData.Result.MISS: 0}
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
	# 过了判定窗口还没按的算 Miss
	while _next < notes.size():
		var n := notes[_next]
		if Conductor.song_time - Conductor.beat_to_sec(n.beat) <= GOOD_WINDOW:
			break
		_apply(n, NoteData.Result.MISS, GOOD_WINDOW)


func _unhandled_input(event: InputEvent) -> void:
	if not Conductor.playing or not event.is_action_pressed(HIT_ACTION):
		return
	pressed.emit(_sound_for_press())
	if _next < notes.size():
		var n := notes[_next]
		var diff := Conductor.song_time - Conductor.beat_to_sec(n.beat)
		if absf(diff) <= PERFECT_WINDOW:
			_apply(n, NoteData.Result.PERFECT, diff)
			return
		if absf(diff) <= GOOD_WINDOW:
			_apply(n, NoteData.Result.GOOD, diff)
			return
	empty_hit.emit()


## 按下时该发哪种鼓：取时间上离现在最近的那个音符的音色（空按也一样会响）
func _sound_for_press() -> int:
	if notes.is_empty():
		return NoteData.Sound.KICK
	var i := mini(_next, notes.size() - 1)
	if i > 0:
		var to_next := absf(Conductor.beat_to_sec(notes[i].beat) - Conductor.song_time)
		var to_prev := absf(Conductor.beat_to_sec(notes[i - 1].beat) - Conductor.song_time)
		if to_prev < to_next:
			i -= 1
	return notes[i].sound


func _apply(n: NoteData, result: int, diff: float) -> void:
	n.judged = true
	n.result = result
	_next += 1
	counts[result] += 1
	if result == NoteData.Result.MISS:
		combo = 0
	else:
		combo += 1
		max_combo = maxi(max_combo, combo)
		score += 100 if result == NoteData.Result.PERFECT else 50
	note_judged.emit(n, result, diff)
	if result != NoteData.Result.MISS and combo in COMBO_MILESTONES:
		combo_milestone.emit(combo)
	stats_changed.emit()
