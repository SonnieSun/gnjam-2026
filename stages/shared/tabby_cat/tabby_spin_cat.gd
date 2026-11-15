class_name TabbySpinCat
extends Node3D
## 可复用的虎斑猫（3D）：玩家每按一次键就绕竖轴猛转一下（加一把转速、弹一下），
## 转速带惯性慢慢减下来，停在哪就是哪，不会回到正面；连按会越转越快。
## 身上是发光四芒星那套发光（中心亮白偏粉、往外渐变成外光颜色）。
## 拖 tabby_spin_cat.tscn 进任意 3D 场景就能用；外光要场景里的 WorldEnvironment 打开 Glow 才会晕开。
##
## 发光：越转越亮。每转一圈亮度 + glow_per_spin（最多到 1）；
## 停下来 fade_delay 秒没再转，就按 fade_speed 慢慢暗回 0（暗回去就是猫原来的贴图）。
## 想自己控制：set_glow(0~1) 定住一个亮度（传负数恢复自动），add_glow(多少) 加一点。

@export_group("转圈")
## 按键时转一圈（关掉 = 只由外面调 spin()）
@export var listen_input := true
## 每按一下加多少转速（圈 / 秒）
@export var spin_push := 2.5
## 转速最快多少（圈 / 秒）
@export var max_spin_speed := 6.0
## 惯性：越大停得越快（每秒转速衰减的比例）
@export var spin_friction := 1.6
## 按键时弹一下的大小、弹回去用几秒
@export var spin_bounce := 1.12
@export var bounce_time := 0.3
## 转的时候顺带往别的方向歪着晃（像陀螺），最大歪多少度；0 = 只绕竖轴转
@export_range(0.0, 45.0, 0.5) var wobble_degrees := 12.0
## 晃的快慢（每秒晃几下）
@export var wobble_speed := 1.6
## 转多快时晃到最大（圈/秒）；转得越慢晃得越小，停下就回正
@export var wobble_full_speed := 3.0
@export_group("毛色")
## 生成时从这些贴图里随机挑一张（虎斑、三花、橘猫、奶牛猫）
@export var coats: Array[Texture2D] = [
	preload("res://stages/shared/tabby_cat/tabby_basecolor.png"),
	preload("res://stages/shared/tabby_cat/calico_basecolor.png"),
	preload("res://stages/shared/tabby_cat/ginger_basecolor.png"),
	preload("res://stages/shared/tabby_cat/tuxedo_basecolor.png"),
]
## 固定用第几张（-1 = 随机）
@export var coat_index := -1
@export_group("发光")
## 生成时从这些颜色里随机挑一种当外光颜色
@export var glow_colors: Array[Color] = [
	Color(0.35, 0.60, 1.0),   # 蓝
	Color(1.0, 0.35, 0.75),   # 粉
	Color(0.70, 0.40, 1.0),   # 紫
	Color(0.30, 0.95, 0.85),  # 青
	Color(1.0, 0.75, 0.25),   # 金
	Color(0.50, 1.0, 0.45),   # 绿
	Color(1.0, 0.45, 0.35),   # 珊瑚红
]
## 固定用第几种（-1 = 随机）
@export var glow_color_index := -1
## 现在的外光颜色（生成时从 glow_colors 里挑；也可以直接改）
@export var glow_color := Color(0.35, 0.60, 1.0)
@export var body_color := Color(1.0, 0.90, 0.95)
## 外光颜色按色相循环（每秒转多少圈），0 = 固定颜色
@export var hue_cycle_speed := 0.0
## 每转一圈亮多少（0~1）
@export_range(0.0, 1.0, 0.01) var glow_per_spin := 0.12
## 停下来多少秒后开始变暗
@export var fade_delay := 0.6
## 变暗的速度（每秒暗多少，0~1）
@export var fade_speed := 0.25
## 亮度变化的平滑程度（越大跟得越快）
@export var glow_smooth := 10.0
@export_group("Godot Glow（后期光晕）")
## 自动打开所在场景的 Glow：场景里有 WorldEnvironment 就把它的 Glow 打开（只在没开时改，开着就不动），
## 没有就自己加一个只开 Glow 的环境。关掉 = 不碰场景环境。
@export var ensure_scene_glow := true
@export_range(0.0, 8.0, 0.05) var glow_intensity := 1.2
@export_range(0.0, 1.0, 0.01) var glow_bloom := 0.1
## 多亮的地方才开始晕（越小越容易晕）
@export_range(0.0, 4.0, 0.05) var glow_threshold := 0.7

var _mat: ShaderMaterial
var _model: Node3D
var _rest_scale := Vector3.ONE
var _spin_tween: Tween
var _spin_speed := 0.0  # 圈 / 秒
var _yaw := 0.0
var _wobble_phase := 0.0
var _wobble_amount := 0.0
var _target := 0.0
var _shown := 0.0
var _idle := 99.0
var _fixed := -1.0


func _ready() -> void:
	_model = get_node_or_null("Model") as Node3D
	if _model:
		_rest_scale = _model.scale
		_yaw = _model.rotation.y
		_mat = ShaderMaterial.new()
		_mat.shader = preload("res://stages/shared/tabby_cat/tabby_glow.gdshader")
		if not coats.is_empty():
			var ci := coat_index if coat_index >= 0 else randi() % coats.size()
			_mat.set_shader_parameter("albedo_tex", coats[clampi(ci, 0, coats.size() - 1)])
		if not glow_colors.is_empty():
			var gi := glow_color_index if glow_color_index >= 0 else randi() % glow_colors.size()
			glow_color = glow_colors[clampi(gi, 0, glow_colors.size() - 1)]
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = _mat
	if ensure_scene_glow:
		_ensure_glow.call_deferred()


## 让所在场景有 Godot 的 Glow（后期光晕），发光部分才会晕开
func _ensure_glow() -> void:
	var envs := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	var env: Environment = null
	if not envs.is_empty():
		env = (envs[0] as WorldEnvironment).environment
	if env == null:
		var we := WorldEnvironment.new()
		we.name = "TabbyGlowEnvironment"
		env = Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		we.environment = env
		get_parent().add_child(we)
	if env.glow_enabled:
		return
	env.glow_enabled = true
	env.glow_intensity = glow_intensity
	env.glow_bloom = glow_bloom
	env.glow_hdr_threshold = glow_threshold
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, 1.0 if (i >= 1 and i <= 4) else 0.0)


## 转一整圈，并且亮一点
func spin() -> void:
	add_glow(glow_per_spin)
	if _model == null:
		return
	_spin_speed = minf(_spin_speed + spin_push, max_spin_speed)
	if _spin_tween:
		_spin_tween.kill()
	_model.scale = _rest_scale * spin_bounce
	_spin_tween = create_tween()
	_spin_tween.tween_property(_model, "scale", _rest_scale, bounce_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 亮一点（0~1），会重新开始计“停了多久”
func add_glow(amount: float) -> void:
	_target = clampf(_target + amount, 0.0, 1.0)
	_idle = 0.0


## 定住一个亮度（0~1）；传负数 = 恢复自动
func set_glow(strength: float) -> void:
	_fixed = strength


## 现在显示的亮度（0~1）
func current_glow() -> float:
	return _shown


func _unhandled_input(event: InputEvent) -> void:
	if not listen_input or event.is_echo():
		return
	var pressed := false
	if InputMap.has_action("hit"):
		pressed = event.is_action_pressed("hit")
	else:
		var k := event as InputEventKey
		pressed = k != null and k.pressed and k.physical_keycode == KEY_SPACE
	if pressed:
		spin()


func _process(delta: float) -> void:
	# 惯性转：转速按比例慢慢减，太慢就停住（停在哪就是哪）
	if _model and _spin_speed > 0.0:
		_yaw = fposmod(_yaw + _spin_speed * TAU * delta, TAU)
		_spin_speed *= exp(-spin_friction * delta)
		if _spin_speed < 0.02:
			_spin_speed = 0.0
	# 别的轴：按转速歪着晃，两个方向频率错开免得太规律；停下慢慢回正
	if _model:
		var want_wobble := clampf(_spin_speed / maxf(wobble_full_speed, 0.01), 0.0, 1.0)
		_wobble_amount = lerpf(_wobble_amount, want_wobble, minf(1.0, 6.0 * delta))
		_wobble_phase += wobble_speed * TAU * delta
		var a := deg_to_rad(wobble_degrees) * _wobble_amount
		var tilt := Basis.from_euler(Vector3(sin(_wobble_phase) * a, 0.0, cos(_wobble_phase * 1.37) * a))
		_model.quaternion = (tilt * Basis(Vector3.UP, _yaw)).get_rotation_quaternion()
	_idle += delta
	if _idle > fade_delay:
		_target = maxf(_target - fade_speed * delta, 0.0)
	var want := _fixed if _fixed >= 0.0 else _target
	_shown = lerpf(_shown, want, minf(1.0, glow_smooth * delta))
	if hue_cycle_speed != 0.0:
		glow_color.h = fposmod(glow_color.h + hue_cycle_speed * delta, 1.0)
	if _mat:
		_mat.set_shader_parameter("glow", _shown)
		_mat.set_shader_parameter("glow_color", glow_color)
		_mat.set_shader_parameter("body_color", body_color)
