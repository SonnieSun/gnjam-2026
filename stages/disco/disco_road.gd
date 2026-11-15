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
@export var fruit_glow := 0.55
## 水果表面多光滑（越小越反光）、边缘光多强
@export_range(0.0, 1.0) var fruit_roughness := 0.12
@export_range(0.0, 1.0) var fruit_rim := 0.3
## 照水果的那盏灯（挂在猫前上方，给水果打出高光）：亮度、颜色
@export var fruit_light_energy := 0.9
@export var fruit_light_color := Color(1.0, 0.95, 0.9)

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
## 每拍视野「顶」一下的幅度（度）
@export var fov_punch := 2.5

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

@export_group("圆台上的猫 meme")
## MemeLib 里的名字，按出现的先后
@export var plaza_memes := PackedStringArray(["banana", "apple", "oiia", "nyan", "flower", "popcat", "nyanrun"])
## 每只出现在屏幕上哪里（相对屏幕中心，像素）和多高（像素），和 plaza_memes 一一对应
@export var plaza_meme_positions := PackedVector2Array([
	Vector2(-431, -74), Vector2(396, -4), Vector2(-167, -191), Vector2(113, -138),
	Vector2(-243, 213), Vector2(194, 238), Vector2(6, 256),
])
@export var plaza_meme_heights := PackedFloat32Array([160, 235, 130, 125, 170, 150, 130])
## 在圆台上打出第几个 Perfect 时出现第一只；之后每个 Perfect 再出一只
@export var plaza_meme_first_perfect := 2
## 每拍跳起来多高（像素）、动图放一遍用几拍
@export var plaza_meme_hop := 18.0
@export var plaza_meme_loop_beats := 2.0

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
var _plaza_perfects := 0
var _fruit_light: OmniLight3D
var _plaza_cats: Array[MemeSprite] = []
var _ball_scale := 1.0


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
func finale(seconds: float = 8.0) -> void:
	if phase == Phase.FINALE or phase == Phase.ROOM:
		return
	phase = Phase.FINALE
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
	ball.visible = ball.position.y < 45.0
	if phase == Phase.FINALE:
		ball.position.y += 20.0 * delta  # 给飞碟让位

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
func _update_fruits(beat: float, notes: Array[NoteData]) -> void:
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
		fruit.position = Vector3(_lane_of(n), fruit_height + sin(beat * PI + n.beat) * 0.3, -ahead * units_per_beat)
		fruit.rotation.y = beat * 1.5 + n.beat
	# 没打中、已经飞到身后的收掉
	for n: NoteData in _fruits.keys():
		if n.beat - beat < -1.5:
			(_fruits[n] as Node3D).queue_free()
			_fruits.erase(n)


func _make_fruit(n: NoteData) -> Node3D:
	var kind := (n.sound + (3 if roundi(n.beat) % 5 == 0 else 0)) % FRUITS.size()
	var fruit := FRUITS[kind].instantiate() as Node3D
	fruit.scale = Vector3.ONE * 1.3
	_cat.world.add_child(fruit)
	# 水果换成亮面反光的材质：很光滑 + 清漆高光 + 边缘光，再用自己的贴图微微发光（暗场景里颜色才鲜）
	for mi in fruit.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s) as StandardMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as StandardMaterial3D
			mat.emission_enabled = true
			mat.emission = Color.WHITE if src.albedo_texture else src.albedo_color
			mat.emission_texture = src.albedo_texture
			mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY  # 默认是相加，会把颜色冲白
			mat.emission_energy_multiplier = fruit_glow
			mat.roughness = fruit_roughness
			mat.metallic_specular = 0.9
			mat.clearcoat_enabled = true
			mat.clearcoat = 1.0
			mat.clearcoat_roughness = 0.08
			mat.rim_enabled = true
			mat.rim = fruit_rim
			mat.rim_tint = 1.0
			m.set_surface_override_material(s, mat)
	return fruit


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
	cam.fov = _mix("fov") - pulse * fov_punch * (1.0 if phase != Phase.UNFOLD else 0.0)
	cam.position = look + dir * _mix("dist")
	cam.look_at(look)


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


## 在圆台上打出一个 Perfect：攒够了就多出来一只猫 meme，站在周围跟着一起跳
func plaza_perfect() -> void:
	if phase != Phase.PLAZA:
		return
	_plaza_perfects += 1
	var i := _plaza_cats.size()
	if _plaza_perfects < plaza_meme_first_perfect + i or i >= plaza_memes.size():
		return
	if not MemeLib.has(plaza_memes[i]):
		return
	var h := plaza_meme_heights[i] if i < plaza_meme_heights.size() else 150.0
	var cat := MemeSprite.create(plaza_memes[i], h)
	cat.position = plaza_meme_positions[i] if i < plaza_meme_positions.size() else Vector2.ZERO
	cat.flip_h = cat.position.x > 0.0
	var full := cat.scale
	cat.scale = Vector2.ZERO
	_stage.add_child(cat)  # 舞台节点是 2D 的，原点在屏幕中心
	_plaza_cats.append(cat)
	cat.create_tween().tween_property(cat, "scale", full, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 圆台上的猫 meme 跟拍跳（每帧调）
func _update_plaza_cats(beat: float) -> void:
	for i in _plaza_cats.size():
		var cat := _plaza_cats[i]
		cat.set_progress(beat / plaza_meme_loop_beats + i * 0.3)
		cat.offset.y = -absf(sin((beat + i * 0.5) * PI)) * plaza_meme_hop / maxf(cat.scale.y, 0.01)


## 结尾镜头开始时，猫 meme 缩小淡出
func _dismiss_plaza_cats() -> void:
	for i in _plaza_cats.size():
		var cat := _plaza_cats[i]
		var t := cat.create_tween().set_parallel()
		t.tween_property(cat, "scale", Vector2.ZERO, 0.6).set_delay(i * 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(cat, "modulate:a", 0.0, 0.6).set_delay(i * 0.08)
		t.chain().tween_callback(cat.queue_free)
	_plaza_cats.clear()
