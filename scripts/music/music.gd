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
## 预备信号：进度刚过了一条线，这次切换已经排好了，还没发生。kind = "tier"（升到第 id 档）/ "fever"（进 fever）。
## fill_beat = 过门从哪一拍起，commit_beat = 新的那一段从哪一拍进（都是小节线；没有过门时两个一样）。
## 场景、谱面要和音乐的切换对上，就听这个信号按这两个拍点排自己的事，不要在进度过线的那一下各自开始。
## 正式切换的那一下是 tier_changed / fever_started。有乐句线要等（"on_bars"）的切换，拍点是按现在在放的曲子推出来的。
signal change_planned(kind: String, id: int, fill_beat: float, commit_beat: float)
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
var _slot_gain := PackedFloat32Array()   # 片段自己的 "gain_db"（加在所在那一轨的音量上）
var _slot_clip := PackedStringArray()
## 每一段在哪个同步流里、是里面的第几条（见下面的"曲子组"）
var _slot_stream: Array[AudioStreamSynchronized] = []
var _slot_index := PackedInt32Array()
var _slot_tune := PackedStringArray()

## 曲子组：片段上写了 "tune": "ode" 的，同一首曲子的几条轨道单独放在一个同步流里，用自己的播放器放，
## 不跟主同步流（鼓这些没写 tune 的）绑在一起。这首曲子的轨道从"都没响"变成"有一条要响"的那条小节线，
## 它从自己的第 1 小节放起；都不响了就停，下次再进来又从第 1 小节起。
## （都放在一个同步流里的话，所有片段共用一个播放位置，曲子总是从循环的中间接上，听着像从第二小节开始唱。）
## 两个播放器走的是同一个音频时钟，不会越走越偏；起播时按节拍时钟算好该从第几秒放起，偶尔差多了会自己对回去。
## 这首曲子的喵谱子（和声、打中唱）也从同一条小节线算起。
var _tunes := {}          # 名字 -> {"stream", "player", "origin"（从第几拍起，没在放是 INF）, "length"（秒）}
var _pattern_tune := {}   # "轨道/片段" -> 曲子名（喵谱子片段）
const TUNE_RESYNC_SEC := 0.04
## 起播之后实测：曲子比节拍早这么多秒（和声卡的缓冲有关，每台机器不一样）。起播时把它扣掉；
## 每次起播后量一小会儿，慢慢修这个数，所以同一次运行里越往后越准。
static var _tune_bias := 0.012
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
## 鬼畜猫旋律叠在猫主唱上面的时候（升档送的小 kiai、连击里程碑、有的关的 fever），两条猫旋律一起全音量会乱：
## 主唱（lead 轨）让开这么多 dB，鬼畜在前面，主唱垫在下面。只在 kiai 轨上响的是鬼畜（片段名里有 kichiku）时才让，
## kiai 轨上是乐器（比如 cc_double）就不让。
const KIAI_DUCK_DB := -6.0
var _duck_on := false
var _plan := {}           # 排好了还没发生的那次切换（见 change_planned / planned_change）
var _planned_for := -1    # 已经为升到第几档排过
var _fill_until := -1.0  # 几小节长的专门过门放到第几拍：在那之前不换（进度变了也不重新排到更早的小节线）
var _outro := false       # 结尾段在放：除了鼓，别的轨道都停着（见 outro()）
var _outro_wait := false  # 叫了 outro()，等下一条小节线
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
## 换小关、进 fever、以及切换描述里写了要过门的那几档，先放一小节过门（只留节奏轨 + 过门，别的都停；见 change_spec），
## 下一个小节线才换成新的。所有的切换都落在小节线上。
const FILL_LANE := "fill"
# 过门小节里照常响的轨道：鼓、低音、和声都不停，只有旋律、高潮层、猫叫让出一小节（全停听起来像音乐断了）
const KEEP_IN_FILL := ["beat", "bass", "bed"]
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
## 等待的时候透出来的"下一关的声音"（见 bridge_tease）
var _tease: AudioStreamPlayer
var _tease_fade: Tween
## 透出来多响（dB）、用几秒淡进来
const TEASE_DB := -4.0
const TEASE_FADE := 0.8
## 等待的循环多响（dB）：刚打完时 / 下一关的声音进来之后
const BRIDGE_DB := -2.0
const BRIDGE_UNDER_DB := -6.0


func _ready() -> void:
	Conductor.beat.connect(_on_beat)
	# 总线上放一个限幅器：满编制的段落（大高潮）各条音轨加起来会超过满幅，不拦着就是爆音。平时够不到它，不改变声音。
	if not _has_limiter():
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.3
		lim.pre_gain_db = 0.0
		lim.release = 0.1
		AudioServer.add_bus_effect(0, lim)
	fever_started.connect(_set_fever_reverb.bind(true))
	fever_ended.connect(_set_fever_reverb.bind(false))
	meow = MeowPlayer.new()
	add_child(meow)
	for i in 3:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)
	_bridge = AudioStreamPlayer.new()
	add_child(_bridge)
	_tease = AudioStreamPlayer.new()
	add_child(_tease)


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
	_carry = 0.0
	data = d
	stream = AudioStreamSynchronized.new()
	_slot_lane = PackedStringArray()
	_slot_gain = PackedFloat32Array()
	_slot_clip = PackedStringArray()
	_slot_stream = []
	_slot_index = PackedInt32Array()
	_slot_tune = PackedStringArray()
	_free_tunes()
	_pattern_tune.clear()
	_lane_gain.clear()
	_fill_until = -1.0
	_plan = {}
	_planned_for = -1
	_set_fever_reverb(false)
	_outro = false
	_outro_wait = false
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
	var tune_streams := {}
	for lane in d.get("lanes", []):
		_lane_gain[lane.id] = lane.get("gain_db", 0.0)
		for clip in lane.get("clips", []):
			# 谱子片段（{"id", "pattern": "res://levels/music/patterns/x.json"}）不进同步流，由 meow 按格子放
			# 加上 "by_hit": true 的谱子片段不自己响：玩家每打中一下，才唱出离现在最近的那个音
			if clip.has("pattern"):
				_patterns["%s/%s" % [lane.id, clip.id]] = MeowPlayer.read_pattern(clip.pattern)
				if str(clip.get("tune", "")) != "":
					_pattern_tune["%s/%s" % [lane.id, clip.id]] = str(clip.tune)
				if clip.get("by_hit", false):
					_by_hit["%s/%s" % [lane.id, clip.id]] = true
				continue
			var tune := str(clip.get("tune", ""))
			var into: Array = tune_streams.get(tune, []) if tune != "" else streams
			if into.size() >= AudioStreamSynchronized.MAX_STREAMS:
				push_warning("Music: more than %d clips, the rest are left out" % AudioStreamSynchronized.MAX_STREAMS)
				break
			var s: AudioStream = load(clip.file)
			if s is AudioStreamWAV:
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_begin = 0
				s.loop_end = int(round(s.get_length() * s.mix_rate))
			if tune != "" and not _tunes.has(tune):
				var player := AudioStreamPlayer.new()
				add_child(player)
				_tunes[tune] = {"stream": AudioStreamSynchronized.new(), "player": player, "origin": INF, "length": 0.0}
				tune_streams[tune] = into
			_slot_stream.append(_tunes[tune].stream if tune != "" else stream)
			_slot_index.append(into.size())
			_slot_tune.append(tune)
			into.append(s)
			_slot_lane.append(lane.id)
			_slot_gain.append(float(clip.get("gain_db", 0.0)))
			_slot_clip.append(clip.id)
	stream.stream_count = streams.size()
	for i in streams.size():
		stream.set_sync_stream(i, streams[i])
	for tune: String in tune_streams:
		var ts: AudioStreamSynchronized = _tunes[tune].stream
		var list: Array = tune_streams[tune]
		ts.stream_count = list.size()
		for i in list.size():
			ts.set_sync_stream(i, list[i])
			_tunes[tune].length = maxf(float(_tunes[tune].length), (list[i] as AudioStream).get_length())
		(_tunes[tune].player as AudioStreamPlayer).stream = ts
	_target.resize(_slot_lane.size())
	_level.resize(_slot_lane.size())
	for i in _slot_lane.size():
		_slot_stream[i].set_sync_stream_volume(_slot_index[i], SILENT_DB)
		_target[i] = 0.0
		_level[i] = 0.0
	section = 0
	progress = 0.0
	_apply_now()
	return stream


## 这一关不用叠轨音乐：把上一关留下的东西清掉（不然上一关的喵谱子、KIAI、打中唱会跟到这一关来）
func _free_tunes() -> void:
	for tune: String in _tunes:
		(_tunes[tune].player as AudioStreamPlayer).stop()
		(_tunes[tune].player as AudioStreamPlayer).queue_free()
	_tunes.clear()


## 这个片段属于哪首曲子（"" = 不属于哪首，在主同步流里）
func _tune_of(lane_id: String, clip_id: String) -> String:
	for i in _slot_lane.size():
		if _slot_lane[i] == lane_id and _slot_clip[i] == clip_id:
			return _slot_tune[i]
	return str(_pattern_tune.get("%s/%s" % [lane_id, clip_id], ""))


## 这首曲子现在该不该响：它有一条轨道要响，或者它的一个喵谱子片段在用
func _tune_wanted(tune: String) -> bool:
	for i in _slot_tune.size():
		if _slot_tune[i] == tune and _target[i] > 0.0:
			return true
	for key: String in _pattern_tune:
		if _pattern_tune[key] == tune and _now.get(key.get_slice("/", 0), "") == key.get_slice("/", 1):
			return true
	return false


## 排好了各条轨道该响什么之后：刚进来的曲子记下从哪条小节线起（beat_index < 0 = 还没开始放，从第 0 拍起）
func _mark_tunes(beat_index: int) -> void:
	for tune: String in _tunes:
		if _tune_wanted(tune) and is_inf(_tunes[tune].origin):
			_tunes[tune].origin = float(beat_index) if beat_index >= 0 else maxf(floorf(Conductor.song_beat / 4.0) * 4.0, 0.0) if Conductor.playing else 0.0


## 每帧：该响的曲子没在放就放起来（从算好的位置放，正好对上节拍），放偏了对回去；不该响、也淡完了的停掉
func _run_tunes() -> void:
	var spb := 60.0 / bpm()
	for tune: String in _tunes:
		var t: Dictionary = _tunes[tune]
		var player: AudioStreamPlayer = t.player
		if is_inf(t.origin) or not Conductor.playing:
			if player.playing:
				player.stop()
			continue
		var quiet := true
		for i in _slot_tune.size():
			if _slot_tune[i] == tune and (_level[i] > 0.0001 or _target[i] > 0.0):
				quiet = false
				break
		if quiet and not _tune_wanted(tune):
			player.stop()
			t.origin = INF
			continue
		# 现在"听到的"该是这首曲子的第几秒；交给声卡的要再晚一个输出延迟才出声
		var heard := (Conductor.song_beat - float(t.origin)) * spb
		if heard < -0.001 or float(t.length) <= 0.0:
			continue
		if not player.playing:
			player.play(fposmod(heard + AudioServer.get_output_latency() + AudioServer.get_time_to_next_mix() - _tune_bias, float(t.length)))
			t.cal_n = 0
			t.cal_sum = 0.0
			continue
		var at := player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		var err := fposmod(at - heard + float(t.length) * 0.5, float(t.length)) - float(t.length) * 0.5
		if absf(err) > TUNE_RESYNC_SEC:
			t.off = int(t.get("off", 0)) + 1
			if int(t.off) >= 3:      # 连着几帧都偏：重新对一次（只有一帧是播放位置自己跳了一下，不理）
				t.off = 0
				player.seek(fposmod(heard + AudioServer.get_output_latency() + AudioServer.get_time_to_next_mix() - _tune_bias, float(t.length)))
		else:
			t.off = 0
			# 起播后的头半秒量一下偏了多少，修正下一次起播用的数
			var n := int(t.get("cal_n", 99))
			if n < 30:
				t.cal_n = n + 1
				if n >= 6:
					t.cal_sum = float(t.get("cal_sum", 0.0)) + err
				if n == 29:
					_tune_bias = clampf(_tune_bias + float(t.cal_sum) / 24.0 * 0.7, -0.03, 0.05)


## 给谱面 / 关卡用：这首曲子是从第几拍起的（没在放返回 -1）。它的第 1 小节第 1 拍就在这一拍上，
## 所以"曲子里的第 n 拍" = Conductor.song_beat - tune_origin(tune)，对循环的拍数取余就是循环里的位置。
## 曲子名是音乐配置里片段上的 "tune"（比如 "ode"、"mk"、"cc"）。MIDI 在 docs/music_midi/。
func tune_origin(tune: String) -> float:
	return float(_tunes[tune].origin) if _tunes.has(tune) and not is_inf(_tunes[tune].origin) else -1.0


## 现在在放的曲子（名字的列表）
func tunes_playing() -> PackedStringArray:
	var out := PackedStringArray()
	for tune: String in _tunes:
		if not is_inf(_tunes[tune].origin):
			out.append(tune)
	return out


## 这个喵谱子片段从第几拍算起（它那首曲子是从哪条小节线起的；不属于哪首曲子就是 0）
func _pattern_origin(key: String) -> float:
	var tune: String = _pattern_tune.get(key, "")
	if tune == "" or not _tunes.has(tune) or is_inf(_tunes[tune].origin):
		return 0.0
	return float(_tunes[tune].origin)


## 这一大关从头重来（按 R、编辑面板跳阶段）：回到刚读进配置时的样子。不重读文件，只把状态清掉：
## 各条轨道静音、曲子停、档位 / fever / 结尾段 / 排好的切换 / 带过来的满度都清零、还在响的结尾段和过门停掉。
## 接着由 set_section() 排上开头该响的。
func restart() -> void:
	if stream == null:
		return
	_end_fever()
	_set_fever_reverb(false)
	section = -1                    # 让接下来的 set_section(0) 当成新进一个小关
	progress = 0.0
	progress_override = -1.0
	effective = 0.0
	_effective_at_beat = 0.0
	tier = 0
	_carry = 0.0
	_force.clear()
	_now.clear()
	_pending = false
	_outro = false
	_outro_wait = false
	_fill_until = -1.0
	_plan = {}
	_planned_for = -1
	_riser_for = -1
	_fill_done_for = -1
	_fever_fill_done = false
	_quiet_tier_change = true
	_dip_until = -1.0
	for i in _slot_lane.size():
		_target[i] = 0.0
		_level[i] = 0.0
		_slot_stream[i].set_sync_stream_volume(_slot_index[i], SILENT_DB)
	for tune: String in _tunes:
		(_tunes[tune].player as AudioStreamPlayer).stop()
		_tunes[tune].origin = INF
	for key: String in meow.active.keys():
		meow.set_active(key, {})
	for p in _sfx:
		# 只停那些几小节长的（结尾段、专门写的过门）：开场数拍子、上一关收尾和弦的尾巴照常放完
		var playing := p.stream.resource_path.get_file() if p.playing and p.stream != null else ""
		if playing.begins_with("out_") or playing.begins_with("tr_"):
			p.stop()


func clear() -> void:
	_free_tunes()
	_pattern_tune.clear()
	_carry = 0.0
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
	progress_override = -1.0
	var changed := index != section
	# 换小关不从"全开"一下掉到"什么都没有"：上一个小关走的时候有多满，新小关就先带着它的几成进来
	# （过门那一小节之后），再用 CARRY_BARS 小节慢慢落回玩家在新小关里真正的进度。
	# （积累条在换小关的同一帧先清零了，所以看的是这一拍开头记下的值）
	var leaving := maxf(maxf(effective, _carry_level()), _effective_at_beat)
	_end_fever()
	section = index
	progress = 0.0
	effective = 0.0
	_riser_for = -1
	_planned_for = -1
	_plan = {}
	_fill_done_for = -1
	_quiet_tier_change = true
	_carry = 0.0
	if changed and dynamics() and Conductor.playing and Conductor.song_beat > 1.0:
		_carry = leaving * _carry_amount()
		_carry_from = (floorf(Conductor.song_beat / 4.0) + 1.0) * 4.0  # 过门那一小节之后才开始往下落
	_queue()
	# 换小关是在小节线上发生的：这一小节放过门，下一个小节线（上面排好的）新小关的音乐才进来
	if changed and dynamics() and Conductor.playing and Conductor.song_beat > 1.0:
		var spec := change_spec("enter")
		if spec.fill:
			_play_change(spec)
			if spec.written == "":
				play_sfx("crash", -9.0)


## 换小关时带过来的"满的程度"（见 set_section）。只影响各条轨道响哪一段，不算档位、不触发 fever 和升降档的音效。
## 带几成：小关里写 "carry"（0 = 这个小关要从头安静地起，比如故意的反差），不写就用整关的 "carry"，再不写是 CARRY_DEFAULT。
const CARRY_DEFAULT := 0.6
const CARRY_BARS := 8.0
var _carry := 0.0
var _carry_from := 0.0
var _effective_at_beat := 0.0  # 最近一拍开头时有多满

func _carry_amount() -> float:
	var secs: Array = data.get("sections", [])
	var d: Dictionary = secs[section] if section >= 0 and section < secs.size() else {}
	return clampf(float(d.get("carry", data.get("carry", CARRY_DEFAULT))), 0.0, 1.0)


func _carry_level() -> float:
	if _carry <= 0.0 or not Conductor.playing:
		return 0.0
	var t := (Conductor.song_beat - _carry_from) / (CARRY_BARS * 4.0)
	return _carry * clampf(1.0 - t, 0.0, 1.0)


## 小关自己报进度，不看积累条（比如洗衣机那一段：积累条不涨，进度是按完了几次长按）。
## 换小关时自动取消。p < 0 = 取消，回到看积累条。
var progress_override := -1.0

func override_progress(p: float) -> void:
	progress_override = p
	if p >= 0.0 and not is_equal_approx(p, progress):
		set_progress(p)


## 积累条进度变了（0-1），排到下一个边界生效。
## 往上直接跟；往下迟钝：掉到当前档位线以下 DOWN_MARGIN 才退档，不然就停在档位线上。
func set_progress(p: float) -> void:
	if progress_override >= 0.0:
		p = progress_override  # 这个小关自己报进度（见 override_progress）
	progress = clampf(p, 0.0, 1.0)
	if not dynamics() or progress >= effective:
		effective = progress
	else:
		var lines := tier_lines(section)
		var k := tier_of(effective, lines)
		var line: float = lines[k - 1] if k > 0 else 0.0
		effective = progress if k == 0 or progress < line - DOWN_MARGIN else maxf(progress, line)
	_queue()


## ---- 切换：换小关 / 升档 / 进 fever 时音乐怎么换，都用同一种描述，走同一段代码 ----
## 小关里写 "changes": {"enter": {…}, "tier": {"5": {…}}, "fever": {…}}，每一项可以有：
##   "fill"      true / false：先放一小节通用过门（节奏、低音、和声照常，旋律让出一小节，过门轨响）。
##               不写：换小关（enter）和进 fever 要，升档（tier）不要。
##               过门那一小节旋律是停的：曲子不换、只是往上加东西的地方写 false，旋律莫名其妙断一小节很怪。
##   "written"   专门写的过门（assets/audio/sfx 里的一次性音效，tools/music_gen/make_transitions.py 做的）：
##               有它就不放通用的，只留鼓，上一段的和声、低音、旋律都让开，这几小节交给它
##   "db"        专门过门放多响（不写 = ENTER_DB；从正式音轨里切出来的过门文件是压低了存的，在这里抬回去）
##   "bars"      专门过门几小节（不写 = 1）
##   "replaces"  它顶替上一句结尾的几小节（不写：1 小节的过门顶替 1 小节，更长的不顶替、接在那一句唱完之后）。
##               只在写了 "on_bars" 时有用：等的是「过门开头 + 这几小节」落在乐句线上
##   "on_bars"   等正在放的曲子唱到几小节一句的乐句线才换（不写 = 不等）。换曲子 / 换段落的地方用，
##               不然新的一段会从上一句的中间唱起
##   "sfx"       升到这一档那一下的专用音效，代替通用的镲和喵，也不送小 kiai（"none" = 什么都不放）
##   "lead_beats" 最短的预备时间：进度过线到过门开始至少隔这么多拍，离下一条小节线不够就顺延一小节（不写 = 0）。
##               场景要在过门之前先做铺垫的切换用
## 读出来的是补齐了默认值的一份：{fill: 到底放不放过门, written, db, bars, replaces, on_bars, sfx, lead_beats}
const ENTER_DB := -1.0
## 档位线、fever 的两头、各条轨道的切换点在配置里只写到小数点后三位（0.256），而积累条的分数线是整数除出来的
## （110 / 430 = 0.25581）。积累条正好停在分数线上时，进度比写下来的线小一点点，要算过线：不然关卡那边
## 已经触发了这个阶段（拆房子、歇着不出音符），音乐却要等玩家再打中一个才换，一直停在上一段。
## 0.0006 > 四舍五入的最大误差 0.0005，又远小于积累条的一格（满条不到 900 格时一格 > 0.0011）。
const LINE_EPS := 0.0006

func change_spec(kind: String, t := 0) -> Dictionary:
	var out := {"fill": false, "written": "", "db": ENTER_DB, "bars": 1, "replaces": 1, "on_bars": 0, "sfx": "", "lead_beats": 0.0}
	var secs: Array = data.get("sections", [])
	if section < 0 or section >= secs.size():
		return out
	var all: Dictionary = secs[section].get("changes", {})
	var raw: Dictionary = all.get("tier", {}).get(str(t), {}) if kind == "tier" else all.get(kind, {})
	var written := str(raw.get("written", ""))
	if written != "" and ResourceLoader.exists(SFX_DIR + written + ".wav"):
		out.written = written
		out.db = float(raw.get("db", ENTER_DB))
		out.bars = maxi(1, int(raw.get("bars", 1)))
		out.replaces = clampi(int(raw.get("replaces", 1 if out.bars <= 1 else 0)), 0, out.bars)
	out.fill = out.written != "" or (bool(raw.get("fill", kind != "tier")) and _fill_clip() != "")
	out.on_bars = int(raw.get("on_bars", 0))
	out.sfx = str(raw.get("sfx", ""))
	out.lead_beats = float(raw.get("lead_beats", 0.0))
	return out


## 排好了还没发生的那次切换：{kind, id, fill_beat, commit_beat}，没有就是 {}（见 change_planned）
func planned_change() -> Dictionary:
	return _plan


## 进度刚过线、要升到第 up 档（或者进 fever）：算出过门从哪一拍起、新的一段从哪一拍进，发预备信号。
## 写了 "lead_beats" 而离下一条小节线不够远，就顺延一小节（这是这里唯一会改动时间的地方）。
func _plan_change(up: int) -> void:
	var kind := "tier"
	var spec := change_spec("tier", up)
	if not spec.fill and in_fever(effective) and not fever and not _fever_fill_done:
		kind = "fever"
		spec = change_spec("fever")
	var q: float = data.get("quantize_beats", 4)
	var first := _next_beat
	if first - Conductor.song_beat < float(spec.lead_beats):
		first += q
		_next_beat = first
		_fill_until = first
	var fill_beat := first
	if spec.on_bars > 0:
		var shift := q * int(spec.replaces) if spec.fill else 0.0
		for i in 32:
			if _on_phrase_line(fill_beat + shift, spec.on_bars):
				break
			fill_beat += q
	var commit := fill_beat + (q * int(spec.bars) if spec.fill else 0.0)
	_plan = {"kind": kind, "id": up if kind == "tier" else 0, "fill_beat": fill_beat, "commit_beat": commit}
	change_planned.emit(kind, int(_plan.id), fill_beat, commit)


## 现在起放这次切换的过门：专门写的（只留鼓 + 那个一次性音效）或者通用的那一小节
func _play_change(spec: Dictionary) -> void:
	if spec.written != "":
		_play_fill_bar(true)
		play_sfx(spec.written, spec.db)
	else:
		_play_fill_bar()


## 大高潮的混响：小关里写 "fever_reverb": 0.2（湿声的量），进这个小关的 fever 时整个总线慢慢加上一层大厅混响，
## fever 结束、换关时收掉。加在 Master 上，所以打击音效也一起进大厅：要的就是"整体"都更大。
var _reverb: AudioEffectReverb
var _reverb_index := -1
var _reverb_tween: Tween


func _has_limiter() -> bool:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			return true
	return false


func _set_fever_reverb(on: bool) -> void:
	var secs: Array = data.get("sections", [])
	var amount := float(secs[section].get("fever_reverb", 0.0)) if on and section >= 0 and section < secs.size() else 0.0
	if amount <= 0.0 and _reverb == null:
		return
	if _reverb == null:
		_reverb = AudioEffectReverb.new()
		_reverb.room_size = 0.75
		_reverb.damping = 0.35
		_reverb.spread = 1.0
		_reverb.hipass = 0.25
		_reverb.predelay_msec = 40.0
		_reverb.predelay_feedback = 0.0
		_reverb.dry = 1.0
		_reverb.wet = 0.0
		# 放在限幅器前面（限幅器要在最后）
		_reverb_index = 0
		for i in AudioServer.get_bus_effect_count(0):
			if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
				break
			_reverb_index = i + 1
		AudioServer.add_bus_effect(0, _reverb, _reverb_index)
	if _reverb_tween:
		_reverb_tween.kill()
	if amount > 0.0:
		AudioServer.set_bus_effect_enabled(0, _reverb_index, true)
	_reverb_tween = create_tween()
	_reverb_tween.tween_property(_reverb, "wet", amount, 1.2 if amount > 0.0 else 0.6)
	if amount <= 0.0:
		_reverb_tween.tween_callback(AudioServer.set_bus_effect_enabled.bind(0, _reverb_index, false))


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
		if p + LINE_EPS >= r[0] and (p < r[1] or r[1] >= 0.999):
			return true
	return false


func _end_fever() -> void:
	_fever_fill_done = false
	if fever:
		fever = false
		fever_ended.emit()


## 某条轨道里的第一段（没有这条轨道或者它是空的，返回 ""）
## 一关里串了几首曲子时，每个小关可以写明自己用哪一段（小关里的 "own": {"kiai": "cc_kichiku", "hit": ""}，
## "" = 这个小关没有）：升档送的小 kiai、里程碑的 kiai、fever 里自动补上的轨道都按它来，不会拿错成别的曲子的。
func _first_clip(lane_id: String) -> String:
	var secs: Array = data.get("sections", [])
	if section >= 0 and section < secs.size() and secs[section].get("own", {}).has(lane_id):
		return str(secs[section].own[lane_id])
	for lane in data.get("lanes", []):
		if lane.id == lane_id and not lane.get("clips", []).is_empty():
			return lane.clips[0].id
	return ""


## 进度 p 已经过了几条档位线
func tier_of(p: float, lines: PackedFloat32Array) -> int:
	var k := 0
	for line in lines:
		if p + LINE_EPS >= line:
			k += 1
	return k


## 关卡的结尾演出开始（音符停了、玩家没有操作了）时由关卡调：下一条小节线起，除了鼓以外的轨道都停，
## 放这个小关专门写的结尾段（小关里的 "outro": "out_ufo_takes_the_cat"，assets/audio/sfx 里几小节长的一次性音效，
## tools/music_gen/make_outros.py 做的），一直到过关；过关那一下 "exit" 的收束和弦落在它的尾巴上。
## 小关没写 "outro" 就什么都不变。
func outro() -> void:
	if _outro or _outro_wait or _outro_sfx() == "" or not dynamics():
		return
	_outro_wait = true


func _outro_sfx() -> String:
	var secs: Array = data.get("sections", [])
	if section < 0 or section >= secs.size():
		return ""
	var sfx_name := str(secs[section].get("outro", ""))
	return sfx_name if sfx_name != "" and ResourceLoader.exists(SFX_DIR + sfx_name + ".wav") else ""


## 这个小关打完（整关过关）时的收尾音效（"" = 没有，用通用的）
func _exit_sfx() -> String:
	var secs: Array = data.get("sections", [])
	if section < 0 or section >= secs.size():
		return ""
	var sfx_name := str(secs[section].get("exit", ""))
	return sfx_name if sfx_name != "" and ResourceLoader.exists(SFX_DIR + sfx_name + ".wav") else ""


func _fill_clip() -> String:
	for lane in data.get("lanes", []):
		if lane.id == FILL_LANE and not lane.get("clips", []).is_empty():
			return lane.clips[0].id
	return ""


## 现在起放过门：过门轨道响，鼓、低音、和声照旧，别的轨道都停（淡出一拍）。之后由下一次 _apply_now 换成该响的。
## drums_only = 只留鼓（换曲子的变奏过门用：上一首的和声和低音不能再响，通用的过门也不放）
func _play_fill_bar(drums_only := false) -> void:
	var fill := "" if drums_only else _fill_clip()
	for lane in data.get("lanes", []):
		var keep: bool = lane.id == "beat" if drums_only else lane.id in KEEP_IN_FILL
		var c: String = fill if lane.id == FILL_LANE else (_now.get(lane.id, "") if keep else "")
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
	var clip := _first_clip("kiai")
	if clip != "":
		var from := Conductor.song_beat if now else ceilf(Conductor.song_beat / 4.0) * 4.0
		_force["kiai"] = [clip, from + bars * 4.0]
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


## 玩家按下去了，画风突变：八音盒戛然而止，一记镲 + 乐队重音 + glitch 喵，一段倒带正好倒到第一拍（seconds 秒后）
func cozy_snap(seconds := 1.5) -> void:
	if _bridge_fade:
		_bridge_fade.kill()
	_bridge.stop()
	play_sfx("crash", -2.0)
	play_sfx("orch_hit_Bb", -3.0)
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
	# 过关的一声，转场不至于一下子空掉。这个小关有自己的收尾（"exit": "end_g_major"，曲子的调上的一个收束和弦 +
	# 猫的一声 MIAO，tools/music_gen/make_transitions.py 做的）就放它，没有就放通用的
	var ending := _exit_sfx()
	play_sfx(ending if ending != "" else "level_clear", -1.0 if ending != "" else -4.0)
	play_sfx("crash", -8.0)
	_tease_stop(0.0)
	_bridge.stream = load(BRIDGE_LOOP)
	_bridge.volume_db = BRIDGE_DB
	_bridge.play()


## 喘息的时候下一关的声音已经在响了：下一关开头的鼓，加上开头那条和声（没有就低音），循环着放，
## 和等待循环的小节对齐，很快淡进来；等待循环自己让开一点。这样转场不安静，每个接口听起来也是通往不同的地方。
## 要在下一关的音乐配置读进来之后调（main.gd 的 _wait_for_start）。
func bridge_tease() -> void:
	if not bridge_active() or _bridge.stream.resource_path != BRIDGE_LOOP:
		return
	var files: Array[String] = []
	for group in [["beat"], ["bed", "bass"]]:
		for lane_id: String in group:
			var file := _clip_file(lane_id, clip_at(0, lane_id, 0.0))
			if file != "" and ResourceLoader.exists(file):
				files.append(file)
				break
	if files.is_empty():
		return
	var both := AudioStreamSynchronized.new()
	both.stream_count = files.size()
	for i in files.size():
		var wav := (load(files[i]) as AudioStream).duplicate()
		if wav is AudioStreamWAV:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
		both.set_sync_stream(i, wav)
	_tease.stream = both
	_tease.volume_db = -40.0
	var seek := fmod(_bridge.get_playback_position(), 240.0 / bpm())
	_tease.play(seek)
	_tease_t0 = Time.get_ticks_usec() - int(seek * 1000000.0)
	if _tease_fade:
		_tease_fade.kill()
	_tease_fade = create_tween().set_parallel()
	_tease_fade.tween_property(_tease, "volume_db", TEASE_DB, TEASE_FADE)
	_tease_fade.tween_property(_bridge, "volume_db", BRIDGE_UNDER_DB, TEASE_FADE)


func _clip_file(lane_id: String, clip_id: String) -> String:
	for lane in data.get("lanes", []):
		if lane.id == lane_id:
			for c in lane.clips:
				if c.id == clip_id:
					return str(c.get("file", ""))
	return ""


## 离透出来的那段音乐的下一条小节线还有几秒（没在放就是 0）。在小节线上开始数拍子，
## 透出来的鼓就能一直响到下一关的第一拍，和正式的音乐接上，中间不断。
var _tease_t0 := 0

func bridge_seconds_to_bar() -> float:
	if not _tease.playing:
		return 0.0
	var bar := 240.0 / bpm()
	var pos := (Time.get_ticks_usec() - _tease_t0) / 1000000.0
	var left := bar - fmod(pos, bar)
	return 0.0 if left > bar - 0.02 else left


func _tease_stop(seconds: float) -> void:
	if _tease_fade:
		_tease_fade.kill()
	if not _tease.playing:
		return
	if seconds <= 0.0:
		_tease.stop()
		return
	_tease_fade = create_tween()
	_tease_fade.tween_property(_tease, "volume_db", -40.0, seconds)
	_tease_fade.tween_callback(_tease.stop)


## 现在是不是在两关之间等着（过门在响）
func bridge_active() -> bool:
	return _bridge != null and _bridge.playing


## 下一关正式开始（预备拍从现在起，seconds 秒后是第一拍）：数拍子，等待的循环淡出
## on_bar = 是在透出来的那段音乐的小节线上开始的：它就照常响着，最后一拍才收，正好交给正式的音乐
func bridge_go(seconds := 1.5, on_bar := false) -> void:
	if not bridge_active():
		return
	play_sfx("count_in", -1.0, seconds)
	play_sfx("riser_1b", -7.0, seconds)  # 一声上扬的音效，正好在第一拍放完
	if on_bar and _tease.playing:
		if _tease_fade:
			_tease_fade.kill()
		var last := 60.0 / bpm()
		_tease_fade = create_tween()
		_tease_fade.tween_interval(maxf(seconds - last, 0.0))
		_tease_fade.tween_property(_tease, "volume_db", -40.0, last * 0.9)
		_tease_fade.tween_callback(_tease.stop)
	else:
		_tease_stop(minf(seconds, 0.3))
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
		if at <= p + LINE_EPS and at >= best:
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
			_slot_stream[i].set_sync_stream_volume(_slot_index[i], linear_to_db(_level[i]) + db)


func _queue() -> void:
	if stream == null:
		return
	_pending = true
	var q: float = data.get("quantize_beats", 4)
	_next_beat = (floorf(Conductor.song_beat / q) + 1.0) * q if Conductor.playing else 0.0
	if Conductor.playing and _next_beat < _fill_until:
		_next_beat = _fill_until
	# 要升档了：先放一声上扬音效，正好在换的那一拍放完
	if dynamics() and Conductor.playing and not _quiet_tier_change:
		var up := tier_of(effective, tier_lines(section))
		if up > tier and up != _planned_for:
			_planned_for = up
			_plan_change(up)
		var left := (_next_beat - Conductor.song_beat) * Conductor.sec_per_beat()
		if up > tier and up != _riser_for and left > 0.35:
			_riser_for = up
			play_sfx("riser_1b", -8.0, left)


func _on_beat(index: int) -> void:
	_effective_at_beat = effective
	if _outro_wait and index % 4 == 0:
		_outro_wait = false
		_outro = true
		_force.clear()
		play_sfx(_outro_sfx(), ENTER_DB)
		_apply_now(index)
		return
	var expired := false
	for lane_id: String in _force.keys():
		if index >= int(round(_force[lane_id][1])):
			_force.erase(lane_id)
			expired = true
	# 带过来的那几成在往下落：每条小节线重新排一次（落到玩家真正的进度以下就不管了）
	var carrying := _carry > 0.0 and index % 4 == 0 and index >= int(round(_carry_from))
	if carrying and _carry_level() <= effective:
		_carry = 0.0
	if index < int(round(_fill_until)):      # 几小节长的专门过门还没放完：别的事都等它放完那条小节线再办
		if expired or carrying:
			_pending = true
			_next_beat = maxf(_next_beat, _fill_until)
		return
	if expired or carrying or (_pending and index >= int(round(_next_beat))):
		_apply_now(index)


## 第 beat 拍是不是正在放的那首曲子的乐句线（每 bars 小节一句，从这首曲子起播的那条小节线数起）
func _on_phrase_line(beat: float, bars: int) -> bool:
	var origin := 0.0
	for lane_id in ["lead", "kiai", "bed"]:
		var tune := _tune_of(lane_id, str(_now.get(lane_id, "")))
		if tune != "" and _tunes.has(tune) and not is_inf(_tunes[tune].origin):
			origin = float(_tunes[tune].origin)
			break
	return posmod(int(round(beat - origin)), bars * 4) == 0


## 进度 p 所在的那一段 fever 是从哪开始的
func _fever_start(p: float) -> float:
	for r: Array in fever_ranges(section):
		if p >= float(r[0]) and p <= float(r[1]):
			return float(r[0])
	return p


## beat_index >= 0：这是在第几拍的边界上应用的（用来判断是不是乐句线）；-1 = 马上、不管边界
func _apply_now(beat_index := -1) -> void:
	_pending = false
	var base: float = data.get("quantize_beats", 4)
	var use_dynamics := dynamics()
	# 换曲子 / 换段落的切换写了 "on_bars"：只在正在放的曲子的乐句线上换，不然新的一段会从句子中间唱起。
	# 没到乐句线就先按切换前的样子等着（进度当成还差一点没过线）。
	var eff := effective
	var hold := false
	var into_fever := change_spec("fever")
	if use_dynamics and beat_index >= 0 and not fever and in_fever(eff) and not _fever_fill_done:
		# 过门顶替上一句结尾的几小节（"replaces"），所以要是乐句线的是那几小节之后的那条线；没有过门就是这条线本身
		var lands := beat_index + (base * int(into_fever.replaces) if into_fever.fill else 0.0)
		if into_fever.on_bars > 0 and not _on_phrase_line(lands, into_fever.on_bars):
			eff = _fever_start(eff) - 0.002
			hold = true
	if use_dynamics and beat_index >= 0 and not hold:
		var lines := tier_lines(section)
		var up := tier_of(eff, lines)
		for t in range(tier + 1, up + 1):
			var up_spec := change_spec("tier", t)
			var wait := int(up_spec.on_bars)
			# 和进 fever 一样：过门顶替上一句结尾的几小节时，要是乐句线的是那几小节之后的那条线
			var t_lands := beat_index + (base * int(up_spec.replaces) if up_spec.fill else 0.0)
			# （过门已经放过的那一档不再等：过门放完的这条线就是它该进的地方）
			if wait > 0 and t != _fill_done_for and not _on_phrase_line(t_lands, wait):
				eff = lines[t - 1] - 0.002
				hold = true
				break
	# 升到要过门的那一档：这条小节线先放过门，过门放完的那条小节线才真的换
	var going_to := tier_of(eff, tier_lines(section))
	var into_tier := change_spec("tier", going_to)
	if use_dynamics and beat_index >= 0 and going_to > tier and going_to != _fill_done_for and not _outro and into_tier.fill:
		_fill_done_for = going_to
		_play_change(into_tier)
		_pending = true
		_next_beat = beat_index + base * int(into_tier.bars)
		if into_tier.bars > 1:
			_fill_until = _next_beat
		return
	# 要进 fever：一样
	var fever_now := use_dynamics and in_fever(eff)
	if fever_now and not fever and not _fever_fill_done and beat_index >= 0 and into_fever.fill and not _outro:
		_fever_fill_done = true
		_play_change(into_fever)
		_pending = true
		_next_beat = beat_index + base * int(into_fever.bars)
		_fill_until = _next_beat
		return
	# 升档：送一小节小 kiai（fever 里本来就开着，不用送）
	if use_dynamics and beat_index >= 0 and not _quiet_tier_change and going_to > tier and not fever_now \
			and not _force.has("kiai") and _first_clip("kiai") != "" and into_tier.sfx == "":
		_force["kiai"] = [_first_clip("kiai"), float(beat_index) + base]
	for lane in data.get("lanes", []):
		var c := clip_at(section, lane.id, maxf(eff, _carry_level()))
		if fever_now and c == "" and lane.id in FEVER_LANES and not lane.get("clips", []).is_empty():
			c = _first_clip(lane.id)
		if _force.has(lane.id):
			c = _force[lane.id][0]
		if muted.get(lane.id, false) or (_outro and lane.id != "beat"):
			c = ""
		var was: String = _now.get(lane.id, "")
		if was != c:
			# 旋律类的轨道从一段换到另一段：等到乐句线。从没声到有声、或者要静音，不用等。
			var q: float = lane.get("quantize_beats", PHRASE_BEATS if lane.id in PHRASE_LANES else base)
			if use_dynamics and beat_index >= 0 and q > base and was != "" and c != "" \
					and not _force.has(lane.id) and beat_index % int(q) != 0 \
					and _tune_of(lane.id, was) == _tune_of(lane.id, c):  # 换到另一首曲子的片段不等：它是从这条小节线重新起的
				_pending = true
				_next_beat = beat_index + base
				c = was
			else:
				lane_switched.emit(lane.id, c)
		_now[lane.id] = c
	for i in _slot_lane.size():
		_target[i] = 1.0 if _now.get(_slot_lane[i], "") == _slot_clip[i] else 0.0
	_mark_tunes(beat_index)
	for lane in data.get("lanes", []):
		var key := "%s/%s" % [lane.id, _now.get(lane.id, "")]
		meow.set_active(lane.id, _patterns.get(key, {}), float(_lane_gain.get(lane.id, 0.0)), _by_hit.has(key), _pattern_origin(key))
	# 档位变了：升档 = 镲 + 一声上扬的喵，降档 = 一声往下的喵（刚换小关那一次不放）
	var new_tier := tier_of(eff, tier_lines(section))
	if use_dynamics and Conductor.playing and not _quiet_tier_change and beat_index >= 0 and not _outro:
		if new_tier > tier:
			# 这一档有自己的音效（切换描述里的 "sfx"）就放它，不放通用的镲和喵
			var own_sfx := str(change_spec("tier", new_tier).sfx)
			if own_sfx != "":
				play_sfx(own_sfx, -2.0)
			else:
				play_sfx("crash", -9.0)
				play_sfx("catness_up", -6.0)
		elif new_tier < tier:
			play_sfx("catness_down", -6.0)
	if beat_index >= 0:
		_quiet_tier_change = false
	if new_tier != tier:
		tier_changed.emit(new_tier, new_tier > tier)
	if new_tier != tier:
		_planned_for = -1
		_plan = {}
	tier = new_tier
	if hold:
		_pending = true
		_next_beat = beat_index + base
	if fever_now != fever:
		fever = fever_now
		if fever:
			if Conductor.playing and beat_index >= 0:
				play_sfx("crash", -7.0)  # 进 fever 只放一声镲（原来还有一段转圈喵，太突兀，去掉了）
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
	var duck_now := "kichiku" in str(_now.get("kiai", "")) and str(_now.get("lead", "")) != ""
	var duck_changed := duck_now != _duck_on
	_duck_on = duck_now
	_dip_on = dip_now
	for i in _target.size():
		var cur := _level[i]
		var goal := _target[i]
		var dipped := _slot_lane[i] in DIP_LANES
		var ducked := _slot_lane[i] == "lead"
		if cur == goal and not (dip_changed and dipped) and not (duck_changed and ducked):
			continue
		if cur != goal:
			var step := delta / (FADE_IN_SEC if goal > cur else beat_sec)
			cur = minf(goal, cur + step) if goal > cur else maxf(goal, cur - step)
			_level[i] = cur
		var db: float = SILENT_DB if cur <= 0.0001 else linear_to_db(cur) + float(_lane_gain.get(_slot_lane[i], 0.0)) + _slot_gain[i]
		if dip_now and dipped and cur > 0.0001:
			db += DIP_DB
		if duck_now and ducked and cur > 0.0001:
			db += KIAI_DUCK_DB
		_slot_stream[i].set_sync_stream_volume(_slot_index[i], db)
	_run_tunes()
