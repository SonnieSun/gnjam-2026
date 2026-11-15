extends Node3D
## Blender v8 的材质颜色动画逐帧采样；独立于节拍、长按和关卡进度持续循环。
const DATA_PATH := "res://stages/tv_wall/washer/washing_lightband_animation.json"
## HDR 自发光强度；配合 Level 4 的 Glow，作为清晰的节奏判定线。
@export_range(0.0, 4.0, 0.05) var emission_energy := 0.45
var _elapsed := 0.0
var _fps := 24.0
var _frame_count := 24
var _bands: Array[Dictionary] = []

func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_fps = float(data.fps)
	_frame_count = int(data.end_frame) - int(data.start_frame)
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var material := source.duplicate() as StandardMaterial3D
			mesh.set_surface_override_material(surface, material)
			if not data.materials.has(source.resource_name):
				material.metallic = 0.0
				material.roughness = 1.0
				continue
			material.emission_enabled = true
			# 灯带自身发光，不再叠加场景强灯照明，避免原有粉紫色被冲成白色。
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.emission_energy_multiplier = emission_energy
			_bands.append({"material": material, "colors": data.materials[source.resource_name]})
	_apply_frame(0)

func _process(delta: float) -> void:
	_elapsed = fposmod(_elapsed + delta, float(_frame_count) / _fps)
	_apply_frame(int(floor(_elapsed * _fps)) % _frame_count)

func _apply_frame(frame: int) -> void:
	for band in _bands:
		var rgba: Array = band.colors[frame]
		# Blender 节点值为线性颜色，Godot 的 albedo_color 使用 sRGB。
		var color := Color(rgba[0], rgba[1], rgba[2], rgba[3]).linear_to_srgb()
		band.material.albedo_color = color
		band.material.emission = color
