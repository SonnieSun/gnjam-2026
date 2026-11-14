@tool
class_name Spin3DSection
extends SpinSection
## 3D 关卡的基类：自带一个 3D 视口、摄像机和灯光，音符统一用“缩圈”显示在焦点位置。
## 判定、鼓声、星星、连击、编辑器预览都沿用 2D 关卡那一套，不用管。
##
## 子类只需要重写四个函数（对应原型里每个镜头的 grp / camera / focus / update）：
##   _build(root)             往 root 下面摆 3D 物体（只调用一次）
##   _camera_pose(p, t)       返回这一刻的机位 {"pos": Vector3, "look": Vector3, "roll": float}
##                            p = 这一段的进度 0→1，t = 一直在走的秒数
##   _focus()                 缩圈画在哪：返回一个 3D 世界坐标，基类会换算到屏幕上
##   _update_view(t)          每帧更新物体的姿态
## 转动用基类的 step_rot（打中才转一格）或 free_spin（一直转、打中被推一把），
## 打击感用 pulse()、hit_age。

## 3D 世界的背景色
@export var bg_color := Color(0.16, 0.09, 0.25)
## 判定圈的半径，占屏幕高度的比例
@export var ring_radius_ratio := 0.12
## 圆环从出现到重合用几拍
@export var approach_beats := 2.0
## 圆环刚出现时离判定圈多远，占屏幕高度的比例
@export var approach_travel_ratio := 0.35
## 打中时镜头往前推多少（0 = 不推）
@export var hit_push := 0.06
## 漏打时镜头抖多大（0 = 不抖）
@export var miss_shake := 0.15

## 3D 物体都挂在这下面
var world: Node3D
var camera: Camera3D

var _container: SubViewportContainer
var _viewport: SubViewport
var _overlay: Node2D
var _posed := false  # 摄像机摆好位置之前先不换算屏幕坐标


func _ready() -> void:
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true  # 每个关卡自己的 3D 世界，互不干扰
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.88, 0.94)
	env.ambient_light_energy = 0.75
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.near = 0.1
	camera.far = 200.0
	camera.environment = env
	_viewport.add_child(camera)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25
	_viewport.add_child(sun)
	sun.look_at_from_position(Vector3(3, 5, 4), Vector3.ZERO)

	world = Node3D.new()
	_viewport.add_child(world)
	_build(world)

	# 缩圈画在 3D 画面上面的一层
	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	_layout()


# ---- 子类重写这些 ----

func _build(_root: Node3D) -> void:
	pass


func _camera_pose(_p: float, _t: float) -> Dictionary:
	return {"pos": Vector3(0, 2, 8), "look": Vector3.ZERO, "roll": 0.0}


func _focus() -> Vector3:
	return Vector3.ZERO


func _update_view(_t: float) -> void:
	pass


# ---- 基类实现 ----

func hit_position(_note: NoteData = null) -> Vector2:
	if camera == null or not _posed or not camera.is_inside_tree():
		return Vector2.ZERO
	var size := _container.size
	var view_size := Vector2(_viewport.size)
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return Vector2.ZERO
	return camera.unproject_position(_focus()) / view_size * size - size / 2.0


func hit_radius() -> float:
	return ring_radius_ratio * screen_size().y


func _layout() -> void:
	var size := screen_size()
	_container.position = -size / 2.0
	_container.size = size


func _update_spin(_local_beat: float, _angle: float) -> void:
	center_on_screen()
	_layout()
	var t := Time.get_ticks_msec() / 1000.0
	_update_view(t)

	var pose := _camera_pose(progress(), t)
	var look: Vector3 = pose.get("look", Vector3.ZERO)
	var pos: Vector3 = pose.get("pos", Vector3(0, 2, 8))
	var roll: float = pose.get("roll", 0.0)
	pos = look + (pos - look) * (1.0 - pulse() * hit_push)  # 打中时往前推一下
	if miss_age < 0.25:
		var k := (1.0 - miss_age / 0.25) * miss_shake
		pos.x += randf_range(-0.5, 0.5) * k
		pos.y += randf_range(-0.5, 0.5) * k
	camera.look_at_from_position(pos, look, Vector3(sin(roll), cos(roll), 0.0))
	_posed = true
	_overlay.queue_redraw()


func _draw_overlay() -> void:
	if def == null:
		return
	draw_approach_rings(_overlay, hit_position(), hit_radius(), approach_beats,
			approach_travel_ratio * screen_size().y)
