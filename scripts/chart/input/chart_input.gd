class_name ChartInput
extends CanvasLayer
## 谱面里「长按」和「连击」的通用处理：挂一个在 Judge 旁边，所有关卡都能用，关卡脚本不用知道它。
## 只用 Judge 的接口（note_judged / pressed / begin_hold / judge_free / rules 和 NoteData.free）。
##
## 长按（音符 length > 0，老鼓谱里音符后面接 "=" 也算）：
##   开头那一下由 Judge 照常判；打中之后交给 Judge.begin_hold 盯着按住。
##   没按完：断连击，积累条按一次 Miss 扣。
##   关卡脚本自己处理长按的（脚本里有 _on_hold_done，比如迪斯科、洗衣机开场）这里不管，免得盯两遍。
##
## 连击（音符 mash = true，length = 连击这一段几拍；谱面编辑器里选中音符按 M）：
##   这一段里不看节奏，只数按了几下；段尾交给 judge.rules.mash_result 出结果，再让 Judge 照常计分、算连击、涨积累条。
##   连击这一段里不要再排别的音符。
##
## 什么算按完、连击按多快算 Perfect，都在 Judge 的 rules（JudgeRules）里调。
## 画面：屏幕下方一条提示（HOLD / MASH + 进度条），关卡自己画的音符照旧。

## 长按有没有尾判。关着（默认）：开头那一下打中就算成，提前松手不扣（不断连击、不扣积累条）。
## 开着：要按完（什么算按完见 Judge 的 rules），没按完断连击、积累条按一次 Miss 扣。
@export var hold_tail_judge := false
## 屏幕下方的提示要不要画
@export var show_prompt := true
## 长按 / 连击来之前提前几拍预告
@export var warn_beats := 2.0
## 提示条的位置（占屏幕高度的比例）和宽度（像素）
@export_range(0.0, 1.0) var prompt_y := 0.8
@export var prompt_width := 360.0

const SCAN := 128  # 每帧只看 Judge 最后铺出来的这么多个音符
const MSG_SECONDS := 0.7

var judge: Judge
## 积累条（长按松早了扣一次），可以不给
var gauge: Node
## 返回现在的关卡节点（用来看它是不是自己处理长按），可以不给
var section_of := Callable()

var _hold: NoteData
var _mash: NoteData
var _mash_count := 0
var _mash_queue: Array[NoteData] = []
var _msg := ""
var _msg_color := Color.WHITE
var _msg_age := INF
var _panel: Control


## 建一个挂好的组件：把返回值 add_child 到随便哪个节点下就行
static func attach(with_judge: Judge, with_gauge: Node = null, current_section := Callable()) -> ChartInput:
	var c := ChartInput.new()
	c.judge = with_judge
	c.gauge = with_gauge
	c.section_of = current_section
	return c


func _ready() -> void:
	layer = 30
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_prompt)
	add_child(_panel)
	if judge:
		judge.note_judged.connect(_on_note_judged)
		judge.pressed.connect(_on_pressed)


func _process(delta: float) -> void:
	if judge == null:
		return
	_msg_age += delta
	# 新铺出来的连击音符：交给 Judge 当“不判定的音符”，排队等它的那一段
	for i in range(maxi(judge.notes.size() - SCAN, 0), judge.notes.size()):
		var n := judge.notes[i]
		if n.mash and not n.free and not n.judged:
			n.free = true
			_mash_queue.append(n)
	if Conductor.playing:
		var now := Conductor.input_beat()
		if _mash and now >= _mash.beat + _mash_len(_mash):
			_finish_mash()
		while _mash == null and not _mash_queue.is_empty() and now >= _mash_queue[0].beat - 0.1:
			var q: NoteData = _mash_queue.pop_front()
			# 换小关时被丢掉的、已经过完的都跳过
			if judge.notes.has(q) and now < q.beat + _mash_len(q):
				_mash = q
				_mash_count = 0
	_panel.queue_redraw()


func _mash_len(n: NoteData) -> float:
	return n.length if n.length > 0.0 else 1.0


func _on_pressed(_sound: int) -> void:
	if _mash:
		_mash_count += 1


func _finish_mash() -> void:
	var n := _mash
	_mash = null
	if not judge.notes.has(n):
		return
	var r := judge.rules.mash_result(_mash_count, _mash_len(n) * Conductor.sec_per_beat())
	_say("MASH x%d" % _mash_count, SpinSection.result_color(r))
	judge.judge_free(n, r)


func _handles_holds_itself() -> bool:
	var s: Variant = section_of.call() if section_of.is_valid() else null
	return s is Node and (s as Node).has_method("_on_hold_done")


func _on_note_judged(note: NoteData, result: int, _diff: float) -> void:
	if note.mash or note.length <= 0.0 or result == NoteData.Result.MISS:
		return
	if _handles_holds_itself():
		return
	_hold = note
	judge.begin_hold(note, note.beat + note.length, _on_hold_done.bind(note))


func _on_hold_done(success: bool, _release_beat: float, note: NoteData) -> void:
	if note != _hold:
		return
	_hold = null
	if success or not hold_tail_judge:
		_say("HOLD OK", SpinSection.result_color(NoteData.Result.PERFECT))
		return
	_say("TOO EARLY", SpinSection.result_color(NoteData.Result.MISS))
	judge.combo = 0
	judge.stats_changed.emit()
	if gauge and gauge.has_method("apply"):
		gauge.call("apply", NoteData.Result.MISS)


func _say(text: String, color: Color) -> void:
	_msg = text
	_msg_color = color
	_msg_age = 0.0


# ---------------------------------------------------------------- 画

## 马上要来的长按 / 连击（还没判、在 warn_beats 拍之内），没有就是 null
func _upcoming() -> NoteData:
	var beat := Conductor.song_beat
	var own_holds := _handles_holds_itself()
	for i in range(maxi(judge.notes.size() - SCAN, 0), judge.notes.size()):
		var n := judge.notes[i]
		if n.judged or n.beat < beat or n.beat - beat > warn_beats:
			continue
		if n.mash or (n.length > 0.0 and not own_holds):
			return n
	return null


func _draw_prompt() -> void:
	if not show_prompt or judge == null:
		return
	var beat := Conductor.song_beat
	var text := ""
	var color := SpinSection.HOLD_COLOR
	var fill := -1.0
	if _mash:
		text = "MASH!  x%d" % _mash_count
		color = Color(1.0, 0.75, 0.15)
		fill = 1.0 - clampf((beat - _mash.beat) / _mash_len(_mash), 0.0, 1.0)
	elif _hold:
		text = "HOLD"
		fill = clampf((beat - _hold.beat) / maxf(_hold.length, 0.001), 0.0, 1.0)
	elif _msg_age < MSG_SECONDS:
		text = _msg
		color = Color(_msg_color, 1.0 - _msg_age / MSG_SECONDS)
	else:
		var n := _upcoming()
		if n == null:
			return
		text = "MASH" if n.mash else "HOLD"
		if n.mash:
			color = Color(1.0, 0.75, 0.15)
		color.a = 0.55
	var size := _panel.size
	var font := ThemeDB.fallback_font
	var fs := 34
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2((size.x - w) / 2.0, size.y * prompt_y)
	_panel.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, color.a * 0.8))
	_panel.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
	if fill >= 0.0:
		var bar := Rect2((size.x - prompt_width) / 2.0, at.y + 12.0, prompt_width, 12.0)
		_panel.draw_rect(bar.grow(3.0), Color(0, 0, 0, 0.6))
		_panel.draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), color)
