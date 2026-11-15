class_name BeatFx
extends Node
## 统一的节拍效果组件：挂在任何物品下面当子节点，作用在父节点上（或 target 指定的节点）。
## 每当它跟的那个「声音」响一下，就触发一次效果（胀一下 / 亮一下 / 灯闪 / 改 shader 参数 / 放动画）。
##
## 跟什么声音（source）：
##   BEAT   每 every_beats 拍一下（可以错开 beat_offset 拍）
##   BAR    每小节第一拍
##   CHART  谱面里的鼓：kick / snare / hat / any。每关谱面不一样，所以每关的鼓点自然不同。
##          时间点是谱面音符那一拍（玩家按没按都一样）。
##   LANE   叠轨音乐里某一条轨（levels/music/<大关>.json 的 lanes 的 id，比如 beat、bass、lead、meow），
##          按这条轨现在正在放的那段 loop 的打点表触发；band 选频段：all 不分，low 大致是底鼓 / 低音，
##          mid 是军鼓 / 拍手 / 人声，high 是镲。每关同名的轨放的是不同的 loop，所以每关的鼓点也不同。
##          打点表由 tools/make_hit_tables.mjs 从 wav 里算出来，放在 hits/ 下；换了音乐要重跑。
##
## 音乐系统怎么找到它：每个 BeatFx 都在 "beat_fx" 组里，并且有一个频道名 channel
## （"beat"、"bar"、"chart:kick"、"lane:meow/low" 这样），也可以自己再起一个 tag。
##   BeatFx.find("lane:meow/low")   找到所有跟这条轨低频的物品
##   BeatFx.set_gain("chart:kick", 0.0)   这一组全部关掉（1 = 正常，可以 > 1 加强）
## 现有代码不需要知道它：它自己读 Conductor.song_beat、Music 正在放哪段、Judge 的音符列表。
##
## 用法：
##   场景里：选中物品 → 加一个 Node 子节点 → 挂这个脚本 → 检查器里选 source 和 effect。
##   代码里：BeatFx.attach(node, {"source": BeatFx.Source.LANE, "lane": "meow", "effect": BeatFx.Effect.GLOW})
## 一个物品要好几种效果就挂好几个。和 BeatGlow 一样，SCALE 每帧会改父节点的 scale，父节点自己还在做
## 缩放动画的话包一层。

## 物品被触发的那一刻（strength 0~1，乘过 gain）。想做自定义效果就接这个信号或读 pulse。
signal hit(strength: float)

enum Source { BEAT, BAR, CHART, LANE }
enum Effect { NONE, SCALE, GLOW, LIGHT, MODULATE, SHADER_PARAM, ANIMATION }

const GROUP := "beat_fx"
const HITS_DIR := "res://stages/shared/beat_fx/hits/"
const AUDIO_DIR := "res://assets/audio/"

@export_group("跟什么声音")
@export var source := Source.BEAT
## BEAT：几拍一下（1 = 每拍，0.5 = 每半拍，2 = 每两拍）
@export var every_beats := 1.0
## BEAT：错开多少拍（一排东西各错一点像波浪）
@export var beat_offset := 0.0
## CHART：谱面里哪种鼓
@export_enum("kick", "snare", "hat", "any") var chart_sound := 0
## LANE：音轨 id（见 levels/music/<大关>.json 的 lanes）
@export var lane := "beat"
## LANE：频段
@export_enum("all", "low", "mid", "high") var band := 0
## LANE：比这还小声的那一下不理（0~1，按这段 loop 里最响的一下算）
@export_range(0.0, 1.0) var min_strength := 0.15
## 额外的名字，BeatFx.find(tag) 也能找到（比如 "disco_props"）
@export var tag := ""

@export_group("效果")
@export var effect := Effect.SCALE
## 作用在哪个节点上；空 = 父节点
@export var target: NodePath
## 效果有多大：SCALE 胀多少（0.2 = 大 20%）；GLOW 自发光加多少；LIGHT / MODULATE 亮多少倍；
## SHADER_PARAM 参数加多少
@export var amount := 0.3
## 每一下多少拍落回去
@export var decay_beats := 0.5
## SHADER_PARAM：参数名（材质要是 ShaderMaterial）
@export var shader_param := ""
## ANIMATION：每一下从头放这段动画（target 下面找 AnimationPlayer）
@export var animation_name := ""

## 现在亮到哪（0~1 左右），自定义效果可以读
var pulse := 0.0

static var _gains := {}
static var _tables := {}  # 打点表缓存：loop 文件路径 → {beats, bands}

var _target: Node
var _base: Variant
var _mats: Array[BaseMaterial3D] = []
var _mat_base: Array[float] = []
var _shader_mats: Array[ShaderMaterial] = []
var _anim: AnimationPlayer
var _last := 0.0
var _started := false


## 给 node 加上这个效果。config 的键就是上面的参数名。
static func attach(node: Node, config: Dictionary = {}) -> BeatFx:
	var fx := BeatFx.new()
	for key: String in config:
		fx.set(key, config[key])
	node.add_child(fx)
	return fx


## 找到频道名或 tag 等于 name 的所有 BeatFx
static func find(name: String) -> Array[BeatFx]:
	var out: Array[BeatFx] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return out
	for n in tree.get_nodes_in_group(GROUP):
		var fx := n as BeatFx
		if fx and (fx.channel() == name or (fx.tag != "" and fx.tag == name)):
			out.append(fx)
	return out


## 一组的强度（频道名或 tag）：0 = 关掉，1 = 正常
static func set_gain(name: String, gain: float) -> void:
	_gains[name] = gain


static func gain_of(name: String) -> float:
	return _gains.get(name, 1.0)


## 频道名：beat、beat/0.5、bar、chart:kick、lane:meow/low ……
func channel() -> String:
	match source:
		Source.BEAT:
			return "beat" if is_equal_approx(every_beats, 1.0) else "beat/%s" % str(every_beats)
		Source.BAR:
			return "bar"
		Source.CHART:
			return "chart:" + ["kick", "snare", "hat", "any"][chart_sound]
		_:
			return "lane:%s/%s" % [lane, ["all", "low", "mid", "high"][band]]


func _ready() -> void:
	add_to_group(GROUP)
	_target = get_node_or_null(target) if not target.is_empty() else get_parent()
	if _target == null:
		return
	match effect:
		Effect.SCALE:
			if _target is Node3D or _target is Node2D or _target is Control:
				_base = _target.scale
		Effect.GLOW:
			_make_glow_materials()
		Effect.LIGHT:
			if _target is Light3D:
				_base = (_target as Light3D).light_energy
			elif _target is Light2D:
				_base = (_target as Light2D).energy
		Effect.MODULATE:
			if _target is CanvasItem:
				_base = (_target as CanvasItem).modulate
		Effect.SHADER_PARAM:
			_find_shader_materials()
		Effect.ANIMATION:
			_anim = _target as AnimationPlayer
			if _anim == null:
				for n in _target.find_children("*", "AnimationPlayer", true, false):
					_anim = n as AnimationPlayer
					break


func _process(delta: float) -> void:
	if not Conductor.playing:
		_started = false
		return
	var now := Conductor.song_beat
	if not _started or now < _last or now - _last > 4.0:
		# 刚开始、音乐跳了（切关 / 调试跳拍）：这一帧只记位置，不补触发
		_started = true
		_last = now
		return
	var strength := _strength_between(_last, now)
	_last = now
	if strength > 0.0:
		strength *= gain_of(channel()) * (gain_of(tag) if tag != "" else 1.0)
		if strength > 0.0:
			pulse = maxf(pulse, strength)
			hit.emit(strength)
			if _anim and animation_name != "":
				_anim.stop()
				_anim.play(animation_name)
	var beats := delta / maxf(Conductor.sec_per_beat(), 0.001)
	pulse *= exp(-5.0 * beats / maxf(decay_beats, 0.01))
	_apply()


## (from, to] 这段拍子里有没有响一下，有的话返回最响那一下的强度（0~1），没有返回 0
func _strength_between(from: float, to: float) -> float:
	match source:
		Source.BEAT:
			var e := maxf(every_beats, 0.01)
			return 1.0 if floorf((to - beat_offset) / e) > floorf((from - beat_offset) / e) else 0.0
		Source.BAR:
			var bpb := float(Conductor.chart.beats_per_bar) if Conductor.chart else 4.0
			return 1.0 if floorf(to / bpb) > floorf(from / bpb) else 0.0
		Source.CHART:
			return _chart_between(from, to)
		_:
			return _lane_between(from, to)


func _chart_between(from: float, to: float) -> float:
	var judge := _judge()
	if judge == null:
		return 0.0
	var notes: Array[NoteData] = judge.notes
	for i in range(notes.size() - 1, -1, -1):
		var n := notes[i]
		if n.beat <= from:
			break
		if n.beat <= to and (chart_sound == 3 or n.sound == chart_sound):
			return 1.0
	return 0.0


func _lane_between(from: float, to: float) -> float:
	var clip_id := Music.playing_clip(lane)
	if clip_id == "":
		return 0.0
	var level := Music.level_of(lane, clip_id)
	if level < 0.05:
		return 0.0
	var table := _table_for(_clip_file(clip_id))
	if table.is_empty():
		return 0.0
	var length: float = table.beats
	var hits: Array = table.bands.get(["all", "low", "mid", "high"][band], [])
	var a := fposmod(from, length)
	var b := a + (to - from)  # 可能跨过 loop 结尾
	var best := 0.0
	for h: Array in hits:
		var at: float = h[0]
		var s: float = h[1]
		if s < min_strength:
			continue
		if (at > a and at <= b) or (at + length > a and at + length <= b):
			best = maxf(best, s)
	return best * level


func _clip_file(clip_id: String) -> String:
	for l: Dictionary in Music.data.get("lanes", []):
		if l.get("id", "") != lane:
			continue
		for c: Dictionary in l.get("clips", []):
			if c.get("id", "") == clip_id:
				return c.get("file", "")
	return ""


static func _table_for(file: String) -> Dictionary:
	if file == "" or not file.ends_with(".wav"):
		return {}  # 喵谱子轨（.json）是打中时唱的，不跟时钟走，没有打点表
	if not _tables.has(file):
		var path := HITS_DIR + file.trim_prefix(AUDIO_DIR).get_basename() + ".json"
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if parsed == null:
			push_warning("BeatFx：没有打点表 %s（跑一下 stages/shared/beat_fx/tools/make_hit_tables.mjs）" % path)
		_tables[file] = parsed if parsed is Dictionary else {}
	return _tables[file]


func _judge() -> Judge:
	var tree := get_tree()
	var root := tree.current_scene if tree else null
	if root == null:
		return null
	if root is Judge:
		return root
	return root.find_child("Judge", true, false) as Judge


func _apply() -> void:
	if _target == null:
		return
	match effect:
		Effect.SCALE:
			if _base != null:
				_target.scale = _base * (1.0 + pulse * amount)
		Effect.GLOW:
			for i in _mats.size():
				_mats[i].emission_energy_multiplier = _mat_base[i] + pulse * amount
		Effect.LIGHT:
			if _base != null:
				if _target is Light3D:
					(_target as Light3D).light_energy = _base * (1.0 + pulse * amount)
				else:
					(_target as Light2D).energy = _base * (1.0 + pulse * amount)
		Effect.MODULATE:
			if _base != null:
				var k := 1.0 + pulse * amount
				var c: Color = _base
				(_target as CanvasItem).modulate = Color(c.r * k, c.g * k, c.b * k, c.a)
		Effect.SHADER_PARAM:
			for i in _shader_mats.size():
				_shader_mats[i].set_shader_parameter(shader_param, _mat_base[i] + pulse * amount)


## 目标下面所有模型的材质各复制一份（不影响别的物品）。本来没开自发光的，用自己的贴图发光（相乘，不冲白）。
func _make_glow_materials() -> void:
	var meshes: Array = [_target] if _target is MeshInstance3D else []
	meshes.append_array(_target.find_children("*", "MeshInstance3D", true, false))
	for m: MeshInstance3D in meshes:
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s) as BaseMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as BaseMaterial3D
			if not mat.emission_enabled:
				mat.emission_enabled = true
				mat.emission = Color.WHITE if src.albedo_texture else src.albedo_color
				mat.emission_texture = src.albedo_texture
				mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				mat.emission_energy_multiplier = 0.0
			m.set_surface_override_material(s, mat)
			_mats.append(mat)
			_mat_base.append(mat.emission_energy_multiplier)


func _find_shader_materials() -> void:
	if shader_param == "":
		return
	var nodes: Array = [_target]
	nodes.append_array(_target.find_children("*", "", true, false))
	for n: Node in nodes:
		var list: Array[Material] = []
		if n is CanvasItem and (n as CanvasItem).material:
			list.append((n as CanvasItem).material)
		if n is GeometryInstance3D and (n as GeometryInstance3D).material_override:
			list.append((n as GeometryInstance3D).material_override)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			for s in (n as MeshInstance3D).mesh.get_surface_count():
				var mat := (n as MeshInstance3D).get_active_material(s)
				if mat:
					list.append(mat)
		for mat in list:
			var sm := mat as ShaderMaterial
			if sm and sm not in _shader_mats and sm.get_shader_parameter(shader_param) is float:
				_shader_mats.append(sm)
				_mat_base.append(sm.get_shader_parameter(shader_param))
