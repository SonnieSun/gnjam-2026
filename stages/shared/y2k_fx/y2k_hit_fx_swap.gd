extends Node
## 放进某个关卡场景里：这个关卡在场时，把 main 生成的 StarBurst 命中特效原地换成 Y2kBurst。
## 不改 main.gd：只监听 main 的特效层 FxLayer 有新子节点，读 StarBurst 的位置、出发半径、强弱。
## 关卡被删掉时这个节点跟着删掉，其他关卡还是原来的星星。

var _fx_layer: Node2D


func _ready() -> void:
	# 往上找带 fx_layer 的节点（main）
	var n := get_parent()
	while n and not ("fx_layer" in n):
		n = n.get_parent()
	if n == null:
		return
	_fx_layer = n.fx_layer
	_fx_layer.child_entered_tree.connect(_on_fx_added)


func _exit_tree() -> void:
	if _fx_layer and _fx_layer.child_entered_tree.is_connected(_on_fx_added):
		_fx_layer.child_entered_tree.disconnect(_on_fx_added)


func _on_fx_added(node: Node) -> void:
	if node is StarBurst:
		# main 是先 add_child 再设位置和半径，所以等这一帧设完再换
		_swap.call_deferred(node)


func _swap(old: StarBurst) -> void:
	if not is_instance_valid(old) or not is_instance_valid(_fx_layer):
		return
	# StarBurst.create(true) 是 14 颗，create(false) 是 6 颗
	var fx := Y2kBurst.create(old.count > 6)
	_fx_layer.add_child(fx)
	fx.start_radius = old.start_radius * _judge_scale()
	fx.squash = _ring_squash()
	fx.global_position = old.global_position
	old.queue_free()


## 关卡把判定圈画成透视扁椭圆时（迪斯科），粒子也按同样比例压扁扩散。
## 只读：关卡节点下有带 ring_squash() 的子节点（迪斯科的 Stage）就用它，没有就是正圆。
func _ring_squash() -> float:
	var section := get_parent()
	if section == null:
		return 1.0
	for child in section.get_children():
		if child.has_method("ring_squash"):
			return child.ring_squash()
	return 1.0


## 判定圈画大了多少倍（迪斯科的 judge_scale），粒子从同样大的圈上出发
func _judge_scale() -> float:
	var section := get_parent()
	if section and "judge_scale" in section:
		return section.judge_scale
	return 1.0
