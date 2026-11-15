extends SceneTree
## Render the actual game scene for visual QA; no UI automation or production overrides.

var _game: Node
var _clock: Node


func _initialize() -> void:
	_run.call_deferred()


func _at(beat: float, press := false) -> void:
	_clock.song_beat = beat
	_clock.song_time = beat * _clock.sec_per_beat()
	_game.judge._process(0.0)
	if press:
		var event := InputEventAction.new()
		event.action = "hit"
		event.pressed = true
		_game.judge._unhandled_input(event)
	_game._process(0.0)


func _capture(path: String) -> void:
	for _frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _run() -> void:
	root.size = Vector2i(960, 720)
	Levels.selected = 1
	_game = load("res://main.tscn").instantiate()
	root.add_child(_game)
	await process_frame
	await process_frame
	_clock = root.get_node("Conductor")
	_clock.stop()
	_clock.set_process(false)
	_clock.playing = true
	for beat in [4.0, 4.5, 5.0, 5.5]:
		_at(beat, true)
	_at(5.65)
	await _capture("res://docs/cat_earth_level_preview.png")
	_at(6.0, true)
	await _capture("res://docs/cat_earth_impact_preview.png")
	_game.toggle_editor()
	await _capture("res://docs/cat_earth_editor_preview.png")
	_clock.stop()
	_game.queue_free()
	await process_frame
	await process_frame
	quit()
