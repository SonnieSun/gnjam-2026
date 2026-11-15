@tool
class_name WireShape
extends MeshInstance3D
## 只有棱线的立体几何体（白色描边的方块、金字塔、八面体、圆环球）。棱线是细长的小棱柱，所以粗细可调。
## 形状、大小、粗细、颜色在检查器里选；转不转、怎么转由外面的脚本管（见 road_backdrop.gd）。

enum Shape { CUBE, PYRAMID, OCTAHEDRON, RING_BALL, PRISM }

@export var shape: Shape = Shape.CUBE:
	set(v):
		shape = v
		_rebuild()
## 大小（大约的直径）
@export var size := 8.0:
	set(v):
		size = v
		_rebuild()
## 棱线粗细
@export var thickness := 0.18:
	set(v):
		thickness = v
		_rebuild()
@export var color := Color(1, 1, 1):
	set(v):
		color = v
		_apply_color()
## 平时慢慢转：转一圈几拍（0 = 不转），绕哪根轴转
@export var beats_per_rev := 16.0
@export var spin_axis := Vector3(0.3, 1.0, 0.2)
## 玩家按键时多转一整圈，用几秒转完
@export var kick_seconds := 0.45
## 玩家按键时胀大多少（0.25 = 胀到 1.25 倍再缩回去）
@export var kick_pop := 0.25

## 整体多亮 0-1（淡入淡出用）
var strength := 1.0:
	set(v):
		strength = v
		_apply_color()

var _mat: StandardMaterial3D
var _rest_basis := Basis.IDENTITY
var _rest_position := Vector3.ZERO
var _kick_t := -1.0   # 按键那一圈转到哪了（秒），-1 = 没在转
var _kick_from := 0.0  # 上一圈还没转完又按了：从当时的角度接着转满
var _pop := 0.0


func _ready() -> void:
	_rest_basis = basis
	_rest_position = position
	_rebuild()


## 玩家按了一下：多转一整圈（先快后慢），同时胀一下。amount = 这次胀多少的倍数（外面给点随机，各个不一样）
func kick(amount: float = 1.0) -> void:
	_kick_from = _kick_angle()
	_kick_t = 0.0
	_pop = amount


func _kick_angle() -> float:
	if _kick_t < 0.0:
		return 0.0
	var p := clampf(_kick_t / maxf(kick_seconds, 0.01), 0.0, 1.0)
	return lerpf(_kick_from, TAU, 1.0 - pow(1.0 - p, 2.0))


## 每帧调用：一直慢慢转（跟着音乐的速度），按键那一圈叠在上面；轻轻上下浮
func animate(beat: float, delta: float) -> void:
	if _kick_t >= 0.0:
		_kick_t += delta
		if _kick_t >= kick_seconds:
			_kick_t = -1.0
	_pop = maxf(_pop - delta / 0.3, 0.0)
	var slow := beat / beats_per_rev * TAU if beats_per_rev > 0.0 else 0.0
	var axis := spin_axis.normalized()
	basis = (Basis(axis, slow + _kick_angle()) * _rest_basis).scaled(Vector3.ONE * (1.0 + kick_pop * _pop))
	position = _rest_position + Vector3.UP * sin(beat * PI * 0.5 + _rest_position.x) * size * 0.06


func _apply_color() -> void:
	if _mat:
		_mat.albedo_color = Color(color.r, color.g, color.b, strength)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_apply_color()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in _edges():
		_add_edge(st, e[0], e[1])
	st.generate_normals()
	mesh = st.commit()
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 这个形状的所有棱：[[起点, 终点], ...]
func _edges() -> Array:
	var r := size * 0.5
	var pts: Array[Vector3] = []
	var pairs: Array = []
	match shape:
		Shape.CUBE:
			for i in 8:
				pts.append(Vector3(-r if i & 1 == 0 else r, -r if i & 2 == 0 else r, -r if i & 4 == 0 else r))
			pairs = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
		Shape.PYRAMID:
			pts = [Vector3(-r, -r * 0.7, -r), Vector3(r, -r * 0.7, -r), Vector3(r, -r * 0.7, r), Vector3(-r, -r * 0.7, r),
					Vector3(0, r, 0)]
			pairs = [[0, 1], [1, 2], [2, 3], [3, 0], [0, 4], [1, 4], [2, 4], [3, 4]]
		Shape.OCTAHEDRON:
			pts = [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r), Vector3(0, r * 1.3, 0),
					Vector3(0, -r * 1.3, 0)]
			pairs = [[0, 2], [2, 1], [1, 3], [3, 0], [0, 4], [1, 4], [2, 4], [3, 4], [0, 5], [1, 5], [2, 5], [3, 5]]
		Shape.PRISM:
			for k in 2:
				for i in 3:
					var a := i * TAU / 3.0
					pts.append(Vector3(cos(a) * r, (k * 2 - 1) * r * 0.9, sin(a) * r))
			pairs = [[0, 1], [1, 2], [2, 0], [3, 4], [4, 5], [5, 3], [0, 3], [1, 4], [2, 5]]
		Shape.RING_BALL:
			# 三个互相垂直的圆环，看起来像一个线框球
			var out := []
			var seg := 28
			for ring in 3:
				for i in seg:
					var a := i * TAU / seg
					var b := (i + 1) * TAU / seg
					var p := Vector3(cos(a), sin(a), 0.0) * r
					var q := Vector3(cos(b), sin(b), 0.0) * r
					if ring == 1:
						p = Vector3(p.x, 0.0, p.y)
						q = Vector3(q.x, 0.0, q.y)
					elif ring == 2:
						p = Vector3(0.0, p.y, p.x)
						q = Vector3(0.0, q.y, q.x)
					out.append([p, q])
			return out
	var edges := []
	for pr in pairs:
		edges.append([pts[pr[0]], pts[pr[1]]])
	return edges


## 一条棱 = 一根四棱柱
func _add_edge(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized() * thickness * 0.5
	var up := dir.cross(side).normalized() * thickness * 0.5
	a -= dir * thickness * 0.5  # 两头各多出半个粗细，拐角处接得上
	b += dir * thickness * 0.5
	var c := [side + up, -side + up, -side - up, side - up]
	for i in 4:
		var p0: Vector3 = c[i]
		var p1: Vector3 = c[(i + 1) % 4]
		st.add_vertex(a + p0)
		st.add_vertex(b + p0)
		st.add_vertex(b + p1)
		st.add_vertex(a + p0)
		st.add_vertex(b + p1)
		st.add_vertex(a + p1)
