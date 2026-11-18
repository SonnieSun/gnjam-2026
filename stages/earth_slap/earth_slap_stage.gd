class_name EarthSlapStage
extends Node
## 拍地球小关的 3D 舞台。美术整套引用 moumou 的拍地球猫模型（assets/models/cat_earth_y2k/cat_earth_model.tscn：
## 猫、地球、星系背景、蓝紫星星和那段 4 秒挥爪动画，不改他的文件），镜头和灯光照他的 cat_earth.tscn 摆。
## 动画不按时间播，按拍子定位：每 beats_per_swat 拍挥一次爪，爪子碰到地球那一帧正好落在该按的那一拍上。
## 后面的阶段场景里会出现几张猫 meme 纸片（2D 图立在 3D 里），每拍中一次所有纸片做一次 3D 翻转。
## 关卡脚本 EarthSlapSection 每帧调 update()，判定时调 slap() / miss()，需要时调 show_memes()。参数都在 Stage 节点的 Inspector 里。

const MODEL := preload("res://assets/models/cat_earth_y2k/cat_earth_model.tscn")
## 结尾喷火飞出用：猫贴图（512）、火焰图（256×171）、第 3 关的披萨（贴图 512）
const CAT_TEXTURE := preload("res://stages/shared/cat/cat_basecolor_512.png")
const FLAME := preload("res://stages/earth_slap/fx/cat_rocket_flame.png")
const PIZZA := preload("res://stages/space_shooter/model/neapolitan_pizza.glb")
## 结尾撞飞的 UFO（第 1 关的飞碟）、左下角的外星人记者（洗衣机关那只，ProjectSpin 来的）
const UFO := preload("res://stages/abduction/ufo.tscn")
const ALIEN := preload("res://stages/tv_wall/washer/alien/green_alien.fbx")
## 飞出用的东西开场藏起来画几帧预热着色器
const WARMUP_FRAMES := 4

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
## 蓄力连按的段落（update 的 gated = true）：猫的挥爪不跟拍子走，跟玩家走——平时爪子抬在碰到地球前这么多秒
## （动画自己的时间）的姿势等着，玩家真的拍出去（slap()）才挥下去，挥完抬起另一只爪接着等。不拍就一直抬着。
## 原动画碰到前 14~4 帧爪子都是抬稳的，0.25 秒 = 前 6 帧
@export var charge_hold_seconds := 0.25
## 拍出去之后收爪、再抬起来放多快（1 = 和按拍子挥时一样快；大一点，下一串连按开始前就抬好了）
@export var charge_recover_speed := 1.3
## 蓄力时猫自己抖多少（米）：蓄得越多越久抖得越厉害（蓄满 = 这么多，多按到头是它的 2 倍多），看着像在使劲
@export var charge_cat_shake := 0.03
## 蓄力时猫身子跟着歪多少度（同样按蓄力放大）
@export var charge_cat_tilt := 2.0
## 判定圈画在哪（模型自己的坐标，moumou 场景里的 Focus 标记）。下面 ring_on_earth 关掉时才用这个
@export var focus := Vector3(1.11, 1.21, 0.56)
## 判定圈套在地球上（圆心 = 地球球心）；earth_offset 是在球心基础上再挪多少（模型自己的坐标，米）
@export var ring_on_earth := true
@export var earth_offset := Vector3.ZERO

@export_group("省性能")
## 地球换成 Godot 内置球的横向段数（竖向取一半）；原模型 96×48 段约 9000 三角。0 = 用原模型
@export var earth_segments := 32

@export_group("拍中反馈")
## 拍中时整套模型弹大多少（蓄力拍按力度放大）
@export var hit_pulse := 0.04
## 蓄力不够的那一下：镜头抖和模型弹只有平时的多少（软绵绵的一下）
@export_range(0.0, 1.0) var weak_slap := 0.3

@export_group("连按蓄力时越来越紧")
## 蓄满时镜头推近多少（0.08 = 画面放大 8%）
@export var charge_zoom := 0.08
## 蓄满时镜头一直抖多少（米）
@export var charge_shake := 0.025

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

@export_group("结尾：猫喷火飞出地球")
## 飞出来的猫多高（米）、火焰多长（米）、脚下披萨多大（米）
@export var rocket_cat_height := 1.5
@export var flame_length := 2.6
@export var pizza_diameter := 2.4
## 整段结尾一共几拍（= 关卡的过渡空位 ENDING_SLOT_BARS 小节；音乐 out_earth_to_space 按同样的 4 个小节写）。一小节一个镜头：
##   0~4   重击、停转：拍下去那一瞬间镜头就往地球上推（ease out：一下子推过去 = 冲击，再慢慢贴近），画面一震、一甩，
##         拍地球的猫被打飞出画面；之后是休止，地球带着惯性越转越慢，第 4 拍停住、镜头也贴到最近（地球撑满画面）
##   4~8   升空（整整一小节）：第 4 拍地球停住，猫在地球正面以几乎看不见的一个点出现，十字星一闪、转一圈、叮一声（冲出大气层）；
##         猫斜着往右上升、朝镜头冲过来（正交镜头没有近大远小，用变大当深度），速度按指数越来越快；镜头中心追着猫、
##         跟着拉远（比猫慢一点，猫在画面里越来越大），地球往左下让开；第 8 拍地球还大大的、被挤在画面左下角边上 = 刚升空
##   8~12  进轨道：猫歪向右上飞出去一小段，镜头错开地球中心跟着猫、稍微拉远，地球退到画面左下（还在画面里）；
##         飞得最快的那一拍脑袋撞上一只飘过来的 UFO（rocket_ufo_hit 拍），UFO 转着圈飞出画面，猫被撞得慢下来；
##         停在地球右上方的近地轨道上站正，脚下弹出披萨（这一刻地球还在画面里）
##   12~16 冲出：蹲一下（预备），火再喷起来，猫加速冲向右上、越来越小，镜头拉远追，追不上，猫出画面 = 切下一关
@export var rocket_beats := 16.0
## 拍下去之后镜头推到多近（第 4 拍推到；正交镜头的 size，越小越近；2.2 = 地球撑满画面）
@export var rocket_close_size := 2.2
## 升空这一小节猫往哪升（镜头坐标：相对地球正面，x 往右、y 往上，米）：斜一点 = 和镜头有个角度
@export var rocket_rise_to := Vector2(0.45, 1.5)
## 升空的指数有多陡：猫的位置按 (e^(rate·拍) - 1) 走（越大开头越慢、最后越猛）；镜头拉远用 pull_rate（更陡：前面镜头几乎不动、猫在画面里长大，最后一拍镜头猛拉远、猫在画面里的大小保持住 = 速度感）
@export var rocket_rise_rate := 0.9
@export var rocket_pull_rate := 1.4
## 猫刚出现时是全身的几分之一（之后按指数长到全身）
@export var rocket_rise_from_size := 0.04
## 镜头跟猫时落后几拍（看的是猫这么多拍之前的位置）
@export var rocket_cam_lag := 0.2
## 升空这一小节最后（第 8 拍）镜头拉到多远、中心在猫的哪边（镜头坐标，米）：不拉回正常远近，地球还大大的占着画面下半，
## 猫刚刚离开地球的轮廓（还有一点在轮廓里）
@export var rocket_lift_size := 3.8
@export var rocket_lift_offset := Vector2(0.35, -0.45)
## 冲出大气层的十字星：多大（米）、闪几拍（这几拍里转一圈）、叮一声的音效（assets/audio/sfx 里的名字，"" = 不放）
@export var rocket_star_size := 1.4
@export var rocket_star_beats := 0.75
@export var rocket_star_sfx := "star_ding"
## 飞走时 / 最后冲出时镜头的远近
@export var rocket_leave_size := 4.2
@export var rocket_final_size := 8.4
## 拍下去之后地球惯性转多少度（第 4 拍转停）
@export var rocket_spin_degrees := 540.0
## 猫飞到哪停一下（镜头坐标：相对地球，x 往右、y 往上，米），最后往同一个方向冲出画面
@export var rocket_stop := Vector2(1.9, 2.2)
## 进轨道时镜头中心在猫的哪边（镜头坐标，米）：地球留在画面左下角；之后冲出那一小节地球才出画面
@export var rocket_leave_offset := Vector2(0.15, -0.7)
## 飞出去最快的那一拍撞飞一只 UFO（之后猫才减速停下）：第几拍撞上（半拍也行，BONK 是单独的音效）、UFO 多宽（米）、撞上前它从右边飘进猫的路线用几拍
@export var rocket_ufo_hit := 8.0
@export var rocket_ufo_size := 1.3
@export var rocket_ufo_drift_beats := 1.5
## 撞上那一下的音效（assets/audio/sfx 里的名字，"" = 不放）
@export var rocket_ufo_sfx := "ufo_bonk"
## 撞上 UFO 时和 bonk 一起响的一小下爆炸/破坏（留空就只有 bonk）
@export var rocket_break_sfx := "ufo_break"

@export_group("外星人记者")
## 拍地球第二段第一下拍出去，画面左下角冒出一个拿话筒的外星人（新闻台的现场记者），跟着拍子蹦、摇头，
## 每拍中一下吓一跳（蓄满的重拍大惊），漏了一下歪头；进 fever 时缩下去消失
@export var reporter_enabled := true
@export var reporter_height := 2.6
## 离画面左边、下边多远（米，按正常远近的画面算；下边是负的 = 脚在画面外，腿被新闻条挡住）
@export var reporter_margin := Vector2(1.7, -0.1)
## 身子朝右（朝地球）转多少度
@export var reporter_turn := 22.0
## 话筒网罩在哪（按身高的比例：x 往右，y 往上；嘴前面大概在 0.5）
@export var reporter_mic_at := Vector2(0.05, 0.5)

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
var _earth: Node3D
var _earth_rest := Vector3.ZERO   # 地球球心（模型自己的坐标）：记爪子碰到地球那一刻的，圈不跟着动画晃
var _earth_radius := 1.0          # 地球半径（米）
var _charge := 0.0                # 关卡告诉的蓄力比例（0~1），平滑追过去
var _charge_goal := 0.0
var _rocket: Node3D       # 飞出来的猫（外层：位置和歪斜）
var _rocket_cat: Node3D
var _flame: Sprite3D
var _pizza: Node3D
var _star: Sprite3D       # 冲出大气层的十字星
var _dinged := false
var _bonked := false
var _ufo: Node3D          # 停下来之前撞飞的 UFO
var _reporter: Node3D     # 左下角的外星人记者（外层：位置和歪斜）
var _rep_body: Node3D     # 里层：摇头
var _rep_label: Label3D   # 头上的 ! / ?
var _rep_state := 0       # 0 没出来，1 在，2 正在缩回去，3 走了
var _rep_t := 0.0
var _rep_shock := 0.0     # 吓一跳（1 = 刚吓到，慢慢落回 0）
var _rep_power := 0.0
var _rep_label_t := 99.0
var _rocket_p := -1.0     # 飞出放到百分之几（< 0 = 还没开始）
var _anim_t := 0.0        # 挥爪动画放到几秒：结尾开始后停在拍下去的那一帧
var _cat_t := -1.0        # 蓄力段里猫的动画放到几秒（< 0 = 还没进蓄力段）
var _cat_stop := 0.0      # 放到这里停住（下一只爪抬好的姿势）
var _slaps := 0           # 蓄力段里拍出去了几下：两只爪轮着来
var _gated := false
var _rig: Node3D          # 猫（CatRig）：蓄力时抖它
var _rig_home := Transform3D.IDENTITY
var _cat_tracks: Array[Dictionary] = []  # 动画里猫骨头的轨道 {"track", "type", "bone"}：蓄力停住时只改猫，地球和星星照转
var _skeleton: Skeleton3D
var _rig_rest := Transform3D.IDENTITY  # 拍地球的猫原来在哪（结尾被拍飞出画面）
var _cam_basis := Basis.IDENTITY        # 结尾开始时镜头的朝向（之后的侧倾都是在它上面转）


func setup(host: Node2D) -> void:
	world = SubViewport.new()
	world.size = Vector2i(host.get_viewport_rect().size)
	world.own_world_3d = true  # 要在带蒙皮的模型进场景树之前设好
	world.msaa_3d = Viewport.MSAA_2X
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
	# 跟拍：模型里的星星一颗接一颗闪着胀过去，小光点跟军鼓（猫和地球是主体，不动）
	var stars: Array = []
	for n in _model.get_children():
		if String(n.name).begins_with("Star"):
			stars.append(n)
		elif String(n.name).begins_with("Glint"):
			BeatDecor.stagger(n, 5 if String(n.name).ends_with("1") else 9, 0.25)  # 一个在小节最后一拍闪，一个在小节头
	BeatDecor.wave(stars, 0.3, 4.0)
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
			_animation.seek(contact_seconds, true)
			_collect_cat_tracks()
	_rig = _model.get_node_or_null("CatRig") as Node3D
	if _rig:
		_rig_home = _rig.transform
	_earth = _model.find_child("EarthSpin", true, false) as Node3D
	if _earth:
		_earth_rest = _model.to_local(_earth.global_position)
		var mesh := _earth.find_child("EarthMesh", true, false) as MeshInstance3D
		if mesh and mesh.mesh:
			var size := mesh.mesh.get_aabb().size * mesh.global_transform.basis.get_scale()
			_earth_radius = maxf(size.x, maxf(size.y, size.z)) / 2.0
			_use_low_poly_earth(mesh)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_size
	camera.far = 80.0
	camera.position = camera_position
	world.add_child(camera)
	camera.look_at(camera_target)
	camera.current = true
	_build_rocket()
	_build_reporter()


# ---------------- 给关卡脚本的 ----------------

## 拍中一次。power 0 = 轻拍，1 = 蓄满力的重拍。weak = 蓄力不够：软绵绵的一下
## 原地球是 UV 经纬度展开的球（球心在原点、两极沿 Z 轴），和 SphereMesh 的 UV 一样，
## 只差一个 90° 旋转：同一个 UV 点，SphereMesh 上的方向 = EARTH_TO_SPHERE × 原方向。节点反着转回去，贴图位置不变。
const EARTH_TO_SPHERE := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))


func _use_low_poly_earth(mesh: MeshInstance3D) -> void:
	if earth_segments <= 0:
		return
	var sphere := SphereMesh.new()
	var r := mesh.mesh.get_aabb().size.x / 2.0
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = earth_segments
	sphere.rings = maxi(earth_segments / 2, 4)
	sphere.material = mesh.mesh.surface_get_material(0)
	mesh.mesh = sphere  # material_override 留着不动
	mesh.transform = mesh.transform * Transform3D(EARTH_TO_SPHERE.inverse(), Vector3.ZERO)


func slap(power: float, weak := false) -> void:
	if _gated:
		# 蓄力段：这一下真的拍出去了——从碰到地球前一帧放起，挥完接着抬另一只爪
		var contact := contact_seconds + (_slaps % 2) * swat_seconds
		_slaps += 1
		_cat_t = contact - 1.0 / 24.0
		_cat_stop = contact + swat_seconds - charge_hold_seconds
	_reporter_shock(0.0 if weak else power, "?" if weak else ("!!!" if power >= 0.99 else "!"))
	_shake = (1.0 + power * 2.0) * (weak_slap if weak else 1.0)
	_pulse = (1.0 + power * 2.0) * (weak_slap if weak else 1.0)
	var turn := deg_to_rad(meme_flip_degrees) * (1 + roundi(power * meme_extra_half_turns))
	for c in _cards:
		c.from = c.to
		c.to = c.from + turn
		c.t = 0.0


func miss() -> void:
	_shake = 0.5
	_reporter_shock(0.0, "?!")


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
		# 跟拍：每张纸片用不同的节奏胀（接在外面这层上，里面那层自己在做翻转和长大）
		BeatDecor.stagger(holder, i * 3 + 1, 0.11)


## 连按蓄力蓄到多少了（1 = 达标；超过了还在按可以到 1.5）：镜头慢慢推近、越抖越厉害
func set_charge(ratio: float) -> void:
	_charge_goal = clampf(ratio, 0.0, 1.5)


## 结尾的喷火飞出：从最后那一下重拍开始放（之后每帧用 set_rocket() 告诉它放到百分之几）
func start_rocket() -> void:
	if _rocket_p < 0.0:
		_rocket_p = 0.0
		var rig := _model.get_node_or_null("CatRig") as Node3D
		if rig:
			rig.transform = _rig_home  # 蓄力的抖动先归位
			_rig_rest = rig.global_transform
		_cam_basis = camera.global_transform.basis


func set_rocket(p: float) -> void:
	if _rocket_p >= 0.0:
		_rocket_p = clampf(p, 0.0, 1.3)  # 放满后（切关、黑幕落下的那 0.6 秒）还接着冲


func rocket_active() -> bool:
	return _rocket_p >= 0.0


## 飞出用的猫、火焰、披萨开场就做好：先缩得很小藏在地球里面画几帧（网页版第一次画新材质要编着色器，
## 不在这里编的话会卡在飞出的那一下），之后藏起来，到结尾再拿出来。材质都是共用的一份，只多 3 种。
func _build_rocket() -> void:
	_rocket = Node3D.new()
	world.add_child(_rocket)
	_rocket_cat = TvWallRoom.make_cat()
	_rocket.add_child(_rocket_cat)
	var box := TvWallRoom.measure(_rocket_cat)
	_rocket_cat.scale = Vector3.ONE * rocket_cat_height / maxf(box.size.y, 0.0001)
	_rocket_cat.position = -(_rocket_cat.transform.basis * box.get_center())
	_rocket_cat.rotation.y = deg_to_rad(25.0)
	var cat_mat := StandardMaterial3D.new()
	cat_mat.albedo_texture = CAT_TEXTURE
	cat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi in _rocket_cat.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = cat_mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 火焰：图里喷口在左边、尾巴往右；转成尾巴朝下，贴在猫屁股往下喷
	_flame = Sprite3D.new()
	_flame.texture = FLAME
	_flame.pixel_size = flame_length / FLAME.get_width()
	_flame.centered = false
	_flame.offset = Vector2(-FLAME.get_width() * 0.1, -FLAME.get_height() * 0.5)  # 原点放在喷口
	_flame.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	_flame.position = Vector3(0.0, -rocket_cat_height * 0.4, -0.3)
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = FLAME
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame.material_override = fm
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rocket.add_child(_flame)
	# 披萨（第 3 关披萨猫踩的那块）：从猫脚下冒出来，稍微朝镜头翻一点好看见饼面
	_pizza = Node3D.new()
	_rocket.add_child(_pizza)
	var pie := PIZZA.instantiate() as Node3D
	_pizza.add_child(pie)
	var pbox := TvWallRoom.measure(pie)
	pie.scale = Vector3.ONE * pizza_diameter / maxf(maxf(pbox.size.x, pbox.size.z), 0.0001)
	pie.position = -(pie.transform.basis * pbox.get_center())
	for mi in pie.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pizza.position = Vector3(0.0, -rocket_cat_height * 0.55, 0.0)
	_pizza.rotation_degrees = Vector3(35.0, 0.0, 0.0)
	# 冲出大气层的十字星（贴图现画：四道长光 + 四道短的斜光 + 中间一团亮），叠加混合、永远画在最上面
	_star = Sprite3D.new()
	_star.texture = _star_texture(256)
	_star.pixel_size = 1.0 / 256.0
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = _star.texture
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.no_depth_test = true
	sm.render_priority = 10
	_star.material_override = sm
	_star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_star.scale = Vector3.ONE * 0.05  # 预热时跟着猫画几帧（很小，看不见），之后藏起来
	world.add_child(_star)
	# 预热：藏在地球球心里（在镜头里、但被地球挡住），画几帧
	_rocket.scale = Vector3.ONE * 0.05
	_rocket.position = _model.to_global(_earth_rest) if _earth else _model.global_position
	_star.position = _rocket.position
	# UFO：第 1 关的飞碟缩到 rocket_ufo_size 宽，预热时也跟着画几帧
	_ufo = Node3D.new()
	world.add_child(_ufo)
	var saucer := UFO.instantiate() as Node3D
	_ufo.add_child(saucer)
	var ubox := TvWallRoom.measure(saucer)
	saucer.scale = Vector3.ONE * rocket_ufo_size / maxf(maxf(ubox.size.x, ubox.size.z), 0.0001)
	saucer.position = -(saucer.transform.basis * ubox.get_center())
	for mi in saucer.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ufo.position = _rocket.position
	_ufo.scale = Vector3.ONE * 0.05
	_hide_rocket_after_warmup()


## 动画里那种十字星：横竖两道细长的光，斜着两道短的，中心一团亮，微微偏暖
static func _star_texture(n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dx := (x + 0.5) / n * 2.0 - 1.0
			var dy := (y + 0.5) / n * 2.0 - 1.0
			var r2 := dx * dx + dy * dy
			var a := exp(-absf(dy) * 60.0) * pow(maxf(1.0 - absf(dx), 0.0), 2.0) 					+ exp(-absf(dx) * 60.0) * pow(maxf(1.0 - absf(dy), 0.0), 2.0)
			var u := (dx + dy) * 0.7071
			var v := (dx - dy) * 0.7071
			a += 0.45 * (exp(-absf(v) * 70.0) * pow(maxf(1.0 - absf(u) * 2.2, 0.0), 2.0)
					+ exp(-absf(u) * 70.0) * pow(maxf(1.0 - absf(v) * 2.2, 0.0), 2.0))
			a += exp(-r2 * 40.0) * 0.9 + exp(-r2 * 6.0) * 0.25
			a = clampf(a, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.96, 0.82, a).lerp(Color(1, 1, 1, a), clampf(1.0 - r2 * 8.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _hide_rocket_after_warmup() -> void:
	for i in WARMUP_FRAMES:
		await RenderingServer.frame_post_draw
	if is_instance_valid(_rocket) and _rocket_p < 0.0:
		_rocket.visible = false
		_star.visible = false
		_ufo.visible = false


## 外星人记者：外星人（脚在原点）+ 手里一支话筒 + 头上一个 ! / ?（永远画在最上面）
func _build_reporter() -> void:
	if not reporter_enabled:
		return
	_reporter = Node3D.new()
	world.add_child(_reporter)
	_rep_body = Node3D.new()
	_reporter.add_child(_rep_body)
	var model := ALIEN.instantiate() as Node3D
	model.rotation_degrees = Vector3(0.0, -90.0, 0.0)  # 模型脸朝 +X，转成朝镜头
	var holder := Node3D.new()
	holder.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var src := mesh.get_active_material(0) as StandardMaterial3D
		if src:
			var mat := src.duplicate() as StandardMaterial3D
			mat.roughness = 0.7
			mesh.material_override = mat
	var box := TvWallRoom.measure(holder)
	var k := reporter_height / maxf(box.size.y, 0.00001)
	holder.scale = Vector3.ONE * k
	var c := box.get_center()
	holder.position = -Vector3(c.x, box.position.y, c.z) * k
	_rep_body.add_child(holder)
	# 话筒：一根黑杆 + 一个灰色的网罩，斜着举在嘴边
	var mic := Node3D.new()
	var stick := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.03
	cyl.height = 0.4
	stick.mesh = cyl
	var stick_mat := StandardMaterial3D.new()
	stick_mat.albedo_color = Color(0.08, 0.08, 0.1)
	stick_mat.roughness = 0.4
	stick.material_override = stick_mat
	mic.add_child(stick)
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.09
	sph.height = 0.18
	ball.mesh = sph
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.55, 0.57, 0.6)
	ball_mat.metallic = 0.6
	ball_mat.roughness = 0.35
	ball.material_override = ball_mat
	ball.position.y = 0.24
	mic.add_child(ball)
	# 话筒头放在下巴前面（这只外星人头大，嘴在头的下沿，大概身高的 0.44）：先定好网罩要在哪，再倒推杆子的位置
	mic.rotation_degrees = Vector3(0.0, 0.0, 28.0)
	mic.scale = Vector3.ONE * reporter_height / 1.8
	var ball_at := Vector3(reporter_height * reporter_mic_at.x, reporter_height * reporter_mic_at.y, reporter_height * 0.2)
	mic.position = ball_at - mic.transform.basis * Vector3(0.0, 0.24, 0.0)
	_rep_body.add_child(mic)
	_rep_label = Label3D.new()
	_rep_label.text = "!"
	_rep_label.font_size = 140
	_rep_label.outline_size = 36
	_rep_label.pixel_size = 0.005
	_rep_label.modulate = Color(1.0, 0.86, 0.2)
	_rep_label.outline_modulate = Color(0.08, 0.02, 0.15)
	_rep_label.no_depth_test = true
	_rep_label.render_priority = 5
	_rep_label.position = Vector3(reporter_height * 0.25, reporter_height * 1.08, 0.0)
	_rep_label.visible = false
	_rep_body.add_child(_rep_label)
	_reporter.visible = false


## 外星人记者出来（已经出来过就没反应）
func reporter_in() -> void:
	if _reporter and _rep_state == 0:
		_rep_state = 1
		_rep_t = 0.0
		_reporter.visible = true


## 外星人记者缩回去（进 fever、结尾开始时）
func reporter_out() -> void:
	if _reporter and _rep_state == 1:
		_rep_state = 2
		_rep_t = 0.0


## 吓一跳：power 0~1（蓄满的重拍大惊），text = 头上冒的字
func _reporter_shock(power: float, text: String) -> void:
	if _rep_state != 1:
		return
	_rep_shock = 1.0
	_rep_power = power
	_rep_label.text = text
	_rep_label_t = 0.0


## 每帧：钉在画面左下角（跟着镜头的远近和抖动走，在画面上的大小不变），冒出 / 缩回，跟拍蹦、摇头，吓一跳
func _update_reporter(dt: float, beat: float) -> void:
	if _reporter == null or not _reporter.visible:
		return
	if _rocket_p >= 0.0:
		reporter_out()
	_rep_t += dt
	var rise := 1.0
	if _rep_state == 1:
		var e := clampf(_rep_t / 0.45, 0.0, 1.0)
		rise = 1.0 + 2.70158 * pow(e - 1.0, 3.0) + 1.70158 * pow(e - 1.0, 2.0)   # 冒出来：弹一下
	elif _rep_state == 2:
		var e := clampf(_rep_t / 0.4, 0.0, 1.0)
		rise = 1.0 + 0.25 * sin(minf(e / 0.35, 1.0) * PI) - smoothstep(0.3, 1.0, e)   # 先往上一缩脖子，再沉下去
		if e >= 1.0:
			_rep_state = 3
			_reporter.visible = false
			return
	var cam_b := camera.global_transform.basis
	var zoom := camera.size / camera_size
	var half_h := camera.size / 2.0
	var aspect := float(world.size.x) / maxf(float(world.size.y), 1.0)
	_rep_shock = maxf(_rep_shock - dt * 2.5, 0.0)
	var shock := _rep_shock * _rep_shock * (1.0 + 1.5 * _rep_power)
	# 跟拍：每拍一下子换边（十分之一拍就到位，然后停住）= 一顿一顿的，不是平滑地摇
	var frac := fposmod(beat, 1.0)
	var side := 1.0 if posmod(floori(beat), 2) == 0 else -1.0
	var snap := side * (2.0 * (1.0 - exp(-frac * 20.0)) - 1.0)          # 从上一边猛地甩到这一边
	var hop := exp(-frac * 14.0) * 0.05                                 # 每拍很短地一顿
	var dy := (rise - 1.0) * reporter_height * 1.3 + hop + 0.12 * shock
	var at := Vector3(-half_h * aspect + reporter_margin.x * zoom, -half_h + (reporter_margin.y + dy) * zoom, -6.0)
	var sway := deg_to_rad(2.5) * snap
	var lean := deg_to_rad(9.0) * shock                                    # 吓得往后（往左）一仰
	_reporter.global_transform = Transform3D(cam_b * Basis(Vector3.BACK, sway + lean) * Basis(Vector3.UP, deg_to_rad(reporter_turn)),
			camera.position + cam_b * at)
	_reporter.scale = Vector3.ONE * zoom * (1.0 + 0.07 * shock)
	_rep_body.rotation.y = deg_to_rad(5.0) * -snap + deg_to_rad(5.0) * shock * sin(_rep_t * 40.0)   # 一小节摇一次头，吓到时抖
	_rep_label_t += dt
	_rep_label.visible = _rep_label_t < 0.7
	if _rep_label.visible:
		var pop := clampf(_rep_label_t / 0.12, 0.0, 1.0)
		_rep_label.scale = Vector3.ONE * (pop * (1.0 + 0.4 * (1.0 - pop)) * (1.0 + 0.5 * _rep_power)) * (1.0 - smoothstep(0.5, 0.7, _rep_label_t))


## 判定圈中心在 2D 画面上的位置（相对屏幕中心）
func focus_screen_pos() -> Vector2:
	var at := _earth_rest + earth_offset if ring_on_earth and _earth else focus
	# 用摆好的镜头位置算，不跟着镜头抖
	var rel := _model.to_global(at) - camera_position
	var b := camera.global_transform.basis
	return Vector2(rel.dot(b.x), -rel.dot(b.y)) * (world.size.y / camera_size)


## 地球在画面上的半径（像素）
func earth_screen_radius() -> float:
	return _earth_radius * world.size.y / camera_size


# ---------------- 每帧 ----------------

## beat = 这个小关里的拍数；每 beats_per_swat 拍挥一次爪，碰到地球落在每轮的第 strike_beat 拍
## gated = 蓄力连按的段落：猫抬着爪子等，玩家拍出去才挥（见 charge_hold_seconds）
func update(dt: float, beat: float, beats_per_swat: float, strike_beat: float, gated := false) -> void:
	var size := Vector2i(world.get_parent().get_viewport_rect().size)
	if world.size != size:
		world.size = size
	if _animation and _clip != &"":
		var length := _animation.get_animation(_clip).length
		if _rocket_p < 0.0:  # 结尾：停在拍下去的那一帧（地球的转由 _update_rocket 接着转）
			_anim_t = fposmod((beat - strike_beat) / maxf(beats_per_swat, 0.25) * swat_seconds + contact_seconds, swat_seconds * 2.0)
		_animation.seek(minf(_anim_t, length), true)
		_gated = gated
		if gated:
			if _cat_t < 0.0:  # 刚进蓄力段：抬着爪子等
				_cat_t = contact_seconds - charge_hold_seconds
				_cat_stop = _cat_t
			var rate := swat_seconds / maxf(beats_per_swat * Conductor.sec_per_beat(), 0.1) * charge_recover_speed
			_cat_t = minf(_cat_t + dt * rate, _cat_stop)
			_pose_cat(fposmod(_cat_t, swat_seconds * 2.0))
	_shake = maxf(_shake - dt * 8.0, 0.0)
	_pulse = maxf(_pulse - dt * 7.0, 0.0)
	_model.scale = Vector3.ONE * (1.0 + hit_pulse * _pulse)
	var ms := Time.get_ticks_msec() * 0.001
	# 蓄力：推近得快、松掉得更快
	_charge = lerpf(_charge, _charge_goal, 1.0 - exp(-dt * (10.0 if _charge_goal > _charge else 18.0)))
	camera.size = camera_size * (1.0 - charge_zoom * _charge)
	camera.position = camera_position + camera.global_transform.basis * Vector3(sin(ms * 90.0), cos(ms * 110.0), 0.0) \
			* (hit_shake * _shake + charge_shake * _charge)
	if _rig and _rocket_p < 0.0:
		# 猫自己使劲：蓄得越多抖得越厉害（平方：前面几下只是微微颤，快蓄满才抖起来），身子跟着歪
		var effort := _charge * _charge
		var jitter := Vector3(sin(ms * 71.0) + sin(ms * 113.0), sin(ms * 89.0) + sin(ms * 131.0), sin(ms * 97.0)) * 0.5
		var lean := Basis(Vector3.FORWARD, deg_to_rad(charge_cat_tilt) * effort * sin(ms * 83.0))
		_rig.transform = _rig_home.translated(jitter * charge_cat_shake * effort) * Transform3D(lean, Vector3.ZERO)
	# 纸片：出场长大、翻转、播动图；喷火飞出时缩没
	var gone := smoothstep(0.0, 0.15, _rocket_p) if _rocket_p >= 0.0 else 0.0
	for c in _cards:
		var node: Sprite3D = c.node
		c.grow += dt * 3.0
		var g := clampf(c.grow, 0.0, 1.0)
		node.scale = Vector3.ONE * maxf(g * (2.0 - g) * (1.0 - gone), 0.01)
		c.t = minf(c.t + dt / maxf(meme_flip_time, 0.01), 1.0)
		var e := 1.0 - pow(1.0 - c.t, 3.0)
		node.rotation.y = lerpf(c.from, c.to, e)
		var info: Dictionary = c.info
		if int(info.frames) > 1:
			node.frame = int(ms * float(info.fps)) % int(info.frames)
	_update_reporter(dt, beat)
	if _rocket_p >= 0.0:
		_update_rocket(ms)


## 只把猫的骨头摆到动画第 t 秒的样子（地球、星星不动：它们刚按拍子 seek 过）
func _pose_cat(t: float) -> void:
	if _skeleton == null:
		return
	var anim := _animation.get_animation(_clip)
	for c in _cat_tracks:
		match int(c.type):
			Animation.TYPE_ROTATION_3D: _skeleton.set_bone_pose_rotation(c.bone, anim.rotation_track_interpolate(c.track, t))
			Animation.TYPE_POSITION_3D: _skeleton.set_bone_pose_position(c.bone, anim.position_track_interpolate(c.track, t))
			Animation.TYPE_SCALE_3D: _skeleton.set_bone_pose_scale(c.bone, anim.scale_track_interpolate(c.track, t))


func _collect_cat_tracks() -> void:
	_cat_tracks.clear()
	var anim := _animation.get_animation(_clip)
	var base := _animation.get_node_or_null(_animation.root_node)
	for i in anim.get_track_count():
		var path := anim.track_get_path(i)
		if path.get_subname_count() == 0 or base == null:
			continue
		var sk := base.get_node_or_null(NodePath(str(path.get_concatenated_names()))) as Skeleton3D
		if sk == null:
			continue
		var bone := sk.find_bone(path.get_concatenated_subnames())
		if bone >= 0:
			_skeleton = sk
			_cat_tracks.append({"track": i, "type": anim.track_get_type(i), "bone": bone})


## 结尾的 4 个镜头（t = 拍下去之后第几拍，0~rocket_beats；切关之后黑幕落下的那一会儿 t 接着往上走），见 rocket_beats 的说明。
## 每一段的起止都落在拍子上，和 out_earth_to_space 的小节一一对上。
## 镜头：平移 + 远近 + 一点侧倾（转弯时往里歪，dutch）+ 很轻的手持晃动；跟猫的时候落后它一点点（看的是猫 rocket_cam_lag 拍前的位置）。
## 猫：路径是一条按拍子算的曲线（_cat_path），身体顺着它真正的速度方向歪、速度快时顺着拉长，慢下来自己站正。
func _update_rocket(ms: float) -> void:
	var t := _rocket_p * rocket_beats
	var b := _cam_basis
	var forward := -b.z
	var earth := _model.to_global(_earth_rest) if _earth else _model.global_position
	var dir_n := Vector3(rocket_stop.x, rocket_stop.y, 0.0).normalized()

	# ---- 地球：拍下去带着惯性转，越转越慢，第 4 拍转停（停住时轻轻回弹一下）；拍下去那一下一震 ----
	if _earth:
		var eu := clampf(t / 4.0, 0.0, 1.0)
		var spin := rocket_spin_degrees * (1.0 - pow(1.0 - eu, 3.0))
		if t > 4.0:
			spin += 4.0 * sin((t - 4.0) * TAU * 1.5) * exp(-(t - 4.0) * 4.0)
		_earth.rotate_object_local(Vector3.BACK, deg_to_rad(spin))
	_model.scale = Vector3.ONE * (1.0 + 0.07 * exp(-t * 5.0) * absf(sin(ms * 40.0)))

	# ---- 拍地球的猫：被拍飞出画面左上（一下子弹出去，越飞越慢 = 被打飞），边飞边翻 ----
	var rig := _model.get_node_or_null("CatRig") as Node3D
	if rig:
		var kx := clampf(t / 1.25, 0.0, 1.0)
		var k := 1.0 - pow(1.0 - kx, 2.5)
		rig.visible = kx < 1.0
		var away := b * (Vector3(-1.0, 0.65, 0.0).normalized() * 10.0 * k)
		var roll := Basis(b.z, TAU * 0.9 * k)
		rig.global_transform = Transform3D(roll * _rig_rest.basis, roll * (_rig_rest.origin - earth) + earth + away)

	# ---- 飞出来的猫 ----
	_rocket.visible = t >= 4.0
	var ru := clampf(t - 4.0, 0.0, 4.0)                               # 升空这一小节里第几拍
	var size := rocket_rise_from_size * pow(1.0 / rocket_rise_from_size, ru / 4.0)   # 按指数长大（= 往镜头冲过来）
	size *= lerpf(1.0, 0.35, smoothstep(12.75, 16.0, t))              # 冲出：越来越小（往远处去）
	var path := _cat_path(t, earth, b)
	var vel := (_cat_path(t + 0.05, earth, b) - _cat_path(t - 0.05, earth, b)) / 0.1   # 米 / 拍
	var vx := vel.dot(b.x)
	var vy := vel.dot(b.y)
	var speed := Vector2(vx, vy).length()
	var settle := smoothstep(10.4, 11.3, t) * (1.0 - smoothstep(12.0, 12.4, t))   # 停住踩着披萨飘的那一段
	var crouch := sin(clampf((t - 12.0) / 0.75, 0.0, 1.0) * PI)       # 冲出前蹲一下往回缩
	var cat := path + b.y * (sin(ms * 2.2) * 0.12 * settle) - b * dir_n * 0.35 * crouch
	var bump := _kick(t, rocket_ufo_hit)                               # 撞上 UFO 的那一下
	# 身体：顺着速度方向歪（慢了自己站正），升空时轻轻左右摇，停住时站着晃
	var follow_w := smoothstep(0.15, 1.2, speed)
	var tilt := clampf(-atan2(vx, vy), -0.95, 0.95) * follow_w if speed > 0.001 else 0.0   # 最多歪 55°，不躺平
	tilt += deg_to_rad(4.0) * sin(ms * 5.3) * smoothstep(4.0, 4.5, t) * (1.0 - smoothstep(7.5, 8.0, t))
	tilt += deg_to_rad(6.0) * sin(ms * 2.2 + 0.8) * settle
	# 冲出前蹲下：身子先顺着要冲的方向歪过去（蓄力）
	tilt = lerpf(tilt, -atan2(dir_n.x, dir_n.y) * 0.6, crouch * 0.8)
	tilt += deg_to_rad(16.0) * bump                                     # 撞到 UFO：脑袋往后一仰
	_rocket.transform = Transform3D(b * Basis(Vector3.BACK, tilt), cat)
	# 拉伸：快的时候顺着身子（= 顺着速度）拉长、横着变窄；踩上披萨那一下压扁；蹲下时压扁
	var stretch := clampf(speed / maxf(size, 0.05) * 0.03, 0.0, 0.25)
	var land := sin(clampf((t - 10.85) / 0.6, 0.0, 1.0) * PI) * 0.14
	# 撞上 UFO：一下子压扁（脑袋顶到它），再弹回来、稍微拉长一下、再落稳（衰减的弹簧）
	var hu := t - rocket_ufo_hit
	var squash := 0.0
	if hu >= -0.03:
		squash = 0.32 * smoothstep(-0.03, 0.03, hu) * exp(-maxf(hu, 0.0) * 5.5) * cos(maxf(hu, 0.0) * TAU * 1.4)
	var sy := (1.0 + stretch) * (1.0 - land) * (1.0 - 0.15 * crouch) * (1.0 - squash)
	var sx := 1.0 / sqrt(maxf(sy, 0.3))
	_rocket.scale = Vector3(sx, sy, 1.0) * maxf(size, 0.005)
	# 火：升起来时一直喷，停住时收小，蹲完再喷得更猛
	var burn := (1.0 - smoothstep(10.4, 11.3, t)) * smoothstep(4.0, 4.4, t) + smoothstep(12.6, 12.9, t) * 1.3
	_flame.visible = burn > 0.02
	_flame.scale = Vector3(1.0, 0.85 + 0.25 * sin(ms * 31.0), 1.0) * burn * (0.9 + 0.15 * sin(ms * 47.0))
	# 披萨：停住时从脚下弹出来，之后一直踩着
	var pop := smoothstep(10.75, 11.5, t)
	_pizza.visible = pop > 0.0
	_pizza.scale = Vector3.ONE * maxf(pop + sin(pop * PI) * 0.3, 0.01)
	(_pizza.get_child(0) as Node3D).rotation.y = ms * 0.8

	# ---- 停下来之前撞飞一只 UFO：先从右边慢慢飘进猫要经过的地方（晃着），猫的脑袋撞上的那一拍被撞飞，
	# 转着圈往右上飞出画面 ----
	var hit_pos := _cat_path(rocket_ufo_hit, earth, b) + b * Vector3(0.6, 0.2, 0.0) - forward * 0.3   # 猫脑袋的右边
	var ut := t - rocket_ufo_hit
	_ufo.visible = ut > -rocket_ufo_drift_beats and ut < 3.0
	if _ufo.visible:
		var ub := b
		var upos := hit_pos
		if ut < 0.0:
			var a := 1.0 - clampf(-ut / rocket_ufo_drift_beats, 0.0, 1.0)
			upos += b * Vector3(2.6 * pow(1.0 - a, 2.0), 0.08 * sin(ms * 3.0), 0.0)
			ub = b * Basis(Vector3.BACK, deg_to_rad(8.0) * sin(ms * 2.6)) * Basis(Vector3.RIGHT, deg_to_rad(18.0)) * Basis(Vector3.UP, ms * 2.0)
		else:
			var go := Vector3(1.0, 0.35, 0.0).normalized()
			upos += b * go * (4.5 * (1.0 - exp(-ut * 1.4)) + 1.2 * ut)      # 撞飞：一下子弹开，转着圈大概一拍飞出画面
			ub = b * Basis(Vector3.BACK, -TAU * 2.0 * (1.0 - exp(-ut * 1.8))) * Basis(Vector3.RIGHT, deg_to_rad(18.0) + ut * 4.0) \
					* Basis(Vector3.UP, ms * 2.0 + ut * 18.0)
		_ufo.transform = Transform3D(ub, upos)
		_ufo.scale = Vector3.ONE * (1.0 - 0.3 * clampf(ut, 0.0, 1.0))
	if ut >= 0.0 and not _bonked:
		_bonked = true
		if rocket_ufo_sfx != "" and Conductor.playing:
			Music.play_sfx(rocket_ufo_sfx, -2.0)    # 转场音乐这时还在响（第 3 小节重拍正压在这一下上），太轻会被盖住
		if rocket_break_sfx != "" and Conductor.playing:
			Music.play_sfx(rocket_break_sfx, -4.0)

	# ---- 十字星：第 4 拍冲出大气层时在猫出现的地方一闪（转一圈、叮一声）；撞上 UFO 时在撞的地方再闪一下（小一点） ----
	var st := (t - 4.0) / maxf(rocket_star_beats, 0.01)
	var st2 := (t - rocket_ufo_hit) / 0.5
	_star.visible = (st > 0.0 and st < 1.0) or (st2 > 0.0 and st2 < 1.0)
	if st2 > 0.0 and st2 < 1.0:
		_star.transform = Transform3D(b * Basis(Vector3.BACK, -PI * st2), hit_pos - forward * 0.6 - b * Vector3(0.15, 0.2, 0.0))
		_star.scale = Vector3.ONE * rocket_star_size * 0.7 * pow(sin(PI * st2), 0.6)
	if st > 0.0 and st < 1.0:
		var flash := pow(sin(PI * st), 0.6)
		_star.transform = Transform3D(b * Basis(Vector3.BACK, -TAU * st), cat - forward * 0.6)
		_star.scale = Vector3.ONE * rocket_star_size * flash
		if not _dinged and rocket_star_sfx != "" and Conductor.playing:
			Music.play_sfx(rocket_star_sfx, -4.0)
		_dinged = true

	# ---- 镜头 ----
	var lag_cat := _cat_path(t - rocket_cam_lag, earth, b)            # 跟猫时看的是它稍早一点的位置：落后一点 = 速度感
	# 拍下去的那一瞬间就往地球上推（ease out：一下子推过去，再慢慢贴近），第 4 拍推到最近
	var zx := clampf(t / 4.0, 0.0, 1.0)
	var zin := 1.0 - pow(1.0 - zx, 4.0)
	var cx := clampf(t / 2.5, 0.0, 1.0)
	var center := camera_position.lerp(_on_view(earth), 1.0 - pow(1.0 - cx, 3.0))
	var view := lerpf(camera_size, rocket_close_size, zin)
	# 升空：中心追着猫、跟着拉远（指数，比猫缓），第 8 拍拉到 rocket_lift_size：地球还很大、但被挤到画面左下角边上
	# = 猫刚离开地球。之后飞走的那一小节再拉远到 rocket_leave_size，地球滑出画面
	var back := _expo(ru, rocket_pull_rate)
	view = lerpf(view, rocket_lift_size, back)
	center = center.lerp(_on_view(lag_cat + b * Vector3(rocket_lift_offset.x, rocket_lift_offset.y, 0.0)), back)
	# 飞走：镜头错开地球中心跟着猫，往右上偏，地球滑出画面左下（和升空接着，不停顿）
	var leave := smoothstep(8.0, 11.5, t)
	center = center.lerp(_on_view(lag_cat + b * Vector3(rocket_leave_offset.x, rocket_leave_offset.y, 0.0)), leave)
	view = lerpf(view, rocket_leave_size, leave)
	# 冲出：追着冲出去的猫，追不上
	var chase := smoothstep(12.6, 16.0, t)
	center = center.lerp(_on_view(lag_cat), chase * 0.5)
	view = lerpf(view, rocket_final_size, chase * chase)
	# 重音上镜头顶一下：十字星闪（推近一点）、冲出去（拉远一点）
	view *= 1.0 - 0.05 * _kick(t, 4.0) - 0.04 * _kick(t, rocket_ufo_hit) + 0.06 * _kick(t, 12.75)
	# 手持感：很慢的轻微漂移（跟远近成比例）+ 拍下去那一下的震
	var drift := Vector3(sin(ms * 1.3) * 0.6 + sin(ms * 2.9) * 0.4, sin(ms * 1.7 + 1.0) * 0.6 + sin(ms * 3.3) * 0.3, 0.0)
	center += b * drift * 0.025 * view / camera_size
	center += b * Vector3(sin(ms * 70.0), cos(ms * 83.0), 0.0) * 0.1 * exp(-t * 3.0)
	# 侧倾：拍下去那一下甩一下再回正；升空时顺着猫往右上斜一点；飞走转弯时往里歪；冲出时再歪
	var roll_deg := 5.0 * exp(-t * 2.2) * cos(t * 4.0)
	roll_deg += -3.0 * back * (1.0 - leave)
	roll_deg += -5.0 * sin(clampf((t - 7.6) / 3.4, 0.0, 1.0) * PI)
	roll_deg += -6.0 * chase
	var backdrop := _model.get_node_or_null("GalaxyBackdrop") as Node3D
	if backdrop:
		backdrop.scale = Vector3.ONE * lerpf(1.0, 4.0, zin)  # 星空背景放大：镜头后面挪远了也不露边（推近的时候放大，看不出来）
	camera.global_transform = Transform3D(Basis(b.z, deg_to_rad(roll_deg)) * b, center)
	camera.size = view


## 猫在第 t 拍的位置（不含晃动、蹲下）：升空（指数，斜着）→ 飞走（接着升空的速度冲出去，稍微冲过头再回来）→ 冲出（越冲越快）
func _cat_path(t: float, earth: Vector3, b: Basis) -> Vector3:
	var forward := -b.z
	var ru := clampf(t - 4.0, 0.0, 4.0)
	var p := earth - forward * (_earth_radius * 1.05 + 0.8) + b * Vector3(rocket_rise_to.x, rocket_rise_to.y, 0.0) * _expo(ru, rocket_rise_rate)
	var fx := clampf((t - 8.0) / 3.0, 0.0, 1.0)
	# 飞走：起步接着升空的速度（不突然加速，地球慢慢滑出画面），中间加速，最后稳稳停住
	var fly := 1.2 * (fx * fx * fx - 2.0 * fx * fx + fx) + (3.0 * fx * fx - 2.0 * fx * fx * fx)
	p = p.lerp(earth - forward * 3.5 + b * Vector3(rocket_stop.x, rocket_stop.y, 0.0), fly)
	var s := clampf((t - 12.75) / 3.25, 0.0, 1.3)
	return p + b * Vector3(rocket_stop.x, rocket_stop.y, 0.0).normalized() * 22.0 * pow(s, 2.6)


## 第 at 拍上镜头顶一下：一下子到 1，很快落回 0
static func _kick(t: float, at: float) -> float:
	if t < at - 0.05:
		return 0.0
	return exp(-maxf(t - at, 0.0) * 5.0) * smoothstep(at - 0.05, at, t)


## 指数的进度：u 从 0 到 4 拍，返回 0~1，按 e^(rate·u) 走（开头慢，越来越快）
static func _expo(u: float, rate: float) -> float:
	if rate <= 0.001:
		return clampf(u / 4.0, 0.0, 1.0)
	return (exp(rate * clampf(u, 0.0, 4.0)) - 1.0) / (exp(rate * 4.0) - 1.0)


## 让画面中心对准 point 的镜头位置（深度不变，只在镜头平面上挪）
func _on_view(point: Vector3) -> Vector3:
	var forward := -camera.global_transform.basis.z
	return point - forward * (point - camera_position).dot(forward)
