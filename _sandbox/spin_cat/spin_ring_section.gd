@tool
extends "res://scripts/sections/ring_section.gd"
## 缩圈 + 3D 转圈猫：判定玩法和 Sonnie 的缩圈段落完全一样（圈往中间收，和白色轮廓重合时按）。
## 画面换成铺满屏幕的 3D isometric 小屋，猫站在小屋中间（= 判定圆的位置）。
## 只要按键猫就转（按住一直转，松手停），不管有没有打中；打中时的星星特效由主场景照常放。
## 原来的蓝色圆盘在 spin_ring.tscn 里把 disc_color 设成全透明藏掉了，只留白色判定圈。
## 编辑器预览里仍显示原来的 2D 画面（SpinCat3D 不是 @tool）。
## 测试用，只在本机 _sandbox 里，不进仓库。只支持一个目标圆。

## 小屋场景
@export var room: PackedScene = preload("res://_sandbox/spin_cat/iso_room.tscn")

var _spin_cat: SpinCat3D


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	for cat in _cats:
		cat.visible = false
	_spin_cat = SpinCat3D.new()
	_spin_cat.full_screen = true
	_spin_cat.backdrop = room
	_spin_cat.listen_input = true  # 每次按键都转，不管有没有打中
	_spin_cat.position = target_position(0)
	_spin_cat.z_index = -1  # 3D 画面垫在最底下，缩圈和判定圈画在它上面
	add_child(_spin_cat)
