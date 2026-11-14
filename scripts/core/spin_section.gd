@tool
class_name SpinSection
extends Node2D
## 所有旋转段落的基类。
## 子类只管“画面和反馈”，重写下面带下划线的钩子即可；
## 时间来自 Conductor，判定结果由 Main 转发过来。
##
## 编辑器预览：这个脚本和所有关卡脚本都带 @tool，在编辑器里单独打开某个关卡场景时，
## 会用一段假的鼓谱把画面跑起来，并画出游戏画面的边界框，方便摆美术。
## 预览只发生在编辑器里，不会改动场景文件，也不影响正式运行。
## 新写的关卡脚本第一行也要加 @tool 才会有预览。

@export_group("编辑器预览")
## 勾上 = 预览自动循环播放；取消 = 停在下面指定的那一拍
@export var preview_playing := true
## 不播放时停在第几拍（0 ~ 12），可以拖动来逐拍查看
@export_range(0.0, 12.0, 0.05) var preview_beat := 2.0
## 预览时转一圈用几拍（正式运行时这个值来自谱面）
@export var preview_beats_per_rev := 8.0
@export_group("")

const PREVIEW_BPM := 120.0
const PREVIEW_BEATS := 12.0
const PREVIEW_BARS: Array[String] = ["k...s...k.h.s...", "k.h...s...k.s...", "k...s.h.....s..."]

## 测试用：在正常运行时也强制走预览逻辑
static var force_preview := false

var def: SectionDef
## 本段的音符（绝对拍数，已按时间排序）
var notes: Array[NoteData] = []
var active := false


func setup(section_def: SectionDef, section_notes: Array[NoteData]) -> void:
	def = section_def
	notes = section_notes


func enter() -> void:
	active = true
	_on_enter()


func exit() -> void:
	active = false
	_on_exit()


## 当前歌曲拍数。关卡脚本里要用拍数时调这个，不要直接读 Conductor（编辑器里没有它）。
func song_beat() -> float:
	return _preview_now if _previewing() else Conductor.song_beat


## 段内拍数（段落开头 = 0）
func local_beat() -> float:
	return song_beat() - def.start_beat


## 当前旋转角度（弧度），转一圈 = def.beats_per_rev 拍
func spin_angle() -> float:
	return local_beat() / def.beats_per_rev * TAU


## 距离这个音符还有几拍（负数 = 已经过了）
func beats_until(note: NoteData) -> float:
	return note.beat - song_beat()


## 这个音符离判定点还差多少角度（弧度）
func angle_until(note: NoteData) -> float:
	return beats_until(note) / def.beats_per_rev * TAU


# ---- 画面上的小工具，子类随便用 ----

## 底鼓 / 军鼓 / 踩镲 各自的颜色
const SOUND_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.2), Color(1.0, 0.45, 0.7), Color(0.4, 0.9, 1.0),
]


func sound_color(note: NoteData) -> Color:
	return SOUND_COLORS[note.sound % SOUND_COLORS.size()]


## 判定结果对应的闪光颜色
static func result_color(result: int) -> Color:
	match result:
		NoteData.Result.PERFECT: return Color(1.0, 0.9, 0.2)
		NoteData.Result.GOOD: return Color(0.4, 1.0, 0.5)
		NoteData.Result.MISS: return Color(1.0, 0.3, 0.3)
	return Color(0.6, 0.6, 0.6)


## 游戏画面的大小。编辑器里返回项目设置的基准尺寸。
func screen_size() -> Vector2:
	if Engine.is_editor_hint():
		return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
				ProjectSettings.get_setting("display/window/size/viewport_height"))
	return get_viewport_rect().size


## 把段落原点放到屏幕中心（在 _update_spin 里调用）；shift 是相对屏幕中心的偏移。
## 编辑器预览时不挪位置（否则会改动场景），只记下偏移用来画边界框。
func center_on_screen(shift: Vector2 = Vector2.ZERO) -> void:
	_screen_shift = shift
	if not _previewing():
		position = screen_size() / 2.0 + shift


## 在屏幕底部画出段落标题（在 _draw 里调用，要求原点在屏幕中心）
func draw_title() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(-200.0, screen_size().y / 2.0 - 60.0),
			def.title, HORIZONTAL_ALIGNMENT_CENTER, 400.0, 28)


func _process(delta: float) -> void:
	if _previewing():
		_preview_tick(delta)
	if def:
		_update_spin(local_beat(), spin_angle())


# ---- 编辑器预览 ----

var _screen_shift := Vector2.ZERO
var _preview_now := 0.0
var _preview_clock := 0.0


func _previewing() -> bool:
	return Engine.is_editor_hint() or force_preview


func _preview_tick(delta: float) -> void:
	if def == null:
		# 造一份假的段落定义和鼓谱
		def = SectionDef.new()
		def.title = String(name)
		def.bars = PackedStringArray(PREVIEW_BARS)
		notes = []
		for d in def.parse_notes(4):
			var n := NoteData.new()
			n.beat = d.beat
			n.sound = d.sound
			notes.append(n)
	def.beats_per_rev = maxf(preview_beats_per_rev, 0.25)

	var before := _preview_now
	if preview_playing:
		_preview_clock += delta
		_preview_now = fmod(_preview_clock * PREVIEW_BPM / 60.0, PREVIEW_BEATS)
	else:
		_preview_now = preview_beat
	var moving_forward := preview_playing and _preview_now > before
	# 已经过了的音符当作“打中了”，这样能看到击中反馈
	for n in notes:
		var was_judged := n.judged
		n.judged = n.beat < _preview_now - 0.02
		if n.judged and not was_judged and moving_forward:
			_on_note_judged(n, NoteData.Result.PERFECT)
	if moving_forward and floori(_preview_now) != floori(before):
		_on_beat(floori(_preview_now))


func _notification(what: int) -> void:
	# 预览时画出游戏画面的边界（这个框不会出现在正式运行里）
	if what == NOTIFICATION_DRAW and _previewing():
		var size := screen_size()
		draw_rect(Rect2(-size / 2.0 - _screen_shift, size), Color(1.0, 0.4, 0.8, 0.9), false, 3.0)


# ---- 子类重写这些 ----

## 判定点（玩家交互的圆圈）在本段落里的本地坐标，命中特效会出现在这里。
## 有多个判定点的段落根据 note 返回对应的那个；note 可能是 null。
func hit_position(_note: NoteData = null) -> Vector2:
	return Vector2.ZERO


## 判定圈的半径，命中特效的星星从这个距离开始往外飞
func hit_radius() -> float:
	return 22.0


func _on_enter() -> void:
	pass


func _on_exit() -> void:
	pass


## 每帧调用。用 angle 直接设置旋转，不要用 delta 累加。
func _update_spin(_local_beat: float, _angle: float) -> void:
	pass


## 每拍一次（beat_in_section 从 0 开始）
func _on_beat(_beat_in_section: int) -> void:
	pass


## 音符被判定（result 是 NoteData.Result）
func _on_note_judged(_note: NoteData, _result: int) -> void:
	pass


## 玩家空按
func _on_empty_hit() -> void:
	pass
