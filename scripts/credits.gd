extends Control
## 片尾字幕：星空背景上，字幕像星球大战那样从画面底边往远处滚走；名单后面跟着一张图（猫猫），和字幕在同一块平面上一起滚，
## 图滚到画面中间时停住。
## 字幕的内容、字体、颜色、图，都摆在 scenes/credits.tscn 里（TextView/Text 下面的那些 Label 和最后的 Photo），
## 这里只负责滚和淡入淡出。想加一行字：在 TextView/Text 里复制一个 Label 改字就行。
## 滚完停几秒自动回主菜单。按住打击键（空格等）快进；滚完之后按一下马上回主菜单；任何时候按 Esc 直接回主菜单。

## 字幕从冒出来到全部滚进远处用几秒
@export var crawl_seconds := 24.0
## 开头先黑着等几秒再开始滚
@export var start_delay := 0.8
## 按住打击键时快几倍
@export var fast_forward := 4.0
## 滚到多少停住（1 = 最下面的图刚好整张冒出底边；再大 = 它往远处走得更远、更小）
@export var scroll_end := 1.06
## 滚完之后停几秒自动回主菜单（0 = 一直停着，等玩家按键）
@export var hold_seconds := 5.0

@onready var _crawl: TextureRect = %Crawl
@onready var _text_view: SubViewport = %TextView

var _time := 0.0
var _scroll := 0.0
var _done_for := 0.0
var _leaving := false


func _ready() -> void:
	Judge.ensure_input()
	_crawl.texture = _text_view.get_texture()
	_set_scroll(0.0)
	# 从黑里淡进来
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)


func _process(delta: float) -> void:
	_time += delta
	if _time < start_delay:
		return
	var speed := fast_forward if Input.is_action_pressed(Judge.HIT_ACTION) and _scroll < scroll_end else 1.0
	_scroll = minf(_scroll + delta * speed * scroll_end / maxf(crawl_seconds, 0.1), scroll_end)
	_set_scroll(_scroll)
	if _scroll >= scroll_end:
		_done_for += delta
		if hold_seconds > 0.0 and _done_for >= hold_seconds:
			_leave()


func _set_scroll(v: float) -> void:
	var mat := _crawl.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter(&"scroll", v)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		_leave()
	elif event.is_action_pressed(Judge.HIT_ACTION) and _scroll >= scroll_end and _done_for > 0.3:
		_leave()


## 淡出，回主菜单
func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	Conductor.stop()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.5)
	t.tween_callback(get_tree().change_scene_to_file.bind(Levels.MENU_SCENE))
