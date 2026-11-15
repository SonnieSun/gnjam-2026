class_name BeatGlow
extends Node
## 通用的「跟着拍子发光 + 胀缩」效果（原来是迪斯科路上水果专用的，抽出来谁都能用）。
## 加到任何节点下面当子节点就生效，作用在父节点上：
##   3D（Node3D）：父节点下所有模型换成用自己贴图发光的材质（可选亮面反光：很光滑 + 清漆高光 + 边缘光），
##                 每拍亮一下；
##   2D（Node2D / Control）：每拍把 modulate 提亮一下。
##   两种都会每拍胀一下，玩家按键时再额外胀一下。
## 拍子读 Conductor.song_beat，永远和音乐对齐。
##
## 用法：
##   场景里：选中要发光的节点 → 加一个 Node 子节点 → 挂这个脚本，在检查器里调参数。
##   代码里：BeatGlow.attach(fruit, {"glow": 1.3, "scale_pulse": 0.4})  （第二个参数可省）
## 注意：它每帧会改父节点的 scale（以加进来那一刻的 scale 为基准）。父节点自己还想做缩放动画的话，
##       包一层：动画做在外面那层，BeatGlow 挂在里面那层。

@export_group("发光")
## 平时自己发多亮（暗场景里也看得清）；3D 才有，2D 不用
@export var glow := 1.3
## 每拍再亮多少（3D 加在 glow 上；2D 是 modulate 提亮的比例）
@export var glow_pulse := 0.9
## 3D：顺便换成亮面反光的材质（很光滑 + 清漆高光 + 边缘光）
@export var glossy := true
@export_range(0.0, 1.0) var roughness := 0.12
@export_range(0.0, 1.0) var rim := 0.3

@export_group("胀缩")
## 每拍胀大多少（0.4 = 拍点上大 40%）
@export var scale_pulse := 0.4
## 玩家按键时额外胀多少，多久缩回去（秒）
@export var press_pop := 0.8
@export var press_seconds := 0.3

@export_group("节奏")
## 几拍闪一次（1 = 每拍，0.5 = 每半拍，2 = 每两拍）
@export var every_beats := 1.0
## 错开多少拍（一排东西各错一点，看起来像波浪）
@export var beat_offset := 0.0
## 闪完掉下来有多快（越大越“啪”一下就灭）
@export_range(1.0, 8.0) var sharpness := 3.0

## 现在这一拍亮到哪（0~1），别的效果想跟着同步可以读
var pulse := 0.0

var _target: Node
var _base_scale: Variant
var _base_modulate := Color.WHITE
var _mats: Array[StandardMaterial3D] = []
var _press := 0.0


## 给 node 加上这个效果。config 里的键就是上面那些参数名，在加进场景树之前设好（材质要在加进来时就换好）。
static func attach(node: Node, config: Dictionary = {}) -> BeatGlow:
	var g := BeatGlow.new()
	for key: String in config:
		g.set(key, config[key])
	node.add_child(g)
	return g


func _ready() -> void:
	Judge.ensure_input()
	_target = get_parent()
	if _target is Node3D:
		_base_scale = (_target as Node3D).scale
		_make_materials(_target)
	elif _target is Node2D:
		_base_scale = (_target as Node2D).scale
	elif _target is Control:
		_base_scale = (_target as Control).scale
	if _target is CanvasItem:
		_base_modulate = (_target as CanvasItem).modulate


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(Judge.HIT_ACTION):
		_press = 1.0


func _process(delta: float) -> void:
	if _target == null:
		return
	var b := (Conductor.song_beat - beat_offset) / maxf(every_beats, 0.01)
	pulse = pow(1.0 - fposmod(b, 1.0), sharpness)
	_press = maxf(_press - delta / maxf(press_seconds, 0.01), 0.0)
	var s := 1.0 + pulse * scale_pulse + _press * press_pop
	if _target is Node3D:
		(_target as Node3D).scale = _base_scale * s
		for mat in _mats:
			mat.emission_energy_multiplier = glow + pulse * glow_pulse
	elif _base_scale != null:
		_target.scale = _base_scale * s
	if _target is CanvasItem:
		var k := 1.0 + pulse * glow_pulse * 0.5
		(_target as CanvasItem).modulate = Color(_base_modulate.r * k, _base_modulate.g * k, _base_modulate.b * k, _base_modulate.a)


## 父节点下所有模型的材质复制一份，换成用自己的贴图发光（相乘，不会把颜色冲白）
func _make_materials(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as StandardMaterial3D
			mat.emission_enabled = true
			mat.emission = Color.WHITE if src.albedo_texture else src.albedo_color
			mat.emission_texture = src.albedo_texture
			mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY  # 默认是相加，会把颜色冲白
			mat.emission_energy_multiplier = glow
			if glossy:
				mat.roughness = roughness
				mat.metallic_specular = 0.9
				mat.clearcoat_enabled = true
				mat.clearcoat = 1.0
				mat.clearcoat_roughness = 0.08
				mat.rim_enabled = true
				mat.rim = rim
				mat.rim_tint = 1.0
			m.set_surface_override_material(s, mat)
			_mats.append(mat)
