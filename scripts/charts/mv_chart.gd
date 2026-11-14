class_name MvChart
extends RefCounted
## 猫咪 MV 原型（Cat/cat_mv_3d.html）的歌和镜头。
## 120 BPM。音乐是按原型的音色参数离线合成的不带鼓版本（60 拍，循环播放），
## 鼓由玩家打：每拍一下，底鼓和军鼓交替。
## 小关不限时：每个镜头的鼓谱一直循环，积累条满了才切下一个镜头。
##
## 六个镜头：唱片 / 追尾巴 / 拍地球 / 打大猫 / 洗衣机 / 飞碟，镜头之间硬切。
## 谱面字符：k = 底鼓  s = 军鼓  h = 踩镲  . = 休止，每小节 16 格。

const BEAT := "k...s...k...s..."  # 每拍一下


static func build() -> SongChart:
	var c := SongChart.new()
	c.stream = preload("res://assets/mv/mv_no_drums.ogg")
	c.bpm = 120.0
	c.beats_per_bar = 4
	c.first_beat_offset_sec = 0.0
	c.drum_kick = preload("res://assets/mv/kick.wav")
	c.drum_snare = preload("res://assets/mv/snare.wav")
	c.drum_hat = preload("res://assets/mv/hat.wav")

	var cut := SectionDef.Transition.CUT
	c.sections.append(_section("1 DISC", preload("res://scenes/sections/mv_disc.tscn"), [BEAT, BEAT], cut))
	c.sections.append(_section("2 TAIL", preload("res://scenes/sections/mv_tail.tscn"), [BEAT, BEAT], cut))
	c.sections.append(_section("3 EARTH", preload("res://scenes/sections/mv_earth.tscn"), [BEAT, BEAT], cut))
	c.sections.append(_section("4 BIGCAT", preload("res://scenes/sections/mv_bigcat.tscn"), [BEAT, BEAT], cut))
	c.sections.append(_section("5 WASHER", preload("res://scenes/sections/mv_washer.tscn"), [BEAT, BEAT], cut))
	c.sections.append(_section("6 UFO", preload("res://scenes/sections/mv_ufo.tscn"), [BEAT, BEAT], cut))
	c.recompute()
	return c


static func _section(title: String, scene: PackedScene, bars: Array,
		transition: int = SectionDef.Transition.ZOOM) -> SectionDef:
	var s := SectionDef.new()
	s.title = title
	s.scene = scene
	s.beats_per_rev = 8.0
	s.bars = PackedStringArray(bars)
	s.transition = transition
	return s
