class_name Playtest
extends Control
## Tab in the editor: play the chart with the lane keys, judged. A generic
## four-lane highway so a chart can be tested before the real game exists;
## the jam game replaces this with its own player, using the same SongClock
## and Judge.

signal finished

const HIT_X := 180.0
const LANE_H := 56.0
## Beats visible ahead of the hit line.
const LOOKAHEAD := 4.0

var doc: LevelDoc
var clock: SongClock
var judge: Judge
var active := false

var _flash: Array[float] = []
var _text := ""
var _text_color := Color.WHITE
var _text_age := 9.0
var _last_ms := 0.0
var _end_beat := 0.0
var _done := false
var _hitsounds_before := true


func setup(d: LevelDoc, c: SongClock) -> void:
	doc = d
	clock = c
	judge = Judge.new(d.level)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for i in Registry.lane_count():
		_flash.append(0.0)


## Starts from `from_beat` with one bar of count-in.
func start(from_beat: float) -> void:
	judge.level = doc.level
	active = true
	visible = true
	_done = false
	_text_age = 9.0
	var last: float = doc.level.chart[-1].b if not doc.level.chart.is_empty() else from_beat
	_end_beat = last + 4.0
	judge.reset(from_beat)
	_hitsounds_before = clock.hitsounds
	clock.hitsounds = false
	clock.seek_beat(from_beat - 4.0)
	clock.play()


func stop() -> void:
	active = false
	visible = false
	clock.pause()
	clock.hitsounds = _hitsounds_before
	finished.emit()


func _process(delta: float) -> void:
	if not active:
		return
	if not judge.expire(clock.time).is_empty():
		_say("MISS", Color(1, 1, 1, 0.5))
	for i in _flash.size():
		_flash[i] = maxf(0.0, _flash[i] - delta * 6.0)
	_text_age += delta
	if not _done and clock.beat > _end_beat:
		_done = true
		_say("RESULT  %d%%" % roundi(judge.accuracy() * 100.0), UiKit.ACCENT)
		clock.pause()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not active or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE or key == KEY_TAB:
		get_viewport().set_input_as_handled()
		stop()
		return
	for i in Registry.lane_count():
		if key == Registry.LANES[i].key:
			get_viewport().set_input_as_handled()
			press(i)
			return


func press(lane: int) -> void:
	_flash[lane] = 1.0
	clock.tap(lane)
	Sfx.play(Registry.LANES[lane].sound)
	var r := judge.press(lane, clock.time)
	_last_ms = r.ms
	match r.judge:
		"perfect":
			_say("PERFECT", Registry.LANES[lane].color)
		"good":
			_say("GOOD  %s" % ("early" if r.ms < 0 else "late"), Color.WHITE)
		"miss":
			_say("MISS", Color(1, 1, 1, 0.5))


func _say(text: String, color: Color) -> void:
	_text = text
	_text_color = color
	_text_age = 0.0


func _draw() -> void:
	var font := get_theme_default_font()
	var lanes := Registry.lane_count()
	var top := size.y - lanes * LANE_H - 40.0
	var ppb := (size.x - HIT_X) / LOOKAHEAD
	draw_rect(Rect2(0, top - 10, size.x, lanes * LANE_H + 50), Color(0, 0, 0, 0.75))
	for i in lanes:
		var lane: Dictionary = Registry.LANES[i]
		var y := top + i * LANE_H
		draw_rect(Rect2(0, y, size.x, LANE_H - 4), Color(lane.color, 0.08 + _flash[i] * 0.3))
		draw_string(font, Vector2(16, y + LANE_H / 2.0 + 6), OS.get_keycode_string(lane.key), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, lane.color)
	# Beat lines.
	var b := ceilf(clock.beat)
	while b < clock.beat + LOOKAHEAD:
		var x := HIT_X + (b - clock.beat) * ppb
		draw_line(Vector2(x, top), Vector2(x, top + lanes * LANE_H), Color(1, 1, 1, 0.25 if posmod(int(b), 4) == 0 else 0.08))
		b += 1.0
	# Notes.
	for n in doc.level.notes_between(clock.beat - 1.0, clock.beat + LOOKAHEAD):
		var x := HIT_X + (float(n.b) - clock.beat) * ppb
		var y := top + int(n.lane) * LANE_H
		var c: Color = Registry.LANES[int(n.lane)].color
		if float(n.len) > 0.0:
			draw_rect(Rect2(x, y + LANE_H * 0.35, float(n.len) * ppb, LANE_H * 0.25), Color(c, 0.5))
		draw_rect(Rect2(x - 8, y + 6, 16, LANE_H - 16), c)
	draw_line(Vector2(HIT_X, top - 6), Vector2(HIT_X, top + lanes * LANE_H + 2), Color.WHITE, 3.0)
	# Score line.
	var c := judge.counts
	var stats := "combo %d   best %d   perfect %d  good %d  miss %d   acc %d%%   last %+d ms   Esc: back" % [
		judge.combo, judge.best_combo, c.perfect, c.good, c.miss, roundi(judge.accuracy() * 100.0), roundi(_last_ms)]
	draw_string(font, Vector2(16, size.y - 14), stats, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	# Judgement.
	if _text_age < (3.0 if _done else 0.6):
		var k := 0.0 if _done else _text_age / 0.6
		var fs := 48
		var at := Vector2(0, top - 40 - k * 20.0)
		draw_string_outline(font, at, _text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 10, Color(0, 0, 0, 1.0 - k))
		draw_string(font, at, _text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(_text_color, _text_color.a * (1.0 - k * k)))
