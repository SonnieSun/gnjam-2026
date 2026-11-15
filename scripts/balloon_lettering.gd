@tool
extends Label3D
## Keeps the editable font text as layout metadata; renders inflated foil meshes.
const METRICS_PATH := "res://assets/fonts/candy_gem/balloon/metrics.json"
const FOIL := preload("res://assets/menu/balloon_foil.gdshader")
var _foil: ShaderMaterial
var _last_text := ""
var _last_size := 0

func _ready() -> void:
	_rebuild()

func _process(_delta: float) -> void:
	if text != _last_text or font_size != _last_size:
		_rebuild()
	if _foil:
		_foil.set_shader_parameter("brightness", modulate.r)
	modulate.a = 0.0

func _rebuild() -> void:
	_last_text = text
	_last_size = font_size
	for child in get_children():
		if child.name.begins_with("FoilGlyph"):
			remove_child(child)
			child.queue_free()
	if not FileAccess.file_exists(METRICS_PATH):
		return
	var metrics: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(METRICS_PATH))
	_foil = ShaderMaterial.new()
	_foil.shader = FOIL
	var unit := float(font_size) / 256.0 * pixel_size
	var width := 0.0
	for c in text:
		width += float(metrics[c].advance) if metrics.has(c) else 80.0
	var cursor := -width / 2.0
	# Label3D's original atlas becomes the dark recessed silhouette underneath.
	transparency = 1.0
	modulate.a = 0.0
	var socket_material := StandardMaterial3D.new()
	socket_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	socket_material.albedo_color = Color(0.055, 0.009, 0.085)
	socket_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for c in text:
		if not metrics.has(c):
			cursor += 80.0
			continue
		var mesh := MeshInstance3D.new()
		mesh.name = "FoilGlyph%d" % get_child_count()
		mesh.mesh = load("res://assets/fonts/candy_gem/balloon/%s.obj" % c)
		mesh.material_override = _foil
		mesh.scale = Vector3.ONE * unit
		# Font baseline is 216 pixels in a 280-pixel line box.
		mesh.position = Vector3((cursor + 8.0) * unit, -76.0 * unit, -0.018)
		add_child(mesh)
		var socket := MeshInstance3D.new()
		socket.name = "FoilGlyphSocket%d" % get_child_count()
		socket.mesh = mesh.mesh
		socket.material_override = socket_material
		socket.scale = Vector3(unit * 1.10, unit * 1.08, unit * 0.045)
		socket.position = mesh.position - Vector3(float(metrics[c].width) * unit * 0.05, 6.0 * unit, 0.006)
		add_child(socket)
		cursor += float(metrics[c].advance)
