@tool
extends Node2D
## 运行菜单时的显示桥接。3D 美术直接编辑 scenes/menu_disc_3d.tscn；
## 本脚本只把原菜单的 Tween 和选中状态传给该场景，不生成美术节点。

@export var disc_controller: Node2D
@export var cat_arm_controller: Node2D
@export var cat_head_controller: Node2D
@onready var _stage: Node3D = $View/Viewport/Stage
@onready var _record: Node3D = $View/Viewport/Stage/Record
@onready var _labels: Node3D = $View/Viewport/Stage/Labels

var _items: Array[Dictionary] = []
var _record_rest := Transform3D.IDENTITY
var _labels_rest := Transform3D.IDENTITY


func _ready() -> void:
	_stage.get_node("Cat").bind_controllers(cat_arm_controller, cat_head_controller)
	_record_rest = _record.transform
	_labels_rest = _labels.transform
	if not is_instance_valid(disc_controller):
		return
	var index := 0
	for sector in disc_controller.get_children():
		if not sector is Node2D or not sector.name.begins_with("Sector"):
			continue
		index += 1
		var anchor := _labels.get_node("Item%d/Anchor" % index)
		var title := anchor.get_node("Title") as Label3D
		var sub := anchor.get_node("Sub") as Label3D
		_items.append({
			"sector": sector,
			"title": title,
			"sub": sub,
			"title_color": title.modulate,
			"sub_color": sub.modulate,
		})
	_sync_visuals()


func _process(_delta: float) -> void:
	if is_instance_valid(disc_controller) and is_instance_valid(_record):
		_sync_visuals()


func _sync_visuals() -> void:
	# 直接读取原来的 Tween 转角，保留每格角度、回弹和开始时整圈加速。
	_record.transform = _record_rest.rotated_local(Vector3.UP, disc_controller.rotation)
	_labels.transform = _labels_rest.rotated_local(Vector3.UP, disc_controller.rotation)
	for item in _items:
		item.title.modulate = item.title_color * item.sector.modulate
		item.sub.modulate = item.sub_color * item.sector.modulate
