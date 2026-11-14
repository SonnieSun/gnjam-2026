extends Node3D
## 电视墙效果图：只用来出图，不进关卡。
## 暗房间里一面堆叠的 CRT 电视 + 录像机，每台屏幕里放猫脸特写（另一个 SubViewport 实时渲染 CATS.fbx）；
## 前景小圆桌上坐着猫，左右下角抽屉柜。材质照 spaceship/y2k_mockup 的 Y2K 配方（光泽塑料、菲涅尔玻璃），
## 最后盖一层 360 线方像素 + 16 位抖动 + 长春花蓝 / 金分离调色。
## 运行后等几帧自动截图存到 _local/mockups/，然后退出。
## 测试用，只在本机 _sandbox 里，不进仓库。

const CAT := preload("res://stages/shared/cat/CATS.fbx")

## 出图文件名（_local/mockups/ 下）
@export var out_name := "tv-wall-y2k-v1"
## 方像素输出开关
@export var era_output := true
## 截完图自动退出
@export var auto_quit := true
## 桌上猫的高度（米）
@export var cat_height := 0.66
## 屏幕里猫脸特写的镜头远近（猫身高的倍数）
@export var feed_distance := 1.6
## 屏幕暗角强度
@export var screen_vignette := 2.2

var _rng := RandomNumberGenerator.new()
var _screen_tex: Array[Texture2D] = []
var _frames := 0


func _ready() -> void:
	_rng.seed = 7
	_make_screen_feeds()
	_build_env()
	_build_room()
	_build_tv_wall()
	_build_table_and_cat()
	_build_dressers()
	_build_camera()
	if era_output:
		var layer := CanvasLayer.new()
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://stages/tv_wall/mockup/era_screen.gdshader")
		rect.material = mat
		layer.add_child(rect)
		add_child(layer)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 30:
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://stages/tv_wall/mockup/%s.png" % out_name)
		img.save_png(path)
		print("saved ", path)
		if auto_quit:
			get_tree().quit()


# ---------------- 屏幕画面：猫脸特写 ----------------

func _make_screen_feeds() -> void:
	# 两路画面：正脸特写、侧一点的特写
	var shots := [[0.0, 1.0, Color(0.25, 0.75, 0.7)], [28.0, 0.8, Color(0.45, 0.55, 1.0)]]
	for s in shots:
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
		var cat := _make_cat(1.0)
		cat.rotation_degrees.y = s[0]
		vp.add_child(cat)
		var box := _measure(cat)
		var cam := Camera3D.new()
		cam.fov = 30.0
		# 头在模型前上方：对准包围盒前 1/5、上 1/4 处
		var head := Vector3(box.get_center().x, box.end.y - box.size.y * 0.22, box.end.z - box.size.z * 0.18)
		var dir := Vector3(0.0, 0.08, 1.0).rotated(Vector3.UP, deg_to_rad(s[0])).normalized()
		cam.position = head + dir * box.size.y * (feed_distance * s[1])
		vp.add_child(cam)
		cam.look_at(head)
		_screen_tex.append(vp.get_texture())


# ---------------- 环境 ----------------

func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.03, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.5, 0.55)
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_intensity = 0.9
	env.glow_bloom = 0.2
	env.ssr_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.3, 0.32)
	env.fog_density = 0.02
	we.environment = env
	add_child(we)

	# 屏幕散出来的青绿光（从电视墙往前打）
	for x in [-2.2, 0.0, 2.2]:
		var o := OmniLight3D.new()
		o.position = Vector3(x, 1.6, -1.6)
		o.light_color = Color(0.35, 0.95, 0.85)
		o.light_energy = 1.1
		o.omni_range = 5.0
		add_child(o)
	# 猫背后的长春花蓝逆光
	var rim := SpotLight3D.new()
	rim.position = Vector3(0.0, 1.6, -1.2)
	rim.light_color = Color(0.6, 0.65, 1.0)
	rim.light_energy = 6.0
	rim.spot_range = 4.0
	rim.spot_angle = 35.0
	add_child(rim)
	rim.look_at(Vector3(0.0, 0.8, 0.0))
	# 前景两侧抽屉柜的弱青绿补光
	for x in [-1.9, 1.9]:
		var f := OmniLight3D.new()
		f.position = Vector3(x, 1.4, 1.6)
		f.light_color = Color(0.4, 0.85, 0.9)
		f.light_energy = 0.8
		f.omni_range = 3.0
		add_child(f)
	# 镜头这边一点暖金补光，让猫脸看得见
	var key := SpotLight3D.new()
	key.position = Vector3(1.2, 1.8, 2.6)
	key.light_color = Color(1.0, 0.82, 0.55)
	key.light_energy = 2.5
	key.spot_range = 6.0
	key.spot_angle = 22.0
	key.shadow_enabled = true
	add_child(key)
	key.look_at(Vector3(0.0, 0.85, 0.0))


func _build_room() -> void:
	var floor_mat := _plastic(Color(0.06, 0.14, 0.16), 0.25)
	_box(Vector3(10.0, 0.1, 8.0), Vector3(0.0, -0.05, 0.0), floor_mat)
	_box(Vector3(10.0, 6.0, 0.1), Vector3(0.0, 3.0, -3.2), _plastic(Color(0.03, 0.07, 0.08), 0.6))


# ---------------- 电视墙 ----------------

func _build_tv_wall() -> void:
	var shells := [
		Color(0.92, 0.94, 0.97), Color(0.62, 0.68, 1.0), Color(0.7, 0.9, 1.0),
		Color(0.85, 0.8, 0.95), Color(0.55, 0.85, 0.8), Color(0.25, 0.27, 0.32),
	]
	# 一列一列往上堆：宽度不同，偶尔插一台录像机
	var x := -3.6
	var col := 0
	while x < 3.6:
		var w := _rng.randf_range(0.75, 1.05)
		var y := 0.0
		var z := -2.55 + _rng.randf_range(-0.12, 0.12)
		var tier := 0
		while y < 3.8:
			if _rng.randf() < 0.28 and tier > 0:
				_vcr(Vector3(x + w * 0.5, y, z + 0.1), w * 0.9)
				y += 0.16
			var h := w * _rng.randf_range(0.72, 0.85)
			var shell: Color = shells[_rng.randi() % shells.size()]
			_crt(Vector3(x + w * 0.5 + _rng.randf_range(-0.04, 0.04), y, z), Vector2(w * 0.97, h), shell, (col + tier) % 2)
			y += h
			tier += 1
		x += w
		col += 1
	# 墙前地上再摆两台录像机 + 一台小电视
	_vcr(Vector3(-1.3, 0.0, -1.7), 0.8)
	_vcr(Vector3(-1.3, 0.16, -1.7), 0.8)
	_crt(Vector3(1.5, 0.0, -1.75), Vector2(0.6, 0.48), shells[1], 1)


func _crt(base: Vector3, size: Vector2, shell: Color, feed: int) -> void:
	var w := size.x
	var h := size.y
	var d := w * 0.85
	var root := Node3D.new()
	root.position = base
	root.rotation_degrees.y = _rng.randf_range(-4.0, 4.0)
	add_child(root)
	# 机壳：前框 + 后面的显像管罩（菲涅尔玻璃，Y2K 半透明）
	_box(Vector3(w, h, d * 0.45), Vector3(0.0, h * 0.5, -d * 0.22), _plastic(shell, 0.12), root)
	var hood := _box(Vector3(w * 0.8, h * 0.78, d * 0.5), Vector3(0.0, h * 0.5, -d * 0.65), _glass(shell.lerp(Color(0.6, 0.95, 1.0), 0.5)), root)
	hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 屏幕
	var scr := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w * 0.74, h * 0.7)
	scr.mesh = q
	scr.position = Vector3(-w * 0.06, h * 0.52, 0.006)
	scr.material_override = _screen_mat(feed)
	root.add_child(scr)
	# 屏幕外的玻璃盖（亮边）
	var cover := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	cover.mesh = sp
	cover.scale = Vector3(w * 0.39, h * 0.37, 0.05)
	cover.position = scr.position
	cover.material_override = _glass(Color(0.75, 1.0, 0.95))
	cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cover)
	# 右边旋钮 + 金色指示灯
	for i in 2:
		var knob := _cyl(w * 0.04, 0.03, Vector3(w * 0.4, h * (0.68 - i * 0.2), 0.015), _plastic(Color(0.85, 0.87, 0.9), 0.1), root)
		knob.rotation_degrees.x = 90.0
	var led := _box(Vector3(0.03, 0.015, 0.01), Vector3(w * 0.4, h * 0.16, 0.005), _neon(Color(1.0, 0.8, 0.35), 3.0), root)
	led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _vcr(base: Vector3, w: float) -> void:
	var root := Node3D.new()
	root.position = base
	add_child(root)
	_box(Vector3(w, 0.15, 0.55), Vector3(0.0, 0.075, -0.27), _plastic(Color(0.18, 0.2, 0.26), 0.15), root)
	_box(Vector3(w * 0.5, 0.035, 0.01), Vector3(-w * 0.15, 0.085, 0.003), _plastic(Color(0.02, 0.02, 0.03), 0.3), root)
	# 青绿时钟显示 + 金按钮
	_box(Vector3(w * 0.16, 0.035, 0.01), Vector3(w * 0.3, 0.09, 0.003), _neon(Color(0.4, 1.0, 0.85), 2.5), root)
	_box(Vector3(w * 0.05, 0.02, 0.012), Vector3(w * 0.42, 0.045, 0.003), _neon(Color(1.0, 0.8, 0.35), 1.5), root)


# ---------------- 圆桌 + 猫 ----------------

func _build_table_and_cat() -> void:
	var top_h := 0.62
	var white := _plastic(Color(0.93, 0.95, 0.97), 0.1)
	var peri := _plastic(Color(0.62, 0.68, 1.0), 0.12)
	_cyl(0.42, 0.05, Vector3(0.0, top_h - 0.025, 0.0), white)
	# 桌边一圈长春花蓝胶圈
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.4
	tm.outer_radius = 0.45
	ring.mesh = tm
	ring.position = Vector3(0.0, top_h - 0.025, 0.0)
	ring.material_override = peri
	add_child(ring)
	# 半透明玻璃柱 + 圆底座
	_cyl(0.06, top_h - 0.05, Vector3(0.0, (top_h - 0.05) * 0.5, 0.0), _glass(Color(0.7, 0.92, 1.0)))
	_cyl(0.03, top_h - 0.05, Vector3(0.0, (top_h - 0.05) * 0.5, 0.0), _neon(Color(1.0, 0.8, 0.35), 1.2))
	_cyl(0.26, 0.04, Vector3(0.0, 0.02, 0.0), peri)

	var cat := _make_cat(1.0)
	add_child(cat)
	var box := _measure(cat)
	var s := cat_height / box.size.y
	cat.scale = Vector3.ONE * s
	box = _measure(cat)
	cat.position = Vector3(-box.get_center().x, top_h - box.position.y, -box.get_center().z + 0.05)
	cat.rotation_degrees.y = -18.0


func _make_cat(_size: float) -> Node3D:
	var inst := CAT.instantiate() as Node3D
	# 跟 KisaSpinCat3D 一样不用骨骼，按静止姿势画
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).skeleton = NodePath("")
		(mi as MeshInstance3D).skin = null
	var holder := Node3D.new()
	holder.add_child(inst)
	return holder


# ---------------- 抽屉柜 ----------------

func _build_dressers() -> void:
	_dresser(Vector3(-2.1, 0.0, 0.55), 24.0, Color(0.7, 0.9, 1.0))
	_dresser(Vector3(2.15, 0.0, 0.5), -22.0, Color(0.85, 0.8, 0.95))


func _dresser(pos: Vector3, yaw: float, tint: Color) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	var w := 0.95
	var h := 0.78
	var d := 0.55
	_box(Vector3(w, h, d), Vector3(0.0, h * 0.5, 0.0), _plastic(Color(0.92, 0.94, 0.97), 0.12), root)
	# 三层半透明抽屉（Y2K 收纳柜那种）+ 金色把手
	for i in 3:
		var y := h * (0.2 + i * 0.29)
		_box(Vector3(w * 0.9, h * 0.25, 0.04), Vector3(0.0, y, d * 0.5), _glass(tint), root)
		_box(Vector3(w * 0.25, 0.03, 0.03), Vector3(0.0, y + 0.02, d * 0.5 + 0.03), _plastic(Color(1.0, 0.8, 0.35), 0.15), root)
	# 柜面上的小东西：一台小电视
	_crt_on(root, Vector3(-0.15, h, -0.05))


func _crt_on(parent: Node3D, p: Vector3) -> void:
	var holder := Node3D.new()
	holder.position = p
	parent.add_child(holder)
	var old_add := holder
	# 复用 _crt：先建在根上，再挪到柜子下面
	var before := get_child_count()
	_crt(Vector3.ZERO, Vector2(0.42, 0.34), Color(0.62, 0.68, 1.0), 0)
	var tv := get_child(before)
	remove_child(tv)
	old_add.add_child(tv)


# ---------------- 镜头 ----------------

func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.fov = 48.0
	cam.position = Vector3(0.0, 1.0, 3.5)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.35, -1.0))
	cam.current = true


# ---------------- 材质 / 小工具 ----------------

func _plastic(c: Color, rough: float) -> StandardMaterial3D:
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


func _glass(tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://stages/tv_wall/mockup/glass_aero.gdshader")
	m.set_shader_parameter("tint", tint)
	return m


func _neon(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _screen_mat(feed: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://stages/tv_wall/mockup/crt_screen.gdshader")
	m.set_shader_parameter("feed", _screen_tex[feed])
	var tints := [Color(0.55, 1.0, 0.85), Color(0.5, 0.95, 1.0), Color(0.7, 0.75, 1.0), Color(1.0, 0.88, 0.6)]
	m.set_shader_parameter("tint", tints[0] if _rng.randf() < 0.55 else tints[_rng.randi() % tints.size()])
	m.set_shader_parameter("zoom", _rng.randf_range(0.85, 1.15))
	m.set_shader_parameter("offset", Vector2(_rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.05, 0.05)))
	m.set_shader_parameter("energy", _rng.randf_range(1.4, 2.4))
	m.set_shader_parameter("roll", _rng.randf())
	m.set_shader_parameter("vignette", screen_vignette)
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


func _measure(root: Node3D) -> AABB:
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
