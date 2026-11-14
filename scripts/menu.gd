extends Node2D
## 主菜单：猫在打碟。按 ← / → 猫把转盘往左 / 往右拨一格来换大关，按空格或回车进入。
## 画面上的东西（转盘、每一格、猫、箭头、文字）都摆在 scenes/menu.tscn 里，这里只负责让它们动。
## 大关的顺序和对应的谱面在 scripts/core/levels.gd。

## 场景是按这个画面大小摆的；窗口比例不同时整体居中
const BASE_SIZE := Vector2(1152, 648)

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


func _ready() -> void:
	for child in _disc.get_children():
		if child.name.begins_with("Sector"):
			_sectors.append(child)
	if _sectors.size() != Levels.count():
		push_warning("转盘上有 %d 格，但 levels.gd 里有 %d 个大关，两边要一样多" % [_sectors.size(), Levels.count()])
	_arm_rest = _arm.rotation
	_head_rest = _head.position
	_turns = Levels.selected
	_disc.rotation = _turns * _step()
	_left.pressed.connect(turn.bind(-1))
	_right.pressed.connect(turn.bind(1))
	_refresh()


func _process(_delta: float) -> void:
	position = ((get_viewport_rect().size - BASE_SIZE) / 2.0).round()
	# 猫头跟着节奏轻轻点
	_head.position = _head_rest + Vector2(0.0, sin(Time.get_ticks_msec() / 1000.0 * TAU * 2.0) * 3.0)


## 每一格占多大角度
func _step() -> float:
	return TAU / maxi(_sectors.size(), 1)


## 把转盘拨一格：dir = 1 往右拨（下一关），-1 往左拨（上一关）
func turn(dir: int) -> void:
	if _starting:
		return
	_turns += dir
	Levels.selected = posmod(_turns, Levels.count())
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
	if _starting:
		return
	_starting = true
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
	if event.is_echo():
		return
	if event.is_action_pressed("ui_left"):
		turn(-1)
	elif event.is_action_pressed("ui_right"):
		turn(1)
	elif event.is_action_pressed("ui_accept") or _is_click(event):
		start()


## 鼠标左键点在空白处（没点到箭头）也算确认
func _is_click(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	return mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
