class_name NoteAccents
extends Node
## 音符的重点标记：按音符在音乐里的位置，告诉画音符的地方"这个音符是哪一种"，以及它该长什么样。
## 不改判定，不改谱面，只管样子。放进小关的场景里（节点名 NoteAccents），画音符的脚本来问它：
##     var look := accents.look(note, 原来的颜色)   # {"kind", "color", "width", "glow", "echo", "rainbow"}
##
## 五种（一个音符同时算好几种时，按下面从上到下的顺序取第一种）：
##   FEVER       换段音符：新的一段进来的那一拍上的音符，动态七彩（scripts/fx/note_rainbow.gdshader）。
##               进 fever 的那条小节线，和 rainbow_on_tiers 里写了的那几档的那条小节线。
##               谱里那一拍没有音符就加一个（add_change_note，用 Judge.add_note）。
##   LEAD_IN     （默认关着）音乐马上要换段了（Music.planned_change() 排好的那次）：换之前 lead_in_beats 拍里的音符。
##               要等积累条过了线才知道，只管得到过线之后才出现的音符。
##   ACCENT      重音：落在现在这套鼓型的拍手上（听得见的那一下）。
##   SYNCOPATED  切分：一串连着的、不在整拍上的音符（比如三连切分）的第一个。
##   DOWNBEAT    小节线：一小节的第一拍。
## 谱面里给音符单独指定了颜色的（NoteData.color），颜色听谱面的，这里只加粗细和光。
## 一个音符是哪一种，在它第一次出现时定下来就不再变（只有"进 fever 的那一个"例外），所以不会飞到一半换颜色。
##
## 现在是按规则自动判的样例。要做成每关单独设计：给音符加一个"重点"属性（和 color / size 一样进 ChartPattern、
## 在谱面编辑器里按音符编辑），kind_of() 先看它、没写再按规则，画法不用变。

enum Kind { NONE, DOWNBEAT, SYNCOPATED, ACCENT, LEAD_IN, FEVER }

## 总开关
@export var enabled := true
@export_group("小节线上的音符")
@export var downbeat := true
## 往这个颜色偏多少（0 = 不变色，1 = 完全换成它）
@export var downbeat_color := Color(1.0, 0.95, 0.75)
@export_range(0.0, 1.0) var downbeat_tint := 0.45
@export var downbeat_width := 1.35
@export_group("重音（落在拍手上）")
@export var accent := true
@export var accent_color := Color(1.0, 0.35, 0.75)
@export_range(0.0, 1.0) var accent_tint := 0.7
@export var accent_width := 1.6
## 外面常亮一圈柔光（0 = 没有）
@export_range(0.0, 1.0) var accent_glow := 0.5
@export_group("切分音（一串的第一个）")
@export var syncopated := true
## 一串切分音至少几个才标（1 = 单独一个不在整拍上的音符也标；3 = 只标三连以上的）
@export var syncopated_min_run := 1
## 相邻两个隔多少拍以内算连着
@export var syncopated_gap := 1.0
@export var syncopated_color := Color(0.45, 1.0, 0.95)
@export_range(0.0, 1.0) var syncopated_tint := 0.75
@export var syncopated_width := 0.8
## 外面多画一圈细的"回声"圈（看起来是双圈），一眼能和整拍的音符分开
@export var syncopated_echo := true
@export_group("fever 的音符（七彩）")
## 进 fever 的那一个音符
@export var fever := true
## 打中换段音符（七彩的那一个）时它自己的音效（一串往上的玻璃铃声；tools/music_gen/make_fever_sfx.py 合成的，C 大调）。空 = 不放
@export var change_note_sfx: AudioStream = preload("res://assets/audio/sfx/fever_note.wav")
@export_range(-30.0, 6.0) var change_note_sfx_db := -8.0
## 换段的那一拍上谱里没有音符（前后 add_note_gap 拍以内都没有）就加一个，让换段音符正好落在新的一段进来的那一下
@export var add_change_note := true
@export var add_note_gap := 0.45
## 升到这几档的那一拍上的音符也是七彩的"换段音符"（比如天空关写 2：欢乐颂进来的那一拍）。档 = Music.change_planned 的 id
@export var rainbow_on_tiers := PackedInt32Array()
@export var fever_width := 1.5
## 外面常亮的柔光
@export_range(0.0, 1.0) var fever_glow := 0.6
## 彩虹每秒转几圈 / 绕一圈重复几遍 / 从里到外错开多少 / 往白色提亮多少 / 闪多少
@export var rainbow_speed := 0.6
@export var rainbow_bands := 1.0
@export var rainbow_radial := 0.35
@export_range(0.0, 1.0) var rainbow_lift := 0.25
@export_range(0.0, 1.0) var rainbow_sparkle := 0.2
@export_group("换段之前的音符")
@export var lead_in := false
## 换段之前多少拍里的音符算
@export var lead_in_beats := 4.0
## 只管进 fever（关掉 = 升档也算）
@export var lead_in_fever_only := false
@export var lead_in_color := Color(1.0, 0.85, 0.2)
@export_range(0.0, 1.0) var lead_in_tint := 0.9
@export var lead_in_width := 1.5
## 每拍闪一下的幅度（0 = 不闪）
@export_range(0.0, 1.0) var lead_in_flash := 0.5


## 画音符的脚本每帧给一次：这个小关现在的音符（按拍子排好的）。切分音要看前一个音符是什么，没给就不判切分音。
var notes: Array[NoteData] = []

var _kinds := {}            # NoteData -> Kind：一个音符第一次被问到时定下来，之后不变（不然飞到一半会突然换颜色）
var _fever_at := -1.0       # 排好的那次进 fever 落在第几拍（-1 = 没有）
var _fever_note: NoteData   # 进 fever 的那个音符
var _add_in := 0            # 几帧之后检查换段那一拍有没有音符
var _sfx: AudioStreamPlayer


## 打中了换段音符：放它自己的音效
func _on_note_judged(note: NoteData, result: int, _diff: float) -> void:
	if enabled and change_note_sfx and result != NoteData.Result.MISS and _fever_at >= 0.0 and kind_of(note) == Kind.FEVER:
		_sfx.stream = change_note_sfx
		_sfx.volume_db = change_note_sfx_db
		_sfx.play()


func _ready() -> void:
	Conductor.song_started.connect(_forget)
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	var judge := get_tree().current_scene.get_node_or_null("Judge") if get_tree().current_scene else null
	if judge and judge.has_signal("note_judged"):
		judge.connect("note_judged", _on_note_judged)
	Music.fever_ended.connect(func() -> void: _fever_at = -1.0)
	Music.change_planned.connect(func(kind: String, _id: int, _fill: float, commit: float) -> void:
		if (kind == "fever" and fever) or (kind == "tier" and _id in rainbow_on_tiers):
			_fever_at = commit
			_fever_note = null
			_add_in = 2)   # 过两帧再看要不要加音符：关卡可能就在这一下换谱（天空关），等它换完


func _process(_delta: float) -> void:
	if _add_in <= 0:
		return
	_add_in -= 1
	if _add_in > 0 or not enabled or not add_change_note or _fever_at < 0.0:
		return
	for n in notes:
		if not n.judged and absf(n.beat - _fever_at) <= add_note_gap:
			return   # 那一拍上（或者紧挨着）有音符：它就是换段音符
	var judge := get_tree().current_scene.get_node_or_null("Judge") if get_tree().current_scene else null
	if judge and judge.has_method("add_note"):
		_fever_note = judge.add_note(_fever_at)
		# 关卡手里的音符表通常就是判定那一份（加进去了）；不是同一份的话补进去，按拍子排好
		if _fever_note and not notes.has(_fever_note):
			var i := notes.size()
			while i > 0 and notes[i - 1].beat > _fever_note.beat:
				i -= 1
			notes.insert(i, _fever_note)


## 小关自己指定换段音符落在第几拍（比如洗衣机谱面放完、过门进来的那一拍），和进 fever 的那一个同一种样子和音效
func mark_change(beat: float) -> void:
	_fever_at = beat
	_fever_note = null
	_add_in = 2


func _forget() -> void:
	_kinds.clear()
	_fever_at = -1.0
	_fever_note = null


## 这个音符是哪一种
func kind_of(n: NoteData) -> Kind:
	if not enabled:
		return Kind.NONE
	# 换段音符：进 fever（或者 rainbow_on_tiers 里写的那一档）的那条小节线上的音符——新的一段进来的那一拍。
	# 那一拍上没有音符就取之后一小节里的第一个。这一种要等积累条过线才知道，所以它是唯一会在音符飞过来的途中变样子的。
	if _fever_at >= 0.0 and n.beat >= _fever_at - 0.01 and n.beat < _fever_at + 4.0:
		if _fever_note == null or n.beat < _fever_note.beat:
			_fever_note = n
		if n == _fever_note:
			return Kind.FEVER
	if not _kinds.has(n):
		if _kinds.size() > 4000:
			_kinds.clear()
		_kinds[n] = _decide(n)
	return _kinds[n]


func _off_beat(beat: float) -> bool:
	return absf(beat - roundf(beat)) > 0.05


func _decide(n: NoteData) -> Kind:
	if lead_in:
		var plan: Dictionary = Music.planned_change()
		if not plan.is_empty() and (plan.kind == "fever" or not lead_in_fever_only):
			var commit := float(plan.commit_beat)
			if n.beat >= commit - lead_in_beats - 0.01 and n.beat <= commit + 0.01:
				return Kind.LEAD_IN
	var in_bar := fposmod(n.beat, 4.0)
	var step := in_bar * 4.0
	if accent and absf(step - roundf(step)) < 0.05:
		var groove: Dictionary = Music.events.groove(Music.events.groove_of(Music.playing_clip("beat")))
		if float(int(roundf(step)) % 16) in groove.get("clap", []):
			return Kind.ACCENT
	if syncopated and _off_beat(n.beat):
		# 一串连着的切分音（一个接一个都不在整拍上，相邻两个隔不到 syncopated_gap 拍）只标第一个
		var i := notes.find(n)
		if i >= 0:
			var first := i == 0 or not _off_beat(notes[i - 1].beat) or n.beat - notes[i - 1].beat > syncopated_gap
			var run := 1
			while i + run < notes.size() and _off_beat(notes[i + run].beat) and notes[i + run].beat - notes[i + run - 1].beat <= syncopated_gap:
				run += 1
			if first and run >= syncopated_min_run:
				return Kind.SYNCOPATED
	if downbeat and (in_bar < 0.05 or in_bar > 3.95):
		return Kind.DOWNBEAT
	return Kind.NONE


## 这个音符该长什么样。base = 它原来的颜色。
## 返回 {"kind", "color", "width"（粗细乘多少）, "glow"（0~1，外面常亮的柔光）, "echo"（要不要多画一圈细的）,
##        "rainbow"（七彩：能用材质的地方用 rainbow_material() 画成白色；不能的地方直接用 color，它是一个一直在转的颜色）}
func look(n: NoteData, base: Color) -> Dictionary:
	var out := {"kind": kind_of(n), "color": base, "width": 1.0, "glow": 0.0, "echo": false, "rainbow": false}
	var own_color := n.color.a > 0.0   # 谱面里指定了颜色：不改色
	match out.kind:
		Kind.DOWNBEAT:
			out.color = base if own_color else base.lerp(downbeat_color, downbeat_tint)
			out.width = downbeat_width
		Kind.ACCENT:
			out.color = base if own_color else base.lerp(accent_color, accent_tint)
			out.width = accent_width
			out.glow = accent_glow
		Kind.SYNCOPATED:
			out.color = base if own_color else base.lerp(syncopated_color, syncopated_tint)
			out.width = syncopated_width
			out.echo = syncopated_echo
		Kind.FEVER:
			out.rainbow = true
			out.color = Color.from_hsv(fposmod(Time.get_ticks_msec() / 1000.0 * rainbow_speed + n.beat * 0.13, 1.0), 0.75, 1.0)
			out.width = fever_width
			out.glow = fever_glow
		Kind.LEAD_IN:
			var c := base if own_color else base.lerp(lead_in_color, lead_in_tint)
			# 每拍闪一下：拍点上最亮
			var pulse := pow(1.0 - fposmod(Conductor.song_beat, 1.0), 2.0)
			out.color = c.lerp(Color.WHITE, lead_in_flash * pulse)
			out.width = lead_in_width * (1.0 + 0.25 * lead_in_flash * pulse)
			out.glow = 0.4 + 0.6 * lead_in_flash * pulse
	return out


var _rainbow: ShaderMaterial

## 七彩音符的材质（大家共用一份）。center = 彩虹的中心，画这些音符的那个节点自己的坐标。
func rainbow_material(center := Vector2.ZERO) -> ShaderMaterial:
	if _rainbow == null:
		_rainbow = ShaderMaterial.new()
		_rainbow.shader = preload("res://scripts/fx/note_rainbow.gdshader")
	_rainbow.set_shader_parameter("center", center)
	_rainbow.set_shader_parameter("speed", rainbow_speed)
	_rainbow.set_shader_parameter("bands", rainbow_bands)
	_rainbow.set_shader_parameter("radial", rainbow_radial)
	_rainbow.set_shader_parameter("lift", rainbow_lift)
	_rainbow.set_shader_parameter("sparkle", rainbow_sparkle)
	return _rainbow
