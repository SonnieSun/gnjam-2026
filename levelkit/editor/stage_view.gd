class_name StageView
extends Control
## The level's world, drawn with placeholders. World x is tied to time:
## x = beat * meta.px_per_beat, so the beat grid is drawn right on it.
##
##   palette type picked   left-click to place (snaps to the beat grid and
##                         8 px; hold Shift for free placement)
##   left-drag entity      move it        right-click entity  delete it
##   Ctrl/Cmd+D            duplicate      Delete              delete selected
##   wheel                 zoom           middle-drag         pan

signal selection_changed(e: Dictionary)

const Y_SNAP := 8.0

var doc: LevelDoc
var clock: SongClock
## Entity type to place, "" = select / move.
var tool := ""
## Beats per grid cell for placement (shared with the chart).
var snap := 0.25
var cam := Vector2(400, -100)
var zoom := 0.6
var follow := true
var show_hint := true
var selected := {}

var _drag := ""
var _drag_from := Vector2.ZERO
var _grab := Vector2.ZERO


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_NONE


func level() -> LevelData:
	return doc.level


func to_screen(p: Vector2) -> Vector2:
	return (p - cam) * zoom + size / 2.0


func to_world(p: Vector2) -> Vector2:
	return (p - size / 2.0) / zoom + cam


func snap_point(w: Vector2, free: bool) -> Vector2:
	if free:
		return w
	var step := level().beat_to_x(snap)
	return Vector2(snappedf(w.x, step), snappedf(w.y, Y_SNAP))


func entity_rect(e: Dictionary) -> Rect2:
	var s := Registry.size_of(e)
	return Rect2(LevelData.entity_pos(e) - s / 2.0, s)


func entity_under(screen: Vector2) -> Dictionary:
	var w := to_world(screen)
	for i in range(level().entities.size() - 1, -1, -1):
		var e: Dictionary = level().entities[i]
		if entity_rect(e).grow(4.0 / zoom).has_point(w):
			return e
	return {}


func select(e: Dictionary) -> void:
	selected = e
	selection_changed.emit(e)


func delete_selected() -> void:
	if selected.is_empty():
		return
	doc.checkpoint()
	_erase(selected)
	select({})
	Sfx.play("poof")


func duplicate_selected() -> void:
	if selected.is_empty():
		return
	doc.checkpoint()
	var e: Dictionary = selected.duplicate(true)
	e.x = float(e.x) + level().beat_to_x(1.0)
	level().entities.append(e)
	select(e)
	Sfx.play("pop")


## Drops a stale selection after undo/redo/load replaced the level.
func revalidate() -> void:
	if not selected.is_empty() and not level().entities.any(func(e: Dictionary) -> bool: return is_same(e, selected)):
		select({})


func _erase(e: Dictionary) -> void:
	for i in level().entities.size():
		if is_same(level().entities[i], e):
			level().entities.remove_at(i)
			return


func _process(_delta: float) -> void:
	if follow and clock.playing and _drag == "":
		var px := level().beat_to_x(clock.beat)
		var left := to_world(Vector2.ZERO).x
		var right := to_world(size).x
		if px > left + (right - left) * 0.7 or px < left:
			cam.x = px + (right - left) * 0.25
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var p := mb.position
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var at := to_world(p)
					zoom = clampf(zoom * (1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12), 0.05, 4.0)
					cam += at - to_world(p)
			MOUSE_BUTTON_MIDDLE:
				_drag = "pan" if mb.pressed else ""
				_drag_from = p
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					var e := entity_under(p)
					if not e.is_empty():
						doc.checkpoint()
						_erase(e)
						if is_same(e, selected):
							select({})
						Sfx.play("poof")
			MOUSE_BUTTON_LEFT:
				if not mb.pressed:
					if _drag == "move":
						selection_changed.emit(selected) # refresh the inspector's X/Y
					_drag = ""
					return
				var e := entity_under(p)
				if tool != "" and (e.is_empty() or mb.shift_pressed):
					doc.checkpoint()
					select(level().add_entity(tool, snap_point(to_world(p), mb.shift_pressed)))
					Sfx.play("pop")
				elif not e.is_empty():
					doc.checkpoint()
					select(e)
					_grab = LevelData.entity_pos(e) - to_world(p)
					_drag = "move"
					Sfx.play("grab")
				else:
					select({})
					_drag = "pan"
					_drag_from = p
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		match _drag:
			"pan":
				cam -= (mm.position - _drag_from) / zoom
				_drag_from = mm.position
			"move":
				var w := snap_point(to_world(mm.position) + _grab, mm.shift_pressed)
				selected.x = w.x
				selected.y = w.y


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.12, 0.18))
	var lvl := level()
	# Beat grid in the world.
	var left := to_world(Vector2.ZERO)
	var right := to_world(size)
	var b := floorf(lvl.x_to_beat(left.x))
	var step := 1.0 if lvl.beat_to_x(1.0) * zoom > 10.0 else 4.0
	b = floorf(b / step) * step
	while lvl.beat_to_x(b) < right.x:
		var x := to_screen(Vector2(lvl.beat_to_x(b), 0)).x
		var on_bar := is_zero_approx(fposmod(b, 4.0))
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.12 if on_bar else 0.04), 1.0)
		if on_bar:
			draw_string(font, Vector2(x + 4, 16), str(int(b / 4.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.4))
		b += step
	var ground := to_screen(Vector2.ZERO)
	draw_line(Vector2(0, ground.y), Vector2(size.x, ground.y), Color(1, 1, 1, 0.2), 1.0)
	# Song end.
	var end_x := to_screen(Vector2(lvl.beat_to_x(clock.length_beats()), 0)).x
	if end_x < size.x:
		draw_rect(Rect2(end_x, 0, size.x - end_x, size.y), Color(0, 0, 0, 0.35))
	# Entities.
	for e in lvl.entities:
		var def := Registry.get_def(e.type)
		var r := entity_rect(e)
		var sr := Rect2(to_screen(r.position), r.size * zoom)
		if not sr.intersects(Rect2(Vector2.ZERO, size)):
			continue
		var c: Color = def.color
		var center := sr.get_center()
		draw_set_transform(center, deg_to_rad(float(e.rot)))
		draw_rect(Rect2(-sr.size / 2.0, sr.size), Color(c, 0.85))
		if is_same(e, selected):
			draw_rect(Rect2(-sr.size / 2.0, sr.size).grow(3), Color.WHITE, false, 2.0)
		draw_set_transform(Vector2.ZERO)
		if sr.size.x > 30:
			draw_string(font, center + Vector2(-sr.size.x / 2.0, 5), def.label, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 12, Color(0, 0, 0, 0.8))
	# Playhead.
	var ph := to_screen(Vector2(lvl.beat_to_x(clock.beat), 0)).x
	draw_line(Vector2(ph, 0), Vector2(ph, size.y), Color("ff3b3b"), 2.0)
	# Placement ghost.
	if tool != "" and get_global_rect().has_point(get_global_mouse_position()):
		var w := snap_point(to_world(get_local_mouse_position()), Input.is_key_pressed(KEY_SHIFT))
		var ghost := {type = tool, x = w.x, y = w.y, props = Registry.default_props(tool)}
		var r := entity_rect(ghost)
		draw_rect(Rect2(to_screen(r.position), r.size * zoom), Color(Registry.get_def(tool).color, 0.35))
	if not show_hint:
		return
	var hint := "placing %s  (Esc: stop placing)" % Registry.get_def(tool).label if tool != "" else "select / move"
	draw_string(font, Vector2(10, size.y - 10), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5))
