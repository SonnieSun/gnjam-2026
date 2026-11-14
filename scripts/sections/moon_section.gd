@tool
extends SpinSection
## 月相：月亮一点点变圆，外圈的圆弧同时合拢；变成满月（圆弧闭合成整圆）的瞬间按键。
## 每个音符是一次“盈满”，适合节奏稀疏的段落。

@export var moon_color := Color(1.0, 0.95, 0.75)
## 月亮里的猫 meme：月亮越圆它越清楚，满月时完全显形
@export var center_meme := "flower"
@export var dark_color := Color(0.14, 0.15, 0.26)
@export var moon_radius := 150.0
## 一次盈满最长用几拍（两个音符离得更近时，用它们的间隔）
@export var max_approach_beats := 3.0

var _pulse := 0.0
var _flash := Color.WHITE
var _center: MemeSprite
var _phase := 0.0


func _ready() -> void:
	_center = MemeSprite.create(center_meme, moon_radius * 1.6)
	add_child(_center)


func hit_position(_note: NoteData = null) -> Vector2:
	return Vector2.ZERO


func hit_radius() -> float:
	return moon_radius + 30.0


func _update_spin(_local_beat: float, _angle: float) -> void:
	center_on_screen()
	_pulse = lerpf(_pulse, 0.0, 0.12)
	_flash = _flash.lerp(Color.WHITE, 0.1)
	_center.modulate = Color(1, 1, 1, clampf(_phase * 1.2 - 0.2, 0.0, 1.0))
	_center.scale = Vector2.ONE * (moon_radius * 1.6 / 128.0) * (0.8 + 0.2 * _phase + 0.12 * _pulse)
	queue_redraw()


func _on_note_judged(_note: NoteData, result: int) -> void:
	_flash = result_color(result)
	if result != NoteData.Result.MISS:
		_pulse = 1.0


func _on_empty_hit() -> void:
	_flash = result_color(NoteData.Result.NONE)


func _draw() -> void:
	if def == null:
		return
	# 找到下一个要打的音符，算出离“满月”还差多少
	var phase := 0.0
	var accent := Color(1, 1, 1, 0.3)
	for i in notes.size():
		var n := notes[i]
		if n.judged:
			continue
		var prev_beat := notes[i - 1].beat if i > 0 else def.start_beat
		var span := clampf(n.beat - prev_beat, 0.5, max_approach_beats)
		phase = clampf(1.0 - beats_until(n) / span, 0.0, 1.0)
		accent = sound_color(n)
		break
	_phase = phase

	var r := moon_radius * (1.0 + 0.08 * _pulse)
	draw_circle(Vector2.ZERO, r, dark_color)
	# 亮面：右边的圆弧 + 一条随月相移动的椭圆明暗线
	var lit := moon_color.lerp(_flash, 0.5)
	if phase > 0.97:
		draw_circle(Vector2.ZERO, r, lit)
	elif phase > 0.03:
		var k := 1.0 - 2.0 * phase  # 1 = 新月，-1 = 满月
		var pts := PackedVector2Array()
		for i in 25:
			var th := -PI / 2 + PI * i / 24.0
			pts.append(Vector2(cos(th), sin(th)) * r)
		for i in range(23, 0, -1):
			var th := -PI / 2 + PI * i / 24.0
			pts.append(Vector2(k * cos(th), sin(th)) * r)
		draw_colored_polygon(pts, lit)
	# 外圈：淡淡的整圆做参考，上面一段彩色圆弧逐渐合拢
	var ring_r := moon_radius + 30.0
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 96, Color(1, 1, 1, 0.15), 3.0)
	if phase > 0.0:
		draw_arc(Vector2.ZERO, ring_r, -PI / 2, -PI / 2 + phase * TAU, 96, accent, 8.0)
	draw_title()
