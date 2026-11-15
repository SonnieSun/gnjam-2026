class_name Y2kBurstStyle
extends Resource
## Y2kBurst 的可调参数：用哪些形状、外发光多强、飞多快多大。
## 形状图在 shapes/ 里，每张 xxx.png 旁边有一张烘好的 xxx_glow.png（外发光），按文件名自动配对。

## 飞出来的形状（只放本体图，不放 _glow 图）
@export var shapes: Array[Texture2D] = []
## 形状图四周留给外发光的空白（像素），切图时定的，别改
@export var texture_pad := 28.0

@export_group("颜色")
## 形状图是纯白的，每个形状从这里随机挑一组颜色附上（像 Unity 粒子的 Start Color）
## 本体颜色：浅、亮
@export var colors: Array[Color] = [
	Color(1.0, 0.8, 0.9),    # 浅粉
	Color(0.78, 1.0, 0.98),  # 浅青
	Color(0.86, 0.8, 1.0),   # 淡紫
	Color(1.0, 0.95, 0.74),  # 奶油黄
]
## 光晕颜色：和上面同一行配对，更深、更饱和
@export var glow_colors: Array[Color] = [
	Color(1.0, 0.12, 0.5),   # 桃红
	Color(0.0, 0.78, 0.68),  # 蓝绿
	Color(0.5, 0.2, 1.0),    # 紫
	Color(1.0, 0.55, 0.05),  # 橙黄
]

@export_group("外发光")
## 光晕浓度（叠加混合，太高会烧成白色）
@export_range(0.0, 3.0) var glow_strength := 1.0
## 光晕整体放大（光晕图已经自带大范围淡出，一般保持 1）
@export_range(0.5, 2.0) var glow_scale := 1.0
@export_group("本体")
## 本体不透明度（略带半透明）
@export_range(0.0, 1.0) var core_alpha := 0.85

@export_group("Perfect")
@export var perfect_count := 10
## 每个形状各自在这个区间里随机抽最长边大小（像素）
@export var perfect_size := Vector2(16.0, 84.0)
@export var perfect_speed := Vector2(200.0, 380.0)
@export var perfect_lifetime := 0.6
@export_group("Good")
@export var good_count := 5
@export var good_size := Vector2(10.0, 42.0)
@export var good_speed := Vector2(90.0, 170.0)
@export var good_lifetime := 0.45
## Good 整体再淡一点
@export_range(0.0, 1.0) var good_alpha := 0.7

@export_group("运动")
## 每个形状随机自转的最大速度（弧度/秒）
@export var spin_max := 5.0
## 到最后缩到原来的多少
@export_range(0.0, 1.0) var end_scale := 0.4
