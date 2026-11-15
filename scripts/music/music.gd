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
## 档位变了（在小节线上生效的那一刻）。new_tier = 这个小关里已经过了几条档位线，up = 是升档
signal tier_changed(new_tier: int, up: bool)
## FEVER 开始 / 结束（在小节线上）。画面、得分想跟着 fever 走就接这两个。
signal fever_started
signal fever_ended

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
## 过门小节：配置里有一条 id 是 "fill" 的轨道（里面放一段过门，比如 s1_X_fill）时才有。
## 换小关时、以及升到小关里 "transition_tiers" 写的那几档时，先放一小节过门（只留节奏轨 + 过门，别的都停），
## 下一个小节线才换成新的。所有的切换都落在小节线上。
const FILL_LANE := "fill"
const KEEP_IN_FILL := ["beat"]          # 过门小节里照常响的轨道
var _fill_done_for := -1                # 已经为升到第几档放过过门小节

## FEVER：手动设计的。每个小关的配置里写 "fever": [从, 到]（积累条进度 0-1，可以写好几段 [[a, b], [c, d]]），
## 进度走进这一段就是 fever：先一小节过门（有过门轨道的话），然后鬼畜猫旋律（kiai 轨道）和"打中唱"（hit 轨道）
## 全程开着，不管它们的切换点怎么写；走出这一段（往上走完，或者掉回去）就结束。
## 另外每次升档会送一小节"小 kiai"（鬼畜猫旋律响一小节就退），fever 里面不重复送。
const FEVER_LANES := ["kiai", "hit"]
var fever := false
var _fever_fill_done := false
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_next := 0

## 关与关之间的过门（一路连着玩）。Music 是自动加载，换场景不会被清掉，所以它能从上一关响到下一关：
##   bridge_out()  上一关打完：一声"飞走"的音效，同时起一段等待的循环（风 + 心跳 + 一个低音）
##   （换场景、加载；玩家看到下一关，喘口气）
##   bridge_go()   玩家按了一下、下一关的预备拍开始：一小节数拍子（四声 mi），等待的循环在这一小节里淡出
const BRIDGE_LOOP := "res://assets/audio/music/sky/bridge_wait_4b.wav"
var _bridge: AudioStreamPlayer
var _whoosh_ms := -100000
var _bridge_fade: Tween


func _ready() -> void:
	Conductor.beat.connect(_on_beat)
	meow = MeowPlayer.new()
	add_child(meow)
	for i in 3:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)
	_bridge = AudioStreamPlayer.new()
	add_child(_bridge)


## 第 level_index 个大关（0 起）的音乐配置：和大关文件同名（levels/level_1.tres -> levels/music/level_1.json）
## （正在玩插曲关时，当前这一关指的是插曲关：levels/interludes/after_x.tres -> levels/music/after_x.json）
func path_for(level_index: int) -> String:
	var level: String = Levels.current_path() if level_index == Levels.selected else Levels.paths()[level_index]
	return MUSIC_DIR + level.get_file().get_basename() + ".json"


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
	_fill_done_for = -1
	_quiet_tier_change = true
	_dip_until = -1.0
	_end_fever()
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
	_end_fever()
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
	var changed := index != section
	_end_fever()
	section = index
	progress = 0.0
	effective = 0.0
	_riser_for = -1
	_fill_done_for = -1
	_quiet_tier_change = true
	_queue()
	# 换小关是在小节线上发生的：这一小节放过门，下一个小节线（上面排好的）新小关的音乐才进来
	if changed and dynamics() and Conductor.playing and Conductor.song_beat > 1.0 and _fill_clip() != "":
		_play_fill_bar()
		play_sfx("crash", -9.0)


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


## 这个小关升到第 t 档（1 起）时要不要先放一小节过门：小关里的 "transition_tiers"
func _wants_fill(t: int) -> bool:
	var secs: Array = data.get("sections", [])
	if section < 0 or section >= secs.size():
		return false
	for v in secs[section].get("transition_tiers", []):
		if int(v) == t:
			return true
	return false


## 升到这个小关的第 t 档（1 起）时放的专用音效（没写就是 ""）
func _tier_sfx(t: int) -> String:
	var secs: Array = data.get("sections", [])
	if section < 0 or section >= secs.size():
		return ""
	return str(secs[section].get("tier_sfx", {}).get(str(t), ""))


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
			var line := snappedf(float(v), 0.001)      # 和 fever 的两头用同一个精度，不然同一条线会算两次
			if not out.has(line):
				out.append(line)
	else:
		var seen := {}
		for lane_cues: Array in sec.get("cues", {}).values():
			for cue: Array in lane_cues:
				var at := snappedf(float(cue[0]), 0.001)
				if at > 0.0 and not seen.has(at):
					seen[at] = true
					out.append(at)
	for r: Array in fever_ranges(section_index):          # fever 的两头也是档位线（进出 fever 也有迟钝）
		for v: float in r:
			if v > 0.0 and v < 1.0 and not out.has(v):
				out.append(v)
	out.sort()
	return out


## 这个小关手动标的 fever 段：[[从, 到], ...]（没标就是空的）
func fever_ranges(section_index: int) -> Array:
	var secs: Array = data.get("sections", [])
	if section_index < 0 or section_index >= secs.size():
		return []
	var raw: Array = secs[section_index].get("fever", [])
	if raw.is_empty():
		return []
	if not raw[0] is Array:
		raw = [raw]
	var out: Array = []
	for r: Array in raw:
		out.append([snappedf(float(r[0]), 0.001), snappedf(float(r[1]), 0.001)])
	return out


## 进度 p 在不在这个小关的 fever 段里
func in_fever(p: float) -> bool:
	for r: Array in fever_ranges(section):
		if p + 0.0001 >= r[0] and (p < r[1] or r[1] >= 0.999):
			return true
	return false


func _end_fever() -> void:
	_fever_fill_done = false
	if fever:
		fever = false
		fever_ended.emit()


## 某条轨道里的第一段（没有这条轨道或者它是空的，返回 ""）
func _first_clip(lane_id: String) -> String:
	for lane in data.get("lanes", []):
		if lane.id == lane_id and not lane.get("clips", []).is_empty():
			return lane.clips[0].id
	return ""


## 进度 p 已经过了几条档位线
func tier_of(p: float, lines: PackedFloat32Array) -> int:
	var k := 0
	for line in lines:
		if p + 0.0001 >= line:
			k += 1
	return k


## 过门轨道里的那一段（没有过门轨道返回 ""）
func _fill_clip() -> String:
	for lane in data.get("lanes", []):
		if lane.id == FILL_LANE and not lane.get("clips", []).is_empty():
			return lane.clips[0].id
	return ""


## 现在起放过门：过门轨道响，节奏轨照旧，别的轨道都停（淡出一拍）。之后由下一次 _apply_now 换成该响的。
func _play_fill_bar() -> void:
	var fill := _fill_clip()
	for lane in data.get("lanes", []):
		var c: String = fill if lane.id == FILL_LANE else (_now.get(lane.id, "") if lane.id in KEEP_IN_FILL else "")
		if _now.get(lane.id, "") != c:
			lane_switched.emit(lane.id, c)
		_now[lane.id] = c
		meow.set_active(lane.id, {})
	for i in _slot_lane.size():
		_target[i] = 1.0 if _now.get(_slot_lane[i], "") == _slot_clip[i] else 0.0


## 积累条满了，下一个小节线要换小关：放一声上扬音效，正好在那条小节线上放完
func rise_to_bar() -> void:
	if stream == null or not dynamics() or not Conductor.playing:
		return
	var line := (floorf(Conductor.song_beat / 4.0) + 1.0) * 4.0
	var left := (line - Conductor.song_beat) * Conductor.sec_per_beat()
	if left > 0.35:
		play_sfx("riser_1b", -6.0, left)


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


## 第 1 关的温馨开头：放那段八音盒的循环（一直响到 cozy_snap）
const COZY_LOOP := "res://assets/audio/music/sky/cozy_intro_8b.wav"

func cozy_intro() -> void:
	if not ResourceLoader.exists(COZY_LOOP):
		return
	if _bridge_fade:
		_bridge_fade.kill()
	_bridge.stream = load(COZY_LOOP)
	_bridge.volume_db = -3.0
	_bridge.play()


## 玩家按下去了，画风突变：八音盒戛然而止，一声 glitch 喵，一段倒带正好倒到第一拍（seconds 秒后）
func cozy_snap(seconds := 1.5) -> void:
	if _bridge_fade:
		_bridge_fade.kill()
	_bridge.stop()
	play_sfx("glitch_meow", -3.0)
	play_sfx("rewind_1b", -5.0, seconds)


## 上一关打完，要去下一关：飞走的音效 + 等待的循环（一直响到 bridge_go）
func bridge_out() -> void:
	if not ResourceLoader.exists(BRIDGE_LOOP):
		return
	if _bridge_fade:
		_bridge_fade.kill()
	if Time.get_ticks_msec() - _whoosh_ms > 5000:      # 关卡自己刚放过"飞走"（猫飞出屏幕）就不再放一遍
		play_sfx("sky_whoosh_up", -3.0)
	_bridge.stream = load(BRIDGE_LOOP)
	_bridge.volume_db = -5.0
	_bridge.play()


## 现在是不是在两关之间等着（过门在响）
func bridge_active() -> bool:
	return _bridge != null and _bridge.playing


## 下一关正式开始（预备拍从现在起，seconds 秒后是第一拍）：数拍子，等待的循环淡出
func bridge_go(seconds := 1.5) -> void:
	if not bridge_active():
		return
	play_sfx("count_in", -4.0, seconds)
	if _bridge_fade:
		_bridge_fade.kill()
	_bridge_fade = create_tween()
	_bridge_fade.tween_property(_bridge, "volume_db", -40.0, seconds)
	_bridge_fade.tween_callback(_bridge.stop)


## 放一个一次性音效（assets/audio/sfx/<name>.wav）。ends_in_sec > 0：变速，让它正好在这么多秒后放完。
func play_sfx(sfx_name: String, db := 0.0, ends_in_sec := 0.0) -> void:
	var path := SFX_DIR + sfx_name + ".wav"
	if not ResourceLoader.exists(path):
		return
	if sfx_name == "sky_whoosh_up":
		_whoosh_ms = Time.get_ticks_msec()
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
	# 升到要过门的那一档：这条小节线先放一小节过门，下一条小节线才真的换
	var going_to := tier_of(effective, tier_lines(section))
	if use_dynamics and beat_index >= 0 and going_to > tier and going_to != _fill_done_for \
			and _fill_clip() != "" and _wants_fill(going_to):
		_fill_done_for = going_to
		_play_fill_bar()
		_pending = true
		_next_beat = beat_index + base
		return
	# 要进 fever：也先一小节过门
	var fever_now := use_dynamics and in_fever(effective)
	if fever_now and not fever and not _fever_fill_done and beat_index >= 0 and _fill_clip() != "":
		_fever_fill_done = true
		_play_fill_bar()
		_pending = true
		_next_beat = beat_index + base
		return
	# 升档：送一小节小 kiai（fever 里本来就开着，不用送）
	if use_dynamics and beat_index >= 0 and not _quiet_tier_change and going_to > tier and not fever_now \
			and not _force.has("kiai") and _first_clip("kiai") != "" and _tier_sfx(going_to) == "":
		_force["kiai"] = [_first_clip("kiai"), float(beat_index) + base]
	for lane in data.get("lanes", []):
		var c := clip_at(section, lane.id, effective)
		if fever_now and c == "" and lane.id in FEVER_LANES and not lane.get("clips", []).is_empty():
			c = lane.clips[0].id
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
			# 这一档有自己的音效（小关里的 "tier_sfx": {"2": "sky_holy_hit"}）就放它，不放通用的镲和喵，也不送小 kiai
			if _tier_sfx(new_tier) != "":
				play_sfx(_tier_sfx(new_tier), -2.0)
			else:
				play_sfx("crash", -9.0)
				play_sfx("catness_up", -6.0)
		elif new_tier < tier:
			play_sfx("catness_down", -6.0)
	if beat_index >= 0:
		_quiet_tier_change = false
	if new_tier != tier:
		tier_changed.emit(new_tier, new_tier > tier)
	tier = new_tier
	if fever_now != fever:
		fever = fever_now
		if fever:
			if Conductor.playing and beat_index >= 0:
				play_sfx("crash", -7.0)
				play_sfx("spin_meow_a", -5.0)
			fever_started.emit()
		else:
			_fever_fill_done = false
			fever_ended.emit()


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
