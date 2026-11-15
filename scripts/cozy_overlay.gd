extends Control
## 第 1 关的温馨开头：盖在真正的关卡场景上面的一层。
## 一个把画面调成粉粉软软的滤镜（提亮、降一点饱和、往奶油粉上靠、四周泛白），
## 再贴一些贴纸（爱心、星星、圆角的边框）和一句提示。玩家按一下，main.gd 把这一层整个删掉，画风就变回去了。

## 提示文字
@export var prompt := "press SPACE to pet the cat"
## 滤镜的强度（0 = 原样，1 = 最粉）
@export_range(0.0, 1.0) var softness := 0.62
@export var pink := Color("ff8fb8")
@export var cream := Color("fff3e6")
@export var mint := Color("a8ecd4")
@export var lilac := Color("c9b6ff")

## 神秘的猫猫特写运镜：一组镜头轮着放，硬切。每个镜头是
## [几秒, 水平角从, 到, 俯角从, 到, 画面高度（猫的几倍）从, 到, 看向猫身上多高（0 = 中心，猫的几倍）]
@export var shots: Array = [
	[4.0, 45.0, 45.0, 35.0, 35.0, 0.0, 0.0, 0.0],      # 原来的全景（0 = 关卡自己的大小），慢慢推近
	[3.5, 25.0, -15.0, 6.0, 6.0, 1.1, 0.95, 0.12],     # 正面的脸，慢慢绕
	[3.5, 110.0, 80.0, 2.0, 10.0, 1.7, 1.4, 0.0],      # 贴着地面的侧面
	[3.0, -6.0, 6.0, 4.0, 4.0, 0.5, 0.42, 0.2],        # 眼睛的大特写
	[3.5, 0.0, 50.0, 80.0, 72.0, 2.6, 2.1, 0.0],       # 正上方往下看，慢慢转
]

## main.gd 给的：第 1 关那只猫的 3D 舞台（KisaSpinCat3D：用它的 camera / focus / cat_view_height）
var cat: Node
var _wide := 0.0
var _shot := 0
var _shot_t := 0.0

const FILTER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float softness = 0.62;
void fragment() {
	// 稍微糊一点，像柔焦
	vec3 c = mix(texture(screen, SCREEN_UV).rgb, textureLod(screen, SCREEN_UV, 1.5).rgb, 0.3);
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(l), 0.35 * softness);                       // 降一点饱和
	c = mix(c, c * vec3(0.78, 0.70, 0.74) + vec3(1.0, 0.80, 0.86) * 0.30, softness); // 提亮，往奶油粉上靠
	float v = distance(UV, vec2(0.5));
	c = mix(c, vec3(1.0, 0.93, 0.95), smoothstep(0.38, 0.80, v) * 0.75 * softness); // 四周泛白
	COLOR = vec4(c, 1.0);
}
"""

var _t := 0.0
# 贴纸：[位置（占屏幕的比例）, 大小, 种类（0 爱心 1 星星）, 颜色序号, 歪多少]
var _stickers := [
	[Vector2(0.10, 0.20), 46.0, 0, 0, -0.3], [Vector2(0.19, 0.11), 22.0, 1, 2, 0.0], [Vector2(0.07, 0.42), 18.0, 1, 3, 0.2],
	[Vector2(0.90, 0.17), 38.0, 0, 3, 0.25], [Vector2(0.82, 0.09), 26.0, 1, 0, 0.0], [Vector2(0.94, 0.40), 20.0, 0, 2, -0.2],
	[Vector2(0.12, 0.78), 30.0, 1, 0, 0.3], [Vector2(0.06, 0.63), 24.0, 0, 2, 0.15], [Vector2(0.88, 0.76), 34.0, 0, 0, -0.25],
	[Vector2(0.93, 0.60), 22.0, 1, 3, 0.0], [Vector2(0.30, 0.07), 16.0, 0, 3, 0.2], [Vector2(0.70, 0.06), 16.0, 1, 2, 0.0],
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := ColorRect.new()
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = FILTER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("softness", softness)
	f.material = m
	f.show_behind_parent = true
	add_child(f)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	_move_camera(delta)


func _move_camera(delta: float) -> void:
	if cat == null or cat.get("camera") == null or shots.is_empty():
		return
	var cam: Camera3D = cat.camera
	if _wide <= 0.0:
		_wide = cam.size
	_shot_t += delta
	if _shot_t >= float(shots[_shot][0]):
		_shot_t = 0.0
		_shot = (_shot + 1) % shots.size()
	var s: Array = shots[_shot]
	var k := _shot_t / float(s[0])
	var h: float = cat.cat_view_height
	var yaw := deg_to_rad(lerpf(s[1], s[2], k))
	var pitch := deg_to_rad(lerpf(s[3], s[4], k))
	var dir := Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw)
	var look: Vector3 = cat.focus + Vector3.UP * h * float(s[7])
	cam.size = lerpf(_wide, _wide * 0.82, k) if float(s[5]) <= 0.0 else h * lerpf(s[5], s[6], k)
	cam.position = look + dir * 100.0
	cam.look_at(look)


func _draw() -> void:
	var s := size
	var cols := [pink, cream, mint, lilac]
	# 圆角的边框：外面一圈奶油色，里面一圈粉色的虚线
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_corner_radius_all(46)
	box.set_border_width_all(18)
	box.border_color = cream
	draw_style_box(box, Rect2(Vector2.ZERO, s).grow(-10.0))
	var inset := 40.0
	var n := 64
	for i in n:
		var a := float(i) / n
		var p := _on_frame(a, s, inset)
		draw_circle(p, 4.0, pink)
	# 贴纸，各自慢慢晃
	for i in _stickers.size():
		var st: Array = _stickers[i]
		var bob := sin(_t * 1.6 + i * 1.3)
		var pos: Vector2 = Vector2(st[0]) * s + Vector2(0.0, bob * 6.0)
		var rot: float = float(st[4]) + bob * 0.08
		var col: Color = cols[st[3]]
		var pts := _heart(float(st[1])) if st[2] == 0 else _sparkle(float(st[1]))
		draw_set_transform(pos + Vector2(3.0, 4.0), rot)
		draw_colored_polygon(pts, Color(1.0, 0.55, 0.7, 0.35))  # 一点影子
		draw_set_transform(pos, rot)
		draw_colored_polygon(pts, col)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color.WHITE, 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0)
	# 猫头上冒的小爱心
	for k in 3:
		var ph := fmod(_t * 0.45 + k / 3.0, 1.0)
		var hp := Vector2(s.x * 0.5 + sin(ph * TAU + k) * 26.0, s.y * 0.40 - ph * 90.0)
		draw_set_transform(hp, 0.0, Vector2.ONE * (0.5 + ph * 0.6))
		draw_colored_polygon(_heart(18.0), Color(pink, 1.0 - ph))
	draw_set_transform(Vector2.ZERO, 0.0)
	# 提示：一条圆角的丝带，轻轻呼吸
	var font := get_theme_default_font()
	var fs := 34
	var tw := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pulse := 1.0 + sin(_t * 3.0) * 0.03
	var rib := Rect2(0, 0, tw + 90.0, 68.0)
	var c := Vector2(s.x * 0.5, s.y * 0.84)
	draw_set_transform(c, 0.0, Vector2.ONE * pulse)
	var rb := StyleBoxFlat.new()
	rb.bg_color = Color.WHITE
	rb.set_corner_radius_all(34)
	rb.set_border_width_all(5)
	rb.border_color = pink
	rb.shadow_color = Color(1.0, 0.55, 0.7, 0.35)
	rb.shadow_size = 8
	rb.shadow_offset = Vector2(0, 5)
	draw_style_box(rb, Rect2(-rib.size * 0.5, rib.size))
	draw_string(font, Vector2(-tw * 0.5, fs * 0.36), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pink)
	draw_set_transform(c + Vector2(-rib.size.x * 0.5 * pulse, -30.0), -0.3)
	draw_colored_polygon(_heart(20.0), pink)
	draw_set_transform(Vector2.ZERO, 0.0)


# 边框上的一个点（a = 0..1 绕一圈）
func _on_frame(a: float, s: Vector2, inset: float) -> Vector2:
	var w := s.x - inset * 2.0
	var h := s.y - inset * 2.0
	var d := a * (w + h) * 2.0
	if d < w:
		return Vector2(inset + d, inset)
	d -= w
	if d < h:
		return Vector2(s.x - inset, inset + d)
	d -= h
	if d < w:
		return Vector2(s.x - inset - d, s.y - inset)
	return Vector2(inset, s.y - inset - (d - w))


func _heart(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 28:
		var t := TAU * i / 28.0
		pts.append(Vector2(16.0 * pow(sin(t), 3.0), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) * r / 16.0)
	return pts


func _sparkle(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0 - PI / 2.0
		pts.append(Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.38))
	return pts
