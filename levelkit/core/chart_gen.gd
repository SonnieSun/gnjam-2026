class_name ChartGen
## Procedural charts. Two sources:
##   patterns  hand-written one-bar rhythms stitched into 4-bar phrases
##             (A A B A'), getting busier through the song
##   onsets    the song's own onsets (tools/analyze_song.py), filtered by
##             strength and snapped to the grid
## Then the same lane rules and spacing limits for both, so every chart is
## playable. Same seed + options = same chart.
##
## Options (all optional):
##   seed        int
##   difficulty  0..1
##   from_bar    first bar with notes (default 1: one bar of count-in)
##   bars        how many bars (default: up to meta.length)
##   onsets      [{ t = seconds, s = strength 0..1 }]  -> onset mode

## One bar = 16 steps. [density 0..3, rhythm]. Add your own: more patterns
## = less repetitive charts.
const PATTERNS: Array = [
	[0, "x.......x......."],
	[0, "x...x...x...x..."],
	[0, "x.......x...x..."],
	[1, "x...x...x...x.x."],
	[1, "x.x.....x.x....."],
	[1, "x...x.x.x...x..."],
	[1, "x..x..x.x..x..x."],
	[2, "x.x.x.x.x.x.x.x."],
	[2, "x..x..x...x.x.x."],
	[2, "x.xxx...x.xxx..."],
	[2, "x...xxx.x...xxx."],
	[3, "x.xxx.xxx.xxx.x."],
	[3, "xxx.xxx.xxx.x.x."],
	[3, "x.x.xxxxx.x.xxxx"],
]


static func generate(level: LevelData, opts := {}) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 1))
	var diff := clampf(float(opts.get("difficulty", 0.5)), 0.0, 1.0)
	var from_bar := int(opts.get("from_bar", 1))
	var bars := int(opts.get("bars", maxi(1, floori(float(level.meta.length) / 4.0) - from_bar)))
	var beats: Array[float]
	if opts.has("onsets") and not (opts.onsets as Array).is_empty():
		beats = _from_onsets(level, opts.onsets, diff, from_bar * 4.0, (from_bar + bars) * 4.0)
	else:
		beats = _from_patterns(rng, diff, from_bar, bars)
	level.chart.clear()
	for n in _assign_lanes(level, rng, beats, diff):
		level.chart.append(n)
	level.sort_chart()
	level.meta.length = maxf(float(level.meta.length), (from_bar + bars) * 4.0)


# --- rhythm ----------------------------------------------------------------

static func _from_patterns(rng: RandomNumberGenerator, diff: float, from_bar: int, bars: int) -> Array[float]:
	var out: Array[float] = []
	var a := ""
	var b := ""
	for i in bars:
		var bar := from_bar + i
		var phrase_pos := i % 4
		if phrase_pos == 0:
			# Busier as the song goes on, busier with difficulty.
			var ramp := float(i) / maxf(1.0, bars - 1)
			var density := roundi(clampf(diff * 2.4 + ramp * 1.2 + rng.randf_range(-0.5, 0.5), 0.0, 3.0))
			a = _pick(rng, density)
			b = _pick(rng, mini(density + 1, 3))
		var rhythm := a
		if phrase_pos == 2:
			rhythm = b
		elif phrase_pos == 3:
			rhythm = _mutate(rng, a)
		# Breathing room: a quiet bar every 8 on easier settings.
		if i % 8 == 7 and diff < 0.6:
			rhythm = "x.......x......."
		for s in 16:
			if rhythm[s] == "x":
				out.append(bar * 4.0 + s / 4.0)
	return out


static func _pick(rng: RandomNumberGenerator, density: int) -> String:
	var pool := PATTERNS.filter(func(p: Array) -> bool: return p[0] == density)
	return pool[rng.randi() % pool.size()][1]


## The phrase's last bar: same idea, one note moved, a variation.
static func _mutate(rng: RandomNumberGenerator, rhythm: String) -> String:
	var s := rng.randi_range(1, 15)
	return rhythm.substr(0, s) + ("." if rhythm[s] == "x" else "x") + rhythm.substr(s + 1)


static func _from_onsets(level: LevelData, onsets: Array, diff: float, from: float, to: float) -> Array[float]:
	var snap := 0.25 if diff > 0.6 else 0.5
	var threshold := lerpf(0.6, 0.1, diff)
	var seen := {}
	var out: Array[float] = []
	for o: Dictionary in onsets:
		if float(o.get("s", 1.0)) < threshold:
			continue
		var b := snappedf(level.sec_to_beat(float(o.t)), snap)
		if b < from or b >= to or seen.has(b):
			continue
		seen[b] = true
		out.append(b)
	out.sort()
	return out


# --- lanes and spacing -----------------------------------------------------

static func _assign_lanes(level: LevelData, rng: RandomNumberGenerator, beats: Array[float], diff: float) -> Array[Dictionary]:
	var lanes := Registry.lane_count()
	var min_gap := lerpf(0.30, 0.10, diff) # seconds between any two notes
	var max_run := 2 if diff < 0.5 else 4 # same lane in a row
	var out: Array[Dictionary] = []
	var last_t := -INF
	var last_lane := -1
	var run := 0
	for i in beats.size():
		var b := beats[i]
		var t := level.beat_to_sec(b)
		if t - last_t < min_gap:
			continue
		# Downbeats lean on lane 0, backbeats on lane 1, the rest anywhere.
		var lane: int
		var in_beat := fposmod(b, 4.0)
		if is_zero_approx(in_beat):
			lane = 0
		elif is_equal_approx(in_beat, 1.0) or is_equal_approx(in_beat, 3.0):
			lane = 1 % lanes
		elif lanes > 2 and rng.randf() < 0.75:
			lane = rng.randi_range(2, lanes - 1) # off-beats mostly on the upper lanes
		else:
			lane = rng.randi_range(0, lanes - 1)
		if lane == last_lane and run >= max_run:
			lane = (lane + rng.randi_range(1, lanes - 1)) % lanes
		run = run + 1 if lane == last_lane else 1
		last_lane = lane
		last_t = t
		# A hold when there is room before the next note.
		var gap := (beats[i + 1] - b) if i + 1 < beats.size() else 4.0
		var length := 0.0
		if gap >= 2.0 and rng.randf() < 0.25 + diff * 0.3:
			length = floorf(gap * 0.5)
		out.append(LevelData.note(b, lane, length))
		# A chord on strong beats at higher difficulty.
		if lanes > 1 and is_zero_approx(fposmod(b, 2.0)) and rng.randf() < diff * 0.35:
			out.append(LevelData.note(b, (lane + rng.randi_range(1, lanes - 1)) % lanes, 0.0))
	return out


# --- world -----------------------------------------------------------------

## Example: lays out a runner-style world along the chart (x = beat).
## One platform per bar, a coin above every note, a spike for lane-1 notes,
## spawn at the start, goal at the end. Replace with the jam game's rules;
## the point is that geometry generated from the chart lands on the beat.
static func place_runner(level: LevelData, lane_y := -120.0) -> void:
	level.entities.clear()
	var bar_px := level.beat_to_x(4.0)
	var bars := ceili(float(level.meta.length) / 4.0)
	level.add_entity("spawn", Vector2(-level.beat_to_x(1.0), -60))
	for i in bars:
		var w := bar_px - 48.0
		level.add_entity("platform", Vector2(i * bar_px + bar_px / 2.0, 0), {width = w})
	for n in level.chart:
		var x := level.beat_to_x(float(n.b))
		if int(n.lane) == 1:
			level.add_entity("spike", Vector2(x, -34))
		else:
			level.add_entity("coin", Vector2(x, lane_y - int(n.lane) * 56.0))
	level.add_entity("goal", Vector2(bars * bar_px - 60.0, -62))
