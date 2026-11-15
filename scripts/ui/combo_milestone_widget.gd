@tool
class_name ComboMilestoneWidget
extends Control
## Horizontal jelly COMBO + digits. Independent of the live top-right widget.
const FONT := ScoreComboWidget.FONT
const TITLE := ScoreComboWidget.COMBO_TITLE
const SHADER := preload("res://assets/ui/score_combo/milestone_palette.gdshader")
var value := 0
var color_stage := 0
var number: Label
var word: TextureRect
var content: Control
var palette_material: ShaderMaterial
var _tween: Tween
var opacity := 0.0:
	set(next):
		opacity = clampf(next,0.0,1.0)
		if palette_material:
			palette_material.set_shader_parameter("opacity",opacity)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	FONT.set_fixed_size_scale_mode(TextServer.FIXED_SIZE_SCALE_ENABLED)
	palette_material = ShaderMaterial.new()
	palette_material.shader = SHADER
	content = Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	word = TextureRect.new()
	word.name = "ComboWord"
	var tight_title := AtlasTexture.new()
	tight_title.atlas = TITLE
	tight_title.region = Rect2(TITLE.get_image().get_used_rect())
	word.texture = tight_title
	word.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	word.material = palette_material
	content.add_child(word)
	number = Label.new()
	number.name = "Number"
	number.add_theme_font_override("font",FONT)
	number.add_theme_font_size_override("font_size",64)
	number.add_theme_color_override("font_color",Color.WHITE)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.material = palette_material
	content.add_child(number)
	resized.connect(_layout)
	clear()
	if Engine.is_editor_hint():
		_set_combo(10)
		opacity = 1.0
		visible = true

func _set_combo(combo: int) -> void:
	value = maxi(combo,0)
	color_stage = ScoreComboWidget.stage_for(value,ScoreComboWidget.Kind.COMBO)
	number.text = str(value)
	palette_material.set_shader_parameter("stage_color",ScoreComboWidget.PALETTE[color_stage])
	palette_material.set_shader_parameter("rainbow",color_stage == 5)
	_layout()

func show_combo(combo: int) -> void:
	if combo <= 0:
		clear()
		return
	if _tween:
		_tween.kill()
	_set_combo(combo)
	visible = true
	opacity = 1.0
	scale = Vector2.ONE * 0.55
	set_process(color_stage == 5)
	_sync_rainbow()
	_tween = create_tween()
	_tween.tween_property(self,"scale",Vector2.ONE*1.12,0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self,"scale",Vector2.ONE,0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(1.0)
	_tween.tween_property(self,"opacity",0.0,0.4)
	_tween.tween_callback(_finish)

func _finish() -> void:
	visible = false
	set_process(false)

func clear() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	opacity = 0.0
	visible = false
	scale = Vector2.ONE
	set_process(false)

func _layout() -> void:
	if number == null:
		return
	var advance := FONT.get_string_size(number.text,HORIZONTAL_ALIGNMENT_LEFT,-1,64).x
	# The baked digit body is ~52px high. Word body is ~39px (75%).
	word.size = Vector2(248,40.5)
	word.position = Vector2(0,5.75)
	number.position = Vector2(256,0)
	number.size = Vector2(advance+9,68)
	var width := 256.0+advance+9.0
	var fit := minf(1.0,size.x/maxf(width,1.0))
	content.size = Vector2(width,52)
	content.scale = Vector2.ONE*fit
	content.position = Vector2(size.x-width*fit,(size.y-52.0*fit)*0.5)
	pivot_offset = size*Vector2(1.0,0.5)
	_sync_rainbow()

func _process(_delta: float) -> void:
	_sync_rainbow()

func _sync_rainbow() -> void:
	if palette_material == null or content == null:
		return
	var rect := content.get_global_rect()
	var stretch := get_viewport().get_stretch_transform().get_scale().x
	palette_material.set_shader_parameter("rainbow_origin",rect.position.x*stretch)
	palette_material.set_shader_parameter("rainbow_span",rect.size.x*stretch)
