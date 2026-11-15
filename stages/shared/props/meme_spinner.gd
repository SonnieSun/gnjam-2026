class_name MemeSpinner
extends PropModule
## 一只会转的 meme（发光转圈猫的 2D 版）：玩家每按一下就猛转一下，转速带惯性慢慢减下来，连按越转越快；
## 每拍轻轻弹一下；越转越亮（叠一层发光），停下来慢慢暗回去。FEVER 里自己一直慢慢转。
## 拖 meme_spinner.tscn 进场景，在检查器里选素材；也可以单独用，也可以当一圈 / 一串里的每一只（prop_ring、prop_stream）。

@export_group("素材")
## 素材的名字（MemeLib 里的，比如 "popcat"、"oiia"、"cats/bingus"）
@export var meme := "popcat":
	set(value):
		meme = value
		_rebuild()
## 显示出来多高（像素）
@export var height := 160.0:
	set(value):
		height = value
		_rebuild()
@export_group("转圈")
## 每按一下加多少转速（圈 / 秒）
@export var spin_push := 2.0
## 最快转多快（圈 / 秒）
@export var max_spin := 5.0
## 惯性：越大停得越快
@export var friction := 1.8
## 平时自己转多快（圈 / 秒，0 = 不转；负数 = 反着转）
@export var idle_spin := 0.0
## FEVER 里自己转多快（圈 / 秒）
@export var fever_spin := 0.6
@export_group("弹和亮")
## 按键时弹多大、弹回去用几秒
@export var bounce := 1.2
@export var bounce_time := 0.3
## 每拍弹多大（0 = 不弹）
@export_range(0.0, 0.6, 0.01) var beat_bounce := 0.1
## 每转一下亮多少（0–1），停下来多快暗回去（每秒）
@export_range(0.0, 1.0, 0.01) var glow_per_hit := 0.2
@export var glow_fade := 0.5
## 发光的颜色
@export var glow_color := Color(1.0, 0.75, 0.95)

var _sprite: MemeSprite
var _glow_sprite: MemeSprite
var _speed := 0.0
var _glow := 0.0
var _pulse := 0.0
var _tween: Tween
var _base_scale := Vector2.ONE


func _ready() -> void:
	super()
	_rebuild()


func _validate_property(property: Dictionary) -> void:
	if property.name == "meme":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(MemeLib.keys())


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in [_sprite, _glow_sprite]:
		if c:
			c.queue_free()
	_sprite = MemeSprite.create(meme, height)
	_base_scale = _sprite.scale
	add_child(_sprite)
	# 发光：同一张图用加色再叠一层，转得越多越亮
	_glow_sprite = MemeSprite.create(meme, height)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_sprite.material = mat
	_glow_sprite.modulate = Color(glow_color, 0.0)
	add_child(_glow_sprite)


## 转一下（外面也可以直接调，比如一圈里的每一只由圈来叫）
func spin(push := -1.0) -> void:
	_speed = minf(_speed + (spin_push if push < 0.0 else push), max_spin)
	_glow = minf(_glow + glow_per_hit, 1.0)
	if _sprite == null:
		return
	if _tween:
		_tween.kill()
	_pulse = bounce - 1.0
	_tween = create_tween()
	_tween.tween_property(self, "_pulse", 0.0, bounce_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func on_hit() -> void:
	spin()


func on_beat(_index: int) -> void:
	if beat_bounce > 0.0 and _pulse < beat_bounce:
		_pulse = beat_bounce
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "_pulse", 0.0, 0.25).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var turn := _speed + (fever_spin if fever else idle_spin)
	_sprite.rotation = fposmod(_sprite.rotation + turn * TAU * delta, TAU)
	_speed *= exp(-friction * delta)
	if _speed < 0.02:
		_speed = 0.0
	_glow = maxf(_glow - glow_fade * delta, 0.0)
	_sprite.scale = _base_scale * (1.0 + _pulse)
	_glow_sprite.scale = _sprite.scale
	_glow_sprite.rotation = _sprite.rotation
	_glow_sprite.frame = _sprite.frame
	_glow_sprite.modulate = Color(glow_color, clampf(_glow + (0.25 if fever else 0.0), 0.0, 1.0))
