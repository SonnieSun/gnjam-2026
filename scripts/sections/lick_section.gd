@tool
extends SpinSection
## 小猫舔地球：中间是自转的地球，小猫趴在地球顶上低头舔。
## 音符固定在地球边缘，随地球转到小猫嘴边（顶部白圈）时按键，小猫会舔一下。
## 转一圈 = beats_per_rev 拍。

## 趴在地球顶上的小猫图片；舌头是代码画的，嘴的位置对不上就调 mouth_offset。
@export var cat_texture: Texture2D = preload("res://assets/art/cat_lick.svg")
## 嘴相对图片中心的位置（以 cat_size 为 1）
@export var mouth_offset := Vector2(0.0, 0.2)
## 想改用猫 meme 动图就在这里填 MemeLib 里的名字（比如 "lick"），填了就不用上面的图片；
## 击中时把动画从头放一遍。留空 = 用图片。
@export var meme := ""
@export var cat_size := 190.0
@export var radius := 160.0
@export var ocean_color := Color(0.13, 0.42, 0.85)
@export var land_color := Color(0.25, 0.68, 0.35)
## 整个画面往下挪一点，给顶上的小猫留位置
@export var center_shift := Vector2(0.0, 50.0)

const HIT_ANGLE := -PI / 2
const SHOW_AHEAD := 0.85

## 大陆的形状（单位圆坐标，跟着地球一起转）
var CONTINENTS := [
	PackedVector2Array([Vector2(-0.1, -0.75), Vector2(0.25, -0.8), Vector2(0.5, -0.55), Vector2(0.45, -0.25),
		Vector2(0.2, -0.1), Vector2(0.3, 0.2), Vector2(0.1, 0.45), Vector2(-0.1, 0.2),
		Vector2(-0.05, -0.1), Vector2(-0.3, -0.3), Vector2(-0.35, -0.6)]),
	PackedVector2Array([Vector2(-0.8, -0.2), Vector2(-0.55, -0.3), Vector2(-0.45, 0.0), Vector2(-0.6, 0.2),
		Vector2(-0.5, 0.5), Vector2(-0.6, 0.62), Vector2(-0.75, 0.4), Vector2(-0.85, 0.1)]),
	PackedVector2Array([Vector2(0.45, 0.45), Vector2(0.7, 0.4), Vector2(0.68, 0.58), Vector2(0.5, 0.7),
		Vector2(0.38, 0.6)]),
	PackedVector2Array([Vector2(0.65, -0.05), Vector2(0.8, 0.0), Vector2(0.72, 0.15), Vector2(0.6, 0.1)]),
]
## 云：[角度, 离圆心的距离, 大小]，转得比地球稍快
const CLOUDS := [[0.4, 0.55, 0.13], [2.1, 0.7, 0.1], [3.6, 0.35, 0.12], [5.0, 0.72, 0.09]]

var _angle := 0.0
var _lick := 0.0   # 1 = 舌头完全伸出，逐渐收回
var _bob := 0.0    # 跟着拍子点头
var _tint := Color.WHITE
var _cat: MemeSprite


func _ready() -> void:
	if meme != "":
		_cat = MemeSprite.create(meme, cat_size)
		_cat.mode = MemeSprite.Mode.MANUAL
		add_child(_cat)


func hit_position(_note: NoteData = null) -> Vector2:
	return Vector2.from_angle(HIT_ANGLE) * radius


func hit_radius() -> float:
	return 34.0  # 星星从稍远一点的地方炸开，别挡住小猫的脸


func _update_spin(_local_beat: float, angle: float) -> void:
	center_on_screen(center_shift)
	_angle = angle
	_lick = lerpf(_lick, 0.0, 0.14)
	_bob = lerpf(_bob, 0.0, 0.18)
	_tint = _tint.lerp(Color.WHITE, 0.1)
	# 小猫趴在判定圈上方，跟着拍子点头，舔的时候往下探
	if _cat:
		_cat.position = hit_position() + Vector2(0.0, -cat_size * 0.42 + 6.0 * _lick + 3.0 * _bob)
		_cat.modulate = _tint
	queue_redraw()


func _on_beat(_beat_in_section: int) -> void:
	_bob = 1.0


func _on_note_judged(_note: NoteData, result: int) -> void:
	if result == NoteData.Result.MISS:
		_tint = result_color(result)
	else:
		_lick = 1.0
		if _cat:
			_cat.play_once(0.35)


func _on_empty_hit() -> void:
	_lick = 0.6  # 空舔一下
	if _cat:
		_cat.play_once(0.35)


func _draw() -> void:
	if def == null:
		return
	# --- 地球 ---
	draw_circle(Vector2.ZERO, radius + 10.0, Color(0.55, 0.8, 1.0, 0.18))  # 大气层
	draw_circle(Vector2.ZERO, radius, ocean_color)
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE * radius)
	for shape: PackedVector2Array in CONTINENTS:
		draw_colored_polygon(shape, land_color)
	draw_set_transform(Vector2.ZERO, _angle * 1.15, Vector2.ONE * radius)
	for cloud: Array in CLOUDS:
		var cloud_pos: Vector2 = Vector2.from_angle(cloud[0]) * float(cloud[1])
		var cloud_r: float = cloud[2]
		draw_circle(cloud_pos, cloud_r, Color(1, 1, 1, 0.55))
		draw_circle(cloud_pos + Vector2(cloud_r * 0.9, 0.02), cloud_r * 0.7, Color(1, 1, 1, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2(-radius * 0.42, -radius * 0.42), radius * 0.22, Color(1, 1, 1, 0.1))  # 高光
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(0.75, 0.9, 1.0, 0.7), 3.0)

	# --- 音符：固定在地球边缘 ---
	var show_beats := def.beats_per_rev * SHOW_AHEAD
	for n in notes:
		if n.judged:
			continue
		var ahead := beats_until(n)
		if ahead > show_beats:
			break
		var a := HIT_ANGLE - angle_until(n)
		var c := sound_color(n)
		c.a = clampf((show_beats - ahead) / (show_beats * 0.2), 0.0, 1.0)
		var p := Vector2.from_angle(a) * radius
		draw_circle(p, 15.0, Color(1, 1, 1, c.a))
		draw_circle(p, 11.0, c)

	# --- 判定圈 ---
	var hit := hit_position()
	draw_arc(hit, 22.0, 0.0, TAU, 32, Color.WHITE, 3.0)

	# --- 小猫（用图片时）：趴在地球顶上，舔的时候头往下探、舌头伸到判定圈 ---
	if _cat == null:
		var head_drop := 5.0 * _lick + 3.0 * _bob
		var cat_center := hit + Vector2(0.0, -cat_size * 0.3 + head_drop)
		var squash := 1.0 + 0.04 * _bob
		var size := Vector2(cat_size * squash, cat_size / squash)
		draw_texture_rect(cat_texture, Rect2(cat_center - size / 2.0, size), false, _tint)
		var mouth := cat_center + mouth_offset * cat_size
		var tip := mouth + Vector2(0.0, 6.0 + 20.0 * _lick)
		draw_line(mouth, tip, Color(0.95, 0.5, 0.6), 11.0)
		draw_circle(tip, 5.5, Color(0.95, 0.5, 0.6))
		draw_line(mouth + Vector2(0.0, 2.0), tip, Color(0.85, 0.38, 0.5), 2.0)

	draw_string(ThemeDB.fallback_font, Vector2(-200.0, radius + 48.0), def.title,
			HORIZONTAL_ALIGNMENT_CENTER, 400.0, 28)
