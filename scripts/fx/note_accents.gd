class_name NoteAccents
extends Node
## 音符的重点标记：按音符在音乐里的位置，告诉画音符的地方"这个音符是哪一种"，以及它该长什么样。
## 不改判定，不改谱面，只管样子。放进小关的场景里（节点名 NoteAccents），画音符的脚本来问它：
##     var look := accents.look(note, 原来的颜色)   # {"kind", "color", "width", "glow", "echo", "rainbow"}
##
## 五种（一个音符同时算好几种时，按下面从上到下的顺序取第一种）：
##   FEVER       fever 里的音符，和进 fever 之前 lead_in_beats 拍里的音符：动态七彩（scripts/fx/note_rainbow.gdshader）。
##   LEAD_IN     音乐马上要换段了（升档 / 进 fever，Music.planned_change() 排好的那次）：换之前 lead_in_beats 拍里的音符，
##               和正好落在换段那一拍上的音符。要等积累条过了线才知道，所以通常只管到最后一小节左右。
##   ACCENT      重音：落在现在这套鼓型的拍手上（听得见的那一下）。
##   SYNCOPATED  切分：不在整拍上（半拍、十六分）。
##   DOWNBEAT    小节线：一小节的第一拍。
## 谱面里给音符单独指定了颜色的（NoteData.color），颜色听谱面的，这里只加粗细和光。
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
@export_group("切分音（不在整拍上）")
@export var syncopated := true
@export var syncopated_color := Color(0.45, 1.0, 0.95)
@export_range(0.0, 1.0) var syncopated_tint := 0.75
@export var syncopated_width := 0.8
## 外面多画一圈细的"回声"圈（看起来是双圈），一眼能和整拍的音符分开
@export var syncopated_echo := true
@export_group("fever 的音符（七彩）")
## fever 里的音符，和进 fever 之前 lead_in_beats 拍里的音符
@export var fever := true
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
@export var lead_in := true
## 换段之前多少拍里的音符算
@export var lead_in_beats := 4.0
## 只管进 fever（关掉 = 升档也算）
@export var lead_in_fever_only := false
@export var lead_in_color := Color(1.0, 0.85, 0.2)
@export_range(0.0, 1.0) var lead_in_tint := 0.9
@export var lead_in_width := 1.5
## 每拍闪一下的幅度（0 = 不闪）
@export_range(0.0, 1.0) var lead_in_flash := 0.5


## 这个音符是哪一种
func kind_of(n: NoteData) -> Kind:
	if not enabled:
		return Kind.NONE
	var plan: Dictionary = Music.planned_change()
	if fever:
		if Music.fever:
			return Kind.FEVER
		if not plan.is_empty() and plan.kind == "fever" and n.beat >= float(plan.commit_beat) - lead_in_beats - 0.01:
			return Kind.FEVER
	if lead_in:
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
	if syncopated and absf(in_bar - roundf(in_bar)) > 0.05:
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
