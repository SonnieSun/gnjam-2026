class_name Y2kBurst
extends Node2D
## 一次性的 Y2K 图形炸开效果（星星、圆、三角、准星等），带外发光、半透明，播完自动销毁。
## 用法和 StarBurst 一样：var fx := Y2kBurst.create(true); parent.add_child(fx); fx.global_position = ...
## 外发光一层用叠加混合，本体一层用普通混合，这样放在亮背景上也不会糊成白色。

const DEFAULT_STYLE := preload("res://stages/shared/y2k_fx/y2k_burst_style.tres")

var style: Y2kBurstStyle = DEFAULT_STYLE
var strong := true
## 形状从离中心多远的地方出发（判定圈的半径附近）
var start_radius := 22.0

var _age := 0.0
var _lifetime := 0.6
var _alpha := 1.0
var _parts: Array[Dictionary] = []
var _glow_layer := Node2D.new()
var _core_layer := Node2D.new()

static var _glow_cache := {}


## strong = true 是 Perfect 的强烈版，false 是 Good 的微弱版
static func create(is_strong: bool) -> Y2kBurst:
	var fx := Y2kBurst.new()
	fx.strong = is_strong
	return fx


func _ready() -> void:
	var count := style.perfect_count if strong else style.good_count
	var size_range := style.perfect_size if strong else style.good_size
	var speed_range := style.perfect_speed if strong else style.good_speed
	_lifetime = style.perfect_lifetime if strong else style.good_lifetime
	_alpha = 1.0 if strong else style.good_alpha

	# 形状图缩得很小，用 mipmap 采样才不会锯齿
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer.material = glow_mat
	add_child(_glow_layer)
	add_child(_core_layer)
	_glow_layer.draw.connect(_draw_layer.bind(true))
	_core_layer.draw.connect(_draw_layer.bind(false))

	if style.shapes.is_empty():
		return
	for i in count:
		# 方向大致均匀分布，再加一点随机
		var a := (i + randf_range(-0.35, 0.35)) * TAU / count
		var tex: Texture2D = style.shapes.pick_random()
		var content := tex.get_size() - Vector2.ONE * style.texture_pad * 2.0
		_parts.append({
			"tex": tex,
			# 像 Unity 粒子的 Start Color：从颜色表里随机挑一个附上
			"color": style.colors.pick_random() if not style.colors.is_empty() else Color.WHITE,
			"glow": _glow_for(tex),
			"dir": Vector2.from_angle(a),
			"speed": randf_range(speed_range.x, speed_range.y),
			# 把形状最长边缩放到目标大小
			"scale": randf_range(size_range.x, size_range.y) / maxf(content.x, content.y),
			"rot": randf() * TAU,
			"spin": randf_range(-style.spin_max, style.spin_max),
		})


func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return
	_glow_layer.queue_redraw()
	_core_layer.queue_redraw()


func _draw_layer(is_glow: bool) -> void:
	var layer := _glow_layer if is_glow else _core_layer
	var t := _age / _lifetime
	# 先快后慢地飞出去，同时缩小淡出
	var travel := 1.0 - (1.0 - t) * (1.0 - t)
	var fade := (1.0 - t * t) * _alpha
	var shrink := lerpf(1.0, style.end_scale, t)
	for p in _parts:
		var tex: Texture2D = p.glow if is_glow else p.tex
		# 形状图是白的：本体 = 附上的颜色，外发光 = 同一颜色压暗
		var c: Color = p.color * (style.glow_brightness if is_glow else 1.0)
		c.a = (style.glow_strength if is_glow else style.core_alpha) * fade
		if tex == null:
			continue
		var pos: Vector2 = p.dir * (start_radius + p.speed * _lifetime * travel)
		var s: float = p.scale * shrink * (style.glow_scale if is_glow else 1.0)
		layer.draw_set_transform(pos, p.rot + p.spin * _age, Vector2.ONE * s)
		layer.draw_texture(tex, -tex.get_size() * 0.5, c)


## 找本体图旁边的 xxx_glow.png
static func _glow_for(tex: Texture2D) -> Texture2D:
	var path := tex.resource_path
	if not _glow_cache.has(path):
		var glow_path := path.get_basename() + "_glow.png"
		_glow_cache[path] = load(glow_path) if ResourceLoader.exists(glow_path) else null
	return _glow_cache[path]
