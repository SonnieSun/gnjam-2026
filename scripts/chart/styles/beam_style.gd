extends "res://scripts/chart/styles/style_3d.gd"
## 光圈沿光束套下：天上一道（或几道）光束打到地上的目标，音符是光圈，从光束顶上顺着往下套，
## 套到底部目标的那一拍按。轨道 = 第几道光束。光圈斜一点放，自转时看得出在转。

var top_y := 10.0
var bottom_y := 1.2
var beam_gap := 5.0
var top_radius := 0.9
var bottom_radius := 2.2


var _target_mats: Array[StandardMaterial3D] = []


func beam_x(i: int) -> float:
	return (i - (lanes() - 1) / 2.0) * beam_gap


func _build() -> void:
	camera.fov = 55.0
	camera.position = Vector3(0.0, 3.5, 14.0)
	camera.look_at(Vector3(0.0, 5.0, 0.0))
	for i in lanes():
		var beam := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = top_radius
		cone.bottom_radius = bottom_radius
		cone.height = top_y - bottom_y + 1.0
		cone.cap_top = false
		cone.cap_bottom = false
		beam.mesh = cone
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.45, 1.0, 0.45, 0.18)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = m
		beam.position = Vector3(beam_x(i), (top_y + bottom_y - 1.0) / 2.0, 0.0)
		root3d.add_child(beam)
		var target := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.5
		cap.height = 2.0
		target.mesh = cap
		target.material_override = make_material(Color(1.0, 0.95, 0.85))
		_target_mats.append(target.material_override)
		target.position = Vector3(beam_x(i), bottom_y, 0.0)
		root3d.add_child(target)
		var top := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = top_radius * 2.2
		disc.bottom_radius = top_radius * 1.4
		disc.height = 0.6
		top.mesh = disc
		top.material_override = make_material(Color(0.4, 0.4, 0.6))
		top.position = Vector3(beam_x(i), top_y + 0.3, 0.0)
		root3d.add_child(top)


func _update_3d() -> void:
	for i in _target_mats.size():
		var t := target_look(i)
		var c := Color(1.0, 0.95, 0.85).lerp(t.color, t.k * 0.8)
		_target_mats[i].albedo_color = c
		_target_mats[i].emission = c
		_target_mats[i].emission_energy_multiplier = 0.4 + t.k * 3.0


## 辅助线：光束上这一拍的光圈会到的高度，绕光束一圈（实线只画在有音符的那道光束上）
func _draw_guide(g: Dictionary) -> void:
	var look := guide_look(g)
	var y := lerpf(bottom_y, top_y, clampf(g.a, 0.0, 1.0))
	var u := (y - bottom_y) / (top_y - bottom_y)
	var radius := lerpf(bottom_radius, top_radius, u) * 1.15
	for i in lanes():
		if g.solid and not (g.lanes as Array).has(i):
			continue
		var pts := PackedVector2Array()
		for k in 33:
			var ang := k * TAU / 32.0
			pts.append(to_screen(Vector3(beam_x(i) + cos(ang) * radius, y, sin(ang) * radius)))
		if look.dashed:
			draw_dashed_polyline(pts, look.color, 1.5)
		else:
			draw_polyline(pts, look.color, 2.5 * look.width, true)


func _make_note(_n: NoteData) -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 1.0
	torus.rings = 48
	mi.mesh = torus
	mi.material_override = make_material(Color.WHITE)
	holder.add_child(mi)
	return holder


func _place_note(n: NoteData, node: Node3D, f: Dictionary) -> void:
	var a := clampf(approach(n), -0.15, 1.0)
	var y := lerpf(bottom_y, top_y, maxf(a, 0.0))
	var u := (y - bottom_y) / (top_y - bottom_y)
	var radius: float = lerpf(bottom_radius, top_radius, u) * 1.15 * f.scale
	node.position = Vector3(beam_x(lane_of(n)), y, 0.0)
	var ring := node.get_child(0) as Node3D
	ring.scale = Vector3.ONE * radius
	ring.rotation = Vector3(deg_to_rad(12.0), f.angle, 0.0)
	apply_look(node, f)


## 音符本身就是一圈：不画实线，只补空拍的虚线
func _solid_guides() -> bool:
	return false
