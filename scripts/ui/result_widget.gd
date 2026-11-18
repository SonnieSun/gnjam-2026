class_name ResultWidget
extends Control
## 最终结算（最后一关打完）。Denominator uses judged notes because charts loop.
## 背景是游戏画面接着动（压暗、模糊），音乐接着循环但压低、削掉高频（Settings.duck_music）。
## 不用方框面板，整屏摆：上面 ALL CLEAR；左边评级字母（后面一圈转着的光芒）、准确率、彩虹果冻数字的分数（从 0 滚上去）、
## 四种判定的涂鸦字配次数（和游戏里 HUD 同一套美术）；右边一叠歪着贴上去的贴纸，每张一只猫 meme 和几句 meow。
## 一拍一样东西弹出来。meow 和猫在下面的 MEOW_* 里改。
## 这个脚本不直接写 autoload 的名字（Settings、Conductor、Music），用 /root 下的节点取：
## 结算测试用 --script 跑，那时 autoload 还没有名字。
const GRADES := {
	"S": preload("res://assets/ui/result_grades/S.png"),
	"A": preload("res://assets/ui/result_grades/A.png"),
	"B": preload("res://assets/ui/result_grades/B.png"),
	"C": preload("res://assets/ui/result_grades/C.png"),
}
const JUDGE_ART := [
	[1, preload("res://assets/ui/judgements/perfect.png")],  # NoteData.Result.PERFECT
	[4, preload("res://assets/ui/judgements/great.png")],    # GREAT
	[2, preload("res://assets/ui/judgements/good.png")],     # GOOD
	[3, preload("res://assets/ui/judgements/miss.png")],     # MISS
]
const DIGITS := preload("res://assets/ui/score_combo/jelly/digits.fnt")
const SCORE_WIDGET := preload("res://ui/score_combo_widget.tscn")
## 第一张贴纸按评级来：[那句 meow, 猫 meme 的名字（assets/memes、assets/cats，见 meme_lib.gd）]
const MEOW_GRADE := {
	"S": ["MEOW MEOW MEOW!!!", "maxwell_spin"],
	"A": ["Meow meow. Meow!", "polite_cat"],
	"B": ["Meow? Meow meow.", "huh"],
	"C": ["meow...  meow.", "sad_but_ok"],
}
## 另外两张随机：一句 meow、一只猫，各挑各的
const MEOW_LINES := [
	"Meow meow meow, meow.", "Mrrp? Meow!", "Meow. Meow meow meow meow.", "MEOW.  (meow)",
	"Meow meow? Meow.", "meow meow meow meow meow meow", "Mew!", "Meow meow, meow meow meow!",
	"Meeeeeow.", "Meow?  ...Meow.",
]
const MEOW_CATS := [
	"stare", "oiia", "grumpy", "catjam", "cat_sing", "keyboard_cat", "floppa", "floppa_cozy",
	"popcat", "blep", "el_gato", "happy_cat", "bingus", "cat_pls",
]
## 贴纸上的猫多高（像素），贴纸歪几度（轮流）
const CAT_SIZE := 96.0
const CARD_TILT := [-3.0, 2.5, -1.5]

## Next 被点了（鼠标点按钮，或者键盘打击键按两下：第一下高亮、第二下确认）
signal next_pressed
## 结算出来后多久才收 Next 的按键（免得打最后几个音符时连按的空格直接把结算跳过）
@export var next_input_delay := 0.6
## 背景模糊多少、压暗多少
@export var blur_lod := 2.5
@export var dim_amount := 0.6
var grade := "C"
var accuracy := 0.0
@onready var grade_art: TextureRect = $Panel/Grade
@onready var percent_label: Label = $Panel/Accuracy
@onready var stats: Label = $Panel/Stats
@onready var next_button: Button = $Panel/Next
@onready var _panel: Control = $Panel
@onready var _dim: ColorRect = $Dim
@onready var _rays: ColorRect = $Panel/Rays
@onready var _title: Label = $Panel/Title
@onready var _lore: VBoxContainer = $Panel/Lore
var _score_widget: Control
var _counts: Array[Control] = []
var _score := 0
var _next_armed := false
var _next_done := false
var _shown_at := 0.0
var _anim: Tween

const DIM_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float lod = 2.5;
uniform float amount = 0.6;
uniform vec3 tint : source_color = vec3(0.05, 0.015, 0.09);
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, lod).rgb;
	COLOR = vec4(mix(c, tint, amount), COLOR.a);
}
"""
## 评级后面的光芒：粉紫两色相间的放射条，慢慢转，往外淡掉，中间一团亮
const RAYS_SHADER := """
shader_type canvas_item;
uniform vec4 ray : source_color = vec4(1.0, 0.45, 0.9, 0.5);
uniform vec4 gap : source_color = vec4(0.55, 0.2, 1.0, 0.12);
uniform float count = 14.0;
uniform float speed = 0.12;
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x) / 6.2831853 + TIME * speed;
	float s = smoothstep(0.45, 0.55, abs(fract(a * count) - 0.5) * 2.0);
	vec4 c = mix(gap, ray, s);
	float fade = smoothstep(1.0, 0.25, r);
	float core = smoothstep(0.55, 0.0, r) * 0.45;
	COLOR = vec4(c.rgb + core, (c.a * fade + core) * COLOR.a);
}
"""


func _ready() -> void:
	next_button.pressed.connect(_fire_next)
	_dim.material = _shader_material(DIM_SHADER, {"lod": blur_lod, "amount": dim_amount})
	_rays.material = _shader_material(RAYS_SHADER, {})
	# 分数：游戏里 HUD 那个彩虹果冻数字
	_score_widget = SCORE_WIDGET.instantiate()
	_panel.add_child(_score_widget)
	_score_widget.position = Vector2(110, 424)
	_score_widget.size = Vector2(320, 100)
	# 四种判定：涂鸦字 + 果冻数字的次数，两行两列
	for i in JUDGE_ART.size():
		var cell := _count_cell(JUDGE_ART[i][1])
		_panel.add_child(cell)
		cell.position = Vector2(40 + (i % 2) * 220, 532 + floori(i / 2.0) * 58)
		_counts.append(cell)
	visibility_changed.connect(func() -> void:
		if not visible:
			_duck(false))


func _exit_tree() -> void:
	_duck(false)


static func rank_for(score: int, judged_count: int) -> String:
	if judged_count <= 0: return "C"
	# Integer comparisons avoid precision changes at exact thresholds.
	if score >= judged_count * 95: return "S"
	if score >= judged_count * 85: return "A"
	if score >= judged_count * 70: return "B"
	return "C"


func show_result(judge) -> void:
	var total := 0
	for result in [NoteData.Result.PERFECT, NoteData.Result.GREAT, NoteData.Result.GOOD, NoteData.Result.MISS]:
		total += int(judge.counts.get(result, 0))
	# Current scoring banks weighted stages; judged-note count is not its maximum.
	var possible: float = float(judge.get("possible")) if judge.get("possible") != null else 0.0
	if possible > 0.0:
		grade = judge.rank()
		accuracy = clampf(float(judge.score) / possible,0.0,1.0)
	else:
		grade = rank_for(judge.score,total)
		accuracy = clampf(float(judge.score) / float(total*100),0.0,1.0) if total > 0 else 0.0
	grade_art.texture = GRADES[grade]
	_score = int(judge.score)
	percent_label.text = "ACCURACY  %.2f%%      MAX COMBO  %d" % [accuracy * 100.0, judge.max_combo]
	var ms: float = judge.mean_offset() * 1000.0
	var lean := ("LATE" if ms > 0 else "EARLY") if absf(ms) >= 1.0 else ""
	stats.text = "AVERAGE TIMING  %+.0f ms  %s" % [ms, lean]
	for i in JUDGE_ART.size():
		(_counts[i].get_node("N") as Label).text = str(int(judge.counts.get(JUDGE_ART[i][0], 0)))
	_title.text = "ALL CLEAR" if _is_last_level() else "LEVEL CLEAR"
	_fill_lore()
	visible = true
	_next_armed = false
	_next_done = false
	_shown_at = Time.get_ticks_msec() / 1000.0
	next_button.modulate = Color.WHITE
	next_button.scale = Vector2.ONE
	_duck(true)
	_enter()


## 弹进来，跟着拍子：0 拍背景暗下去、标题落下；1 拍评级盖章；2 拍分数滚上去；4 拍起判定次数半拍一个；6、8、10 拍贴纸一张张拍上去
func _enter() -> void:
	if _anim:
		_anim.kill()
	var beat := 60.0 / 160.0
	var c := get_node_or_null("/root/Conductor")
	if c and c.has_method("sec_per_beat"):
		beat = float(c.sec_per_beat())
	_dim.modulate.a = 0.0
	_title.scale = Vector2.ONE * 1.15
	_title.modulate.a = 0.0
	_rays.modulate.a = 0.0
	_rays.scale = Vector2.ONE * 0.4
	grade_art.scale = Vector2.ONE * 2.6
	grade_art.modulate.a = 0.0
	_score_widget.set("value", 0)
	_score_widget.call("set_value", 0)
	_score_widget.modulate.a = 0.0
	for n: Control in [percent_label, stats, $Panel/LoreTitle, $Panel/Controls, next_button]:
		n.modulate.a = 0.0
	for cell in _counts:
		cell.modulate.a = 0.0
		cell.scale = Vector2.ONE * 1.5
	for card: Control in _lore.get_children():
		card.modulate.a = 0.0
	var t := create_tween().set_parallel()
	_anim = t
	t.tween_property(_dim, "modulate:a", 1.0, 0.45)
	t.tween_property(_title, "scale", Vector2.ONE, 0.25).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_title, "modulate:a", 1.0, 0.12).set_delay(0.2)  # 等最后一下的大字飞到这里（hud.gd）
	# 评级盖章 + 光芒张开
	var g := beat
	t.tween_property(grade_art, "scale", Vector2.ONE, 0.14).set_delay(g).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(grade_art, "modulate:a", 1.0, 0.06).set_delay(g)
	t.tween_callback(_sfx.bind("crash", -8.0)).set_delay(g + 0.14)
	t.tween_property(_rays, "modulate:a", 1.0, 0.3).set_delay(g + 0.14)
	t.tween_property(_rays, "scale", Vector2.ONE, 0.5).set_delay(g + 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(percent_label, "modulate:a", 1.0, 0.2).set_delay(g + 0.3)
	# 分数滚上去
	var s := beat * 2.0
	t.tween_property(_score_widget, "modulate:a", 1.0, 0.1).set_delay(s)
	t.tween_method(func(v: float) -> void: _score_widget.call("set_value", int(v)), 0.0, float(_score), beat * 3.0) \
			.set_delay(s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 判定次数
	for i in _counts.size():
		var at := beat * (4.0 + i * 0.5)
		t.tween_property(_counts[i], "modulate:a", 1.0, 0.08).set_delay(at)
		t.tween_property(_counts[i], "scale", Vector2.ONE, 0.22).set_delay(at).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(stats, "modulate:a", 1.0, 0.3).set_delay(beat * 6.0)
	t.tween_property($Panel/LoreTitle, "modulate:a", 1.0, 0.2).set_delay(beat * 5.0)
	# 贴纸：拍上去（大 → 小、多歪一点 → 回正），每张一声喵
	var k := 0
	for card: Control in _lore.get_children():
		var at := beat * (6.0 + k * 2.0)
		var tilt := deg_to_rad(float(CARD_TILT[k % CARD_TILT.size()]))
		card.scale = Vector2.ONE * 1.35
		card.rotation = tilt * 3.0
		t.tween_property(card, "modulate:a", 1.0, 0.06).set_delay(at)
		t.tween_property(card, "scale", Vector2.ONE, 0.18).set_delay(at).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(card, "rotation", tilt, 0.22).set_delay(at).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_callback(_sfx.bind(["meow_short_08_D5", "meow_short_11_D6", "meow_short_08_Bb5"][k % 3], -9.0)).set_delay(at)
		k += 1
	var done := beat * (6.0 + k * 2.0)
	t.tween_property($Panel/Controls, "modulate:a", 1.0, 0.3).set_delay(done)
	t.tween_property(next_button, "modulate:a", 1.0, 0.3).set_delay(done)


## 三张贴纸：第一张按评级（只在最后一关），后面随机
func _fill_lore() -> void:
	for child in _lore.get_children():
		_lore.remove_child(child)
		child.queue_free()
	var cats: Array = MEOW_CATS.duplicate()
	cats.shuffle()
	var lines: Array = MEOW_LINES.duplicate()
	lines.shuffle()
	var rows: Array = []
	if _is_last_level():
		rows.append(MEOW_GRADE[grade])
	while rows.size() < 3:
		rows.append([lines.pop_back(), cats.pop_back()])
	for r: Array in rows:
		_lore.add_child(_card(r[0], r[1]))


## 一张贴纸：奶白底、粉边、带影子，猫从左边探出来一点
func _card(text: String, cat: String) -> Control:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.94, 0.98)
	sb.border_color = Color(0.95, 0.35, 0.9)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(0.1, 0.0, 0.2, 0.45)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(5, 7)
	sb.content_margin_left = CAT_SIZE + 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size.y = CAT_SIZE + 16.0
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(0.32, 0.06, 0.42))
	card.add_child(l)
	# 猫不进容器（容器会把它拉成格子大小），挂在一个不参与排版的节点下面
	var holder := Node2D.new()
	var sprite := MemeSprite.create(cat, CAT_SIZE)
	if sprite.texture:
		var w := sprite.texture.get_width() / float(sprite.hframes) * sprite.scale.x
		if w > CAT_SIZE * 1.15:
			sprite.scale *= CAT_SIZE * 1.15 / w
	holder.add_child(sprite)
	card.add_child(holder)
	card.resized.connect(func() -> void:
		card.pivot_offset = card.size / 2.0
		holder.position = Vector2(CAT_SIZE * 0.5 + 4.0, card.size.y / 2.0))
	return card


func _count_cell(art: Texture2D) -> Control:
	var cell := Control.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.size = Vector2(210, 54)
	cell.pivot_offset = Vector2(60, 27)
	var img := TextureRect.new()
	img.texture = art
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.size = Vector2(120, 54)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(img)
	var n := Label.new()
	n.name = "N"
	n.add_theme_font_override("font", DIGITS)
	n.add_theme_font_size_override("font_size", 44)
	n.position = Vector2(126, 0)
	n.size = Vector2(84, 54)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(n)
	return cell


func _shader_material(code: String, params: Dictionary) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


func _is_last_level() -> bool:
	return Levels.selected == Levels.count() - 1


func _duck(on: bool) -> void:
	var s := get_node_or_null("/root/Settings")
	if s and s.has_method("duck_music"):
		s.duck_music(on, 1.2 if on else 0.4)


func _sfx(sfx_name: String, db: float) -> void:
	var m := get_node_or_null("/root/Music")
	if m and m.has_method("play_sfx"):
		m.play_sfx(sfx_name, db)


func _unhandled_input(event: InputEvent) -> void:
	# 只认键盘上的打击键（空格等）：鼠标点别处不算，鼠标只能点按钮本身
	if not visible or not event is InputEventKey or event.is_echo() or not event.is_action_pressed(Judge.HIT_ACTION):
		return
	if Time.get_ticks_msec() / 1000.0 - _shown_at < next_input_delay:
		return
	get_viewport().set_input_as_handled()
	if _next_armed:
		_fire_next()
		return
	# 第一下：高亮 Next
	_next_armed = true
	next_button.modulate = Color(1.6, 1.4, 1.6)
	next_button.scale = Vector2.ONE * 1.18
	next_button.create_tween().tween_property(next_button, "scale", Vector2.ONE * 1.08, 0.15)


func _fire_next() -> void:
	if _next_done or not visible:
		return
	_next_done = true
	next_pressed.emit()
