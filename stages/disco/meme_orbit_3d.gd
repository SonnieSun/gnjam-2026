class_name MemeOrbit3D
extends Node3D
## 一圈猫图在 3D 场景里绕着一个点飞（不是贴在屏幕上转）：每只是一张始终朝着镜头的图，
## 圈可以歪着（tilt），所以近的大远的小、会被镜头的运动带着走。每拍半径弹一下，玩家按键推一把，FEVER 更快。
## 放进猫所在的那个 3D 世界（KisaSpinCat3D.world），center 每帧由外面更新成猫的位置。

## 用哪张猫图（MemeLib 里的名字）
var meme := "oiia"
var count := 8
## 圈多大、每只多高（3D 单位）
var radius := 3.0
var item_height := 1.0
## 圈歪多少度（0 = 平着绕，90 = 竖着绕），绕哪个方向歪
var tilt := 25.0
var tilt_yaw := 0.0
## 每拍转几圈（负数 = 反着转）
var turns_per_beat := 0.06
## 圈的中心比 center 高多少
var lift := 0.0
## 每拍半径弹多少（比例）、按键推多少圈
var beat_pulse := 0.12
var hit_push := 0.06
var fever_speed := 2.5

var center := Vector3.ZERO
var _angle := 0.0
var _push := 0.0
var _fever := false
var _sprites: Array[Sprite3D] = []
var _info := {}
var _grow := 0.0


func _ready() -> void:
	_info = MemeLib.find(meme)
	if _info.is_empty():
		return
	var tex: Texture2D = load(_info.path)
	var frame_h := tex.get_height() / float(_info.rows)
	for i in count:
		var s := Sprite3D.new()
		s.texture = tex
		s.hframes = _info.cols
		s.vframes = _info.rows
		s.pixel_size = item_height / frame_h
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		add_child(s)
		_sprites.append(s)
	if has_node("/root/Music"):
		var music: Node = get_node("/root/Music")
		music.fever_started.connect(func(): _fever = true)
		music.fever_ended.connect(func(): _fever = false)
		_fever = music.fever
	create_tween().tween_property(self, "_grow", 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 缩回去再消失
func leave() -> void:
	var t := create_tween()
	t.tween_property(self, "_grow", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"hit"):
		_push += hit_push


func _process(delta: float) -> void:
	if _sprites.is_empty():
		return
	var beat: float = Conductor.song_beat
	var bpm: float = Conductor.chart.bpm if Conductor.get("chart") else 120.0
	var bps := bpm / 60.0
	var speed := turns_per_beat * bps * (fever_speed if _fever else 1.0)
	_angle += (speed * delta + _push * minf(delta * 8.0, 1.0)) * TAU
	_push -= _push * minf(delta * 8.0, 1.0)
	var pulse := exp(-fposmod(beat, 1.0) * 5.0) * beat_pulse
	var r := radius * (1.0 + pulse) * _grow
	var basis := Basis(Vector3.RIGHT, deg_to_rad(tilt)).rotated(Vector3.UP, deg_to_rad(tilt_yaw))
	var frames: int = _info.frames
	var frame := int(beat / bps * float(_info.fps)) if frames > 1 else 0
	for i in _sprites.size():
		var a := _angle + TAU * i / _sprites.size()
		var s := _sprites[i]
		s.position = center + Vector3.UP * lift + basis * (Vector3(cos(a), 0.0, sin(a)) * r)
		s.scale = Vector3.ONE * _grow * (1.0 + pulse)
		if frames > 1:
			s.frame = posmod(frame + i * 3, frames)
