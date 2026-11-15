class_name NoteStyle
extends Node2D
## 音符的「表现方式」基类：同一份谱子（ChartPattern）可以用不同的样子画出来。
## 判定永远是 Conductor + Judge，这里只管画：给它拍子和音符列表，它负责把音符画到该在的位置。
##
## 每帧调 update_notes(beat, notes)。beat 用画面时间（Conductor.song_beat，或编辑器里拖动的播放头）。
## 音符被判定后调 judged(note, result)，出一下命中特效。
##
## 子类只要实现 _update() / _draw()，位置怎么算各不相同，但每个音符的“出现时间、发光、胀缩、旋转、大小、颜色”
## 统一用 fx(note) 算，所以谱面编辑器里调的属性在每种表现里意思都一样。
##
## 加一种新表现：继承这个类写一个脚本，登记到下面的 STYLES 里。

## 表现方式的 id -> 脚本
const STYLES := {
	"rings": "res://scripts/chart/styles/rings_style.gd",
	"orbit": "res://scripts/chart/styles/orbit_style.gd",
	"fall": "res://scripts/chart/styles/fall_style.gd",
	"highway": "res://scripts/chart/styles/highway_style.gd",
	"beam": "res://scripts/chart/styles/beam_style.gd",
}
## 给人看的名字
const STYLE_NAMES := {
	"rings": "圆圈往中心收",
	"orbit": "沿轨道对虚影",
	"fall": "2D 下落式",
	"highway": "3D 轨道从深处过来",
	"beam": "光圈沿光束套下",
}
const SOUND_COLORS: Array[Color] = [Color(1.0, 0.85, 0.2), Color(1.0, 0.45, 0.7), Color(0.4, 0.9, 1.0)]
const HIT_FLASH_SECONDS := 0.3

## 谱子的整体设置（轨道数、默认出现时间、转一圈几拍）从这里读
var pattern: ChartPattern
## 当前拍（画面时间）
var beat := 0.0
var notes: Array = []
## 命中特效：[{lane, age, color, note}]
var flashes: Array[Dictionary] = []


static func create(id: String) -> NoteStyle:
	var path: String = STYLES.get(id, STYLES["rings"])
	return (load(path) as GDScript).new() as NoteStyle


func update_notes(now_beat: float, note_list: Array) -> void:
	beat = now_beat
	notes = note_list
	var dt := get_process_delta_time()
	for i in range(flashes.size() - 1, -1, -1):
		flashes[i].age += dt
		if flashes[i].age >= HIT_FLASH_SECONDS:
			flashes.remove_at(i)
	_update()
	queue_redraw()


## 音符判定了：打中就在它的目标位置闪一下
func judged(note: NoteData, result: int) -> void:
	if result == NoteData.Result.MISS or result == NoteData.Result.NONE:
		return
	flashes.append({"lane": note.lane, "age": 0.0, "color": SpinSection.result_color(result), "note": note})
	_on_judged(note, result)


# ---- 子类实现 ----

func _update() -> void:
	pass


func _on_judged(_note: NoteData, _result: int) -> void:
	pass


# ---- 子类共用的小工具 ----

func lanes() -> int:
	return pattern.lanes if pattern else 1


func lane_of(n: NoteData) -> int:
	return clampi(n.lane, 0, lanes() - 1)


## 这个音符提前几拍出现
func lead_of(n: NoteData) -> float:
	if n.lead > 0.0:
		return n.lead
	return pattern.default_lead if pattern else 4.0


## 1 = 刚出现，0 = 该按的那一拍，负数 = 已经过了
func approach(n: NoteData) -> float:
	return (n.beat - beat) / maxf(lead_of(n), 0.01)


## 这个音符现在要不要画：出现了、还没判定（或者是还在按住的长按），过了判定点一小会儿还画着
func showing(n: NoteData) -> bool:
	var a := approach(n)
	if a > 1.0:
		return false
	if n.length > 0.0:
		return beat <= n.beat + n.length + 0.1 and not (n.judged and n.result == NoteData.Result.MISS)
	return not n.judged and a > -0.15


## 每个音符统一的表现参数：
##   alpha 刚出现时淡入；scale 大小 × 跟拍胀缩；angle 初始角度 + 自转（弧度）；
##   glow 发光强度（平时 + 跟拍闪）；color 颜色（没指定就按音色）；pulse 这一拍闪到哪（0~1）
func fx(n: NoteData) -> Dictionary:
	var lead := lead_of(n)
	var since := beat - (n.beat - lead)  # 出现了多少拍
	var p := pow(1.0 - fposmod(beat, 1.0), 3.0)
	var c: Color = n.color if n.color.a > 0.0 else SOUND_COLORS[n.sound % SOUND_COLORS.size()]
	return {
		"alpha": clampf(since / maxf(lead * 0.15, 0.01), 0.0, 1.0),
		"scale": n.size * (1.0 + n.throb * p),
		"angle": deg_to_rad(n.rot + n.spin * since),
		"glow": n.glow + n.pulse * p,
		"color": c,
		"pulse": p,
	}


## 2D 发光：在形状外面叠几圈半透明的光晕（glow 越大越亮越宽）
func draw_glow_ring(center: Vector2, radius: float, color: Color, glow: float, width: float) -> void:
	if glow <= 0.01:
		return
	for k in 3:
		var w := width * (2.0 + k * 2.0) * minf(glow, 2.0)
		var c := Color(color, clampf(glow * 0.22 / (k + 1), 0.0, 0.6))
		draw_arc(center, radius, 0.0, TAU, 72, c, w, true)


func draw_glow_dot(center: Vector2, radius: float, color: Color, glow: float) -> void:
	if glow <= 0.01:
		return
	for k in 3:
		draw_circle(center, radius * (1.3 + k * 0.45) * (0.6 + minf(glow, 2.0) * 0.4),
				Color(color, clampf(glow * 0.18 / (k + 1), 0.0, 0.5)))


## 一圈虚线组成的环：转起来看得出角度
func draw_dashed_ring(center: Vector2, radius: float, color: Color, width: float, angle: float, dashes := 12) -> void:
	var step := TAU / dashes
	for i in dashes:
		var a0 := angle + i * step
		draw_arc(center, radius, a0, a0 + step * 0.62, 8, color, width, true)


func area() -> Vector2:
	return get_viewport_rect().size


# ---- 节拍辅助线 ----
# 每一拍一条线，和音符用同一套「从远处过来」的位置：
#   要按的拍子（有音符，包括不在整拍上的音符）：音符颜色的实线，越靠近判定越亮、越粗、越偏白；
#   不用按的拍子：淡淡的虚线，只用来数拍子。
# 每种表现方式在 _draw_guide(g) 里按自己的形状画（圆圈、横线、轨道上的刻度、3D 里的线……）。

## 现在要画的辅助线，从远到近。每项：
##   beat 第几拍  a 远近（1 = 刚出现，0 = 判定点）  solid 是不是要按的拍子
##   color 颜色  k 有多近（0 远 ~ 1 到了，实线用来变亮变粗）  lanes 这一拍的音符在哪些轨道（虚线是空的）
func guides() -> Array[Dictionary]:
	if pattern == null or not pattern.beat_guides:
		var none: Array[Dictionary] = []
		return none
	var list := BeatGuides.compute(notes, beat, pattern.default_lead, pattern.guide_every,
			func(n: NoteData) -> Color: return fx(n).color, lead_of)
	for g in list:
		var ls := []
		for n: NoteData in g.notes:
			ls.append(lane_of(n))
		g["lanes"] = ls
	return list


## 一条辅助线该用的颜色和粗细倍数（规则见 BeatGuides.look）
func guide_look(g: Dictionary) -> Dictionary:
	return BeatGuides.look(g)


func _draw_guides() -> void:
	for g in guides():
		_draw_guide(g)


## 子类实现：按自己的形状画一条辅助线
func _draw_guide(_g: Dictionary) -> void:
	pass


## 判定点「预亮」（规则见 BeatGuides.anticipation）。lane >= 0 时只看那条轨道
func anticipation(lane := -1) -> Dictionary:
	return BeatGuides.anticipation(notes, beat, func(n: NoteData) -> Color: return fx(n).color,
			func(n: NoteData) -> bool: return lane < 0 or lane_of(n) == lane)


## 判定圈 / 判定线预亮后的颜色和粗细倍数
func target_look(lane := -1) -> Dictionary:
	return BeatGuides.target_look(anticipation(lane))


## 虚线折线（3D 投影过来的圆圈用）
func draw_dashed_polyline(pts: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(0, pts.size() - 1, 2):
		draw_line(pts[i], pts[i + 1], color, width, true)
