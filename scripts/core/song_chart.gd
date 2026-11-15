@tool
class_name SongChart
extends Resource
## 一个大关：一首循环播放的伴奏 + 按顺序闯的若干小关（sections）。
## 小关不限时：每个小关的鼓谱一直循环，积累条满了才进下一个（见 gauge.gd 和 main.gd）。
##
## 每个大关存成 levels/ 文件夹里的一个 .tres 文件，在编辑器里双击它，就能在检查器里编辑：
## 用哪首歌、有哪些小关、顺序、每个小关的场景 / 谱子 / 积累条。怎么编辑见 levels/README.md。

## 主菜单上显示的名字
@export var title := ""
## 这一大关里 3D 小关默认的画面风格（游戏里按 C 可以临时切换着看）
@export_enum("OFF", "HALFTONE", "HATCH", "FLAT", "PRINT", "Y2K", "Y2K_JPEG") var look := "OFF"

## 背景音乐（不带鼓的版本，鼓由玩家打）。
## 留空时 Conductor 会自动生成占位伴奏，方便没有歌时先开发
@export var stream: AudioStream
@export var bpm := 160.0
@export var beats_per_bar := 4
## 音频文件里第一拍出现的时间（秒）
@export var first_beat_offset_sec := 0.0
## 这首歌专用的鼓音色（玩家按键时发出）。留空则用 DrumKit 节点上的默认音色。
@export var drum_kick: AudioStream
@export var drum_snare: AudioStream
@export var drum_hat: AudioStream
## 每进一个小关，先空几个小节再出音符（让玩家看清新画面）
@export var rest_bars_on_switch := 1
@export var sections: Array[SectionDef] = []


## 根据各段长度计算每段的 start_beat。改完 sections 后调用一次。
func recompute() -> void:
	var b := 0.0
	for s in sections:
		s.start_beat = b
		s.length = s.length_beats(beats_per_bar)
		b += s.length


func total_beats() -> float:
	if sections.is_empty():
		return 0.0
	var last := sections[-1]
	return last.start_beat + last.length_beats(beats_per_bar)


func section_index_at(beat: float) -> int:
	var idx := 0
	for i in sections.size():
		if beat >= sections[i].start_beat:
			idx = i
	return idx


## 展开成按时间排序的全曲音符列表
func build_notes() -> Array[NoteData]:
	var out: Array[NoteData] = []
	for i in sections.size():
		var s := sections[i]
		for d in s.parse_notes(beats_per_bar):
			var n := NoteData.new()
			n.beat = s.start_beat + d.beat
			n.sound = d.sound
			n.section_index = i
			out.append(n)
	return out
