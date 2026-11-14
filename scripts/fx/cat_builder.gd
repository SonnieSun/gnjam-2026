@tool
class_name CatBuilder
extends RefCounted
## 用基本形状拼卡通猫和道具的工具（照着猫咪 MV 原型里的 makeHead / makeCat 移植）。
## 现在的 MV 镜头场景里的模型就是用它生成一次后存进场景文件的；正式运行时不再调用它。
## 想用脚本再造一只猫（比如先生成、再存成场景给美术调）时可以继续用。
## 坐标习惯和原型一致：y 朝上，整只猫的身体沿 x 轴、头朝 +x；单独的猫头脸朝 +z。

const WHITE := Color("f7f3ec")
const ORANGE := Color("e0a060")
const DARK := Color("3a3330")
const PINK := Color("f2a0a8")
## 四条腿的节点名（走路动画按这个名字找腿）
const LEG_NAMES: Array[String] = ["LegFrontL", "LegFrontR", "LegBackL", "LegBackR"]

static var _mats := {}
static var _faces := {}


## 卡通材质（同一种颜色只建一次）
static func toon(color: Color) -> StandardMaterial3D:
	if _mats.has(color):
		return _mats[color]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	_mats[color] = m
	return m


## 贴了图的卡通材质；cutout = 透明的地方直接镂空
static func toon_textured(tex: Texture2D, cutout: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	if cutout:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	return m


static func part(mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


static func sphere(radius: float, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	return part(m, mat, pos)


## 胶囊：length 是中间圆柱那段的长度（和原型的写法一致）
static func capsule(radius: float, length: float, mat: Material,
		pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = length + radius * 2.0
	return part(m, mat, pos)


static func cylinder(top: float, bottom: float, height: float, mat: Material,
		sides: int = 32) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	return part(m, mat)


## 按原型（three.js）的顺序设置旋转：先绕 x、再 y、再 z
static func euler_xyz(node: Node3D, x: float, y: float, z: float) -> void:
	var s := node.scale
	node.basis = Basis.from_euler(Vector3(x, y, z), EULER_ORDER_XYZ)
	node.scale = s


## 把一段 SVG 文字变成贴图（相当于原型里往画布上画）
static func svg_texture(svg: String) -> ImageTexture:
	var img := Image.new()
	img.load_svg_from_string(svg)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## SVG 圆弧路径，参数和画布的 arc 一样（角度是弧度，顺时针）
static func svg_arc(cx: float, cy: float, r: float, a0: float, a1: float) -> String:
	if a1 < a0:
		a1 += TAU
	return "M%.1f %.1f A%.1f %.1f 0 %d 1 %.1f %.1f" % [
		cx + r * cos(a0), cy + r * sin(a0), r, r, 1 if a1 - a0 > PI else 0,
		cx + r * cos(a1), cy + r * sin(a1)]


## 猫脸贴图。eyes: dot | closed | happy | big，mouth: w | smile
static func face_texture(eyes: String = "dot", mouth: String = "w") -> Texture2D:
	var key := eyes + mouth
	if _faces.has(key):
		return _faces[key]
	var s := '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">'
	for sx: float in [-1.0, 1.0]:
		var ex: float = 128.0 + sx * 58.0
		var ey: float = 110.0
		match eyes:
			"closed":
				s += '<path d="%s" fill="none" stroke="#111" stroke-width="12" stroke-linecap="round"/>' % svg_arc(ex, ey - 6, 22, 0.3, PI - 0.3)
			"happy":
				s += '<path d="%s" fill="none" stroke="#111" stroke-width="12" stroke-linecap="round"/>' % svg_arc(ex, ey + 14, 22, PI + 0.3, -0.3)
			"big":
				s += '<circle cx="%.1f" cy="%.1f" r="26" fill="#111"/><circle cx="%.1f" cy="%.1f" r="8" fill="#fff"/>' % [ex, ey, ex + 8, ey - 8]
			_:
				s += '<circle cx="%.1f" cy="%.1f" r="16" fill="#111"/>' % [ex, ey]
	s += '<path d="M116 140 L140 140 L128 154 Z" fill="#f08a98"/>'
	var mouth_path := svg_arc(128, 150, 30, 0.3, PI - 0.3) if mouth == "smile" \
			else svg_arc(110, 158, 18, 0.0, PI) + " " + svg_arc(146, 158, 18, 0.0, PI)
	s += '<path d="%s" fill="none" stroke="#111" stroke-width="9" stroke-linecap="round"/>' % mouth_path
	for sx: int in [-1, 1]:  # 胡子
		for dy: int in [-8, 8]:
			s += '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#000" stroke-opacity="0.5" stroke-width="4" stroke-linecap="round"/>' % [
				128 + sx * 70, 150 + dy, 128 + sx * 120, 144 + dy * 2]
	s += '</svg>'
	_faces[key] = svg_texture(s)
	return _faces[key]


## 猫头，脸朝 +z。o 里可以填：r（半径）、eyes、mouth、color（毛色）、patch（false = 不要橘色花斑）
static func make_head(o: Dictionary = {}) -> Node3D:
	var head := Node3D.new()
	var r: float = o.get("r", 0.4)
	var mat := toon(o.get("color", WHITE))
	var patch: bool = o.get("patch", true)
	var ball := sphere(r, mat)
	ball.scale = Vector3(1.1, 0.95, 1.0)
	ball.name = "Ball"
	head.add_child(ball)
	for sx: float in [-1.0, 1.0]:
		var ear := cylinder(0.0, r * 0.35, r * 0.6, toon(ORANGE) if (sx < 0 and patch) else mat, 4)
		ear.position = Vector3(sx * r * 0.55, r * 0.85, 0.0)
		euler_xyz(ear, 0.0, PI / 4, -sx * 0.35)
		ear.name = "EarL" if sx < 0 else "EarR"
		head.add_child(ear)
	if patch:
		var p := sphere(r * 0.45, toon(ORANGE), Vector3(-r * 0.45, r * 0.45, r * 0.45))
		p.scale = Vector3(1.0, 0.8, 0.5)
		p.name = "Patch"
		head.add_child(p)
	var quad := QuadMesh.new()
	quad.size = Vector2(r * 1.9, r * 1.9)
	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_texture = face_texture(o.get("eyes", "dot"), o.get("mouth", "w"))
	face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var face := part(quad, face_mat, Vector3(0.0, 0.0, r * 1.02))
	face.name = "Face"
	head.add_child(face)
	return head


## 整只猫，身体沿 x 轴、头朝 +x。o 同 make_head。
## 返回的节点上带着几个部件，可以用 cat.get_meta("legs") / "head" / "tail" / "body" 取到。
static func make_cat(o: Dictionary = {}) -> Node3D:
	var cat := Node3D.new()
	var mat := toon(o.get("color", WHITE))
	var body := sphere(0.5, mat)
	body.scale = Vector3(1.3, 0.85, 0.85)
	body.name = "Body"
	cat.add_child(body)
	var patch := sphere(0.3, toon(ORANGE), Vector3(-0.2, 0.3, 0.1))
	patch.scale = Vector3(1.3, 0.6, 1.0)
	patch.name = "Patch"
	cat.add_child(patch)
	var head := make_head(o)
	head.position = Vector3(0.7, 0.4, 0.0)
	head.rotation.y = PI / 2
	head.name = "Head"
	cat.add_child(head)
	var legs: Array[Node3D] = []
	for xz: Vector2 in [Vector2(0.35, 0.22), Vector2(0.35, -0.22), Vector2(-0.35, 0.22), Vector2(-0.35, -0.22)]:
		var pivot := Node3D.new()
		pivot.position = Vector3(xz.x, -0.2, xz.y)
		pivot.add_child(capsule(0.1, 0.25, mat, Vector3(0.0, -0.2, 0.0)))
		pivot.get_child(0).name = "Leg"
		pivot.name = LEG_NAMES[legs.size()]
		cat.add_child(pivot)
		legs.append(pivot)
	# 尾巴：沿一条曲线排一串小球
	var tail := Node3D.new()
	tail.name = "Tail"
	var pts: Array[Vector3] = [Vector3(-0.6, 0.05, 0), Vector3(-0.9, 0.2, 0), Vector3(-1.0, 0.55, 0), Vector3(-0.85, 0.8, 0)]
	for seg in 3:
		for i in 6:
			var before: Vector3 = pts[maxi(seg - 1, 0)]
			var after: Vector3 = pts[mini(seg + 2, 3)]
			tail.add_child(sphere(0.07, mat, pts[seg].cubic_interpolate(pts[seg + 1], before, after, i / 6.0)))
	tail.add_child(sphere(0.07, mat, pts[3]))
	for i in tail.get_child_count():
		tail.get_child(i).name = "Seg%02d" % i
	cat.add_child(tail)
	cat.set_meta("head", head)
	cat.set_meta("legs", legs)
	cat.set_meta("tail", tail)
	cat.set_meta("body", body)
	return cat


## 不受光照影响的纯色材质；alpha < 1 就是半透明（玻璃、光束），double_sided = 两面都画
static func flat(color: Color, alpha: float = 1.0, double_sided: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func box(size: Vector3, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return part(m, mat, pos)


## 圆环（甜甜圈）：radius 是环的半径，tube 是管子的粗细。平躺着（轴朝上）。
static func torus(radius: float, tube: float, mat: Material,
		pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = radius - tube
	m.outer_radius = radius + tube
	return part(m, mat, pos)


## 圆片：平躺着（面朝上）。要立起来面向镜头就把 rotation.x 设成 PI / 2。
static func disc(radius: float, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var d := cylinder(radius, radius, 0.01, mat, 48)
	d.position = pos
	return d


## 一片星星：每个点上放一个发光小方块，全部合成一个物体，很省
static func star_field(points: PackedVector3Array, size: float) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := flat(Color.WHITE)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED  # 永远正对镜头
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	return mi
