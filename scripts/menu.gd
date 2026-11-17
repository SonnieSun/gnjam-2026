extends Node2D
## 主菜单：猫在打碟。按 ← / → 猫把转盘往左 / 往右拨一格来换大关，按空格或回车进入。
## 画面上的东西（转盘、每一格、猫、箭头、文字）都摆在 scenes/menu.tscn 里，这里只负责让它们动。
## 大关的顺序和对应的谱面在 scripts/core/levels.gd。

## 场景是按这个画面大小摆的；窗口比例不同时整体居中
const BASE_SIZE := Vector2(960, 720)
## 按 O 进延迟校准（设置面板里也有 CALIBRATE）
const CALIBRATE_SCENE := "res://scenes/calibrate.tscn"
## PLAY 字跟着猫点头一起轻轻跳（每秒几下，和猫头一样）
const PULSE_HZ := 2.0

## 转盘转一格用多久（秒）
@export var turn_time := 0.35
## 拨盘时猫的手臂甩多大（弧度）
@export var arm_swing := 0.45
## 没选中的格子暗多少（1 = 不变暗）
@export var dim := 0.55

@onready var _disc: Node2D = %Disc
@onready var _arm: Node2D = %ArmPivot
@onready var _head: Node2D = %Head
@onready var _left: Button = %ArrowLeft
@onready var _right: Button = %ArrowRight
@onready var _turn_sfx: AudioStreamPlayer = $TurnSfx
@onready var _start_sfx: AudioStreamPlayer = $StartSfx

var _sectors: Array[Node2D] = []
var _turns := 0  # 一共往右拨了几格（可以是负数、可以超过一圈），转盘角度 = 它 × 每格角度
var _arm_rest := 0.0
var _head_rest := Vector2.ZERO
var _starting := false
var _disc_tween: Tween
var _arm_tween: Tween
var _settings: SettingsPanel
## 鼠标停在上面的按钮（放大一点）
var _hovered: Control


## 转盘格子数跟 levels/ 里的大关数走：场景里摆的格子不够就照第一格复制，多了就删，再平均分好角度。
## 放在 _enter_tree 里做，这样 3D 转盘（Disc3D，子节点，比这里先 _ready）读格子时已经是对的数目。
func _enter_tree() -> void:
	var disc := get_node("%Disc") as Node2D
	var sectors: Array[Node2D] = []
	for child in disc.get_children():
		if child.name.begins_with("Sector"):
			sectors.append(child)
	if sectors.is_empty():
		return
	while sectors.size() < Levels.count():
		var copy := sectors[0].duplicate() as Node2D
		copy.name = "Sector%d" % (sectors.size() + 1)
		disc.add_child(copy)
		sectors.append(copy)
	while sectors.size() > Levels.count():
		disc.remove_child(sectors[-1])
		sectors.pop_back().queue_free()
	for i in sectors.size():
		sectors[i].rotation = -i * TAU / sectors.size()


func _ready() -> void:
	for child in _disc.get_children():
		if child.name.begins_with("Sector"):
			_sectors.append(child)
	_arm_rest = _arm.rotation
	_head_rest = _head.position
	_turns = Levels.selected
	_disc.rotation = _turns * _step()
	_left.pressed.connect(turn.bind(-1))
	_right.pressed.connect(turn.bind(1))
	$MenuActions/Play.pressed.connect(start)
	$MenuActions/Settings.pressed.connect(open_settings)
	$MenuActions/Credit.gui_input.connect(_on_credit_input)
	for b: Control in [$MenuActions/Play, $MenuActions/Settings, $MenuActions/Credit]:
		b.mouse_entered.connect(func() -> void: _hovered = b)
		b.mouse_exited.connect(func() -> void:
			if _hovered == b:
				_hovered = null)
	_refresh()


## 点右上角的 Credit：盖一层制作名单，按任意键关掉回到菜单（游戏里 Esc 开的菜单也一样，游戏进度不动）
func _on_credit_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not _starting and not _busy():
		get_viewport().set_input_as_handled()
		preload("res://scripts/credits.gd").open_overlay(self)


## 打开设置面板（左上角 SETTINGS、Esc）。面板开着时菜单不响应按键
func open_settings() -> void:
	if _starting or _busy():
		return
	_settings = SettingsPanel.open_overlay(self)
	_start_sfx.pitch_scale = 1.4
	_start_sfx.play()


func _busy() -> bool:
	return is_instance_valid(_settings)


func _process(_delta: float) -> void:
	position = ((get_viewport_rect().size - BASE_SIZE) / 2.0).round()
	# 猫头跟着节奏轻轻点
	var phase := Time.get_ticks_msec() / 1000.0 * TAU * PULSE_HZ
	_head.position = _head_rest + Vector2(0.0, sin(phase) * 3.0)
	# 底下的按钮：PLAY 跟着点头轻轻跳；鼠标停在哪个按钮上它就大一点
	for b: Control in [$MenuActions/Play, $MenuActions/Settings, $MenuActions/Credit]:
		var target := 1.12 if b == _hovered else 1.0
		if b == $MenuActions/Play:
			target += maxf(sin(phase), 0.0) * 0.06
		b.pivot_offset = b.size / 2.0
		b.scale = b.scale.lerp(Vector2.ONE * target, minf(1.0, _delta * 14.0))


## 每一格占多大角度
func _step() -> float:
	return TAU / maxi(_sectors.size(), 1)


## 把转盘拨一格：dir = 1 往右拨（下一关），-1 往左拨（上一关）
func turn(dir: int) -> void:
	if _starting or _busy():
		return
	_turns += dir
	Levels.selected = posmod(_turns, Levels.count())
	Levels.interlude = ""
	_refresh()
	_turn_sfx.pitch_scale = 1.15 if dir > 0 else 0.9
	_turn_sfx.play()

	if _disc_tween:
		_disc_tween.kill()
	_disc_tween = create_tween()
	_disc_tween.tween_property(_disc, "rotation", _turns * _step(), turn_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 手臂往拨的方向甩一下再回来
	if _arm_tween:
		_arm_tween.kill()
	_arm_tween = create_tween()
	_arm_tween.tween_property(_arm, "rotation", _arm_rest - dir * arm_swing, turn_time * 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_arm_tween.tween_property(_arm, "rotation", _arm_rest, turn_time * 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var arrow: Button = _right if dir > 0 else _left
	arrow.pivot_offset = arrow.size / 2.0
	arrow.scale = Vector2.ONE * 1.3
	arrow.create_tween().tween_property(arrow, "scale", Vector2.ONE, 0.2)


## 进入当前选中的大关
func start() -> void:
	if _starting or _busy():
		return
	_starting = true
	# 从选中的这一关开始一路玩到最后一关（前面的跳过），累计成绩从零算
	preload("res://scripts/main.gd").reset_run()
	_start_sfx.play()
	var t := create_tween().set_parallel()
	t.tween_property(_disc, "rotation", _disc.rotation + TAU, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.45)
	t.chain().tween_callback(get_tree().change_scene_to_file.bind(Levels.GAME_SCENE))


func _refresh() -> void:
	for i in _sectors.size():
		var on := i == Levels.selected
		_sectors[i].modulate = Color.WHITE if on else Color(dim, dim, dim)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or _busy():
		return
	if event.is_action_pressed("ui_cancel"):
		open_settings()
		return
	if event.is_action_pressed("ui_left"):
		turn(-1)
	elif event.is_action_pressed("ui_right"):
		turn(1)
	elif event.is_action_pressed("ui_accept") or _is_click(event):
		start()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_O and not _starting:
		get_tree().change_scene_to_file(CALIBRATE_SCENE)


## 鼠标左键点在空白处（没点到箭头）也算确认
func _is_click(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	return mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
