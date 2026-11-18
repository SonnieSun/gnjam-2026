@tool
extends SpinSection
## 电视墙关开场：画面中间一台洗衣机，圆圈收到门框上时按键。
## 单点：舱门里的猫脸原地转一小段。长按时猫脸一直转、越转越快。长按（谱面里音符后面接 "="）：开头那一下打中就得分；
## 中途松手不扣也不加分，但松手那一下有反馈（按完 = PERFECT，早一点 = GOOD，太早 = MISS 的字）。开头漏了才变灰、算失败。
## 推进按小节走，长度是定死的：前一套谱放 early_loops 遍、后一套放 late_loops 遍（默认一共 16 小节），
## 然后是两小节过门：过门第一拍上是一个七彩的换段音符（NoteAccents），打它（漏了也一样）镜头钻进屏幕，
## 去下一个小关的过门音乐就在这两小节里放（Music.enter_early），画面切过去时下一个小关的音乐正好进来。
## 画面和音乐跟着走到第几小节一步步来——先是镜头拉远，再是洗衣机发电、一台台电视亮起来，换段音符前一小节全亮
## （见 TvWallIntroStage）。打得好坏只影响分数和连击，不影响这一段多长、电视什么时候亮。
## 判定用框架的 Judge：长按的开头由 Judge 当普通音符判，按住的部分交给 Judge.begin_hold 盯
## （松手时间和按下用同一个判定时钟，和迪斯科关同一种写法）。
## 3D 画面和可调参数都在 Stage 节点里。编辑器预览里不跑 3D，只显示一行说明。

## 圆圈提前几拍出现
@export var approach_beats := 3.0
## 圆圈从多远收过来（占画面高度的比例）
@export var approach_travel_ratio := 0.45
## 长按没有尾判：开头那一下打中就算成，分数上松早松晚都一样，提前松手不会失败。但松手那一下和打一个音符一样有反馈
## （大字、喵声、画面顶一下）：按完了（什么算按完见 Judge 的 rules）= PERFECT，早一点 = GOOD，再早 = MISS（只是字）。
## 长按按完（可以松手了）时：判定圈闪绿光、响一声的颜色和持续时间（秒）
@export var hold_ok_color := Color(0.35, 1.0, 0.45)
@export var hold_ok_seconds := 0.6
## 判定圈（舱门那一圈）的粗细（像素），颜色用上面的 hold_ok_color
@export var judge_ring_width := 15.0
## 按住时判定圈外面那圈进度的颜色（要和画面里别的颜色都拉开，默认亮粉）
@export var hold_progress_color := SpinSection.HOLD_COLOR
## 进度圈跟着拍子胀缩：每拍往外胀多少（占判定圈半径的比例）
@export_range(0.0, 0.4) var hold_progress_pulse := 0.12
## 进度圈颜色随按住的进度变化：色相一共转多少（0.45 ≈ 粉 → 紫 → 蓝 → 青；0 = 不变色）
@export_range(0.0, 1.0) var hold_progress_hue_shift := 0.45
## 没打中时整个画面红闪的强度
@export_range(0.0, 1.0) var miss_flash := 0.2
## 调试用：自动按键（看演出用，正式玩要关掉）
## 结尾演出（散开 + 镜头钻进屏幕）至少放几拍；实际会凑到下一个小节线
@export var finale_min_beats := 5.0
## 洗衣机的两套谱，都是四小节（16 拍）一个循环，长按的位置是定好的：
##   前半段（音乐还弱的时候）用大关文件里这个小关的 bars：2-2-2-1-1 | 2-2-长按 2 拍 + 空 2 拍
##       长按只有一个：第 2 个八拍的最后四拍（第 4 小节），按 2 拍，后两拍空着（曲子那里是个长音加空拍）。
##   前一套放完 early_loops 遍之后换成下面这套（快的阶段，猫接过主旋律），长按三个：
##       第 1 小节的后两拍、第 2 小节的后两拍、第 4 小节（按 2 拍，空 2 拍）。
## 前一套放几遍、后一套放几遍（一遍四小节 = 曲子的一句）。循环从曲子那一句的开头算起，开头歇的两小节算在
## 第一遍里（所以第一遍只打后两小节）。后一套放完的那条小节线是过门和换段音符。
@export var early_loops := 2
@export var late_loops := 2
@export var late_bars := PackedStringArray([
	"k...k...k======.", "k...k...k======.", "k...k...k...k...", "k========......."])
## 钻进屏幕后切到下一个小关时，用几秒叠化盖住框架的白闪
@export var crossfade_seconds := 0.25
@export var autoplay := false

var _stage: TvWallIntroStage
var _hold_lens := {}  # 鼓谱里的位置（毫拍）-> 长按几拍
var _pattern_len := 0.0
var _pattern_origin := INF
var _late := false  # 已经换成后半段的谱了
var _old_holds := {}  # 换谱时还没打的旧音符 -> 它的长按几拍
var _holding: NoteData
var _failed := {}  # 失败的长按 -> true（尾巴过去之前画成灰色）
var _bolts: Array[Dictionary] = []  # {"to": 电视序号, "age": 秒}
var _flash := 0.0
var _auto_next := 0
var _auto_release_at := -INF
var _auto_down := false
var _finale := false
var _start := INF  # 第一个音符所在的小节线
var _loop_from := INF  # 谱面的循环从哪一拍算起（对着曲子那一句的开头；可以比 _start 早）
var _late_at := INF  # 换成后一套谱的那一拍
var _end_at := INF  # 谱面放完的那一拍 = 过门进来、换段音符所在的那一拍
var _marked := false  # 换段音符标过了
var _music_left := false  # 音乐已经提前换到下一个小关（在放过门）
var _fill_at := INF
var _next_view: SubViewport
var _hold_ok_age := INF  # 长按刚按完过了几秒（INF = 没在闪）
var _early_age := INF  # 长按提前松手过了几秒（白的小闪）


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_stage = get_node_or_null("Stage") as TvWallIntroStage
	if _stage == null:
		_stage = TvWallIntroStage.new()
		add_child(_stage)
	_stage.setup(self)
	# 开场猫飞进洗衣机：一声往下掉的喵正好掉到落进去那一下，落进去"咚"一声
	_stage.cat_flying.connect(func(seconds: float) -> void: Music.play_sfx("catness_down", -5.0, seconds))
	_stage.cat_landed.connect(func() -> void:
		Music.play_sfx("kick", -2.0)
		Music.play_sfx("kitten_mi", -6.0))


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
	# 画面和音乐都跟着「放到第几拍」走，放完开始结尾演出
	var ratio := 1.0 if _finale else _time_ratio()
	# 画面比音乐早一小节走到头：电视全亮之后才来换段音符
	var bpb_f := float(Conductor.chart.beats_per_bar)
	var seen := ratio
	if not _finale and not is_inf(_end_at):
		seen = clampf((song_beat() - _start) / maxf(_end_at - bpb_f - _start, 1.0), 0.0, 1.0)
	_stage.set_progress(seen)
	if not _marked and note_accents and song_beat() >= _end_at - 8.0:
		_marked = true
		note_accents.mark_change(_end_at, true)  # 结束彩圈
	_stage.update(song_beat(), dt)
	if active and not _music_left and song_beat() >= _end_at:
		# 过门的那条小节线：音乐现在就换到下一个小关（先放它的过门），不等画面
		var next_index := Conductor.chart.sections.find(def) + 1
		if next_index > 0 and next_index < Conductor.chart.sections.size():
			_music_left = true
			Music.enter_early(next_index)
	if active:
		Music.override_progress(0.0 if _music_left else ratio)
	# 换段音符判了（打中或漏掉，见 _on_note_judged）就开始结尾演出；万一没判到，过一拍也开始
	if not _finale and song_beat() >= _end_at + 1.0 and _holding == null:
		_start_finale()
	if active and not _late and not _finale and not late_bars.is_empty() and song_beat() >= _late_at - 12.0:
		_switch_to_late()
	if song_beat() >= _fill_at:
		_fill_gauge_now()
	for tv in _stage.take_just_lit():
		_bolts.append({"to": tv, "age": 0.0})
		Music.play_sfx("laser_zap", -12.0)  # 电视亮起来：滋一声
	for i in range(_bolts.size() - 1, -1, -1):
		_bolts[i].age += dt
		if _bolts[i].age > 0.35:
			_bolts.remove_at(i)
	for n: NoteData in _failed.keys():
		if song_beat() > n.beat + hold_beats(n):
			_failed.erase(n)
	_flash = maxf(_flash - dt * 2.5, 0.0)
	_hold_ok_age += dt
	_early_age += dt
	queue_redraw()


func _on_note_judged(note: NoteData, result: int) -> void:
	if _stage == null:
		return
	if not _finale and absf(note.beat - _end_at) < 0.01:
		# 换段音符：打中就猫脸转一下、钻进屏幕；漏了也照样走
		if result != NoteData.Result.MISS:
			_stage.tap()
		_start_finale()
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
		# 按住 = 洗衣机转起来：一声上扬的音效，正好在该松手的时候放完
		Music.play_sfx("riser_1b", -11.0, hold_beats(note) * Conductor.sec_per_beat())
		# 松手的时刻由 Judge 盯（和按下同一个判定时钟）：只用来给反馈
		j.begin_hold(note, note.beat + hold_beats(note), _on_hold_done.bind(note))
	else:
		_stage.tap()


# ---------------- 进度：按小节 ----------------

const MUSIC_LEAD := 6.0

func _time_ratio() -> float:
	if is_inf(_end_at):
		return 0.0
	# 从曲子那一句的开头算，再提前 MUSIC_LEAD 拍：音乐过了档位线要等下一条小节线放一小节过门才换，
	# 提前这么多，换档正好落在谱面换的那条线上（一半 = 第 32 拍：快的那套谱和猫的主旋律一起进）
	return clampf((song_beat() + MUSIC_LEAD - _loop_from) / maxf(_end_at - _loop_from, 1.0), 0.0, 1.0)


# ---------------- 长按 ----------------

## 这个音符是长按的话返回按几拍，否则 0
func hold_beats(n: NoteData) -> float:
	if _old_holds.has(n):
		return _old_holds[n]  # 换谱之前铺的音符：长度按前一套谱算好了
	if _pattern_len <= 0.0 or notes.is_empty():
		return 0.0
	if is_inf(_pattern_origin):
		# 鼓谱从哪一拍开始循环：用第一个音符倒推
		_pattern_origin = notes[0].beat - def.parse_notes(Conductor.chart.beats_per_bar)[0].beat
	var rel := fposmod(n.beat - _pattern_origin, _pattern_len)
	return _hold_lens.get(roundi(rel * 1000.0) % roundi(_pattern_len * 1000.0), 0.0)


## 换成后半段的谱（late_bars）：前一套打到它下一次循环开头的那条线为止，之前铺好的音符照常打照常画，新的一套从那条线起算。
func _switch_to_late() -> void:
	var main := get_parent().get_parent()
	if main == null or not main.get("judge") or notes.is_empty() or _pattern_len <= 0.0:
		return
	if is_inf(_pattern_origin):
		_pattern_origin = notes[0].beat - def.parse_notes(Conductor.chart.beats_per_bar)[0].beat
	var bpb: int = Conductor.chart.beats_per_bar
	var origin := _late_at  # （判定只提前铺 16 拍，所以离那条线 12 拍以内才来换）
	_late = true
	var d: SectionDef = def.duplicate()
	d.chart = null
	d.bars = late_bars
	var keep: Array[NoteData] = []
	var keep_len := {}
	for n in notes:
		if not n.judged and n.beat < origin - 0.001:
			keep.append(n)
			keep_len[n] = hold_beats(n)
	var index: int = main.get("_index") if main.get("_index") != null else 0
	notes = main.judge.begin_section(index, d, bpb, origin, origin)
	for i in keep.size():
		notes.insert(i, keep[i])
	# （def 不换：结尾要靠它在大关里找下一个小关）
	_pattern_len = d.length_beats(bpb)
	_pattern_origin = origin
	_hold_lens = d.hold_lengths(bpb)
	_hold_lens[-1] = 0.0
	_old_holds = keep_len


## 从谱面里找出长按：音符后面跟着的每个 "=" 把它延长一格
func _parse_holds() -> void:
	var bpb: int = Conductor.chart.beats_per_bar
	_pattern_len = def.length_beats(bpb)
	_hold_lens = def.hold_lengths(bpb)  # 老鼓谱的 "=" 或谱面编辑器里的长按
	_hold_lens[-1] = 0.0  # 占个位，表示已经找过了
	if is_inf(_start) and not notes.is_empty() and _pattern_len > 0.0:
		_start = notes[0].beat - def.parse_notes(bpb)[0].beat
		# 谱面的循环要对上曲子的循环（曲子从第 0 拍起，16 拍一句）。框架是从「开头歇完的那条小节线」起铺谱的
		# （这一关歇两小节 = 第 8 拍），那样谱面就比曲子晚了半句：长按落到了下一句的前半。这里把谱面的起点
		# 挪回曲子那一句的开头：歇掉的那几小节算在第一遍里，第一遍从谱面的第 3 小节打起。
		var skip := int(roundf(fposmod(_start, _pattern_len) / bpb))
		var main := get_parent().get_parent() if get_parent() else null
		if skip > 0 and skip < def.bars.size() and def.chart == null and main and main.get("judge"):
			var d: SectionDef = def.duplicate()
			var turned := PackedStringArray()
			for i in def.bars.size():
				turned.append(def.bars[(i + skip) % def.bars.size()])
			d.bars = turned
			var index: int = main.get("_index") if main.get("_index") != null else 0
			notes = main.judge.begin_section(index, d, bpb, _start, _start)
			_hold_lens = d.hold_lengths(bpb)
			_hold_lens[-1] = 0.0
			_pattern_origin = _start
			_loop_from = _start - skip * bpb
		else:
			_loop_from = _start
		_late_at = _loop_from + maxi(early_loops, 1) * _pattern_len
		var late_len := late_bars.size() * float(bpb)
		_end_at = _late_at + maxi(late_loops, 0) * late_len if not late_bars.is_empty() else _late_at


## 正在按住：只更新画面上的进度（画面时间）。按到尾巴 / 松手由 Judge 按判定时钟判，结束时回调 _on_hold_done
func _update_hold() -> void:
	var length := hold_beats(_holding)
	var now := minf(song_beat(), _holding.beat + length)
	_stage.hold_update((now - _holding.beat) / maxf(length, 0.001), (now - _holding.beat) * Conductor.sec_per_beat())
	if main_judge() == null and song_beat() >= _holding.beat + length:
		_finish_hold(true)   # 没有尾判：到尾巴那一拍就算按完，不管手还在不在键上


func _on_hold_done(success: bool, release_beat: float, note: NoteData) -> void:
	if note != _holding:
		return
	# 没有尾判：分数、连击、积累条都不动，但松手那一下和打一个音符一样有判定的样子——大字、命中的喵声、画面顶一下。
	# 尾巴附近松（或者按到尾巴）= PERFECT；早不到 0.8 拍 = GOOD；再早 = MISS（只是字，不扣东西）。
	var early := note.beat + hold_beats(note) - release_beat
	var result := NoteData.Result.PERFECT if success else (NoteData.Result.GOOD if early <= 0.8 else NoteData.Result.MISS)
	var main := get_parent().get_parent() if get_parent() else null
	if main and main.get("hud"):
		main.hud.show_judgement(result, -maxf(early, 0.0) * Conductor.sec_per_beat())
	if main and main.get("hit_meow"):
		main.hit_meow.play(result)
	if result == NoteData.Result.MISS:
		_early_age = 0.0
		_holding = null
		_stage.hold_end(true)
		return
	if main and main.get("screen_fx"):
		main.screen_fx.punch_for(result)
	_finish_hold(true)
	_stage.tap()  # 猫脸再转一下、镜头顶一下


func _finish_hold(success: bool) -> void:
	if not success:
		_failed[_holding] = true
		_flash = 1.0
	else:
		# 「可以松手了」：判定圈闪绿光 + 叮一声（按到尾巴那一拍由 Judge 判定成功时触发）
		_hold_ok_age = 0.0
		Sfx.play("good")
	_holding = null
	_stage.hold_end(success)


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
	draw_lit_target(self, center, radius, Color(hold_ok_color, 0.95), judge_ring_width)  # 默认的判定圈：粗的绿圈
	draw_target_guides(self, center, radius, travel, approach_beats, Callable(), 1.0, 1.0, false)  # 只补空拍的虚线
	for n in own_notes():
		var length := hold_beats(n)
		var ahead := beats_until(n)
		if ahead > approach_beats or n.beat > _end_at + 0.01:
			break  # （换段音符之后的音符不会打到：不画）
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
		# 和第 1 关一样：越靠近判定圈越亮越粗，最后一段带柔光（长按的头圈更粗一点；断掉的长按是灰的、淡一点）
		var base := Color(0.5, 0.5, 0.5) if failed else note_color(n)
		var look := approach_ring_look(k, base, 0.35 if failed else 0.5,
				10.0 if length > 0.0 else 8.0, 16.0 if length > 0.0 else 14.0)
		draw_approach_ring(self, center, radius + k * travel, look)
	if _holding:
		draw_arc(center, radius, 0.0, TAU, 96, hold_progress_color, 7.0)
		_draw_ring_lightning(center, radius)
		_draw_hold_progress(center, radius, _holding)
	if _hold_ok_age < hold_ok_seconds:
		_draw_hold_ok(center, radius)
	if _early_age < 0.25:
		var ek := _early_age / 0.25
		draw_arc(center, radius * (1.0 + 0.12 * ek), 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.8 * (1.0 - ek)), 8.0 * (1.0 - ek) + 2.0)
	for b in _bolts:
		_draw_bolt(center, _stage.tv_screen_pos(b.to), 1.0 - b.age / 0.35)
	if tap_age < 0.15:
		draw_arc(center, radius * (1.0 + tap_age), 0.0, TAU, 64, Color(1, 1, 1, 1.0 - tap_age / 0.15), 6.0)
	if _flash > 0.0:
		draw_rect(Rect2(-size / 2.0, size), Color(1.0, 0.15, 0.2, _flash * miss_flash))


## 长按的拖尾：从头到尾巴的一条半透明带子 + 提示文字
func _draw_hold_tail(center: Vector2, radius: float, travel: float, n: NoteData,
		ahead: float, tail_ahead: float, failed: bool, holding_this: bool) -> void:
	# 长按 = 两个节拍圈 + 中间填满：头圈收到判定圈时按下，尾圈收到判定圈时松手，
	# 两个圈之间整段填上（一直填到尾圈，不再限宽），整个长按有多长一眼看得出来
	var inner := radius + maxf(ahead, 0.0) / maxf(approach_beats, 0.01) * travel
	var tail_t := maxf(tail_ahead, 0.0) / maxf(approach_beats, 0.01)
	var tail_r := minf(radius + tail_t * travel, screen_size().length())
	var c := Color(0.48, 0.48, 0.48) if failed else hold_progress_color
	if tail_r > inner + 0.5:
		c.a = 0.15 if failed else (0.32 if holding_this else 0.22)
		draw_arc(center, (inner + tail_r) / 2.0, 0.0, TAU, 128, c, tail_r - inner)
	if not failed and tail_t <= 1.0:
		# 尾圈：和头圈一样的节拍圈（越靠近判定圈越亮越粗），收到判定圈的那一拍松手
		draw_approach_ring(self, center, tail_r, approach_ring_look(tail_t, hold_progress_color, 0.5, 10.0, 16.0))
	if failed:
		# 只在失败时提示一句
		var pos := center + Vector2(-120.0, -radius * 0.6)
		c.a = 1.0
		draw_string_outline(ThemeDB.fallback_font, pos, "HOLD FAILED", HORIZONTAL_ALIGNMENT_CENTER, 240, 24, 6, Color(0.02, 0.02, 0.04, 0.95))
		draw_string(ThemeDB.fallback_font, pos, "HOLD FAILED", HORIZONTAL_ALIGNMENT_CENTER, 240, 24, c)


## 按住时判定圈外面一圈进度（亮粉色，和画面里别的颜色拉开）：从正上方顺时针填满，满了 = 可以松手。
## 底下的浅色圈上每一拍一个刻度，可以跟着数拍子
func _draw_hold_progress(center: Vector2, radius: float, n: NoteData) -> void:
	var length := maxf(hold_beats(n), 0.001)
	var p := clampf((song_beat() - n.beat) / length, 0.0, 1.0)
	# 和按完时的绿圈一样：就画在判定圈上、一样粗。
	# 跟着拍子：拍点上往外胀、变粗、外面闪一圈光，拍子之间缩回来；颜色随按住的进度从粉慢慢转到青
	var beat_k := pow(1.0 - fposmod(song_beat(), 1.0), 3.0)
	var r := radius * (1.0 + hold_progress_pulse * beat_k)
	var w := 15.0 * (1.0 + 0.5 * beat_k)
	var c := Color.from_hsv(fposmod(hold_progress_color.h - hold_progress_hue_shift * p, 1.0),
			hold_progress_color.s, hold_progress_color.v)
	if beat_k > 0.02:
		draw_arc(center, r * (1.0 + 0.08 * beat_k), 0.0, TAU, 96, Color(c, 0.35 * beat_k), w * 1.8, true)
	draw_arc(center, r, 0.0, TAU, 96, Color(1, 1, 1, 0.18), w, true)
	var beats := int(round(length))
	for b in range(1, beats):
		var ang := -PI / 2.0 + TAU * b / length
		var dir := Vector2.from_angle(ang)
		draw_line(center + dir * (r - w * 0.7), center + dir * (r + w * 0.7), Color(1, 1, 1, 0.55), 2.0, true)
	if p > 0.0:
		draw_arc(center, r, -PI / 2.0, -PI / 2.0 + TAU * p, maxi(8, int(96 * p)), c, w, true)


## 长按按完：判定圈闪一圈绿光往外扩
func _draw_hold_ok(center: Vector2, radius: float) -> void:
	var t := clampf(_hold_ok_age / maxf(hold_ok_seconds, 0.01), 0.0, 1.0)
	var c := Color(hold_ok_color, 1.0 - t)
	draw_arc(center, radius, 0.0, TAU, 96, c, 12.0 * (1.0 - t) + 3.0, true)
	draw_arc(center, radius * (1.0 + t * 0.9), 0.0, TAU, 96, Color(c, c.a * 0.7), 8.0 * (1.0 - t) + 1.0, true)


## 按住时贴着判定圈的一圈细闪电
func _draw_ring_lightning(center: Vector2, radius: float) -> void:
	var phase := floori(Time.get_ticks_msec() / 75.0)
	var pts := PackedVector2Array()
	for i in 65:
		var zig := sin(float(i * 17 + phase * 11)) * 4.0 + (2.0 if i % 2 == 0 else -2.0)
		pts.append(center + Vector2.from_angle(TAU * i / 64.0) * (radius * 1.055 + zig))
	pts[64] = pts[0]
	var c := hold_progress_color.lerp(Color(1.0, 0.8, 0.95), 0.35)
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
	if not is_inf(_end_at):
		switch_at = _end_at + 2.0 * bpb  # 过门两小节，放完的那条线切到下一个小关
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


## 计分用（见 main.gd 的 _compute_stage_weights）：这一段不靠积累条推进，谱子放完就完
const SCORE_BY_PATTERN := true
## 这个小关自己有结尾演出：框架不用再加结束音符和过渡空位（见 main.gd 的 _plan_ending）
const OWN_ENDING := true


## 音符的颜色：长按统一是粉色，点按按音色
func note_color(n: NoteData) -> Color:
	if n.color.a > 0.0:
		return n.color  # 谱子里给这个音符单独指定了颜色
	return hold_progress_color if hold_beats(n) > 0.0 else sound_color(n)


## 辅助线 / 预亮也用同一套颜色（长按的拍子是粉色）
func guide_color(n: NoteData) -> Color:
	return note_color(n)
