class_name Y2KStyle
extends RefCounted
## 试验：给 3D 关卡套上“千禧年主机”的画面（shader 来自 y2k_retro_kit，放在 assets/shaders/y2k/）。
## 思路照那份资料里写的：复古的画面，现代的光。
##   1. 3D 画面只渲染 480 线、不抗锯齿，再切成 16 位色加抖动，放大成方像素（era_output）
##      Y2K_JPEG 风格还会先过一遍 JPEG 压缩，出现块状和色彩渗漏（era_jpeg_encode）
##   2. 模型换成带清漆高光的亮面塑料；玻璃罩换成边缘发亮的玻璃（glass_aero）；飞碟的光束换成光柱（light_beam）
##   3. 灯光用现代的：软阴影、环境光遮蔽、泛光、ACES 色调
##   4. 整个画面做一次分离色调调色（theme_grade）：暗部偏靛蓝，亮部偏暖
##   5. 屏幕边缘一圈旋转的彩虹（fever_rainbow），积累条越满越明显，打中时闪一下
## 和漫画风格一样不改场景文件，运行时临时换上，切走就全部恢复。
## 参数都在下面的常量和 _make_xxx 函数里，各个 shader 参数的含义见 shader 文件开头的注释。

const ERA_OUTPUT := preload("res://assets/shaders/y2k/era_output.gdshader")
const JPEG_ENCODE := preload("res://assets/shaders/y2k/era_jpeg_encode.gdshader")
const THEME_GRADE := preload("res://assets/shaders/y2k/theme_grade.gdshader")
const GLASS := preload("res://assets/shaders/y2k/glass_aero.gdshader")
const FEVER := preload("res://assets/shaders/y2k/fever_rainbow.gdshader")
const BEAM := preload("res://assets/shaders/y2k/light_beam.gdshader")

## 3D 画面渲染多少线（那个年代的 VGA 输出是 480）
const LINES := 480
## JPEG 质量（越低块越重）
const JPEG_QUALITY := 30.0
## 边缘彩虹最亮到多少（0 = 不要彩虹）
const FEVER_MAX := 0.7

const STATE := &"_y2k_state"
const ORIGINAL := &"_y2k_original_material"


static func is_active(section: Node) -> bool:
	return section.has_meta(STATE)


## 套上（jpeg = 要不要 JPEG 压缩感）。view / viewport / camera / world / overlay 是 3D 关卡的那几个节点。
static func apply(section: Node2D, view: SubViewportContainer, viewport: SubViewport,
		camera: Camera3D, world: Node3D, overlay: Node2D, jpeg: bool) -> void:
	restore(section, view, viewport, camera, world)
	var env := camera.environment
	var sun := viewport.get_node_or_null("Sun") as DirectionalLight3D
	var state := {
		"stretch": view.stretch, "msaa": viewport.msaa_3d, "aa": viewport.screen_space_aa,
		"tonemap": env.tonemap_mode, "glow": env.glow_enabled, "ssao": env.ssao_enabled,
		"sky": env.sky, "reflect": env.reflected_light_source,
		"white": env.tonemap_white, "exposure": env.tonemap_exposure,
		"glow_intensity": env.glow_intensity, "glow_threshold": env.glow_hdr_threshold,
		"shadow": sun.shadow_enabled if sun else false,
		"nodes": [],
		# 彩虹是“加亮”叠上去的，背景越亮越容易把画面洗白，所以亮背景的镜头里自动调弱
		"fever_scale": clampf(1.15 - env.background_color.get_luminance() * 1.3, 0.06, 1.0),
	}
	section.set_meta(STATE, state)

	# 1. 低分辨率、不抗锯齿；原来的显示藏起来，换成下面的 EraScreen 来显示
	var screen := Vector2(view.size)
	view.stretch = false
	view.self_modulate.a = 0.0  # 不能直接隐藏，隐藏了里面的 3D 就不渲染了
	viewport.size = Vector2i(ceili(LINES * screen.x / screen.y / 8.0) * 8, LINES)  # 宽取 8 的倍数，JPEG 要用
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED

	var era := ShaderMaterial.new()
	era.shader = ERA_OUTPUT
	era.set_shader_parameter("plain", viewport.get_texture())
	era.set_shader_parameter("jpeg", jpeg)
	era.set_shader_parameter("bits", Vector3(5, 6, 5) if not jpeg else Vector3(5, 5, 5))  # 16 位色
	era.set_shader_parameter("dither", 1.0 if not jpeg else 0.6)
	if jpeg:
		# JPEG 编码要单独一遍：一个只画 2D 的小视口
		var pass_vp := SubViewport.new()
		pass_vp.name = "Y2KJpegPass"
		pass_vp.disable_3d = true
		pass_vp.size = viewport.size
		pass_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var enc := ShaderMaterial.new()
		enc.shader = JPEG_ENCODE
		enc.set_shader_parameter("source", viewport.get_texture())
		enc.set_shader_parameter("source_smooth", viewport.get_texture())
		enc.set_shader_parameter("quality", JPEG_QUALITY)
		var enc_rect := _full_rect(enc, Vector2(viewport.size))
		enc_rect.position = Vector2.ZERO
		pass_vp.add_child(enc_rect)
		section.add_child(pass_vp)
		state.nodes.append(pass_vp)
		era.set_shader_parameter("coefs", pass_vp.get_texture())

	# 2D 这几层的顺序：EraScreen（3D 画面）-> Grade（调色）-> 原来的缩圈 -> Fever（彩虹）
	var era_rect := _full_rect(era, screen)
	era_rect.name = "Y2KEraScreen"
	var grade_rect := _full_rect(_make_grade(), screen)
	grade_rect.name = "Y2KGrade"
	var fever_rect := _full_rect(_make_fever(), screen)
	fever_rect.name = "Y2KFever"
	for r: ColorRect in [era_rect, grade_rect]:
		section.add_child(r)
		section.move_child(r, overlay.get_index())
		state.nodes.append(r)
	section.add_child(fever_rect)
	state.nodes.append(fever_rect)

	# 2. 材质
	var cache := {}
	for node in world.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var src := mi.material_override as StandardMaterial3D
		if src == null:
			continue
		var made: Material = null
		var unshaded := src.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		var see_through := src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		if not unshaded and not see_through:
			if not cache.has(src):
				cache[src] = _make_gloss(src)
			made = cache[src]
		elif unshaded and see_through and src.albedo_texture == null:
			var cone := mi.mesh as CylinderMesh
			if cone and cone.top_radius == 0.0:
				made = _make_beam(src, cone.height)   # 尖顶的半透明圆锥 = 光束
			else:
				made = _make_glass(src)               # 其他半透明的 = 玻璃
		if made:
			mi.set_meta(ORIGINAL, src)
			mi.material_override = made

	# 3. 现代的光
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0      # 越大高光越不容易爆成一片白
	env.tonemap_exposure = 0.85
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.2
	# 亮面材质要有东西可以反射：背景还是原来的纯色，反射用一片看不见的天空
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.16, 0.42)
	sky_mat.sky_horizon_color = Color(0.85, 0.82, 0.95)
	sky_mat.ground_horizon_color = Color(0.85, 0.82, 0.95)
	sky_mat.ground_bottom_color = Color(0.25, 0.2, 0.35)
	sky.sky_material = sky_mat
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	if sun:
		sun.shadow_enabled = true
		sun.shadow_blur = 1.0
		sun.light_angular_distance = 0.8


## 拿掉，恢复原样
static func restore(section: Node2D, view: SubViewportContainer, viewport: SubViewport,
		camera: Camera3D, world: Node3D) -> void:
	if not section.has_meta(STATE):
		return
	var state: Dictionary = section.get_meta(STATE)
	section.remove_meta(STATE)
	for n: Node in state.nodes:
		n.free()
	view.self_modulate.a = 1.0
	view.stretch = state.stretch
	viewport.msaa_3d = state.msaa
	viewport.screen_space_aa = state.aa
	var env := camera.environment
	env.tonemap_mode = state.tonemap
	env.tonemap_white = state.white
	env.tonemap_exposure = state.exposure
	env.glow_intensity = state.glow_intensity
	env.glow_hdr_threshold = state.glow_threshold
	env.glow_enabled = state.glow
	env.ssao_enabled = state.ssao
	env.sky = state.sky
	env.reflected_light_source = state.reflect
	var sun := viewport.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = state.shadow
	for node in world.find_children("*", "MeshInstance3D", true, false):
		if node.has_meta(ORIGINAL):
			(node as MeshInstance3D).material_override = node.get_meta(ORIGINAL)
			node.remove_meta(ORIGINAL)


## 每帧调用：边缘彩虹跟着积累条（gauge = 0~1）和打中的脉冲（pulse = 0~1）变
static func tick(section: Node2D, gauge: float, pulse: float) -> void:
	var fever := section.get_node_or_null("Y2KFever") as ColorRect
	if fever:
		var scale: float = section.get_meta(STATE).fever_scale
		(fever.material as ShaderMaterial).set_shader_parameter("opacity",
				clampf(FEVER_MAX * scale * (gauge * gauge * 0.8 + pulse * 0.2), 0.0, 1.0))


## 铺满屏幕、以屏幕中心为原点的色块（关卡的原点在屏幕中心）
static func _full_rect(mat: ShaderMaterial, size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.material = mat
	r.size = size
	r.position = -size / 2.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 亮面塑料 / 瓷：清漆高光 + 一点边缘光
static func _make_gloss(src: StandardMaterial3D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = src.albedo_color
	m.albedo_texture = src.albedo_texture
	m.roughness = 0.12
	m.metallic_specular = 0.7
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.04
	m.rim_enabled = true
	m.rim = 0.15
	m.rim_tint = 0.4
	m.cull_mode = src.cull_mode
	return m


static func _make_glass(src: StandardMaterial3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLASS
	var c := src.albedo_color
	m.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("face_alpha", 0.12)   # 正对着看有多透明
	m.set_shader_parameter("edge_alpha", 0.75)   # 边缘有多实
	m.set_shader_parameter("rim_glow", 0.25)
	return m


static func _make_beam(src: StandardMaterial3D, height: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BEAM
	var c := src.albedo_color
	m.set_shader_parameter("color", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("strength", 1.4)
	m.set_shader_parameter("height", height)
	m.set_shader_parameter("fade_start", 0.45)
	return m


## 分离色调：暗部推向靛蓝，亮部推向暖色
static func _make_grade() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = THEME_GRADE
	m.set_shader_parameter("shadow_tint", Vector3(0.25, 0.2, 0.75))
	m.set_shader_parameter("highlight_tint", Vector3(1.0, 0.8, 0.55))
	m.set_shader_parameter("shadow_amount", 0.14)
	m.set_shader_parameter("highlight_amount", 0.08)
	m.set_shader_parameter("saturation", 1.1)
	m.set_shader_parameter("contrast", 1.08)
	return m


static func _make_fever() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FEVER
	m.set_shader_parameter("opacity", 0.0)
	return m
