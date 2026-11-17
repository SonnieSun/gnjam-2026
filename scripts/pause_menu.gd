extends CanvasLayer
## 暂停转盘：游戏里按 Esc 把选关转盘（scenes/menu.tscn）叠在游戏上面，同时暂停游戏；再按 Esc 关掉、继续。
## 在转盘上选一关确认（空格 / 回车 / 点击），就从那一关开头开始（转盘自己的逻辑，没改它）。
## 从转盘选进去的关不算“一路连着玩”，打完直接出结算；选第 1 关则重新开始一路连着玩。
## main.gd 在 _ready 里挂上这个节点。

## 叠在游戏上面多高的层
@export var overlay_layer := 100

@export_group("开场动画")
## 黑胶从下面升上来用多久（秒）
@export var rise_time := 0.55
## 黑胶一开始在多低（像素，按 960×720 的菜单画面）
@export var rise_distance := 720.0
## 升上来时黑胶多转多少（圈），落定时正好停在当前选中的那格
@export var rise_spin_turns := 0.35
## 左右箭头和黑胶速度不一样，做视差：箭头起点更低多少倍、用时多多少倍
@export var arrow_distance_scale := 1.35
@export var arrow_time_scale := 1.45
## 猫从多高掉下来（3D 单位，往上）、掉多久
@export var cat_drop_height := 7.0
@export var cat_drop_time := 0.38
## 黑胶升到多少（0~1）时猫开始掉
@export_range(0.0, 1.0) var cat_drop_start := 0.55
## 猫落地压扁多少
@export var cat_land_squash := 0.18
## 聚光灯从多高降下来（3D 单位）、降多久、黑胶升到多少（0~1）时开始降
@export var spot_drop_height := 10.0
@export var spot_drop_time := 0.4
@export_range(0.0, 1.0) var spot_drop_start := 0.35
## 背景渐显用多久
@export var background_fade_time := 0.3

var _menu: Node
## 转盘场景读过一次就留着，再开不用重读
var _menu_scene: PackedScene
var _intro: Tween
var _closing := false
## 开场时记下的节点和它们在场景里的原位，退场倒放用
var _parts := {}


func _ready() -> void:
	layer = overlay_layer
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if _closing:
		return  # 退场动画还在放
	if _menu:
		close()
	else:
		open()


func open() -> void:
	if _menu_scene == null:
		_menu_scene = load(Levels.MENU_SCENE)
	_menu = _menu_scene.instantiate()
	add_child(_menu)
	# 转盘场景里按钮那层（PLAY / CREDIT / 音量）自己是第 1 层，叠在游戏上时会被画到转盘下面，抬到转盘上面
	var actions := _menu.get_node_or_null("MenuActions") as CanvasLayer
	if actions:
		actions.layer = overlay_layer + 1
	get_tree().paused = true
	# 转盘确认后会切场景；在那之前记下这次是不是从第 1 关开始一路连着玩
	_menu.tree_exiting.connect(_on_menu_leaving)
	_play_intro()


## 找出要动的节点，记下原位
func _collect_parts() -> void:
	var p := {}
	p.disc_view = _menu.get_node_or_null("Disc3D") as Node2D
	p.disc_ctrl = _menu.get_node_or_null("Disc") as Node2D  # 3D 黑胶的转角跟着它
	p.disc_rest = p.disc_view.position if p.disc_view else Vector2.ZERO
	p.disc_rot = p.disc_ctrl.rotation if p.disc_ctrl else 0.0
	p.arrows = []
	p.arrow_rest = []
	for n in ["ArrowLeft", "ArrowRight"]:
		var a := _menu.get_node_or_null(n) as Control
		if a:
			p.arrows.append(a)
			p.arrow_rest.append(a.position)
	p.bg = _menu.get_node_or_null("BackgroundLayer/Background") as CanvasItem
	# 猫和它前爪对准的两个点一起挪，爪子姿势不变形
	p.cat_parts = []
	p.cat_rest = []
	var stage := _menu.get_node_or_null("Disc3D/View/Viewport/Stage") as Node3D
	if stage:
		for n in ["Cat", "ScratchContact", "SupportContact"]:
			var c := stage.get_node_or_null(n) as Node3D
			if c:
				p.cat_parts.append(c)
				p.cat_rest.append(c.position)
	p.cat_scale = p.cat_parts[0].scale if not p.cat_parts.is_empty() else Vector3.ONE
	# 从上往下打的聚光灯（灯 + 看得见的光柱子节点）
	p.spot = stage.get_node_or_null("BeamLight2") as SpotLight3D if stage else null
	p.spot_rest = p.spot.position if p.spot else Vector3.ZERO
	p.spot_energy = p.spot.light_energy if p.spot else 0.0
	_parts = p


## 开场动画：黑胶从下面边转边升上来，左右箭头慢一点升（视差），猫从上面掉下来落到原来的姿势。
## 只动转盘场景里节点的位置 / 转角，结束后都回到场景里摆好的原位；转盘的文件没改。
func _play_intro() -> void:
	_collect_parts()
	# 开场时不让转盘收按键，免得和这里的转角动画打架
	_menu.set_process_unhandled_input(false)
	_intro = create_tween().set_parallel()

	if _parts.bg:
		_parts.bg.modulate.a = 0.0
		_intro.tween_property(_parts.bg, "modulate:a", 1.0, background_fade_time)

	if _parts.disc_view:
		_parts.disc_view.position = _parts.disc_rest + Vector2(0, rise_distance)
		_intro.tween_property(_parts.disc_view, "position", _parts.disc_rest, rise_time) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _parts.disc_ctrl:
		_parts.disc_ctrl.rotation = _parts.disc_rot - rise_spin_turns * TAU
		_intro.tween_property(_parts.disc_ctrl, "rotation", _parts.disc_rot, rise_time * 1.1) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

	for i in _parts.arrows.size():
		var a: Control = _parts.arrows[i]
		a.position = _parts.arrow_rest[i] + Vector2(0, rise_distance * arrow_distance_scale)
		_intro.tween_property(a, "position", _parts.arrow_rest[i], rise_time * arrow_time_scale) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var drop_at := rise_time * cat_drop_start
	var cat_parts: Array = _parts.cat_parts
	for i in cat_parts.size():
		cat_parts[i].position = _parts.cat_rest[i] + Vector3.UP * cat_drop_height
		_intro.tween_property(cat_parts[i], "position", _parts.cat_rest[i], cat_drop_time).set_delay(drop_at) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if not cat_parts.is_empty():
		var cat: Node3D = cat_parts[0]
		cat.visible = false
		_intro.tween_callback(cat.show).set_delay(drop_at)
		# 落地压扁一下再弹回
		var squash: Vector3 = _parts.cat_scale * Vector3(1.0 + cat_land_squash, 1.0 - cat_land_squash, 1.0 + cat_land_squash)
		var land := drop_at + cat_drop_time
		_intro.tween_property(cat, "scale", squash, 0.07).set_delay(land) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_intro.tween_property(cat, "scale", _parts.cat_scale, 0.22).set_delay(land + 0.07) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 聚光灯从上面降下来：黑胶升到一部分时出现，往下滑到原位、慢慢亮起来
	if _parts.spot:
		var spot: SpotLight3D = _parts.spot
		var spot_at := rise_time * spot_drop_start
		spot.visible = false
		spot.position = _parts.spot_rest + Vector3.UP * spot_drop_height
		spot.light_energy = 0.0
		_intro.tween_callback(spot.show).set_delay(spot_at)
		_intro.tween_property(spot, "position", _parts.spot_rest, spot_drop_time).set_delay(spot_at) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_intro.tween_property(spot, "light_energy", _parts.spot_energy, spot_drop_time).set_delay(spot_at)

	_intro.chain().tween_callback(_on_intro_done)


func _on_intro_done() -> void:
	_intro = null
	if is_instance_valid(_menu):
		_menu.set_process_unhandled_input(true)


func close() -> void:
	if _closing:
		return
	if _intro:
		_intro.kill()
		_intro = null
	if not is_instance_valid(_menu) or _parts.is_empty():
		_finish_close()
		return
	_play_outro()


## 退场动画：开场倒着放——猫先蹲一下往上跳走，黑胶边倒转边沉下去，箭头沉得慢一点（视差），背景淡掉。
func _play_outro() -> void:
	_closing = true
	_menu.set_process_unhandled_input(false)
	var t := create_tween().set_parallel()
	_intro = t

	var cat_time := cat_drop_time + 0.08
	var cat_parts: Array = _parts.cat_parts
	if not cat_parts.is_empty():
		var cat: Node3D = cat_parts[0]
		var squash: Vector3 = _parts.cat_scale * Vector3(1.0 + cat_land_squash, 1.0 - cat_land_squash, 1.0 + cat_land_squash)
		t.tween_property(cat, "scale", squash, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(cat, "scale", _parts.cat_scale, 0.1).set_delay(0.08)
		for i in cat_parts.size():
			t.tween_property(cat_parts[i], "position", _parts.cat_rest[i] + Vector3.UP * cat_drop_height, cat_drop_time) \
					.set_delay(0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_callback(cat.hide).set_delay(cat_time)

	# 聚光灯往上收走、变暗
	if _parts.spot:
		var spot: SpotLight3D = _parts.spot
		t.tween_property(spot, "position", _parts.spot_rest + Vector3.UP * spot_drop_height, spot_drop_time) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		t.tween_property(spot, "light_energy", 0.0, spot_drop_time)
		t.tween_callback(spot.hide).set_delay(spot_drop_time)

	var sink_at := cat_time * (1.0 - cat_drop_start)
	if _parts.disc_view:
		t.tween_property(_parts.disc_view, "position", _parts.disc_rest + Vector2(0, rise_distance), rise_time) \
				.set_delay(sink_at).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if _parts.disc_ctrl:
		t.tween_property(_parts.disc_ctrl, "rotation", _parts.disc_rot - rise_spin_turns * TAU, rise_time * 1.1) \
				.set_delay(sink_at).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	for i in _parts.arrows.size():
		t.tween_property(_parts.arrows[i], "position", _parts.arrow_rest[i] + Vector2(0, rise_distance * arrow_distance_scale),
				rise_time * arrow_time_scale).set_delay(sink_at).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if _parts.bg:
		var fade_at := sink_at + rise_time * arrow_time_scale - background_fade_time
		t.tween_property(_parts.bg, "modulate:a", 0.0, background_fade_time).set_delay(maxf(fade_at, 0.0))

	t.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	_closing = false
	_intro = null
	_parts = {}
	if _menu:
		var m := _menu
		_menu = null
		m.queue_free()
	get_tree().paused = false


func _on_menu_leaving() -> void:
	if _menu == null:
		return  # 是 close() 关掉的
	# 转盘选了关、正在切场景：从选的这一关开始一路玩到最后一关，累计成绩从零算（转盘的 start() 也会调一次，重复调没关系）
	preload("res://scripts/main.gd").reset_run()


func _exit_tree() -> void:
	get_tree().paused = false
