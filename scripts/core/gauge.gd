class_name Gauge
extends Node
## 小关的积累条。打得准就涨，漏打就掉；涨过事先定好的分数线就触发一次事件，涨满就过关。
##
## 每个小关可以有自己的满条值和事件分数线，按下面的顺序取，前面没填就用后面的：
##   1. 谱面里这个小关的 SectionDef.gauge_max / gauge_events
##   2. 关卡场景根节点（检查器“积累条”一栏）的 gauge_max / gauge_events
##   3. 这个节点上的默认值（main.tscn 里选中 Gauge 节点调）
## 加减分的规则（Perfect / Good / Miss）全游戏统一，只在这个节点上调。
##
## 想在触发事件时做点什么：关卡脚本里重写 _on_gauge_event(index, value)，
## 或者接 Main 节点的 gauge_event 信号（加音轨、全局特效）。

## 数值变了（value 当前值，max_value 满条值）
signal changed(value: int, max_value: int)
## 第一次涨过第 index 条分数线（index 从 1 开始），value = 那条线的分数。
## 每条线在一个小关里只触发一次，之后掉下去再涨回来不会重复触发。
signal event(index: int, value: int)
## 涨满了
signal filled

## 默认的满条数值
@export var default_max := 60
## 默认的事件分数线：涨到这些分数时各触发一次事件。可以有任意多条，也可以一条都没有。
@export var default_events := PackedInt32Array([20, 40])
## Perfect / Good 各加多少
@export var perfect_gain := 5
@export var good_gain := 2
## Miss 扣多少（最低扣到 0）
@export var miss_loss := 3

var max_value := 60
## 这个小关的事件分数线（从小到大）
var events := PackedInt32Array()
var value := 0
## 已经触发了几条
var events_fired := 0
var full := false


## 开始一个小关：new_max <= 0 用默认满条值；new_events 传 null 用默认分数线（传空数组 = 这一关没有事件）
func begin(new_max: int = 0, new_events: Variant = null) -> void:
	max_value = new_max if new_max > 0 else default_max
	var list := PackedInt32Array(new_events) if new_events != null else default_events.duplicate()
	list.sort()
	events = PackedInt32Array()
	for v in list:  # 超出范围的线没有意义，去掉
		if v > 0 and v <= max_value:
			events.append(v)
	value = 0
	events_fired = 0
	full = false
	changed.emit(value, max_value)


## 直接把积累条拨到某个数（游戏里的编辑面板拖进度条时用）。不触发事件，也不会过关。
func set_value(new_value: int) -> void:
	value = clampi(new_value, 0, max_value)
	full = false
	changed.emit(value, max_value)


## 按判定结果加减分。满条之后不再变化。
func apply(result: int) -> void:
	if full:
		return
	match result:
		NoteData.Result.PERFECT: value += perfect_gain
		NoteData.Result.GOOD: value += good_gain
		NoteData.Result.MISS: value -= miss_loss
		_: return
	value = clampi(value, 0, max_value)
	changed.emit(value, max_value)
	while events_fired < events.size() and value >= events[events_fired]:
		events_fired += 1
		event.emit(events_fired, events[events_fired - 1])
	if value >= max_value:
		full = true
		filled.emit()
