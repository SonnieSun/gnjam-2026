@tool
class_name ChartPattern
extends Resource
## 一个小关的谱子（谱面编辑器 scenes/tools/chart_editor.tscn 写的）：一段循环的音符，
## 和老的鼓谱字符串（SectionDef.bars）一样一直循环到积累条满，只是每个音符可以带表现属性。
## SectionDef.chart 填了这个，就用它代替 bars（Judge 照常判定，时间只看 beat）。
##
## notes 里每一项是一个字典：
##   beat   这一段里的第几拍（0 起，< length_beats）
##   sound  NoteData.Sound（0 底鼓 / 1 军鼓 / 2 踩镲）
##   其余是表现属性，见 NoteData.STYLE_DEFAULTS（没写的用默认值）：
##   length 长按几拍  lead 提前几拍出现  lane 轨道  color 颜色  size 大小
##   rot 初始角度  spin 自转速度  glow 发光  pulse 跟拍闪  throb 跟拍胀缩

## 循环一遍多少拍
@export var length_beats := 16.0
## 默认用哪种表现（NoteStyle.STYLES 的键）：编辑器预览用，关卡勾了 use_style 时游戏里也用
@export var style := "rings"
## 勾上 = 游戏里这个小关用上面的表现方式画音符（叠在关卡画面上，关卡自己的音符画法关掉）；
## 不勾 = 只用这份谱子的时间，音符还是关卡自己画
@export var use_style := false
## 音符默认提前几拍出现
@export var default_lead := 4.0
## 有几条轨道 / 几个目标
@export_range(1, 8) var lanes := 1
## 轨道式（orbit）：转一圈几拍
@export var beats_per_rev := 8.0
## 节拍辅助线：每拍一条，要按的拍子是彩色实线（越靠近判定越亮越粗），不用按的拍子是淡虚线
@export var beat_guides := true
## 虚线隔几拍一条（1 = 每拍，0.5 = 每半拍）
@export var guide_every := 1.0
@export var notes: Array[Dictionary] = []


## 按拍子排好序的音符（Judge 和各关卡用，格式同 SectionDef.parse_notes）
func parse_notes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in notes:
		if float(d.get("beat", 0.0)) < length_beats:
			out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.beat < b.beat)
	return out


## 从老的鼓谱字符串转过来（"=" 接在音符后面 = 长按）
static func from_bars(bars: PackedStringArray, beats_per_bar: int) -> ChartPattern:
	var p := ChartPattern.new()
	p.length_beats = maxf(bars.size(), 1) * beats_per_bar
	for bar_i in bars.size():
		var s := bars[bar_i]
		var cell := float(beats_per_bar) / maxi(s.length(), 1)
		var i := 0
		while i < s.length():
			var sound := SectionDef._char_to_sound(s[i])
			var run := 0
			while sound >= 0 and i + 1 + run < s.length() and s[i + 1 + run] == "=":
				run += 1
			if sound >= 0:
				var d := {"beat": bar_i * beats_per_bar + i * cell, "sound": sound}
				if run > 0:
					d["length"] = run * cell
				p.notes.append(d)
			i += 1 + run
	return p
