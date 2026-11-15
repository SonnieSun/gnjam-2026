extends Node3D
## BeatFx 测试场景（F6 运行）：放某一大关的叠轨音乐，一排方块各跟一个频道闪，看每关的鼓点有什么不同。
##   1 / 2 / 3   换第 1 / 2 / 3 大关的音乐和谱面
##   ↑ / ↓       积累条进度 +/- 10%（音乐跟着加减轨，方块跟着有没有声音）
## 谱面鼓（CHART）那几个方块亮的时候会放这一关的鼓声，方便对照。

## 用第几大关（0 = 第 1 关）
@export var level := 0
## 一开始的积累条进度（0~1）
@export_range(0.0, 1.0) var start_progress := 1.0

const CHANNELS := [
	["拍", {"source": BeatFx.Source.BEAT}],
	["小节", {"source": BeatFx.Source.BAR}],
	["谱面 kick", {"source": BeatFx.Source.CHART, "chart_sound": 0}],
	["谱面 snare", {"source": BeatFx.Source.CHART, "chart_sound": 1}],
	["节奏 high", {"source": BeatFx.Source.LANE, "lane": "beat", "band": 3}],
	["节奏 mid", {"source": BeatFx.Source.LANE, "lane": "beat", "band": 2}],
	["低音 low", {"source": BeatFx.Source.LANE, "lane": "bass", "band": 1}],
	["和声", {"source": BeatFx.Source.LANE, "lane": "bed"}],
	["旋律", {"source": BeatFx.Source.LANE, "lane": "lead"}],
	["高潮", {"source": BeatFx.Source.LANE, "lane": "peak"}],
	["猫鼓", {"source": BeatFx.Source.LANE, "lane": "meow"}],
	["鬼畜", {"source": BeatFx.Source.LANE, "lane": "kiai"}],
]

static var _level_override := -1

var _chart: SongChart
var _progress := 1.0
var _info: Label
var _drums := {}


func _ready() -> void:
	if _level_override >= 0:
		level = _level_override
	_progress = start_progress
	Levels.selected = clampi(level, 0, Levels.count() - 1)
	_chart = Levels.build_chart()
	if Music.enabled_for(Levels.selected):
		_chart.stream = Music.build(Music.read(Music.path_for(Levels.selected)))
		_chart.bpm = Music.bpm()
		_chart.first_beat_offset_sec = 0.0
	else:
		Music.clear()
	Conductor.load_chart(_chart)
	var judge := Judge.new()
	judge.name = "Judge"
	add_child(judge)
	judge.load_chart(_chart)
	judge.begin_section(0, _chart.sections[0], _chart.beats_per_bar, 0.0, 0.0)
	Music.set_section(0)
	Music.set_progress(_progress)
	Music.apply_now()
	_drums = {NoteData.Sound.KICK: _chart.drum_kick, NoteData.Sound.SNARE: _chart.drum_snare}
	_build_row()
	_build_view()
	Conductor.play(0.0)


func _build_row() -> void:
	var gap := 2.4
	var per_row := 6
	for i in CHANNELS.size():
		var holder := Node3D.new()
		holder.position = Vector3((i % per_row - (per_row - 1) / 2.0) * gap, 1.3 - (i / per_row) * 3.0, 0.0)
		add_child(holder)
		var cube := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(float(i) / CHANNELS.size(), 0.55, 0.9)
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 0.05
		mesh.material = mat
		cube.mesh = mesh
		holder.add_child(cube)
		var config: Dictionary = (CHANNELS[i][1] as Dictionary).duplicate()
		config["effect"] = BeatFx.Effect.SCALE
		config["amount"] = 0.45
		config["decay_beats"] = 0.35
		var fx := BeatFx.attach(cube, config)
		var glow := config.duplicate()
		glow["effect"] = BeatFx.Effect.GLOW
		glow["amount"] = 3.0
		BeatFx.attach(cube, glow)
		if fx.source == BeatFx.Source.CHART:
			var sound: int = fx.chart_sound
			fx.hit.connect(func(_s: float) -> void: _play_drum(sound))
		var label := Label3D.new()
		label.text = "%s\n%s" % [CHANNELS[i][0], fx.channel()]
		label.font_size = 28
		label.pixel_size = 0.011
		label.position = Vector3(0.0, -1.25, 0.0)
		holder.add_child(label)


func _build_view() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.6, 10.5)
	cam.look_at_from_position(cam.position, Vector3(0.0, -0.9, 0.0))
	add_child(cam)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.04, 0.09)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	add_child(sun)
	var layer := CanvasLayer.new()
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(20.0, 16.0)
	_info.add_theme_font_size_override("font_size", 18)
	layer.add_child(_info)


func _play_drum(sound: int) -> void:
	var stream: AudioStream = _drums.get(sound)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_1, KEY_2, KEY_3:
			_level_override = k.physical_keycode - KEY_1
			Conductor.stop()
			get_tree().reload_current_scene()
		KEY_UP, KEY_DOWN:
			_progress = clampf(_progress + (0.1 if k.physical_keycode == KEY_UP else -0.1), 0.0, 1.0)
			Music.set_progress(_progress)


func _process(_delta: float) -> void:
	if _info == null:
		return
	var lines := PackedStringArray()
	lines.append("第 %d 大关  %s   BPM %d   拍 %.1f   进度 %d%%（↑↓ 调，1/2/3 换关）" % [
		Levels.selected + 1, _chart.title, roundi(_chart.bpm), Conductor.song_beat, roundi(_progress * 100.0)])
	for l: Dictionary in Music.data.get("lanes", []):
		var id: String = l.get("id", "")
		var clip := Music.playing_clip(id)
		lines.append("  %-6s %s" % [id, clip if clip != "" else "（静音）"])
	_info.text = "\n".join(lines)
