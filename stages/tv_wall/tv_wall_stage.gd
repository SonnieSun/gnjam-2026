class_name TvWallStage
extends Node
## 电视墙关卡的 3D 舞台：房间（TvWallRoom）、镜头、水果猫、屏幕状态。
## 玩法：墙上同一时间只亮一台电视（靶子）。每个音符是一只水果猫，从画面外飞过来，正好在拍子上砸到它那台电视；
## 按准了：电视白闪、冒 Y2K 星星（main 的命中特效）、黑屏裂开，下一台亮起来；桌上的猫转一圈。
## 没按准：水果猫被弹开掉下去，电视没坏，下一只猫还砸这台。
## 所有电视都砸黑之后一起重新亮起来（白闪一下），接着砸。
## 谁砸哪台：一条电视排队表，第 k 只还在飞的猫砸表里第 k 台；判定一只就从表头拿掉一台。
## 关卡脚本 TvWallSection 每帧调 update()，判定时调 knock() / bounce()。参数都在 Stage 节点的 Inspector 里。

## 水果猫素材（名字写法见 MemeLib），每只随机挑一个
@export var fruit_cats := PackedStringArray(["banana", "apple", "cats/lemon_cat_run", "cats/wide_apple_cat", "banana_cat"])
## 水果猫大小（米，高度）
@export var fruit_size := 0.42
## 水果猫飞的时候转几圈（整段路程）
@export var fruit_spin_turns := 1.5
## 飞行弧线往上拱多高（米）
@export var fruit_arc := 0.6

@export_group("屏幕")
## 不是靶子的电视雪花亮度
@export_range(0.0, 1.0) var idle_static := 0.25
## 靶子电视前面那盏灯多亮
@export var lit_light_energy := 1.4
## 排队中（有猫正飞向它）的电视闪的速度（次 / 拍）
@export var queued_blink := 2.0

@export_group("镜头")
@export var camera_position := Vector3(-0.05, 1.3, 1.75)
@export var camera_look_at := Vector3(0.12, 0.95, -0.6)
@export var camera_fov := 52.0
## 每拍轻轻点一下头（米）
@export var beat_bob := 0.015
## 砸中时镜头抖多少（米）
@export var hit_shake := 0.035
## 全部重新亮起来时镜头往前推多少（米）
@export var relight_push := 0.25

@export_group("桌上的猫")
## 砸中一次转一圈用几秒
@export var cat_spin_time := 0.3

var world: SubViewport
var camera: Camera3D
var room: TvWallRoom

var _sprite: Sprite2D
var _queue: Array[int] = []
## 音符 -> {"tv": 电视序号, "node": 水果猫, "start": 起点, "ctrl": 弧线控制点, "info": 素材信息, "spin": 转向}
var _flying := {}
## 判定过的音符还记一会儿电视序号（main 判定后才来问特效位置）
var _target_of := {}
var _broken: Array[bool] = []
var _flash: Array[float] = []
var _falling: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _shake := 0.0
var _push := 0.0
var _cat_spin_t := 1.0
var _cat_base_yaw := 0.0
var _last_tv := -1


func setup(host: Node2D) -> void:
	_rng.randomize()
	world = SubViewport.new()
	world.size = Vector2i(host.get_viewport_rect().size)
	world.own_world_3d = true
	world.msaa_3d = Viewport.MSAA_4X
	host.add_child(world)
	_sprite = Sprite2D.new()
	_sprite.texture = world.get_texture()
	_sprite.z_index = -1
	host.add_child(_sprite)

	_build_env()
	room = TvWallRoom.new()
	world.add_child(room)
	camera = Camera3D.new()
	camera.fov = camera_fov
	world.add_child(camera)
	camera.position = camera_position
	camera.look_at(camera_look_at)
	camera.current = true
	_cat_base_yaw = room.cat.rotation.y
	for i in room.tvs.size():
		_broken.append(false)
		_flash.append(0.0)


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.03, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.5, 0.55)
	env.ambient_light_energy = 0.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_intensity = 0.9
	env.glow_bloom = 0.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.3, 0.32)
	env.fog_density = 0.02
	we.environment = env
	world.add_child(we)
	# 墙那边常亮的一点青绿光（就算全部电视都黑了房间也不至于全黑）
	for p in [Vector3(-0.9, 1.4, -0.6), Vector3(0.0, 1.5, -0.9), Vector3(1.0, 1.4, -0.2)]:
		var o := OmniLight3D.new()
		o.position = p
		o.light_color = Color(0.45, 0.95, 0.85)
		o.light_energy = 0.35
		o.omni_range = 3.0
		o.light_specular = 0.0  # 不在电视玻璃盖上映出高光
		world.add_child(o)
	# 猫背后的长春花蓝逆光
	var rim := SpotLight3D.new()
	rim.position = Vector3(0.1, 1.3, -0.8)
	rim.light_color = Color(0.6, 0.65, 1.0)
	rim.light_energy = 4.0
	rim.spot_range = 3.0
	rim.spot_angle = 30.0
	world.add_child(rim)
	rim.look_at(Vector3(0.0, 0.8, 0.0))
	# 镜头这边一点暖金补光
	var key := SpotLight3D.new()
	key.position = Vector3(0.7, 1.9, 1.7)
	key.light_color = Color(1.0, 0.85, 0.6)
	key.light_energy = 0.8
	key.spot_range = 4.0
	key.spot_angle = 22.0
	key.shadow_enabled = true
	world.add_child(key)
	key.look_at(Vector3(0.0, 0.8, 0.0))


# ---------------- 每帧 ----------------

func update(beat: float, notes: Array[NoteData], approach_beats: float) -> void:
	var dt := get_process_delta_time()
	var size := Vector2i(world.get_parent().get_viewport_rect().size)
	if world.size != size:
		world.size = size
	_spawn_and_fly(beat, notes, approach_beats)
	_update_falling(dt)
	_update_screens(beat, dt)
	_update_cat(dt)
	_update_camera(beat, dt)


## 快到的音符生成水果猫，飞着的猫按拍子走弧线
func _spawn_and_fly(beat: float, notes: Array[NoteData], approach_beats: float) -> void:
	for n in notes:
		if n.judged:
			continue
		var ahead := n.beat - beat
		if ahead > approach_beats:
			break
		if not _flying.has(n):
			_launch(n)
		var f: Dictionary = _flying[n]
		var t := clampf(1.0 - ahead / approach_beats, 0.0, 1.0)
		var end := _target_point(f.tv)
		var p: Vector3 = (f.start as Vector3).lerp(f.ctrl, t).lerp((f.ctrl as Vector3).lerp(end, t), t)
		var node: Sprite3D = f.node
		node.position = p
		_face_camera(node, t * TAU * fruit_spin_turns * f.spin)
		node.scale = Vector3.ONE * lerpf(0.8, 1.0, t)
		_animate_frames(node, f.info)


func _launch(n: NoteData) -> void:
	var tv := _queue_at(_flying.size())
	var info := MemeLib.find(fruit_cats[_rng.randi() % fruit_cats.size()]) if fruit_cats.size() > 0 else {}
	var node := Sprite3D.new()
	if not info.is_empty():
		node.texture = load(info.path)
		node.hframes = info.cols
		node.vframes = info.rows
		node.pixel_size = fruit_size / (node.texture.get_height() / float(info.rows))
	node.shaded = false
	node.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	node.no_depth_test = true  # 飞的时候永远画在最前面，不被电视挡住
	node.render_priority = 10
	world.add_child(node)
	# 起点：镜头左 / 右 / 上方画面外面一点
	var cam := camera.global_transform
	var side := _rng.randf_range(-1.0, 1.0)
	var start := cam.origin - cam.basis.z * 1.6 + cam.basis.x * side * 1.9 + cam.basis.y * _rng.randf_range(0.6, 1.0)
	var end := _target_point(tv)
	var ctrl := start.lerp(end, 0.5) + Vector3.UP * fruit_arc
	_flying[n] = {"tv": tv, "node": node, "start": start, "ctrl": ctrl, "info": info, "spin": -signf(side) if side != 0.0 else 1.0}
	_target_of[n] = tv


## 判定了一只：从表头拿掉一台电视。hit = true 砸坏，false 弹开（这台还排回去让下一只新猫再砸）
## 返回 {"tv": 电视序号, "node": 水果猫}
func _finish(n: NoteData, hit: bool) -> Dictionary:
	if not _flying.has(n):  # 还没飞出来就判定了（理论上不会）：补一只
		_launch(n)
	var f: Dictionary = _flying[n]
	_flying.erase(n)
	var tv: int = f.tv
	if not _queue.is_empty():
		_queue.pop_front()
	if not hit:
		# 排在还在飞的猫后面，下一只新猫接着砸它
		_queue.insert(mini(_flying.size(), _queue.size()), tv)
	_trim_target_memory()
	return f


func knock(n: NoteData, result: int) -> void:
	var f := _finish(n, true)
	(f.node as Node).queue_free()
	var tv: int = f.tv
	_broken[tv] = true
	_flash[tv] = 1.0 if result == NoteData.Result.PERFECT else 0.7
	_shake = 1.0
	_cat_spin_t = 0.0
	_last_tv = tv
	# 全部砸黑了：一起重新亮
	if not _broken.has(false):
		for i in _broken.size():
			_broken[i] = false
			_flash[i] = 1.0
		_push = 1.0


func bounce(n: NoteData) -> void:
	var node: Sprite3D = _finish(n, false).node
	# 往回弹、往下掉、转着淡出
	var away := (camera.global_position - node.position).normalized()
	_falling.append({"node": node, "vel": away * 1.6 + Vector3(_rng.randf_range(-0.8, 0.8), 1.4, 0.0), "life": 1.2, "rot": 0.0})


func _trim_target_memory() -> void:
	# 只留最近判定的一批，免得越攒越多
	if _target_of.size() > 64:
		for k in _target_of.keys().slice(0, _target_of.size() - 32):
			_target_of.erase(k)


func _update_falling(dt: float) -> void:
	for i in range(_falling.size() - 1, -1, -1):
		var f: Dictionary = _falling[i]
		var node: Sprite3D = f.node
		f.vel += Vector3.DOWN * 6.0 * dt
		node.position += (f.vel as Vector3) * dt
		f.rot += dt * 10.0
		f.life -= dt
		_face_camera(node, f.rot)
		node.modulate.a = clampf(f.life / 0.5, 0.0, 1.0)
		if f.life <= 0.0:
			node.queue_free()
			_falling.remove_at(i)


## 每台电视的屏幕状态：坏了 / 靶子（亮）/ 有猫飞过来（闪）/ 平时（雪花）
func _update_screens(beat: float, dt: float) -> void:
	var target := _queue_at(0) if not _flying.is_empty() or not _queue.is_empty() else -1
	# 轮到一台之前砸坏、还没等到全部重亮的电视：轮到它时先修好亮起来
	if target >= 0 and _broken[target]:
		_broken[target] = false
		_flash[target] = 0.6
	var queued := {}
	for f in _flying.values():
		queued[f.tv] = true
	for i in room.tvs.size():
		var tv: Dictionary = room.tvs[i]
		var mat: ShaderMaterial = tv.mat
		var light: OmniLight3D = tv.light
		_flash[i] = maxf(_flash[i] - dt * 4.0, 0.0)
		var power := 0.0
		if not _broken[i]:
			if i == target:
				power = 1.0
			elif queued.has(i):
				power = 0.35 + 0.35 * (0.5 + 0.5 * sin(beat * TAU * queued_blink))
		mat.set_shader_parameter("power", power)
		mat.set_shader_parameter("broken", 1.0 if _broken[i] else 0.0)
		mat.set_shader_parameter("static_level", 0.0 if _broken[i] else idle_static)
		mat.set_shader_parameter("flash", _flash[i])
		light.light_energy = lit_light_energy * power + _flash[i] * 2.5 + (0.0 if _broken[i] else 0.08)


func _update_cat(dt: float) -> void:
	_cat_spin_t = minf(_cat_spin_t + dt / maxf(cat_spin_time, 0.01), 1.0)
	var k := 1.0 - pow(1.0 - _cat_spin_t, 3.0)
	room.cat.rotation.y = _cat_base_yaw + k * TAU
	var hop := sin(_cat_spin_t * PI) * 0.06 if _cat_spin_t < 1.0 else 0.0
	room.cat.position.y = room.table_height + hop


func _update_camera(beat: float, dt: float) -> void:
	_shake = maxf(_shake - dt * 5.0, 0.0)
	_push = maxf(_push - dt * 1.5, 0.0)
	var bob := -absf(sin(beat * PI)) * beat_bob
	var dir := (camera_look_at - camera_position).normalized()
	var shake := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0.0) * hit_shake * _shake * _shake
	camera.position = camera_position + Vector3(0.0, bob, 0.0) + dir * relight_push * sin(_push * PI * 0.5) + shake
	camera.look_at(camera_look_at + shake * 0.5)


# ---------------- 给关卡脚本的 ----------------

## 音符那台电视的屏幕中心在 2D 画面上的位置（相对屏幕中心）
func screen_offset(n: NoteData) -> Vector2:
	var tv: int = _target_of.get(n, _queue_at(0))
	return _to_screen(room.screen_center(tv))


## 音符那台电视的屏幕在 2D 画面上大概多大（半径，像素）
func screen_radius(n: NoteData) -> float:
	var tv: int = _target_of.get(n, _queue_at(0))
	var c := room.screen_center(tv)
	var half: Vector2 = room.tvs[tv].half
	var right := camera.global_transform.basis.x
	return (_to_screen(c + right * half.length() * 0.8) - _to_screen(c)).length()


## 还没判定、已经飞出来的音符（给关卡脚本画缩圈）
func flying_notes() -> Array:
	return _flying.keys()


func _to_screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p) - Vector2(world.size) / 2.0


func _target_point(tv: int) -> Vector3:
	return room.screen_center(tv) + room.screen_normal(tv) * 0.05


## 排队表第 i 台；不够就补一轮打乱的（不和上一台重复）
func _queue_at(i: int) -> int:
	while _queue.size() <= i:
		var order: Array[int] = []
		for k in room.tvs.size():
			order.append(k)
		order.shuffle()
		var last: int = _queue.back() if not _queue.is_empty() else _last_tv
		if order[0] == last and order.size() > 1:
			order.append(order.pop_front())
		_queue.append_array(order)
	return _queue[i]


func _face_camera(node: Node3D, roll: float) -> void:
	var to_cam := camera.global_position - node.position
	if to_cam.length() < 0.001:
		return
	node.look_at(node.position - to_cam, Vector3.UP)  # Sprite3D 正面朝 +Z，所以让 -Z 背对镜头
	node.rotate_object_local(Vector3.FORWARD, roll)


func _animate_frames(node: Sprite3D, info: Dictionary) -> void:
	if info.is_empty() or int(info.frames) <= 1:
		return
	node.frame = int(Time.get_ticks_msec() / 1000.0 * float(info.fps)) % int(info.frames)
