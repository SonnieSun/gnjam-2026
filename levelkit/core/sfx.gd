extends Node
## Autoload "Sfx". Every sound in the game, synthesized at startup: the four
## track voices (named like BeatClock.TRACK_NAMES, lower case), the interface
## blips and the play-mode feedback. Placeholder until there is real audio.

const RATE := 22050

var enabled := true
var _players := {}


func _ready() -> void:
	seed(7) # same noise every run
	#             length  from Hz  to Hz  decay  noise  square  gain
	_add("kick", 0.16, 170.0, 45.0, 22.0, 0.0, false, 1.0)
	_add("snare", 0.14, 210.0, 170.0, 30.0, 0.75, false, 0.7)
	_add("hat", 0.05, 0.0, 0.0, 90.0, 1.0, false, 0.35)
	_add("blip", 0.10, 880.0, 880.0, 28.0, 0.0, true, 0.3)
	_add("pop", 0.09, 320.0, 950.0, 30.0, 0.0, false, 0.6)
	_add("grab", 0.05, 520.0, 760.0, 45.0, 0.0, false, 0.4)
	_add("drop", 0.08, 520.0, 240.0, 35.0, 0.0, false, 0.45)
	_add("whoosh", 0.22, 300.0, 1400.0, 12.0, 0.6, false, 0.4)
	_add("poof", 0.20, 400.0, 90.0, 16.0, 0.6, false, 0.5)
	_add("tick", 0.025, 1500.0, 1500.0, 80.0, 0.0, false, 0.3)
	_add("meow", 0.16, 950.0, 520.0, 14.0, 0.05, false, 0.45)
	_add("good", 0.14, 1250.0, 1900.0, 22.0, 0.0, false, 0.3)
	_add("miss", 0.12, 140.0, 90.0, 20.0, 0.1, true, 0.3)
	_add("frenzy", 0.5, 400.0, 2400.0, 5.0, 0.1, true, 0.25)
	randomize()


func play(sound: String, pitch := 1.0) -> void:
	if enabled and _players.has(sound):
		var p: AudioStreamPlayer = _players[sound]
		p.pitch_scale = pitch
		p.play()


func _add(sound: String, length: float, f0: float, f1: float, decay: float, noise: float, square: bool, gain: float) -> void:
	var n := int(RATE * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(f0, f1, t / length) / RATE
		var wave := signf(sin(phase)) if square else sin(phase)
		var s := lerpf(wave, randf_range(-1.0, 1.0), noise) * exp(-t * decay) * gain
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	var p := AudioStreamPlayer.new()
	p.stream = wav
	p.volume_db = -6.0
	add_child(p)
	_players[sound] = p
