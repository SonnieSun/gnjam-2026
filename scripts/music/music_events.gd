class_name MusicEvents
extends Node
## 画面跟着音乐的信号的来源：Music 的子节点，每帧看节拍走到哪了，把这一帧里经过的鼓点和旋律音符
## 用 Music 的信号发出去（Music.drum_kick / drum_clap / drum_hat / lead_note）。说明见 docs/music_manager.md。
##
## 数据是 levels/music/events/ 里的小 json（tools/music_gen/export_music_events.py 从作曲脚本里读出来写的）：
##   grooves.json    节奏轨每种鼓型一小节里的底鼓 / 拍手 / 镲在第几个十六分音符
##   <曲子>.json     这首曲子的旋律 [[第几个十六分, 音高, 多长], ...]
## 哪段片段对应哪份数据：
##   节奏轨（beat）：片段上写了 "groove": "club" 就用它；否则看文件名（s1_Rclub_L1_groove → club，
##                   s1_L1_groove → four），再不行看片段 id（half / club / break / groove）。
##   旋律轨（lead）：片段上写了 "notes": "entertainer" 就用它；否则看文件在 classics/ 的哪个文件夹里。
##   找不到数据的片段就不发信号。
## 属于曲子组的片段从那首曲子自己的第 1 小节算起（Music.tune_origin）。

const EVENTS_DIR := "res://levels/music/events/"
const STEPS_PER_BEAT := 4.0
const BEAT_LANE := "beat"
const LEAD_LANE := "lead"

## 提前多少拍发（0 = 节拍走到那一下的那一帧发）。效果自己有起势（比如先缩再弹）的话可以调大一点。
var lead_beats := 0.0
## 调试：把每一下打印出来（应该在第几拍 / 实际发出时节拍走到了第几拍）
var log_events := false

var _grooves := {}
var _songs := {}          # 曲子名 -> {"bars", "cat_octave", "notes"}（读不到的记成 {}）
var _clip_groove := {}    # 节奏轨的片段 id -> 鼓型名（"" = 没有数据）
var _clip_song := {}      # 旋律轨的片段 id -> 曲子名
var _built_for: Dictionary
var _last := 0.0
var _running := false


func _ready() -> void:
	_grooves = _read(EVENTS_DIR + "grooves.json")
	Conductor.song_started.connect(func() -> void: _running = false)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## 节奏轨的这段片段是哪种鼓型（"" = 不知道）
func groove_of(clip_id: String) -> String:
	_index()
	return _clip_groove.get(clip_id, "")


## 这种鼓型一小节里每种鼓在第几个十六分：{"kick": [...], "clap": [...], "hat": [...], "open_hat": [...]}，没有就是 {}
func groove(groove_name: String) -> Dictionary:
	return _grooves.get(groove_name, {})


## 旋律轨的这段片段是哪首曲子的旋律（"" = 没有音符数据）
func song_of(clip_id: String) -> String:
	_index()
	return _clip_song.get(clip_id, "")


## 这首曲子的音符数据：{"bars", "cat_octave", "notes": [[第几个十六分, 音高, 多长], ...]}，没有就是 {}
func song(song_name: String) -> Dictionary:
	if not _songs.has(song_name):
		_songs[song_name] = _read(EVENTS_DIR + song_name + ".json")
	return _songs[song_name]


## 配置换了（换关）就重新认一遍片段
func _index() -> void:
	var music: Node = get_parent()
	if is_same(_built_for, music.data):
		return
	_built_for = music.data
	_clip_groove.clear()
	_clip_song.clear()
	var by_id := {"groove": "four", "four": "four", "half": "half", "club": "club", "break": "break"}
	var groove_file := RegEx.create_from_string("_(?:R([a-z]+)_)?L1_groove")
	for lane in music.data.get("lanes", []):
		for clip in lane.get("clips", []):
			var file := str(clip.get("file", ""))
			if lane.id == BEAT_LANE:
				var g := str(clip.get("groove", ""))
				var m := groove_file.search(file.get_file())
				if g == "" and m:
					g = m.get_string(1) if m.get_string(1) != "" else "four"
				if g == "":
					g = by_id.get(clip.id, "")
				_clip_groove[clip.id] = g if _grooves.has(g) else ""
			elif lane.id == LEAD_LANE:
				var s := str(clip.get("notes", ""))
				if s == "" and "/classics/" in file:
					s = file.get_base_dir().get_file()
				_clip_song[clip.id] = s if s != "" and not song(s).is_empty() else ""


func _process(_delta: float) -> void:
	var music: Node = get_parent()
	if music.stream == null or not Conductor.playing:
		_running = false
		return
	var now := Conductor.song_beat + lead_beats
	if not _running or now < _last:   # 刚开始放 / 跳回去了：从这一帧起算（正好压在拍点上的那一下也算）
		_running = true
		_last = now - 0.05
	if now - _last > 2.0:             # 卡了很久：中间的不补发
		_last = now - 0.05
	_index()
	_drums(music, _last, now)
	_lead(music, _last, now)
	_last = now


## (from, to] 这段拍子里，一个 loop_steps 个十六分长、从第 origin 拍起循环的片段经过了哪些十六分：
## 对每个整数格 n 调 hit(循环里的第几格, 那一格在第几拍)
func _each_step(from: float, to: float, origin: float, loop_steps: int, hit: Callable) -> void:
	var first := floori((from - origin) * STEPS_PER_BEAT) + 1
	var last := floori((to - origin) * STEPS_PER_BEAT)
	for n in range(maxi(first, 0), last + 1):
		hit.call(n % loop_steps, origin + n / STEPS_PER_BEAT)


func _drums(music: Node, from: float, to: float) -> void:
	var clip := str(music._now.get(BEAT_LANE, ""))
	var g: Dictionary = _grooves.get(_clip_groove.get(clip, ""), {})
	# 预备拍那一小节里关卡的鼓是让开的（见 Music.count_in），不发
	if g.is_empty() or music.muted.get(BEAT_LANE, false) or Conductor.song_beat < music._count_until:
		return
	var tune: String = music._tune_of(BEAT_LANE, clip)
	var origin: float = music.tune_origin(tune) if tune != "" else 0.0
	if origin < 0.0:
		return
	_each_step(from, to, origin, 16, func(step: int, beat: float) -> void:
		if float(step) in g.kick:
			_log("kick", beat)
			music.drum_kick.emit(beat)
		if float(step) in g.clap:
			_log("clap", beat)
			music.drum_clap.emit(beat)
		var open: bool = float(step) in g.open_hat
		if open or float(step) in g.hat:
			music.drum_hat.emit(beat, open))


func _lead(music: Node, from: float, to: float) -> void:
	var clip := str(music._now.get(LEAD_LANE, ""))
	var s: Dictionary = song(_clip_song[clip]) if _clip_song.get(clip, "") != "" else {}
	if s.is_empty() or music.muted.get(LEAD_LANE, false):
		return
	var tune: String = music._tune_of(LEAD_LANE, clip)
	var origin: float = music.tune_origin(tune) if tune != "" else 0.0
	if origin < 0.0:
		return
	var notes: Array = s.notes
	_each_step(from, to, origin, int(s.bars) * 16, func(step: int, beat: float) -> void:
		for note: Array in notes:
			if int(note[0]) == step:
				_log("note %d" % int(note[1]), beat)
				music.lead_note.emit(beat, int(note[1]), float(note[2]) / STEPS_PER_BEAT)
			elif int(note[0]) > step:
				break)


func _log(what: String, beat: float) -> void:
	if log_events:
		print("[music event] %-8s beat %7.2f  (bar %d, step %2d)  fired at %7.3f" % [what, beat, floori(beat / 4.0) + 1,
				int(round(fposmod(beat, 4.0) * 4.0)), Conductor.song_beat])
