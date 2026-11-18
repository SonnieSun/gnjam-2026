class_name SkyStage
extends AbductionStage
## 上升关的 3D 舞台，以吸猫舞台（AbductionStage）为基底：猫被光柱牵着，一直在屏幕中间往上飞。
## 光圈、判定线、打中转圈、最后被吸进飞碟都是吸猫舞台原来的；这里换掉的是天空、云、镜头，加上五个阶段：
##   0 云层    傍晚的紫色天空，云从上往下掠过（有几层，最近的一层从镜头前面扫过去）
##   1 风暴    天黑下来，乌云，闪电，雨，镜头抖
##   2 亮起来  一下全白，然后是金色的天、白云、光芒、金色的碎光
##   3 太空    云没了，星星往下流，地球的弧线沉下去
##   4 飞碟    镜头抬起来，飞碟出现在头顶
## 最后 finale()：镜头推到飞碟底下的特写，猫转着被吸进去，飞碟一闪，飞走。
## 阶段由关卡脚本（sky_section.gd）调 set_phase()，它跟着音乐的档位走。
## 音符带着它那一段谱子的样子（NoteData.skin，见 scripts/chart/note_skin.gd）：光圈变粗、变成岩浆（光圈自己的着色器：
## 整圈红橙、里面暗色的壳在流动、裂缝发亮）、三连音的圈（断成三段、转着的金色岩浆弧）、往上飘的火星、打中溅火星，
## 和整个画面的暗角、对比度都按它来。风暴的谱子挂的是 levels/skins/doom.tres（末日重金属）。

@export_group("上升")
## 云往下掠过的速度（米 / 秒），每个阶段一个
@export var rise_speeds := PackedFloat32Array([14.0, 26.0, 18.0, 30.0, 12.0])
## 打中一下，速度冲一下（倍数）
@export var hit_boost := 0.8
## 云有几朵（分三层：远、中、镜头前）
@export var cloud_count := 34
## 猫在光柱里上下浮、左右晃
@export var float_bob := 0.25
@export var float_tilt_degrees := 7.0

@export_group("阶段的颜色")
@export var sky_tops: Array[Color] = [Color(0.10, 0.08, 0.30), Color(0.02, 0.02, 0.04), Color(0.30, 0.58, 1.0), Color(0.0, 0.0, 0.03), Color(0.0, 0.02, 0.03)]
@export var sky_horizons: Array[Color] = [Color(0.62, 0.36, 0.62), Color(0.20, 0.05, 0.07), Color(1.0, 0.90, 0.62), Color(0.04, 0.07, 0.24), Color(0.03, 0.14, 0.14)]
@export var cloud_colors: Array[Color] = [Color(0.78, 0.62, 0.88, 0.95), Color(0.13, 0.11, 0.15, 0.97), Color(1.0, 0.96, 0.86, 0.95), Color(0.5, 0.6, 1.0, 0.0), Color(0.5, 0.6, 1.0, 0.0)]
@export var ambients: Array[Color] = [Color(0.6, 0.5, 0.8), Color(0.25, 0.2, 0.3), Color(1.0, 0.95, 0.85), Color(0.4, 0.45, 0.7), Color(0.35, 0.6, 0.5)]
@export var ambient_energies := PackedFloat32Array([0.7, 0.35, 1.3, 0.6, 0.6])
## 换阶段时颜色过渡用几秒（亮起来那一下是瞬间的）
@export var phase_fade_seconds := PackedFloat32Array([1.0, 0.5, 0.6, 4.0, 2.5])

@export_group("亮起来时看得清")
## 天亮了以后，发光的白圈在亮背景上看不见，所以这一段：光圈和判定线换成深色的实心圈，
## 光柱调暗（不然猫和圈都泡在一片白里），猫周围垫一圈淡淡的暗影
@export var bright_ring_color := Color(0.42, 0.05, 0.62)
@export var bright_judge_color := Color(0.85, 0.0, 0.45)
## 这一段光柱的亮度乘多少
@export_range(0.0, 1.0) var bright_beam_scale := 0.4
## 猫周围的暗影多深（0 = 不垫）
@export_range(0.0, 1.0) var bright_shade := 0.4
## 亮起来那一下的白闪最亮多少（1 = 整屏纯白）、多久淡掉（秒）
@export_range(0.0, 1.0) var bright_flash := 0.8
@export var bright_flash_seconds := 0.5

@export_group("风暴")
## 平均几拍打一次闪电
@export var lightning_every_beats := 3.0
@export var storm_shake := 0.12

@export_group("音符的样子")
## 关掉 = 不管音符带的样子（NoteSkin），和原来一样
@export var use_note_skins := true
## 画面上的样子（暗角、滴血、对比度）跟着「现在这一段」：最近要打的那个音符的样子。换过去 / 换回来用几秒
@export var skin_fade_seconds := 0.6
## 转场音符到了，天空也一起切到这个阶段（还没到的话；-1 = 不管，等音乐换档）。风暴 = 1
@export var impact_sky_phase := 1

@export_group("飞碟出现和特写")
## 飞碟出现时镜头抬起来看哪里、退到哪里
@export var reveal_position := Vector3(0.0, 1.0, 25.0)
@export var reveal_target := Vector3(0.0, 9.5, 0.0)
## 最后的特写：镜头在哪、视野多大
@export var closeup_position := Vector3(3.5, 4.0, 12.0)
@export var closeup_fov := 50.0

var sky_phase := 0

var _sky_mat: ProceduralSkyMaterial
var _env: Environment
var _sun: DirectionalLight3D
var _cloud_nodes: Array[Dictionary] = []
var _col_t := 1.0  # 这次换阶段颜色过渡到哪了
var _from := {}
var _now := {}
var _boost := 0.0
var _speed := 14.0
var _bolt := 0.0  # 闪电还剩多亮
var _bolt_points := PackedVector2Array()
var _next_bolt := 0.0
var _white := 0.0  # 全屏白闪
var _holy := 0.0  # 光芒
var _earth := 0.0  # 地球弧线出现了多少
var _reveal := 0.0
var _closeup := 0.0
var _closeup_speed := 0.0
var _finale := false
var _follow := Vector3.ZERO
var _overlay: Node2D
var _rain: CPUParticles3D
var _sparks: CPUParticles3D
var _stars: CPUParticles3D
var _time := 0.0
## 规矩：玩家没在操作的时候镜头不乱动。最后一次打中之后过这么多秒，镜头的左右摇和风暴里的抖动就收掉
@export var idle_hold_seconds := 1.2
var _idle := 99.0
var _active := 0.0
var _shade_tex: GradientTexture2D
var _ring_color0 := Color.WHITE
var _judge_color0 := Color.WHITE
var _beam_energy0 := 1.0
var _beam_light0 := 1.0
var _plain_skin := NoteSkin.new()  # 没挂样子的音符标成三连音时用它的颜色
var _skin: NoteSkin  # 画面现在用的样子（淡出时还留着，直到 _skin_k 回到 0）
var _skin_k := 0.0  # 画面上的样子出来了多少（0~1）
var _triplet := {}  # NoteData 的 id -> 是不是三连音（第一次看到时定）
var _vignette_tex: GradientTexture2D
var _lava_meshes := {}  # 粗细 -> TorusMesh（带样子的光圈用粗一点的环）
var _embers: CPUParticles3D  # 带样子的那一段：猫周围往上飘的火星
var _ember_burst: CPUParticles3D  # 打中带样子的音符：判定圈上溅一圈火星
var _ember_big: CPUParticles3D  # 打中三连音：溅得又多又高
var _pyro: Array[CPUParticles3D] = []  # 画面左右下角往上喷的火柱（小节线上的音符、一串三连音的最后一个）
var _strobe := 0.0  # 八分连打的频闪还剩多少
var _strobe_n := 0
var _notes_ref: Array[NoteData] = []
var _skin_at: NoteSkin  # 「现在这一段」的样子：最近一个到了拍子的音符带的（换了 = 转场音符到了）
var _impact_note := {}  # NoteData 的 id -> 是不是转场音符（这一段第一个带新样子的）
var _impact := 0.0  # 转场冲击还剩多少（1 -> 0）
var _shocks: Array[Dictionary] = []  # 转场冲击波：{node, mat, t, r0}


func _ready() -> void:
	# 吸猫舞台的参数换成这一关的：猫在正中间，光柱是竖直的一根，飞碟在画面上面（看不到），不会中途被吸进去
	cat_ground = Vector3(0.0, 0.0, 0.0)
	saucer_position = Vector3(0.0, 21.0, 0.0)
	saucer_tilt_degrees = Vector3(8.0, 0.0, 0.0)
	beam_bottom_center = Vector3(0.0, -34.0, 0.0)
	beam_bottom_radius = 5.2
	beam_top_radius = 2.6
	beam_energy = 0.5
	beam_light_energy = 5.0
	hits_needed = 1000000
	max_lift = 0.0
	repeat_rounds = false
	absorb_beats = 3.0
	away_beats = 3.0
	away_offset = Vector3(30.0, 60.0, -80.0)
	camera_position = Vector3(0.0, 2.6, 15.0)
	camera_target = Vector3(0.0, 3.4, 0.0)
	camera_follow = 0.0
	camera_sway = 0.25
	super()
	if Engine.is_editor_hint():
		return
	_ring_color0 = ring_color
	_judge_color0 = judge_ring_color
	_beam_energy0 = beam_energy
	_beam_light0 = beam_light_energy
	_now = _look(0)
	_from = _now
	_speed = rise_speeds[0]
	_make_particles()
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## 换阶段（0 云层 / 1 风暴 / 2 亮起来 / 3 太空 / 4 飞碟）
func set_phase(p: int) -> void:
	p = clampi(p, 0, 4)
	if p == sky_phase:
		return
	_from = _current_look()
	_col_t = 0.0
	if p == 2 and sky_phase < 2:
		_white = bright_flash  # 亮起来：先闪一下白
	sky_phase = p


## 最后：镜头推到飞碟底下，猫被吸进去，飞碟飞走（一共 seconds 秒）
func finale(seconds: float) -> void:
	if _finale:
		return
	_finale = true
	_closeup_speed = 1.0 / maxf(seconds * 0.3, 0.1)
	var spb := Conductor.sec_per_beat()
	absorb_beats = seconds * 0.55 / spb
	away_beats = seconds * 0.45 / spb
	_start_phase(Phase.ABSORB)
	absorb_started.emit()


func judge(note: NoteData, result: int) -> void:
	var key := note.get_instance_id()
	var r: Dictionary = _rings.get(key, {})
	var tri: bool = _triplet.get(key, false)
	_triplet.erase(key)
	super(note, result)
	var hit := result != NoteData.Result.MISS and _phase == Phase.LIFT
	var skin0: NoteSkin = note.skin
	if hit and skin0:
		var burst := _ember_big if tri else _ember_burst
		if skin0.embers and burst:
			burst.position = _cat.position - _rig.position
			burst.color = skin0.triplet_hot if tri else skin0.ember_hot
			burst.restart()
			burst.emitting = true
		if tri:
			_shake = maxf(_shake, skin0.triplet_shake)
		var downbeat: bool = accents != null and accents.look(note, ring_color).kind == NoteAccents.Kind.DOWNBEAT
		if skin0.pyro and (downbeat or (tri and not _has_note(note.beat + 2.0 / 3.0))):
			_fire_pyro(skin0, tri)
		if skin0.strobe and _has_note(note.beat - 0.5) and (_has_note(note.beat - 1.0) or _has_note(note.beat + 0.5)):
			_strobe = 1.0
			_strobe_n += 1
	if tri and not r.is_empty() and result != NoteData.Result.MISS:
		# 三连音打中：三段弧一边往外扩一边收短，散成三点
		var skin: NoteSkin = note.skin if note.skin else _plain_skin
		r["tri"] = true
		r.mat.set_shader_parameter("color", skin.triplet_color)
	if result != NoteData.Result.MISS:
		_boost = 1.0
		_idle = 0.0


func update(beat: float, notes: Array[NoteData], approach_beats: float) -> void:
	# 亮背景上换成深色的圈、调暗光柱（要在吸猫舞台算这一帧之前定好）
	var sk := _skin_k if _skin else 0.0
	var ring0 := _ring_color0  # 光圈的颜色按每个音符自己的样子来（_color_rings），这里不跟画面的样子走
	var judge0 := _judge_color0.lerp(Color(_skin.judge_color, 1.0), _skin.judge_color.a * sk) if _skin else _judge_color0
	ring_color = ring0.lerp(bright_ring_color, _holy)
	judge_ring_color = judge0.lerp(bright_judge_color, _holy)
	beam_energy = _beam_energy0 * lerpf(1.0, bright_beam_scale, _holy)
	beam_light_energy = _beam_light0 * lerpf(1.0, bright_beam_scale, _holy)
	for key in _rings:
		_rings[key].mat.set_shader_parameter("color", ring_color)
		_rings[key].mat.set_shader_parameter("solid", _holy)
	super(beat, notes, approach_beats)
	if _space == null:
		return
	var dt := get_process_delta_time()
	_notes_ref = notes
	_strobe = maxf(_strobe - dt * 7.0, 0.0)
	_impact = maxf(_impact - dt / 0.5, 0.0)
	for i in range(_shocks.size() - 1, -1, -1):
		var sh: Dictionary = _shocks[i]
		sh.t += dt / 0.4
		var e := 1.0 - pow(1.0 - clampf(sh.t, 0.0, 1.0), 3.0)
		var node: Node3D = sh.node
		var radius: float = sh.r0 * lerpf(1.0, sh.grow, e)
		node.scale = Vector3(radius, radius * lerpf(1.0, 0.15, e), radius)
		sh.mat.set_shader_parameter("alpha", pow(clampf(1.0 - sh.t, 0.0, 1.0), 2.0))
		if sh.t >= 1.0:
			node.queue_free()
			_shocks.remove_at(i)
	_update_skin(beat, notes, dt)
	_color_rings(beat, notes, approach_beats)
	for r in _fading:
		if r.get("tri", false):
			r.mat.set_shader_parameter("seg_gap", lerpf(0.2, 0.9, r.t))
		if r.has("mat2"):
			r.mat2.set_shader_parameter("alpha", r.mat.get_shader_parameter("alpha"))
			r.mat2.set_shader_parameter("seg_gap", lerpf(0.45, 0.95, r.t))
	_time += dt
	_idle += dt
	_active = move_toward(_active, 1.0 if _idle < idle_hold_seconds else 0.0, dt * (4.0 if _idle < idle_hold_seconds else 1.5))
	_boost = maxf(_boost - dt * 2.5, 0.0)
	_col_t = minf(_col_t + dt / maxf(phase_fade_seconds[sky_phase], 0.01), 1.0)
	_white = maxf(_white - dt / maxf(bright_flash_seconds, 0.05), 0.0)
	_holy = move_toward(_holy, 1.0 if sky_phase == 2 else 0.0, dt * (3.0 if sky_phase == 2 else 0.5))
	_earth = move_toward(_earth, 1.0 if sky_phase >= 3 else 0.0, dt * 0.25)
	_reveal = move_toward(_reveal, 1.0 if sky_phase >= 4 or _finale else 0.0, dt * 0.6)
	if _finale:
		_closeup = minf(_closeup + dt * _closeup_speed, 1.0)
	_speed = lerpf(_speed, rise_speeds[sky_phase] * (0.25 if _finale else 1.0), 1.0 - exp(-2.0 * dt))
	_apply_look()
	_update_clouds(dt)
	_update_storm(beat, dt)
	_rain.emitting = sky_phase == 1
	_sparks.emitting = sky_phase == 2
	_stars.emitting = sky_phase >= 3
	_overlay.queue_redraw()


# ---- 天空、云 ----

func _make_environment() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.08
	_env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = _env
	_vp.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_vp.add_child(_sun)
	_sun.look_at_from_position(Vector3(4.0, 12.0, 15.0), Vector3(0.0, 2.0, 0.0))


## 三层云：远的大而慢，中间的在猫后面，最近的一层在镜头前面扫过去（又大又淡又快）
func _make_clouds() -> void:
	var shader := Shader.new()
	shader.code = CLOUD_SHADER
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in cloud_count:
		var layer := i % 3
		var z: float = [rng.randf_range(-70.0, -35.0), rng.randf_range(-22.0, -6.0), rng.randf_range(5.0, 11.0)][layer]
		var size: float = [rng.randf_range(40.0, 70.0), rng.randf_range(16.0, 30.0), rng.randf_range(14.0, 22.0)][layer]
		var spread: float = [70.0, 26.0, 9.0][layer]
		var span: float = [90.0, 45.0, 26.0][layer]  # 上下各多远，出了下面从上面再来
		var q := QuadMesh.new()
		q.size = Vector2(size, size * 0.55)
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("seed", float(i) * 7.31)
		m.set_shader_parameter("drift", 0.02)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_space.add_child(mi)
		var x := rng.randf_range(-spread, spread)
		if layer == 2 and absf(x) < 4.0:
			x = 4.0 * signf(x + 0.001) + x  # 镜头前那层别正好挡住猫
		mi.position = Vector3(x, rng.randf_range(-span, span), z)
		_cloud_nodes.append({"node": mi, "mat": m, "span": span, "rate": [0.35, 1.0, 1.8][layer], "alpha": [1.0, 1.0, 0.45][layer]})


func _update_clouds(dt: float) -> void:
	var col: Color = _now.cloud
	var fall := _speed * (1.0 + hit_boost * _boost) * dt
	for c in _cloud_nodes:
		var node: MeshInstance3D = c.node
		node.position.y -= fall * c.rate
		if node.position.y < -c.span:
			node.position.y += c.span * 2.0
		node.visible = col.a > 0.01
		c.mat.set_shader_parameter("color", Color(col.r, col.g, col.b, col.a * c.alpha))


func _make_particles() -> void:
	# 雨（风暴）：斜着往下的细线
	_rain = _streaks(Color(0.6, 0.7, 1.0), Vector2(0.05, 2.2), 260, 70.0)
	_rain.direction = Vector3(-0.25, -1.0, 0.0)
	# 金色的碎光（亮起来）：慢慢往下飘
	_sparks = _streaks(Color(1.0, 0.9, 0.5), Vector2(0.16, 0.16), 90, 9.0)
	# 星星（太空）：往下流的短线
	_stars = _streaks(Color(0.9, 0.95, 1.0), Vector2(0.06, 0.7), 160, 26.0)
	# 火星（带样子的那一段）：猫周围慢慢往上飘、一闪一闪
	_embers = _ember_particles(45, false)
	_ember_burst = _ember_particles(16, true)
	_ember_big = _ember_particles(55, true)
	_ember_big.initial_velocity_min = 6.0
	_ember_big.initial_velocity_max = 12.0
	_ember_big.spread = 85.0
	_ember_big.lifetime = 1.0
	_ember_big.scale_amount_max = 2.4
	# 火柱：画面左右下角，往上喷
	for side in [-1.0, 1.0]:
		_pyro.append(_pyro_particles(Vector3(9.5 * side, -4.8, 3.0), side))


func _pyro_particles(at: Vector3, side: float) -> CPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var tex := GradientTexture2D.new()
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = soft
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	mat.albedo_texture = tex
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	q.material = mat
	var p := CPUParticles3D.new()
	p.mesh = q
	p.amount = 160
	p.one_shot = true
	p.explosiveness = 0.35
	p.lifetime = 0.7
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3(-0.1 * side, 1.0, 0.0)
	p.spread = 4.0
	p.initial_velocity_min = 13.0
	p.initial_velocity_max = 19.0
	p.gravity = Vector3(0.0, -4.0, 0.0)
	p.damping_min = 2.0
	p.damping_max = 5.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(1.3, 1.0, 0.5, 0.9), Color(1.2, 0.45, 0.06, 0.8), Color(0.8, 0.1, 0.01, 0.5), Color(0.15, 0.0, 0.0, 0.0)])
	p.color_ramp = ramp
	var size := Curve.new()
	size.add_point(Vector2(0.0, 1.0))
	size.add_point(Vector2(0.3, 1.3))
	size.add_point(Vector2(1.0, 0.25))
	p.scale_amount_curve = size
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.5
	p.position = at
	_space.add_child(p)
	return p


func _fire_pyro(skin: NoteSkin, big: bool) -> void:
	for p in _pyro:
		p.initial_velocity_min = 14.0 if big else 10.0
		p.initial_velocity_max = 20.0 if big else 15.0
		p.restart()
		p.emitting = true
	_shake = maxf(_shake, skin.pyro_shake)


## 转场音符到了（打没打中都放）：判定圈上炸开两道岩浆冲击波，两边火柱，大火星，红白闪，镜头往里一冲再抖
func _fire_impact(skin: NoteSkin) -> void:
	if _phase != Phase.LIFT or camera == null:
		return
	_impact = 1.0
	if impact_sky_phase >= 0 and sky_phase < impact_sky_phase:
		set_phase(impact_sky_phase)
	_shake = maxf(_shake, skin.impact_shake)
	_bolt = maxf(_bolt, 0.6)
	_fire_pyro(skin, true)
	if _ember_big and skin.embers:
		_ember_big.position = _cat.position - _rig.position
		_ember_big.color = skin.ember_hot
		_ember_big.restart()
		_ember_big.emitting = true
	var center := _cat.position - _rig.position
	for k in 2:
		var r := _make_ring()
		var node: MeshInstance3D = r.node
		node.mesh = _lava_mesh(skin.thickness if k == 0 else skin.triplet_halo_thickness)
		_place_ring(node, center.y)
		var m: ShaderMaterial = r.mat
		m.set_shader_parameter("color", skin.downbeat_color if k == 0 else skin.ring_color)
		m.set_shader_parameter("hot", skin.ember_hot)
		m.set_shader_parameter("dark", skin.lava_dark)
		m.set_shader_parameter("ember", skin.ember)
		m.set_shader_parameter("crack_gain", skin.triplet_crack_glow)
		_shocks.append({"node": node, "mat": m, "t": -0.12 * k, "r0": node.scale.x, "grow": skin.impact_size * (1.0 + 0.5 * k)})


func _has_note(at: float) -> bool:
	for n in _notes_ref:
		if absf(n.beat - at) < 0.02:
			return true
		if n.beat > at + 0.1:
			break
	return false


func _ember_particles(amount: int, burst: bool) -> CPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	q.material = mat
	var p := CPUParticles3D.new()
	p.mesh = q
	p.amount = amount
	p.emitting = false
	p.color = Color(1.0, 0.5, 0.1)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray([Color(1.6, 1.4, 1.0, 1.0), Color(1.2, 1.0, 1.0, 1.0), Color(0.6, 0.1, 0.0, 0.0)])
	p.color_ramp = fade
	var size := Curve.new()
	size.add_point(Vector2(0.0, 1.0))
	size.add_point(Vector2(1.0, 0.3))
	p.scale_amount_curve = size
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	if burst:
		p.one_shot = true
		p.explosiveness = 1.0
		p.lifetime = 0.7
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = beam_bottom_radius * ring_scale * 0.6
		p.emission_ring_inner_radius = p.emission_ring_radius * 0.9
		p.emission_ring_height = 0.1
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 8.0
		p.gravity = Vector3(0.0, -9.0, 0.0)
		p.damping_min = 1.0
		p.damping_max = 3.0
	else:
		p.lifetime = 2.5
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(7.0, 4.0, 3.0)
		p.direction = Vector3.UP
		p.spread = 25.0
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 4.0
		p.gravity = Vector3.ZERO
		p.position = Vector3(0.0, -2.0, 0.0)
	if burst:
		_rig.add_child(p)
	else:
		_space.add_child(p)
	return p


func _streaks(color: Color, size: Vector2, amount: int, speed: float) -> CPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	var q := QuadMesh.new()
	q.size = size
	q.material = mat
	var p := CPUParticles3D.new()
	p.mesh = q
	p.amount = amount
	p.lifetime = 90.0 / speed
	p.preprocess = 0.0
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(34.0, 2.0, 12.0)
	p.direction = Vector3.DOWN
	p.spread = 0.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = speed * 0.8
	p.initial_velocity_max = speed * 1.2
	p.position = Vector3(0.0, 36.0, -8.0)
	_space.add_child(p)
	return p


# ---- 阶段的颜色 ----

func _look(p: int) -> Dictionary:
	return {"top": sky_tops[p], "horizon": sky_horizons[p], "cloud": cloud_colors[p], "ambient": ambients[p],
			"energy": ambient_energies[p]}


func _current_look() -> Dictionary:
	var to := _look(sky_phase)
	var out := {}
	for k in to:
		out[k] = lerp(_from[k], to[k], _col_t)
	return out


func _apply_look() -> void:
	_now = _current_look()
	var flash := _bolt * 0.6
	var top: Color = _now.top
	var hor: Color = _now.horizon
	_sky_mat.sky_top_color = top.lerp(Color(0.7, 0.75, 1.0), flash * 0.5)
	_sky_mat.sky_horizon_color = hor.lerp(Color(0.9, 0.9, 1.0), flash)
	_sky_mat.ground_horizon_color = _sky_mat.sky_horizon_color
	_sky_mat.ground_bottom_color = top.lerp(hor, 0.35)
	_env.ambient_light_color = _now.ambient
	_env.ambient_light_energy = float(_now.energy) + flash * 1.5 + _closeup * 1.2  # 特写时把飞碟底下照亮一点
	_sun.light_color = (_now.ambient as Color).lerp(Color.WHITE, 0.5)
	_sun.light_energy = float(_now.energy) * 0.9 + flash * 2.0
	# 光柱：亮起来之后从绿的变成金白的，到太空再变回绿的
	var gold := _holy
	var beam := beam_color
	var core := beam_core_color
	if _skin and _skin_k > 0.0:
		beam = beam.lerp(Color(_skin.beam_color, 1.0), _skin.beam_color.a * _skin_k)
		core = core.lerp(Color(_skin.ring_color, 1.0), _skin.ring_color.a * _skin_k)
	_beam_mat.set_shader_parameter("color", beam.lerp(Color(1.0, 0.9, 0.55), gold))
	_spot.light_color = beam.lerp(core, 0.5).lerp(Color(1.0, 0.95, 0.8), gold)


func _update_storm(beat: float, dt: float) -> void:
	_bolt = maxf(_bolt - dt * 3.5, 0.0)
	if sky_phase != 1:
		_next_bolt = 0.0
		return
	if _next_bolt <= 0.0:
		_next_bolt = ceilf(beat) + 1.0
	if beat >= _next_bolt:
		_next_bolt = ceilf(beat) + maxf(roundf(randf_range(0.5, 1.5) * lightning_every_beats), 1.0) - 0.001
		_bolt = 1.0
		_shake = maxf(_shake, storm_shake * 3.0 * _active)
		# 一道锯齿形的闪电，从屏幕上面劈到中下
		var size := get_viewport_rect().size
		var x := randf_range(-0.42, 0.42) * size.x
		if absf(x) < size.x * 0.1:
			x += size.x * 0.15 * signf(x + 0.001)
		_bolt_points = PackedVector2Array()
		var y := -size.y * 0.5
		while y < size.y * randf_range(0.05, 0.35):
			_bolt_points.append(Vector2(x, y))
			x += randf_range(-60.0, 60.0)
			y += randf_range(40.0, 90.0)
	_shake = maxf(_shake, storm_shake * _active)


## 光圈的材质：暗的时候是发光的（和吸猫舞台一样），solid 往 1 走就变成不透明的实心色，亮背景上也看得清
func _ring_shader() -> Shader:
	if _ring_shader_cache == null:
		_ring_shader_cache = Shader.new()
		_ring_shader_cache.code = SKY_RING_SHADER
	return _ring_shader_cache


const SKY_RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(0.8, 1.0, 0.8, 1.0);
uniform float alpha = 1.0;
uniform float solid = 0.0;
// 岩浆（音符的样子，NoteSkin.ember，0~1）：整圈是 color 的红橙，里面暗色的壳（dark）沿着圈流动、翻滚，
// 壳之间的裂缝发亮（hot），边上一圈热光；越大越不透明（暗的壳才看得出来）
uniform float ember = 0.0;
uniform vec4 hot : source_color = vec4(1.0, 0.7, 0.2, 1.0);
uniform vec4 dark : source_color = vec4(0.12, 0.01, 0.0, 1.0);
uniform float flow = 0.6;
uniform float beat_pulse = 0.0;
uniform float crack_gain = 1.1;
// 断成几段（三连音 = 3；0 = 不断）、转到哪、每段之间空多少（0~1）
uniform float segments = 0.0;
uniform float seg_spin = 0.0;
uniform float seg_gap = 0.2;
varying float ang;
varying float tube;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}
void vertex() {
	ang = atan(VERTEX.z, VERTEX.x);
	// 管子截面上的角度：离中心线往外 / 往上
	tube = atan(VERTEX.y, length(VERTEX.xz) - 0.9);
}
void fragment() {
	vec3 c = color.rgb;
	float glow = 1.0;
	if (segments > 0.5) {
		float s = fract((ang - seg_spin) / 6.2831853 * segments);
		float half_gap = seg_gap * 0.5;
		if (s < half_gap || s > 1.0 - half_gap) {
			discard;
		}
		float mid = 1.0 - abs(s - 0.5) / (0.5 - half_gap);
		glow = mix(0.6, 1.25, smoothstep(0.0, 0.7, mid));
	}
	float body = 0.0;
	if (ember > 0.0) {
		// 圈绕一周是 12 格，往一个方向流，再用噪声扭一下（暗流翻滚）
		vec2 p = vec2(ang / 6.2831853 * 12.0, tube * 0.9);
		p.x -= TIME * flow;
		vec2 warp = vec2(fbm(p * 1.3 + vec2(0.0, TIME * 0.35)), fbm(p * 1.1 + vec2(5.2, -TIME * 0.3)));
		float n = fbm(p + warp * 1.6);
		float crust = smoothstep(0.4, 0.55, n);  // 暗壳
		float crack = 1.0 - smoothstep(0.26, 0.38, n);  // 最亮的裂缝
		vec3 lava = mix(c, dark.rgb, crust * 0.95);
		lava += hot.rgb * crack * crack_gain * (1.0 + beat_pulse * 0.7);
		// 边上一圈热光（侧着看的地方）
		float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
		lava += c * rim * 1.2;
		lava *= 1.0 + beat_pulse * 0.25;
		c = mix(c * 1.6, lava, ember);
		body = ember;
	}
	float s_amt = max(solid, body * 0.85);
	ALBEDO = c * glow * mix(1.6, 1.0, max(solid, body)) * alpha;
	ALPHA = s_amt * alpha;
}
"""


# ---- 猫、镜头 ----

func _update_cat(beat: float, dt: float) -> void:
	super(beat, dt)
	if _phase != Phase.LIFT:
		return
	# 一直浮在光柱里：上下浮、左右晃（吸猫舞台里要升起来才晃，这里从头就晃）
	_cat.position += Vector3(sin(beat * PI * 0.25) * 0.3, sin(beat * PI * 0.5) * float_bob + _boost * 0.35, 0.0)
	_cat.rotation.z = sin(beat * PI * 0.5) * deg_to_rad(float_tilt_degrees)
	if _skin and _skin_k > 0.0 and _skin.headbang_degrees > 0.0:
		# 甩头：每 headbang_every 拍往前一点头（快下、慢回）
		var k := fposmod(beat, maxf(_skin.headbang_every, 0.25)) / maxf(_skin.headbang_every, 0.25)
		var nod := pow(1.0 - k, 3.0) if k > 0.04 else k / 0.04
		_cat.rotation.x = deg_to_rad(_skin.headbang_degrees) * nod * _skin_k * (1.0 - _holy)
	else:
		_cat.rotation.x = 0.0


func _apply_camera(beat: float, dt: float) -> void:
	_shake = maxf(_shake - dt * 2.0, 0.0)
	var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake
	var sway := Vector3(sin(beat * PI * 0.25) * camera_sway * _active, 0.0, 0.0)
	var r := smoothstep(0.0, 1.0, _reveal)
	var c := smoothstep(0.0, 1.0, _closeup)
	var pos := camera_position.lerp(reveal_position, r).lerp(closeup_position, c)
	# 特写：跟着被吸上去的猫，猫进去之后看着飞碟飞走
	var top := _beam_top + _rig.position + Vector3.DOWN * 2.0
	var follow := _cat.position.lerp(top, 0.35) if _cat.visible else top
	_follow = follow if _closeup <= 0.0 else _follow.lerp(follow, 1.0 - exp(-5.0 * dt))
	var target := camera_target.lerp(reveal_target, r).lerp(_follow, c)
	camera.fov = lerpf(camera_fov, closeup_fov, c) - (_skin.impact_punch if _skin else 0.0) * pow(_impact, 2.0)
	camera.position = pos + sway + jitter
	camera.look_at(target + jitter * 0.5)


# ---- 音符的样子（NoteSkin）：光圈的颜色、荆棘、三连音的圈、画面的暗角和滴血 ----

## 画面上的样子跟着「现在这一段」：还没判定、最近要打的那个音符带的样子（新的一段的音符一出现，画面就开始换）
func _update_skin(beat: float, notes: Array[NoteData], dt: float) -> void:
	var want: NoteSkin = null
	if use_note_skins and _phase == Phase.LIFT and not _finale:
		# 最近一个到了拍子的音符（打没打中都算）带的样子；这一段的第一个到了 = 转场音符到了：冲击，样子一下换上
		var seen := false
		for n in notes:
			if n.beat > beat + 0.01:
				break
			want = n.skin
			seen = true
		if not seen:
			want = _skin_at
		if want != _skin_at:
			_skin_at = want
			if want:
				_fire_impact(want)
				_skin = want
				_skin_k = 1.0
	var step := dt / maxf(skin_fade_seconds, 0.01)
	if want and want == _skin:
		_skin_k = minf(_skin_k + step, 1.0)
	else:
		_skin_k = maxf(_skin_k - step, 0.0)
		if _skin_k <= 0.0:
			_skin = want
	var sk := _skin_k if _skin else 0.0
	if _embers:
		_embers.emitting = sk > 0.5 and _skin.embers and _holy < 0.5
		if _skin:
			_embers.color = _skin.ember_hot
	_env.adjustment_enabled = sk > 0.001
	if _skin:
		_env.adjustment_contrast = lerpf(1.0, _skin.contrast, sk)
		_env.adjustment_saturation = lerpf(1.0, _skin.saturation, sk)


## 光圈的颜色和着色器参数（吸猫舞台按重点标记上过色之后再改）：音符带着样子就换成样子里的颜色、开熔岩流光，
## 三连音断成三段转着的金色弧
func _color_rings(beat: float, notes: Array[NoteData], approach_beats: float) -> void:
	if _phase != Phase.LIFT or not use_note_skins:
		return
	for n in notes:
		if n.judged:
			continue
		if n.beat - beat > approach_beats:
			break
		var key := n.get_instance_id()
		if not _rings.has(key):
			continue
		if not _triplet.has(key):
			_triplet[key] = _is_triplet(n, notes)
			var prev: NoteData = null
			for m in notes:
				if m == n:
					break
				prev = m
			_impact_note[key] = n.skin != null and (prev == null or prev.skin != n.skin) and n.skin != _skin_at
		var tri: bool = _triplet[key]
		var impact: bool = _impact_note.get(key, false)
		if n.skin == null and not tri:
			continue
		var skin: NoteSkin = n.skin if n.skin else _plain_skin
		var r: Dictionary = _rings[key]
		var c := _ring_color0
		var kind := NoteAccents.Kind.NONE
		if accents:
			var mark := accents.look(n, _ring_color0)
			kind = mark.kind
			if kind != NoteAccents.Kind.NONE:
				c = mark.color
		var m: ShaderMaterial = r.mat
		if kind == NoteAccents.Kind.FEVER:
			m.set_shader_parameter("ember", 0.0)
			m.set_shader_parameter("segments", 0.0)
			continue
		var hot := skin.ember_hot
		if n.skin:
			var to := skin.downbeat_color if kind == NoteAccents.Kind.DOWNBEAT else skin.ring_color
			c = c.lerp(Color(to, 1.0), to.a)
		if tri:
			c = skin.triplet_color
			hot = skin.triplet_hot
		var lava := (skin.ember if n.skin else 0.0) if not tri else skin.triplet_ember
		lava *= 1.0 - _holy
		m.set_shader_parameter("color", c.lerp(bright_ring_color, _holy))
		m.set_shader_parameter("hot", hot)
		m.set_shader_parameter("dark", skin.lava_dark if not tri else skin.triplet_dark)
		m.set_shader_parameter("ember", lava)
		m.set_shader_parameter("flow", skin.lava_flow)
		var pulse := pow(1.0 - fposmod(beat, 1.0), 3.0)
		m.set_shader_parameter("beat_pulse", pulse)
		m.set_shader_parameter("crack_gain", skin.triplet_crack_glow if tri else skin.crack_glow)
		if tri and skin.triplet_throb > 0.0:
			# 三连音：管子跟拍子一胀一胀（只胀粗细，半径不变，和判定圈对得上）
			var node: Node3D = r.node
			node.scale = Vector3(node.scale.x, node.scale.x * (1.0 + skin.triplet_throb * pulse), node.scale.z)
		m.set_shader_parameter("segments", 3.0 if tri else 0.0)
		m.set_shader_parameter("seg_spin", beat * skin.triplet_spin * TAU)
		var thick := skin.thickness if not tri else skin.triplet_thickness
		if thick > ring_thickness:
			(r.node as MeshInstance3D).mesh = _lava_mesh(thick)
		if impact:
			(r.node as MeshInstance3D).mesh = _lava_mesh(skin.triplet_thickness)
			m.set_shader_parameter("crack_gain", skin.triplet_crack_glow)
		if (tri or impact) and skin.triplet_halo > 0.0:
			_halo(r, m, skin, beat, pulse, 0.0 if impact else 3.0)


## 三连音外面再套一圈细的光环（大一圈，跟拍子往外呼吸）：也是三段，和里面的错开、反着转。里面那圈和判定圈一样大，对拍子不受影响
func _halo(r: Dictionary, inner: ShaderMaterial, skin: NoteSkin, beat: float, pulse: float, segments := 3.0) -> void:
	if not r.has("halo"):
		var m := ShaderMaterial.new()
		m.shader = _ring_shader()
		var mi := MeshInstance3D.new()
		mi.mesh = _lava_mesh(skin.triplet_halo_thickness)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(r.node as Node3D).add_child(mi)
		r["halo"] = mi
		r["mat2"] = m
	var m2: ShaderMaterial = r.mat2
	for k in ["color", "hot", "dark", "ember", "flow", "beat_pulse", "crack_gain", "alpha"]:
		m2.set_shader_parameter(k, inner.get_shader_parameter(k))
	m2.set_shader_parameter("segments", segments)
	m2.set_shader_parameter("seg_gap", 0.45)
	m2.set_shader_parameter("seg_spin", -beat * skin.triplet_spin * TAU + PI / 3.0)
	var halo: Node3D = r.halo
	var grow := skin.triplet_halo * (1.0 + 0.2 * pulse)
	# 子节点跟着光圈的缩放；把里面那圈胀粗细的那一下抵掉，光环自己按 halo 的大小
	var parent: Node3D = r.node
	halo.scale = Vector3(1.0 + grow, (1.0 + grow) * parent.scale.x / maxf(parent.scale.y, 0.001), 1.0 + grow)


func _lava_mesh(thick: float) -> TorusMesh:
	var key := snappedf(thick, 0.01)
	if not _lava_meshes.has(key):
		var t := TorusMesh.new()
		t.inner_radius = 1.0 - key
		t.outer_radius = 1.0
		t.rings = 64
		t.ring_segments = 16
		_lava_meshes[key] = t
	return _lava_meshes[key]


## 三连音：记号写了就听记号；自动 = 这一段的样子开着自动判（没样子的音符不自动判）：
## 拍子落在三分之一 / 三分之二上，或者后面三分之二拍还有一个（三连的第一个）
static func _is_triplet(n: NoteData, notes: Array[NoteData]) -> bool:
	if n.mark == NoteData.Mark.TRIPLET:
		return true
	if n.mark == NoteData.Mark.PLAIN or n.skin == null or not n.skin.auto_triplets:
		return false
	var f := fposmod(n.beat, 1.0)
	if absf(f - 1.0 / 3.0) < 0.02 or absf(f - 2.0 / 3.0) < 0.02:
		return true
	var next := n.beat + 2.0 / 3.0
	for m in notes:
		if absf(m.beat - next) < 0.02:
			return true
		if m.beat > next + 0.1:
			break
	return false


## 画面四周的暗角（跟拍子轻轻一呼一吸）
func _draw_skin_screen(size: Vector2) -> void:
	if _skin.vignette <= 0.0:
		return
	if _vignette_tex == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.1), Color(1, 1, 1, 1)])
		_vignette_tex = GradientTexture2D.new()
		_vignette_tex.gradient = grad
		_vignette_tex.fill = GradientTexture2D.FILL_RADIAL
		_vignette_tex.fill_from = Vector2(0.5, 0.5)
		_vignette_tex.fill_to = Vector2(1.0, 0.5)
		_vignette_tex.width = 256
		_vignette_tex.height = 256
	var pulse := pow(1.0 - fposmod(Conductor.song_beat, 1.0), 4.0)
	var big := size * 1.2
	_overlay.draw_texture_rect(_vignette_tex, Rect2(-big * 0.5, big), false,
			Color(_skin.vignette_color, _skin.vignette * _skin_k * (1.0 - _holy) * (0.9 + 0.1 * pulse)))


# ---- 画在 3D 画面上面的：闪电、光芒、地球、白闪 ----

func _draw_overlay() -> void:
	var size := get_viewport_rect().size
	var half := size * 0.5
	if _earth > 0.0 and _closeup < 1.0:
		# 地球的弧线：一个很大的圆从屏幕底下露一点，慢慢沉下去
		var radius := size.x * 1.6
		var center := Vector2(0.0, half.y + radius - size.y * 0.16 * sin(_earth * PI) * (1.0 - _reveal))
		_overlay.draw_circle(center, radius + 14.0, Color(0.45, 0.75, 1.0, 0.25))
		_overlay.draw_circle(center, radius, Color(0.06, 0.2, 0.5))
		_overlay.draw_arc(center, radius, PI * 1.2, PI * 1.8, 96, Color(0.7, 0.9, 1.0, 0.9), 3.0, true)
	if _holy > 0.0 and bright_shade > 0.0 and camera:
		# 猫周围垫一圈暗影（中间深、往外淡），圈和猫才从亮背景里分得出来
		var at := hit_screen_offset()
		var r := ring_screen_radius() * 4.2
		if _shade_tex == null:
			var grad := Gradient.new()
			grad.set_color(0, Color(1, 1, 1, 1))
			grad.set_color(1, Color(1, 1, 1, 0))
			_shade_tex = GradientTexture2D.new()
			_shade_tex.gradient = grad
			_shade_tex.fill = GradientTexture2D.FILL_RADIAL
			_shade_tex.fill_from = Vector2(0.5, 0.5)
			_shade_tex.fill_to = Vector2(1.0, 0.5)
			_shade_tex.width = 256
			_shade_tex.height = 256
		_overlay.draw_texture_rect(_shade_tex, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(0.12, 0.05, 0.25, bright_shade * _holy))
	if _holy > 0.0:
		# 光芒：从屏幕上面正中散开的几道金光，慢慢转
		var origin := Vector2(0.0, -half.y * 1.25)
		for i in 9:
			var a := PI * 0.5 + (float(i) - 4.0) * 0.26 + sin(_time * 0.3 + i) * 0.05
			var w := 0.035 + 0.02 * sin(_time * 0.7 + i * 2.1)
			var far := size.y * 2.2
			var pts := PackedVector2Array([origin, origin + Vector2(cos(a - w), sin(a - w)) * far, origin + Vector2(cos(a + w), sin(a + w)) * far])
			_overlay.draw_colored_polygon(pts, Color(1.0, 0.93, 0.6, 0.09 * _holy))
	if _skin and _skin_k > 0.01:
		_draw_skin_screen(size)
	if _bolt > 0.0 and _bolt_points.size() > 1:
		var glow := Color(0.8, 0.85, 1.0)
		if _skin:
			glow = glow.lerp(Color(_skin.bolt_color, 1.0), _skin.bolt_color.a * _skin_k)
		_overlay.draw_polyline(_bolt_points, Color(glow, _bolt * 0.5), 14.0)
		_overlay.draw_polyline(_bolt_points, Color(1.0, 1.0, 1.0, _bolt), 4.0)
		_overlay.draw_rect(Rect2(-half, size), Color(glow, _bolt * 0.18))
	if _impact > 0.0:
		var flash := Color(1.0, 0.95, 0.9).lerp(Color(0.85, 0.0, 0.03), 1.0 - _impact)
		_overlay.draw_rect(Rect2(-half, size), Color(flash, 0.35 * pow(_impact, 2.0)))
	if _strobe > 0.0:
		var sc := Color(1.0, 0.92, 0.85) if _strobe_n % 2 == 0 else Color(0.9, 0.0, 0.05)
		_overlay.draw_rect(Rect2(-half, size), Color(sc, _strobe * 0.32))
	var white := maxf(_white, _flash * 0.7 if _finale else 0.0)
	if white > 0.0:
		_overlay.draw_rect(Rect2(-half, size), Color(1.0, 0.94, 0.8, minf(white * 1.3, 1.0)))
