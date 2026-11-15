class_name SpaceStage
extends Node
## 飞船关卡的 3D 舞台：星空往后飞、行星飞过来 / 被撞飞 / 撞上飞船、判定圈、电影感镜头。
## 不管判定，只听 SpaceshipSection 说「这颗打中了 / 这颗没打中」。
##
## 两种视角，按小节来回切（时间表在「视角切换」里调）：
## - 冲刺：镜头追在飞船斜后上方，行星从正前方飞来，飞进飞船前面竖着的判定圈。
## - 太阳系：镜头升到正上方往下看，飞船在中心，周围一圈圈轨道；行星先沿轨道绕，
##   再往里收，撞到飞船外面平躺的判定圈。
## 切换时镜头一边绕一边升高 / 降低，判定圈和行星路线也一起平滑过渡；从太阳系回到冲刺时加速冲一下。
##
## 坐标约定：飞船朝 -Z 飞（其实飞船不动，是星星往 +Z 走），猫站在原点，脚踩 y = 0。
##
## 分阶段推进（预留的口子，现在没有任何阶段演出）：
## - add_success() / add_miss() 改进度，进度到 stage_at 里的门槛就换阶段，发 stage_changed。
## - 下面带「每阶段」的数组按阶段取值（数组比阶段少就一直用最后一个）；
##   要加新演出，接 stage_changed 信号或者在 _enter_stage 里加。

signal stage_changed(stage: int)
## 视角切换开始时发：solar = true 是开始升到太阳系，false 是开始回到冲刺
signal view_changed(solar: bool)

@export_group("阶段（进度到多少时进入下一阶段；空 = 只有第 0 阶段）")
@export var stage_at := PackedInt32Array()

@export_group("视角切换（按小节循环：冲刺 -> 太阳系 -> 冲刺 ...）")
## 冲刺持续几小节（包括过渡）
@export var dash_bars := 8
## 太阳系持续几小节（包括过渡）
@export var solar_bars := 8
## 抬升 / 俯冲过渡用几拍（在各自那段的最后几拍进行）
@export var transition_beats := 6.0
## 过渡时镜头顺带绕飞船转多少度
@export var transition_orbit_degrees := 120.0
## 从太阳系回到冲刺时，星星加速多少倍（冲刺感）
@export var dash_boost := 2.0
## 回到冲刺时视野放大多少度
@export var dash_boost_fov := 14.0
## 加速冲刺持续几拍
@export var dash_boost_beats := 4.0

@export_group("冲刺：判定点和行星")
## 判定点（判定圈中心），相对猫脚下
@export var hit_point := Vector3(0.0, 1.8, -7.5)
## 判定圈半径（3D 单位）
@export var ring_radius := 2.6
@export var ring_color := Color(1.0, 1.0, 1.0)
## 行星从多远的地方出发（沿 -Z）
@export var spawn_distance := 140.0
## 行星出发点左右 / 上下随机偏多少，飞过来时会斜着收进判定圈
@export var spawn_spread := Vector2(26.0, 14.0)
## 被撞飞：初速度（x 会随机朝左或朝右）
@export var knock_velocity := Vector3(26.0, 12.0, -30.0)

@export_group("太阳系")
## 镜头在多高的地方往下看
@export var solar_height := 52.0
## 行星在离飞碟中心多远的地方撞上（飞碟外缘）。太阳系里飞碟外面不显示判定圈
@export var solar_ring_radius := 8.5
## 行星所在的高度
@export var solar_plane_y := 1.5
## 各条轨道的半径，行星随机停在其中一条上
@export var orbit_radii := PackedFloat32Array([16.0, 20.0, 24.0])
@export var orbit_color := Color(0.6, 0.75, 1.0, 0.35)
## ① 飞出去：从离中心多远的地方出发
@export var launch_radius := 7.0
## ① 飞出去：用几拍飞到轨道上（之后停住，直到冲刺）
@export var out_beats := 1.5
## ③ 冲过来：最后几拍超高速直线冲向飞碟
@export var charge_beats := 0.25
## ② 停住时抖动多大（越接近冲刺抖得越厉害）
@export var aim_shake := 0.35
## 行星身上的收缩圈：停住那一刻多大（3D 单位），缩到 0 拍时正好贴住行星
@export var shrink_start_radius := 6.0
@export var shrink_color := Color(1.0, 0.88, 0.4)
## 收缩圈多粗（相对圈半径的比例）
@export var shrink_thickness := 0.09
## 索敌线：只给「下一颗要撞过来」的行星画一条虚线指向飞碟（关掉 = 不画）
@export var aim_line := true
@export var aim_line_color := Color(1.0, 0.35, 0.42)
@export var aim_line_width := 0.45
## 虚线每段多长、间隔多长（3D 单位）
@export var aim_dash := Vector2(1.4, 0.9)
## 太阳系里飞行速度的倍数（星星往下流的速度）
@export var solar_speed_scale := 0.5
## 被撞飞：往外甩的速度
@export var solar_knock_speed := 34.0

@export_group("行星")
## 行星半径范围
@export var planet_radius := Vector2(1.5, 2.1)
@export var planet_colors: Array[Color] = [
	Color(1.0, 0.55, 0.3), Color(0.55, 0.75, 1.0), Color(0.75, 0.5, 1.0),
	Color(0.45, 0.95, 0.65), Color(1.0, 0.8, 0.35), Color(1.0, 0.5, 0.7),
]
## 有几成行星带土星环
@export_range(0.0, 1.0) var planet_ring_chance := 0.35
## 行星模型（本体半径 1、原点在中心）。不为空时随机挑一个代替代码做的球，也不再随机加环
@export var planet_models: Array[PackedScene] = []
## 每个模型对应的彗星尾巴颜色（和 planet_models 一一对应，缺的用 planet_colors）
@export var planet_model_colors: Array[Color] = []
## 模型行星自发光多少（星空很暗，贴图本身颜色提一点亮）
@export_range(0.0, 2.0) var planet_model_glow := 0.35
## 模型行星粗糙度（越大越哑光，反射的星云越少）
@export_range(0.0, 1.0) var planet_model_roughness := 0.9
## 被撞飞后多久消失（秒）
@export var knock_time := 1.2
## 没打中：行星从判定点继续撞到飞船要多久（拍）
@export var crash_beats := 0.25
## 彗星尾巴：记多少个点、拖多长（秒）、多粗（0 个点 = 不要尾巴）
@export var trail_points := 16
@export var trail_seconds := 0.35
@export var trail_width := 1.0

@export_group("星空")
@export var star_count := 700
## 星星分布的范围（宽 / 高 / 深）
@export var star_box := Vector3(170.0, 90.0, 260.0)
## 星星高度范围（太阳系镜头在上面往下看，星星要在镜头下面）
@export var star_y_range := Vector2(-60.0, 30.0)
## 飞行速度（3D 单位 / 拍）
@export var fly_speed := 40.0
## 每拍速度顶一下（倍数，0 = 不顶）
@export var beat_speed_punch := 0.6
## 星星拉成多长的线（随速度变长）
@export var star_streak := 0.08
@export var space_color := Color(0.03, 0.02, 0.08)

@export_group("运镜")
@export_range(20.0, 100.0) var fov := 62.0
## 冲刺：镜头离对准点多远（近 / 远），在两者之间来回推拉
@export var near_distance := 12.0
@export var far_distance := 22.0
## 推近再拉远一个来回多少拍
@export var dolly_beats := 16.0
## 太阳系：高度跟着推拉变化多少比例
@export var solar_dolly := 0.12
## 冲刺：镜头对准哪里（相对猫脚下）
@export var look_target := Vector3(0.0, 1.5, -3.0)
## 冲刺：镜头仰角（度，越大越俯视）
@export_range(-30.0, 80.0) var camera_pitch := 18.0
## 冲刺：镜头偏到飞船哪一侧（度，0 = 正后方）
@export_range(-90.0, 90.0) var camera_yaw := 24.0
## 每阶段：每拍顶一下（往前推的比例）
@export var beat_punch := PackedFloat32Array([0.05])
## 每阶段：左右摇摆幅度（度）
@export var sway_degrees := PackedFloat32Array([10.0])
@export var sway_beats := 8.0
## 每阶段：歪头幅度（度）
@export var roll_degrees := PackedFloat32Array([4.0])
@export var roll_beats := 4.0
## 打中时镜头往前冲一下（比例）
@export var hit_kick := 0.06
## 撞上飞船时镜头抖多大（3D 单位）
@export var crash_shake := 0.8

@export_group("天空盒（等距柱状全景图）")
## 全景图，留空 = 纯色背景（space_color）。原图 7680×3840 在 FBX 里，这里用缩小的 1024×512（显存压缩）
@export var sky_texture: Texture2D = preload("res://stages/spaceship/skybox/nebula_1024.png")
## 天空亮度（调暗一点，免得抢了行星和猫）
@export var sky_energy := 0.7
## 太阳系俯视时天空亮度（星云正好铺在下面，压暗一点让行星和收缩圈更清楚）
@export var sky_solar_energy := 0.45
## 冲刺时天空转到哪个方向（度），决定正前方看到星云的哪一块
@export var sky_yaw_degrees := 0.0
## 太阳系俯视时天空往下翻多少度，让星云铺在镜头下面（0 = 不翻，俯视时会看到全景图的极点）
@export var sky_solar_pitch_degrees := 90.0
## 天空每拍慢慢转多少度（给一点飞行感，0 = 不转）
@export var sky_drift_degrees := 0.15

@export_group("飞船晃动")
@export var ship_bob := 0.35
@export var ship_bob_beats := 2.0
## 跟着镜头摇摆往一边侧倾（度）
@export var ship_bank_degrees := 7.0
## 尾焰每拍变长多少（倍数）
@export var flame_punch := 0.5

## 当前进度和阶段（只读）
var progress := 0
var stage := 0
## 现在有多「太阳系」（0 = 冲刺，1 = 太阳系，过渡时在中间，只读）
var solar_weight := 0.0

var _cat: KisaSpinCat3D
var _ship: Node3D
var _flames: Node3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _ring_now := 2.6  # 判定圈现在的半径
var _orbits: Array[MeshInstance3D] = []
var _orbit_mat: StandardMaterial3D
var _trail_mat: StandardMaterial3D
var _aim: MeshInstance3D  # 索敌线（ImmediateMesh，每帧重画）
var _stars: MultiMeshInstance3D
var _star_pos := PackedVector3Array()
var _planets := {}  # NoteData -> Dictionary（node / start / orbit / ...）
var _flying: Array[Dictionary] = []  # 被撞飞 / 撞上的行星，自己动到消失
var _last_beat := 0.0
var _clock := 0.0  # 舞台自己的时钟（秒），用帧间隔累加
var _kick := 0.0
var _shake := 0.0
var _boost := 0.0
var _was_solar := false
var _flash_tween: Tween
var _ring_tint := Color.WHITE  # 判定圈现在的颜色（打中 / Miss 时闪一下再变回 ring_color）


func setup(cat: KisaSpinCat3D) -> void:
	_cat = cat
	_ship = cat.backdrop_node
	_flames = _ship.get_node_or_null("Flames")
	_ring_now = ring_radius

	var cam := cat.camera
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = fov
	cam.far = spawn_distance + star_box.z

	var env := cat.environment
	env.background_color = space_color
	if sky_texture:
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = sky_texture
		env.sky = Sky.new()
		env.sky.sky_material = mat
		# 天空只算一次环境反射（最小尺寸），之后不再改天空材质，免得每帧重算
		env.sky.radiance_size = Sky.RADIANCE_SIZE_32
		env.background_mode = Environment.BG_SKY
		env.background_energy_multiplier = sky_energy
	env.ambient_light_color = Color(0.7, 0.75, 1.0)
	env.ambient_light_energy = 0.45
	env.glow_enabled = true
	env.glow_intensity = 0.7
	cat.key_light.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	cat.key_light.light_energy = 1.1

	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_make_ring()
	_make_orbits()
	_make_stars()
	_aim = MeshInstance3D.new()
	_aim.mesh = ImmediateMesh.new()
	_aim.material_override = _trail_mat  # 同样是顶点色 + 透明 + 不受光
	_cat.world.add_child(_aim)


## 判定成功（Perfect / Good）
func add_success() -> void:
	_set_progress(progress + 1)


func add_miss() -> void:
	_set_progress(maxi(progress - 1, 0))


## 每帧调用：beat = 当前歌曲拍数；notes = 本段音符；approach_beats = 行星提前几拍出现
func update(beat: float, notes: Array[NoteData], approach_beats: float) -> void:
	var dt := clampf(get_process_delta_time(), 0.0, 0.1)
	_clock += dt
	var beat_dt := clampf(beat - _last_beat, 0.0, 1.0)
	_last_beat = beat
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-dt * 8.0))
	_shake = lerpf(_shake, 0.0, 1.0 - exp(-dt * 6.0))

	_update_view(beat)
	# 天空：冲刺时星云在前方；俯视时整片往下翻，铺在镜头下面；平时慢慢转
	_cat.environment.sky_rotation = Vector3(deg_to_rad(sky_solar_pitch_degrees) * solar_weight,
			deg_to_rad(sky_yaw_degrees + beat * sky_drift_degrees), 0.0)
	# 亮度用背景倍率调（只影响画面背景，不会触发天空重算）
	_cat.environment.background_energy_multiplier = lerpf(sky_energy, sky_solar_energy, solar_weight)
	var pulse := exp(-fposmod(beat, 1.0) * 5.0)  # 每拍开头 = 1，之后很快落回 0
	var speed := lerpf(1.0, solar_speed_scale, solar_weight) * (1.0 + pulse * beat_speed_punch) \
			* (1.0 + _boost * (dash_boost - 1.0))
	_update_stars(beat_dt, speed)
	_update_ring(pulse)
	_update_planets(beat, notes, approach_beats)
	_update_flying(dt)
	_update_ship(beat, pulse)
	_apply_camera(beat, pulse)


## 这颗打中了：从现在的位置被撞飞
func knock(note: NoteData, result: int) -> void:
	_kick = hit_kick
	_flash_ring(SpinSection.result_color(result))
	var p: Dictionary = _planets.get(note, {})
	if p.is_empty():
		return
	_planets.erase(note)
	_free_shrink(p)
	var node: Node3D = p.node
	# 冲刺：往左或往右前方甩；太阳系：从中心往外甩（原路弹回去）
	var side := 1.0 if (int(note.beat * 4.0) % 2 == 0) else -1.0
	var dash_v := Vector3(knock_velocity.x * side, knock_velocity.y, knock_velocity.z)
	var out := Vector3(node.position.x, 0.0, node.position.z).normalized()
	var solar_v := out * solar_knock_speed + Vector3.UP * 6.0
	p.velocity = dash_v.lerp(solar_v, solar_weight)
	p.gravity = lerpf(9.0, 0.0, solar_weight)
	p.age = 0.0
	p.life = knock_time
	p.spin_speed = 14.0
	_flying.append(p)


## 这颗没打中：继续往前撞上飞船
func crash(note: NoteData) -> void:
	_flash_ring(SpinSection.result_color(NoteData.Result.MISS))
	var p: Dictionary = _planets.get(note, {})
	if p.is_empty():
		return
	_planets.erase(note)
	_free_shrink(p)
	var node: Node3D = p.node
	var sec := crash_beats * Conductor.sec_per_beat()
	p.velocity = (Vector3(0.0, 1.0, 0.0) - node.position) / maxf(sec, 0.01)
	p.age = 0.0
	p.life = sec
	p.crash = true
	p.spin_speed = 4.0
	_flying.append(p)


## 判定点在 2D 屏幕上相对屏幕中心的位置（给命中特效用）。
## 太阳系里没有判定圈，返回刚被撞到的那颗行星的位置
func hit_screen_offset() -> Vector2:
	var p := _ring.position
	if solar_weight > 0.5:
		var nearest: Variant = _nearest_planet()
		if nearest != null:
			p = nearest
	return _to_screen(p)


## 判定圈在屏幕上大概多大（像素）。太阳系里圈很大，特效用一个小半径
func ring_screen_radius() -> float:
	var right := _cat.camera.global_transform.basis.x
	var r := lerpf(_ring_now, 1.5, solar_weight)
	return (_to_screen(_ring.position + right * r) - _to_screen(_ring.position)).length()


func _to_screen(p: Vector3) -> Vector2:
	var cam := _cat.camera
	if cam.is_position_behind(p):
		return Vector2.ZERO
	return cam.unproject_position(p) - Vector2(_cat.world.size) / 2.0


func _nearest_planet() -> Variant:
	var best: Variant = null
	var best_d := INF
	for p: Dictionary in _planets.values():
		var pos: Vector3 = (p.node as Node3D).position
		var d := pos.length()
		if d < best_d:
			best_d = d
			best = pos
	for p in _flying:
		if p.age < 0.05:
			return (p.node as Node3D).position
	return best


# ---- 阶段 ----

func _set_progress(value: int) -> void:
	progress = value
	var s := 0
	for threshold in stage_at:
		if progress >= threshold:
			s += 1
	if s != stage:
		stage = s
		_enter_stage(s)
		stage_changed.emit(s)


## 进入某个阶段时的演出（现在没有，以后加在这里或者接 stage_changed）
func _enter_stage(_which: int) -> void:
	pass


func _by_stage(values: PackedFloat32Array) -> float:
	return values[mini(stage, values.size() - 1)] if values.size() > 0 else 0.0


# ---- 视角切换 ----

## 按时间表算出 solar_weight（平滑过渡），以及回到冲刺时的加速
func _update_view(beat: float) -> void:
	solar_weight = _solar_weight_at(beat)
	var rising := _solar_weight_at(beat + 0.01) > solar_weight
	var falling := _solar_weight_at(beat + 0.01) < solar_weight
	if rising and not _was_solar:
		_was_solar = true
		view_changed.emit(true)
	elif falling and _was_solar:
		_was_solar = false
		view_changed.emit(false)
	# 加速：从回到冲刺的那一刻起，持续 dash_boost_beats 拍慢慢消退
	var since := _beats_since_dash_start(beat)
	_boost = 0.0 if since < 0.0 else clampf(1.0 - since / maxf(dash_boost_beats, 0.01), 0.0, 1.0)
	_boost *= _boost


func _cycle_beats() -> float:
	return float((dash_bars + solar_bars) * _beats_per_bar())


func _beats_per_bar() -> int:
	return Conductor.chart.beats_per_bar if Conductor.chart else 4


## 0 = 冲刺，1 = 太阳系。冲刺段最后 transition_beats 拍抬升，太阳系段最后 transition_beats 拍俯冲
func _solar_weight_at(beat: float) -> float:
	if solar_bars <= 0 or beat < 0.0:
		return 0.0
	var dash := float(dash_bars * _beats_per_bar())
	var cycle := _cycle_beats()
	var c := fposmod(beat, cycle)
	var t := maxf(transition_beats, 0.01)
	if c < dash - t:
		return 0.0
	if c < dash:
		return smoothstep(0.0, 1.0, (c - (dash - t)) / t)
	if c < cycle - t:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (c - (cycle - t)) / t)


## 离最近一次「俯冲完、回到冲刺」过了几拍（还没回到过冲刺 = -1）
func _beats_since_dash_start(beat: float) -> float:
	if solar_bars <= 0 or beat < _cycle_beats():
		return -1.0
	return fposmod(beat, _cycle_beats())


# ---- 判定圈和轨道 ----

func _make_ring() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = ring_radius - 0.12
	mesh.outer_radius = ring_radius + 0.12
	mesh.rings = 64
	mesh.ring_segments = 8
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = ring_color
	mesh.material = _ring_mat
	_ring = MeshInstance3D.new()
	_ring.mesh = mesh
	_cat.world.add_child(_ring)


## 判定圈在冲刺（竖着在飞船前面）和太阳系（平躺围着飞船）之间过渡
func _update_ring(pulse: float) -> void:
	var w := solar_weight
	_ring_now = lerpf(ring_radius, solar_ring_radius, w)
	var dash_q := Quaternion(Vector3.RIGHT, PI / 2.0)  # 圈面朝前后（对着飞来的行星）
	var q := dash_q.slerp(Quaternion.IDENTITY, w)
	var s := _ring_now / ring_radius * (1.0 + pulse * 0.06)
	_ring.basis = Basis(q).scaled(Vector3(s, lerpf(s, 1.0, w), s))
	_ring.position = hit_point.lerp(Vector3(0.0, solar_plane_y, 0.0), w)
	# 太阳系里不要飞碟外的判定圈，时机看行星身上的收缩圈
	_ring_mat.albedo_color = Color(_ring_tint, 1.0 - w)
	_ring.visible = w < 0.99
	_orbit_mat.albedo_color = Color(orbit_color, orbit_color.a * w)
	for o in _orbits:
		o.visible = w > 0.01
		o.position.y = solar_plane_y


func _make_orbits() -> void:
	_orbit_mat = StandardMaterial3D.new()
	_orbit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_orbit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_orbit_mat.albedo_color = orbit_color
	for r in orbit_radii:
		var mesh := TorusMesh.new()
		mesh.inner_radius = r - 0.12
		mesh.outer_radius = r + 0.12
		mesh.rings = 96
		mesh.ring_segments = 4
		mesh.material = _orbit_mat
		var o := MeshInstance3D.new()
		o.mesh = mesh
		o.visible = false
		_cat.world.add_child(o)
		_orbits.append(o)


func _flash_ring(c: Color) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_ring_tint = c
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "_ring_tint", ring_color, 0.3)


# ---- 星空 ----

func _make_stars() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.75)
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = star_count
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	_star_pos.resize(star_count)
	for i in star_count:
		var p := Vector3(rng.randf_range(-0.5, 0.5) * star_box.x, rng.randf_range(star_y_range.x, star_y_range.y),
				-rng.randf() * star_box.z + 40.0)
		# 别让星星穿过飞船和镜头附近
		if absf(p.x) < 14.0 and p.y > -8.0:
			p.x += signf(p.x + 0.01) * 14.0
		_star_pos[i] = p
	_stars = MultiMeshInstance3D.new()
	_stars.multimesh = mm
	_cat.world.add_child(_stars)


## beats = 这一帧过了几拍；boost = 速度倍数
func _update_stars(beats: float, boost: float) -> void:
	var move := fly_speed * boost * beats
	var length := maxf(fly_speed * boost * star_streak, 0.3)
	var mm := _stars.multimesh
	for i in star_count:
		var p := _star_pos[i]
		p.z += move
		if p.z > 40.0:
			p.z -= star_box.z
		_star_pos[i] = p
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, length)), p))


# ---- 行星 ----

func _update_planets(beat: float, notes: Array[NoteData], approach_beats: float) -> void:
	# 保险：已经判定过、但没人通知的行星，按结果补上撞飞 / 撞上
	for n: NoteData in _planets.keys():
		if n.judged:
			if n.result == NoteData.Result.MISS:
				crash(n)
			else:
				knock(n, n.result)
	var aim_target: Dictionary = {}
	var aim_ahead := 0.0
	for n in notes:
		if n.judged:
			continue
		var ahead := n.beat - beat
		if ahead > approach_beats:
			break
		if not _planets.has(n):
			_planets[n] = _make_planet(n)
		var p: Dictionary = _planets[n]
		var t := ahead / approach_beats  # 1 = 刚出现，0 = 到判定点，负数 = 已经过了
		var node: Node3D = p.node
		node.position = _dash_pos(p, t).lerp(_solar_pos(p, ahead, approach_beats), solar_weight)
		node.rotate(p.spin_axis, 0.02)
		node.scale = Vector3.ONE * clampf((1.0 - t) * 6.0, 0.0, 1.0)
		_update_shrink(p, ahead, approach_beats)
		_push_trail(p)
		if aim_target.is_empty():  # 按时间顺序，第一颗就是下一颗要撞的
			aim_target = p
			aim_ahead = ahead
	_draw_aim(aim_target, aim_ahead, approach_beats)


## 索敌线：从下一颗要撞的行星画红色虚线到飞碟外缘。停住之后才出现，冲刺时消失；只在太阳系里
func _draw_aim(p: Dictionary, ahead: float, approach_beats: float) -> void:
	var mesh := _aim.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if not aim_line or p.is_empty() or solar_weight < 0.01:
		return
	var since := approach_beats - ahead
	if since < out_beats or ahead < charge_beats:
		return
	var from: Vector3 = (p.node as Node3D).position
	var dir := Vector3(-from.x, 0.0, -from.z)
	var dist := dir.length() - solar_ring_radius
	if dist <= 0.5:
		return
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP) * aim_line_width * 0.5
	var start: float = p.radius * 1.3
	var appear := clampf((since - out_beats) / 0.3, 0.0, 1.0) * solar_weight
	# 虚线往飞碟方向流动，提示行星会从这里冲过来
	var period := aim_dash.x + aim_dash.y
	var offset := fposmod(_clock * 6.0, period)
	var y := Vector3(0.0, 0.05, 0.0)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var d := start - period + offset
	while d < dist:
		var a := maxf(d, start)
		var b := minf(d + aim_dash.x, dist)
		if b > a:
			var c := Color(aim_line_color, 0.85 * appear)
			var pa := from + dir * a + y
			var pb := from + dir * b + y
			for v in [pa + side, pa - side, pb + side, pb + side, pa - side, pb - side]:
				mesh.surface_set_color(c)
				mesh.surface_add_vertex(v)
		d += period
	# 箭头
	var tip := from + dir * dist + y
	var base := tip - dir * 1.6
	for v in [tip, base + side * 3.0, base - side * 3.0]:
		mesh.surface_set_color(Color(aim_line_color, 0.95 * appear))
		mesh.surface_add_vertex(v)
	mesh.surface_end()


## 冲刺路线：从前方远处匀速飞来，左右上下最后才收进圈里
func _dash_pos(p: Dictionary, t: float) -> Vector3:
	var start: Vector3 = p.start
	var lateral := Vector3(start.x - hit_point.x, start.y - hit_point.y, 0.0) * t * t
	return Vector3(hit_point.x, hit_point.y, hit_point.z - spawn_distance * t) + lateral


## 太阳系路线（ahead = 离该按键还有几拍）：
## ① 飞出去：从飞碟附近沿直线飞到轨道上 -> ② 停住抖动 -> ③ 最后 charge_beats 拍超高速直线冲到飞碟外缘
func _solar_pos(p: Dictionary, ahead: float, approach_beats: float) -> Vector3:
	var orbit: float = p.orbit
	var dir := Vector3(cos(p.angle), 0.0, sin(p.angle))
	var since := approach_beats - ahead  # 出现了几拍
	var r: float
	var shake := Vector3.ZERO
	if since < out_beats:
		var k := clampf(since / maxf(out_beats, 0.01), 0.0, 1.0)
		r = lerpf(launch_radius, orbit, 1.0 - pow(1.0 - k, 3.0))  # 先快后慢地停到轨道上
	elif ahead > charge_beats:
		r = orbit
		var tension := 1.0 - clampf((ahead - charge_beats) / maxf(approach_beats - out_beats - charge_beats, 0.01), 0.0, 1.0)
		var a := _clock * 40.0 + float(p.angle) * 10.0
		shake = Vector3(sin(a), 0.0, cos(a * 1.3)) * aim_shake * tension
	elif ahead >= 0.0:
		r = lerpf(solar_ring_radius, orbit, ahead / maxf(charge_beats, 0.01))
	else:
		r = solar_ring_radius * (1.0 + ahead * 4.0)  # 过了还没判定，继续往中心冲
	return dir * r + Vector3(0.0, solar_plane_y, 0.0) + shake


## 行星身上的收缩圈：停住那一刻出现，到该按键的那一拍正好缩到贴住行星；只在太阳系里显示
func _update_shrink(p: Dictionary, ahead: float, approach_beats: float) -> void:
	var ring: MeshInstance3D = p.shrink
	var node: Node3D = p.node
	var hold := maxf(approach_beats - out_beats, 0.01)  # 停住 + 冲刺一共几拍
	var k := clampf(ahead / hold, 0.0, 1.0)  # 1 = 刚停住，0 = 该按了
	var end_r: float = p.radius * 1.15
	var r := lerpf(end_r, shrink_start_radius, k)
	ring.position = node.position
	ring.scale = Vector3(r, 1.0, r)
	var appear := clampf((hold - ahead) / 0.3, 0.0, 1.0)  # 停住后 0.3 拍内淡入
	var mat := ring.material_override as StandardMaterial3D
	mat.albedo_color = Color(shrink_color, appear * solar_weight)
	ring.visible = ahead <= hold and solar_weight > 0.01


func _free_shrink(p: Dictionary) -> void:
	if p.has("shrink"):
		(p.shrink as Node).queue_free()
		p.erase("shrink")


func _make_planet(n: NoteData) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(n.beat)
	var radius := rng.randf_range(planet_radius.x, planet_radius.y)
	var color := planet_colors[rng.randi() % planet_colors.size()]
	var root := Node3D.new()
	if not planet_models.is_empty():
		var idx := rng.randi() % planet_models.size()
		if idx < planet_model_colors.size():
			color = planet_model_colors[idx]
		var model := planet_models[idx].instantiate() as Node3D
		model.scale = Vector3.ONE * radius
		model.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))
		_glow_model(model)
		root.add_child(model)
		return _finish_planet(rng, root, radius, color)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 14
	sphere.rings = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mat.emission_enabled = true
	mat.emission = color * 0.25
	sphere.material = mat
	body.mesh = sphere
	root.add_child(body)
	if rng.randf() < planet_ring_chance:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius * 1.35
		torus.outer_radius = radius * 1.8
		torus.rings = 24
		torus.ring_segments = 4
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = color.lightened(0.4)
		torus.material = rmat
		ring.mesh = torus
		ring.scale = Vector3(1.0, 0.08, 1.0)
		ring.rotation = Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))
		root.add_child(ring)
	return _finish_planet(rng, root, radius, color)


## 模型行星：每个材质复制一份，加一点按贴图颜色的自发光（不改模型文件本身）
func _glow_model(model: Node) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if m == null:
				continue
			m = m.duplicate()
			# Blender 导出的默认 0.5 粗糙度会反光一层星云，整颗发白；改成和代码做的球一样哑光
			m.roughness = planet_model_roughness
			m.metallic = 0.0
			m.metallic_specular = 0.2
			m.emission_enabled = true
			m.emission = Color.WHITE
			m.emission_energy_multiplier = planet_model_glow
			if m.albedo_texture:
				m.emission_texture = m.albedo_texture
				m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY  # 默认是相加，会整颗发白
			mi.set_surface_override_material(s, m)


func _finish_planet(rng: RandomNumberGenerator, root: Node3D, radius: float, color: Color) -> Dictionary:
	_cat.world.add_child(root)
	var start := hit_point + Vector3(rng.randf_range(-0.5, 0.5) * spawn_spread.x,
			rng.randf_range(-0.5, 0.5) * spawn_spread.y, -spawn_distance)
	var axis := Vector3(rng.randf_range(-1.0, 1.0), 1.0, rng.randf_range(-1.0, 1.0)).normalized()
	var orbit := orbit_radii[rng.randi() % orbit_radii.size()] if orbit_radii.size() > 0 else 20.0
	var p := {"node": root, "start": start, "spin_axis": axis, "orbit": orbit, "radius": radius,
			"angle": rng.randf() * TAU, "color": color, "trail": PackedVector3Array()}
	# 收缩圈：半径 1 的平躺细圈，用 scale 控制大小
	var shrink := MeshInstance3D.new()
	var shrink_mesh := TorusMesh.new()
	shrink_mesh.inner_radius = 1.0 - shrink_thickness
	shrink_mesh.outer_radius = 1.0 + shrink_thickness
	shrink_mesh.rings = 48
	shrink_mesh.ring_segments = 4
	shrink.mesh = shrink_mesh
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(shrink_color, 0.0)
	shrink.material_override = smat
	shrink.visible = false
	_cat.world.add_child(shrink)
	p.shrink = shrink
	if trail_points > 1:
		var trail := MeshInstance3D.new()
		trail.mesh = ImmediateMesh.new()
		trail.material_override = _trail_mat
		_cat.world.add_child(trail)
		p.trail_node = trail
	return p


func _update_flying(dt: float) -> void:
	for i in range(_flying.size() - 1, -1, -1):
		var p := _flying[i]
		var node: Node3D = p.node
		p.age += dt
		node.position += p.velocity * dt
		node.rotate(p.spin_axis, p.spin_speed * dt)
		_push_trail(p)
		if p.get("crash", false):
			if p.age >= p.life:
				_shake = crash_shake
				_flying.remove_at(i)
				_explode(node)
				_free_trail(p)
			continue
		p.velocity.y -= p.get("gravity", 9.0) * dt
		var k := clampf(1.0 - p.age / p.life, 0.0, 1.0)
		node.scale = Vector3.ONE * k
		if p.age >= p.life:
			node.queue_free()
			_free_trail(p)
			_flying.remove_at(i)


## 撞上飞船：行星炸成一团红光后消失
func _explode(node: Node3D) -> void:
	var t := create_tween().set_parallel()
	t.tween_property(node, "scale", Vector3.ONE * 1.8, 0.18).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(node, "scale", Vector3.ZERO, 0.15)
	t.chain().tween_callback(node.queue_free)
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mi.mesh is PrimitiveMesh:
			# 模型行星：每个面换成红光材质
			for s in mi.mesh.get_surface_count():
				var src := mi.get_active_material(s) as StandardMaterial3D
				var red := (src.duplicate() if src else StandardMaterial3D.new()) as StandardMaterial3D
				red.emission_enabled = true
				red.emission = Color(1.0, 0.25, 0.2)
				red.emission_texture = null
				red.emission_energy_multiplier = 3.0
				mi.set_surface_override_material(s, red)
			continue
		var m := (mi.mesh as PrimitiveMesh).material as StandardMaterial3D
		if m:
			m.emission_enabled = true
			m.emission = Color(1.0, 0.25, 0.2)
			m.emission_energy_multiplier = 3.0


# ---- 彗星尾巴 ----

## 记下行星现在的位置，重画尾巴（一条朝着镜头的带子，越往后越细越透明）
func _push_trail(p: Dictionary) -> void:
	if not p.has("trail_node"):
		return
	var node: Node3D = p.node
	# 按时间记点（和帧率无关）：每隔 trail_seconds / trail_points 秒记一个，最旧的丢掉
	var now := _clock
	var pts: PackedVector3Array = p.trail
	var step := trail_seconds / maxf(trail_points - 1, 1)
	if pts.size() < 2 or now - float(p.get("trail_last", 0.0)) >= step:
		pts.insert(1 if pts.size() > 0 else 0, node.position)
		p.trail_last = now
	if pts.is_empty():
		pts.append(node.position)
	pts[0] = node.position  # 头一直贴着行星
	if pts.size() > trail_points:
		pts.resize(trail_points)
	p.trail = pts
	var mesh: ImmediateMesh = (p.trail_node as MeshInstance3D).mesh
	mesh.clear_surfaces()
	if pts.size() < 2:
		return
	var cam_pos := _cat.camera.global_position
	var color: Color = p.color
	var width := trail_width * node.scale.x
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var along := (b - a).normalized()
		var side := along.cross(cam_pos - pts[i]).normalized()
		var f := 1.0 - float(i) / (pts.size() - 1)
		mesh.surface_set_color(Color(color.lightened(0.3), f * 0.8))
		mesh.surface_add_vertex(pts[i] + side * width * f)
		mesh.surface_set_color(Color(color.lightened(0.3), f * 0.8))
		mesh.surface_add_vertex(pts[i] - side * width * f)
	mesh.surface_end()


func _free_trail(p: Dictionary) -> void:
	if p.has("trail_node"):
		(p.trail_node as Node).queue_free()


# ---- 飞船和镜头 ----

func _update_ship(beat: float, pulse: float) -> void:
	var bob := sin(beat / ship_bob_beats * TAU) * ship_bob
	var bank := -sin(beat / sway_beats * TAU) * deg_to_rad(ship_bank_degrees)
	_ship.position.y = bob
	_ship.rotation.z = bank
	# 猫跟着飞船一起晃（叠加在按键转圈上）
	_cat.pose_position = Vector3(0.0, bob, 0.0)
	_cat.pose_tilt = Vector2(0.0, bank)
	if _flames:
		_flames.scale = Vector3(1.0, 1.0, 1.0 + pulse * flame_punch + sin(beat * 20.0) * 0.08 + _boost)


## 冲刺：追在斜后上方，忽近忽远 + 左右摇 + 歪头；太阳系：正上方往下看，高度轻微推拉。
## 两者之间按 solar_weight 过渡：仰角从 camera_pitch 抬到 90 度，距离从追拍距离升到 solar_height，顺带绕一圈
func _apply_camera(beat: float, pulse: float) -> void:
	var cam := _cat.camera
	var w := solar_weight
	var dolly := 0.5 - 0.5 * cos(beat / dolly_beats * TAU)  # 0 = 近，1 = 远
	var dash_dist := lerpf(near_distance, far_distance, dolly)
	var solar_dist := solar_height * (1.0 + (dolly - 0.5) * 2.0 * solar_dolly)
	var dist := lerpf(dash_dist, solar_dist, w * w)  # 先抬头再拉高，过渡更像「升起来」
	dist *= 1.0 - pulse * _by_stage(beat_punch) - _kick
	var sway := sin(beat / sway_beats * TAU) * _by_stage(sway_degrees) * (1.0 - w)
	var orbit := sin(w * PI) * transition_orbit_degrees * (1.0 if _was_solar else -1.0)
	var pitch := deg_to_rad(lerpf(camera_pitch, 89.5, smoothstep(0.0, 1.0, w)))
	var yaw := deg_to_rad(lerpf(camera_yaw, 0.0, w) + sway + orbit)
	var dir := Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw)
	var target := look_target.lerp(Vector3.ZERO, w)
	var shake := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake
	cam.position = target + dir * dist + shake
	# 太阳系里镜头的「上方」= 飞行方向（-Z），飞船在画面里往上飞
	var up := Vector3.UP.lerp(Vector3.FORWARD, smoothstep(0.5, 1.0, w)).normalized()
	cam.look_at(target + shake * 0.5, up)
	cam.rotate_object_local(Vector3.BACK, deg_to_rad(sin(beat / roll_beats * TAU) * _by_stage(roll_degrees)))
	cam.fov = fov + _boost * dash_boost_fov
