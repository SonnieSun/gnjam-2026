extends "res://scripts/chart/styles/style_3d.gd"
## 3D 轨道从深处过来：几条往远处延伸的道，音符（水果那种立体物件）从深处沿道飞到镜头前的判定线，压线时按。
## 轨道 = 第几条道。底鼓是球、军鼓是方块、踩镲是菱形；大小 / 自转 / 发光 / 跟拍胀缩都作用在物件上。

## 道有多长（音符从多远开始飞）、两条道隔多宽
var depth := 42.0
var lane_gap := 2.6
var _judge_mat: StandardMaterial3D


func lane_x(i: int) -> float:
	return (i - (lanes() - 1) / 2.0) * lane_gap


func _build() -> void:
	camera.fov = 55.0
	camera.position = Vector3(0.0, 4.2, 7.5)
	camera.look_at(Vector3(0.0, 0.0, -8.0))
	for i in lanes():
		var strip := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(lane_gap * 0.92, depth + 6.0)
		strip.mesh = plane
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.08, 0.22, 0.75)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		strip.material_override = m
		strip.position = Vector3(lane_x(i), 0.0, -depth / 2.0 + 3.0)
		root3d.add_child(strip)
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(lane_gap * maxi(lanes(), 1) + 0.6, 0.08, 0.25)
	line.mesh = box
	_judge_mat = make_material(Color(1, 1, 1))
	line.material_override = _judge_mat
	line.position = Vector3(0.0, 0.05, 0.0)
	root3d.add_child(line)


func _make_note(n: NoteData) -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	match n.sound:
		NoteData.Sound.KICK:
			var s := SphereMesh.new()
			s.radius = 0.55
			s.height = 1.1
			mi.mesh = s
		NoteData.Sound.SNARE:
			var b := BoxMesh.new()
			b.size = Vector3.ONE * 0.9
			mi.mesh = b
		_:
			var p := PrismMesh.new()
			p.size = Vector3(0.9, 1.0, 0.9)
			mi.mesh = p
	mi.material_override = make_material(Color.WHITE)
	holder.add_child(mi)
	if n.length > 0.0:
		var tail := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.35, 0.1, 1.0)
		tail.mesh = tb
		tail.name = "Tail"
		tail.material_override = make_material(Color.WHITE)
		holder.add_child(tail)
	return holder


func _place_note(n: NoteData, node: Node3D, f: Dictionary) -> void:
	var a := approach(n)
	if n.length > 0.0:
		a = maxf(a, 0.0)
	node.position = Vector3(lane_x(lane_of(n)), 0.6, -a * depth)
	var body := node.get_child(0) as Node3D
	body.scale = Vector3.ONE * f.scale
	body.rotation = Vector3(0.0, f.angle, f.angle * 0.3)
	var tail := node.get_node_or_null("Tail") as MeshInstance3D
	if tail:
		var end_a := clampf((n.beat + n.length - beat) / lead_of(n), 0.0, 1.0)
		var len := maxf((end_a - a) * depth, 0.01)
		tail.scale = Vector3(1.0, 1.0, len)
		tail.position = Vector3(0.0, -0.4, -len / 2.0)
	apply_look(node, f)


func _update_3d() -> void:
	_update_guides()
	if _judge_mat:
		var t := target_look()
		_judge_mat.emission = t.color
		_judge_mat.albedo_color = t.color
		_judge_mat.emission_energy_multiplier = 0.6 + pow(1.0 - fposmod(beat, 1.0), 3.0) * 1.2 + t.k * 3.0


## 辅助线在这里是真的 3D 细条，平铺在道面上（画在 2D 层会被半透明的道面挡住）
func _draw_guide(_g: Dictionary) -> void:
	pass


var _guide_pool: Array[MeshInstance3D] = []


func _guide_strip(i: int) -> MeshInstance3D:
	while _guide_pool.size() <= i:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mi.mesh = box
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = false
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root3d.add_child(mi)
		_guide_pool.append(mi)
	return _guide_pool[i]


## 每拍一条横跨所有道的细条，在这一拍飞到的深度：实线一整条，虚线切成一小段一小段
func _update_guides() -> void:
	var used := 0
	var half := lane_gap * lanes() / 2.0
	for g in guides():
		var look := guide_look(g)
		var z := -clampf(g.a, -0.1, 1.0) * depth
		var thick: float = 0.12 * look.width if not look.dashed else 0.06
		var pieces := 1 if not look.dashed else lanes() * 4
		var piece_len := half * 2.0 / pieces
		for k in pieces:
			var mi := _guide_strip(used)
			used += 1
			mi.visible = true
			var len := piece_len * (1.0 if pieces == 1 else 0.55)
			mi.scale = Vector3(len, 0.01, thick)
			mi.position = Vector3(-half + piece_len * (k + 0.5), 0.02, z)
			(mi.material_override as StandardMaterial3D).albedo_color = look.color
	for k in range(used, _guide_pool.size()):
		_guide_pool[k].visible = false
