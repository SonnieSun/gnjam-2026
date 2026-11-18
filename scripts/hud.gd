extends CanvasLayer

@onready var score_label: ScoreComboWidget = $ScoreLabel
@onready var combo_label: ScoreComboWidget = $ComboLabel
@onready var judge_label: Label = $JudgeLabel
@onready var judgement_art: JudgementWidget = $JudgementArt
@onready var debug_label: Label = $DebugLabel
@onready var result_label: ResultWidget = $ResultLabel
@onready var milestone_label: ComboMilestoneWidget = $MilestoneLabel
## 积累条（样子在 main.tscn 的 HUD/GaugeBar 里调）
@onready var gauge_bar: ProgressBar = get_node_or_null("GaugeBar")
## 结算评级字母（样子在 main.tscn 的 HUD/RankLabel 里调）
@onready var rank_label: Label = get_node_or_null("RankLabel")

## 判定文字下面的小字（EARLY / LATE）。main.tscn 的 HUD/TimingLabel，没有这个节点就不显示
@onready var timing_label: Label = get_node_or_null("TimingLabel")

@export_group("判定文字")
## 判定文字弹出来时先放大到多少倍再弹回原大小（Perfect 单独一个更大的）
@export var judge_pop := 1.3
@export var perfect_pop := 1.7
## 弹回去用多久（秒）
@export var judge_pop_seconds := 0.18
## 四种判定各用什么颜色
@export var perfect_color := Color(1.0, 0.9, 0.2)
@export var great_color := Color(0.3, 0.85, 1.0)
@export var good_color := Color(0.4, 1.0, 0.5)
@export var miss_color := Color(1.0, 0.3, 0.3)
@export_group("连击数字")
## 每打中一下，连击数字放大到多少倍再弹回去
@export var combo_pop := 1.35
## 连击到多少以上，断掉时才播“碎掉”的动画
@export var combo_break_min := 5
## 连击到多少时数字完全变成下面这个颜色、也最大（中间按比例过渡）
@export var combo_hot_at := 50
@export var combo_hot_color := Color(1.0, 0.85, 0.25)
@export var combo_hot_scale := 1.25
@export_group("积累条")
## 涨了：新涨出来的那一截亮一下的颜色；掉了：掉的那一截红一下的颜色
@export var gauge_gain_color := Color(1.0, 1.0, 1.0, 0.9)
@export var gauge_loss_color := Color(1.0, 0.25, 0.25, 0.9)
## 亮 / 红多久褪掉（秒）
@export var gauge_flash_seconds := 0.3
## 阶段分数线的刻度：还没到的、已经过了的各是什么颜色
@export var gauge_tick_color := Color(1.0, 1.0, 1.0, 0.75)
@export var gauge_tick_done_color := Color(1.0, 1.0, 1.0, 0.25)
## 离下一条分数线还差多少分以内，那条刻度开始跟着拍子闪（越近闪得越亮、伸得越长）
@export var gauge_tick_near := 15
@export var gauge_tick_near_color := Color(1.0, 0.95, 0.4)
@export_group("")

## 积累条本体（main.gd 进游戏时填进来）：刻度要读它的分数线和已经触发了几条
var gauge: Gauge
## 几个小关共用一条积累条时（SectionDef.joins_previous）：现在这一段前面已经有多少分、每两段在哪交接（main.gd 填）
var gauge_offset := 0
var gauge_bounds := PackedInt32Array()

var _gauge_tween: Tween
var _gauge_marks: Control        # 叠在积累条上画刻度和涨跌闪光的一层
var _gauge_last := 0
var _gauge_skip := true          # 下一次数值变化不闪（刚进小关、条被清零）
var _gauge_span := Vector2.ZERO  # 正在闪的那一截：从多少分到多少分
var _gauge_span_gain := true
var _gauge_span_age := 99.0

## ---- 升阶的两步：预备 / 正式（Music.change_planned 是预备，到 commit 那一拍 / Music.fever_started 是正式）----
## 预备：音乐排好了一次大的换段（有过门的升档，或者进 fever）。积累条变成金色、跟着拍子一亮一亮，
##       一道高光从左往右扫，外面一圈金边。一直持续到正式升阶。
## 正式：过门放完、新的一段进来的那一拍。整条白闪一下、弹一下，两圈边框往外扩开，一排小光点往上飞。
##       进的是 fever 的话，之后整条一直是流动的七彩，到 fever 结束。
@export var gauge_stage_fx := true
@export var gauge_prepare_color := Color(1.0, 0.82, 0.25)
@export var gauge_commit_seconds := 0.7
var _prep := false
var _prep_age := 0.0
var _prep_commit := -1.0  # 正式升阶在第几拍
var _prep_fever := false
var _commit_age := 99.0
var _fever_on := false
var _fx_time := 0.0

var _judge_tween: Tween
var _combo_tween: Tween
var _last_combo := 0
var _flash_rect: ColorRect


func _ready() -> void:
	# 全屏闪光用的色块（硬切镜头时白闪一下）
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)
	add_child(_flash_rect)
	move_child(_flash_rect, 0)  # 垫在文字下面
	if gauge_bar:
		_gauge_marks = Control.new()
		_gauge_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gauge_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_gauge_marks.draw.connect(_draw_gauge_marks)
		gauge_bar.add_child(_gauge_marks)
		Music.change_planned.connect(_on_change_planned)
		Music.fever_started.connect(func() -> void:
			_fever_on = true
			if _prep_fever or not _prep:
				_stage_commit())
		Music.fever_ended.connect(func() -> void: _fever_on = false)


func _on_change_planned(kind: String, _id: int, fill_beat: float, commit_beat: float) -> void:
	if not gauge_stage_fx or (kind != "fever" and commit_beat <= fill_beat + 0.01):
		return  # 小的升档（没有过门、下一条线直接换）不算
	_prep = true
	_prep_age = 0.0
	_prep_commit = commit_beat
	_prep_fever = kind == "fever"


func _stage_commit() -> void:
	_prep = false
	_commit_age = 0.0
	pulse_gauge(true)


func _process(delta: float) -> void:
	_gauge_span_age += delta
	_fx_time += delta
	_prep_age += delta
	_commit_age += delta
	if _prep and not _prep_fever and Conductor.playing and Conductor.song_beat >= _prep_commit:
		_stage_commit()
	if gauge_bar and gauge_stage_fx:
		var tint := Color.WHITE
		if _fever_on:
			tint = Color.from_hsv(fposmod(_fx_time * 0.6, 1.0), 0.55, 1.0)
		elif _prep:
			var beat_k := pow(1.0 - fposmod(Conductor.song_beat, 1.0), 2.0) if Conductor.playing else 0.0
			tint = Color.WHITE.lerp(gauge_prepare_color, 0.75) * (1.0 + 0.5 * beat_k)
			tint.a = 1.0
		gauge_bar.self_modulate = tint
	if _gauge_marks:
		_gauge_marks.queue_redraw()


## 刚进一个小关：积累条清零的这一下不算“掉分”，不闪
func reset_gauge() -> void:
	_prep = false
	_fever_on = false
	_gauge_skip = true
	_gauge_span_age = 99.0


## 升阶的特效（预备 / 正式），画在积累条上面那一层（可以画到条的外面）
func _draw_stage_fx(size: Vector2) -> void:
	if not gauge_stage_fx:
		return
	var box := Rect2(Vector2.ZERO, size)
	if _prep:
		var beat := Conductor.song_beat if Conductor.playing else _fx_time * 2.0
		var beat_k := pow(1.0 - fposmod(beat, 1.0), 2.0)
		var appear := clampf(_prep_age / 0.25, 0.0, 1.0)
		# 刚进预备：白闪一下
		if _prep_age < 0.25:
			_gauge_marks.draw_rect(box, Color(1.0, 1.0, 1.0, 0.7 * (1.0 - appear)))
		# 外面一圈金边，跟着拍子胀
		var grow := 3.0 + 5.0 * beat_k
		_gauge_marks.draw_rect(box.grow(grow), Color(gauge_prepare_color, (0.45 + 0.45 * beat_k) * appear), false, 3.0)
		_gauge_marks.draw_rect(box.grow(grow + 5.0), Color(gauge_prepare_color, 0.18 * appear), false, 6.0)
		# 一道斜的高光，每拍从左扫到右
		var x := (fposmod(beat, 1.0) * 1.3 - 0.15) * size.x
		var w := size.x * 0.08
		var x0 := clampf(x - w, 0.0, size.x)
		var x1 := clampf(x + w, 0.0, size.x)
		if x1 > x0:
			_gauge_marks.draw_rect(Rect2(x0, 2.0, x1 - x0, size.y - 4.0), Color(1.0, 1.0, 0.85, 0.5 * appear))
	if _commit_age < gauge_commit_seconds:
		var t := _commit_age / gauge_commit_seconds
		var out := 1.0 - pow(1.0 - t, 3.0)
		var c := Color.from_hsv(fposmod(_fx_time * 0.6, 1.0), 0.5, 1.0) if _fever_on else Color(1.0, 0.95, 0.7)
		_gauge_marks.draw_rect(box, Color(1.0, 1.0, 1.0, 0.85 * pow(1.0 - t, 3.0)))
		# 两圈边框往外扩开
		_gauge_marks.draw_rect(box.grow(4.0 + 34.0 * out), Color(c, 0.8 * (1.0 - t)), false, 4.0 * (1.0 - t) + 1.0)
		_gauge_marks.draw_rect(box.grow(2.0 + 16.0 * out), Color(1.0, 1.0, 1.0, 0.6 * (1.0 - t)), false, 2.0)
		# 一排小光点往上飞
		for i in 14:
			var fx := (i + 0.5) / 14.0
			var lift := (30.0 + 40.0 * fposmod(i * 0.618, 1.0)) * out
			var sway := sin(i * 2.4 + t * 6.0) * 6.0
			var pc := Color.from_hsv(fposmod(fx + _fx_time * 0.4, 1.0), 0.45, 1.0) if _fever_on else c
			_gauge_marks.draw_circle(Vector2(fx * size.x + sway, -lift), 3.5 * (1.0 - t) + 0.5, Color(pc, 1.0 - t))


## 积累条上面那一层：阶段分数线的刻度 + 刚涨 / 刚掉的那一截闪一下
func _draw_gauge_marks() -> void:
	var size := _gauge_marks.size
	var top := gauge_bar.max_value
	_draw_stage_fx(size)
	if top <= 0.0:
		return
	# 刚涨的那一截亮一下、刚掉的那一截红一下，很快褪掉
	if _gauge_span_age < gauge_flash_seconds:
		var k := 1.0 - _gauge_span_age / gauge_flash_seconds
		var c := gauge_gain_color if _gauge_span_gain else gauge_loss_color
		var x0 := size.x * _gauge_span.x / top
		var x1 := size.x * _gauge_span.y / top
		_gauge_marks.draw_rect(Rect2(x0, 4.0, maxf(x1 - x0, 3.0), size.y - 8.0), Color(c, c.a * k * k))
	if gauge == null:
		return
	# 两段交接的地方：和阶段线一样画，快到时也跟着拍子闪
	for b in gauge_bounds:
		var bx := size.x * b / top
		var bc := gauge_tick_color
		var bgrow := 0.0
		var left := b - gauge_offset - gauge.value
		if b <= gauge_offset:
			bc = gauge_tick_done_color
		elif b == gauge_offset + gauge.max_value and left <= gauge_tick_near:
			var bnear := 1.0 - clampf(float(left) / maxf(gauge_tick_near, 1.0), 0.0, 1.0)
			var bbeat := pow(1.0 - fposmod(Conductor.song_beat, 1.0), 2.0)
			bc = gauge_tick_color.lerp(gauge_tick_near_color, 0.5 + 0.5 * bnear)
			bc.a = lerpf(0.7, 1.0, bbeat)
			bgrow = (3.0 + 6.0 * bnear) * (0.4 + 0.6 * bbeat)
		_gauge_marks.draw_line(Vector2(bx, 3.0 - bgrow), Vector2(bx, size.y - 3.0 + bgrow), bc, 3.0 + bgrow * 0.25)
	for i in gauge.events.size():
		var at := gauge.events[i] + gauge_offset
		if at >= top or at in gauge_bounds:
			continue  # 满条那条线就是条的尽头，不用画
		var x := size.x * at / top
		var c := gauge_tick_color
		var grow := 0.0
		if i < gauge.events_fired:
			c = gauge_tick_done_color
		elif i == gauge.events_fired and at - gauge_offset - gauge.value <= gauge_tick_near:
			# 下一条线快到了：跟着拍子闪，越近越亮、伸得越长
			var near := 1.0 - clampf(float(at - gauge_offset - gauge.value) / maxf(gauge_tick_near, 1.0), 0.0, 1.0)
			var beat := pow(1.0 - fposmod(Conductor.song_beat, 1.0), 2.0)
			c = gauge_tick_color.lerp(gauge_tick_near_color, 0.5 + 0.5 * near)
			c.a = lerpf(0.7, 1.0, beat)
			grow = (3.0 + 6.0 * near) * (0.4 + 0.6 * beat)
		_gauge_marks.draw_line(Vector2(x, 3.0 - grow), Vector2(x, size.y - 3.0 + grow), c, 2.0 + grow * 0.25)


## 全屏闪一下
func flash(color: Color = Color.WHITE, strength: float = 0.8, seconds: float = 0.12) -> void:
	_flash_rect.color = Color(color, strength)
	create_tween().tween_property(_flash_rect, "color:a", 0.0, seconds)


func reset() -> void:
	if is_instance_valid(_stamp):
		_stamp.queue_free()
	_stamp = null
	judge_label.text = ""
	judgement_art.clear()
	result_label.visible = false
	milestone_label.clear()


func set_stats(score: int, combo: int) -> void:
	score_label.set_value(score)
	combo_label.set_value(combo)


## 连击数字回到平时的样子（缩放以右边中点为轴，因为它是靠右对齐的）
func _rest_combo() -> void:
	combo_label.pivot_offset = combo_label.size * Vector2(1.0, 0.5)
	combo_label.scale = Vector2.ONE
	combo_label.rotation = 0.0
	combo_label.modulate = Color.WHITE


## 判定文字：按等级上色，带过冲地弹出来（Perfect 弹得最大，Miss 不弹、从小的长回来）；偏早 / 偏晚写在下面的小字里
func show_judgement(result: int, diff_sec: float) -> void:
	if _judge_tween:
		_judge_tween.kill()
	judge_label.text = ""
	judge_label.visible = false
	judgement_art.show_judgement(result, diff_sec)


## 屏幕右侧弹出 "COMBO XX"，停留一会儿后淡出
func show_combo_milestone(combo: int) -> void:
	milestone_label.show_combo(combo)


## 更新积累条
func set_gauge(value: int, max_value: int) -> void:
	if gauge_bar == null:
		return
	gauge_bar.max_value = max_value
	if _gauge_skip:
		_gauge_skip = false
	elif value != _gauge_last:
		_gauge_span = Vector2(minf(value, _gauge_last), maxf(value, _gauge_last))
		_gauge_span_gain = value > _gauge_last
		_gauge_span_age = 0.0
	_gauge_last = value
	if _gauge_tween:
		_gauge_tween.kill()
	_gauge_tween = create_tween()
	_gauge_tween.tween_property(gauge_bar, "value", float(value), 0.15)


## 积累条触发事件时闪一下（满条时闪得更明显）
func pulse_gauge(is_full: bool) -> void:
	if gauge_bar == null:
		return
	gauge_bar.pivot_offset = gauge_bar.size / 2.0
	gauge_bar.scale = Vector2.ONE * (1.25 if is_full else 1.12)
	gauge_bar.modulate = Color(2.0, 2.0, 1.4) if is_full else Color(1.5, 1.5, 1.5)
	var t := gauge_bar.create_tween().set_parallel()
	t.tween_property(gauge_bar, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(gauge_bar, "modulate", Color.WHITE, 0.35)


## 在判定文字的位置临时显示一句提示（调试用）
func show_note(text: String) -> void:
	judgement_art.clear()
	judge_label.visible = true
	judge_label.text = text
	judge_label.modulate = Color.WHITE
	judge_label.scale = Vector2.ONE
	if timing_label:
		timing_label.text = ""
	if _judge_tween:
		_judge_tween.kill()
	_judge_tween = create_tween()
	_judge_tween.tween_property(judge_label, "modulate:a", 0.0, 0.5).set_delay(1.0)


## 屏幕底下那行调试文字（小节、拍数、积累条、快捷键）：只在编辑器里运行时显示，导出的版本里藏起来
func set_debug(text: String) -> void:
	debug_label.visible = OS.has_feature("editor")
	debug_label.text = text


func show_result(judge: Judge) -> void:
	judgement_art.clear()
	judge_label.visible = false
	milestone_label.clear()
	move_child(result_label, -1)  # 盖在积累条、分数这些上面
	result_label.show_result(judge)
	# 最后一下的大字：结算弹进来时飞到结算标题的位置、缩成标题那么大，再把位置让给标题（同一句 ALL CLEAR）
	if is_instance_valid(_stamp):
		var s := _stamp
		_stamp = null
		var view := get_viewport().get_visible_rect().size
		var title_y := view.y / 2.0 - 360.0 + 67.0  # 结算标题的中线（ui/result_widget.tscn：Panel 居中 960×720，Title 在 22～112）
		var t := s.create_tween().set_parallel()
		t.tween_property(s, "position:y", title_y - s.size.y / 2.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(s, "scale", Vector2.ONE * (76.0 / 124.0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(s, "rotation", 0.0, 0.22)
		t.chain().tween_property(s, "modulate:a", 0.0, 0.12)
		t.chain().tween_callback(s.queue_free)


## 整个游戏的最后一下（最后一关的七彩结束音符那一拍）：画面中间砸下一个大字，停到结算弹进来（show_result）
const CANDY := preload("res://assets/fonts/candy_gem/CandyGem.fnt")
var _stamp: Label

func final_pop(text: String) -> void:
	if is_instance_valid(_stamp):
		_stamp.queue_free()
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", CANDY)
	l.add_theme_font_size_override("font_size", 124)
	l.add_theme_color_override("font_color", Color(1.0, 0.92, 1.0))
	l.add_theme_color_override("font_outline_color", Color(0.45, 0.05, 0.6))
	l.add_theme_constant_override("outline_size", 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var view := get_viewport().get_visible_rect().size
	l.size = Vector2(view.x, 200.0)
	l.position = Vector2(0.0, view.y * 0.42 - 100.0)
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2.ONE * 3.2
	l.modulate.a = 0.0
	l.rotation = deg_to_rad(-8.0)
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(l, "modulate:a", 1.0, 0.08)
	t.tween_property(l, "rotation", deg_to_rad(-4.0), 0.16)
	# 砸下来之后轻轻弹一下、再慢慢变大一点，停着等结算
	t.chain().tween_property(l, "scale", Vector2.ONE * 1.1, 0.08)
	t.chain().tween_property(l, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(l, "scale", Vector2.ONE * 1.06, 1.6)
	_stamp = l
	flash(Color.WHITE, 0.9, 0.5)
