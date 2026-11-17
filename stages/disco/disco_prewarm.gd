class_name DiscoPrewarm
extends Node3D
## 迪斯科关的「后面才出现的东西」提前画一遍（主要给网页版用）：
## 网页版第一次画某种材质时要当场编着色器、第一次 load() 贴图要当场读文件，玩到一半会停一下。
## 关卡一开始把这些东西（上路的灯球、水果、路面、彩虹和线框、各档的猫图、FEVER 的发光猫、
## 广场的站立猫、结尾的飞碟）缩得很小，藏在猫脚下的地板下面画几帧，再删掉；
## 用到的材质和贴图留着不放（材质一放掉，着色器也跟着放掉，之后又要重编）。
##
## 用法（关卡脚本里，DiscoRoad.setup 之后）：DiscoPrewarm.run(spin_cat, road)

## 画几帧
const FRAMES := 3
## 迪斯科里会在 3D 里冒出来的猫图（disco_decor.gd 各档 + 圆台围观的那些在 DiscoRoad.plaza_memes 里）
const DECOR_MEMES := ["popcat", "oiia", "nyan", "meow"]

## 留着不放的材质、贴图、场景（这一次运行一直留着）
static var _keep: Array = []

var _cat: KisaSpinCat3D
var _road: DiscoRoad


static func run(cat: KisaSpinCat3D, road: DiscoRoad) -> void:
	if cat == null or cat.world == null:
		return
	var p := DiscoPrewarm.new()
	p._cat = cat
	p._road = road
	p.name = "DiscoPrewarm"
	cat.world.add_child(p)


func _ready() -> void:
	_place()
	if _road:
		_add_scene(DiscoRoad.BALL)
		for fruit_scene in DiscoRoad.FRUITS:
			var fruit := _add_scene(fruit_scene)
			if fruit:
				BeatGlow.attach(fruit, {"glow": 1.0, "roughness": 0.12, "rim": 0.3})
		_add_floor()
		if _road.backdrop:
			var b := _add_scene(_road.backdrop) as RoadBackdrop
			if b:
				b.amount = 1.0
				b.update(0.0)
		if _road.saucer:
			_add_scene(_road.saucer)
		_add_stand_cat()
		for m in _road.plaza_memes:
			_add_meme(m, BaseMaterial3D.BILLBOARD_FIXED_Y, SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS)
	for m in DECOR_MEMES:
		_add_meme(m, BaseMaterial3D.BILLBOARD_ENABLED, SpriteBase3D.ALPHA_CUT_DISCARD)
	# 发光猫：要在加进场景之前关掉「自己开 Glow」，不然会改掉迪斯科世界的 Glow 设置
	var tabby := TabbyOrbit3D.CAT_SCENE.instantiate() as TabbySpinCat
	if tabby:
		tabby.ensure_scene_glow = false
		tabby.listen_input = false
		add_child(tabby)
		tabby.set_glow(1.0)
	_finish()


func _process(_delta: float) -> void:
	_place()


## 缩得很小，放在猫脚下的地板下面（在镜头视野里，所以会真的画，但被地板挡住看不见）
func _place() -> void:
	if _cat == null:
		return
	position = _cat.focus + _cat.pose_position + Vector3.DOWN * 3.0
	scale = Vector3.ONE * 0.05


func _finish() -> void:
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	_collect(self)
	queue_free()


func _add_scene(scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	_keep.append(scene)
	var n := scene.instantiate() as Node3D
	if n == null:
		return null
	add_child(n)
	return n


func _add_floor() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://stages/disco/road_floor.gdshader")
	mat.set_shader_parameter("reveal", 100.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	plane.material = mat
	var m := MeshInstance3D.new()
	m.mesh = plane
	add_child(m)


func _add_stand_cat() -> void:
	if _road.stand_cat == null:
		return
	var inst := _add_scene(_road.stand_cat)
	if inst == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _road.stand_cat_texture
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.skeleton = NodePath("")
		m.skin = null
		for s in m.mesh.get_surface_count():
			m.set_surface_override_material(s, mat)


func _add_meme(key: String, billboard: BaseMaterial3D.BillboardMode, alpha_cut: SpriteBase3D.AlphaCutMode) -> void:
	var info := MemeLib.find(key)
	if info.is_empty():
		return
	var tex: Texture2D = load(info.path)
	if tex == null:
		return
	_keep.append(tex)  # 留着，后面那些脚本 load() 同一张图时直接拿缓存
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = info.cols
	s.vframes = info.rows
	s.billboard = billboard
	s.shaded = false
	s.alpha_cut = alpha_cut
	s.pixel_size = 1.0 / maxf(tex.get_height() / float(info.rows), 1.0)
	add_child(s)


## 把画过的材质（连同 next_pass）、贴图都记下来留着
func _collect(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.material_override:
			_keep_material(g.material_override)
		if g is MeshInstance3D:
			var m := g as MeshInstance3D
			if m.mesh == null:
				continue
			for s in m.mesh.get_surface_count():
				_keep_material(m.get_active_material(s))


func _keep_material(mat: Material) -> void:
	while mat:
		if not _keep.has(mat):
			_keep.append(mat)
		mat = mat.next_pass
