extends NoteStyle
## 3D 表现方式的共用部分：自己开一个透明背景的 3D 视口（叠在关卡画面上也行），
## 每个看得见的音符一个 3D 节点（_make_note 造，_place_note 每帧摆），打中时节点放大淡出。

var world: SubViewport
var camera: Camera3D
var root3d: Node3D
var _nodes := {}  # NoteData -> Node3D
var _fading: Array[Dictionary] = []  # {node, t}
var _sprite: Sprite2D


func _ready() -> void:
	world = SubViewport.new()
	world.transparent_bg = true
	world.own_world_3d = true
	world.msaa_3d = Viewport.MSAA_4X
	world.size = Vector2i(area())
	add_child(world)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture = world.get_texture()
	add_child(_sprite)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.9)
	env.environment.ambient_light_energy = 0.6
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.8
	env.environment.glow_bloom = 0.05
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	world.add_child(sun)
	root3d = Node3D.new()
	world.add_child(root3d)
	camera = Camera3D.new()
	world.add_child(camera)
	_build()


func _update() -> void:
	if world == null:
		return
	var s := Vector2i(area())
	if world.size != s:
		world.size = s
	var seen := {}
	for n: NoteData in notes:
		if not showing(n):
			continue
		seen[n] = true
		var node: Node3D = _nodes.get(n)
		if node == null:
			node = _make_note(n)
			root3d.add_child(node)
			_nodes[n] = node
		_place_note(n, node, fx(n))
	for n: NoteData in _nodes.keys():
		if not seen.has(n):
			_drop(n, false)
	var dt := get_process_delta_time()
	for i in range(_fading.size() - 1, -1, -1):
		var f: Dictionary = _fading[i]
		f.t += dt / HIT_FLASH_SECONDS
		var node: Node3D = f.node
		node.scale *= 1.0 + dt * 4.0
		_set_alpha(node, 1.0 - f.t)
		if f.t >= 1.0:
			node.queue_free()
			_fading.remove_at(i)
	_update_3d()


## 辅助线画在 2D 层（在 3D 画面下面），位置由 3D 坐标投到屏幕上
func _draw() -> void:
	if camera:
		_draw_guides()


func to_screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p)


func _on_judged(note: NoteData, _result: int) -> void:
	if note.length <= 0.0:
		_drop(note, true)


func _drop(n: NoteData, pop: bool) -> void:
	var node: Node3D = _nodes.get(n)
	_nodes.erase(n)
	if node == null:
		return
	if pop:
		_fading.append({"node": node, "t": 0.0})
	else:
		node.queue_free()


## 发光材质：颜色 + 自发光（glow 越大越亮）
func make_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.4
	m.roughness = 0.25
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func apply_look(node: Node3D, f: Dictionary) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m:
			var c: Color = f.color
			m.albedo_color = Color(c, f.alpha)
			m.emission = c
			m.emission_energy_multiplier = 0.4 + f.glow * 2.5


func _set_alpha(node: Node3D, a: float) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m:
			m.albedo_color.a = clampf(a, 0.0, 1.0)


# ---- 子类实现 ----

## 搭场景（轨道、判定线、镜头位置）
func _build() -> void:
	pass


func _make_note(_n: NoteData) -> Node3D:
	return Node3D.new()


func _place_note(_n: NoteData, _node: Node3D, _f: Dictionary) -> void:
	pass


## 每帧额外要更新的（比如判定线跟拍亮）
func _update_3d() -> void:
	pass
