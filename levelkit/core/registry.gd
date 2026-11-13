extends Node
## Autoload "Registry": every kind of thing a level can hold, and the lanes
## of the chart. THIS is the file to edit during the jam.
##
## Add an entity type with add() in _ready(). The editor palette, the
## inspector, save files, the generator and LevelBuilder pick it up on their
## own. Give it a `scene` and LevelBuilder spawns that scene in the game;
## leave it out and you get a coloured placeholder box.
##
## Props are specs made with param() / choice() / flag(). In the game, each
## prop is set on the spawned node if it has a property of the same name,
## and the whole dict is passed to setup(props) if the node has that method.

## Chart lanes: name, colour, key. Change the count here and everywhere follows.
const LANES: Array[Dictionary] = [
	{name = "Kick", color = Color("ff5d8f"), key = KEY_D, sound = "kick"},
	{name = "Snare", color = Color("ffd23f"), key = KEY_F, sound = "snare"},
	{name = "Hat", color = Color("3bceac"), key = KEY_J, sound = "hat"},
	{name = "Blip", color = Color("9b8cff"), key = KEY_K, sound = "blip"},
]

## type -> { label, color, size, scene, props: Array[Dictionary] }
var types := {}
## Insertion order, for the palette.
var order: Array[String] = []


func _init() -> void:
	# --- example types: replace with the jam game's own ----------------------
	add("spawn", {label = "Spawn", color = Color("3bceac"), size = Vector2(56, 56)})
	add("goal", {label = "Goal", color = Color("ffd23f"), size = Vector2(64, 96)})
	add("platform", {label = "Platform", color = Color("8d7bd8"), size = Vector2(160, 28), props = [
		param("width", 160.0, 32.0, 1280.0, 16.0),
		flag("one_way", false),
		param("move_beats", 0.0, 0.0, 16.0, 1.0, "Moves back and forth over this many beats (0 = still)"),
		param("move_y", 0.0, -400.0, 400.0, 8.0),
	]})
	add("spike", {label = "Spike", color = Color("ff5d8f"), size = Vector2(48, 40), props = [
		choice("on_beat", ["always", "on beat", "off beat"], 0),
	]})
	add("coin", {label = "Coin", color = Color("ffb84d"), size = Vector2(32, 32), props = [
		param("value", 1.0, 1.0, 10.0, 1.0),
	]})
	add("cat", {label = "Cat", color = Color("ffffff"), size = Vector2(80, 80), props = [
		choice("dance", ["bob", "spin", "hop"], 0),
		param("scale", 1.0, 0.25, 4.0, 0.05),
	]})


## Registers an entity type. `def` keys: label, color, size, scene, props.
func add(type: String, def: Dictionary) -> void:
	var d := {label = type.capitalize(), color = Color.WHITE, size = Vector2(64, 64), scene = "", props = []}
	d.merge(def, true)
	types[type] = d
	if not order.has(type):
		order.append(type)


func has(type: String) -> bool:
	return types.has(type)


func get_def(type: String) -> Dictionary:
	return types.get(type, {})


func default_props(type: String) -> Dictionary:
	var out := {}
	for p: Dictionary in types.get(type, {}).get("props", []):
		out[p.key] = p.default
	return out


## Defaults filled in, unknown keys kept, and every value cast to its spec's
## type (JSON turns every number into a float).
func clean_props(type: String, raw: Dictionary) -> Dictionary:
	var out := raw.duplicate(true)
	for p: Dictionary in types.get(type, {}).get("props", []):
		var v: Variant = out.get(p.key, p.default)
		if p.has("options"):
			v = clampi(int(v), 0, p.options.size() - 1)
		elif p.default is bool:
			v = bool(v)
		else:
			v = float(v)
		out[p.key] = v
	return out


## Placeholder size in the world, honouring a `width` prop if there is one.
func size_of(e: Dictionary) -> Vector2:
	var s: Vector2 = get_def(e.type).get("size", Vector2(64, 64))
	if e.props.has("width"):
		s.x = float(e.props.width)
	if e.props.has("scale"):
		s *= float(e.props.scale)
	return s


func lane_count() -> int:
	return LANES.size()


# --- prop specs (same shape as UiKit.params expects) -----------------------

static func param(key: String, default: float, lo: float, hi: float, step := 0.01, tip := "") -> Dictionary:
	return {key = key, label = key.capitalize(), default = default, min = lo, max = hi, step = step, tip = tip}


static func choice(key: String, options: Array, default := 0) -> Dictionary:
	return {key = key, label = key.capitalize(), default = default, options = options}


static func flag(key: String, default := false) -> Dictionary:
	return {key = key, label = key.capitalize(), default = default}
