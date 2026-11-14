@tool
extends Spin3DSection
## MV 镜头 6 · 飞碟：外星猫坐着飞碟在宇宙里飞，飞碟一直自转，每打中一下多转一截、往前冲一下。
## 照着猫咪 MV 原型里的 VIEWS.ufo 移植。

const STAR_LOOP := 100.0  # 星星飞过这么远就绕回去

var _stars: Node3D
var _planet: Node3D
var _saucer: Node3D
var _pilot: Node3D
var _lights: Node3D
var _beam_mat: StandardMaterial3D
var _star_offset := 0.0
var _last_t := -1.0


func _build(root: Node3D) -> void:
	# 星星：摆两份一前一后，整体往镜头方向挪，挪过头就绕回去，看起来就是无穷无尽
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var pts := PackedVector3Array()
	for i in 900:
		pts.append(Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(-20.0, 20.0), rng.randf_range(-80.0, 10.0)))
	_stars = Node3D.new()
	root.add_child(_stars)
	for copy in 2:
		var field := CatBuilder.star_field(pts, 0.12)
		field.position.z = -STAR_LOOP * copy
		_stars.add_child(field)

	_planet = CatBuilder.sphere(4.0, CatBuilder.toon(Color("c77dff")))
	root.add_child(_planet)
	var planet_ring := CatBuilder.torus(6.0, 0.25, CatBuilder.toon(Color("ffd27a")))
	planet_ring.rotation.x = 1.2 + PI / 2
	_planet.add_child(planet_ring)

	_saucer = Node3D.new()
	root.add_child(_saucer)
	var hull := CatBuilder.sphere(2.2, CatBuilder.toon(Color("9aa3b5")))
	hull.scale.y = 0.22
	_saucer.add_child(hull)
	_saucer.add_child(CatBuilder.torus(2.1, 0.12, CatBuilder.toon(Color("6a7385"))))

	_pilot = Node3D.new()  # 外星猫 + 两根天线
	_pilot.position.y = 0.75
	_saucer.add_child(_pilot)
	_pilot.add_child(CatBuilder.make_head({"r": 0.55, "eyes": "big", "color": Color("b8e08a"), "patch": false}))
	for sx: float in [-1.0, 1.0]:
		var ant := CatBuilder.cylinder(0.03, 0.03, 0.5, CatBuilder.toon(CatBuilder.DARK), 8)
		ant.position = Vector3(sx * 0.2, 0.75, 0.0)
		ant.rotation.z = -sx * 0.3
		_pilot.add_child(ant)
		_pilot.add_child(CatBuilder.sphere(0.08, CatBuilder.toon(Color("ffe34d")), Vector3(sx * 0.28, 1.0, 0.0)))

	var dome_mesh := SphereMesh.new()  # 玻璃罩（半球）
	dome_mesh.radius = 1.2
	dome_mesh.height = 1.2
	dome_mesh.is_hemisphere = true
	_saucer.add_child(CatBuilder.part(dome_mesh, CatBuilder.flat(Color("bff0ff"), 0.25), Vector3(0.0, 0.3, 0.0)))

	_lights = Node3D.new()  # 一圈彩灯
	_saucer.add_child(_lights)
	for i in 10:
		var a := i / 10.0 * TAU
		_lights.add_child(CatBuilder.sphere(0.13, CatBuilder.flat(Color("ffe34d") if i % 2 else Color("ff6a8a")),
				Vector3(cos(a) * 2.1, 0.0, sin(a) * 2.1)))

	_beam_mat = CatBuilder.flat(Color("fff2a0"), 0.12, true)  # 下面的光束
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.0
	beam_mesh.bottom_radius = 1.6
	beam_mesh.height = 3.0
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	_saucer.add_child(CatBuilder.part(beam_mesh, _beam_mat, Vector3(0.0, -1.6, 0.0)))


func _focus() -> Vector3:
	return _pilot.global_position


func _camera_pose(_p: float, t: float) -> Dictionary:
	var a := sin(t * 0.5) * 0.6
	var sp := _saucer.position
	return {
		"pos": Vector3(sp.x * 0.6 + sin(a) * 7.5, sp.y * 0.6 + 2.2, cos(a) * 7.5),
		"look": Vector3(sp.x * 0.8, sp.y * 0.8 + 0.3, 0.0),
		"roll": -_saucer.rotation.z * 0.8,
	}


func _update_view(t: float) -> void:
	var dt := 0.0 if _last_t < 0.0 else minf(t - _last_t, 0.05)
	_last_t = t
	# 星星往镜头飞过来 = 飞碟在往前飞；打中时加速
	_star_offset = fmod(_star_offset + (18.0 + pulse() * 60.0) * dt, STAR_LOOP)
	_stars.position.z = _star_offset
	_planet.position = Vector3(-14.0, 6.0, -60.0 + fmod(t * 6.0, 80.0))
	if _planet.position.z > 15.0:
		_planet.position.z -= 80.0

	_saucer.position = Vector3(sin(t * 0.7) * 1.6, sin(t * 1.1) * 0.7, 0.0)
	CatBuilder.euler_xyz(_saucer, 0.0,
			step_rot * 1.2 + t * 1.5,                # 整个飞碟自转
			-cos(t * 0.7) * 0.35 + pulse() * 0.15)   # 跟着左右飘倾斜
	_pilot.rotation.y = step_rot * 1.5
	_lights.rotation.y = step_rot * 2.0 + t
	_beam_mat.albedo_color.a = 0.1 + pulse() * 0.25
