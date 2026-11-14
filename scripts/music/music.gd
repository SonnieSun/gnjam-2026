extends Node
## 叠轨音乐（autoload 名：Music）。设计见 docs/music_manager.md。
##
## 一关的音乐是几条"轨道"（节奏、低音、和声、旋律……），每条轨道里放几段 loop（片段），同一时刻
## 每条轨道只响一段。所有片段放进一个 AudioStreamSynchronized，从头一起放、从不停；换片段就是
## 改音量，所以永远对齐。
##
## 每个小关里，每条轨道有一串"切换点"：积累条进度到 X（0 = 刚进小关，1 = 满）时换成某段
## （"" = 静音）。当前进度之前最后一个切换点决定这条轨道响哪段。配置在 levels/music/<谱面名>.json（如 disco.json），
## 用 Music Director 面板（scenes/tools/music_director.tscn）编辑。
##
## 进度和小关的变化排队到下一个边界（默认 4 拍 = 一小节）才生效。时钟仍然是 Conductor：
## 它放的就是这里建出来的同步流。

## 一条轨道换了片段（在边界上生效的那一刻发出；clip 为 "" 表示静音）
signal lane_switched(lane: String, clip: String)

const MUSIC_DIR := "res://levels/music/"
const SILENT_DB := -80.0
const FADE_IN_SEC := 0.01   # 只为避免爆音；淡出 1 拍

var data: Dictionary = {}
var stream: AudioStreamSynchronized
var section := 0
var progress := 0.0
## Director 面板用：静音的轨道（lane id -> true），不写进配置
var muted := {}

## 同步流里第 i 条子流是哪条轨道的哪段
var _slot_lane := PackedStringArray()
var _slot_clip := PackedStringArray()
var _lane_gain := {}                    # lane id -> dB
var _now := {}                          # lane id -> 现在响的片段
var _target := PackedFloat32Array()
var _level := PackedFloat32Array()
var _pending := false
var _next_beat := 0.0


func _ready() -> void:
	Conductor.beat.connect(_on_beat)


## 第 level_index 个大关（0 起）的音乐配置：按它用的谱面命名（disco_chart.gd -> disco.json），
## 所以用同一个谱面的大关共用一套音乐，各分支的大关顺序不同也对得上。
func path_for(level_index: int) -> String:
	var chart: String = Levels.LIST[level_index].chart
	return MUSIC_DIR + chart.get_file().get_basename().trim_suffix("_chart") + ".json"


func enabled_for(level_index: int) -> bool:
	return read(path_for(level_index)).get("use_in_game", false)


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


## 按配置建同步流（全部静音），返回它，交给 Conductor 放。
func build(d: Dictionary) -> AudioStreamSynchronized:
	data = d
	stream = AudioStreamSynchronized.new()
	_slot_lane = PackedStringArray()
	_slot_clip = PackedStringArray()
	_lane_gain.clear()
	_now.clear()
	var streams: Array[AudioStream] = []
	for lane in d.get("lanes", []):
		_lane_gain[lane.id] = lane.get("gain_db", 0.0)
		for clip in lane.get("clips", []):
			if streams.size() >= AudioStreamSynchronized.MAX_STREAMS:
				push_warning("Music: more than %d clips, the rest are left out" % AudioStreamSynchronized.MAX_STREAMS)
				break
			var s: AudioStream = load(clip.file)
			if s is AudioStreamWAV:
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_begin = 0
				s.loop_end = int(round(s.get_length() * s.mix_rate))
			streams.append(s)
			_slot_lane.append(lane.id)
			_slot_clip.append(clip.id)
	stream.stream_count = streams.size()
	_target.resize(streams.size())
	_level.resize(streams.size())
	for i in streams.size():
		stream.set_sync_stream(i, streams[i])
		stream.set_sync_stream_volume(i, SILENT_DB)
		_target[i] = 0.0
		_level[i] = 0.0
	section = 0
	progress = 0.0
	_apply_now()
	return stream


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


## 马上应用（不等边界）
func apply_now() -> void:
	_apply_now()


## 这条轨道在这个小关、这个进度该响哪段（"" = 静音）
func clip_at(section_index: int, lane: String, p: float) -> String:
	var secs: Array = data.get("sections", [])
	if section_index < 0 or section_index >= secs.size():
		return ""
	var clip := ""
	var best := -1.0
	for cue in secs[section_index].get("cues", {}).get(lane, []):
		var at: float = cue[0]
		if at <= p + 0.0001 and at >= best:
			best = at
			clip = cue[1]
	return clip


## 这条轨道现在（最近一次应用时）响的片段
func playing_clip(lane: String) -> String:
	return _now.get(lane, "")


## 某段现在的音量（线性 0-1）
func level_of(lane: String, clip: String) -> float:
	for i in _slot_lane.size():
		if _slot_lane[i] == lane and _slot_clip[i] == clip:
			return _level[i]
	return 0.0


func set_lane_gain(lane: String, db: float) -> void:
	_lane_gain[lane] = db
	for i in _slot_lane.size():
		if _slot_lane[i] == lane and _level[i] > 0.0001:
			stream.set_sync_stream_volume(i, linear_to_db(_level[i]) + db)


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
	for lane in data.get("lanes", []):
		var c := "" if muted.get(lane.id, false) else clip_at(section, lane.id, progress)
		if _now.get(lane.id, "") != c:
			lane_switched.emit(lane.id, c)
		_now[lane.id] = c
	for i in _slot_lane.size():
		_target[i] = 1.0 if _now.get(_slot_lane[i], "") == _slot_clip[i] else 0.0


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
		var db: float = SILENT_DB if cur <= 0.0001 else linear_to_db(cur) + float(_lane_gain.get(_slot_lane[i], 0.0))
		stream.set_sync_stream_volume(i, db)
