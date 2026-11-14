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
	"": {"label": "原样", "color": Color(0.3, 0.3, 0.35)},
	"grid2": {"label": "四宫格", "color": Color("7fd1ff"), "tiles": 2.0},
	"grid3": {"label": "九宫格", "color": Color("4f9dff"), "tiles": 3.0},
	"grid4": {"label": "十六宫格", "color": Color("3a6bd8"), "tiles": 4.0},
	"kaleido": {"label": "万花筒", "color": Color("ff5d8f"), "kaleido": 1.0},
	"mirror": {"label": "左右镜像", "color": Color("86ffa3"), "mirror": 1.0},
	"rgb": {"label": "色彩错位", "color": Color("ffd23f"), "rgb_split": 0.012},
	"zoom": {"label": "推近", "color": Color("ff9a3c"), "zoom": 1.45},
	"invert": {"label": "反色", "color": Color("b38cff"), "invert": 1.0},
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
	for key: String in NEUTRAL:
		var to: float = goal.get(key, NEUTRAL[key])
		_now[key] = lerpf(_now[key], to, minf(1.0, delta * blend_speed))
		if absf(_now[key] - to) < 0.002:
			_now[key] = to
		if absf(_now[key] - NEUTRAL[key]) > 0.0005:
			active = true
		_mat.set_shader_parameter(key, _now[key])
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
