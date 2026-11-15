class_name PropArranger
extends PropModule
## 把一样东西变成好多份再摆起来的模块（一圈、一串、绕着转）的公共部分：管"摆的是什么、摆几份"。
## 这是从 Cat Rotator 学来的思路：那边每只猫身上叠几个组件，有的组件把一只变成很多只（Ring、Stream）。
## 这里把组件做成节点：摆的东西可以是一张 meme，也可以是**另一个模块的场景**（item），
## 所以能一层套一层 —— 一圈"会转的 meme"、一串"一圈猫"、一圈"发光转圈猫"。

@export_group("摆什么")
## 摆的东西：一个场景（比如 meme_spinner.tscn、tabby_card.tscn，或者另一个 prop_ring.tscn）。空着就用下面的 meme。
@export var item: PackedScene:
	set(value):
		item = value
		rebuild()
## item 空着时摆的 meme 素材（MemeLib 里的名字）
@export var meme := "popcat":
	set(value):
		meme = value
		rebuild()
## 每一份多高（像素；item 是别的模块时不管这个，用它自己的大小）
@export var item_height := 110.0:
	set(value):
		item_height = value
		rebuild()
## 摆几份
@export_range(1, 64) var count := 8:
	set(value):
		count = value
		rebuild()
## 里面每一份自己要不要也对按键 / 节拍起反应（关掉 = 只有整体在动，比较整齐）
@export var items_react := false:
	set(value):
		items_react = value
		rebuild()

var items: Array[Node2D] = []


func _ready() -> void:
	super()
	rebuild()


func _validate_property(property: Dictionary) -> void:
	if property.name == "meme":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(MemeLib.keys())


## 重新生成每一份（属性改了会自动调）
func rebuild() -> void:
	if not is_inside_tree():
		return
	for it in items:
		it.queue_free()
	items.clear()
	for i in count:
		var node: Node2D
		if item:
			node = item.instantiate() as Node2D
		else:
			var spinner := MemeSpinner.new()
			spinner.meme = meme
			spinner.height = item_height
			node = spinner
		if node == null:
			push_error("PropArranger: item 的根节点要是 Node2D")
			return
		if node is PropModule and not items_react:
			node.react_to_hit = false
			node.react_to_beat = false
		add_child(node)
		items.append(node)
	arrange(0.0)


## 把每一份摆到现在该在的位置（子类写；每帧调）
func arrange(_delta: float) -> void:
	pass


func _process(delta: float) -> void:
	arrange(delta)
