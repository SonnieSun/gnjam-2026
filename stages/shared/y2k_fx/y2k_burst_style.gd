class_name Y2kBurstStyle
extends Resource
## Y2kBurst 的可调参数：用哪些形状、外发光多强、飞多快多大。
## 形状图在 shapes/ 里，每张 xxx.png 旁边有一张烘好的 xxx_glow.png（外发光），按文件名自动配对。

## 飞出来的形状（只放本体图，不放 _glow 图）
@export var shapes: Array[Texture2D] = []
## 形状图四周留给外发光的空白（像素），切图时定的，别改
@export var texture_pad := 28.0

@export_group("颜色")
## 形状图是纯白的，每个形状从这里随机挑一个颜色附上（像 Unity 粒子的 Start Color）
@export var colors: Array[Color] = [
	Color(1.0, 0.1, 0.62),   # 粉
	Color(1.0, 0.72, 0.5),   # 桃
	Color(0.3, 0.78, 1.0),   # 天蓝
	Color(0.4, 1.0, 1.0),    # 青
	Color(0.1, 0.5, 1.0),    # 蓝
	Color(0.55, 0.55, 1.0),  # 紫
]

@export_group("外发光")
## 外发光亮度（叠加混合）
@export_range(0.0, 3.0) var glow_strength := 1.4
## 外发光 = 附上的颜色 × 这个值（1 = 和本体一样亮，越小越暗）
@export_range(0.0, 1.0) var glow_brightness := 0.5
## 外发光比本体大多少
@export_range(1.0, 2.0) var glow_scale := 1.15
@export_group("本体")
## 本体不透明度（半透明感）
@export_range(0.0, 1.0) var core_alpha := 0.95

@export_group("Perfect")
@export var perfect_count := 10
@export var perfect_size := Vector2(34.0, 68.0)
@export var perfect_speed := Vector2(200.0, 380.0)
@export var perfect_lifetime := 0.6
@export_group("Good")
@export var good_count := 5
@export var good_size := Vector2(20.0, 36.0)
@export var good_speed := Vector2(90.0, 170.0)
@export var good_lifetime := 0.45
## Good 整体再淡一点
@export_range(0.0, 1.0) var good_alpha := 0.7

@export_group("运动")
## 每个形状随机自转的最大速度（弧度/秒）
@export var spin_max := 5.0
## 到最后缩到原来的多少
@export_range(0.0, 1.0) var end_scale := 0.4
