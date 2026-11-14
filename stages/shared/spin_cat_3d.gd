class_name KisaSpinCat3D
extends Node2D
## 3D 转圈猫：把 3D 猫模型放进一个透明背景的 SubViewport，画到 2D 画面上。
## 按一下绕竖轴快速转一圈，按住一直转，松手马上回到正面停下。
## 对外接口和 SpinCat 一样：spin() / set_held()，信号 spin_started / spin_finished。
## 不用骨骼动画，只转整个模型。
## 测试用，只在本机 _sandbox 里，不进仓库。

signal spin_started
signal spin_finished

## 猫模型（fbx / glb 导入后的场景）
@export var model: PackedScene = preload("res://stages/shared/cat/CATS.fbx")
## 显示高度（像素）
@export var height := 260.0
## 模型摆正用：先把模型转成正面朝向镜头（度）
@export var model_rotation_degrees := Vector3.ZERO
## 旋转轴心相对模型包围盒中心挪多少（模型自己的坐标，+z = 猫脸朝的方向）
@export var pivot_offset := Vector3(0.0, 0.0, 1.2)
## 背景小屋（不跟着猫转，地板顶面要在 y = 0）；留空 = 只有猫
@export var backdrop: PackedScene = preload("res://stages/shared/iso_room.tscn")
## 镜头俯视角度（度，0 = 平视，89 ≈ 正上方；35.26 = 标准 isometric）
@export_range(-89.0, 89.0) var camera_pitch := 35.26
## 镜头水平方向转多少度（45 = 标准 isometric，猫平时斜对镜头；0 = 正对猫脸）
@export_range(-180.0, 180.0) var camera_yaw := 45.0
## 画面留白：1 = 刚好塞满
@export_range(0.8, 2.0) var frame_margin := 1.05
## 铺满整个屏幕当关卡场景（节点要放在屏幕中心；这时 height / render_size 不起作用）
@export var full_screen := false
## 铺满屏幕时小屋外面的底色
@export var background_color := Color(0.98, 0.86, 0.78)
## 渲染分辨率（正方形边长，像素）
@export var render_size := 1024

@export_group("旋转")
## 单点：转一圈用几秒
@export_range(0.05, 3.0) var spin_time := 0.225
## 按住：第一圈之后每一圈用几秒
@export_range(0.05, 3.0) var hold_spin_time := 0.45
## 松手后回到正面用几秒
@export_range(0.0, 0.5) var settle_time := 0.08
## 转的方向：1 = 从上往下看逆时针，-1 = 顺时针
@export var direction := 1.0

@export_group("输入")
@export var listen_input := true
## 项目里的打鼓键（Judge 运行时创建）。这个键位不存在时（比如单独测试）改听 fallback_key
@export var action := &"hit"
@export var fallback_key: Key = KEY_SPACE
## 按住时一直转
@export var hold_to_loop := true

@export_group("弹一下")
@export var pop_scale := 1.12
@export var pop_time := 0.12
@export var stop_pop_scale := 1.05

# ---- 给外面的「舞台」脚本用（只读）：想自己运镜、打灯、往 3D 世界里加东西时拿这些 ----
var world: SubViewport
var camera: Camera3D
var environment: Environment
var key_light: DirectionalLight3D
var backdrop_node: Node3D
## 镜头对准的点（猫的中心）
var focus := Vector3.ZERO
## 猫（转起来）在画面里占多高（3D 单位）
var cat_view_height := 0.0
# ---- 外面可以每帧改这三个，让猫离开原地、多转一个角度、歪一下（都叠加在按键转圈上） ----
## 猫离开原位多远（3D 单位）
var pose_position := Vector3.ZERO
## 额外的水平转角（弧度）
var pose_yaw := 0.0
## 前后 / 左右歪多少（弧度）
var pose_tilt := Vector2.ZERO

var _viewport: SubViewport
var _pivot: Node3D
var _sprite: Sprite2D
var _spinning := false
var _looping := false
var _t := 0.0
var _held := false
var _angle := 0.0  # 当前转角（弧度），0 = 正面
var _settle_tween: Tween
var _pop_tween: Tween


func _ready() -> void:
	_viewport = SubViewport.new()
	if full_screen:
		_viewport.size = Vector2i(get_viewport_rect().size)
	else:
		_viewport.size = Vector2i(render_size, render_size)
	_viewport.transparent_bg = not full_screen
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	world = _viewport

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	environment = env.environment
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = background_color
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	_viewport.add_child(env)

	var light := DirectionalLight3D.new()
	key_light = light
	light.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	light.light_energy = 1.2
	_viewport.add_child(light)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	var holder := Node3D.new()  # 用来把模型挪到旋转轴上
	_pivot.add_child(holder)
	var inst := model.instantiate() as Node3D
	inst.rotation_degrees = model_rotation_degrees
	# 不用骨骼动画：把蒙皮去掉，直接按静止姿势画（网页版 WebGL 上带骨骼的猫会画不出来）
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).skeleton = NodePath("")
		(mi as MeshInstance3D).skin = null
	holder.add_child(inst)

	# 量出模型大小：轴心 = 包围盒中心 + pivot_offset，脚踩在 y = 0
	var box := _measure(inst)
	var axis := box.get_center() + Vector3(pivot_offset.x, 0.0, pivot_offset.z)
	holder.position = Vector3(-axis.x, -box.position.y, -axis.z)
	# 转起来水平方向最远到哪（以轴心为圆心）
	var spin_radius := 0.0
	for i in 8:
		var c := box.get_endpoint(i) - axis
		spin_radius = maxf(spin_radius, Vector2(c.x, c.z).length())

	# 背景小屋：不跟着猫转，地板顶面在 y = 0
	var room_box := AABB()
	if backdrop:
		var room := backdrop.instantiate() as Node3D
		backdrop_node = room
		_viewport.add_child(room)
		room_box = _measure(room)

	# isometric 正交镜头，把猫（转起来当圆柱）和小屋都框进画面
	var pitch := deg_to_rad(camera_pitch)
	var cam_dir := Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, deg_to_rad(camera_yaw))
	var basis := Basis.looking_at(-cam_dir)
	var right := basis.x
	var up := basis.y
	var pts: Array[Vector3] = []
	for k in 16:
		var d := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 16.0) * spin_radius
		pts.append(d)
		pts.append(d + Vector3.UP * box.size.y)
	var cat_min := Vector2(INF, INF)
	var cat_max := -cat_min
	for p in pts:
		var q := Vector2(p.dot(right), p.dot(up))
		cat_min = cat_min.min(q)
		cat_max = cat_max.max(q)
	var all_min := cat_min
	var all_max := cat_max
	if backdrop:
		for i in 8:
			var p := room_box.get_endpoint(i)
			var q := Vector2(p.dot(right), p.dot(up))
			all_min = all_min.min(q)
			all_max = all_max.max(q)
	var cat_center := (cat_min + cat_max) / 2.0
	var cam := Camera3D.new()
	camera = cam
	cat_view_height = cat_max.y - cat_min.y
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 300.0
	_sprite = Sprite2D.new()
	_sprite.texture = _viewport.get_texture()
	if full_screen:
		# 铺满屏幕：镜头对准猫，画面大小刚好装下小屋，节点要放在屏幕中心
		var screen := get_viewport_rect().size
		var half := Vector2(maxf(all_max.x - cat_center.x, cat_center.x - all_min.x),
				maxf(all_max.y - cat_center.y, cat_center.y - all_min.y))
		cam.size = maxf(half.y * 2.0, half.x * 2.0 * screen.y / screen.x) * frame_margin
		var look_at_point := right * cat_center.x + up * cat_center.y
		cam.position = look_at_point + cam_dir * 100.0
		_viewport.add_child(cam)
		cam.look_at(look_at_point)
		focus = look_at_point
	else:
		var extent := maxf(all_max.x - all_min.x, all_max.y - all_min.y) * frame_margin
		var view_center := (all_min + all_max) / 2.0
		cam.size = extent
		var look_at_point := right * view_center.x + up * view_center.y
		cam.position = look_at_point + cam_dir * 100.0
		_viewport.add_child(cam)
		cam.look_at(look_at_point)
		focus = look_at_point
		# height 指猫在屏幕上的高度；节点位置 = 猫的中心（不是整张渲染图的中心）
		var px_per_unit := render_size / extent
		var cat_h_px := (cat_max.y - cat_min.y) * px_per_unit
		_sprite.scale = Vector2.ONE * (height / cat_h_px)
		_sprite.offset = Vector2(view_center.x - cat_center.x, cat_center.y - view_center.y) * px_per_unit
	add_child(_sprite)


## 转一圈。正在转的时候再调用，会从当前角度重新开始转一整圈
func spin() -> void:
	if _settle_tween:
		_settle_tween.kill()
	_angle = wrapf(_angle, -PI, PI)
	_spinning = true
	_looping = false
	_t = 0.0
	_start_angle = _angle
	spin_started.emit()
	_pop(pop_scale)


## 由外部控制「按住」状态（listen_input 关掉时用）
func set_held(held: bool) -> void:
	_held = held


var _start_angle := 0.0


func _input(event: InputEvent) -> void:
	if listen_input and _is_press(event):
		spin()


func _process(delta: float) -> void:
	if listen_input:
		_held = _is_input_held()
	if _spinning:
		if _looping and not _held:
			_stop(true)
		else:
			_t += delta
			if not _looping and _t >= spin_time:
				if hold_to_loop and _held:
					_looping = true
					_t -= spin_time
					_start_angle = 0.0
				else:
					_angle = 0.0
					_stop(false)
			if _spinning:
				if _looping:
					# 按住：匀速转
					_angle = fmod(_t / hold_spin_time, 1.0) * TAU
				else:
					# 单点：先快后慢地转满一圈，最后落回正面
					var p := _t / spin_time
					_angle = lerpf(_start_angle, TAU, 1.0 - pow(1.0 - p, 2.0))
	# 铺满屏幕时，窗口大小 / 比例变了就跟着变，免得边上露出后面的东西
	if full_screen and _viewport.size != Vector2i(get_viewport_rect().size):
		_viewport.size = Vector2i(get_viewport_rect().size)
	_pivot.position = pose_position
	_pivot.rotation = Vector3(pose_tilt.x, _angle * direction + pose_yaw, pose_tilt.y)


func _stop(settle: bool) -> void:
	_spinning = false
	_looping = false
	spin_finished.emit()
	if not settle:
		return
	# 松手：最短路径快速转回正面
	_angle = wrapf(_angle, -PI, PI)
	if _settle_tween:
		_settle_tween.kill()
	_settle_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_settle_tween.tween_property(self, "_angle", 0.0, settle_time)
	_pop(stop_pop_scale)


func _pop(amount: float) -> void:
	if _pop_tween:
		_pop_tween.kill()
	_pivot.scale = Vector3.ONE * amount
	_pop_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(_pivot, "scale", Vector3.ONE, pop_time)


## 模型所有网格合起来的包围盒（相对 holder）
func _measure(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var base := root.get_parent() as Node3D
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := _relative_xform(base, m)
		var b := xf * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _relative_xform(base: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != base:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _is_press(event: InputEvent) -> bool:
	if InputMap.has_action(action):
		return event.is_action_pressed(action)
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.physical_keycode == fallback_key


func _is_input_held() -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	return Input.is_physical_key_pressed(fallback_key)
