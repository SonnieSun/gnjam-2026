@tool
extends Spin3DSection
## MV 镜头 3 · 拍地球：大猫探头伸爪子拍地球，地球一直在慢慢转，每拍中一下转得飞快再慢下来。
## 照着猫咪 MV 原型里的 VIEWS.earth 移植。

const EARTH_POS := Vector3(-0.8, -0.6, 0.0)

var _earth: MeshInstance3D
var _arm_pivot: Node3D


func _build(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pts := PackedVector3Array()
	for i in 600:  # 远处一圈星星
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		pts.append(dir * rng.randf_range(40.0, 80.0))
	root.add_child(CatBuilder.star_field(pts, 0.25))

	var ball := SphereMesh.new()
	ball.radius = 1.3
	ball.height = 2.6
	_earth = CatBuilder.part(ball, CatBuilder.toon_textured(_earth_texture()), EARTH_POS)
	root.add_child(_earth)

	var head := CatBuilder.make_head({"r": 1.0, "eyes": "dot"})
	head.position = Vector3(2.0, 2.0, -0.8)
	CatBuilder.euler_xyz(head, 0.35, -0.5, 0.0)
	root.add_child(head)

	_arm_pivot = Node3D.new()  # 肩膀；整条手臂绕着这里挥
	_arm_pivot.position = Vector3(1.6, 1.2, -0.3)
	root.add_child(_arm_pivot)
	_arm_pivot.add_child(CatBuilder.capsule(0.32, 1.8, CatBuilder.toon(CatBuilder.WHITE), Vector3(0.0, -1.0, 0.0)))
	_arm_pivot.add_child(CatBuilder.sphere(0.38, CatBuilder.toon(CatBuilder.WHITE), Vector3(0.0, -2.0, 0.0)))
	for i: int in [-1, 0, 1]:  # 肉垫
		_arm_pivot.add_child(CatBuilder.sphere(0.08, CatBuilder.toon(CatBuilder.PINK), Vector3(i * 0.15, -2.3, 0.15)))


func _focus() -> Vector3:
	return EARTH_POS


func _camera_pose(p: float, _t: float) -> Dictionary:
	var a := -0.15 + p * 0.3
	var d := 8.0 - p * 1.6
	return {
		"pos": Vector3(sin(a) * d, 0.3 + p * 0.6, cos(a) * d),
		"look": Vector3(0.0, 0.2, 0.0),
		"roll": -0.06 + p * 0.12,
	}


func _update_view(_t: float) -> void:
	_earth.rotation.y = free_spin
	var swing := sin(minf(hit_age / 0.25, 1.0) * PI)  # 打中后 0.25 秒内挥一下爪子
	CatBuilder.euler_xyz(_arm_pivot, swing * 0.3, 0.0, 0.55 - swing * 0.6)


## 地球表面：蓝色的海、几块绿色的陆地、两极的冰、几道云
func _earth_texture() -> Texture2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var s := '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="512" viewBox="0 0 1024 512">'
	s += '<rect width="1024" height="512" fill="#1d4fa8"/>'
	var blobs: Array[Rect2] = [Rect2(150, 180, 90, 120), Rect2(260, 330, 60, 90), Rect2(480, 170, 110, 70),
		Rect2(520, 300, 60, 110), Rect2(700, 200, 140, 80), Rect2(820, 330, 70, 50), Rect2(380, 80, 60, 30)]
	for b: Rect2 in blobs:  # position = 中心，size = 两个半径
		s += '<ellipse cx="%d" cy="%d" rx="%d" ry="%d" transform="rotate(17 %d %d)" fill="#4c9a3c"/>' % [
			b.position.x, b.position.y, b.size.x, b.size.y, b.position.x, b.position.y]
	s += '<rect width="1024" height="30" fill="#fff" fill-opacity="0.75"/><rect y="482" width="1024" height="30" fill="#fff" fill-opacity="0.75"/>'
	for i in 12:
		var cx := rng.randf() * 1024.0
		var cy := rng.randf() * 512.0
		s += '<path d="M%.0f %.0f q80 %.0f 160 0" fill="none" stroke="#fff" stroke-opacity="0.4" stroke-width="10" stroke-linecap="round"/>' % [
			cx - 80.0, cy, rng.randf_range(-24.0, 24.0)]
	s += '</svg>'
	return CatBuilder.svg_texture(s)
