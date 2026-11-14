@tool
extends SpinSection
## 波纹：圆圈从中心的“喇叭”向外扩散，碰到外面固定的大圆环时按键。
## 是缩圈关的反方向。

@export var speaker_color := Color(0.75, 0.25, 0.45)
## 中心“喊出波纹”的猫 meme
@export var center_meme := "meow"
@export var inner_radius := 55.0
@export var outer_radius := 245.0
## 波纹从出现到碰到外环需要几拍
@export var approach_beats := 3.0

var _angle := 0.0
var _pulse := 0.0
var _ring_color := Color.WHITE
var _center: MemeSprite


func _ready() -> void:
	_center = MemeSprite.create(center_meme, inner_radius * 2.6)
	_center.z_index = 1
	add_child(_center)


func hit_position(_note: NoteData = null) -> Vector2:
	return Vector2.ZERO


func hit_radius() -> float:
	return outer_radius


func _update_spin(_local_beat: float, angle: float) -> void:
	center_on_screen()
	_angle = angle
	_pulse = lerpf(_pulse, 0.0, 0.15)
	_ring_color = _ring_color.lerp(Color.WHITE, 0.1)
	_center.scale = Vector2.ONE * (inner_radius * 2.6 / 128.0) * (1.0 + 0.18 * _pulse)
	queue_redraw()


func _on_beat(_beat_in_section: int) -> void:
	_pulse = 1.0


func _on_note_judged(_note: NoteData, result: int) -> void:
	_ring_color = result_color(result)


func _on_empty_hit() -> void:
	_ring_color = result_color(NoteData.Result.NONE)


func _draw() -> void:
	if def == null:
		return
	# 正在扩散的波纹
	for n in notes:
		if n.judged:
			continue
		var ahead := beats_until(n)
		if ahead > approach_beats:
			break
		var t := 1.0 - ahead / approach_beats  # 0 = 刚出现，1 = 碰到外环
		var c := sound_color(n)
		c.a = clampf(t / 0.2, 0.0, 1.0)
		draw_arc(Vector2.ZERO, inner_radius + t * (outer_radius - inner_radius), 0.0, TAU, 96, c, 6.0)
	# 外面的判定环
	draw_arc(Vector2.ZERO, outer_radius, 0.0, TAU, 96, _ring_color, 3.0 + 3.0 * _pulse)
	# 中心留一个淡淡的底，猫在上面
	draw_circle(Vector2.ZERO, inner_radius * (1.0 + 0.15 * _pulse), Color(speaker_color, 0.45))
	draw_title()
