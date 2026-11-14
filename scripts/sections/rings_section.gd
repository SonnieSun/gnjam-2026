@tool
extends SpinSection
## 同心环：三层圆环各自旋转，底鼓 / 军鼓 / 踩镲 的音符分别固定在内 / 中 / 外环上，
## 转到正上方各自的判定圈时按键。
## 圆环正中的猫摆在场景里（Center），动画跟着拍子走（每两拍放一遍）。

@export var ring_radii := PackedFloat32Array([105.0, 170.0, 235.0])
## 每层转一圈的拍数 = beats_per_rev * 这个倍数；负数 = 反方向转
@export var rev_multipliers := PackedFloat32Array([1.0, -1.0, 1.5])

const HIT_ANGLE := -PI / 2
const SHOW_AHEAD := 0.8

var _flash: Array[Color] = [Color.WHITE, Color.WHITE, Color.WHITE]

@onready var _center: MemeSprite = get_node_or_null("%Center")


func _ring(note: NoteData) -> int:
	return note.sound % ring_radii.size()


func hit_position(note: NoteData = null) -> Vector2:
	return Vector2(0.0, -ring_radii[_ring(note) if note else 0])


func hit_radius() -> float:
	return 18.0


func _update_spin(_local_beat: float, _angle: float) -> void:
	center_on_screen()
	if _center and can_animate():
		_center.set_progress(_local_beat / 2.0)
	for i in _flash.size():
		_flash[i] = _flash[i].lerp(Color.WHITE, 0.1)
	queue_redraw()


func _on_note_judged(note: NoteData, result: int) -> void:
	_flash[_ring(note)] = result_color(result)


func _on_empty_hit() -> void:
	for i in _flash.size():
		_flash[i] = result_color(NoteData.Result.NONE)


func _draw() -> void:
	if def == null:
		return
	var lb := local_beat()
	for k in ring_radii.size():
		var r := ring_radii[k]
		var beats := def.beats_per_rev * rev_multipliers[k]  # 带方向的一圈拍数
		var base := SOUND_COLORS[k % SOUND_COLORS.size()]
		# 环带 + 跟着转的刻痕，让人看得出它在转
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color(base, 0.18), 22.0)
		var rot := lb / beats * TAU
		for i in 8:
			var dir := Vector2.from_angle(rot + i * TAU / 8.0)
			draw_line(dir * (r - 11.0), dir * (r + 11.0), Color(base, 0.35), 2.0)
		# 这一层的判定圈
		draw_arc(Vector2(0.0, -r), 18.0, 0.0, TAU, 32, _flash[k], 3.0)
	# 音符
	for n in notes:
		if n.judged:
			continue
		var k := _ring(n)
		var beats := def.beats_per_rev * rev_multipliers[k]
		var show_beats := absf(beats) * SHOW_AHEAD
		var ahead := beats_until(n)
		if ahead > show_beats:
			continue
		var a := HIT_ANGLE - ahead / beats * TAU
		var c := sound_color(n)
		c.a = clampf((show_beats - ahead) / (show_beats * 0.2), 0.0, 1.0)
		draw_circle(Vector2.from_angle(a) * ring_radii[k], 12.0, c)
	draw_title()
