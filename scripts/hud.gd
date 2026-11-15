extends CanvasLayer

@onready var score_label: Label = $ScoreLabel
@onready var combo_label: Label = $ComboLabel
@onready var judge_label: Label = $JudgeLabel
@onready var debug_label: Label = $DebugLabel
@onready var result_label: Label = $ResultLabel
@onready var milestone_label: Label = $MilestoneLabel
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


func _process(delta: float) -> void:
	_gauge_span_age += delta
	if _gauge_marks:
		_gauge_marks.queue_redraw()


## 刚进一个小关：积累条清零的这一下不算“掉分”，不闪
func reset_gauge() -> void:
	_gauge_skip = true
	_gauge_span_age = 99.0


## 积累条上面那一层：阶段分数线的刻度 + 刚涨 / 刚掉的那一截闪一下
func _draw_gauge_marks() -> void:
	var size := _gauge_marks.size
	var top := gauge_bar.max_value
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
var _milestone_tween: Tween


func reset() -> void:
	judge_label.text = ""
	if timing_label:
		timing_label.text = ""
	if _combo_tween:
		_combo_tween.kill()
	_last_combo = 0
	_rest_combo()
	result_label.visible = false
	if rank_label:
		rank_label.visible = false
	if _milestone_tween:
		_milestone_tween.kill()
	milestone_label.modulate.a = 0.0


func set_stats(score: int, combo: int) -> void:
	score_label.text = "SCORE %d" % score
	var before := _last_combo
	_last_combo = combo
	if combo > before and combo > 1:
		# 打中了：数字跳一下
		if _combo_tween:
			_combo_tween.kill()
		_rest_combo()
		combo_label.text = "%d COMBO" % combo
		var hot := clampf(float(combo) / maxi(combo_hot_at, 1), 0.0, 1.0)
		var rest := Vector2.ONE * lerpf(1.0, combo_hot_scale, hot)
		combo_label.modulate = Color.WHITE.lerp(combo_hot_color, hot)
		combo_label.scale = rest * combo_pop
		_combo_tween = create_tween()
		_combo_tween.tween_property(combo_label, "scale", rest, 0.16) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif combo == 0 and before >= combo_break_min:
		# 连击断了：原来的数字变红、歪着缩小消失
		if _combo_tween:
			_combo_tween.kill()
		_rest_combo()
		combo_label.text = "%d COMBO" % before
		combo_label.modulate = miss_color
		_combo_tween = create_tween().set_parallel()
		_combo_tween.tween_property(combo_label, "scale", Vector2.ONE * 0.6, 0.35).set_ease(Tween.EASE_IN)
		_combo_tween.tween_property(combo_label, "rotation", deg_to_rad(-10.0), 0.35)
		_combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
		_combo_tween.chain().tween_callback(func() -> void:
			combo_label.text = ""
			_rest_combo())
	elif combo <= 1 and (_combo_tween == null or not _combo_tween.is_running()):
		combo_label.text = ""


## 连击数字回到平时的样子（缩放以右边中点为轴，因为它是靠右对齐的）
func _rest_combo() -> void:
	combo_label.pivot_offset = combo_label.size * Vector2(1.0, 0.5)
	combo_label.scale = Vector2.ONE
	combo_label.rotation = 0.0
	combo_label.modulate = Color.WHITE


## 判定文字：按等级上色，带过冲地弹出来（Perfect 弹得最大，Miss 不弹、从小的长回来）；偏早 / 偏晚写在下面的小字里
func show_judgement(result: int, diff_sec: float) -> void:
	var color := Color.WHITE
	var from := judge_pop
	var timing := ""
	match result:
		NoteData.Result.PERFECT:
			judge_label.text = "PERFECT"
			color = perfect_color
			from = perfect_pop
		NoteData.Result.GREAT:
			judge_label.text = "GREAT"
			color = great_color
			timing = "LATE" if diff_sec > 0 else "EARLY"
		NoteData.Result.GOOD:
			judge_label.text = "GOOD"
			color = good_color
			from = lerpf(1.0, judge_pop, 0.5)
			timing = "LATE" if diff_sec > 0 else "EARLY"
		NoteData.Result.MISS:
			judge_label.text = "MISS"
			color = miss_color
			from = 0.8
	judge_label.modulate = color
	judge_label.pivot_offset = judge_label.size / 2.0
	judge_label.scale = Vector2.ONE * from
	if timing_label:
		timing_label.text = timing
		timing_label.modulate = Color(color, 0.85)
	if _judge_tween:
		_judge_tween.kill()
	_judge_tween = create_tween()
	_judge_tween.tween_property(judge_label, "scale", Vector2.ONE, judge_pop_seconds) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_judge_tween.tween_property(judge_label, "modulate:a", 0.0, 0.5).set_delay(0.2)
	if timing_label:
		_judge_tween.parallel().tween_property(timing_label, "modulate:a", 0.0, 0.5).set_delay(0.2)


## 屏幕右侧弹出 "COMBO XX"，停留一会儿后淡出
func show_combo_milestone(combo: int) -> void:
	milestone_label.text = "COMBO %d" % combo
	milestone_label.pivot_offset = milestone_label.size * Vector2(1.0, 0.5)
	milestone_label.scale = Vector2.ONE * 1.6
	milestone_label.modulate.a = 1.0
	if _milestone_tween:
		_milestone_tween.kill()
	_milestone_tween = create_tween()
	_milestone_tween.tween_property(milestone_label, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_milestone_tween.tween_property(milestone_label, "modulate:a", 0.0, 0.4).set_delay(1.0)


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
	judge_label.text = text
	judge_label.modulate = Color.WHITE
	judge_label.scale = Vector2.ONE
	if timing_label:
		timing_label.text = ""
	if _judge_tween:
		_judge_tween.kill()
	_judge_tween = create_tween()
	_judge_tween.tween_property(judge_label, "modulate:a", 0.0, 0.5).set_delay(1.0)


func set_debug(text: String) -> void:
	debug_label.text = text


func show_result(judge: Judge) -> void:
	# 平均偏差：明显偏早 / 偏晚就该去主菜单按 O 重新校准
	var ms := judge.mean_offset() * 1000.0
	var lean := "LATE" if ms > 0.0 else "EARLY"
	result_label.text = "LEVEL CLEAR!\nSCORE %d   MAX COMBO %d\nPERFECT %d   GREAT %d   GOOD %d   MISS %d\nAVG %+.0f ms %s\n\n[R] restart   [Esc] menu" % [
		judge.score, judge.max_combo,
		judge.counts[NoteData.Result.PERFECT],
		judge.counts[NoteData.Result.GREAT],
		judge.counts[NoteData.Result.GOOD],
		judge.counts[NoteData.Result.MISS],
		ms, lean if absf(ms) >= 1.0 else "",
	]
	result_label.visible = true
	if rank_label:
		rank_label.text = judge.rank()
		rank_label.visible = true
