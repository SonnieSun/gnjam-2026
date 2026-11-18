extends CanvasLayer
## 全屏 retro 滤镜测试（autoload 名：RetroScreen）。照 runway-tm-sequel 的 era 输出：
## 整个画面（3D、2D、HUD、菜单）变成约 480 线的方像素，再切色深（可选 JPEG 压缩感）。
## shader 在 assets/shaders/retro/retro_screen.gdshader，直接读屏幕，不用改任何关卡。
##
## 只在 debug 版本里能开：F4 开 / 关，F5 换预设（四个预设和 runway 一样）。
## 和 C 键的 Y2K 风格（scripts/fx/y2k_style.gd，只管 3D 小关）是两回事，可以叠着开，但会过两遍。
##
## 原生像素（2026-11-19 试，默认开）：整帧按 NATIVE_LINES 线取样，一个像素 = 整数个窗口像素、只取它中心那一点（不混色），
## 看起来就像游戏原生跑在 360p（960x720 的窗口里是 480x360）。界面和关卡的坐标还是 960x720，什么都不用改。
## 开着的时候上面那几个 era 预设也按 360 线。
## 开不开是玩家设置（Settings.native_pixels，设置面板里的 PIXELS，存盘）；debug 版本里 F3 也能切（一样会存）。

const SHADER := preload("res://assets/shaders/retro/retro_screen.gdshader")
## 画面接近多少线（一个 era 像素取整数个窗口像素，所以 720p 窗口是 360 线、1080p 是 540 线）
const LINES := 480.0
const NATIVE_LINES := 360.0
const PRESETS := [
	{"name": "16-bit VGA (RGB565, dither)", "jpeg": false, "bits": Vector3(5, 6, 5), "dither": 1.0},
	{"name": "JPEG q35, 4:2:0, 16-bit", "jpeg": true, "quality": 35.0, "bits": Vector3(5, 6, 5), "dither": 0.0},
	{"name": "JPEG q15, 4:2:0, 4096 colours", "jpeg": true, "quality": 15.0, "bits": Vector3(4, 4, 4), "dither": 0.6},
	{"name": "256 colours (RGB332, dither)", "jpeg": false, "bits": Vector3(3, 3, 2), "dither": 1.0},
]

var enabled := false
var preset := 0
var native := true

var _plain: ColorRect   # mode 0
var _encode: ColorRect  # mode 1
var _copy: BackBufferCopy
var _decode: ColorRect  # mode 2
var _label: Label


func _ready() -> void:
	layer = 128  # 盖在所有东西上面（设置面板 50、字幕 120）
	process_mode = Node.PROCESS_MODE_ALWAYS
	_plain = _pass(0)
	_encode = _pass(1)
	_copy = BackBufferCopy.new()
	_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_copy)
	_decode = _pass(2)
	# 预设名字单独一层，不被滤镜过
	var label_layer := CanvasLayer.new()
	label_layer.layer = 129
	add_child(label_layer)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.modulate.a = 0.0
	label_layer.add_child(_label)
	native = Settings.native_pixels
	get_viewport().size_changed.connect(_apply)
	_apply()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not OS.is_debug_build():
		return
	if key.physical_keycode == KEY_F3:
		Settings.set_native_pixels(not native)
		_flash("NATIVE 360P: %s  (F3)" % ("ON" if native else "OFF"))
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_F4:
		set_enabled(not enabled)
		_flash("RETRO: %s" % (PRESETS[preset].name if enabled else "OFF"))
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_F5:
		set_preset(preset + 1)
		if not enabled:
			set_enabled(true)
		_flash("RETRO: %s  (F5)" % PRESETS[preset].name)
		get_viewport().set_input_as_handled()


func set_enabled(on: bool) -> void:
	enabled = on
	_apply()


func set_native(on: bool) -> void:
	native = on
	_apply()


func set_preset(index: int) -> void:
	preset = posmod(index, PRESETS.size())
	_apply()


## 一个 era 像素是几个窗口像素
func pixel_scale() -> int:
	var h := float(get_viewport().get_visible_rect().size.y)
	var win := get_tree().root.size
	if win.y > 0:
		h = float(win.y)
	return maxi(1, roundi(h / (NATIVE_LINES if native else LINES)))


func _apply() -> void:
	var p: Dictionary = PRESETS[preset]
	var jpeg: bool = p.jpeg
	_plain.visible = (enabled and not jpeg) or (native and not enabled)
	_encode.visible = enabled and jpeg
	_copy.visible = enabled and jpeg
	_decode.visible = enabled and jpeg
	for r: ColorRect in [_plain, _encode, _decode]:
		var m := r.material as ShaderMaterial
		m.set_shader_parameter("px", float(pixel_scale()))
		# 只开原生像素：不切色深、不抖动，只取样
		m.set_shader_parameter("bits", p.bits if enabled else Vector3(8, 8, 8))
		m.set_shader_parameter("dither", p.dither if enabled else 0.0)
		m.set_shader_parameter("quality", p.get("quality", 50.0))


func _pass(mode: int) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("mode", mode)
	r.material = m
	add_child(r)
	return r


func _flash(text: String) -> void:
	_label.text = text
	var t := create_tween()
	t.tween_property(_label, "modulate:a", 1.0, 0.1)
	t.tween_interval(1.5)
	t.tween_property(_label, "modulate:a", 0.0, 0.5)
