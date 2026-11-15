extends Node
## 飞船关卡的星云粒子星空（照 Kisa 的参考图：黑底上蓝紫色柔光星团，粒子有大有小，亮的带十字星芒和光晕）。
## 放在 SpaceshipSection 下面当子节点就生效，不改关卡脚本和舞台脚本。
## 由「一团团星云粒子」组成（clouds 列表，每团可调方向、大小、密度、粒子大小、颜色），
## 外加一层散在整个天上的背景星星。全部一次画完，每拍一起闪一下，慢慢漂动。

## 总开关
@export var enabled := true
## 星云团（每团的参数点开调）
@export var clouds: Array[StarCloud] = []
@export_group("背景星星")
## 散在整个天上的星星数量（密度）
@export_range(0, 5000) var background_count := 350
## 离飞船多远（最近 / 最远）
@export var background_distance := Vector2(170.0, 260.0)
@export var background_size := Vector2(1.2, 3.5)
## 颜色：每颗在这条渐变上随机取
@export var background_colors: Gradient
@export var background_alpha := Vector2(0.3, 1.0)
## 几成是带十字星芒的亮星
@export_range(0.0, 1.0) var background_flare_ratio := 0.05
@export var background_flare_size := Vector2(8.0, 18.0)
@export_group("闪烁")
## 整体亮度
@export var brightness := 1.0
## 每拍亮多少
@export var pulse_gain := 0.6
## 平时自己闪烁的幅度
@export_range(0.0, 1.0) var twinkle := 0.3
## 漂动快慢
@export var drift_speed := 0.4

const FLARE := preload("res://stages/spaceship/stars/star_flare.gdshader")

var _cat: KisaSpinCat3D
var _mat: ShaderMaterial


func _ready() -> void:
	if Engine.is_editor_hint() or not enabled:
		set_process(false)


func _process(_delta: float) -> void:
	if _cat == null:
		_cat = get_parent().get("_spin_cat") as KisaSpinCat3D
		if _cat == null or _cat.world == null:
			return  # 关卡还没搭好，下一帧再试
		_build()
	_mat.set_shader_parameter("pulse", exp(-fposmod(Conductor.song_beat, 1.0) * 5.0))


func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = FLARE
	_mat.set_shader_parameter("brightness", brightness)
	_mat.set_shader_parameter("pulse_gain", pulse_gain)
	_mat.set_shader_parameter("twinkle", twinkle)
	_mat.set_shader_parameter("drift_speed", drift_speed)

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var total := background_count
	for c in clouds:
		if c:
			total += c.count + (1 if c.glow_size > 0.0 else 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = total
	var i := 0
	var far := background_distance.y
	# 背景星星：均匀散在整个天上
	for k in background_count:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var pos := dir * rng.randf_range(background_distance.x, background_distance.y)
		var flare := rng.randf() < background_flare_ratio
		var size := rng.randf_range(background_flare_size.x, background_flare_size.y) if flare \
				else rng.randf_range(background_size.x, background_size.y)
		_put_star(mm, i, rng, pos, size, _pick(background_colors, rng), background_alpha, flare, 0.5)
		i += 1
	# 星云团：在一个椭球里撒，越靠中心越密
	for c in clouds:
		if c == null:
			continue
		var center := c.direction.normalized() * c.distance
		far = maxf(far, c.distance + c.size.length())
		for k in c.count:
			var off := Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * 0.5
			off *= lerpf(1.0, rng.randf(), c.concentration)  # 往中心挤
			var flare := rng.randf() < c.flare_ratio
			var size := rng.randf_range(c.flare_size.x, c.flare_size.y) if flare \
					else rng.randf_range(c.particle_size.x, c.particle_size.y)
			_put_star(mm, i, rng, center + off * c.size, size, _pick(c.colors, rng), c.alpha, flare, c.drift)
			i += 1
		if c.glow_size > 0.0:
			# 中心柔光（w = 1：shader 画成一大片淡光）
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * c.glow_size), center * 1.02))
			mm.set_instance_color(i, c.glow_color)
			mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 1.0))
			i += 1

	var node := MultiMeshInstance3D.new()
	node.name = "StarField"
	node.multimesh = mm
	node.material_override = _mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 星星离得很远又一直在画面里，直接给一个够大的包围盒，免得被剔除
	node.custom_aabb = AABB(Vector3.ONE * -far * 1.5, Vector3.ONE * far * 3.0)
	_cat.world.add_child(node)
	# 镜头要能看到最远的星星
	_cat.camera.far = maxf(_cat.camera.far, far * 1.6)


func _pick(g: Gradient, rng: RandomNumberGenerator) -> Color:
	return g.sample(rng.randf()) if g else Color(0.6, 0.7, 1.0)


func _put_star(mm: MultiMesh, i: int, rng: RandomNumberGenerator, pos: Vector3, size: float, color: Color,
		alpha: Vector2, flare: bool, drift: float) -> void:
	mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), pos))
	color.a = rng.randf_range(maxf(alpha.x, 0.7), 1.0) if flare else rng.randf_range(alpha.x, alpha.y)
	mm.set_instance_color(i, color)
	# x = 星芒强度（0 = 普通光点），y = 闪烁 / 漂动相位，z = 漂动幅度，w = 0（不是柔光）
	mm.set_instance_custom_data(i, Color(rng.randf_range(0.6, 1.0) if flare else 0.0, rng.randf() * TAU, drift, 0.0))
