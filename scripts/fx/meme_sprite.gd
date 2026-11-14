@tool
class_name MemeSprite
extends Sprite2D
## 播放猫 meme 序列帧图。assets/memes/ 和 assets/cats/ 两个文件夹里的都能用，名字怎么写见 meme_lib.gd。
## 用法：var cat := MemeSprite.create("popcat", 150.0); add_child(cat)
##   默认按原动图速度循环播放；
##   set_progress(p)  自己控制播到哪（p 取 0~1，可以用拍数驱动，让动画跟着音乐走）；
##   play_once(秒)    从头放一遍后停回第一帧（比如“舔一下”）；
##   flash_frame(帧, 秒)  临时切到某一帧再切回来（比如 popcat 张嘴）。

enum Mode { LOOP, MANUAL, ONCE }

var frame_count := 1
var fps := 10.0
var mode: int = Mode.LOOP
## MANUAL / ONCE 模式下平时停在哪一帧
var idle_frame := 0

var _t := 0.0
var _once_duration := 0.5
var _flash_left := 0.0


## key 是素材的名字，比如 "popcat"、"maxwell"、"cats/oiia"；height 是显示出来的高度（像素）
static func create(key: String, height: float) -> MemeSprite:
	var s := MemeSprite.new()
	var info := MemeLib.find(key)
	if info.is_empty():
		push_error("找不到猫 meme 素材：%s（可用的名字见 MemeLib.keys()）" % key)
		return s
	s.texture = load(info.path)
	s.hframes = info.cols
	s.vframes = info.rows
	s.frame_count = info.frames
	s.fps = info.fps
	s.scale = Vector2.ONE * (height / (s.texture.get_height() / float(info.rows)))
	if s.frame_count == 1:
		s.mode = Mode.MANUAL
	return s


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
