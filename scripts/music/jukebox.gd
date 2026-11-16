extends VBoxContainer
## 曲库（嵌在 scenes/tools/jukebox.tscn 里，见 jukebox_scene.gd）。把现在做好的曲子列出来，点一首就放（它的几条音轨一起循环），
## 右边的按钮开关每条音轨；下面是所有一次性音效（喵、打中喵、SFX），点一下听一声。
## 只是用来听的，不改任何配置；自己一个播放器，不用 Conductor。
## 加了新曲子 / 新音轨：在 _songs() 里加一行。

const M := "res://assets/audio/music/"
const S1 := M + "scene1/"
const ONE_SHOT_DIRS := ["res://assets/audio/sfx/", "res://assets/audio/meows/"]
const BPM := 160.0
const SILENT_DB := -80.0

var _player: AudioStreamPlayer
var _shot: AudioStreamPlayer
var _stream: AudioStreamSynchronized
var _songs_list: Array = []
var _song := -1
var _song_buttons: Array[Button] = []
var _stems_box: HFlowContainer
var _now: Label
var _lcd: Label
var _patterns_box: HFlowContainer
var _pattern_on := {}                 # 正在跟着放的喵谱子：路径 -> true

## 精简模式（喵谱子工作室里当伴奏用）：只有"这首曲子的音轨"那一排开关，曲子由外面选（play_song）。
## 要在加进场景树之前设好。
var compact := false


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_shot = AudioStreamPlayer.new()
	_shot.max_polyphony = 4
	add_child(_shot)
	_songs_list = _songs()
	if compact:
		_now = Label.new()
		_lcd = Label.new()
		_stems_box = HFlowContainer.new()
		add_child(_stems_box)
		return

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	_now = Label.new()
	_now.theme_type_variation = "Header"
	_now.text = "点一首曲子开始放"
	_now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_now)
	_lcd = Label.new()
	_lcd.theme_type_variation = "Lcd"
	_lcd.custom_minimum_size.x = 150
	_lcd.text = "STOPPED"
	head.add_child(_lcd)
	var stop := Button.new()
	stop.text = "STOP"
	stop.theme_type_variation = "Big"
	stop.focus_mode = Control.FOCUS_NONE
	stop.pressed.connect(stop_all)
	head.add_child(stop)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)

	_title(body, "曲子（点了就放，再点一首就换）")
	var songs := HFlowContainer.new()
	body.add_child(songs)
	for i in _songs_list.size():
		var b := Button.new()
		b.text = _songs_list[i].name
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(play_song.bind(i))
		songs.add_child(b)
		_song_buttons.append(b)

	_title(body, "这首曲子的音轨（亮着 = 在响，点一下开 / 关）")
	_stems_box = HFlowContainer.new()
	body.add_child(_stems_box)

	_title(body, "喵谱子（游戏里按格子触发的猫鼓 / 鬼畜猫旋律，可以改）：点名字 = 跟着曲子一起放，✎ = 打开编辑")
	_patterns_box = HFlowContainer.new()
	body.add_child(_patterns_box)
	_fill_patterns()

	_title(body, "一次性音效（点一下听一声）")
	var shots := HFlowContainer.new()
	body.add_child(shots)
	for dir in ONE_SHOT_DIRS:
		for f in DirAccess.get_files_at(dir):
			if f.get_extension() != "wav":
				continue
			var b := Button.new()
			b.text = f.get_basename()
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_play_shot.bind(dir + f))
			shots.add_child(b)


func _title(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Hint"
	parent.add_child(l)


# ---------------------------------------------------------------- the songs

## 一条音轨：[按钮上的名字, 文件, 一开始开不开]
func _t(label: String, path: String, on := true) -> Array:
	return [label, path, on]


func _style(name: String, folder: String, prefix: String) -> Dictionary:
	return {"name": name, "stems": [
		_t("鼓", S1 + "skeleton/s1_L1_groove_4b.wav"), _t("低音", S1 + "skeleton/s1_L2_bass_4b.wav"),
		_t("和声", "%s%s/s1_%s_L0_keys_4b.wav" % [S1, folder, prefix]),
		_t("旋律", "%s%s/s1_%s_L3_hook_4b.wav" % [S1, folder, prefix]),
		_t("高潮", "%s%s/s1_%s_L4_peak_4b.wav" % [S1, folder, prefix]),
		_t("猫鼓", S1 + "cat_band/s1_C_drums_4b.wav", false),
		_t("事件：喵", S1 + "events/s1_X_meow_4b.wav", false),
		_t("事件：海豹", S1 + "events/s1_X_seal_4b.wav", false),
		_t("事件：人声", S1 + "events/s1_X_vox_4b.wav", false)]}


func _rhythm(name: String, key: String) -> Dictionary:
	return {"name": name, "stems": [
		_t("鼓", "%srhythm_variants/s1_R%s_L1_groove_4b.wav" % [S1, key]),
		_t("低音", "%srhythm_variants/s1_R%s_L2_bass_4b.wav" % [S1, key]),
		_t("和声", S1 + "style_futurebass/s1_fb_L0_keys_4b.wav"),
		_t("旋律", S1 + "style_futurebass/s1_fb_L3_hook_4b.wav"),
		_t("猫旋律", S1 + "cat_band/s1_C_lead_flow_4b.wav", false)]}


## 经典曲：version 0 = 普通版，1 = 猫版（喵连着唱旋律），2 = 鬼畜版（每 4 小节一只猫，变速变调，硬切）。
## 三个版本是同样的音轨，只是一开始开的不一样。
func _classic(name: String, key: String, bars: int, version: int) -> Dictionary:
	var p := "%sclassics/%s/%s_" % [M, key, key]
	var e := "_%db.wav" % bars
	var cat := version > 0
	# 猫版 / 鬼畜版 = 原来的伴奏 + 猫鼓 + 猫唱旋律；猫和声、猫低音默认关着，想听自己点开
	return {"name": name + ["", "（猫版）", "（鬼畜版）"][version], "stems": [
		_t("鼓", S1 + "skeleton/s1_L1_groove_4b.wav"),
		_t("和声", p + "fb_L0_keys" + e), _t("低音", p + "L2_bass" + e),
		_t("旋律", p + "L3_pluck" + e, not cat), _t("高潮", p + "fb_L4_peak" + e),
		_t("猫旋律", p + "L3_cat" + e, false), _t("猫旋律 连着唱", p + "L3_cat_flow" + e, version == 1),
		_t("猫旋律 轮流唱", p + "L3_cat_pool" + e, false), _t("猫旋律 鬼畜", p + "L3_cat_kichiku" + e, version == 2),
		_t("猫鼓", p + "C_drums" + e, cat), _t("猫和声", p + "C_stabs" + e, false), _t("猫低音", p + "C_bass" + e, false)]}


func _songs() -> Array:
	var out: Array = [
		_style("Future Bass", "style_futurebass", "fb"),
		_style("Eurobeat", "style_eurobeat", "A"),
		_style("Chip", "style_chip", "chip"),
		_style("Disco", "style_disco", "B"),
		{"name": "全猫乐队", "stems": [
			_t("鼓", S1 + "skeleton/s1_L1_groove_4b.wav"), _t("猫鼓", S1 + "cat_band/s1_C_drums_4b.wav"),
			_t("猫和声", S1 + "cat_band/s1_C_stabs_4b.wav"), _t("猫低音", S1 + "cat_band/s1_C_bass_4b.wav"),
			_t("猫旋律", S1 + "cat_band/s1_C_lead_flow_4b.wav"), _t("猫旋律 鬼畜", S1 + "cat_band/s1_C_lead_kichiku_4b.wav", false),
			_t("事件：喵", S1 + "events/s1_X_meow_4b.wav", false)]},
		{"name": "Jazz", "stems": [
			_t("鼓", S1 + "style_jazz/s1_J_L1_groove_4b.wav"), _t("低音", S1 + "style_jazz/s1_J_L2_bass_4b.wav"),
			_t("钢琴", S1 + "style_jazz/s1_J_L0_piano_4b.wav"), _t("萨克斯", S1 + "style_jazz/s1_J_L3_sax_4b.wav"),
			_t("齐奏", S1 + "style_jazz/s1_J_L4_shout_4b.wav")]},
		_rhythm("节奏：半拍", "half"), _rhythm("节奏：Break", "break"), _rhythm("节奏：Club", "club"),
		{"name": "Entertainer", "stems": [
			_t("鼓", S1 + "skeleton/s1_L1_groove_4b.wav"), _t("低音", S1 + "skeleton/s1_L2_bass_4b.wav"),
			_t("和声", S1 + "style_futurebass/s1_fb_L0_keys_4b.wav"),
			_t("旋律", S1 + "entertainer_leads/s1_ent_fb_L3_lead_16b.wav"),
			_t("猫旋律", S1 + "entertainer_leads/s1_ent_cat_L3_lead_16b.wav", false)]},
	]
	# 天空关（被光柱吸上天）：云层和风暴是 C 小调，突然亮起来之后是 C 大调的欢乐颂
	var sky := M + "sky/sky_"
	var oj := M + "classics/ode_to_joy/ode_to_joy_"
	out.append({"name": "天空关 · 云层和风暴", "stems": [
		_t("半拍鼓", S1 + "rhythm_variants/s1_Rhalf_L1_groove_4b.wav"), _t("低音长音", sky + "drone_8b.wav"),
		_t("穿云的风", sky + "wind_8b.wav"), _t("末日号角", sky + "doom_horns_8b.wav", false)]})
	out.append({"name": "天空关 · 亮起来", "stems": [
		_t("鼓", S1 + "skeleton/s1_L1_groove_4b.wav"), _t("低音", oj + "L2_bass_16b.wav"), _t("和声", oj + "fb_L0_keys_16b.wav"),
		_t("神圣长音", sky + "holy_pad_8b.wav"), _t("旋律", oj + "L3_pluck_16b.wav"),
		_t("猫旋律", oj + "L3_cat_flow_16b.wav", false), _t("猫鼓", oj + "C_drums_16b.wav", false),
		_t("猫旋律 鬼畜", oj + "L3_cat_kichiku_16b.wav", false), _t("高潮", oj + "fb_L4_peak_16b.wav", false)]})
	out.append({"name": "关与关之间的等待", "stems": [_t("等待循环", M + "sky/bridge_wait_4b.wav")]})
	# 120 BPM 版（Kisa 的迪斯科关用）：同样的东西放慢重渲染的，拿来对比哪种风格在 120 下好听
	var s120 := M + "scene1_120/s120_"
	for st in [["Jazz", "J_L1_groove", "J_L2_bass", "J_L0_piano", "J_L3_sax", "J_L4_shout"],
			["Disco", "L1_groove", "L2_bass", "B_L0_keys", "B_L3_hook", "B_L4_peak"],
			["Future Bass", "L1_groove", "L2_bass", "fb_L0_keys", "fb_L3_hook", "fb_L4_peak"],
			["Club + Future Bass", "Rclub_L1_groove", "Rclub_L2_bass", "fb_L0_keys", "fb_L3_hook", "fb_L4_peak"],
			["Eurobeat", "L1_groove", "L2_bass", "A_L0_keys", "A_L3_hook", "A_L4_peak"],
			["Chip", "L1_groove", "L2_bass", "chip_L0_keys", "chip_L3_hook", "chip_L4_peak"],
			["全猫乐队", "Rhalf_L1_groove", "C_bass", "C_stabs", "C_lead_flow", "C_drums"]]:
		var stems: Array = []
		for k in range(1, st.size()):
			stems.append(_t(["鼓", "低音", "和声", "旋律", "高潮"][k - 1], "%s%s_4b.wav" % [s120, st[k]]))
		stems.append(_t("猫鼓", s120 + "C_drums_4b.wav", false))
		stems.append(_t("猫旋律 连着唱", s120 + "C_lead_flow_4b.wav", false))
		stems.append(_t("猫旋律 鬼畜", s120 + "C_lead_kichiku_4b.wav", false))
		stems.append(_t("猫旋律 旧版（切短）", s120 + "C_lead_4b.wav", false))
		out.append({"name": "120 · " + st[0], "bpm": 120.0, "stems": stems})
	for c in [["康康舞曲", "can_can", 8], ["康康舞曲 · 开场段", "can_can_a", 8], ["The Entertainer", "entertainer", 16], ["土耳其进行曲", "turkish_march", 16], ["土耳其进行曲 · 第二段", "turkish_march_b", 8], ["山魔王", "mountain_king", 8],
			["欢乐颂", "ode_to_joy", 16], ["致爱丽丝", "fur_elise", 4],
			["Your Best Friend", "your_best_friend", 8],   # Undertale，只给内部试玩；下面三个是它的别的段落
			["YBF · 前奏", "ybf_intro", 4], ["YBF · B 段", "ybf_b", 8], ["YBF · 结尾", "ybf_end", 4]]:
		for version in 3:
			out.append(_classic(c[0], c[1], c[2], version))
	return out


# ---------------------------------------------------------------- playing

## autoplay = false：只把这首曲子和它的音轨开关准备好，先不放
func play_song(index: int, autoplay := true) -> void:
	_song = index
	var song: Dictionary = _songs_list[index]
	_stream = AudioStreamSynchronized.new()
	_stream.stream_count = song.stems.size()
	for c in _stems_box.get_children():
		c.queue_free()
	for i in song.stems.size():
		var stem: Array = song.stems[i]
		var s: AudioStream = load(stem[1]) if ResourceLoader.exists(stem[1]) else null
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(round(s.get_length() * s.mix_rate))
		_stream.set_sync_stream(i, s)
		_stream.set_sync_stream_volume(i, 0.0 if stem[2] else SILENT_DB)
		var b := Button.new()
		b.text = stem[0] if s else stem[0] + "（文件没了）"
		b.disabled = s == null
		b.toggle_mode = true
		b.button_pressed = stem[2]
		b.theme_type_variation = "Hot" if stem[2] else ""
		b.focus_mode = Control.FOCUS_NONE
		b.toggled.connect(_on_stem.bind(i, b))
		_stems_box.add_child(b)
	_player.stream = _stream
	if autoplay:
		_player.play()
		if not _pattern_on.is_empty():
			Music.meow.start_free(song_bpm())      # 跟着放的喵谱子和曲子一起从头开始
	_now.text = "正在放：" + song.name
	for i in _song_buttons.size():
		_song_buttons[i].theme_type_variation = "Hot" if i == index else ""


func _on_stem(on: bool, index: int, button: Button) -> void:
	_stream.set_sync_stream_volume(index, 0.0 if on else SILENT_DB)
	button.theme_type_variation = "Hot" if on else ""


func stop_all() -> void:
	_player.stop()
	_shot.stop()
	_lcd.text = "STOPPED"
	if not compact:
		Music.meow.stop_free()
		var empty: Dictionary = {}
		for path: String in _pattern_on:
			Music.meow.set_active("jukebox:" + path, empty)
		_pattern_on.clear()
		if _patterns_box:
			_fill_patterns()


## 现在这首曲子的速度（没选曲子就是 160）
func song_bpm() -> float:
	return float(_songs_list[_song].get("bpm", BPM)) if _song >= 0 else BPM


func song_names() -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in _songs_list:
		out.append(s.name)
	return out


# ---------------------------------------------------------------- 喵谱子

func _fill_patterns() -> void:
	for c in _patterns_box.get_children():
		_patterns_box.remove_child(c)
		c.queue_free()
	for path in MeowPlayer.list_patterns():
		var kind: String = MeowPlayer.read_pattern(path).get("kind", "")
		var b := Button.new()
		b.text = ("鼓 " if kind == "drums" else "旋律 ") + path.get_file().get_basename()
		b.toggle_mode = true
		b.button_pressed = _pattern_on.has(path)
		b.theme_type_variation = "Hot" if _pattern_on.has(path) else ""
		b.focus_mode = Control.FOCUS_NONE
		b.toggled.connect(_on_pattern.bind(path, b))
		_patterns_box.add_child(b)
		var e := Button.new()
		e.text = "✎"
		e.tooltip_text = "在喵谱子工作室里打开编辑"
		e.focus_mode = Control.FOCUS_NONE
		e.pressed.connect(_edit.bind(path))
		_patterns_box.add_child(e)
	for kind: Array in [["+ 新猫鼓", "new:drums"], ["+ 新旋律", "new:melody"]]:
		var n := Button.new()
		n.text = kind[0]
		n.focus_mode = Control.FOCUS_NONE
		n.pressed.connect(_edit.bind(kind[1]))
		_patterns_box.add_child(n)


## 点了一个喵谱子：开 = 跟着现在的曲子一起放（没在放曲子就自己按 160 走），关 = 停
func _on_pattern(on: bool, path: String, button: Button) -> void:
	button.theme_type_variation = "Hot" if on else ""
	var empty: Dictionary = {}
	if on:
		_pattern_on[path] = true
		Music.meow.set_active("jukebox:" + path, MeowPlayer.read_pattern(path))
		if _player.playing:
			_player.play()                         # 曲子和谱子一起从头，才对得齐
		Music.meow.start_free(song_bpm())
	else:
		_pattern_on.erase(path)
		Music.meow.set_active("jukebox:" + path, empty)
		if _pattern_on.is_empty() and not _player.playing:
			Music.meow.stop_free()


## 去喵谱子工作室编辑（request = 谱子路径，或 "new:drums" / "new:melody"）
func _edit(request: String) -> void:
	stop_all()
	Music.meow.edit_request = request
	get_tree().change_scene_to_file("res://scenes/tools/meow_studio.tscn")


func is_playing() -> bool:
	return _player.playing


func _play_shot(path: String) -> void:
	_shot.stream = load(path)
	_shot.play()


func _process(_delta: float) -> void:
	if _player.playing:
		var beat: float = _player.get_playback_position() * _songs_list[_song].get("bpm", BPM) / 60.0
		_lcd.text = "BAR %3d  BEAT %d" % [int(beat / 4.0) + 1, int(beat) % 4 + 1]
