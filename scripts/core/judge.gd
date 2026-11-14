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

const PERFECT_WINDOW := 0.05
const GOOD_WINDOW := 0.12
const HIT_ACTION := "hit"
const COMBO_MILESTONES: Array[int] = [10, 20, 50, 100, 200, 300, 400, 500]

var notes: Array[NoteData] = []
var score := 0
var combo := 0
var max_combo := 0
var counts := {}

var _next := 0  # 第一个还没判定的音符


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


func load_chart(chart: SongChart) -> void:
	notes = chart.build_notes()
	reset(0.0)


## 重置成绩；from_beat 之前的音符直接跳过（用于从中间开始）
func reset(from_beat: float) -> void:
	score = 0
	combo = 0
	max_combo = 0
	counts = {NoteData.Result.PERFECT: 0, NoteData.Result.GOOD: 0, NoteData.Result.MISS: 0}
	_next = notes.size()
	for i in notes.size():
		var n := notes[i]
		n.judged = n.beat < from_beat
		n.result = NoteData.Result.NONE
		if not n.judged and i < _next:
			_next = i
	stats_changed.emit()


func notes_for_section(index: int) -> Array[NoteData]:
	var out: Array[NoteData] = []
	for n in notes:
		if n.section_index == index:
			out.append(n)
	return out


func _process(_delta: float) -> void:
	if not Conductor.playing:
		return
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
