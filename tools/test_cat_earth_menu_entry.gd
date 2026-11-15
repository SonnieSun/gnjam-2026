extends SceneTree
## Regression for loading the actual menu, selecting slot 3 (ORBIT CAT) and entering the game.

var _checks: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		_checks.append(label)
	else:
		_failures.append(label)
		push_error(label)


func _finish() -> void:
	print("CAT_EARTH_MENU_ENTRY ", JSON.stringify({"passed": _failures.is_empty(), "checks": _checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)


func _run() -> void:
	var chart: Resource = load("res://levels/level_3_orbit_cat.tres")
	_check(chart != null, "Third level resource loads without a merge or parse error")
	if chart == null:
		_finish()
		return
	_check(chart.get("title") == "ORBIT CAT", "Third menu slot resolves to ORBIT CAT")
	Levels.selected = 0
	var menu: Node = load(Levels.MENU_SCENE).instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.turn(1)
	menu.turn(1)
	_check(Levels.selected == 2, "Existing menu turns select slot 3")
	menu.start()
	# Allow the normal start tween, scene replacement and initial rendering to finish.
	await create_timer(1.2).timeout
	var game: Node = current_scene
	_check(game != null and game.scene_file_path == Levels.GAME_SCENE, "Actual menu start opens the existing game scene")
	if game == null or game.scene_file_path != Levels.GAME_SCENE:
		_finish()
		return
	_check(game.chart != null and game.chart.title == "ORBIT CAT", "Game initializes the selected chart")
	_check(game._current != null and game._current.name == "CatEarth", "Cat Earth section enters successfully")
	await create_timer(1.0).timeout
	_check(game._current != null and game._current.is_inside_tree(), "Cat Earth stays active after the start")
	_check(root.get_node("Conductor").playing, "Shared music clock is running")
	game.back_to_menu()
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.scene_file_path == Levels.MENU_SCENE, "Return to the existing menu succeeds")
	_finish()
