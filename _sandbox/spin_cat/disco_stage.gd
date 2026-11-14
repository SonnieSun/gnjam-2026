class_name DiscoStage
extends Node2D
## 迪斯科猫砂盆关卡的「舞台导演」：根据进度推进 / 倒退阶段，并负责运镜、灯光和跟拍律动。
## 进度 progress：成功 +1，Miss -1（最少 0，最多 drift_at + drift_steps）。
##   开场       镜头很近，只有猫和猫砂盆，房间很暗
##   每 +1      镜头拉远一档
##   stars_at   星星灯掉下来，场景变亮
##   ball_at    迪斯科灯球掉下来并一直转，彩色光斑扫场
##   cats_at    2D 跳舞猫从两边进场
##   drift_at   猫离开猫砂盆，一边慢慢转、一边歪来歪去，沿着房间里的路线漂；
##              之后每 +1 往前漂一段，每 -1 往回漂一段，漂满 drift_steps 段到终点
## 进度掉回某个阶段的门槛以下，那个阶段的东西会收回去（灯升回去、猫退场……）。
## 用法：把它加到关卡里，调 setup(猫)；每帧调 update(拍数)；成功调 add_success()，Miss 调 add_miss()。
## 3D 的东西都在 SpinCat3D 的 3D 世界里，这里只是摆弄它们。房间里的 Stars/*、DiscoBall 是空的
## 定位点，下面没有模型时这里自动放占位模型；DriftPath/* 是漂移路线依次经过的点（起点是猫砂盆）。
## 测试用，只在本机 _sandbox 里，不进仓库。

signal stage_changed(stage: int)

@export_group("阶段（进度到多少时触发）")
@export var stars_at := 5
@export var ball_at := 10
@export var cats_at := 15
@export var drift_at := 20
## 漂移路线分成几段走完（到终点一共要再成功这么多次）
@export var drift_steps := 80

@export_group("运镜")
## 开场镜头有多近：画面高度 = 猫的高度 × 这个倍数
@export var close_zoom := 1.15
## 星星灯掉下来时镜头已经拉远到多少（0 = 开场，1 = 看到整个房间）
@export_range(0.0, 1.0) var zoom_at_stars := 0.7
## 镜头跟上目标的快慢（越大越快）
@export var zoom_speed := 4.0
## 每拍镜头往里「顶」一下的幅度（占画面的比例），按阶段 0 / 1 / 2 / 3 / 4 分别设
@export var beat_punch := PackedFloat32Array([0.0, 0.02, 0.045, 0.06, 0.06])
## 镜头左右摇摆的角度（度），按阶段分别设
@export var sway_degrees := PackedFloat32Array([0.0, 3.0, 7.0, 9.0, 9.0])
## 摇摆一个来回用几拍
@export var sway_beats := 8.0
## 镜头歪头（倾斜）的角度（度），按阶段分别设
@export var roll_degrees := PackedFloat32Array([0.0, 0.0, 2.5, 4.0, 4.0])
## 歪头一个来回用几拍
@export var roll_beats := 4.0
## 进入新阶段时镜头猛地拉远再弹回来的幅度
@export var stage_kick := 0.18

@export_group("灯光")
## 开场 / 变亮之后 的环境光和主光强度
@export var dark_ambient := 0.16
@export var dark_key := 0.22
@export var bright_ambient := 0.55
@export var bright_key := 0.95
## 小屋外面的底色：开场 / 变亮之后
@export var dark_background := Color(0.05, 0.03, 0.09)
@export var bright_background := Color(0.2, 0.08, 0.28)
@export var star_colors: Array[Color] = [
	Color(1.0, 0.85, 0.2), Color(1.0, 0.35, 0.7), Color(0.3, 0.8, 1.0), Color(1.0, 0.8, 0.25),
]
@export var spot_colors: Array[Color] = [
	Color(1.0, 0.2, 0.8), Color(0.2, 0.9, 1.0), Color(1.0, 0.85, 0.2), Color(0.6, 0.3, 1.0),
]
## 灯球转一圈用几拍
@export var ball_beats_per_rev := 8.0

@export_group("2D 跳舞猫")
## MemeLib 里的名字，从左到右
@export var dancers := PackedStringArray(["oiia", "banana", "apple", "nyanrun"])
## 每只猫相对屏幕中心的位置
@export var dancer_positions := PackedVector2Array([
	Vector2(-480, 150), Vector2(-330, 60), Vector2(330, 60), Vector2(480, 150),
])
@export var dancer_height := 190.0
## 每拍跳起来多高（像素）
@export var dancer_hop := 22.0
## 动图放一遍用几拍
@export var dancer_loop_beats := 2.0

@export_group("漂移")
## 猫沿路线移动、跟上进度的快慢（越大越快）
@export var drift_speed := 2.5
## 漂移时猫自己慢慢转，转一圈用几秒
@export var drift_spin_seconds := 4.0
## 漂移时猫歪来歪去的角度（度）
@export var drift_tilt_degrees := 18.0
## 歪一个来回用几拍
@export var drift_tilt_beats := 4.0
## 漂移时上下浮动的幅度（3D 单位）和一个来回的拍数
@export var drift_bob := 0.35
@export var drift_bob_beats := 2.0

var progress := 0
var stage := 0
## 由外面（积累条）来推进阶段和镜头。打开后 add_success() / add_miss() 不再起作用，
## 改用 enter_stage(第几阶段) 和 external_zoom（0 = 开场特写，1 = 整个房间）。
var external := false
var external_zoom := 0.0

var _cat: SpinCat3D
var _full_size := 1.0
var _zoom := 0.0  # 0 = 开场特写，1 = 整个房间
var _kick := 0.0
var _last_time := 0.0
var _stars: Array[Node3D] = []
var _star_rest: Array[Vector3] = []
var _star_mats: Array[StandardMaterial3D] = []
var _star_lights: Array[OmniLight3D] = []
var _ball: Node3D
var _ball_rest := Vector3.ZERO
var _spot_rig: Node3D
var _dancers: Array[MemeSprite] = []
var _tweens := {}  # 每样东西同时只留一个动画
var _path := Curve3D.new()
var _drift := 0.0  # 现在漂到路线的哪里（0 = 猫砂盆，1 = 终点）
var _spin_phase := 0.0


func setup(cat: SpinCat3D) -> void:
	_cat = cat
	_full_size = cat.camera.size
	_last_time = Time.get_ticks_msec() / 1000.0

	cat.environment.ambient_light_energy = dark_ambient
	cat.environment.background_color = dark_background
	cat.environment.glow_enabled = true
	cat.environment.glow_intensity = 0.6
	cat.key_light.light_energy = dark_key

	var room := cat.backdrop_node
	var star_mesh := _make_star_mesh(0.8, 0.38, 0.3)
	for marker in room.get_node("Stars").get_children():
		var star := marker as Node3D
		var i := _stars.size()
		var color := star_colors[i % star_colors.size()]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if star.get_child_count() == 0:
			var mesh := MeshInstance3D.new()
			mesh.mesh = star_mesh
			mesh.material_override = mat
			mesh.rotation.y = deg_to_rad(45.0)  # 正对镜头
			star.add_child(mesh)
			star.add_child(_make_cord(12.0, 0.8))
		var light := OmniLight3D.new()
		light.light_color = color
		light.omni_range = 9.0
		light.light_energy = 0.0
		star.add_child(light)
		_stars.append(star)
		_star_rest.append(star.position)
		_star_mats.append(mat)
		_star_lights.append(light)
		star.position.y += 30.0  # 先藏到天花板上面

	_ball = room.get_node("DiscoBall")
	_ball_rest = _ball.position
	if _ball.get_child_count() == 0:
		var ball_mesh := SphereMesh.new()
		ball_mesh.radius = 1.3
		ball_mesh.height = 2.6
		ball_mesh.radial_segments = 12
		ball_mesh.rings = 6
		var ball_mat := StandardMaterial3D.new()
		ball_mat.albedo_color = Color(0.85, 0.8, 0.95)
		ball_mat.metallic = 0.9
		ball_mat.roughness = 0.25
		ball_mat.emission_enabled = true
		ball_mat.emission = Color(0.6, 0.4, 0.9)
		ball_mat.emission_energy_multiplier = 0.5
		ball_mesh.material = ball_mat
		var ball := MeshInstance3D.new()
		ball.mesh = ball_mesh
		_ball.add_child(ball)
		_ball.add_child(_make_cord(12.0, 1.3))
	# 彩色射灯：挂在灯球上，跟着灯球转，在地板和墙上扫出光斑
	_spot_rig = Node3D.new()
	_ball.add_child(_spot_rig)
	for i in spot_colors.size():
		var spot := SpotLight3D.new()
		spot.light_color = spot_colors[i]
		spot.light_energy = 0.0
		spot.spot_range = 40.0
		spot.spot_angle = 16.0
		spot.rotation_degrees = Vector3(-52.0, i * 360.0 / spot_colors.size(), 0.0)
		_spot_rig.add_child(spot)
	_ball.position.y += 30.0

	# 漂移路线：猫砂盆（原点）-> DriftPath 下面的点，按顺序连成一条圆滑的线
	var pts: Array[Vector3] = [Vector3.ZERO]
	for p in room.get_node("DriftPath").get_children():
		pts.append((p as Node3D).position)
	for i in pts.size():
		var prev := pts[maxi(i - 1, 0)]
		var next := pts[mini(i + 1, pts.size() - 1)]
		var handle := (next - prev) / 6.0
		_path.add_point(pts[i], -handle, handle)

	_apply_camera(0.0)


## 成功一次（Perfect / Good）：进度 +1
func add_success() -> void:
	if not external:
		_set_progress(progress + 1)


## Miss 一次：进度 -1
func add_miss() -> void:
	if not external:
		_set_progress(progress - 1)


## 直接推进到第 which 阶段（1 = 星星灯，2 = 灯球，3 = 跳舞猫）。只进不退。
func enter_stage(which: int) -> void:
	while stage < which:
		stage += 1
		_enter_stage(stage)


## 猫现在在屏幕上的位置（相对屏幕中心，像素），判定圈跟着它走
func cat_screen_offset() -> Vector2:
	if _cat == null:
		return Vector2.ZERO
	var screen := Vector2(_cat.world.size)
	return _cat.camera.unproject_position(_cat.focus + _cat.pose_position) - screen / 2.0


## 每帧调用，beat = 当前歌曲拍数
func update(beat: float) -> void:
	if _cat == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var delta := minf(now - _last_time, 0.1)
	_last_time = now
	_zoom = lerpf(_zoom, _target_zoom(), 1.0 - exp(-zoom_speed * delta))
	_apply_camera(beat)

	var pulse := exp(-fposmod(beat, 1.0) * 5.0)  # 每拍开头 = 1，然后很快落回 0
	if stage >= 1:
		for i in _stars.size():
			# 相邻的星星隔拍轮流亮
			var mine := exp(-fposmod(beat + i % 2, 2.0) * 3.0)
			_star_mats[i].emission_energy_multiplier = 1.0 + mine * 3.0
			_star_lights[i].light_energy = 0.6 + mine * 1.6
			_stars[i].scale = Vector3.ONE * (1.0 + mine * 0.25)
			_stars[i].rotation.z = sin(beat * PI / 2.0 + i) * 0.15
	if stage >= 2:
		_ball.rotation.y = beat / ball_beats_per_rev * TAU
		_ball.scale = Vector3.ONE * (1.0 + pulse * 0.08)
		for spot in _spot_rig.get_children():
			(spot as SpotLight3D).light_energy = 5.0 + pulse * 6.0
	for i in _dancers.size():
		var d := _dancers[i]
		d.set_progress(beat / dancer_loop_beats + i * 0.25)
		d.offset.y = -absf(sin((beat + i * 0.5) * PI)) * dancer_hop / d.scale.y

	# 漂移：位置慢慢跟上进度；刚离开猫砂盆的第一段里，自转 / 歪头 / 浮动渐渐加上
	var target := clampf(float(progress - drift_at) / drift_steps, 0.0, 1.0)
	_drift = lerpf(_drift, target, 1.0 - exp(-drift_speed * delta))
	var float_amount := smoothstep(0.0, 1.0 / drift_steps, _drift)
	var bob := sin(beat / drift_bob_beats * TAU) * drift_bob * float_amount
	_cat.pose_position = _path.sample_baked(_drift * _path.get_baked_length(), true) + Vector3.UP * bob
	# 自转用真实时间累加（进度倒退时不会倒着转）；回到猫砂盆时转回正面
	if float_amount > 0.0:
		_spin_phase = fposmod(_spin_phase + delta / drift_spin_seconds, 1.0)
	else:
		_spin_phase = 0.0
	_cat.pose_yaw = _spin_phase * TAU * float_amount
	var tilt := deg_to_rad(drift_tilt_degrees) * float_amount
	var phase := beat / drift_tilt_beats * TAU
	_cat.pose_tilt = Vector2(sin(phase), cos(phase * 0.5)) * tilt


func _set_progress(value: int) -> void:
	progress = clampi(value, 0, drift_at + drift_steps)
	var new_stage := 0
	for at in [stars_at, ball_at, cats_at, drift_at]:
		if progress >= at:
			new_stage += 1
	while stage < new_stage:
		stage += 1
		_enter_stage(stage)
	while stage > new_stage:
		_leave_stage(stage)
		stage -= 1


func _target_zoom() -> float:
	if external:
		return clampf(external_zoom, 0.0, 1.0)
	var s := float(progress)
	if s <= stars_at:
		return s / stars_at * zoom_at_stars
	return lerpf(zoom_at_stars, 1.0, clampf((s - stars_at) / (ball_at - stars_at), 0.0, 1.0))


func _enter_stage(which: int) -> void:
	# 镜头猛地往外一甩再弹回来
	_kick = stage_kick
	_tween(self).tween_property(self, "_kick", 0.0, 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	match which:
		1:
			for i in _stars.size():
				var t := _tween(_stars[i])
				t.tween_interval(i * 0.08)
				t.tween_property(_stars[i], "position", _star_rest[i], 0.7) \
						.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_set_lights(bright_ambient, bright_key, bright_background)
		2:
			_tween(_ball).tween_property(_ball, "position", _ball_rest, 0.8) \
					.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		3:
			for i in dancers.size():
				var d := MemeSprite.create(dancers[i], dancer_height)
				var home := dancer_positions[i]
				d.flip_h = home.x > 0.0
				d.position = Vector2(signf(home.x) * 900.0, home.y)
				add_child(d)
				_dancers.append(d)
				var t := _tween(d)
				t.tween_interval(i * 0.12)
				t.tween_property(d, "position", home, 0.5) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	stage_changed.emit(which)


## 进度掉回门槛以下：把这个阶段的东西收回去
func _leave_stage(which: int) -> void:
	match which:
		1:
			for i in _stars.size():
				_tween(_stars[i]).tween_property(_stars[i], "position",
						_star_rest[i] + Vector3.UP * 30.0, 0.5).set_ease(Tween.EASE_IN)
				_star_lights[i].light_energy = 0.0
				_star_mats[i].emission_energy_multiplier = 1.0
			_set_lights(dark_ambient, dark_key, dark_background)
		2:
			_tween(_ball).tween_property(_ball, "position", _ball_rest + Vector3.UP * 30.0, 0.5) \
					.set_ease(Tween.EASE_IN)
			for spot in _spot_rig.get_children():
				(spot as SpotLight3D).light_energy = 0.0
		3:
			for d in _dancers:
				var t := _tween(d)
				t.tween_property(d, "position:x", signf(d.position.x) * 900.0, 0.4) \
						.set_ease(Tween.EASE_IN)
				t.tween_callback(d.queue_free)
			_dancers.clear()
	stage_changed.emit(which - 1)


func _set_lights(ambient: float, key: float, background: Color) -> void:
	var env := _cat.environment
	var t := _tween(env).set_parallel()
	t.tween_property(env, "ambient_light_energy", ambient, 0.8)
	t.tween_property(env, "background_color", background, 0.8)
	t.tween_property(_cat.key_light, "light_energy", key, 0.8)


## 给某样东西开一个新动画，并停掉它上一个还没放完的
func _tween(what: Object) -> Tween:
	var old: Tween = _tweens.get(what)
	if old and old.is_valid():
		old.kill()
	var t := create_tween()
	_tweens[what] = t
	return t


## isometric 镜头：始终对准猫砂盆上方（猫原来的位置）；zoom 决定远近，
## 再叠加跟拍的顶一下、左右摇摆和歪头
func _apply_camera(beat: float) -> void:
	var cam := _cat.camera
	var close_size := _cat.cat_view_height * close_zoom
	var size := lerpf(close_size, _full_size, _zoom)
	var punch := exp(-fposmod(beat, 1.0) * 6.0) * _by_stage(beat_punch)
	cam.size = size * (1.0 - punch) * (1.0 + _kick)

	var sway := sin(beat / sway_beats * TAU) * _by_stage(sway_degrees)
	var pitch := deg_to_rad(_cat.camera_pitch)
	var dir := Vector3(0.0, sin(pitch), cos(pitch)) \
			.rotated(Vector3.UP, deg_to_rad(_cat.camera_yaw + sway))
	cam.position = _cat.focus + dir * 100.0
	cam.look_at(_cat.focus)
	cam.rotate_object_local(Vector3.BACK, deg_to_rad(sin(beat / roll_beats * TAU) * _by_stage(roll_degrees)))


func _by_stage(values: PackedFloat32Array) -> float:
	return values[mini(stage, values.size() - 1)] if values.size() > 0 else 0.0


## 占位用的五角星（有厚度）
func _make_star_mesh(outer: float, inner: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array[Vector3] = []
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		var a := PI / 2.0 + i * TAU / 10.0
		ring.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	var front := Vector3(0.0, 0.0, depth / 2.0)
	var back := Vector3(0.0, 0.0, -depth / 2.0)
	for i in 10:
		var a := ring[i]
		var b := ring[(i + 1) % 10]
		for tri in [[front, b, a], [back, a, b]]:
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## 吊线：从定位点上方 gap 处往上 length 长
func _make_cord(length: float, gap: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.04
	mesh.height = length
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.1, 0.2)
	mesh.material = mat
	var cord := MeshInstance3D.new()
	cord.mesh = mesh
	cord.position.y = gap + length / 2.0
	return cord
