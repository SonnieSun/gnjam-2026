extends Node
## 全局节拍时钟 + BGM 播放器（autoload 名：Conductor）。
## 所有和时间有关的东西（旋转角度、判定、动画）都应该读这里的
## song_time / song_beat，而不是自己用 delta 累加，这样永远不会和音乐漂移。

signal beat(index: int)
signal bar(index: int)
signal song_started
signal song_finished

## 延迟校准（秒），存在 user://settings.cfg，在主菜单按 O 进校准界面测。
## 按键延迟：玩家听到拍子 → 按键被游戏收到，中间晚了多少。判定时从按键时间里扣掉。
## 蓝牙耳机一般要 0.15~0.25。
var input_offset_sec := 0.0
## 画面提前量：正数 = 画面往前提（显示器 / 画面本身有延迟时用）。只影响 song_time / song_beat，不影响判定。
var visual_offset_sec := 0.0
const SETTINGS_PATH := "user://settings.cfg"

## 时钟平滑：每帧先按系统时钟往前走，再把和音频位置的偏差修掉这么多比例
const CLOCK_CORRECTION := 0.1
## 和音频位置差得比这还多就直接对齐（卡顿、音频重启）
const CLOCK_SNAP_SEC := 0.05

var chart: SongChart
## 距离第一拍的秒数
var song_time := 0.0
## 浮点拍数，0 = 第一拍
var song_beat := 0.0
var playing := false

var _player: AudioStreamPlayer
var _raw_time := 0.0
var _last_beat := -1
var _end_beat := 0.0
## 音乐循环播放（小关不限时，歌放完了从头接着放）。song_time / song_beat 不会跟着归零，一直往上涨。
var looping := true
var _loop_len := 0.0   # 音乐文件一遍多长（秒）
var _loop_base := 0.0  # 已经放完的整遍加起来多长
# 预备拍：从负的时间开始时，先用系统时钟走，到 0 再真正开始放音乐
var _waiting := false
var _wait_from := 0.0
var _wait_start_usec := 0
## _raw_time 是哪一刻的值（系统时钟），用来算“此刻”的时间和平滑
var _raw_usec := 0


func _ready() -> void:
	process_priority = -100  # 保证比其他节点先更新时钟
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_finish)
	load_offsets()


func load_offsets() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		input_offset_sec = cfg.get_value("latency", "input_offset_sec", 0.0)
		visual_offset_sec = cfg.get_value("latency", "visual_offset_sec", 0.0)


func save_offsets() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 保留别的设置
	cfg.set_value("latency", "input_offset_sec", input_offset_sec)
	cfg.set_value("latency", "visual_offset_sec", visual_offset_sec)
	cfg.save(SETTINGS_PATH)


func load_chart(c: SongChart) -> void:
	stop()
	chart = c
	_end_beat = c.total_beats()
	if c.stream:
		_player.stream = c.stream
	else:
		_player.stream = MetronomeStream.build(c.bpm, _end_beat, c.beats_per_bar)
	_loop_len = _player.stream.get_length()
	if looping:
		_set_stream_loop(_player.stream)


## 从指定拍开始播放（也用作 seek：调试时直接跳到某一段）。
## from_beat 可以是负数：音乐开始前先空走几拍，给玩家准备时间。
func play(from_beat: float = 0.0) -> void:
	var t := beat_to_sec(from_beat) + chart.first_beat_offset_sec
	_player.stop()
	_waiting = t < 0.0
	if _waiting:
		_wait_from = t
		_wait_start_usec = Time.get_ticks_usec()
	else:
		_player.play(t)
	_raw_time = t
	_raw_usec = Time.get_ticks_usec()
	_loop_base = 0.0
	_update_clock()
	_last_beat = ceili(from_beat) - 1
	playing = true
	song_started.emit()


func stop() -> void:
	playing = false
	_waiting = false
	if _player:
		_player.stop()


func sec_per_beat() -> float:
	return 60.0 / chart.bpm


func beat_to_sec(b: float) -> float:
	return b * sec_per_beat()


func _process(_delta: float) -> void:
	if not playing:
		return
	var now := Time.get_ticks_usec()
	if _waiting:
		_raw_time = _wait_from + (now - _wait_start_usec) / 1000000.0
		# 提前一个输出延迟开始放，这样“听到”的第一拍正好落在时间 0
		if _raw_time + AudioServer.get_output_latency() >= 0.0:
			_waiting = false
			_player.play(0.0)
	else:
		# 音频报的位置是按混音块一跳一跳的，直接用会让时间（和画面、判定）抖。
		# 所以：按系统时钟往前推，再一点点往音频位置靠；差太多才直接对齐。
		var predicted := _raw_time + (now - _raw_usec) / 1000000.0
		var t := _loop_base + _player.get_playback_position() \
				+ AudioServer.get_time_since_last_mix() \
				- AudioServer.get_output_latency()
		if looping and _loop_len > 0.0 and t < predicted - _loop_len * 0.5:
			# 播放位置突然掉回开头 = 音乐绕回去了，时间接着往上数
			_loop_base += _loop_len
			t += _loop_len
		var err := t - predicted
		if absf(err) > CLOCK_SNAP_SEC:
			_raw_time = t
		else:
			_raw_time = maxf(_raw_time, predicted + err * CLOCK_CORRECTION)  # 小修正时保证不回退
	_raw_usec = now
	_update_clock()

	var b := floori(song_beat)
	while _last_beat < b:
		_last_beat += 1
		beat.emit(_last_beat)
		if _last_beat % chart.beats_per_bar == 0:
			bar.emit(_last_beat / chart.beats_per_bar)

	if not looping and song_beat >= _end_beat:
		_finish()


## 让音乐文件循环播放。注意：文件长度要正好是整数个小节，否则绕回去之后节拍会对不上。
func _set_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	elif "loop" in stream:
		stream.set("loop", true)


func _update_clock() -> void:
	song_time = _raw_time - chart.first_beat_offset_sec + visual_offset_sec
	song_beat = song_time / sec_per_beat()


## 判定用的拍数（input_time() 换算成拍）
func input_beat() -> float:
	return input_time() / sec_per_beat()


## 判定用的时间：此刻（不是这帧开头）音乐放到哪了，扣掉按键延迟，不含画面提前量。
## 输入事件是在 _process 之前分发的，那时 song_time 还是上一帧的值，所以要按系统时钟补上这段。
func input_time() -> float:
	if not playing:
		return song_time - visual_offset_sec - input_offset_sec
	var raw := _raw_time + (Time.get_ticks_usec() - _raw_usec) / 1000000.0
	return raw - chart.first_beat_offset_sec - input_offset_sec


func _finish() -> void:
	if not playing:
		return
	playing = false
	_player.stop()
	song_finished.emit()
