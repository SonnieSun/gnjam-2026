class_name VolumeSlider
extends Control
## 音量滑条：拖动改一条总线的音量（0~1 线性，拖到 0 静音），经 Settings 存盘，下次打开游戏还是这个音量。
## 默认不抢键盘焦点（← → 还是转转盘、空格还是开始）；放进设置面板时打开 keyboard_focus，用 ↑ ↓ 选、← → 调。

## 总线名：Master / Music / SFX（见 scripts/core/settings.gd）
@export var bus_name := "Master"
## 滑条上面的字（CandyGem 字体只有字母、数字和空格）
@export var label_text := "VOLUME"
## 能不能用键盘选中它
@export var keyboard_focus := false

@onready var _slider: HSlider = $Box/Slider
@onready var _label: Label = $Box/Label


func _ready() -> void:
	_label.text = label_text
	_slider.focus_mode = Control.FOCUS_ALL if keyboard_focus else Control.FOCUS_NONE
	_slider.value = Settings.get_volume(StringName(bus_name))
	_slider.value_changed.connect(func(v: float) -> void: Settings.set_volume(StringName(bus_name), v))


## 键盘焦点要落在滑条上（设置面板用来排上下顺序）
func focus_target() -> Control:
	return _slider
