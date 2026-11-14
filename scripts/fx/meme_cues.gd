class_name MemeCues
extends Node2D
## 跟着积累条冒出来的猫图：每个小关有一串 {at 进度, meme 素材名, x, y, size}，
## 积累条涨到 at（0-1）时那只猫蹦出来，一直待到这个小关结束。
## x / y 是相对屏幕中心的位置（-0.5 ~ 0.5，按屏幕宽 / 高算），size 是猫的高度占屏幕高度的比例。
## 数据存在大关 .tres 里那个小关的 meme_cues，在游戏里按 Tab 调出的面板上编辑。
## 猫图画在小关画面上面、全屏镜头特效下面，所以九宫格 / 万花筒会把它们一起铺开。

## true = 正式游戏：冒出来就不会再消失；false = 面板里拖进度条预览，严格按进度显示
var latched := true
var cues: Array = []

var _progress := 0.0
var _sprites: Array[MemeSprite] = []
var _shown: Array[bool] = []


func begin(section_cues: Array) -> void:
	cues = section_cues
	_progress = 0.0
	rebuild()


func set_progress(p: float) -> void:
	_progress = maxf(_progress, p) if latched else p
	_update(true)


## 猫图的清单改过了（面板里增删、换素材之后调用）
func rebuild() -> void:
	for s in _sprites:
		s.queue_free()
	_sprites.clear()
	_shown.clear()
	for cue: Dictionary in cues:
		var s := MemeSprite.new()
		s.meme = cue.get("meme", "")
		s.visible = false
		add_child(s)
		_sprites.append(s)
		_shown.append(false)
	_update(false)


## 只是挪了位置、改了大小（面板里拖动时每帧调用）
func layout() -> void:
	var size := get_viewport_rect().size
	for i in _sprites.size():
		var cue: Dictionary = cues[i]
		var s := _sprites[i]
		s.position = size * (Vector2(cue.get("x", 0.0), cue.get("y", 0.0)) + Vector2(0.5, 0.5))
		if s.texture and not s.has_meta("popping"):
			s.scale = Vector2.ONE * _scale_of(s, cue)


func _scale_of(s: MemeSprite, cue: Dictionary) -> float:
	var frame_h := s.texture.get_height() / float(maxi(s.vframes, 1))
	return get_viewport_rect().size.y * float(cue.get("size", 0.25)) / maxf(frame_h, 1.0)


func _update(animate: bool) -> void:
	layout()
	for i in _sprites.size():
		var want: bool = float(cues[i].get("at", 0.0)) <= _progress + 0.0001
		if want == _shown[i]:
			continue
		_shown[i] = want
		var s := _sprites[i]
		s.visible = want
		if want and animate and s.texture:  # 蹦出来
			var to := _scale_of(s, cues[i])
			s.scale = Vector2.ZERO
			s.set_meta("popping", true)
			var t := s.create_tween()
			t.tween_property(s, "scale", Vector2.ONE * to, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_callback(s.remove_meta.bind("popping"))


func _process(_delta: float) -> void:
	layout()  # 窗口大小变了也跟着挪
