@tool
extends SpinSection
## 轨道：一个小圆沿圆形轨道绕中心的行星跑，经过轨道上的标记点时按键。
## 和转盘关相反——这里盘不动，判定点自己在跑。跑一圈 = beats_per_rev 拍。

@export var planet_color := Color(0.2, 0.55, 0.45)
## 中间的猫 meme，动画跟着拍子走（每小节放一遍）
@export var center_meme := "oiia"
## 沿轨道跑的猫 meme
@export var runner_meme := "nyan"
@export var planet_radius := 95.0
@export var orbit_radius := 205.0
@export var runner_radius := 20.0

const START_ANGLE := -PI / 2
const SHOW_AHEAD := 0.85  # 提前多少圈显示标记点

var _angle := 0.0
var _pulse := 0.0
var _runner_color := Color.WHITE
var _center: MemeSprite
var _runner: MemeSprite


func _ready() -> void:
	_center = MemeSprite.create(center_meme, planet_radius * 2.1)
	add_child(_center)
	_runner = MemeSprite.create(runner_meme, runner_radius * 11.0)
	add_child(_runner)


func _runner_pos(angle_offset: float = 0.0) -> Vector2:
	return Vector2.from_angle(START_ANGLE + _angle + angle_offset) * orbit_radius


func hit_position(_note: NoteData = null) -> Vector2:
	return _runner_pos()


func hit_radius() -> float:
	return runner_radius


func _update_spin(_local_beat: float, angle: float) -> void:
	center_on_screen()
	_angle = angle
	_pulse = lerpf(_pulse, 0.0, 0.15)
	_runner_color = _runner_color.lerp(Color.WHITE, 0.1)
	_center.set_progress(_local_beat / 4.0)
	_center.scale = _center.scale.lerp(Vector2.ONE * (planet_radius * 2.1 / 128.0) * (1.0 + 0.1 * _pulse), 0.5)
	_runner.position = _runner_pos()
	_runner.rotation = START_ANGLE + _angle + PI / 2  # 头朝前进方向
	_runner.modulate = _runner_color
	queue_redraw()


func _on_beat(_beat_in_section: int) -> void:
	_pulse = 1.0


func _on_note_judged(_note: NoteData, result: int) -> void:
	_runner_color = result_color(result)


func _on_empty_hit() -> void:
	_runner_color = result_color(NoteData.Result.NONE)


func _draw() -> void:
	if def == null:
		return
	# 行星只留一个淡淡的底，猫在上面
	draw_circle(Vector2.ZERO, planet_radius * (1.0 + 0.06 * _pulse), Color(planet_color, 0.35))
	# 轨道
	draw_arc(Vector2.ZERO, orbit_radius, 0.0, TAU, 96, Color(1, 1, 1, 0.25), 2.0)
	# 轨道上的标记点
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
		draw_circle(Vector2.from_angle(a) * orbit_radius, 12.0, c)
	# 跑动的猫由 _runner 精灵显示，这里只画它身上的判定圈
	draw_arc(_runner_pos(), runner_radius + 5.0, 0.0, TAU, 32, _runner_color, 2.5)
	draw_title()
