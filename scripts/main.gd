extends Node2D
## 游戏本体：加载谱面，按拍数切换 SectionHost 下的旋转段落，
## 并把节拍 / 判定事件转发给当前段落和 HUD。

## 调试用：从第几段开始（0 起）
@export var start_section := 0
## 开始前的预备拍数。从中间某段开始时，会从该段之前这么多拍的地方放起。
@export var lead_in_beats := 8.0

@onready var section_host: Node2D = $SectionHost
@onready var fx_layer: Node2D = $FxLayer
@onready var judge: Judge = $Judge
@onready var drum_kit: DrumKit = $DrumKit
@onready var hud = $HUD

var chart: SongChart
var _index := -1
var _min_index := 0  # 预备拍期间不要切回前一段
var _current: SpinSection


func _ready() -> void:
	# 谱面：所有关卡画法轮流展示，每关约 6 秒。以后有别的谱面就换这一行。
	chart = ShowcaseChart.build()
	drum_kit.use_chart(chart)
	Conductor.load_chart(chart)
	judge.load_chart(chart)

	Conductor.beat.connect(_on_beat)
	Conductor.song_finished.connect(_on_song_finished)
	judge.note_judged.connect(_on_note_judged)
	judge.pressed.connect(drum_kit.play)
	judge.empty_hit.connect(_on_empty_hit)
	judge.combo_milestone.connect(func(combo: int): hud.show_combo_milestone(combo))
	judge.stats_changed.connect(func(): hud.set_stats(judge.score, judge.combo))

	start_from(start_section)


## 从某一段的开头开始播放（成绩清零）
func start_from(index: int) -> void:
	index = clampi(index, 0, chart.sections.size() - 1)
	var from_beat := chart.sections[index].start_beat
	judge.reset(from_beat)
	hud.reset()
	_min_index = index
	Conductor.play(from_beat - lead_in_beats)
	_switch_to(index, false)


func _process(_delta: float) -> void:
	if not Conductor.playing:
		return
	var i := maxi(chart.section_index_at(Conductor.song_beat), _min_index)
	if i != _index:
		_switch_to(i, true)
	hud.set_debug("%s  |  bar %d  beat %.2f  |  [1-%d] jump  [R] restart" % [
		chart.sections[_index].title,
		int(Conductor.song_beat / chart.beats_per_bar) + 1,
		Conductor.song_beat,
		chart.sections.size(),
	])


func _switch_to(index: int, animate: bool) -> void:
	var old := _current
	_index = index
	var def := chart.sections[index]
	_current = def.scene.instantiate() as SpinSection
	_current.setup(def, judge.notes_for_section(index))
	section_host.add_child(_current)
	_current.enter()

	if old:
		old.exit()
	if not animate:
		if old:
			old.queue_free()
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


func _on_beat(beat_index: int) -> void:
	if _current:
		_current._on_beat(beat_index - int(_current.def.start_beat))


func _on_note_judged(note: NoteData, result: int, diff_sec: float) -> void:
	hud.show_judgement(result, diff_sec)
	if _current and note.section_index == _index:
		_current._on_note_judged(note, result)
		if result == NoteData.Result.PERFECT or result == NoteData.Result.GOOD:
			var fx := StarBurst.create(result == NoteData.Result.PERFECT)
			fx_layer.add_child(fx)
			fx.start_radius = _current.hit_radius()
			fx.global_position = _current.to_global(_current.hit_position(note))


func _on_empty_hit() -> void:
	if _current:
		_current._on_empty_hit()


func _on_song_finished() -> void:
	hud.show_result(judge)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_R:
		start_from(0)
	elif OS.is_debug_build():
		var n := key.physical_keycode - KEY_1
		if n >= 0 and n < chart.sections.size():
			start_from(n)
