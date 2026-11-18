@tool
class_name NoteSkin
extends Resource
## 一段谱子的「样子」：挂在 ChartPattern.skin 上，这份谱子铺出来的每个音符都带着它（NoteData.skin，Judge 给的），
## 画音符的地方按音符自己的样子画，所以同一关里不同的段（换谱子 = 换段）可以长得不一样，到了那一段自动换上、走了自动换回。
## 不改判定，只管样子。现在读它的：天空关的舞台（stages/sky/sky_stage.gd，光柱里落下来的光圈）。
## 别的舞台 / 表现方式要用，读 note.skin 就行（没挂 = null = 和原来一样）。
##
## 例子：levels/skins/doom.tres（天空关风暴那一段的末日重金属：粗粗的岩浆圈、往上飘的火星、暗红暗角、高一点的对比度）。
##
## 音符上还有一个「记号」（NoteData.mark，谱面编辑器里按音符改）：自动 / 普通 / 三连音。
## 自动 = 按这里的规则判（auto_triplets：拍子落在 1/3、2/3 上，或者后面 2/3 拍还有一个的，算四拍三连）。

## 给人看的名字（编辑器里显示）
@export var title := ""

@export_group("音符")
## 光圈的颜色往这个颜色换（alpha = 换多少，0 = 不换）
@export var ring_color := Color(1.0, 0.3, 0.06, 1.0)
## 小节线上的音符（NoteAccents 判的 DOWNBEAT）
@export var downbeat_color := Color(1.0, 0.04, 0.04, 1.0)
## 判定圈
@export var judge_color := Color(1.0, 0.1, 0.08, 1.0)
## 光柱（alpha = 换多少）
@export var beam_color := Color(0.6, 0.03, 0.05, 1.0)
## 光圈多粗（相对半径；比舞台原来的细就不变）
@export_range(0.02, 0.4) var thickness := 0.13
## 岩浆：整圈是上面的颜色，里面暗色的壳（lava_dark）在流动翻滚，壳之间的裂缝发亮（ember_hot）。
## 多少（0 = 没有，1 = 满）、壳的颜色、往前流多快
@export_range(0.0, 1.0) var ember := 0.9
@export var ember_hot := Color(1.0, 0.62, 0.15)
@export var lava_dark := Color(0.14, 0.01, 0.0)
@export var lava_flow := 0.5
## 裂缝多亮（普通的音符收着一点）
@export var crack_glow := 0.7
## 火星：这一段里猫周围往上飘，打中时判定圈上溅一圈（颜色 = ember_hot）
@export var embers := true

@export_group("死亡重金属")
## 甩头：猫每 headbang_every 拍往前点一下头，点多深（度，0 = 不甩）。2 拍 = 跟着半速的军鼓
@export var headbang_degrees := 16.0
@export var headbang_every := 2.0
## 火柱：小节线上的音符、一串三连音的最后一个打中时，画面左右下角往上喷火；喷的时候镜头抖多少
@export var pyro := true
@export var pyro_shake := 0.12
## 频闪：八分连打（连着三个隔半拍的）打中时画面红白交替闪
@export var strobe := true
## 转场音符（这一段第一个带样子的音符，ChartPattern.skin_from_beat）到了那一拍，打没打中都放：
## 岩浆冲击波往外扩到几倍大、镜头往里冲多少（视野的度数）、抖多少
@export var impact_size := 2.2
@export var impact_punch := 9.0
@export var impact_shake := 0.45

@export_group("画面")
## 四周的暗角（0 = 没有）和颜色
@export_range(0.0, 1.0) var vignette := 0.55
@export var vignette_color := Color(0.16, 0.0, 0.02)
## 3D 画面的对比度、饱和度（舞台自己的 Environment，不是全局滤镜；1 = 不变）
@export var contrast := 1.2
@export var saturation := 1.15
## 闪电的光晕往这个颜色换（alpha = 换多少）
@export var bolt_color := Color(1.0, 0.25, 0.15, 1.0)

@export_group("三连音")
## 记号是「自动」的音符，按拍子位置判是不是四拍三连
@export var auto_triplets := true
## 三连音的圈：断成三段的金色岩浆弧，转着往下落，打中时三段一边往外扩一边收短，散成三点
@export var triplet_color := Color(0.95, 0.55, 0.08)
## 三段弧也是岩浆，金色的：裂缝的颜色、壳的颜色、有多少（0 = 纯色发光）、多粗
@export var triplet_hot := Color(1.0, 0.85, 0.45)
@export var triplet_dark := Color(0.28, 0.07, 0.0)
@export_range(0.0, 1.0) var triplet_ember := 0.9
@export_range(0.02, 0.4) var triplet_thickness := 0.15
## 外面再套一圈细的光环：大多少（0.3 = 半径大三成，0 = 不套）、多细
@export var triplet_halo := 0.25
@export_range(0.02, 0.4) var triplet_halo_thickness := 0.06
## 三连音的裂缝多亮、跟拍子胀多少（只胀粗细）、打中时镜头抖多少
@export var triplet_crack_glow := 1.4
@export var triplet_throb := 0.35
@export var triplet_shake := 0.2
## 三段弧每拍转几圈（负数 = 反着转）
@export var triplet_spin := -0.5
