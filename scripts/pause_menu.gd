extends CanvasLayer
## 暂停转盘：游戏里按 Esc 把选关转盘（scenes/menu.tscn）叠在游戏上面，同时暂停游戏；再按 Esc 关掉、继续。
## 在转盘上选一关确认（空格 / 回车 / 点击），就从那一关开头开始（转盘自己的逻辑，没改它）。
## 从转盘选进去的关不算“一路连着玩”，打完直接出结算；选第 1 关则重新开始一路连着玩。
## main.gd 在 _ready 里挂上这个节点。

## 叠在游戏上面多高的层
@export var overlay_layer := 100

var _menu: Node


func _ready() -> void:
	layer = overlay_layer
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if _menu:
		close()
	else:
		open()


func open() -> void:
	_menu = load(Levels.MENU_SCENE).instantiate()
	add_child(_menu)
	get_tree().paused = true
	# 转盘确认后会切场景；在那之前记下这次是不是从第 1 关开始一路连着玩
	_menu.tree_exiting.connect(_on_menu_leaving)


func close() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
	get_tree().paused = false


func _on_menu_leaving() -> void:
	if _menu == null:
		return  # 是 close() 关掉的
	# 转盘选了关、正在切场景
	var main_script := preload("res://scripts/main.gd")
	Levels.interlude = ""  # 从转盘选关：不在插曲关里了
	main_script.in_run = Levels.selected == 0
	main_script.run_counts = {}
	main_script.run_max_combo = 0
	main_script.run_score = 0
	main_script.run_possible = 0.0


func _exit_tree() -> void:
	get_tree().paused = false
