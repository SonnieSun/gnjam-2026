class_name ChartView
extends Control
## The chart, time running left to right, one row per lane.
##
##   left-click empty   add a note (drag right = hold note)
##   left-drag note     move it (time and lane)
##   right-click note   delete it
##   click the ruler    move the playhead there
##   wheel              scroll time      Ctrl/Cmd+wheel  zoom
##   middle-drag        scroll time

signal seek_requested(beat: float)

const RULER_H := 24.0
const GUTTER := 64.0

var doc: LevelDoc
var clock: SongClock
## Beats per grid cell (0.25 = sixteenths).
var snap := 0.25
var view_beat := -1.0
var px_per_beat := 64.0
## Keep the playhead on screen while playing.
var follow := true

var _drag := "" # "", "new", "move", "pan"
var _drag_note := {}
var _drag_from := Vector2.ZERO
var _drag_grab := 0.0 # beat offset inside the grabbed note


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP


func level() -> LevelData:
	return doc.level


func lane_h() -> float:
	return (size.y - RULER_H) / Registry.lane_count()


func beat_to_px(b: float) -> float:
	return GUTTER + (b - view_beat) * px_per_beat


func px_to_beat(x: float) -> float:
	return view_beat + (x - GUTTER) / px_per_beat


func snap_beat(b: float) -> float:
	return snappedf(b, snap)


func lane_at(y: float) -> int:
	return clampi(floori((y - RULER_H) / lane_h()), 0, Registry.lane_count() - 1)


func note_rect(n: Dictionary) -> Rect2:
	var x := beat_to_px(float(n.b))
	var w := maxf(float(n.len) * px_per_beat, 0.0) + 14.0
	var y := RULER_H + int(n.lane) * lane_h()
	return Rect2(x - 7.0, y + 6.0, w, lane_h() - 12.0)


func note_under(p: Vector2) -> Dictionary:
	for i in range(level().chart.size() - 1, -1, -1):
		var n: Dictionary = level().chart[i]
		if note_rect(n).has_point(p):
			return n
	return {}


func _process(_delta: float) -> void:
	if follow and clock.playing and _drag == "":
		var span := (size.x - GUTTER) / px_per_beat
		if clock.beat > view_beat + span * 0.75 or clock.beat < view_beat:
			view_beat = clock.beat - span * 0.25
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion:
		_mouse_motion(event)


func _mouse_button(mb: InputEventMouseButton) -> void:
	var p := mb.position
	if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var dir := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		if mb.ctrl_pressed or mb.meta_pressed:
			var at := px_to_beat(p.x)
			px_per_beat = clampf(px_per_beat * (1.15 if dir > 0 else 1.0 / 1.15), 8.0, 600.0)
			view_beat = at - (p.x - GUTTER) / px_per_beat
		else:
			view_beat -= dir * 120.0 / px_per_beat
		accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		_drag = "pan" if mb.pressed else ""
		_drag_from = p
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var n := note_under(p)
		if not n.is_empty():
			doc.checkpoint()
			level().chart.erase(n)
			Sfx.play("drop")
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not mb.pressed:
		if _drag == "new" or _drag == "move":
			level().sort_chart()
		_drag = ""
		_drag_note = {}
		return
	if p.y < RULER_H:
		seek_requested.emit(maxf(snap_beat(px_to_beat(p.x)), -8.0))
		return
	var hit := note_under(p)
	doc.checkpoint()
	if hit.is_empty():
		var lane := lane_at(p.y)
		_drag_note = level().add_note(snap_beat(px_to_beat(p.x)), lane)
		_drag = "new"
		Sfx.play(Registry.LANES[lane].sound)
	else:
		_drag_note = hit
		_drag_grab = px_to_beat(p.x) - float(hit.b)
		_drag = "move"
		Sfx.play("grab")


func _mouse_motion(mm: InputEventMouseMotion) -> void:
	var p := mm.position
	match _drag:
		"pan":
			view_beat -= (p.x - _drag_from.x) / px_per_beat
			_drag_from = p
		"new":
			_drag_note.len = maxf(0.0, snap_beat(px_to_beat(p.x)) - float(_drag_note.b))
		"move":
			_drag_note.b = snap_beat(px_to_beat(p.x) - _drag_grab)
			_drag_note.lane = lane_at(p.y)
	if _drag == "":
		var n := note_under(p)
		tooltip_text = "" if n.is_empty() else "beat %.2f  lane %s%s" % [float(n.b), Registry.LANES[int(n.lane)].name, ("  hold %.2f" % float(n.len)) if float(n.len) > 0.0 else ""]


func _draw() -> void:
	var font := get_theme_default_font()
	var lanes := Registry.lane_count()
	var lh := lane_h()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.06, 0.1))
	# Lane rows.
	for i in lanes:
		var lane: Dictionary = Registry.LANES[i]
		var y := RULER_H + i * lh
		draw_rect(Rect2(GUTTER, y, size.x - GUTTER, lh), Color(lane.color, 0.05 if i % 2 == 0 else 0.09))
		draw_rect(Rect2(0, y, GUTTER, lh), Color(lane.color, 0.25))
		draw_string(font, Vector2(6, y + lh / 2.0 + 5), lane.name, HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 8, 13, Color.WHITE)
	# Song extent.
	var end_x := beat_to_px(clock.length_beats())
	if end_x < size.x:
		draw_rect(Rect2(end_x, RULER_H, size.x - end_x, size.y), Color(0, 0, 0, 0.45))
	# Grid: snap lines faint, beats stronger, bars strongest with numbers.
	var first := floorf(px_to_beat(GUTTER) / snap) * snap
	var b := first
	while beat_to_px(b) < size.x:
		var x := beat_to_px(b)
		if x >= GUTTER:
			var on_bar := is_zero_approx(fposmod(b, 4.0))
			var on_beat := is_zero_approx(fposmod(b, 1.0))
			var a := 0.45 if on_bar else (0.18 if on_beat else 0.06)
			if px_per_beat * snap >= 6.0 or on_beat:
				draw_line(Vector2(x, RULER_H), Vector2(x, size.y), Color(1, 1, 1, a), 2.0 if on_bar else 1.0)
			if on_bar:
				draw_string(font, Vector2(x + 4, 17), str(int(b / 4.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
		b += snap
	draw_rect(Rect2(0, 0, size.x, RULER_H), Color(1, 1, 1, 0.06))
	# Notes.
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(6)
	for n in level().chart:
		var r := note_rect(n)
		if r.end.x < GUTTER or r.position.x > size.x:
			continue
		var c: Color = Registry.LANES[int(n.lane)].color
		if float(n.len) > 0.0:
			draw_rect(Rect2(r.position.x + 7, r.position.y + r.size.y * 0.3, r.size.x - 7, r.size.y * 0.4), Color(c, 0.5))
		box.bg_color = c.lightened(0.3) if is_same(n, _drag_note) else c
		draw_style_box(box, Rect2(r.position, Vector2(14, r.size.y)))
	# Playhead.
	var px := beat_to_px(clock.beat)
	if px >= GUTTER and px <= size.x:
		draw_line(Vector2(px, 0), Vector2(px, size.y), Color("ff3b3b"), 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(px - 7, 0), Vector2(px + 7, 0), Vector2(px, 10)]), Color("ff3b3b"))
	draw_line(Vector2(GUTTER, 0), Vector2(GUTTER, size.y), Color(1, 1, 1, 0.3))
