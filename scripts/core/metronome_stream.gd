class_name MetronomeStream
extends RefCounted
## 没有 BGM 时顶替用的占位伴奏：每拍一个贝斯音（每小节换一个根音）+ 很轻的节拍提示音。
## 故意不带鼓——鼓由玩家打（见 DrumKit）。
## 走的是真实音频播放路径，所以同步表现和正式歌曲一致。

const MIX_RATE := 22050
## 每小节的贝斯根音（Hz），循环使用：A F C G
const BASS_ROOTS: Array[float] = [110.0, 87.31, 130.81, 98.0]


static func build(bpm: float, total_beats: float, beats_per_bar: int) -> AudioStreamWAV:
	var spb := 60.0 / bpm
	var total_samples := int((total_beats * spb + 1.0) * MIX_RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2)  # 16 位单声道，默认全 0（静音）
	var note_len := int(minf(0.3, spb * 0.9) * MIX_RATE)
	var click_len := int(0.03 * MIX_RATE)
	for b in int(total_beats):
		var start := int(b * spb * MIX_RATE)
		var downbeat := b % beats_per_bar == 0
		var bass: float = BASS_ROOTS[(b / beats_per_bar) % BASS_ROOTS.size()]
		var click_freq := 1760.0 if downbeat else 880.0
		for i in note_len:
			if start + i >= total_samples:
				break
			var t := float(i) / MIX_RATE
			var v := (sin(TAU * bass * t) + 0.4 * sin(TAU * bass * 2.0 * t)) * exp(-t * 7.0) * 0.32
			if i < click_len:
				v += sin(TAU * click_freq * t) * exp(-t * 120.0) * 0.15
			data.encode_s16((start + i) * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
