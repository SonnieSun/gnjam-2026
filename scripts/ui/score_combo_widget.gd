@tool
class_name ScoreComboWidget
extends Control
## Outlined-jelly HUD. Values/colors update synchronously; stage rises pop once.
enum Kind { SCORE, COMBO }
const PALETTE := [Color("fff0a6"),Color("ffd21a"),Color("ff872d"),Color("ff71b8"),Color("f44555"),Color.WHITE]
const FONT := preload("res://assets/ui/score_combo/jelly/digits.fnt")
const SCORE_TITLE := preload("res://assets/ui/score_combo/jelly/score_title.png")
const COMBO_TITLE := preload("res://assets/ui/score_combo/jelly/combo_title.png")
const STAR := preload("res://assets/ui/score_combo/jelly/star.png")
const SHADER := preload("res://assets/ui/score_combo/jelly_palette.gdshader")
@export var kind: Kind = Kind.SCORE
var value := 0
var color_stage := 0
var number: Label
var title: TextureRect
var crest: TextureRect
var palette_material: ShaderMaterial
var visual: Control
var stage_jump_count := 0
var _has_value := false
var _stage_tween: Tween

static func stage_for(amount: int, widget_kind: Kind) -> int:
	var interval := 2000 if widget_kind == Kind.SCORE else 10
	return clampi(floori(float(maxi(amount,0)) / interval),0,5)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	FONT.set_fixed_size_scale_mode(TextServer.FIXED_SIZE_SCALE_ENABLED)
	palette_material = ShaderMaterial.new()
	palette_material.shader = SHADER
	visual = Control.new()
	visual.name = "Visual"
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(visual)
	title = TextureRect.new()
	title.name = "Title"
	title.texture = SCORE_TITLE if kind == Kind.SCORE else COMBO_TITLE
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_SCALE
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.material = palette_material
	visual.add_child(title)
	number = Label.new()
	number.name = "Number"
	number.add_theme_font_override("font",FONT)
	number.add_theme_color_override("font_color",Color.WHITE)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.material = palette_material
	visual.add_child(number)
	crest = TextureRect.new()
	crest.name = "Star"
	crest.texture = STAR
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crest.material = palette_material
	visual.add_child(crest)
	item_rect_changed.connect(_layout)
	set_value(value)

func set_value(amount: int) -> void:
	var old_stage := color_stage
	var jump := _has_value and stage_for(amount,kind) > old_stage
	value = maxi(amount,0)
	color_stage = stage_for(value,kind)
	if number == null:
		return
	# Text and color are committed before any purely visual feedback.
	number.text = str(value)
	palette_material.set_shader_parameter("stage_color",PALETTE[color_stage])
	palette_material.set_shader_parameter("rainbow",color_stage == 5)
	visible = kind == Kind.SCORE or value > 0
	_layout()
	_has_value = true
	if value == 0 or color_stage < old_stage:
		_reset_feedback()
	elif jump and not Engine.is_editor_hint():
		_jump_stage()

func _reset_feedback() -> void:
	if _stage_tween:
		_stage_tween.kill()
	if visual:
		visual.scale = Vector2.ONE
		visual.position = Vector2.ZERO

func _jump_stage() -> void:
	_reset_feedback()
	stage_jump_count += 1
	_stage_tween = create_tween()
	_stage_tween.tween_property(visual,"scale",Vector2.ONE*1.38,0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_stage_tween.parallel().tween_property(visual,"position",Vector2(0,-10),0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_stage_tween.tween_property(visual,"scale",Vector2.ONE,0.32).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_stage_tween.parallel().tween_property(visual,"position",Vector2.ZERO,0.32).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _layout() -> void:
	if number == null:
		return
	var is_score := kind == Kind.SCORE
	var font_size := 84
	var max_width := size.x - (12.0 if is_score else 30.0)
	var width := FONT.get_string_size(number.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	if width > max_width:
		font_size = maxi(12,int(font_size*max_width/width))
		width = FONT.get_string_size(number.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	number.add_theme_font_size_override("font_size",font_size)
	var x := 3.0 if is_score else size.x-width-22.0
	number.position = Vector2(x,0)
	number.size = Vector2(width,68.0)
	title.size = Vector2(150,36) if is_score else Vector2(108,19)
	title.position = Vector2(maxf(0.0,x+(width-150.0)*0.5),72) if is_score else Vector2(x+(width-108.0)*0.5+3.0,72)
	# Keep left/right HUD edges fixed while the component grows inward.
	visual.pivot_offset = Vector2(0,0) if is_score else Vector2(size.x,0)
	crest.visible = not is_score
	crest.size = Vector2(18,18)
	crest.position = Vector2(size.x-20,-5)
	# Map a static rainbow across this component, including text and digits.
	var rect := get_global_rect()
	var canvas_scale := get_viewport().get_stretch_transform().get_scale().x
	var ink_left := minf(title.position.x,number.position.x)
	var ink_right := maxf(title.position.x+title.size.x,number.position.x+width+9.0*font_size/64.0)
	palette_material.set_shader_parameter("rainbow_origin",(rect.position.x+ink_left)*canvas_scale)
	palette_material.set_shader_parameter("rainbow_span",(ink_right-ink_left)*canvas_scale)
