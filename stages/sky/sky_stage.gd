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
@export var phase_fade_seconds := PackedFloat32Array([1.0, 2.0, 0.25, 4.0, 2.5])

@export_group("亮起来时看得清")
## 天亮了以后，发光的白圈在亮背景上看不见，所以这一段：光圈和判定线换成深色的实心圈，
## 光柱调暗（不然猫和圈都泡在一片白里），猫周围垫一圈淡淡的暗影
@export var bright_ring_color := Color(0.42, 0.05, 0.62)
@export var bright_judge_color := Color(0.85, 0.0, 0.45)
## 这一段光柱的亮度乘多少
@export_range(0.0, 1.0) var bright_beam_scale := 0.4
## 猫周围的暗影多深（0 = 不垫）
@export_range(0.0, 1.0) var bright_shade := 0.4

@export_group("风暴")
## 平均几拍打一次闪电
@export var lightning_every_beats := 3.0
@export var storm_shake := 0.12

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
		_white = 1.0  # 亮起来：先全白
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
	super(note, result)
	if result != NoteData.Result.MISS:
		_boost = 1.0
		_idle = 0.0


func update(beat: float, notes: Array[NoteData], approach_beats: float) -> void:
	# 亮背景上换成深色的圈、调暗光柱（要在吸猫舞台算这一帧之前定好）
	ring_color = _ring_color0.lerp(bright_ring_color, _holy)
	judge_ring_color = _judge_color0.lerp(bright_judge_color, _holy)
	beam_energy = _beam_energy0 * lerpf(1.0, bright_beam_scale, _holy)
	beam_light_energy = _beam_light0 * lerpf(1.0, bright_beam_scale, _holy)
	for key in _rings:
		_rings[key].mat.set_shader_parameter("color", ring_color)
		_rings[key].mat.set_shader_parameter("solid", _holy)
	super(beat, notes, approach_beats)
	if _space == null:
		return
	var dt := get_process_delta_time()
	_time += dt
	_idle += dt
	_active = move_toward(_active, 1.0 if _idle < idle_hold_seconds else 0.0, dt * (4.0 if _idle < idle_hold_seconds else 1.5))
	_boost = maxf(_boost - dt * 2.5, 0.0)
	_col_t = minf(_col_t + dt / maxf(phase_fade_seconds[sky_phase], 0.01), 1.0)
	_white = maxf(_white - dt * 0.9, 0.0)
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
	_beam_mat.set_shader_parameter("color", beam_color.lerp(Color(1.0, 0.9, 0.55), gold))
	_spot.light_color = beam_color.lerp(beam_core_color, 0.5).lerp(Color(1.0, 0.95, 0.8), gold)


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
void fragment() {
	// 预乘：ALPHA = 0 时是纯加色（发光），ALPHA = 1 时是盖住背景的实心色
	ALBEDO = color.rgb * mix(1.6, 1.0, solid) * alpha;
	ALPHA = solid * alpha;
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
	camera.fov = lerpf(camera_fov, closeup_fov, c)
	camera.position = pos + sway + jitter
	camera.look_at(target + jitter * 0.5)


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
	if _bolt > 0.0 and _bolt_points.size() > 1:
		_overlay.draw_polyline(_bolt_points, Color(0.8, 0.85, 1.0, _bolt * 0.5), 14.0)
		_overlay.draw_polyline(_bolt_points, Color(1.0, 1.0, 1.0, _bolt), 4.0)
		_overlay.draw_rect(Rect2(-half, size), Color(0.8, 0.85, 1.0, _bolt * 0.18))
	var white := maxf(_white, _flash * 0.7 if _finale else 0.0)
	if white > 0.0:
		_overlay.draw_rect(Rect2(-half, size), Color(1.0, 1.0, 0.96, minf(white * 1.3, 1.0)))
