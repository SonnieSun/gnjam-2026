extends Control
## 片尾字幕：星空背景上，字幕像星球大战那样从画面底边往远处滚走；名单后面跟着一张图（猫猫），和字幕在同一块平面上一起滚，
## 图滚到画面中间时停住。
## 字幕的内容、字体、颜色、图，都摆在 scenes/credits.tscn 里（TextView/Text 下面的那些 Label 和最后的 Photo），
## 这里只负责滚和淡入淡出。想加一行字：在 TextView/Text 里复制一个 Label 改字就行。
##
## 游戏打完进来的这一次：游戏里还在放的音乐（康康舞曲）先淡出，然后片尾曲（ending_song，慢版康康舞曲）和字幕一起开始，
## 字幕滚到停住的那一刻正好是片尾曲最后一个音（crawl_seconds 就是从曲子开头到最后一个音的秒数，
## 曲子换了要跟着改，见 tools/music_gen/make_ending_song.py 打出来的 "last note lands at"）。
## 停住之后不再自己走：过一会儿底下出现 prompt_text，按空格回主菜单。
## 按住打击键（空格等）字幕快进（曲子照常放）；任何时候按 Esc 直接回主菜单。

## 字幕从冒出来到停住用几秒（= 片尾曲从开头到最后一个音）
@export var crawl_seconds := 26.66
## 开头先黑着等几秒再开始滚（游戏里没有音乐在放时；有的话等它淡出完）
@export var start_delay := 0.8
## 游戏里的音乐用几秒淡出
@export var music_fade := 1.2
## 片尾曲（只放一遍，不循环）和它的音量
@export var ending_song: AudioStream
@export var song_db := 0.0
## 按住打击键时快几倍
@export var fast_forward := 4.0
## 滚到多少停住（1 = 最下面的图刚好整张冒出底边；再大 = 它往远处走得更远、更小）
@export var scroll_end := 1.06
## 滚完之后停几秒自动回主菜单（0 = 一直停着，等玩家按空格）
@export var hold_seconds := 0.0
## 停住之后过几秒出提示，提示写什么
@export var prompt_after := 1.6
@export var prompt_text := "PRESS SPACE TO END THE GAME"

@onready var _crawl: TextureRect = %Crawl
@onready var _text_view: SubViewport = %TextView
@onready var _prompt: Label = get_node_or_null(^"Prompt")

var _time := 0.0
var _scroll := 0.0
var _done_for := 0.0
var _leaving := false
var _rolling := false
var _song: AudioStreamPlayer
var _fade: Tween
## 快速退出版（从菜单的 Credit 按钮打开的）：一层盖在当前画面上，按任意键 / 点一下马上关掉这一层，
## 下面的菜单（和暂停着的游戏）原样还在。片尾（游戏打完）那次不开这个，还是上面说的规则；也不放片尾曲。
var quick_exit := false

const SCENE := "res://scenes/credits.tscn"


## 在 parent 上面盖一层快速退出版的字幕，返回那一层（关掉时它自己删掉）
static func open_overlay(parent: Node, layer := 120) -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.layer = layer
	cl.process_mode = Node.PROCESS_MODE_ALWAYS  # 游戏里开的菜单是暂停状态，字幕也要能动
	var c = load(SCENE).instantiate()
	c.quick_exit = true
	cl.add_child(c)
	parent.add_child(cl)
	return cl


func _ready() -> void:
	Judge.ensure_input()
	_crawl.texture = _text_view.get_texture()
	_set_scroll(0.0)
	if _prompt:
		_prompt.text = prompt_text
		_prompt.modulate.a = 0.0
	# 从黑里淡进来
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)
	if quick_exit:
		return
	_song = AudioStreamPlayer.new()
	_song.stream = ending_song
	_song.volume_db = song_db
	_song.bus = &"Music"  # 先定好总线（Settings 只改还在 Master 上的播放器）：跟着音乐音量走
	add_child(_song)
	_fade = create_tween()
	if Conductor.playing:
		_fade.tween_method(Settings.music_trim, 0.0, -50.0, music_fade)
	else:
		_fade.tween_interval(start_delay)
	_fade.tween_callback(_start_song)


## 游戏里的音乐停掉、总线音量还原，片尾曲和字幕一起开始
func _start_song() -> void:
	Conductor.stop()
	Settings.duck_music(false, 0.05)
	Settings.music_trim(0.0)
	if _song.stream:
		_song.play()
	_rolling = true


func _exit_tree() -> void:
	if not quick_exit:
		Settings.music_trim(0.0)  # 淡出途中按 Esc 走掉：总线别停在压低的音量上


func _process(delta: float) -> void:
	_time += delta
	if quick_exit and _time >= start_delay:
		_rolling = true
	if not _rolling:
		return
	var speed := fast_forward if Input.is_action_pressed(Judge.HIT_ACTION) and _scroll < scroll_end else 1.0
	_scroll = minf(_scroll + delta * speed * scroll_end / maxf(crawl_seconds, 0.1), scroll_end)
	_set_scroll(_scroll)
	if _scroll >= scroll_end:
		var was := _done_for
		_done_for += delta
		if not quick_exit and was < prompt_after and _done_for >= prompt_after:
			_show_prompt()
		if hold_seconds > 0.0 and _done_for >= hold_seconds:
			_leave()


## 停住之后底下的提示：淡进来，然后一直轻轻地一明一暗
func _show_prompt() -> void:
	if _prompt == null:
		return
	var t := _prompt.create_tween()
	t.tween_property(_prompt, "modulate:a", 1.0, 0.6)
	t.tween_callback(func() -> void:
		var loop := _prompt.create_tween().set_loops()
		loop.tween_property(_prompt, "modulate:a", 0.45, 0.9).set_trans(Tween.TRANS_SINE)
		loop.tween_property(_prompt, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE))


func _set_scroll(v: float) -> void:
	var mat := _crawl.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter(&"scroll", v)


## 快速退出版：任意键 / 鼠标键按下就关，事件吞掉，下面的菜单和暂停转盘（Esc）都收不到
func _input(event: InputEvent) -> void:
	if not quick_exit:
		return
	var pressed := (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) \
			and event.is_pressed() and not event.is_echo()
	if pressed or event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
	if pressed and _time > 0.15:  # 刚打开那一下（点 Credit 的那次）不算
		_leave()


func _unhandled_input(event: InputEvent) -> void:
	if quick_exit:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		_leave()
	elif _scroll >= scroll_end and _done_for >= prompt_after and (event.is_action_pressed(Judge.HIT_ACTION)
			or (key and key.pressed and not key.echo and key.physical_keycode == KEY_SPACE)):
		_leave()


## 淡出，回主菜单
func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	if quick_exit:
		# 快速退出版：淡出后把盖上来的那一层删掉，回到原来的菜单
		var q := create_tween()
		q.tween_property(self, "modulate:a", 0.0, 0.25)
		q.tween_callback(get_parent().queue_free if get_parent() is CanvasLayer else queue_free)
		return
	if _fade:
		_fade.kill()
	Conductor.stop()
	Settings.music_trim(0.0)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.5)
	if _song and _song.playing:
		t.parallel().tween_property(_song, "volume_db", song_db - 40.0, 0.5)
	t.tween_callback(get_tree().change_scene_to_file.bind(Levels.MENU_SCENE))
