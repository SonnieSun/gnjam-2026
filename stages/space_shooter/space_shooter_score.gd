class_name SpaceShooterScore
extends Resource
## 太空打飞机这一关自己的算分规则（只管数，不管显示）。
## 准确率部分照常由 Judge 在小关打完时入账，但只占这一大关满分的 accuracy_share（默认 80%）；
## 剩下的靠打星球：每打掉一颗立刻加 kill_points，被星球撞到一次立刻扣 crash_penalty（不算进准确率）。
## 评级按「拿到的分 ÷ 能拿的分」算，所以每颗有了结果的星球都会把 kill_points 记进“能拿的分”。

## 准确率部分占这一大关满分的比例
@export_range(0.0, 1.0, 0.05) var accuracy_share := 0.8
## 打掉一颗星球立刻加多少分。
## 现在第 3 大关有两段，打星球这段占大关满分约 28.6 万（按两段满条值 100 : 250 分），
## 其中 20% ≈ 5.7 万留给星球；这一段大约飞来 19 颗，所以每颗 3000。两段的满条值或星球数变了要跟着改。
@export var kill_points := 3000
## 猫被星球撞到一次扣多少分
@export var crash_penalty := 3000

var kills := 0     # 打掉的星球
var escaped := 0   # 没打掉、飞走的星球
var crashes := 0   # 撞到猫的星球


func planets_done() -> int:
	return kills + escaped + crashes
