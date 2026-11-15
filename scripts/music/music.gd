extends Node
## 叠轨音乐（autoload 名：Music）。设计见 docs/music_manager.md。
##
## 一关的音乐是几条"轨道"（节奏、低音、和声、旋律……），每条轨道里放几段 loop（片段），同一时刻
## 每条轨道只响一段。所有片段放进一个 AudioStreamSynchronized，从头一起放、从不停；换片段就是
## 改音量，所以永远对齐。
##
## 每个小关里，每条轨道有一串"切换点"：积累条进度到 X（0 = 刚进小关，1 = 满）时换成某段
## （"" = 静音）。当前进度之前最后一个切换点决定这条轨道响哪段。配置在 levels/music/<大关文件名>.json（如 level_1.json），
## 切换点在游戏里按 Tab 调出的面板上编辑（scripts/tools/game_editor.gd）；轨道和片段直接改 json。
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
## 谱子片段（不是 WAV，而是运行时按格子放喵的谱子，见 meow_player.gd）："轨道 id/片段 id" -> 谱子
var _patterns := {}
## 运行时放喵的节点
var meow: MeowPlayer
var _next_beat := 0.0

# --- 动态（配置里写 "dynamics": false 可以整套关掉）---------------------------------------------
## 换片段时旋律类的轨道等到乐句线（4 小节）才换，不把一句唱到一半切掉；可以在轨道上写 "quantize_beats" 改
const PHRASE_LANES := ["lead", "kiai"]
const PHRASE_BEATS := 16.0
## 降档迟钝：进度要掉到档位线以下这么多，才真的退一档（不然在线附近抖一下音轨就来回切）
const DOWN_MARGIN := 0.06
## 漏打时压低的轨道和压多少
const DIP_LANES := ["lead", "kiai"]
const DIP_DB := -14.0
const SFX_DIR := "res://assets/audio/sfx/"

## 实际用来选片段的进度：往上跟着积累条走，往下迟钝（见 DOWN_MARGIN）
var effective := 0.0
## 现在在第几档（这个小关里已经过了几条档位线）
var tier := 0
var _by_hit := {}                       # "轨道 id/片段 id" -> true：由玩家打中来唱的谱子片段
var _force := {}                        # 强制响的片段（KIAI）：lane id -> [clip id, 到第几拍为止]
var _dip_until := -1.0
var _dip_on := false
var _riser_for := -1                    # 已经为升到第几档放过上扬音效
var _quiet_tier_change := true          # 刚换小关 / 刚开始：档位变了不放音效
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_next := 0


func _ready() -> void:
	Conductor.beat.connect(_on_beat)
	meow = MeowPlayer.new()
	add_child(meow)
	for i in 3:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)


## 第 level_index 个大关（0 起）的音乐配置：和大关文件同名（levels/level_1.tres -> levels/music/level_1.json）
func path_for(level_index: int) -> String:
	return MUSIC_DIR + Levels.paths()[level_index].get_file().get_basename() + ".json"


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
	_patterns.clear()
	_by_hit.clear()
	_force.clear()
	effective = 0.0
	tier = 0
	_riser_for = -1
	_quiet_tier_change = true
	_dip_until = -1.0
	for key: String in meow.active.keys():
		meow.set_active(key, {})
	var streams: Array[AudioStream] = []
	for lane in d.get("lanes", []):
		_lane_gain[lane.id] = lane.get("gain_db", 0.0)
		for clip in lane.get("clips", []):
			# 谱子片段（{"id", "pattern": "res://levels/music/patterns/x.json"}）不进同步流，由 meow 按格子放
			# 加上 "by_hit": true 的谱子片段不自己响：玩家每打中一下，才唱出离现在最近的那个音
			if clip.has("pattern"):
				_patterns["%s/%s" % [lane.id, clip.id]] = MeowPlayer.read_pattern(clip.pattern)
				if clip.get("by_hit", false):
					_by_hit["%s/%s" % [lane.id, clip.id]] = true
				continue
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


## 这一关不用叠轨音乐：把上一关留下的东西清掉（不然上一关的喵谱子、KIAI、打中唱会跟到这一关来）
func clear() -> void:
	data = {}
	stream = null
	_patterns.clear()
	_by_hit.clear()
	_force.clear()
	_now.clear()
	_pending = false
	_dip_until = -1.0
	for key: String in meow.active.keys():
		meow.set_active(key, {})


func bpm() -> float:
	return data.get("bpm", 160.0)


## 进了第 index 个小关（进度从 0 开始），排到下一个边界生效
func set_section(index: int) -> void:
	section = index
	progress = 0.0
	effective = 0.0
	_riser_for = -1
	_quiet_tier_change = true
	_queue()


## 积累条进度变了（0-1），排到下一个边界生效。
## 往上直接跟；往下迟钝：掉到当前档位线以下 DOWN_MARGIN 才退档，不然就停在档位线上。
func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	if not dynamics() or progress >= effective:
		effective = progress
	else:
		var lines := tier_lines(section)
		var k := tier_of(effective, lines)
		var line: float = lines[k - 1] if k > 0 else 0.0
		effective = progress if k == 0 or progress < line - DOWN_MARGIN else maxf(progress, line)
	_queue()


## 这套配置开没开动态（升档过门、降档迟钝、乐句线切换、漏打压低、KIAI）
func dynamics() -> bool:
	return data.get("dynamics", true)


## 这个小关的档位线（0-1，从小到大）：小关里写了 "tiers" 就用它，否则是所有切换点的位置
func tier_lines(section_index: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var secs: Array = data.get("sections", [])
	if section_index < 0 or section_index >= secs.size():
		return out
	var sec: Dictionary = secs[section_index]
	if sec.has("tiers"):
		for v in sec.tiers:
			out.append(float(v))
	else:
		var seen := {}
		for lane_cues: Array in sec.get("cues", {}).values():
			for cue: Array in lane_cues:
				var at := snappedf(float(cue[0]), 0.001)
				if at > 0.0 and not seen.has(at):
					seen[at] = true
					out.append(at)
	out.sort()
	return out


## 进度 p 已经过了几条档位线
func tier_of(p: float, lines: PackedFloat32Array) -> int:
	var k := 0
	for line in lines:
		if p + 0.0001 >= line:
			k += 1
	return k


## KIAI：不管积累条到哪，让 kiai 轨道（鬼畜猫旋律）响 bars 小节。now = 马上开始，否则从下一个小节线开始。
## 连击到里程碑、积累条刚满的时候用。这一关没有 kiai 轨道就什么也不做。
func kiai(bars := 4, now := false) -> void:
	if stream == null or not dynamics():
		return
	for lane in data.get("lanes", []):
		if lane.id == "kiai" and not lane.get("clips", []).is_empty():
			var from := Conductor.song_beat if now else ceilf(Conductor.song_beat / 4.0) * 4.0
			_force["kiai"] = [lane.clips[0].id, from + bars * 4.0]
			if now:
				_apply_now()
			else:
				_queue()


## 漏打：旋律类的轨道压低 beats 拍（听起来像旋律被打断了一下）
func dip(beats := 1.0) -> void:
	if stream != null and dynamics() and Conductor.playing:
		_dip_until = Conductor.song_beat + beats


## 放一个一次性音效（assets/audio/sfx/<name>.wav）。ends_in_sec > 0：变速，让它正好在这么多秒后放完。
func play_sfx(sfx_name: String, db := 0.0, ends_in_sec := 0.0) -> void:
	var path := SFX_DIR + sfx_name + ".wav"
	if not ResourceLoader.exists(path):
		return
	var p := _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx.size()
	p.stream = load(path)
	p.volume_db = db
	p.pitch_scale = clampf(p.stream.get_length() / ends_in_sec, 0.5, 2.0) if ends_in_sec > 0.0 else 1.0
	p.play()


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


## 把一个谱子片段加进某条轨道（没有这条轨道就新建），之后就能像别的片段一样按进度切换到它。
## 已经有同名片段就只是重新读一遍谱子。返回片段 id。
func add_pattern_clip(lane_id: String, pattern_path: String) -> String:
	var clip_id := pattern_path.get_file().get_basename()
	var lanes: Array = data.get("lanes", [])
	var lane: Dictionary = {}
	for l: Dictionary in lanes:
		if l.id == lane_id:
			lane = l
	if lane.is_empty():
		lane = {"id": lane_id, "name": lane_id, "gain_db": 0.0, "clips": []}
		lanes.append(lane)
		data["lanes"] = lanes
		_lane_gain[lane_id] = 0.0
	var found := false
	for c: Dictionary in lane.clips:
		if c.id == clip_id:
			found = true
	if not found:
		lane.clips.append({"id": clip_id, "pattern": pattern_path})
	_patterns["%s/%s" % [lane_id, clip_id]] = MeowPlayer.read_pattern(pattern_path)
	_apply_now()
	return clip_id


## 谱子片段的文件改了：重新读（正在播的马上换成新的）
func reload_patterns() -> void:
	for lane in data.get("lanes", []):
		for clip in lane.get("clips", []):
			if clip.has("pattern"):
				_patterns["%s/%s" % [lane.id, clip.id]] = MeowPlayer.read_pattern(clip.pattern)
	_apply_now()


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
	# 要升档了：先放一声上扬音效，正好在换的那一拍放完
	if dynamics() and Conductor.playing and not _quiet_tier_change:
		var up := tier_of(effective, tier_lines(section))
		var left := (_next_beat - Conductor.song_beat) * Conductor.sec_per_beat()
		if up > tier and up != _riser_for and left > 0.35:
			_riser_for = up
			play_sfx("riser_1b", -8.0, left)


func _on_beat(index: int) -> void:
	var expired := false
	for lane_id: String in _force.keys():
		if index >= int(round(_force[lane_id][1])):
			_force.erase(lane_id)
			expired = true
	if expired or (_pending and index >= int(round(_next_beat))):
		_apply_now(index)


## beat_index >= 0：这是在第几拍的边界上应用的（用来判断是不是乐句线）；-1 = 马上、不管边界
func _apply_now(beat_index := -1) -> void:
	_pending = false
	var base: float = data.get("quantize_beats", 4)
	var use_dynamics := dynamics()
	for lane in data.get("lanes", []):
		var c := clip_at(section, lane.id, effective)
		if _force.has(lane.id):
			c = _force[lane.id][0]
		if muted.get(lane.id, false):
			c = ""
		var was: String = _now.get(lane.id, "")
		if was != c:
			# 旋律类的轨道从一段换到另一段：等到乐句线。从没声到有声、或者要静音，不用等。
			var q: float = lane.get("quantize_beats", PHRASE_BEATS if lane.id in PHRASE_LANES else base)
			if use_dynamics and beat_index >= 0 and q > base and was != "" and c != "" \
					and not _force.has(lane.id) and beat_index % int(q) != 0:
				_pending = true
				_next_beat = beat_index + base
				c = was
			else:
				lane_switched.emit(lane.id, c)
		_now[lane.id] = c
		var key := "%s/%s" % [lane.id, c]
		meow.set_active(lane.id, _patterns.get(key, {}), float(_lane_gain.get(lane.id, 0.0)), _by_hit.has(key))
	for i in _slot_lane.size():
		_target[i] = 1.0 if _now.get(_slot_lane[i], "") == _slot_clip[i] else 0.0
	# 档位变了：升档 = 镲 + 一声上扬的喵，降档 = 一声往下的喵（刚换小关那一次不放）
	var new_tier := tier_of(effective, tier_lines(section))
	if use_dynamics and Conductor.playing and not _quiet_tier_change and beat_index >= 0:
		if new_tier > tier:
			play_sfx("crash", -9.0)
			play_sfx("catness_up", -6.0)
		elif new_tier < tier:
			play_sfx("catness_down", -6.0)
	if beat_index >= 0:
		_quiet_tier_change = false
	tier = new_tier


func _process(delta: float) -> void:
	if stream == null:
		return
	var beat_sec := 60.0 / bpm()
	var dip_now := Conductor.playing and Conductor.song_beat < _dip_until
	var dip_changed := dip_now != _dip_on
	_dip_on = dip_now
	for i in _target.size():
		var cur := _level[i]
		var goal := _target[i]
		var dipped := _slot_lane[i] in DIP_LANES
		if cur == goal and not (dip_changed and dipped):
			continue
		if cur != goal:
			var step := delta / (FADE_IN_SEC if goal > cur else beat_sec)
			cur = minf(goal, cur + step) if goal > cur else maxf(goal, cur - step)
			_level[i] = cur
		var db: float = SILENT_DB if cur <= 0.0001 else linear_to_db(cur) + float(_lane_gain.get(_slot_lane[i], 0.0))
		if dip_now and dipped and cur > 0.0001:
			db += DIP_DB
		stream.set_sync_stream_volume(i, db)
