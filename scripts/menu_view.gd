@tool
extends Node2D
## 运行菜单时的显示桥接。3D 美术直接编辑 scenes/menu_disc_3d.tscn；
## 本脚本只把原菜单的 Tween 和选中状态传给该场景；唯一生成的是关名牌：格子数变了时照 Item1 复制（见 _match_items）。

@export var disc_controller: Node2D
@export var cat_arm_controller: Node2D
@export var cat_head_controller: Node2D
## Disc title and stage count sizes; editable on Menu/Disc3D.
@export var title_font_size := 190
@export var stage_font_size := 100
@export var title_max_width := 1100.0
@onready var _stage: Node3D = $View/Viewport/Stage
@onready var _record: Node3D = $View/Viewport/Stage/Record
@onready var _labels: Node3D = $View/Viewport/Stage/Labels

var _items: Array[Dictionary] = []
var _record_rest := Transform3D.IDENTITY
var _labels_rest := Transform3D.IDENTITY
var _authored_fov := -1.0
var _authored_keep := Camera3D.KEEP_WIDTH


func _ready() -> void:
	_stage.get_node("Cat").bind_controllers(cat_arm_controller, cat_head_controller)
	_record_rest = _record.transform
	_labels_rest = _labels.transform
	if not is_instance_valid(disc_controller):
		return
	if not Engine.is_editor_hint():
		_match_items()
	var index := 0
	for sector in disc_controller.get_children():
		if not sector is Node2D or not sector.name.begins_with("Sector"):
			continue
		index += 1
		var anchor := _labels.get_node("Item%d/Anchor" % index)
		var title := anchor.get_node("Title") as Label3D
		var sub := anchor.get_node("Sub") as Label3D
		# 关名和小关数从 levels/menu_info.json 读（Levels.info），不读整关文件
		if not Engine.is_editor_hint() and index <= Levels.count():
			var info := Levels.info(index - 1)
			var stages := int(info.get("stages", 1))
			title.text = String(info.get("title", "")).to_upper() if info.get("title", "") != "" else "LEVEL %d" % index
			sub.text = "%d %s" % [stages, "STAGE" if stages == 1 else "STAGES"]
		# Keep long names within the same disc sector as DISCO.
		title.font_size = title_font_size
		sub.font_size = stage_font_size
		var title_width := title.font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.font_size).x
		if title_width > title_max_width:
			title.font_size = maxi(60, int(title.font_size * title_max_width / title_width))
		_items.append({
			"sector": sector,
			"title": title,
			"sub": sub,
			"title_color": title.modulate,
			"sub_color": sub.modulate,
		})
	_sync_visuals()


## 关名牌（Labels/Item1、Item2……）跟转盘格子一样多：不够就照 Item1 复制，多了就删，再按格子平均转开
## （格子数由 menu.gd 按 levels/ 里的大关数定；Item1 是第一格的摆法，其它格 = 它绕转盘中心转 i 格）
func _match_items() -> void:
	var count := 0
	for sector in disc_controller.get_children():
		if sector is Node2D and sector.name.begins_with("Sector"):
			count += 1
	var first := _labels.get_node_or_null("Item1") as Node3D
	if first == null or count == 0:
		return
	var rest := first.transform
	for i in range(1, maxi(count, _labels.get_child_count())):
		var item := _labels.get_node_or_null("Item%d" % (i + 1)) as Node3D
		if i >= count:
			if item:
				_labels.remove_child(item)
				item.queue_free()
			continue
		if item == null:
			item = first.duplicate() as Node3D
			item.name = "Item%d" % (i + 1)
			_labels.add_child(item)
		item.transform = Transform3D(Basis(Vector3.UP, -i * TAU / count), Vector3.ZERO) * rest


func _process(_delta: float) -> void:
	if is_instance_valid(disc_controller) and is_instance_valid(_record):
		_sync_visuals()
	if not Engine.is_editor_hint():
		_fit_to_window()


## 3D 布景是按 960×720（4:3）摆的。窗口更宽时，3D 画面铺满整个窗口，上下取景不变、两边多露出来，
## 不再是中间一块 4:3、两边一条硬边。窗口更窄（竖屏）时照旧按宽度取景。
func _fit_to_window() -> void:
	var view := $View as SubViewportContainer
	var cam := _stage.get_node_or_null("Camera") as Camera3D
	var win := get_viewport_rect().size
	if view == null or cam == null or win.x <= 0.0 or win.y <= 0.0:
		return
	if _authored_fov < 0.0:
		_authored_fov = cam.fov
		_authored_keep = cam.keep_aspect
	view.global_position = Vector2.ZERO
	if view.size != win:
		view.size = win
	var base := Vector2(960.0, 720.0)
	if win.x / win.y > base.x / base.y and _authored_keep == Camera3D.KEEP_WIDTH:
		# 原来按宽度给的视角，换算成同样的上下视角
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_authored_fov) / 2.0) * base.y / base.x))
	else:
		cam.keep_aspect = _authored_keep
		cam.fov = _authored_fov


func _sync_visuals() -> void:
	# 直接读取原来的 Tween 转角，保留每格角度、回弹和开始时整圈加速。
	_record.transform = _record_rest.rotated_local(Vector3.UP, disc_controller.rotation)
	_labels.transform = _labels_rest.rotated_local(Vector3.UP, disc_controller.rotation)
	for item in _items:
		item.title.modulate = item.title_color * item.sector.modulate
		item.sub.modulate = item.sub_color * item.sector.modulate
