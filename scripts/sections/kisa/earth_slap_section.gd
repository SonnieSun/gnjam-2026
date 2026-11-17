@tool
extends SpinSection
## 拍地球小关（电视机关卡钻进屏幕之后的玩法）。大关里连着排三段，都用这同一个场景，谱面不同：
##   第 1 段 轻拍：谱面里只有 k / s，每拍轻轻拍一下。拍到积累条第 1 条线，画面下方升起 MEOW 新闻播报条。
##   第 2 段 蓄力拍：每 4 拍一组，前面连点踩镲（h）蓄力，第 3 拍重拍（s）。蓄得越满这一下越重。
##                   新闻条一开始就在；拍到第 1 条线，猫 meme 纸片出场，之后每拍中一次翻转一次。
##   第 3 段 蓄力加密：连点更密，新闻条和纸片一开始就在。打满通关。
## 是第几段看它在大关的小关列表里排在第几个用这个场景的；是不是蓄力段看谱面里有没有 h。
## 判定用框架的 Judge（不改）。蓄力音符只攒力量、不涨积累条（用框架留的 gauge_result 钩子），重拍才涨。
## 美术是 moumou 的拍地球猫（见 EarthSlapStage），3D 画面和参数在 Stage 节点里。编辑器预览里不跑 3D。

## 圆圈提前几拍出现（原来 1.5：160 BPM 下只有半秒多一点，来不及看；2 拍 = 0.75 秒）
@export var approach_beats := 2.0
## 圆圈从多远收过来（占画面高度的比例）。原来 0.3，外圈太小、离判定圈太近；调大之后圈从更外面收进来，
## 配合上面多出来的半拍，收的速度和原来差不多
@export var approach_travel_ratio := 0.45
## 判定圈半径（占画面高度的比例）。下面 ring_fits_earth 关掉时才用这个
@export var ring_radius_ratio := 0.1
## 判定圈和地球一样大（再乘下面这个倍数，1.08 = 比地球大一圈，不挡住地球）
@export var ring_fits_earth := true
@export var ring_earth_scale := 1.08
@export_group("蓄力")
## 蓄力段每几拍一组、重拍在每组的第几拍（谱面里有 s 就按谱面里第一个 s 的位置，这个数只是没有 s 时用）
@export var charge_cycle_beats := 4.0
@export var charge_strike_beat := 2.0
@export var charge_color := Color("8878ff")
@export var charged_color := Color("79dfff")
@export_group("连按")
## 连按不看节奏：连按那一段时间里随便按，没有上限，每一下都有反馈。整段连按算一次判定：
##   按够数（达标）的那一下立刻 Perfect，之后可以接着按；到连按段结束还没达标按比例算 Good / Miss。
## 要按几下、算 Good 的比例、这一段从哪拍数到哪拍、蓄力够不够，都在 Judge 的 rules（JudgeRules）里调。
## 超过达标数之后每多按一下，MAX 那行字大几号（最大到多少号）、颜色沿色环转多少（0.13 ≈ 每下换一种明显不同的颜色）
@export var max_grow_per_press := 4
@export var max_grow_limit := 84
@export_range(0.0, 1.0, 0.01) var max_hue_step := 0.13
## 超过达标数之后每多按一下，满蓄重拍的画面顶动再大多少（最多加到 mash_over_max）
@export var mash_over_punch := 0.1
@export var mash_over_max := 0.6
## 连按有没有尾判。关着（默认）：连按段结束时不出判定——按够数的那一下照常立刻 Perfect，没按够就只是蓄力不满
## （后面那一下重拍轻一点），不算 Good 也不算 Miss、不断连击。开着：段结束时没达标的按 Judge 的 rules 出 Good / Miss。
@export var mash_tail_judge := false
## 提示文字（快到连按段时显示 / 蓄满时显示）和提示的按键名
@export var mash_text := "MASH!"
@export var max_text := "MAX!"
@export var mash_key_text := "SPACE"
## 连按唱鬼畜：每按一下，猫唱出现在这首曲子的下一个音（按多快唱多快，硬切），每一串连按接着唱下一小节、换一只猫；
## 超过达标数之后每多按一下整体再升 mash_sing_lift 个半音。关掉 = 用下面那个一下比一下高的声音
@export var mash_sings := true
## 现在响的和声是哪首曲子（片段名的开头）就唱哪首的谱子（levels/music/patterns/ 里的名字）；都对不上用 mash_sing_default
@export var mash_sing_tunes := {"mk_": "mountain_king", "mka_": "mountain_king", "cc_": "can_can", "ybf": "your_best_friend"}
@export var mash_sing_default := "kichiku_riff"
@export_range(-30.0, 6.0) var mash_sing_db := -3.0
@export var mash_sing_lift := 1.0
## 每按一下的声音，一下比一下高几个半音；蓄满时的一声
@export var charge_sound: AudioStream = preload("res://assets/audio/sfx/hit_meow_good_a.wav")
@export var charge_pitch_step := 2.0
@export_range(-30.0, 6.0) var charge_sound_db := -6.0
@export var max_sound: AudioStream = preload("res://assets/audio/sfx/clap.wav")
@export_range(-30.0, 6.0) var max_sound_db := -4.0
@export_group("重拍")
## 蓄满力的重拍：画面顶多大（1 = 一次 Perfect 那么大）、白闪多亮、再响哪个音效（assets/audio/sfx 里的名字，留空不响）
@export var power_punch := 2.5
@export_range(0.0, 1.0) var power_flash := 0.35
@export var power_sound := "orch_hit_Bb"
@export_range(-30.0, 6.0) var power_sound_db := -6.0
## 蓄力不够的重拍：音乐压低几拍（0 = 不压），舞台那边只软绵绵地晃一下
@export var low_charge_dip_beats := 1.0
@export_group("新闻条")
## 新闻条高度（像素）和滚动速度（像素 / 秒）
@export var news_height := 54.0
@export var news_speed := 160.0
## 新闻条左边的台标和滚动的文字
@export var news_label := "MEOW NEWS"
@export var news_text := "MEOW MEOW MEOW!  MEOOOW MEOW.  MEOW?  MEOW MEOW MEOW MEOW...  MEEEOW!!  "
@export_group("")
## 没打中时整个画面红闪的强度
@export_range(0.0, 1.0) var miss_flash := 0.2
## 切到下一段时用几秒叠化盖住框架的白闪
@export var crossfade_seconds := 0.25
## 调试用：自动按键（看演出用，正式玩要关掉）
@export var autoplay := false

var _stage: EarthSlapStage
var _phase := 0  # 第几段（0 起）
var _charge_mode := false
var _charge_target := 1
var _charge := 0
var _last_power := 0.0
var _slap_text := ""
var _slap_text_age := 99.0
var _news := 0.0  # 新闻条升起来多少（0~1）
var _news_on := false
var _scroll := 0.0
var _flash := 0.0
var _auto_next := 0
var _auto_release := false
var _strike_beat := 2.0  # 这一段的重拍在每组的第几拍（见 _on_enter）
var _zones: Array[Dictionary] = []  # 连按段：{start, end 在鼓谱一遍里的拍数, beats 那一串 h 各在第几拍, need 要按几下}
var _pattern_len := 0.0
var _pattern_origin := INF
var _zone_id := -1       # 现在算的是第几个连按段（鼓谱第几遍 × 段数 + 第几段），换了就把蓄力清零
var _zone := {}          # 正在按 / 刚按完还没出结果的那一段
var _zone_judged := true # 这一段出过判定了没有
var _maxed := false
var _over_at_slap := 0
var _pop := 0.0          # 刚按了一下：蓄力圈胀一下
var _max_flash := 0.0
var _free_i := 0
var _players: Array[AudioStreamPlayer] = []
var _player_next := 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_stage = get_node_or_null("Stage") as EarthSlapStage
	if _stage == null:
		_stage = EarthSlapStage.new()
		add_child(_stage)
	_stage.setup(self)


func _on_enter() -> void:
	if def == null or _stage == null:
		return
	# 第几段：前面有几个小关也用这个场景
	_phase = 0
	var sections: Array = Conductor.chart.sections if Conductor.chart else []
	for s: SectionDef in sections:
		if s == def:
			break
		if s.scene == def.scene:
			_phase += 1
	# 蓄力段：谱面里有踩镲。每组要连点几下 = 一小节里 h 的个数
	_charge_target = 0
	for bar in def.bars:
		_charge_target = maxi(_charge_target, bar.count("h"))
	_charge_mode = _charge_target > 0
	_charge_target = maxi(_charge_target, 1)
	_build_zones()
	# 重拍在每组的第几拍：谱面里第一个 s 在哪就是哪（没有 s 就用 charge_strike_beat），挥爪的动画按它对
	_strike_beat = charge_strike_beat
	for d: Dictionary in def.parse_notes(Conductor.chart.beats_per_bar):
		if int(d.sound) == NoteData.Sound.SNARE:
			_strike_beat = fposmod(float(d.beat), charge_cycle_beats)
			break
	_news_on = _phase >= 1
	if _news_on:
		_news = 1.0
	if _phase >= 2:
		_stage.show_memes()


func _on_exit() -> void:
	# 下一段还是拍地球：把最后一帧留在最上面很快淡掉，盖住框架切关时的白闪
	var sections: Array = Conductor.chart.sections if Conductor.chart else []
	var i := sections.find(def)
	if i >= 0 and i + 1 < sections.size() and (sections[i + 1] as SectionDef).scene == def.scene:
		_leave_crossfade()


func hit_position(_note: NoteData = null) -> Vector2:
	return _stage.focus_screen_pos() if _stage else Vector2.ZERO


func hit_radius() -> float:
	if ring_fits_earth and _stage:
		return _stage.earth_screen_radius() * ring_earth_scale
	return ring_radius_ratio * screen_size().y


# ---------------- 连按 ----------------

## 从谱面里找出连按段：挨着的一串 h（相邻不超过 1 拍）算一段
func _build_zones() -> void:
	_zones = []
	_zone_id = -1
	_zone = {}
	_zone_judged = true
	_pattern_origin = INF
	_free_i = 0
	if not _charge_mode:
		return
	var bpb: int = Conductor.chart.beats_per_bar
	_pattern_len = def.length_beats(bpb)
	var list := def.parse_notes(bpb)
	var run: Array[float] = []
	for i in list.size() + 1:
		var is_h: bool = i < list.size() and int(list[i].sound) == NoteData.Sound.HAT
		if is_h and (run.is_empty() or float(list[i].beat) - run[-1] <= 1.0):
			run.append(float(list[i].beat))
			continue
		if not run.is_empty():
			# 这一串后面第一个真正要判的音符：连按段要在它之前收住
			var next_beat := float(list[i].beat) if i < list.size() else _pattern_len + float(list[0].beat)
			var span := _rules().mash_zone(run[0], run[-1], next_beat)
			_zones.append({
				"start": span.x,
				"end": span.y,
				"beats": run.duplicate(),
				"need": _rules().mash_count_need(run.size()),
			})
			run = []
		if is_h:
			run.append(float(list[i].beat))


## 这一关的结束（框架的 _plan_ending，见 main.gd）：积累条满了之后下一条乐句线上来一个七彩的大长按，按满这么多拍，
## 按完的那一拍拍下去（结束音符），然后进过渡。大长按期间蓄力条跟着涨到满，所以最后那一下一定是满蓄的 POWER SLAP。
const ENDING_HOLD_BEATS := 8.0
## 大长按从第几拍起（框架给；INF = 还没到结束）。从这里起不再有连按段。
var ending_from := INF


## 离现在最近的还没结束的连按段：{id, start, end（全曲拍数）, beats, need}；没有连按段返回空
func _zone_now() -> Dictionary:
	if _zones.is_empty() or _pattern_len <= 0.0:
		return {}
	if song_beat() >= ending_from - approach_beats:
		return _ending_zone()
	if is_inf(_pattern_origin):
		if notes.is_empty():
			return {}
		_pattern_origin = notes[0].beat - float(def.parse_notes(Conductor.chart.beats_per_bar)[0].beat)
	var now := song_beat()
	var lap := maxi(floori((now - _pattern_origin) / _pattern_len), 0)
	for l in [lap, lap + 1]:
		for i in _zones.size():
			var z := _zones[i]
			var base: float = _pattern_origin + l * _pattern_len
			if base + float(z.start) >= ending_from - 0.5:
				return _ending_zone()  # 结束的大长按之后没有连按段了：下一段就是它
			if now <= base + float(z.end):
				return {"id": l * _zones.size() + i, "start": base + float(z.start), "end": base + float(z.end),
						"base": base, "beats": z.beats, "need": z.need}
	return {}


## 结束的大长按当成一段特别长的连按段来画：紫色的色带从外圈收进来、判定圈上的蓄力弧、大字，都和连按一样
func _ending_zone() -> Dictionary:
	if song_beat() > ending_from + ENDING_HOLD_BEATS:
		return {}
	var beats: Array = []
	for i in int(ENDING_HOLD_BEATS):
		beats.append(float(i))
	return {"id": 1000000, "start": ending_from, "end": ending_from + ENDING_HOLD_BEATS, "base": ending_from,
			"beats": beats, "need": int(ENDING_HOLD_BEATS)}


## 现在是不是在连按段里
func _mashing(zone: Dictionary) -> bool:
	return not zone.is_empty() and song_beat() >= float(zone.start)


## 连按段里按了一下（不看准不准）
func _on_empty_hit() -> void:
	var zone := _zone_now()
	if not _charge_mode or not _mashing(zone) or int(zone.id) != _zone_id:
		return
	_charge += 1  # 没有上限：达标之后接着按，每一下照样有反馈
	_pop = 1.0
	# 连按唱鬼畜（没唱成，比如没有谱子，就用原来的声音：一下比一下高，最高到两个八度）
	if not (mash_sings and Music.meow.sing_step(_mash_tune(), _charge - 1, _zone_id, mash_sing_db,
			maxf(_charge - _charge_target, 0.0) * mash_sing_lift)):
		_play(charge_sound, charge_sound_db, pow(2.0, minf((_charge - 1) * charge_pitch_step, 24.0) / 12.0))
	if _charge == _charge_target:
		# 达标的这一下：立刻 Perfect
		_maxed = true
		_max_flash = 1.0
		_play(max_sound, max_sound_db)
		_judge_zone(NoteData.Result.PERFECT)
	elif _charge > _charge_target:
		_max_flash = maxf(_max_flash, 0.6)  # 多按的每一下再炸一小圈


## 连按唱哪首：看现在响的是哪首曲子的和声
var _tune_cache := {}

func _mash_tune() -> Dictionary:
	var clip: String = Music.playing_clip("bed")
	var tune_name := mash_sing_default
	for prefix: String in mash_sing_tunes:
		if clip.begins_with(prefix):
			tune_name = mash_sing_tunes[prefix]
	if not _tune_cache.has(tune_name):
		var path := "res://levels/music/patterns/%s.json" % tune_name
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_tune_cache[tune_name] = d if d is Dictionary else {}
	return _tune_cache[tune_name]


## 这一段连按出结果：找这一段里最后一个连按音符当“代表”，交给 Judge 照常计分、算连击、弹判定文字
func _judge_zone(result: int) -> void:
	if _zone_judged or _zone.is_empty():
		return
	_zone_judged = true
	var j := main_judge()
	var beats: Array = _zone.beats
	if j == null or beats.is_empty():
		return
	var at: float = float(_zone.base) + float(beats[-1])
	for n in notes:
		if n.free and absf(n.beat - at) < 0.01:
			j.judge_free(n, result)
			break
	if result == NoteData.Result.MISS:
		_flash = 1.0


func _play(stream: AudioStream, db: float, pitch := 1.0) -> void:
	if stream == null or _players.is_empty():
		return
	var p := _players[_player_next]
	_player_next = (_player_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func is_charge_note(note: NoteData) -> bool:
	return _charge_mode and note != null and note.sound == NoteData.Sound.HAT


## 判定规则：游戏里用 Judge 那份；编辑器预览没有 Judge，用默认值
func _rules() -> JudgeRules:
	var j := main_judge()
	return j.rules if j else JudgeRules.new()


## 蓄了多少（达标 = 1，超过了也只算 1）
func charge_ratio() -> float:
	return clampf(float(_charge) / _charge_target, 0.0, 1.0)


## 超过达标数多按了几下
func charge_over() -> int:
	return maxi(_charge - _charge_target, 0)


## 框架在算积累条之前问一下：蓄力音符不动积累条；重拍蓄力不够只按 Good 算
func gauge_result(note: NoteData, result: int) -> int:
	if is_charge_note(note):
		return NoteData.Result.NONE
	return _rules().charged_result(result, charge_ratio()) if _charge_mode else result


## 蓄力连点不放大范围的命中特效，只有拍地球那一下放
func wants_hit_effects(note: NoteData) -> bool:
	return not is_charge_note(note)


func _update_spin(local: float, _angle: float) -> void:
	center_on_screen()
	if _stage == null:
		return
	var dt := get_process_delta_time()
	if autoplay:
		_autoplay()
	if _charge_mode:
		# 连按的音符交给 Judge 当“不判定的音符”：不算 Miss、不计分，只吃掉那一下按键
		while _free_i < notes.size():
			if notes[_free_i].sound == NoteData.Sound.HAT:
				notes[_free_i].free = true
			_free_i += 1
		var zone := _zone_now()
		if not zone.is_empty() and int(zone.id) != _zone_id and _mashing(zone):
			# 新的一段连按开始：从 0 蓄起
			_zone_id = zone.id
			_zone = zone
			_zone_judged = false
			_charge = 0
			_maxed = false
			_charge_target = zone.need
		if not _zone_judged and song_beat() > float(_zone.end):
			# 连按段结束了还没达标。没有尾判：不出判定。有尾判：按比例算 Good / Miss
			if mash_tail_judge:
				_judge_zone(_rules().mash_count_result(_charge, _charge_target))
			else:
				_zone_judged = true
		if song_beat() >= ending_from:
			# 结束的大长按：蓄力跟着按住的进度涨到满
			_charge = maxi(_charge, roundi(clampf((song_beat() - ending_from) / ENDING_HOLD_BEATS, 0.0, 1.0) * _charge_target))
			_maxed = _charge >= _charge_target
		_stage.set_charge(charge_ratio() + minf(charge_over() * 0.1, 0.5))
		_pop = maxf(_pop - dt * 9.0, 0.0)
		_max_flash = maxf(_max_flash - dt * 2.5, 0.0)
	if _charge_mode:
		_stage.update(dt, local, charge_cycle_beats, _strike_beat)
	else:
		_stage.update(dt, local, 1.0, 0.0)
	_news = move_toward(_news, 1.0 if _news_on else 0.0, dt * 2.5)
	_scroll += news_speed * dt
	_flash = maxf(_flash - dt * 2.5, 0.0)
	_slap_text_age += dt
	queue_redraw()


func _on_note_judged(note: NoteData, result: int) -> void:
	if _stage == null:
		return
	var hit := result != NoteData.Result.MISS
	if is_charge_note(note):
		return  # 连按的音符不判定（见 NoteData.free），蓄力在 _on_empty_hit 里数
	if not hit:
		_stage.miss()
		_flash = 1.0
		if _charge_mode:
			_slap_text = "MISS"
			_slap_text_age = 0.0
			_charge = 0
			_maxed = false
		return
	if absf(note.beat - (ending_from + ENDING_HOLD_BEATS)) < 0.01:
		# 最后那一下拍下去：白闪，fever 到此为止
		var m := get_parent().get_parent() if get_parent() else null
		if m and m.get("hud"):
			m.hud.flash(Color.WHITE, 0.9, 0.3)
		Music.end_fever()
	_last_power = charge_ratio() if _charge_mode else 0.0
	_over_at_slap = charge_over()
	var low := _charge_mode and _last_power < _rules().charge_min_ratio
	_stage.slap(_last_power, low)
	if _charge_mode:
		_slap_text = "POWER SLAP!" if _last_power >= 0.99 else ("LOW CHARGE" if low else "SLAP!")
		_slap_text_age = 0.0
		_charge = 0
		_maxed = false
		if _last_power >= 0.99:
			_power_impact(_over_at_slap)
		elif low and low_charge_dip_beats > 0.0:
			Music.dip(low_charge_dip_beats)


## 蓄满力的重拍：画面顶一大下 + 白闪 + 一声重音（用主场景里现成的 ScreenFx / HUD）
func _power_impact(over: int = 0) -> void:
	var main := get_parent().get_parent() if get_parent() else null
	if main and main.get("screen_fx"):
		main.screen_fx.punch(power_punch * (1.0 + minf(over * mash_over_punch, mash_over_max)))
	if main and main.get("hud") and power_flash > 0.0:
		main.hud.flash(Color.WHITE, power_flash, 0.2)
	if power_sound != "":
		Music.play_sfx(power_sound, power_sound_db)


func _on_gauge_event(index: int, _value: int) -> void:
	if index < 1:
		return
	if _phase == 0:
		_news_on = true
	elif _stage:
		_stage.show_memes()


func _draw() -> void:
	if def == null:
		return
	var size := screen_size()
	if Engine.is_editor_hint():
		draw_string(ThemeDB.fallback_font, Vector2(-300.0, 0.0), "拍地球小关：3D 画面不在编辑器里预览",
				HORIZONTAL_ALIGNMENT_CENTER, 600.0, 20)
		return
	if _stage == null:
		return
	var center := hit_position()
	var radius := hit_radius()
	var charged := charge_ratio() >= _rules().charge_min_ratio
	var travel := approach_travel_ratio * size.y
	# 和第 1 关一样：判定点外面压暗、判定圈预亮、空拍补虚线（音符本身就是缩圈，不再叠实线）
	draw_focus(self, center, radius)
	draw_lit_target(self, center, radius, Color(1, 1, 1, 0.9))
	draw_target_guides(self, center, radius, travel, approach_beats, Callable(), 1.0, 1.0, false)
	for n in own_notes():
		if n.judged:
			continue
		var ahead := beats_until(n)
		if ahead > approach_beats:
			break
		var k := clampf(ahead / approach_beats, 0.0, 1.0)
		var r := radius + k * travel
		if is_charge_note(n):
			continue  # 连按不画成一个个圈，画成一整条色带（见 _draw_mash）
		else:
			draw_approach_ring(self, center, r, approach_ring_look(k, sound_color(n), 0.5,
					10.0 if _charge_mode else 8.0, 16.0 if _charge_mode else 14.0))
	if _charge_mode:
		_draw_mash(center, radius, travel)
	if song_beat() >= ending_from - approach_beats and song_beat() < ending_from + ENDING_HOLD_BEATS + 0.25:
		# 结束的大长按：判定圈外面一大圈七彩的进度
		var ep := clampf((song_beat() - ending_from) / ENDING_HOLD_BEATS, 0.0, 1.0)
		var hue := fposmod(Time.get_ticks_msec() * 0.0006, 1.0)
		var pulse := 1.0 + 0.04 * pow(1.0 - fposmod(song_beat(), 1.0), 2.0)
		draw_arc(center, radius * 1.22 * pulse, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.25), 10.0)
		if ep > 0.0:
			draw_arc(center, radius * 1.22 * pulse, -PI / 2.0, -PI / 2.0 + TAU * ep, 96, Color.from_hsv(hue, 0.65, 1.0), 18.0)
			draw_arc(center, radius * 1.22 * pulse, -PI / 2.0, -PI / 2.0 + TAU * ep, 96, Color.from_hsv(hue, 0.3, 1.0, 0.35), 34.0)
	if tap_age < 0.15:
		draw_arc(center, radius * (1.0 + tap_age), 0.0, TAU, 64, Color(1, 1, 1, 1.0 - tap_age / 0.15), 6.0)
	if _news > 0.0:
		_draw_news(size)
	if _flash > 0.0:
		draw_rect(Rect2(-size / 2.0, size), Color(1.0, 0.15, 0.2, _flash * miss_flash))


## 连按：收过来的一整条色带（里面的细线 = 谱面上那几下）+ 判定圈上的蓄力弧 + 大字提示和闪动的按键
func _draw_mash(center: Vector2, radius: float, travel: float) -> void:
	var font := ThemeDB.fallback_font
	var now := song_beat()
	var zone := _zone_now()
	var active := _mashing(zone)
	var coming := false
	if not zone.is_empty():
		var a0 := (float(zone.start) - now) / maxf(approach_beats, 0.01)
		var a1 := (float(zone.end) - now) / maxf(approach_beats, 0.01)
		coming = a0 <= 1.0
		if coming:
			var inner := radius + clampf(a0, 0.0, 1.0) * travel
			var outer := radius + clampf(a1, 0.0, 1.0) * travel
			if outer > inner + 0.5:
				draw_arc(center, (inner + outer) / 2.0, 0.0, TAU, 96, Color(charge_color, 0.34 if active else 0.24), outer - inner)
				draw_arc(center, outer, 0.0, TAU, 96, Color(charge_color, 0.9), 3.0)
				if a0 > 0.0:
					draw_arc(center, inner, 0.0, TAU, 96, Color(charge_color.lerp(Color.WHITE, 0.4), 0.95), 4.0)
			for b: float in zone.beats:
				var k := (float(zone.base) + b - now) / maxf(approach_beats, 0.01)
				if k > 0.0 and k <= 1.0:
					draw_arc(center, radius + k * travel, 0.0, TAU, 96, Color(1, 1, 1, 0.3), 1.5)
	# 判定圈：连按的时候换成蓄力色、轻轻抖；蓄了多少画成圈上的一段粗弧，每按一下胀一下
	var ratio := charge_ratio()
	if active or _charge > 0:
		var shake := sin(Time.get_ticks_msec() * 0.06) * (2.0 + 3.0 * ratio)
		draw_arc(center, radius + shake, 0.0, TAU, 96, Color(charge_color, 0.55), 5.0)
		if _charge > 0:
			var fill := charged_color if _maxed else charge_color.lerp(charged_color, ratio * 0.7)
			draw_arc(center, radius + shake, -PI / 2.0, -PI / 2.0 + TAU * ratio, 96, Color(fill, 0.35), 26.0 + 14.0 * _pop)
			draw_arc(center, radius + shake, -PI / 2.0, -PI / 2.0 + TAU * ratio, 96, fill, 12.0 + 8.0 * _pop)
	if _max_flash > 0.0:
		draw_arc(center, radius * (1.0 + 0.6 * (1.0 - _max_flash)), 0.0, TAU, 96, Color(1, 1, 1, _max_flash), 4.0 + 10.0 * _max_flash)
	# 大字：重拍的结果 / MAX / MASH + 数字；下面一个一闪一闪的按键
	var label := ""
	var col := Color(1, 1, 1)
	var fs := 34
	if _slap_text_age < 0.8:
		label = _slap_text
		col = Color(1.0, 0.9, 0.3) if _slap_text != "MISS" and _slap_text != "LOW CHARGE" else Color(1.0, 0.5, 0.5)
		fs = 40 if _slap_text == "POWER SLAP!" else 30
	elif _maxed:
		label = "%s  %d / %d" % [max_text, _charge, _charge_target] if _charge > _charge_target else max_text
		col = charged_color.lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03))
		fs = 44
		var over := charge_over()
		if over > 0:
			# 每多按一下：字再大一号（到上限为止），颜色换一种（沿色环转一格），按下的瞬间再额外胀一下
			fs = mini(44 + over * max_grow_per_press, max_grow_limit) + int(10.0 * _pop)
			col = Color.from_hsv(fposmod(charged_color.h + over * max_hue_step, 1.0), 0.75, 1.0).lerp(Color.WHITE, 0.35 * _pop)
	elif active and int(zone.get("id", -1)) == 1000000:
		label = "HOLD!  %d / %d" % [_charge, _charge_target]
		col = Color.from_hsv(fposmod(Time.get_ticks_msec() * 0.0006, 1.0), 0.5, 1.0)
		fs = 40 + int(8.0 * _pop)
	elif active:
		label = "%s  %d / %d" % [mash_text, _charge, _charge_target]
		col = charge_color.lerp(Color.WHITE, 0.55)
		fs = 36 + int(8.0 * _pop)
	elif coming:
		label = mash_text
		col = Color(charge_color.lerp(Color.WHITE, 0.55), 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.012)))
	if label == "":
		return
	var pos := center + Vector2(-320.0, -radius - 44.0)
	draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 640, fs, 8, Color(0.02, 0.02, 0.06, 0.95))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 640, fs, col)
	if (coming or active) and _slap_text_age >= 0.8 and mash_key_text != "":
		# 按键提示：一上一下地快速闪，告诉玩家“一直按”
		var down := int(Time.get_ticks_msec() / 70.0) % 2 == 0
		var key := Rect2(center + Vector2(-52.0, -radius - 34.0 + (3.0 if down else 0.0)), Vector2(104.0, 26.0))
		draw_rect(Rect2(key.position + Vector2(0.0, 4.0), key.size), Color(0.02, 0.02, 0.06, 0.9))
		draw_rect(key, Color(1, 1, 1, 0.95) if down else Color(charge_color.lerp(Color.WHITE, 0.3), 0.95))
		draw_string(font, key.position + Vector2(0.0, 19.0), mash_key_text, HORIZONTAL_ALIGNMENT_CENTER, key.size.x, 16, Color(0.05, 0.05, 0.15))


## 画面下方的新闻播报条：左边台标，右边一行字从右往左滚
func _draw_news(size: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var top := size.y / 2.0 - news_height * _news
	var left := -size.x / 2.0
	draw_rect(Rect2(left, top, size.x, news_height), Color(0.08, 0.1, 0.35, 0.95))
	draw_rect(Rect2(left, top, size.x, 4.0), Color(1.0, 0.85, 0.2))
	var fs := int(news_height * 0.5)
	var text_w := maxf(font.get_string_size(news_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, 1.0)
	var x := left - fposmod(_scroll, text_w)
	var y := top + news_height * 0.68
	while x < size.x / 2.0:
		draw_string(font, Vector2(x, y), news_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
		x += text_w
	var label_w := font.get_string_size(news_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 28.0
	draw_rect(Rect2(left, top, label_w, news_height), Color(0.85, 0.12, 0.2))
	draw_string(font, Vector2(left + 14.0, y), news_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))


func _leave_crossfade() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(img)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	get_tree().root.add_child(layer)
	var t := layer.create_tween()
	t.tween_property(rect, "modulate:a", 0.0, crossfade_seconds)
	t.tween_callback(layer.queue_free)


# ---------------- 调试：自动按键 ----------------

func _autoplay() -> void:
	if _auto_release:
		_send_hit(false)
		_auto_release = false
	while _auto_next < notes.size() and notes[_auto_next].judged:
		_auto_next += 1
	if _auto_next < notes.size() and beats_until(notes[_auto_next]) <= 0.0:
		_auto_next += 1
		_send_hit(true)
		_auto_release = true


func _send_hit(pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = Judge.HIT_ACTION
	e.pressed = pressed
	Input.parse_input_event(e)


## 计分用（见 main.gd 的 _compute_stage_weights）：踩镲（h）只蓄力不涨积累条，只有 k / s 涨条
const SCORE_GAUGE_SOUNDS := "ksx"
