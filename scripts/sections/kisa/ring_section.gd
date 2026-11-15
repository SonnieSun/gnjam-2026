@tool
extends SpinSection
## （副本：原文件是 Sonnie 的 scripts/sections/ring_section.gd，main 上删掉了；迪斯科继承它，所以复制一份放在我们的文件夹里。）
## 缩圈段落：圆圈从屏幕外向目标圆收缩，和目标圆的白色轮廓重合时按键。
## - 只有一个目标（target_offsets 留一个点）= 第二关：所有圈都往中心收。
## - 多个目标 = 第三关：每个音符按鼓的种类去不同的目标圆
##   （底鼓 -> 第 1 个，军鼓 -> 第 2 个，踩镲 -> 第 3 个，目标不够就循环）。
## 目标圆本身仍然按 beats_per_rev 自转。
##
## 目标圆的个数和位置由场景决定：Targets 节点下面每放一只猫（挂 meme_sprite.gd 的节点）就是一个目标圆，
## 猫摆在哪目标圆就在哪。只有两帧的猫（比如 popcat）击中时张一下嘴，其他的一直循环播放。

@export var disc_color := Color(0.15, 0.4, 0.75)
## 目标圆上的猫要不要跟着节拍旋转（转一圈 = beats_per_rev 拍）
@export var spin_memes := false
@export var target_radius := 110.0
## 圆圈从出现到重合需要几拍
@export var approach_beats := 2.0
## 圆圈刚出现时的半径；0 = 自动取“刚好在屏幕外”
@export var start_radius := 0.0

## 不同鼓的圈用不同颜色：底鼓 / 军鼓 / 踩镲
const RING_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.2), Color(1.0, 0.45, 0.7), Color(0.4, 0.9, 1.0),
]

var _angle := 0.0
var _cats: Array[MemeSprite] = []
var _bump: Array[float] = []  # 每只猫现在被“顶大”了多少，逐渐回落


func _ready() -> void:
	var targets := get_node_or_null("Targets")
	if targets == null:
		push_error("%s：场景里缺少 Targets 节点（下面放猫）" % name)
		return
	for child in targets.get_children():
		var cat := child as MemeSprite
		if cat == null:
			continue
		if cat.frame_count == 2:
			cat.mode = MemeSprite.Mode.MANUAL
			cat.idle_frame = 1  # popcat：第 1 帧闭嘴，第 0 帧张嘴
			cat.frame = 1
		_cats.append(cat)
		_bump.append(0.0)


## 这个音符去哪个目标圆
func target_index(note: NoteData) -> int:
	return note.sound % maxi(_cats.size(), 1)


## 第 i 个目标圆的位置 = 那只猫在场景里摆的位置
func target_position(i: int) -> Vector2:
	return placed(_cats[i]).origin if i < _cats.size() else Vector2.ZERO


func hit_position(note: NoteData = null) -> Vector2:
	return target_position(target_index(note) if note else 0)


func hit_radius() -> float:
	return target_radius


func _update_spin(_local_beat: float, angle: float) -> void:
	center_on_screen()
	_angle = angle
	var animate := can_animate()
	for i in _cats.size():
		_bump[i] = lerpf(_bump[i], 0.0, 0.2)
		if animate:
			var pose := rest2d(_cats[i]).scaled_local(Vector2.ONE * (1.0 + _bump[i]))
			_cats[i].transform = pose.rotated_local(angle) if spin_memes else pose
	queue_redraw()


func _on_beat(_beat_in_section: int) -> void:
	for i in _bump.size():
		_bump[i] = 0.12


func _on_note_judged(note: NoteData, result: int) -> void:
	if _cats.is_empty():
		return
	var cat := _cats[target_index(note)]
	if result != NoteData.Result.MISS and cat.frame_count == 2:
		cat.flash_frame(0, 0.14)
		_bump[target_index(note)] = 0.25
	match result:
		NoteData.Result.PERFECT: _flash(cat, Color(1.0, 0.9, 0.2))
		NoteData.Result.GREAT: _flash(cat, Color(0.3, 0.85, 1.0))
		NoteData.Result.GOOD: _flash(cat, Color(0.4, 1.0, 0.5))
		NoteData.Result.MISS: _flash(cat, Color(1.0, 0.3, 0.3))


func _on_empty_hit() -> void:
	for cat in _cats:
		_flash(cat, Color(0.6, 0.6, 0.6))


func _flash(cat: MemeSprite, c: Color) -> void:
	if not can_animate():
		return
	var normal := rest_modulate(cat)
	cat.modulate = c
	create_tween().tween_property(cat, "modulate", normal, 0.25)


func _draw() -> void:
	if def == null:
		return
	# 目标圆：圆盘 + 自转的辐条 + 白色判定轮廓
	for k in _cats.size():
		var offset := target_position(k)
		draw_circle(offset, target_radius, disc_color)
		for i in 4:
			var dir := Vector2.from_angle(_angle + i * TAU / 4.0)
			draw_line(offset + dir * target_radius * 0.55, offset + dir * target_radius * 0.92,
					disc_color.lightened(0.3), 4.0)
		draw_arc(offset, target_radius, 0.0, TAU, 64, Color.WHITE, 3.0)
	# 正在靠近的圆圈
	var from_r := start_radius
	if from_r <= 0.0:
		from_r = screen_size().length() / 2.0 + 40.0
	for n in notes:
		if n.judged:
			continue
		var ahead := beats_until(n)
		if ahead > approach_beats:
			break
		var t := ahead / approach_beats  # 1 = 刚出现，0 = 重合，负数 = 已经过了
		var r := maxf(target_radius + t * (from_r - target_radius), 4.0)
		var c := RING_COLORS[n.sound % RING_COLORS.size()]
		c.a = clampf((1.0 - t) / 0.2, 0.0, 1.0)
		draw_arc(hit_position(n), r, 0.0, TAU, 96, c, 6.0)
	# 标题
	var size := screen_size()
	draw_string(ThemeDB.fallback_font, Vector2(-200.0, size.y / 2.0 - 60.0), def.title,
			HORIZONTAL_ALIGNMENT_CENTER, 400.0, 28)
