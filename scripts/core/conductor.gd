extends Node
## 全局节拍时钟 + BGM 播放器（autoload 名：Conductor）。
## 所有和时间有关的东西（旋转角度、判定、动画）都应该读这里的
## song_time / song_beat，而不是自己用 delta 累加，这样永远不会和音乐漂移。

signal beat(index: int)
signal bar(index: int)
signal song_started
signal song_finished

## 延迟校准（秒）。感觉要“提前按”才准就调大，反之调小。
var latency_offset_sec := 0.0

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
# 预备拍：从负的时间开始时，先用系统时钟走，到 0 再真正开始放音乐
var _waiting := false
var _wait_from := 0.0
var _wait_start_usec := 0


func _ready() -> void:
	process_priority = -100  # 保证比其他节点先更新时钟
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_finish)


func load_chart(c: SongChart) -> void:
	stop()
	chart = c
	_end_beat = c.total_beats()
	if c.stream:
		_player.stream = c.stream
	else:
		_player.stream = MetronomeStream.build(c.bpm, _end_beat, c.beats_per_bar)


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
	if _waiting:
		_raw_time = _wait_from + (Time.get_ticks_usec() - _wait_start_usec) / 1000000.0
		# 提前一个输出延迟开始放，这样“听到”的第一拍正好落在时间 0
		if _raw_time + AudioServer.get_output_latency() >= 0.0:
			_waiting = false
			_player.play(0.0)
	else:
		var t := _player.get_playback_position() \
				+ AudioServer.get_time_since_last_mix() \
				- AudioServer.get_output_latency()
		_raw_time = maxf(_raw_time, t)  # 保证单调不回退
	_update_clock()

	var b := floori(song_beat)
	while _last_beat < b:
		_last_beat += 1
		beat.emit(_last_beat)
		if _last_beat % chart.beats_per_bar == 0:
			bar.emit(_last_beat / chart.beats_per_bar)

	if song_beat >= _end_beat:
		_finish()


func _update_clock() -> void:
	song_time = _raw_time - chart.first_beat_offset_sec - latency_offset_sec
	song_beat = song_time / sec_per_beat()


func _finish() -> void:
	if not playing:
		return
	playing = false
	_player.stop()
	song_finished.emit()
