class_name BackgroundManager
extends CanvasLayer
## 管理背景。背景和关卡完全无关：什么时候换背景由下面的时间表决定，按歌曲的秒数走。
##
## 用法：
##   1. 每张背景是这个节点的一个子节点（一般是铺满屏幕的 TextureRect），名字随便起。
##   2. 在 schedule 里填“第几秒 -> 显示哪个子节点”。例如
##        0.0 -> "collage1"     开头显示 collage1
##        8.0 -> "space"        第 8 秒换成 space
##       20.0 -> ""             第 20 秒起不显示背景（名字留空）
##      每一项一直生效到下一项的时间为止，顺序怎么填都行。
##   3. schedule 留空时，全程显示第一个子节点。
##
## 秒数是歌曲时间（音乐开始 = 0），开场预备拍期间显示第 0 秒该显示的背景。
## 这首歌是 120 BPM：1 拍 = 0.5 秒，1 小节 = 2 秒，想卡在小节线上换就填偶数秒。
## 调试时用数字键跳到别的段落，背景也会跟着跳到对应时间该有的那张。

## 时间表：歌曲第几秒 -> 背景子节点的名字（留空 = 不显示背景）
@export var schedule: Dictionary[float, String] = {}
## 切换背景时淡入淡出的秒数
@export var fade_time := 0.4

var _shown: CanvasItem
var _tweens := {}
var _times: Array[float] = []
var _started := false


func _ready() -> void:
	for child in get_children():
		if child is CanvasItem:
			child.visible = false
	_times.assign(schedule.keys())
	_times.sort()


func _process(_delta: float) -> void:
	var target := _background_at(maxf(Conductor.song_time, 0.0))
	if target != _shown or not _started:
		_show(target, _started)  # 第一次直接显示，之后淡入淡出
		_started = true


## 第 t 秒应该显示哪个子节点（可能是 null）
func _background_at(t: float) -> CanvasItem:
	if _times.is_empty():
		for child in get_children():
			if child is CanvasItem:
				return child
		return null
	var wanted := ""
	for time in _times:
		if time > t:
			break
		wanted = schedule[time]
	return _find(wanted)


func _find(wanted: String) -> CanvasItem:
	if wanted == "":
		return null
	for child in get_children():
		if child is CanvasItem and String(child.name).to_lower() == wanted.to_lower():
			return child
	return null


func _show(target: CanvasItem, animate: bool) -> void:
	if _shown and _shown != target:
		_fade(_shown, 0.0, animate)
	if target:
		_fade(target, 1.0, animate)
	_shown = target


func _fade(item: CanvasItem, to_alpha: float, animate: bool) -> void:
	if _tweens.has(item):
		_tweens[item].kill()
		_tweens.erase(item)
	if to_alpha > 0.0 and not item.visible:
		item.modulate.a = 0.0
		item.visible = true
	if not animate or fade_time <= 0.0:
		item.modulate.a = to_alpha
		item.visible = to_alpha > 0.0
		return
	var tween := create_tween()
	tween.tween_property(item, "modulate:a", to_alpha, fade_time)
	if to_alpha <= 0.0:
		tween.tween_callback(func(): item.visible = false)
	_tweens[item] = tween
