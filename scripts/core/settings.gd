extends Node
## 玩家设置（autoload 名：Settings）：音量（总 / 音乐 / 音效）、全屏。存在 user://settings.cfg，
## 和延迟校准（Conductor 的 [latency] 一节）放在同一个文件里，互相不覆盖。
## 设置面板在 ui/settings_panel.tscn（主菜单的 SETTINGS 打开它）。
##
## 音频总线：启动时建两条总线 Music、SFX，都送进 Master（Master 上的限幅器、fever 混响照样作用在全部声音上）。
## 播放器不用一个个去改：凡是进了场景树的 AudioStreamPlayer（2D / 3D 也算），
## 属于 Music 或 Conductor（叠轨音乐、伴奏、过门、节拍器）的走 Music，其余（按键鼓声、打中喵、菜单音效……）走 SFX。
## 自己在场景里把 bus 设成别的总线的播放器不会被改。

signal changed

const PATH := "user://settings.cfg"
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
## 三个音量滑条对应的总线
const VOLUME_BUSES: Array[StringName] = [&"Master", MUSIC_BUS, SFX_BUS]

## 音量（0 ~ 1 线性，0 = 静音）
var volumes := {&"Master": 1.0, MUSIC_BUS: 1.0, SFX_BUS: 1.0}
var fullscreen := false


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_load()
	apply()
	get_tree().node_added.connect(_route)
	_route_tree(get_tree().root)


## 改一个总线的音量（0 ~ 1），马上生效并存盘
func set_volume(bus: StringName, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)
	save()
	changed.emit()


func get_volume(bus: StringName) -> float:
	return volumes.get(bus, 1.0)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_window()
	save()
	changed.emit()


## 判定延迟（毫秒）。存在 Conductor 那一节里，校准界面测出来的也是它。
func set_input_offset_ms(ms: float) -> void:
	Conductor.input_offset_sec = ms / 1000.0
	Conductor.save_offsets()
	changed.emit()


func get_input_offset_ms() -> float:
	return Conductor.input_offset_sec * 1000.0


## 网页版不能自己切全屏（浏览器要求用户点了才行），也不需要这一项
func can_fullscreen() -> bool:
	return not OS.has_feature("web")


func apply() -> void:
	for bus in VOLUME_BUSES:
		_apply_volume(bus)
	_apply_window()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # 保留别的设置（延迟校准）
	for bus in VOLUME_BUSES:
		cfg.set_value("audio", String(bus).to_lower(), volumes[bus])
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for bus in VOLUME_BUSES:
		volumes[bus] = clampf(float(cfg.get_value("audio", String(bus).to_lower(), 1.0)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("video", "fullscreen", false))


func _apply_volume(bus: StringName) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var v: float = volumes[bus]
	AudioServer.set_bus_mute(i, v <= 0.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))


func _apply_window() -> void:
	if not can_fullscreen() or DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


func _ensure_bus(bus: StringName) -> void:
	if AudioServer.get_bus_index(bus) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus)
	AudioServer.set_bus_send(i, &"Master")


func _route_tree(node: Node) -> void:
	_route(node)
	for child in node.get_children():
		_route_tree(child)


func _route(node: Node) -> void:
	if not (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D):
		return
	if node.bus != &"Master":
		return  # 场景里自己指定了总线的，不动
	var music := get_node_or_null(^"/root/Music")
	var conductor := get_node_or_null(^"/root/Conductor")
	var is_music := (music and music.is_ancestor_of(node)) or (conductor and conductor.is_ancestor_of(node))
	node.bus = MUSIC_BUS if is_music else SFX_BUS
