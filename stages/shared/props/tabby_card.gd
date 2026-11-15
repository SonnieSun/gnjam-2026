class_name TabbyCard
extends PropModule
## 发光转圈猫的 2D 版：把那只 3D 虎斑猫（stages/shared/tabby_cat）画在一张小画布上，当成一张会动的图来用，
## 所以它能放进任何 2D 场景，也能当一圈 / 一串里的每一只。按一下它就转（越转越亮），和 3D 的一样。
## 每张卡自己一个小 3D 世界（一只猫、一盏灯、一个镜头），所以放很多张会比放很多张图费一些，一屏十来张没问题。

@export_group("猫")
## 显示出来多高（像素）
@export var height := 220.0:
	set(value):
		height = value
		_resize()
## 毛色：-1 随机，0 虎斑，1 三花，2 橘猫，3 奶牛猫
@export_range(-1, 3) var coat := -1
## 外光颜色：-1 随机，0–6 是蓝、粉、紫、青、金、绿、珊瑚红
@export_range(-1, 6) var glow_color := -1
## 平时就亮着多少（0 = 不转不亮；1 = 一直最亮）
@export_range(0.0, 1.0, 0.01) var base_glow := 0.0
## 每拍自己转一下（关掉 = 只在按键时转）
@export var spin_on_beat := false
## 画布的边长（像素）。猫显示得很大时调高，会更清楚也更费
@export var canvas_size := 384

const CAT := preload("res://stages/shared/tabby_cat/tabby_spin_cat.tscn")

var cat: TabbySpinCat
var _viewport: SubViewport
var _sprite: Sprite2D


func _ready() -> void:
	super()
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(canvas_size, canvas_size)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true                      # 自己的小世界：不会和场景里别的 3D 东西混在一起
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.7, 0.85)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 0.8
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var world := WorldEnvironment.new()
	world.environment = env
	_viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	sun.light_energy = 1.2
	_viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0.0, 0.75, 3.4)
	camera.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	_viewport.add_child(camera)
	cat = CAT.instantiate() as TabbySpinCat
	cat.listen_input = false                           # 按键由这张卡转交（小画布里收不到按键）
	cat.ensure_scene_glow = false                      # 光晕用上面这个小世界自己的
	cat.coat_index = coat
	cat.glow_color_index = glow_color
	_viewport.add_child(cat)
	if base_glow > 0.0:
		cat.set_glow(base_glow)
	_sprite = Sprite2D.new()
	_sprite.texture = _viewport.get_texture()
	add_child(_sprite)
	_resize()


func _resize() -> void:
	if _sprite:
		_sprite.scale = Vector2.ONE * (height / float(canvas_size))


## 转一下（外面也可以直接调）
func spin(_push := -1.0) -> void:
	if cat:
		cat.spin()


func on_hit() -> void:
	spin()


func on_beat(_index: int) -> void:
	if spin_on_beat:
		spin()


func on_fever(on: bool) -> void:
	if cat:
		cat.set_glow(1.0 if on else (base_glow if base_glow > 0.0 else -1.0))
		cat.hue_cycle_speed = 0.5 if on else 0.0
