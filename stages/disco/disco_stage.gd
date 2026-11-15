class_name KisaDiscoStage
extends Node2D
## 迪斯科猫砂盆关卡的「舞台导演」：根据进度推进 / 倒退阶段，并负责运镜、灯光和跟拍律动。
## 进度 progress：成功 +1，Miss -1（最少 0，最多 drift_at + drift_steps）。
##   开场       镜头很近，只有猫和猫砂盆，房间很暗
##   每 +1      镜头拉远一档
##   stars_at   星星灯掉下来，场景变亮
##   ball_at    迪斯科灯球掉下来并一直转，彩色光斑扫场
##   cats_at    2D 跳舞猫从两边进场
##   drift_at   猫离开猫砂盆，一边慢慢转、一边歪来歪去，沿着房间里的路线漂；
##              之后每 +1 往前漂一段，每 -1 往回漂一段，漂满 drift_steps 段到终点
## 进度掉回某个阶段的门槛以下，那个阶段的东西会收回去（灯升回去、猫退场……）。
## 用法：把它加到关卡里，调 setup(猫)；每帧调 update(拍数)；成功调 add_success()，Miss 调 add_miss()。
## 3D 的东西都在 KisaSpinCat3D 的 3D 世界里，这里只是摆弄它们。房间里的 Stars/*、DiscoBall 是空的
## 定位点，下面没有模型时这里自动放占位模型；DriftPath/* 是漂移路线依次经过的点（起点是猫砂盆）。
## 测试用，只在本机 _sandbox 里，不进仓库。

signal stage_changed(stage: int)

@export_group("阶段（进度到多少时触发）")
@export var stars_at := 5
@export var ball_at := 10
@export var cats_at := 15
@export var drift_at := 20
## 漂移路线分成几段走完（到终点一共要再成功这么多次）
@export var drift_steps := 80

@export_group("运镜")
## 开场镜头有多近：画面高度 = 猫的高度 × 这个倍数
@export var close_zoom := 1.15
## 星星灯掉下来时镜头已经拉远到多少（0 = 开场，1 = 看到整个房间）
@export_range(0.0, 1.0) var zoom_at_stars := 0.7
## 镜头跟上目标的快慢（越大越快）
@export var zoom_speed := 4.0
## 每拍镜头往里「顶」一下的幅度（占画面的比例），按阶段 0 / 1 / 2 / 3 / 4 分别设
@export var beat_punch := PackedFloat32Array([0.0, 0.02, 0.045, 0.06, 0.06])
## 镜头左右摇摆的角度（度），按阶段分别设
@export var sway_degrees := PackedFloat32Array([0.0, 3.0, 7.0, 9.0, 9.0])
## 摇摆一个来回用几拍
@export var sway_beats := 8.0
## 镜头歪头（倾斜）的角度（度），按阶段分别设
@export var roll_degrees := PackedFloat32Array([0.0, 0.0, 2.5, 4.0, 4.0])
## 歪头一个来回用几拍
@export var roll_beats := 4.0
## 进入新阶段时镜头猛地拉远再弹回来的幅度
@export var stage_kick := 0.18
## 拉到最远时画面多大：1 = 刚好看到整个房间，越小越近（房间边缘留在画面外）
@export_range(0.2, 1.0) var far_view := 0.5
## 猫漂移时镜头跟着猫走多少（0 = 不跟，1 = 一直对准猫）
@export_range(0.0, 1.0) var drift_follow := 1.0
## 镜头拉远时画面中心往上抬多少（3D 单位，拉到最远时用满），让上面的灯球和星星进画面
@export var far_look_up := 5.0

@export_group("灯光")
## 开场 / 变亮之后 的环境光和主光强度
@export var dark_ambient := 0.07
@export var dark_key := 0.12
@export var bright_ambient := 0.12
@export var bright_key := 0.16
## 小屋外面的底色：开场 / 变亮之后
@export var dark_background := Color(0.02, 0.01, 0.04)
@export var bright_background := Color(0.05, 0.02, 0.09)
@export var star_colors: Array[Color] = [
	Color(1.0, 0.85, 0.2), Color(1.0, 0.35, 0.7), Color(0.3, 0.8, 1.0), Color(1.0, 0.8, 0.25),
]
@export var spot_colors: Array[Color] = [
	Color(1.0, 0.2, 0.8), Color(0.2, 0.9, 1.0), Color(1.0, 0.85, 0.2), Color(0.6, 0.3, 1.0),
]
## 现成灯球模型的镜面颜色和平时的自发光强度（每拍会再亮一下）
@export var ball_tint := Color(0.85, 0.72, 0.98)
@export var ball_glow := 0.35
## 灯球镜片的材质（金属镜面 + 假的环境反射，参数在这个材质文件里调）。留空 = 用原来那种带自发光的亮紫镜面
@export var ball_material: ShaderMaterial = preload("res://stages/disco/disco_ball_mirror.tres")
## 夜晚的环境光颜色和主光（月光）颜色
@export var night_ambient_color := Color(0.42, 0.36, 0.78)
@export var moon_color := Color(0.55, 0.6, 1.0)
## 星星灯照多远、平时多亮、跟拍闪多少
@export var star_light_range := 22.0
@export var star_light_energy := 1.6
@export var star_light_pulse := 2.4
## 灯球的彩色射灯平时多亮、跟拍闪多少；灯球自身的点光多亮
@export var spot_energy := 9.0
@export var spot_pulse := 8.0
@export var ball_light_energy := 5.0
## 猫的轮廓边光：颜色、平时多亮、每拍多亮一下（暗房间里让猫更显眼，不冲淡贴图）
@export var cat_rim_color := Color(1.0, 0.85, 0.7)
@export var cat_rim := 0.4
@export var cat_rim_pulse := 0.8
## 跟着猫走的补光（从镜头这一侧斜上方照猫）：颜色和亮度
@export var cat_light_color := Color(1.0, 0.92, 0.85)
@export var cat_light_energy := 0.7
## 猫头顶往下打的聚光灯（会跟着猫走）：颜色、亮度、光圈角度、灯有多高
@export var top_light_color := Color(1.0, 0.86, 0.66)
@export var top_light_energy := 6.0
@export var top_light_pulse := 3.0
@export var top_light_angle := 14.0
@export var top_light_height := 16.0
## 看得见的光柱：亮度、底部半径
@export var beam_strength := 0.28
@export var beam_radius := 3.2
## 猫每次转圈时脚下扩散的光波：颜色、亮度、扩到多大（半径）、用几秒
@export var wave_color := Color(1.0, 0.78, 0.95)
@export var wave_strength := 1.6
@export var wave_radius := 7.0
@export var wave_time := 0.6
## 墙灯、电脑屏幕每拍闪的幅度（发光强度最多变成原来的 1 + 这个值 倍）
@export var prop_pulse := 1.5
## 灯球转一圈用几拍
@export var ball_beats_per_rev := 24.0  # 光束和射灯挂在灯球上一起转；原来 8 拍一圈太快，晃眼

@export_group("灯球光束和闪光")
## 勾上 = 灯球打出来的光（光束、地上的光斑、射灯、灯球自己的光）全用白色，并且暗一点、少闪一点，不晃眼；
## 不勾 = 原来的彩色迪斯科灯
@export var white_light := true
@export var white_light_color := Color(1.0, 0.97, 0.92)
## 白光时整体亮度（乘在原来的亮度上）、闪烁和跟拍闪还剩多少
@export_range(0.1, 1.0) var white_brightness := 0.35
@export_range(0.0, 1.0) var white_flicker := 0.3
## 灯球往地上打的光束：有几根、用哪些颜色（每隔 beam_color_beats 拍颜色整体轮换一格）
@export var beam_count := 14
@export var beam_colors: Array[Color] = [
	Color(1.0, 0.2, 0.75), Color(0.2, 0.9, 1.0), Color(1.0, 0.85, 0.2), Color(0.6, 0.3, 1.0),
	Color(1.0, 0.45, 0.15), Color(0.3, 1.0, 0.5), Color(1.0, 0.25, 0.3), Color(0.3, 0.5, 1.0),
]
@export var beam_color_beats := 2.0
## 勾上 = 显示灯球射出来的一根根光束（光柱本身）；不勾 = 光柱藏起来，只留它们打在地上的光斑
@export var ball_beams_visible := false
## 光束亮度、每拍多亮一下、自己闪烁的幅度（0 = 不闪）
@export var ball_beam_strength := 0.55
@export var ball_beam_pulse := 0.5
@export_range(0.0, 1.0) var ball_beam_flicker := 0.45
## 光束落到地上那头有多粗（3D 单位）；光束打在地上的彩色光斑多亮
@export var ball_beam_radius := 0.9
@export var ball_beam_light := 6.0
## 灯球表面的十字星光：同时最多几颗、多大（灯球半径的倍数）、每颗亮多久（秒）
@export var glint_count := 9
@export var glint_size := 1.5
@export var glint_life := 0.5
## 灯球镜片自己的闪烁强度（参数更多在 disco_ball_mirror.gdshader 里），每拍开头再加多少
@export var ball_sparkle := 5.0
@export var ball_sparkle_pulse := 6.0

@export_group("2D 跳舞猫")
## MemeLib 里的名字，从左到右
@export var dancers := PackedStringArray(["oiia", "banana", "apple", "nyanrun"])
## 每只猫相对屏幕中心的位置
@export var dancer_positions := PackedVector2Array([
	Vector2(-480, 150), Vector2(-330, 60), Vector2(330, 60), Vector2(480, 150),
])
@export var dancer_height := 190.0
## 每拍跳起来多高（像素）
@export var dancer_hop := 22.0
## 动图放一遍用几拍
@export var dancer_loop_beats := 2.0

@export_group("漂移")
## 猫沿路线移动、跟上进度的快慢（越大越快）
@export var drift_speed := 2.5
## 漂移时猫自己慢慢转，转一圈用几秒
@export var drift_spin_seconds := 4.0
## 漂移时猫歪来歪去的角度（度）
@export var drift_tilt_degrees := 18.0
## 歪一个来回用几拍
@export var drift_tilt_beats := 4.0
## 漂移时上下浮动的幅度（3D 单位）和一个来回的拍数
@export var drift_bob := 0.35
@export var drift_bob_beats := 2.0

var progress := 0
var stage := 0
## 由外面（积累条）来推进阶段和镜头。打开后 add_success() / add_miss() 不再起作用，
## 改用 enter_stage(第几阶段) 和 external_zoom（0 = 开场特写，1 = 整个房间）。
var external := false
var external_zoom := 0.0
## external 时漂移走到路线的哪里（0 = 猫砂盆，1 = 终点），由外面按积累条给
var external_drift := 0.0
## 后面的阶段（DiscoRoad）接管镜头和猫的位置姿态：打开后这里不再动镜头、不再做漂移
var takeover := false

var _cat: KisaSpinCat3D
var _full_size := 1.0
var _zoom := 0.0  # 0 = 开场特写，1 = 整个房间
var _kick := 0.0
var _last_time := 0.0
var _stars: Array[Node3D] = []
var _star_rest: Array[Vector3] = []
var _star_mats: Array[StandardMaterial3D] = []
var _star_lights: Array[OmniLight3D] = []
var _ball: Node3D
var _ball_rest := Vector3.ZERO
var _ball_mats: Array[StandardMaterial3D] = []
var _ball_mirror: ShaderMaterial  # 用了 ball_material 时，所有镜片共用的那一份
var _prop_mats: Array[StandardMaterial3D] = []
var _prop_base: Array[float] = []
var _spot_rig: Node3D
var _ball_light: OmniLight3D
## 灯球整体还剩多少（1 = 正常，0 = 完全消失）：球本身、彩色光束、射灯、星光一起淡。结尾飞碟出现时 DiscoRoad 把它淡到 0
var ball_fade := 1.0
var _ball_fade_applied := 1.0
var _ball_center: Node3D  # 灯球球心（灯球节点的原点在吊线上面，不在球心）
var _ball_radius := 1.0  # 球半径（_ball_center 的局部单位）
var _beam_rig: Node3D
var _ball_beams: Array[MeshInstance3D] = []
var _ball_beam_lights: Array[SpotLight3D] = []
var _glints: Array[MeshInstance3D] = []
var _glint_t: Array[float] = []  # 每颗星光现在亮到哪了（0..1，>= 1 = 等下一次）
var _glint_dir: Array[Vector3] = []
var _glint_scale: Array[float] = []
var _cat_rim: ShaderMaterial
var _cat_light: OmniLight3D
var _top_light: SpotLight3D
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _dancers: Array[MemeSprite] = []
var _tweens := {}  # 每样东西同时只留一个动画
var _path := Curve3D.new()
var _drift := 0.0  # 现在漂到路线的哪里（0 = 猫砂盆，1 = 终点）
var _spin_phase := 0.0


func setup(cat: KisaSpinCat3D) -> void:
	_cat = cat
	_full_size = _frame_size(cat, _find(cat.backdrop_node, "RoomShell")) * far_view
	_last_time = Time.get_ticks_msec() / 1000.0

	cat.environment.ambient_light_energy = dark_ambient
	cat.environment.ambient_light_color = night_ambient_color
	cat.key_light.light_color = moon_color
	cat.environment.background_color = dark_background
	cat.environment.glow_enabled = true
	cat.environment.glow_intensity = 0.6
	cat.key_light.light_energy = dark_key

	var room := cat.backdrop_node
	var star_mesh := _make_star_mesh(0.8, 0.38, 0.3)
	for marker in _find(room, "Stars").get_children():
		var star := marker as Node3D
		var i := _stars.size()
		var color := star_colors[i % star_colors.size()]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if star.get_child_count() == 0:
			var mesh := MeshInstance3D.new()
			mesh.mesh = star_mesh
			mesh.material_override = mat
			mesh.rotation.y = deg_to_rad(45.0)  # 正对镜头
			star.add_child(mesh)
			star.add_child(_make_cord(12.0, 0.8))
		else:
			# 现成模型：材质名叫 Emitter 的那一面换成这盏灯的颜色，跟着节拍发光
			for mi in star.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				for s in m.mesh.get_surface_count():
					var src := m.mesh.surface_get_material(s)
					if src and src.resource_name.begins_with("Emitter"):
						m.set_surface_override_material(s, mat)
		var light := OmniLight3D.new()
		light.light_color = color
		light.omni_range = star_light_range
		light.omni_attenuation = 0.8
		light.light_energy = 0.0
		star.add_child(light)
		_stars.append(star)
		_star_rest.append(star.position)
		_star_mats.append(mat)
		_star_lights.append(light)
		star.position.y += 30.0  # 先藏到天花板上面

	_ball = _find(room, "DiscoBall")
	_ball_rest = _ball.position
	if _ball.get_child_count() == 0:
		var ball_mesh := SphereMesh.new()
		ball_mesh.radius = 1.3
		ball_mesh.height = 2.6
		ball_mesh.radial_segments = 12
		ball_mesh.rings = 6
		var ball_mat := StandardMaterial3D.new()
		ball_mat.albedo_color = Color(0.85, 0.8, 0.95)
		ball_mat.metallic = 0.9
		ball_mat.roughness = 0.25
		ball_mat.emission_enabled = true
		ball_mat.emission = Color(0.6, 0.4, 0.9)
		ball_mat.emission_energy_multiplier = 0.5
		ball_mesh.material = ball_mat
		var ball := MeshInstance3D.new()
		ball.mesh = ball_mesh
		_ball.add_child(ball)
		_ball.add_child(_make_cord(12.0, 1.3))
	else:
		# 现成模型：镜面材质在没有环境反射的房间里会发黑，换成带一点自发光的亮紫镜面
		for mi in _ball.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for s in m.mesh.get_surface_count():
				var src := m.mesh.surface_get_material(s) as StandardMaterial3D
				if src == null or src.metallic < 0.5:
					continue
				if ball_material:
					if _ball_mirror == null:
						_ball_mirror = ball_material.duplicate()
						_ball_mirror.set_shader_parameter("glow_color", ball_tint)
					m.set_surface_override_material(s, _ball_mirror)
					continue
				var mat := src.duplicate() as StandardMaterial3D
				mat.albedo_color = ball_tint
				mat.metallic = 0.6
				mat.roughness = 0.3
				mat.emission_enabled = true
				mat.emission = ball_tint
				mat.emission_energy_multiplier = ball_glow
				m.set_surface_override_material(s, mat)
				_ball_mats.append(mat)
	_setup_ball_center()
	# 彩色射灯：挂在灯球球心，跟着灯球转，在地板和墙上扫出光斑
	_spot_rig = Node3D.new()
	_ball_center.add_child(_spot_rig)
	_setup_ball_beams()
	_setup_glints(cat)
	for i in spot_colors.size():
		var spot := SpotLight3D.new()
		spot.light_color = white_light_color if white_light else spot_colors[i]
		spot.light_energy = 0.0
		spot.spot_range = 70.0
		spot.spot_attenuation = 0.6
		spot.spot_angle = 16.0
		spot.rotation_degrees = Vector3(-52.0, i * 360.0 / spot_colors.size(), 0.0)
		_spot_rig.add_child(spot)
	_ball_light = OmniLight3D.new()
	_ball_light.omni_range = 45.0
	_ball_light.light_energy = 0.0
	_ball.add_child(_ball_light)
	_ball.position.y += 30.0

	# 漂移路线：猫砂盆（原点）-> DriftPath 下面的点，按顺序连成一条圆滑的线
	var pts: Array[Vector3] = [Vector3.ZERO]
	for p in room.get_node("DriftPath").get_children():
		pts.append((p as Node3D).position)
	for i in pts.size():
		var prev := pts[maxi(i - 1, 0)]
		var next := pts[mini(i + 1, pts.size() - 1)]
		var handle := (next - prev) / 6.0
		_path.add_point(pts[i], -handle, handle)

	# 家具墙饰里的发光面（材质名 Emitter* / Screen）：复制一份材质，之后跟着节拍闪
	var props := _find(room, "Props")
	if props:
		for mi in props.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for s in m.mesh.get_surface_count():
				var src := m.mesh.surface_get_material(s) as StandardMaterial3D
				if src == null or not src.emission_enabled:
					continue
				if not (src.resource_name.begins_with("Emitter") or src.resource_name.begins_with("Screen")):
					continue
				var mat := src.duplicate() as StandardMaterial3D
				m.set_surface_override_material(s, mat)
				_prop_mats.append(mat)
				_prop_base.append(src.emission_energy_multiplier)

	# 猫显眼：贴图不动，外面叠一圈轮廓边光（跟拍变亮），再加一盏跟着猫走的补光
	_cat_rim = ShaderMaterial.new()
	_cat_rim.shader = preload("res://stages/disco/cat_rim.gdshader")
	_cat_rim.set_shader_parameter("rim_color", cat_rim_color)
	for mi in cat._pivot.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			if src == null:
				continue
			var mat := src.duplicate() as Material
			mat.next_pass = _cat_rim
			m.set_surface_override_material(s, mat)
	_cat_light = OmniLight3D.new()
	_cat_light.light_color = cat_light_color
	_cat_light.light_energy = cat_light_energy
	_cat_light.omni_range = 10.0
	cat.world.add_child(_cat_light)
	_top_light = SpotLight3D.new()
	_top_light.light_color = top_light_color
	_top_light.spot_angle = top_light_angle
	_top_light.spot_range = top_light_height + 4.0
	_top_light.spot_attenuation = 0.4
	_top_light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # 朝正下方
	cat.world.add_child(_top_light)
	var cone := CylinderMesh.new()
	cone.top_radius = beam_radius * 0.18
	cone.bottom_radius = beam_radius
	cone.height = top_light_height
	cone.radial_segments = 32
	cone.cap_top = false
	cone.cap_bottom = false
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = preload("res://stages/disco/spot_beam.gdshader")
	_beam_mat.set_shader_parameter("beam_color", top_light_color)
	cone.material = _beam_mat
	_beam = MeshInstance3D.new()
	_beam.mesh = cone
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cat.world.add_child(_beam)
	cat.spin_started.connect(_emit_wave)

	_apply_camera(0.0)


## 成功一次（Perfect / Good）：进度 +1
func add_success() -> void:
	if not external:
		_set_progress(progress + 1)


## Miss 一次：进度 -1
func add_miss() -> void:
	if not external:
		_set_progress(progress - 1)


## 直接推进到第 which 阶段（1 = 星星灯，2 = 灯球，3 = 跳舞猫）。只进不退。
func enter_stage(which: int) -> void:
	while stage < which:
		stage += 1
		_enter_stage(stage)


## 猫现在在屏幕上的位置（相对屏幕中心，像素），判定圈跟着它走
func cat_screen_offset() -> Vector2:
	if _cat == null:
		return Vector2.ZERO
	var screen := Vector2(_cat.world.size)
	return _cat.camera.unproject_position(_cat.focus + _cat.pose_position) - screen / 2.0


## 每帧调用，beat = 当前歌曲拍数
func update(beat: float) -> void:
	if _cat == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var delta := minf(now - _last_time, 0.1)
	_last_time = now
	_zoom = lerpf(_zoom, _target_zoom(), 1.0 - exp(-zoom_speed * delta))
	if not takeover:
		_apply_camera(beat)

	var pulse := exp(-fposmod(beat, 1.0) * 5.0)  # 每拍开头 = 1，然后很快落回 0
	if _cat_rim:
		_cat_rim.set_shader_parameter("strength", cat_rim + pulse * cat_rim_pulse)
		var pitch := deg_to_rad(_cat.camera_pitch)
		var to_cam := Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, deg_to_rad(_cat.camera_yaw))
		_cat_light.position = _cat.focus + _cat.pose_position + to_cam * 4.0 + Vector3.UP * 2.0
		var feet := _cat.pose_position  # 猫脚底（猫的旋转轴心在原点、脚踩 y = 0）
		_top_light.position = feet + Vector3.UP * top_light_height
		_top_light.light_energy = top_light_energy + pulse * top_light_pulse
		_beam.position = feet + Vector3.UP * (top_light_height / 2.0)
		_beam_mat.set_shader_parameter("strength", beam_strength * (1.0 + pulse * 0.6))
	if stage >= 1:
		for i in _stars.size():
			# 相邻的星星隔拍轮流亮
			var mine := exp(-fposmod(beat + i % 2, 2.0) * 3.0)
			_star_mats[i].emission_energy_multiplier = 1.0 + mine * 3.0
			_star_lights[i].light_energy = star_light_energy + mine * star_light_pulse
			_stars[i].scale = Vector3.ONE * (1.0 + mine * 0.25)
			_stars[i].rotation.z = sin(beat * PI / 2.0 + i) * 0.15
	# 墙灯、电脑屏幕：变亮之后每拍闪一下，之前保持原样
	for i in _prop_mats.size():
		_prop_mats[i].emission_energy_multiplier = _prop_base[i] * (1.0 + (pulse * prop_pulse if stage >= 1 else 0.0))
	if stage >= 2:
		_ball.rotation.y = beat / ball_beats_per_rev * TAU
		_ball.scale = Vector3.ONE * (1.0 + pulse * 0.08)
		for mat in _ball_mats:
			mat.emission_energy_multiplier = ball_glow + pulse * 1.2
		if _ball_mirror:
			_ball_mirror.set_shader_parameter("glow", ball_glow * 0.3 + pulse * 0.5)
		for spot in _spot_rig.get_children():
			(spot as SpotLight3D).light_energy = (spot_energy + pulse * spot_pulse * _calm()) * ball_fade * _dim()
		_ball_light.light_energy = ball_light_energy * (0.6 + pulse * _calm()) * ball_fade * _dim()
		_ball_light.light_color = white_light_color if white_light else beam_colors[int(beat) % beam_colors.size()]
		if _ball_mirror:
			_ball_mirror.set_shader_parameter("sparkle", ball_sparkle)
			_ball_mirror.set_shader_parameter("sparkle_boost", pulse * ball_sparkle_pulse)
		_update_ball_beams(beat, now, pulse)
		_update_glints(delta, pulse)
	_apply_ball_fade()
	_beam_rig.visible = stage >= 2 and _ball.visible
	for g in _glints:
		g.visible = stage >= 2 and _ball.visible and ball_fade > 0.3
	for i in _dancers.size():
		var d := _dancers[i]
		d.set_progress(beat / dancer_loop_beats + i * 0.25)
		d.offset.y = -absf(sin((beat + i * 0.5) * PI)) * dancer_hop / d.scale.y

	if takeover:
		return
	# 漂移：位置慢慢跟上进度；刚离开猫砂盆的第一段里，自转 / 歪头 / 浮动渐渐加上
	var target := clampf(float(progress - drift_at) / drift_steps, 0.0, 1.0)
	if external:
		target = clampf(external_drift, 0.0, 1.0)
	_drift = lerpf(_drift, target, 1.0 - exp(-drift_speed * delta))
	var float_amount := smoothstep(0.0, 1.0 / drift_steps, _drift)
	var bob := sin(beat / drift_bob_beats * TAU) * drift_bob * float_amount
	_cat.pose_position = _path.sample_baked(_drift * _path.get_baked_length(), true) + Vector3.UP * bob
	# 自转用真实时间累加（进度倒退时不会倒着转）；回到猫砂盆时转回正面
	if float_amount > 0.0:
		_spin_phase = fposmod(_spin_phase + delta / drift_spin_seconds, 1.0)
	else:
		_spin_phase = 0.0
	_cat.pose_yaw = _spin_phase * TAU * float_amount
	var tilt := deg_to_rad(drift_tilt_degrees) * float_amount
	var phase := beat / drift_tilt_beats * TAU
	_cat.pose_tilt = Vector2(sin(phase), cos(phase * 0.5)) * tilt


func _set_progress(value: int) -> void:
	progress = clampi(value, 0, drift_at + drift_steps)
	var new_stage := 0
	for at in [stars_at, ball_at, cats_at, drift_at]:
		if progress >= at:
			new_stage += 1
	while stage < new_stage:
		stage += 1
		_enter_stage(stage)
	while stage > new_stage:
		_leave_stage(stage)
		stage -= 1


func _target_zoom() -> float:
	if external:
		return clampf(external_zoom, 0.0, 1.0)
	var s := float(progress)
	if s <= stars_at:
		return s / stars_at * zoom_at_stars
	return lerpf(zoom_at_stars, 1.0, clampf((s - stars_at) / (ball_at - stars_at), 0.0, 1.0))


func _enter_stage(which: int) -> void:
	# 镜头猛地往外一甩再弹回来
	_kick = stage_kick
	_tween(self).tween_property(self, "_kick", 0.0, 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	match which:
		1:
			for i in _stars.size():
				var t := _tween(_stars[i])
				t.tween_interval(i * 0.08)
				t.tween_property(_stars[i], "position", _star_rest[i], 0.7) \
						.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_set_lights(bright_ambient, bright_key, bright_background)
		2:
			_tween(_ball).tween_property(_ball, "position", _ball_rest, 0.8) \
					.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		3:
			for i in dancers.size():
				var d := MemeSprite.create(dancers[i], dancer_height)
				var home := dancer_positions[i]
				d.flip_h = home.x > 0.0
				d.position = Vector2(signf(home.x) * 900.0, home.y)
				add_child(d)
				_dancers.append(d)
				var t := _tween(d)
				t.tween_interval(i * 0.12)
				t.tween_property(d, "position", home, 0.5) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	stage_changed.emit(which)


## 进度掉回门槛以下：把这个阶段的东西收回去
func _leave_stage(which: int) -> void:
	match which:
		1:
			for i in _stars.size():
				_tween(_stars[i]).tween_property(_stars[i], "position",
						_star_rest[i] + Vector3.UP * 30.0, 0.5).set_ease(Tween.EASE_IN)
				_star_lights[i].light_energy = 0.0
				_star_mats[i].emission_energy_multiplier = 1.0
			_set_lights(dark_ambient, dark_key, dark_background)
		2:
			_tween(_ball).tween_property(_ball, "position", _ball_rest + Vector3.UP * 30.0, 0.5) \
					.set_ease(Tween.EASE_IN)
			for spot in _spot_rig.get_children():
				(spot as SpotLight3D).light_energy = 0.0
			_ball_light.light_energy = 0.0
			for light in _ball_beam_lights:
				light.light_energy = 0.0
		3:
			for d in _dancers:
				var t := _tween(d)
				t.tween_property(d, "position:x", signf(d.position.x) * 900.0, 0.4) \
						.set_ease(Tween.EASE_IN)
				t.tween_callback(d.queue_free)
			_dancers.clear()
	stage_changed.emit(which - 1)


func _set_lights(ambient: float, key: float, background: Color) -> void:
	var env := _cat.environment
	var t := _tween(env).set_parallel()
	t.tween_property(env, "ambient_light_energy", ambient, 0.8)
	t.tween_property(env, "background_color", background, 0.8)
	t.tween_property(_cat.key_light, "light_energy", key, 0.8)


## 给某样东西开一个新动画，并停掉它上一个还没放完的
func _tween(what: Object) -> Tween:
	var old: Tween = _tweens.get(what)
	if old and old.is_valid():
		old.kill()
	var t := create_tween()
	_tweens[what] = t
	return t


## isometric 镜头：始终对准猫砂盆上方（猫原来的位置）；zoom 决定远近，
## 再叠加跟拍的顶一下、左右摇摆和歪头
func _apply_camera(beat: float) -> void:
	var cam := _cat.camera
	var close_size := _cat.cat_view_height * close_zoom
	var size := lerpf(close_size, _full_size, _zoom)
	var punch := exp(-fposmod(beat, 1.0) * 6.0) * _by_stage(beat_punch)
	cam.size = size * (1.0 - punch) * (1.0 + _kick)

	var sway := sin(beat / sway_beats * TAU) * _by_stage(sway_degrees)
	var pitch := deg_to_rad(_cat.camera_pitch)
	var dir := Vector3(0.0, sin(pitch), cos(pitch)) \
			.rotated(Vector3.UP, deg_to_rad(_cat.camera_yaw + sway))
	var target := _cat.focus + _cat.pose_position * drift_follow + Vector3.UP * far_look_up * _zoom
	cam.position = target + dir * 100.0
	cam.look_at(target)
	cam.rotate_object_local(Vector3.BACK, deg_to_rad(sin(beat / roll_beats * TAU) * _by_stage(roll_degrees)))


func _by_stage(values: PackedFloat32Array) -> float:
	return values[mini(stage, values.size() - 1)] if values.size() > 0 else 0.0


## 占位用的五角星（有厚度）
func _make_star_mesh(outer: float, inner: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array[Vector3] = []
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		var a := PI / 2.0 + i * TAU / 10.0
		ring.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	var front := Vector3(0.0, 0.0, depth / 2.0)
	var back := Vector3(0.0, 0.0, -depth / 2.0)
	for i in 10:
		var a := ring[i]
		var b := ring[(i + 1) % 10]
		for tri in [[front, b, a], [back, a, b]]:
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## 吊线：从定位点上方 gap 处往上 length 长
func _make_cord(length: float, gap: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.04
	mesh.height = length
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.1, 0.2)
	mesh.material = mat
	var cord := MeshInstance3D.new()
	cord.mesh = mesh
	cord.position.y = gap + length / 2.0
	return cord


## 找出灯球的球心和半径：用镜面那几块网格的包围盒（顶上的吊环 / 吊线不算，球心按水平宽度从底往上推）
func _setup_ball_center() -> void:
	_ball_center = Node3D.new()
	_ball.add_child(_ball_center)
	var box := AABB()
	var first := true
	for mi in _ball.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var local := _ball.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		box = local if first else box.merge(local)
		first = false
	if first:
		return
	_ball_radius = maxf(box.size.x, box.size.z) / 2.0
	var c := box.get_center()
	_ball_center.position = Vector3(c.x, box.position.y + _ball_radius, c.z)


## 灯球往地上打的一圈彩色光束（看得见的光柱 + 打在地上的光斑），挂在球心、跟着灯球转
func _setup_ball_beams() -> void:
	_beam_rig = Node3D.new()
	_ball_center.add_child(_beam_rig)
	# 下面全用世界单位：抵消房间的放大
	var world_scale := _ball_center.global_transform.basis.get_scale().x
	_beam_rig.scale = Vector3.ONE / world_scale
	var height := maxf(_ball_center.global_position.y, 4.0)  # 球心离地多高（地面 y = 0）
	var start := _ball_radius * world_scale * 0.9
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://stages/disco/disco_ball_beam.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tilts := PackedFloat32Array([38.0, 52.0, 66.0, 46.0, 74.0, 58.0])
	for i in beam_count:
		var tilt := deg_to_rad(tilts[i % tilts.size()] + rng.randf_range(-4.0, 4.0))
		var yaw := TAU * i / beam_count + rng.randf_range(-0.15, 0.15)
		var dir := Vector3(cos(tilt) * sin(yaw), -sin(tilt), cos(tilt) * cos(yaw))
		var length := height / sin(tilt) * 1.04 - start
		var cone := CylinderMesh.new()
		cone.top_radius = 0.1
		cone.bottom_radius = ball_beam_radius
		cone.height = length
		cone.radial_segments = 16
		cone.rings = 1
		cone.cap_top = false
		cone.cap_bottom = false
		var beam := MeshInstance3D.new()
		beam.mesh = cone
		beam.material_override = mat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 圆柱的 +Y（顶）朝灯球，底朝地面
		beam.transform = Transform3D(Basis(Quaternion(Vector3.UP, -dir)), dir * (start + length / 2.0))
		_beam_rig.add_child(beam)
		_ball_beams.append(beam)
		var light := SpotLight3D.new()
		light.light_energy = 0.0
		light.spot_range = length + start + 6.0
		light.spot_angle = rad_to_deg(atan(ball_beam_radius / (length + start))) * 1.6
		light.spot_attenuation = 0.3
		light.spot_angle_attenuation = 0.6
		_beam_rig.add_child(light)
		light.transform = Transform3D(Basis.looking_at(dir), Vector3.ZERO)
		_ball_beam_lights.append(light)
	_beam_rig.visible = false


## 白光时亮度乘多少 / 闪烁剩多少（彩色时都是 1，和原来一样）
func _dim() -> float:
	return white_brightness if white_light else 1.0


func _calm() -> float:
	return white_flicker if white_light else 1.0


func _update_ball_beams(beat: float, now: float, pulse: float) -> void:
	var shift := int(beat / beam_color_beats)
	for i in _ball_beams.size():
		var color := white_light_color if white_light else beam_colors[(i + shift) % beam_colors.size()]
		# 自己的闪烁（两个不同频率的波相乘，忽明忽暗）+ 每半拍绕一圈追着亮
		var shimmer := 0.5 + 0.5 * sin(now * 11.0 + i * 1.7) * sin(now * 6.3 + i * 2.9)
		var chase := exp(-fposmod(beat * 2.0 - float(i) / _ball_beams.size() * 2.0, 1.0) * 4.0)
		var flicker := ball_beam_flicker * _calm()
		var k := (1.0 - flicker) + flicker * (shimmer * 0.7 + chase * 0.9)
		k *= (1.0 + pulse * ball_beam_pulse * _calm()) * _dim()
		var beam := _ball_beams[i]
		beam.visible = ball_beams_visible
		beam.set_instance_shader_parameter("beam_color", color)
		beam.set_instance_shader_parameter("strength", ball_beam_strength * k * ball_fade)
		_ball_beam_lights[i].light_color = color
		_ball_beam_lights[i].light_energy = ball_beam_light * k * ball_fade


## 灯球的模型（球、吊绳）跟着 ball_fade 变透明；完全淡没就藏起来
func _apply_ball_fade() -> void:
	if is_equal_approx(ball_fade, _ball_fade_applied):
		return
	_ball_fade_applied = ball_fade
	for g in _ball.find_children("*", "GeometryInstance3D", true, false):
		if g.get_parent() == _beam_rig:
			continue  # 光束自己按 strength 淡
		(g as GeometryInstance3D).transparency = 1.0 - ball_fade
	_ball.visible = ball_fade > 0.01


## 灯球表面的十字星光：几颗轮流在朝镜头的那半边随机冒出来，亮一下就灭
func _setup_glints(cat: KisaSpinCat3D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://stages/disco/disco_glint.gdshader")
	for i in glint_count:
		var g := MeshInstance3D.new()
		g.mesh = quad
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visible = false
		cat.world.add_child(g)
		_glints.append(g)
		_glint_t.append(randf() * 2.0 + 1.0)  # 一开始错开
		_glint_dir.append(Vector3.UP)
		_glint_scale.append(1.0)


func _update_glints(delta: float, pulse: float) -> void:
	var center := _ball_center.global_position
	var radius := _ball_radius * _ball_center.global_transform.basis.get_scale().x
	var to_cam := (_cat.camera.global_position - center).normalized()
	if _cat.camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		to_cam = _cat.camera.global_transform.basis.z
	for i in _glints.size():
		_glint_t[i] += delta / glint_life
		if _glint_t[i] >= 1.0:
			# 等一会儿再冒（拍子开头更容易冒出来）
			if randf() > delta * (2.5 + pulse * 25.0):
				_glints[i].set_instance_shader_parameter("glint", 0.0)
				continue
			_glint_t[i] = 0.0
			var rand := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
			_glint_dir[i] = (to_cam * 1.2 + rand).normalized()
			_glint_scale[i] = randf_range(0.6, 1.0) * (1.0 + pulse * 0.5)
			var color := beam_colors[randi() % beam_colors.size()].lerp(Color.WHITE, 0.45)
			_glints[i].set_instance_shader_parameter("glint_color", color)
		var t := _glint_t[i]
		var amount := sin(t * PI)
		amount *= amount
		var g := _glints[i]
		# 稍微往镜头那边挪一点，免得被球面挡住一半
		g.global_position = center + _glint_dir[i] * radius * 1.02 + to_cam * radius * 0.25
		g.scale = Vector3.ONE * radius * glint_size * _glint_scale[i] * (0.4 + 0.6 * amount)
		g.set_instance_shader_parameter("glint", amount)
		g.set_instance_shader_parameter("spin", t * 0.6 + i)


## 镜头要多大才能刚好装下 node（一般是房间空壳；吊线、藏在天花板上的灯不算），以猫为中心
func _frame_size(cat: KisaSpinCat3D, node: Node3D) -> float:
	if node == null:
		return cat.camera.size
	var cam := cat.camera
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var half := Vector2.ZERO
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var aabb := m.global_transform * m.get_aabb()
		for i in 8:
			var p := aabb.get_endpoint(i) - cat.focus
			half = half.max(Vector2(absf(p.dot(right)), absf(p.dot(up))))
	var screen := Vector2(cat.world.size)
	return maxf(half.y * 2.0, half.x * 2.0 * screen.y / screen.x) * cat.frame_margin


## 房间里按名字找定位点（可能直接在房间下面，也可能包在放大用的 Scaled 节点里）
func _find(room: Node, node_name: String) -> Node3D:
	var n := room.get_node_or_null(node_name)
	if n == null:
		n = room.find_child(node_name, true, false)
	return n as Node3D


## 猫转一圈时，从脚下往外扩散一圈光波
func _emit_wave() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://stages/disco/spin_wave.gdshader")
	mat.set_shader_parameter("wave_color", wave_color)
	mat.set_shader_parameter("strength", wave_strength)
	plane.material = mat
	var wave := MeshInstance3D.new()
	wave.mesh = plane
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wave.position = _cat.pose_position + Vector3.UP * 1.2  # 略高于猫砂盆边，光波不被盆壁挡住
	wave.scale = Vector3.ONE * 0.6
	_cat.world.add_child(wave)
	var t := create_tween().set_parallel()
	t.tween_property(wave, "scale", Vector3.ONE * wave_radius, wave_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(func(p: float): mat.set_shader_parameter("progress", p), 0.0, 1.0, wave_time)
	t.chain().tween_callback(wave.queue_free)


## 判定圈在屏幕上的中心：猫脚下、和光波同一高度的那一点（相对屏幕中心，像素）
func ring_screen_offset() -> Vector2:
	if _cat == null:
		return Vector2.ZERO
	var screen := Vector2(_cat.world.size)
	return _cat.camera.unproject_position(_cat.pose_position + Vector3.UP * 1.2) - screen / 2.0


## 地上的圆在镜头里压扁成椭圆：竖向 / 横向 的比例（= 镜头俯视角的 sin）
func ring_squash() -> float:
	return sin(deg_to_rad(_cat.camera_pitch)) if _cat else 1.0


# ---- 给后面的阶段（DiscoRoad）用 ----

## 迪斯科灯球的节点
func ball_node() -> Node3D:
	return _ball


## 2D 跳舞猫退场：一只接一只慢慢滑出画面，滑的时候还在跳
func dismiss_dancers(seconds: float = 2.4) -> void:
	for i in _dancers.size():
		var d := _dancers[i]
		var t := _tween(d)
		t.tween_interval(i * 0.25)
		t.tween_property(d, "position:x", signf(d.position.x) * 900.0, seconds) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_callback(func():
			_dancers.erase(d)
			d.queue_free())


## 星星灯升回天花板上面（灯还亮着，只是出了画面）
func raise_stars() -> void:
	for i in _stars.size():
		var t := _tween(_stars[i])
		t.tween_interval(i * 0.2)
		t.tween_property(_stars[i], "position", _star_rest[i] + Vector3.UP * 40.0, 2.2) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
