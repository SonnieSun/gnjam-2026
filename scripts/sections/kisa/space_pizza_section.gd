@tool
extends "res://scripts/sections/pizza_section.gd"
## 太空版披萨猫（第 3 大关第二段）：玩法完全沿用 Sonnie 的披萨猫关（过圈 → 九宫格 → 万花筒），
## 这里只多做一件事——从上一段「太空打飞机」接过来：
## 上一段结尾猫飞走、黑幕落下盖满画面（见 space_shooter_section.gd 的结尾过场），切到这一段时黑幕还盖着，
## 这一段一开始就让它往下落出屏幕，露出新画面（和两关之间的黑幕一样）。
## 黑幕在 SpaceShooterScore.handoff 里；没有（比如直接跳到这一段）就和原来的披萨猫关一样。

## 康康舞曲在这一段有三个阶段，谱面跟着换（都在音乐换的那条小节线上换，之前铺好的音符照常打完）：
##   开头（另一段旋律）      大关文件里这个小关的 bars：每小节第 1、3 拍
##   四阶下行（进度一半起）  阶段 steps：两小节一个循环，第 1 小节的四拍就是那四个往下走的重音，第 2 小节不打
##   高潮（经典旋律，fever） 阶段 peak：四分音符连打，每拍一下
## 后两套是谱面文件 levels/charts/<大关>_<小关>_steps.tres / _peak.tres，配拍编辑器按 chart_phases() 列出来、能直接改；
## 没有文件时用下面的 mid_bars / peak_bars。
## 每个阶段多长在大关文件里（这个小关的 gauge_events 65 / 98 + phase_gain / fever_gain）：四阶下行大约放一遍（8 小节），
## 高潮从过线算起大约 14 小节（等乐句线 + 两小节过门 + 经典旋律至少一遍）。
@export var mid_bars := PackedStringArray(["k...k...k...k...", "................"])
@export var peak_bars := PackedStringArray(["k...s...k...s..."])
var _next_bars := PackedStringArray()
var _next_phase := ""


## 这个小关里换谱子的玩法阶段（配拍编辑器读这个）
static func chart_phases() -> Array:
	return [
		{"id": "", "name": "开头（康康舞曲的另一段）", "event": 0},
		{"id": "steps", "name": "四阶下行", "event": 1},
		{"id": "peak", "name": "高潮（经典旋律，fever）", "event": 2},
	]
var _next_at := INF

## 黑幕落出屏幕前再盖几秒（等新画面摆好）、落出去用几秒
@export var curtain_hold := 0.1
@export var curtain_leave := 0.9


func _on_enter() -> void:
	super._on_enter()
	if Engine.is_editor_hint() or camera == null:
		return
	if not Music.change_planned.is_connected(_on_change_planned):
		Music.change_planned.connect(_on_change_planned)
		get_tree().process_frame.connect(_chart_tick)
	_beat_decor()
	var curtain := SpaceShooterScore.handoff.get("curtain") as CanvasLayer
	SpaceShooterScore.handoff = {}
	if curtain == null or not is_instance_valid(curtain) or curtain.get_child_count() == 0:
		return
	var rect := curtain.get_child(0) as Control
	var tw := rect.create_tween()
	tw.tween_interval(curtain_hold)
	tw.tween_property(rect, "position:y", get_viewport().get_visible_rect().size.y + 40.0, curtain_leave) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(curtain.queue_free)


## 音乐排好了换阶段（预备信号）：记下在哪条线换哪套谱
func _on_change_planned(kind: String, id: int, _fill_beat: float, commit_beat: float) -> void:
	if not active:
		return
	if kind == "tier" and id == 2 and not mid_bars.is_empty():
		_next_bars = mid_bars
		_next_phase = "steps"
		_next_at = commit_beat
	elif kind == "fever" and not peak_bars.is_empty():
		_next_bars = peak_bars
		_next_phase = "peak"
		_next_at = commit_beat


## 离那条线 12 拍以内才换（判定只提前铺 16 拍）：旧谱打到那条线为止，新谱从那条线起算
func _chart_tick() -> void:
	if not active or is_inf(_next_at) or song_beat() < _next_at - 12.0:
		return
	var main := get_parent().get_parent() if get_parent() else null
	var at := _next_at
	_next_at = INF
	if main == null or not main.get("judge") or main.get("_switch_at") == null:
		return
	if float(main.get("_switch_at")) >= 0.0:
		return  # 已经在收尾了（积累条满了）：不再换谱
	var index: int = main.get("_index") if main.get("_index") != null else 0
	var d: SectionDef = def.duplicate()
	var file := "res://levels/charts/%s_%d_%s.tres" % [Levels.current_path().get_file().get_basename(), index, _next_phase]
	d.chart = load(file) as ChartPattern if ResourceLoader.exists(file) else null
	if d.chart == null:
		d.bars = _next_bars
	var keep: Array[NoteData] = []
	for n in notes:
		if not n.judged and n.beat < at - 0.001:
			keep.append(n)
	notes = main.judge.begin_section(index, d, Conductor.chart.beats_per_bar, at, at)
	for i in keep.size():
		notes.insert(i, keep[i])


## 装饰跟拍（BeatFx，见 stages/shared/beat_fx）：光环的砖一块接一块胀过去；光球的芯各用各的节奏，灯跟底鼓。
## 光球 / 气泡 / 云本身每帧被这一关挪位置，所以接在它们里面的零件上。披萨、猫、判定圈是主体，不接。
var _decor_done := false

func _beat_decor() -> void:
	if _decor_done:
		return
	_decor_done = true
	BeatDecor.wave(_halo.get_children(), 0.2, 2.0)
	var k := 0
	for orb in _orbs.get_children():
		k += 1
		var core := orb.get_node_or_null("Core")
		if core:
			BeatDecor.stagger(core, k * 3, 0.25)  # 每个光球的芯用不同的节奏
		var lamp := orb.get_node_or_null("Light")
		if lamp:
			BeatDecor.light(lamp, 0.9)
