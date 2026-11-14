class_name ComicStyle
extends RefCounted
## 3D 关卡的画面风格切换（试验用）。这里管“现在用哪种风格”和漫画那几种；
## Y2K 那两种的具体做法在 y2k_style.gd。每个大关默认用哪种，在 levels/ 里那个大关的 .tres 的 look 一项里选。
##
## 漫画风格：给 3D 关卡套上漫画风格的 shader（assets/shaders/comic/，作者 Francisco Cidade，fcidade.itch.io）。
## 不改场景文件：运行时把模型的普通材质临时换成漫画材质，随时可以换回去。
## 游戏里按 C 键轮流切换几种风格（见 NAMES）；想改默认风格就改下面的 style。
##
## 只换“受光照的不透明材质”。猫脸贴图、星星、玻璃、光束、彩灯这些不受光照或半透明的保持原样。
## 调参数：改下面几个 _make_xxx 函数里的数值，各个参数的含义在 shader 文件开头的注释里都有。

enum { OFF, HALFTONE, HATCH, FLAT, PRINT, Y2K, Y2K_JPEG }
const NAMES := ["OFF", "HALFTONE", "HATCH", "FLAT", "PRINT", "Y2K", "Y2K_JPEG"]

## 现在用哪种风格：
##   OFF       原样
##   HALFTONE  暗部印成网点 + 墨线描边
##   HATCH     暗部画成排线 + 墨线描边
##   FLAT      暗部是一整块平涂 + 墨线描边
##   PRINT     网点 + 整个画面再过一遍“印刷”效果（按深度勾线、套色错位、纸张颗粒）
##   Y2K       千禧年主机的画面：480 线方像素、16 位色抖动、亮面塑料、现代光照（见 y2k_style.gd）
##   Y2K_JPEG  同上，再加一层 JPEG 压缩的块感
static var style := HALFTONE

const COMIC := preload("res://assets/shaders/comic/comic.gdshader")
const OUTLINE := preload("res://assets/shaders/comic/comic_outline.gdshader")
const SCREEN := preload("res://assets/shaders/comic/comic_screen_forward.gdshader")
const ORIGINAL := &"_comic_original_material"
const SCREEN_NODE := "ComicScreenPass"


## 按名字选风格（名字见 NAMES；不认识的名字 = OFF）
static func set_by_name(style_name: String) -> void:
	style = maxi(NAMES.find(style_name.to_upper()), 0)


## 换到下一种风格，返回它的名字
static func next_style() -> String:
	style = (style + 1) % NAMES.size()
	return NAMES[style]


## 把 world 下面的模型换成当前风格（先恢复原样再换，所以可以反复调用）
static func apply(world: Node3D, camera: Camera3D) -> void:
	_restore(world)
	var old := camera.get_node_or_null(SCREEN_NODE)
	if old:
		old.free()
	if style == OFF or style >= Y2K:
		return
	var cache := {}  # 同一个原材质只转换一次
	for node in world.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var src := mi.material_override as StandardMaterial3D
		if src == null or src.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				or src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		mi.set_meta(ORIGINAL, src)
		# 描边方式：0 = 不描（地板这种薄片，描了会鼓出一大块黑），1 = 沿法线推（圆滑的模型），
		# 2 = 从中心往外推（有棱角的模型，不然边角会裂开）
		var outline := 1
		if mi.mesh is PlaneMesh or mi.mesh is QuadMesh or (mi.mesh is CylinderMesh and (mi.mesh as CylinderMesh).height < 0.05):
			outline = 0
		elif mi.mesh is BoxMesh or mi.mesh is CylinderMesh:
			outline = 2
		var key := [src, outline]
		if not cache.has(key):
			cache[key] = _make_comic(src, outline)
		mi.material_override = cache[key]
	if style == PRINT:
		camera.add_child(_make_screen_pass())


static func _restore(world: Node3D) -> void:
	for node in world.find_children("*", "MeshInstance3D", true, false):
		if node.has_meta(ORIGINAL):
			(node as MeshInstance3D).material_override = node.get_meta(ORIGINAL)
			node.remove_meta(ORIGINAL)


static func _make_comic(src: StandardMaterial3D, outline: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = COMIC
	m.set_shader_parameter("albedo", src.albedo_color)
	if src.albedo_texture:
		m.set_shader_parameter("albedo_texture", src.albedo_texture)
	m.set_shader_parameter("shade_style", {HALFTONE: 1, HATCH: 2, FLAT: 0, PRINT: 1}[style])
	m.set_shader_parameter("shadow_color", Color(0.55, 0.48, 0.7))  # 暗部的颜色（乘在原色上）
	m.set_shader_parameter("light_threshold", 0.35)                 # 越大亮部越小
	m.set_shader_parameter("shade_reach", 0.8)                      # 网点 / 排线从稀到密过渡多宽
	m.set_shader_parameter("dot_size", 9.0)                         # 网点间距（像素）
	m.set_shader_parameter("hatch_spacing", 8.0)                    # 排线间距（像素）
	if style != PRINT and outline > 0:  # PRINT 的线由整屏那一遍来画
		m.next_pass = _make_outline(outline == 2)
	return m


static func _make_outline(hard_edges: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OUTLINE
	m.set_shader_parameter("outline_color", Color(0.1, 0.06, 0.12))
	m.set_shader_parameter("outline_width", 3.5)       # 线宽（按 1080 高的屏幕算的像素）
	m.set_shader_parameter("outline_variation", 0.3)   # 线条粗细变化，像毛笔的轻重
	m.set_shader_parameter("outline_smooth", 1.0 if hard_edges else 0.0)
	return m


## 整屏的“印刷”效果：一块永远贴在镜头前的面片
static func _make_screen_pass() -> MeshInstance3D:
	var m := ShaderMaterial.new()
	m.shader = SCREEN
	m.render_priority = -128  # 先画它，猫脸、玻璃这些半透明的东西再盖在上面（否则会被它抹掉）
	m.set_shader_parameter("line_width", 2.5)
	m.set_shader_parameter("depth_threshold", 0.05)
	m.set_shader_parameter("crease_threshold", 0.5)
	m.set_shader_parameter("saturation", 1.15)
	m.set_shader_parameter("contrast", 1.05)
	m.set_shader_parameter("misregistration", 1.5)     # 套色错位（像素）
	m.set_shader_parameter("paper_color", Color(1.0, 0.97, 0.9))
	m.set_shader_parameter("paper_amount", 0.5)
	m.set_shader_parameter("grain", 0.06)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mi := MeshInstance3D.new()
	mi.name = SCREEN_NODE
	mi.mesh = quad
	mi.material_override = m
	mi.extra_cull_margin = 16384.0  # 永远不被裁掉
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
