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

# ---- 表现用的属性（谱面编辑器里按音符编辑，见 scripts/chart/chart_pattern.gd）----
# 判定只看 beat 和 sound，这些都不影响判定；画音符的地方（NoteStyle 或关卡脚本）按需读。

## 长按几拍（0 = 普通点按）
var length := 0.0
## 提前几拍出现（飞过来 / 收过来用多久）；<= 0 = 用表现方式的默认值
var lead := 0.0
## 轨道 / 方向：下落式和 3D 轨道是第几条道，圆圈和光束是第几个目标，轨道式是第几圈
var lane := 0
## 颜色：alpha = 0 表示用音色的默认颜色
var color := Color(0, 0, 0, 0)
## 大小倍数
var size := 1.0
## 出现时的角度（度）和自转速度（度 / 拍）
var rot := 0.0
var spin := 0.0
## 平时多亮（自发光，0 = 不额外发光）、每拍闪多亮、每拍胀多少（0.3 = 拍点上大 30%）
var glow := 0.0
var pulse := 0.0
var throb := 0.0

## 表现属性的名字和默认值（谱面文件里没写的就用这个）
const STYLE_DEFAULTS := {
	"length": 0.0, "lead": 0.0, "lane": 0, "color": Color(0, 0, 0, 0), "size": 1.0,
	"rot": 0.0, "spin": 0.0, "glow": 0.0, "pulse": 0.0, "throb": 0.0,
}


## 把谱面里一个音符的字典（ChartPattern.notes 的一项）里的表现属性抄过来
func apply_props(d: Dictionary) -> void:
	for key: String in STYLE_DEFAULTS:
		set(key, d.get(key, STYLE_DEFAULTS[key]))
