@tool
extends Spin3DSection
## MV 镜头 1 · 唱片：猫站在斜放的唱片上原地迈步，每打中一下唱片转一格。
## 照着猫咪 MV 原型里的 VIEWS.disc 移植。

var _disc: Node3D
var _cat: Node3D


func _build(root: Node3D) -> void:
	var tilt := Node3D.new()  # 唱片斜着放
	root.add_child(tilt)
	CatBuilder.euler_xyz(tilt, 0.45, 0.0, -0.38)

	_disc = Node3D.new()
	tilt.add_child(_disc)
	_disc.add_child(CatBuilder.cylinder(3.0, 3.0, 0.12, CatBuilder.toon(Color("222222")), 64))
	var top := PlaneMesh.new()
	top.size = Vector2(6.0, 6.0)
	_disc.add_child(CatBuilder.part(top, CatBuilder.toon_textured(_label_texture(), true), Vector3(0.0, 0.062, 0.0)))

	_cat = CatBuilder.make_cat({"eyes": "happy"})  # 猫站在唱片一侧，不跟着唱片转
	_cat.scale = Vector3.ONE * 0.85
	_cat.position = Vector3(1.9, 0.62, 0.9)
	_cat.rotation.y = PI / 2 + 0.4
	tilt.add_child(_cat)


func _focus() -> Vector3:
	return _cat.to_global(Vector3(0.0, 0.35, 0.0))


func _camera_pose(p: float, t: float) -> Dictionary:
	var a := -0.5 + p * 0.35
	return {
		"pos": Vector3(sin(a) * 7.5 - 0.5, 3.2 - p * 0.6, cos(a) * 7.5),
		"look": Vector3(0.4, 0.0, 0.0),
		"roll": 0.12 + sin(t * 1.2) * 0.04,
	}


func _update_view(t: float) -> void:
	_disc.rotation.y = -step_rot
	CatBuilder.walk(_cat, 14.0)
	_cat.position.y = 0.62 + absf(sin(t * 14.0)) * 0.05 + pulse() * 0.3  # 打中时蹦一下


## 唱片表面：纹路、两道反光、粉色的标签
func _label_texture() -> Texture2D:
	var s := '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">'
	s += '<circle cx="256" cy="256" r="255" fill="#111"/>'
	var r := 250
	while r > 90:
		s += '<circle cx="256" cy="256" r="%d" fill="none" stroke="%s" stroke-width="3"/>' % [r, "#1d1d1d" if r % 12 else "#2a2a2a"]
		r -= 6
	for mid: float in [0.0, PI]:
		s += '<path d="M256 256 L%.1f %.1f A255 255 0 0 1 %.1f %.1f Z" fill="#fff" fill-opacity="0.12"/>' % [
			256 + 255 * cos(mid - 0.3), 256 + 255 * sin(mid - 0.3), 256 + 255 * cos(mid + 0.3), 256 + 255 * sin(mid + 0.3)]
	s += '<circle cx="256" cy="256" r="85" fill="#ff7eb0"/>'
	var star := ""
	for i in 10:  # 标签上的星星
		var rr: float = 34.0 if i % 2 == 0 else 14.0
		var a: float = -PI / 2 + i * TAU / 10.0
		star += "%.1f,%.1f " % [256 + rr * cos(a), 212 + rr * sin(a)]
	s += '<polygon points="%s" fill="#fff"/>' % star
	s += '<rect x="216" y="286" width="80" height="10" rx="5" fill="#fff"/>'
	s += '<circle cx="256" cy="256" r="10" fill="#111"/></svg>'
	return CatBuilder.svg_texture(s)
