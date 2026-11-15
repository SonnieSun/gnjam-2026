@tool
extends SpinSection
## 电视墙关开场：画面中间一台洗衣机，圆圈收到门框上时按键。
## 单点：舱门里的猫脸原地转一小段。长按时猫脸一直转、越转越快。长按（谱面里音符后面接 "="）：按住到尾巴才算成，中途松手变灰失败、不能补按。
## 每完整按完一次长按推进一步：前 3 次镜头拉远，之后每次洗衣机发电、亮两台电视，直到全部亮起（见 TvWallIntroStage）。
## 判定用框架的 Judge：长按的开头由 Judge 当普通音符判，按住的部分交给 Judge.begin_hold 盯
## （松手时间和按下用同一个判定时钟，和迪斯科关同一种写法）。
## 3D 画面和可调参数都在 Stage 节点里。编辑器预览里不跑 3D，只显示一行说明。

## 圆圈提前几拍出现
@export var approach_beats := 3.0
## 圆圈从多远收过来（占画面高度的比例）
@export var approach_travel_ratio := 0.45
## 长按离尾巴不到这么多拍时松手也算成
@export var hold_release_grace := 0.3
## 没打中时整个画面红闪的强度
@export_range(0.0, 1.0) var miss_flash := 0.2
## 调试用：自动按键（看演出用，正式玩要关掉）
## 结尾演出（散开 + 镜头钻进屏幕）至少放几拍；实际会凑到下一个小节线
@export var finale_min_beats := 5.0
## 钻进屏幕后切到下一个小关时，用几秒叠化盖住框架的白闪
@export var crossfade_seconds := 0.25
@export var autoplay := false

var _stage: TvWallIntroStage
var _hold_lens := {}  # 鼓谱里的位置（毫拍）-> 长按几拍
var _pattern_len := 0.0
var _pattern_origin := INF
var _holding: NoteData
var _failed := {}  # 失败的长按 -> true（尾巴过去之前画成灰色）
var _bolts: Array[Dictionary] = []  # {"to": 电视序号, "age": 秒}
var _flash := 0.0
var _auto_next := 0
var _auto_release_at := -INF
var _auto_down := false
var _finale := false
var _fill_at := INF
var _next_view: SubViewport


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_stage = get_node_or_null("Stage") as TvWallIntroStage
	if _stage == null:
		_stage = TvWallIntroStage.new()
		add_child(_stage)
	_stage.setup(self)


func hit_position(_note: NoteData = null) -> Vector2:
	return _stage.ring_center() if _stage else Vector2.ZERO


func hit_radius() -> float:
	return _stage.ring_radius() if _stage else 80.0


func _update_spin(_local_beat: float, _angle: float) -> void:
	center_on_screen()
	if _stage == null:
		return
	var dt := get_process_delta_time()
	if _hold_lens.is_empty():
		_parse_holds()
	if autoplay and not _finale:
		_autoplay()
	if _holding:
		_update_hold()
	_stage.update(song_beat(), dt)
	if song_beat() >= _fill_at:
		_fill_gauge_now()
	for tv in _stage.take_just_lit():
		_bolts.append({"to": tv, "age": 0.0})
	for i in range(_bolts.size() - 1, -1, -1):
		_bolts[i].age += dt
		if _bolts[i].age > 0.35:
			_bolts.remove_at(i)
	for n: NoteData in _failed.keys():
		if song_beat() > n.beat + hold_beats(n):
			_failed.erase(n)
	_flash = maxf(_flash - dt * 2.5, 0.0)
	queue_redraw()


func _on_note_judged(note: NoteData, result: int) -> void:
	if _stage == null:
		return
	var is_hold := hold_beats(note) > 0.0
	if result == NoteData.Result.MISS:
		_flash = 1.0
		if is_hold:
			_failed[note] = true
		return
	if is_hold:
		var j := main_judge()
		if j == null:
			_stage.tap()
			return
		_holding = note
		_stage.hold_begin()
		j.begin_hold(note, note.beat + hold_beats(note), hold_release_grace, _on_hold_done.bind(note))
	else:
		_stage.tap()


# ---------------- 长按 ----------------

## 这个音符是长按的话返回按几拍，否则 0
func hold_beats(n: NoteData) -> float:
	if _pattern_len <= 0.0 or notes.is_empty():
		return 0.0
	if is_inf(_pattern_origin):
		# 鼓谱从哪一拍开始循环：用第一个音符倒推
		_pattern_origin = notes[0].beat - def.parse_notes(Conductor.chart.beats_per_bar)[0].beat
	var rel := fposmod(n.beat - _pattern_origin, _pattern_len)
	return _hold_lens.get(roundi(rel * 1000.0) % roundi(_pattern_len * 1000.0), 0.0)


## 从谱面里找出长按：音符后面跟着的每个 "=" 把它延长一格
func _parse_holds() -> void:
	var bpb: int = Conductor.chart.beats_per_bar
	_pattern_len = def.length_beats(bpb)
	_hold_lens = def.hold_lengths(bpb)  # 老鼓谱的 "=" 或谱面编辑器里的长按
	_hold_lens[-1] = 0.0  # 占个位，表示已经找过了


## 正在按住：只更新画面上的进度（画面时间）。按到尾巴 / 松手由 Judge 按判定时钟判，结束时回调 _on_hold_done
func _update_hold() -> void:
	var length := hold_beats(_holding)
	var now := minf(song_beat(), _holding.beat + length)
	_stage.hold_update((now - _holding.beat) / maxf(length, 0.001), (now - _holding.beat) * Conductor.sec_per_beat())


func _on_hold_done(success: bool, _release_beat: float, note: NoteData) -> void:
	if note == _holding:
		_finish_hold(success)


func _finish_hold(success: bool) -> void:
	if not success:
		_failed[_holding] = true
		_flash = 1.0
	_holding = null
	_stage.hold_end(success)
	if _stage.finale_pending:
		_start_finale()


# ---------------- 表现 ----------------

func _draw() -> void:
	if def == null:
		return
	var size := screen_size()
	if Engine.is_editor_hint():
		draw_string(ThemeDB.fallback_font, Vector2(-300.0, 0.0), "电视墙开场：3D 画面不在编辑器里预览，F5 运行后按 4",
				HORIZONTAL_ALIGNMENT_CENTER, 600.0, 20)
		return
	if _stage == null:
		return
	if _finale:
		return
	var center := hit_position()
	var radius := maxf(hit_radius(), 1.0)
	var travel := approach_travel_ratio * size.y
	draw_focus(self, center, radius)
	draw_lit_target(self, center, radius, Color(1.0, 0.62, 0.18, 0.95), 4.0)
	draw_target_guides(self, center, radius, travel, approach_beats, Callable(), 1.0, 1.0, false)  # 只补空拍的虚线
	for n in own_notes():
		var length := hold_beats(n)
		var ahead := beats_until(n)
		if ahead > approach_beats:
			break
		var tail_ahead := ahead + length
		var failed := _failed.has(n)
		var holding_this := n == _holding
		if length > 0.0 and tail_ahead >= 0.0 and (not n.judged or holding_this or failed):
			_draw_hold_tail(center, radius, travel, n, ahead, tail_ahead, failed, holding_this)
		if n.judged and not failed:
			continue
		if failed and tail_ahead < 0.0:
			continue
		var k := maxf(ahead, 0.0) / maxf(approach_beats, 0.01)
		var c := Color(0.5, 0.5, 0.5) if failed else sound_color(n)
		c.a = clampf(1.0 - k * 0.6, 0.0, 1.0)
		draw_arc(center, radius + k * travel, 0.0, TAU, 96, c, 8.0 if length > 0.0 else 5.0)
	if _holding:
		draw_arc(center, radius, 0.0, TAU, 96, sound_color(_holding), 7.0)
		_draw_ring_lightning(center, radius)
	for b in _bolts:
		_draw_bolt(center, _stage.tv_screen_pos(b.to), 1.0 - b.age / 0.35)
	if tap_age < 0.15:
		draw_arc(center, radius * (1.0 + tap_age), 0.0, TAU, 64, Color(1, 1, 1, 1.0 - tap_age / 0.15), 6.0)
	if _flash > 0.0:
		draw_rect(Rect2(-size / 2.0, size), Color(1.0, 0.15, 0.2, _flash * miss_flash))


## 长按的拖尾：从头到尾巴的一条半透明带子 + 提示文字
func _draw_hold_tail(center: Vector2, radius: float, travel: float, n: NoteData,
		ahead: float, tail_ahead: float, failed: bool, holding_this: bool) -> void:
	var inner := radius + maxf(ahead, 0.0) / maxf(approach_beats, 0.01) * travel
	var outer := radius + tail_ahead / maxf(approach_beats, 0.01) * travel
	outer = minf(outer, inner + screen_size().y * 0.07)  # 带子不要太宽，免得盖住猫头
	var c := Color(0.48, 0.48, 0.48) if failed else sound_color(n)
	if outer > inner + 0.5:
		c.a = 0.15 if failed else (0.3 if holding_this else 0.2)
		draw_arc(center, (inner + outer) / 2.0, 0.0, TAU, 96, c, outer - inner)
		c.a = 0.75
		draw_arc(center, outer, 0.0, TAU, 96, c, 3.0)
	var seconds := (tail_ahead if holding_this else hold_beats(n)) * Conductor.sec_per_beat()
	var label := "HOLD FAILED" if failed else "HOLD %.1fs" % seconds
	var pos := center + Vector2(-120.0, -radius * 0.6)
	c.a = 1.0
	draw_string_outline(ThemeDB.fallback_font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 240, 24, 6, Color(0.02, 0.02, 0.04, 0.95))
	draw_string(ThemeDB.fallback_font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 240, 24, c)


## 按住时贴着判定圈的一圈细闪电
func _draw_ring_lightning(center: Vector2, radius: float) -> void:
	var phase := floori(Time.get_ticks_msec() / 75.0)
	var pts := PackedVector2Array()
	for i in 65:
		var zig := sin(float(i * 17 + phase * 11)) * 4.0 + (2.0 if i % 2 == 0 else -2.0)
		pts.append(center + Vector2.from_angle(TAU * i / 64.0) * (radius * 1.055 + zig))
	pts[64] = pts[0]
	var c := sound_color(_holding).lerp(Color(0.55, 0.9, 1.0), 0.45)
	c.a = 0.2
	draw_polyline(pts, c, 8.0, true)
	c.a = 0.95
	draw_polyline(pts, c, 2.5, true)
	draw_polyline(pts, Color(0.92, 1.0, 1.0, 0.85), 1.0, true)


## 洗衣机通到刚亮起来的电视的一道闪电
func _draw_bolt(from: Vector2, to: Vector2, alpha: float) -> void:
	var phase := floori(Time.get_ticks_msec() / 50.0)
	var side := (to - from).orthogonal().normalized()
	var pts := PackedVector2Array()
	for i in 13:
		var k := i / 12.0
		var off := sin(float(i * 31 + phase * 7)) * 14.0 * sin(k * PI)
		pts.append(from.lerp(to, k) + side * off)
	draw_polyline(pts, Color(0.55, 0.9, 1.0, 0.25 * alpha), 10.0, true)
	draw_polyline(pts, Color(0.75, 0.95, 1.0, 0.95 * alpha), 3.0, true)
	draw_polyline(pts, Color(1.0, 1.0, 1.0, alpha), 1.2, true)


# ---------------- 调试：自动按键 ----------------

func _autoplay() -> void:
	if _auto_down and song_beat() >= _auto_release_at:
		_send_hit(false)
		_auto_down = false
	while _auto_next < notes.size() and notes[_auto_next].judged:
		_auto_next += 1
	if not _auto_down and _auto_next < notes.size() and beats_until(notes[_auto_next]) <= 0.0:
		var n := notes[_auto_next]
		_auto_next += 1
		_send_hit(true)
		_auto_down = true
		_auto_release_at = n.beat + maxf(hold_beats(n), 0.05)


func _send_hit(pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = Judge.HIT_ACTION
	e.pressed = pressed
	Input.parse_input_event(e)


# ---------------- 结尾：钻进屏幕，接到下一个小关 ----------------

## 全亮之后那次长按按完：不再出音符，下一个小关的画面先在一块看不见的画布上跑起来，贴到中间那台电视的屏幕上；
## 镜头钻进屏幕、画面铺满全屏的那一拍（小节线）让框架切到真正的下一个小关。
## Judge 和 Gauge 是主场景里框架的节点，这里只调它们现成的方法（和迪斯科结尾同一种做法）。
func _start_finale() -> void:
	_finale = true
	if _auto_down:
		_send_hit(false)
		_auto_down = false
	var main := get_parent().get_parent() if get_parent() else null
	if main and main.get("judge"):
		main.judge.stop_notes()
	var bpb: int = Conductor.chart.beats_per_bar
	var now := song_beat()
	var switch_at := ceilf((now + finale_min_beats) / bpb) * bpb
	var live: Texture2D = null
	var next := _next_def()
	if next and next.scene:
		# 下一个小关提前跑起来（没有音符），画面和待会儿真正切过去时是同一拍的同一个场景
		_next_view = SubViewport.new()
		_next_view.size = Vector2i(screen_size())
		_next_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_next_view)
		next.start_beat = switch_at
		var preview := next.scene.instantiate() as SpinSection
		var none: Array[NoteData] = []
		preview.setup(next, none)
		_next_view.add_child(preview)
		preview.enter()
		live = _next_view.get_texture()
		_fill_at = switch_at - 1.5
	_stage.start_finale(now, switch_at, live)


func _next_def() -> SectionDef:
	var sections: Array = Conductor.chart.sections
	var i := sections.find(def)
	return sections[i + 1] if i >= 0 and i + 1 < sections.size() else null


## 把积累条顶满，框架会在下一个小节线切到下一个小关
func _fill_gauge_now() -> void:
	_fill_at = INF
	var main := get_parent().get_parent() if get_parent() else null
	if main == null or not main.get("gauge"):
		return
	var g: Gauge = main.gauge
	while not g.full:
		g.apply(NoteData.Result.PERFECT)


func _on_exit() -> void:
	if _finale:
		_leave_crossfade()


## 切走的那一刻把最后一帧画面留在最上面很快淡掉，盖住框架切关时的白闪
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


## 调试：按 T 直接跳到「电视全亮」（只在调试版里有效），方便测后面钻进屏幕那一段
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_T and OS.is_debug_build():
		if _stage and not _finale:
			_stage.skip_to_all_lit()


## 计分用（见 main.gd 的 _compute_stage_weights）：这一段不靠积累条推进，谱子放一遍就完，按一遍的音符数算它占这关满分的比例
const SCORE_BY_PATTERN := true
