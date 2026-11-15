@tool
extends SpinSection
## 拍地球小关（电视机关卡钻进屏幕之后的玩法）：单点 + 连点区间。大关里连着排两段，都用这同一个场景，谱面不同：
##   第 1 段 单点：每拍拍一下。拍到积累条第 1 条线，画面下方升起 MEOW 新闻播报条。
##   第 2 段 单点 + 连点：谱面里的 "r" 后面接 "=" 是一个连点区间（"r=====" = 这几格都是区间）。
##            新闻条一开始就在；积累条每过一条线进场一只猫 meme 纸片；纸片全进场后的下一条线触发结尾。
## 连点区间：区间里什么时候按都行，只数按了几下，区间结束时按次数给档位——
##   每秒 perfect_taps_per_second 下以上 Perfect，每秒 great_taps_per_second 下以上 Great，按了至少 1 下 Good，0 下 Miss。
## 区间不是框架的音符（"r" 对 Judge 来说是休止），由这里自己数次数，再把结果记进 Judge 的成绩
## （各档个数、连击）和积累条，只用它们现成的公开成员，不改框架文件。
## 结尾：不再出音符，镜头拉近地球，猫屁股喷着火飞出来，脚下冒披萨（见 EarthSlapStage），放完把积累条顶满，框架结算。
## 是第几段看它在大关的小关列表里排在第几个用这个场景的。美术是 moumou 的拍地球猫，3D 画面和参数在 Stage 节点里。

## 圆圈提前几拍出现
@export var approach_beats := 1.5
## 圆圈从多远收过来（占画面高度的比例）
@export var approach_travel_ratio := 0.3
## 判定圈半径（占画面高度的比例）
@export var ring_radius_ratio := 0.1
@export_group("连点区间")
## 每秒按到这么多下算 Perfect / Great（乘区间的秒数，向上取整）
@export var perfect_taps_per_second := 5.0
@export var great_taps_per_second := 3.5
## 区间开头提前、结尾延后这么多拍内按的也算数
@export var window_slack_beats := 0.15
@export var window_color := Color("79dfff")
@export_group("结尾")
## 结尾演出放几拍；放完把积累条顶满，框架在下一个小节线结算
@export var ending_beats := 20.0
@export_group("新闻条")
## 新闻条高度（像素）和滚动速度（像素 / 秒）
@export var news_height := 54.0
@export var news_speed := 160.0
## 新闻条左边的台标和滚动的文字
@export var news_label := "MEOW NEWS"
@export var news_text := "MEOW MEOW MEOW!  MEOOOW MEOW.  MEOW?  MEOW MEOW MEOW MEOW...  MEEEOW!!  "
@export_group("")
## 没打中时整个画面红闪的强度
@export_range(0.0, 1.0) var miss_flash := 0.2
## 切到下一段时用几秒叠化盖住框架的白闪
@export var crossfade_seconds := 0.25
## 调试用：自动按键（看演出用，正式玩要关掉）
@export var autoplay := false

const RESULT_NAMES := {
	NoteData.Result.PERFECT: "PERFECT", NoteData.Result.GREAT: "GREAT",
	NoteData.Result.GOOD: "GOOD", NoteData.Result.MISS: "MISS",
}

var _stage: EarthSlapStage
var _phase := 0  # 第几段（0 起）
var _windows: Array[Vector2] = []  # 鼓谱里的连点区间：x = 开始（相对鼓谱开头的拍数），y = 几拍
var _pattern_len := 0.0
var _pattern_origin := INF  # 鼓谱从全曲第几拍开始循环
var _win_start := INF  # 现在这个（或下一个）区间的开始 / 结束（全曲拍数）
var _win_end := INF
var _win_count := 0
var _win_done_until := -INF  # 这一拍之前的区间都结算过了
var _win_text := ""
var _win_text_color := Color.WHITE
var _win_text_age := 99.0
var _memes_in := 0
var _ending_from := INF
var _fill_at := INF
var _news := 0.0  # 新闻条升起来多少（0~1）
var _news_on := false
var _scroll := 0.0
var _flash := 0.0
var _auto_next := 0
var _auto_release := false
var _auto_tap_at := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_stage = get_node_or_null("Stage") as EarthSlapStage
	if _stage == null:
		_stage = EarthSlapStage.new()
		add_child(_stage)
	_stage.setup(self)


func _on_enter() -> void:
	if def == null or _stage == null:
		return
	# 第几段：前面有几个小关也用这个场景
	_phase = 0
	var sections: Array = Conductor.chart.sections if Conductor.chart else []
	for s: SectionDef in sections:
		if s == def:
			break
		if s.scene == def.scene:
			_phase += 1
	_parse_windows()
	_news_on = _phase >= 1
	if _news_on:
		_news = 1.0


func _on_exit() -> void:
	# 下一段还是拍地球：把最后一帧留在最上面很快淡掉，盖住框架切关时的白闪
	var sections: Array = Conductor.chart.sections if Conductor.chart else []
	var i := sections.find(def)
	if i >= 0 and i + 1 < sections.size() and (sections[i + 1] as SectionDef).scene == def.scene:
		_leave_crossfade()


func hit_position(_note: NoteData = null) -> Vector2:
	return _stage.focus_screen_pos() if _stage else Vector2.ZERO


func hit_radius() -> float:
	return ring_radius_ratio * screen_size().y


func _update_spin(local: float, _angle: float) -> void:
	center_on_screen()
	if _stage == null:
		return
	var dt := get_process_delta_time()
	var now := song_beat()
	if not is_inf(_ending_from):
		_stage.set_ending((now - _ending_from) / maxf(ending_beats, 0.01))
		if now >= _fill_at:
			_fill_gauge_now()
	else:
		_update_window(now)
		if autoplay:
			_autoplay(now)
	# 连点区间里猫挥得飞快，平时一拍挥一下
	_stage.update(dt, local, 0.5 if _in_window(now) else 1.0, 0.0)
	_news = move_toward(_news, 1.0 if _news_on and is_inf(_ending_from) else 0.0, dt * 2.5)
	_scroll += news_speed * dt
	_flash = maxf(_flash - dt * 2.5, 0.0)
	_win_text_age += dt
	queue_redraw()


func _on_note_judged(_note: NoteData, result: int) -> void:
	if _stage == null:
		return
	if result == NoteData.Result.MISS:
		_stage.miss()
		_flash = 1.0
	else:
		_stage.slap(0.0)


## 空按（附近没有音符）：在连点区间里就算一下
func _on_empty_hit() -> void:
	if _stage == null or not is_inf(_ending_from):
		return
	var b := Conductor.input_beat()
	if b >= _win_start - window_slack_beats and b <= _win_end + window_slack_beats:
		_win_count += 1
		_stage.slap(0.15)


func _on_gauge_event(index: int, _value: int) -> void:
	if index < 1:
		return
	if _phase == 0:
		_news_on = true
		return
	if _stage == null:
		return
	if _memes_in < _stage.meme_total():
		_memes_in += 1
		_stage.show_memes(_memes_in)
	else:
		_start_ending()


# ---------------- 连点区间 ----------------

## 从谱面里找出连点区间："r" 后面每个 "=" 把区间延长一格（"r" 自己也算一格）
func _parse_windows() -> void:
	_windows.clear()
	var bpb: int = Conductor.chart.beats_per_bar
	_pattern_len = def.length_beats(bpb)
	for bar_i in def.bars.size():
		var s := def.bars[bar_i]
		var cell := float(bpb) / maxi(s.length(), 1)
		var i := 0
		while i < s.length():
			var run := 0
			if s[i] == "r":
				while i + 1 + run < s.length() and s[i + 1 + run] == "=":
					run += 1
				_windows.append(Vector2(bar_i * bpb + i * cell, (run + 1) * cell))
			i += 1 + run


## 现在是不是在连点区间里
func _in_window(now: float) -> bool:
	return now >= _win_start and now <= _win_end


## 区间要按几下才是 Perfect / Great
func window_taps(beats: float, per_second: float) -> int:
	return maxi(ceili(beats * Conductor.sec_per_beat() * per_second - 0.001), 1)


func _update_window(now: float) -> void:
	if _windows.is_empty() or _pattern_len <= 0.0:
		return
	if is_inf(_pattern_origin):
		# 鼓谱从哪一拍开始循环：框架进小关后先空 rest_bars_on_switch 个小节
		_pattern_origin = def.start_beat + Conductor.chart.rest_bars_on_switch * Conductor.chart.beats_per_bar
	# 现在这个区间过完了：结算
	if not is_inf(_win_end) and now > _win_end + window_slack_beats:
		_finish_window()
	# 找下一个还没结算的区间
	if is_inf(_win_start):
		var loop_i := floori(maxf(now - _pattern_origin, 0.0) / _pattern_len)
		for k in 2:
			for w in _windows:
				var start := _pattern_origin + (loop_i + k) * _pattern_len + w.x
				if start + w.y > now and start >= _win_done_until - 0.001:
					_win_start = start
					_win_end = start + w.y
					_win_count = 0
					return


## 区间结束：按次数给档位，记进成绩、连击、积累条
func _finish_window() -> void:
	var beats := _win_end - _win_start
	var result: int = NoteData.Result.MISS
	if _win_count >= window_taps(beats, perfect_taps_per_second):
		result = NoteData.Result.PERFECT
	elif _win_count >= window_taps(beats, great_taps_per_second):
		result = NoteData.Result.GREAT
	elif _win_count >= 1:
		result = NoteData.Result.GOOD
	_win_done_until = _win_end
	_win_start = INF
	_win_end = INF
	_win_text = "%s  x%d" % [RESULT_NAMES.get(result, ""), _win_count]
	_win_text_color = result_color(result)
	_win_text_age = 0.0
	if result == NoteData.Result.MISS:
		_stage.miss()
		_flash = 1.0
	else:
		_stage.slap(1.0 if result == NoteData.Result.PERFECT else 0.5)
	var main := get_parent().get_parent() if get_parent() else null
	if main == null or not main.get("judge"):
		return
	var j: Judge = main.judge
	j.counts[result] += 1
	j.stage_counts[result] += 1
	if result == NoteData.Result.MISS:
		j.combo = 0
	else:
		j.combo += 1
		j.max_combo = maxi(j.max_combo, j.combo)
	j.stats_changed.emit()
	if main.get("hud"):
		main.hud.show_judgement(result, 0.0)
	if main.get("gauge") and not main.get("editing"):
		main.gauge.apply(result)


# ---------------- 结尾 ----------------

func _start_ending() -> void:
	if not is_inf(_ending_from):
		return
	_ending_from = song_beat()
	_fill_at = _ending_from + ending_beats
	_win_start = INF
	_win_end = INF
	if _auto_release:
		_send_hit(false)
		_auto_release = false
	_stage.start_ending()
	var main := get_parent().get_parent() if get_parent() else null
	if main and main.get("judge"):
		main.judge.stop_notes()


## 把积累条顶满，框架会在下一个小节线结算
func _fill_gauge_now() -> void:
	_fill_at = INF
	var main := get_parent().get_parent() if get_parent() else null
	if main == null or not main.get("gauge"):
		return
	var g: Gauge = main.gauge
	while not g.full:
		g.apply(NoteData.Result.PERFECT)


# ---------------- 画 ----------------

func _draw() -> void:
	if def == null:
		return
	var size := screen_size()
	if Engine.is_editor_hint():
		draw_string(ThemeDB.fallback_font, Vector2(-300.0, 0.0), "拍地球小关：3D 画面不在编辑器里预览",
				HORIZONTAL_ALIGNMENT_CENTER, 600.0, 20)
		return
	if _stage == null:
		return
	if is_inf(_ending_from):
		_draw_rings(size)
	if _news > 0.0:
		_draw_news(size)
	if _flash > 0.0:
		draw_rect(Rect2(-size / 2.0, size), Color(1.0, 0.15, 0.2, _flash * miss_flash))


func _draw_rings(size: Vector2) -> void:
	var center := hit_position()
	var radius := hit_radius()
	var travel := approach_travel_ratio * size.y
	var now := song_beat()
	draw_arc(center, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.9), 3.0)
	for n in notes:
		if n.judged:
			continue
		var ahead := beats_until(n)
		if ahead > approach_beats:
			break
		var k := clampf(ahead / approach_beats, 0.0, 1.0)
		var c := sound_color(n)
		c.a = 1.0 - k * 0.6
		draw_arc(center, radius + k * travel, 0.0, TAU, 96, c, 5.0)
	# 连点区间：一条宽带子收过来；到了之后判定圈外面一圈倒计时，中间显示按了几下 / 要几下
	if not is_inf(_win_start):
		var ahead := _win_start - now
		var beats := _win_end - _win_start
		var need := window_taps(beats, perfect_taps_per_second)
		if ahead > 0.0 and ahead <= approach_beats:
			var k := ahead / approach_beats
			var inner := radius + k * travel
			var outer := minf(radius + (ahead + beats) / approach_beats * travel, inner + size.y * 0.09)
			draw_arc(center, (inner + outer) / 2.0, 0.0, TAU, 96, Color(window_color, 0.3), outer - inner)
			draw_arc(center, inner, 0.0, TAU, 96, Color(window_color, 1.0 - k * 0.5), 7.0)
			_label(center + Vector2(0.0, radius + 34.0), "TAP x%d !" % need, window_color)
		elif ahead <= 0.0:
			var left := clampf((_win_end - now) / maxf(beats, 0.01), 0.0, 1.0)
			draw_arc(center, radius * 1.18, 0.0, TAU, 64, Color(0.1, 0.09, 0.19, 0.7), 10.0)
			draw_arc(center, radius * 1.18, -PI / 2.0, -PI / 2.0 + TAU * left, 64, window_color, 10.0)
			var col := Color(1.0, 0.9, 0.3) if _win_count >= need else Color(1, 1, 1)
			_label(center + Vector2(0.0, radius + 40.0), "TAP TAP TAP!  %d / %d" % [_win_count, need], col, 26)
	if _win_text_age < 0.8 and (is_inf(_win_start) or _win_start - now > 0.0):
		_label(center + Vector2(0.0, -radius - 20.0), _win_text, _win_text_color, 26)
	if tap_age < 0.15:
		draw_arc(center, radius * (1.0 + tap_age), 0.0, TAU, 64, Color(1, 1, 1, 1.0 - tap_age / 0.15), 6.0)


func _label(pos: Vector2, text: String, col: Color, font_size := 22) -> void:
	var p := pos + Vector2(-160.0, 0.0)
	draw_string_outline(ThemeDB.fallback_font, p, text, HORIZONTAL_ALIGNMENT_CENTER, 320, font_size, 6, Color(0.02, 0.02, 0.06, 0.95))
	draw_string(ThemeDB.fallback_font, p, text, HORIZONTAL_ALIGNMENT_CENTER, 320, font_size, col)


## 画面下方的新闻播报条：左边台标，右边一行字从右往左滚
func _draw_news(size: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var top := size.y / 2.0 - news_height * _news
	var left := -size.x / 2.0
	draw_rect(Rect2(left, top, size.x, news_height), Color(0.08, 0.1, 0.35, 0.95))
	draw_rect(Rect2(left, top, size.x, 4.0), Color(1.0, 0.85, 0.2))
	var fs := int(news_height * 0.5)
	var text_w := maxf(font.get_string_size(news_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, 1.0)
	var x := left - fposmod(_scroll, text_w)
	var y := top + news_height * 0.68
	while x < size.x / 2.0:
		draw_string(font, Vector2(x, y), news_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
		x += text_w
	var label_w := font.get_string_size(news_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 28.0
	draw_rect(Rect2(left, top, label_w, news_height), Color(0.85, 0.12, 0.2))
	draw_string(font, Vector2(left + 14.0, y), news_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))


func _leave_crossfade() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(img)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	get_tree().root.add_child(layer)
	var t := layer.create_tween()
	t.tween_property(rect, "modulate:a", 0.0, crossfade_seconds)
	t.tween_callback(layer.queue_free)


# ---------------- 调试：自动按键 ----------------

func _autoplay(now: float) -> void:
	if _auto_release:
		_send_hit(false)
		_auto_release = false
		return
	while _auto_next < notes.size() and notes[_auto_next].judged:
		_auto_next += 1
	if _auto_next < notes.size() and beats_until(notes[_auto_next]) <= 0.0:
		_auto_next += 1
		_send_hit(true)
		_auto_release = true
	elif _in_window(now) and Time.get_ticks_msec() * 0.001 >= _auto_tap_at:
		# 连点区间里每秒按 10 下左右
		_auto_tap_at = Time.get_ticks_msec() * 0.001 + 0.1
		_send_hit(true)
		_auto_release = true


func _send_hit(pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = Judge.HIT_ACTION
	e.pressed = pressed
	Input.parse_input_event(e)
