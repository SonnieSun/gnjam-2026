class_name VolumeSlider
extends Control
## 主音量滑条：拖动改 Master 总线音量（0~1 线性，拖到 0 静音）。
## 不存盘，只在这次运行里有效；打开时读 Master 当前音量，所以菜单关了再开位置不变。
## 不抢键盘焦点：← → 还是转转盘、空格还是开始。

## 总线名
@export var bus_name := "Master"

@onready var _slider: HSlider = $Box/Slider


func _ready() -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		push_warning("找不到音频总线 %s" % bus_name)
		return
	_slider.value = 0.0 if AudioServer.is_bus_mute(bus) else db_to_linear(AudioServer.get_bus_volume_db(bus))
	_slider.value_changed.connect(_on_value_changed.bind(bus))


func _on_value_changed(value: float, bus: int) -> void:
	AudioServer.set_bus_mute(bus, value <= 0.0)
	if value > 0.0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(value))
