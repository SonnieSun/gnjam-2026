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
## 打中时整个画面顶一下（Main/ScreenFx 的 punch）在这一关乘多少倍。
## 这一关自己的镜头已经会在打中时往前推的话调小一点，免得两样叠起来太晃；0 = 这一关不顶
@export_range(0.0, 2.0, 0.05) var screen_punch := 1.0
@export_group("积累条")
## 这一关的满条值。0 = 用 Gauge 节点的默认值
@export var gauge_max_override := 0
## 勾上 = 这一关用下面自己的事件分数线；不勾 = 用 Gauge 节点的默认分数线
@export var custom_gauge_events := false
## 这一关的事件分数线：积累条涨到这些分数时各触发一次 _on_gauge_event，
## 想要几个事件就填几个数（留空 = 这一关没有事件）。谱面里可以再单独覆盖。
@export var gauge_events := PackedInt32Array()
@export_group("节拍辅助线")
## 每拍一条辅助线：要按的拍子是音符颜色的实线（越靠近判定越亮越粗），不用按的拍子是淡虚线；
## 判定点在音符到之前一拍开始染色变亮。规则统一在 scripts/chart/beat_guides.gd
@export var beat_guides := true
## 虚线隔几拍一条（1 = 每拍，0.5 = 每半拍）
@export_range(0.125, 4.0, 0.125) var guide_every := 1.0
@export_group("视觉焦点")
## 判定点周围留一块干净的区域，外面慢慢压暗（压在音符和辅助线下面），让眼睛集中在判定线上。0 = 不压暗
@export_range(0.0, 0.8, 0.05) var focus_dim := 0.35
## 判定圈半径的几倍以内保持原样、几倍以外压到最暗
@export var focus_clear := 1.8
@export var focus_soft := 4.5
@export_group("编辑器预览")
## 勾上 = 预览自动循环播放；取消 = 停在下面指定的那一拍
@export var preview_playing := true
## 不播放时停在第几拍（0 ~ 12），可以拖动来逐拍查看
@export_range(0.0, 12.0, 0.05) var preview_beat := 2.0
## 预览时转一圈用几拍（正式运行时这个值来自谱面）
@export var preview_beats_per_rev := 8.0
@export_group("")

const PREVIEW_BPM := 160.0
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
## 现在套着哪种全屏镜头特效（"" = 没有；"grid3" 九宫格、"kaleido" 万花筒……）
var screen_fx := ""


func setup(section_def: SectionDef, section_notes: Array[NoteData]) -> void:
	def = section_def
	notes = section_notes


func enter() -> void:
	active = true
	_start_note_style()
	_on_enter()


func exit() -> void:
	active = false
	if _style_layer:
		_style_layer.queue_free()
		_style_layer = null
		note_style = null
	_on_exit()


# ---- 谱面编辑器的表现方式（ChartPattern.use_style）----

## 谱子勾了“游戏里用这个表现方式”时，音符由它画（叠在关卡画面上）
var note_style: NoteStyle
## 关掉 = 不自己叠表现方式（谱面编辑器的预览自己叠一层，就把这个关掉）
var allow_note_style := true
var _style_layer: CanvasLayer


## 关卡自己要不要画音符：谱子交给表现方式画时返回 false
func draws_own_notes() -> bool:
	return not (def and def.chart and def.chart.use_style)


## 关卡画音符时用这个代替 notes：表现方式接管时是空的，关卡自己的圆圈 / 水果 / 光圈就都不出来了
func own_notes() -> Array[NoteData]:
	if draws_own_notes():
		return notes
	var none: Array[NoteData] = []
	return none


# ---- 视觉焦点 ----

var _focus_amount := 0.0  # 现在压暗了多少（0~1）：有音符要来时压暗，歇着的时候慢慢松开
var _focus_tex: GradientTexture2D


## 画视觉焦点：center / radius 是判定圈（关卡画音符之前先调这个，压暗就在音符下面）
func draw_focus(ci: CanvasItem, center: Vector2, radius: float, squash := 1.0) -> void:
	if focus_dim <= 0.0 or _focus_amount <= 0.01 or not draws_own_notes():
		return
	if _focus_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0))
		g.set_color(1, Color(0, 0, 0, 1))
		g.set_offset(0, clampf(focus_clear / maxf(focus_soft, 0.01), 0.0, 0.95))
		g.set_offset(1, 1.0)
		_focus_tex = GradientTexture2D.new()
		_focus_tex.gradient = g
		_focus_tex.fill = GradientTexture2D.FILL_RADIAL
		_focus_tex.fill_from = Vector2(0.5, 0.5)
		_focus_tex.fill_to = Vector2(1.0, 0.5)
		_focus_tex.width = 256
		_focus_tex.height = 256
	var tint := Color(1, 1, 1, focus_dim * _focus_amount)
	var half := Vector2(radius * focus_soft, radius * focus_soft * squash)
	var inner := Rect2(center - half, half * 2.0)
	ci.draw_texture_rect(_focus_tex, inner, false, tint)
	# 渐变框外面的部分一样压暗
	var big := maxf(screen_size().length(), 2000.0) * 2.0
	var dark := Color(0, 0, 0, focus_dim * _focus_amount)
	var l := center.x - big
	var t := center.y - big
	ci.draw_rect(Rect2(l, t, big * 2.0, inner.position.y - t), dark)
	ci.draw_rect(Rect2(l, inner.end.y, big * 2.0, center.y + big - inner.end.y), dark)
	ci.draw_rect(Rect2(l, inner.position.y, inner.position.x - l, inner.size.y), dark)
	ci.draw_rect(Rect2(inner.end.x, inner.position.y, center.x + big - inner.end.x, inner.size.y), dark)


func _update_focus(delta: float) -> void:
	var want := 0.0
	var now := song_beat()
	for n in notes:
		if n.judged:
			continue
		var ahead := n.beat - now
		if ahead > 4.0:
			break
		if ahead > -0.2:
			want = 1.0
			break
	_focus_amount = move_toward(_focus_amount, want, delta * (2.0 if want > _focus_amount else 0.6))


# ---- 节拍辅助线（规则在 BeatGuides）----

## 现在要画的辅助线（见 BeatGuides.compute）。lead = 这一关音符提前几拍出现
## include_solid = false：音符本身就是缩圈的关卡用（实线会和音符完全重合，只画虚线）
func guide_list(lead: float, note_list: Variant = null, include_solid := true) -> Array[Dictionary]:
	if not beat_guides or not draws_own_notes():
		var none: Array[Dictionary] = []
		return none
	return BeatGuides.compute(note_list if note_list != null else notes, song_beat(), lead, guide_every, guide_color,
			Callable(), include_solid)


## 辅助线（和预亮）用什么颜色：和关卡画音符的颜色一致。关卡用自己的一套颜色时重写这个
func guide_color(note: NoteData) -> Color:
	return sound_color(note)


## 判定圈 / 判定线预亮后的样子（见 BeatGuides.target_look）。base = 判定圈平时的颜色
func target_look(base := Color.WHITE, filter := Callable()) -> Dictionary:
	if not beat_guides or not draws_own_notes():
		return {"color": base, "width": 1.0, "k": 0.0}
	return BeatGuides.target_look(BeatGuides.anticipation(notes, song_beat(), guide_color, filter), base)


## 通用画法：判定点外面一圈圈的辅助线，和“缩圈音符”同一种几何（远近 a 的那一拍在 radius + a × travel）。
## 音符不是缩圈的关卡也用这个：辅助线围着判定点收过来，提示「第几拍该按」。
## note_target(note) -> [圆心, 半径]：每个音符的判定点不一样时给（实线画在音符自己的判定点上）
func draw_target_guides(ci: CanvasItem, center: Vector2, radius: float, travel: float, lead: float,
		note_target := Callable(), squash := 1.0, scale_x := 1.0, include_solid := true) -> void:
	for g in guide_list(lead, null, include_solid):
		var l := BeatGuides.look(g)
		var a := clampf(g.a, 0.0, 1.0)
		if g.solid and note_target.is_valid():
			var done := {}
			for n: NoteData in g.notes:
				var tgt: Array = note_target.call(n)
				if done.has(tgt[0]):
					continue
				done[tgt[0]] = true
				BeatGuides.draw_ring(ci, tgt[0], float(tgt[1]) + a * travel, l, 3.0, squash, scale_x)
		else:
			BeatGuides.draw_ring(ci, center, radius + a * travel, l, 3.0, squash, scale_x)


## 缩圈音符的样子（第 1 关调好的手感，各关共用）：刚出现时半透明、细，越靠近判定圈越亮、越粗、略偏白，
## 最后一段外面带一圈柔光。t = 远近（1 = 刚出现，0 = 到判定圈）。返回 {color, width, glow}
func approach_ring_look(t: float, base: Color, far_alpha := 0.5, width_far := 8.0, width_near := 14.0) -> Dictionary:
	var k := 1.0 - clampf(t, 0.0, 1.0)
	var c := base.lerp(Color.WHITE, k * k * 0.3)
	c.a = clampf((1.0 - t) / 0.15, 0.0, 1.0) * lerpf(far_alpha, 1.0, pow(k, 1.5))
	return {"color": c, "width": lerpf(width_far, width_near, k), "glow": c.a * maxf(k - 0.5, 0.0) * 0.6}


## 按 approach_ring_look 的样子画一圈（squash < 1 = 透视压扁的椭圆）
func draw_approach_ring(ci: CanvasItem, center: Vector2, r: float, look: Dictionary, squash := 1.0, scale_x := 1.0) -> void:
	var c: Color = look.color
	if look.glow > 0.0:
		BeatGuides.draw_ring(ci, center, r, {"color": Color(c, look.glow), "width": 1.0, "dashed": false},
				look.width * 2.6, squash, scale_x)
	BeatGuides.draw_ring(ci, center, r, {"color": c, "width": 1.0, "dashed": false}, look.width, squash, scale_x)


## 预亮的判定圈：平时的样子 + 音符快到时染色、变粗、外面一圈光晕
func draw_lit_target(ci: CanvasItem, center: Vector2, radius: float, base := Color.WHITE, width := 3.0,
		squash := 1.0, scale_x := 1.0) -> void:
	var t := target_look(base)
	BeatGuides.draw_target_glow(ci, center, radius, t, squash, scale_x)
	BeatGuides.draw_ring(ci, center, radius, {"color": Color(t.color, base.a), "width": t.width, "dashed": false},
			width, squash, scale_x)


func _start_note_style() -> void:
	if draws_own_notes() or not allow_note_style or Engine.is_editor_hint():
		return
	_style_layer = CanvasLayer.new()
	_style_layer.layer = 5
	add_child(_style_layer)
	note_style = NoteStyle.create(def.chart.style)
	note_style.pattern = def.chart
	_style_layer.add_child(note_style)


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
		match result:
			NoteData.Result.PERFECT: free_spin_vel += 6.0
			NoteData.Result.GREAT: free_spin_vel += 5.0
			_: free_spin_vel += 3.5
	if note_style:
		note_style.judged(note, result)
	_on_note_judged(note, result)


## 特殊小关可让蓄力音符只积攒力量，到正式击打时才推进过关条。
## 判定与成绩仍由 Judge 统一处理，其他小关默认沿用原规则。
func gauge_result(_note: NoteData, result: int) -> int:
	return result


## 主场景里的 Judge（编辑器预览里没有，返回 null）
func main_judge() -> Judge:
	var main := get_parent().get_parent() if get_parent() else null
	if main == null:
		return null
	return main.get("judge") as Judge


## 蓄力段可以保留鼓声与判定，只在正式击打时播放喵声和大范围命中特效。
func wants_hit_effects(_note: NoteData) -> bool:
	return true


## 积累条的数值变了
func notify_gauge(value: int, max_value: int) -> void:
	gauge_value = value
	gauge_max = max_value


## 积累条第一次涨过第 index 条事件分数线
func notify_gauge_event(index: int, value: int) -> void:
	gauge_events_fired = index
	_on_gauge_event(index, value)


## 全屏镜头特效换了（id 见 scripts/fx/screen_fx.gd 的 EFFECTS，"" = 原样）
func notify_screen_fx(id: String) -> void:
	screen_fx = id
	_on_screen_fx(id)


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


## 所有长按音符统一用的颜色（亮粉，和画面里别的颜色拉开）：头圈、带子、辅助线、按住时的判定圈和进度圈
const HOLD_COLOR := Color(1.0, 0.15, 0.7)


func sound_color(note: NoteData) -> Color:
	return SOUND_COLORS[note.sound % SOUND_COLORS.size()]


## 判定结果对应的闪光颜色
static func result_color(result: int) -> Color:
	match result:
		NoteData.Result.PERFECT: return Color(1.0, 0.9, 0.2)
		NoteData.Result.GREAT: return Color(0.3, 0.85, 1.0)
		NoteData.Result.GOOD: return Color(0.4, 1.0, 0.5)
		NoteData.Result.MISS: return Color(1.0, 0.3, 0.3)
	return Color(0.6, 0.6, 0.6)


## 通用的缩圈音符画法：在 center 画一个半径 radius 的判定圈，
## 每个快到的音符画一个从外面收缩过来的圆环，和判定圈重合时就是该按的时候。
## ci 是画在哪个节点上（一般传 self）；travel 是圆环最远离判定圈多少像素。
func draw_approach_rings(ci: CanvasItem, center: Vector2, radius: float,
		approach_beats: float, travel: float) -> void:
	draw_focus(ci, center, radius)
	draw_lit_target(ci, center, radius, Color(1, 1, 1, 0.9))
	draw_target_guides(ci, center, radius, travel, approach_beats, Callable(), 1.0, 1.0, false)  # 音符就是缩圈，只补虚线
	for n in own_notes():
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
	if note_style:
		note_style.update_notes(song_beat(), notes)
	if def:
		_update_focus(delta)


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


## 全屏镜头特效换了时调用（比如万花筒里想把自己的 3D 音符藏起来）
func _on_screen_fx(_id: String) -> void:
	pass


## 积累条满了时调用（之后在下一个小节线切到下一关）
func _on_gauge_filled() -> void:
	pass


func _on_empty_hit() -> void:
	pass
