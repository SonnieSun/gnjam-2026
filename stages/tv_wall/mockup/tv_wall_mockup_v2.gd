extends "res://stages/tv_wall/mockup/tv_wall_mockup.gd"
## 电视墙效果图 v2：照 Kisa 给的参考图构图重排（只借构图）。
## 镜头拉近、略往下看；电视少而大、歪歪扭扭地堆，左边正对镜头、右边往前弯过来；
## 左下一个抽屉柜，右边桌子后面一个矮柜；猫在小圆桌上占画面中间。
## 材质、屏幕画面、后期都沿用 v1（tv_wall_mockup.gd）。
## 测试用，只在本机 _sandbox 里，不进仓库。

const SHELLS := [
	Color(0.92, 0.94, 0.97), Color(0.62, 0.68, 1.0), Color(0.7, 0.9, 1.0),
	Color(0.85, 0.8, 0.95), Color(0.55, 0.85, 0.8),
]


func _init() -> void:
	out_name = "tv-wall-y2k-v2"
	cat_height = 0.5
	feed_distance = 2.1
	screen_vignette = 1.2


func _build_room() -> void:
	_box(Vector3(8.0, 0.1, 8.0), Vector3(0.0, -0.05, 0.0), _plastic(Color(0.06, 0.14, 0.16), 0.3))
	_box(Vector3(8.0, 5.0, 0.1), Vector3(0.0, 2.5, -2.4), _plastic(Color(0.03, 0.07, 0.08), 0.6))


func _build_env() -> void:
	super._build_env()
	# v1 的灯是按远景摆的，这里关掉重打
	for n in get_children():
		if n is Light3D:
			n.queue_free()
	for p in [Vector3(-0.9, 1.4, -0.6), Vector3(0.0, 1.5, -0.9), Vector3(1.0, 1.4, -0.2)]:
		var o := OmniLight3D.new()
		o.position = p
		o.light_color = Color(0.45, 0.95, 0.85)
		o.light_energy = 0.9
		o.omni_range = 3.0
		add_child(o)
	# 猫背后的长春花蓝逆光
	var rim := SpotLight3D.new()
	rim.position = Vector3(0.1, 1.3, -0.8)
	rim.light_color = Color(0.6, 0.65, 1.0)
	rim.light_energy = 5.0
	rim.spot_range = 3.0
	rim.spot_angle = 30.0
	add_child(rim)
	rim.look_at(Vector3(0.0, 0.8, 0.0))
	# 镜头这边一点暖金补光
	var key := SpotLight3D.new()
	key.position = Vector3(0.7, 1.9, 1.7)
	key.light_color = Color(1.0, 0.85, 0.6)
	key.light_energy = 0.8
	key.spot_range = 4.0
	key.spot_angle = 22.0
	key.shadow_enabled = true
	add_child(key)
	key.look_at(Vector3(0.0, 0.8, 0.0))


func _build_tv_wall() -> void:
	# [底部中心, 宽, 水平转角, 歪角, 外壳色, 画面]
	var tvs := [
		# 左边一列，压在抽屉柜上
		[Vector3(-1.25, 0.82, -0.95), 0.72, 18.0, 3.0, 0, 0],
		[Vector3(-1.3, 1.42, -1.1), 0.68, 14.0, -4.0, 2, 1],
		# 中间（猫背后）两台大的
		[Vector3(-0.35, 0.55, -1.35), 0.85, 4.0, -4.0, 3, 0],
		[Vector3(-0.3, 1.27, -1.45), 0.95, 0.0, 3.0, 0, 0],
		# 右边往前弯过来
		[Vector3(0.72, 0.72, -1.0), 0.88, -24.0, -5.0, 1, 0],
		[Vector3(0.8, 1.48, -1.15), 0.72, -18.0, 2.0, 4, 1],
		[Vector3(1.5, 0.45, -0.6), 0.8, -52.0, 3.0, 2, 1],
		[Vector3(1.58, 1.1, -0.7), 0.85, -48.0, -4.0, 0, 0],
		[Vector3(1.62, 1.8, -0.85), 0.72, -42.0, 2.0, 3, 1],
		# 上面和缝里再塞几台
		[Vector3(-0.85, 2.0, -1.6), 0.8, 8.0, -2.0, 4, 1],
		[Vector3(0.2, 2.05, -1.7), 0.8, -6.0, 4.0, 1, 0],
		[Vector3(0.3, 1.4, -1.65), 0.7, -10.0, -3.0, 2, 1],
		[Vector3(1.15, 2.2, -1.3), 0.8, -22.0, 3.0, 0, 0],
		[Vector3(-1.6, 1.95, -1.2), 0.75, 16.0, -3.0, 1, 0],
		[Vector3(-0.8, 0.7, -1.6), 0.7, 10.0, 2.0, 4, 1],
		[Vector3(-1.75, 0.0, -0.4), 0.7, 35.0, 0.0, 1, 1],
	]
	for t in tvs:
		var w: float = t[1]
		_crt(t[0], Vector2(w, w * 0.8), SHELLS[t[4]], t[5])
		var tv := get_child(get_child_count() - 1) as Node3D
		tv.rotation_degrees = Vector3(0.0, t[2], t[3])
		# 屏幕下面一条录像机插口（参考图里那种电视录像一体机）
		_box(Vector3(w * 0.36, 0.022, 0.01), Vector3(-w * 0.1, w * 0.8 * 0.08, 0.004), _plastic(Color(0.02, 0.03, 0.04), 0.3), tv)
	# 垫在电视下面的东西：中间录像机一摞、右边矮柜和一个箱子
	_vcr(Vector3(-0.35, 0.0, -1.3), 0.85)
	_vcr(Vector3(-0.35, 0.16, -1.3), 0.82)
	_vcr(Vector3(-0.35, 0.32, -1.3), 0.85)
	_cabinet(Vector3(0.72, 0.0, -0.95), -24.0, Vector3(0.9, 0.72, 0.55), Color(0.85, 0.8, 0.95))
	_cabinet(Vector3(1.5, 0.0, -0.55), -52.0, Vector3(0.8, 0.45, 0.6), Color(0.7, 0.9, 1.0))


func _build_table_and_cat() -> void:
	super._build_table_and_cat()
	# 猫是最后加进去的：侧一点，身子露出来多一些（参考图那样斜对镜头）
	var cat := get_child(get_child_count() - 1) as Node3D
	cat.rotation_degrees.y = -32.0


func _build_dressers() -> void:
	# 左下：抽屉柜（上面压着左边那列电视）
	var root := Node3D.new()
	root.position = Vector3(-1.2, 0.0, -0.75)
	root.rotation_degrees.y = 18.0
	add_child(root)
	var w := 0.9
	var h := 0.82
	var d := 0.6
	_box(Vector3(w, h, d), Vector3(0.0, h * 0.5, 0.0), _plastic(Color(0.92, 0.94, 0.97), 0.12), root)
	for i in 3:
		var y := h * (0.18 + i * 0.3)
		_box(Vector3(w * 0.9, h * 0.26, 0.04), Vector3(0.0, y, d * 0.5), _glass(Color(0.7, 0.9, 1.0)), root)
		_box(Vector3(w * 0.25, 0.03, 0.03), Vector3(0.0, y + 0.02, d * 0.5 + 0.03), _plastic(Color(1.0, 0.8, 0.35), 0.15), root)


## 矮柜：白色光泽机身 + 半透明柜门 + 金色圆把手
func _cabinet(pos: Vector3, yaw: float, size: Vector3, tint: Color) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	_box(size, Vector3(0.0, size.y * 0.5, -size.z * 0.5), _plastic(Color(0.92, 0.94, 0.97), 0.12), root)
	_box(Vector3(size.x * 0.9, size.y * 0.85, 0.04), Vector3(0.0, size.y * 0.5, 0.0), _glass(tint), root)
	var knob := _cyl(0.025, 0.03, Vector3(size.x * 0.3, size.y * 0.6, 0.035), _plastic(Color(1.0, 0.8, 0.35), 0.15), root)
	knob.rotation_degrees.x = 90.0


func _screen_mat(feed: int) -> ShaderMaterial:
	var m := super._screen_mat(feed)
	# 参考图的屏幕偏亮偏白
	m.set_shader_parameter("energy", _rng.randf_range(2.2, 3.0))
	m.set_shader_parameter("zoom", _rng.randf_range(0.95, 1.1))
	return m


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.fov = 52.0
	cam.position = Vector3(-0.05, 1.3, 1.75)
	add_child(cam)
	cam.look_at(Vector3(0.12, 0.95, -0.6))
	cam.current = true
