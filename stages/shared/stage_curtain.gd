class_name StageCurtain
extends CanvasLayer
## 两关之间的黑幕：从上往下落下来盖住画面，换关的那一下盖着，
## 下一关的场景一摆出来就接着往下落出屏幕，露出新的一关（喘息是在新场景里，不在黑幕里）。自己管自己，用完自己删掉。
## 用法：StageCurtain.drop(get_tree(), 秒数)   （只在后面确定还有一关时用，不然它会一直盖着）

## 落出屏幕用几秒
const LEAVE_SECONDS := 0.9

var _rect: ColorRect
var _state := 0  # 0 落下来  1 盖着，等上一关停  2 盖着，等换到下一关的场景  3 落出去
var _from_scene := 0  # 落下来时的那个场景（换成别的了 = 下一关摆出来了）
var _hold := 0
var _t := 0.0
var _seconds := 0.7


static func drop(tree: SceneTree, seconds := 0.7) -> void:
	if tree.root.has_node("StageCurtain"):
		return
	var c := StageCurtain.new()
	c.name = "StageCurtain"
	c._seconds = maxf(seconds, 0.05)
	c._from_scene = tree.current_scene.get_instance_id() if tree.current_scene else 0
	tree.root.add_child(c)


func _ready() -> void:
	layer = 15
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_place(-1.0)


## at = -1 整块在屏幕上面，0 正好盖满，1 整块在屏幕下面
func _place(at: float) -> void:
	var size := get_viewport().get_visible_rect().size
	_rect.size = size + Vector2(0.0, 40.0)
	_rect.position = Vector2(0.0, at * (size.y + 40.0))


func _process(delta: float) -> void:
	match _state:
		0:
			_t = minf(_t + delta / _seconds, 1.0)
			_place(-1.0 + _t * _t)
			if _t >= 1.0:
				_state = 1
		1:
			_place(0.0)
			if not Conductor.playing:
				_state = 2
		2:
			_place(0.0)
			var scene := get_tree().current_scene
			if scene and scene.scene_file_path != Levels.GAME_SCENE:
				queue_free()  # 没去下一关（回了主菜单之类）
			elif scene and scene.get_instance_id() != _from_scene:
				_hold += 1
				if _hold > 3:  # 新场景摆出来了，等它画上几帧再落走
					_state = 3
					_t = 0.0
		3:
			_t = minf(_t + delta / LEAVE_SECONDS, 1.0)
			_place(_t * _t)
			if _t >= 1.0:
				queue_free()
