@tool
extends Spin3DSection
## 披萨猫：猫坐着披萨贴着水面往前飞（云、玻璃环、光条、水纹都往后掠过去）。
## 一个小关里有三段画面，跟着积累条走：
##   第 1 段  镜头从侧面慢慢绕到正面（积累条 0 → 第 1 条事件线）
##   第 2 段  九宫格：同一个画面铺成 3×3（第 1 条 → 第 2 条事件线）
##   第 3 段  万花筒（第 2 条事件线 → 满条）
## 每拍 +5 分、每秒两拍，所以默认的 100 / 150 / 250 分正好是大约 10 秒 / 5 秒 / 10 秒；
## 想改每段多长，就改场景根节点“积累条”一栏里的满条值和事件分数线。
##
## 前两段的音符是真的 3D 圆环：从猫的正前方飞过来，和猫身上那个橙色的判定环重合时按键。
## 侧面看是一串排着队的椭圆，正面看就是从屏幕外往中心缩的圆。
## 万花筒那一段 3D 圆环会被折进花瓣里看不清，所以换成画在最上面的平面缩圈（和别的关一样）。
##
## 模型、材质、天空、水面都在场景 pizza.tscn 里，这里只负责运镜和动画。
## 九宫格 / 万花筒是 View 节点上的材质（assets/shaders/dream/mosaic_kaleido.gdshader）。

@export_group("运镜")
## 侧面机位离猫多远
@export var side_distance := 10.5
## 正面机位离猫多远
@export var front_distance := 8.5
## 侧面时镜头往猫的前方偏多少（让猫待在画面左边，给飞过来的圆环留地方）
@export var side_lead := 2.6
## 一开始的机位：0 = 正侧面（圆环会被看成一条线），稍微往正面偏一点才看得出是椭圆
@export_range(0.0, 60.0) var side_angle_deg := 22.0
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
@export_group("九宫格和万花筒")
## 九宫格每边几格
@export var grid_tiles := 3.0
## 万花筒每秒转多少（弧度）
@export var kaleido_speed := 0.35
## 万花筒里平面判定圈的半径，占屏幕高度的比例
@export var kaleido_ring_ratio := 0.2
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

var _phase := 0          # 0 = 转镜头，1 = 九宫格，2 = 万花筒
var _tiles := 1.0        # 现在铺到每边几格了
var _kaleido := 0.0      # 万花筒现在的浓度
var _flash := 0.0
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
	_update_phase(dt)

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
	var mat := _container.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("tiles", _tiles)
		mat.set_shader_parameter("kaleido", _kaleido)
		mat.set_shader_parameter("spin", t * kaleido_speed + step_rot * 0.25)
		mat.set_shader_parameter("flash", _flash)


## 现在该在第几段。正式运行时看已经触发了几个事件；编辑器预览里没有积累条，按进度推算。
func _wanted_phase() -> int:
	if not _previewing():
		return mini(gauge_events_fired, 2)
	var top := float(maxi(gauge_max_override, 1))
	var n := 0
	for v in gauge_events:
		if progress() * top >= v:
			n += 1
	return mini(n, 2)


func _update_phase(dt: float) -> void:
	var want := _wanted_phase()
	if want != _phase:
		if want > _phase or want == 0:
			_flash = 0.5
		_phase = want
	# 第 1 段里镜头跟着积累条从侧面绕到正面；之后一直是正面
	var first := 1.0
	var top := float(maxi(gauge_max if not _previewing() else gauge_max_override, 1))
	var lines := gauge_event_values if not _previewing() else gauge_events
	if lines.size() > 0:
		first = lines[0] / top
	_turn = 1.0 if _phase > 0 else clampf(progress() / maxf(first, 0.001), 0.0, 1.0)
	_tiles = lerpf(_tiles, grid_tiles if _phase == 1 else 1.0, minf(1.0, dt * 6.0))
	_kaleido = move_toward(_kaleido, 1.0 if _phase == 2 else 0.0, dt * 2.5)
	_flash = move_toward(_flash, 0.0, dt * 1.5)


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
	for n in notes:
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


## 万花筒里判定圈小一点，正好套住中间那只猫
func hit_radius() -> float:
	return (kaleido_ring_ratio if _phase == 2 else ring_radius_ratio) * screen_size().y


## 前两段音符是 3D 圆环，这里只画按键时的一圈闪光；万花筒那一段画平面缩圈
func _draw_overlay() -> void:
	if def == null:
		return
	if _phase == 2:
		draw_approach_rings(_overlay, hit_position(), hit_radius(), ring_beats,
				approach_travel_ratio * screen_size().y)
	elif tap_age < 0.15:
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
	var mat := _container.material as ShaderMaterial if _container else null
	if mat:
		mat.set_shader_parameter("tiles", 1.0)
		mat.set_shader_parameter("kaleido", 0.0)
		mat.set_shader_parameter("flash", 0.0)
	_phase = 0
	_tiles = 1.0
	_kaleido = 0.0
	_flash = 0.0
	_last_t = -1.0
