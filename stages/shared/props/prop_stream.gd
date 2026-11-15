class_name PropStream
extends PropArranger
## 一串：同样的东西一个接一个从这里出发，沿着这个节点朝的方向（本地 +X）流出去，边走边变大（或变小），到头淡掉再从头来。
## 朝着镜头由小变大就是隧道 / 喷泉；横着不变大小就是一排流过去的猫。速度按拍子算，所以和音乐是一起走的。
## 把这个节点转个角度就换了方向；外面再套一圈（prop_ring 的 item 用 prop_stream.tscn）就是往四面八方喷。

@export_group("一串")
## 从头流到尾多远（像素）
@export var distance := 600.0
## 出发时多大、到头时多大（倍数）
@export var from_scale := 0.2
@export var to_scale := 1.4
## 一份从头流到尾要几拍（越小越快）
@export var beats_per_lap := 4.0
## 两头淡入淡出（关掉 = 到头直接消失）
@export var fade_ends := true
## 边走边转多少圈（0 = 不转）
@export var twist := 0.0
## 按一下往前窜多少（占一整程的比例），FEVER 里速度乘多少
@export_range(0.0, 1.0, 0.01) var hit_jump := 0.12
@export var fever_speed := 2.0

var _phase := 0.0
var _last_beat := -1.0
var _jump := 0.0


func on_hit() -> void:
	_jump += hit_jump


func arrange(delta: float) -> void:
	# 跟着拍子往前走；音乐没在放、或者刚重新开始，就按上一帧过了多久来算
	var now := beat_time()
	var step := now - _last_beat if _last_beat >= 0.0 and now >= _last_beat and now - _last_beat < 1.0 else delta * 2.0
	_last_beat = now
	var eased := _jump * minf(1.0, 10.0 * delta)        # 窜的那一下分几帧走完，不会跳
	_jump -= eased
	_phase = fposmod(_phase + step / maxf(beats_per_lap, 0.05) * (fever_speed if fever else 1.0) + eased, 1.0)
	for i in items.size():
		var u := fposmod(_phase + float(i) / maxi(items.size(), 1), 1.0)
		var it := items[i]
		it.position = Vector2(u * distance, 0.0)
		it.scale = Vector2.ONE * lerpf(from_scale, to_scale, u)
		it.rotation = twist * TAU * u
		it.modulate.a = clampf(minf(u, 1.0 - u) * 8.0, 0.0, 1.0) if fade_ends else 1.0
		it.z_index = int(u * 10.0) if to_scale >= from_scale else int((1.0 - u) * 10.0)    # 大的在上面
