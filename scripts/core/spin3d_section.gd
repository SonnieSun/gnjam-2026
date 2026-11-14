@tool
class_name Spin3DSection
extends SpinSection
## 3D 关卡的基类。模型、材质、灯光、背景色都直接放在场景里，美术可以在编辑器里随便调；
## 脚本只负责“让它们动起来”。音符统一用“缩圈”显示在焦点位置。
## 判定、鼓声、星星、连击、编辑器预览都沿用 2D 关卡那一套，不用管。
##
## 场景里需要有这些节点（名字要一致，复制一个现成的 mv_*.tscn 改最省事）：
##   View (SubViewportContainer)
##     Viewport (SubViewport)
##       Camera (Camera3D)        背景色在它的 Environment 里改；位置由脚本运镜，手动摆了也会被盖掉
##       Sun (DirectionalLight3D)
##       World (Node3D)           模型都放在这下面，在编辑器的 3D 视图里摆
##         ...Focus (Marker3D，勾上“作为唯一名称访问”)   缩圈跟着它走，挂在谁下面就跟着谁
##
## 子类重写两个函数：
##   _camera_pose(p, t)   返回这一刻的机位 {"pos": Vector3, "look": Vector3, "roll": float}
##                        p = 这一段的进度 0→1，t = 一直在走的秒数
##   _update_view(t)      每帧让物体动起来。动画要写成“在摆好的姿势上叠加”：
##                        node.transform = rest(node).rotated_local(Vector3.UP, 角度)
##                        这样美术在场景里把东西挪到哪，动画就在哪做。
## 转动用基类的 step_rot（打中才转一格）或 free_spin（一直转、打中被推一把），
## 打击感用 pulse()、hit_age。
##
## 编辑器里：勾着“预览播放”时模型会动；想摆东西先取消勾选，模型会回到摆好的姿势。
## 保存场景时会自动先回到摆好的姿势，不会把动到一半的样子存进去。

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
var _focus_node: Node3D
var _posed := false  # 摄像机摆好位置之前先不换算屏幕坐标
var _rest := {}      # 节点 -> 场景里摆好的姿势


func _ready() -> void:
	_container = get_node_or_null("View")
	_viewport = get_node_or_null("View/Viewport")
	camera = get_node_or_null("View/Viewport/Camera")
	world = get_node_or_null("View/Viewport/World")
	_focus_node = get_node_or_null("%Focus")
	if camera == null or world == null:
		push_error("%s：3D 关卡场景里缺少 View/Viewport/Camera 或 World 节点" % name)
		return
	if not Engine.is_editor_hint():
		# 运行时每个关卡用自己的 3D 世界，两关同时在场也互不干扰。
		# （场景文件里没勾这一项，是为了在编辑器的 3D 视图里能直接看到、摆弄模型。）
		_viewport.own_world_3d = true
		camera.current = true
	# 缩圈画在 3D 画面上面的一层
	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	_layout()


# ---- 子类重写这些 ----

func _camera_pose(_p: float, _t: float) -> Dictionary:
	return {"pos": Vector3(0, 2, 8), "look": Vector3.ZERO, "roll": 0.0}


## 缩圈画在哪（3D 世界坐标）。默认跟着场景里叫 Focus 的节点。
func _focus() -> Vector3:
	return _focus_node.global_position if _focus_node else Vector3.ZERO


func _update_view(_t: float) -> void:
	pass


## 回到摆好的姿势时调用（除了位置姿态之外还改了别的东西，比如材质透明度，在这里改回去）
func _on_restore() -> void:
	pass


# ---- 给子类用的工具 ----

## 这个节点在场景里摆好的姿势。动画都在它的基础上叠加，不要直接写死位置。
func rest(node: Node3D) -> Transform3D:
	if not _rest.has(node):
		_rest[node] = node.transform
	return _rest[node]


## 让猫原地迈步：speed 越大腿摆得越快，amp 是摆动幅度。
## cat 下面要有 LegFrontL / LegFrontR / LegBackL / LegBackR 四个节点。
func walk(cat: Node3D, speed: float, amp: float = 0.6) -> void:
	var t := Time.get_ticks_msec() / 1000.0 * speed
	for i in CatBuilder.LEG_NAMES.size():
		var leg := cat.get_node_or_null(CatBuilder.LEG_NAMES[i]) as Node3D
		if leg:
			leg.transform = rest(leg).rotated_local(Vector3.BACK, sin(t + (0.0 if (i == 0 or i == 3) else PI)) * amp)


## 所有动过的节点回到场景里摆好的姿势
func restore_rest() -> void:
	for node: Node3D in _rest:
		if is_instance_valid(node):
			node.transform = _rest[node]
	_rest.clear()
	_on_restore()


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
	if camera == null or world == null:
		return
	center_on_screen()
	_layout()
	# 编辑器里没勾“预览播放”时不动模型，方便摆东西
	if Engine.is_editor_hint() and not preview_playing:
		if not _rest.is_empty():
			restore_rest()
		_overlay.queue_redraw()
		return
	var t := Time.get_ticks_msec() / 1000.0
	_update_view(t)

	rest(camera)  # 摄像机也记下来，保存场景时回到原位
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


func _notification(what: int) -> void:
	# 保存场景之前先回到摆好的姿势，免得把动到一半的样子存进文件
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		restore_rest()


func _draw_overlay() -> void:
	if def == null:
		return
	draw_approach_rings(_overlay, hit_position(), hit_radius(), approach_beats,
			approach_travel_ratio * screen_size().y)
