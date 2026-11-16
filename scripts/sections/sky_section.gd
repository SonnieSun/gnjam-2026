@tool
extends "res://scripts/sections/kisa/abduction_section.gd"
## 上升关（第 1 关后面的插曲关）：猫被光柱牵着在屏幕中间往上飞，穿过云层、风暴，突然亮起来，飞进太空，最后进飞碟。
## 玩法是吸猫关原来的（光圈顺着光柱落到猫身上的那一拍按），舞台是 SkyStage。
## 阶段跟着音乐的档位走（Music.tier_changed，在小节线上，和音乐一起变）：
##   0 云层  1 风暴  2 亮起来（欢乐颂）  3 太空  4 飞碟出现（fever）
## 积累条的最后一条线（谱面里 gauge_events 的最后一个）= 结尾：不再出音符，镜头推到飞碟底下，猫被吸进去，然后过关。

## 结尾的特写一共几拍
@export var finale_beats := 12.0
## 从风暴切到亮起来那一下画面全白、圈看不清：切过去时把接下来几个还没到的音符直接去掉（不算 Miss，0 = 不去）
@export var bright_skip_notes := 3

var _bright_skipped := false

var _clear_at := INF
var _sky: SkyStage


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_sky = _stage as SkyStage
	Music.tier_changed.connect(_on_tier)


func _on_enter() -> void:
	if _sky:
		_sky.set_phase(Music.tier)


func _on_tier(new_tier: int, _up: bool) -> void:
	if _sky and active:
		_sky.set_phase(maxi(new_tier, _sky.sky_phase))  # 只往前走，掉档不往回退
		if _sky.sky_phase >= 2 and not _bright_skipped:
			_bright_skipped = true
			_skip_next_notes(bright_skip_notes)


## 把接下来 count 个还没到的音符标成已处理：Judge 跳过它们（不算 Miss、不计判定），舞台也不再画
func _skip_next_notes(count: int) -> void:
	var now := song_beat()
	for n in notes:
		if count <= 0:
			break
		if not n.judged and n.beat > now:
			n.judged = true
			count -= 1
			# 已经在光柱里往下落的圈：舞台只给判定过的音符收圈，这里直接让它淡掉（不然会停在半空）
			var key := n.get_instance_id()
			if _sky._rings.has(key):
				var r: Dictionary = _sky._rings[key]
				_sky._rings.erase(key)
				r.hit = true
				r.t = 0.0
				_sky._fading.append(r)


func _update_spin(local_beat: float, angle: float) -> void:
	super(local_beat, angle)
	if song_beat() >= _clear_at:
		_clear_at = INF
		_fill_gauge_now()


func _on_gauge_event(index: int, _value: int) -> void:
	if _sky == null or index < gauge_event_values.size():
		return
	# 最后一条线：结尾
	var main := get_parent().get_parent()
	if main and main.get("judge"):
		main.judge.stop_notes()
	_sky.set_phase(4)
	_sky.finale(finale_beats * Conductor.sec_per_beat())
	_clear_at = song_beat() + finale_beats
	Music.outro()  # 音乐换成这一关写好的结尾段（小关音乐配置里的 "outro"）
	Music.play_sfx("sky_whoosh_up", -4.0, finale_beats * Conductor.sec_per_beat() * 0.55)


func _fill_gauge_now() -> void:
	var main := get_parent().get_parent()
	if main == null or not main.get("gauge"):
		return
	var g: Gauge = main.gauge
	while not g.full:
		g.apply(NoteData.Result.PERFECT)
