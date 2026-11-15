class_name MemeField3D
extends Node3D
## 猫图在 3D 场景的空间里莫名其妙地冒出来：一块空间（box）里随机的位置，一只只弹出来、悬着、过几拍消失、
## 换个地方再冒出来。flow 不是零的话它们整体往一个方向飘（路上用：迎面飞过去，飞出这块空间就从另一头回来）。
## 每拍弹一下。放进猫所在的那个 3D 世界（KisaSpinCat3D.world），center 由外面给（这块空间的中心）。

## 用哪些猫图（MemeLib 里的名字），每只随机挑一张
var memes: Array = ["popcat"]
var count := 8
## 每只多高（3D 单位），随机上下浮动多少（比例）
var item_height := 1.0
var size_jitter := 0.5
## 这块空间有多大（3D 单位，以 center 为中心），中间要空出来的宽度（别挡住猫和音符，0 = 不空）
var box := Vector3(6.0, 3.0, 6.0)
var clear_width := 0.0
## 每拍往哪飘多少（3D 单位）
var flow := Vector3.ZERO
## 一只出现几拍就消失（0 = 一直在；有 flow 时一般用 0）
var life_beats := 4.0
## 每拍弹多大
var beat_pulse := 0.2
var fever_speed := 1.8

var center := Vector3.ZERO
var _sprites: Array[Sprite3D] = []
var _infos: Array = []
var _pos: Array[Vector3] = []   # 相对 center
var _born: Array[float] = []    # 第几拍冒出来的
var _size: Array[float] = []
var _leaving := -1.0
var _fever := false
var _last_beat := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(str(memes) + str(count))
	_last_beat = Conductor.song_beat
	for i in count:
		var info := MemeLib.find(memes[i % memes.size()])
		if info.is_empty():
			continue
		var tex: Texture2D = load(info.path)
		var s := Sprite3D.new()
		s.texture = tex
		s.hframes = info.cols
		s.vframes = info.rows
		s.pixel_size = item_height / (tex.get_height() / float(info.rows))
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.scale = Vector3.ZERO
		add_child(s)
		_sprites.append(s)
		_infos.append(info)
		_pos.append(_random_spot())
		# 不同时冒出来：错开
		_born.append(_last_beat + (float(i) / count) * (life_beats if life_beats > 0.0 else 2.0))
		_size.append(1.0 + _rng.randf_range(-size_jitter, size_jitter))
	if has_node("/root/Music"):
		var music: Node = get_node("/root/Music")
		music.fever_started.connect(func(): _fever = true)
		music.fever_ended.connect(func(): _fever = false)
		_fever = music.fever


## 都缩回去再消失
func leave() -> void:
	_leaving = 1.0


func _random_spot() -> Vector3:
	var p := Vector3(_rng.randf_range(-0.5, 0.5) * box.x, _rng.randf_range(-0.5, 0.5) * box.y, _rng.randf_range(-0.5, 0.5) * box.z)
	if clear_width > 0.0 and absf(p.x) < clear_width / 2.0:
		p.x = signf(p.x if p.x != 0.0 else 1.0) * (clear_width / 2.0 + absf(p.x))
	return p


func _process(delta: float) -> void:
	var beat: float = Conductor.song_beat
	var step := clampf(beat - _last_beat, 0.0, 1.0) * (fever_speed if _fever else 1.0)
	_last_beat = beat
	if _leaving >= 0.0:
		_leaving -= delta * 4.0
		if _leaving <= 0.0:
			queue_free()
			return
	var pulse := exp(-fposmod(beat, 1.0) * 5.0) * beat_pulse
	var bpm: float = Conductor.chart.bpm if Conductor.get("chart") else 120.0
	for i in _sprites.size():
		var s := _sprites[i]
		var age := beat - _born[i]
		if life_beats > 0.0 and age >= life_beats:
			_pos[i] = _random_spot()
			_born[i] = beat
			age = 0.0
		var p := _pos[i] + flow * step
		# 飘出这块空间就从另一头回来
		for axis in 3:
			if flow[axis] != 0.0 and absf(p[axis]) > box[axis] / 2.0:
				p = _random_spot()
				p[axis] = -signf(flow[axis]) * box[axis] / 2.0
		_pos[i] = p
		s.position = center + p
		# 弹出来（前半拍），快到点了缩回去（最后半拍）
		var k := 0.0
		if age >= 0.0:
			k = clampf(age / 0.5, 0.0, 1.0)
			k = 1.0 + 0.35 * sin(k * PI) if k < 1.0 else 1.0
			k *= clampf(age * 4.0, 0.0, 1.0)
			if life_beats > 0.0:
				k *= clampf((life_beats - age) / 0.5, 0.0, 1.0)
		if _leaving >= 0.0:
			k *= _leaving
		s.scale = Vector3.ONE * k * _size[i] * (1.0 + pulse)
		var frames: int = _infos[i].frames
		if frames > 1:
			s.frame = posmod(int(beat * 60.0 / bpm * float(_infos[i].fps)) + i * 5, frames)
