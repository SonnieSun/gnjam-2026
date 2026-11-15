class_name TvWallIntroStage
extends Node
## 电视墙关开场的 3D 舞台：黑底上一台洗衣机，周围一圈一开始看不见的电视（TvGrid）。
## 洗衣机舱门里正中央是一张填满舱门的猫脸（在机身里面），原地旋转：单点转一小段，长按一直转、越转越快。
## 按 Kisa 要求没有：衣物贴图、点击时的镜头鼓包、水滴、平时的抖动；只有发电（亮电视阶段的长按）才震动。
## 推进只看「完整按完的长按」次数：
##   前 zoom_holds 次：每次镜头拉远一档（按住的过程中就慢慢拉，松手失败则退回）；最后一档洗衣机在画面中下方。
##   之后每次：洗衣机发电，震动停下来时亮 tvs_per_hold 台电视，直到全部亮起。
## 关卡脚本 TvWallIntroSection 每帧调 update()，判定时调 tap() / hold_begin() / hold_end()。参数都在 Stage 节点的 Inspector 里。

const MACHINE := preload("res://stages/tv_wall/washer/washing_machine.tscn")
const HEAD := preload("res://stages/tv_wall/washer/CATS_head_only.fbx")
const CAT_TEXTURE := preload("res://stages/shared/cat/cat_basecolor_512.png")
const LENS_SHADER := preload("res://stages/tv_wall/washer/washing_hit_lens.gdshader")

@export_group("镜头")
@export var camera_fov := 40.0
## 每一档镜头：[看向的点, 画面上下能装下多高（米）]。第 0 档是开头的大特写，之后每完成一次长按往后一档。
## 洗衣机宽 0.6、高 0.84，中心在原点。
@export var shots: Array = [
	[Vector3(0.0, 0.03, 0.25), 0.95],
	[Vector3(0.0, 0.08, 0.25), 1.35],
	[Vector3(0.0, 0.2, 0.25), 1.8],
	[Vector3(0.0, 0.36, 0.25), 2.4],
]
## 镜头追上目标的快慢
@export var camera_follow := 5.0

@export_group("画面风格")
## 进这一关时默认用哪种漫画滤镜（名字见 scripts/fx/comic_style.gd 的 NAMES；OFF = 原样）。游戏里按 C 轮流切换。
## Y2K 那两档只对框架的 3D 小关有效，这里切到它们时显示原样。
@export var default_look := "HALFTONE"

@export_group("洗衣机舱门")
## 舱门洞口中心和半径（洗衣机自己的坐标，照原洗衣机关的数值）
@export var opening_center := Vector3(0.004025, 0.02949, 0.2456)
@export var opening_radius := 0.145
## 判定圈画在门框上
@export var judgement_center := Vector3(0.004025, 0.02949, 0.2495)
@export var judgement_radius := 0.176

@export_group("猫脸")
## 猫脸（按宽和高里较短的一边算）是洞口直径的几倍；>= 1 时脸填满舱门，多出来的边角被机身挡住
@export var head_diameter_ratio := 1.05
## 猫脸最前面离洞口平面多远（米，往机身里面）
@export var head_inset := 0.01
## 猫脸朝向（度），导入的模型不正对镜头时在这里调
@export var head_rotation := Vector3.ZERO
## 没按的时候也一直慢慢转（度 / 秒）
@export var head_idle_speed_degrees := 30.0
## 单点一下转多快（度 / 秒）、转多久（秒）
@export var head_click_speed_degrees := 360.0
@export var head_click_duration := 0.25
## 长按按到后面最快转多快（度 / 秒）
@export var head_hold_max_speed_degrees := 1080.0
## 顺时针转
@export var clockwise := true

@export_group("结尾：进屏幕")
## 没有下一个小关时屏幕上显示的图（有下一个小关就直接显示它的实时画面）
@export var finale_image: Texture2D
## 其他电视往外散开多远（米）
@export var scatter_distance := 5.0
## 洗衣机往哪边退场
@export var machine_exit := Vector3(0.0, -3.0, 0.0)

@export_group("跟拍运镜")
## 镜头跟着音乐动：每 change_beats 拍（默认一小节）在小节开头换一个随机的角度和远近（很快滑过去），
## 每一拍再往里推一下。随机是按小节定的，每次玩都一样。判定圈跟着洗衣机门在画面上的位置走，不会对不上
@export var beat_camera := true
@export var beat_change_beats := 4.0
## 换角度用几拍滑过去
@export var beat_ease_beats := 0.6
## 随机角度的范围（度）：左右绕、上下绕、歪头
@export var beat_yaw_degrees := 14.0
@export var beat_pitch_degrees := 8.0
@export var beat_roll_degrees := 5.0
## 随机远近（镜头距离的倍数，小于 1 = 推近）
@export var beat_zoom_range := Vector2(0.85, 1.1)
## 每一拍往里推多少（0.05 = 推近 5%）
@export_range(0.0, 0.3) var beat_zoom_punch := 0.05

@export_group("朋克运镜")
## 跟拍运镜随着进展越来越疯（进展 = 按完了几次长按 / 一共要按几次）。关掉 = 一直是上面"跟拍运镜"的强度
@export var punk_camera := true
## 到最后，随机角度的幅度乘到这么多倍
@export var punk_angle_scale := 1.5
## 到最后，远近在这个范围里一近一远地跳（镜头距离的倍数）
@export var punk_zoom_range := Vector2(0.68, 1.3)
## 进展过了这两个比例，换镜头从每小节一次变成每 2 拍一次、每拍一次；换的时候也越来越"硬"（几乎是切）
@export_range(0.0, 1.0) var punk_half_bar_at := 0.3
@export_range(0.0, 1.0) var punk_every_beat_at := 0.7
## 打中、长按按完的那一下镜头猛地推近多少（占距离的比例），很快弹回去；进展越靠后推得越狠
@export_range(0.0, 0.6) var punk_hit_zoom := 0.14
## 规矩：玩家没在操作的时候镜头不乱动。最后一次按键 / 按住之后过了 idle_hold_seconds 秒，镜头用 idle_settle_seconds 秒
## 回到正面停住（角度、远近、每拍推的那一下都停），玩家再按才重新动起来。0 = 不管，一直按拍子动
@export var idle_hold_seconds := 0.8
@export var idle_settle_seconds := 0.6
## 镜头不管怎么动，洗衣机都基本在画面中间：镜头一直对着洗衣机（舱门）和原来那一档的取景点之间的一点，
## 推近的时候完全对准洗衣机。1 = 永远正对洗衣机，0 = 只按原来的取景（拉远后洗衣机在画面中下方）
@export_range(0.0, 1.0) var punk_keep_centered := 0.6

@export_group("开场：猫飞进洗衣机")
## 开场预备拍里，猫头从画面上方转着飞进舱门，正好在第一拍落进去（几拍；0 = 不放，猫一开始就在里面）
@export var fly_in_beats := 3.0
## 从哪里飞来（洗衣机坐标，画面上方靠近镜头）、中途经过哪里
@export var fly_in_from := Vector3(-0.35, 0.75, 1.15)
@export var fly_in_via := Vector3(0.3, 0.45, 0.8)
## 飞的时候多大（落进去才变回填满舱门）、转多快（度 / 秒）
@export var fly_in_scale := 0.6
@export var fly_in_spin_degrees := 900.0

@export_group("发电")
## 发电时画面震动最大多少像素
@export var holding_shake_pixels := 5.0
## 发电时洗衣机机身抖多少（米）
@export var machine_shake := 0.006
## 前几次长按用来拉远镜头（不震动）
@export var zoom_holds := 3
## 之后每次长按亮几台电视
@export var tvs_per_hold := 2
## 两台电视先后亮起隔几秒
@export var light_gap := 0.18

var world: SubViewport
var camera: Camera3D
var _beat := 0.0
var grid: TvGrid
## 已经完整按完几次长按
var holds_done := 0
## 全亮之后那次长按按完了，等关卡脚本调 start_finale()
var finale_pending := false

var _sprite: Sprite2D
var _machine: Node3D
var _cat: Node3D
var _lens: MeshInstance3D
var _lens_mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _zoom := 0.0
var _hold_progress := -1.0  # < 0 = 没在长按
var _hold_seconds := 0.0
var _head_angle := 0.0
var _head_click := 0.0
var _release_age := 99.0
var _release_shake := 0.0
var _pending_lights: Array[Dictionary] = []  # {"tv": 序号, "wait": 还要等几秒}
var _just_lit: Array[int] = []
var _beat_pulse := 0.0
var _look := -1
var _env: Environment
var _finale_hold := false
var _finale_from := INF
var _finale_to := INF
var _finale_cam: Transform3D
var _center_tv := 0
var _machine_home := Vector3.ZERO
var _cat_home := Vector3.ZERO
var _flying := false
var _landed := false
var _hit_punch := 0.0
var _idle := 99.0  # 玩家多久没操作了（秒）
var _active := 0.0  # 镜头现在动几成（0 = 停在正面）

## 猫开始往洗衣机里飞（seconds 秒后落进去）/ 落进去了
signal cat_flying(seconds: float)
signal cat_landed


func setup(host: Node2D) -> void:
	_rng.randomize()
	world = SubViewport.new()
	world.size = Vector2i(host.get_viewport_rect().size)
	world.own_world_3d = true
	world.msaa_3d = Viewport.MSAA_4X
	host.add_child(world)
	_sprite = Sprite2D.new()
	_sprite.texture = world.get_texture()
	_sprite.z_index = -1
	host.add_child(_sprite)

	_build_env()
	_build_machine()
	grid = TvGrid.new()
	world.add_child(grid)
	camera = Camera3D.new()
	camera.fov = camera_fov
	camera.near = 0.02
	world.add_child(camera)
	camera.current = true
	_build_lens()
	if ComicStyle.style == ComicStyle.OFF:
		ComicStyle.set_by_name(default_look)
	_apply_look()
	_place_camera(0.0)


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.88, 1.0)
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_intensity = 0.9
	env.glow_bloom = 0.2
	we.environment = env
	_env = env
	world.add_child(we)
	# 只照洗衣机的一盏主灯（范围小，照不到远处的电视）
	var key := SpotLight3D.new()
	key.position = Vector3(0.5, 0.75, 1.5)
	key.light_color = Color(1.0, 0.96, 0.9)
	key.light_energy = 1.8
	key.spot_range = 2.4
	key.spot_angle = 26.0
	world.add_child(key)
	key.look_at(Vector3(0.0, 0.0, 0.2))
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.5, 0.2, 0.9)
	fill.light_color = Color(0.6, 0.75, 1.0)
	fill.light_energy = 0.5
	fill.omni_range = 1.6
	fill.light_specular = 0.0
	world.add_child(fill)


func _build_machine() -> void:
	_machine = MACHINE.instantiate() as Node3D
	# GLB 按材质拆分网格；读取表面材质供漫画滤镜使用，保留机身和门框各自的颜色
	for mi in _machine.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).get_active_material(0)
		if m:
			(mi as MeshInstance3D).material_override = m
	world.add_child(_machine)
	# 猫脸：外面一层 _cat 放在舱门正中央、负责原地旋转；里面一层把模型摆正、缩到填满舱门
	_cat = Node3D.new()
	_machine.add_child(_cat)
	var body := HEAD.instantiate() as Node3D
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		mesh.skeleton = NodePath("")
		mesh.skin = null
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = CAT_TEXTURE
		mat.roughness = 0.8
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # 猫脸不吃漫画滤镜，保持贴图原样
		mesh.material_override = mat
	var holder := Node3D.new()
	holder.rotation_degrees = head_rotation
	holder.add_child(body)
	_cat.add_child(holder)
	var box := TvWallRoom.measure(holder)
	var s := opening_radius * 2.0 * head_diameter_ratio / maxf(minf(box.size.x, box.size.y), 0.00001)
	holder.scale = Vector3.ONE * s
	holder.position = -(holder.transform.basis * box.get_center())
	# 整张脸都在机身里面：脸最前面比洞口平面再往里一点
	_cat.position = Vector3(opening_center.x, opening_center.y, opening_center.z - head_inset - box.size.z * s * 0.5)
	_cat_home = _cat.position
	# 舱门里面的灯，不然脸在机身里是黑的
	var inner := OmniLight3D.new()
	inner.position = Vector3(opening_center.x, opening_center.y, opening_center.z + 0.06)
	inner.light_color = Color(1.0, 0.97, 0.92)
	inner.light_energy = 0.6
	inner.omni_range = 0.3
	inner.light_specular = 0.0
	_machine.add_child(inner)


## 镜头前的一块全屏片：发电时的画面震动（用原洗衣机关的 shader，鼓包强度一直是 0）
func _build_lens() -> void:
	_lens_mat = ShaderMaterial.new()
	_lens_mat.shader = LENS_SHADER
	_lens_mat.render_priority = 127
	_lens_mat.set_shader_parameter("strength", 0.0)
	_lens = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_lens.mesh = quad
	_lens.material_override = _lens_mat
	_lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lens.extra_cull_margin = 16384.0
	_lens.position.z = -0.05
	_lens.visible = false
	camera.add_child(_lens)


# ---------------- 给关卡脚本的 ----------------

## 进展（0~1）：按完了几次长按 / 一共要按几次（拉远镜头的几次 + 把电视全点亮的几次）
func progress() -> float:
	var total := zoom_holds + ceili(float(grid.count()) / maxi(tvs_per_hold, 1))
	return clampf(float(holds_done) / maxi(total, 1), 0.0, 1.0)


## 单点打中：猫脸转一小段
func tap() -> void:
	_head_click = head_click_duration
	_hit_punch = 1.0
	_idle = 0.0


## 长按开头打中，开始按住
func hold_begin() -> void:
	_hold_progress = 0.0
	_finale_hold = all_lit() and not finale_pending and not finale_active()
	_hold_seconds = 0.0
	_head_click = 0.0


## 按住的过程中每帧告诉舞台按到了百分之几、按了几秒
func hold_update(progress: float, seconds: float) -> void:
	_hold_progress = clampf(progress, 0.0, 1.0)
	if _finale_hold:
		grid.flicker = _hold_progress
	_hold_seconds = seconds


## 长按结束。success = 完整按完。返回这次要亮的电视序号（没有就是空的）。
func hold_end(success: bool) -> Array[int]:
	_release_shake = _shake_envelope()
	_release_age = 0.0
	_hold_progress = -1.0
	var lit: Array[int] = []
	if _finale_hold:
		_finale_hold = false
		grid.flicker = 0.0
		finale_pending = success
		return lit
	if not success:
		return lit
	_hit_punch = 1.0
	holds_done += 1
	if holds_done <= zoom_holds:
		return lit
	var left := grid.unlit()
	for tv in _pending_lights:
		left.erase(tv.tv)
	for i in mini(tvs_per_hold, left.size()):
		# 先亮离洗衣机近的
		var best := 0
		for k in left.size():
			if grid.screen_center(left[k]).length() < grid.screen_center(left[best]).length():
				best = k
		lit.append(left[best])
		_pending_lights.append({"tv": left[best], "wait": i * light_gap})
		left.remove_at(best)
	return lit


## 是不是还在拉远镜头的阶段（还没开始亮电视）
func zooming_phase() -> bool:
	return holds_done < zoom_holds


func all_lit() -> bool:
	return grid.lit_count() >= grid.count()


## 这一帧刚亮起来的电视（关卡脚本拿去画闪电），读完就清掉
func take_just_lit() -> Array[int]:
	var out := _just_lit
	_just_lit = []
	return out


## 判定圈中心在 2D 画面上的位置（相对屏幕中心）
func ring_center() -> Vector2:
	return to_screen(_machine.to_global(judgement_center))


## 判定圈在 2D 画面上的半径（像素）
func ring_radius() -> float:
	var c := _machine.to_global(judgement_center)
	return (to_screen(c + camera.global_transform.basis.x * judgement_radius) - to_screen(c)).length()


func tv_screen_pos(i: int) -> Vector2:
	return to_screen(grid.screen_center(i))


func to_screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p) - Vector2(world.size) / 2.0


# ---------------- 每帧 ----------------

func update(beat: float, dt: float) -> void:
	var size := Vector2i(world.get_parent().get_viewport_rect().size)
	if world.size != size:
		world.size = size
	if _look != ComicStyle.style:
		_apply_look()
	_release_age += dt
	_beat_pulse = exp(-fposmod(beat, 1.0) * 5.0) if all_lit() else 0.0
	_update_lights(dt)
	grid.update(dt, _beat_pulse)
	_update_cat(dt)
	_update_fly_in(beat, dt)
	_hit_punch = maxf(_hit_punch - dt * 6.0, 0.0)
	_idle = 0.0 if _hold_progress >= 0.0 else _idle + dt
	var want := 1.0 if idle_hold_seconds <= 0.0 or _idle < idle_hold_seconds else 0.0
	_active = move_toward(_active, want, dt / maxf(idle_settle_seconds if want < _active else 0.15, 0.01))
	_update_shake()
	_beat = beat
	_update_camera(dt)
	if finale_active():
		_update_finale(beat)


func _update_lights(dt: float) -> void:
	for i in range(_pending_lights.size() - 1, -1, -1):
		var p: Dictionary = _pending_lights[i]
		p.wait -= dt
		if p.wait <= 0.0:
			grid.light_up(p.tv)
			_just_lit.append(p.tv)
			_pending_lights.remove_at(i)


## 猫脸原地旋转（绕正对镜头的轴）：单点转一小段；长按一直转，前一秒保持点击速度，之后越按越快
func _update_cat(dt: float) -> void:
	var travel := deg_to_rad(head_idle_speed_degrees) * dt
	if _hold_progress >= 0.0:
		var speed := lerpf(head_click_speed_degrees, maxf(head_hold_max_speed_degrees, head_click_speed_degrees),
				clampf((_hold_seconds - 1.0) / 1.5, 0.0, 1.0))
		travel = deg_to_rad(speed) * dt
	elif _head_click > 0.0:
		travel = deg_to_rad(head_click_speed_degrees) * minf(dt, _head_click)
		_head_click = maxf(_head_click - dt, 0.0)
	_head_angle = fposmod(_head_angle + travel * (-1.0 if clockwise else 1.0), TAU)
	_cat.rotation = Vector3(0.0, 0.0, _head_angle)


## 开场：猫头从画面上方转着飞进舱门（预备拍里，第一拍落进去），落进去洗衣机震一下
func _update_fly_in(beat: float, dt: float) -> void:
	if _landed or fly_in_beats <= 0.0:
		return
	if not Conductor.playing:
		_cat.visible = false  # 还没开始（两关之间的喘息）：洗衣机是空的，猫等开始了才飞进来
		return
	var t := (beat + fly_in_beats) / fly_in_beats
	if t >= 1.0:
		_landed = true
		_cat.position = _cat_home
		_cat.scale = Vector3.ONE
		if _flying:  # 真的飞过才算落地（从中间跳进这一关时不放）
			_release_shake = 1.0
			_release_age = 0.0
			_hit_punch = 1.0
			cat_landed.emit()
		return
	if not _flying and t > 0.0:
		_flying = true
		cat_flying.emit((1.0 - t) * fly_in_beats * Conductor.sec_per_beat())
	t = clampf(t, 0.0, 1.0)
	var e := t * t  # 越飞越快，砸进去
	var a := fly_in_from.lerp(fly_in_via, e)
	var b := fly_in_via.lerp(_cat_home, e)
	_cat.position = a.lerp(b, e)
	_cat.scale = Vector3.ONE * fly_in_scale
	_cat.rotation.z += deg_to_rad(fly_in_spin_degrees) * dt
	_cat.visible = t > 0.0


## 发电震动的强弱：只有亮电视阶段的长按才震。起按就有 70%，很快升到最大；松手后 0.2 秒收掉
func _shake_envelope() -> float:
	if _hold_progress >= 0.0:
		if zooming_phase():
			return 0.0
		return 0.7 + 0.3 * smoothstep(0.0, 0.25, _hold_progress)
	if not _landed:
		return 0.0
	return _release_shake * (1.0 - smoothstep(0.0, 0.2, _release_age))


func _update_shake() -> void:
	var e := _shake_envelope()
	_machine.position = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0.0) * machine_shake * e
	var t := Time.get_ticks_msec() / 1000.0
	var wave := Vector2(sin(t * TAU * 7.5 + 0.93) * 0.85 + sin(t * TAU * 13.0 + 0.93) * 0.15,
			sin(t * TAU * 9.2 - 0.64) * 0.85 + sin(t * TAU * 11.0 - 0.64) * 0.15)
	var shake := wave.limit_length(1.0) * holding_shake_pixels * e
	_lens_mat.set_shader_parameter("screen_offset", shake / Vector2(world.size))
	_lens.visible = shake.length_squared() > 0.000001


func _update_camera(dt: float) -> void:
	var target := float(mini(holds_done, zoom_holds))
	if _hold_progress >= 0.0 and holds_done < zoom_holds:
		target += _hold_progress
	_zoom = lerpf(_zoom, target, minf(1.0, dt * camera_follow))
	if not finale_active():
		_place_camera(_zoom)


func _place_camera(zoom: float) -> void:
	var last := shots.size() - 1
	var i := clampi(floori(zoom), 0, last)
	var j := mini(i + 1, last)
	var k := smoothstep(0.0, 1.0, clampf(zoom - i, 0.0, 1.0))
	var look: Vector3 = (shots[i][0] as Vector3).lerp(shots[j][0], k)
	var frame_h := lerpf(shots[i][1], shots[j][1], k)
	# 档位是按 16:9 的画面定的；画面更窄（比如 4:3）时把镜头再拉远一点，两边的电视才不会出画
	var vp := Vector2(world.size)
	frame_h *= maxf(1.0, (16.0 / 9.0) / maxf(vp.x / maxf(vp.y, 1.0), 0.1))
	var dist := frame_h * 0.5 / tan(deg_to_rad(camera_fov) * 0.5)
	camera.fov = camera_fov
	camera.position = look + Vector3(0.0, 0.0, dist)
	camera.rotation = Vector3.ZERO
	if beat_camera and _beat >= 0.0:
		var m := _beat_pose()
		if punk_camera:
			# 洗衣机保持在中间：对着洗衣机多一点；推得越近越要对准它，不然一推近它就出画了
			var keep := maxf(punk_keep_centered * progress(), clampf((1.0 - float(m.scale)) * 3.0, 0.0, 1.0))
			look = look.lerp(Vector3(opening_center.x, opening_center.y, look.z), keep)
		var orbit := Basis.from_euler(Vector3(deg_to_rad(m.pitch), deg_to_rad(m.yaw), 0.0))
		camera.position = look + orbit * Vector3(0.0, 0.0, dist * m.scale)
		camera.look_at(look, Vector3.UP)
		camera.rotate_object_local(Vector3(0.0, 0.0, 1.0), deg_to_rad(m.roll))


## 现在的跟拍姿势：从上一小节的随机姿势很快滑到这一小节的（先快后慢），再叠上每拍往里推一下
func _beat_pose() -> Dictionary:
	var step := maxf(beat_change_beats, 0.5)
	var ease_beats := beat_ease_beats
	var p := progress() if punk_camera else 0.0
	if punk_camera:
		# 朋克：越往后换得越勤、越硬
		if p >= punk_every_beat_at:
			step = 1.0
		elif p >= punk_half_bar_at:
			step = minf(step, 2.0)
		ease_beats = lerpf(beat_ease_beats, 0.12, p)
	var bar := floori(_beat / step)
	var a := _bar_pose(bar - 1)
	var b := _bar_pose(bar)
	var t := clampf((_beat - bar * step) / maxf(ease_beats, 0.01), 0.0, 1.0)
	t = 1.0 - pow(1.0 - t, 3.0)
	var punch := pow(1.0 - fposmod(_beat, 1.0), 4.0) * beat_zoom_punch
	punch += _hit_punch * punk_hit_zoom * (0.4 + 0.6 * p) if punk_camera else 0.0
	# 玩家没在操作：按 _active 收回正面（平滑的），每拍推的那一下也收掉；打中的那一下照常
	var k := smoothstep(0.0, 1.0, _active)
	punch = pow(1.0 - fposmod(_beat, 1.0), 4.0) * beat_zoom_punch * k
	punch += _hit_punch * punk_hit_zoom * (0.4 + 0.6 * p) if punk_camera else 0.0
	return {
		"yaw": lerpf(a.yaw, b.yaw, t) * k, "pitch": lerpf(a.pitch, b.pitch, t) * k, "roll": lerpf(a.roll, b.roll, t) * k,
		"scale": lerpf(1.0, lerpf(a.scale, b.scale, t), k) * (1.0 - punch),
	}


## 第 i 小节的随机姿势（按小节号定种子：同一小节每次都一样）。开始之前是正面
func _bar_pose(i: int) -> Dictionary:
	if i < 0:
		return {"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "scale": 1.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 9973 + 17
	var p := progress() if punk_camera else 0.0
	var k := lerpf(1.0, punk_angle_scale, p)
	var near := lerpf(beat_zoom_range.x, punk_zoom_range.x, p)
	var far := lerpf(beat_zoom_range.y, punk_zoom_range.y, p)
	var zoom := rng.randf_range(near, far)
	if p > 0.15:
		# 一近一远地跳：单数拍在近的那一半里挑，双数拍在远的那一半里挑
		var mid := (near + far) * 0.5
		zoom = rng.randf_range(near, lerpf(near, mid, 0.6)) if i % 2 == 0 else rng.randf_range(lerpf(far, mid, 0.6), far)
	return {
		"yaw": rng.randf_range(-beat_yaw_degrees, beat_yaw_degrees) * k,
		"pitch": rng.randf_range(-beat_pitch_degrees, beat_pitch_degrees) * k,
		"roll": rng.randf_range(-beat_roll_degrees, beat_roll_degrees) * k,
		"scale": zoom,
	}


## 按 ComicStyle 现在选的风格给洗衣机和电视套上（或拿掉）漫画材质。框架按 C 切换风格后这里跟着换。
func _apply_look() -> void:
	_look = ComicStyle.style
	ComicStyle.apply(_machine, camera)
	ComicStyle.apply(grid, camera)


# ---------------- 结尾：电视闪烁 → 换成下一个玩法的画面 → 散开 → 镜头钻进中间那台电视 ----------------

func finale_active() -> bool:
	return not is_inf(_finale_from)


## 开始结尾演出：from_beat 到 to_beat 之间放完，to_beat 那一刻屏幕里的画面正好铺满全屏。
## live = 下一个小关的实时画面（没有就只显示图）。
func start_finale(from_beat: float, to_beat: float, live: Texture2D) -> void:
	finale_pending = false
	_finale_from = from_beat
	_finale_to = maxf(to_beat, from_beat + 0.01)
	_finale_cam = camera.global_transform
	_machine_home = Vector3.ZERO
	_center_tv = grid.nearest_to(Vector3(0.0, shots[shots.size() - 1][0].y + 0.3, 0.0))
	grid.show_image(finale_image)
	if live:
		# 所有屏幕直接显示下一个小关的实时画面
		var s := Vector2(world.size)
		for i in grid.count():
			var m := grid.screen_material(i)
			m.set_shader_parameter("live", live)
			m.set_shader_parameter("live_aspect", s.x / maxf(s.y, 1.0))
			m.set_shader_parameter("live_mix", 1.0)
	# 屏幕里的画面要和真正的小关一模一样，所以这里把色调映射换成线性（趁白闪换，看不出来）
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR


func _update_finale(beat: float) -> void:
	var p := clampf((beat - _finale_from) / (_finale_to - _finale_from), 0.0, 1.0)
	# 散开
	var a := smoothstep(0.2, 0.7, p)
	a = a * a
	grid.scatter(_center_tv, a, scatter_distance)
	_machine.position = machine_exit * a
	# 辉光慢慢关掉，屏幕从电视感变成画面原样，占位图换成实时画面
	_env.glow_intensity = 0.9 * (1.0 - smoothstep(0.2, 0.6, p))
	_env.glow_enabled = p < 0.6
	var m := grid.screen_material(_center_tv)
	m.set_shader_parameter("fit", smoothstep(0.4, 0.85, p))  # 中间这台从裁边铺满慢慢变成完整画面
	m.set_shader_parameter("crt", 1.0 - smoothstep(0.6, 0.92, p))
	grid.set_cover_visible(_center_tv, p < 0.6)
	# 镜头：从现在的位置钻到「画面正好铺满全屏」的位置（宽度对齐屏幕宽度），角度跟电视的歪斜对齐
	var tv_xf: Transform3D = (grid.tvs[_center_tv].root as Node3D).global_transform
	var vp := Vector2(world.size)
	var frame_h := grid.screen_size(_center_tv).x * vp.y / maxf(vp.x, 1.0)
	var dist := frame_h * 0.5 / tan(deg_to_rad(camera_fov) * 0.5)
	var target := Transform3D(tv_xf.basis.orthonormalized(), grid.screen_center(_center_tv) + tv_xf.basis.z.normalized() * dist)
	var k := smoothstep(0.35, 1.0, p)
	k = k * k * (3.0 - 2.0 * k)
	camera.global_transform = _finale_cam.interpolate_with(target, k)


## 调试用：直接跳到镜头拉到最远、电视全亮
func skip_to_all_lit() -> void:
	holds_done = maxi(holds_done, zoom_holds)
	_pending_lights.clear()
	for i in grid.unlit():
		grid.light_up(i)
