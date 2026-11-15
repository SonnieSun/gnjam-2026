class_name EarthSlapStage
extends Node
## 拍地球小关的 3D 舞台。美术整套引用 moumou 的拍地球猫模型（assets/models/cat_earth_y2k/cat_earth_model.tscn：
## 猫、地球、星系背景、蓝紫星星和那段 4 秒挥爪动画，不改他的文件），镜头和灯光照他的 cat_earth.tscn 摆。
## 动画不按时间播，按拍子定位：每 beats_per_swat 拍挥一次爪，爪子碰到地球那一帧正好落在该按的那一拍上。
## 猫 meme 纸片（2D 图立在 3D 里）一只只进场，每拍中一次所有纸片做一次 3D 翻转。
## 结尾：镜头拉近到地球占大半个画面，原来的猫和纸片消失；我们的猫屁股喷着火从地球里飞出来，
## 飞进宇宙停住，脚下冒出一块披萨（披萨用飞船关的模型，只引用）。
## 关卡脚本 EarthSlapSection 每帧调 update()，判定时调 slap() / miss()。参数都在 Stage 节点的 Inspector 里。

const MODEL := preload("res://assets/models/cat_earth_y2k/cat_earth_model.tscn")
const PIZZA := preload("res://stages/space_shooter/model/neapolitan_pizza.glb")
const FLAME := preload("res://stages/earth_slap/fx/cat_rocket_flame.png")

@export_group("镜头和灯光（照 cat_earth.tscn）")
@export var camera_position := Vector3(7.4, 6.0, 11.5)
@export var camera_target := Vector3(0.36, 1.95, -0.22)
## 正交镜头上下能看到多高（米）
@export var camera_size := 7.5
## 拍中时镜头抖多少（米），按力度放大
@export var hit_shake := 0.06

@export_group("动画")
@export var animation_clip: StringName = &"CatEarthLoop"
## 原动画一轮 4 秒里挥两次爪，一次 2 秒；这是第一次碰到地球的时刻（秒）
@export var contact_seconds := 29.0 / 24.0
@export var swat_seconds := 2.0
## 判定圈画在哪（模型自己的坐标，moumou 场景里的 Focus 标记）
@export var focus := Vector3(1.11, 1.21, 0.56)

@export_group("拍中反馈")
## 拍中时整套模型弹大多少（按力度放大）
@export var hit_pulse := 0.04

@export_group("猫 meme 纸片")
## 素材名字（写法见 MemeLib），按这个顺序一只只进场
@export var memes := PackedStringArray(["banana", "oiia", "popcat", "nyan", "apple", "flower"])
## 每张纸片在画面上的位置（镜头坐标：x 往右、y 往上，米；画面高 7.5 米、4:3 时宽 10 米），和 memes 一一对应
@export var meme_positions := PackedVector2Array([
	Vector2(-3.9, 2.4), Vector2(-4.0, -0.9), Vector2(3.9, 2.5),
	Vector2(4.0, -0.6), Vector2(-1.9, 3.0), Vector2(3.1, -2.5),
])
## 纸片高度（米）
@export var meme_height := 1.3
## 拍中一次翻多少度；力度大的按力度最多再多翻几个半圈
@export var meme_flip_degrees := 180.0
@export var meme_extra_half_turns := 3
@export var meme_flip_time := 0.35

@export_group("结尾：猫着火飞出去")
## 拉近后画面上下能看到多高（米；地球直径约 2 米，越小地球越大）
@export var ending_close_size := 2.4
## 地球中心（模型自己的坐标）
@export var earth_center := Vector3(0.15, 0.65, 1.2)
## 猫飞到哪停住（镜头坐标：x 往右、y 往上，米，相对地球中心）
@export var ending_fly_to := Vector2(3.2, 2.6)
## 猫停住时镜头看多高（米）和画面中心（镜头坐标，相对地球中心）
@export var ending_final_size := 7.0
@export var ending_final_center := Vector2(1.9, 1.5)
## 飞出来的猫多高（米）
@export var ending_cat_height := 1.5
## 火焰长度（米）
@export var flame_length := 2.6
## 披萨直径（米）
@export var pizza_diameter := 2.4

var world: SubViewport
var camera: Camera3D

var _sprite: Sprite2D
var _model: Node3D
var _animation: AnimationPlayer
var _clip: StringName
var _shake := 0.0
var _pulse := 0.0
var _cards: Array[Dictionary] = []  # {"node", "info", "from", "to", "t", "grow"}
var _basis: Basis  # 镜头的朝向（纸片、飞出来的猫都朝着镜头摆）
var _ending := -1.0  # 结尾放到百分之几（< 0 = 还没开始）
var _rocket: Node3D
var _rocket_cat: Node3D
var _flame: Sprite3D
var _pizza: Node3D


func setup(host: Node2D) -> void:
	world = SubViewport.new()
	world.size = Vector2i(host.get_viewport_rect().size)
	world.own_world_3d = true  # 要在带蒙皮的模型进场景树之前设好
	world.msaa_3d = Viewport.MSAA_4X
	host.add_child(world)
	_sprite = Sprite2D.new()
	_sprite.texture = world.get_texture()
	_sprite.z_index = -1
	host.add_child(_sprite)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.008, 0.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 1.0)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.15
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.9, 0.83)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	for l in [[Vector3(-5.0, 4.0, 1.0), Color(0.54, 0.74, 1.0), 1.1, 16.0], [Vector3(3.0, 7.0, -5.0), Color(0.55, 0.76, 1.0), 1.4, 18.0]]:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.light_color = l[1]
		o.light_energy = l[2]
		o.omni_range = l[3]
		world.add_child(o)

	_model = MODEL.instantiate() as Node3D
	world.add_child(_model)
	_animation = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation:
		_clip = animation_clip
		if not _animation.has_animation(_clip):
			_clip = &""
			for candidate: StringName in _animation.get_animation_list():
				if candidate != &"RESET":
					_clip = candidate
					break
		if _clip != &"":
			_animation.play(_clip)
			_animation.pause()

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_size
	camera.far = 80.0
	camera.position = camera_position
	world.add_child(camera)
	camera.look_at(camera_target)
	camera.current = true
	_basis = camera.global_transform.basis


# ---------------- 给关卡脚本的 ----------------

## 拍中一次。power 0 = 轻拍，1 = 最重
func slap(power: float) -> void:
	_shake = 1.0 + power * 2.0
	_pulse = 1.0 + power * 2.0
	var turn := deg_to_rad(meme_flip_degrees) * (1 + roundi(power * meme_extra_half_turns))
	for c in _cards:
		c.from = c.to
		c.to = c.from + turn
		c.t = 0.0


func miss() -> void:
	_shake = 0.5


## 让纸片进场到一共 count 只（已经在场的不动）
func show_memes(count: int) -> void:
	var total := mini(memes.size(), meme_positions.size())
	for i in range(_cards.size(), mini(count, total)):
		var info := MemeLib.find(memes[i])
		# 外面一层朝着镜头站好，里面的纸片绕自己的竖轴翻
		var holder := Node3D.new()
		holder.transform = Transform3D(_basis, camera_position + _basis * Vector3(meme_positions[i].x, meme_positions[i].y, -8.0 - i * 0.2))
		world.add_child(holder)
		var node := Sprite3D.new()
		if not info.is_empty():
			node.texture = load(info.path)
			node.hframes = info.cols
			node.vframes = info.rows
			node.pixel_size = meme_height / (node.texture.get_height() / float(info.rows))
		node.shaded = false
		node.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		node.scale = Vector3.ONE * 0.01
		holder.add_child(node)
		_cards.append({"node": node, "info": info, "from": 0.0, "to": 0.0, "t": 1.0, "grow": 0.0})


## 一共能进场几只纸片
func meme_total() -> int:
	return mini(memes.size(), meme_positions.size())


## 判定圈中心在 2D 画面上的位置（相对屏幕中心）
func focus_screen_pos() -> Vector2:
	return camera.unproject_position(_model.to_global(focus)) - Vector2(world.size) / 2.0


## 开始放结尾（之后每帧用 set_ending() 告诉它放到百分之几）
func start_ending() -> void:
	if _ending >= 0.0:
		return
	_ending = 0.0
	# 飞出来的猫：外面一层朝着镜头摆、负责位置和歪斜；里面是猫、火焰
	_rocket = Node3D.new()
	_rocket.visible = false
	world.add_child(_rocket)
	_rocket_cat = TvWallRoom.make_cat()
	_rocket.add_child(_rocket_cat)
	var box := TvWallRoom.measure(_rocket_cat)
	_rocket_cat.scale = Vector3.ONE * ending_cat_height / maxf(box.size.y, 0.0001)
	_rocket_cat.position = -(_rocket_cat.transform.basis * box.get_center())
	for mi in _rocket_cat.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_texture = preload("res://stages/shared/cat/cat_basecolor_512.png")
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		(mi as MeshInstance3D).material_override = m
	# 火焰：图里喷口在左边，尾巴往右。贴在猫屁股（脚下）往下喷，所以转成尾巴朝下
	_flame = Sprite3D.new()
	_flame.texture = FLAME
	_flame.pixel_size = flame_length / FLAME.get_width()
	_flame.centered = false
	_flame.offset = Vector2(-FLAME.get_width() * 0.1, -FLAME.get_height() * 0.5)  # 原点放在喷口
	_flame.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	_flame.position = Vector3(0.0, -ending_cat_height * 0.4, -0.3)
	_flame.shaded = false
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = FLAME
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame.material_override = fm
	_rocket.add_child(_flame)
	# 披萨：最后从猫脚下冒出来，稍微朝镜头翻一点好看见饼面
	_pizza = Node3D.new()
	_pizza.visible = false
	_rocket.add_child(_pizza)
	var pie := PIZZA.instantiate() as Node3D
	_pizza.add_child(pie)
	var pbox := TvWallRoom.measure(pie)
	pie.scale = Vector3.ONE * pizza_diameter / maxf(maxf(pbox.size.x, pbox.size.z), 0.0001)
	pie.position = -(pie.transform.basis * pbox.get_center())
	_pizza.position = Vector3(0.0, -ending_cat_height * 0.55, 0.0)
	_pizza.rotation_degrees = Vector3(35.0, 0.0, 0.0)


## 结尾放到百分之几（0~1）
func set_ending(p: float) -> void:
	_ending = clampf(p, 0.0, 1.0)


func ending_active() -> bool:
	return _ending >= 0.0


# ---------------- 每帧 ----------------

## beat = 这个小关里的拍数；每 beats_per_swat 拍挥一次爪，碰到地球落在每轮的第 strike_beat 拍
func update(dt: float, beat: float, beats_per_swat: float, strike_beat: float) -> void:
	var size := Vector2i(world.get_parent().get_viewport_rect().size)
	if world.size != size:
		world.size = size
	if _animation and _clip != &"":
		var length := _animation.get_animation(_clip).length
		var t := fposmod((beat - strike_beat) / maxf(beats_per_swat, 0.25) * swat_seconds + contact_seconds, swat_seconds * 2.0)
		_animation.seek(minf(t, length), true)
	_shake = maxf(_shake - dt * 8.0, 0.0)
	_pulse = maxf(_pulse - dt * 7.0, 0.0)
	_model.scale = Vector3.ONE * (1.0 + hit_pulse * _pulse)
	var ms := Time.get_ticks_msec() * 0.001
	var shake := _basis * Vector3(sin(ms * 90.0), cos(ms * 110.0), 0.0) * hit_shake * _shake
	# 纸片：出场长大、翻转、播动图；结尾时缩没
	var gone := smoothstep(0.0, 0.12, _ending) if _ending >= 0.0 else 0.0
	for c in _cards:
		var node: Sprite3D = c.node
		c.grow += dt * 3.0
		var g := clampf(c.grow, 0.0, 1.0)
		node.scale = Vector3.ONE * maxf(g * (2.0 - g) * (1.0 - gone), 0.01)
		c.t = minf(c.t + dt / maxf(meme_flip_time, 0.01), 1.0)
		var e := 1.0 - pow(1.0 - c.t, 3.0)
		node.rotation.y = lerpf(c.from, c.to, e)
		var info: Dictionary = c.info
		if not info.is_empty() and int(info.frames) > 1:
			node.frame = int(ms * float(info.fps)) % int(info.frames)
	if _ending < 0.0:
		camera.size = camera_size
		camera.position = camera_position + shake
		return
	_update_ending(ms)


## 结尾：0~0.3 拉近地球、原来的猫消失；0.3~0.4 地球抖；0.4~0.75 猫喷着火飞出来、镜头跟着拉远；
## 0.75~0.9 猫停住站正、火灭、脚下冒披萨；之后停着飘
func _update_ending(ms: float) -> void:
	var p := _ending
	var rig := _model.get_node_or_null("CatRig") as Node3D
	if rig:
		rig.visible = p < 0.1
	# 镜头只平移和改大小，朝向不变。画面中心从原来的位置挪到地球，再跟着猫挪出去
	var forward := -_basis.z
	var earth := _model.to_global(earth_center)
	var home := camera_position
	var on_earth := earth - forward * (earth - camera_position).dot(forward)  # 正对地球、和原来一样远
	var final := on_earth + _basis * Vector3(ending_final_center.x, ending_final_center.y, 0.0)
	var zin := smoothstep(0.0, 0.3, p)
	var zout := smoothstep(0.45, 0.8, p)
	var pos := home.lerp(on_earth, zin).lerp(final, zout)
	var rumble := smoothstep(0.28, 0.4, p) * (1.0 - smoothstep(0.4, 0.5, p))
	pos += _basis * Vector3(sin(ms * 70.0), cos(ms * 83.0), 0.0) * 0.05 * rumble
	camera.size = lerpf(lerpf(camera_size, ending_close_size, zin), ending_final_size, zout)
	camera.position = pos
	# 飞出来的猫
	var fly := smoothstep(0.4, 0.78, p)
	_rocket.visible = p >= 0.4
	var k := 1.0 - pow(1.0 - fly, 2.0)
	var target := earth + _basis * Vector3(ending_fly_to.x, ending_fly_to.y, 0.0) - forward * 3.0  # 往镜头这边一点，不被地球挡
	var from := earth - forward * 1.0
	var settle := smoothstep(0.75, 0.9, p)
	var bob := sin(ms * 2.2) * 0.12 * settle
	var tilt := -atan2(ending_fly_to.x, ending_fly_to.y) * (1.0 - settle)  # 飞的时候头朝飞的方向，停住后站正
	_rocket.transform = Transform3D(_basis * Basis(Vector3.BACK, tilt), from.lerp(target, k) + _basis.y * bob)
	_rocket.scale = Vector3.ONE * lerpf(0.25, 1.0, smoothstep(0.4, 0.55, p))
	_rocket_cat.rotation.y = deg_to_rad(25.0)
	# 火焰：忽大忽小地抖，停住后熄掉
	var burn := 1.0 - settle
	_flame.visible = burn > 0.02
	_flame.scale = Vector3(1.0, 0.85 + 0.25 * sin(ms * 31.0), 1.0) * burn * (0.9 + 0.15 * sin(ms * 47.0))
	# 披萨：猫停住时从脚下弹出来
	var pop := smoothstep(0.78, 0.9, p)
	_pizza.visible = pop > 0.0
	_pizza.scale = Vector3.ONE * (pop + sin(pop * PI) * 0.25)
	(_pizza.get_child(0) as Node3D).rotation.y = ms * 0.8  # 披萨绕自己的轴慢慢转
