extends SceneTree
## Validate the imported washer in its real stage and capture its materials and cat opening.

const OUT := "res://docs/washer_preview"

func _initialize() -> void:
	_run.call_deferred()

func _capture(stage: Node, label: String) -> void:
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	stage.world.get_texture().get_image().save_png(OUT + "_" + label + ".png")

func _run() -> void:
	root.size = Vector2i(960, 720)
	var host := Node2D.new()
	root.add_child(host)
	var stage: Node = load("res://stages/tv_wall/intro/tv_wall_intro_stage.gd").new()
	host.add_child(stage)
	stage.fly_in_beats = 0.0
	stage.beat_camera = false
	stage.setup(host)
	var box := TvWallRoom.measure(stage._machine)
	assert(absf(box.size.x - 0.59) < 0.001, "Washer width must remain 0.59m")
	assert(absf(box.size.y - 0.84) < 0.001, "Washer height must remain 0.84m")
	var parts: Array = stage._machine.get_node("Model").find_children("*", "MeshInstance3D", true, false)
	assert(parts.size() == 3, "All three material parts must be imported")
	ComicStyle.style = ComicStyle.OFF
	stage.update(0.0, 0.0)
	var materials: Array[Material] = []
	for part in parts:
		assert(part.material_override is StandardMaterial3D)
		materials.append(part.material_override)
	assert(materials[0] != materials[1] and materials[1] != materials[2])
	await _capture(stage, "original")
	ComicStyle.style = ComicStyle.HALFTONE
	stage.update(0.0, 0.0)
	for part in parts:
		assert(part.material_override is ShaderMaterial, "Comic filter must reach every material")
	await _capture(stage, "comic")
	ComicStyle.style = ComicStyle.OFF
	stage.update(0.0, 0.0)
	for i in range(parts.size()):
		assert(parts[i].material_override == materials[i], "Style switching must restore source materials")
	stage.tap()
	var angle: float = stage._cat.rotation.z
	stage.update(0.0, 0.1)
	assert(not is_equal_approx(stage._cat.rotation.z, angle), "Cat still spins on tap")
	stage.holds_done = stage.zoom_holds
	stage.hold_begin()
	stage.hold_update(1.0, 2.0)
	var lit: Array = stage.hold_end(true)
	assert(lit.size() == stage.tvs_per_hold, "Completed hold still powers televisions")
	stage.skip_to_all_lit()
	stage._zoom = float(stage.zoom_holds)
	stage.update(0.0, 0.0)
	await _capture(stage, "tv_wall")
	print("PASS: washer size, three materials, comic switching, cat tap and TV power interaction")
	host.queue_free()
	await process_frame
	quit()
