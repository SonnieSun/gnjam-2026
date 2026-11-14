@tool
extends Spin3DSection
## MV 镜头 6 · 飞碟：外星猫坐着飞碟在宇宙里飞，飞碟一直自转，每打中一下多转一截、往前冲一下。
## 模型都在场景 mv_ufo.tscn 里，这里只负责运镜和动画。

const STAR_LOOP := 100.0  # 星星飞过这么远就绕回去（Stars 下面两份星星前后正好隔这么远）

@onready var _stars: Node3D = %Stars
@onready var _planet: Node3D = %Planet
@onready var _saucer: Node3D = %Saucer
@onready var _pilot: Node3D = %Pilot
@onready var _lights: Node3D = %Lights
@onready var _beam: MeshInstance3D = %Beam

var _star_offset := 0.0
var _last_t := -1.0
var _drift := Vector3.ZERO  # 飞碟这一刻飘到了哪
var _roll := 0.0            # 飞碟这一刻歪了多少
var _beam_alpha := -1.0     # 光束在场景里设的透明度


func _camera_pose(_p: float, t: float) -> Dictionary:
	var a := sin(t * 0.5) * 0.6
	return {
		"pos": Vector3(_drift.x * 0.6 + sin(a) * 7.5, _drift.y * 0.6 + 2.2, cos(a) * 7.5),
		"look": Vector3(_drift.x * 0.8, _drift.y * 0.8 + 0.3, 0.0),
		"roll": -_roll * 0.8,
	}


func _update_view(t: float) -> void:
	var dt := 0.0 if _last_t < 0.0 else minf(t - _last_t, 0.05)
	_last_t = t
	# 星星往镜头飞过来 = 飞碟在往前飞；打中时加速
	_star_offset = fmod(_star_offset + (18.0 + pulse() * 60.0) * dt, STAR_LOOP)
	_stars.transform = rest(_stars).translated(Vector3(0.0, 0.0, _star_offset))
	_planet.transform = rest(_planet).translated(Vector3(0.0, 0.0, fmod(t * 6.0, 80.0)))  # 远处的星球慢慢飘过来

	_drift = Vector3(sin(t * 0.7) * 1.6, sin(t * 1.1) * 0.7, 0.0)
	_roll = -cos(t * 0.7) * 0.35 + pulse() * 0.15  # 跟着左右飘倾斜
	var pose := rest(_saucer).translated(_drift)
	pose.basis = pose.basis * Basis.from_euler(Vector3(0.0, step_rot * 1.2 + t * 1.5, _roll), EULER_ORDER_XYZ)
	_saucer.transform = pose
	_pilot.transform = rest(_pilot).rotated_local(Vector3.UP, step_rot * 1.5)
	_lights.transform = rest(_lights).rotated_local(Vector3.UP, step_rot * 2.0 + t)

	var mat := _beam.material_override as StandardMaterial3D
	if mat:
		if _beam_alpha < 0.0:
			_beam_alpha = mat.albedo_color.a
		mat.albedo_color.a = _beam_alpha + pulse() * 0.25


func _on_restore() -> void:
	var mat := _beam.material_override as StandardMaterial3D
	if mat and _beam_alpha >= 0.0:
		mat.albedo_color.a = _beam_alpha
	_beam_alpha = -1.0
