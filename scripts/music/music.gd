extends Node
## 叠轨音乐（autoload 名：Music）。设计见 docs/music_manager.md。
##
## 一关的所有 loop 放进一个 AudioStreamSynchronized，从头一起放、从不停；"开一层"就是把它的音量
## 拉起来。每层在什么时候响，由音乐配置（levels/music/level_<n>.json，用 Music Director 面板编辑）
## 决定：每个小关一张表，写着每条 track 在积累条进度（0 = 刚进小关，1 = 满）的哪些区间里响。
##
## 进度和小关的变化排队到下一个边界（默认 4 拍 = 一小节）才生效，所以开层总在小节线上。
## 时钟仍然是 Conductor：它放的就是这里建出来的同步流。

## 某条 track 开 / 关（在边界上生效的那一刻发出）
signal track_toggled(id: String, on: bool)
## 应用了一次新的进度 / 小关
signal state_applied(section: int, progress: float)

const MUSIC_DIR := "res://levels/music/"
const SILENT_DB := -80.0
## 淡入很短（只为避免爆音），淡出 1 拍
const FADE_IN_SEC := 0.01

var data: Dictionary = {}
var stream: AudioStreamSynchronized
var track_ids: PackedStringArray = []
var section := 0
var progress := 0.0
## Director 面板用：静音 / 独奏某些 track（不写进配置）
var muted := {}
var soloed := {}

var _gain_db := PackedFloat32Array()   # 每条 track 自己的增益（配置里的 gain_db）
var _target := PackedFloat32Array()    # 应该响：1，不该响：0
var _level := PackedFloat32Array()     # 现在的音量（线性 0-1）
var _pending := false
var _next_beat := 0.0


func _ready() -> void:
	Conductor.beat.connect(_on_beat)


## 第 n 个大关（0 起）的配置文件路径
func path_for(level_index: int) -> String:
	return MUSIC_DIR + "level_%d.json" % (level_index + 1)


## 这一大关有没有配置、并且开了“在游戏里用”
func enabled_for(level_index: int) -> bool:
	var d := read(path_for(level_index))
	return d.get("use_in_game", false)


static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func write(path: String, d: Dictionary) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "\t"))
	return OK


## 按配置建同步流（所有 track 先静音），返回它，交给 Conductor 放。
func build(d: Dictionary) -> AudioStreamSynchronized:
	data = d
	stream = AudioStreamSynchronized.new()
	var tracks: Array = d.get("tracks", [])
	var n := mini(tracks.size(), AudioStreamSynchronized.MAX_STREAMS)
	if tracks.size() > n:
		push_warning("Music: %d tracks, only the first %d fit in one stream" % [tracks.size(), n])
	stream.stream_count = n
	track_ids = PackedStringArray()
	_gain_db.resize(n)
	_target.resize(n)
	_level.resize(n)
	for i in n:
		var t: Dictionary = tracks[i]
		var s: AudioStream = load(t.file)
		if s is AudioStreamWAV:
			# 循环整个文件（导入时写进 WAV 的循环点也是这样，这里再保证一次）
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(round(s.get_length() * s.mix_rate))
		stream.set_sync_stream(i, s)
		stream.set_sync_stream_volume(i, SILENT_DB)
		track_ids.append(t.id)
		_gain_db[i] = t.get("gain_db", 0.0)
		_target[i] = 0.0
		_level[i] = 0.0
	section = 0
	progress = 0.0
	_apply_now()
	return stream


## 配置的 BPM（默认 160）
func bpm() -> float:
	return data.get("bpm", 160.0)


## 进了第 index 个小关（进度从 0 开始），排到下一个边界生效
func set_section(index: int) -> void:
	section = index
	progress = 0.0
	_queue()


## 积累条进度变了（0-1），排到下一个边界生效
func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	_queue()


## 马上应用（不等边界）。Director 面板拖滑条时用。
func apply_now() -> void:
	_apply_now()


## 第 i 条 track 在这个小关、这个进度下该不该响（只看配置）
func rule_on(section_index: int, id: String, p: float) -> bool:
	var secs: Array = data.get("sections", [])
	if section_index < 0 or section_index >= secs.size():
		return false
	var ranges: Array = secs[section_index].get("rules", {}).get(id, [])
	for r in ranges:
		var a: float = r[0]
		var b: float = r[1]
		if p >= a and (p < b or (b >= 1.0 and p >= 1.0)):
			return true
	return false


## 改一条 track 的增益（dB），马上生效；面板用，配置要另存
func set_track_gain(id: String, db: float) -> void:
	var i := track_ids.find(id)
	if i >= 0:
		_gain_db[i] = db
		if _level[i] > 0.0001:
			stream.set_sync_stream_volume(i, linear_to_db(_level[i]) + db)


## 现在的音量（线性 0-1），面板画电平用
func level_of(i: int) -> float:
	return _level[i] if i < _level.size() else 0.0


func _queue() -> void:
	if stream == null:
		return
	_pending = true
	var q: float = data.get("quantize_beats", 4)
	_next_beat = (floorf(Conductor.song_beat / q) + 1.0) * q if Conductor.playing else 0.0


func _on_beat(index: int) -> void:
	if _pending and index >= int(round(_next_beat)):
		_apply_now()


func _apply_now() -> void:
	_pending = false
	var any_solo := false
	for id in soloed:
		if soloed[id]:
			any_solo = true
	for i in track_ids.size():
		var id := track_ids[i]
		var on := rule_on(section, id, progress)
		if any_solo:
			on = soloed.get(id, false)
		if muted.get(id, false):
			on = false
		var t := 1.0 if on else 0.0
		if t != _target[i]:
			track_toggled.emit(id, on)
		_target[i] = t
	state_applied.emit(section, progress)


func _process(delta: float) -> void:
	if stream == null:
		return
	var beat_sec := 60.0 / bpm()
	for i in _target.size():
		var cur := _level[i]
		var goal := _target[i]
		if cur == goal:
			continue
		var step := delta / (FADE_IN_SEC if goal > cur else beat_sec)
		cur = minf(goal, cur + step) if goal > cur else maxf(goal, cur - step)
		_level[i] = cur
		var db := SILENT_DB if cur <= 0.0001 else linear_to_db(cur) + _gain_db[i]
		stream.set_sync_stream_volume(i, db)
