class_name PropModule
extends Node2D
## 场景小模块的公共部分。一个"模块"是一个自己会动、自己会对游戏起反应的小东西（转圈的 meme、一圈猫、一串流过去的猫……），
## 拖进任何 2D 场景就能用，不需要别的东西配合；也可以用代码放（见 prop_kit.gd）。
## 发光转圈猫（stages/shared/tabby_cat）就是这样一个模块，这个文件夹里是照同样思路做的 2D 模块。
##
## 模块会对三样东西起反应（每样都能在检查器里关掉）：
##   玩家按键（"hit"，就是打拍子那个键）  -> on_hit()
##   节拍（Conductor.beat，每拍一次）       -> on_beat(第几拍)
##   FEVER 开始 / 结束（Music 的信号）      -> on_fever(开没开)
## 没有 Conductor / Music 的场景（比如单独的测试场景）里也能用，只是收不到后两样。
##
## 做一个新模块：写一个 extends PropModule 的脚本，重写 on_hit / on_beat / on_fever 和 _process，
## 需要 _ready 的话记得先调 super()；再存一个只有根节点 + 脚本的 .tscn，并在 prop_kit.gd 的 SCENES 里登记名字。

@export_group("反应")
## 玩家按键时起反应
@export var react_to_hit := true
## 跟着节拍起反应
@export var react_to_beat := true
## FEVER 的时候更猛
@export var react_to_fever := true

## 现在是不是在 FEVER 里
var fever := false


func _ready() -> void:
	var conductor := get_node_or_null("/root/Conductor")
	if conductor and conductor.has_signal("beat"):
		conductor.beat.connect(_beat)
	var music := get_node_or_null("/root/Music")
	if music and music.has_signal("fever_started"):
		music.fever_started.connect(_fever.bind(true))
		music.fever_ended.connect(_fever.bind(false))
		if music.get("fever"):
			_fever(true)


## 用一个字典一次设好几个属性（代码放模块时用）：configure({"count": 12, "radius": 300})
func configure(props: Dictionary) -> void:
	for key: String in props:
		if key in self:
			set(key, props[key])
		else:
			push_warning("%s 没有 %s 这个属性" % [get_script().resource_path.get_file(), key])


## 玩家按了一下
func on_hit() -> void:
	pass


## 到了第 index 拍
func on_beat(_index: int) -> void:
	pass


## FEVER 开始（on = true）或结束
func on_fever(_on: bool) -> void:
	pass


func _beat(index: int) -> void:
	if react_to_beat and is_visible_in_tree():
		on_beat(index)


func _fever(on: bool) -> void:
	fever = on and react_to_fever
	on_fever(fever)


func _unhandled_input(event: InputEvent) -> void:
	if not react_to_hit or event.is_echo() or not is_visible_in_tree():
		return
	var pressed := false
	if InputMap.has_action("hit"):
		pressed = event.is_action_pressed("hit")
	else:
		var k := event as InputEventKey
		pressed = k != null and k.pressed and k.physical_keycode == KEY_SPACE
	if pressed:
		on_hit()


## 现在的时间，单位是拍：音乐在放就用音乐的拍子，没在放就用墙上的钟（按 120 BPM 算），所以模块不放音乐也会动
func beat_time() -> float:
	var conductor := get_node_or_null("/root/Conductor")
	if conductor and conductor.get("playing"):
		return conductor.song_beat
	return Time.get_ticks_msec() / 500.0
