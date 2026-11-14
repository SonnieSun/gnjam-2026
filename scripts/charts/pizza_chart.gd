class_name PizzaChart
extends RefCounted
## 披萨猫：只有一个小关（scenes/sections/pizza.tscn），画面分三段，跟着积累条走：
## 侧面转到正面（约 10 秒）→ 九宫格（约 5 秒）→ 万花筒（约 10 秒），满条通关。
## 每段多长由场景根节点“积累条”一栏里的满条值和事件分数线决定（默认 250 分满，100 / 150 分换画面）。
## 120 BPM，每拍一下，底鼓和军鼓交替；伴奏沿用猫咪 MV 那首不带鼓的版本。

const BEAT := "k...s...k...s..."


static func build() -> SongChart:
	var c := SongChart.new()
	c.stream = preload("res://assets/mv/mv_no_drums.ogg")
	c.bpm = 120.0
	c.beats_per_bar = 4
	c.first_beat_offset_sec = 0.0
	c.drum_kick = preload("res://assets/mv/kick.wav")
	c.drum_snare = preload("res://assets/mv/snare.wav")
	c.drum_hat = preload("res://assets/mv/hat.wav")

	var s := SectionDef.new()
	s.title = "PIZZA CAT"
	s.scene = load("res://scenes/sections/pizza.tscn")
	s.beats_per_rev = 8.0
	s.bars = PackedStringArray([BEAT, BEAT])
	s.transition = SectionDef.Transition.CUT
	c.sections.append(s)
	c.recompute()
	return c
