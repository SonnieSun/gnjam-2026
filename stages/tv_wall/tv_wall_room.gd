class_name TvWallRoom
extends Node3D
## 电视墙房间（3D）：照效果图 v2 的摆位搭出来——一面歪着堆的 CRT 电视、录像机、左边抽屉柜、右边矮柜、
## 中间小圆桌和桌上的 3D 猫。全部用代码现搭方块 / 圆柱，材质是 Y2K 光泽塑料 + 菲涅尔玻璃。
## 屏幕里的猫脸由两个小 SubViewport 实时渲染 CATS.fbx。
## 搭好之后 tvs 里是每台电视的数据，给 TvWallStage 控制屏幕状态。

const CAT := preload("res://stages/shared/cat/CATS.fbx")
const SCREEN_SHADER := preload("res://stages/tv_wall/tv_screen.gdshader")
const GLASS_SHADER := preload("res://stages/tv_wall/glass_aero.gdshader")
const SHELLS: Array[Color] = [
	Color(0.92, 0.94, 0.97), Color(0.62, 0.68, 1.0), Color(0.7, 0.9, 1.0),
	Color(0.85, 0.8, 0.95), Color(0.55, 0.85, 0.8),
]
## 电视摆位：[底部中心, 宽, 水平转角, 歪角, 外壳色, 画面]（和效果图 v2 一样）
const LAYOUT := [
	[Vector3(-1.25, 0.82, -0.95), 0.72, 18.0, 3.0, 0, 0],
	[Vector3(-1.3, 1.42, -1.1), 0.68, 14.0, -4.0, 2, 1],
	[Vector3(-0.35, 0.55, -1.35), 0.85, 4.0, -4.0, 3, 0],
	[Vector3(-0.3, 1.27, -1.45), 0.95, 0.0, 3.0, 0, 0],
	[Vector3(0.72, 0.72, -1.0), 0.88, -24.0, -5.0, 1, 0],
	[Vector3(0.8, 1.48, -1.15), 0.72, -18.0, 2.0, 4, 1],
	[Vector3(1.5, 0.45, -0.6), 0.8, -52.0, 3.0, 2, 1],
	[Vector3(1.58, 1.1, -0.7), 0.85, -48.0, -4.0, 0, 0],
	[Vector3(1.62, 1.8, -0.85), 0.72, -42.0, 2.0, 3, 1],
	[Vector3(-0.85, 2.0, -1.6), 0.8, 8.0, -2.0, 4, 1],
	[Vector3(0.2, 2.05, -1.7), 0.8, -6.0, 4.0, 1, 0],
	[Vector3(0.3, 1.4, -1.65), 0.7, -10.0, -3.0, 2, 1],
	[Vector3(1.15, 2.2, -1.3), 0.8, -22.0, 3.0, 0, 0],
	[Vector3(-1.6, 1.95, -1.2), 0.75, 16.0, -3.0, 1, 0],
	[Vector3(-0.8, 0.7, -1.6), 0.7, 10.0, 2.0, 4, 1],
	[Vector3(-1.75, 0.0, -0.4), 0.7, 35.0, 0.0, 1, 1],
]

## 桌上猫的高度（米）
@export var cat_height := 0.5
## 桌面高度
@export var table_height := 0.62

## 每台电视：{root, screen, mat, light, center（屏幕中心，世界坐标）, normal（屏幕朝向）, half（屏幕半宽 / 半高）}
var tvs: Array[Dictionary] = []
## 桌上的猫（转圈用）
var cat: Node3D

var _rng := RandomNumberGenerator.new()
var _feeds: Array[Texture2D] = []


func _ready() -> void:
	_rng.seed = 7
	_make_feeds()
	_build_room()
	_build_tvs()
	_build_props()
	_build_table_and_cat()


# ---------------- 屏幕画面：猫脸特写 ----------------

func _make_feeds() -> void:
	# 两路：正脸、侧一点
	for s in [[0.0, 1.0, Color(0.25, 0.75, 0.7)], [28.0, 0.8, Color(0.45, 0.55, 1.0)]]:
		var vp := SubViewport.new()
		vp.size = Vector2i(320, 240)
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = (s[2] as Color).darkened(0.55)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = s[2]
		env.environment.ambient_light_energy = 0.5
		vp.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-25.0, 20.0, 0.0)
		light.light_energy = 1.3
		vp.add_child(light)
		var c := make_cat()
		c.rotation_degrees.y = s[0]
		vp.add_child(c)
		var box := measure(c)
		var cam := Camera3D.new()
		cam.fov = 30.0
		var head := Vector3(box.get_center().x, box.end.y - box.size.y * 0.22, box.end.z - box.size.z * 0.18)
		var dir := Vector3(0.0, 0.08, 1.0).rotated(Vector3.UP, deg_to_rad(s[0])).normalized()
		cam.position = head + dir * box.size.y * 2.1 * s[1]
		vp.add_child(cam)
		cam.look_at(head)
		_feeds.append(vp.get_texture())


# ---------------- 房间 ----------------

func _build_room() -> void:
	_box(Vector3(8.0, 0.1, 8.0), Vector3(0.0, -0.05, 0.0), _plastic(Color(0.06, 0.14, 0.16), 0.3))
	_box(Vector3(8.0, 5.0, 0.1), Vector3(0.0, 2.5, -2.4), _plastic(Color(0.03, 0.07, 0.08), 0.6))


func _build_tvs() -> void:
	for t in LAYOUT:
		var w: float = t[1]
		var h := w * 0.8
		var d := w * 0.85
		var root := Node3D.new()
		root.position = t[0]
		root.rotation_degrees = Vector3(0.0, t[2], t[3])
		add_child(root)
		var shell: Color = SHELLS[t[4]]
		_box(Vector3(w, h, d * 0.45), Vector3(0.0, h * 0.5, -d * 0.22), _plastic(shell, 0.12), root)
		var hood := _box(Vector3(w * 0.8, h * 0.78, d * 0.5), Vector3(0.0, h * 0.5, -d * 0.65),
				_glass(shell.lerp(Color(0.6, 0.95, 1.0), 0.5)), root)
		hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 屏幕
		var scr := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(w * 0.74, h * 0.7)
		scr.mesh = q
		scr.position = Vector3(-w * 0.06, h * 0.52, 0.006)
		var mat := _screen_mat(t[5])
		scr.material_override = mat
		root.add_child(scr)
		# 屏幕外的玻璃盖
		var cover := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 1.0
		sp.height = 2.0
		cover.mesh = sp
		cover.scale = Vector3(w * 0.39, h * 0.37, 0.05)
		cover.position = scr.position
		var cover_mat := _glass(Color(0.75, 1.0, 0.95))
		cover_mat.set_shader_parameter("face_alpha", 0.02)  # 正面几乎全透，免得屏幕黑了还罩着一层亮青色
		cover.material_override = cover_mat
		cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(cover)
		# 旋钮、金色指示灯、录像机插口
		for i in 2:
			var knob := _cyl(w * 0.04, 0.03, Vector3(w * 0.4, h * (0.68 - i * 0.2), 0.015), _plastic(Color(0.85, 0.87, 0.9), 0.1), root)
			knob.rotation_degrees.x = 90.0
		_box(Vector3(0.03, 0.015, 0.01), Vector3(w * 0.4, h * 0.16, 0.005), _neon(Color(1.0, 0.8, 0.35), 3.0), root)
		_box(Vector3(w * 0.36, 0.022, 0.01), Vector3(-w * 0.1, h * 0.08, 0.004), _plastic(Color(0.02, 0.03, 0.04), 0.3), root)
		# 屏幕前面一盏灯：屏幕亮的时候照亮周围
		var light := OmniLight3D.new()
		light.position = scr.position + Vector3(0.0, 0.0, 0.35)
		light.light_color = Color(0.45, 0.95, 0.85)
		light.light_energy = 0.0
		light.omni_range = 2.2
		light.light_specular = 0.0  # 不然玻璃盖正中间会映出一大块高光
		root.add_child(light)
		tvs.append({
			"root": root, "screen": scr, "mat": mat, "light": light,
			"local_center": scr.position, "half": Vector2(q.size.x, q.size.y) * 0.5,
		})


## 屏幕中心（世界坐标）
func screen_center(i: int) -> Vector3:
	var tv: Dictionary = tvs[i]
	return (tv.root as Node3D).global_transform * (tv.local_center as Vector3)


## 屏幕朝向（世界坐标）
func screen_normal(i: int) -> Vector3:
	return (tvs[i].root as Node3D).global_transform.basis.z.normalized()


func _build_props() -> void:
	# 中间一摞录像机
	for i in 3:
		_vcr(Vector3(-0.35, 0.16 * i, -1.3), 0.85 - (i % 2) * 0.03)
	# 右边矮柜、箱子
	_cabinet(Vector3(0.72, 0.0, -0.95), -24.0, Vector3(0.9, 0.72, 0.55), Color(0.85, 0.8, 0.95))
	_cabinet(Vector3(1.5, 0.0, -0.55), -52.0, Vector3(0.8, 0.45, 0.6), Color(0.7, 0.9, 1.0))
	# 左下抽屉柜
	var root := Node3D.new()
	root.position = Vector3(-1.2, 0.0, -0.75)
	root.rotation_degrees.y = 18.0
	add_child(root)
	var w := 0.9
	var h := 0.82
	var d := 0.6
	_box(Vector3(w, h, d), Vector3(0.0, h * 0.5, 0.0), _plastic(Color(0.92, 0.94, 0.97), 0.12), root)
	for i in 3:
		var y := h * (0.18 + i * 0.3)
		_box(Vector3(w * 0.9, h * 0.26, 0.04), Vector3(0.0, y, d * 0.5), _glass(Color(0.7, 0.9, 1.0)), root)
		_box(Vector3(w * 0.25, 0.03, 0.03), Vector3(0.0, y + 0.02, d * 0.5 + 0.03), _plastic(Color(1.0, 0.8, 0.35), 0.15), root)


func _vcr(base: Vector3, w: float) -> void:
	var root := Node3D.new()
	root.position = base
	add_child(root)
	_box(Vector3(w, 0.15, 0.55), Vector3(0.0, 0.075, -0.27), _plastic(Color(0.18, 0.2, 0.26), 0.15), root)
	_box(Vector3(w * 0.5, 0.035, 0.01), Vector3(-w * 0.15, 0.085, 0.003), _plastic(Color(0.02, 0.02, 0.03), 0.3), root)
	_box(Vector3(w * 0.16, 0.035, 0.01), Vector3(w * 0.3, 0.09, 0.003), _neon(Color(0.4, 1.0, 0.85), 2.5), root)
	_box(Vector3(w * 0.05, 0.02, 0.012), Vector3(w * 0.42, 0.045, 0.003), _neon(Color(1.0, 0.8, 0.35), 1.5), root)


func _cabinet(pos: Vector3, yaw: float, size: Vector3, tint: Color) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	_box(size, Vector3(0.0, size.y * 0.5, -size.z * 0.5), _plastic(Color(0.92, 0.94, 0.97), 0.12), root)
	_box(Vector3(size.x * 0.9, size.y * 0.85, 0.04), Vector3(0.0, size.y * 0.5, 0.0), _glass(tint), root)
	var knob := _cyl(0.025, 0.03, Vector3(size.x * 0.3, size.y * 0.6, 0.035), _plastic(Color(1.0, 0.8, 0.35), 0.15), root)
	knob.rotation_degrees.x = 90.0


func _build_table_and_cat() -> void:
	var white := _plastic(Color(0.85, 0.88, 0.92), 0.2)
	var peri := _plastic(Color(0.62, 0.68, 1.0), 0.12)
	_cyl(0.42, 0.05, Vector3(0.0, table_height - 0.025, 0.0), white)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.4
	tm.outer_radius = 0.45
	ring.mesh = tm
	ring.position = Vector3(0.0, table_height - 0.025, 0.0)
	ring.material_override = peri
	add_child(ring)
	_cyl(0.06, table_height - 0.05, Vector3(0.0, (table_height - 0.05) * 0.5, 0.0), _glass(Color(0.7, 0.92, 1.0)))
	_cyl(0.03, table_height - 0.05, Vector3(0.0, (table_height - 0.05) * 0.5, 0.0), _neon(Color(1.0, 0.8, 0.35), 1.2))
	_cyl(0.26, 0.04, Vector3(0.0, 0.02, 0.0), peri)

	# 猫：外面一层 cat 只管转（绕桌子中心的竖轴），里面一层摆正位置大小
	cat = Node3D.new()
	cat.position = Vector3(0.0, table_height, 0.05)
	cat.rotation_degrees.y = -32.0
	add_child(cat)
	var body := make_cat()
	cat.add_child(body)
	var box := measure(body)
	var s := cat_height / box.size.y
	body.scale = Vector3.ONE * s
	box = measure(body)
	body.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)


## 一只不带骨骼的 3D 猫（跟 KisaSpinCat3D 一样按静止姿势画）
static func make_cat() -> Node3D:
	var inst := CAT.instantiate() as Node3D
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).skeleton = NodePath("")
		(mi as MeshInstance3D).skin = null
	var holder := Node3D.new()
	holder.add_child(inst)
	return holder


## 模型在父节点坐标里的包围盒
static func measure(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var cur: Node = m
		while cur != null and cur != root.get_parent():
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var b := xf * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# ---------------- 材质 / 小工具 ----------------

func _screen_mat(feed: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SCREEN_SHADER
	m.set_shader_parameter("feed", _feeds[feed])
	var tints := [Color(0.55, 1.0, 0.85), Color(0.5, 0.95, 1.0), Color(0.7, 0.75, 1.0), Color(1.0, 0.88, 0.6)]
	m.set_shader_parameter("tint", tints[0] if _rng.randf() < 0.55 else tints[_rng.randi() % tints.size()])
	m.set_shader_parameter("zoom", _rng.randf_range(0.95, 1.1))
	m.set_shader_parameter("offset", Vector2(_rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.05, 0.05)))
	m.set_shader_parameter("energy", _rng.randf_range(2.2, 3.0))
	m.set_shader_parameter("roll", _rng.randf())
	m.set_shader_parameter("seed", _rng.randf())
	return m


static func _plastic(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic_specular = 0.7
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.05
	m.rim_enabled = true
	m.rim = 0.15
	m.rim_tint = 0.4
	return m


static func _glass(tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLASS_SHADER
	m.set_shader_parameter("tint", tint)
	return m


static func _neon(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _cyl(r: float, h: float, pos: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	mi.mesh = c
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi
