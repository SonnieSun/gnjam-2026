class_name HitMeow
extends Node
## 打中时的喵（按键反馈音效）：Perfect / Good 各一组队员自己录的喵（每组 3 个，一声录音一个），
## 每次随机挑一个（不会连着两次同一个），再轻微随机一点音高和音量，连打不会像复读机。
## 随机的幅度在检查器里调；素材由 tools/music_gen/make_hit_meows.py 生成。
##
## 也管别的"打得怎样"的声音反馈：
##   漏打      连着打中之后的第一下漏打，一声 miss 喵，旋律压低一拍；连击断了（断之前 >= break_min_combo）是一声 glitch 喵。
##             一直漏打不会一直响，只在"刚断"的那一下响。
##   连击里程碑  转圈喵；连击到 kiai_combo 以上的里程碑，再送 kiai_bars 小节的鬼畜全开（Music.kiai）。
##   打中唱旋律  这一关的音乐里有"由打中来唱"的谱子片段在响时，打中一下唱出旋律的那个音，就不再放随机的打中喵。

## 关掉 = 打中不喵
@export var enabled := true
@export var perfect_sounds: Array[AudioStream] = [
	preload("res://assets/audio/sfx/hit_meow_perfect_a.wav"),
	preload("res://assets/audio/sfx/hit_meow_perfect_b.wav"),
	preload("res://assets/audio/sfx/hit_meow_perfect_c.wav"),
]
@export var good_sounds: Array[AudioStream] = [
	preload("res://assets/audio/sfx/hit_meow_good_a.wav"),
	preload("res://assets/audio/sfx/hit_meow_good_b.wav"),
	preload("res://assets/audio/sfx/hit_meow_good_c.wav"),
]
@export_range(-30.0, 6.0) var volume_db := -1.0
## 音高随机上下多少（0.03 = ±3%，大约半个半音；0 = 不变）
@export_range(0.0, 0.2, 0.005) var pitch_random := 0.03
## Perfect 比 Great 高多少音高（0.06 ≈ 高一个半音，听得出“这一下更准”；0 = 一样）
@export_range(0.0, 0.3, 0.005) var perfect_pitch_up := 0.06
## 音量随机上下多少 dB
@export_range(0.0, 6.0, 0.1) var volume_random_db := 1.0
## 连击到里程碑（10、20、50……）时的转圈喵（"oiia"那种，用我们自己的喵做的），两个轮流放；清空 = 不放
@export var spin_sounds: Array[AudioStream] = [
	preload("res://assets/audio/sfx/spin_meow_a.wav"),
	preload("res://assets/audio/sfx/spin_meow_b.wav"),
]
@export_range(-30.0, 6.0) var spin_volume_db := -4.0
## 漏打的那一声（连着打中之后第一下漏打才响）；清空 = 不放
@export var miss_sound: AudioStream = preload("res://assets/audio/sfx/miss_meow.wav")
@export_range(-30.0, 6.0) var miss_volume_db := -8.0
## 连击断了的那一声（断之前的连击数 >= break_min_combo 才响）；清空 = 不放
@export var break_sound: AudioStream = preload("res://assets/audio/sfx/glitch_meow.wav")
@export_range(-30.0, 6.0) var break_volume_db := -6.0
@export var break_min_combo := 10
## 连击到这个数以上的里程碑，送几小节的鬼畜全开（0 小节 = 不送）
@export var kiai_combo := 50
@export_range(0, 16) var kiai_bars := 4
## 同时最多几声（连打很快时前一声还没完）
@export_range(1, 8) var voices := 4

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}   # 每组上次挑的是第几个
var _spin_player: AudioStreamPlayer
var _spin_next := 0
var _streak := 0          # 现在连着打中了几下


func _ready() -> void:
	for i in voices:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_spin_player = AudioStreamPlayer.new()
	add_child(_spin_player)


## 按判定结果喵一声：Perfect 和 Good 喵，Miss 不出声
func play(result: int) -> void:
	if not enabled:
		return
	if result == NoteData.Result.MISS:
		_missed()
		return
	if result == NoteData.Result.NONE:
		return
	_streak += 1
	if Music.meow.sing_hit():      # 这一下由旋律来唱，不放随机的打中喵
		return
	match result:
		NoteData.Result.PERFECT: _play_from(perfect_sounds, "perfect", 1.0 + perfect_pitch_up)
		NoteData.Result.GREAT: _play_from(perfect_sounds, "perfect")
		NoteData.Result.GOOD: _play_from(good_sounds, "good")


func _missed() -> void:
	var lost := _streak
	_streak = 0
	if lost == 0:                  # 本来就在漏打：不重复响
		return
	var broke := lost >= break_min_combo and break_sound != null
	var s: AudioStream = break_sound if broke else miss_sound
	if s:
		_spin_player.stream = s
		_spin_player.volume_db = break_volume_db if broke else miss_volume_db
		_spin_player.play()
	Music.dip(2.0 if broke else 1.0)


## 连击到了里程碑（10、20、50……）：转圈喵；够高的里程碑再送一段鬼畜全开
func milestone(combo: int) -> void:
	spin()
	if enabled and kiai_bars > 0 and combo >= kiai_combo:
		Music.kiai(kiai_bars)


## 连击里程碑：转圈喵一声
func spin() -> void:
	if not enabled or spin_sounds.is_empty():
		return
	_spin_player.stream = spin_sounds[_spin_next % spin_sounds.size()]
	_spin_next += 1
	_spin_player.volume_db = spin_volume_db
	_spin_player.play()


func _play_from(sounds: Array[AudioStream], group: String, pitch: float = 1.0) -> void:
	if sounds.is_empty():
		return
	var i := randi() % sounds.size()
	if sounds.size() > 1 and i == _last.get(group, -1):
		i = (i + 1 + randi() % (sounds.size() - 1)) % sounds.size()
	_last[group] = i
	# 轮流用几个播放器，前一声不会被切断
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = sounds[i]
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_random, pitch_random))
	p.volume_db = volume_db + randf_range(-volume_random_db, volume_random_db)
	p.play()
