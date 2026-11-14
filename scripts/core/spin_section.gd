@tool
class_name SpinSection
extends Node2D
## 所有旋转段落的基类。
## 子类只管“画面和反馈”，重写下面带下划线的钩子即可；
## 时间来自 Conductor，判定结果由 Main 转发过来。
##
## 编辑器预览：这个脚本和所有关卡脚本都带 @tool，在编辑器里单独打开某个关卡场景时，
## 会用一段假的鼓谱把画面跑起来，并画出游戏画面的边界框，方便摆美术。
## 预览只发生在编辑器里，不影响正式运行；保存场景时动过的节点会自动回到摆好的姿势。
## 想拖动场景里的猫图，先取消勾选“预览播放”。
## 新写的关卡脚本第一行也要加 @tool 才会有预览。

@export_group("击中手感")
## 每打中一下，step_rot 往前转多少（弧度）。漏打不转。
@export var step_angle := PI / 4
@export_group("积累条")
## 这一关的满条值。0 = 用 Gauge 节点的默认值
@export var gauge_max_override := 0
## 勾上 = 这一关用下面自己的事件分数线；不勾 = 用 Gauge 节点的默认分数线
@export var custom_gauge_events := false
## 这一关的事件分数线：积累条涨到这些分数时各触发一次 _on_gauge_event，
## 想要几个事件就填几个数（留空 = 这一关没有事件）。谱面里可以再单独覆盖。
@export var gauge_events := PackedInt32Array()
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

# ---- 由击中驱动的共用状态（基类自动更新，关卡脚本直接读）----
## 距离上一次打中 / 漏打 / 按键过了多少秒
var hit_age := 99.0
var miss_age := 99.0
var tap_age := 99.0
## “打中才转一格”的转角：每次打中目标值加 step_angle，实际值平滑追上去；漏打不动
var step_rot := 0.0
var step_rot_target := 0.0
## 一直慢慢自转、打中时被推一把的转角（适合地球这类一直在转的东西）
var free_spin := 0.0
var free_spin_vel := 0.3

# ---- 积累条（Main 通知过来，关卡脚本直接读）----
var gauge_value := 0
var gauge_max := 60
## 已经触发了几个事件（0 = 一个还没触发）
var gauge_events_fired := 0
## 这一关实际生效的事件分数线（从小到大）
var gauge_event_values := PackedInt32Array()
var _gauge_smooth := 0.0


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


## 这个小关打到哪了：0 = 刚开始，1 = 积累条满了（运镜之类用；跟着积累条平滑变化）。
## 编辑器预览里没有积累条，就按预览的拍子从 0 走到 1。
func progress() -> float:
	if _previewing():
		return clampf(local_beat() / maxf(def.length, 0.001), 0.0, 1.0)
	return _gauge_smooth


## 打中后的脉冲：打中瞬间是 1，很快衰减到 0
func pulse() -> float:
	return exp(-hit_age * 8.0)


# ---- Main 通过这三个入口通知关卡；它们先更新共用状态，再调对应的钩子 ----

func notify_beat(beat_in_section: int) -> void:
	_on_beat(beat_in_section)


func notify_judged(note: NoteData, result: int) -> void:
	if result == NoteData.Result.MISS:
		miss_age = 0.0
	else:
		hit_age = 0.0
		tap_age = 0.0
		step_rot_target += step_angle
		free_spin_vel += 6.0 if result == NoteData.Result.PERFECT else 3.5
	_on_note_judged(note, result)


## 积累条的数值变了
func notify_gauge(value: int, max_value: int) -> void:
	gauge_value = value
	gauge_max = max_value


## 积累条第一次涨过第 index 条事件分数线
func notify_gauge_event(index: int, value: int) -> void:
	gauge_events_fired = index
	_on_gauge_event(index, value)


## 积累条满了（马上要切到下一关）
func notify_gauge_filled() -> void:
	_on_gauge_filled()


func notify_empty_hit() -> void:
	tap_age = 0.0
	_on_empty_hit()


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


## 通用的缩圈音符画法：在 center 画一个半径 radius 的判定圈，
## 每个快到的音符画一个从外面收缩过来的圆环，和判定圈重合时就是该按的时候。
## ci 是画在哪个节点上（一般传 self）；travel 是圆环最远离判定圈多少像素。
func draw_approach_rings(ci: CanvasItem, center: Vector2, radius: float,
		approach_beats: float, travel: float) -> void:
	ci.draw_arc(center, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.9), 3.0)
	for n in notes:
		if n.judged:
			continue
		var ahead := beats_until(n)
		if ahead > approach_beats:
			break
		var k := clampf(ahead / approach_beats, 0.0, 1.0)
		var c := sound_color(n)
		c.a = 1.0 - k * 0.6
		ci.draw_arc(center, radius + k * travel, 0.0, TAU, 96, c, 6.0)
	if tap_age < 0.15:  # 每次按键都闪一圈
		ci.draw_arc(center, radius * (1.0 + tap_age), 0.0, TAU, 64,
				Color(1, 1, 1, 1.0 - tap_age / 0.15), 8.0)


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
	# 更新击中驱动的共用状态
	hit_age += delta
	miss_age += delta
	tap_age += delta
	free_spin_vel += (0.3 - free_spin_vel) * minf(1.0, delta * 2.5)
	free_spin += free_spin_vel * delta
	step_rot += (step_rot_target - step_rot) * minf(1.0, delta * 18.0)
	_gauge_smooth = lerpf(_gauge_smooth, float(gauge_value) / maxi(gauge_max, 1), minf(1.0, delta * 4.0))
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
		def.length = PREVIEW_BEATS
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
			notify_judged(n, NoteData.Result.PERFECT)
	if moving_forward and floori(_preview_now) != floori(before):
		notify_beat(floori(_preview_now))


# ---- 摆在场景里的 2D 美术（猫图等）：动画在摆好的姿势上叠加 ----

var _rest2d := {}  # 节点 -> [摆好的位置姿态, 摆好的颜色]


## 现在能不能动场景里的节点。编辑器里没勾“预览播放”时返回 false，并让动过的节点回到摆好的姿势，
## 这样美术可以放心拖动它们。让节点动起来的代码都要包在 if can_animate(): 里。
func can_animate() -> bool:
	if Engine.is_editor_hint() and not preview_playing:
		restore_rest2d()
		return false
	return true


## 这个节点在场景里摆好的位置姿态（第一次问的时候记下来）。
## 动画写成：node.transform = rest2d(node).scaled_local(...) 之类，不要写死位置和大小。
func rest2d(node: Node2D) -> Transform2D:
	if not _rest2d.has(node):
		_rest2d[node] = [node.transform, node.modulate]
	return _rest2d[node][0]


## 这个节点在场景里设的颜色（modulate）
func rest_modulate(node: Node2D) -> Color:
	rest2d(node)
	return _rest2d[node][1]


## 只是想知道它摆在哪（不打算动它）：有记录用记录，没有就读现在的
func placed(node: Node2D) -> Transform2D:
	return _rest2d[node][0] if _rest2d.has(node) else node.transform


## 所有动过的 2D 节点回到摆好的姿势
func restore_rest2d() -> void:
	for node: Node2D in _rest2d:
		if is_instance_valid(node):
			node.transform = _rest2d[node][0]
			node.modulate = _rest2d[node][1]
	_rest2d.clear()


func _notification(what: int) -> void:
	# 保存场景之前先回到摆好的姿势，免得把动到一半的样子存进文件
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		restore_rest2d()
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
## 积累条第一次涨过第 index 条事件分数线时调用（index 从 1 开始，value = 那条线的分数）。
## 有几条线、各在多少分，在场景根节点检查器的“积累条”一栏里填。
## 留给关卡自己发挥：多放几个物体、加特效之类。现在默认什么都不做。
func _on_gauge_event(_index: int, _value: int) -> void:
	pass


## 积累条满了时调用（之后在下一个小节线切到下一关）
func _on_gauge_filled() -> void:
	pass


func _on_empty_hit() -> void:
	pass
