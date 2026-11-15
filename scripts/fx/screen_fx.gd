class_name ScreenFx
extends CanvasLayer
## 全屏镜头特效（九宫格、万花筒、镜像……），跟着积累条走：
## 每个小关有一串“切换点”[[进度, 特效名], ...]，积累条涨到那个进度就换成那个特效（"" = 原样）。
## 切换点存在大关 .tres 里那个小关的 fx_cues，在游戏里按 Tab 调出的面板上编辑。
## 特效对所有小关都生效（2D、3D 都行），因为它加工的是已经画好的整个画面；HUD 在它上面，不受影响。
##
## 加一种新特效：在 EFFECTS 里加一项（名字 + 各个 shader 参数要到的目标值），
## shader 是 assets/shaders/screen_fx.gdshader。

## 换了特效（id 是 EFFECTS 里的名字，"" = 原样）
signal effect_changed(id: String)

## 特效名 -> {label 面板上显示的名字, color 面板上的颜色, 其余是 shader 参数的目标值}
const EFFECTS := {
	"": {"label": "Normal", "color": Color(0.3, 0.3, 0.35)},
	"grid2": {"label": "2x2 Grid", "color": Color("7fd1ff"), "tiles": 2.0},
	"grid3": {"label": "3x3 Grid", "color": Color("4f9dff"), "tiles": 3.0},
	"grid4": {"label": "4x4 Grid", "color": Color("3a6bd8"), "tiles": 4.0},
	"kaleido": {"label": "Kaleidoscope", "color": Color("ff5d8f"), "kaleido": 1.0},
	"mirror": {"label": "Mirror", "color": Color("86ffa3"), "mirror": 1.0},
	"rgb": {"label": "RGB Split", "color": Color("ffd23f"), "rgb_split": 0.012},
	"zoom": {"label": "Zoom In", "color": Color("ff9a3c"), "zoom": 1.45},
	"invert": {"label": "Invert", "color": Color("b38cff"), "invert": 1.0},
}
const NEUTRAL := {"tiles": 1.0, "kaleido": 0.0, "mirror": 0.0, "rgb_split": 0.0, "zoom": 1.0, "invert": 0.0}
const SHADER := preload("res://assets/shaders/screen_fx.gdshader")

## 换特效时过渡得多快（越大越快）
@export var blend_speed := 6.0
## 万花筒每秒转多少（弧度）
@export var kaleido_speed := 0.35
## 万花筒里画在最上面的判定圈半径，占屏幕高度的比例（正好套住中间那一份画面）
@export var top_ring_ratio := 0.2
## 换特效时白闪多亮（0 = 不闪）
@export var flash_strength := 0.45

@export_group("打中时顶一下")
## 打中的瞬间整个画面推近一下再弹回来（带一点过冲），同时红蓝错开一瞬间。全部小关通用，HUD 不受影响。
## 推近多少（0.025 = 放大 2.5%；0 = 不顶）
@export var punch_zoom := 0.025
## 红蓝错开多远（占屏幕宽度的比例）
@export var punch_rgb := 0.004
## 弹回来用多久（秒）
@export var punch_seconds := 0.22
## Perfect / Great / Good 各顶多大（乘在上面两个值上；0 = 这个等级不顶）
@export var punch_perfect := 1.0
@export var punch_great := 0.5
@export var punch_good := 0.0
@export_group("连击越高越热闹")
## 连击到这个数算“全热”，中间按比例来（0 = 不要这个效果）
@export var heat_full_combo := 50
## 全热时打中顶得比平时大多少（0.6 = 大 60%）
@export var heat_punch := 0.6
## 全热时画面比平时鲜艳多少（0.2 = 饱和度 1.2 倍）
@export var heat_saturation := 0.2
## 热起来有多快、连击断了凉下去有多快（越大越快）
@export var heat_rise_speed := 2.0
@export var heat_fall_speed := 6.0
## 连击断掉的一瞬间画面褪色多少（按断之前有多热打折；0 = 不褪色），多久恢复（秒）
@export_range(0.0, 1.0) var break_fade := 0.45
@export var break_fade_seconds := 0.4
@export_group("")

## 当前小关（万花筒里要替它把缩圈画在最上面，不然会被折进花瓣里看不清）
var section: SpinSection
## true = 正式游戏：进度只进不退，掉分不会把特效退回去；false = 面板里拖进度条预览，跟着进度走
var latched := true
var cues: Array = []
var effect := ""

var _progress := 0.0
var _rect: ColorRect
var _rings: Node2D
var _mat: ShaderMaterial
var _now := NEUTRAL.duplicate()
var _flash := 0.0
var _punch := 0.0      # 这一下顶多大
var _punch_age := 99.0
var _heat_goal := 0.0  # 按现在的连击数该有多热（0~1）
var _heat := 0.0       # 实际热到哪了（平滑追过去）
var _fade := 0.0       # 连击刚断：褪色还剩多少


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.visible = false
	add_child(_rect)
	_rings = Node2D.new()
	_rings.draw.connect(_draw_rings)
	add_child(_rings)


## 进了一个新的小关
func begin(section_cues: Array, current: SpinSection) -> void:
	cues = section_cues
	section = current
	_progress = 0.0
	_apply(false)


## 积累条进度变了（0-1）
func set_progress(p: float) -> void:
	_progress = maxf(_progress, p) if latched else p
	_apply(true)


## 切换点改过了（面板里编辑之后调用）
func refresh() -> void:
	_apply(false)


## 现在有多热（0 = 没连击，1 = 连击到了 heat_full_combo），别的效果想跟着连击变可以读
func heat() -> float:
	return _heat


## 连击数变了（main.gd 每次判定后告诉这里）
func set_combo(combo: int) -> void:
	var goal := clampf(float(combo) / heat_full_combo, 0.0, 1.0) if heat_full_combo > 0 else 0.0
	if goal < _heat_goal and combo == 0:
		_fade = maxf(_fade, break_fade * _heat)  # 断了：褪色一下，之前越热褪得越明显
	_heat_goal = goal


## 换小关 / 重开：热度清零，不褪色
func reset_heat() -> void:
	_heat_goal = 0.0
	_heat = 0.0
	_fade = 0.0


## 画面顶一下。strength：1 = Perfect 那么大（连击高时自动更大；小关可以用 screen_punch 整体调大调小）
func punch(strength: float = 1.0) -> void:
	strength *= 1.0 + heat_punch * _heat
	if is_instance_valid(section):
		strength *= section.screen_punch
	if strength <= 0.0:
		return
	if _punch_age < 0.05 and strength < _punch:
		return  # 同一下里已经有更大的（比如刚好打进新阶段），小的不盖掉它
	_punch = strength
	_punch_age = 0.0


## 按判定结果顶一下（Miss 不顶）
func punch_for(result: int) -> void:
	match result:
		NoteData.Result.PERFECT: punch(punch_perfect)
		NoteData.Result.GREAT: punch(punch_great)
		NoteData.Result.GOOD: punch(punch_good)


static func effect_at(list: Array, p: float) -> String:
	var id := ""
	var best := -1.0
	for cue in list:
		var at: float = cue[0]
		if at <= p + 0.0001 and at >= best:
			best = at
			id = cue[1]
	return id if EFFECTS.has(id) else ""


func _apply(with_flash: bool) -> void:
	var id := effect_at(cues, _progress)
	if id == effect:
		return
	effect = id
	if with_flash:
		_flash = flash_strength
	if is_instance_valid(section):
		section.notify_screen_fx(id)
	effect_changed.emit(id)


func _process(delta: float) -> void:
	var goal: Dictionary = EFFECTS[effect]
	var active := _flash > 0.001
	# 顶一下：瞬间推到最近，然后衰减着晃回来（晃过头一点点再回正）
	_punch_age += delta
	var add := {}
	if _punch_age < punch_seconds:
		var t := _punch_age / maxf(punch_seconds, 0.001)
		var fall := (1.0 - t) * (1.0 - t)
		add["zoom"] = punch_zoom * _punch * fall * cos(t * PI * 1.5)
		add["rgb_split"] = punch_rgb * _punch * fall
		active = true
	for key: String in NEUTRAL:
		var to: float = goal.get(key, NEUTRAL[key])
		_now[key] = lerpf(_now[key], to, minf(1.0, delta * blend_speed))
		if absf(_now[key] - to) < 0.002:
			_now[key] = to
		if absf(_now[key] - NEUTRAL[key]) > 0.0005:
			active = true
		_mat.set_shader_parameter(key, _now[key] + add.get(key, 0.0))
	# 连击热度：鲜艳一点；刚断的时候褪色一下
	_heat = move_toward(_heat, _heat_goal, delta * (heat_rise_speed if _heat_goal > _heat else heat_fall_speed))
	_fade = move_toward(_fade, 0.0, delta * break_fade / maxf(break_fade_seconds, 0.01))
	var sat := 1.0 + heat_saturation * _heat - _fade
	if absf(sat - 1.0) > 0.003:
		active = true
	_mat.set_shader_parameter("saturation", sat)
	_flash = move_toward(_flash, 0.0, delta * 1.5)
	_mat.set_shader_parameter("flash", _flash)
	var step := section.step_rot if is_instance_valid(section) else 0.0
	_mat.set_shader_parameter("spin", Time.get_ticks_msec() / 1000.0 * kaleido_speed + step * 0.25)
	_rect.visible = active
	_rings.queue_redraw()


## 万花筒里的缩圈：画在特效上面、屏幕正中
func _draw_rings() -> void:
	if effect != "kaleido" or not is_instance_valid(section) or section.def == null:
		return
	var size := _rect.get_viewport_rect().size
	var beats: float = section.get("approach_beats") if section.get("approach_beats") != null else 2.0
	section.draw_approach_rings(_rings, size / 2.0, top_ring_ratio * size.y, beats, 0.35 * size.y)
