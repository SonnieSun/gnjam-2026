extends Node
## 飞船关卡的 Y2K 画面（之前效果图 y2k_mockup 的配方，做成关卡里的一个节点）。
## 放在 SpaceshipSection 下面当子节点就生效，不改关卡脚本和舞台脚本：
## 运行时把飞碟换成光泽白塑料 / 菲涅尔玻璃 / 金色霓虹，行星加清漆变成亮面珍珠感，
## 灯光换成暖主光 + 蓝紫逆光，再盖一层「360 线方像素 + 16 位色抖动 + 长春花蓝 / 金 分离调色」。
## 关掉 enabled 就是原来的画面。

## 总开关
@export var enabled := true
## 方像素 + 抖动 + 调色那层（关掉 = 只换材质灯光）
@export var era_output := true
## 方像素有多少线（越小像素越大）
@export var lines := 360.0
@export_group("灯光和环境")
@export var exposure := 0.8
@export var ambient_energy := 0.3
@export var glow_intensity := 0.6
@export var key_color := Color(1.0, 0.9, 0.75)
@export var key_energy := 1.1
@export var rim_color := Color(0.55, 0.6, 1.0)
@export var rim_energy := 1.2
## 天空亮度（冲刺 / 俯视），Y2K 画面里压暗一点让主体更跳
@export var sky_energy := 0.5
@export var sky_solar_energy := 0.28
@export_group("颜色")
## 飞碟边圈（长春花蓝光泽塑料；铬在暗天空下只会反射一片黑）
@export var rim_plastic_color := Color(0.62, 0.68, 1.0)
## 霓虹（飞碟底光）
@export var neon_color := Color(1.0, 0.8, 0.35)
## 强调色只给玩家要看的收缩圈
@export var shrink_color := Color(1.0, 0.82, 0.3)
@export var orbit_color := Color(0.75, 0.82, 1.0, 0.45)

const ERA_SCREEN := preload("res://stages/spaceship/y2k/era_screen.gdshader")
const GLASS := preload("res://assets/shaders/y2k/glass_aero.gdshader")

var _cat: KisaSpinCat3D
var _stage: Node
var _styled := false
var _known := {}  # 开始时 3D 世界里已有的节点（飞碟、猫、星空……），之后新出现的 Node3D 才是行星


func _ready() -> void:
	if Engine.is_editor_hint() or not enabled:
		set_process(false)
		return
	if era_output:
		var layer := CanvasLayer.new()
		layer.layer = 100  # 盖在 HUD 上面，UI 也一起变成时代输出
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = ERA_SCREEN
		mat.set_shader_parameter("lines", lines)
		rect.material = mat
		layer.add_child(rect)
		add_child(layer)


func _process(_delta: float) -> void:
	if not _styled:
		var section := get_parent()
		_cat = section.get("_spin_cat") as KisaSpinCat3D
		_stage = section.get_node_or_null("Stage")
		if _cat == null or _cat.environment == null or _cat.backdrop_node == null:
			return  # 关卡还没搭好，下一帧再试
		_styled = true
		_style_world()
		for n in _cat.world.get_children():
			_known[n] = true
	_style_new_planets()


func _style_world() -> void:
	var env := _cat.environment
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = exposure
	env.ambient_light_energy = ambient_energy
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_intensity = glow_intensity
	env.glow_bloom = 0.15
	# 暖主光 + 彩色逆光
	_cat.key_light.light_color = key_color
	_cat.key_light.light_energy = key_energy
	var rim := DirectionalLight3D.new()
	rim.light_color = rim_color
	rim.light_energy = rim_energy
	rim.rotation_degrees = Vector3(-20.0, 160.0, 0.0)
	_cat.world.add_child(rim)

	var plastic := StandardMaterial3D.new()  # 光泽白塑料
	plastic.albedo_color = Color(0.86, 0.88, 0.92)
	plastic.roughness = 0.12
	plastic.metallic_specular = 0.7
	plastic.clearcoat_enabled = true
	plastic.clearcoat = 1.0
	plastic.clearcoat_roughness = 0.04
	plastic.rim_enabled = true
	plastic.rim = 0.15
	plastic.rim_tint = 0.4
	var rim_plastic := StandardMaterial3D.new()
	rim_plastic.albedo_color = rim_plastic_color
	rim_plastic.roughness = 0.15
	rim_plastic.clearcoat_enabled = true
	var neon := StandardMaterial3D.new()
	neon.albedo_color = neon_color
	neon.emission_enabled = true
	neon.emission = neon_color
	neon.emission_energy_multiplier = 4.0
	neon.roughness = 0.2
	var glass := ShaderMaterial.new()
	glass.shader = GLASS

	var ship := _cat.backdrop_node
	_set_mat(ship.get_node_or_null("Top"), plastic)
	_set_mat(ship.get_node_or_null("Bottom"), plastic)
	_set_mat(ship.get_node_or_null("Rim"), rim_plastic)
	_set_mat(ship.get_node_or_null("Dome"), glass)
	_set_mat(ship.get_node_or_null("Flames/Glow"), neon)

	if _stage:
		_stage.set("shrink_color", shrink_color)
		_stage.set("orbit_color", orbit_color)
		_stage.set("sky_energy", sky_energy)
		_stage.set("sky_solar_energy", sky_solar_energy)


## 行星（代码做的球或模型都行）：每个材质复制一份，加清漆，变成亮面珍珠感
func _style_new_planets() -> void:
	for n in _cat.world.get_children():
		if _known.has(n):
			continue
		_known[n] = true
		if n.get_class() != "Node3D":
			continue  # 行星的根是普通 Node3D；尾巴、收缩圈这些是 MeshInstance3D，不动
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as StandardMaterial3D
				if m == null:
					continue
				m = m.duplicate()
				m.roughness = minf(m.roughness, 0.45)
				m.clearcoat_enabled = true
				m.clearcoat = 0.7
				m.clearcoat_roughness = 0.05
				mi.set_surface_override_material(s, m)


func _set_mat(node: Node, mat: Material) -> void:
	var mi := node as MeshInstance3D
	if mi:
		mi.material_override = mat
