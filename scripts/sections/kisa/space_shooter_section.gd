@tool
extends Spin3DSection
## 太空打飞机：做披萨的猫站在披萨上，左右键（← → / A D）移动。
## 猫身上有跟着音乐节拍收缩的判定圈（和第 1 关一样的缩圈）：按在拍子上猫转一圈并往前发射食物，
## Perfect 5 发大扇形、Great 3 发小扇形、Good 正前方 1 发，Miss / 空按不发射。
## 星球在左 / 中 / 右三条路里挑一条直着飞下来（不拐弯），被食物打中一击就碎。
## 没打掉的星球会继续往下飞，撞到猫飘 MISS 并扣分。
##
## 这一段的分数完全看打掉了多少星球（见 stages/space_shooter/space_shooter_score.gd）：
## 进关时把 Judge.accuracy_share 设成 0，打掉星球的分用 Judge.add_bonus() 立刻加到总分上。
## 猫、披萨、灯光、天空都在场景 space_shooter.tscn 里摆，这里只负责让它们动和玩法。

@export_group("移动")
## 猫最多能往左右走多远
@export var move_range := 7.0
## 左右移动速度（每秒多少米）
@export var move_speed := 16.0
## 移动时披萨往那一侧倾斜多少度
@export var move_bank_deg := 16.0
@export_group("镜头")
@export var camera_height := 14.0
@export var camera_back := 12.0
## 镜头看向猫前方多远
@export var look_ahead := 4.0
## 镜头往右偏多少（猫会落在画面偏左）
@export var camera_side := 3.0
## 镜头跟着猫左右走多少（0 = 不跟，1 = 完全跟）
@export_range(0.0, 1.0) var camera_follow := 0.3
@export_group("星球")
@export var planet_models: Array[PackedScene] = []
## 拖尾颜色（和 planet_models 一一对应，缺的用白色）
@export var planet_colors: Array[Color] = []
## 星球半径（最小 / 最大）
@export var planet_radius := Vector2(0.9, 1.3)
## 星球提前几拍出现
@export var planet_beats := 6.0
## 星球刚出现时在猫前方多远
@export var spawn_distance := 34.0
## 音符那一拍，星球正好飞到猫前方多远
@export var target_distance := 8.0
## 星球走三条直路（左 / 中 / 右），这是相邻两条路隔多远
@export var lane_spacing := 4.5
## 拖尾长度（星球半径的几倍）
@export var tail_length := 7.0
@export_group("食物子弹")
## 子弹用的食物模型（轮流发射）。空着就用彩色方块占位
@export var food_models: Array[PackedScene] = []
## 食物大小（模型最长边是 1 米，这里是放大倍数）
@export var food_size := 1.0
@export var bullet_speed := 24.0
## 子弹最远飞多远
@export var bullet_range := 30.0
## 同时最多有几个食物在飞（连按太快时多出来的不发射；一个食物只打掉一颗星球）
@export var max_bullets := 20
## Perfect 的扇形：每一发偏离正前方多少度（负 = 往左）。中间直射，两发斜着，最外面两发几乎横着飞
@export var perfect_fan: Array[float] = [-72.0, -32.0, 0.0, 32.0, 72.0]
## Great 的扇形：直射一发，左右各斜一发，比 Perfect 窄
@export var great_fan: Array[float] = [-24.0, 0.0, 24.0]
## Good：只有正前方一发
@export var good_fan: Array[float] = [0.0]
@export_group("计分")
## 这一段的算分规则；空着用默认值（全部按打掉的星球算，见 SpaceShooterScore）
@export var score_rule: SpaceShooterScore
## 猫被撞的判定半径
@export var cat_radius := 0.9
@export_group("转圈星星")
## 每转一圈撒几颗发光四芒星
@export var star_count := 6
## 星星大小（最小 / 最大，米）
@export var star_size := Vector2(0.5, 1.1)
## 星星外光的颜色，每颗随机挑一个
@export var star_colors: Array[Color] = [Color(0.35, 0.6, 1.0), Color(1.0, 0.45, 0.8), Color(0.7, 0.45, 1.0),
		Color(0.3, 1.0, 0.9), Color(1.0, 0.85, 0.3), Color(0.5, 1.0, 0.5), Color(1.0, 0.55, 0.45)]
@export_group("")
## 猫的动作（模型自带的动画名）；一个小节做一遍
@export var cat_animation := "ARM-CATS-Scratch|ACT-CATS-LeftPaw-Scratch"
## 猫转一圈用多少秒
@export var spin_time := 0.225
## 调试用：自动走位、自动按键（看演出用，正式玩要关掉）
@export var autoplay := false

@onready var _player: Node3D = %Player
@onready var _pizza: Node3D = %Pizza
@onready var _cat: Node3D = %Cat

var _x := 0.0            # 猫现在的左右位置
var _lean := 0.0         # 披萨现在的倾斜（-1 ~ 1）
var _spin_age := 99.0    # 距离上一次按键转圈过了多少秒
var _last_t := -1.0
var _anim: AnimationPlayer
var _dyn: Node3D         # 星球、子弹、碎片都挂在这下面
var _planets: Array[Dictionary] = []
var _bullets: Array[Dictionary] = []
var _shards: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _spawn_i := 0        # 下一个还没生成星球的音符
var _food_i := 0
var _flash := 0.0
var _judge: Judge
var _score: SpaceShooterScore
var _auto_i := 0
var _auto_release := false
var _stars: Array[Dictionary] = []
var _star_mesh: Mesh
var _fx_layer: Node

const STAR_SCENE := preload("res://stages/space_shooter/star/four_point_star.glb")
const STAR_SHADER := preload("res://stages/space_shooter/star/star_glow.gdshader")


func _on_enter() -> void:
	if Engine.is_editor_hint() or world == null:
		return
	_dyn = Node3D.new()
	world.add_child(_dyn)
	_score = score_rule.duplicate() if score_rule else SpaceShooterScore.new()
	# 往上找带 judge 的节点（main），把这一关的算分规则挂上去
	var n := get_parent()
	while n and not ("judge" in n):
		n = n.get_parent()
	if n:
		_judge = n.judge
		_judge.accuracy_share = 0.0  # 这一段不按准确率给分，全部靠打星球
		_score.stage_points = roundi(_judge.stage_max())
		# 框架每次打中会在猫身上放 2D 命中特效，这一段换成 3D 发光星星，所以把它们拿掉
		if "fx_layer" in n:
			_fx_layer = n.fx_layer
			_fx_layer.child_entered_tree.connect(_on_fx_added)
	var star := STAR_SCENE.instantiate()
	for mi: MeshInstance3D in star.find_children("*", "MeshInstance3D", true, false):
		_star_mesh = mi.mesh
	star.free()


## 离开这一关：准确率占比还回 100%，后面的小关回到通常的按段计分。
## （框架是先把这一段的分入账、再让旧小关退场，所以这时还回去不影响这一段。）
func _on_exit() -> void:
	if _judge:
		_judge.accuracy_share = 1.0
		if _score:
			_judge.add_bonus(0, _score.take_rest_possible())
	if _fx_layer and _fx_layer.child_entered_tree.is_connected(_on_fx_added):
		_fx_layer.child_entered_tree.disconnect(_on_fx_added)
	# 把镜头相对猫的位置交给下一段，它从这个机位开始移动，画面不跳
	if camera and _posed:
		var at := Vector3(_x, 0.0, 0.0)
		SpaceShooterScore.handoff = {
			"pos": camera.global_position - at,
			"look": Vector3(_x * camera_follow + camera_side, 0.0, -look_ahead) - at,
			"fov": camera.fov,
		}


func _on_fx_added(node: Node) -> void:
	if node is StarBurst:
		node.queue_free()


func _camera_pose(_p: float, _t: float) -> Dictionary:
	var cx := _x * camera_follow
	return {
		"pos": Vector3(cx + camera_side, camera_height, camera_back),
		"look": Vector3(cx + camera_side, 0.0, -look_ahead),
		"roll": 0.0,
	}


func _update_view(t: float) -> void:
	var dt := 0.0 if _last_t < 0.0 else minf(t - _last_t, 0.05)
	_last_t = t
	_spin_age += dt
	_flash = maxf(_flash - dt * 2.5, 0.0)

	var dir := 0.0
	if not Engine.is_editor_hint():
		if autoplay:
			dir = _autoplay()
		else:
			dir = float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)) \
					- float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
	_x = clampf(_x + dir * move_speed * dt, -move_range, move_range)
	_lean = lerpf(_lean, dir, minf(1.0, dt * 10.0))

	# 披萨带着猫左右走、往移动的方向侧倾，上下轻轻浮动
	var ride := Transform3D(Basis(Vector3.BACK, -_lean * deg_to_rad(move_bank_deg)),
			Vector3(_x, sin(t * 1.4) * 0.08, 0.0))
	_player.transform = ride * rest(_player)
	_pizza.transform = rest(_pizza).rotated_local(Vector3.UP, t * 0.8)
	# 猫：每次按键转一整圈（先快后慢），顺便弹一下
	var k := clampf(_spin_age / spin_time, 0.0, 1.0)
	var bounce := 1.0 + sin(k * PI) * 0.12
	_cat.transform = rest(_cat).rotated_local(Vector3.UP, (1.0 - pow(1.0 - k, 3.0)) * TAU) \
			.scaled_local(Vector3.ONE * bounce)
	_play_cat()

	if _dyn:
		_update_planets(dt)
		_update_bullets(dt)
		_update_shards(dt)
		_update_stars(dt)
	for i in range(_popups.size() - 1, -1, -1):
		_popups[i].age += dt
		if _popups[i].age > 0.7:
			_popups.remove_at(i)


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


# ---- 按键 = 转圈 + 发射 ----

func _on_note_judged(_note: NoteData, result: int) -> void:
	match result:
		NoteData.Result.PERFECT: _fire(perfect_fan)
		NoteData.Result.GREAT: _fire(great_fan)
		NoteData.Result.GOOD: _fire(good_fan)


## 空按：猫照样转一圈，但不发射
func _on_empty_hit() -> void:
	_fire([])


## 猫转一圈、撒星星，按 fan 里的角度（度，0 = 正前方）扇形发射食物
func _fire(fan: Array) -> void:
	_spin_age = 0.0
	if _dyn == null:
		return
	_spawn_stars()
	for deg: float in fan:
		if _bullets.size() >= max_bullets:
			break
		var node: Node3D
		if food_models.is_empty():
			node = _placeholder_food()
		else:
			node = food_models[_food_i % food_models.size()].instantiate() as Node3D
		_food_i += 1
		node.scale = Vector3.ONE * food_size
		_dyn.add_child(node)
		var a := deg_to_rad(deg)
		node.position = Vector3(_x, 0.9, -1.2)
		_bullets.append({"node": node, "x": _x, "z": -1.2, "dir": Vector2(sin(a), -cos(a)), "gone": 0.0})


## 转圈时从猫身上甩出去的发光四芒星：大小、颜色各自随机
func _spawn_stars() -> void:
	if _star_mesh == null:
		return
	for i in star_count:
		var mi := MeshInstance3D.new()
		mi.mesh = _star_mesh
		var mat := ShaderMaterial.new()
		mat.shader = STAR_SHADER
		if not star_colors.is_empty():
			mat.set_shader_parameter("glow_color", star_colors[randi() % star_colors.size()])
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dyn.add_child(mi)
		var a := randf() * TAU
		mi.position = Vector3(_x, 1.0, 0.0)
		mi.rotation = Vector3(-0.9, 0.0, randf() * TAU)  # 大致朝着镜头
		_stars.append({"node": mi, "age": 0.0, "size": randf_range(star_size.x, star_size.y),
				"vel": Vector3(cos(a), randf_range(0.1, 0.6), sin(a)) * randf_range(3.5, 7.0)})


func _update_stars(dt: float) -> void:
	for i in range(_stars.size() - 1, -1, -1):
		var s := _stars[i]
		s.age += dt
		var node: Node3D = s.node
		if s.age > 0.6:
			node.queue_free()
			_stars.remove_at(i)
			continue
		var k: float = s.age / 0.6
		node.position += (s.vel as Vector3) * dt * (1.0 - k)
		node.rotate_object_local(Vector3.BACK, dt * 4.0)
		node.scale = Vector3.ONE * s.size * sin(minf(k * 1.4 + 0.25, 1.0) * PI)


## 没有食物模型时的占位：彩色方块
func _placeholder_food() -> Node3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(fposmod(_food_i * 0.21, 1.0), 0.6, 1.0)
	box.material = mat
	mi.mesh = box
	return mi


func _update_bullets(dt: float) -> void:
	for i in range(_bullets.size() - 1, -1, -1):
		var b := _bullets[i]
		var node: Node3D = b.node
		var step: Vector2 = (b.dir as Vector2) * bullet_speed * dt
		b.x += step.x
		b.z += step.y
		b.gone += bullet_speed * dt
		node.position = Vector3(b.x, 0.9, b.z)
		node.rotate_y(dt * 9.0)
		node.rotate_x(dt * 5.0)
		var hit := false
		for j in range(_planets.size() - 1, -1, -1):
			var p := _planets[j]
			var reach: float = p.radius + food_size * 0.5
			if absf(p.x - b.x) < reach and absf(p.z - b.z) < reach:
				_kill_planet(j)
				hit = true
				break
		if hit or b.gone > bullet_range:
			node.queue_free()
			_bullets.remove_at(i)


# ---- 星球 ----

func _update_planets(dt: float) -> void:
	# 快到的音符各生成一颗星球
	while _spawn_i < notes.size():
		var n := notes[_spawn_i]
		var ahead := beats_until(n)
		if ahead > planet_beats:
			break
		_spawn_i += 1
		if ahead > 0.5:  # 一进关就已经贴脸的不要了
			_spawn_planet(n)
	var span := spawn_distance - target_distance
	for i in range(_planets.size() - 1, -1, -1):
		var p := _planets[i]
		if p.note.judged and p.note.result == NoteData.Result.NONE:
			_remove_planet(i)  # 音符被框架丢掉了（切关 / 通关），星球跟着消失，不算放跑
			continue
		var u: float = beats_until(p.note) / planet_beats  # 1 = 刚出现，0 = 音符那一拍，之后是负的
		p.u = u
		p.z = -target_distance - u * span
		var node: Node3D = p.node
		node.position = Vector3(p.x, 0.9, p.z)
		(p.body as Node3D).rotate_y(dt * 1.2)
		if absf(p.z) < p.radius and absf(p.x - _x) < p.radius + cat_radius:
			_crash(i)
		elif p.z > camera_back:
			_score.escaped += 1
			_remove_planet(i)
			_bank(0)


func _spawn_planet(n: NoteData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(n.beat)
	var radius := rng.randf_range(planet_radius.x, planet_radius.y)
	# 三条路里随机挑一条，一路直着飞下来
	var lane := (float(rng.randi() % 3) - 1.0) * lane_spacing

	var root := Node3D.new()
	var color := Color.WHITE
	var body: Node3D
	if planet_models.is_empty():
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radial_segments = 14
		sphere.rings = 8
		var mat := StandardMaterial3D.new()
		color = Color.from_hsv(rng.randf(), 0.5, 1.0)
		mat.albedo_color = color
		sphere.material = mat
		mi.mesh = sphere
		mi.scale = Vector3.ONE * radius * 2.0
		body = mi
	else:
		var idx := rng.randi() % planet_models.size()
		if idx < planet_colors.size():
			color = planet_colors[idx]
		body = planet_models[idx].instantiate() as Node3D
		body.scale = Vector3.ONE * radius
		body.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))
	root.add_child(body)

	# 彗星尾巴：一头粗一头尖的发光锥，粗的那头贴着星球
	var tail := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius * 0.85
	cone.height = radius * tail_length
	cone.radial_segments = 12
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var grad := Gradient.new()
	grad.set_color(0, Color(color, 0.0))
	grad.set_color(1, Color(color, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 4
	tex.height = 32
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tmat.albedo_texture = tex
	cone.material = tmat
	tail.mesh = cone
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tail.transform = Transform3D(Basis(Quaternion(Vector3.UP, Vector3.FORWARD)), Vector3.FORWARD * cone.height * 0.5)
	root.add_child(tail)

	_dyn.add_child(root)
	root.position = Vector3(lane, 0.9, -spawn_distance)
	_planets.append({"node": root, "body": body, "tail": tail, "note": n, "lane": lane,
			"radius": radius, "color": color, "x": lane, "z": -spawn_distance, "u": 1.0})


func _remove_planet(i: int) -> void:
	(_planets[i].node as Node3D).queue_free()
	_planets.remove_at(i)


## 被食物打中：碎掉，飘分
func _kill_planet(i: int) -> void:
	var p := _planets[i]
	var pos: Vector3 = (p.node as Node3D).position
	_burst(pos, p.color, p.radius)
	_popups.append({"pos": pos, "age": 0.0, "text": "+%d" % _score.kill_points(), "color": Color(1.0, 0.95, 0.4)})
	_score.kills += 1
	_remove_planet(i)
	_bank(_score.take_kill())


## 撞到猫：算一次 Miss，只扣分
func _crash(i: int) -> void:
	var p := _planets[i]
	var pos: Vector3 = (p.node as Node3D).position
	_burst(pos, Color(1.0, 0.3, 0.3), p.radius)
	_popups.append({"pos": pos, "age": 0.0, "text": "MISS  -%d" % _score.crash_penalty, "color": Color(1.0, 0.35, 0.35)})
	_score.crashes += 1
	_flash = 1.0
	miss_age = 0.0  # 借基类的漏打抖镜头
	_remove_planet(i)
	_bank(-_score.crash_penalty)


## 一颗星球有了结果：分数立刻加到（或扣在）左上角的总分上
func _bank(points: int) -> void:
	if _judge:
		_judge.add_bonus(points, _score.take_possible())


## 碎片：一把小方块往四周飞、越飞越小
func _burst(pos: Vector3, color: Color, radius: float) -> void:
	for i in 10:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * radius * randf_range(0.25, 0.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.8
		box.material = mat
		mi.mesh = box
		_dyn.add_child(mi)
		mi.position = pos
		var vel := Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 1.0), randf_range(-1.0, 1.0)).normalized() \
				* randf_range(6.0, 14.0)
		_shards.append({"node": mi, "vel": vel, "age": 0.0})


func _update_shards(dt: float) -> void:
	for i in range(_shards.size() - 1, -1, -1):
		var s := _shards[i]
		s.age += dt
		var node: Node3D = s.node
		if s.age > 0.5:
			node.queue_free()
			_shards.remove_at(i)
			continue
		node.position += (s.vel as Vector3) * dt
		node.rotate_x(dt * 8.0)
		node.rotate_z(dt * 6.0)
		node.scale = Vector3.ONE * (1.0 - s.age / 0.5)


# ---- 自动演示 ----

## 走到下一颗要打的星球下面，到拍子就按键。返回这一帧往哪边走（-1 / 0 / 1）
func _autoplay() -> float:
	if _auto_release:
		_send_hit(false)
		_auto_release = false
	while _auto_i < notes.size() and notes[_auto_i].judged:
		_auto_i += 1
	if _auto_i < notes.size() and beats_until(notes[_auto_i]) <= 0.0:
		_auto_i += 1
		_send_hit(true)
		_auto_release = true
	var best: Dictionary = {}
	for p in _planets:
		if best.is_empty() or p.u < best.u:
			best = p
	if best.is_empty() or absf(best.lane - _x) < 0.15:
		return 0.0
	return signf(best.lane - _x)


func _send_hit(pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = Judge.HIT_ACTION
	e.pressed = pressed
	Input.parse_input_event(e)


# ---- 画在 3D 画面上面的东西 ----

## 3D 世界里的一个点在这一关画面上的位置
func _screen(p: Vector3) -> Vector2:
	var size := _container.size
	return camera.unproject_position(p) / Vector2(_viewport.size) * size - size / 2.0


func _draw_overlay() -> void:
	if def == null or camera == null or not _posed:
		return
	var size := screen_size()
	var font := ThemeDB.fallback_font
	# 猫身上的判定圈：每个音符一个从外面收过来的圈，收到和判定圈重合时按（先画，压在飘字下面）
	draw_approach_rings(_overlay, hit_position(), hit_radius(), approach_beats,
			approach_travel_ratio * size.y)
	for pop in _popups:
		var c := _screen(pop.pos) + Vector2(-180.0, -30.0 - pop.age * 80.0)
		var col: Color = pop.color
		col.a = 1.0 - pop.age / 0.7
		_overlay.draw_string_outline(font, c, pop.text, HORIZONTAL_ALIGNMENT_CENTER, 360.0, 30, 6, Color(0, 0, 0, col.a))
		_overlay.draw_string(font, c, pop.text, HORIZONTAL_ALIGNMENT_CENTER, 360.0, 30, col)
	if _score:
		_overlay.draw_string(font, Vector2(-size.x / 2.0 + 28.0, -size.y / 2.0 + 96.0),
				"PLANETS %d / %d    HIT BY PLANET %d" % [_score.kills, _score.planets_done(), _score.crashes],
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(1, 1, 1, 0.85))
	if _flash > 0.0:
		_overlay.draw_rect(Rect2(-size / 2.0, size), Color(1.0, 0.15, 0.2, _flash * 0.3))


func _on_restore() -> void:
	_last_t = -1.0
	_spin_age = 99.0
	_x = 0.0
	_lean = 0.0
	if _anim and _anim.has_animation(cat_animation):
		_anim.seek(0.0, true)
