class_name MeowPlayer
extends Node
## 运行时按格子放喵：猫鼓和鬼畜猫旋律的"谱子片段"（levels/music/patterns/*.json）不预渲染，
## 游戏里跟着 Conductor 一格一格（16 分音符）触发喵采样。
##
## 每只猫一个采样（assets/audio/meows/runtime/，共鸣已经烤进去），用 pitch_scale 变速变调到要的音高，
## 到音符结束就停掉（硬切）—— 也就是鬼畜的做法。所以换速度不用重渲染，谱子可以在游戏里改了马上听。
## Music autoload 里有一个这样的节点：某条轨道当前响的片段是谱子片段时，它就在这里播。
##
## 谱子片段的格式（两种）：
##   猫鼓  {"kind": "drums", "bars": 2, "rows": [{"name", "cat": "13", "tick": false, "midi": 64, "steps": 2, "gain_db": 0,
##                                             "bars": ["x...x...x...x...", ...]}]}
##          每行一种声音：哪只猫、唱哪个音、响几格；tick = 只用喵开头那一小下（当踩镲用）。"x" = 这一格响。
##   旋律  {"kind": "melody", "bars": 4, "cat": "auto", "gain_db": 0, "notes": [[第几格, midi 音高, 几格长], ...]}
##          cat = "auto"：每 4 小节挑原本音高离这一句最近的那只猫（相邻两句不重复）；也可以写死一只（"13"）。

const DIR := "res://assets/audio/meows/runtime/"
const PATTERN_DIR := "res://levels/music/patterns/"
const STEPS_PER_BAR := 16
const VOICES := 10

## cat id -> {"meow": AudioStream, "tick": AudioStream, "midi": float}
var cats := {}
## 现在在播的谱子片段：名字（一般是轨道 id）-> 谱子
var active := {}
## 每个在播片段的音量（dB），名字同上
var gain_db := {}

var _voices: Array[AudioStreamPlayer] = []
var _voice_end := PackedFloat32Array()     # 这个播放器到第几拍要停（-1 = 放完为止）
var _next_voice := 0
var _last_step := -1000000
var _phrase_cat := {}                      # 旋律片段："名字/第几句" -> cat id


func _ready() -> void:
	var info := read_pattern(DIR + "meows.json")
	for c: Dictionary in info.get("cats", []):
		cats[c.id] = {"meow": load(DIR + c.file), "tick": load(DIR + c.tick), "midi": float(c.midi)}
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
		_voice_end.append(-1.0)


## 读一个谱子片段（读不到返回空字典）
static func read_pattern(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func write_pattern(path: String, d: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "\t"))
	return OK


## 所有谱子片段文件（完整路径），按名字排序
static func list_patterns() -> PackedStringArray:
	var out := PackedStringArray()
	if DirAccess.dir_exists_absolute(PATTERN_DIR):
		for f in DirAccess.get_files_at(PATTERN_DIR):
			if f.get_extension() == "json":
				out.append(PATTERN_DIR + f)
	out.sort()
	return out


## 让一个谱子片段开始 / 停止跟着节拍播（pattern 为空 = 停）
func set_active(key: String, pattern: Dictionary, db := 0.0) -> void:
	for k in _phrase_cat.keys():
		if k.begins_with(key + "/"):
			_phrase_cat.erase(k)
	if pattern.is_empty():
		active.erase(key)
		gain_db.erase(key)
	else:
		active[key] = pattern
		gain_db[key] = db


## 马上放一声（编辑器里点格子试听用）
func preview(cat: String, midi: float, tick := false, seconds := 0.4) -> void:
	_play(cat, midi, tick, 0.0, Conductor.song_beat + seconds / Conductor.sec_per_beat() if Conductor.playing else -1.0)


func _process(_delta: float) -> void:
	if not Conductor.playing or Conductor.chart == null:
		_last_step = -1000000
		return
	var beat := Conductor.song_beat
	for i in _voices.size():
		if _voice_end[i] >= 0.0 and beat >= _voice_end[i]:
			_voices[i].stop()
			_voice_end[i] = -1.0
	if active.is_empty():
		_last_step = -1000000
		return
	# Conductor 的时间是"现在听到的"，喇叭还要晚一个输出延迟才出声：提前这么多触发，喵才落在格子上
	var ahead := AudioServer.get_output_latency() / Conductor.sec_per_beat()
	var step := floori((beat + ahead) * 4.0)
	if step < 0:
		return
	if step < _last_step or step - _last_step > 4:      # 重新开始了，或者刚开始播 / 卡了一下：只放当前这一格
		_last_step = step - 1
	for s in range(_last_step + 1, step + 1):
		for key: String in active:
			_trigger(key, active[key], s)
	_last_step = step


func _trigger(key: String, pattern: Dictionary, step: int) -> void:
	var total: int = maxi(int(pattern.get("bars", 1)), 1) * STEPS_PER_BAR
	var at := step % total
	var db: float = gain_db.get(key, 0.0) + float(pattern.get("gain_db", 0.0))
	if pattern.get("kind", "") == "drums":
		for row: Dictionary in pattern.get("rows", []):
			var bars: Array = row.get("bars", [])
			var bar := at / STEPS_PER_BAR
			if bar >= bars.size():
				continue
			var line: String = bars[bar]
			var i := at % STEPS_PER_BAR
			if i < line.length() and line[i] != ".":
				_play(str(row.get("cat", "")), float(row.get("midi", 60)), row.get("tick", false),
						db + float(row.get("gain_db", 0.0)), (step + float(row.get("steps", 2))) / 4.0)
	else:
		for note: Array in pattern.get("notes", []):
			if int(note[0]) == at:
				var cat := _cat_for(key, pattern, at)
				_play(cat, float(note[1]), false, db, (step + float(note[2]) * 0.95) / 4.0)


## 旋律片段这一格该哪只猫唱
func _cat_for(key: String, pattern: Dictionary, at: int) -> String:
	var fixed := str(pattern.get("cat", "auto"))
	if cats.has(fixed):
		return fixed
	var phrase := at / (STEPS_PER_BAR * 4)
	var id := "%s/%d" % [key, phrase]
	if not _phrase_cat.has(id):
		var pitches: Array[float] = []
		for note: Array in pattern.get("notes", []):
			if int(note[0]) / (STEPS_PER_BAR * 4) == phrase:
				pitches.append(float(note[1]))
		pitches.sort()
		var mid: float = pitches[pitches.size() / 2] if not pitches.is_empty() else 72.0
		var before: String = _phrase_cat.get("%s/%d" % [key, phrase - 1], "")
		var best := ""
		for c: String in cats:
			if c == before and cats.size() > 1:
				continue
			if best == "" or absf(cats[c].midi - mid) < absf(cats[best].midi - mid):
				best = c
		_phrase_cat[id] = best
	return _phrase_cat[id]


func _play(cat: String, midi: float, tick: bool, db: float, end_beat: float) -> void:
	if not cats.has(cat):
		if cats.is_empty():
			return
		cat = cats.keys()[0]
	var c: Dictionary = cats[cat]
	var p := _voices[_next_voice]
	_voice_end[_next_voice] = end_beat
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = c.tick if tick else c.meow
	p.pitch_scale = clampf(pow(2.0, (midi - c.midi) / 12.0), 0.25, 4.0)
	p.volume_db = db
	p.play()
