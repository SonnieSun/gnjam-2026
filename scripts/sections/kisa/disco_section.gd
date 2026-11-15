@tool
extends "res://scripts/sections/kisa/ring_section.gd"
## 迪斯科猫砂盆关卡：判定玩法和 Sonnie 的缩圈段落完全一样（圈往中间收，和白色轮廓重合时按）。
## 画面是铺满屏幕的 3D isometric 房间，猫在猫砂盆里，按键就转。
## 舞台由通用的积累条推进（见 scripts/core/gauge.gd）：
##   积累条越满镜头拉得越远；
##   第 1 个事件（disco.tscn 里配的是 20 分）星星灯掉下来、场景变亮；
##   第 2 个事件（40 分）迪斯科灯球掉下来；
##   第 3 个事件（现在没配）2D 跳舞猫进场。想加就在 disco.tscn 的 gauge_events 里多填一个分数。
## 具体演出都在 KisaDiscoStage 里，这里只负责把积累条的事件和「现在第几拍」告诉它。
## 示例原来自带的“成功 +1 / Miss -1”进度和“猫离开猫砂盆漂移”阶段现在不用了（代码还留在 KisaDiscoStage 里）。
## 长按音符是按“谱面只放一遍”写的，现在鼓谱是循环的，长按暂时不要用。
##
## 长按音符（只有这个关卡认）：谱面里在音符后面接一串 "="，比如 "k=======s......."
## = 底鼓按下后按住 8 格（2 拍）再松手。Sonnie 的谱面解析把 "=" 当休止，所以开头那一下
## 仍由 Judge 正常判定；按住的部分交给 Judge.begin_hold 盯（松手时间和按下用同一个判定时钟）：
## 每按住满 1 拍进度 +1，按到尾巴再 +1，中途提前松手算一次 Miss（进度 -1）。长按期间不要排别的音符。长按不计入 HUD 的分数和连击。
##
## 蓝色圆盘在 disco.tscn 里把 disc_color 设成全透明藏掉了，只留白色判定圈。
## 编辑器预览里仍显示原来的 2D 画面。只支持一个目标圆。

## 房间场景（里面要有 Stars/*、DiscoBall、DriftPath/* 这些定位点）
@export var room: PackedScene = preload("res://stages/disco/disco_room.tscn")
## 长按可以提前多少拍松手还算按完
@export var hold_release_grace := 0.3
## 长按条带的透明度
@export_range(0.0, 1.0) var hold_band_alpha := 0.4
## 往里收的圈：刚出现时多不透明（越靠近判定圈越亮，到判定圈时是完全不透明）
@export_range(0.0, 1.0) var ring_alpha := 0.5
## 往里收的圈多粗：刚出现时、到判定圈时（像素）
@export var ring_width := 8.0
@export var ring_width_near := 14.0
## 判定圈和收圈画多大（乘在 target_radius 上），画成和地上光波一样透视的扁椭圆
@export var judge_scale := 1.5
## 音轨淡入淡出的快慢（越大越快）
@export var layer_fade := 3.0
## 结尾那段镜头（猫站起来、飞碟来接、镜头降下去）一共几拍；放完才切到吸猫小关
@export var finale_beats := 16.0
## 切到吸猫小关时，旧画面叠化淡出用几秒
@export var crossfade_seconds := 1.2
## 拆完房子上路后，先空滑几拍才来第一个水果
@export var road_quiet_beats := 8.0
## 水果路滑到圆台（舞台）时歇多久再出音符（秒，大概值：会对到最近的小节线上）
@export var plaza_rest_seconds := 5.0

@export_group("结尾接着玩吸猫")
## 结尾镜头放完后不切小关，直接用降下来的那架飞碟接着玩吸猫（玩法和吸猫小关一样）。关掉 = 结尾放完就过关
@export var abduction_after_finale := true
## 吸猫这一段的鼓谱（打中 8 下猫就被吸进去，整关结束；没吸进去之前鼓谱循环）
@export var abduction_bars := PackedStringArray(["................", "k.......s.......", "k.......s.......", "k.......s.......", "k.......s.......", "................", "................", "k.......s.......", "k.......s.......", "k.......s.......", "k.......s.......", "................", "................", "k.......s.......", "k.......s.......", "k.......s.......", "k.......s.......", "................", "................"])
## 光圈提前几拍从飞碟出发
@export var abduction_approach_beats := 3.0
## 飞碟接手后先空几拍再出第一个光圈
@export var abduction_quiet_beats := 2.0
## 猫平时慢慢自转（度 / 秒）
@export var abduction_idle_spin := 30.0
## 每按一下键猫快速转一整圈，用几秒
@export var abduction_press_turn_seconds := 0.3

var _spin_cat: KisaSpinCat3D
var _stage: KisaDiscoStage
var _hold_ends := {}  # NoteData -> 长按结束的拍数（绝对拍数）
var _holds_parsed := false
var _holding: NoteData  # 正在按住的那个长按音符
var _hold_ticks := 0  # 这次长按已经给过几次「按住满 1 拍」的进度
var _circle_pos := Vector2.ZERO
var _road: DiscoRoad
var _layer_gain := PackedFloat32Array()  # 每条分轨现在的音量（0~1）
var _fill_at := INF  # 结尾镜头放到这一拍：接着玩吸猫（或者把积累条顶满过关）
var _abduct: AbductionStage  # 结尾之后接着玩的吸猫舞台（嵌在迪斯科的 3D 世界里）
var _abduct_gauge_from := 0  # 开始吸猫时积累条的值


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	for cat in _cats:
		cat.visible = false
	_spin_cat = KisaSpinCat3D.new()
	_spin_cat.full_screen = true
	_spin_cat.backdrop = room
	_spin_cat.listen_input = true  # 每次按键都转，按住一直转，不管有没有打中
	_spin_cat.position = target_position(0)
	_spin_cat.z_index = -1  # 3D 画面垫在最底下，缩圈和判定圈画在它上面
	add_child(_spin_cat)
	# 舞台节点放在 disco.tscn 里（这样参数能在 Inspector 里调）；没有就现做一个
	_stage = get_node_or_null("Stage") as KisaDiscoStage
	if _stage == null:
		_stage = KisaDiscoStage.new()
		add_child(_stage)
	_stage.setup(_spin_cat)
	_stage.external = true  # 阶段和镜头交给积累条
	# 房间之后的几段：拆房子、路上撞水果、圆台、结尾（场景里有 Road 节点就用它，参数能在 Inspector 调）
	_road = get_node_or_null("Road") as DiscoRoad
	if _road == null:
		_road = DiscoRoad.new()
		add_child(_road)
	_road.setup(_spin_cat, _stage)
	_road.beat_guides = beat_guides and draws_own_notes()
	_road.guide_every = guide_every
	# 配乐从只有房间的背景节拍开始
	_layer_gain.resize(DiscoMusic.LAYERS.size())
	_layer_gain.fill(0.0)
	_layer_gain[DiscoMusic.ROOM_BASE] = 1.0
	for i in _layer_gain.size():
		DiscoMusic.set_layer(i, _layer_gain[i])


func _update_spin(local_beat: float, angle: float) -> void:
	super(local_beat, angle)
	if _stage == null:
		return
	if not _holds_parsed:
		_parse_holds()
	_stage.external_zoom = _zoom_for_gauge()
	_stage.external_drift = _drift_for_gauge()
	_stage.update(song_beat())
	_road.update(song_beat(), own_notes())
	_update_layers()
	if song_beat() >= _fill_at:
		_fill_at = INF
		if abduction_after_finale:
			_start_abduction()
		else:
			_fill_gauge_now()
	if _abduct:
		_abduct.update(song_beat(), own_notes(), abduction_approach_beats)
	# 判定圈（和缩过来的圈、命中特效）跟着猫走
	_circle_pos = _stage.ring_screen_offset()
	if _holding:
		_update_hold()


## 判定圈的位置：跟着 3D 猫在屏幕上的位置（编辑器预览里没有 3D 猫，就用场景里摆的）
func target_position(i: int) -> Vector2:
	if _abduct:
		return _abduct.hit_screen_offset()
	return _circle_pos if _stage else super(i)


func hit_radius() -> float:
	return _abduct.ring_screen_radius() if _abduct else super()


## 结尾镜头放完：飞碟已经停在猫头顶了，直接接着玩吸猫。吸猫舞台嵌进这里的 3D 世界，接手这架飞碟，
## 鼓谱换成吸猫的；积累条接着涨，涨满就过关。
func _start_abduction() -> void:
	var saucer := _road.hand_over_saucer()
	if saucer == null:
		_fill_gauge_now()
		return
	_abduct = AbductionStage.new()
	_abduct.embedded = true
	_abduct.repeat_rounds = false  # 只吸一次：猫被吸进去，整关就结束
	_abduct.beat_guides = beat_guides and draws_own_notes()
	_abduct.guide_every = guide_every
	_abduct.idle_spin_speed = abduction_idle_spin
	_abduct.press_spin_speed = 0.0
	_abduct.press_full_turn = true
	_abduct.hit_spin_time = abduction_press_turn_seconds
	_abduct.absorb_started.connect(_on_absorb_started)
	_abduct.absorbed.connect(_on_absorbed)
	_abduct.progress_changed.connect(_on_abduct_progress)
	add_child(_abduct)
	# 两边的飞碟摆在各自坐标里的同一个相对位置：差多少就整体平移多少
	_abduct.embed(_spin_cat.world, _spin_cat.camera, saucer, _road.saucer_position - _abduct.saucer_position)
	_rest_until(song_beat() + abduction_quiet_beats, abduction_bars)
	# 积累条不再按判定加减，改成跟着吸猫的进度走：吸到第几格，就涨到剩下那段的几成，
	# 吸满那一下正好到顶（full 先保持 true，免得框架提前过关；猫真被吸进去时再正式满条）
	var g := _main_gauge()
	if g:
		g.full = true
		_abduct_gauge_from = g.value


## 吸猫进度变了：积累条从开始吸猫时的值涨到满条，按吸了几格算
func _on_abduct_progress(value: int, needed: int) -> void:
	var g := _main_gauge()
	if g == null:
		return
	var p := float(value) / maxi(needed, 1)
	g.value = _abduct_gauge_from + roundi((g.max_value - _abduct_gauge_from) * p)
	g.changed.emit(g.value, g.max_value)


## 攒满了，猫开始往上吸：不再出音符
func _on_absorb_started() -> void:
	var main := get_parent().get_parent()
	if main and main.get("judge"):
		main.judge.stop_notes()


## 猫被吸进飞碟：顶满积累条，框架在下一个小节线结算过关
func _on_absorbed() -> void:
	var g := _main_gauge()
	if g:
		g.full = false
	_fill_gauge_now()


func _main_gauge() -> Gauge:
	var main := get_parent().get_parent()
	if main == null or not main.get("gauge"):
		return null
	return main.gauge


## 积累条触发事件（分数线在 disco.tscn 根节点的 gauge_events 里）：
##   1 星星灯  2 灯球  3 跳舞猫  4 猫离开猫砂盆漂移
##   5 拆房子上路  6 舞池地板  7 霓虹网格  8 圆台  9 结尾镜头（飞碟来接）
func _on_gauge_event(index: int, _value: int) -> void:
	if _stage == null:
		return
	if index <= 4:
		_stage.enter_stage(index)
	elif index == 5:
		# 拆房子转镜头这段不出音符，让玩家歇一下；上路的第一个水果落在歇完那个小节的第 1 拍
		var resume := _rest_until(song_beat() + _road.unfold_beats + road_quiet_beats, DiscoMusic.road_bars())
		_road.start(song_beat(), resume)
	elif index == 6 or index == 7:
		_road.set_floor(index - 5)
	elif index == 9:
		_start_finale()
	elif index == 8:
		# 滑到圆台这段先歇一会儿（不直接接着出音符），歇完在小节线上接着打路上那套鼓谱
		var bpb: int = Conductor.chart.beats_per_bar
		var rest := plaza_rest_seconds / Conductor.sec_per_beat()
		_rest_until(song_beat() + rest - bpb * 0.5, DiscoMusic.road_bars())
		_road.enter_plaza(song_beat())


## 积累条满了，框架会在下一个小节线切到吸猫小关。正常流程里结尾镜头早就开始了（第 9 个事件），
## 这里只管没放过结尾的情况（比如调试时按 N 直接跳关）。
func _on_gauge_filled() -> void:
	if _road:
		_road.finale(2.0)


## 漂移走到路线的哪里：第 4 个事件开始漂，到第 5 个事件（拆房子）前漂完
func _drift_for_gauge() -> float:
	if gauge_event_values.size() < 5:
		return 0.0
	var a := float(gauge_event_values[3])
	var b := float(gauge_event_values[4])
	return clampf((progress() * gauge_max - a) / maxf(b - a, 1.0), 0.0, 1.0)


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
	if _abduct:
		_abduct.judge(note, result)
		return
	if _road and (result == NoteData.Result.PERFECT or result == NoteData.Result.GREAT):
		_road.plaza_perfect()
	if _road and _road.uses_fruit(note):
		_road.fruit_judged(note, result)
	if result == NoteData.Result.MISS:
		_stage.add_miss()
		return
	_stage.add_success()
	if _hold_ends.has(note):
		var j := main_judge()
		if j == null:
			return
		_holding = note
		_hold_ticks = 0
		j.begin_hold(note, _hold_ends[note], hold_release_grace, _on_hold_done.bind(note))


## 按住的过程中：每按住满 1 拍 +1（拍数按判定时钟算）
func _update_hold() -> void:
	_give_hold_ticks(Conductor.input_beat())


func _give_hold_ticks(up_to_beat: float) -> void:
	var end: float = _hold_ends[_holding]
	var ticks := floori(minf(up_to_beat, end) - _holding.beat)
	while _hold_ticks < ticks:
		_hold_ticks += 1
		_stage.add_success()


## Judge 说这个长按结束了：按到尾巴（或在宽限内松手）+1 收工；提前松手 -1
func _on_hold_done(success: bool, release_beat: float, note: NoteData) -> void:
	if note != _holding:
		return
	_give_hold_ticks(release_beat)
	if success:
		_stage.add_success()
	else:
		_stage.add_miss()
	_holding = null


## 从谱面里找出长按：音符后面跟着的每个 "=" 把它延长一格
func _parse_holds() -> void:
	_holds_parsed = true
	# 长按来自老鼓谱的 "="，或谱面编辑器里给音符设的长按拍数
	var holds := def.hold_lengths(Conductor.chart.beats_per_bar)
	for key: int in holds:
		var beat := def.start_beat + key / 1000.0
		for n in notes:
			if is_equal_approx(n.beat, beat):
				_hold_ends[n] = beat + holds[key]


func _draw() -> void:
	# 不调用 ring_section 的画法：自己画白色判定圈和往里收的圈，好单独调圈的透明度
	if def and _stage:
		# 视觉焦点：判定点（猫）周围保持原样，外面压暗。房间 / 圆台里是透视的椭圆，路上和吸猫时是正圆
		var ring_phase := _abduct == null and (_road == null or _road.rings_visible(song_beat()))
		if ring_phase:
			draw_focus(self, target_position(0), target_radius * judge_scale, _stage.ring_squash())
		else:
			draw_focus(self, target_position(0), hit_radius() * 1.4)
	_draw_rings()
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
		var c := HOLD_COLOR  # 长按统一是粉色
		var center := hit_position(n)
		if tail_r > head_r:
			c.a = hold_band_alpha
			_ellipse(center, (head_r + tail_r) / 2.0, c, (tail_r - head_r) * judge_scale)
		c.a = ring_alpha
		_ellipse(center, tail_r, c, 6.0)
		if holding_this:
			_ellipse(center, target_radius, c, 10.0)


## 离判定点还有 ahead 拍的圈现在多大（和 ring_section 画圈的算法一致）
func _ring_radius(ahead: float, from_r: float) -> float:
	var t := minf(ahead / approach_beats, 1.0)
	return maxf(target_radius + t * (from_r - target_radius), 4.0)


## 白色判定圈 + 往里收的圈（画法同 ring_section，只是收的圈乘上 ring_alpha）
func _draw_rings() -> void:
	if def == null or _abduct:
		return  # 吸猫那一段的光圈是 3D 的，由吸猫舞台自己画
	var show_judge := _road == null or _road.rings_visible(song_beat())
	var squash := _stage.ring_squash() if _stage else 1.0
	for k in _cats.size():
		if show_judge:
			draw_lit_target(self, target_position(k), target_radius, Color.WHITE, 3.0, squash, judge_scale)
	var from_r := start_radius
	if from_r <= 0.0:
		from_r = screen_size().length() / 2.0 + 40.0
	if show_judge:
		# 辅助线：和缩圈一样是透视压扁的椭圆；路上的水果音符另有 3D 辅助线（DiscoRoad），这里不算
		var ring_notes: Array[NoteData] = []
		for n in own_notes():
			if not (_road and _road.uses_fruit(n)):
				ring_notes.append(n)
		for g in guide_list(approach_beats, ring_notes, false):  # 音符就是缩圈，只补空拍的虚线
			var r := maxf(target_radius + clampf(g.a, 0.0, 1.0) * (from_r - target_radius), 4.0)
			BeatGuides.draw_ring(self, target_position(0), r, BeatGuides.look(g), 4.0, squash, judge_scale)
	for n in own_notes():
		if _road and _road.uses_fruit(n):
			continue  # 路上的音符用水果表现，不画圈
		if n.judged:
			continue
		var ahead := beats_until(n)
		if ahead > approach_beats:
			break
		var t := ahead / approach_beats  # 1 = 刚出现，0 = 重合
		var r := maxf(target_radius + t * (from_r - target_radius), 4.0)
		# 越靠近判定圈越亮、越粗、稍微偏白，最后一段外面再加一圈柔光
		var k := 1.0 - clampf(t, 0.0, 1.0)
		var c := guide_color(n).lerp(Color.WHITE, k * k * 0.3)
		c.a = clampf((1.0 - t) / 0.15, 0.0, 1.0) * lerpf(ring_alpha, 1.0, pow(k, 1.5))
		var w := lerpf(ring_width, ring_width_near, k)
		if k > 0.5:
			_ellipse(hit_position(n), r, Color(c, c.a * (k - 0.5) * 0.6), w * 2.6)
		_ellipse(hit_position(n), r, c, w)


## 按镜头透视画「平放在地上的圆」：横向半径 r × judge_scale，竖向再乘镜头压扁比例
func _ellipse(center: Vector2, r: float, color: Color, width: float) -> void:
	var squash := _stage.ring_squash() if _stage else 1.0
	var rx := r * judge_scale
	var pts := PackedVector2Array()
	for i in 97:
		var a := i * TAU / 96.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * rx * squash))
	draw_polyline(pts, color, width, true)


## 分层配乐跟着积累条走：分数过了第 n 条线，第 n 个元素的音轨就开；Miss 掉回线以下就关。
## 房间里用房间那一套（背景节拍 + 星星灯 / 灯球 / 跳舞猫 / 漂移），拆房子以后换成路上那一套
## （背景节拍 + 上路 / 舞池 / 网格 / 圆台），结尾再叠上飞碟那一条。
func _update_layers() -> void:
	if _layer_gain.is_empty() or DiscoMusic.music() == null:
		return
	var v := progress() * gauge_max
	var on_road := _road.phase != DiscoRoad.Phase.ROOM
	var want := PackedFloat32Array()
	want.resize(_layer_gain.size())
	want.fill(0.0)
	want[DiscoMusic.ROAD_BASE if on_road else DiscoMusic.ROOM_BASE] = 1.0
	for n in 4:
		var event_i := n + (4 if on_road else 0)  # 第几条分数线（0 起）
		var layer := (DiscoMusic.ROAD_BASE if on_road else DiscoMusic.ROOM_BASE) + 1 + n
		if event_i < gauge_event_values.size() and v >= gauge_event_values[event_i]:
			want[layer] = 1.0
	if _road.phase == DiscoRoad.Phase.FINALE:
		want[DiscoMusic.UFO] = 1.0
	var k := 1.0 - exp(-layer_fade * get_process_delta_time())
	for i in _layer_gain.size():
		if not is_equal_approx(_layer_gain[i], want[i]):
			_layer_gain[i] = lerpf(_layer_gain[i], want[i], k)
			if absf(_layer_gain[i] - want[i]) < 0.01:
				_layer_gain[i] = want[i]
			DiscoMusic.set_layer(i, _layer_gain[i])


## 这一小关结束（切到吸猫）：配乐只留路上的背景节拍和飞碟那一条
func _on_exit() -> void:
	super()
	if _road and _road.phase == DiscoRoad.Phase.FINALE:
		_leave_crossfade()
	for i in DiscoMusic.LAYERS.size():
		DiscoMusic.set_layer(i, 1.0 if i == DiscoMusic.ROAD_BASE or i == DiscoMusic.UFO else 0.0)


## 结尾镜头开始：不再出音符（这一段只看演出），放完 finale_beats 拍后把积累条顶满，
## 让框架在下一个小节线切到吸猫小关。Judge 和 Gauge 是主场景里 Sonnie 的节点，这里只调它们现成的方法。
func _start_finale() -> void:
	_road.finale(finale_beats * Conductor.sec_per_beat())
	_fill_at = song_beat() + finale_beats - 2.0
	var main := get_parent().get_parent()
	if main and main.get("judge"):
		main.judge.stop_notes()


func _fill_gauge_now() -> void:
	_fill_at = INF
	var main := get_parent().get_parent()
	if main == null or not main.get("gauge"):
		return
	var g: Gauge = main.gauge
	while not g.full:
		g.apply(NoteData.Result.PERFECT)


## 切走的那一刻把最后一帧画面留在最上面慢慢淡掉，新小关从底下透出来（叠化），盖住框架的白闪
func _leave_crossfade() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(img)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	get_tree().root.add_child(layer)
	var t := layer.create_tween()
	t.tween_property(rect, "modulate:a", 0.0, crossfade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(layer.queue_free)


## 歇一会儿：从现在到 until_beat 之后的第一个小节线都不出音符，那个小节线起鼓谱从头接着来。
## 返回恢复出音符的那一拍。做法是让 Judge 把这一小关的鼓谱从那一拍重新开始（调它现成的 begin_section）。
func _rest_until(until_beat: float, bars := PackedStringArray()) -> float:
	var main := get_parent().get_parent()
	var bpb: int = Conductor.chart.beats_per_bar
	var resume := ceilf(until_beat / bpb) * bpb
	if main == null or not main.get("judge"):
		return resume
	var index: int = main.get("_index") if main.get("_index") != null else 0
	var d: SectionDef = def
	if not bars.is_empty():
		# 换一份鼓谱接着打（只换这一小关自己用的副本，不改原来的谱面资源）
		d = def.duplicate()
		d.bars = bars
	notes = main.judge.begin_section(index, d, bpb, song_beat(), resume)
	_hold_ends.clear()
	_holding = null
	return resume


## 音符圈和辅助线的颜色：长按统一粉色，其余按 ring_section 的那套
func guide_color(note: NoteData) -> Color:
	if not _holds_parsed and def:
		_parse_holds()
	return HOLD_COLOR if _hold_ends.has(note) else super(note)
