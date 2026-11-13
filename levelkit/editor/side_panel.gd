class_name SidePanel
extends PanelContainer
## Left panel: the palette of entity types (from Registry) and the
## inspector for the selected entity. Both are built from data, so a new
## Registry type or prop shows up here with no UI code.

var doc: LevelDoc
var stage: StageView

var _palette := VBoxContainer.new()
var _inspector := VBoxContainer.new()
var _tool_buttons := {}


func setup(d: LevelDoc, s: StageView) -> void:
	doc = d
	stage = s
	custom_minimum_size.x = 270
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := UiKit.padded(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(box.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.header(box, "Place")
	box.add_child(_palette)
	UiKit.hint(box, "Pick a type, click the world. Esc = select tool.")
	box.add_child(HSeparator.new())
	box.add_child(_inspector)
	_build_palette()
	stage.selection_changed.connect(func(_e: Dictionary) -> void: rebuild_inspector())
	rebuild_inspector()


func _build_palette() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	_palette.add_child(grid)
	var group := ButtonGroup.new()
	for type: String in [""] + Registry.order:
		var b := Button.new()
		b.text = "Select" if type == "" else Registry.get_def(type).label
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = type == stage.tool
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if type != "":
			b.add_theme_color_override("font_color", Registry.get_def(type).color)
		b.pressed.connect(func() -> void: set_tool(type))
		grid.add_child(b)
		_tool_buttons[type] = b
	UiKit.no_focus(grid)


func set_tool(type: String) -> void:
	stage.tool = type
	if _tool_buttons.has(type):
		_tool_buttons[type].button_pressed = true


func rebuild_inspector() -> void:
	UiKit.clear(_inspector)
	var e := stage.selected
	if e.is_empty():
		UiKit.header(_inspector, "Inspector")
		UiKit.hint(_inspector, "Nothing selected.")
		return
	var def := Registry.get_def(e.type)
	UiKit.header(_inspector, def.label)
	var begin := doc.checkpoint
	var pos_specs: Array[Dictionary] = [
		{key = "x", label = "X", default = 0.0, min = -2000.0, max = 40000.0, step = 1.0},
		{key = "y", label = "Y", default = 0.0, min = -2000.0, max = 2000.0, step = 1.0},
		{key = "rot", label = "Rotation", default = 0.0, min = -180.0, max = 180.0, step = 1.0},
	]
	UiKit.params(_inspector, pos_specs, e, begin)
	var lvl := doc.level
	UiKit.hint(_inspector, "beat %.2f" % lvl.x_to_beat(float(e.x)))
	var specs: Array[Dictionary] = []
	for p: Dictionary in def.props:
		specs.append(p)
	if not specs.is_empty():
		_inspector.add_child(HSeparator.new())
		UiKit.params(_inspector, specs, e.props, begin)
	var row := UiKit.row(_inspector)
	UiKit.button(row, "Duplicate", stage.duplicate_selected, "Ctrl/Cmd+D")
	UiKit.button(row, "Delete", stage.delete_selected, "Delete")
	UiKit.no_focus(_inspector)
