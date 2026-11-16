class_name SpaceShooterScore
extends Resource
## 太空打飞机这一段自己的算分规则（只管数，不管显示）。
## 这一段的分数完全看打掉了多少星球，和 Perfect / Miss 无关：进关时把 Judge.accuracy_share 设成 0，
## 每打掉一颗星球立刻用 Judge.add_bonus() 加 kill_points()，加满 stage_points 为止。
## 被星球撞到一次立刻扣 crash_penalty。

## 这一段的满分。进关时会换成 Judge.stage_max()（大关满分 × 这一段的占比），这里只是读不到时的备用值
@export var stage_points := 285000
## 这一段大约会飞来多少颗星球；全打掉正好拿满 stage_points
@export var expected_planets := 20
## 猫被星球撞到一次扣多少分
@export var crash_penalty := 5000

var kills := 0     # 打掉的星球
var escaped := 0   # 没打掉、飞走的星球
var crashes := 0   # 撞到猫的星球
var awarded := 0   # 打星球已经加了多少分
var counted := 0   # 已经记进“能拿的分”的有多少

## 交给下一段（披萨猫过圈）的接力数据：{"curtain": 结尾落下来盖满画面的黑幕}，下一段开头让它落出屏幕
static var handoff := {}


func planets_done() -> int:
	return kills + escaped + crashes


## 打掉一颗值多少分
func kill_points() -> int:
	return roundi(float(stage_points) / maxi(expected_planets, 1))


## 打掉一颗：返回这次实际加多少（总共不超过 stage_points）
func take_kill() -> int:
	var p := mini(kill_points(), stage_points - awarded)
	awarded += p
	return p


## 一颗星球有了结果：返回要记进“能拿的分”的数（总共不超过 stage_points）
func take_possible() -> int:
	var p := mini(kill_points(), stage_points - counted)
	counted += p
	return p


## 这一段结束时，还没记进“能拿的分”的剩下多少（一次补齐，评级才不会偏高）
func take_rest_possible() -> int:
	var p := stage_points - counted
	counted = stage_points
	return p
