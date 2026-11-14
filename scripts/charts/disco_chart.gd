class_name DiscoChart
extends RefCounted
## 第 1 大关：迪斯科猫砂盆（关卡在 _sandbox/spin_cat/ 里，舞台演出见那里的 disco_section.gd / disco_stage.gd）。
## 只有一个小关：积累条到 20 星星灯掉下来，到 40 迪斯科灯球掉下来，满 60 通关。
## 这两个分数在 _sandbox/spin_cat/disco.tscn 根节点的 gauge_events 里改。
## 伴奏用 electronic-fantasy（120 BPM，循环播放）。
## 谱面字符：k = 底鼓  s = 军鼓  h = 踩镲  . = 休止，每小节 16 格；下面这几小节一直循环。

const BARS := [
	"k.......k.......",
	"k...k...k...k...",
	"k...s...k...s...",
	"k...s...k.k.s...",
]


static func build() -> SongChart:
	var c := SongChart.new()
	c.stream = preload("res://assets/fantasy/backing_no_drums.ogg")
	c.bpm = 120.0
	c.beats_per_bar = 4
	c.first_beat_offset_sec = 0.0
	c.drum_kick = preload("res://assets/fantasy/kick.wav")
	c.drum_snare = preload("res://assets/fantasy/snare.wav")
	c.drum_hat = preload("res://assets/fantasy/hat.wav")

	var s := SectionDef.new()
	s.title = "DISCO"
	s.scene = preload("res://_sandbox/spin_cat/disco.tscn")
	s.beats_per_rev = 8.0
	s.bars = PackedStringArray(BARS)
	c.sections.append(s)
	c.recompute()
	return c
