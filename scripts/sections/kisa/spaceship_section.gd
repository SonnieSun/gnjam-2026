@tool
extends SpinSection
## 飞船关卡：猫「毛毛」开着飞船往前飞，每个音符是一颗飞过来的行星，
## 行星飞进飞船前面的判定圈那一刻按键，猫转一圈把行星撞飞；没按到行星就撞上飞船（镜头抖、红闪）。
## 判定用 Sonnie 的 Judge（不改），这里只把结果转给 SpaceStage 做表现。
## 3D 画面（星空、行星、镜头）都在 SpaceStage 里，可调参数在 Stage 节点的 Inspector 里。
##
## 编辑器预览里不跑 3D，只显示一行说明；看效果用 F6 运行 spaceship_test.tscn。
## 测试用，只在本机 _sandbox 里，不进仓库。

## 飞船场景（会当作 KisaSpinCat3D 的背景放进 3D 世界，不跟猫转）。里面有 Flames 节点的话尾焰会跟着拍子变长。
## 默认飞碟 saucer.tscn；换成 ship.tscn 就是原来的火箭
@export var ship: PackedScene = preload("res://stages/shared/saucer.tscn")
## 行星提前几拍出现
@export var approach_beats := 4.0
## 猫的朝向（度）。模型默认朝 +Z，转 180 让它朝飞行方向 -Z
@export var cat_yaw_degrees := 180.0
## 猫转圈的轴心（相对模型包围盒中心，朝向转过之后的坐标）
@export var cat_pivot_offset := Vector3(0.0, 0.0, -1.2)
## 没打中时整个画面红闪的强度
@export_range(0.0, 1.0) var miss_flash := 0.35
## 调试用：自动在每个音符的时机按键（看演出用，正式玩要关掉）
@export var autoplay := false

var _spin_cat: KisaSpinCat3D
var _stage: SpaceStage
var _flash := 0.0
var _auto_next := 0
var _auto_release := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_spin_cat = KisaSpinCat3D.new()
	_spin_cat.full_screen = true
	_spin_cat.backdrop = ship
	_spin_cat.model_rotation_degrees = Vector3(0.0, cat_yaw_degrees, 0.0)
	_spin_cat.pivot_offset = cat_pivot_offset
	_spin_cat.listen_input = true  # 每次按键都转，按住一直转，不管有没有打中
	_spin_cat.z_index = -1
	add_child(_spin_cat)
	_stage = $Stage as SpaceStage
	if _stage == null:
		_stage = SpaceStage.new()
		add_child(_stage)
	_stage.setup(_spin_cat)


func hit_position(_note: NoteData = null) -> Vector2:
	return _stage.hit_screen_offset() if _stage else Vector2.ZERO


func hit_radius() -> float:
	return _stage.ring_screen_radius() if _stage else 80.0


func _update_spin(_local_beat: float, _angle: float) -> void:
	center_on_screen()
	if _stage:
		_stage.update(song_beat(), own_notes(), approach_beats)
		if autoplay:
			_autoplay()
	_flash = maxf(_flash - get_process_delta_time() * 2.5, 0.0)
	queue_redraw()


func _on_note_judged(note: NoteData, result: int) -> void:
	if _stage == null:
		return
	if result == NoteData.Result.MISS:
		_stage.crash(note)
		_stage.add_miss()
		_flash = 1.0
	else:
		_stage.knock(note, result)
		_stage.add_success()


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
		draw_string(ThemeDB.fallback_font, Vector2(-300.0, 0.0), "飞船关卡：3D 画面不在编辑器里预览，F6 运行 spaceship_test.tscn",
				HORIZONTAL_ALIGNMENT_CENTER, 600.0, 20)
		return
	# 节拍辅助线：行星各走各的路线，这里围着判定点（猫）收过来，提示「第几拍该按」
	draw_lit_target(self, hit_position(), hit_radius(), Color(1, 1, 1, 0.45), 2.0)
	draw_target_guides(self, hit_position(), hit_radius(), 0.3 * size.y, approach_beats)
	if _flash > 0.0:
		draw_rect(Rect2(-size / 2.0, size), Color(1.0, 0.15, 0.2, _flash * miss_flash))
