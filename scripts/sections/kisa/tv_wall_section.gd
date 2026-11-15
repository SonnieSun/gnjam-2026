@tool
extends SpinSection
## 电视墙关卡：墙上一次亮一台电视，每个音符是一只水果猫（香蕉猫、苹果猫……）从画面外飞过来砸它。
## 猫砸到屏幕的那一刻正好在拍子上，这时按键：电视白闪、冒 Y2K 星星、黑屏裂开，换下一台亮；桌上的猫转一圈。
## 没按准：水果猫被弹开，电视没坏，下一只接着砸它。全部砸黑后一起重新亮。
## 判定用框架的 Judge（不改），这里只把结果转给 TvWallStage 做表现；3D 画面和可调参数都在 Stage 节点里。
## 编辑器预览里不跑 3D，只显示一行说明。效果图场景在 stages/tv_wall/mockup/。

## 水果猫提前几拍飞出来
@export var approach_beats := 2.0
## 缩圈从屏幕外多远收过来（像素）
@export var ring_travel := 220.0
## 没打中时整个画面红闪的强度
@export_range(0.0, 1.0) var miss_flash := 0.25
## 调试用：自动在每个音符的时机按键（看演出用，正式玩要关掉）
@export var autoplay := false

var _stage: TvWallStage
var _last_note: NoteData
var _flash := 0.0
var _auto_next := 0
var _auto_release := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_stage = get_node_or_null("Stage") as TvWallStage
	if _stage == null:
		_stage = TvWallStage.new()
		add_child(_stage)
	_stage.setup(self)


func hit_position(note: NoteData = null) -> Vector2:
	var n := note if note else _last_note
	return _stage.screen_offset(n) if _stage and n else Vector2.ZERO


func hit_radius() -> float:
	return _stage.screen_radius(_last_note) * 0.6 if _stage and _last_note else 80.0


func _update_spin(_local_beat: float, _angle: float) -> void:
	center_on_screen()
	if _stage:
		_stage.update(song_beat(), own_notes(), approach_beats)
		if autoplay:
			_autoplay()
	_flash = maxf(_flash - get_process_delta_time() * 2.5, 0.0)
	queue_redraw()


func _on_note_judged(note: NoteData, result: int) -> void:
	_last_note = note
	if _stage == null:
		return
	if result == NoteData.Result.MISS:
		_stage.bounce(note)
		_flash = 1.0
	else:
		_stage.knock(note, result)


## 自动按键：到了音符的拍子就按下，下一帧松开
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


func _draw() -> void:
	if def == null:
		return
	var size := screen_size()
	if Engine.is_editor_hint():
		draw_string(ThemeDB.fallback_font, Vector2(-300.0, 0.0), "电视墙关卡：3D 画面不在编辑器里预览，F5 运行后按 4",
				HORIZONTAL_ALIGNMENT_CENTER, 600.0, 20)
		return
	if _stage:
		# 节拍辅助线：要按的拍子围着那只水果猫要砸的电视收过来；不用按的拍子围着上一台被砸的电视
		draw_target_guides(self, hit_position(), hit_radius(), ring_travel, approach_beats,
				func(n: NoteData) -> Array: return [_stage.screen_offset(n), _stage.screen_radius(n)])
	if _stage:
		# 每只飞着的水果猫：在它要砸的那台电视上画一个收过来的圈，收到和屏幕一样大时按
		for n: NoteData in _stage.flying_notes():
			var ahead := beats_until(n)
			var k := clampf(ahead / approach_beats, 0.0, 1.0)
			var c := sound_color(n)
			c.a = 1.0 - k * 0.6
			var center := _stage.screen_offset(n)
			var r := _stage.screen_radius(n)
			draw_arc(center, r + k * ring_travel, 0.0, TAU, 96, c, 5.0)
			if k < 0.5:
				draw_arc(center, r, 0.0, TAU, 64, Color(1, 1, 1, 0.5 * (1.0 - k * 2.0)), 2.0)
	if _flash > 0.0:
		draw_rect(Rect2(-size / 2.0, size), Color(1.0, 0.15, 0.2, _flash * miss_flash))
