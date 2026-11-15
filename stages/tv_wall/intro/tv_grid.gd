class_name TvGrid
extends Node3D
## 只有电视的墙（电视墙关开场用）：电视机的做法和 TvWallRoom 一样（外壳、屏幕、玻璃盖、旋钮），
## 不带柜子、录像机、桌子。电视错落摆在一个竖直平面上，围着中间下方的洗衣机，背景全黑。
## 一开始全部不显示；light_up(i) 让第 i 台亮起来（白闪一下再显示猫脸画面）。
## 屏幕里的猫脸和 TvWallRoom 一样由两个小 SubViewport 实时渲染 CATS.fbx。

const SCREEN_SHADER := preload("res://stages/tv_wall/tv_screen.gdshader")
const GLASS_SHADER := preload("res://stages/tv_wall/glass_aero.gdshader")
const SHELLS: Array[Color] = [
	Color(0.92, 0.94, 0.97), Color(0.62, 0.68, 1.0), Color(0.7, 0.9, 1.0),
	Color(0.85, 0.8, 0.95), Color(0.55, 0.85, 0.8),
]

## 电视摆位：每台 [屏幕中心 x, 中心 y, 宽, 歪斜角度, 外壳色, 画面]（米；洗衣机中心在 0,0，宽 0.6 高 0.84）
@export var layout: Array = [
	[-1.55, 1.15, 0.75, 3.0, 0, 0],
	[-0.75, 0.95, 0.7, -3.0, 2, 1],
	[0.15, 0.88, 0.95, 2.0, 3, 0],
	[0.95, 1.38, 0.6, -4.0, 1, 1],
	[1.6, 0.8, 0.8, 3.0, 4, 0],
	[-1.2, 0.2, 0.8, -2.0, 1, 1],
	[1.05, 0.0, 0.8, 2.5, 0, 0],
	[-1.75, -0.55, 0.5, 4.0, 3, 1],
	[-0.85, -0.5, 0.65, -3.0, 4, 0],
	[1.35, -0.66, 0.75, -2.0, 2, 1],
]
## 电视墙所在的深度（洗衣机正面在 z = 0.31）
@export var wall_z := -0.05
## 亮起来的电视屏幕前那盏灯的亮度
@export var lit_light_energy := 0.3
## 亮起来用几秒从白闪过渡到画面
@export var light_up_time := 0.5

## 每台电视：{root, mat, light, center（屏幕中心，世界坐标）, lit, t（亮起来之后过了几秒）, flash}
var tvs: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _feeds: Array[Texture2D] = []


func _ready() -> void:
	_rng.seed = 11
	_make_feeds()
	_build_tvs()


func count() -> int:
	return tvs.size()


func lit_count() -> int:
	var n := 0
	for tv in tvs:
		if tv.lit:
			n += 1
	return n


## 还没亮的电视序号
func unlit() -> Array[int]:
	var out: Array[int] = []
	for i in tvs.size():
		if not tvs[i].lit:
			out.append(i)
	return out


func light_up(i: int) -> void:
	var tv: Dictionary = tvs[i]
	tv.lit = true
	tv.t = 0.0
	tv.flash = 1.0
	(tv.root as Node3D).visible = true


func reset() -> void:
	for tv in tvs:
		tv.lit = false
		(tv.root as Node3D).visible = false


## 屏幕中心（世界坐标）
func screen_center(i: int) -> Vector3:
	var tv: Dictionary = tvs[i]
	return (tv.root as Node3D).global_transform * (tv.local_center as Vector3)


## 每帧调用：beat_pulse 是 0~1 的跟拍脉冲（全亮之后一起跟着拍子闪）
func update(dt: float, beat_pulse: float) -> void:
	for tv in tvs:
		if not tv.lit:
			continue
		tv.t += dt
		tv.flash = maxf(tv.flash - dt * 3.0, 0.0)
		var power := clampf(tv.t / maxf(light_up_time, 0.01), 0.0, 1.0)
		var mat: ShaderMaterial = tv.mat
		mat.set_shader_parameter("power", power)
		mat.set_shader_parameter("static_level", 0.3)
		mat.set_shader_parameter("flash", tv.flash)
		(tv.light as OmniLight3D).light_energy = lit_light_energy * power * (1.0 + beat_pulse * 0.6) + tv.flash * 1.5


# ---------------- 屏幕画面：猫脸特写 ----------------

func _make_feeds() -> void:
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
		var c := TvWallRoom.make_cat()
		c.rotation_degrees.y = s[0]
		vp.add_child(c)
		var box := TvWallRoom.measure(c)
		var cam := Camera3D.new()
		cam.fov = 30.0
		var head := Vector3(box.get_center().x, box.end.y - box.size.y * 0.22, box.end.z - box.size.z * 0.18)
		var dir := Vector3(0.0, 0.08, 1.0).rotated(Vector3.UP, deg_to_rad(s[0])).normalized()
		cam.position = head + dir * box.size.y * 2.1 * s[1]
		vp.add_child(cam)
		cam.look_at(head)
		_feeds.append(vp.get_texture())


# ---------------- 电视 ----------------

func _build_tvs() -> void:
	for t in layout:
		var w: float = t[2]
		var h := w * 0.8
		var d := w * 0.85
		var root := Node3D.new()
		# 摆位给的是屏幕中心，电视的原点在底部中间
		root.position = Vector3(t[0], t[1] - h * 0.5, wall_z)
		root.rotation_degrees = Vector3(0.0, 0.0, t[3])
		root.visible = false
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
		cover_mat.set_shader_parameter("face_alpha", 0.02)
		cover.material_override = cover_mat
		cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(cover)
		# 旋钮、金色指示灯、录像带插口
		for i in 2:
			var knob := _cyl(w * 0.04, 0.03, Vector3(w * 0.4, h * (0.68 - i * 0.2), 0.015), _plastic(Color(0.85, 0.87, 0.9), 0.1), root)
			knob.rotation_degrees.x = 90.0
		_box(Vector3(0.03, 0.015, 0.01), Vector3(w * 0.4, h * 0.16, 0.005), _neon(Color(1.0, 0.8, 0.35), 3.0), root)
		_box(Vector3(w * 0.36, 0.022, 0.01), Vector3(-w * 0.1, h * 0.08, 0.004), _plastic(Color(0.02, 0.03, 0.04), 0.3), root)
		# 屏幕前面一盏灯：亮起来之后照亮自己的外壳和旁边的电视
		var light := OmniLight3D.new()
		light.position = scr.position + Vector3(0.0, 0.0, 0.6)
		light.light_color = Color(0.45, 0.95, 0.85)
		light.light_energy = 0.0
		light.omni_range = 1.6
		light.light_specular = 0.0
		root.add_child(light)
		tvs.append({
			"root": root, "mat": mat, "light": light, "local_center": scr.position,
			"lit": false, "t": 0.0, "flash": 0.0,
		})


# ---------------- 材质 / 小工具（和 TvWallRoom 同样的做法） ----------------

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
	m.set_shader_parameter("power", 0.0)
	m.set_shader_parameter("static_level", 0.0)
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
