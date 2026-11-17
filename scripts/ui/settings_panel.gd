class_name SettingsPanel
extends CanvasLayer
## 设置面板：盖在当前画面上，改的东西马上生效并存盘（见 scripts/core/settings.gd）。
##   MASTER / MUSIC / SFX  三条音量
##   FULLSCREEN            全屏开关（网页版没有这一项）
##   OFFSET                判定延迟（毫秒），和校准界面测的是同一个值
##   CALIBRATE             进延迟校准界面（测完回主菜单）
##   BACK                  关掉（Esc 也行）
## 键盘：↑ ↓ 选，← → 调，回车按按钮。鼠标也能点能拖。
## 用法：SettingsPanel.open_overlay(某个节点)。暂停的时候也能用（process_mode = ALWAYS）。

signal closed

const CANDY := preload("res://assets/fonts/candy_gem/CandyGem.fnt")
const CALIBRATE_SCENE := "res://scenes/calibrate.tscn"
## 判定延迟能调的范围（毫秒）
const OFFSET_RANGE := 200.0
const OFFSET_STEP := 5.0

const PINK := Color(0.95, 0.35, 0.9)
const VIOLET := Color(0.82, 0.38, 1.0)
const DEEP := Color(0.1, 0.03, 0.16, 0.92)
## 没选中的行名字暗到多少
const DIM := Color(0.68, 0.62, 0.75)

var _panel: PanelContainer
var _first: Control
var _fullscreen_btn: Button
var _offset_slider: HSlider
var _offset_value: Label
var _closing := false


static func open_overlay(parent: Node) -> SettingsPanel:
	var p := SettingsPanel.new()
	parent.add_child(p)
	return p


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	# 弹出来：从小一点、透明淡进来
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2.ONE * 0.92
	_panel.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_panel, "modulate:a", 1.0, 0.12)
	_first.grab_focus.call_deferred()


func close() -> void:
	if _closing:
		return
	_closing = true
	var t := create_tween().set_parallel()
	t.tween_property(_panel, "scale", Vector2.ONE * 0.94, 0.12)
	t.tween_property(_panel, "modulate:a", 0.0, 0.12)
	t.chain().tween_callback(func() -> void:
		closed.emit()
		queue_free())


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE):
		close()
	# 面板开着时，按键和点击都不往下传（不转转盘、不开始游戏、不触发暂停菜单）
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.0, 0.06, 0.72)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close())  # 点面板外面 = 关掉
	root.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(560, 0)
	_panel.add_theme_stylebox_override("panel", _box(DEEP, VIOLET, 18, 4, 28, Color(0.56, 0.08, 1.0, 0.55), 18))
	center.add_child(_panel)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	_panel.add_child(list)

	var title := _candy_label("SETTINGS", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(title)
	list.add_child(_spacer(4))

	var focusables: Array[Control] = []
	for bus in Settings.VOLUME_BUSES:
		var caption := {&"Master": "MASTER", Settings.MUSIC_BUS: "MUSIC", Settings.SFX_BUS: "SFX"}[bus] as String
		var s := _slider(0.0, 1.0, 0.05, Settings.get_volume(bus))
		var value := _value_label("%d%%" % roundi(s.value * 100.0))
		s.value_changed.connect(func(v: float) -> void:
			Settings.set_volume(bus, v)
			value.text = "%d%%" % roundi(v * 100.0))
		list.add_child(_row(caption, s, value))
		focusables.append(s)

	if Settings.can_fullscreen():
		_fullscreen_btn = _button("")
		_fullscreen_btn.toggle_mode = true
		_fullscreen_btn.button_pressed = Settings.fullscreen
		_fullscreen_btn.toggled.connect(func(on: bool) -> void:
			Settings.set_fullscreen(on)
			_sync_fullscreen())
		_fullscreen_btn.custom_minimum_size.x = 150
		_sync_fullscreen()
		list.add_child(_row("FULLSCREEN", _fullscreen_btn, null))
		focusables.append(_fullscreen_btn)

	_offset_slider = _slider(-OFFSET_RANGE, OFFSET_RANGE, OFFSET_STEP, Settings.get_input_offset_ms())
	_offset_value = _value_label("")
	_offset_slider.value_changed.connect(func(v: float) -> void:
		Settings.set_input_offset_ms(v)
		_sync_offset())
	_sync_offset()
	list.add_child(_row("OFFSET", _offset_slider, _offset_value))
	focusables.append(_offset_slider)

	var hint := Label.new()
	hint.text = "Hits judged LATE?  Raise OFFSET.   EARLY?  Lower it."
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.8, 0.74, 0.87))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(hint)
	list.add_child(_spacer(2))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 28)
	list.add_child(buttons)
	var calibrate := _button("CALIBRATE")
	calibrate.pressed.connect(_calibrate)
	buttons.add_child(calibrate)
	var back := _button("BACK")
	back.pressed.connect(close)
	buttons.add_child(back)
	focusables.append(calibrate)
	focusables.append(back)

	# ↑ ↓ 按列表顺序走，首尾相接；两个按钮之间 ← → 互跳
	for i in focusables.size():
		var c := focusables[i]
		c.focus_neighbor_top = c.get_path_to(focusables[posmod(i - 1, focusables.size())])
		c.focus_neighbor_bottom = c.get_path_to(focusables[posmod(i + 1, focusables.size())])
	calibrate.focus_neighbor_right = calibrate.get_path_to(back)
	back.focus_neighbor_left = back.get_path_to(calibrate)
	calibrate.focus_neighbor_bottom = calibrate.get_path_to(focusables[0])
	_first = focusables[0]


func _calibrate() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(CALIBRATE_SCENE)


func _sync_fullscreen() -> void:
	_fullscreen_btn.text = "ON" if Settings.fullscreen else "OFF"


func _sync_offset() -> void:
	var ms := roundi(_offset_slider.value)
	_offset_value.text = "0 ms" if ms == 0 else "%+d ms" % ms


## 一行：左边名字，中间控件，右边数值
func _row(text: String, control: Control, value: Label) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var caption := _candy_label(text, 30)
	caption.custom_minimum_size.x = 190
	row.add_child(caption)
	# 选中的这一行名字亮起来，其它行暗一点
	caption.modulate = DIM
	control.focus_entered.connect(func() -> void: caption.modulate = Color.WHITE)
	control.focus_exited.connect(func() -> void: caption.modulate = DIM)
	if not control is Button:
		control.mouse_entered.connect(control.grab_focus)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL if control is HSlider else Control.SIZE_SHRINK_BEGIN
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	if value:
		row.add_child(value)
	elif control is Button:
		var filler := Control.new()
		filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(filler)
	return row


func _candy_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", CANDY)
	l.add_theme_font_size_override("font_size", size)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _value_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 76
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1, 0.91, 1))
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


## 和主菜单音量条同一套样子：深紫槽、粉色填充、发光的圆钮；选中时槽的边框变亮
func _slider(lo: float, hi: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 34)
	s.focus_mode = Control.FOCUS_ALL
	var track := _box(Color(0.1, 0.03, 0.16, 0.85), VIOLET, 10, 3, 8, Color(0.56, 0.08, 1.0, 0.6), 0)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill := _box(PINK, Color(1, 0.91, 1), 10, 3, 8, Color(1, 0.3, 0.9, 0.55), 0)
	fill.content_margin_top = 8
	fill.content_margin_bottom = 8
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var focus := _box(Color(0, 0, 0, 0), Color(1, 0.95, 1), 14, 2, 10, Color(1, 0.5, 1, 0.8), 0)
	focus.expand_margin_left = 6
	focus.expand_margin_right = 6
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	s.add_theme_stylebox_override("focus", focus)
	var knob := _knob()
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	return s


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", CANDY)
	b.add_theme_font_size_override("font_size", 34)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	var normal := _box(Color(0.1, 0.03, 0.16, 0.6), VIOLET, 14, 3, 0, Color(0, 0, 0, 0), 0)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	normal.content_margin_top = 6
	normal.content_margin_bottom = 4
	var lit := normal.duplicate() as StyleBoxFlat
	lit.bg_color = Color(0.45, 0.1, 0.55, 0.85)
	lit.border_color = Color(1, 0.91, 1)
	lit.shadow_color = Color(1, 0.3, 0.9, 0.6)
	lit.shadow_size = 10
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("pressed", lit)
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("hover_pressed", lit)
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color(1, 0.95, 1), 16, 2, 0, Color(1, 0.5, 1, 0.8), 8))
	b.mouse_entered.connect(b.grab_focus)
	return b


func _box(bg: Color, border: Color, radius: int, border_w: int, margin: float, shadow: Color, shadow_size: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.shadow_color = shadow
	sb.shadow_size = shadow_size
	return sb


func _knob() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 0.72, 1.0])
	g.colors = PackedColorArray([Color(1, 0.95, 1), Color(1, 0.75, 1), VIOLET, Color(0.56, 0.08, 1.0, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 34
	t.height = 34
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t
