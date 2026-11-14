class_name LevelEditor
extends Control
## The level tool: toolbar on top, palette + inspector on the left, the
## world in the middle, the chart at the bottom. Tab = playtest.
##
##   Space play/pause      Home back to start      Tab playtest from playhead
##   D F J K  (lanes)      audition; with Rec on, written into the chart
##   R rec   M metronome   H hit sounds
##   Ctrl/Cmd+S save   Z undo   Shift+Z / Y redo   D duplicate
##   Delete  delete selected entity     Esc  back to the select tool

const SNAPS := {"1/1": 1.0, "1/2": 0.5, "1/3": 1.0 / 3.0, "1/4": 0.25, "1/6": 1.0 / 6.0, "1/8": 0.125}

var doc := LevelDoc.new()
var clock: SongClock
var chart := ChartView.new()
var stage := StageView.new()
var side := SidePanel.new()
var playtest := Playtest.new()
## Onsets from the song's .analysis.json (tools/analyze_song.py), if any.
var onsets: Array = []
var recording := false

var _name := LineEdit.new()
var _bpm := SpinBox.new()
var _offset := SpinBox.new()
var _length := SpinBox.new()
var _song_label := Label.new()
var _play := Button.new()
var _rec := Button.new()
var _metro := Button.new()
var _hits := Button.new()
var _snap := OptionButton.new()
var _open := MenuButton.new()
var _seed := SpinBox.new()
var _diff := HSlider.new()
var _use_onsets := CheckBox.new()
var _status := Label.new()
var _song_dialog := FileDialog.new()
var _ui := VBoxContainer.new()
var _bar := PanelContainer.new()
var _cam_before := Vector2.ZERO
var _held := {} # lane -> { note, from } while recording a key held down
var _status_age := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme_ := UiKit.make_theme()
	theme_.default_font_size = 15
	theme = theme_
	clock = SongClock.new(doc.level)
	add_child(clock)
	chart.doc = doc
	chart.clock = clock
	stage.doc = doc
	stage.clock = clock
	_build()
	playtest.setup(doc, clock)
	add_child(playtest)
	playtest.finished.connect(func() -> void: _set_editor_ui(true))
	chart.seek_requested.connect(func(b: float) -> void: clock.seek_beat(b))
	doc.applied.connect(_on_applied)
	# Clicking the world or chart takes keyboard focus away from text fields,
	# so Space and the lane keys reach the shortcuts again.
	for view: Control in [chart, stage]:
		view.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed:
				get_viewport().gui_release_focus())
	get_window().files_dropped.connect(func(files: PackedStringArray) -> void:
		for f in files:
			if f.get_extension().to_lower() in ["ogg", "mp3", "wav"]:
				import_song(f)
				return)
	var levels := LevelDoc.list()
	if not levels.is_empty():
		doc.open(levels[0].path)
	_on_applied()
	if not OS.get_cmdline_user_args().is_empty():
		add_child(LevelKitDev.new(self))


# --- layout ----------------------------------------------------------------

func _build() -> void:
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_theme_constant_override("separation", 0)
	add_child(_ui)

	var bar := _bar
	_ui.add_child(bar)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 6)
	m.add_child(flow)
	bar.add_child(m)

	# File.
	_name.custom_minimum_size.x = 150
	_name.placeholder_text = "level name"
	_name.text_submitted.connect(func(_t: String) -> void: _name.release_focus())
	_name.text_changed.connect(func(t: String) -> void: doc.level.meta.name = t)
	flow.add_child(_name)
	_small(flow, "New", func() -> void: doc.new_level(), "Empty level (undo brings the old one back)")
	_small(flow, "Save", save, "Ctrl/Cmd+S: saves to levels/<name>.json")
	_open.text = "Open ▾"
	_open.flat = false
	_open.about_to_popup.connect(_fill_open_menu)
	_open.get_popup().index_pressed.connect(func(i: int) -> void:
		doc.open(_open.get_popup().get_item_metadata(i)))
	flow.add_child(_open)
	_small(flow, "Undo", func() -> void: doc.undo())
	_small(flow, "Redo", func() -> void: doc.redo())
	flow.add_child(VSeparator.new())

	# Song and tempo.
	_small(flow, "Song…", func() -> void: _song_dialog.popup_centered_ratio(0.7), "Pick an .ogg/.mp3/.wav (or drop one on the window)")
	_song_label.custom_minimum_size.x = 110
	_song_label.clip_text = true
	flow.add_child(_song_label)
	_spin(flow, _bpm, "BPM", 40.0, 300.0, 0.01, func(v: float) -> void: doc.level.meta.bpm = v)
	_spin(flow, _offset, "Offset ms", -5000.0, 5000.0, 1.0, func(v: float) -> void: doc.level.meta.offset = v / 1000.0)
	_offset.tooltip_text = "Song time of beat 0. Tap play with the metronome on and nudge until the clicks sit on the song."
	_spin(flow, _length, "Beats", 4.0, 4000.0, 4.0, func(v: float) -> void: doc.level.meta.length = v)
	flow.add_child(VSeparator.new())

	# Transport.
	_toggle(flow, _play, "▶ Play", func(_on: bool) -> void: clock.toggle(), "Space")
	_toggle(flow, _rec, "● Rec", func(on: bool) -> void: set_recording(on), "R: lane keys write notes while playing")
	_toggle(flow, _metro, "Metro", func(on: bool) -> void: clock.metronome = on, "M")
	_toggle(flow, _hits, "Hits", func(on: bool) -> void: clock.hitsounds = on, "H: play lane sounds on notes")
	_hits.button_pressed = true
	for k: String in SNAPS:
		_snap.add_item(k)
	_snap.selected = 3
	_snap.tooltip_text = "Grid / snap"
	_snap.item_selected.connect(func(i: int) -> void: set_snap(SNAPS.values()[i]))
	flow.add_child(_snap)
	flow.add_child(VSeparator.new())

	# Generator.
	_spin(flow, _seed, "Seed", 0.0, 99999.0, 1.0, func(_v: float) -> void: pass)
	_seed.value = 1
	var dl := Label.new()
	dl.text = "Diff"
	flow.add_child(dl)
	_diff.min_value = 0.0
	_diff.max_value = 1.0
	_diff.step = 0.05
	_diff.value = 0.5
	_diff.custom_minimum_size = Vector2(80, 24)
	_diff.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.add_child(_diff)
	_use_onsets.text = "from song"
	_use_onsets.tooltip_text = "Use the song's onsets (needs songs/<song>.analysis.json from tools/analyze_song.py)"
	flow.add_child(_use_onsets)
	_small(flow, "Gen chart", generate_chart, "Replace the chart with a generated one")
	_small(flow, "Gen world", generate_world, "Replace the entities with ChartGen.place_runner (an example)")
	var playtest_button := Button.new()
	playtest_button.text = "PLAYTEST (Tab)"
	playtest_button.theme_type_variation = "Hot"
	playtest_button.pressed.connect(start_playtest)
	flow.add_child(playtest_button)
	_status.modulate = Color(1, 1, 1, 0.7)
	flow.add_child(_status)

	# Body.
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui.add_child(split)
	var top := HSplitContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(top)
	side.setup(doc, stage)
	top.add_child(side)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(stage)
	chart.custom_minimum_size.y = 230
	split.add_child(chart)
	UiKit.no_focus(bar)

	_song_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_song_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_song_dialog.filters = PackedStringArray(["*.ogg, *.mp3, *.wav ; Audio"])
	_song_dialog.use_native_dialog = true
	_song_dialog.file_selected.connect(import_song)
	add_child(_song_dialog)


func _small(parent: Control, text: String, on_press: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _toggle(parent: Control, b: Button, text: String, on_toggle: Callable, tip := "") -> void:
	b.text = text
	b.toggle_mode = true
	b.tooltip_text = tip
	b.toggled.connect(on_toggle)
	parent.add_child(b)


func _spin(parent: Control, sb: SpinBox, label: String, lo: float, hi: float, step: float, on_change: Callable) -> void:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.custom_minimum_size.x = 90
	sb.value_changed.connect(func(v: float) -> void:
		doc.checkpoint()
		on_change.call(v))
	sb.get_line_edit().text_submitted.connect(func(_t: String) -> void: sb.get_line_edit().release_focus())
	parent.add_child(sb)


func _fill_open_menu() -> void:
	var p := _open.get_popup()
	p.clear()
	for f in LevelDoc.list():
		p.add_item(f.name)
		p.set_item_metadata(p.item_count - 1, f.path)
	if p.item_count == 0:
		p.add_item("(no levels yet)")
		p.set_item_disabled(0, true)


# --- state -----------------------------------------------------------------

## The level object was replaced wholesale: pull everything from it.
func _on_applied() -> void:
	var m := doc.level.meta
	_name.text = str(m.name)
	_bpm.set_value_no_signal(float(m.bpm))
	_offset.set_value_no_signal(float(m.offset) * 1000.0)
	_length.set_value_no_signal(float(m.length))
	_load_song()
	stage.revalidate()
	side.rebuild_inspector()


func _process(delta: float) -> void:
	_play.set_pressed_no_signal(clock.playing)
	_status_age += delta
	if _status_age > 3.0:
		_status.text = "beat %.2f   %d notes  %d entities%s" % [clock.beat, doc.level.chart.size(), doc.level.entities.size(), ("   " + doc.path.get_file()) if doc.path else ""]


func say(text: String) -> void:
	_status.text = text
	_status_age = 0.0


func set_snap(beats: float) -> void:
	chart.snap = beats
	stage.snap = beats


func set_recording(on: bool) -> void:
	recording = on
	_rec.set_pressed_no_signal(on)
	if on:
		doc.checkpoint() # one undo step per take
		if not clock.playing:
			clock.play()
	_held.clear()


func save() -> void:
	if doc.save():
		say("saved " + doc.path)
		Sfx.play("good")
	else:
		say("SAVE FAILED: " + doc.path)


# --- song ------------------------------------------------------------------

## Uses an audio file as the level's song. From the Godot editor the file is
## copied into res://songs so it ships with the game (with its analysis).
func import_song(src: String) -> void:
	var dst := src
	if OS.has_feature("editor") and not src.begins_with("res://"):
		dst = "res://songs".path_join(src.get_file())
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://songs"))
		DirAccess.copy_absolute(src, ProjectSettings.globalize_path(dst))
		var analysis := src.get_basename() + ".analysis.json"
		if FileAccess.file_exists(analysis):
			DirAccess.copy_absolute(analysis, ProjectSettings.globalize_path(dst.get_basename() + ".analysis.json"))
	doc.checkpoint()
	doc.level.meta.song = dst
	var a := _load_song()
	if not a.is_empty():
		doc.level.meta.bpm = float(a.get("bpm", doc.level.meta.bpm))
		doc.level.meta.offset = float(a.get("offset", doc.level.meta.offset))
		say("song + analysis: %.2f bpm, offset %d ms, %d onsets" % [doc.level.meta.bpm, roundi(doc.level.meta.offset * 1000.0), onsets.size()])
	else:
		say("song loaded (no .analysis.json: set BPM/offset by hand)")
	if clock.player.stream:
		doc.level.meta.length = ceilf(clock.length_beats() / 4.0) * 4.0
	_on_applied()


## Loads meta.song into the clock, and its analysis if there is one.
func _load_song() -> Dictionary:
	var path := str(doc.level.meta.song)
	var ok := clock.load_song()
	_song_label.text = path.get_file() if ok else ("(missing) " + path.get_file() if path else "(no song)")
	onsets = []
	var a := path.get_basename() + ".analysis.json"
	if path.is_empty() or not FileAccess.file_exists(a):
		_use_onsets.disabled = true
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(a))
	if not d is Dictionary:
		return {}
	onsets = d.get("onsets", [])
	_use_onsets.disabled = onsets.is_empty()
	return d


# --- generation ------------------------------------------------------------

func generate_chart() -> void:
	doc.checkpoint()
	var opts := {seed = int(_seed.value), difficulty = _diff.value}
	if _use_onsets.button_pressed and not onsets.is_empty():
		opts.onsets = onsets
	ChartGen.generate(doc.level, opts)
	_length.set_value_no_signal(float(doc.level.meta.length))
	say("generated %d notes (seed %d, diff %.2f%s)" % [doc.level.chart.size(), opts.seed, opts.difficulty, ", from song" if opts.has("onsets") else ""])
	Sfx.play("whoosh")


func generate_world() -> void:
	doc.checkpoint()
	ChartGen.place_runner(doc.level)
	stage.select({})
	say("placed %d entities" % doc.level.entities.size())
	Sfx.play("whoosh")


# --- playtest --------------------------------------------------------------

func start_playtest() -> void:
	set_recording(false)
	_set_editor_ui(false)
	playtest.start(maxf(clock.beat, 0.0) if clock.beat > 0.5 else 0.0)


## Playtest keeps the world on screen (following the playhead) and hides
## the rest of the editor.
func _set_editor_ui(on: bool) -> void:
	for c: Control in [_bar, side, chart]:
		c.visible = on
	stage.follow = true
	stage.show_hint = on
	if not on:
		stage.select({})
		_cam_before = stage.cam
		stage.cam.y = 260.0 / stage.zoom * 0.6 # ground above the highway
	else:
		stage.cam = _cam_before


# --- keys ------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if playtest.active:
		return
	var k := event as InputEventKey
	for i in Registry.lane_count():
		if k.keycode == Registry.LANES[i].key and not (k.ctrl_pressed or k.meta_pressed):
			if not k.echo:
				lane_key(i, k.pressed)
			accept_event()
			return
	if not k.pressed or k.echo:
		return
	var cmd := k.ctrl_pressed or k.meta_pressed
	match k.keycode:
		KEY_SPACE:
			clock.toggle()
		KEY_HOME:
			clock.seek_beat(0.0)
			chart.view_beat = -1.0
		KEY_TAB:
			start_playtest()
		KEY_R:
			set_recording(not recording)
		KEY_M:
			_metro.button_pressed = not _metro.button_pressed
		KEY_H:
			_hits.button_pressed = not _hits.button_pressed
		KEY_ESCAPE:
			side.set_tool("")
		KEY_DELETE, KEY_BACKSPACE:
			stage.delete_selected()
		KEY_S:
			if cmd:
				save()
		KEY_Z:
			if cmd:
				var ok := doc.redo() if k.shift_pressed else doc.undo()
				if ok:
					Sfx.play("tick")
		KEY_Y:
			if cmd and doc.redo():
				Sfx.play("tick")
		KEY_D:
			if cmd:
				stage.duplicate_selected()
		_:
			return
	accept_event()


## A lane key went down or up: sound, a hit on the clock, and while
## recording a note (held past half a beat = a hold note).
func lane_key(lane: int, down: bool) -> void:
	if down:
		clock.tap(lane)
		Sfx.play(Registry.LANES[lane].sound)
		if recording and clock.playing:
			var b := snappedf(clock.beat, chart.snap)
			_held[lane] = {note = doc.level.add_note(b, lane), from = b}
	elif _held.has(lane):
		var h: Dictionary = _held[lane]
		_held.erase(lane)
		var length := snappedf(clock.beat - float(h.from), chart.snap)
		if length >= 0.5:
			h.note.len = length
