class_name SpinCat
extends Node2D
## 转圈猫：按一下快速转一圈，按住一直转，松手立刻停下。
## 画面用猫 meme 的序列帧（默认 oiia）：平时停在站着的那一帧，转的时候播「转圈」那一段帧。
## 默认自己听按键；也可以关掉 listen_input，由段落脚本调用 spin() / set_held()。
## 测试用，只在本机 _sandbox 里，不进仓库。

signal spin_started
signal spin_finished

## MemeLib.DATA 里的名字
@export var meme_key := "oiia"
## 显示高度（像素）
@export var height := 260.0

@export_group("帧")
## 平时停在哪一帧
@export var idle_frame := 0
## 「转圈」从哪一帧到哪一帧（oiia：0~13 站着，14~31 在转）
@export var spin_first_frame := 14
@export var spin_last_frame := 31
## 单点：转一圈（把转圈帧播一遍）用几秒
@export_range(0.05, 3.0) var spin_time := 0.225
## 按住：第一圈之后每一圈用几秒
@export_range(0.05, 3.0) var hold_spin_time := 0.45

@export_group("输入")
@export var listen_input := true
## 项目里的打鼓键（Judge 运行时创建）。这个键位不存在时（比如单独测试）改听 fallback_key
@export var action := &"hit"
@export var fallback_key: Key = KEY_SPACE
## 按住时一直转
@export var hold_to_loop := true

@export_group("弹一下")
## 每次按下猫弹大一下
@export var pop_scale := 1.12
@export var pop_time := 0.12
## 按住转、松手停下时猫轻轻弹一下（1 = 不弹）
@export var stop_pop_scale := 1.05

var _cat: MemeSprite
var _spinning := false
## 第一圈转完后还按着 = 进入「按住一直转」，这时一松手就停
var _looping := false
var _t := 0.0
var _held := false
var _pop_tween: Tween


func _ready() -> void:
	_cat = MemeSprite.create(meme_key, height)
	_cat.mode = MemeSprite.Mode.MANUAL
	_cat.idle_frame = idle_frame
	_cat.frame = idle_frame
	add_child(_cat)


## 转一圈。正在转的时候再调用，会从头再转一圈（每一下都看得见）
func spin() -> void:
	_spinning = true
	_looping = false
	_t = 0.0
	spin_started.emit()
	_pop(pop_scale)


## 由外部控制「按住」状态（listen_input 关掉时用）
func set_held(held: bool) -> void:
	_held = held


func _input(event: InputEvent) -> void:
	if listen_input and _is_press(event):
		spin()


func _process(delta: float) -> void:
	if listen_input:
		_held = _is_input_held()
	if not _spinning:
		return
	if _looping and not _held:
		_stop()
		_pop(stop_pop_scale)
		return
	_t += delta
	if not _looping and _t >= spin_time:
		if hold_to_loop and _held:
			_looping = true
			_t -= spin_time
		else:
			_stop()
			return
	if _looping:
		_t = fmod(_t, hold_spin_time)
	var dur := hold_spin_time if _looping else spin_time
	var n := spin_last_frame - spin_first_frame + 1
	_cat.frame = spin_first_frame + mini(int(_t / dur * n), n - 1)


func _stop() -> void:
	_spinning = false
	_looping = false
	_cat.frame = idle_frame
	spin_finished.emit()


func _pop(amount: float) -> void:
	if _pop_tween:
		_pop_tween.kill()
	scale = Vector2.ONE * amount
	_pop_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(self, "scale", Vector2.ONE, pop_time)


func _is_press(event: InputEvent) -> bool:
	if InputMap.has_action(action):
		return event.is_action_pressed(action)
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.physical_keycode == fallback_key


func _is_input_held() -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	return Input.is_physical_key_pressed(fallback_key)
