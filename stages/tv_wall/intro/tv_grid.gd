class_name TvGrid
extends Node3D
## 只有电视的墙（电视墙关开场用）：电视用 Kisa 的粉色复古电视模型（stages/tv_wall/retro_tv/retro_tv.glb），
## 不带柜子、录像机、桌子。电视错落摆在一个竖直平面上，围着中间下方的洗衣机，背景全黑。
## 一开始全部不显示；light_up(i) 让第 i 台亮起来（白闪一下再显示猫脸画面）。
## 屏幕画面用我们自己的屏幕 shader 盖在模型的 Screen 网格上（没用模型自带的 tv_screen.gd）。
## 屏幕里的猫脸和 TvWallRoom 一样由两个小 SubViewport 实时渲染 CATS.fbx。

const SCREEN_SHADER := preload("res://stages/tv_wall/tv_screen.gdshader")
const TV_MODEL := preload("res://stages/tv_wall/retro_tv/retro_tv.glb")
## 外壳颜色（设定图的粉、紫、薄荷，加两个过渡色）；摆位表里的「外壳色」是这里的序号
@export var shell_colors: Array[Color] = [
	Color(1.0, 0.56, 0.76), Color(0.72, 0.62, 1.0), Color(0.5, 0.95, 0.85),
	Color(1.0, 0.72, 0.6), Color(0.6, 0.8, 1.0),
]

## 电视摆位：每台 [屏幕中心 x, 中心 y, 宽, 歪斜角度, 外壳色, 画面, 左右转角, 俯仰角]（米 / 度；洗衣机中心在 0,0，宽 0.6 高 0.84）。
## 左右转角正数 = 屏幕转向右边，俯仰角正数 = 屏幕朝下。有大有小、各自歪着，朝中间的洗衣机围过来。
@export var layout: Array = [
	[-1.6, 1.15, 0.85, 8.0, 0, 0, 28.0, 12.0],
	[-0.75, 0.98, 0.5, -10.0, 2, 1, 14.0, 8.0],
	[0.15, 0.92, 1.0, 4.0, 3, 0, -6.0, 10.0],
	[0.98, 1.4, 0.45, -14.0, 1, 1, -18.0, 16.0],
	[1.65, 0.8, 0.9, 9.0, 4, 0, -30.0, 6.0],
	[-1.2, 0.15, 0.7, -7.0, 1, 1, 24.0, -4.0],
	[1.05, 0.0, 0.6, 12.0, 0, 0, -20.0, -2.0],
	[-1.8, -0.55, 0.4, 16.0, 3, 1, 34.0, -12.0],
	[-0.85, -0.55, 0.55, -12.0, 4, 0, 16.0, -14.0],
	[1.45, -0.6, 0.95, -6.0, 2, 1, -26.0, -10.0],
]
## 电视墙所在的深度（洗衣机正面在 z = 0.31）
@export var wall_z := -0.05
## 亮起来的电视屏幕前那盏灯的亮度
@export var lit_light_energy := 0.3
## 亮起来用几秒从白闪过渡到画面
@export var light_up_time := 0.5
## 跟拍的小动作有多大（1 = 正常，0 = 不动）。每台电视一种动法（见 MOVES），整面墙各动各的；全亮之后再大一点
@export var move_amount := 0.2
@export var move_all_lit_boost := 1.4

## 小动作的种类，第 i 台电视用 MOVES[i % 7]：
##   hop     每拍往上蹦一下            wobble  左右摇摆（一拍一边）
##   nod     每拍往前点一下头          shimmy  每半拍左右横着抖一下
##   twist   反拍上扭一下（左右转）    lean    跟军鼓（第 2、4 拍）斜着晃一下再弹回来
##   flip    平时轻轻晃，每 4 小节在小节线上整台转一圈
const MOVES := ["hop", "wobble", "nod", "shimmy", "twist", "lean", "flip"]

## 每台电视：{root, mat, light, center（屏幕中心，世界坐标）, lit, t（亮起来之后过了几秒）, flash}
var tvs: Array[Dictionary] = []
## 闪烁强度 0~1（结尾那次长按时由舞台设）
var flicker := 0.0

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


## 每帧调用：beat_pulse 是 0~1 的跟拍脉冲（全亮之后一起跟着拍子闪）；beat = 全曲第几拍（< 0 = 不跟拍动）
func update(dt: float, beat_pulse: float, beat := -1.0) -> void:
	var all_lit := lit_count() == tvs.size()
	for i in tvs.size():
		var tv: Dictionary = tvs[i]
		if not tv.lit:
			continue
		_move(tv, i, beat, all_lit)
		tv.t += dt
		tv.flash = maxf(tv.flash - dt * 3.0, 0.0)
		var power := clampf(tv.t / maxf(light_up_time, 0.01), 0.0, 1.0)
		var mat: ShaderMaterial = tv.mat
		mat.set_shader_parameter("power", power)
		mat.set_shader_parameter("static_level", 0.3)
		mat.set_shader_parameter("flash", tv.flash)
		# 闪烁：每台电视各闪各的，越到后面闪得越凶
		var dim := 1.0
		if flicker > 0.0:
			dim = 1.0 - flicker * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * (38.0 + tv.home.x * 7.0) + tv.home.y * 9.0)) * _rng.randf_range(0.6, 1.0)
		mat.set_shader_parameter("dim", dim)
		power *= dim
		mat.set_shader_parameter("power", power)
		(tv.light as OmniLight3D).light_energy = lit_light_energy * power * (1.0 + beat_pulse * 0.6) + tv.flash * 1.5


## 一台电视的跟拍小动作：在摆好的位置 / 角度上叠一点偏移（大小按电视宽度算，大电视动得慢一点小一点）
func _move(tv: Dictionary, i: int, beat: float, all_lit: bool) -> void:
	var root := tv.root as Node3D
	if beat < 0.0 or move_amount <= 0.0:
		root.position = tv.home
		root.rotation = tv.home_rot
		return
	var k := move_amount * (move_all_lit_boost if all_lit else 1.0) * clampf(tv.t / 0.6, 0.0, 1.0)  # 刚亮起来时慢慢加上
	var w: float = (tv.size as Vector2).x
	var hit := exp(-fposmod(beat, 1.0) * 6.0)          # 每拍一下，很快收回
	var off := Vector3.ZERO
	var rot := Vector3.ZERO
	match MOVES[i % MOVES.size()]:
		"hop":
			off.y = hit * 0.06 * w
		"wobble":
			rot.z = sin(beat * PI) * deg_to_rad(5.0)
		"nod":
			rot.x = hit * deg_to_rad(9.0)
		"shimmy":
			off.x = sin(beat * TAU * 2.0) * 0.025 * w
		"twist":
			rot.y = exp(-fposmod(beat - 0.5, 1.0) * 6.0) * deg_to_rad(12.0) * (1.0 if int(floor(beat)) % 2 == 0 else -1.0)
		"lean":
			var snare := exp(-fposmod(beat - 1.0, 2.0) * 3.5)
			rot.z = snare * deg_to_rad(8.0) * (1.0 if i % 2 == 0 else -1.0)
			off.y = snare * 0.03 * w
		"flip":
			var into := fposmod(beat, 16.0)
			if into < 1.0:
				var e := 1.0 - pow(1.0 - into, 3.0)    # 转得快、收得稳
				rot.z = e * TAU * (1.0 if i % 2 == 0 else -1.0)
				off.z = sin(into * PI) * 0.6 * w / maxf(k, 0.01)  # 转的时候往前浮出来，不插进旁边的电视（不跟着 k 缩）
			else:
				rot.z = sin(beat * PI * 0.5) * deg_to_rad(3.0)
	var spinning: bool = MOVES[i % MOVES.size()] == "flip" and fposmod(beat, 16.0) < 1.0
	root.position = (tv.home as Vector3) + off * k
	root.rotation = (tv.home_rot as Vector3) + rot * (1.0 if spinning else k)  # 整圈的转不缩小，不然转不回原位


# ---------------- 屏幕画面：猫脸特写 ----------------

func _make_feeds() -> void:
	for s in [[0.0, 1.0, Color(0.25, 0.75, 0.7)], [28.0, 0.8, Color(0.45, 0.55, 1.0)]]:
		var vp := SubViewport.new()
		vp.size = Vector2i(160, 120)
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
		var root := TV_MODEL.instantiate() as Node3D
		var box := _screen_box(root)
		# 摆位给的是屏幕中心；模型原点在底部中间，屏幕朝 +Z；模型宽 1 米，缩放 = 想要的宽度
		root.scale = Vector3.ONE * float(t[2])
		root.rotation_degrees = Vector3(t[7], t[6], t[3])
		root.position = Vector3(t[0], t[1], wall_z) - root.transform.basis * Vector3(box.get_center().x, box.get_center().y, box.end.z)
		_setup_tv(root, t[4], t[5])


## 屏幕在模型里的位置和大小（模型自己的坐标）
func _screen_box(root: Node3D) -> AABB:
	var scr := root.find_child("Screen", true, false) as MeshInstance3D
	var to_root := Transform3D.IDENTITY
	var cur: Node = scr
	while cur != root:
		to_root = (cur as Node3D).transform * to_root
		cur = cur.get_parent()
	return to_root * scr.get_aabb()


## 一台摆好位置的电视：换外壳色、盖上屏幕 shader、加屏幕灯，登记进 tvs
func _setup_tv(root: Node3D, color_i: int, feed: int) -> void:
	var scr := root.find_child("Screen", true, false) as MeshInstance3D
	var box := _screen_box(root)
	var local_center := Vector3(box.get_center().x, box.get_center().y, box.end.z)
	var s := root.scale.x
	root.visible = false
	add_child(root)
	# 外壳和控制区换色。材质放到 material_override 上，漫画滤镜才认得（贴纸是透明的，保持原样）
	var shell: Color = shell_colors[color_i % shell_colors.size()]
	_tint(root.find_child("Shell", true, false), shell)
	for part in ["Controls", "ControlsDots_L", "ControlsDots_R"]:
		_tint(root.find_child(part, true, false), shell.darkened(0.12))
	var mat := _screen_mat(feed)
	scr.material_override = mat
	# 屏幕前面一盏灯：亮起来之后照亮自己的外壳和旁边的电视
	var light := OmniLight3D.new()
	light.position = local_center + Vector3(0.0, 0.0, 0.6)
	light.light_color = Color(0.45, 0.95, 0.85)
	light.light_energy = 0.0
	light.omni_range = 1.6 / maxf(s, 0.01)
	light.light_specular = 0.0
	root.add_child(light)
	tvs.append({
		"root": root, "mat": mat, "light": light, "local_center": local_center,
		"screen": scr, "cover": null, "size": Vector2(box.size.x, box.size.y) * s, "home": root.position, "home_rot": root.rotation,
		"lit": false, "t": 0.0, "flash": 0.0,
	})
	# 跟拍：每台电视用不同的节奏胀一下（正拍、反拍、每两拍、跟底鼓 / 军鼓……），整面墙错落着动
	BeatDecor.stagger(root, tvs.size() - 1, 0.06)


func _tint(node: Node, col: Color) -> void:
	var mi := node as MeshInstance3D
	var m := (mi.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = col
	mi.material_override = m


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


# ---------------- 结尾演出用 ----------------

const INTRO_SCREEN_SHADER := preload("res://stages/tv_wall/intro/tv_intro_screen.gdshader")


## 所有屏幕换成同一张图（白闪一下）。之后屏幕用 tv_intro_screen.gdshader。
func show_image(image: Texture2D) -> void:
	for tv in tvs:
		var m := ShaderMaterial.new()
		m.shader = INTRO_SCREEN_SHADER
		m.set_shader_parameter("image", image)
		m.set_shader_parameter("screen_aspect", tv.size.x / tv.size.y)
		(tv.screen as MeshInstance3D).material_override = m
		tv.mat = m
		tv.flash = 1.0
	flicker = 0.0


## 第 i 台电视的屏幕材质（show_image 之后是 tv_intro_screen.gdshader 的材质）
func screen_material(i: int) -> ShaderMaterial:
	return tvs[i].mat


## 屏幕的宽、高（米）
func screen_size(i: int) -> Vector2:
	return tvs[i].size


## 屏幕外的玻璃盖显示 / 藏起来（镜头钻进屏幕前藏掉）
func set_cover_visible(i: int, on: bool) -> void:
	if tvs[i].cover:
		(tvs[i].cover as Node3D).visible = on


## 离屏幕中心最近的那台电视（「中间的电视」）
func nearest_to(p: Vector3) -> int:
	var best := 0
	for i in tvs.size():
		if screen_center(i).distance_to(p) < screen_center(best).distance_to(p):
			best = i
	return best


## 除了第 keep 台，其他电视从它那里往外散开。amount 0 = 原位，1 = 散到最远（distance 米）
func scatter(keep: int, amount: float, distance: float) -> void:
	var c: Vector3 = tvs[keep].home
	for i in tvs.size():
		if i == keep:
			continue
		var tv: Dictionary = tvs[i]
		var dir := ((tv.home as Vector3) - c)
		dir.z = 0.0
		(tv.root as Node3D).position = (tv.home as Vector3) + dir.normalized() * distance * amount
