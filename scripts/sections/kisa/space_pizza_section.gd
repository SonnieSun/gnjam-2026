@tool
extends "res://scripts/sections/pizza_section.gd"
## 太空版披萨猫（第 3 大关第二段）：玩法完全沿用 Sonnie 的披萨猫关（过圈 → 九宫格 → 万花筒），
## 这里只多做一件事——从上一段「太空打飞机」无缝接过来：
## 开头镜头不是直接出现在猫前方，而是从打飞机结束时的机位（猫背后上方）绕到猫前方，
## 同时用上一帧画面盖一下再淡掉，遮住框架切小关时的白闪。
## 上一段留下的机位在 SpaceShooterScore.handoff 里；没有（比如直接跳到这一段）就和原来的披萨猫关一样。

## 镜头从打飞机的机位绕到猫前方用几拍
@export var handoff_beats := 8.0
## 盖住切关白闪的那一帧画面：先完全盖住多少秒，再用多少秒淡掉
@export var cover_hold := 0.12
@export var cover_fade := 0.3

var _from := {}
var _to_fov := 45.0


func _on_enter() -> void:
	super._on_enter()
	if Engine.is_editor_hint() or camera == null:
		return
	_beat_decor()
	_from = SpaceShooterScore.handoff
	SpaceShooterScore.handoff = {}
	if _from.is_empty():
		return
	_to_fov = camera.fov
	camera.fov = _from.get("fov", _to_fov)
	# 上一帧画面盖在最上面，慢慢淡掉
	var layer := CanvasLayer.new()
	layer.layer = 100
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	add_child(layer)
	var tw := rect.create_tween()
	tw.tween_interval(cover_hold)
	tw.tween_property(rect, "modulate:a", 0.0, cover_fade)
	tw.tween_callback(layer.queue_free)


## 接力进度：0 = 还在打飞机的机位，1 = 已经到了披萨猫关自己的机位
func _handoff_k() -> float:
	if _from.is_empty():
		return 1.0
	return smoothstep(0.0, 1.0, clampf(local_beat() / maxf(handoff_beats, 0.01), 0.0, 1.0))


func _camera_pose(p: float, t: float) -> Dictionary:
	var pose := super._camera_pose(p, t)
	var k := _handoff_k()
	if k >= 1.0:
		return pose
	# 打飞机那边猫朝 -Z、这边猫朝 +Z，所以把那边的机位绕竖轴转 180° 搬过来（都是相对猫的位置）
	var from_pos: Vector3 = _from.pos
	var from_look: Vector3 = _from.look
	from_pos = Vector3(-from_pos.x, from_pos.y, -from_pos.z)
	from_look = Vector3(-from_look.x, from_look.y, -from_look.z)
	var to_pos: Vector3 = pose.pos
	var to_look: Vector3 = pose.look
	var look := from_look.lerp(to_look, k)
	# 绕着猫转过去（不是直线穿过去）
	var arm := (from_pos - from_look).slerp(to_pos - to_look, k)
	return {"pos": look + arm, "look": look, "roll": 0.0}


func _update_view(t: float) -> void:
	super._update_view(t)
	if not _from.is_empty():
		camera.fov = lerpf(_from.get("fov", _to_fov), _to_fov, _handoff_k())


## 装饰跟拍（BeatFx，见 stages/shared/beat_fx）：光环的砖一块接一块胀过去；光球的芯各用各的节奏，灯跟底鼓。
## 光球 / 气泡 / 云本身每帧被这一关挪位置，所以接在它们里面的零件上。披萨、猫、判定圈是主体，不接。
var _decor_done := false

func _beat_decor() -> void:
	if _decor_done:
		return
	_decor_done = true
	BeatDecor.wave(_halo.get_children(), 0.2, 2.0)
	var k := 0
	for orb in _orbs.get_children():
		k += 1
		var core := orb.get_node_or_null("Core")
		if core:
			BeatDecor.stagger(core, k * 3, 0.25)  # 每个光球的芯用不同的节奏
		var lamp := orb.get_node_or_null("Light")
		if lamp:
			BeatDecor.light(lamp, 0.9)

