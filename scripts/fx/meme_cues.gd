class_name MemeCues
extends Node2D
## 跟着积累条冒出来的猫图：每个小关有一串 {at 进度, meme 素材名, x, y, size, fx, speed}，
## 积累条涨到 at（0-1）时那只猫蹦出来，一直待到这个小关结束。
## x / y 是相对屏幕中心的位置（-0.5 ~ 0.5，按屏幕宽 / 高算），size 是猫的高度占屏幕高度的比例。
## fx 是动效（见 EFFECTS），speed 是动效的快慢（1 = 正常）。
## 数据存在大关 .tres 里那个小关的 meme_cues，在游戏里按 Tab 调出的面板上编辑。
## 猫图画在小关画面上面、全屏镜头特效下面，所以九宫格 / 万花筒会把它们一起铺开。

## 动效名 -> 面板上显示的名字。加新动效：这里加一项，再在 layout() 的 match 里写它怎么动。
const EFFECTS := {
	"": "None",
	"spin": "Spin",        # 原地自转
	"orbit": "Orbit",      # 绕着屏幕中心转圈（半径 = 摆的位置离中心多远）
	"stream": "Stream",    # 一排同样的猫从右往左不停地流过去（高度 = 摆的位置）
	"bounce": "Bounce",    # 跟着拍子一下一下弹
	"float": "Float",      # 上下飘、轻轻摇
}
## “流过去”的一排里有几只
const STREAM_COUNT := 4

## true = 正式游戏：冒出来就不会再消失；false = 面板里拖进度条预览，严格按进度显示
var latched := true
var cues: Array = []

var _progress := 0.0
var _holders: Array[Node2D] = []  # 每条数据一个节点，下面挂一只或一排猫
var _shown: Array[bool] = []


func begin(section_cues: Array) -> void:
	cues = section_cues
	_progress = 0.0
	rebuild()


func set_progress(p: float) -> void:
	_progress = maxf(_progress, p) if latched else p
	_update(true)


## 猫图的清单改过了（面板里增删、换素材、换动效之后调用）
func rebuild() -> void:
	for h in _holders:
		h.queue_free()
	_holders.clear()
	_shown.clear()
	for cue: Dictionary in cues:
		var holder := Node2D.new()
		holder.visible = false
		add_child(holder)
		for k in (STREAM_COUNT if cue.get("fx", "") == "stream" else 1):
			var s := MemeSprite.new()
			s.meme = cue.get("meme", "")
			holder.add_child(s)
		_holders.append(holder)
		_shown.append(false)
	_update(false)


## 每帧摆位置、做动效
func layout() -> void:
	var size := get_viewport_rect().size
	var t := Time.get_ticks_msec() / 1000.0
	for i in mini(_holders.size(), cues.size()):
		var cue: Dictionary = cues[i]
		var holder := _holders[i]
		var first := holder.get_child(0) as MemeSprite
		if first.texture == null:
			continue
		var base := size * (Vector2(cue.get("x", 0.0), cue.get("y", 0.0)) + Vector2(0.5, 0.5))
		var height := size.y * float(cue.get("size", 0.25))
		var unit := height / maxf(first.texture.get_height() / float(maxi(first.vframes, 1)), 1.0)
		var speed: float = cue.get("speed", 1.0)
		var pos := base
		var rot := 0.0
		var grow := 1.0
		match cue.get("fx", ""):
			"spin":
				rot = t * speed * 3.0
			"orbit":
				pos = size / 2.0 + (base - size / 2.0).rotated(t * speed * 1.5)
			"bounce":
				grow = 1.0 + 0.3 * exp(-fposmod(Conductor.song_beat * speed, 1.0) * 6.0)
			"float":
				pos.y += sin(t * 2.0 * speed + i) * 0.04 * size.y
				rot = sin(t * 1.3 * speed + i) * 0.15
			"stream":
				pos = Vector2(0.0, base.y)
		holder.position = pos
		holder.rotation = rot
		var span := size.x + height * 2.0
		for k in holder.get_child_count():
			var s := holder.get_child(k) as MemeSprite
			s.scale = Vector2.ONE * unit * grow
			if cue.get("fx", "") == "stream":
				s.position.x = fposmod(base.x + k * span / holder.get_child_count() - t * speed * 0.3 * size.x + height, span) - height
			else:
				s.position = Vector2.ZERO


func _update(animate: bool) -> void:
	layout()
	for i in _holders.size():
		var want: bool = float(cues[i].get("at", 0.0)) <= _progress + 0.0001
		if want == _shown[i]:
			continue
		_shown[i] = want
		var holder := _holders[i]
		holder.visible = want
		if want and animate:  # 蹦出来（一排流动的猫改成淡入，免得从屏幕角上缩放）
			if cues[i].get("fx", "") == "stream":
				holder.modulate.a = 0.0
				holder.create_tween().tween_property(holder, "modulate:a", 1.0, 0.4)
			else:
				holder.scale = Vector2.ZERO
				holder.create_tween().tween_property(holder, "scale", Vector2.ONE, 0.3) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	layout()
