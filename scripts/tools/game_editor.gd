extends CanvasLayer
## 游戏里的编辑面板：进了关卡按 Tab 调出来，再按 Tab 收起。只在编辑器里运行游戏时有（导出的游戏里没有）。
## 直接看着画面改当前小关：
##
##   最上面一根“积累条”进度条：拖它 = 假装玩家把积累条打到了这么满，画面、镜头特效、猫图、音乐都会跟着变。
##   面板开着的时候，打中 / 漏打不再改积累条。
##
##   Phases       这个小关的积累条分数线（阶段）：改名字、改分数、增删；点“Jump”把小关重开并直接跳到那个阶段。
##                进度条往前拖过一条线会触发那个阶段，往回拖不会撤销（要回去就用 Jump）。
##   Camera       点一个特效 = 从当前进度起切到它（再点一次 = 从这里起回到原样）；
##                细条上的白线是切换点，拖动改位置，右键删掉。
##   Memes        左边点缩略图选素材，在当前进度加一只；选中后在画面上拖动摆位置，
##                还可以给它选动效（自转、绕圈、流过去……）和快慢。
##   音乐         每条轨道点一段 = 从当前进度起换成它。
##   谱子         点格子写这个小关循环的鼓谱。
##
## 改动先只在这次运行里生效，点“保存”才写进文件：阶段 / 镜头 / 猫图 / 谱子 / 满条值写进大关的 .tres，
## 音乐写进 levels/music/ 里对应的 .json。

const Grid := preload("res://scripts/tools/pattern_grid.gd")
const CueStrip := preload("res://scripts/music/cue_strip.gd")
const THEME := preload("res://assets/ui/theme.tres")
const PALETTE := [Color("ffd23f"), Color("ff5d8f"), Color("7fd1ff"), Color("86ffa3"), Color("b38cff"),
		Color("ff9a3c"), Color("5ee6d0"), Color("f2f2f2")]
const PANEL_HEIGHT := 330.0
const SNAP := 0.05

var main: Node
var dirty := false

var _panel: PanelContainer
var _title: Label
var _status: Label
var _gauge_max: SpinBox
var _progress: HSlider
var _progress_lcd: Label
var _ticks: Control
var _phase_chips: HFlowContainer
var _phase_box: HBoxContainer
var _phase_name: LineEdit
var _phase_at: SpinBox
var _phase_pct: Label
var _phase_sel := 0
var _fx_strip: Control
var _fx_buttons := {}
var _meme_chips: HFlowContainer
var _meme_list: ItemList
var _meme_box: VBoxContainer
var _meme_at: SpinBox
var _meme_size: HSlider
var _meme_fx: OptionButton
var _meme_speed: HSlider
var _meme_sel := -1
var _dragging := false
var _music_box: VBoxContainer
var _music_strips := {}
var _music_chips := {}
var _grid: Control
var _loading := false


func setup(game: Node) -> void:
	main = game
	layer = 10
	_build_ui()
	main.section_entered.connect(func(_i: int) -> void: _load_section())
	_load_section()


func set_open(on: bool) -> void:
	main.editing = on
	_panel.visible = on
	main.screen_fx.latched = not on
	main.memes.latched = not on
	if on:
		_load_section()


func _def() -> SectionDef:
	return main.chart.sections[main._index]


func _p() -> float:
	return _progress.value / 100.0


# ---------------------------------------------------------------- 界面

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.theme = THEME
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -PANEL_HEIGHT
	_panel.self_modulate.a = 0.94
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	_panel.add_child(root)

	# 小关信息
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	_btn(head, "◀", func() -> void: _go(-1), "Previous stage")
	_btn(head, "▶", func() -> void: _go(1), "Next stage")
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.custom_minimum_size.x = 120
	head.add_child(_title)
	head.add_child(_lbl("   Gauge max"))
	_gauge_max = SpinBox.new()
	_gauge_max.min_value = 5
	_gauge_max.max_value = 2000
	_gauge_max.step = 5
	_gauge_max.tooltip_text = "Points needed to fill this stage's gauge (a Perfect is +5)"
	_gauge_max.value_changed.connect(_on_gauge_max)
	head.add_child(_gauge_max)
	_status = _lbl("")
	head.add_child(_status)
	_btn(head, "Jukebox", _open_jukebox, "Leave the game and listen to every song and sound we have")
	_btn(head, "Save", save, "Write the changes of every stage to disk")
	_btn(head, "Close (Tab)", func() -> void: main.toggle_editor())

	# 积累条
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	bar.add_child(_lbl("Gauge"))
	_progress = HSlider.new()
	_progress.max_value = 100
	_progress.step = 1
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.focus_mode = Control.FOCUS_NONE
	_progress.value_changed.connect(_on_progress)
	var track := VBoxContainer.new()
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.add_theme_constant_override("separation", 0)
	bar.add_child(track)
	track.add_child(_progress)
	# 进度条下面一排小刻度：每条分数线（阶段）一个编号，已经触发过的是亮的
	_ticks = Control.new()
	_ticks.custom_minimum_size.y = 14
	_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticks.draw.connect(_draw_ticks)
	track.add_child(_ticks)
	_progress_lcd = _lbl("0%")
	_progress_lcd.custom_minimum_size.x = 150
	bar.add_child(_progress_lcd)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_build_phase_tab())
	tabs.add_child(_build_fx_tab())
	tabs.add_child(_build_meme_tab())
	tabs.tab_changed.connect(func(tab: int) -> void:
		if tabs.get_child(tab).name == "Memes":
			_fill_thumbnails())
	tabs.add_child(_build_music_tab())
	tabs.add_child(_build_pattern_tab())


func _build_phase_tab() -> Control:
	var v := VBoxContainer.new()
	v.name = "Phases"
	v.add_theme_constant_override("separation", 6)
	_phase_chips = HFlowContainer.new()
	v.add_child(_phase_chips)
	_phase_box = HBoxContainer.new()
	_phase_box.add_theme_constant_override("separation", 6)
	v.add_child(_phase_box)
	_btn(_phase_box, "▶ Jump here", func() -> void: _jump_phase(_phase_sel),
			"Restart this stage and go straight to the selected phase (earlier phases are triggered in order)")
	_phase_box.add_child(_lbl("  Name"))
	_phase_name = LineEdit.new()
	_phase_name.custom_minimum_size.x = 130
	_phase_name.text_changed.connect(_rename_phase)
	_phase_box.add_child(_phase_name)
	_phase_box.add_child(_lbl("Starts at"))
	_phase_at = SpinBox.new()
	_phase_at.min_value = 1
	_phase_at.step = 1
	_phase_at.custom_arrow_step = 5
	_phase_at.suffix = "pts"
	_phase_at.tooltip_text = "Gauge points where this phase starts (a Perfect is +5)"
	_phase_at.value_changed.connect(_move_phase)
	_phase_box.add_child(_phase_at)
	_phase_pct = _lbl("")
	_phase_box.add_child(_phase_pct)
	_btn(_phase_box, "Delete", _remove_phase, "Remove this gauge line. Later phases move up one slot")
	var row := HBoxContainer.new()
	v.add_child(row)
	_btn(row, "+ Add phase at current gauge", _add_phase, "Add a gauge line at the current gauge position")
	var hint := _lbl("   Dragging the gauge forward past a line triggers that phase; dragging back does not undo it. Use Jump to go back.")
	hint.modulate.a = 0.6
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	return v


func _build_fx_tab() -> Control:
	var v := VBoxContainer.new()
	v.name = "Camera"
	v.add_theme_constant_override("separation", 6)
	var row := HFlowContainer.new()
	v.add_child(row)
	row.add_child(_lbl("Camera  "))
	for id: String in ScreenFx.EFFECTS:
		var info: Dictionary = ScreenFx.EFFECTS[id]
		var b := _btn(row, info.label, func() -> void: _cue_fx(id),
				"From the current gauge position on, switch to %s (click again to go back to Normal from here)" % info.label)
		b.add_theme_color_override("font_color", info.color.lightened(0.3))
		_fx_buttons[id] = b
	_fx_strip = CueStrip.new()
	_fx_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fx_strip.custom_minimum_size.y = 18
	for id: String in ScreenFx.EFFECTS:
		_fx_strip.colors[id] = ScreenFx.EFFECTS[id].color
	_fx_strip.changed.connect(func() -> void:
		_tidy(_def().fx_cues)
		main.screen_fx.refresh()
		_mark_dirty())
	v.add_child(_fx_strip)

	return v


func _build_meme_tab() -> Control:
	var split := HBoxContainer.new()
	split.name = "Memes"
	split.add_theme_constant_override("separation", 10)
	# 左边：所有素材的缩略图
	_meme_list = ItemList.new()
	_meme_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meme_list.size_flags_stretch_ratio = 1.1
	_meme_list.max_columns = 0
	_meme_list.icon_mode = ItemList.ICON_MODE_TOP
	_meme_list.fixed_icon_size = Vector2i(46, 46)
	_meme_list.fixed_column_width = 50
	_meme_list.same_column_width = true
	_meme_list.focus_mode = Control.FOCUS_NONE
	_meme_list.tooltip_text = "Click to pick, double-click to add at the current gauge position"
	_meme_list.item_activated.connect(func(_i: int) -> void: _add_meme())
	split.add_child(_meme_list)
	# 右边：这个小关已经放了哪些，以及选中那只的设置
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	_btn(right, "+ Add picked meme at current gauge", _add_meme, "The picked cat pops in when the gauge reaches the current position")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_meme_chips = HFlowContainer.new()
	_meme_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_meme_chips)
	_meme_box = VBoxContainer.new()
	_meme_box.tooltip_text = "Drag on the picture to place the selected meme"
	right.add_child(_meme_box)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	_meme_box.add_child(row1)
	row1.add_child(_lbl("At"))
	_meme_at = SpinBox.new()
	_meme_at.max_value = 100
	_meme_at.step = 5
	_meme_at.suffix = "%"
	_meme_at.value_changed.connect(func(val: float) -> void: _edit_meme("at", val / 100.0))
	row1.add_child(_meme_at)
	row1.add_child(_lbl("Size"))
	_meme_size = _slider(row1, 0.05, 1.0, func(val: float) -> void: _edit_meme("size", val))
	_btn(row1, "Delete", _remove_meme)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	_meme_box.add_child(row2)
	row2.add_child(_lbl("Effect"))
	_meme_fx = OptionButton.new()
	_meme_fx.focus_mode = Control.FOCUS_NONE
	for id: String in MemeCues.EFFECTS:
		_meme_fx.add_item(MemeCues.EFFECTS[id])
		_meme_fx.set_item_metadata(_meme_fx.item_count - 1, id)
	_meme_fx.item_selected.connect(func(i: int) -> void: _edit_meme("fx", _meme_fx.get_item_metadata(i)))
	row2.add_child(_meme_fx)
	row2.add_child(_lbl("Speed"))
	_meme_speed = _slider(row2, 0.1, 3.0, func(val: float) -> void: _edit_meme("speed", val))
	return split


func _slider(parent: Control, lo: float, hi: float, action: Callable) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.01
	sl.custom_minimum_size.x = 110
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(action)
	parent.add_child(sl)
	return sl


## 第一次点开 Memes 页时才把缩略图加载进来（一百来张图，提前加载会让开面板卡一下）
func _fill_thumbnails() -> void:
	if _meme_list.item_count > 0:
		return
	for key in MemeLib.keys():
		var info := MemeLib.find(key)
		var sheet: Texture2D = load(info.path)
		var icon := AtlasTexture.new()  # 只取序列帧图的第一格
		icon.atlas = sheet
		icon.region = Rect2(0, 0, sheet.get_width() / float(info.cols), sheet.get_height() / float(info.rows))
		_meme_list.add_icon_item(icon)
		_meme_list.set_item_tooltip(_meme_list.item_count - 1, key)
		_meme_list.set_item_metadata(_meme_list.item_count - 1, key)
	_meme_list.select(0)


func _build_music_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Music"
	_music_box = VBoxContainer.new()
	_music_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_music_box)
	return scroll


func _build_pattern_tab() -> Control:
	var v := VBoxContainer.new()
	v.name = "Pattern"
	var tools := HFlowContainer.new()
	v.add_child(tools)
	tools.add_child(_lbl("Brush  "))
	var group := ButtonGroup.new()
	var names := ["Kick K", "Snare S", "Hat H", "Eraser"]
	for i in names.size():
		var b := _btn(tools, names[i], func() -> void: _grid.brush = i if i < 3 else -1)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		if i < 3:
			b.add_theme_color_override("font_color", Grid.COLORS[i])
			b.add_theme_color_override("font_pressed_color", Grid.COLORS[i])
	tools.add_child(VSeparator.new())
	_btn(tools, "+ Bar", func() -> void: _resize_bars(1))
	_btn(tools, "- Bar", func() -> void: _resize_bars(-1))
	_btn(tools, "Restart stage with new pattern", func() -> void: main.start_from(main._index),
			"Notes follow the new pattern only after the stage restarts (score resets, music starts over)")
	var hint := _lbl("   Left click paints / click again clears, right click erases. These bars loop until the gauge is full")
	hint.modulate.a = 0.6
	tools.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_grid = Grid.new()
	_grid.edited.connect(func() -> void:
		_def().bars = _grid.bars.duplicate()
		_mark_dirty())
	scroll.add_child(_grid)
	return v


func _lbl(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


## 曲库：离开游戏，去听所有做好的曲子和音效（scenes/tools/jukebox.tscn）。没保存的改动不会丢在文件里，但会丢在这次运行里。
func _open_jukebox() -> void:
	Conductor.stop()
	get_tree().change_scene_to_file("res://scenes/tools/jukebox.tscn")


func _btn(parent: Control, text: String, action: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


# ---------------------------------------------------------------- 小关

func _go(by: int) -> void:
	var to: int = main._index + by
	if to >= 0 and to < main.chart.sections.size():
		main.start_from(to)


## 把当前小关的数据填进面板
func _load_section() -> void:
	if _panel == null or main.chart == null or main._index < 0:
		return
	var def := _def()
	_loading = true
	var file: String = def.get("scene_file")
	_title.text = "Stage %d / %d   %s   ·   %s" % [main._index + 1, main.chart.sections.size(), def.title, file]
	_gauge_max.value = main.gauge.max_value
	_progress.value = roundf(100.0 * main.gauge.value / maxi(main.gauge.max_value, 1))
	_progress_lcd.text = "%d%%" % int(_progress.value)
	_fx_strip.cues = def.fx_cues
	_fx_strip.markers = _markers()
	_grid.beats_per_bar = main.chart.beats_per_bar
	_grid.set_bars(def.bars)
	_loading = false
	_meme_sel = -1
	_phase_sel = clampi(_phase_sel, 0, main.gauge.events.size())
	_fill_phases()
	_fill_memes()
	_fill_music()
	_refresh()


## 积累条的事件分数线在进度条上的位置（细条上的粉色竖线，拖切换点时会吸附过去）
func _markers() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in main.gauge.events:
		out.append(float(v) / maxi(main.gauge.max_value, 1))
	return out


func _on_gauge_max(v: float) -> void:
	if _loading:
		return
	_def().gauge_max = int(v)
	main.gauge.max_value = int(v)
	_on_progress(_progress.value)
	_mark_dirty()


func _on_progress(v: float) -> void:
	if _loading:
		return
	_progress_lcd.text = "%d%%" % int(v)
	main.gauge.set_value(roundi(v / 100.0 * main.gauge.max_value))
	main.gauge.fire_passed_events()
	_refresh()


## 进度条位置变了 / 数据变了之后，更新细条和按钮的高亮
func _refresh() -> void:
	var p := _p()
	var phase := _phase_now()
	_progress_lcd.text = "%d%%" % int(_progress.value) + ("  ·  %s" % _phase_title(phase) if not main.gauge.events.is_empty() else "")
	_ticks.queue_redraw()
	for i in _phase_chips.get_child_count():
		_phase_chips.get_child(i).modulate.a = 1.0 if i <= main.gauge.events_fired else 0.55
	_fx_strip.playhead = p
	_fx_strip.queue_redraw()
	var now := ScreenFx.effect_at(_def().fx_cues, p)
	for id: String in _fx_buttons:
		_fx_buttons[id].modulate = Color.WHITE if id == now else Color(1, 1, 1, 0.55)
	for lid: String in _music_strips:
		_music_strips[lid].playhead = p
		_music_strips[lid].queue_redraw()
		var playing := Music.clip_at(main._index, lid, p)
		for cid: String in _music_chips[lid]:
			_music_chips[lid][cid].modulate = Color.WHITE if cid == playing else Color(1, 1, 1, 0.55)
	for i in _meme_chips.get_child_count():
		var cue: Dictionary = _def().meme_cues[i]
		_meme_chips.get_child(i).modulate.a = 1.0 if float(cue.at) <= p + 0.0001 else 0.55


## 切换点排好序，去掉“换成和之前一样的”那种多余的点
func _tidy(list: Array) -> void:
	list.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	var last := ""
	for c in list:
		if c[1] != last:
			out.append(c)
			last = c[1]
	list.clear()
	list.append_array(out)


## 在当前进度放一个切换点：换成 id；如果那里本来就是 id，就改成 ""（原样 / 静音）
func _put_cue(list: Array, now: String, id: String) -> void:
	var p := snappedf(_p(), SNAP)
	for i in range(list.size() - 1, -1, -1):
		if absf(list[i][0] - p) < 0.001:
			list.remove_at(i)
	list.append([p, "" if now == id else id])
	_tidy(list)


func _mark_dirty() -> void:
	dirty = true
	_status.text = "● Unsaved changes"


# ---------------------------------------------------------------- 阶段（积累条的分数线）

## 第 i 个阶段叫什么（0 = 第一条线之前）
func _phase_title(i: int) -> String:
	if i <= 0:
		return "Start"
	var names := _def().gauge_event_names
	return names[i - 1] if i - 1 < names.size() and names[i - 1] != "" else "Phase %d" % i


## 积累条现在的数值落在第几个阶段里
func _phase_now() -> int:
	var n := 0
	for v in main.gauge.events:
		if main.gauge.value >= v:
			n += 1
	return n


func _draw_ticks() -> void:
	var font := _panel.get_theme_default_font()
	var grab := 8.0  # 滑块两头各留半个把手的宽度
	var events: PackedInt32Array = main.gauge.events
	for i in events.size():
		var x := grab + (_ticks.size.x - grab * 2.0) * events[i] / maxf(main.gauge.max_value, 1.0)
		var c := Color(1, 0.36, 0.56) if i < main.gauge.events_fired else Color(1, 1, 1, 0.45)
		if i + 1 == _phase_sel:
			c = Color("ffd23f")
		_ticks.draw_line(Vector2(x, 0), Vector2(x, 4), c, 2.0)
		_ticks.draw_string(font, Vector2(x - 10, 14), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 20, 10, c)


func _fill_phases() -> void:
	for c in _phase_chips.get_children():
		_phase_chips.remove_child(c)
		c.queue_free()
	var events: PackedInt32Array = main.gauge.events
	for i in events.size() + 1:
		var text := "Start" if i == 0 else "%d  %s · %d" % [i, _phase_title(i), events[i - 1]]
		var b := _btn(_phase_chips, text, func() -> void: _select_phase(i), "Click to select, double-click to jump there")
		b.toggle_mode = true
		b.button_pressed = i == _phase_sel
		b.gui_input.connect(func(e: InputEvent) -> void:
			var m := e as InputEventMouseButton
			if m and m.pressed and m.double_click and m.button_index == MOUSE_BUTTON_LEFT:
				_jump_phase(i))
	var on := _phase_sel > 0 and _phase_sel <= events.size()
	for c in _phase_box.get_children().slice(1):
		c.visible = on
	if on:
		_loading = true
		if _phase_name.text != _phase_title(_phase_sel) and not _phase_name.has_focus():
			_phase_name.text = _phase_title(_phase_sel)
		_phase_at.max_value = main.gauge.max_value
		_phase_at.value = events[_phase_sel - 1]
		_phase_pct.text = "= %d%%" % roundi(100.0 * events[_phase_sel - 1] / maxi(main.gauge.max_value, 1))
		_loading = false
	_ticks.queue_redraw()
	if _fx_strip:
		_fx_strip.markers = _markers()
		_fx_strip.queue_redraw()
	for lid: String in _music_strips:
		_music_strips[lid].markers = _markers()


func _select_phase(i: int) -> void:
	_phase_sel = i
	_phase_name.release_focus()
	_fill_phases()
	_refresh()


func _jump_phase(i: int) -> void:
	_phase_sel = i
	main.jump_to_phase(i)
	_load_section()


## 分数线改了：记到这个小关的定义里（以后以它为准，不再用场景里填的），并马上用到正在跑的积累条上
func _apply_phases(events: PackedInt32Array, names: PackedStringArray) -> void:
	var def := _def()
	def.gauge_events = events
	def.use_gauge_events = true
	def.gauge_event_names = names
	main.gauge.set_events(events)
	main._current.gauge_event_values = main.gauge.events
	_mark_dirty()
	_fill_phases()
	_refresh()


## 现在所有阶段的名字（补齐到和分数线一样多）
func _phase_names() -> PackedStringArray:
	var out := PackedStringArray()
	for i in main.gauge.events.size():
		out.append(_phase_title(i + 1))
	return out


func _rename_phase(text: String) -> void:
	if _loading or _phase_sel <= 0:
		return
	var names := _phase_names()
	names[_phase_sel - 1] = text
	_apply_phases(main.gauge.events.duplicate(), names)


## 改分数：不能越过前后两条线（阶段的先后顺序不变）
func _move_phase(v: float) -> void:
	if _loading or _phase_sel <= 0:
		return
	var events: PackedInt32Array = main.gauge.events.duplicate()
	var i := _phase_sel - 1
	var lo := events[i - 1] + 1 if i > 0 else 1
	var hi: int = events[i + 1] - 1 if i + 1 < events.size() else main.gauge.max_value
	events[i] = clampi(int(v), lo, hi)
	_apply_phases(events, _phase_names())


func _add_phase() -> void:
	var at := clampi(main.gauge.value, 1, main.gauge.max_value)
	var events: PackedInt32Array = main.gauge.events.duplicate()
	if events.has(at):
		return
	var names := _phase_names()
	var i := 0
	while i < events.size() and events[i] < at:
		i += 1
	events.insert(i, at)
	names.insert(i, "Phase %d" % (i + 1))
	_phase_sel = i + 1
	_apply_phases(events, names)


func _remove_phase() -> void:
	if _phase_sel <= 0 or _phase_sel > main.gauge.events.size():
		return
	var events: PackedInt32Array = main.gauge.events.duplicate()
	var names := _phase_names()
	events.remove_at(_phase_sel - 1)
	names.remove_at(_phase_sel - 1)
	_phase_sel = mini(_phase_sel, events.size())
	_apply_phases(events, names)


# ---------------------------------------------------------------- 镜头

func _cue_fx(id: String) -> void:
	var list := _def().fx_cues
	_put_cue(list, ScreenFx.effect_at(list, snappedf(_p(), SNAP)), id)
	main.screen_fx.refresh()
	main.screen_fx.set_progress(_p())
	_mark_dirty()
	_refresh()


# ---------------------------------------------------------------- 猫图

func _fill_memes() -> void:
	for c in _meme_chips.get_children():
		_meme_chips.remove_child(c)
		c.queue_free()
	var list := _def().meme_cues
	for i in list.size():
		var cue: Dictionary = list[i]
		var b := _btn(_meme_chips, "%d%%  %s" % [roundi(float(cue.at) * 100.0), cue.meme], func() -> void: _select_meme(i),
				"Click to select, then drag on the picture to place it")
		b.toggle_mode = true
		b.button_pressed = i == _meme_sel
	_meme_box.visible = _meme_sel >= 0 and _meme_sel < list.size()
	if _meme_box.visible:
		_loading = true
		var cue: Dictionary = list[_meme_sel]
		_meme_at.value = roundf(float(cue.at) * 100.0)
		_meme_size.value = cue.get("size", 0.25)
		_meme_speed.value = cue.get("speed", 1.0)
		for k in _meme_fx.item_count:
			if _meme_fx.get_item_metadata(k) == cue.get("fx", ""):
				_meme_fx.select(k)
		_loading = false


func _select_meme(i: int) -> void:
	_meme_sel = -1 if i == _meme_sel else i
	_fill_memes()
	_refresh()


func _add_meme() -> void:
	var list := _def().meme_cues
	# 新加的先错开一点放，免得叠在一起
	var n := list.size()
	list.append({"at": snappedf(_p(), SNAP), "meme": _picked_meme(),
			"x": -0.3 + 0.15 * (n % 5), "y": -0.25 + 0.12 * ((n / 5) % 3), "size": 0.25})
	_meme_sel = n
	_memes_changed(true)


## 缩略图里现在选中的素材名
func _picked_meme() -> String:
	_fill_thumbnails()
	var picked := _meme_list.get_selected_items()
	return _meme_list.get_item_metadata(picked[0] if picked.size() > 0 else 0)


func _remove_meme() -> void:
	if _meme_sel >= 0 and _meme_sel < _def().meme_cues.size():
		_def().meme_cues.remove_at(_meme_sel)
		_meme_sel = -1
		_memes_changed(true)


func _edit_meme(key: String, value: Variant) -> void:
	if _loading or _meme_sel < 0:
		return
	_def().meme_cues[_meme_sel][key] = value
	_memes_changed(key == "at" or key == "fx")


func _memes_changed(rebuild: bool) -> void:
	if rebuild:
		main.memes.rebuild()
		main.memes.set_progress(_p())
		_fill_memes()
	_mark_dirty()
	_refresh()


## 面板开着、选中了一只猫图时，在画面上按住拖动 = 摆它的位置
func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible or _meme_sel < 0 or _meme_sel >= _def().meme_cues.size():
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
		if mb.pressed:
			_drag_to(mb.position)
		get_viewport().set_input_as_handled()
	var mm := event as InputEventMouseMotion
	if mm and _dragging:
		_drag_to(mm.position)


func _drag_to(pos: Vector2) -> void:
	var size := get_viewport().get_visible_rect().size
	var cue: Dictionary = _def().meme_cues[_meme_sel]
	cue.x = snappedf(clampf(pos.x / size.x - 0.5, -0.5, 0.5), 0.005)
	cue.y = snappedf(clampf(pos.y / size.y - 0.5, -0.5, 0.5), 0.005)
	_mark_dirty()


# ---------------------------------------------------------------- 音乐

## 这个小关的音乐切换点（Music 的配置里），没有就建一份空的
func _music_cues() -> Dictionary:
	if not Music.data.has("sections"):
		Music.data["sections"] = []
	var secs: Array = Music.data.sections
	while secs.size() <= main._index:
		secs.append({"title": main.chart.sections[secs.size()].title, "cues": {}})
	if not secs[main._index].has("cues"):
		secs[main._index]["cues"] = {}
	return secs[main._index].cues


func _fill_music() -> void:
	for c in _music_box.get_children():
		_music_box.remove_child(c)
		c.queue_free()
	_music_strips.clear()
	_music_chips.clear()
	if not Music.enabled_for(Levels.selected) or Music.stream == null:
		var note := _lbl("This level does not use layered music (it plays the single backing track from its chart), so there are no lanes to switch by gauge.\nTo use it, set up the lanes in this level's .json under levels/music/ and set use_in_game to true.")
		note.modulate.a = 0.7
		_music_box.add_child(note)
		return
	var cues := _music_cues()
	for lane: Dictionary in Music.data.get("lanes", []):
		var lid: String = lane.id
		var row := HBoxContainer.new()
		_music_box.add_child(row)
		var name_label := _lbl(lid)  # 轨道的 id 本来就是英文；json 里的 name 是中文
		name_label.custom_minimum_size.x = 70
		row.add_child(name_label)
		var right := VBoxContainer.new()
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.add_theme_constant_override("separation", 2)
		row.add_child(right)
		var chips := HFlowContainer.new()
		right.add_child(chips)
		var strip := CueStrip.new()
		strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not cues.has(lid):
			cues[lid] = []
		strip.cues = cues[lid]
		strip.markers = _markers()
		_music_chips[lid] = {}
		var clips: Array = lane.get("clips", [])
		for i in clips.size():
			var cid: String = clips[i].id
			var color: Color = PALETTE[i % PALETTE.size()]
			strip.colors[cid] = color
			var b := _btn(chips, cid, func() -> void: _cue_music(lid, cid),
					"From the current gauge position on, this lane plays this clip (click again to mute it from here)")
			b.add_theme_color_override("font_color", color)
			_music_chips[lid][cid] = b
		strip.changed.connect(func() -> void:
			_tidy(cues[lid])
			Music.apply_now()
			_mark_dirty())
		right.add_child(strip)
		_music_strips[lid] = strip


func _cue_music(lid: String, cid: String) -> void:
	var list: Array = _music_cues()[lid]
	_put_cue(list, Music.clip_at(main._index, lid, snappedf(_p(), SNAP)), cid)
	Music.progress = _p()
	Music.apply_now()
	_mark_dirty()
	_refresh()


# ---------------------------------------------------------------- 谱子

func _resize_bars(by: int) -> void:
	var bars := _def().bars.duplicate()
	if by > 0:
		bars.append(".".repeat(bars[-1].length() if bars.size() > 0 and bars[-1] != "" else 16))
	elif bars.size() > 1:
		bars.remove_at(bars.size() - 1)
	_def().bars = bars
	_grid.set_bars(bars)
	_mark_dirty()


# ---------------------------------------------------------------- 保存

## 游戏里用的谱面是文件的一份副本，这里把每个小关改过的东西抄回文件里那一份再存
func save() -> void:
	var path: String = Levels.paths()[Levels.selected]
	var src := load(path) as SongChart
	var err := OK
	if src.sections.size() != main.chart.sections.size():
		err = ERR_INVALID_DATA
	else:
		for i in src.sections.size():
			var from: SectionDef = main.chart.sections[i]
			src.sections[i].fx_cues = from.fx_cues.duplicate(true)
			src.sections[i].meme_cues = from.meme_cues.duplicate(true)
			src.sections[i].bars = from.bars.duplicate()
			src.sections[i].gauge_max = from.gauge_max
			src.sections[i].gauge_events = from.gauge_events.duplicate()
			src.sections[i].use_gauge_events = from.use_gauge_events
			src.sections[i].gauge_event_names = from.gauge_event_names.duplicate()
		err = ResourceSaver.save(src, path)
	var saved := path.get_file()
	if err == OK and Music.enabled_for(Levels.selected) and Music.stream != null:
		var out: Dictionary = Music.data.duplicate(true)
		for sec: Dictionary in out.get("sections", []):
			var cues: Dictionary = sec.get("cues", {})
			for lid in cues.keys():
				if cues[lid].is_empty():
					cues.erase(lid)
		err = Music.write(Music.path_for(Levels.selected), out)
		saved += " and " + Music.path_for(Levels.selected).get_file()
	dirty = err != OK
	_status.text = ("Saved " + saved) if err == OK else ("Save failed: " + error_string(err))


func _input(event: InputEvent) -> void:
	# 面板开着时 Tab 会被输入框拿去切焦点，所以在这里先接住
	var key := event as InputEventKey
	if _panel.visible and key and key.pressed and not key.echo and key.physical_keycode == KEY_TAB:
		main.toggle_editor()
		get_viewport().set_input_as_handled()
