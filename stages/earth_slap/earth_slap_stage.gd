class_name EarthSlapStage
extends Node
## 拍地球小关的 3D 舞台。美术整套引用 moumou 的拍地球猫模型（assets/models/cat_earth_y2k/cat_earth_model.tscn：
## 猫、地球、星系背景、蓝紫星星和那段 4 秒挥爪动画，不改他的文件），镜头和灯光照他的 cat_earth.tscn 摆。
## 动画不按时间播，按拍子定位：每 beats_per_swat 拍挥一次爪，爪子碰到地球那一帧正好落在该按的那一拍上。
## 后面的阶段场景里会出现几张猫 meme 纸片（2D 图立在 3D 里），每拍中一次所有纸片做一次 3D 翻转。
## 关卡脚本 EarthSlapSection 每帧调 update()，判定时调 slap() / miss()，需要时调 show_memes()。参数都在 Stage 节点的 Inspector 里。

const MODEL := preload("res://assets/models/cat_earth_y2k/cat_earth_model.tscn")

@export_group("镜头和灯光（照 cat_earth.tscn）")
@export var camera_position := Vector3(7.4, 6.0, 11.5)
@export var camera_target := Vector3(0.36, 1.95, -0.22)
## 正交镜头上下能看到多高（米）
@export var camera_size := 7.5
## 拍中时镜头抖多少（米），蓄力拍会按力度放大
@export var hit_shake := 0.06

@export_group("动画")
@export var animation_clip: StringName = &"CatEarthLoop"
## 原动画一轮 4 秒里挥两次爪，一次 2 秒；这是第一次碰到地球的时刻（秒）
@export var contact_seconds := 29.0 / 24.0
@export var swat_seconds := 2.0
## 判定圈画在哪（模型自己的坐标，moumou 场景里的 Focus 标记）
@export var focus := Vector3(1.11, 1.21, 0.56)

@export_group("拍中反馈")
## 拍中时整套模型弹大多少（蓄力拍按力度放大）
@export var hit_pulse := 0.04

@export_group("猫 meme 纸片")
## 素材名字（写法见 MemeLib）
@export var memes := PackedStringArray(["banana", "oiia", "popcat", "nyan", "apple", "flower"])
## 每张纸片在画面上的位置（镜头坐标：x 往右、y 往上，米；画面高 7.5 米、4:3 时宽 10 米），和 memes 一一对应
@export var meme_positions := PackedVector2Array([
	Vector2(-3.9, 2.4), Vector2(-4.0, -0.9), Vector2(3.9, 2.5),
	Vector2(4.0, -0.6), Vector2(-1.9, 3.0), Vector2(3.1, -2.5),
])
## 纸片高度（米）
@export var meme_height := 1.3
## 轻拍一次翻多少度；蓄力拍按力度最多再多翻几个半圈
@export var meme_flip_degrees := 180.0
@export var meme_extra_half_turns := 3
@export var meme_flip_time := 0.35

var world: SubViewport
var camera: Camera3D

var _sprite: Sprite2D
var _model: Node3D
var _animation: AnimationPlayer
var _clip: StringName
var _shake := 0.0
var _pulse := 0.0
var _cards: Array[Dictionary] = []  # {"node", "info", "from", "to", "t", "grow"}
var _memes_on := false


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


# ---------------- 给关卡脚本的 ----------------

## 拍中一次。power 0 = 轻拍，1 = 蓄满力的重拍
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


## 猫 meme 纸片出场（已经出场了再调没反应）
func show_memes() -> void:
	if _memes_on:
		return
	_memes_on = true
	var basis := camera.global_transform.basis
	for i in mini(memes.size(), meme_positions.size()):
		var info := MemeLib.find(memes[i])
		if info.is_empty():
			continue
		# 外面一层朝着镜头站好，里面的纸片绕自己的竖轴翻
		var holder := Node3D.new()
		holder.transform = Transform3D(basis, camera_position + basis * Vector3(meme_positions[i].x, meme_positions[i].y, -8.0 - i * 0.2))
		world.add_child(holder)
		var node := Sprite3D.new()
		node.texture = load(info.path)
		node.hframes = info.cols
		node.vframes = info.rows
		node.pixel_size = meme_height / (node.texture.get_height() / float(info.rows))
		node.shaded = false
		node.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		node.scale = Vector3.ONE * 0.01
		holder.add_child(node)
		_cards.append({"node": node, "info": info, "from": 0.0, "to": 0.0, "t": 1.0, "grow": -i * 0.12})


## 判定圈中心在 2D 画面上的位置（相对屏幕中心）
func focus_screen_pos() -> Vector2:
	return camera.unproject_position(_model.to_global(focus)) - Vector2(world.size) / 2.0


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
	camera.position = camera_position + camera.global_transform.basis * Vector3(sin(ms * 90.0), cos(ms * 110.0), 0.0) * hit_shake * _shake
	# 纸片：出场长大、翻转、播动图
	for c in _cards:
		var node: Sprite3D = c.node
		c.grow += dt * 3.0
		var g := clampf(c.grow, 0.0, 1.0)
		node.scale = Vector3.ONE * maxf(g * (2.0 - g), 0.01)
		c.t = minf(c.t + dt / maxf(meme_flip_time, 0.01), 1.0)
		var e := 1.0 - pow(1.0 - c.t, 3.0)
		node.rotation.y = lerpf(c.from, c.to, e)
		var info: Dictionary = c.info
		if int(info.frames) > 1:
			node.frame = int(ms * float(info.fps)) % int(info.frames)
