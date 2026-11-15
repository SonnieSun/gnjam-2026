class_name AbductionStage
extends Node2D
## 飞碟吸猫关卡的 3D 舞台：夜空、紫色云、飞碟、绿白色光束、站着的猫、仰拍镜头，外面套一层 VHS 效果。
## 每个音符是一个光圈，从飞碟顺着光束往下套，套到猫身上的那一拍按键。
## 打中一下猫往上升一格，没打中掉一格；攒满 hits_needed 下猫被吸进飞碟，飞碟闪一下飞走，过几拍再飞回来重来一轮
## （repeat_rounds 关掉就只吸一次）。
## 判定不在这里做，关卡脚本（abduction_section.gd）把 Judge 的结果转过来。
## 测试用，只在本机 _sandbox 里，不进仓库。

enum Phase { LIFT, ABSORB, AWAY, RETURN }

## 攒满了，猫开始被吸上去
signal absorb_started
## 猫被吸进飞碟了（吸上去的动画放完、飞碟闪光那一刻）
signal absorbed
## 吸了几格变了（progress / hits_needed）
signal progress_changed(value: int, needed: int)

@export_group("猫")
@export var cat_model: PackedScene = preload("res://stages/abduction/model/cat_stand.fbx")
@export var cat_texture: Texture2D = preload("res://stages/abduction/model/cat_stand_basecolor.png")
## 猫的高度（米）
@export var cat_height := 4.0
## 猫的朝向（度），让脸对着镜头
@export var cat_yaw_degrees := 0.0
## 猫脚下的地面点，光束打到这里
@export var cat_ground := Vector3(-4.5, 0.0, 0.0)
## 被吸起来以后上下浮动的幅度
@export var cat_bob := 0.15
## 被吸起来以后慢慢转（度 / 秒，升到最高时的速度）；0 = 不转，猫一直正对镜头
@export var lift_spin_speed := 0.0
## 被吸起来以后左右晃（度）
@export var lift_wobble_degrees := 8.0
## 打中时猫弹一下的大小
@export var hit_pop := 0.12
## 打中被吸一格时猫转一整圈，用几秒（和转圈猫的 spin_time 一样默认 0.225）
@export_range(0.05, 2.0) var hit_spin_time := 0.225
## 猫一直慢慢自转（度 / 秒）；0 = 不转
@export var idle_spin_speed := 0.0
## 按键时额外加的转速（度 / 秒）：按住一直这么快，松开后按 press_spin_decay 慢下来。
## 大于 0 时打中不再转一整圈（点一下大约多转 press_spin_speed / press_spin_decay 度）
@export var press_spin_speed := 0.0
@export var press_spin_decay := 6.0
## 打开后：每按一下键猫就快速转一整圈（用 hit_spin_time 秒），不管打没打中；打中时不再另外转
@export var press_full_turn := false
## 猫自己亮多少（贴图自发光），夜里看得清脸
@export_range(0.0, 2.0) var cat_self_light := 0.6

@export_group("飞碟")
@export var saucer: PackedScene = preload("res://stages/abduction/ufo.tscn")
@export var saucer_position := Vector3(-4.0, 15.0, -3.0)
## 飞碟倾斜（度），往镜头这边倒一点能看到上面
@export var saucer_tilt_degrees := Vector3(16.0, 0.0, -8.0)
@export var saucer_scale := 1.0
## 每拍上下浮动
@export var saucer_bob := 0.3
## 飞碟底部发光口在飞碟自己坐标里的位置（光束从这里出来）
@export var beam_top_local := Vector3(0.0, -2.6, 0.0)

@export_group("光束")
@export var beam_top_radius := 2.2
## 光束打到地面的那个圆：圆心和半径（不一定在猫脚下，按 Kisa 画的红线摆）
@export var beam_bottom_center := Vector3(-6.5, 0.0, 0.3)
@export var beam_bottom_radius := 5.8
@export var beam_color := Color(0.45, 1.0, 0.45)
@export var beam_core_color := Color(0.95, 1.0, 0.9)
@export var beam_energy := 1.0
## 光束打在猫身上的绿光亮度
@export var beam_light_energy := 10.0

@export_group("玩法")
## 打中几下被吸进去
@export var hits_needed := 8
## 没打中掉几格
@export var miss_drop := 1
## 吸进去以后飞碟飞走再飞回来，重来一轮；关掉 = 吸一次就完（飞碟飞走后不再回来）
@export var repeat_rounds := true
## 攒满之前最高升到光束长度的几成
@export_range(0.0, 1.0) var max_lift := 0.6
## 升降的跟随速度
@export var lift_follow := 6.0

@export_group("光圈")
@export var ring_color := Color(0.8, 1.0, 0.8)
## 光圈比光束粗多少倍
@export var ring_scale := 1.15
## 光圈粗细（相对半径）
@export_range(0.02, 0.5) var ring_thickness := 0.08

@export_group("吸进去以后")
## 猫被吸上去用几拍
@export var absorb_beats := 1.5
## 飞碟飞走用几拍
@export var away_beats := 2.0
## 飞走以后空几拍
@export var gone_beats := 2.0
## 飞回来用几拍
@export var return_beats := 2.0
## 飞走的方向和距离
@export var away_offset := Vector3(45.0, 25.0, -40.0)
## 吸进去那一下飞碟闪光的亮度
@export var absorb_flash_energy := 30.0

@export_group("镜头")
@export var camera_position := Vector3(1.5, 2.0, 14.5)
@export var camera_target := Vector3(-1.2, 6.8, 0.0)
@export_range(20.0, 100.0) var camera_fov := 60.0
## 猫升起来时镜头往上看多少
@export var camera_follow := 2.0
## 镜头每 2 拍左右摇
@export var camera_sway := 0.3
## 没打中镜头抖
@export var miss_shake := 0.5

@export_group("天空")
@export var sky_top_color := Color(0.05, 0.03, 0.1)
@export var sky_horizon_color := Color(0.24, 0.14, 0.26)
@export var ground_color := Color(0.06, 0.05, 0.08)
@export var ambient_color := Color(0.45, 0.35, 0.6)
@export var ambient_energy := 0.5
## 月光（从镜头这边照过来，让猫的脸看得见）
@export var moon_color := Color(0.75, 0.7, 1.0)
@export var moon_energy := 0.5
@export var cloud_color := Color(0.42, 0.34, 0.6, 0.95)
## 每朵云：x, y, z, 大小
@export var clouds := PackedVector4Array([
	Vector4(17.0, 1.0, -12.0, 22.0), Vector4(-24.0, 8.0, -40.0, 40.0),
	Vector4(22.0, 20.0, -55.0, 50.0), Vector4(-6.0, 32.0, -70.0, 60.0),
	Vector4(-30.0, 0.0, -25.0, 26.0),
])
## 云飘动速度
@export var cloud_drift := 0.01

@export_group("画面")
## 全屏 VHS 效果（vhs.gdshader），留空就不加
@export var screen_material: ShaderMaterial

var camera: Camera3D
var progress := 0
## 嵌在别的关卡的 3D 世界里用（迪斯科结尾直接接着玩吸猫，见 embed()）。加进场景树之前设成 true，
## 就不自己开视口、天空和镜头了。
var embedded := false

var _space: Node  # 3D 的东西都加到这里：自己玩时是自己的视口，嵌入时是别人世界里的一个定位点

var _vp: SubViewport
var _sprite: Sprite2D
var _rig: Node3D  # 飞碟 + 光束，一起浮动、飞走
var _saucer: Node3D
var _saucer_light: OmniLight3D
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _spot: SpotLight3D
var _cat: Node3D  # 位置 = 猫的中心
var _cat_body: Node3D
var _beam_top := Vector3.ZERO  # 飞碟坐标系（_rig 里）
var _axis := Vector3.UP  # 从地面指向飞碟
var _beam_len := 1.0
var _ring_mesh: TorusMesh
var _rings := {}  # NoteData 的 id -> { node, mat }
var _fading: Array[Dictionary] = []
var _phase := Phase.LIFT
var _phase_beat := 0.0
var _lift := 0.0
var _spin := 0.0
var _hit_t := -1.0  # 打中转圈已经转了几秒，-1 = 没在转
var _hit_start := 0.0
var _hit_angle := 0.0
var _pop := 0.0
var _shake := 0.0
var _flash := 0.0
var _beam_fade := 1.0
var _cat_scale := 1.0
var _press_boost := 0.0  # 0~1，按键加速还剩多少
## 节拍辅助线：光束上一圈圈的环，在每一拍光圈会套到的高度（规则见 BeatGuides）。关卡脚本按自己的设置填
var beat_guides := true
var guide_every := 1.0
var _guides: BeatGuideStrips


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	Judge.ensure_input()  # 按键加速自转要读 "hit" 这个动作
	if embedded:
		return
	z_index = -1  # 画在关卡脚本自己画的东西（红闪）下面
	_vp = SubViewport.new()
	_vp.size = Vector2i(get_viewport_rect().size)
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	_sprite = Sprite2D.new()
	_sprite.texture = _vp.get_texture()
	_sprite.material = screen_material
	add_child(_sprite)
	_space = _vp

	_make_environment()
	_make_clouds()
	_make_saucer()
	_make_cat()
	_make_beam()
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 1.0 - ring_thickness
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 48
	_ring_mesh.ring_segments = 8

	camera = Camera3D.new()
	camera.fov = camera_fov
	camera.far = 400.0
	_vp.add_child(camera)
	camera.position = camera_position
	camera.look_at(camera_target)


## 嵌进别的 3D 世界接着玩：3D 的东西加到 host 里，整套坐标平移 origin（让这里的猫脚下对上那边的猫脚下）。
## 飞碟用那边已经停好的 saucer_node（位置不变，只是接过来管），镜头用那边的 cam，这里不动它。
## 天空不换，只补上云；光束从 0 淡入，猫和光圈照常。
func embed(host: Node, cam: Camera3D, saucer_node: Node3D, origin: Vector3) -> void:
	var space := Node3D.new()
	space.position = origin
	host.add_child(space)
	_space = space
	camera = cam
	_make_clouds()
	_rig = Node3D.new()
	_space.add_child(_rig)
	_saucer = saucer_node
	_saucer.reparent(_rig, true)
	_beam_top = _saucer.transform * beam_top_local
	_saucer_light = OmniLight3D.new()
	_saucer_light.light_color = beam_core_color
	_saucer_light.light_energy = 0.0
	_saucer_light.omni_range = 30.0
	_saucer_light.position = _beam_top
	_rig.add_child(_saucer_light)
	_make_cat()
	_make_beam()
	_beam_fade = 0.0
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 1.0 - ring_thickness
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 48
	_ring_mesh.ring_segments = 8


## 每帧由关卡脚本调用
func update(beat: float, notes: Array[NoteData], approach_beats: float) -> void:
	if _space == null:
		return
	var dt := get_process_delta_time()
	var size := Vector2i(get_viewport_rect().size)
	if _vp and _vp.size != size:
		_vp.size = size
	var pulse := pow(1.0 - fposmod(beat, 1.0), 3.0)
	_update_phase(beat)
	_update_rings(beat, notes, approach_beats, dt)
	_update_guides(beat, notes, approach_beats)
	_update_cat(beat, dt)
	_update_rig(beat, pulse, dt)
	if not embedded:
		_apply_camera(beat, dt)


## 音符判定结果（只在猫还在地上 / 光束里的时候算）
func judge(note: NoteData, result: int) -> void:
	var hit := result != NoteData.Result.MISS
	var key := note.get_instance_id()
	if _rings.has(key):
		var r: Dictionary = _rings[key]
		_rings.erase(key)
		r.hit = hit
		r.t = 0.0
		r.mat.set_shader_parameter("color", SpinSection.result_color(result))
		_fading.append(r)
	if _phase != Phase.LIFT:
		return
	var before := progress
	if hit:
		progress = mini(progress + 1, hits_needed)
		_pop = 1.0
		if press_spin_speed <= 0.0 and not press_full_turn:
			_hit_start = wrapf(_hit_angle, -PI, PI)  # 正在转时再打中，从当前角度重新转一整圈
			_hit_t = 0.0
		if progress >= hits_needed:
			_start_phase(Phase.ABSORB)
			absorb_started.emit()
	else:
		progress = maxi(progress - miss_drop, 0)
		_shake = miss_shake
	if progress != before:
		progress_changed.emit(progress, hits_needed)


func _input(event: InputEvent) -> void:
	if not press_full_turn or _cat == null or Engine.is_editor_hint():
		return
	if event.is_action_pressed(Judge.HIT_ACTION) and not event.is_echo():
		# 正在转时再按：从当前角度接着多转一整圈，不跳
		_hit_start = _hit_angle - TAU if _hit_t >= 0.0 else 0.0
		_hit_t = 0.0


## 猫中心在屏幕上的位置（相对屏幕中心），命中星星从这里飞出来
func hit_screen_offset() -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(_cat.global_position) - Vector2(camera.get_viewport().get_visible_rect().size) / 2.0


func ring_screen_radius() -> float:
	if camera == null:
		return 80.0
	var c := camera.unproject_position(_cat.global_position)
	var e := camera.unproject_position(_cat.global_position + camera.global_basis.x * cat_height * 0.35)
	return c.distance_to(e)


# ---- 搭场景 ----

func _make_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_top_color
	sky_mat.sky_horizon_color = sky_horizon_color
	sky_mat.ground_horizon_color = sky_horizon_color
	sky_mat.ground_bottom_color = ground_color
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = moon_color
	moon.light_energy = moon_energy
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_vp.add_child(moon)
	moon.look_at_from_position(camera_position + Vector3(4.0, 10.0, 0.0), cat_ground + Vector3.UP * cat_height * 0.5)


func _make_clouds() -> void:
	var shader := Shader.new()
	shader.code = CLOUD_SHADER
	var i := 0
	for c in clouds:
		var q := QuadMesh.new()
		q.size = Vector2(c.w, c.w * 0.55)
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("color", cloud_color)
		m.set_shader_parameter("seed", float(i) * 7.31)
		m.set_shader_parameter("drift", cloud_drift)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_space.add_child(mi)
		mi.position = Vector3(c.x, c.y, c.z)
		mi.basis = Basis.looking_at(camera_position - mi.position)
		i += 1


func _make_saucer() -> void:
	_rig = Node3D.new()
	_space.add_child(_rig)
	_saucer = saucer.instantiate() as Node3D
	var tilt := saucer_tilt_degrees * (PI / 180.0)
	_saucer.transform = Transform3D(Basis.from_euler(tilt).scaled(Vector3.ONE * saucer_scale), saucer_position)
	_rig.add_child(_saucer)
	_beam_top = _saucer.transform * beam_top_local
	_saucer_light = OmniLight3D.new()
	_saucer_light.light_color = beam_core_color
	_saucer_light.light_energy = 0.0
	_saucer_light.omni_range = 30.0
	_saucer_light.position = _beam_top
	_rig.add_child(_saucer_light)


func _make_cat() -> void:
	_cat = Node3D.new()
	_space.add_child(_cat)
	_cat_body = Node3D.new()
	_cat.add_child(_cat_body)
	var inst := cat_model.instantiate() as Node3D
	_cat_body.add_child(inst)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = cat_texture
	mat.roughness = 0.9
	# 自发光用同一张贴图：夜里光线暗，不然猫脸会糊成一片
	mat.emission_enabled = true
	mat.emission_texture = cat_texture
	mat.emission_energy_multiplier = cat_self_light
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	# 量大小：缩放到 cat_height，中心挪到 _cat 原点
	var box := _measure(inst)
	inst.position = -box.get_center()
	_cat_body.scale = Vector3.ONE * (cat_height / maxf(box.size.y, 0.001))
	_cat_body.rotation_degrees.y = cat_yaw_degrees
	_cat.position = _cat_rest()


func _make_beam() -> void:
	# 斜锥：顶上是飞碟发光口的水平圆，底下是地面上的水平圆（圆心可以不在正下方），侧面连起来
	var bottom := beam_bottom_center
	var dir := _beam_top - bottom
	_beam_len = dir.length()
	_axis = dir / _beam_len
	var seg := 48
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in seg + 1:
		var a := TAU * i / seg
		var out := Vector3(cos(a), 0.0, sin(a))
		verts.append(_beam_top + out * beam_top_radius)
		verts.append(bottom + out * beam_bottom_radius)
		normals.append(out)
		normals.append(out)
		uvs.append(Vector2(float(i) / seg, 0.0))
		uvs.append(Vector2(float(i) / seg, 1.0))
	var idx := PackedInt32Array()
	for i in seg:
		var t0 := i * 2
		idx.append_array([t0, t0 + 1, t0 + 2, t0 + 2, t0 + 1, t0 + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shader := Shader.new()
	shader.code = BEAM_SHADER
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = shader
	_beam_mat.set_shader_parameter("color", beam_color)
	_beam_mat.set_shader_parameter("core_color", beam_core_color)
	_beam = MeshInstance3D.new()
	_beam.mesh = mesh
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(_beam)

	_spot = SpotLight3D.new()
	_spot.light_color = beam_color.lerp(beam_core_color, 0.5)
	_spot.light_energy = beam_light_energy
	_spot.spot_range = _beam_len * 1.5
	_spot.spot_angle = rad_to_deg(atan(beam_bottom_radius / _beam_len)) * 1.3
	_rig.add_child(_spot)
	_spot.position = _beam_top  # 聚光灯朝 -Z，对准地面上的光圈中心
	_spot.basis = Basis.looking_at(bottom - _beam_top)


# ---- 每帧 ----

func _start_phase(p: int) -> void:
	_phase = p
	_phase_beat = -1.0  # 下一帧记下开始的拍子


func _update_phase(beat: float) -> void:
	if _phase_beat < 0.0:
		_phase_beat = beat
	var t := beat - _phase_beat
	match _phase:
		Phase.ABSORB:
			_clear_rings()
			if t >= absorb_beats:
				_flash = 1.0
				_cat.visible = false
				_start_phase(Phase.AWAY)
				absorbed.emit()
		Phase.AWAY:
			if repeat_rounds and t >= away_beats + gone_beats:
				progress = 0
				_lift = 0.0
				_cat.visible = true
				_cat_scale = 0.0
				_spin = 0.0
				_hit_t = -1.0
				_hit_angle = 0.0
				_start_phase(Phase.RETURN)
		Phase.RETURN:
			if t >= return_beats:
				_start_phase(Phase.LIFT)


func _phase_t(beats: float) -> float:
	if _phase_beat < 0.0:
		return 0.0
	return clampf((Conductor.song_beat - _phase_beat) / maxf(beats, 0.01), 0.0, 1.0)


func _update_rings(beat: float, notes: Array[NoteData], approach_beats: float, dt: float) -> void:
	var cat_c := _cat.position - _rig.position  # 换到飞碟坐标系
	if _phase == Phase.LIFT:
		for n in notes:
			if n.judged:
				continue
			var ahead := n.beat - beat
			if ahead > approach_beats:
				break
			var key := n.get_instance_id()
			if not _rings.has(key):
				_rings[key] = _make_ring()
			var r: Dictionary = _rings[key]
			var t := clampf(1.0 - ahead / approach_beats, 0.0, 1.0)
			_place_ring(r.node, lerpf(_beam_top.y, cat_c.y, t))
			r.mat.set_shader_parameter("alpha", smoothstep(0.0, 0.15, t))
	# 判定过的光圈：打中往外扩散变淡，没打中往下掉变淡
	for i in range(_fading.size() - 1, -1, -1):
		var r: Dictionary = _fading[i]
		r.t += dt / 0.35
		var node: Node3D = r.node
		if r.hit:
			node.scale *= 1.0 + dt * 1.5
		else:
			node.position -= Vector3.UP * dt * 6.0
		r.mat.set_shader_parameter("alpha", 1.0 - r.t)
		if r.t >= 1.0:
			node.queue_free()
			_fading.remove_at(i)


func _update_guides(beat: float, notes: Array[NoteData], approach_beats: float) -> void:
	if _guides == null:
		_guides = BeatGuideStrips.new()
		_rig.add_child(_guides)
	_guides.begin()
	if beat_guides and _phase == Phase.LIFT and _beam_fade > 0.5:
		var cat_c := _cat.position - _rig.position
		for g in BeatGuides.compute(notes, beat, approach_beats, guide_every,
				func(n: NoteData) -> Color: return SpinSection.SOUND_COLORS[n.sound % 3]):
			var h := lerpf(_beam_top.y, cat_c.y, 1.0 - clampf(g.a, 0.0, 1.0))
			var u := clampf((h - beam_bottom_center.y) / maxf(_beam_top.y - beam_bottom_center.y, 0.01), 0.0, 1.0)
			var center := beam_bottom_center.lerp(_beam_top, u)
			var radius := lerpf(beam_bottom_radius, beam_top_radius, u) * ring_scale
			_guides.circle(center, radius, BeatGuides.look(g), 0.1)
	_guides.finish()


func _make_ring() -> Dictionary:
	var shader := _ring_shader()
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("color", ring_color)
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(mi)
	return {"node": mi, "mat": m, "hit": true, "t": 0.0}


var _ring_shader_cache: Shader


func _ring_shader() -> Shader:
	if _ring_shader_cache == null:
		_ring_shader_cache = Shader.new()
		_ring_shader_cache.code = RING_SHADER
	return _ring_shader_cache


## 光圈 = 光束在 height 这个高度（飞碟坐标系）的水平截面，半径 × ring_scale
func _place_ring(node: Node3D, height: float) -> void:
	var u := clampf((height - beam_bottom_center.y) / maxf(_beam_top.y - beam_bottom_center.y, 0.01), 0.0, 1.0)
	var center := beam_bottom_center.lerp(_beam_top, u)
	var radius := lerpf(beam_bottom_radius, beam_top_radius, u) * ring_scale
	node.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), center)


func _clear_rings() -> void:
	for key in _rings:
		var r: Dictionary = _rings[key]
		r.hit = true
		r.t = 0.0
		_fading.append(r)
	_rings.clear()


func _update_cat(beat: float, dt: float) -> void:
	var lift_target := float(progress) / float(maxi(hits_needed, 1))
	_lift = lerpf(_lift, lift_target, 1.0 - exp(-lift_follow * dt))
	_pop = maxf(_pop - dt / 0.12, 0.0)
	var rest := _cat_rest()
	var top := _beam_top + _rig.position - _axis * cat_height * 0.6
	var pos := rest.lerp(top, _lift * max_lift)
	pos += Vector3.UP * sin(beat * PI * 0.5) * cat_bob * minf(_lift * 4.0, 1.0)
	var spin_speed := lift_spin_speed * _lift + idle_spin_speed
	if press_spin_speed > 0.0:
		# 按着就是最快，松开以后慢慢回到平时的慢转
		if Input.is_action_pressed(Judge.HIT_ACTION):
			_press_boost = 1.0
		else:
			_press_boost *= exp(-press_spin_decay * dt)
		spin_speed += press_spin_speed * _press_boost
	var tilt := sin(beat * PI * 0.5) * deg_to_rad(lift_wobble_degrees) * minf(_lift * 4.0, 1.0)
	var size := 1.0 + hit_pop * _pop
	match _phase:
		Phase.ABSORB:
			var t := _phase_t(absorb_beats)
			var e := t * t
			pos = pos.lerp(_beam_top + _rig.position, e)
			size *= lerpf(1.0, 0.05, e)
			spin_speed += 720.0 * t
		Phase.RETURN:
			_cat_scale = minf(_cat_scale + dt * 4.0, 1.0)
			size *= ease(_cat_scale, -2.0) if _cat_scale < 1.0 else 1.0
	_spin += deg_to_rad(spin_speed) * dt
	# 打中转一圈：和前面关卡的转圈猫一样，先快后慢转满一圈，落回正面
	if _hit_t >= 0.0:
		_hit_t += dt
		var p := _hit_t / hit_spin_time
		if p >= 1.0:
			_hit_angle = 0.0
			_hit_t = -1.0
		else:
			_hit_angle = lerpf(_hit_start, TAU, 1.0 - pow(1.0 - p, 2.0))
	_cat.position = pos
	_cat.rotation = Vector3(0.0, _spin + _hit_angle, tilt)
	_cat.scale = Vector3.ONE * maxf(size, 0.001)


func _update_rig(beat: float, pulse: float, dt: float) -> void:
	var bob := Vector3.UP * sin(beat * PI * 0.5) * saucer_bob
	var away := Vector3.ZERO
	var beam_target := 1.0
	match _phase:
		Phase.ABSORB:
			beam_target = 1.6
		Phase.AWAY:
			var t := _phase_t(away_beats)
			away = away_offset * t * t
			beam_target = 0.0
		Phase.RETURN:
			var t := _phase_t(return_beats)
			away = away_offset * pow(1.0 - t, 2.0)
			beam_target = 1.0 if t > 0.8 else 0.0
	_rig.position = bob + away
	_beam_fade = move_toward(_beam_fade, beam_target, dt * 4.0)
	_flash = maxf(_flash - dt * 1.5, 0.0)
	var energy := beam_energy * _beam_fade * (0.85 + 0.25 * pulse)
	_beam_mat.set_shader_parameter("intensity", energy)
	_beam.visible = _beam_fade > 0.01
	_spot.light_energy = beam_light_energy * _beam_fade * (0.85 + 0.25 * pulse)
	_saucer_light.light_energy = absorb_flash_energy * _flash
	var flames := _saucer.get_node_or_null("Flames") as Node3D
	if flames:
		flames.scale = Vector3.ONE * (1.0 + 0.2 * pulse)


func _apply_camera(beat: float, dt: float) -> void:
	_shake = maxf(_shake - dt * 2.0, 0.0)
	var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake
	var sway := Vector3(sin(beat * PI * 0.5) * camera_sway, 0.0, 0.0)
	var target := camera_target + Vector3.UP * camera_follow * _lift
	camera.position = camera_position + sway + jitter
	camera.look_at(target + jitter * 0.5)


# ---- 小工具 ----

## 猫站在地上时中心的位置
func _cat_rest() -> Vector3:
	return cat_ground + Vector3.UP * cat_height * 0.5


## 量 root 下所有网格的包围盒，用 root 自己的坐标（嵌进别的世界时整套坐标平移过，用世界坐标会把猫的中心算偏，
## 猫就绕着一个圈转而不是原地自转）
func _measure(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var to_root := root.global_transform.affine_inverse()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := to_root * m.global_transform * m.mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 color : source_color = vec4(0.42, 0.34, 0.6, 0.95);
uniform float seed = 0.0;
uniform float drift = 0.01;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int k = 0; k < 5; k++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = UV - 0.5;
	vec2 q = UV * 3.0 + vec2(seed, seed * 1.7) + vec2(TIME * drift, 0.0);
	float n = fbm(q);
	float r = length(uv * vec2(1.0, 1.7));
	float mask = smoothstep(0.5, 0.12, r + (n - 0.5) * 0.6);
	float shade = 0.55 + 0.7 * fbm(q * 1.7 + 3.0);
	ALBEDO = color.rgb * shade;
	ALPHA = mask * color.a;
}
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(0.45, 1.0, 0.45, 1.0);
uniform vec4 core_color : source_color = vec4(0.95, 1.0, 0.9, 1.0);
uniform float intensity = 1.0;
uniform float front_strength = 0.35;
varying vec3 out_n;
void vertex() {
	out_n = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	float d = dot(normalize(out_n), VIEW);
	float f = abs(d);
	float core = pow(f, 3.0);
	float bands = 0.85 + 0.15 * sin(UV.y * 40.0 - TIME * 10.0);
	vec3 c = mix(color.rgb, core_color.rgb, core);
	float side = d > 0.0 ? front_strength : 1.0;  // 朝镜头这半边淡一点，免得把猫盖住
	ALBEDO = c * (0.2 + 0.8 * core) * f * bands * intensity * side;
}
"""

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(0.8, 1.0, 0.8, 1.0);
uniform float alpha = 1.0;
void fragment() {
	ALBEDO = color.rgb * 1.6 * alpha;
}
"""
