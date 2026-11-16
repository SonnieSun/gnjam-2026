@tool
extends "res://scripts/sections/pizza_section.gd"
## 太空版披萨猫（第 3 大关第二段）：玩法完全沿用 Sonnie 的披萨猫关（过圈 → 九宫格 → 万花筒），
## 这里只多做一件事——从上一段「太空打飞机」接过来：
## 上一段结尾猫飞走、黑幕落下盖满画面（见 space_shooter_section.gd 的结尾过场），切到这一段时黑幕还盖着，
## 这一段一开始就让它往下落出屏幕，露出新画面（和两关之间的黑幕一样）。
## 黑幕在 SpaceShooterScore.handoff 里；没有（比如直接跳到这一段）就和原来的披萨猫关一样。

## 黑幕落出屏幕前再盖几秒（等新画面摆好）、落出去用几秒
@export var curtain_hold := 0.1
@export var curtain_leave := 0.9


func _on_enter() -> void:
	super._on_enter()
	if Engine.is_editor_hint() or camera == null:
		return
	_beat_decor()
	var curtain := SpaceShooterScore.handoff.get("curtain") as CanvasLayer
	SpaceShooterScore.handoff = {}
	if curtain == null or not is_instance_valid(curtain) or curtain.get_child_count() == 0:
		return
	var rect := curtain.get_child(0) as Control
	var tw := rect.create_tween()
	tw.tween_interval(curtain_hold)
	tw.tween_property(rect, "position:y", get_viewport().get_visible_rect().size.y + 40.0, curtain_leave) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(curtain.queue_free)


## 装饰跟拍（BeatFx，见 stages/shared/beat_fx）：光环的砖一块接一块胀过去；光球的芯各用各的节奏，灯跟底鼓。
## 光球 / 气泡 / 云本身每帧被这一关挪位置，所以接在它们里面的零件上。披萨、猫、判定圈是主体，不接。
var _decor_done := false

func _beat_decor() -> void:
	if _decor_done:
		return
	_decor_done = true
	BeatDecor.wave(_halo.get_children(), 0.2, 2.0)
	var k := 0
	for orb in _orbs.get_children():
		k += 1
		var core := orb.get_node_or_null("Core")
		if core:
			BeatDecor.stagger(core, k * 3, 0.25)  # 每个光球的芯用不同的节奏
		var lamp := orb.get_node_or_null("Light")
		if lamp:
			BeatDecor.light(lamp, 0.9)
