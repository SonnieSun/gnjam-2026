@tool
class_name JudgementWidget
extends Control
## Approved word art with a short centered pop and local impact vibration.
const ART := {
	NoteData.Result.PERFECT: preload("res://assets/ui/judgements/perfect.png"),
	NoteData.Result.GREAT: preload("res://assets/ui/judgements/great.png"),
	NoteData.Result.GOOD: preload("res://assets/ui/judgements/good.png"),
	NoteData.Result.MISS: preload("res://assets/ui/judgements/miss.png"),
}
const WIDTHS := {NoteData.Result.PERFECT: 280.0, NoteData.Result.GREAT: 232.0, NoteData.Result.GOOD: 196.0, NoteData.Result.MISS: 160.0}
@export var display_seconds := 0.7
@export_range(0.5, 1.0, 0.01) var entry_scale := 0.74
@export_range(1.0, 1.2, 0.01) var peak_scale := 1.08
@export_range(0.0, 4.0, 0.1) var shake_pixels := 1.8
var _entry: Tween
var _picture_rest := Vector2.ZERO
@onready var picture: TextureRect = $Picture
@onready var timing: Label = $Timing
@onready var expiry: Timer = $Expiry

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expiry.timeout.connect(clear)
	clear()

func show_judgement(result: int, diff_sec: float) -> void:
	_stop_entry()
	if not ART.has(result):
		clear()
		return
	picture.texture = ART[result]
	var w: float = WIDTHS[result]
	var h := minf(144.0, w * picture.texture.get_height() / picture.texture.get_width())
	picture.position = Vector2((size.x - w) * 0.5, 0)
	picture.size = Vector2(w, h)
	_picture_rest = picture.position
	picture.pivot_offset = picture.size * 0.5
	timing.position = Vector2(0, h + 2)
	timing.size = Vector2(size.x, 22)
	timing.text = ("LATE" if diff_sec > 0 else "EARLY") if result in [NoteData.Result.GREAT, NoteData.Result.GOOD] else ""
	visible = true
	picture.scale = Vector2.ONE * entry_scale
	_entry = create_tween().set_parallel()
	_entry.tween_property(picture, "scale", Vector2.ONE * peak_scale, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_entry.tween_property(picture, "scale", Vector2.ONE, 0.14).set_delay(0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_entry.tween_method(_vibrate, 0.0, 1.0, 0.20)
	expiry.start(display_seconds)

func _vibrate(progress: float) -> void:
	var strength := shake_pixels * pow(1.0 - progress, 2.0)
	picture.position = _picture_rest + Vector2(sin(progress * TAU * 4.0), sin(progress * TAU * 5.0) * 0.65) * strength

func _stop_entry() -> void:
	if _entry:
		_entry.kill()
		_entry = null
	if is_instance_valid(picture):
		picture.position = _picture_rest
		picture.scale = Vector2.ONE

func clear() -> void:
	_stop_entry()
	if is_instance_valid(expiry): expiry.stop()
	visible = false
