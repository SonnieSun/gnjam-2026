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
## Perfect / Great / Good 各加多少
@export var perfect_gain := 5
@export var great_gain := 4
@export var good_gain := 2
## Miss 扣多少（最低扣到 0）
@export var miss_loss := 3

## 涨跌的倍数（1 = 正常）。关卡想让某一段长一点就在那一段调小：0.5 = 每一下只涨一半，这一段要打两倍那么多下。
## 分数线、满条值都不用动，音乐按进度切换的那些点也就不用动。每进一个小关回到 1。
var gain_scale := 1.0
var _fraction := 0.0  # 乘了倍数之后不满 1 的零头，攒着
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
	gain_scale = 1.0
	_fraction = 0.0
	changed.emit(value, max_value)


## 直接把积累条拨到某个数（游戏里的编辑面板拖进度条时用）。不触发事件，也不会过关。
func set_value(new_value: int) -> void:
	value = clampi(new_value, 0, max_value)
	full = false
	changed.emit(value, max_value)


## 编辑面板拖进度条往前拖过了分数线：把还没触发过的线按顺序补触发（往回拖不会撤销已经触发的）
func fire_passed_events() -> void:
	while events_fired < events.size() and value >= events[events_fired]:
		events_fired += 1
		event.emit(events_fired, events[events_fired - 1])


## 编辑面板“跳到第 count 个阶段”：积累条拨到第 count 条分数线上（0 = 开头），前面的线按顺序补触发
func jump_to_event(count: int) -> void:
	count = clampi(count, 0, events.size())
	set_value(events[count - 1] if count > 0 else 0)
	fire_passed_events()


## 编辑面板改了分数线：换成新的一组（已经触发过几条不变）
func set_events(list: PackedInt32Array) -> void:
	list = list.duplicate()
	list.sort()
	events = list
	events_fired = mini(events_fired, events.size())


## 按判定结果加减分。满条之后不再变化。
func apply(result: int) -> void:
	if full:
		return
	var step := 0
	match result:
		NoteData.Result.PERFECT: step = perfect_gain
		NoteData.Result.GREAT: step = great_gain
		NoteData.Result.GOOD: step = good_gain
		NoteData.Result.MISS: step = -miss_loss
		_: return
	if is_equal_approx(gain_scale, 1.0):
		value += step
	else:
		_fraction += step * gain_scale
		var whole := int(_fraction)   # 往 0 取整：零头留到下一下
		_fraction -= whole
		value += whole
	value = clampi(value, 0, max_value)
	changed.emit(value, max_value)
	while events_fired < events.size() and value >= events[events_fired]:
		events_fired += 1
		event.emit(events_fired, events[events_fired - 1])
	if value >= max_value:
		full = true
		filled.emit()
