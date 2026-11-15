@tool
extends Spin3DSection
## 猫猫打地球：完整 FBX 动画由歌曲拍数驱动；判定与输入仍由 Judge 统一处理。
## 每四拍：前两拍按密集踩镲蓄力，第三拍重拍。蓄力不直接涨关卡积累条。
## 美术、镜头定位点、灯光、UI 样式均在 cat_earth.tscn 中编辑。

@export_group("原动画与节拍")
## FBX 整段动画；留空或不存在时自动选择导入的非 RESET 动画。
@export var animation_clip: StringName = &"CatEarthLoop"
@export_range(1.0, 8.0, 0.25) var beats_per_swat := 4.0
@export_range(1.0, 120.0, 1.0) var source_fps := 24.0
@export_range(1, 240, 1) var source_loop_frames := 96
## 第六帧起播，使原第 30 / 78 帧恰好落在第 3 / 7 拍。
@export_range(1, 97, 1) var animation_start_frame := 6
@export_group("连续点击蓄力")
@export_range(0.0, 4.0, 0.05) var charge_start_beat := 0.0
@export_range(0.0, 4.0, 0.05) var charge_end_beat := 1.75
@export_range(0.0, 8.0, 0.05) var strike_beat := 2.0
## 实际目标会与当前鼓谱这一轮的踩镲数量取较小值；编辑 Pattern 后自动跟随。
@export_range(1, 32, 1) var required_charge_hits := 8
@export_range(0.0, 1.0, 0.05) var minimum_charge_ratio := 0.75
@export_group("提示与反馈")
@export var show_charge_hud := true
@export var hud_margin := Vector2(24.0, 96.0)
@export var charge_color := Color("8878ff")
@export var charged_color := Color("79dfff")
@export var charge_bone: StringName = &"fore_paw.L"
@export_group("")

@onready var _model: Node3D = %CatEarth
@onready var _camera_pose_marker: Marker3D = %CameraPose
@onready var _camera_target: Marker3D = %CameraTarget
@onready var _charge_panel: Control = %ChargePanel
@onready var _status_label: Label = %ChargeStatus
@onready var _hint_label: Label = %ChargeHint
@onready var _charge_bar: ProgressBar = %ChargeBar

var last_strike_was_charged := false
var _animation: AnimationPlayer
var _clip: StringName
var _skeleton: Skeleton3D
var _charge_bone_index := -1
var _charge_cycle := -999
var _charge_hits := 0
var _charge_by_cycle: Dictionary = {}
var _last_strike_cycle := -999
var _last_strike_text := ""
var _last_strike_ratio := 0.0
var _standalone_preview := false


func _enter_tree() -> void:
	# 必须在蒙皮进入场景树之前创建独立世界，避免绑定完成后切换世界
	# 导致 GPU 蒙皮脱离 Skeleton3D，出现网格位置与骨骼位置不一致。
	if not Engine.is_editor_hint():
		var view := get_node_or_null("View/Viewport") as SubViewport
		if view:
			view.own_world_3d = true


func _ready() -> void:
	_standalone_preview = def == null and not Engine.is_editor_hint()
	super._ready()
	_resolve_model()
	if _previewing() and def == null:
		_make_editor_preview()
	_update_charge_ui()


func _previewing() -> bool:
	return super._previewing() or _standalone_preview


func _resolve_model() -> void:
	if _model == null:
		return
	_animation = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation:
		_clip = animation_clip
		if not _animation.has_animation(_clip):
			_clip = &""
			for candidate: StringName in _animation.get_animation_list():
				if candidate != &"RESET":
					_clip = candidate
					break
		if _clip != &"":
			_animation.play(_clip)
			_animation.pause()
	_skeleton = _find_skeleton(_model)
	if _skeleton:
		_charge_bone_index = _skeleton.find_bone(charge_bone)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _make_editor_preview() -> void:
	def = SectionDef.new()
	def.title = "ORBIT CAT / CHARGE + HIT"
	def.bars = PackedStringArray(["hhhhhhhhs.......", "hhhhhhhhs.......", "hhhhhhhhs......."])
	def.length = PREVIEW_BEATS
	notes = []
	for item in def.parse_notes(4):
		var note := NoteData.new()
		note.beat = float(item.beat)
		note.sound = int(item.sound)
		notes.append(note)


func _camera_pose(_progress: float, _time: float) -> Dictionary:
	return {
		"pos": _camera_pose_marker.global_position if _camera_pose_marker else Vector3(7.4, 6.0, 11.5),
		"look": _camera_target.global_position if _camera_target else Vector3(0.36, 1.95, -0.22),
		"roll": 0.0,
	}


func _update_view(_time: float) -> void:
	_ensure_cycle(_cycle_for(local_beat()))
	if _animation and _clip != &"":
		if _animation.assigned_animation != _clip:
			_animation.play(_clip)
			_animation.pause()
		# 按拍数 seek 而非 delta 累加；改 BPM 后仍然每四拍重拍一次。
		var source_seconds := float(source_loop_frames) / source_fps
		var swat_seconds := source_seconds * 0.5
		var offset := float(animation_start_frame - 1) / source_fps
		var source_time := fposmod(maxf(local_beat(), 0.0) / beats_per_swat * swat_seconds + offset, source_seconds)
		_animation.seek(minf(source_time, _animation.get_animation(_clip).length), true)
	_update_charge_ui()


func _cycle_for(beat: float) -> int:
	return floori(beat / maxf(beats_per_swat, 0.25))


func _ensure_cycle(cycle: int) -> void:
	if cycle != _charge_cycle:
		_charge_cycle = cycle
		_charge_hits = int(_charge_by_cycle.get(cycle, 0))
		# 提前命中的下一轮首音仍属于下一轮，不能被当前帧的拍数清掉。
		for previous: int in _charge_by_cycle.keys():
			if previous < cycle - 2:
				_charge_by_cycle.erase(previous)


func _runtime_chart() -> SongChart:
	if _previewing():
		return null
	var clock := get_node_or_null("/root/Conductor")
	return clock.get("chart") as SongChart if clock else null


func _pattern_bar_beats() -> int:
	var chart := _runtime_chart()
	return chart.beats_per_bar if chart else 4


func _pattern_rest_beats() -> float:
	var chart := _runtime_chart()
	if chart == null:
		return 0.0
	return float(chart.rest_bars_on_switch * chart.beats_per_bar)


func charge_target(cycle: int = -999) -> int:
	if def == null:
		return required_charge_hits
	if cycle == -999:
		cycle = _charge_cycle
	var bar_beats := _pattern_bar_beats()
	var pattern_length := def.length_beats(bar_beats)
	if pattern_length <= 0.0:
		return required_charge_hits
	var start := float(cycle) * beats_per_swat - _pattern_rest_beats()
	var in_pattern := fposmod(start, pattern_length)
	var planned := 0
	for item in def.parse_notes(bar_beats):
		var ahead := fposmod(float(item.beat) - in_pattern, pattern_length)
		if int(item.sound) == NoteData.Sound.HAT and ahead >= charge_start_beat - 0.001 and ahead <= charge_end_beat + 0.001:
			planned += 1
	return mini(required_charge_hits, maxi(planned, 1))


func charge_hits() -> int:
	return _charge_hits


func charge_ratio() -> float:
	return clampf(float(_charge_hits) / charge_target(), 0.0, 1.0)


func is_charge_note(note: NoteData) -> bool:
	if def == null or note == null or note.sound != NoteData.Sound.HAT:
		return false
	var phase := fposmod(note.beat - def.start_beat, beats_per_swat)
	return phase >= charge_start_beat - 0.001 and phase <= charge_end_beat + 0.001


func is_strike_note(note: NoteData) -> bool:
	if def == null or note == null or note.sound == NoteData.Sound.HAT:
		return false
	var phase := fposmod(note.beat - def.start_beat, beats_per_swat)
	return absf(phase - strike_beat) < 0.01


## Main 在 notify_judged 之前调用；仍由共用 Gauge 处理分数。
func gauge_result(note: NoteData, result: int) -> int:
	if is_charge_note(note):
		return NoteData.Result.NONE
	if not is_strike_note(note) or result == NoteData.Result.MISS:
		return result
	_ensure_cycle(_cycle_for(note.beat - def.start_beat))
	return result if charge_ratio() >= minimum_charge_ratio else NoteData.Result.NONE


func wants_hit_effects(note: NoteData) -> bool:
	# 密集连打保留踩镲和蓄力条，只在重拍时使用大范围特效与喵声。
	return not is_charge_note(note)


func _on_note_judged(note: NoteData, result: int) -> void:
	if def == null:
		return
	var cycle := _cycle_for(note.beat - def.start_beat)
	_ensure_cycle(cycle)
	if is_charge_note(note):
		if result != NoteData.Result.MISS and result != NoteData.Result.NONE:
			_charge_hits += 1
			_charge_by_cycle[cycle] = _charge_hits
	elif is_strike_note(note):
		_last_strike_ratio = charge_ratio()
		last_strike_was_charged = result != NoteData.Result.MISS and _last_strike_ratio >= minimum_charge_ratio
		_last_strike_cycle = cycle
		if result == NoteData.Result.MISS:
			_last_strike_text = "MISSED THE BEAT"
		elif not last_strike_was_charged:
			_last_strike_text = "LOW CHARGE"
		else:
			_last_strike_text = "POWER SHOT!"
		_charge_hits = 0
		_charge_by_cycle[cycle] = 0
	_update_charge_ui()


func hit_position(note: NoteData = null) -> Vector2:
	# 连打反馈跟着真正举起的爪子；主重拍仍落在场景里的 Focus 标记。
	if note and is_charge_note(note) and _skeleton and _charge_bone_index >= 0 and camera and _posed:
		var hand := _skeleton.global_transform * _skeleton.get_bone_global_pose(_charge_bone_index).origin
		var view_size := Vector2(_viewport.size)
		if view_size.x > 0 and view_size.y > 0:
			return camera.unproject_position(hand) / view_size * _container.size - _container.size / 2.0
	return super.hit_position(note)


func _draw_overlay() -> void:
	if def == null or _overlay == null:
		return
	var center := super.hit_position()
	var radius := hit_radius()
	var now_phase := fposmod(local_beat(), beats_per_swat)
	var charged := charge_ratio() >= minimum_charge_ratio
	var target_color := charged_color if charged else charge_color
	draw_lit_target(_overlay, center, radius, Color(target_color, 0.66), 2.5)
	draw_target_guides(_overlay, center, radius, approach_travel_ratio * screen_size().y, approach_beats)
	# 踩镲连打不叠八层圆环；只给主要重拍显示接近圈。
	for note in own_notes():
		if note.judged or is_charge_note(note):
			continue
		var ahead := beats_until(note)
		if ahead > approach_beats:
			break
		if ahead < -0.4:
			continue
		var k := clampf(ahead / approach_beats, 0.0, 1.0)
		_overlay.draw_arc(center, radius + k * approach_travel_ratio * screen_size().y, 0.0, TAU, 96,
				Color(charged_color, 1.0 - k * 0.68), 4.0)
	if now_phase <= charge_end_beat + 0.1 and charge_ratio() > 0.0:
		_overlay.draw_arc(center, radius * 0.86, -PI / 2.0, -PI / 2.0 + TAU * charge_ratio(), 64,
				Color(target_color, 0.9), 4.0)
	if tap_age < 0.12:
		_overlay.draw_arc(center, radius * (1.0 + tap_age), 0.0, TAU, 64,
				Color(charged_color, (1.0 - tap_age / 0.12) * 0.7), 3.0)


func _update_charge_ui() -> void:
	if not is_instance_valid(_charge_panel):
		return
	_charge_panel.visible = show_charge_hud
	var viewport_size := screen_size()
	_charge_panel.position = Vector2(-viewport_size.x * 0.5 + hud_margin.x,
			viewport_size.y * 0.5 - _charge_panel.size.y - hud_margin.y)
	if def == null:
		return
	var phase := fposmod(local_beat(), beats_per_swat)
	var waiting := local_beat() < _pattern_rest_beats()
	var ratio := charge_ratio()
	var target := charge_target()
	if waiting:
		_status_label.text = "LISTEN / GET READY"
		_hint_label.text = "Click / Space follows the hats"
	elif _last_strike_cycle != -999 and _last_strike_cycle == _charge_cycle and phase >= strike_beat:
		_status_label.text = _last_strike_text
		_hint_label.text = "Next roll is coming"
		ratio = _last_strike_ratio
	elif phase < strike_beat and ratio >= 1.0:
		_status_label.text = "READY  %d / %d" % [mini(_charge_hits, target), target]
		_hint_label.text = "Strike once when the ring meets"
	elif phase <= charge_end_beat + 0.16:
		_status_label.text = "CHARGE  %d / %d" % [mini(_charge_hits, target), target]
		_hint_label.text = "Fast taps to the hats"
	else:
		_status_label.text = "HIT THE EARTH!"
		_hint_label.text = "One strong hit on the snare"
	_charge_bar.value = ratio * 100.0
	_status_label.modulate = charged_color if ratio >= minimum_charge_ratio else Color.WHITE


func _on_enter() -> void:
	_charge_cycle = -999
	_charge_hits = 0
	_charge_by_cycle.clear()
	_last_strike_cycle = -999
	last_strike_was_charged = false


func _on_restore() -> void:
	if _animation and _clip != &"":
		_animation.pause()
		_animation.seek(0.0, true)
	_charge_cycle = -999
	_charge_hits = 0
	_charge_by_cycle.clear()
	_last_strike_cycle = -999
	_last_strike_ratio = 0.0
	_last_strike_text = ""
	last_strike_was_charged = false
	if is_instance_valid(_status_label):
		_status_label.modulate = Color.WHITE
	_update_charge_ui()
