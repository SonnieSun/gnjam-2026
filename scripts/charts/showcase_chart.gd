class_name ShowcaseChart
extends RefCounted
## 关卡展示：用 electronic-fantasy（120 BPM，96 秒）把所有关卡画法轮流放一遍，
## 每关 3 小节（6 秒），音乐一直往下放不中断。8 种画法，全曲轮两遍。
##
## 鼓谱是手写的，每关一句、每句都不一样：以四分音符为主，夹着切分、休止和偶尔的
## 八分连打，最密也只到八分音符（0.25 秒一下）。改节奏直接改下面两张表。
## 谱面字符：k = 底鼓  s = 军鼓  h = 踩镲  . = 休止，每小节 16 格。
## 除了全曲第一关，每关第一小节的第一拍都空着，让玩家看清新画面。

## 第一遍：每关 3 小节
const ROUND_1 := [
	["k...s...k...s...", "k...s.....k.s...", "k.....k.....s..."],  # 1 LICK
	["....s...k.k.s...", "k.......s...k...", "k...s.s.....s..."],  # 2 SHRINK
	["....h...s...k...", "k.h.s.......h.s.", "k.....s.h...s..."],  # 3 TRIPLE
	["....k.....s.....", "k.k...s...k.s...", "k.....k...s.s..."],  # 4 ORBIT
	["....s...k.....s.", "..k...s...k...s.", "k...k...s......."],  # 5 CLOCK
	["....k...s...k...", "s.......k.k.....", "k.....k.....k.s."],  # 6 RIPPLE
	["....k...h...s...", "k.h...s...h.k...", "s...k.h.....k..."],  # 7 RINGS
	["....k.......s...", "k.......s.......", "k.....s.....k..."],  # 8 MOON
]

## 第二遍：同样的关卡，换一套稍微活泼一点的节奏
const ROUND_2 := [
	["....s...k.k.s...", "k.....s...k.....", "k.k...s.....s.s."],  # 1 LICK
	["....k.....k.s...", "s...k.......k...", "k...s...k.k.s..."],  # 2 SHRINK
	["....s.h.k.......", "k...h...s.h.....", "k.s...h...k.s..."],  # 3 TRIPLE
	["....s.....k.k...", "k.....s.k.....s.", "k...k.....s....."],  # 4 ORBIT
	["....k.k.....s...", "k...s.......k.s.", "..k...k...s....."],  # 5 CLOCK
	["....s.....s.k...", "k.....k.s.......", "k...s.....k.s..."],  # 6 RIPPLE
	["....h.k...s.....", "k...s.h.....h...", "k.h.s.....k.s..."],  # 7 RINGS
	["....s.......k...", "k.....k.....s...", "s.......k......."],  # 8 MOON
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

	# [标题, 场景, 转一圈的拍数（越大转得越慢）]
	var levels := [
		["1 LICK", preload("res://scenes/sections/lick.tscn"), 8.0],
		["2 SHRINK", preload("res://scenes/sections/earth.tscn"), 8.0],
		["3 TRIPLE", preload("res://scenes/sections/tail.tscn"), 4.0],
		["4 ORBIT", preload("res://scenes/sections/orbit.tscn"), 8.0],
		["5 CLOCK", preload("res://scenes/sections/clock.tscn"), 8.0],
		["6 RIPPLE", preload("res://scenes/sections/ripple.tscn"), 8.0],
		["7 RINGS", preload("res://scenes/sections/rings.tscn"), 8.0],
		["8 MOON", preload("res://scenes/sections/moon.tscn"), 8.0],
	]
	for round_bars in [ROUND_1, ROUND_2]:
		for i in levels.size():
			var s := SectionDef.new()
			s.title = levels[i][0]
			s.scene = levels[i][1]
			s.beats_per_rev = levels[i][2]
			s.bars = PackedStringArray(round_bars[i])
			c.sections.append(s)
	c.recompute()
	return c
