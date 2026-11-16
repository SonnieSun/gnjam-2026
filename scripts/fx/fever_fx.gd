class_name FeverFx
extends CanvasLayer
## FEVER 的画面：彩色滤镜 + 彩带。听 Music.fever_started / fever_ended，放进小关的场景里（或者 main.tscn）就生效。
## 参考的是《力量涌现出来了》的 fever_fx.gd，改了这些：
##   - 跟音乐走：滤镜每拍呼吸一下（原来是自己按时间的正弦），拍手那一下亮一下、往外扩一圈彩虹波纹、两边角落各喷一小把彩带；
##     玩家打中时也亮一下。所以鼓型是什么样，画面就是什么节奏。
##   - 省：彩带炮是固定的几门轮着用（原来每一下新建一个粒子节点、喷完删掉），同屏的纸片数有上限，可以放心每拍喷。
##   - 中间留给音符：滤镜只压边缘，彩带雨只从两边三分之一落（中间不落），整层在 HUD 下面。
## 每一样有自己的开关，数值都在检查器里调。

## 总开关
@export var enabled := true
@export_group("彩色滤镜")
@export var filter := true
## 边缘彩虹平时多亮
@export_range(0.0, 1.0) var filter_opacity := 0.5
## 每拍呼吸的幅度（0 = 不呼吸）
@export_range(0.0, 1.0) var filter_beat_pulse := 1.0
## 拍手 / 打中那一下再亮多少（叠在上面，很快退掉）
@export_range(0.0, 1.0) var filter_punch := 0.35
## 每秒转多少圈、绕一圈重复几遍彩虹
@export var filter_speed := 0.18
@export var filter_bands := 1.0
## 从多靠里开始有颜色（越小越往中间压）
@export_range(0.0, 0.8) var filter_inner := 0.28
## 拍手那一下往外扩的彩虹波纹多亮（0 = 没有）
@export_range(0.0, 1.0) var wave_strength := 0.5
## 进 fever 那一下白闪多亮（0 = 不闪）
@export_range(0.0, 1.0) var enter_flash := 0.3
## 淡入 / 淡出几秒
@export var fade_in := 0.25
@export var fade_out := 0.6
@export_group("声音")
## 进 fever 那一下的升阶音效（一串往上跑的琶音，落在一个响着的和弦上；tools/music_gen/make_fever_sfx.py 合成的，C 大调）。空 = 不放
@export var enter_sfx: AudioStream = preload("res://assets/audio/sfx/fever_enter.wav")
@export_range(-30.0, 6.0) var enter_sfx_db := -10.0
@export_group("彩带")
@export var confetti := true
## 进 fever：两边角落各一大炮，每边多少片
@export var enter_amount := 90
## fever 里每个拍手：两边各一小炮，每边多少片（0 = 不喷）
@export var clap_amount := 10
## 顶上一直往下飘的彩带雨，同时有多少片（0 = 没有）
@export var rain_amount := 24
## 纸片大小（像素）
@export var paper_size := Vector2(9.0, 17.0)
## 小炮和彩带雨的纸片是大炮的多少倍
@export_range(0.2, 1.0) var small_scale := 0.6
@export_group("")

const SMALL_CANNONS := 3   # 每边几门小炮轮着用（一门喷完要 lifetime 秒，轮着用才不会把上一把掐掉）

var _sfx: AudioStreamPlayer
var _rect: ColorRect
var _mat: ShaderMaterial
var _on := false
var _level := 0.0      # 淡入淡出 0~1
var _punch := 0.0
var _wave := 2.0
var _flash := 0.0
var _big: Array[CPUParticles2D] = []      # 左、右
var _small: Array[CPUParticles2D] = []    # 左右交替，每边 SMALL_CANNONS 门
var _small_next := 0
var _rain: Array[CPUParticles2D] = []     # 左、右两条
var _ramp: Gradient
var _flutter: Curve


func _ready() -> void:
	layer = 1   # 和 ScreenFx 同一层（在它后面画），HUD（2）在上面
	_sfx = AudioStreamPlayer.new()   # 自己的播放器：Music 那几个放一次性音效的在进 fever 那一下都占着（镲、升档的喵）
	add_child(_sfx)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://scripts/fx/fever_rainbow.gdshader")
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	_ramp = Gradient.new()
	var cols := PackedColorArray()
	var offs := PackedFloat32Array()
	for i in 7:
		offs.append(i / 6.0)
		cols.append(Color.from_hsv(i / 7.0, 0.8, 1.0))
	_ramp.offsets = offs
	_ramp.colors = cols
	# 纸片翻面：宽度在 1 和 0.15 之间来回
	_flutter = Curve.new()
	for i in 13:
		_flutter.add_point(Vector2(i / 12.0, 1.0 if i % 2 == 0 else 0.15))
	for side: float in [-1.0, 1.0]:
		_big.append(_cannon(side, enter_amount, 1.0, 2.6))
		_rain.append(_make_rain())
	for i in SMALL_CANNONS * 2:
		_small.append(_cannon(-1.0 if i % 2 == 0 else 1.0, maxi(clap_amount, 1), small_scale, 1.8))
	_layout()
	get_viewport().size_changed.connect(_layout)
	Music.fever_started.connect(start)
	Music.fever_ended.connect(stop)
	Music.drum_clap.connect(func(_b: float) -> void: hit(1.0, true))
	Conductor.song_started.connect(stop.bind(true))
	# 玩家打中：边缘亮一下（没有 Judge 的地方，比如单独测试，就算了）
	var judge := get_tree().current_scene.get_node_or_null("Judge") if get_tree().current_scene else null
	if judge and judge.has_signal("note_judged"):
		judge.connect("note_judged", func(_n: NoteData, result: int, _diff: float) -> void:
			if result != NoteData.Result.MISS:
				hit(0.6, false))
	if Music.fever:
		start()


## fever 开始（Music.fever_started 自动调；想在别的时候借用这套画面也可以自己调）
func start() -> void:
	if _on or not enabled:
		return
	_on = true
	_punch = 1.0
	_wave = 0.0
	if enter_sfx and Conductor.playing:
		_sfx.stream = enter_sfx
		_sfx.volume_db = enter_sfx_db
		_sfx.play()
	_flash = enter_flash if filter else 0.0
	if confetti:
		for c in _big:
			c.amount = maxi(enter_amount, 1)
			c.restart()
		for r in _rain:
			r.amount = maxi(rain_amount / 2, 1)
			r.emitting = rain_amount > 0


## fever 结束：滤镜淡出，彩带雨停（已经在飞的飞完）。now = 马上清掉（重开、换关）
func stop(now := false) -> void:
	_on = false
	for r in _rain:
		r.emitting = false
	if now:
		_level = 0.0
		for c: CPUParticles2D in _big + _small + _rain:
			c.emitting = false
			c.restart()
			c.emitting = false


## fever 里的一下：边缘亮一下（strength 0~1）；burst = 再扩一圈波纹、两边各喷一小把彩带
func hit(strength: float, burst: bool) -> void:
	if not _on:
		return
	_punch = maxf(_punch, strength)
	if not burst:
		return
	_wave = 0.0
	if confetti and clap_amount > 0:
		for i in 2:   # 左右各一门，轮到下一对
			var c := _small[(_small_next + i) % _small.size()]
			c.amount = clap_amount
			c.restart()
		_small_next = (_small_next + 2) % _small.size()


func _process(delta: float) -> void:
	_level = move_toward(_level, 1.0 if _on else 0.0, delta / maxf(fade_in if _on else fade_out, 0.01))
	_punch = move_toward(_punch, 0.0, delta / 0.3)
	_flash = move_toward(_flash, 0.0, delta / 0.35)
	_wave += delta / 0.7
	_rect.visible = filter and (_level > 0.001 or _flash > 0.001)
	if not _rect.visible:
		return
	# 每拍呼吸：拍点上最亮，然后落回去（读节拍时钟，和音乐对齐）
	var beat_pulse := pow(1.0 - fposmod(Conductor.song_beat, 1.0), 2.0) if Conductor.playing else 0.0
	_mat.set_shader_parameter("opacity", _level * (filter_opacity + filter_punch * _punch))
	_mat.set_shader_parameter("pulse", lerpf(1.0, beat_pulse, filter_beat_pulse))
	_mat.set_shader_parameter("speed", filter_speed)
	_mat.set_shader_parameter("bands", filter_bands)
	_mat.set_shader_parameter("inner", filter_inner)
	_mat.set_shader_parameter("wave", _wave)
	_mat.set_shader_parameter("wave_strength", wave_strength * _level)
	_mat.set_shader_parameter("flash", _flash)


func _paper(p: CPUParticles2D, size: float) -> void:
	p.color_initial_ramp = _ramp
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = paper_size.x * size
	p.scale_amount_max = paper_size.y * size
	p.split_scale = true
	p.scale_curve_x = _flutter
	# 快落完时淡掉，不是突然没了
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade


## 角落的彩带炮：往上、往屏幕里斜着喷，重力拉回来、空气阻力让它飘
func _cannon(side: float, amount: int, size: float, lifetime: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.set_meta("side", side)
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.92
	p.amount = maxi(amount, 1)
	p.lifetime = lifetime
	p.direction = Vector2(-side * 0.55, -1.0).normalized()
	p.spread = 22.0
	p.initial_velocity_min = 700.0 * (0.6 + 0.4 * size)
	p.initial_velocity_max = 1300.0 * (0.6 + 0.4 * size)
	p.gravity = Vector2(0, 1250)
	p.damping_min = 260.0
	p.damping_max = 520.0
	_paper(p, size)
	add_child(p)
	return p


func _make_rain() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = maxi(rain_amount / 2, 1)
	p.lifetime = 3.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2.DOWN
	p.spread = 30.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 180)
	p.damping_min = 20.0
	p.damping_max = 40.0
	_paper(p, small_scale)
	add_child(p)
	return p


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", view.x / maxf(view.y, 1.0))
	for c: CPUParticles2D in _big + _small:
		var side: float = c.get_meta("side")
		c.position = Vector2(view.x * 0.5 + side * view.x * 0.5, view.y + 20.0)
	# 彩带雨：左右两条，各占屏幕宽的三分之一，中间不落
	for i in _rain.size():
		_rain[i].position = Vector2(view.x * (1.0 / 6.0 if i == 0 else 5.0 / 6.0), -30.0)
		_rain[i].emission_rect_extents = Vector2(view.x / 6.0, 10.0)
