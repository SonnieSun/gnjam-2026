@tool
extends SpinSection
## 表盘：一根指针扫过圆形表盘，扫到表盘边缘的刻度音符时按键。
## 指针转一圈 = beats_per_rev 拍。

@export var dial_color := Color(0.16, 0.14, 0.24)
## 表盘正中的猫 meme
@export var center_meme := "grumpy"
@export var center_size := 170.0
@export var dial_radius := 235.0
@export var note_radius := 200.0

const START_ANGLE := -PI / 2
const SHOW_AHEAD := 0.85
const SWEEP := 0.7  # 指针后面拖着的扇形有多宽（弧度）

var _angle := 0.0
var _hand_color := Color.WHITE
var _center: MemeSprite


func _ready() -> void:
	_center = MemeSprite.create(center_meme, center_size)
	add_child(_center)


func _tip() -> Vector2:
	return Vector2.from_angle(START_ANGLE + _angle) * note_radius


func hit_position(_note: NoteData = null) -> Vector2:
	return _tip()


func hit_radius() -> float:
	return 18.0


func _update_spin(_local_beat: float, angle: float) -> void:
	center_on_screen()
	_angle = angle
	_hand_color = _hand_color.lerp(Color.WHITE, 0.1)
	queue_redraw()


func _on_note_judged(_note: NoteData, result: int) -> void:
	_hand_color = result_color(result)


func _on_empty_hit() -> void:
	_hand_color = result_color(NoteData.Result.NONE)


func _draw() -> void:
	if def == null:
		return
	# 表盘和 12 个刻度
	draw_circle(Vector2.ZERO, dial_radius, dial_color)
	draw_arc(Vector2.ZERO, dial_radius, 0.0, TAU, 96, dial_color.lightened(0.4), 4.0)
	for i in 12:
		var dir := Vector2.from_angle(i * TAU / 12.0)
		var inner := 0.86 if i % 3 == 0 else 0.92
		draw_line(dir * dial_radius * inner, dir * dial_radius * 0.98, dial_color.lightened(0.4), 3.0)
	# 指针扫过留下的扇形
	var hand := START_ANGLE + _angle
	var fan := PackedVector2Array([Vector2.ZERO])
	for i in 13:
		fan.append(Vector2.from_angle(hand - SWEEP + SWEEP * i / 12.0) * note_radius)
	draw_colored_polygon(fan, Color(_hand_color, 0.12))
	# 刻度音符
	var show_beats := def.beats_per_rev * SHOW_AHEAD
	for n in notes:
		if n.judged:
			continue
		var ahead := beats_until(n)
		if ahead > show_beats:
			break
		var a := START_ANGLE + (n.beat - def.start_beat) / def.beats_per_rev * TAU
		var c := sound_color(n)
		c.a = clampf((show_beats - ahead) / (show_beats * 0.2), 0.0, 1.0)
		var p := Vector2.from_angle(a) * note_radius
		draw_circle(p, 13.0, c)
		draw_circle(p, 6.0, Color(dial_color, c.a))
	# 指针
	draw_line(Vector2.ZERO, _tip(), _hand_color, 6.0)
	draw_arc(_tip(), 18.0, 0.0, TAU, 32, _hand_color, 3.0)
	draw_circle(Vector2.ZERO, 14.0, _hand_color)
	draw_title()
