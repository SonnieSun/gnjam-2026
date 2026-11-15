extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var model := load("res://stages/tv_wall/washer/washing_machine.tscn").instantiate() as Node3D
	root.add_child(model)
	model.set_process(false)
	assert(model._bands.size() == 2, "Both animated lightband materials must survive export")
	var mesh := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	assert(mesh.mesh.get_surface_count() == 3, "Body and both lightbands need separate surfaces")
	assert(mesh.material_override == null, "A whole-mesh override would erase the lightbands")
	var body := mesh.get_active_material(0) as StandardMaterial3D
	assert(is_zero_approx(body.metallic) and is_equal_approx(body.roughness, 1.0), "Body must retain its base color with no metallic effect")
	var box := mesh.global_transform * mesh.get_aabb()
	assert(absf(box.size.x - 0.59) < 0.002 and absf(box.size.y - 0.84) < 0.002)
	var first: Color = model._bands[0].material.albedo_color
	var second: Color = model._bands[1].material.albedo_color
	for band in model._bands:
		assert(band.material.emission_enabled and band.material.emission_energy_multiplier > 0.0)
		assert(band.material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
		assert(band.material.emission.is_equal_approx(band.material.albedo_color))
	model._process(0.5)
	assert(model._bands[0].material.albedo_color.is_equal_approx(second), "First band must switch at half a second")
	assert(model._bands[1].material.albedo_color.is_equal_approx(first), "Second band must alternate in opposite phase")
	assert(model._bands[0].material.emission.is_equal_approx(second), "Emission must follow the animated band color")
	model._process(0.5)
	assert(model._bands[0].material.albedo_color.is_equal_approx(first), "Animation must wrap after one second")
	model._process(10.5)
	assert(model._bands[0].material.albedo_color.is_equal_approx(second), "Animation must keep looping")
	print("PASS: v8 geometry, three materials, two alternating bands, one-second continuous loop")
	model.free()
	quit()
