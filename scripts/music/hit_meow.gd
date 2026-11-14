class_name HitMeow
extends Node
## 打中时的喵（按键反馈音效）：Perfect / Good 各一组队员自己录的喵，每次随机挑一个（不会连着两次同一个），
## 再随机一点音高和音量，所以连打不会像复读机。
## 两组都是 AudioStreamRandomizer（assets/audio/sfx/hit_meow_perfect.tres / hit_meow_good.tres）：
## 在检查器里打开它们就能加减文件、改随机音高（random_pitch，1.06 ≈ 上下一个半音）和随机音量。
## 素材由 tools/music_gen/make_hit_meows.py 生成。

## 关掉 = 打中不喵
@export var enabled := true
@export var perfect_sound: AudioStream = preload("res://assets/audio/sfx/hit_meow_perfect.tres")
@export var good_sound: AudioStream = preload("res://assets/audio/sfx/hit_meow_good.tres")
@export_range(-30.0, 6.0) var volume_db := -6.0
## 同时最多几声（连打很快时前一声还没完）
@export_range(1, 8) var polyphony := 3

var _perfect: AudioStreamPlayer
var _good: AudioStreamPlayer


func _ready() -> void:
	_perfect = _player(perfect_sound)
	_good = _player(good_sound)


func _player(s: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.max_polyphony = polyphony
	add_child(p)
	return p


## 按判定结果喵一声：Perfect 和 Good 喵，Miss 不出声
func play(result: int) -> void:
	if not enabled:
		return
	var p: AudioStreamPlayer = null
	match result:
		NoteData.Result.PERFECT: p = _perfect
		NoteData.Result.GOOD: p = _good
	if p:
		p.volume_db = volume_db
		p.play()
