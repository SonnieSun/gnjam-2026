@tool
extends "res://scripts/sections/ring_section.gd"
## 迪斯科猫砂盆关卡：判定玩法和 Sonnie 的缩圈段落完全一样（圈往中间收，和白色轮廓重合时按）。
## 画面是铺满屏幕的 3D isometric 房间，猫在猫砂盆里，按键就转。
## 舞台由通用的积累条推进（见 scripts/core/gauge.gd）：
##   积累条越满镜头拉得越远；
##   第 1 个事件（disco.tscn 里配的是 20 分）星星灯掉下来、场景变亮；
##   第 2 个事件（40 分）迪斯科灯球掉下来；
##   第 3 个事件（现在没配）2D 跳舞猫进场。想加就在 disco.tscn 的 gauge_events 里多填一个分数。
## 具体演出都在 DiscoStage 里，这里只负责把积累条的事件和「现在第几拍」告诉它。
## 示例原来自带的“成功 +1 / Miss -1”进度和“猫离开猫砂盆漂移”阶段现在不用了（代码还留在 DiscoStage 里）。
## 长按音符是按“谱面只放一遍”写的，现在鼓谱是循环的，长按暂时不要用。
##
## 长按音符（只有这个关卡认）：谱面里在音符后面接一串 "="，比如 "k=======s......."
## = 底鼓按下后按住 8 格（2 拍）再松手。Sonnie 的谱面解析把 "=" 当休止，所以开头那一下
## 仍由 Judge 正常判定；按住的部分由这里自己盯：每按住满 1 拍进度 +1，按到尾巴再 +1，
## 中途提前松手算一次 Miss（进度 -1）。长按期间不要排别的音符。长按不计入 HUD 的分数和连击。
##
## 蓝色圆盘在 disco.tscn 里把 disc_color 设成全透明藏掉了，只留白色判定圈。
## 编辑器预览里仍显示原来的 2D 画面。测试用，只在本机 _sandbox 里，不进仓库。只支持一个目标圆。

## 房间场景（里面要有 Stars/*、DiscoBall、DriftPath/* 这些定位点）
@export var room: PackedScene = preload("res://_sandbox/spin_cat/disco_room.tscn")
## 长按可以提前多少拍松手还算按完
@export var hold_release_grace := 0.3
## 长按条带的透明度
@export_range(0.0, 1.0) var hold_band_alpha := 0.4

var _spin_cat: SpinCat3D
var _stage: DiscoStage
var _hold_ends := {}  # NoteData -> 长按结束的拍数（绝对拍数）
var _holds_parsed := false
var _holding: NoteData  # 正在按住的那个长按音符
var _hold_ticks := 0  # 这次长按已经给过几次「按住满 1 拍」的进度
var _circle_pos := Vector2.ZERO


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	for cat in _cats:
		cat.visible = false
	_spin_cat = SpinCat3D.new()
	_spin_cat.full_screen = true
	_spin_cat.backdrop = room
	_spin_cat.listen_input = true  # 每次按键都转，按住一直转，不管有没有打中
	_spin_cat.position = target_position(0)
	_spin_cat.z_index = -1  # 3D 画面垫在最底下，缩圈和判定圈画在它上面
	add_child(_spin_cat)
	_stage = DiscoStage.new()
	add_child(_stage)
	_stage.setup(_spin_cat)
	_stage.external = true  # 阶段和镜头交给积累条


func _update_spin(local_beat: float, angle: float) -> void:
	super(local_beat, angle)
	if _stage == null:
		return
	if not _holds_parsed:
		_parse_holds()
	_stage.external_zoom = _zoom_for_gauge()
	_stage.update(song_beat())
	# 判定圈（和缩过来的圈、命中特效）跟着猫走
	_circle_pos = _stage.cat_screen_offset()
	if _holding:
		_update_hold()


## 判定圈的位置：跟着 3D 猫在屏幕上的位置（编辑器预览里没有 3D 猫，就用场景里摆的）
func target_position(i: int) -> Vector2:
	return _circle_pos if _stage else super(i)


## 积累条触发事件：第 1 个 = 星星灯，第 2 个 = 灯球，第 3 个 = 跳舞猫
func _on_gauge_event(index: int, _value: int) -> void:
	if _stage:
		_stage.enter_stage(index)


## 镜头远近跟着积累条：到第 1 个事件时拉到 zoom_at_stars，到第 2 个事件时看到整个房间
func _zoom_for_gauge() -> float:
	var v := progress() * gauge_max
	var first := float(gauge_event_values[0]) if gauge_event_values.size() > 0 else gauge_max / 3.0
	var second := float(gauge_event_values[1]) if gauge_event_values.size() > 1 else gauge_max * 2.0 / 3.0
	if v <= first:
		return v / maxf(first, 1.0) * _stage.zoom_at_stars
	return lerpf(_stage.zoom_at_stars, 1.0, clampf((v - first) / maxf(second - first, 1.0), 0.0, 1.0))


func _on_note_judged(note: NoteData, result: int) -> void:
	super(note, result)
	if _stage == null:
		return
	if result == NoteData.Result.MISS:
		_stage.add_miss()
		return
	_stage.add_success()
	if _hold_ends.has(note):
		_holding = note
		_hold_ticks = 0


## 盯着正在进行的长按：按住满 1 拍 +1；按到尾巴 +1 收工；提前松手 -1
func _update_hold() -> void:
	var end: float = _hold_ends[_holding]
	var now := song_beat()
	if now >= end:
		_stage.add_success()
		_holding = null
		return
	if not Input.is_action_pressed(Judge.HIT_ACTION):
		if now < end - hold_release_grace:
			_stage.add_miss()
		else:
			_stage.add_success()
		_holding = null
		return
	var ticks := floori(now - _holding.beat)
	while _hold_ticks < ticks:
		_hold_ticks += 1
		_stage.add_success()


## 从谱面里找出长按：音符后面跟着的每个 "=" 把它延长一格
func _parse_holds() -> void:
	_holds_parsed = true
	var beats_per_bar: int = Conductor.chart.beats_per_bar
	for bar_i in def.bars.size():
		var s := def.bars[bar_i]
		var i := 0
		while i < s.length():
			var run := 0
			while i + 1 + run < s.length() and s[i + 1 + run] == "=":
				run += 1
			if run > 0 and SectionDef._char_to_sound(s[i]) >= 0:
				var cell := float(beats_per_bar) / s.length()
				var beat := def.start_beat + bar_i * beats_per_bar + i * cell
				for n in notes:
					if is_equal_approx(n.beat, beat):
						_hold_ends[n] = beat + run * cell
			i += 1 + run


func _draw() -> void:
	super()
	if def == null:
		return
	# 长按：头圈和尾圈之间填一条半透明的带子；尾圈缩到判定圈时松手
	var from_r := start_radius
	if from_r <= 0.0:
		from_r = screen_size().length() / 2.0 + 40.0
	for n: NoteData in _hold_ends:
		var holding_this := n == _holding
		if n.judged and not holding_this:
			continue  # 已经打完，或者头没打中 / 中途断了
		var end: float = _hold_ends[n]
		if beats_until(n) > approach_beats:
			continue
		var head_r := target_radius if holding_this else _ring_radius(beats_until(n), from_r)
		var tail_r := _ring_radius(end - song_beat(), from_r)
		var c := sound_color(n)
		var center := hit_position(n)
		if tail_r > head_r:
			c.a = hold_band_alpha
			draw_arc(center, (head_r + tail_r) / 2.0, 0.0, TAU, 96, c, tail_r - head_r)
		c.a = 1.0
		draw_arc(center, tail_r, 0.0, TAU, 96, c, 6.0)
		if holding_this:
			draw_arc(center, target_radius, 0.0, TAU, 96, c, 10.0)


## 离判定点还有 ahead 拍的圈现在多大（和 ring_section 画圈的算法一致）
func _ring_radius(ahead: float, from_r: float) -> float:
	var t := minf(ahead / approach_beats, 1.0)
	return maxf(target_radius + t * (from_r - target_radius), 4.0)
