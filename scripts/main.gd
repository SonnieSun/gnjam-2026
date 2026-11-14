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

@onready var section_host: Node2D = $SectionHost
@onready var fx_layer: Node2D = $FxLayer
@onready var judge: Judge = $Judge
@onready var gauge: Gauge = $Gauge
@onready var drum_kit: DrumKit = $DrumKit
@onready var hud = $HUD

var chart: SongChart
var _index := -1
var _current: SpinSection
var _switch_at := -1.0  # 积累条满了之后，定在第几拍切关（-1 = 还没满）
var _cleared := false


func _ready() -> void:
	# 谱面由主菜单选中的大关决定（见 scripts/core/levels.gd）；直接运行本场景时是第 1 大关
	var requested := Levels.take_editor_request()  # 从关卡编辑器点“试玩”进来的
	if requested >= 0:
		start_section = requested
	chart = Levels.build_chart()
	ComicStyle.set_by_name(Levels.look())
	drum_kit.use_chart(chart)
	Conductor.load_chart(chart)
	judge.load_chart(chart)

	Conductor.beat.connect(_on_beat)
	judge.note_judged.connect(_on_note_judged)
	judge.pressed.connect(drum_kit.play)
	judge.empty_hit.connect(_on_empty_hit)
	judge.combo_milestone.connect(func(combo: int): hud.show_combo_milestone(combo))
	judge.stats_changed.connect(func(): hud.set_stats(judge.score, judge.combo))
	gauge.changed.connect(_on_gauge_changed)
	gauge.event.connect(_on_gauge_event)
	gauge.filled.connect(_on_gauge_filled)

	start_from(start_section)


## 从某个小关重新开始（成绩清零，音乐从头放）
func start_from(index: int) -> void:
	index = clampi(index, 0, chart.sections.size() - 1)
	judge.reset()
	hud.reset()
	_cleared = false
	_switch_at = -1.0
	Conductor.play(-lead_in_beats)
	_enter(index, 0.0, false)


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
	hud.set_debug("%s  |  bar %d  beat %.2f  |  gauge %d/%d  |  [1-%d] jump  [N] next  [C] look  [R] restart  [Esc] menu" % [
		chart.sections[_index].title,
		int(Conductor.song_beat / chart.beats_per_bar) + 1,
		Conductor.song_beat,
		gauge.value, gauge.max_value,
		mini(chart.sections.size(), 9),
	])


## 进入第 index 个小关。at_beat = 它从全曲第几拍开始（必须落在小节线上，鼓谱才和音乐对得齐）。
func _enter(index: int, at_beat: float, animate: bool) -> void:
	var old := _current
	_index = index
	var def := chart.sections[index]
	def.start_beat = at_beat
	var first_note := at_beat + chart.rest_bars_on_switch * chart.beats_per_bar
	_current = def.scene.instantiate() as SpinSection
	_current.setup(def, judge.begin_section(index, def, chart.beats_per_bar, at_beat, first_note))
	section_host.add_child(_current)
	_current.enter()
	# 这一关的满条值和事件分数线：谱面里填了用谱面的，否则用关卡场景里填的，都没填用默认值
	var g_max := def.gauge_max if def.gauge_max > 0 else _current.gauge_max_override
	var g_events: Variant = null
	if def.use_gauge_events:
		g_events = def.gauge_events
	elif _current.custom_gauge_events:
		g_events = _current.gauge_events
	gauge.begin(g_max, g_events)
	_current.gauge_event_values = gauge.events
	section_entered.emit(index)

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
	hud.show_result(judge)
	level_cleared.emit()


func _on_gauge_changed(value: int, max_value: int) -> void:
	hud.set_gauge(value, max_value)
	if _current:
		_current.notify_gauge(value, max_value)


func _on_gauge_event(index: int, value: int) -> void:
	hud.pulse_gauge(false)
	if _current:
		_current.notify_gauge_event(index, value)
	gauge_event.emit(_index, index, value)


## 满条了：定在下一个小节线切关（这之前剩下的几个音符照常打、照常计分，只是积累条不再动）
func _on_gauge_filled() -> void:
	hud.pulse_gauge(true)
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
		gauge.apply(result)
		_current.notify_judged(note, result)
		if result == NoteData.Result.PERFECT or result == NoteData.Result.GOOD:
			var fx := StarBurst.create(result == NoteData.Result.PERFECT)
			fx_layer.add_child(fx)
			fx.start_radius = _current.hit_radius()
			fx.global_position = _current.to_global(_current.hit_position(note))


func _on_empty_hit() -> void:
	if _current:
		_current.notify_empty_hit()


## 回主菜单
func back_to_menu() -> void:
	Conductor.stop()
	get_tree().change_scene_to_file(Levels.MENU_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_R:
		start_from(0)
	elif key.physical_keycode == KEY_C:
		# 试验：轮流切换 3D 关卡的漫画 shader 风格（见 scripts/fx/comic_style.gd）
		hud.show_note("LOOK: " + ComicStyle.next_style())
		if _current is Spin3DSection:
			(_current as Spin3DSection).apply_comic_style()
	elif key.physical_keycode == KEY_N and OS.is_debug_build():
		# 调试：直接把积累条加满，跳到下一个小关
		while not gauge.full and not _cleared:
			gauge.apply(NoteData.Result.PERFECT)
	elif key.physical_keycode == KEY_ESCAPE:
		back_to_menu()
	elif OS.is_debug_build():
		var n := key.physical_keycode - KEY_1
		if n >= 0 and n < chart.sections.size():
			start_from(n)
