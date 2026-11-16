class_name CountInDisplay
extends CanvasLayer
## 预备拍的屏幕数字：音乐放预备拍（节拍器的四下，Music.count_in()，发 Music.count_in_started）的那一小节里，
## 屏幕中间每拍蹦出一个字，最后一个字之后的下一拍就是第一个音符。
## 放进小关的场景里（或者 main.tscn）就生效，不用接线。字和样子都在检查器里调。

@export var enabled := true
## 四下各显示什么（第几下用第几个；空字符串 = 这一下不显示）
@export var labels := PackedStringArray(["READY", "3", "2", "1"])
@export var font: Font = preload("res://assets/fonts/CandyGem/CandyGem.fnt")
## 数字的字号；比较长的词（READY）自动缩小到 word_scale 倍
@export var font_size := 220
@export_range(0.2, 1.0) var word_scale := 0.5
@export var color := Color(1.0, 1.0, 1.0)
## 屏幕上的位置（0~1，相对整个画面）
@export var screen_position := Vector2(0.5, 0.4)
## 蹦出来时放大到多少倍，再落回 1
@export var pop_scale := 1.6
## 一个字留多久（拍）；1 = 正好留到下一个字出来
@export_range(0.2, 1.0) var hold_beats := 0.85
## 每一下屏幕边上闪一圈的亮度（0 = 不闪）
@export_range(0.0, 1.0) var edge_flash := 0.25

var _from := -100.0   # 预备拍的第一下落在第几拍
var _label: Label
var _edge: ColorRect
var _shown := -1


func _ready() -> void:
	layer = 5
	_edge = ColorRect.new()
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = "shader_type canvas_item;\nuniform float amount = 0.0;\nvoid fragment() {\n\tvec2 d = abs(UV - 0.5) * 2.0;\n\tfloat edge = smoothstep(0.55, 1.0, max(d.x, d.y));\n\tCOLOR = vec4(COLOR.rgb, edge * amount);\n}\n"
	_edge.material = mat
	_edge.visible = false
	add_child(_edge)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	if font:
		_label.add_theme_font_override("font", font)
	add_child(_label)
	Music.count_in_started.connect(start)


## 从第 beat 拍起数（Music.count_in_started 会自动调；别的地方想借用这个显示也可以自己调）
func start(beat: float) -> void:
	_from = beat
	_shown = -1


func _process(_delta: float) -> void:
	var at := Conductor.song_beat - _from
	var i := floori(at)
	if not enabled or not Conductor.playing or at < 0.0 or i >= labels.size():
		_label.visible = false
		_edge.visible = false
		return
	var t := at - i   # 这一下过了多少拍
	if i != _shown:
		_shown = i
		_label.text = labels[i]
		var size := int(font_size * (word_scale if labels[i].length() > 2 else 1.0))
		_label.add_theme_font_size_override("font_size", size)
		_label.reset_size()
		_label.pivot_offset = _label.size / 2.0
	var view := get_viewport().get_visible_rect().size
	_label.position = view * screen_position - _label.size / 2.0
	_label.visible = labels[i] != "" and t < hold_beats
	# 蹦出来：很快从大落回 1；快到下一拍时淡掉
	var pop := pow(clampf(1.0 - t / 0.35, 0.0, 1.0), 2.0)
	_label.scale = Vector2.ONE * lerpf(1.0, pop_scale, pop)
	_label.modulate = Color(color, clampf((hold_beats - t) / 0.2, 0.0, 1.0))
	_edge.visible = edge_flash > 0.0
	_edge.color = color
	(_edge.material as ShaderMaterial).set_shader_parameter("amount", edge_flash * pow(clampf(1.0 - t / 0.5, 0.0, 1.0), 2.0))
