@tool
extends "res://scripts/sections/kisa/abduction_section.gd"
## 上升关（第 1 关后面的插曲关）：猫被光柱牵着在屏幕中间往上飞，穿过云层、风暴，突然亮起来，飞进太空，最后进飞碟。
## 玩法是吸猫关原来的（光圈顺着光柱落到猫身上的那一拍按），舞台是 SkyStage。
## 阶段跟着音乐的档位走（Music.tier_changed，在小节线上，和音乐一起变）：
##   0 云层  1 风暴  2 亮起来（欢乐颂）  3 太空  4 飞碟出现（fever）
## 积累条的最后一条线（谱面里 gauge_events 的最后一个）= 结尾：不再出音符，镜头推到飞碟底下，猫被吸进去，然后过关。

## 结尾的特写一共几拍
@export var finale_beats := 12.0
## 从风暴切到亮起来那一下画面全白、圈看不清：切过去时把接下来几个还没到的音符直接去掉（不算 Miss，0 = 不去）
@export var bright_skip_notes := 3

var _bright_skipped := false

var _clear_at := INF
var _sky: SkyStage
var _accents: NoteAccents  # 音符的重点标记（场景里有 NoteAccents 节点才有）
var _ode_chart := false


## 这个小关里换谱子的玩法阶段（配拍编辑器读这个）。"" = 开头的主谱（云层、风暴）；
## "ode" = 亮起来之后：谱子就是欢乐颂的旋律（levels/charts/<关>_<小关>_ode.tres，tools/music_gen/make_tune_charts.py 写的）。
static func chart_phases() -> Array:
	return [
		{"id": "", "name": "云层、风暴", "event": 0},
		{"id": "ode", "name": "亮起来之后（欢乐颂的旋律）", "event": 0, "at": 0.5},  # at = 从积累条的多少开始（编辑器按它放那一段的音乐）
	]


## 音乐排好了"亮起来"（升到第 2 档：欢乐颂从那条小节线的第 1 小节起）：谱子在同一条小节线换成欢乐颂的旋律，
## 所以之后每个音符都是旋律里的一个音。没有那份谱就不换，和原来一样。
func _on_change_planned(kind: String, id: int, _fill_beat: float, commit_beat: float) -> void:
	if not active or _ode_chart or kind != "tier" or id != 2:
		return
	var main := get_parent().get_parent()
	var file := "res://levels/charts/%s_%d_ode.tres" % [Levels.current_path().get_file().get_basename(),
			int(main.get("_index")) if main and main.get("_index") != null else 0]
	if main == null or not main.get("judge") or not ResourceLoader.exists(file):
		return
	_ode_chart = true
	var d: SectionDef = def.duplicate()
	d.chart = load(file) as ChartPattern
	var keep: Array[NoteData] = []
	for n in notes:
		if n.judged:
			continue
		if n.beat < commit_beat - 0.001:
			keep.append(n)
		elif _sky:
			_drop_ring(n)  # 旧谱里那条小节线之后的音符不要了：已经在光柱里的圈淡掉
	notes = main.judge.begin_section(int(main.get("_index")), d, Conductor.chart.beats_per_bar, commit_beat, commit_beat)
	for i in keep.size():
		notes.insert(i, keep[i])  # 还没打的旧音符留在这一关的列表里，接着画


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
	if song_beat() >= _clear_at:
		_clear_at = INF
		_fill_gauge_now()


func _on_gauge_event(index: int, _value: int) -> void:
	if _sky == null or index < gauge_event_values.size():
		return
	# 最后一条线：结尾
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
	while not g.full:
		g.apply(NoteData.Result.PERFECT)
