@tool
extends "res://scripts/sections/kisa/abduction_section.gd"
## 上升关（第 1 关后面的插曲关）：猫被光柱牵着在屏幕中间往上飞，穿过云层、风暴，突然亮起来，飞进太空，最后进飞碟。
## 玩法是吸猫关原来的（光圈顺着光柱落到猫身上的那一拍按），舞台是 SkyStage。
## 阶段跟着音乐的档位走（Music.tier_changed，在小节线上，和音乐一起变）：
##   0 云层  1 风暴  2 亮起来（欢乐颂）  3 太空  4 飞碟出现（fever）
## 积累条的最后一条线（谱面里 gauge_events 的最后一个）= 结尾：不再出音符，镜头推到飞碟底下，猫被吸进去，然后过关。
## 欢乐颂（16 小节 A A' B A'）要完整唱完一遍：太空在第 9 小节（B 句）进、fever 在第 13 小节（最后一句 A'）进（音乐配置里的 on_bars），
## 最后一条线过了也要等第 16 小节唱完才开始结尾（等的时候积累条不再涨，不会提前满条过关）。

## 结尾的特写一共几拍
@export var finale_beats := 12.0
## 从风暴切到亮起来那一下画面全白、圈看不清：切过去时把接下来几个还没到的音符直接去掉（不算 Miss，0 = 不去）
@export var bright_skip_notes := 3

var _bright_skipped := false

var _clear_at := INF
var _finale_at := INF  # 结尾演出从这一拍开始（这一拍上是结束彩圈）
var _sky: SkyStage
var _accents: NoteAccents  # 音符的重点标记（场景里有 NoteAccents 节点才有）
var _ode_chart := false
var _ode_at := INF  # 欢乐颂进来的那一拍（八分连打的最后一个 = 换段音符）
var _ode_file := ""
var _ode_origin := INF  # 欢乐颂（谱子）从哪一拍起（它的第 1 小节）
var _storm_chart := false
var _run_at := INF  # 八分连打从哪一拍起（还没换上）
## 欢乐颂一遍有几拍（16 小节）：结尾演出不早于它唱完的那一拍
@export var ode_beats := 64.0
## 欢乐颂进来以后空几拍不出音符（换段音符那一拍还在；白光、神圣的和弦，给玩家喘口气）。4 = 一整小节
@export var ode_rest_beats := 4.0
## 进欢乐颂之前的八分连打一共几个（最后一个是换段音符）。8 = 差半拍一小节
@export var ode_run_notes := 8


## 这个小关里换谱子的玩法阶段（配拍编辑器读这个）。"" = 开头的主谱（云层、风暴）；
## "ode" = 亮起来之后：谱子就是欢乐颂的旋律（levels/charts/<关>_<小关>_ode.tres，tools/music_gen/make_tune_charts.py 写的）。
static func chart_phases() -> Array:
	return [
		{"id": "", "name": "云层", "event": 0},
		{"id": "storm", "name": "风暴（末日重金属）", "event": 0, "at": 0.107},
		{"id": "ode", "name": "亮起来之后（欢乐颂的旋律）", "event": 0, "at": 0.508},  # at = 从积累条的多少开始（编辑器按它放那一段的音乐）
	]


## 音乐排好了"亮起来"（升到第 2 档：欢乐颂从那条小节线的第 1 小节起）：谱子在同一条小节线换成欢乐颂的旋律，
## 所以之后每个音符都是旋律里的一个音。没有那份谱就不换，和原来一样。
func _on_change_planned(kind: String, id: int, fill_beat: float, commit_beat: float) -> void:
	if active and kind == "tier" and id == 1:
		_plan_storm(fill_beat)
	if not active or _ode_chart or kind != "tier" or id != 2:
		return
	var main := get_parent().get_parent()
	var file := "res://levels/charts/%s_%d_ode.tres" % [Levels.current_path().get_file().get_basename(),
			int(main.get("_index")) if main and main.get("_index") != null else 0]
	if main == null or not main.get("judge") or not ResourceLoader.exists(file):
		return
	_ode_chart = true
	_ode_at = commit_beat
	_ode_file = file
	# 过渡：换之前的那一小节变成一串八分音符连打，看上去后面还有没完没了的八分音符——打到第 ode_run_notes 个
	# （它正好在欢乐颂进来的那一拍上，是七彩的换段音符）谱子当场换成欢乐颂的，后面那些八分音符全没了。
	# 亮起来要等风暴循环的结尾（音乐那边 on_bars 8），可能还有好几小节：这里先记下，等到离连打还有 LOOKAHEAD_BEATS 拍
	# （Judge 铺音符铺到这么远）才换，那时风暴谱在连打之前的音符都已经铺好了，连打的音符也有完整的提前量（_run_tick）
	_run_at = maxf(commit_beat - (ode_run_notes - 1) * 0.5, ceilf(song_beat() * 2.0 + 2.0) / 2.0)


func _run_tick() -> void:
	if is_inf(_run_at) or song_beat() < _run_at - Judge.LOOKAHEAD_BEATS:
		return
	var main := get_parent().get_parent()
	var run_from := maxf(_run_at, ceilf(song_beat() * 2.0 + 2.0) / 2.0)
	_run_at = INF
	if main == null or not main.get("judge"):
		return
	var d: SectionDef = def.duplicate()
	d.chart = null  # 八分连打不带样子：快进欢乐颂时圈变回普通的
	d.bars = PackedStringArray(["k.k.k.k.k.k.k.k."])
	_swap_chart(main, d, run_from, run_from)


## 音乐排好了进风暴（升到第 1 档：先一小节写好的过门 tr_sky_into_doom，再是末日重金属，从它自己的第 1 小节起）：
## 谱子从过门那条小节线换成风暴谱（levels/charts/<关>_<小关>_storm.tres，tools/music_gen/make_sky_storm_chart.py 写的：
## 过门那一小节 + 风暴 8 小节写了好几遍，跟着音乐的循环）。音乐那边写了 lead_beats，过门离过线至少一小节，新的音符来得及出现。
func _plan_storm(fill_beat: float) -> void:
	if _storm_chart:
		return
	var main := get_parent().get_parent()
	var file := "res://levels/charts/%s_%d_storm.tres" % [Levels.current_path().get_file().get_basename(),
			int(main.get("_index")) if main and main.get("_index") != null else 0]
	if main == null or not main.get("judge") or not ResourceLoader.exists(file):
		return
	_storm_chart = true
	var d: SectionDef = def.duplicate()
	d.chart = load(file) as ChartPattern
	_swap_chart(main, d, fill_beat, fill_beat)


## 换谱：旧谱打到 stop 为止（之前铺好的照常打），新谱的循环从 origin 算
func _swap_chart(main: Node, d: SectionDef, stop: float, origin: float) -> void:
	var keep: Array[NoteData] = []
	for n in notes:
		if n.judged:
			continue
		if n.beat < stop - 0.001:
			keep.append(n)
		elif _sky:
			_drop_ring(n)  # 那条线之后的旧音符不要了：已经在光柱里的圈淡掉
	if stop > origin:
		main.judge.skip_before(stop)
	notes = main.judge.begin_section(int(main.get("_index")), d, Conductor.chart.beats_per_bar, stop, origin)
	for i in keep.size():
		notes.insert(i, keep[i])  # 还没打的旧音符留在这一关的列表里，接着画


## 八分连打打到了换段音符（或者它过去了）：谱子换成欢乐颂的旋律，从欢乐颂进来的那一拍算起
func _ode_tick() -> void:
	if is_inf(_ode_at) or song_beat() < _ode_at - 0.3:
		return
	var hit := song_beat() >= _ode_at + 0.4
	for n in notes:
		if absf(n.beat - _ode_at) < 0.01 and n.judged:
			hit = true
	if not hit:
		return
	var main := get_parent().get_parent()
	var d: SectionDef = def.duplicate()
	d.chart = load(_ode_file) as ChartPattern
	var at := _ode_at
	_ode_at = INF
	_ode_origin = at
	if main and main.get("judge") and d.chart:
		_swap_chart(main, d, at + 0.25, at)
		for n in notes:  # 欢乐颂第一小节空出来：这几拍的音符不出（不算 Miss）
			if not n.judged and n.beat > at + 0.01 and n.beat < at + ode_rest_beats - 0.01:
				n.judged = true
				_drop_ring(n)


## 一个音符不要了：它的圈要是已经在光柱里往下落，让它淡掉（舞台只给判定过的音符收圈，不管的话会停在半空）
func _drop_ring(n: NoteData) -> void:
	var key := n.get_instance_id()
	if _sky._rings.has(key):
		var r: Dictionary = _sky._rings[key]
		_sky._rings.erase(key)
		r.hit = true
		r.t = 0.0
		_sky._fading.append(r)


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_sky = _stage as SkyStage
	Music.tier_changed.connect(_on_tier)
	Music.change_planned.connect(_on_change_planned)
	_accents = get_node_or_null("NoteAccents") as NoteAccents
	_stage.accents = _accents


func _on_enter() -> void:
	if _sky:
		_sky.set_phase(Music.tier)


func _on_tier(new_tier: int, _up: bool) -> void:
	if _sky and active:
		_sky.set_phase(maxi(new_tier, _sky.sky_phase))  # 只往前走，掉档不往回退
		if _sky.sky_phase >= 2 and not _bright_skipped:
			_bright_skipped = true
			_skip_next_notes(bright_skip_notes)


## 把接下来 count 个还没到的音符标成已处理：Judge 跳过它们（不算 Miss、不计判定），舞台也不再画
func _skip_next_notes(count: int) -> void:
	var now := song_beat()
	for n in notes:
		if count <= 0:
			break
		if not n.judged and n.beat > now:
			n.judged = true
			count -= 1
			_drop_ring(n)


func _update_spin(local_beat: float, angle: float) -> void:
	if _accents:
		_accents.notes = own_notes()
	super(local_beat, angle)
	_run_tick()
	_ode_tick()
	if song_beat() >= _finale_at + 0.05:
		_finale_at = INF
		_start_finale()
	if song_beat() >= _clear_at:
		_clear_at = INF
		_fill_gauge_now()


## 这个小关自己有结尾演出：框架不用再加结束音符和过渡空位（见 main.gd 的 _plan_ending）
const OWN_ENDING := true


func _on_gauge_event(index: int, _value: int) -> void:
	if _sky == null or index < gauge_event_values.size():
		return
	# 最后一条线：结尾的预备——谱面接着打到下一条小节线（至少还有两拍），那条线上是结束彩圈，打完才开始结尾演出
	var main := get_parent().get_parent()
	if main and main.get("judge"):
		var bpb: int = Conductor.chart.beats_per_bar
		_finale_at = ceilf((song_beat() + 2.0) / bpb) * bpb
		if not is_inf(_ode_origin):
			_finale_at = maxf(_finale_at, _ode_origin + ode_beats)  # 欢乐颂这一遍唱完再结尾
		if main.get("gauge"):
			(main.gauge as Gauge).gain_scale = 0.0  # 等的这几小节照常打，但积累条不再涨（满了就过关了）
		main.judge.end_notes_at(_finale_at)
		if note_accents:
			note_accents.mark_change(_finale_at, true)
	else:
		_start_finale()


func _start_finale() -> void:
	var main := get_parent().get_parent()
	if main and main.get("judge"):
		main.judge.stop_notes()
	_sky.set_phase(4)
	_sky.finale(finale_beats * Conductor.sec_per_beat())
	_clear_at = song_beat() + finale_beats
	Music.outro()  # 音乐换成这一关写好的结尾段（小关音乐配置里的 "outro"）
	Music.play_sfx("sky_whoosh_up", -4.0, finale_beats * Conductor.sec_per_beat() * 0.55)


func _fill_gauge_now() -> void:
	var main := get_parent().get_parent()
	if main == null or not main.get("gauge"):
		return
	var g: Gauge = main.gauge
	g.gain_scale = 1.0  # 等欢乐颂唱完的时候积累条是停住的（gain_scale = 0）：不先放开，下面这个循环永远填不满，游戏卡死
	while not g.full:
		g.apply(NoteData.Result.PERFECT)
