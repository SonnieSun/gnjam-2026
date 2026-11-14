@tool
extends SpinSection
## 缩圈段落：圆圈从屏幕外向目标圆收缩，和目标圆的白色轮廓重合时按键。
## - 只有一个目标（target_offsets 留一个点）= 第二关：所有圈都往中心收。
## - 多个目标 = 第三关：每个音符按鼓的种类去不同的目标圆
##   （底鼓 -> 第 1 个，军鼓 -> 第 2 个，踩镲 -> 第 3 个，目标不够就循环）。
## 目标圆本身仍然按 beats_per_rev 自转。

@export var disc_color := Color(0.15, 0.4, 0.75)
## 每个目标圆上放哪个猫 meme（MemeLib 里的名字），目标比名字多就循环用。
## 只有两帧的（比如 popcat）击中时张一下嘴，其他的一直循环播放。
@export var memes := PackedStringArray(["popcat"])
## 目标圆上的猫要不要跟着节拍旋转（转一圈 = beats_per_rev 拍）
@export var spin_memes := false
## 各个目标圆相对屏幕中心的位置
@export var target_offsets := PackedVector2Array([Vector2.ZERO])
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
var _cat_base_scale := Vector2.ONE


func _ready() -> void:
	for i in target_offsets.size():
		var cat := MemeSprite.create(memes[i % memes.size()], target_radius * 1.7)
		if cat.frame_count == 2:
			cat.mode = MemeSprite.Mode.MANUAL
			cat.idle_frame = 1  # popcat：第 1 帧闭嘴，第 0 帧张嘴
			cat.frame = 1
		cat.position = target_offsets[i]
		cat.z_index = 1  # 盖在自己画的圆盘上面
		add_child(cat)
		_cats.append(cat)
	_cat_base_scale = _cats[0].scale


## 这个音符去哪个目标圆
func target_index(note: NoteData) -> int:
	return note.sound % target_offsets.size()


func hit_position(note: NoteData = null) -> Vector2:
	return target_offsets[target_index(note)] if note else target_offsets[0]


func hit_radius() -> float:
	return target_radius


func _update_spin(_local_beat: float, angle: float) -> void:
	center_on_screen()
	_angle = angle
	for cat in _cats:
		cat.scale = cat.scale.lerp(_cat_base_scale, 0.2)
		if spin_memes:
			cat.rotation = angle
	queue_redraw()


func _on_beat(_beat_in_section: int) -> void:
	for cat in _cats:
		cat.scale = _cat_base_scale * 1.12


func _on_note_judged(note: NoteData, result: int) -> void:
	var cat := _cats[target_index(note)]
	if result != NoteData.Result.MISS and cat.frame_count == 2:
		cat.flash_frame(0, 0.14)
		cat.scale = _cat_base_scale * 1.25
	match result:
		NoteData.Result.PERFECT: _flash(cat, Color(1.0, 0.9, 0.2))
		NoteData.Result.GOOD: _flash(cat, Color(0.4, 1.0, 0.5))
		NoteData.Result.MISS: _flash(cat, Color(1.0, 0.3, 0.3))


func _on_empty_hit() -> void:
	for cat in _cats:
		_flash(cat, Color(0.6, 0.6, 0.6))


func _flash(cat: MemeSprite, c: Color) -> void:
	cat.modulate = c
	create_tween().tween_property(cat, "modulate", Color.WHITE, 0.25)


func _draw() -> void:
	if def == null:
		return
	# 目标圆：圆盘 + 自转的辐条 + 白色判定轮廓
	for offset in target_offsets:
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
