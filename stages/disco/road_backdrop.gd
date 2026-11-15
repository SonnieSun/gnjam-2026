class_name RoadBackdrop
extends Node3D
## 迪斯科上路撞水果那一段的背景：远处一道斜着的彩虹 + 路两边飘着的描边几何体，都跟着音乐动。
## 东西都摆在 road_backdrop.tscn 里（彩虹是 Rainbow 节点，几何体是 Shapes 下面的 WireShape），
## 想加一个几何体就在 Shapes 下面再放一个；这里只管淡入淡出和跟拍子转。

## 彩虹平时多亮、每拍再亮多少
@export var rainbow_strength := 0.6
@export var rainbow_pulse := 0.25
## 几何体多亮
@export_range(0.0, 1.0) var shape_strength := 0.9
## 几何体的大小随机多少：每次进这一段，每个在自己大小的基础上随机放大缩小这么多（0.4 = 0.6 到 1.4 倍）
@export_range(0.0, 0.9) var size_random := 0.4
## 玩家按键时几何体胀一下的幅度也随机一点（1 ± 这么多）
@export_range(0.0, 1.0) var kick_random := 0.5
## 按键用的动作名
@export var action := &"hit"

## 整体显示多少 0-1（外面用 show_up / hide_away 淡入淡出）
var amount := 0.0

var _rainbow_mat: ShaderMaterial
var _shapes: Array[WireShape] = []


func _ready() -> void:
	var rainbow := get_node_or_null("Rainbow") as MeshInstance3D
	if rainbow:
		_rainbow_mat = rainbow.material_override as ShaderMaterial
	for n in find_children("*", "MeshInstance3D", true, false):
		if n is WireShape:
			n.scale *= randf_range(1.0 - size_random, 1.0 + size_random)
			_shapes.append(n)
	update(0.0)


func show_up(seconds: float = 2.0) -> void:
	create_tween().tween_property(self, "amount", 1.0, seconds)


func hide_away(seconds: float = 1.5) -> void:
	create_tween().tween_property(self, "amount", 0.0, seconds)


## 玩家按了一下：所有几何体转一整圈、胀一下
func _input(event: InputEvent) -> void:
	if amount > 0.5 and event.is_action_pressed(action):
		for s in _shapes:
			s.kick(randf_range(1.0 - kick_random, 1.0 + kick_random))


## 每帧调用
func update(beat: float) -> void:
	visible = amount > 0.001
	if not visible:
		return
	var pulse := pow(1.0 - fposmod(beat, 1.0), 3.0)
	if _rainbow_mat:
		_rainbow_mat.set_shader_parameter("strength", (rainbow_strength + pulse * rainbow_pulse) * amount)
		_rainbow_mat.set_shader_parameter("beat", beat)
	for s in _shapes:
		s.strength = shape_strength * amount
		s.animate(beat, get_process_delta_time())
