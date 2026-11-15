extends SceneTree

const DIR := "res://assets/models/cat_earth_y2k/"

func _initialize() -> void:
	call_deferred("_build")

func _material(name: String, texture_name: String, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	material.albedo_texture = load(DIR + texture_name) as Texture2D
	material.albedo_color = Color.WHITE
	material.roughness = roughness
	material.metallic = metallic
	material.emission_enabled = false
	return material

func _save_material(material: Material, name: String) -> void:
	assert(ResourceSaver.save(material, DIR + name + ".tres") == OK)
	material.take_over_path(DIR + name + ".tres")

func _build() -> void:
	# A fresh checkout has no ignored export cache yet.
	assert(DirAccess.make_dir_recursive_absolute(DIR + ".export_cache") == OK)
	var ignore := FileAccess.open(DIR + ".export_cache/.gdignore", FileAccess.WRITE)
	assert(ignore != null)
	ignore.close()
	var packed := load(DIR + "cat_earth_y2k.fbx") as PackedScene
	assert(packed != null)
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	model.name = "CatEarthModel"
	var cat := _material("Cat · original texture", "cat_basecolor_512.png", 0.9)
	cat.metallic_specular = 0.15
	_save_material(cat, "cat_material")
	var earth := _material("Earth · NASA Blue Marble", "earth_day_clouds.jpg", 0.78)
	earth.metallic_specular = 0.23
	_save_material(earth, "earth_material")
	var galaxy := _material("Galaxy · baked camera background", "galaxy_backdrop.png", 1.0)
	galaxy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	galaxy.cull_mode = BaseMaterial3D.CULL_DISABLED
	galaxy.texture_repeat = false
	_save_material(galaxy, "galaxy_material")
	var blue := _material("Puffy stars · blue purple", "star_blue_purple.png", 0.28, 0.30)
	blue.clearcoat_enabled = true
	blue.clearcoat = 0.38
	blue.clearcoat_roughness = 0.22
	blue.emission_enabled = true
	blue.emission = Color.WHITE
	blue.emission_texture = blue.albedo_texture
	blue.emission_energy_multiplier = 0.045
	_save_material(blue, "star_blue_material")
	var purple := blue.duplicate() as StandardMaterial3D
	purple.resource_name = "Puffy stars · purple blue"
	purple.albedo_texture = load(DIR + "star_purple_blue.png") as Texture2D
	purple.emission_texture = purple.albedo_texture
	_save_material(purple, "star_purple_material")
	var glints: Array[StandardMaterial3D] = []
	for i in 2:
		var material := StandardMaterial3D.new()
		material.resource_name = "Glint · " + ("blue" if i == 0 else "purple")
		material.albedo_color = Color(0.3811, 0.65, 0.8808) if i == 0 else Color(0.6343, 0.4366, 0.821)
		material.roughness = 0.32
		material.metallic = 0.35
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 0.4
		_save_material(material, "glint_%s_material" % ("blue" if i == 0 else "purple"))
		glints.append(material)
	model.get_node("CatRig/Skeleton3D/CatMesh").material_override = cat
	model.get_node("EarthSpin/EarthMesh").material_override = earth
	model.get_node("GalaxyBackdrop").material_override = galaxy
	for i in 5:
		model.get_node("Star%02d" % (i+1)).material_override = blue if i in [0,2,4] else purple
	for i in 2:
		model.get_node("Glint%02d" % (i+1)).material_override = glints[i]
	# The gameplay section owns the active camera, not the imported FBX.
	var camera := model.get_node_or_null("SceneCamera")
	if camera:
		model.remove_child(camera)
		camera.free()
	model.set_meta("source_fbx", DIR + "cat_earth_y2k.fbx")
	model.set_meta("source_blend", "cat_earth_y2k_scene.blend")
	model.set_meta("animation_seconds", 4.0)
	model.set_meta("contacts_seconds", PackedFloat32Array([29.0/24.0,77.0/24.0]))
	var output := PackedScene.new()
	assert(output.pack(model) == OK)
	assert(ResourceSaver.save(output, DIR + "cat_earth_model.tscn") == OK)
	var player := model.get_node("AnimationPlayer") as AnimationPlayer
	var take := player.get_animation("CatEarthLoop")
	assert(is_equal_approx(take.length, 4.0))
	var skeleton := model.get_node("CatRig/Skeleton3D") as Skeleton3D
	assert(skeleton.find_bone("fore_paw.L") == 7)
	var report := {"scene": DIR+"cat_earth_model.tscn", "animation_player":"AnimationPlayer", "take":"CatEarthLoop", "length": take.length,
		"paw_bone":"fore_paw.L", "paw_bone_index":7, "removed_imported_camera":true,
		"skinned_cat_path":"CatRig/Skeleton3D/CatMesh", "earth_spin_path":"EarthSpin", "material_overrides":9}
	var file := FileAccess.open(DIR + ".export_cache/wrapper_validation.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report,"\t"))
	quit()
