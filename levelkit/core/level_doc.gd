class_name LevelDoc
extends RefCounted
## The level being edited, plus undo/redo and the levels folder. Undo is a
## stack of JSON snapshots: take checkpoint() BEFORE any change.

signal history_changed
## The whole level was just replaced (open, new, undo, redo).
signal applied

const MAX_UNDO := 100

var level := LevelData.new()
## File the level was opened from / last saved to ("" = never saved).
var path := ""

var _undo: Array[String] = []
var _redo: Array[String] = []


## res://levels while running from the Godot editor (so levels get
## committed with the game), user://levels in an exported build.
static func level_dir() -> String:
	return "res://levels" if OS.has_feature("editor") else "user://levels"


func apply(d: Dictionary) -> void:
	level.from_dict(d)
	applied.emit()


# --- undo ------------------------------------------------------------------

func checkpoint() -> void:
	var now := JSON.stringify(level.to_dict())
	if _undo.is_empty() or _undo[-1] != now:
		_undo.append(now)
		if _undo.size() > MAX_UNDO:
			_undo.pop_front()
	_redo.clear()
	history_changed.emit()


func undo() -> bool:
	var now := JSON.stringify(level.to_dict())
	while not _undo.is_empty() and _undo[-1] == now:
		_undo.pop_back() # a checkpoint for a change that never happened
	if _undo.is_empty():
		return false
	_redo.append(now)
	apply(JSON.parse_string(_undo.pop_back()))
	history_changed.emit()
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(JSON.stringify(level.to_dict()))
	apply(JSON.parse_string(_redo.pop_back()))
	history_changed.emit()
	return true


# --- files -----------------------------------------------------------------

## Level files, sorted by name: [{ name, path }]. Bundled res://levels are
## listed in exported builds too.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for dir in [level_dir(), "res://levels"]:
		if seen.has(dir):
			continue
		seen[dir] = true
		var files := Array(ResourceLoader.list_directory(dir)) if dir.begins_with("res://") else Array(DirAccess.get_files_at(dir))
		files.sort()
		for f: String in files:
			if f.get_extension() == "json" and not f.ends_with(".analysis.json"):
				out.append({name = f.get_basename(), path = dir.path_join(f)})
	return out


func new_level() -> void:
	checkpoint()
	path = ""
	apply({})


func open(p: String) -> bool:
	var loaded := LevelData.load_file(p)
	if loaded == null:
		return false
	checkpoint()
	path = p
	apply(loaded.to_dict())
	return true


## Saves under meta.name in the levels folder (or to `to` if given).
func save(to := "") -> bool:
	if to.is_empty():
		var name := str(level.meta.name).strip_edges().validate_filename()
		if name.is_empty():
			name = "untitled"
		to = level_dir().path_join(name + ".json")
	if not level.save(to):
		return false
	path = to
	return true
