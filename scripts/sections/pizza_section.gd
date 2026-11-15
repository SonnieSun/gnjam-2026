@tool
extends Spin3DSection
## 披萨猫：猫坐着披萨贴着水面往前飞（云、玻璃环、光条、水纹都往后掠过去）。
## 镜头跟着积累条从侧面慢慢绕到正面（进度到 turn_until 时正好转到正面）。
## 九宫格、万花筒这些全屏镜头特效不在这里做了：它们是通用的（scripts/fx/screen_fx.gd），
## 什么进度切到哪个特效，在游戏里按 Tab 调出的面板上排，存在大关 .tres 里这个小关的 fx_cues。
##
## 音符是真的 3D 圆环：从猫的正前方飞过来，和猫身上那个橙色的判定环重合时按键。
## 侧面看是一串排着队的椭圆，正面看就是从屏幕外往中心缩的圆。
## 套上万花筒特效时 3D 圆环会被折进花瓣里看不清，这时把它们藏起来，由特效层在最上面画平面缩圈。
##
## 模型、材质、天空、水面都在场景 pizza.tscn 里，这里只负责运镜和动画。

@export_group("运镜")
## 侧面机位离猫多远
@export var side_distance := 10.5
## 正面机位离猫多远
@export var front_distance := 8.5
## 侧面时镜头往猫的前方偏多少（让猫待在画面左边，给飞过来的圆环留地方）
@export var side_lead := 2.6
## 一开始的机位：0 = 正侧面（圆环会被看成一条线），稍微往正面偏一点才看得出是椭圆
@export_range(0.0, 60.0) var side_angle_deg := 22.0
## 积累条进度到多少（0-1）时镜头正好转到正面
@export_range(0.05, 1.0) var turn_until := 0.4
## 机位比判定环高多少
@export var camera_height := 0.5
@export_group("音符圆环")
## 圆环提前几拍出现
@export var ring_beats := 3.0
## 圆环刚出现时离判定环多远
@export var ring_travel := 6.5
@export_group("往前飞")
## 飞得多快（每秒多少米）。云、玻璃环、水纹按这个速度往后退
@export var fly_speed := 9.0
## 打中时额外冲一下的速度
@export var fly_boost := 14.0
## 光条比别的东西快几倍
@export var streak_factor := 3.0
## 东西从猫前方多远的地方冒出来 / 退到猫身后多远就绕回前面
@export var loop_front := 20.0
@export var loop_back := 54.0
## 猫的动作（模型自带的动画名）；一个小节做一遍
@export var cat_animation := "ARM-CATS-Scratch|ACT-CATS-LeftPaw-Scratch"
@export_group("")

@onready var _pizza: Node3D = %Pizza
@onready var _cat: Node3D = %Cat
@onready var _orbs: Node3D = %Orbs
@onready var _streaks: Node3D = %Streaks
@onready var _halo: Node3D = %Halo
@onready var _bubbles: Node3D = %Bubbles
@onready var _clouds: Node3D = %Clouds
@onready var _hit_ring: Node3D = %HitRing
@onready var _rings: Node3D = %Rings
@onready var _sky: MeshInstance3D = %SkyDome
@onready var _water: MeshInstance3D = %Water

var _phase := 0          # 2 = 套着万花筒（3D 圆环要藏起来），其余是 0
var _turn := 0.0         # 镜头从侧面到正面转了多少（0 → 1）
var _last_t := -1.0
var _dist := 0.0         # 已经往前飞了多远
var _anim: AnimationPlayer


func _camera_pose(_p: float, t: float) -> Dictionary:
	var focus := _focus()
	var k := smoothstep(0.0, 1.0, _turn)
	var a := lerpf(deg_to_rad(side_angle_deg), PI / 2.0, k)  # 0 = 正侧面，90° = 正前方
	var dist := lerpf(side_distance, front_distance, k)
	var look := focus + Vector3(0.0, 0.0, side_lead * (1.0 - k))
	var sway := sin(t * 0.6) * 0.25 * (1.0 - k)
	return {
		"pos": look + Vector3(-cos(a) * dist, camera_height * (1.0 - k) + sway, sin(a) * dist),
		"look": look,
		"roll": 0.0,
	}


func _update_view(t: float) -> void:
	var dt := 0.0 if _last_t < 0.0 else minf(t - _last_t, 0.05)
	_last_t = t
	_phase = 2 if screen_fx == "kaleido" else 0
	_turn = clampf(progress() / turn_until, 0.0, 1.0)

	# 往前飞：猫和披萨不动，别的东西往后退（-z），退到身后就绕回前面
	_dist += (fly_speed + pulse() * fly_boost) * dt
	_stream(_clouds, 1.0, t, 0.3)
	_stream(_bubbles, 1.0, t, 0.0)
	_stream(_orbs, 1.0, t, 0.4)
	_stream(_streaks, streak_factor, t, 0.0)
	_set_param(_water, "scroll", _dist)

	# 披萨像飞盘一样转着飞，机头微微下压、左右轻轻侧倾；每打中一下多转一格
	var bob := sin(t * 1.4) * 0.08
	var bank := sin(t * 0.9) * 0.1
	var lean := Basis.from_euler(Vector3(0.1 + pulse() * 0.08, 0.0, bank))
	var ride := Transform3D(lean, Vector3(0.0, bob, 0.0))
	_pizza.transform = ride * rest(_pizza).rotated_local(Vector3.UP, step_rot * 0.5 + t * 0.6)
	_cat.transform = ride * rest(_cat).translated_local(Vector3(0.0, -pulse() * 0.05, 0.0)) \
			.scaled_local(Vector3(1.0 + pulse() * 0.05, 1.0 - pulse() * 0.07, 1.0 + pulse() * 0.05))
	_play_cat()
	_halo.transform = rest(_halo).rotated_local(Vector3.UP, t * 0.5 + step_rot * 0.6)

	# 判定环：打中时弹一下
	_hit_ring.transform = rest(_hit_ring).scaled_local(Vector3.ONE * (1.0 + pulse() * 0.12))
	_hit_ring.visible = _phase != 2
	_place_rings()

	_set_param(_sky, "boost", 1.0 + pulse() * 0.2)
	_set_param(_water, "boost", pulse())

## parent 下面的东西按“飞了多远 × factor”往后退，退到身后 loop_back 就绕回前面；wobble = 顺便上下飘多少
func _stream(parent: Node3D, factor: float, t: float, wobble: float) -> void:
	var span := loop_front + loop_back
	for i in parent.get_child_count():
		var node := parent.get_child(i) as Node3D
		var pose := rest(node)
		pose.origin.z = loop_front - fposmod(loop_front - pose.origin.z + _dist * factor, span)
		pose.origin.y += sin(t * 0.5 + i * 1.7) * wobble
		node.transform = pose


## 猫的动作跟着拍子走：一个小节（4 拍）做一遍
func _play_cat() -> void:
	if _anim == null:
		_anim = _cat.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null or not _anim.has_animation(cat_animation):
		return
	if _anim.assigned_animation != cat_animation:
		_anim.play(cat_animation)
		_anim.pause()
	var length := _anim.get_animation(cat_animation).length
	_anim.seek(fposmod(local_beat() / 4.0, 1.0) * length, true)


## 把快到的音符一个个摆到飞过来的圆环上；用不上的圆环藏起来。万花筒那一段全部藏起来。
func _place_rings() -> void:
	var used := 0
	var count := _rings.get_child_count() if _phase != 2 else 0
	for n in own_notes():
		if used >= count:
			break
		if n.judged:
			continue
		var ahead := beats_until(n)
		if ahead > ring_beats:
			break
		var k := clampf(ahead / ring_beats, 0.0, 1.0)
		var ring := _rings.get_child(used) as Node3D
		var pose := rest(ring)
		pose.origin = Vector3(0.0, 0.0, k * ring_travel)
		ring.transform = pose
		ring.visible = true
		used += 1
	for i in range(used, _rings.get_child_count()):
		var ring := _rings.get_child(i) as Node3D
		rest(ring)
		ring.visible = false


func _set_param(mesh: MeshInstance3D, param: StringName, value: Variant) -> void:
	var mat := mesh.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter(param, value)


## 音符是 3D 圆环，这里只画按键时的一圈闪光（万花筒里的平面缩圈由特效层画）
func _draw_overlay() -> void:
	if def == null or _phase == 2:
		return
	# 节拍辅助线：围着判定点收过来（3D 圆环各走各的路，这里给一个统一的「第几拍该按」）
	draw_lit_target(_overlay, hit_position(), hit_radius(), Color(1, 1, 1, 0.5), 2.0)
	draw_target_guides(_overlay, hit_position(), hit_radius(), 0.32 * screen_size().y, ring_beats)
	if tap_age >= 0.15:
		return
	_overlay.draw_arc(hit_position(), hit_radius() * (1.0 + tap_age), 0.0, TAU, 64,
			Color(1, 1, 1, 1.0 - tap_age / 0.15), 6.0)


func _on_restore() -> void:
	if _rings:
		for ring: Node3D in _rings.get_children():
			ring.visible = true
	if _hit_ring:
		_hit_ring.visible = true
	if _anim and _anim.has_animation(cat_animation):
		_anim.seek(0.0, true)
	_dist = 0.0
	_set_param(_water, "scroll", 0.0)
	_set_param(_sky, "boost", 1.0)
	_set_param(_water, "boost", 0.0)
	_phase = 0
	_last_t = -1.0
