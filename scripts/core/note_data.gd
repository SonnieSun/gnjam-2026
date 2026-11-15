@tool
class_name NoteData
extends RefCounted
## 一个音符。beat 是整首歌里的绝对拍数。

## GREAT 是后加的，放在最后，免得已有的数值变了
enum Result { NONE, PERFECT, GOOD, MISS, GREAT }
## 这个音符是哪种鼓（玩家按下时发出的声音）
enum Sound { KICK, SNARE, HAT }

var beat := 0.0
var section_index := 0
var sound: int = Sound.KICK
var judged := false
var result: int = Result.NONE
