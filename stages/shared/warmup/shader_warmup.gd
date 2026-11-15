class_name ShaderWarmup
extends CanvasLayer
## 开头的着色器预热（主要给网页版用）：
## 网页版第一次画某种材质时要当场编着色器，整个页面会停住（进第 3 关停 7 秒多）。
## 这里在游戏一开始、温馨开场之前，出一个加载条，把每个大关（和插曲关）的每个小关
## 在一块看不见的画布上真实摆出来画几帧，让着色器先编好；画完删掉场景，
## 但把关卡资源和场景里用到的材质留着不放（材质一放掉，着色器也跟着放掉，之后又要重编）。
## 摆的时候关卡脚本不跑每帧逻辑，声音整个静音，不影响后面的音乐。
##
## 用法（main.gd 里）：await ShaderWarmup.run(self)
## 一次运行只做一遍。只预热每个小关一开场的样子，阶段推进以后才出现的东西不在里面。

## 每个小关画几帧
const FRAMES_PER_SCENE := 3
## 加载条的字体
const FONT_PATH := "res://assets/fonts/CandyGem/CandyGem.fnt"

signal finished

## 这次运行已经预热过了
static var done := false
## 预热过的关卡资源、材质、环境：一直留着
static var _keep := {}

var _bar: ColorRect
var _bar_back: ColorRect


## 预热一遍（已经做过就马上返回）。host = 挂加载画面的节点
static func run(host: Node) -> void:
	if done:
		return
	done = true
	var w := ShaderWarmup.new()
	host.add_child(w)
	await w.finished
	w.queue_free()


func _ready() -> void:
	layer = 30
	_build_ui()
	_go.call_deferred()


func _go() -> void:
	var t0 := Time.get_ticks_msec()
	var items := _list_sections()
	var old_style := ComicStyle.style
	var was_muted := AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	_set_progress(0.0)
	await RenderingServer.frame_post_draw  # 先把加载条画出来
	for i in items.size():
		var it: Dictionary = items[i]
		var t := Time.get_ticks_msec()
		ComicStyle.set_by_name(it.look)
		await _warm(it.def)
		print("[ShaderWarmup] %s  %d ms" % [it.def.scene.resource_path.get_file(), Time.get_ticks_msec() - t])
		_set_progress(float(i + 1) / items.size())
		await RenderingServer.frame_post_draw
	ComicStyle.style = old_style
	AudioServer.set_bus_mute(0, was_muted)
	print("[ShaderWarmup] 一共 %d 个小关，%d ms，留着 %d 个资源" % [items.size(), Time.get_ticks_msec() - t0, _keep.size()])
	finished.emit()


## 所有大关和插曲关的所有小关（同一个场景只摆一次）
func _list_sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var paths := Array(Levels.paths())
	for i in Levels.count():
		var after := Levels.interlude_after(i)
		if after != "":
			paths.append(after)
	for p in paths:
		var chart := load(p) as SongChart
		if chart == null:
			continue
		_keep[chart] = true
		for def in chart.sections:
			if def == null or def.scene == null or seen.has(def.scene):
				continue
			seen[def.scene] = true
			out.append({"def": def, "look": chart.look})
	return out


## 在一块看不见的画布上摆一个小关，画几帧，收下材质，删掉
func _warm(def: SectionDef) -> void:
	var vp := SubViewport.new()
	vp.size = get_viewport().get_visible_rect().size
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var inst := def.scene.instantiate() as SpinSection
	if inst == null:
		vp.queue_free()
		return
	inst.process_mode = Node.PROCESS_MODE_DISABLED
	var none: Array[NoteData] = []
	inst.setup(def, none)
	vp.add_child(inst)
	inst.enter()
	for f in FRAMES_PER_SCENE:
		await RenderingServer.frame_post_draw
	_collect(inst)
	vp.queue_free()


func _collect(n: Node) -> void:
	if n is GeometryInstance3D:
		_hold(n.material_override)
		_hold(n.material_overlay)
		if n is MeshInstance3D:
			_hold(n.mesh)
			for s in n.get_surface_override_material_count():
				_hold(n.get_surface_override_material(s))
		elif n is MultiMeshInstance3D:
			_hold(n.multimesh)
		elif n is GPUParticles3D:
			_hold(n.process_material)
			for d in n.draw_passes:
				_hold(n.get_draw_pass_mesh(d))
	elif n is CanvasItem:
		_hold(n.material)
		if n is GPUParticles2D:
			_hold(n.process_material)
	if n is WorldEnvironment:
		_hold(n.environment)
	elif n is Camera3D:
		_hold(n.environment)
	for c in n.get_children(true):
		_collect(c)


func _hold(r: Resource) -> void:
	if r:
		_keep[r] = true


func _build_ui() -> void:
	var size := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var label := Label.new()
	label.text = "LOADING"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_top = size.y * 0.5 - 70.0
	if ResourceLoader.exists(FONT_PATH):
		label.add_theme_font_override("font", load(FONT_PATH))
	label.add_theme_font_size_override("font_size", 40)
	add_child(label)
	var w := size.x * 0.5
	_bar_back = ColorRect.new()
	_bar_back.color = Color(1, 1, 1, 0.18)
	_bar_back.position = Vector2((size.x - w) * 0.5, size.y * 0.5 + 10.0)
	_bar_back.size = Vector2(w, 10.0)
	add_child(_bar_back)
	_bar = ColorRect.new()
	_bar.color = Color(1.0, 0.72, 0.86)
	_bar.position = _bar_back.position
	_bar.size = Vector2(0.0, 10.0)
	add_child(_bar)


func _set_progress(p: float) -> void:
	_bar.size.x = _bar_back.size.x * clampf(p, 0.0, 1.0)
