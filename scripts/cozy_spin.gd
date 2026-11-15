extends Control
## 温馨开头被按破的那一下：屏幕中间蹦出一只发光的虎斑猫（stages/shared/tabby_cat 的 TabbySpinCat），
## 全速转起来，转到第 1 关的第一拍，放大冲出去消失。main.gd 的 _cozy_break 加它，seconds = 到第一拍还有几秒。

const CAT := preload("res://stages/shared/tabby_cat/tabby_spin_cat.tscn")

## 猫在屏幕上多高（占屏幕高度的比例）
@export var height := 0.8
## 用哪种毛色、哪种外光（-1 = 随机）
@export var coat := -1
@export var glow_color := 1
## 猫身上多亮（0 = 原来的毛色，1 = 整只发白）
@export_range(0.0, 1.0) var glow := 0.35
var seconds := 1.5

var _cat: TabbySpinCat
var _pic: TextureRect
var _push := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 720)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.7)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0.0, 0.75, 3.4)
	cam.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	vp.add_child(cam)
	_cat = CAT.instantiate() as TabbySpinCat
	_cat.listen_input = false
	_cat.ensure_scene_glow = false
	_cat.coat_index = coat
	_cat.glow_color_index = glow_color
	vp.add_child(_cat)
	_cat.set_glow(glow)

	_pic = TextureRect.new()
	_pic.texture = vp.get_texture()
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side := size.y * height
	_pic.size = Vector2(side, side)
	_pic.position = (size - _pic.size) / 2.0
	_pic.pivot_offset = _pic.size / 2.0
	add_child(_pic)

	# 蹦出来 → 转 → 最后一点时间放大冲出去
	_pic.scale = Vector2.ONE * 0.2
	var out := minf(0.28, seconds * 0.3)
	var t := create_tween()
	t.tween_property(_pic, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(maxf(seconds - 0.3 - out, 0.0))
	t.tween_property(_pic, "scale", Vector2.ONE * 5.0, out).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_pic, "modulate:a", 0.0, out).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


func _process(delta: float) -> void:
	# 一直给它加转速，保持全速
	_push -= delta
	if _push <= 0.0 and _cat:
		_push = 0.15
		_cat.spin()
