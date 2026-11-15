extends SceneTree
## End-to-end regression for the authored chart, existing Judge and charge→strike gauge flow.

var _failures: Array[String] = []
var _checks: Array[String] = []
var _game: Node
var _clock: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		_checks.append(label)
	else:
		_failures.append(label)
		push_error(label)


func _freeze_clock() -> void:
	_clock = root.get_node("Conductor")
	_clock.stop()
	_clock.set_process(false)
	_clock.playing = true


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
	_game._current._process(0.0)


func _restart() -> void:
	_game.start_from(0)
	_freeze_clock()


func _run() -> void:
	Levels.selected = 1
	_game = load("res://main.tscn").instantiate()
	root.add_child(_game)
	await process_frame
	await process_frame
	_freeze_clock()
	_check(_game.chart.title == "ORBIT CAT", "Menu slot2 loads ORBIT CAT")
	_check(_game.chart.sections.size() == 3, "Three editor-authored stages")
	_check(is_equal_approx(_game.chart.bpm, 120.0), "120BPM keeps original4second scene timing")
	var bars_in_music: float = _game.chart.stream.get_length() / (_clock.sec_per_beat() * 4.0)
	_check(absf(bars_in_music - roundf(bars_in_music)) < 0.015, "Existing backing track loops on whole120BPM bars")
	var stage: Node = _game._current
	_check(stage.has_method("restore_rest") and stage.has_method("hit_position"), "Section follows Spin3DSection editor contract")
	_check(stage.get_node_or_null("View/Viewport/Camera") != null, "Native editable Camera node")
	_check(stage.get_node_or_null("View/Viewport/World") != null, "Native editable World node")
	_check(stage.get_node_or_null("%Focus") != null, "Unique editable strike Focus marker")
	_check(stage.has_method("charge_ratio"), "Charge state is inspectable")
	_at(4.0, true)
	_check(stage.charge_hits() == 1, "Existing Judge perfect HAT increments charge")
	_check(stage.charge_target() == 4, "Target derives from authored intro HAT pattern")
	_check(_game.gauge.value == 0, "Charging alone cannot fill completion gauge")
	_at(4.5, true)
	_at(5.0, true)
	_at(5.5, true)
	_check(stage.charge_hits() == 4, "Four rapid hits fully charge intro")
	_at(6.0, true)
	_check(_game.gauge.value == 5, "Charged on-beat strike advances existing Gauge")
	_check(stage.last_strike_was_charged, "Strike consumes charged state")
	var player := stage.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_check(player != null and is_equal_approx(player.get_animation("CatEarthLoop").length, 4.0), "FBX retains the original4second animation")
	_check(absf(player.current_animation_position - 77.0 / 24.0) < 0.002, "Beat6 samples the originalframe78 contact exactly")
	var skeleton := stage.find_child("Skeleton3D", true, false) as Skeleton3D
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("fore_paw.L")).origin
	_check(hand.distance_to(Vector3(1.11, 1.21, 0.56)) < 0.025, "Imported strike paw matches the originalEarth contact")
	_check(not stage.wants_hit_effects(_game.judge.notes[0]), "Charge taps preserve subject visibility without overlapping bursts")
	_check(_game.judge.counts[NoteData.Result.PERFECT] == 5, "Unified Judge retains accuracy/combo scoring")
	_restart()
	stage = _game._current
	_at(3.9, true)
	_at(4.0)
	_check(stage.charge_hits() == 1, "Early perfect first tap survives its musicalcycle boundary")
	for beat in [4.5, 5.0, 5.5, 6.0]:
		_at(beat, true)
	_check(_game.gauge.value == 5, "Early accepted charge taps still enable the strike")
	_restart()
	stage = _game._current
	_at(4.0, true)
	_at(6.0, true)
	_check(_game.gauge.value == 0, "Undercharged strike cannot advance completion")
	_check(not stage.last_strike_was_charged, "Undercharged strike reports low power")
	_restart()
	_at(6.5)
	_check(_game.gauge.value == 0, "Missed charge/strike cannot advance completion")
	_restart()
	_game.editing = true
	for beat in [4.0, 4.5, 5.0, 5.5, 6.0]:
		_at(beat, true)
	_check(_game.gauge.value == 0, "Tab editor mode freezes completion Gauge")
	_game.editing = false
	_restart()
	for bar in range(4):
		var start := 4.0 + bar * 4.0
		for offset in [0.0, 0.5, 1.0, 1.5, 2.0]:
			_at(start + offset, true)
	_at(20.0)
	_check(_game._index == 1, "Full charge strikes advance at next bar into stage2")
	_check(_game.gauge.max_value == 30, "Stage2 reads inspector-authored Gauge maximum")
	await _complete_stage()
	_check(_game._index == 2, "Dense six-hit stage advances into SUPERNOVA")
	_check(_game.gauge.max_value == 40, "Final stage reads its editor-authored Gauge maximum")
	await _complete_stage()
	_check(_game._cleared, "Full three-stage level reaches existing level-clear flow")
	_check(_game.hud.result_label.visible, "Existing result HUD displays completion")
	_game._current.restore_rest()
	var final_player := _game._current.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_check(is_zero_approx(final_player.current_animation_position), "Editor restore returns animation to authoredframe0")
	_clock.stop()
	_game.queue_free()
	await process_frame
	Levels.selected = 0
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu.turn(1)
	_check(Levels.selected == 1, "Existing menu selects the second level")
	var anchor: Node = menu.get_node("Disc3D/View/Viewport/Stage/Labels/Item2/Anchor")
	_check(anchor.get_node("Title").text == "ORBIT CAT", "Native 3D menu names the playable level")
	_check(anchor.get_node("Sub").text == "3 STAGES", "Native 3D menu advertises all three stages")
	menu.queue_free()
	await process_frame
	var report := {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures}
	var output := FileAccess.open("res://docs/cat_earth_test_results.json", FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify(report, "\t"))
	print("CAT_EARTH_TESTS ", JSON.stringify(report))
	quit(0 if _failures.is_empty() else 1)


func _complete_stage() -> void:
	var stage_index: int = _game._index
	var first: float = _game.chart.sections[stage_index].start_beat + _game.chart.rest_bars_on_switch * 4.0
	for bar in range(20):
		var start := first + bar * 4.0
		_at(start)
		var planned: Array[NoteData] = []
		for note: NoteData in _game.judge.notes:
			if not note.judged and note.section_index == stage_index and note.beat >= start - 0.001 and note.beat < start + 4.0 - 0.001:
				planned.append(note)
		for note in planned:
			_at(note.beat, true)
		if _game.gauge.full:
			_at(start + 4.0)
			await process_frame
			return
	_check(false, "Authored stage can be completed through realJudge input")
