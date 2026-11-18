@tool
extends "res://scripts/sections/pizza_section.gd"
## 太空版披萨猫（第 4 大关第二段，整个游戏的最后一个小关）。披萨、猫、水面、圆环都沿用披萨猫关的场景，
## 这里管四件事：
##   1. 从上一段「太空打飞机」接过来的黑幕（SpaceShooterScore.handoff）一开始落出屏幕。
##   2. 康康舞曲三个阶段各一套谱（开头 / 四阶下行 / 高潮），在音乐换段的那条小节线上换。
##   3. 分镜：不再是「侧面慢慢绕到正面」一个镜头，而是一张镜头表，在小节线上切（见 SHOTS 和各阶段的镜头顺序）。
##      九宫格、万花筒这些全屏特效也跟着镜头走（不再按积累条切，大关文件里这个小关的 fx_cues 留空）。
##   4. 结尾：积累条满了之后虫洞从前方飞过来，两小节七彩大连按（超光速蓄力，洞壁上掠过前面几关的画面），
##      连按完的那一拍冲出虫洞——框架在同一拍砸下 ALL CLEAR（main.gd 的 _final_pop），一小节后进结算。

# ---------------------------------------------------------------- 谱面

## 康康舞曲在这一段有三个阶段，谱面跟着换（都在音乐换的那条小节线上换，之前铺好的音符照常打完）：
##   开头（另一段旋律）      大关文件里这个小关的 bars：四小节一句，都在底鼓上
##   四阶下行（进度一半起）  阶段 steps：一小节四下重音（旋律的四个往下走的音），下一小节跟旋律跑一小串八分
##   高潮（经典旋律，fever） 阶段 peak：跟经典旋律的节奏（哒哒哒 哒 哒），句尾三下重拍
## 后两套是谱面文件 levels/charts/<大关>_<小关>_steps.tres / _peak.tres，配拍编辑器按 chart_phases() 列出来、能直接改；
## 没有文件时用下面的 mid_bars / peak_bars。
## 每个阶段多长在大关文件里（这个小关的 gauge_events 65 / 98 + phase_gain / fever_gain）：四阶下行大约放一遍（8 小节），
## 高潮从过线算起大约 14 小节。谱子变密了要把对应的 gain 按比例调小，阶段长度才不变。
@export var mid_bars := PackedStringArray(["k...k...k...k...", "s.s.s...k.......", "k...k...k...k...", "s.s.s.s.k......."])
@export var peak_bars := PackedStringArray(["k.k.k...s...k...", "k.k.k...s...k...", "k.k.k.k.s...s...", "k.k.k...s.......",
		"k.k.k...s...k...", "k.k.k...s...k...", "k.k.k.k.s...s...", "k...k...k......."])
var _next_bars := PackedStringArray()
var _next_phase := ""
var _next_at := INF


## 这个小关里换谱子的玩法阶段（配拍编辑器读这个）
static func chart_phases() -> Array:
	return [
		{"id": "", "name": "开头（康康舞曲的另一段）", "event": 0},
		{"id": "steps", "name": "四阶下行", "event": 1},
		{"id": "peak", "name": "高潮（经典旋律，fever）", "event": 2},
	]


# ---------------------------------------------------------------- 结尾（框架读这几个常量，见 main.gd 的 _plan_ending）

## 积累条满了之后，下一条乐句线上来这么多拍的八分大连按，连按完的那一拍是七彩结束音符
const ENDING_HOLD_BEATS := 8.0
## 是连按不是长按：八分音符由这里自己铺（_lay_ending），框架只给最后那一下
const ENDING_MASH := true
## 大连按从第几拍起（框架给；INF = 还没到）
var ending_from := INF
## 按到这么多下算蓄满（一共 16 个八分）
@export var mash_need := 12
## 虫洞提前几拍从前方飞过来
@export var warp_approach_beats := 8.0
@export var mash_text := "MASH!"
@export var mash_full_text := "WARP!!"

var _ending_laid := -INF
var _charge := 0
var _pop := 0.0          # 连按每按一下弹一下（很快衰减）
var _heat := 0.0         # 蓄力的画面强度（平滑追 _charge / mash_need）
var _warp_dist := 0.0    # 虫洞里已经冲了多远

# ---------------------------------------------------------------- 分镜

## 镜头表。每个镜头由 _shot_pose 按 u（这个镜头放到百分之几）算机位。
##   bars  这个镜头几小节      blend 从上一个镜头甩过来用几拍（0 = 硬切）
##   fx    这个镜头套的全屏特效（scripts/fx/screen_fx.gd 的 EFFECTS，"" = 原样）
##   speed 往前飞的速度（米 / 秒）
## 读谱的规矩：打音符的镜头都正对着判定环（在猫的正前方或正后方，最多偏二十来度），判定环始终是屏幕中间的一个正圆；
## 镜头只做推拉、变焦、歪头打滚这些不改变圆环形状的动作。花样靠全屏特效：镜像、竖条分屏、九宫格、几种万花筒。
## 开头：长镜头、慢，梦一样地飘。猫一直在画面正中间，对称轴穿过正中间的镜像看不出来，所以这里用的是
## 「双胞胎」：猫分成一左一右两只（第二个镜头）、一正一倒两只（第三个镜头，像水里的倒影），判定圈跟着各有一个。
## 全打准的话开头只有 8 小节左右，所以这两个镜头各 2 小节、排在前面，保证都能看到。
const INTRO := [
	{"id": "open", "bars": 4, "speed": 9.0},
	{"id": "pull", "bars": 2, "fx": "twin", "speed": 9.0},
	{"id": "far", "bars": 2, "fx": "twin_v", "speed": 10.0},
	{"id": "swing", "bars": 4, "blend": 2.0, "speed": 10.0},
]
## 四阶下行：两小节一切，和「四下重音 + 一串八分」的句子对上。
const STEPS := [
	{"id": "front", "bars": 2, "fx": "strips3", "speed": 12.0},
	{"id": "roll", "bars": 2, "fx": "mirror4", "speed": 12.0},
	{"id": "pull", "bars": 2, "fx": "grid3", "speed": 12.0},
	{"id": "swing", "bars": 2, "fx": "rgb", "blend": 1.0, "speed": 13.0},
]
## 高潮：两小节一切，四种万花筒、镜像、分屏轮着来；每 8 小节的句尾（三下重拍）落在万花筒上。
const PEAK := [
	{"id": "front", "bars": 2, "fx": "kaleido", "speed": 16.0},
	{"id": "spin", "bars": 2, "fx": "mirror", "speed": 17.0},
	{"id": "chase", "bars": 2, "fx": "strips5", "speed": 18.0},
	{"id": "pull", "bars": 2, "fx": "kaleido8", "speed": 16.0},
	{"id": "tilt", "bars": 2, "fx": "mirror4", "speed": 17.0},
	{"id": "front", "bars": 2, "fx": "grid3", "speed": 17.0},
	{"id": "roll", "bars": 2, "fx": "kaleido4", "speed": 18.0},
	{"id": "front", "bars": 2, "fx": "kaleido12", "speed": 16.0},
]
## 结尾四段：虫洞飞过来 → 钻进去连按 → 冲出去 → 结算底下慢慢绕
const APPROACH := [{"id": "chase", "bars": 99, "blend": 2.0, "speed": 20.0}]  # 特效收掉，干干净净地看虫洞过来
const WARP := [{"id": "warp", "bars": 99, "blend": 1.0, "speed": 40.0}]
const BURST := [{"id": "burst", "bars": 99, "speed": 60.0}]
const AFTER := [{"id": "after", "bars": 999, "blend": 6.0, "speed": 8.0}]
const SEQS := {"intro": INTRO, "steps": STEPS, "peak": PEAK,
		"approach": APPROACH, "warp": WARP, "burst": BURST, "after": AFTER}

@export_group("分镜")
## 场景里摄像机的视角（度）：各镜头的视角都是相对它定的
@export var base_fov := 45.0
## 2D 判定圈最小 / 最大多大（占屏幕高度的比例）。镜头拉远时 3D 判定环变小，2D 这圈跟着它，但不小于 / 大于这两个值
@export var ring_ratio_min := 0.08
@export var ring_ratio_max := 0.32
@export_group("")

var _mode := ""
var _seq_i := -1
var _shot := {}
var _shot_from := 0.0
var _shot_to := -INF
var _pose := {}          # 这一帧的机位 {pos, look, roll, fov}
var _from_pose := {}     # 甩镜头的起点（切镜头那一刻上一个镜头的机位）
var _steps_at := INF     # 音乐换到四阶下行 / 高潮的那条线
var _peak_at := INF
var _fx_now := "?"

# 结尾的虫洞（运行时建出来，见 _build_warp）
const WARP_SHADER := "res://stages/space_pizza/wormhole.gdshader"
const CARD_DIR := "res://stages/space_pizza/recap/"
const TUBE_LENGTH := 160.0
const TUBE_RADIUS := 7.0
var _tube: MeshInstance3D
var _tube_mat: ShaderMaterial
var _cards: Node3D

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
	camera.far = 600.0
	_build_warp()
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


func _main() -> Node:
	return get_parent().get_parent() if get_parent() else null


# ---------------------------------------------------------------- 换谱

## 音乐排好了换阶段（预备信号）：记下在哪条线换哪套谱、镜头换哪一组
func _on_change_planned(kind: String, id: int, _fill_beat: float, commit_beat: float) -> void:
	if not active:
		return
	if kind == "tier" and id == 2:
		_steps_at = commit_beat
		if not mid_bars.is_empty():
			_next_bars = mid_bars
			_next_phase = "steps"
			_next_at = commit_beat
	elif kind == "fever":
		_peak_at = commit_beat
		if not peak_bars.is_empty():
			_next_bars = peak_bars
			_next_phase = "peak"
			_next_at = commit_beat


## 离那条线 12 拍以内才换（判定只提前铺 16 拍）：旧谱打到那条线为止，新谱从那条线起算
func _chart_tick() -> void:
	if not active:
		return
	_lay_ending()
	if is_inf(_next_at) or song_beat() < _next_at - 12.0:
		return
	var main := _main()
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


# ---------------------------------------------------------------- 结尾的大连按

## 从 ending_from 起铺 ENDING_HOLD_BEATS 拍的八分踩镲（不判定的音符：只吃按键，按了几下由 _on_empty_hit 数）
func _lay_ending() -> void:
	var j := main_judge()
	if is_inf(ending_from) or j == null:
		return
	_ending_laid = maxf(_ending_laid, ending_from)
	while _ending_laid < ending_from + ENDING_HOLD_BEATS - 0.001 and _ending_laid <= song_beat() + Judge.LOOKAHEAD_BEATS - 1.0:
		if _ending_laid > song_beat():
			var n := j.add_note(_ending_laid, NoteData.Sound.HAT)
			if n:
				n.sound = NoteData.Sound.HAT
				n.free = true
		_ending_laid += 0.5


func _in_mash() -> bool:
	return song_beat() >= ending_from - 0.5 and song_beat() < ending_from + ENDING_HOLD_BEATS + 0.25


func _on_empty_hit() -> void:
	if not _in_mash():
		return
	_charge += 1
	_pop = 1.0
	hit_age = 0.0  # 每按一下画面都顶一下（披萨、猫、镜头都读 pulse()）
	var m := _main()
	if m and m.get("screen_fx"):
		m.screen_fx.punch(0.35 + 0.5 * _charge_ratio())


func _charge_ratio() -> float:
	return clampf(float(_charge) / maxf(mash_need, 1), 0.0, 1.0)


## 连按的音符不涨条、不放命中特效（积累条已经满了）
func wants_hit_effects(note: NoteData) -> bool:
	return not note.free


# ---------------------------------------------------------------- 分镜

## 现在该放哪一组镜头
func _mode_now(beat: float) -> String:
	if not is_inf(ending_from):
		var end := ending_from + ENDING_HOLD_BEATS
		if beat >= end + 4.0:
			return "after"
		if beat >= end:
			return "burst"
		if beat >= ending_from:
			return "warp"
		if beat >= ending_from - warp_approach_beats:
			return "approach"
	if beat >= _peak_at:
		return "peak"
	if beat >= _steps_at:
		return "steps"
	return "intro"


## 每帧：到了小节线就换下一个镜头；换了阶段就从那一组的第一个镜头起
func _direct(beat: float) -> void:
	var mode := _mode_now(beat)
	var cut := false
	if mode != _mode:
		_mode = mode
		_seq_i = -1
		_shot_to = floorf(beat)
		cut = true
	elif beat >= _shot_to:
		cut = true
	if not cut:
		return
	var seq: Array = SEQS[_mode]
	_seq_i = (_seq_i + 1) % seq.size()
	_shot = seq[_seq_i]
	_shot_from = _shot_to if not is_inf(_shot_to) else floorf(beat)
	_shot_to = _shot_from + float(_shot.bars) * 4.0
	_from_pose = _pose.duplicate()
	_set_fx(str(_shot.get("fx", "")))


## 全屏特效跟着镜头走：把特效层的切换点换成「从头就是这个特效」
func _set_fx(id: String) -> void:
	if id == _fx_now:
		return
	var m := _main()
	if m == null or not m.get("screen_fx"):
		return
	_fx_now = id
	m.screen_fx.cues = [[0.0, id]]
	m.screen_fx.refresh()


## 一个镜头的机位。u = 这个镜头放到百分之几（0→1），t = 一直在走的秒数，f = 判定环的位置（猫的正前方是 +z）
func _shot_pose(id: String, u: float, t: float, f: Vector3) -> Dictionary:
	var e := smoothstep(0.0, 1.0, u)
	match id:
		"open":  # 开场：从侧前方慢慢滑到正面（一开始偏三十来度，圆环略扁，之后都是正圆）
			var a := lerpf(deg_to_rad(55.0), PI / 2.0, e)
			var d := lerpf(side_distance, front_distance, e)
			return {"pos": f + Vector3(-cos(a) * d, camera_height * (1.0 - e) + sin(t * 0.6) * 0.2 * (1.0 - e), sin(a) * d),
					"look": f, "roll": 0.0, "fov": base_fov}
		"front":  # 正面，推近的同时把视角拉开（希区柯克变焦）：猫差不多一样大，背景往外涌
			var d := lerpf(12.0, 6.0, e)
			return {"pos": f + Vector3(0.0, 0.2, d), "look": f, "roll": 0.0, "fov": _fov_for(d)}
		"pull":  # 反过来：往后退、视角收窄，背景往里收
			var d := lerpf(6.5, 13.0, e)
			return {"pos": f + Vector3(0.0, 0.2, d), "look": f, "roll": sin(t * 0.5) * 0.04, "fov": _fov_for(d)}
		"far":  # 正面远景，慢慢推近：判定环只占画面高度的三分之一左右，上下分成两半时每一半都装得下
			var d := lerpf(15.0, 12.5, e)
			return {"pos": f + Vector3(sin(t * 0.4) * 0.3, 0.2, d), "look": f, "roll": 0.0, "fov": base_fov}
		"swing":  # 正面，像钟摆一样左右荡（每小节一个来回的一半），带一点歪头
			var a := sin(u * float(_shot.bars) * PI) * 0.32
			return {"pos": f + Vector3(sin(a) * 9.0, 0.4, cos(a) * 9.0), "look": f, "roll": -a * 0.6, "fov": 50.0}
		"roll":  # 正面近一点，歪着头：每小节歪到另一边
			var a := cos(u * float(_shot.bars) * PI) * 0.42
			return {"pos": f + Vector3(0.0, 0.3, 7.5 - 0.8 * e), "look": f, "roll": a, "fov": 52.0}
		"spin":  # 正面，镜头绕着视线转一整圈
			return {"pos": f + Vector3(0.0, 0.2, lerpf(9.5, 7.0, e)), "look": f, "roll": e * TAU, "fov": 54.0}
		"tilt":  # 正面偏下的广角仰拍，慢慢升回来
			return {"pos": f + Vector3(0.0, lerpf(-1.4, 0.3, e), 6.2), "look": f, "roll": lerpf(0.14, -0.08, e), "fov": 66.0}
		"chase":  # 猫的正背后，往前看：圆环迎面过来
			return {"pos": f + Vector3(sin(t * 0.5) * 0.4, 0.9 - 0.4 * e, -7.5 + 1.5 * e), "look": f + Vector3(0.0, 0.0, 6.0),
					"roll": sin(t * 0.5) * 0.06, "fov": 66.0}
		"warp":  # 虫洞里：贴在猫背后，视角越蓄越广，最后一小节打一个滚
			var ep := clampf((song_beat() - ending_from) / ENDING_HOLD_BEATS, 0.0, 1.0)
			var last := smoothstep(0.0, 1.0, clampf(ep * 2.0 - 1.0, 0.0, 1.0))
			var shake := _heat * 0.12
			return {"pos": f + Vector3(sin(t * 31.0) * shake, 1.3 + cos(t * 27.0) * shake, -5.6 + 1.6 * _heat - _pop * 0.3),
					"look": f + Vector3(0.0, 0.2, 8.0), "roll": sin(t * 1.3) * 0.12 + last * TAU,
					"fov": 70.0 + 22.0 * ep + 26.0 * _heat}
		"burst":  # 冲出去：镜头停在前方，猫贴着镜头掠过去，越飞越远
			var bu := clampf((song_beat() - ending_from - ENDING_HOLD_BEATS) / 4.0, 0.0, 1.0)
			var out := 1.0 - pow(1.0 - bu, 4.0)
			return {"pos": f + Vector3(2.4, 0.5 + 1.5 * out, 13.0 - 44.0 * out), "look": f,
					"roll": (1.0 - out) * -0.25, "fov": lerpf(104.0, 50.0, out)}
		_:  # after：结算底下，远远地慢慢绕
			var a := t * 0.12
			return {"pos": f + Vector3(cos(a) * 12.0, 2.6 + sin(t * 0.3) * 0.6, sin(a) * 12.0), "look": f,
					"roll": sin(t * 0.2) * 0.04, "fov": base_fov}


## 镜头离判定环 d 米时，用多大的视角能让它在画面里和正面机位（front_distance、base_fov）一样大
func _fov_for(d: float) -> float:
	return rad_to_deg(2.0 * atan(front_distance * tan(deg_to_rad(base_fov) / 2.0) / d))


func _camera_pose(_p: float, t: float) -> Dictionary:
	var beat := song_beat()
	_direct(beat)
	var f := _focus()
	var u := clampf((beat - _shot_from) / maxf(_shot_to - _shot_from, 0.001), 0.0, 1.0)
	var pose := _shot_pose(str(_shot.get("id", "open")), u, t, f)
	# 甩镜头：从上一个镜头最后的机位快速滑过来（先快后慢），不是硬切
	var blend := float(_shot.get("blend", 0.0))
	if blend > 0.0 and not _from_pose.is_empty() and beat - _shot_from < blend:
		var k := 1.0 - pow(1.0 - clampf((beat - _shot_from) / blend, 0.0, 1.0), 3.0)
		pose.pos = (_from_pose.pos as Vector3).lerp(pose.pos, k)
		pose.look = (_from_pose.look as Vector3).lerp(pose.look, k)
		pose.roll = lerpf(_from_pose.roll, pose.roll, k)
		pose.fov = lerpf(_from_pose.fov, pose.fov, k)
	_pose = pose
	return {"pos": pose.pos, "look": pose.look, "roll": 0.0}


## 基类摆好机位之后再加上歪头（绕镜头自己的前后轴转）和视角
func _update_spin(local_beat: float, angle: float) -> void:
	super._update_spin(local_beat, angle)
	if camera == null or _pose.is_empty() or (Engine.is_editor_hint() and not preview_playing):
		return
	camera.rotate_object_local(Vector3.BACK, float(_pose.roll))
	camera.fov = clampf(float(_pose.fov), 20.0, 140.0)


## 2D 判定圈跟着 3D 判定环的大小走（镜头拉远它就小，推近它就大）
func hit_radius() -> float:
	if camera == null or _pose.is_empty():
		return super.hit_radius()
	var d := maxf(((_pose.pos as Vector3) - _focus()).length(), 0.5)
	var ratio := ring_radius_ratio * front_distance * tan(deg_to_rad(base_fov) / 2.0) / (d * tan(deg_to_rad(camera.fov) / 2.0))
	return clampf(ratio, ring_ratio_min, ring_ratio_max) * screen_size().y


## 判定环被斜着看时压成椭圆：[上下压多少, 左右压多少]
func _ring_squash() -> Array[float]:
	if _pose.is_empty():
		return [1.0, 1.0]
	var d := ((_pose.pos as Vector3) - (_pose.look as Vector3)).normalized()
	var face := maxf(absf(d.z), 0.3)
	if absf(d.x) > absf(d.y):
		return [1.0, face]
	return [face, 1.0]


# ---------------------------------------------------------------- 每帧

func _update_view(t: float) -> void:
	var dt := 0.0 if _last_t < 0.0 else minf(t - _last_t, 0.05)
	_heat = lerpf(_heat, _charge_ratio() if _mode == "warp" else 0.0, minf(1.0, dt * 6.0))
	_pop = maxf(_pop - dt * 6.0, 0.0)
	fly_speed = float(_shot.get("speed", 9.0))
	if _mode == "warp":
		fly_speed += 50.0 * _heat
	elif _mode == "burst":
		var bu := clampf((song_beat() - ending_from - ENDING_HOLD_BEATS) / 4.0, 0.0, 1.0)
		fly_speed = lerpf(70.0, 10.0, bu)
	super._update_view(t)
	_update_warp(t, dt)


## 虫洞：一根只画内壁的长管子 + 洞壁上的回顾画面（前面几关的截图，stages/space_pizza/recap/ 里有几张放几张）
func _build_warp() -> void:
	if _tube or world == null or not ResourceLoader.exists(WARP_SHADER):
		return
	_tube_mat = ShaderMaterial.new()
	_tube_mat.shader = load(WARP_SHADER)
	_tube_mat.set_shader_parameter("tube_length", TUBE_LENGTH)
	var mesh := CylinderMesh.new()
	mesh.top_radius = TUBE_RADIUS * 0.55  # 尽头收窄一点：透视更深
	mesh.bottom_radius = TUBE_RADIUS
	mesh.height = TUBE_LENGTH
	mesh.radial_segments = 48
	mesh.rings = 24
	mesh.cap_top = false
	mesh.cap_bottom = false
	_tube = MeshInstance3D.new()
	_tube.mesh = mesh
	_tube.material_override = _tube_mat
	_tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tube.basis = Basis(Vector3.RIGHT, PI / 2.0)  # 管子的轴（y）转到朝前（+z）
	_tube.visible = false
	world.add_child(_tube)
	_cards = Node3D.new()
	_cards.visible = false
	world.add_child(_cards)
	var textures: Array[Texture2D] = []
	for i in range(1, 9):
		var path := CARD_DIR + "card_%d.png" % i
		if ResourceLoader.exists(path):
			textures.append(load(path))
	if textures.is_empty():
		return
	for i in 12:
		var tex := textures[i % textures.size()]
		var card := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(3.4, 3.4 * tex.get_height() / maxf(tex.get_width(), 1.0))
		card.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = tex
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		card.material_override = mat
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 白边（拍立得）
		var frame := MeshInstance3D.new()
		var fq := QuadMesh.new()
		fq.size = quad.size + Vector2(0.3, 0.3)
		frame.mesh = fq
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = Color(1.0, 0.98, 0.94)
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		frame.material_override = fm
		frame.position.z = -0.03
		frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		card.add_child(frame)
		_cards.add_child(card)


func _update_warp(t: float, dt: float) -> void:
	if _tube == null:
		return
	var beat := song_beat()
	var end := ending_from + ENDING_HOLD_BEATS
	var on := not is_inf(ending_from) and beat >= ending_from - warp_approach_beats - 4.0
	if not on:
		_tube.visible = false
		_cards.visible = false
		return
	var f := _focus()
	# 入口从前方飞过来，ending_from 那一拍正好罩住猫；之后管子不动，花纹和画面往后冲
	var ahead := maxf(ending_from - beat, 0.0) * 14.0
	var mouth := f.z - 12.0 + ahead
	var amount := 1.0
	var widen := 1.0
	if beat >= end:
		# 冲出去：管子一下子炸开、淡掉
		var k := clampf((beat - end) / 1.5, 0.0, 1.0)
		amount = 1.0 - k
		widen = 1.0 + 9.0 * (1.0 - pow(1.0 - k, 3.0))
	_tube.visible = amount > 0.01
	_cards.visible = _tube.visible and beat < end
	_tube.position = Vector3(f.x, f.y, mouth + TUBE_LENGTH / 2.0)
	_tube.scale = Vector3(widen, 1.0, widen)
	_warp_dist += fly_speed * dt
	_tube_mat.set_shader_parameter("scroll", _warp_dist * 0.05)
	_tube_mat.set_shader_parameter("amount", amount)
	_tube_mat.set_shader_parameter("heat", _heat)
	# 回顾画面：贴着洞壁排一圈圈，跟着往后掠过去，掠过猫身后就绕回前面
	var span := 108.0
	for i in _cards.get_child_count():
		var card := _cards.get_child(i) as Node3D
		var a := i * 2.399 + 0.6
		var z := span - fposmod(i * (span / _cards.get_child_count()) + _warp_dist * 0.55, span) - 14.0
		var r := lerpf(4.3, 3.2, clampf(z / span, 0.0, 1.0))
		var pos := Vector3(f.x + cos(a) * r, f.y + sin(a) * r * 0.8, maxf(mouth, f.z - 14.0) + 14.0 + z)
		card.position = pos
		card.look_at(Vector3(f.x, f.y + 0.6, pos.z - 16.0), Vector3.UP)
		card.rotate_object_local(Vector3.UP, PI)
		card.rotate_object_local(Vector3.BACK, sin(t * 2.0 + i) * 0.08)
		card.visible = pos.z > mouth + 2.0 and z > -10.0


## 音符是 3D 圆环；2D 这层放判定点外压暗、判定圈预亮、空拍虚线，连按时再加蓄力弧和大字
func _draw_overlay() -> void:
	if def == null:
		return
	if _phase != 2:
		var sq := _ring_squash()
		draw_focus(_overlay, hit_position(), hit_radius(), sq[0])
		draw_lit_target(_overlay, hit_position(), hit_radius(), Color(1, 1, 1, 0.9), 3.0, sq[0], sq[1])
		draw_target_guides(_overlay, hit_position(), hit_radius(), 0.32 * screen_size().y, ring_beats,
				Callable(), sq[0], sq[1], false)
		if tap_age < 0.15:
			_overlay.draw_arc(hit_position(), hit_radius() * (1.0 + tap_age), 0.0, TAU, 64,
					Color(1, 1, 1, 1.0 - tap_age / 0.15), 6.0)
	_draw_mash()


func _draw_mash() -> void:
	if is_inf(ending_from) or song_beat() < ending_from - 4.0 or song_beat() >= ending_from + ENDING_HOLD_BEATS:
		return
	var font := ThemeDB.fallback_font
	var size := screen_size()
	var center := hit_position()
	var radius := hit_radius()
	var ratio := _charge_ratio()
	var coming := song_beat() < ending_from
	# 蓄力弧：一圈七彩，按一下长一段
	_overlay.draw_arc(center, radius * 1.18, 0.0, TAU, 96, Color(1, 1, 1, 0.18), 10.0, true)
	if ratio > 0.0:
		var steps := maxi(int(ratio * 64.0), 2)
		for i in steps:
			var a0 := -PI / 2.0 + TAU * ratio * i / steps
			var a1 := -PI / 2.0 + TAU * ratio * (i + 1) / steps + 0.02
			_overlay.draw_arc(center, radius * 1.18, a0, a1, 4, Color.from_hsv(fposmod(float(i) / 64.0 + song_beat() * 0.25, 1.0), 0.75, 1.0),
					10.0 + _pop * 8.0, true)
	var full := ratio >= 1.0
	var label := mash_full_text if full else mash_text
	var fs := int((64.0 if coming else 84.0 + _pop * 26.0) * size.y / 720.0)
	var blink := 0.55 + 0.45 * sin(song_beat() * TAU) if coming else 1.0
	var col := Color.from_hsv(fposmod(song_beat() * 0.5, 1.0), 0.45 if full else 0.2, 1.0, blink)
	var pos := Vector2(-320.0, -size.y * 0.28 + fs * 0.35)
	_overlay.draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 640, fs, 10, Color(0.06, 0.02, 0.16, 0.95 * blink))
	_overlay.draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 640, fs, col)


func _on_restore() -> void:
	super._on_restore()
	if camera:
		camera.fov = base_fov
	if _tube:
		_tube.visible = false
		_cards.visible = false
	_mode = ""
	_seq_i = -1
	_shot = {}
	_shot_to = -INF
	_pose = {}
	_from_pose = {}
	_charge = 0
	_heat = 0.0
	_warp_dist = 0.0


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
