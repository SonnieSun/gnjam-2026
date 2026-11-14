class_name SongChart
extends Resource
## 整首歌：一个音频 + 若干首尾相接的段落。

## 背景音乐（不带鼓的版本，鼓由玩家打）。
## 留空时 Conductor 会自动生成占位伴奏，方便没有歌时先开发
@export var stream: AudioStream
@export var bpm := 120.0
@export var beats_per_bar := 4
## 音频文件里第一拍出现的时间（秒）
@export var first_beat_offset_sec := 0.0
## 这首歌专用的鼓音色（玩家按键时发出）。留空则用 DrumKit 节点上的默认音色。
@export var drum_kick: AudioStream
@export var drum_snare: AudioStream
@export var drum_hat: AudioStream
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
