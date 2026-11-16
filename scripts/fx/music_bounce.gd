class_name MusicBounce
extends Node
## 跟着音乐 Q 弹：一个 3D 物体（默认是这一关的主角猫）不用玩家按键，也随着音乐里的鼓点和旋律压扁、弹起。
## 听的是 Music 的信号（drum_kick / drum_clap / lead_note，见 docs/music_manager.md「画面跟着音乐的信号」），
## 所以鼓型换了（半拍 / 四拍 / club / 碎拍）弹法自然跟着变；预备拍和过门里鼓停了，它也跟着停。
##
## 用法：放进小关的场景里当子节点。target 空着 = 找父节点下面的转圈猫（KisaSpinCat3D）；也可以指到任何 Node3D。
## 做法：弹簧。每一下给它一个往下的速度（先压扁），弹簧把它拉回来、冲过头（拉长），再停住。体积大致不变
## （压扁时变宽）。作用在物体和它的子节点之间插进去的一层上，不改物体自己的 scale，所以和别的缩放动画不打架。

## 总开关
@export var enabled := true
@export_group("跟什么")
## 底鼓那一下（鼓型里底鼓的位置）压多深；0 = 不跟
@export var kick := 1.0
## 拍手那一下；0 = 不跟
@export var clap := 0.6
## 旋律的每个音轻轻点一下；0 = 不跟。长音（一拍以上）点得重一点
@export var note := 0.0
## 节奏轨没在响（或者这一关没有鼓型数据）时改成每拍弹一下；0 = 不弹
@export var beat_fallback := 0.5
@export_group("弹法")
## 一下最多压扁多少（0.2 = 矮 20%）
@export_range(0.0, 0.6) var squash := 0.16
## 弹回来有多快（越大越硬、越快）
@export var stiffness := 420.0
## 晃几下停（越小晃得越久，果冻感越强）
@export var damping := 16.0
## 弹起来时离地多高（3D 单位；0 = 不离地）
@export var hop := 0.12
@export_group("")
@export var target: NodePath

var _joint: Node3D   # 插在物体和它的子节点之间的那一层
var _x := 0.0        # 现在的形变：负 = 压扁，正 = 拉长
var _v := 0.0


func _ready() -> void:
	Music.drum_kick.connect(func(b: float) -> void: _drum(b, kick))
	Music.drum_clap.connect(func(b: float) -> void: _drum(b, clap))
	Music.lead_note.connect(func(_b: float, _midi: int, length: float) -> void: _hit(note * (1.0 if length >= 1.0 else 0.6)))
	Conductor.beat.connect(_on_beat)


func _drum(_beat: float, strength: float) -> void:
	_hit(strength)


func _on_beat(index: int) -> void:
	# 节奏轨没在响，或者这段鼓没有鼓型数据：改成每拍弹一下（预备拍那一小节鼓只是让开，不算，猫跟着停）
	if beat_fallback > 0.0 and index >= 0 and Music.events.groove_of(Music.playing_clip("beat")) == "":
		_hit(beat_fallback)


## 弹一下（strength：1 = 压到 squash 那么深）。别的脚本也可以直接调。
func _hit(strength: float) -> void:
	if not enabled or strength <= 0.0:
		return
	# 给一个往下的速度：无阻尼时最深处 = v / sqrt(k)，按它反推（阻尼会吃掉一些，够用）
	_v = minf(_v, 0.0) - strength * squash * sqrt(stiffness) * 1.6


func _find() -> void:
	var node: Node = get_node_or_null(target) if not target.is_empty() else null
	if node == null:
		for c in get_parent().get_children():
			if c is KisaSpinCat3D:
				node = (c as KisaSpinCat3D).get("_pivot")   # 猫绕着转的那个节点：脚在它的原点上
	if not (node is Node3D) or node.get_child_count() == 0:
		return
	_joint = Node3D.new()
	_joint.name = "MusicBounce"
	var kids := node.get_children()
	node.add_child(_joint)
	for k in kids:
		k.reparent(_joint, false)


func _process(delta: float) -> void:
	if not is_instance_valid(_joint):
		_find()
		if not is_instance_valid(_joint):
			return
	# 半隐式欧拉，步子切小一点，卡一帧也不会炸
	var steps := maxi(1, ceili(delta / 0.008))
	var h := delta / steps
	for i in steps:
		_v += (-stiffness * _x - damping * _v) * h
		_x += _v * h
	_x = clampf(_x, -0.6, 0.6)
	var y := 1.0 + _x
	var wide := 1.0 / sqrt(maxf(y, 0.3))
	_joint.scale = Vector3(wide, y, wide) if enabled else Vector3.ONE
	_joint.position.y = maxf(_x, 0.0) / maxf(squash, 0.01) * hop if enabled else 0.0
