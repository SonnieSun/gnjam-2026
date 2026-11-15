class_name BeatDecor
extends RefCounted
## 给装饰物接 BeatFx 的几种常用接法（一行一个），省得每个地方都写一长串参数。
## 接上的都带 tag "decor"，所以可以整体调：BeatFx.set_gain("decor", 0.0) 全关，1 正常，> 1 更猛。
##
## 只给**装饰**用（电视机、纸片、星星、小行星、光球这些）；主体（猫、地球、洗衣机、披萨）不接。
## 都用"胀一下"（SCALE）：它不挑材质。注意它每帧会改那个节点的 scale，所以要接在**自己不做缩放动画**的节点上
## （代码每帧在改它 transform / scale 的，就接到它的子节点或外面包的一层上）。
##
##   BeatDecor.bop(node, 0.1)                 每拍胀一下
##   BeatDecor.kick(node, 0.12) / snare / hat  跟谱面里的底鼓 / 军鼓 / 镲（每关谱面不同，所以每关动得不一样）
##   BeatDecor.stagger(node, i, 0.08)         一堆东西错落着动：第 i 个用第 i 种节奏（见 PATTERNS），不会整齐得像一块
##   BeatDecor.wave(nodes, 0.15, 2.0)         一圈 / 一排东西依次胀过去，一圈走完用 2 拍
##   BeatDecor.light(lamp, 0.8)               灯跟着底鼓亮一下

const TAG := "decor"


## 每 every_beats 拍胀一下（offset = 错开多少拍）
static func bop(node: Node, amount := 0.1, every_beats := 1.0, offset := 0.0, decay_beats := 0.5) -> BeatFx:
	return BeatFx.attach(node, {"source": BeatFx.Source.BEAT, "every_beats": every_beats, "beat_offset": offset,
		"effect": BeatFx.Effect.SCALE, "amount": amount, "decay_beats": decay_beats, "tag": TAG})


## 跟谱面里的鼓胀一下：sound = 0 底鼓，1 军鼓，2 镲，3 任何一下
static func chart(node: Node, sound: int, amount := 0.1, decay_beats := 0.5) -> BeatFx:
	return BeatFx.attach(node, {"source": BeatFx.Source.CHART, "chart_sound": sound,
		"effect": BeatFx.Effect.SCALE, "amount": amount, "decay_beats": decay_beats, "tag": TAG})


static func kick(node: Node, amount := 0.12) -> BeatFx:
	return chart(node, 0, amount)


static func snare(node: Node, amount := 0.1) -> BeatFx:
	return chart(node, 1, amount)


static func hat(node: Node, amount := 0.06) -> BeatFx:
	return chart(node, 2, amount, 0.25)


## 错落用的几种节奏：[每几拍一下, 错开几拍, 幅度倍数, 多少拍收回去]。
## 每几拍 = 0 表示跟谱面的鼓（错开那一格这时是哪种鼓：0 底鼓，1 军鼓）。
## 顺序是故意打乱的：相邻两个东西尽量不同时动；动得少的（每 2 拍、每 4 拍）幅度大一点。
const PATTERNS := [
	[1.0, 0.0, 1.0, 0.5],    # 每拍，正拍
	[2.0, 1.0, 1.5, 0.8],    # 第 2、4 拍（像军鼓的位置）
	[1.0, 0.5, 0.7, 0.35],   # 每拍，反拍，轻一点
	[1.5, 0.0, 1.1, 0.5],    # 每一拍半一下（三对二，跟别的慢慢错开又对上）
	[2.0, 0.0, 1.5, 0.8],    # 第 1、3 拍
	[4.0, 3.0, 2.0, 1.0],    # 每小节最后一拍，大一下
	[0.5, 0.0, 0.45, 0.25],  # 每半拍，小碎动
	[4.0, 1.5, 1.6, 0.6],    # 每小节第 2 拍后半，一下
	[2.0, 1.5, 1.2, 0.5],    # 第 2 拍后半、第 4 拍后半（切分）
	[4.0, 0.0, 2.0, 1.5],    # 每小节第一拍，大一下慢慢收
]


## 一堆东西里的第 i 个：用第 i 种节奏（PATTERNS 轮着用），整体看起来错落。i 可以是序号，也可以是随便一个随机数。
static func stagger(node: Node, i: int, amount := 0.08) -> BeatFx:
	var p: Array = PATTERNS[absi(i) % PATTERNS.size()]
	if p[0] <= 0.0:
		return chart(node, int(p[1]), amount * p[2], p[3])
	return bop(node, amount * p[2], p[0], p[1], p[3])


## 一圈 / 一排东西依次胀过去：lap_beats 拍走完一圈
static func wave(nodes: Array, amount := 0.15, lap_beats := 2.0) -> void:
	for i in nodes.size():
		if nodes[i] is Node:
			bop(nodes[i], amount, lap_beats, lap_beats * i / maxi(nodes.size(), 1), 0.4)


## 灯跟着谱面的底鼓亮一下（amount = 亮多少倍）
static func light(lamp: Node, amount := 0.8) -> BeatFx:
	return BeatFx.attach(lamp, {"source": BeatFx.Source.CHART, "chart_sound": 0,
		"effect": BeatFx.Effect.LIGHT, "amount": amount, "decay_beats": 0.5, "tag": TAG})
