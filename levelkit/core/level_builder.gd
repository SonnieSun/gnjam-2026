class_name LevelBuilder
## Turns a level's entities into real nodes for the GAME (the editor only
## draws placeholders). This is the bridge from the tool to the jam game:
##
##   var level := LevelData.load_file("res://levels/stage1.json")
##   LevelBuilder.build(level, $World)
##
## Per entity: instance Registry's `scene` (or a coloured placeholder box),
## place it, set every prop that the node has a property for, then call
## node.setup(props) if it exists. Each node gets meta "entity" = its data.


static func build(level: LevelData, parent: Node) -> Array[Node]:
	var out: Array[Node] = []
	for e in level.entities:
		var node := spawn(e)
		parent.add_child(node)
		out.append(node)
	return out


static func spawn(e: Dictionary) -> Node:
	var def := Registry.get_def(e.type)
	var node: Node
	var scene_path: String = def.get("scene", "")
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		node = (load(scene_path) as PackedScene).instantiate()
	else:
		node = placeholder(e)
	node.name = "%s_%d" % [e.type, node.get_instance_id()]
	if node is Node2D:
		node.position = LevelData.entity_pos(e)
		node.rotation_degrees = float(e.rot)
	var props: Dictionary = e.props
	for key: String in props:
		if key in node:
			node.set(key, props[key])
	if node.has_method("setup"):
		node.setup(props)
	node.set_meta("entity", e)
	return node


## A centred coloured box the size Registry gives the entity.
static func placeholder(e: Dictionary) -> Node2D:
	var root := Node2D.new()
	var box := ColorRect.new()
	var s := Registry.size_of(e)
	box.size = s
	box.position = -s / 2.0
	box.color = Registry.get_def(e.type).get("color", Color.WHITE)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	return root
