@tool
class_name SectionDef
extends Resource
## 一个旋转段落（关卡）的定义：用哪个场景、转一圈几拍、谱面。

## 切到这一段时的转场：ZOOM = 旧的放大淡出、新的从中心长出来；CUT = 硬切 + 白闪
enum Transition { ZOOM, CUT }

@export var title := ""
## 这个小关用哪个场景。一般不用动这一项：在最下面的 scene_file 下拉框里选就行，
## 那里列出了“小关场景文件夹”里所有能用的场景（文件夹在 项目设置 → Gnjam → Sections Folder 里改）。
@export var scene: PackedScene:
	set(value):
		scene = value
		notify_property_list_changed()
## 转一整圈需要多少拍。旋转角度 = 段内拍数 / beats_per_rev * TAU
@export var beats_per_rev := 4.0
## 谱面：每个字符串是一小节，按字符数等分。
##   k = 底鼓  s = 军鼓  h = 踩镲  （x 等同于 k）  其他字符 = 休止
## 例如 "k...s...k.k.s..." = 十六分音符网格。空字符串 = 整小节休止。
## 这几个小节会一直循环，直到这个小关的积累条满了为止。
@export var bars: PackedStringArray = []
## 谱面编辑器写的谱子（scenes/tools/chart_editor.tscn）。填了就用它代替上面的 bars：
## 音符可以带出现时间、发光、旋转、轨道等表现属性。留空 = 用 bars。
@export var chart: ChartPattern

@export var transition: Transition = Transition.ZOOM
## 勾上 = 这个小关接着上一个小关继续，中间没有“换关”的感觉（要和上一个小关用同一个场景才生效）：
## 画面不重新加载、不转场不白闪，只换谱面；连着的这几个小关在画面上共用一条积累条（一段接一段往上涨）。
@export var joins_previous := false
## 积累条满了之后，等正在放的曲子唱到几小节一句的乐句线才换到下一个小关（0 = 不等，下一条小节线就换）。
## 下一个小关换曲子 / 换段落、或者这是最后一个小关时用：不然那一句唱到一半就被切掉。等的时候音符照常出、照常计分。
## 只在用叠轨音乐的关卡里起作用（乐句从那首曲子自己的第 1 小节数起）。
@export var exit_on_bars := 0
## 每个阶段里积累条涨跌的倍数，用来把一段做长 / 做短：第 0 个 = 第一条分数线之前，第 i 个 = 过了第 i 条线之后，没写的是 1。
## 0.5 = 每一下只涨一半，这一段要打两倍那么多下。分数线、满条值和音乐的切换点都不用动。
## （游戏里 Tab 面板 Phases 页的 Length 改的就是它。）
@export var phase_gain := PackedFloat32Array()
## fever 那一段的倍数（0 = 不单独设，用所在阶段的）
@export var fever_gain := 0.0
## 节奏组件的设置：{节点名: {属性名: 值}}。进小关时套到小关场景里同名的节点上，盖过场景里填的
## （CatBounce / NoteAccents / CountInDisplay / FeverFx；游戏里 Tab 面板 Rhythm 页改的就是它）。
@export var fx := {}
## 接着上一段时，换谱面之前空几小节（大关里的 rest_bars_on_switch 是普通换关用的，一般更长）
@export var join_rest_bars := 1

## 这个小关的积累条满条值。0 = 不指定（用关卡场景里填的，场景也没填就用 Gauge 节点的默认值）
@export var gauge_max := 0
## 这个小关的事件分数线：积累条涨到这些分数时各触发一次事件，比如 [15, 30, 45]。
## 只有 use_gauge_events 勾上时才生效（这样才能表达“这一关一个事件都没有”）。
@export var gauge_events := PackedInt32Array()
@export var use_gauge_events := false
## 每条分数线（阶段）叫什么，只是给编辑面板看的，比如 ["Stars", "Ball"]。不填就显示 Phase 1、Phase 2……
@export var gauge_event_names := PackedStringArray()

## 镜头特效的切换点：[[进度 0-1, 特效名], ...]。积累条涨到那个进度就换成那个特效（"" = 原样）。
## 特效名见 scripts/fx/screen_fx.gd 的 EFFECTS。在游戏里按 Tab 调出的面板上编辑最方便。
@export var fx_cues: Array = []
## 跟着积累条冒出来的猫图：[{at 进度, meme 素材名, x, y, size}, ...]，见 scripts/fx/meme_cues.gd。
@export var meme_cues: Array = []

## 这个小关是从全曲第几拍开始的（进入这个小关时由 Main 填入）
var start_beat := 0.0
## 鼓谱循环一遍多少拍（由 SongChart.recompute() 填入）
var length := 0.0


# ---- 检查器里的 scene_file 下拉框：列出小关场景文件夹里所有的场景 ----

const SECTIONS_FOLDER_SETTING := "gnjam/sections_folder"
const SECTIONS_FOLDER_DEFAULT := "res://scenes/sections"


static func sections_folder() -> String:
	return ProjectSettings.get_setting(SECTIONS_FOLDER_SETTING, SECTIONS_FOLDER_DEFAULT)


## 小关场景文件夹里所有的场景（含子文件夹），返回相对那个文件夹的路径，按名字排序
static func available_scenes(folder: String = "", prefix: String = "") -> PackedStringArray:
	if folder == "":
		folder = sections_folder()
	var out := PackedStringArray()
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "tscn":
			out.append(prefix + f)
	for d in dir.get_directories():
		out.append_array(available_scenes(folder.path_join(d), prefix + d + "/"))
	out.sort()
	return out


func _get_property_list() -> Array[Dictionary]:
	var options := available_scenes()
	var current: String = _get(&"scene_file")
	if current != "" and not options.has(current):
		options.append(current)  # 用的是文件夹外面的场景，也照样显示出来
	return [{
		"name": "scene_file",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_EDITOR,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(options),
	}]


func _get(property: StringName) -> Variant:
	if property == &"scene_file":
		if scene == null:
			return ""
		var root := sections_folder().path_join("")
		var path := scene.resource_path
		return path.trim_prefix(root) if path.begins_with(root) else path
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"scene_file":
		var text := String(value)
		if text == "":
			scene = null
		else:
			var path := text if text.begins_with("res://") else sections_folder().path_join(text)
			if ResourceLoader.exists(path):
				scene = load(path)
		return true
	return false


func length_beats(beats_per_bar: int) -> float:
	if chart:
		return chart.length_beats
	return bars.size() * beats_per_bar


## 返回段内的音符列表，每项是 {"beat": 相对段落开头的拍数, "sound": NoteData.Sound}
func parse_notes(beats_per_bar: int) -> Array[Dictionary]:
	if chart:
		return chart.parse_notes()
	# 老鼓谱：音符后面接 "=" 的带上 length（长按几拍），这样长按在每一关都认
	var out: Array[Dictionary] = []
	out.assign(ChartPattern.from_bars(bars, beats_per_bar).notes)
	return out


## 长按：{段内位置（千分之一拍，取整）: 长按几拍}。谱面编辑器的谱子看 length；老鼓谱看音符后面的 "="
func hold_lengths(beats_per_bar: int) -> Dictionary:
	var out := {}
	var src := chart if chart else ChartPattern.from_bars(bars, beats_per_bar)
	for d in src.notes:
		var len := float(d.get("length", 0.0))
		if len > 0.0 and not d.get("mash", false):  # 连击的长度不是长按
			out[roundi(float(d.beat) * 1000.0)] = len
	return out


static func _char_to_sound(ch: String) -> int:
	match ch:
		"k", "x": return NoteData.Sound.KICK
		"s": return NoteData.Sound.SNARE
		"h": return NoteData.Sound.HAT
	return -1
