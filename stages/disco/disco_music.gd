class_name DiscoMusic
extends RefCounted
## 迪斯科的分层循环配乐（assets/disco_layers，说明见那里的 README.md）：11 条分轨同长度（8 小节）、同步循环，
## 逐条调音量。前 5 条是房间那一套，后 6 条是上路以后那一套；哪条开哪条关由关卡脚本按积累条来定。
## 合成好的那条 AudioStreamSynchronized 存在大关文件 levels/level_6_disco.tres 的 stream 里；
## 这里只记分轨的顺序，并直接调「正在播的那条」（Conductor.chart.stream）里各分轨的音量。

const LAYERS: Array[String] = [
	"res://assets/disco_layers/room_00_base.ogg",
	"res://assets/disco_layers/room_01_stars.ogg",
	"res://assets/disco_layers/room_02_ball.ogg",
	"res://assets/disco_layers/room_03_dancers.ogg",
	"res://assets/disco_layers/room_04_drift.ogg",
	"res://assets/disco_layers/road_00_base.ogg",
	"res://assets/disco_layers/road_05_road.ogg",
	"res://assets/disco_layers/road_06_dance_floor.ogg",
	"res://assets/disco_layers/road_07_grid.ogg",
	"res://assets/disco_layers/road_08_plaza.ogg",
	"res://assets/disco_layers/road_09_ufo.ogg",
]
## 各条分轨在 LAYERS 里的位置
const ROOM_BASE := 0
const ROAD_BASE := 5
const UFO := 10
const SILENT_DB := -60.0


## 正在播的分层配乐（不是分层配乐时返回 null）
static func music() -> AudioStreamSynchronized:
	if Conductor.chart == null:
		return null
	# 这一大关用了叠轨音乐系统（Music autoload，levels/music/<大关>.json 里开了 use_in_game）：
	# 正在播的是它的音轨，由它按积累条来开关，这里不要去动。
	if Music.stream != null and Conductor.chart.stream == Music.stream:
		return null
	return Conductor.chart.stream as AudioStreamSynchronized


## 设一条分轨的音量：gain 0 = 听不见，1 = 原音量
static func set_layer(index: int, gain: float) -> void:
	var m := music()
	if m and index < m.stream_count:
		m.set_sync_stream_volume(index, maxf(linear_to_db(maxf(gain, 0.0001)), SILENT_DB))
