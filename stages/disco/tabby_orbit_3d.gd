class_name TabbyOrbit3D
extends Node3D
## 一圈发光转圈猫（TabbySpinCat）在 3D 场景里绕着主角飞，转法照 MemeOrbit3D：圈可以歪着（tilt），
## 每拍半径弹一下，玩家按键推一把，FEVER 更快。每只随机毛色、随机发光色，按键时各自惯性猛转、越转越亮、歪着晃。
## 放进猫所在的那个 3D 世界（KisaSpinCat3D.world），center 每帧由外面更新成猫的位置。

const CAT_SCENE := preload("res://stages/shared/tabby_cat/tabby_spin_cat.tscn")

var count := 8
## 圈多大、每只多高（3D 单位）
var radius := 3.0
var item_height := 1.0
## 圈歪多少度（0 = 平着绕，90 = 竖着绕），绕哪个方向歪
var tilt := 25.0
var tilt_yaw := 0.0
## 每拍转几圈（负数 = 反着转）
var turns_per_beat := 0.06
## 圈的中心比 center 高多少
var lift := 0.0
## 每拍半径弹多少（比例）、按键推多少圈
var beat_pulse := 0.12
var hit_push := 0.06
var fever_speed := 2.5

var center := Vector3.ZERO
var _angle := 0.0
var _push := 0.0
var _fever := false
var _cats: Array[TabbySpinCat] = []
var _cat_scale := 1.0
var _grow := 0.0


func _ready() -> void:
	for i in count:
		var c := CAT_SCENE.instantiate() as TabbySpinCat
		c.ensure_scene_glow = false  # 迪斯科的 3D 世界自己已经开了 Glow
		c.listen_input = false       # 猫在 SubViewport 里收不到按键，由这里统一读
		add_child(c)
		c.rotation.y = randf() * TAU
		_cats.append(c)
	if not _cats.is_empty():
		_cat_scale = item_height / maxf(_model_height(_cats[0]), 0.001)
	if has_node("/root/Music"):
		var music: Node = get_node("/root/Music")
		music.fever_started.connect(func(): _fever = true)
		music.fever_ended.connect(func(): _fever = false)
		_fever = music.fever
	create_tween().tween_property(self, "_grow", 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 缩回去再消失
func leave() -> void:
	var t := create_tween()
	t.tween_property(self, "_grow", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


# 模型多高（按包围盒量，缩放 1 时）
func _model_height(c: Node3D) -> float:
	var box := AABB()
	var first := true
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := (c.global_transform.affine_inverse() * m.global_transform) * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.size.y


func _process(delta: float) -> void:
	if _cats.is_empty():
		return
	if InputMap.has_action(&"hit") and Input.is_action_just_pressed(&"hit"):
		_push += hit_push
		for c in _cats:
			c.spin()
	var beat: float = Conductor.song_beat
	var bpm: float = Conductor.chart.bpm if Conductor.get("chart") else 120.0
	var bps := bpm / 60.0
	var speed := turns_per_beat * bps * (fever_speed if _fever else 1.0)
	_angle += (speed * delta + _push * minf(delta * 8.0, 1.0)) * TAU
	_push -= _push * minf(delta * 8.0, 1.0)
	var pulse := exp(-fposmod(beat, 1.0) * 5.0) * beat_pulse
	var r := radius * (1.0 + pulse) * _grow
	var basis := Basis(Vector3.RIGHT, deg_to_rad(tilt)).rotated(Vector3.UP, deg_to_rad(tilt_yaw))
	for i in _cats.size():
		var a := _angle + TAU * i / _cats.size()
		var c := _cats[i]
		# 猫脚底在圈上，往下挪半个身高让圈穿过猫的中间
		c.position = center + Vector3.UP * (lift - item_height * 0.5) + basis * (Vector3(cos(a), 0.0, sin(a)) * r)
		c.scale = Vector3.ONE * _cat_scale * maxf(_grow, 0.01) * (1.0 + pulse)
