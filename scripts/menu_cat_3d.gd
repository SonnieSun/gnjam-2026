@tool
extends Node3D
## 将原菜单的猫爪 Tween 和点头状态映射到 CATS_Scratch 的骨骼。
## 固定同一只前爪打碟，左右拨盘使用原始抓挠动画的两个方向姿势。

const SCRATCH := &"ARM-CATS-Scratch|ACT-CATS-LeftPaw-Scratch"

## 编辑骨骼时关闭；查看菜单的单爪姿势时开启。运行游戏不受此开关影响。
@export var preview_pose := true
## 三个姿势均来自原始抓挠动画；只对打碟这只前爪做混合。
@export_range(0.0, 2.0) var idle_pose_time := 0.0
@export_range(0.0, 2.0) var scratch_right_time := 0.4
@export_range(0.0, 2.0) var scratch_left_time := 1.2
## 猫的身体已朝唱片前倾，头部只需要小幅补偿。
@export var head_rest_pitch := -0.15
@export var head_nod_angle := 0.045
@export var scratch_contact: Node3D
@export var support_contact: Node3D
@export var scratch_width := 0.3

@onready var _skeleton: Skeleton3D = $"Model/ARM-CATS-Scratch/Skeleton3D"
@onready var _mesh: MeshInstance3D = $"Model/ARM-CATS-Scratch/Skeleton3D/GEO-CATS"
@onready var _player: AnimationPlayer = $Model/AnimationPlayer

var _arm_controller: Node2D
var _head_controller: Node2D
var _arm_rest := 0.0
var _head_rest_y := 0.0
var _arm_swing := 0.45
var _direction := 1.0
var _head_bone := -1
var _base_poses: Array[Transform3D] = []
var _idle_poses: Array[Transform3D] = []
var _scratch_right: Array[Transform3D] = []
var _scratch_left: Array[Transform3D] = []
var _scratch_bones: Array[int] = []
var _support_bones: Array[int] = []
var _paw_bases: Array[Basis] = []


func _ready() -> void:
	_head_bone = _skeleton.find_bone("head")
	for part in ["fore_upper", "fore_lower", "fore_paw"]:
		_scratch_bones.append(_skeleton.find_bone(part + ".L"))
		_support_bones.append(_skeleton.find_bone(part + ".R"))
	_base_poses = _read_poses()
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.play(SCRATCH)
	_idle_poses = _sample_pose(idle_pose_time)
	_scratch_right = _sample_pose(scratch_right_time)
	_scratch_left = _sample_pose(scratch_left_time)
	_write_poses(_idle_poses)
	for bone in [_scratch_bones[2], _support_bones[2]]:
		_paw_bases.append(_skeleton.get_bone_global_pose(bone).basis)


func bind_controllers(arm: Node2D, head: Node2D) -> void:
	_arm_controller = arm
	_head_controller = head
	if is_instance_valid(arm):
		_arm_rest = arm.rotation
		if not Engine.is_editor_hint():
			_arm_swing = maxf(absf(float(arm.owner.get("arm_swing"))), 0.001)
	if is_instance_valid(head):
		_head_rest_y = head.position.y


func _read_poses() -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for i in _skeleton.get_bone_count():
		poses.append(_skeleton.get_bone_pose(i))
	return poses


func _write_poses(poses: Array[Transform3D]) -> void:
	for i in poses.size():
		_skeleton.set_bone_pose(i, poses[i])


func _sample_pose(seconds: float) -> Array[Transform3D]:
	_write_poses(_base_poses)
	_player.seek(seconds, true)
	return _read_poses()


func _aim_segment(bone: int, child: int, target: Vector3) -> void:
	var pose := _skeleton.get_bone_global_pose(bone)
	var current := _skeleton.get_bone_global_pose(child).origin - pose.origin
	var desired := target - pose.origin
	if current.length_squared() < 0.00000001 or desired.length_squared() < 0.00000001:
		return
	pose.basis = Basis(Quaternion(current.normalized(), desired.normalized())) * pose.basis
	# 两段前臂的子骨骼都沿局部 Y 轴延伸，伸缩该轴以保持爪子贴住碟面。
	pose.basis.y *= desired.length() / current.length()
	_skeleton.set_bone_global_pose(bone, pose)


func _place_paw(bones: Array[int], target: Vector3, outward: float, basis: Basis) -> void:
	var shoulder := _skeleton.to_global(_skeleton.get_bone_global_pose(bones[0]).origin)
	var elbow := shoulder.lerp(target, 0.5) + Vector3(outward, 0.06, -0.03)
	_aim_segment(bones[0], bones[1], _skeleton.to_local(elbow))
	_aim_segment(bones[1], bones[2], _skeleton.to_local(target))
	var paw := _skeleton.get_bone_global_pose(bones[2])
	paw.origin = _skeleton.to_local(target)
	paw.basis = basis
	_skeleton.set_bone_global_pose(bones[2], paw)


func _process(_delta: float) -> void:
	if _idle_poses.is_empty():
		return
	if Engine.is_editor_hint() and not preview_pose:
		return
	var strength := 0.0
	if is_instance_valid(_arm_controller):
		var offset := _arm_controller.rotation - _arm_rest
		strength = clampf(absf(offset) / _arm_swing, 0.0, 1.0)
		if absf(offset) > 0.0001:
			_direction = -signf(offset)
	_write_poses(_idle_poses)
	var target := _scratch_right if _direction > 0.0 else _scratch_left
	for i in _scratch_bones:
		_skeleton.set_bone_pose(i, _idle_poses[i].interpolate_with(target[i], strength))
	if is_instance_valid(scratch_contact):
		var contact := scratch_contact.global_position + Vector3.RIGHT * (_direction * strength * scratch_width)
		_place_paw(_scratch_bones, contact, 0.08, _paw_bases[0])
	if is_instance_valid(support_contact):
		_place_paw(_support_bones, support_contact.global_position, -0.08, _paw_bases[1])
	var nod := 0.0
	if is_instance_valid(_head_controller):
		nod = (_head_controller.position.y - _head_rest_y) / 3.0
	var pose_rotation := _skeleton.get_bone_pose_rotation(_head_bone)
	_skeleton.set_bone_pose_rotation(_head_bone,
			pose_rotation * Quaternion(Vector3.RIGHT, head_rest_pitch + nod * head_nod_angle))
