class_name PropKit
extends RefCounted
## 用代码放场景小模块（stages/shared/props 里那些，说明见 prop_module.gd）。手动放就直接把 .tscn 拖进场景。
##
##   PropKit.spawn("ring", self, Vector2(640, 360), {"meme": "oiia", "count": 12, "radius": 260})
##   PropKit.scatter("spinner", self, 10, Rect2(0, 0, 1280, 720), {"meme": "popcat"}, 3)
##   PropKit.ring_of("tabby", self, Vector2(640, 360), 6, 240.0)          # 一圈发光转圈猫
##
## 加了新模块：在 SCENES 里登记一行。

const DIR := "res://stages/shared/props/"
## 名字 -> 场景
const SCENES := {
	"spinner": DIR + "meme_spinner.tscn",   # 一只会转的 meme
	"ring": DIR + "prop_ring.tscn",         # 一圈
	"stream": DIR + "prop_stream.tscn",     # 一串流过去
	"orbit": DIR + "prop_orbit.tscn",       # 跟拍跳着转
	"tabby": DIR + "tabby_card.tscn",       # 发光转圈猫（2D 卡片）
}


## 有哪些模块
static func kinds() -> PackedStringArray:
	return PackedStringArray(SCENES.keys())


## 放一个模块：kind 是 SCENES 里的名字，parent 是挂到哪个节点下，at 是位置（parent 的本地坐标），
## props 是要改的属性（模块脚本里 @export 的那些）。返回放好的节点。
static func spawn(kind: String, parent: Node, at := Vector2.ZERO, props := {}) -> Node2D:
	if not SCENES.has(kind):
		push_error("PropKit: 没有叫 %s 的模块（有：%s）" % [kind, ", ".join(SCENES.keys())])
		return null
	var node := (load(SCENES[kind]) as PackedScene).instantiate() as Node2D
	node.position = at
	if node is PropModule:
		node.configure(props)
	parent.add_child(node)
	return node


## 在一块区域里随机撒 count 个同样的模块（大小、角度各不一样）。seed 相同撒出来的就一样；返回撒出来的节点。
static func scatter(kind: String, parent: Node, count: int, area: Rect2, props := {}, seed := 0,
		size_range := Vector2(0.7, 1.3)) -> Array[Node2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array[Node2D] = []
	for i in count:
		var at := area.position + Vector2(rng.randf() * area.size.x, rng.randf() * area.size.y)
		var node := spawn(kind, parent, at, props)
		if node == null:
			break
		node.scale = Vector2.ONE * rng.randf_range(size_range.x, size_range.y)
		node.rotation = rng.randf_range(-0.3, 0.3)
		out.append(node)
	return out


## 把某种模块摆成一圈（一圈里的每一份是 kind 那个模块）：比如一圈发光转圈猫、一圈"一串猫"。
static func ring_of(kind: String, parent: Node, at: Vector2, count: int, radius: float, props := {}) -> PropRing:
	if not SCENES.has(kind):
		push_error("PropKit: 没有叫 %s 的模块" % kind)
		return null
	var all := {"item": load(SCENES[kind]), "count": count, "radius": radius}
	all.merge(props, true)
	return spawn("ring", parent, at, all) as PropRing
