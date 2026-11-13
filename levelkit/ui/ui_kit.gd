class_name UiKit
## The look of the interface and the builders every panel shares, so a
## slider row or a header is made in exactly one place.

const LABEL_W := 128.0
const INK := Color(0.11, 0.08, 0.16)
const ACCENT := Color("ffd23f")
const HOT := Color("ff5d8f")


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	t.set_stylebox("panel", "PanelContainer", _box(Color(INK, 0.94), 0, 0))
	# "Card": a component's box inside a panel.
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _box(Color(1, 1, 1, 0.06), 10, 8))
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, _box(Color(1, 1, 1, 0.09), 8, 6))
		t.set_stylebox("hover", type, _box(Color(1, 1, 1, 0.2), 8, 6))
		t.set_stylebox("pressed", type, _box(Color(ACCENT, 0.85), 8, 6))
		t.set_stylebox("disabled", type, _box(Color(1, 1, 1, 0.03), 8, 6))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_pressed_color", type, INK)
	# A checkbox is a Button underneath; it should not light up like one.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_pressed_color", "CheckBox", Color.WHITE)
	# "Big": the chunky buttons of the track bar.
	t.set_type_variation("Big", "Button")
	t.set_font_size("font_size", "Big", 21)
	# "Hot": the one button on screen you are meant to press.
	t.set_type_variation("Hot", "Button")
	t.set_font_size("font_size", "Hot", 21)
	t.set_stylebox("normal", "Hot", _box(HOT, 8, 6))
	t.set_stylebox("hover", "Hot", _box(HOT.lightened(0.2), 8, 6))
	t.set_stylebox("pressed", "Hot", _box(ACCENT, 8, 6))
	t.set_stylebox("normal", "LineEdit", _box(Color(0, 0, 0, 0.35), 8, 6))
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0.55), 8, 6))
	t.set_stylebox("panel", "ItemList", _box(Color(0, 0, 0, 0.25), 8, 4))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0, 0, 0, 0.9), 6, 6))
	return t


static func _box(color: Color, radius: int, pad: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(pad)
	return b


## A VBox with the standard padding, as the only child of a panel.
static func padded(panel: Control, margin := 12, separation := 8) -> VBoxContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, margin)
	panel.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	m.add_child(box)
	return box


static func header(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_color_override("font_color", ACCENT)
	parent.add_child(l)
	return l


static func hint(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(1, 1, 1, 0.6)
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)
	return l


static func button(parent: Control, text: String, on_press: Callable, tooltip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


static func row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	parent.add_child(r)
	return r


static func _labelled_row(parent: Control, label: String) -> HBoxContainer:
	var r := row(parent)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = LABEL_W
	l.clip_text = true
	r.add_child(l)
	return r


static func option(parent: Control, label: String, options: Array, value: int, on_change: Callable) -> OptionButton:
	var ob := OptionButton.new()
	for o in options:
		ob.add_item(str(o))
	ob.selected = value
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.item_selected.connect(on_change)
	(_labelled_row(parent, label) if label != "" else parent).add_child(ob)
	return ob


static func check(parent: Control, label: String, value: bool, on_change: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = value
	cb.toggled.connect(on_change)
	parent.add_child(cb)
	return cb


## A labelled slider with a live readout. `on_begin` runs when a drag starts
## (the place to take an undo checkpoint). Right-click resets to `default`.
static func slider(parent: Control, label: String, lo: float, hi: float, step: float, value: float, on_change: Callable, on_begin := Callable(), default: Variant = null) -> HSlider:
	var r := _labelled_row(parent, label)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(sl)
	var val := Label.new()
	val.custom_minimum_size.x = 54
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.text = _fmt(value, step)
	r.add_child(val)
	sl.value_changed.connect(func(v: float) -> void:
		val.text = _fmt(v, step)
		on_change.call(v))
	if on_begin.is_valid():
		sl.drag_started.connect(on_begin)
	if default != null:
		sl.tooltip_text = "Right-click to reset"
		sl.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
				if on_begin.is_valid():
					on_begin.call()
				sl.value = default)
	return sl


## Controls for a list of params (see CatModifiers.param / choice) editing
## `values` in place: dropdowns, checkboxes and sliders as each one needs.
static func params(parent: Control, specs: Array[Dictionary], values: Dictionary, on_begin := Callable()) -> void:
	for p in specs:
		var key: String = p.key
		if p.has("options"):
			option(parent, p.label, p.options, values[key], func(i: int) -> void:
				if on_begin.is_valid():
					on_begin.call()
				values[key] = i)
		elif p.default is bool:
			check(parent, p.label, values[key], func(on: bool) -> void:
				if on_begin.is_valid():
					on_begin.call()
				values[key] = on)
		else:
			var set_value := func(v: float) -> void: values[key] = v
			slider(parent, p.label, p.min, p.max, p.step, values[key], set_value, on_begin, p.default)


static func _fmt(v: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % roundi(v)
	return ("%.2f" if step >= 0.01 else "%.3f") % v


## Keyboard focus on buttons would swallow Space (pause) and the arrow keys.
## Text fields keep theirs.
static func no_focus(node: Node) -> void:
	if node is Control and not node is LineEdit:
		node.focus_mode = Control.FOCUS_NONE
	for c in node.get_children():
		no_focus(c)


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
