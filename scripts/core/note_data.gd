@tool
class_name NoteData
extends RefCounted
## 一个音符。beat 是整首歌里的绝对拍数。

enum Result { NONE, PERFECT, GOOD, MISS }
## 这个音符是哪种鼓（玩家按下时发出的声音）
enum Sound { KICK, SNARE, HAT }

var beat := 0.0
var section_index := 0
var sound: int = Sound.KICK
var judged := false
var result: int = Result.NONE
