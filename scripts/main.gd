extends Node2D
## 游戏本体：加载一个大关的谱面，一个个小关往下闯。
## 小关不限时：鼓谱一直循环，积累条（Gauge）满了，就在下一个小节线切到下一个小关；
## 最后一个小关也满了 = 大关通关。音乐循环播放，不会因为切关而重放。
## 节拍 / 判定 / 积累条的事件都从这里转发给当前小关和 HUD。

## 积累条第一次涨过某条事件分数线时发出
## （section_index = 第几个小关，index = 这一关的第几个事件，value = 那条线的分数）。
## 留给以后用：加音轨、加全局特效之类接这个信号；只和某个小关的画面有关的，
## 在那个小关的脚本里重写 _on_gauge_event(index, value) 更方便。
## 每个小关有几个事件、各在多少分，见 gauge.gd 开头的说明。
signal gauge_event(section_index: int, index: int, value: int)
## 第 section_index 个小关的积累条满了
signal gauge_filled(section_index: int)
## 进入了第 section_index 个小关
signal section_entered(section_index: int)
## 整个大关打完了
signal level_cleared

## 调试用：从第几个小关开始（0 起）
@export var start_section := 0
## 开始前的预备拍数（音乐响起之前先空走几拍）
@export var lead_in_beats := 4.0
## 最后一关打完，结算画面停几秒之后自动接片尾字幕（期间按任意键马上去；0 = 不自动，等玩家按键）
@export var credits_after_seconds := 6.0
@export_group("阶段触发的大反馈")
## 积累条涨过一条分数线（进了新阶段）/ 涨满时：画面顶一大下（1 = 一次 Perfect 那么大；0 = 不顶）
@export var phase_punch := 2.0
## 同时全屏白闪多亮（0 = 不闪）
@export_range(0.0, 1.0) var phase_flash := 0.3
## 同时响一声重音：assets/audio/sfx/ 里的文件名（不带 .wav，比如 "crash"），留空 = 不响。
## 默认不响：叠轨音乐升档时自己已经会响一声镲（music.gd），再加一声会叠在一起
@export var phase_sound := ""
@export_range(-30.0, 6.0) var phase_sound_db := -10.0
@export_group("")

## 一路连着玩：第 1 大关打完硬切到第 2 大关……一直到这一关（0 起）为止，打完它才出最终结算。
## 之后的大关只能从 Esc 暂停转盘里选；从那里选进去的关打完也直接出结算。
@export var flow_last_level := 2

## 一路连着玩时，前面几关的成绩（Perfect / Great / Good / Miss 个数、最大连击），最终结算时合在一起算总分
static var run_counts := {}
static var run_max_combo := 0
## 一路连着玩时，前面几关已经拿到的分和那几关的满分（左上角显示累计分、最终评级用）
static var run_score := 0
static var run_possible := 0.0
## 现在是不是在一路连着玩（从第 1 关开始的）
static var in_run := true
## 两关之间：等玩家按一下才开始这一关
var _waiting_to_start := false
## 两关之间的黑幕落下来用几秒（落完才换关）
@export var curtain_seconds := 0.6
## 两关之间的喘息：黑幕落走之后，下一关真正的场景先摆在那儿停几小节，然后自动开始数拍子
## （这段时间里按一下就马上开始）。0 = 不自动开始，一直等玩家按
@export var breath_bars := 1.0
var _breath_preview: SpinSection
## 第 1 关的温馨开头：先假装是一个温馨的养猫小游戏（八音盒、粉粉的画面），玩家按一下，画风突变，正式开始。
## 只在一路连着玩、从第 1 关起步的时候出现，这次运行里只出现一次（重开不再放）。关掉 = 直接开始
@export var cozy_intro := true
static var _cozy_seen := false
var _cozy := false
var _cozy_preview: SpinSection

@onready var section_host: Node2D = $SectionHost
@onready var fx_layer: Node2D = $FxLayer
@onready var judge: Judge = $Judge
@onready var gauge: Gauge = $Gauge
@onready var drum_kit: DrumKit = $DrumKit
@onready var hit_meow: HitMeow = $HitMeow  # 打中时喵一声（Perfect / Good 各一组，随机挑）
@onready var hud = $HUD
@onready var screen_fx: ScreenFx = $ScreenFx
@onready var memes: MemeCues = $Memes

const GameEditor := preload("res://scripts/tools/game_editor.gd")
## 片尾字幕（星球大战式滚动字幕，scenes/credits.tscn）
const CREDITS_SCENE := "res://scenes/credits.tscn"
const ShockRing := preload("res://scripts/fx/shock_ring.gd")

## 游戏里的编辑面板开着（Tab）：这时积累条由面板上的进度条控制，打中 / 漏打不再改它
var editing := false
var _editor: CanvasLayer

var chart: SongChart
var _index := -1
var _current: SpinSection
var _switch_at := -1.0  # 积累条满了之后，定在第几拍切关（-1 = 还没满）
var _stage_weights: Array[float] = []  # 每个小关占这一大关满分的比例（计分用）
var _stage_clicks: Array[float] = []  # 每个小关预计要按多少下（实时显示分数用）
var _cleared := false
var _credits_going := false
var _gauge_offset := 0  # 共用积累条：这一段前面的几段一共多少分
var _gauge_total := 0   # 共用积累条：整条一共多少分


func _ready() -> void:
	# 谱面由主菜单选中的大关决定（见 scripts/core/levels.gd）；直接运行本场景时是第 1 大关
	chart = Levels.build_chart()
	# 叠轨音乐：这一大关的音乐配置（json 里的 use_in_game）开了“在游戏里用”，就用它代替谱面里的伴奏，
	# BPM 也跟着配置走；进度 = 积累条，小关 = 当前小关。没开的大关完全不受影响。
	if Music.enabled_for(Levels.selected):
		chart.stream = Music.build(Music.read(Music.path_for(Levels.selected)))
		chart.bpm = Music.bpm()
		chart.first_beat_offset_sec = 0.0
		section_entered.connect(Music.set_section)
		gauge.changed.connect(func(v: int, m: int) -> void: Music.set_progress(float(v) / maxi(m, 1)))
		gauge.filled.connect(Music.rise_to_bar)  # 积累条满了：一声上扬音效，正好在换小关的那条小节线上放完
	else:
		Music.clear()  # 这一关不用叠轨音乐：别让上一关的喵谱子跟过来
	ComicStyle.set_by_name(Levels.look())
	drum_kit.use_chart(chart)
	Conductor.load_chart(chart)
	judge.load_chart(chart)

	hud.gauge = gauge
	Conductor.beat.connect(_on_beat)
	judge.note_judged.connect(_on_note_judged)
	judge.pressed.connect(drum_kit.play)
	judge.empty_hit.connect(_on_empty_hit)
	judge.combo_milestone.connect(func(combo: int): hud.show_combo_milestone(combo))
	judge.combo_milestone.connect(hit_meow.milestone)  # 连击里程碑：转圈喵（oiia），连击够高再送一段鬼畜全开
	# 左上角的分数实时涨（live_score = 已入账 + 当前阶段的估计），真正的成绩还是阶段结束时入账
	judge.stats_changed.connect(func(): hud.set_stats(judge.live_score() + (run_score if in_run else 0), judge.combo))
	judge.stats_changed.connect(func(): screen_fx.set_combo(judge.combo))  # 连击越高画面越热闹
	gauge.changed.connect(_on_gauge_changed)
	gauge.event.connect(_on_gauge_event)
	gauge.filled.connect(_on_gauge_filled)

	# Esc 暂停转盘（暂停时也要能收键，所以挂一个不受暂停影响的层）
	add_child(preload("res://scripts/pause_menu.gd").new())
	# 谱面里的长按 / 连击：通用处理（见 scripts/chart/input/chart_input.gd）
	add_child(ChartInput.attach(judge, gauge, func() -> Node: return _current))

	# 一路连着玩从上一关过来的（过门还在响）：先喘口气，玩家按一下才正式开始这一关
	if Music.bridge_active():
		_wait_for_start()
	elif cozy_intro and not _cozy_seen and in_run and Levels.selected == 0 and Levels.interlude == "":
		_cozy_seen = true
		_cozy = true
		Music.cozy_intro()
		_wait_for_start()
	else:
		start_from(start_section)


## 两关之间的喘息：显示一句提示，等玩家按一下（打鼓的键 / 鼠标）再开始。画面上这时只有背景，
## 想在这里放转场动画（黑幕、猫飞上天）就接在这段时间里；声音是 Music 的等待循环。
func _wait_for_start() -> void:
	_waiting_to_start = true
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.name = "StartPrompt"
	add_child(layer)
	if _cozy:
		# 温馨开头：画面就是第 1 关真正的场景（先摆出来，不开始），上面盖一层粉粉的滤镜、贴纸和一句提示
		# （scripts/cozy_overlay.gd）。分数、积累条这些先藏起来。
		var def := chart.sections[0]
		_cozy_preview = def.scene.instantiate() as SpinSection
		_cozy_preview.setup(def, judge.begin_section(0, def, chart.beats_per_bar, 0.0, 0.0))
		section_host.add_child(_cozy_preview)
		_cozy_preview.enter()
		hud.visible = false
		_cozy_preview.self_modulate.a = 0.0  # 判定圈和辅助线先不画（猫和房间是它的子节点，不受影响）
		var overlay: Control = preload("res://scripts/cozy_overlay.gd").new()
		for c in _cozy_preview.get_children():
			if c is KisaSpinCat3D:
				overlay.cat = c  # 有这只猫的 3D 舞台就做特写运镜
		layer.add_child(overlay)
		return
	# 喘息不在黑幕里：下一关真正的场景先摆出来（不开始，没有音符），黑幕落走就看得到它；
	# 分数、积累条先藏起来，画面上只有关卡名。停 breath_bars 小节后自动开始（或者玩家按一下马上开始）。
	var def := chart.sections[clampi(start_section, 0, chart.sections.size() - 1)]
	_breath_preview = def.scene.instantiate() as SpinSection
	var none: Array[NoteData] = []
	_breath_preview.setup(def, none)
	section_host.add_child(_breath_preview)
	_breath_preview.enter()
	_breath_preview.self_modulate.a = 0.0  # 判定圈和辅助线先不画
	hud.visible = false
	var label := Label.new()
	label.text = Levels.title() if breath_bars > 0.0 else "%s\n\nPRESS TO START" % Levels.title()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_bottom = -70.0
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 10)
	layer.add_child(label)
	# 提示字慢慢一明一暗；下一关的声音从等待的循环里透出来一点
	var blink := label.create_tween().set_loops()
	blink.tween_property(label, "modulate:a", 0.45, 0.75).set_trans(Tween.TRANS_SINE)
	blink.tween_property(label, "modulate:a", 1.0, 0.75).set_trans(Tween.TRANS_SINE)
	Music.bridge_tease()
	if breath_bars > 0.0:
		# 黑幕落走要 StageCurtain.LEAVE_SECONDS，之后再停 breath_bars 小节
		var wait := StageCurtain.LEAVE_SECONDS + breath_bars * chart.beats_per_bar * 60.0 / chart.bpm
		get_tree().create_timer(wait).timeout.connect(_begin_on_bar)


func _unhandled_input(event: InputEvent) -> void:
	if _waiting_to_start and event.is_action_pressed(Judge.HIT_ACTION):
		get_viewport().set_input_as_handled()
		_begin_after_wait()


## 停够了：等到透出来的那段音乐的下一条小节线再开始数拍子，这样它的鼓能一直响到第一拍，和正式的音乐接上
func _begin_on_bar() -> void:
	if not _waiting_to_start:
		return
	var left := Music.bridge_seconds_to_bar()
	if left > 0.0:
		get_tree().create_timer(left).timeout.connect(_begin_after_wait.bind(true))
	else:
		_begin_after_wait(true)


## 喘息结束（玩家按了一下，或者停够了）：正式开始这一关
func _begin_after_wait(on_bar := false) -> void:
	if not _waiting_to_start:
		return
	_waiting_to_start = false
	get_node("StartPrompt").queue_free()
	if _cozy:
		_cozy = false
		_cozy_preview.queue_free()
		_cozy_preview = null
		hud.visible = true
		Music.cozy_snap(lead_in_beats * 60.0 / chart.bpm)  # 八音盒戛然而止，倒带倒到第一拍
		_cozy_break()
		start_from(start_section)
		_cozy_spin(lead_in_beats * 60.0 / chart.bpm)
		return
	if _breath_preview:
		_breath_preview.queue_free()
		_breath_preview = null
		hud.visible = true
	Music.bridge_go(lead_in_beats * 60.0 / chart.bpm, on_bar)  # 数拍子，正好数到第一拍
	start_from(start_section)


## 温馨开头被按破的那一下：闪一下（只闪一次、半透明的粉白，很快退掉；不做黑白频闪，太刺眼），
## 画面猛地放大弹回来、抖几下，再给一记画面冲击。闪多亮、多久在下面两个数上调。
@export_range(0.0, 1.0) var cozy_flash_strength := 0.55
@export var cozy_flash_seconds := 0.3

## 温馨开头被按破之后：关卡里那只猫自己转起来（像被按住一样一直转，比平时快），转到第一拍松开，交还给玩家的按键。
## 转一圈几秒在 cozy_spin_time 上调。
@export var cozy_spin_time := 0.22

func _cozy_spin(seconds: float) -> void:
	var cat: KisaSpinCat3D = null
	for c in _current.get_children():
		if c is KisaSpinCat3D:
			cat = c
	if cat == null:
		return
	var was_listening := cat.listen_input
	var was_time := cat.hold_spin_time
	cat.listen_input = false
	cat.hold_spin_time = cozy_spin_time
	cat.set_held(true)
	cat.spin()
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(cat):
		cat.set_held(false)
		cat.hold_spin_time = was_time
		cat.listen_input = was_listening


func _cozy_break() -> void:
	hud.flash(Color(1.0, 0.86, 0.92), cozy_flash_strength, cozy_flash_seconds)
	# 画面放大弹回来 + 抖
	var home := section_host.position
	section_host.scale = Vector2.ONE * 1.35
	create_tween().tween_property(section_host, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var shake := create_tween()
	for i in 9:
		var amt := 26.0 * (1.0 - i / 9.0)
		shake.tween_property(section_host, "position", home + Vector2(randf_range(-amt, amt), randf_range(-amt, amt)), 0.035)
	shake.tween_property(section_host, "position", home, 0.035)
	screen_fx.punch(2.5)


## 从某个小关重新开始（成绩清零，音乐从头放）
func start_from(index: int) -> void:
	index = clampi(index, 0, chart.sections.size() - 1)
	judge.reset()
	screen_fx.reset_heat()
	_stage_weights = _compute_stage_weights()
	hud.reset()
	_cleared = false
	_switch_at = -1.0
	Conductor.play(-lead_in_beats)
	_enter(index, 0.0, false)


## 编辑面板用：把当前小关从头重开，再把前 phase 条分数线的事件按顺序补触发，停在第 phase 个阶段的起点
## （0 = 小关开头）。阶段的演出大多不能倒退（比如房子拆了就拆了），所以往回跳只能这样重来。
func jump_to_phase(phase: int) -> void:
	start_from(_index)
	gauge.jump_to_event(phase)


func _process(_delta: float) -> void:
	if not Conductor.playing:
		return
	if _switch_at >= 0.0 and Conductor.song_beat >= _switch_at:
		var at := _switch_at
		_switch_at = -1.0
		if _index + 1 < chart.sections.size():
			_enter(_index + 1, at, true)
		else:
			_clear_level()


## 进入第 index 个小关。at_beat = 它从全曲第几拍开始（必须落在小节线上，鼓谱才和音乐对得齐）。
func _enter(index: int, at_beat: float, animate: bool) -> void:
	var old := _current
	_index = index
	var def := chart.sections[index]
	def.start_beat = at_beat
	# 接着上一个小关继续（同一个场景、勾了 joins_previous）：不换场景、不转场，只换谱面
	var joined := animate and old != null and _joins(index)
	var rest_bars := def.join_rest_bars if joined else chart.rest_bars_on_switch
	var first_note := at_beat + rest_bars * chart.beats_per_bar
	if not joined:
		_current = def.scene.instantiate() as SpinSection
	# 计分：上一个阶段（小关）打完，按准确率入账；新阶段从零开始记
	judge.bank_stage()
	judge.begin_stage(_stage_weights[index] if index < _stage_weights.size() else 0.0,
			_stage_clicks[index] if index < _stage_clicks.size() else 0.0)
	var section_notes := judge.begin_section(index, def, chart.beats_per_bar, at_beat, first_note)
	if joined:
		_current.rejoin(def, section_notes)
	else:
		_current.setup(def, section_notes)
		section_host.add_child(_current)
		_current.enter()
	# 这一关的满条值和事件分数线：谱面里填了用谱面的，否则用关卡场景里填的，都没填用默认值
	var g_max := def.gauge_max if def.gauge_max > 0 else _current.gauge_max_override
	var g_events: Variant = null
	if def.use_gauge_events:
		g_events = def.gauge_events
	elif _current.custom_gauge_events:
		g_events = _current.gauge_events
	screen_fx.begin(def.fx_cues, _current)
	memes.begin(def.meme_cues)
	if not joined:
		hud.reset_gauge()
	_group_gauge(index, g_max)
	gauge.begin(g_max, g_events)
	_current.gauge_event_values = gauge.events
	section_entered.emit(index)

	if joined:
		return
	if old:
		old.exit()
	if not animate:
		if old:
			old.queue_free()
		return
	if def.transition == SectionDef.Transition.CUT:
		# 硬切 + 白闪
		if old:
			old.queue_free()
		hud.flash()
		return
	# 圆对圆转场：旧的放大淡出，新的从中心长出来
	if old:
		var t_old := old.create_tween().set_parallel()
		t_old.tween_property(old, "scale", Vector2.ONE * 5.0, 0.35).set_ease(Tween.EASE_IN)
		t_old.tween_property(old, "modulate:a", 0.0, 0.35)
		t_old.chain().tween_callback(old.queue_free)
	_current.scale = Vector2.ONE * 0.05
	_current.create_tween().tween_property(_current, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 最后一个小关也满了：不再出音符，显示结算（音乐继续放）
func _clear_level() -> void:
	_cleared = true
	judge.stop_notes()
	judge.bank_stage()  # 最后一个阶段入账
	level_cleared.emit()  # 关卡在这里可以再用 judge.add_bonus() 加别的分（比如飞船打星球）
	# 一路连着玩：还没到最后一关就把这关成绩记下来，硬切到下一个大关
	# （这一关后面有插曲关就先去插曲关；插曲关打完再去下一个大关）
	var after := Levels.interlude_after(Levels.selected) if Levels.interlude == "" else ""
	if in_run and (after != "" or Levels.selected < mini(flow_last_level, Levels.count() - 1)):
		for r in judge.counts:
			run_counts[r] = run_counts.get(r, 0) + judge.counts[r]
		run_max_combo = maxi(run_max_combo, judge.max_combo)
		run_score += judge.score
		run_possible += judge.possible
		if after != "":
			Levels.interlude = after
		else:
			Levels.interlude = ""
			Levels.selected += 1
		Conductor.stop()
		Music.bridge_out()  # 过门：飞走的音效 + 等待的循环，一直响到下一关玩家按下开始
		# 每个接口都一样：黑幕从上往下落下来盖住画面再换关（关卡自己已经落过了，比如迪斯科结尾，就直接换）
		if get_tree().root.has_node("StageCurtain"):
			get_tree().change_scene_to_file.call_deferred(Levels.GAME_SCENE)
		else:
			StageCurtain.drop(get_tree(), curtain_seconds)
			get_tree().create_timer(curtain_seconds + 0.05).timeout.connect(
					get_tree().change_scene_to_file.bind(Levels.GAME_SCENE))
		return
	# 最终结算：一路连着玩的话把前面几关的成绩合进来
	if in_run:
		for r in run_counts:
			judge.counts[r] += run_counts[r]
		judge.max_combo = maxi(judge.max_combo, run_max_combo)
		judge.score += run_score
		judge.possible += run_possible
	hud.show_result(judge)
	# 结算画面停一会儿，自己接到片尾字幕（不回第 1 关）；字幕放完回主菜单
	if credits_after_seconds > 0.0:
		get_tree().create_timer(credits_after_seconds).timeout.connect(_go_credits)


## 去片尾字幕（scenes/credits.tscn）。音乐不停，接着在字幕下面放
func _go_credits() -> void:
	if _credits_going or not is_inside_tree():
		return
	_credits_going = true
	if ResourceLoader.exists(CREDITS_SCENE):
		get_tree().change_scene_to_file(CREDITS_SCENE)
	else:
		back_to_menu()


## 每个阶段（小关）占这一大关满分的比例 = 这个阶段大约要点几下 ÷ 整关大约要点几下。
## 鼓谱是循环到积累条满为止的，所以「要点几下」按全打 Perfect 打满积累条估算：
##   要循环几遍 = 满条值 ÷ (Perfect 加的条 × 一遍里会涨条的音符数)，向上取整；要点几下 = 一遍的音符数 × 遍数。
## 关卡脚本里可以写两个常量改变估算（不写就按上面算）：
##   const SCORE_BY_PATTERN := true   这一段不靠积累条推进，谱子放一遍就完，按一遍的音符数算（比如电视墙开场）
##   const SCORE_GAUGE_SOUNDS := "ks"  只有这些鼓会涨积累条（比如拍地球的踩镲只蓄力不涨条）
## 满条值的取法和 _enter 里一样：谱面填了用谱面的，否则用关卡场景根节点上填的，都没填用 Gauge 默认值。
func _compute_stage_weights() -> Array[float]:
	var clicks: Array[float] = []
	var total := 0.0
	for def in chart.sections:
		var m := def.gauge_max
		var consts := {}
		if def.scene:
			var state := def.scene.get_state()
			for i in state.get_node_property_count(0):
				var pname := state.get_node_property_name(0, i)
				if pname == &"gauge_max_override" and m <= 0:
					m = state.get_node_property_value(0, i)
				elif pname == &"script":
					var s: Script = state.get_node_property_value(0, i)
					if s:
						consts = s.get_script_constant_map()
		if m <= 0:
			m = gauge.default_max
		var per_pass := 0
		var gauge_per_pass := 0
		var gauge_sounds: String = consts.get("SCORE_GAUGE_SOUNDS", "ksxh")
		for bar in def.bars:
			for ch in bar:
				if ch in "ksxh":
					per_pass += 1
					if ch in gauge_sounds:
						gauge_per_pass += 1
		var c := float(per_pass)
		if not consts.get("SCORE_BY_PATTERN", false) and gauge_per_pass > 0:
			c = per_pass * ceilf(float(m) / (gauge.perfect_gain * gauge_per_pass))
		clicks.append(maxf(c, 1.0))
		total += clicks[-1]
	_stage_clicks = clicks
	var out: Array[float] = []
	for c in clicks:
		out.append(c / total if total > 0.0 else 0.0)
	return out


## 从第 1 大关重新开始一路连着玩
static func restart_run(tree: SceneTree) -> void:
	run_counts = {}
	run_max_combo = 0
	run_score = 0
	run_possible = 0.0
	in_run = true
	Levels.interlude = ""
	Levels.selected = 0
	Conductor.stop()
	tree.change_scene_to_file(Levels.GAME_SCENE)


## 第 index 个小关是不是接着前一个小关继续的（勾了 joins_previous，而且两个用的是同一个场景）
func _joins(index: int) -> bool:
	if index <= 0 or index >= chart.sections.size():
		return false
	var def := chart.sections[index]
	return def.joins_previous and def.scene != null and def.scene == chart.sections[index - 1].scene


## 一个小关的满条值（还没进这个小关时估的：谱面填了用谱面的，否则看场景根节点，都没填用默认值）
func _gauge_max_of(def: SectionDef) -> int:
	if def.gauge_max > 0:
		return def.gauge_max
	if def.scene:
		var state := def.scene.get_state()
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == &"gauge_max_override" and int(state.get_node_property_value(0, i)) > 0:
				return state.get_node_property_value(0, i)
	return gauge.default_max


## 连着的几个小关在画面上共用一条积累条：算出这一段前面已经有多少、整条一共多少、每段在哪交接，告诉 HUD
func _group_gauge(index: int, current_max: int) -> void:
	var first := index
	while _joins(first):
		first -= 1
	var last := index
	while _joins(last + 1):
		last += 1
	_gauge_offset = 0
	_gauge_total = 0
	var bounds := PackedInt32Array()
	for i in range(first, last + 1):
		if i == index:
			_gauge_offset = _gauge_total
		_gauge_total += current_max if i == index else _gauge_max_of(chart.sections[i])
		if i < last:
			bounds.append(_gauge_total)
	hud.gauge_offset = _gauge_offset
	hud.gauge_bounds = bounds


func _on_gauge_changed(value: int, max_value: int) -> void:
	hud.set_gauge(value + _gauge_offset, maxi(_gauge_total, max_value))
	if _current:
		_current.notify_gauge(value, max_value)
	var p := float(value) / maxi(max_value, 1)
	screen_fx.set_progress(p)
	memes.set_progress(p)


## 进了新阶段 / 满条：画面顶一大下 + 白闪 + 一声重音。
## 编辑面板开着时不做（拖进度条、跳阶段会一口气补触发好几条线）
func _phase_impact() -> void:
	if editing:
		return
	screen_fx.punch(phase_punch)
	if phase_flash > 0.0:
		hud.flash(Color.WHITE, phase_flash, 0.25)
	if phase_sound != "":
		Music.play_sfx(phase_sound, phase_sound_db)


func _on_gauge_event(index: int, value: int) -> void:
	hud.pulse_gauge(false)
	_phase_impact()
	if _current:
		_current.notify_gauge_event(index, value)
	gauge_event.emit(_index, index, value)


## 满条了：定在下一个小节线切关（这之前剩下的几个音符照常打、照常计分，只是积累条不再动）
func _on_gauge_filled() -> void:
	hud.pulse_gauge(not _joins(_index + 1))  # 后面还接着同一段：只当过了一条线，不当满条
	_phase_impact()
	if _current:
		_current.notify_gauge_filled()
	gauge_filled.emit(_index)
	var bpb := chart.beats_per_bar
	_switch_at = (floorf(Conductor.song_beat / bpb) + 1.0) * bpb


func _on_beat(beat_index: int) -> void:
	if _current:
		_current.notify_beat(beat_index - int(_current.def.start_beat))


func _on_note_judged(note: NoteData, result: int, diff_sec: float) -> void:
	hud.show_judgement(result, diff_sec)
	if _current and note.section_index == _index:
		if not editing:
			gauge.apply(_current.gauge_result(note, result))
		_current.notify_judged(note, result)
		if _current.wants_hit_effects(note):
			hit_meow.play(result)
		if _current.wants_hit_effects(note) and result != NoteData.Result.MISS:
			screen_fx.punch_for(result)  # 整个画面顶一下（Perfect 最大）
			# 九宫格 / 万花筒把画面切碎时，命中特效放到镜头特效上面、对着上面那套判定圈放，不然会跟着被切碎
			var top := screen_fx.top_fx_layer()
			var fx_parent: Node2D = top if top else fx_layer
			var fx_radius: float = screen_fx.top_radius() if top else _current.hit_radius()
			var fx_at: Vector2 = screen_fx.top_center() if top else _current.to_global(_current.hit_position(note))
			var fx := StarBurst.create(result != NoteData.Result.GOOD)
			fx_parent.add_child(fx)
			fx.start_radius = fx_radius
			fx.global_position = fx_at
			if result == NoteData.Result.PERFECT:
				# Perfect 专属：判定圈上再炸开一圈冲击环
				var ring := ShockRing.create(null if top else _current)
				fx_parent.add_child(ring)
				ring.radius *= fx_radius
				ring.global_position = fx_at


func _on_empty_hit() -> void:
	if _current:
		_current.notify_empty_hit()


## 打开 / 关上游戏里的编辑面板（scripts/tools/game_editor.gd）
func toggle_editor() -> void:
	if _editor == null:
		_editor = GameEditor.new()
		add_child(_editor)
		_editor.setup(self)
	_editor.set_open(not editing)


## 回主菜单
func back_to_menu() -> void:
	Conductor.stop()
	get_tree().change_scene_to_file(Levels.MENU_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		return  # Esc 归暂停转盘管（scripts/pause_menu.gd）
	if _cleared and hud.result_label.visible:
		# 最终结算画面：按任意键马上去片尾字幕（不按也会自己去，见 _clear_level），字幕放完回主菜单
		_go_credits()
		return
	if key.physical_keycode == KEY_TAB and OS.is_debug_build():
		toggle_editor()
	elif key.physical_keycode == KEY_R:
		start_from(0)
	elif key.physical_keycode == KEY_C and OS.is_debug_build():
		# 试验：轮流切换 3D 关卡的漫画 shader 风格（见 scripts/fx/comic_style.gd）
		hud.show_note("LOOK: " + ComicStyle.next_style())
		if _current is Spin3DSection:
			(_current as Spin3DSection).apply_comic_style()
	elif key.physical_keycode == KEY_N and OS.is_debug_build():
		# 调试：直接把积累条加满，跳到下一个小关
		while not gauge.full and not _cleared:
			gauge.apply(NoteData.Result.PERFECT)
	elif OS.is_debug_build():
		var n := key.physical_keycode - KEY_1
		if n >= 0 and n < chart.sections.size():
			start_from(n)
