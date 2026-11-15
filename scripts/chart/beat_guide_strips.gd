class_name BeatGuideStrips
extends Node3D
## 3D 里的节拍辅助线：一堆很薄的发光细条，可以摆成直线（横在路面上）或者一圈（套在光束上）。
## 每帧：begin() → 用 line() / circle() 摆好这一帧要的线 → finish()（没用上的藏起来）。
## 颜色粗细用 BeatGuides.look(g) 给的；虚线自动切成一段一段的。加到哪个节点下，坐标就是那个节点的。

var _pool: Array[MeshInstance3D] = []
var _used := 0


func begin() -> void:
	_used = 0


func finish() -> void:
	for i in range(_used, _pool.size()):
		_pool[i].visible = false


## from → to 一条线。thickness = 实线的基础粗细（米）
func line(from: Vector3, to: Vector3, l: Dictionary, thickness := 0.12, up := Vector3.UP) -> void:
	var pieces := 1
	if l.dashed:
		pieces = maxi(int(from.distance_to(to) / 1.2), 2)
	for k in pieces:
		var a := from.lerp(to, float(k) / pieces)
		var b := from.lerp(to, (k + (0.55 if l.dashed else 1.0)) / pieces)
		_segment(a, b, l.color, (0.05 if l.dashed else thickness * l.width), up)


## 平放的一圈（center 是圆心，normal 是圆面朝向）
func circle(center: Vector3, radius: float, l: Dictionary, thickness := 0.1, normal := Vector3.UP) -> void:
	var count := 40
	var basis := Basis.looking_at(normal, Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.9 else Vector3.UP)
	var u := basis.x
	var v := basis.y
	for i in count:
		if l.dashed and i % 2 == 1:
			continue
		var a0 := i * TAU / count
		var a1 := (i + 1) * TAU / count
		var p0 := center + (u * cos(a0) + v * sin(a0)) * radius
		var p1 := center + (u * cos(a1) + v * sin(a1)) * radius
		_segment(p0, p1, l.color, (0.04 if l.dashed else thickness * l.width), normal)


func _segment(a: Vector3, b: Vector3, color: Color, thickness: float, up: Vector3) -> void:
	var mi := _next()
	var dir := b - a
	var length := dir.length()
	if length < 0.0001:
		mi.visible = false
		return
	var x := dir / length
	var y := up.normalized()
	if absf(x.dot(y)) > 0.95:
		y = Vector3.FORWARD
	var z := x.cross(y).normalized()
	y = z.cross(x).normalized()
	mi.transform = Transform3D(Basis(x * length, y * 0.01, z * thickness), (a + b) / 2.0)
	(mi.material_override as StandardMaterial3D).albedo_color = color
	mi.visible = true


func _next() -> MeshInstance3D:
	if _used >= _pool.size():
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mi.mesh = box
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_pool.append(mi)
	_used += 1
	return _pool[_used - 1]
