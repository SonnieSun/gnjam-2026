class_name LevelKitDev
extends Node
## Command line helpers for the level tool, only alive when the editor scene
## is started with arguments after `--`:
##
##   --selftest                      run every system once, print SELFTEST OK, quit
##   --gen=<name>                    generate levels/<name>.json and quit
##     --seed=N --diff=0..1 --bars=N --bpm=N --world
##   --level=<name>                  open levels/<name>.json
##   --song=<file>                   use this audio as the song (+ its analysis)
##     --gen-from-song                 ...and generate the chart from its onsets
##   --shot=<file.png>               screenshot after a moment, quit
##     --at=<seconds>  --playtest  --play

var ed: LevelEditor
var _fails: Array[String] = []


func _init(editor: LevelEditor) -> void:
	ed = editor


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if args.has("selftest"):
		await _selftest()
		return
	if args.has("gen"):
		_gen(args)
		return
	if args.has("level"):
		ed.doc.open(LevelDoc.level_dir().path_join(args.level + ".json"))
	if args.has("song"):
		ed.import_song(args.song)
		if args.has("gen-from-song"):
			ed._use_onsets.button_pressed = true
			ed.generate_chart()
		print("song: %s  bpm %.2f  offset %.3f  length %d  onsets %d  notes %d" % [ed.doc.level.meta.song, ed.doc.level.meta.bpm, ed.doc.level.meta.offset, ed.doc.level.meta.length, ed.onsets.size(), ed.doc.level.chart.size()])
	if args.has("shot"):
		await _shot(args)


func _gen(args: Dictionary) -> void:
	var lvl := LevelData.new()
	lvl.meta.name = args.gen
	lvl.meta.bpm = float(args.get("bpm", "120"))
	var bars := int(args.get("bars", "16"))
	lvl.meta.length = (bars + 1) * 4.0
	ChartGen.generate(lvl, {seed = int(args.get("seed", "1")), difficulty = float(args.get("diff", "0.5")), bars = bars})
	if args.has("world"):
		ChartGen.place_runner(lvl)
	var path := LevelDoc.level_dir().path_join(str(args.gen) + ".json")
	print("%s %s  (%d notes, %d entities)" % ["wrote" if lvl.save(path) else "FAILED", path, lvl.chart.size(), lvl.entities.size()])
	get_tree().quit()


func _shot(args: Dictionary) -> void:
	await get_tree().process_frame
	if args.has("playtest"):
		ed.start_playtest()
	elif args.has("play"):
		ed.clock.play()
	await get_tree().create_timer(float(args.get("at", "1.5"))).timeout
	get_viewport().get_texture().get_image().save_png(args.shot)
	print("shot ", args.shot)
	get_tree().quit()


# --- self test -------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
		printerr("FAIL: ", what)


func _selftest() -> void:
	Sfx.enabled = false
	await get_tree().process_frame
	_test_data()
	_test_gen()
	_test_judge()
	_test_clock()
	_test_doc_and_builder()
	await _test_ui()
	if _fails.is_empty():
		print("SELFTEST OK")
	else:
		print("SELFTEST FAILED: %d" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)


func _test_data() -> void:
	var a := LevelData.new()
	a.meta.bpm = 140.0
	a.add_note(4.0, 1)
	a.add_note(2.0, 0, 1.5)
	a.add_note(2.0, 0) # replaces the hold on the same spot
	a.add_entity("platform", Vector2(10, 20), {width = 320.0})
	_check(a.chart.size() == 2 and float(a.chart[0].b) == 2.0 and float(a.chart[0].len) == 0.0, "add_note sorts and replaces")
	var b := LevelData.new()
	b.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	_check(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "LevelData JSON round trip")
	var props := Registry.clean_props("spike", {on_beat = 2.0})
	_check(props.on_beat is int and props.on_beat == 2, "clean_props casts choices to int")
	_check(is_equal_approx(a.sec_to_beat(a.beat_to_sec(7.25)), 7.25), "beat <-> seconds")
	_check(a.notes_between(2.0, 4.0).size() == 1, "notes_between is [from, to)")


func _test_gen() -> void:
	var make := func(s: int, d: float) -> LevelData:
		var l := LevelData.new()
		l.meta.length = 68.0
		ChartGen.generate(l, {seed = s, difficulty = d})
		return l
	var a: LevelData = make.call(7, 0.5)
	var b: LevelData = make.call(7, 0.5)
	var c: LevelData = make.call(8, 0.5)
	_check(a.chart.size() > 20, "generator makes notes (%d)" % a.chart.size())
	_check(JSON.stringify(a.chart) == JSON.stringify(b.chart), "same seed = same chart")
	_check(JSON.stringify(a.chart) != JSON.stringify(c.chart), "other seed = other chart")
	var easy: LevelData = make.call(3, 0.0)
	var hard: LevelData = make.call(3, 1.0)
	_check(hard.chart.size() > easy.chart.size(), "harder = more notes (%d > %d)" % [hard.chart.size(), easy.chart.size()])
	var ok := true
	var prev := -INF
	for n in easy.chart:
		var t := easy.beat_to_sec(float(n.b))
		if t != prev and t - prev < 0.30 - 0.001:
			ok = false
		prev = t
		ok = ok and int(n.lane) >= 0 and int(n.lane) < Registry.lane_count() and float(n.b) >= 4.0
	_check(ok, "easy chart keeps spacing, lanes and count-in")
	var on := LevelData.new()
	on.meta.length = 40.0
	var onsets := []
	for i in 64:
		onsets.append({t = i * 0.25 + 0.03, s = 1.0 if i % 2 == 0 else 0.2})
	ChartGen.generate(on, {seed = 1, difficulty = 0.2, onsets = onsets})
	var aligned := on.chart.all(func(n: Dictionary) -> bool: return is_equal_approx(fposmod(float(n.b) * 2.0, 1.0), 0.0) or is_zero_approx(fposmod(float(n.b) * 2.0, 1.0)))
	_check(on.chart.size() > 5 and aligned, "onset mode filters weak onsets and snaps (%d notes)" % on.chart.size())
	ChartGen.place_runner(a)
	_check(a.entities.size() > a.chart.size(), "place_runner builds a world")


func _test_judge() -> void:
	var l := LevelData.new()
	l.meta.bpm = 120.0 # a beat = 0.5 s
	l.add_note(2.0, 0) # t = 1.0
	l.add_note(3.0, 1) # t = 1.5
	l.add_note(4.0, 0) # t = 2.0
	var j := Judge.new(l)
	j.reset()
	_check(j.press(0, 1.02).judge == "perfect", "judge perfect")
	_check(j.press(1, 1.5 + 0.08).judge == "good", "judge good")
	_check(j.press(0, 0.2).judge == "none", "press far from notes is ignored")
	_check(j.expire(2.0 + 0.2).size() == 1 and j.counts.miss == 1, "unpressed note expires as a miss")
	_check(j.combo == 0 and j.best_combo == 2, "combo and best combo")


func _test_clock() -> void:
	var l := LevelData.new()
	l.meta.bpm = 120.0
	for b in [0.0, 1.0, 1.5, 2.0, 7.75]:
		l.add_note(b, 2)
	var c := SongClock.new(l)
	add_child(c)
	c.hitsounds = false
	var passed := []
	c.note_passed.connect(func(n: Dictionary) -> void: passed.append(n.b))
	c.seek_beat(-0.5)
	c.playing = true
	for i in 300:
		c.advance(1.0 / 60.0) # 5 s = 10 beats
	_check(passed == [0.0, 1.0, 1.5, 2.0, 7.75], "clock fires every note once, in order: %s" % [passed])
	_check(int(c.hits(2).x) == 5 and is_equal_approx(c.hits(2).y, 9.5 - 7.75), "hits() counts notes: %s" % c.hits(2))
	c.queue_free()


func _test_doc_and_builder() -> void:
	var d := LevelDoc.new()
	d.checkpoint()
	d.level.add_note(1.0, 0)
	d.checkpoint()
	d.level.add_note(2.0, 0)
	_check(d.undo() and d.level.chart.size() == 1, "undo")
	_check(d.redo() and d.level.chart.size() == 2, "redo")
	var path := "user://selftest_level.json"
	d.level.add_entity("coin", Vector2(5, 6))
	_check(d.save(path) and d.open(path) and d.level.entities.size() == 1, "save and open")
	DirAccess.remove_absolute(path)
	var parent := Node2D.new()
	add_child(parent)
	var nodes := LevelBuilder.build(d.level, parent)
	_check(nodes.size() == 1 and (nodes[0] as Node2D).position == Vector2(5, 6), "LevelBuilder spawns entities")
	parent.queue_free()


func _test_ui() -> void:
	var before := JSON.stringify(ed.doc.level.to_dict())
	ed.doc.new_level()
	await get_tree().process_frame
	# Chart: click adds, drag makes a hold, right-click removes.
	var ch := ed.chart
	var y := ChartView.RULER_H + ch.lane_h() * 1.5
	_click(ch, Vector2(ch.beat_to_px(2.0), y), MOUSE_BUTTON_LEFT, true)
	_motion(ch, Vector2(ch.beat_to_px(4.0), y))
	_click(ch, Vector2(ch.beat_to_px(4.0), y), MOUSE_BUTTON_LEFT, false)
	var lvl := ed.doc.level
	_check(lvl.chart.size() == 1 and int(lvl.chart[0].lane) == 1 and float(lvl.chart[0].len) == 2.0, "chart click+drag makes a hold note: %s" % [lvl.chart])
	_click(ch, Vector2(ch.beat_to_px(2.0), y), MOUSE_BUTTON_RIGHT, true)
	_check(lvl.chart.is_empty(), "chart right-click deletes")
	_check(ed.doc.undo() and lvl.chart.size() == 1, "chart edit undoes")
	# World: place with a tool, drag, delete.
	var st := ed.stage
	ed.side.set_tool("coin")
	var at := st.to_screen(Vector2(lvl.beat_to_x(3.0), -100))
	_click(st, at, MOUSE_BUTTON_LEFT, true)
	_click(st, at, MOUSE_BUTTON_LEFT, false)
	_check(lvl.entities.size() == 1 and is_equal_approx(float(lvl.entities[0].x), lvl.beat_to_x(3.0)), "world click places a snapped entity")
	ed.side.set_tool("")
	_click(st, at, MOUSE_BUTTON_LEFT, true)
	_motion(st, st.to_screen(Vector2(lvl.beat_to_x(5.0), -100)))
	_click(st, at, MOUSE_BUTTON_LEFT, false)
	_check(is_equal_approx(float(lvl.entities[0].x), lvl.beat_to_x(5.0)), "world drag moves the entity")
	st.delete_selected()
	_check(lvl.entities.is_empty(), "delete selected")
	# Recording: a held lane key becomes a hold note on the grid.
	ed.clock.seek_beat(1.0)
	ed.set_recording(true)
	ed.lane_key(3, true)
	ed.clock.advance(1.0) # two beats at 120
	ed.lane_key(3, false)
	ed.set_recording(false)
	ed.clock.pause()
	var rec := lvl.note_at(1.0, 3)
	_check(not rec.is_empty() and float(rec.len) == 2.0, "recording writes a hold note: %s" % [lvl.chart])
	# Playtest starts and stops.
	ed.start_playtest()
	_check(ed.playtest.active and not ed.chart.visible and ed.stage.visible, "playtest starts")
	ed.playtest.stop()
	_check(not ed.playtest.active and ed.chart.visible, "playtest stops")
	ed.doc.apply(JSON.parse_string(before))


func _click(c: Control, p: Vector2, button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.button_index = button
	e.pressed = pressed
	c._gui_input(e)


func _motion(c: Control, p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	c._gui_input(e)
