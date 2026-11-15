@tool
class_name RetroTVScreen
extends Node3D
## 挂在 retro_tv.glb 实例的根节点（TV）上。
## 每台电视各自一份屏幕材质，画面、亮度、外壳颜色都能在 Inspector 或代码里随时改。
## screen_texture 可以是任何 Texture2D：普通图片、AnimatedTexture、
## SubViewport 的 ViewportTexture、VideoStreamPlayer.get_video_texture()。

@export var screen_texture: Texture2D:
	set(v):
		screen_texture = v
		_apply_screen()
## 点亮时的发光强度；0 = 不发光。
@export_range(0.0, 8.0, 0.05) var glow := 1.0:
	set(v):
		glow = v
		_apply_screen()
## 屏幕亮度（乘到画面上）。熄灭时可以调暗而不换图。
@export var screen_tint := Color.WHITE:
	set(v):
		screen_tint = v
		_apply_screen()
@export var shell_color := Color(1.0, 0.56, 0.76):
	set(v):
		shell_color = v
		_apply_tints()
@export var controls_color := Color(0.93, 0.40, 0.62):
	set(v):
		controls_color = v
		_apply_tints()

var _screen_mat: StandardMaterial3D


func _ready() -> void:
	_apply_screen()
	_apply_tints()


## 代码里换画面：tv.set_screen(tex) 或 tv.set_screen(tex, 2.0)
func set_screen(tex: Texture2D, glow_amount: float = -1.0) -> void:
	screen_texture = tex
	if glow_amount >= 0.0:
		glow = glow_amount


func _apply_screen() -> void:
	if not is_inside_tree():
		return
	var mi := get_node_or_null("Screen") as MeshInstance3D
	if mi == null:
		return
	if _screen_mat == null:
		var src := mi.get_active_material(0) as StandardMaterial3D
		_screen_mat = src.duplicate() if src else StandardMaterial3D.new()
		mi.set_surface_override_material(0, _screen_mat)
		if screen_texture == null:
			screen_texture = _screen_mat.albedo_texture  # 默认画面
	_screen_mat.albedo_texture = screen_texture
	_screen_mat.albedo_color = screen_tint
	_screen_mat.emission_enabled = glow > 0.0
	_screen_mat.emission_texture = screen_texture
	_screen_mat.emission = screen_tint  # 发光颜色 × 画面贴图
	_screen_mat.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	_screen_mat.emission_energy_multiplier = glow


func _apply_tints() -> void:
	if not is_inside_tree():
		return
	_tint("Shell", shell_color)
	_tint("Controls", controls_color)
	_tint("ControlsDots_L", controls_color)
	_tint("ControlsDots_R", controls_color)


func _tint(node_name: String, col: Color) -> void:
	var mi := get_node_or_null(node_name) as MeshInstance3D
	if mi == null:
		return
	var m := mi.get_surface_override_material(0) as StandardMaterial3D
	if m == null:
		var src := mi.get_active_material(0) as StandardMaterial3D
		if src == null:
			return
		m = src.duplicate()
		mi.set_surface_override_material(0, m)
	m.albedo_color = col
