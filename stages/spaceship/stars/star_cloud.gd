class_name StarCloud
extends Resource
## 一团星云粒子：朝某个方向、离飞船多远、多大一团，里面撒多少颗、多大、什么颜色。
## 在飞船关卡 Stars 节点的 clouds 列表里加 / 删 / 调。

## 从飞船看出去的方向
@export var direction := Vector3(0.0, 0.0, -1.0)
## 离飞船多远（要比行星出发点远）
@export var distance := 220.0
## 这团有多大（3D 单位），三个方向分开调可以压扁 / 拉长
@export var size := Vector3(90.0, 60.0, 60.0)
## 密度：这团里有多少颗粒子
@export_range(0, 5000) var count := 600
## 越大越往中心挤（0 = 均匀，1 = 很集中）
@export_range(0.0, 1.0) var concentration := 0.6
## 粒子大小范围
@export var particle_size := Vector2(0.8, 3.5)
## 粒子颜色：每颗在这条渐变上随机取一个颜色
@export var colors: Gradient
## 透明度范围（越小越淡，像雾）
@export var alpha := Vector2(0.25, 0.9)
## 几成粒子是带十字星芒的亮星
@export_range(0.0, 1.0) var flare_ratio := 0.04
## 亮星大小范围
@export var flare_size := Vector2(8.0, 20.0)
## 中心那片柔光：大小（0 = 不要）、颜色
@export var glow_size := 160.0
@export var glow_color := Color(0.35, 0.42, 1.0, 0.7)
## 慢慢漂动的幅度（3D 单位）
@export var drift := 1.5
