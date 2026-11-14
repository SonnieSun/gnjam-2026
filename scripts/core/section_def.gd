@tool
class_name SectionDef
extends Resource
## 一个旋转段落（关卡）的定义：用哪个场景、转一圈几拍、谱面。

## 切到这一段时的转场：ZOOM = 旧的放大淡出、新的从中心长出来；CUT = 硬切 + 白闪
enum Transition { ZOOM, CUT }

@export var title := ""
@export var scene: PackedScene
## 转一整圈需要多少拍。旋转角度 = 段内拍数 / beats_per_rev * TAU
@export var beats_per_rev := 4.0
## 谱面：每个字符串是一小节，按字符数等分。
##   k = 底鼓  s = 军鼓  h = 踩镲  （x 等同于 k）  其他字符 = 休止
## 例如 "k...s...k.k.s..." = 十六分音符网格。空字符串 = 整小节休止。
## 段落长度 = 小节数。
@export var bars: PackedStringArray = []

@export var transition: Transition = Transition.ZOOM

## 由 SongChart.recompute() 填入
var start_beat := 0.0
## 这一段总共多少拍（由 SongChart.recompute() 填入）
var length := 0.0


func length_beats(beats_per_bar: int) -> float:
	return bars.size() * beats_per_bar


## 返回段内的音符列表，每项是 {"beat": 相对段落开头的拍数, "sound": NoteData.Sound}
func parse_notes(beats_per_bar: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for bar_i in bars.size():
		var s := bars[bar_i]
		for i in s.length():
			var sound := _char_to_sound(s[i])
			if sound >= 0:
				out.append({
					"beat": bar_i * beats_per_bar + float(i) * beats_per_bar / s.length(),
					"sound": sound,
				})
	return out


static func _char_to_sound(ch: String) -> int:
	match ch:
		"k", "x": return NoteData.Sound.KICK
		"s": return NoteData.Sound.SNARE
		"h": return NoteData.Sound.HAT
	return -1
