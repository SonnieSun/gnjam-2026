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

## 圆圈提前几拍出现
@export var approach_beats := 1.5
## 圆圈从多远收过来（占画面高度的比例）
@export var approach_travel_ratio := 0.3
## 判定圈半径（占画面高度的比例）
@export var ring_radius_ratio := 0.1
@export_group("蓄力")
## 蓄力段每几拍一组、重拍在每组的第几拍（和谱面对应：h 在前两拍，s 在第 3 拍）
@export var charge_cycle_beats := 4.0
@export var charge_strike_beat := 2.0
## 蓄到这个比例以上，重拍才按原判定涨积累条；不够只按 Good 算
@export_range(0.0, 1.0) var minimum_charge_ratio := 0.5
@export var charge_color := Color("8878ff")
@export var charged_color := Color("79dfff")
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


func _ready() -> void:
	if Engine.is_editor_hint():
		return
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
	return ring_radius_ratio * screen_size().y


func is_charge_note(note: NoteData) -> bool:
	return _charge_mode and note != null and note.sound == NoteData.Sound.HAT


func charge_ratio() -> float:
	return clampf(float(_charge) / _charge_target, 0.0, 1.0)


## 框架在算积累条之前问一下：蓄力音符不动积累条；重拍蓄力不够只按 Good 算
func gauge_result(note: NoteData, result: int) -> int:
	if is_charge_note(note):
		return NoteData.Result.NONE
	if _charge_mode and result == NoteData.Result.PERFECT and charge_ratio() < minimum_charge_ratio:
		return NoteData.Result.GOOD
	return result


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
		_stage.update(dt, local, charge_cycle_beats, charge_strike_beat)
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
		if hit:
			_charge = mini(_charge + 1, _charge_target)
		return
	if not hit:
		_stage.miss()
		_flash = 1.0
		if _charge_mode:
			_slap_text = "MISS"
			_slap_text_age = 0.0
			_charge = 0
		return
	_last_power = charge_ratio() if _charge_mode else 0.0
	_stage.slap(_last_power)
	if _charge_mode:
		_slap_text = "POWER SLAP!" if _last_power >= 0.99 else ("SLAP!" if _last_power >= minimum_charge_ratio else "LOW CHARGE")
		_slap_text_age = 0.0
		_charge = 0


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
	var charged := charge_ratio() >= minimum_charge_ratio
	draw_arc(center, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.9), 3.0)
	for n in notes:
		if n.judged:
			continue
		var ahead := beats_until(n)
		if ahead > approach_beats:
			break
		var k := clampf(ahead / approach_beats, 0.0, 1.0)
		var r := radius + k * approach_travel_ratio * size.y
		if is_charge_note(n):
			# 蓄力连点：细的小圈，不抢重拍的大圈
			draw_arc(center, r, 0.0, TAU, 64, Color(charge_color, 0.75 * (1.0 - k * 0.6)), 2.0)
		else:
			var c := sound_color(n)
			c.a = 1.0 - k * 0.6
			draw_arc(center, r, 0.0, TAU, 96, c, 7.0 if _charge_mode else 5.0)
	if _charge_mode:
		# 蓄力条：贴着判定圈里面的一圈弧
		draw_arc(center, radius * 0.82, 0.0, TAU, 64, Color(0.1, 0.09, 0.19, 0.7), 8.0)
		if _charge > 0:
			draw_arc(center, radius * 0.82, -PI / 2.0, -PI / 2.0 + TAU * charge_ratio(), 64,
					charged_color if charged else charge_color, 8.0)
		var label := "CHARGE %d / %d" % [_charge, _charge_target]
		var col := charged_color if charged else Color(1, 1, 1)
		if _slap_text_age < 0.8:
			label = _slap_text
			col = Color(1.0, 0.9, 0.3) if _slap_text != "MISS" and _slap_text != "LOW CHARGE" else Color(1.0, 0.5, 0.5)
		var pos := center + Vector2(-140.0, radius + 34.0)
		draw_string_outline(ThemeDB.fallback_font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 280, 22, 6, Color(0.02, 0.02, 0.06, 0.95))
		draw_string(ThemeDB.fallback_font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 280, 22, col)
	if tap_age < 0.15:
		draw_arc(center, radius * (1.0 + tap_age), 0.0, TAU, 64, Color(1, 1, 1, 1.0 - tap_age / 0.15), 6.0)
	if _news > 0.0:
		_draw_news(size)
	if _flash > 0.0:
		draw_rect(Rect2(-size / 2.0, size), Color(1.0, 0.15, 0.2, _flash * miss_flash))


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
