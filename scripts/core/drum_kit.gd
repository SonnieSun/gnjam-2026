class_name DrumKit
extends Node
## 玩家的按键就是鼓手：每次按下立刻发出一声鼓，不做任何对齐修正。
## 背景音乐里不带鼓，所以按得准，鼓和音乐就合得上；按歪了，听起来就是歪的。
## 漏按（Miss）不会发声，那一拍的鼓就空着。

## 正式音色拖到这里；留空会用代码合成的占位音色。
## 采样开头不要留空白，否则每次按键都会多出延迟。
@export var kick: AudioStream
@export var snare: AudioStream
@export var hat: AudioStream
@export_range(-24.0, 6.0) var volume_db := 0.0

const VOICES := 8
const MIX_RATE := 44100

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _streams := {}


func _ready() -> void:
	_streams = {
		NoteData.Sound.KICK: kick if kick else _synth_kick(),
		NoteData.Sound.SNARE: snare if snare else _synth_snare(),
		NoteData.Sound.HAT: hat if hat else _synth_hat(),
	}
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## 换成某首歌自带的鼓音色；谱面里没填的那几种保持不变
func use_chart(chart: SongChart) -> void:
	if chart.drum_kick:
		_streams[NoteData.Sound.KICK] = chart.drum_kick
	if chart.drum_snare:
		_streams[NoteData.Sound.SNARE] = chart.drum_snare
	if chart.drum_hat:
		_streams[NoteData.Sound.HAT] = chart.drum_hat


func play(sound: int) -> void:
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.play()


# ---- 占位音色合成 ----

static func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


static func _synth_kick() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var phase := 0.0
	for i in int(0.28 * MIX_RATE):
		var t := float(i) / MIX_RATE
		var freq := 45.0 + 130.0 * exp(-t * 35.0)  # 音高快速下滑
		phase += TAU * freq / MIX_RATE
		out.append(sin(phase) * exp(-t * 14.0) * 0.95)
	return _make(out)


static func _synth_snare() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in int(0.2 * MIX_RATE):
		var t := float(i) / MIX_RATE
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 22.0) * 0.6
		var body := sin(TAU * 190.0 * t) * exp(-t * 30.0) * 0.5
		out.append(noise + body)
	return _make(out)


static func _synth_hat() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var prev := 0.0
	for i in int(0.06 * MIX_RATE):
		var t := float(i) / MIX_RATE
		var n := rng.randf_range(-1.0, 1.0)
		out.append((n - prev) * exp(-t * 70.0) * 0.4)  # 相邻差分 = 简易高通
		prev = n
	return _make(out)
