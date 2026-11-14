class_name LevelData
extends RefCounted
## One level as plain data. Saving, loading, undo and the generator all go
## through to_dict() / from_dict(), so there is exactly one format.
##
##   meta      name, bpm, offset (seconds from song start to beat 0), song
##             (path), length (beats), lanes, px_per_beat (world x per beat)
##   chart     notes: { b = beat, lane = int, len = beats (0 = tap) }
##   entities  things in the world: { type, x, y, rot, props = {} }
##             type is a key of Registry; props follow its spec.

const VERSION := 1

var meta := {}
var chart: Array[Dictionary] = []
var entities: Array[Dictionary] = []


func _init() -> void:
	clear()


func clear() -> void:
	meta = {name = "untitled", bpm = 120.0, offset = 0.0, song = "", length = 64.0, lanes = 4, px_per_beat = 160.0}
	chart.clear()
	entities.clear()


# --- time ------------------------------------------------------------------

func bpm() -> float:
	return float(meta.bpm)


func beat_to_sec(b: float) -> float:
	return float(meta.offset) + b * 60.0 / bpm()


func sec_to_beat(s: float) -> float:
	return (s - float(meta.offset)) * bpm() / 60.0


func beat_to_x(b: float) -> float:
	return b * float(meta.px_per_beat)


func x_to_beat(x: float) -> float:
	return x / float(meta.px_per_beat)


# --- chart -----------------------------------------------------------------

static func note(b: float, lane: int, length := 0.0) -> Dictionary:
	return {b = b, lane = lane, len = length}


## Adds a note, replacing one already on the same lane and beat.
func add_note(b: float, lane: int, length := 0.0) -> Dictionary:
	remove_note_at(b, lane)
	var n := note(b, lane, length)
	chart.append(n)
	sort_chart()
	return n


## The note on `lane` covering beat `b` (within `tolerance` of its start),
## or {} if none.
func note_at(b: float, lane: int, tolerance := 0.01) -> Dictionary:
	for n in chart:
		if int(n.lane) == lane and b >= float(n.b) - tolerance and b <= float(n.b) + maxf(float(n.len), tolerance):
			return n
	return {}


func remove_note_at(b: float, lane: int, tolerance := 0.01) -> bool:
	var n := note_at(b, lane, tolerance)
	if n.is_empty():
		return false
	chart.erase(n)
	return true


func sort_chart() -> void:
	chart.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		return float(a.b) < float(c.b) or (float(a.b) == float(c.b) and int(a.lane) < int(c.lane)))


## Notes whose start lies in [from, to).
func notes_between(from: float, to: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in chart:
		var b := float(n.b)
		if b >= to:
			break
		if b >= from:
			out.append(n)
	return out


# --- entities --------------------------------------------------------------

func add_entity(type: String, pos: Vector2, props := {}, rot := 0.0) -> Dictionary:
	var e := {type = type, x = pos.x, y = pos.y, rot = rot, props = Registry.clean_props(type, props)}
	entities.append(e)
	return e


static func entity_pos(e: Dictionary) -> Vector2:
	return Vector2(float(e.x), float(e.y))


# --- files -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {version = VERSION, meta = meta.duplicate(), chart = chart.duplicate(true), entities = entities.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	clear()
	meta.merge(d.get("meta", {}), true)
	for key: String in ["bpm", "offset", "length", "px_per_beat"]:
		meta[key] = float(meta[key])
	meta.lanes = int(meta.lanes) # JSON reads every number back as a float
	for n: Dictionary in d.get("chart", []):
		chart.append(note(float(n.get("b", 0.0)), int(n.get("lane", 0)), float(n.get("len", 0.0))))
	sort_chart()
	for e: Dictionary in d.get("entities", []):
		var type := str(e.get("type", ""))
		if not Registry.has(type):
			push_warning("LevelData: unknown entity type '%s' skipped" % type)
			continue
		var props := Registry.clean_props(type, e.get("props", {}))
		entities.append({type = type, x = float(e.get("x", 0.0)), y = float(e.get("y", 0.0)), rot = float(e.get("rot", 0.0)), props = props})


func save(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return true


static func load_file(path: String) -> LevelData:
	var text := FileAccess.get_file_as_string(path)
	var d: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not d is Dictionary:
		return null
	var level := LevelData.new()
	level.from_dict(d)
	return level
