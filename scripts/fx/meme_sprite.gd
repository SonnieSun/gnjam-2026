@tool
class_name MemeSprite
extends Sprite2D
## 播放猫 meme 序列帧图。assets/memes/ 和 assets/cats/ 两个文件夹里的都能用，名字怎么写见 meme_lib.gd。
## 用法：var cat := MemeSprite.create("popcat", 150.0); add_child(cat)
## 摆在场景里：加一个 Sprite2D 节点，把这个脚本挂上去，在检查器的 Meme 一栏选素材名字，
##   然后像普通图片一样拖动、缩放、旋转就行（贴图和帧数会自动填好）。
##   默认按原动图速度循环播放；
##   set_progress(p)  自己控制播到哪（p 取 0~1，可以用拍数驱动，让动画跟着音乐走）；
##   play_once(秒)    从头放一遍后停回第一帧（比如“舔一下”）；
##   flash_frame(帧, 秒)  临时切到某一帧再切回来（比如 popcat 张嘴）。

enum Mode { LOOP, MANUAL, ONCE }

## 素材的名字（下拉里列出了全部可用的；写法见 meme_lib.gd）。选了之后贴图和帧数自动填好。
@export var meme := "":
	set(value):
		meme = value
		_apply()
## MANUAL / ONCE 模式下平时停在哪一帧
@export var idle_frame := 0

var frame_count := 1
var fps := 10.0
var mode: int = Mode.LOOP

var _t := 0.0
var _once_duration := 0.5
var _flash_left := 0.0


## key 是素材的名字，比如 "popcat"、"maxwell"、"cats/oiia"；height 是显示出来的高度（像素）
static func create(key: String, height: float) -> MemeSprite:
	var s := MemeSprite.new()
	s.meme = key
	if s.texture:
		s.scale = Vector2.ONE * (height / (s.texture.get_height() / float(s.vframes)))
	return s


## 按 meme 的名字把贴图、横竖格数、帧数、速度填好
func _apply() -> void:
	if meme == "":
		return
	var info := MemeLib.find(meme)
	if info.is_empty():
		push_error("找不到猫 meme 素材：%s（可用的名字见 MemeLib.keys()）" % meme)
		return
	texture = load(info.path)
	hframes = info.cols
	vframes = info.rows
	frame_count = info.frames
	fps = info.fps
	frame = mini(frame, frame_count - 1)
	mode = Mode.MANUAL if frame_count == 1 else Mode.LOOP


func _validate_property(property: Dictionary) -> void:
	if property.name == "meme":  # 检查器里给出素材名字的下拉列表
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(MemeLib.keys())


func _notification(what: int) -> void:
	# 保存场景前回到静止帧，免得把播到一半的那一帧存进文件
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		frame = clampi(idle_frame, 0, frame_count - 1)


func set_progress(p: float) -> void:
	mode = Mode.MANUAL
	frame = mini(int(fposmod(p, 1.0) * frame_count), frame_count - 1)


func play_once(duration: float = 0.5) -> void:
	mode = Mode.ONCE
	_once_duration = duration
	_t = 0.0


func flash_frame(which: int, seconds: float = 0.12) -> void:
	mode = Mode.MANUAL
	frame = clampi(which, 0, frame_count - 1)
	_flash_left = seconds


func _process(delta: float) -> void:
	match mode:
		Mode.LOOP:
			_t += delta
			frame = int(_t * fps) % frame_count
		Mode.ONCE:
			_t += delta
			if _t >= _once_duration:
				mode = Mode.MANUAL
				frame = idle_frame
			else:
				frame = mini(int(_t / _once_duration * frame_count), frame_count - 1)
		Mode.MANUAL:
			if _flash_left > 0.0:
				_flash_left -= delta
				if _flash_left <= 0.0:
					frame = idle_frame
