extends Node
## 缩圈 + 转圈猫 的测试入口（F6 运行）。
## 直接借用 Sonnie 的主场景（HUD、判定、鼓声、星星特效都现成），只把谱面换成下面这一关反复打。
## 不改 main.tscn / main.gd，只调用它们已有的方法。
## 测试用，只在本机 _sandbox 里，不进仓库。

## 关卡场景
@export var section_scene: PackedScene = preload("res://_sandbox/spin_cat/spin_ring.tscn")
## 转一圈的拍数
@export var beats_per_rev := 8.0
## 谱面：每个字符串一小节（k 底鼓 / s 军鼓 / h 踩镲 / . 休止，16 格）
@export var bars := PackedStringArray([
	"k.......k.......", "k.......k.......", "k...k...k...k...", "k...s...k...s...",
	"....s...k.k.s...", "k.......s...k...", "k...s.s.....s...", "k...s...k.k.s...",
	"....k.....k.s...", "s...k.......k...", "k...s...k.k.s...", "k.k...s.....s.s.",
	"k...s...k...s...", "k.k.s...k.k.s...", "k...s.s.k...s.s.", "k.......k.......",
])


func _ready() -> void:
	var main = preload("res://main.tscn").instantiate()
	add_child(main)  # main 的 _ready 会先按默认谱面开一次，下面马上换掉

	var c := SongChart.new()
	c.stream = preload("res://assets/fantasy/backing_no_drums.ogg")
	c.bpm = 120.0
	c.beats_per_bar = 4
	c.drum_kick = preload("res://assets/fantasy/kick.wav")
	c.drum_snare = preload("res://assets/fantasy/snare.wav")
	c.drum_hat = preload("res://assets/fantasy/hat.wav")
	var s := SectionDef.new()
	s.title = "SPIN CAT"
	s.scene = section_scene
	s.beats_per_rev = beats_per_rev
	s.bars = bars
	c.sections.append(s)
	c.recompute()

	main.chart = c
	main.drum_kit.use_chart(c)
	Conductor.load_chart(c)
	main.judge.load_chart(c)
	main.start_from(0)
