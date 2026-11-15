class_name DiscoRoad
extends Node
## 迪斯科关卡房间之后的几段演出（都在同一个 3D 世界里接着演，不切画面）：
##   start()        拆房子：两面墙往后倒、星星灯收走，格子地板往前铺成一条长路，镜头转到猫背后往前看
##   （自动）       路上滑行：猫一直往前滑，水果迎面撞来，到猫身上那一拍按键把它撞飞；猫自己挪到下一个水果前面
##   set_floor(1)   方格地板变成跟拍变色的舞池地板，路变宽
##   set_floor(2)   变成深色底上的霓虹网格线，路宽到看不见边
##   enter_plaza()  前面出现大圆台，猫滑到圆台中间停下，镜头转回斜俯视，回到缩圈判定
##   finale()       镜头拉远，猫换成站立的模型，飞碟降到头顶
## 用法：关卡脚本建一个本节点，setup(猫, 舞台)，每帧 update(拍数, 这一小关的音符)。
## 路上的音符不画缩圈，由这里按音符生成水果；uses_fruit(note) 告诉关卡哪些音符归水果管。
## 水果、路边灯球都是占位模型（stages/disco/model/fruit_*.glb）。

enum Phase { ROOM, UNFOLD, RUN, PLAZA, FINALE }

@export_group("拆房子")
## 墙倒下、地板铺出去、镜头转过去一共用几拍
@export var unfold_beats := 16.0
## 过场开头先让跳舞猫退场、星星灯升走，第几拍第一面墙（后墙）才倒
@export var wall_first_beat := 4.0
## 第二面墙（左墙）比第一面（后墙）晚几拍倒
@export var wall_gap_beats := 4.0
## 镜头从第几拍开始转（相对拆房子开始），转到上路为止
@export var camera_turn_from_beat := 9.0

@export_group("路")
## 猫每拍往前滑多远（3D 单位）。水果也按这个速度迎面过来
@export var units_per_beat := 16.0
## 水果提前几拍出现
@export var fruit_lead_beats := 5.0
## 路的半宽：刚铺出来 / 舞池 / 网格
@export var road_half_width := PackedFloat32Array([19.2, 34.0, 400.0])
## 猫左右挪动的道宽上限，和挪过去的快慢
@export var lane_width := 9.0
@export var lane_follow := 5.0
## 每隔几拍换一次道
@export var lane_change_beats := 2.0
## 水果离地多高
@export var fruit_height := 2.0
## 水果自己发多亮（暗场景里看得清）
@export var fruit_glow := 1.3
## 水果表面多光滑（越小越反光）、边缘光多强
@export_range(0.0, 1.0) var fruit_roughness := 0.12
@export_range(0.0, 1.0) var fruit_rim := 0.3
## 水果每拍再亮多少（加在 fruit_glow 上，材质自己发光，和彩色舞池地板区分开）
@export var fruit_glow_pulse := 0.9
## 水果跟着拍子：每拍胀大多少、跳多高、左右歪多少度
@export var fruit_beat_pulse := 0.4
@export var fruit_beat_hop := 0.5
@export var fruit_beat_sway_degrees := 14.0
## 玩家按键时所有水果胀一下：胀多少（每个水果再随机一点）、多久缩回去（秒）
@export var fruit_press_pop := 0.8
@export var fruit_press_seconds := 0.3
## 照水果的那盏灯（挂在猫前上方，给水果打出高光）：亮度、颜色
@export var fruit_light_energy := 0.9
@export var fruit_light_color := Color(1.0, 0.95, 0.9)

@export_group("路上的背景")
## 撞水果那一段的背景（彩虹 + 描边几何体），东西摆在这个场景里；留空 = 不要
@export var backdrop: PackedScene = preload("res://stages/disco/road_backdrop.tscn")

@export_group("镜头（透视）")
## 路上：镜头在猫背后多远、俯视角（度）、视野（度）、看向猫前面多远和多高
@export var run_distance := 27.0
@export var run_pitch := 21.0
@export var run_fov := 58.0
@export var run_look := Vector3(0.0, 3.0, -7.0)
## 圆台：水平转角（度）、俯视角、距离、视野
@export var plaza_yaw := 35.0
@export var plaza_pitch := 30.0
@export var plaza_distance := 36.0
@export var plaza_fov := 42.0
## 结尾镜头最后停在哪：水平转角、俯视角（负数 = 仰看）、距离、视野、看向哪里。
## 默认值和吸猫小关开场的镜头一样（猫在原点时：镜头在 (6, 2, 14.5)，看向 (3.3, 6.8, 0)，视野 60）
@export var finale_yaw := 10.5
@export var finale_pitch := -18.0
@export var finale_distance := 15.5
@export var finale_fov := 60.0
@export var finale_look := Vector3(3.3, 6.8, 0.0)
## 结尾时天空（房间外面的底色）渐渐变成什么颜色
@export var finale_sky := Color(0.13, 0.08, 0.16)
## 猫自己飞走的结尾：飞碟走了之后推到猫的特写，离多近、视角多大、俯仰多少度
@export var fly_closeup_distance := 15.0
## 特写时镜头绕着猫转多少度（180 = 转到正面）
@export var fly_closeup_turn := 165.0
@export var fly_closeup_fov := 38.0
@export var fly_closeup_pitch := 8.0
## 每拍视野「顶」一下的幅度（度）
@export var fov_punch := 4.0
## 跑起来和广场上镜头跟拍歪头：最大歪多少度、一个来回几拍
@export var beat_roll_degrees := 2.0
@export var beat_roll_beats := 4.0
## 升档时镜头踢一下：视野多拉开多少度、歪多少度、多少秒弹回来
@export var kick_fov := 9.0
@export var kick_roll := 5.0
@export var kick_seconds := 0.45
var _kick := 0.0
var _kick_side := 1.0

@export_group("圆台和结尾")
@export var plaza_radius := 46.0
## 圆台提前几拍出现在前方
@export var plaza_lead_beats := 4.0
@export var stand_cat: PackedScene = preload("res://stages/abduction/model/cat_stand.fbx")
@export var stand_cat_texture: Texture2D = preload("res://stages/abduction/model/cat_stand_basecolor.png")
@export var stand_cat_height := 4.0
## 飞碟：模型、位置、倾斜都照吸猫小关的来（猫在原点）
@export var saucer: PackedScene = preload("res://stages/abduction/ufo.tscn")
@export var saucer_position := Vector3(0.5, 15.0, -3.0)
@export var saucer_tilt_degrees := Vector3(16.0, 0.0, -8.0)
@export var saucer_beam_color := Color(0.45, 1.0, 0.45)
@export var saucer_scale := 1.0
## 飞碟出现时迪斯科灯球淡没用几秒
@export var ball_fade_seconds := 1.6

@export_group("圆台上的猫 meme（2.5D 观众）")
## MemeLib 里的名字，按顺序轮流用
@export var plaza_memes := PackedStringArray(["banana", "apple", "oiia", "nyan", "flower", "popcat", "nyanrun", "catjam"])
## 在圆台上打出第几个 Perfect（Great 也算）时开始出现；之后每打中一个再出 plaza_crowd_per_hit 只
@export var plaza_meme_first_perfect := 2
@export var plaza_crowd_per_hit := 4
## 最多几只
@export var plaza_crowd_max := 56
## 站在离主角猫多远的一圈里（3D 单位）：最近、最远
@export var plaza_crowd_near := 6.0
@export var plaza_crowd_far := 21.0
## 镜头和主角猫之间留出多宽的空（3D 单位），观众不站进去挡猫
@export var plaza_crowd_clear := 6.0
## 每只多高（3D 单位），随机上下浮动 plaza_crowd_height_random 倍
@export var plaza_crowd_height := 3.2
@export_range(0.0, 0.8) var plaza_crowd_height_random := 0.3
## 每拍跳起来多高（3D 单位）、落地压扁多少、动图放一遍用几拍
@export var plaza_meme_hop := 0.9
@export_range(0.0, 0.5) var plaza_meme_squash := 0.15
@export var plaza_meme_loop_beats := 2.0
## 玩家按键时大家一起多蹦多高（3D 单位）
@export var plaza_press_hop := 0.6

const FRUITS: Array[PackedScene] = [
	preload("res://stages/disco/model/fruit_apple.glb"),
	preload("res://stages/disco/model/fruit_orange.glb"),
	preload("res://stages/disco/model/fruit_banana.glb"),
	preload("res://stages/disco/model/fruit_watermelon.glb"),
]
const BALL := preload("res://stages/disco/model/disco_ball.glb")
const FLOOR_Y := -0.86  # 比房间地板顶面（-0.9）高一点点，免得两层闪

var phase: int = Phase.ROOM

var _cat: KisaSpinCat3D
var _stage: KisaDiscoStage
var _floor: MeshInstance3D
var _floor_mat: ShaderMaterial
var _room: Node3D
var _travel := 0.0
var _speed := 0.0  # 现在每秒滑多远
var _last_time := 0.0
var _phase_beat := 0.0  # 进入当前阶段时的拍数
var _fruit_from := INF  # 这一拍及以后的音符归水果管
var _run_at := INF  # 过场演到这一拍开始往前滑
var _fruit_until := INF  # 这一拍及以后的音符又回到缩圈
var _plaza_travel := INF  # 滑到这么远就停（圆台中心）
var _fruits := {}  # NoteData -> Node3D
var _side_balls: Array[Node3D] = []
var _half_width := 19.2
var _reveal := 0.0
var _dance := 0.0
var _grid := 0.0
var _plaza := 0.0
var _lane_x := 0.0
# 镜头：水平转角、俯视角、距离、视野、看向哪里；从 _cam_a 过渡到 _cam_b
var _cam_a := {}
var _cam_b := {}
var _cam_t := 1.0
var _fallers: Array = []  # [节点, 原来的全局变换, 铰链点, 轴]
var _fall := 0.0       # 后墙倒了多少（0~1）
var _fall_left := 0.0  # 左墙倒了多少
var _saucer_node: Node3D
var _backdrop: RoadBackdrop
var _press := 0.0  # 玩家刚按键：1 然后很快掉回 0
var _finale_beam: MeshInstance3D
var _finale_beam_mat: ShaderMaterial
var _finale_glow: OmniLight3D
var _plaza_perfects := 0
var _fruit_light: OmniLight3D
var _plaza_cats: Array[Dictionary] = []  # {holder: Node3D, sprite: Sprite3D, h: 高度, phase: 错开的拍数, frames: 帧数}
var _plaza_slots := PackedVector3Array()  # 观众站位（按出现的先后），第一次用到时排好
var _ball_scale := 1.0
## 节拍辅助线（路上滑行那段）：横在路面上的线，在每一拍水果会飞到的位置。关卡脚本按自己的设置填
var beat_guides := true
var guide_every := 1.0
var _guides: BeatGuideStrips
## 路面白圈的半径（米）
var guide_ring_radius := 1.9
## 判定圈：猫脚底的绿圈（和水果底下的白圈一样大），水果的白圈滑到和它重合的那一拍按
var judge_ring_color := Color(0.3, 1.0, 0.4)
var _judge_ring: BeatGuideStrips


func setup(cat: KisaSpinCat3D, stage: KisaDiscoStage) -> void:
	_cat = cat
	_stage = stage
	_room = cat.backdrop_node
	_last_time = Time.get_ticks_msec() / 1000.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(900.0, 1400.0)
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = preload("res://stages/disco/road_floor.gdshader")
	_floor_mat.set_shader_parameter("plaza_radius", plaza_radius)
	plane.material = _floor_mat
	_floor = MeshInstance3D.new()
	_floor.mesh = plane
	_floor.position = Vector3(0.0, FLOOR_Y, -650.0)
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor.visible = false
	cat.world.add_child(_floor)


## 这个音符是不是由水果来表现（是的话关卡就不给它画缩圈）
func uses_fruit(note: NoteData) -> bool:
	return note.beat >= _fruit_from and note.beat < _fruit_until


## 现在要不要画白色判定圈（路上滑行时不画）
func rings_visible(beat: float) -> bool:
	if phase == Phase.FINALE:
		return false
	return phase == Phase.ROOM or phase == Phase.UNFOLD or beat > _fruit_until - 3.0


## 拆房子，然后上路。first_fruit_beat = 第一个水果到猫身上是第几拍（不给就是拆完那一拍）
func start(beat: float, first_fruit_beat: float = -1.0) -> void:
	if phase != Phase.ROOM:
		return
	phase = Phase.UNFOLD
	_phase_beat = beat
	_fruit_from = first_fruit_beat if first_fruit_beat > beat else ceilf(beat + unfold_beats)
	_run_at = beat + unfold_beats - 1.0
	_stage.takeover = true
	_stage.dismiss_dancers()
	_stage.raise_stars()
	# 从背后看光柱太抢眼，慢慢调淡
	create_tween().tween_property(_stage, "beam_strength", _stage.beam_strength * 0.45, 2.0)
	_floor.visible = true
	_cat.camera.far = 2500.0

	# 灯球从房间里摘出来，之后一直跟在猫头顶
	var ball := _stage.ball_node()
	var keep := ball.global_transform
	ball.get_parent().remove_child(ball)
	_cat.world.add_child(ball)
	ball.global_transform = keep
	_ball_scale = keep.basis.get_scale().x / maxf(ball.scale.x, 0.001) * ball.scale.x  # 原来在放大过的房间里，摘出来后自己记着这个大小

	# 两面墙连同挂在上面的东西，绕着墙脚往外倒
	var scaled := _room.get_node_or_null("Scaled") as Node3D
	var to_world := scaled.global_transform if scaled else Transform3D.IDENTITY
	var hinge_back := to_world * Vector3(0.0, -0.9, -8.0)
	var hinge_left := to_world * Vector3(-8.0, -0.9, 0.0)
	for n in ["WallBack", "SkirtingBack", "WallStar", "ZigzagPlaque", "Cable"]:
		_add_faller(n, hinge_back, Vector3.RIGHT, -1.0, false)
	for n in ["WallLeft", "SkirtingLeft", "GamepadLight", "FlowerLight"]:
		_add_faller(n, hinge_left, Vector3.BACK, 1.0, true)
	var t := create_tween()
	t.tween_interval(wall_first_beat * Conductor.sec_per_beat())
	t.tween_property(self, "_fall", 1.0, 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var t_left := create_tween()
	t_left.tween_interval((wall_first_beat + wall_gap_beats) * Conductor.sec_per_beat())
	t_left.tween_property(self, "_fall_left", 1.0, 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	# 镜头：从 isometric 换成透视（先用很窄的视野摆在同一个位置，看起来没变），再转到猫背后
	var cam := _cat.camera
	var size := cam.size
	# 用镜头此刻真实的朝向和位置起步（舞台那边还叠着摇摆和推拉），这样换投影的一瞬间画面不跳
	var back := cam.global_transform.basis.z  # 从目标指向镜头的方向
	var target := cam.global_position - back * 100.0
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam_a = {"yaw": rad_to_deg(atan2(back.x, back.z)), "pitch": rad_to_deg(asin(clampf(back.y, -1.0, 1.0))), "fov": 10.0,
			"dist": size / (2.0 * tan(deg_to_rad(5.0))), "look": target}
	_cam_b = _run_cam()
	_cam_t = 0.0
	var seconds := unfold_beats * Conductor.sec_per_beat()
	var tc := create_tween()
	var turn_from := camera_turn_from_beat * Conductor.sec_per_beat()
	tc.tween_interval(turn_from)
	tc.tween_property(self, "_cam_t", 1.0, maxf(seconds - turn_from, 0.5)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 地板往前铺出去；猫转身背对镜头、回到路中间
	var tr := create_tween()
	tr.tween_interval(seconds * 0.3)
	tr.tween_property(self, "_reveal", 620.0, seconds * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var tp := create_tween().set_parallel()
	tp.tween_property(_cat, "pose_position", Vector3.ZERO, seconds * 0.4)
	tp.tween_property(_cat, "pose_tilt", Vector2.ZERO, seconds * 0.4)
	var ty := create_tween()
	ty.tween_interval(turn_from)
	ty.tween_property(_cat, "pose_yaw", PI, maxf(seconds - turn_from, 0.5) * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	create_tween().tween_property(_cat.environment, "background_color", Color(0.02, 0.01, 0.05), 2.5)


## 换地板：1 = 舞池，2 = 霓虹网格
func set_floor(mode: int) -> void:
	var t := create_tween().set_parallel()
	if mode >= 1:
		t.tween_property(self, "_dance", 1.0, 1.5)
		t.tween_property(self, "_half_width", road_half_width[1], 4.0).set_trans(Tween.TRANS_SINE)
	if mode >= 2:
		t.tween_property(self, "_grid", 1.0, 2.0)
		t.tween_property(self, "_half_width", road_half_width[2], 5.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)


## 前面出现圆台；滑到圆台中间停下，回到缩圈判定
func enter_plaza(beat: float, arrive_beat: float = -1.0) -> void:
	if phase != Phase.RUN:
		return
	if arrive_beat <= beat:
		arrive_beat = ceilf(beat + plaza_lead_beats)
	_plaza_travel = _travel + (arrive_beat - beat) * units_per_beat
	_fruit_until = arrive_beat
	create_tween().tween_property(self, "_plaza", 1.0, 0.3)


## 结尾（一段连续的镜头，不切画面）：猫转一圈变成站立的姿势 -> 飞碟从上面降下来、绿色光柱罩住猫
## -> 镜头从斜俯视慢慢降到低处、仰看飞碟，停在和吸猫小关开场一样的构图上。seconds = 这一段总共多长
## stay_wide = 镜头不降下去，停在广场的远景上（不接吸猫、猫自己飞走的结尾用）
func finale(seconds: float = 8.0, stay_wide: bool = false) -> void:
	if phase == Phase.FINALE or phase == Phase.ROOM:
		return
	phase = Phase.FINALE
	if _backdrop:
		_backdrop.hide_away()
	for fruit: Node3D in _fruits.values():
		fruit.queue_free()
	_fruits.clear()
	_dismiss_plaza_cats()
	# 猫：转一圈，转到一半换成站立的模型
	_cat.spin()
	var tcat := create_tween()
	tcat.tween_interval(0.12)
	tcat.tween_callback(_swap_to_standing_cat)
	create_tween().tween_property(_cat, "pose_position", Vector3.ZERO, 0.5)
	# 原来头顶的暖色光柱淡掉，换成飞碟的绿光
	create_tween().tween_property(_stage, "beam_strength", 0.0, 1.5)
	create_tween().tween_property(_stage, "top_light_energy", 0.0, 2.0)
	create_tween().tween_property(_stage, "top_light_pulse", 0.0, 2.0)
	create_tween().tween_property(_cat.environment, "background_color", finale_sky, seconds * 0.8)

	# 飞碟从上面降下来（位置、倾斜和吸猫小关一样），到位后亮起光柱
	_saucer_node = saucer.instantiate() as Node3D
	var tilt := saucer_tilt_degrees * (PI / 180.0)
	_saucer_node.transform = Transform3D(Basis.from_euler(tilt).scaled(Vector3.ONE * saucer_scale),
			saucer_position + Vector3.UP * 60.0)
	_cat.world.add_child(_saucer_node)
	# 飞碟一出现，迪斯科灯球（连同光束、射灯）就慢慢淡没，给飞碟让位
	var tball := create_tween()
	tball.tween_interval(seconds * 0.08)
	tball.tween_property(_stage, "ball_fade", 0.0, ball_fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var ts := create_tween()
	ts.tween_interval(seconds * 0.08)
	ts.tween_property(_saucer_node, "position", saucer_position, seconds * 0.35) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var glow := OmniLight3D.new()
	glow.light_color = saucer_beam_color
	glow.light_energy = 0.0
	glow.omni_range = 40.0
	glow.position = saucer_position + Vector3.DOWN * 3.0
	_cat.world.add_child(glow)
	var cone := CylinderMesh.new()
	cone.top_radius = 1.6
	cone.bottom_radius = 5.5
	cone.height = saucer_position.length()
	cone.radial_segments = 32
	cone.cap_top = false
	cone.cap_bottom = false
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = preload("res://stages/disco/spot_beam.gdshader")
	beam_mat.set_shader_parameter("beam_color", saucer_beam_color)
	beam_mat.set_shader_parameter("strength", 0.0)
	cone.material = beam_mat
	var beam := MeshInstance3D.new()
	beam.mesh = cone
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 光柱从飞碟肚子斜着罩到猫脚下
	beam.transform = Transform3D(Basis(Quaternion(Vector3.UP, saucer_position.normalized())), saucer_position * 0.5)
	_cat.world.add_child(beam)
	_finale_beam = beam
	_finale_beam_mat = beam_mat
	_finale_glow = glow
	var tb := create_tween().set_parallel()
	tb.tween_interval(seconds * 0.4)
	tb.chain().tween_method(func(v: float): beam_mat.set_shader_parameter("strength", v), 0.0, 0.5, 1.0)
	tb.tween_property(glow, "light_energy", 5.0, 1.0)

	# 镜头：先在斜俯视上稍微拉开看飞碟降下来，再慢慢降到低处仰看
	_cam_a = _current_cam()
	_cam_b = _cam_a.duplicate()
	_cam_b["dist"] = float(_cam_a["dist"]) * 1.25
	_cam_b["look"] = Vector3(0.0, 6.0, 0.0)
	_cam_t = 0.0
	var tc := create_tween()
	tc.tween_property(self, "_cam_t", 1.0, seconds * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if stay_wide:
		return
	tc.tween_callback(func():
		_cam_a = _current_cam()
		_cam_b = {"yaw": finale_yaw, "pitch": finale_pitch, "fov": finale_fov, "dist": finale_distance,
				"look": finale_look}
		_cam_t = 0.0)
	tc.tween_property(self, "_cam_t", 1.0, seconds * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 音符判定了：打中的水果被撞飞，没打中的继续往后飞过去
func fruit_judged(note: NoteData, result: int) -> void:
	var fruit: Node3D = _fruits.get(note)
	if fruit == null:
		return
	if result == NoteData.Result.MISS:
		return
	_fruits.erase(note)
	var side := 1.0 if fruit.position.x >= _cat.pose_position.x else -1.0
	if absf(fruit.position.x - _cat.pose_position.x) < 0.5:
		side = 1.0 if randf() > 0.5 else -1.0
	var t := fruit.create_tween().set_parallel()
	t.tween_property(fruit, "position", fruit.position + Vector3(side * 26.0, 18.0, -40.0), 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(fruit, "rotation", fruit.rotation + Vector3(9.0, 6.0 * side, 4.0), 0.6)
	t.tween_property(fruit, "scale", Vector3.ONE * 0.3, 0.6).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(fruit.queue_free)


## 每帧调用。notes = 这一小关的音符（按时间排好的）
func update(beat: float, notes: Array[NoteData]) -> void:
	if phase == Phase.ROOM:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var delta := minf(now - _last_time, 0.1)
	_last_time = now
	var pulse := exp(-fposmod(beat, 1.0) * 5.0)

	if phase == Phase.UNFOLD:
		_apply_fall()
		_update_fruits(beat, notes)
		if beat >= _run_at:
			_begin_run(beat)

	if phase == Phase.RUN or phase == Phase.PLAZA:
		# 往前滑：起步慢慢加速；快到圆台时不超过圆台中心
		var cruise := units_per_beat / Conductor.sec_per_beat()
		_speed = lerpf(_speed, cruise, 1.0 - exp(-2.5 * delta))
		_travel = minf(_travel + _speed * delta, _plaza_travel)
		if phase == Phase.RUN and _travel >= _plaza_travel:
			_arrive_plaza()
		# 房间留在后面，滑远了就收掉
		if _room.visible:
			_room.position.z = _travel
			if _travel > 140.0:
				_room.visible = false
		_update_fruits(beat, notes)
		_update_guides(beat, notes)
		_update_cat(beat, notes, delta)
		_update_side_balls(beat)

	# 灯球：路上滑行时升到画面外藏起来（挡视野），到圆台再降回来
	var ball := _stage.ball_node()
	var ball_home := Vector3(_cat.pose_position.x * 0.5, 13.0, -10.0)
	if phase == Phase.RUN:
		ball_home.y = 60.0
	if phase == Phase.PLAZA or phase == Phase.FINALE:
		ball_home = Vector3(-6.0, 16.0, -6.0)
	ball.position = ball.position.lerp(ball_home, 1.0 - exp(-2.0 * delta))
	ball.scale *= _ball_scale  # 舞台每帧把灯球缩放设回 1 左右（跟拍一胀一缩），这里补上房间原来的放大倍数
	ball.visible = ball.position.y < 45.0 and _stage.ball_fade > 0.01

	if _backdrop:
		_backdrop.update(beat)
	_floor_mat.set_shader_parameter("half_width", _half_width)
	_floor_mat.set_shader_parameter("reveal", _reveal)
	_floor_mat.set_shader_parameter("travel", _travel)
	_floor_mat.set_shader_parameter("beat", beat)
	_floor_mat.set_shader_parameter("dance", _dance)
	_floor_mat.set_shader_parameter("grid", _grid)
	_floor_mat.set_shader_parameter("plaza", _plaza)
	_floor_mat.set_shader_parameter("plaza_dist", _plaza_travel - _travel if _plaza_travel < INF else 100000.0)
	_update_plaza_cats(beat)
	_apply_camera(pulse)


func _begin_run(beat: float) -> void:
	phase = Phase.RUN
	_phase_beat = beat
	_fall = 1.0
	_fall_left = 1.0
	_apply_fall()
	# 倒下的墙和挂件沉到地板下面，不挡路
	for f in _fallers:
		var n: Node3D = f[0]
		create_tween().tween_property(n, "global_position:y", n.global_position.y - 6.0, 1.0)
	# 一盏照水果的灯，跟在猫前上方
	_fruit_light = OmniLight3D.new()
	_fruit_light.light_color = fruit_light_color
	_fruit_light.light_energy = fruit_light_energy
	_fruit_light.omni_range = 70.0
	_fruit_light.omni_attenuation = 0.6
	_fruit_light.position = Vector3(0.0, 12.0, -22.0)
	_cat.world.add_child(_fruit_light)
	if backdrop:
		_backdrop = backdrop.instantiate() as RoadBackdrop
		_cat.world.add_child(_backdrop)
		_backdrop.show_up()
	for i in 6:
		var b := BALL.instantiate() as Node3D
		b.scale = Vector3.ONE * 0.5
		_cat.world.add_child(b)
		_side_balls.append(b)


func _arrive_plaza() -> void:
	phase = Phase.PLAZA
	_speed = 0.0
	_cam_a = _current_cam()
	_cam_b = {"yaw": plaza_yaw, "pitch": plaza_pitch, "fov": plaza_fov, "dist": plaza_distance,
			"look": Vector3(0.0, 2.5, 0.0)}
	_cam_t = 0.0
	create_tween().tween_property(self, "_cam_t", 1.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var t := create_tween().set_parallel()
	t.tween_property(_cat, "pose_yaw", TAU, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_cat, "pose_position", Vector3.ZERO, 0.8)
	t.tween_property(_cat, "pose_tilt", Vector2.ZERO, 0.4)
	for b in _side_balls:
		b.queue_free()
	_side_balls.clear()


## 按音符生成 / 移动水果：水果在 note.beat 那一拍正好到猫身上
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(Judge.HIT_ACTION):
		_press = 1.0


## 节拍辅助线（规则见 BeatGuides）：路面上的白圈，和水果同一套远近。
##   要按的拍子：每个水果正下方一个白色实线圈，越近越亮越粗；
##   不用按的拍子：一个空着的白色虚线圈，摆在「后面最近那个水果」的那条道上，
##   所以一排空拍会和后面要来的水果竖着对齐，看得出下一个水果从哪条道来。
func _update_guides(beat: float, notes: Array[NoteData]) -> void:
	if _guides == null:
		_guides = BeatGuideStrips.new()
		_cat.world.add_child(_guides)
	_guides.begin()
	if beat_guides and phase == Phase.RUN:
		var fruit_notes: Array[NoteData] = []
		for n in notes:
			if uses_fruit(n) and not n.judged:
				fruit_notes.append(n)
		for g in BeatGuides.compute(fruit_notes, beat, fruit_lead_beats, guide_every,
				func(_n: NoteData) -> Color: return Color.WHITE):
			if not g.solid and g.beat >= _fruit_until:
				continue  # 到了圆台就换回缩圈的辅助线
			var z := -clampf(g.a, -0.1, 1.0) * fruit_lead_beats * units_per_beat
			var l := BeatGuides.look(g)
			if g.solid:
				for n: NoteData in g.notes:
					_guides.circle(Vector3(_lane_of(n), FLOOR_Y + 0.06, z), guide_ring_radius, l, 0.22)
			else:
				_guides.circle(Vector3(_next_lane_x(fruit_notes, g.beat), FLOOR_Y + 0.06, z), guide_ring_radius, l, 0.22)
	_guides.finish()
	_update_judge_ring(beat, notes)


## 猫脚底的绿色判定圈：跟着猫换道，就在水果到猫身上的那个位置（z = 0），大小和水果的白圈一样，
## 所以水果的白圈滑过来和它重合时就是该按的时候。下一个水果不到一拍就到时变粗变亮。
func _update_judge_ring(beat: float, notes: Array[NoteData]) -> void:
	if _judge_ring == null:
		_judge_ring = BeatGuideStrips.new()
		_cat.world.add_child(_judge_ring)
	_judge_ring.begin()
	if beat_guides and phase == Phase.RUN:
		var fruit_notes: Array[NoteData] = []
		for n in notes:
			if uses_fruit(n):
				fruit_notes.append(n)
		var k: float = BeatGuides.anticipation(fruit_notes, beat).k
		var c := judge_ring_color.lerp(Color.WHITE, k * 0.3)
		c.a = 0.85 + 0.15 * k
		var x := _cat.pose_position.x
		_judge_ring.circle(Vector3(x, FLOOR_Y + 0.08, 0.0), guide_ring_radius,
				{"color": c, "width": 1.0 + k * 1.2, "dashed": false}, 0.28)
	_judge_ring.finish()


## 空拍的圈摆在哪条道上：beat 之后最近的那个水果的道（后面没水果了就用前面最近的）
func _next_lane_x(fruit_notes: Array[NoteData], b: float) -> float:
	var prev := 0.0
	for n in fruit_notes:
		if n.beat > b + 0.001:
			return _lane_of(n)
		prev = _lane_of(n)
	return prev


func _update_fruits(beat: float, notes: Array[NoteData]) -> void:
	_press = maxf(_press - get_process_delta_time() / maxf(fruit_press_seconds, 0.01), 0.0)
	for n in notes:
		var ahead := n.beat - beat
		if ahead > fruit_lead_beats:
			break
		if ahead < -2.0 or not uses_fruit(n):
			continue
		if n.judged and not _fruits.has(n):
			continue  # 已经被撞飞了
		var fruit: Node3D = _fruits.get(n)
		if fruit == null:
			fruit = _make_fruit(n)
			_fruits[n] = fruit
		# 跟着拍子动：每拍落地一次（整拍在最低点），左右两拍歪一个来回。发光和胀缩由水果身上的 BeatGlow 管
		fruit.position = Vector3(_lane_of(n), fruit_height + absf(sin(beat * PI)) * fruit_beat_hop, -ahead * units_per_beat)
		fruit.rotation = Vector3(0.0, beat * 1.5 + n.beat, sin(beat * PI) * deg_to_rad(fruit_beat_sway_degrees))
	# 没打中、已经飞到身后的收掉；音符被撤掉了（关卡歇一会儿时）的水果也收掉，不让它空飞过来
	var current := {}
	for n in notes:
		current[n] = true
	for n: NoteData in _fruits.keys():
		if n.beat - beat < -1.5 or not current.has(n):
			(_fruits[n] as Node3D).queue_free()
			_fruits.erase(n)


func _make_fruit(n: NoteData) -> Node3D:
	var kind := (n.sound + (3 if roundi(n.beat) % 5 == 0 else 0)) % FRUITS.size()
	var fruit := FRUITS[kind].instantiate() as Node3D
	fruit.scale = Vector3.ONE * FRUIT_SCALE
	_cat.world.add_child(fruit)
	# 亮面反光、用自己的贴图发光、每拍亮一下胀一下、按键时胀一下：通用效果 BeatGlow（scripts/fx/beat_glow.gd）
	BeatGlow.attach(fruit, {
		"glow": fruit_glow, "glow_pulse": fruit_glow_pulse,
		"roughness": fruit_roughness, "rim": fruit_rim,
		"scale_pulse": fruit_beat_pulse, "press_seconds": fruit_press_seconds,
		"press_pop": fruit_press_pop * (0.6 + 0.8 * fposmod(n.beat * 0.618, 1.0)),  # 每个水果胀的多少不一样
	})
	return fruit


const FRUIT_SCALE := 1.3


## 这个音符的水果在哪条道上（每 lane_change_beats 拍换一次，同一段里的水果排成一串）
func _lane_of(n: NoteData) -> float:
	var k := floori(n.beat / lane_change_beats)
	var lane := posmod(k * 7 + k / 3, 3) - 1
	return lane * minf(lane_width, _half_width * 0.45)


## 猫挪到下一个水果前面，身体跟着歪过去
func _update_cat(beat: float, notes: Array[NoteData], delta: float) -> void:
	if phase != Phase.RUN:
		return
	var target := _lane_x
	for n in notes:
		if n.judged or n.beat - beat < -0.15 or not uses_fruit(n):
			continue
		if n.beat - beat > fruit_lead_beats:
			break
		target = _lane_of(n)
		break
	_lane_x = target
	var x := _cat.pose_position.x
	var nx := lerpf(x, target, 1.0 - exp(-lane_follow * delta))
	var vx := (nx - x) / maxf(delta, 0.001)
	_cat.pose_position = Vector3(nx, 0.25 + sin(beat * PI) * 0.15, 0.0)
	_cat.pose_tilt = Vector2(-0.12, clampf(vx * 0.02, -0.45, 0.45))


## 路两边吊着的灯球：等距排开，跟着地板往后流，流过去的挪到最前面
func _update_side_balls(beat: float) -> void:
	var gap := 70.0
	var span := gap * _side_balls.size() / 2.0
	for i in _side_balls.size():
		var b := _side_balls[i]
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := fposmod((i / 2) * gap + (0.0 if side < 0.0 else gap * 0.5) - _travel, span)
		b.position = Vector3(side * (minf(_half_width, 60.0) + 9.0), 15.0 + sin(beat * 0.5 + i) * 1.5, 40.0 - (span - z))
		b.rotation.y = beat * 0.8 + i


func _add_faller(node_name: String, hinge: Vector3, axis: Vector3, direction: float, is_left: bool) -> void:
	var n := _room.find_child(node_name, true, false) as Node3D
	if n:
		_fallers.append([n, n.global_transform, hinge, axis * direction, is_left])


func _apply_fall() -> void:
	for f in _fallers:
		var axis: Vector3 = (f[3] as Vector3).normalized()
		var hinge: Vector3 = f[2]
		var rot := Basis(axis, (_fall_left if f[4] else _fall) * PI / 2.0)
		var xf := Transform3D(rot, hinge - rot * hinge)
		(f[0] as Node3D).global_transform = xf * (f[1] as Transform3D)


func _run_cam() -> Dictionary:
	return {"yaw": 0.0, "pitch": run_pitch, "fov": run_fov, "dist": run_distance, "look": run_look}


func _current_cam() -> Dictionary:
	var out := {}
	for k in _cam_b:
		out[k] = _mix(k)
	return out


func _mix(key: String) -> Variant:
	var a: Variant = _cam_a.get(key, _cam_b[key])
	var b: Variant = _cam_b[key]
	if key == "dist":  # 距离按比例过渡，远近差很多时更顺
		return exp(lerpf(log(a), log(b), _cam_t))
	return lerp(a, b, _cam_t)


func _apply_camera(pulse: float) -> void:
	if _cam_b.is_empty():
		return
	var cam := _cat.camera
	var yaw := deg_to_rad(_mix("yaw"))
	var pitch := deg_to_rad(_mix("pitch"))
	var look: Vector3 = _mix("look")
	if phase == Phase.RUN:
		look.x += _cat.pose_position.x * 0.6 * _cam_t
	var dir := Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw)
	cam.fov = _mix("fov") - pulse * fov_punch * (1.0 if phase != Phase.UNFOLD else 0.0) + _kick * kick_fov
	cam.position = look + dir * _mix("dist")
	cam.look_at(look)
	# 更带劲一点：跑起来和广场上，镜头跟着拍子左右歪头；升档时踢一下（猛地拉远 + 歪一下，再弹回来）
	if phase == Phase.RUN or phase == Phase.PLAZA:
		var beat := Conductor.song_beat
		var roll := sin(beat / beat_roll_beats * TAU) * beat_roll_degrees + _kick * kick_roll * _kick_side
		cam.rotate_object_local(Vector3.BACK, deg_to_rad(roll))
	_kick = move_toward(_kick, 0.0, get_process_delta_time() / kick_seconds)


## 镜头踢一下（升档时由 disco_decor.gd 调）
func cam_kick(strength: float = 1.0) -> void:
	_kick = strength
	_kick_side = -_kick_side


## 结尾的最后一段（不接吸猫时用）：猫在光柱里浮起来 -> 飞碟自己飞走 -> 过一会儿猫 Q 弹地向上飞出屏幕。
## seconds = 这一段总共多长。返回猫起飞的那一刻离现在多少秒（配音效用）。
func fly_away(seconds: float = 4.5) -> float:
	if phase != Phase.FINALE:
		return 0.0
	var base := _cat.pose_position
	var up := Vector3.UP
	# 猫：浮起来，上下轻轻晃两下，蹲一下，弹出去
	var tc := create_tween()
	tc.tween_property(_cat, "pose_position", base + up * 1.7, seconds * 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tc.tween_property(_cat, "pose_position", base + up * 1.3, seconds * 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tc.tween_property(_cat, "pose_position", base + up * 1.7, seconds * 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tc.tween_property(_cat, "pose_position", base + up * 1.1, seconds * 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# （起飞不用 TRANS_BACK：它会先往回缩飞行距离的一成，猫会掉到地板下面；上面那一下下蹲已经是预备动作了）
	tc.tween_property(_cat, "pose_position", base + up * 60.0, seconds * 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	var launch := seconds * 0.64
	# Q 弹：蹲的时候压扁，弹出去的时候拉长
	var pivot := _cat._pivot
	var s0 := pivot.scale
	var tsq := create_tween()
	tsq.tween_interval(seconds * 0.54)
	tsq.tween_property(pivot, "scale", s0 * Vector3(1.3, 0.65, 1.3), seconds * 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tsq.tween_property(pivot, "scale", s0 * Vector3(0.75, 1.5, 0.75), seconds * 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 飞碟：光柱先灭，然后斜着加速飞走
	if _finale_beam_mat:
		var tb := create_tween().set_parallel()
		tb.tween_interval(seconds * 0.12)
		tb.chain().tween_method(func(v: float): _finale_beam_mat.set_shader_parameter("strength", v), 0.5, 0.0, 0.4)
		tb.tween_property(_finale_glow, "light_energy", 0.0, 0.4)
	if _saucer_node:
		var tu := create_tween()
		tu.tween_interval(seconds * 0.18)
		tu.tween_property(_saucer_node, "position", saucer_position + Vector3(30.0, 55.0, -10.0), seconds * 0.28) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# 镜头：飞碟走了之后推到猫的特写，停住；猫起飞时它就从特写里一下子冲出画面
	var tcam := create_tween()
	tcam.tween_interval(seconds * 0.30)
	tcam.tween_callback(func():
		_cam_a = _current_cam()
		_cam_b = _cam_a.duplicate()
		_cam_b["dist"] = fly_closeup_distance
		_cam_b["fov"] = fly_closeup_fov
		_cam_b["pitch"] = fly_closeup_pitch
		_cam_b["yaw"] = float(_cam_a["yaw"]) + fly_closeup_turn
		_cam_b["look"] = _cat.focus + base + up * 2.2
		_cam_t = 0.0)
	tcam.tween_property(self, "_cam_t", 1.0, seconds * 0.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return launch


## 结尾镜头放完，接着在这里玩吸猫：把停好的飞碟交出去（吸猫舞台接手），自己的光柱和站着的猫收掉
## （吸猫舞台在同一个位置放它自己的光束和猫）。只在结尾阶段能调，返回飞碟节点。
func hand_over_saucer() -> Node3D:
	if phase != Phase.FINALE or _saucer_node == null:
		return null
	if _finale_beam_mat:
		var t := create_tween().set_parallel()
		t.tween_method(func(v: float): _finale_beam_mat.set_shader_parameter("strength", v), 0.5, 0.0, 0.4)
		t.tween_property(_finale_glow, "light_energy", 0.0, 0.4)
		t.chain().tween_callback(_finale_beam.queue_free)
	_saucer_node.position = saucer_position
	_cat._pivot.visible = false
	var out := _saucer_node
	_saucer_node = null
	return out


## 把转圈的猫换成站立的猫（吸猫关卡的模型，只读取用）
func _swap_to_standing_cat() -> void:
	var pivot := _cat._pivot
	for mi in pivot.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false
	var holder := Node3D.new()
	pivot.add_child(holder)
	var inst := stand_cat.instantiate() as Node3D
	holder.add_child(inst)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = stand_cat_texture
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.skeleton = NodePath("")
		m.skin = null
		for s in m.mesh.get_surface_count():
			m.set_surface_override_material(s, mat)
	var box: AABB = _cat._measure(inst)
	var k := stand_cat_height / maxf(box.size.y, 0.001)
	holder.scale = Vector3.ONE * k
	holder.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * k
	_cat.pose_tilt = Vector2.ZERO


## 在圆台上打中一个 Perfect（或 Great）：攒够了就多出来几只猫 meme，站在圆台上围着主角猫一起跳。
## 它们是立在 3D 世界里的纸片（永远正对镜头），远的小、近的大，像一群观众。
func plaza_perfect() -> void:
	if phase != Phase.PLAZA:
		return
	_plaza_perfects += 1
	if _plaza_perfects < plaza_meme_first_perfect or plaza_memes.is_empty():
		return
	if _plaza_slots.is_empty():
		_plaza_slots = _make_plaza_slots()
	for k in plaza_crowd_per_hit:
		var i := _plaza_cats.size()
		if i >= mini(plaza_crowd_max, _plaza_slots.size()):
			return
		_spawn_plaza_cat(i)


func _spawn_plaza_cat(i: int) -> void:
	var info := MemeLib.find(plaza_memes[i % plaza_memes.size()])
	if info.is_empty():
		return
	var tex: Texture2D = load(info.path)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + i
	var h := plaza_crowd_height * (1.0 + rng.randf_range(-plaza_crowd_height_random, plaza_crowd_height_random))
	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.hframes = info.cols
	sprite.vframes = info.rows
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y  # 正对镜头但不往后仰，像立着的纸片
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS  # 一大群叠在一起时前后遮挡不会乱
	sprite.pixel_size = h / (tex.get_height() / float(info.rows))
	sprite.offset.y = tex.get_height() / float(info.rows) / 2.0  # 原点在脚底
	var pos := _plaza_slots[i]
	# 素材默认朝右；站在画面右边的翻过来，都朝着中间的主角猫
	var right := Vector3(cos(deg_to_rad(plaza_yaw)), 0.0, -sin(deg_to_rad(plaza_yaw)))
	sprite.flip_h = pos.dot(right) > 0.0
	var holder := Node3D.new()
	holder.position = pos
	holder.scale = Vector3.ZERO
	holder.add_child(sprite)
	_cat.world.add_child(holder)
	holder.create_tween().tween_property(holder, "scale", Vector3.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_plaza_cats.append({"holder": holder, "sprite": sprite, "h": h,
			"phase": rng.randf_range(0.0, 0.25), "frames": int(info.frames)})


## 观众站位：主角猫周围一圈圈散开，近的先来；镜头和猫之间那条“视线”上不站人
func _make_plaza_slots() -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var yaw := deg_to_rad(plaza_yaw)  # 镜头在猫的这个方向上（见 _apply_camera）
	var slots: Array[Vector3] = []
	var tries := 0
	while slots.size() < plaza_crowd_max and tries < 4000:
		tries += 1
		# 半径按面积均匀撒，近处不会挤成一团
		var r := sqrt(rng.randf_range(plaza_crowd_near * plaza_crowd_near, plaza_crowd_far * plaza_crowd_far))
		var a := rng.randf() * TAU
		var rel := wrapf(a - yaw, -PI, PI)
		if cos(rel) > 0.0 and absf(sin(rel)) * r < plaza_crowd_clear:
			continue  # 挡在镜头和猫中间
		var p := Vector3(sin(a) * r, FLOOR_Y, cos(a) * r)
		var crowded := false
		for q in slots:
			if q.distance_to(p) < plaza_crowd_height * 0.65:
				crowded = true
				break
		if not crowded:
			slots.append(p)
	slots.sort_custom(func(x: Vector3, y: Vector3) -> bool: return x.length() < y.length())
	return PackedVector3Array(slots)


## 圆台上的猫 meme 跟拍跳（每帧调）：每拍蹦一下、落地压扁、动图跟着拍子放；玩家按键时一起多蹦一下
func _update_plaza_cats(beat: float) -> void:
	for c in _plaza_cats:
		var b: float = beat + c.phase
		var hop := absf(sin(b * PI))  # 每拍落地一次
		var land := pow(1.0 - hop, 4.0)  # 刚落地那一下
		var sprite: Sprite3D = c.sprite
		sprite.frame = mini(int(fposmod(b / plaza_meme_loop_beats, 1.0) * c.frames), c.frames - 1)
		sprite.position.y = hop * plaza_meme_hop + _press * plaza_press_hop
		var sq := plaza_meme_squash * land
		sprite.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0)


## 结尾镜头开始时，猫 meme 一只只缩没
func _dismiss_plaza_cats() -> void:
	for i in _plaza_cats.size():
		var holder: Node3D = _plaza_cats[i].holder
		var t := holder.create_tween()
		t.tween_property(holder, "scale", Vector3.ZERO, 0.5).set_delay(i * 0.03) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_callback(holder.queue_free)
	_plaza_cats.clear()
