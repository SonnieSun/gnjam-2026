class_name SongClock
extends Node
## The time a level runs on: the song's own playback position, turned into
## beats with the level's bpm and offset.
##
## Never count time with delta alone against real music: it drifts. Here time
## advances by delta for smoothness, and is pulled back to what the audio
## hardware is actually playing whenever they disagree.
##
## Gameplay code should only ask: beat, time, and hits(lane) (how many notes
## of a lane have passed, and how long ago the latest one was). Chart notes
## and the player's own taps both count as hits, so cats/platforms/lights
## that react to them don't care which it was.

signal beat_crossed(beat: int)
## A chart note reached the playhead.
signal note_passed(n: Dictionary)
signal hit(lane: int, manual: bool)
signal started
signal stopped

const RESYNC_SEC := 0.04

var level: LevelData
var player := AudioStreamPlayer.new()
var playing := false
## Seconds on the song's timeline (negative = before the song starts).
var time := 0.0
var beat := 0.0
## Play the lane's sound on every chart note (hit sounds) and a tick per beat.
var hitsounds := true
var metronome := false

var _count: Array[int] = []
var _last: Array[float] = []


func _init(lvl: LevelData = null) -> void:
	level = lvl if lvl else LevelData.new()
	for i in Registry.lane_count():
		_count.append(0)
		_last.append(-1e6)


func _ready() -> void:
	add_child(player)


# --- song ------------------------------------------------------------------

## Loads the level's song (meta.song). Returns false if there is none or it
## can't be read; the clock then simply runs silent.
func load_song() -> bool:
	player.stream = load_stream(str(level.meta.song))
	return player.stream != null


static func load_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


## Song length in beats, or the level's own length when there is no song.
func length_beats() -> float:
	if player.stream:
		return maxf(level.sec_to_beat(player.stream.get_length()), 1.0)
	return float(level.meta.length)


# --- transport -------------------------------------------------------------

func play() -> void:
	if playing:
		return
	playing = true
	_start_audio()
	started.emit()


func pause() -> void:
	if not playing:
		return
	playing = false
	player.stop()
	stopped.emit()


func toggle() -> void:
	if playing:
		pause()
	else:
		play()


func seek_beat(b: float) -> void:
	seek_time(level.beat_to_sec(b))


func seek_time(t: float) -> void:
	time = t
	beat = level.sec_to_beat(t)
	if playing:
		_start_audio()


func _start_audio() -> void:
	if player.stream and time >= 0.0 and time < player.stream.get_length():
		player.play(time)
	else:
		player.stop()


## What the speakers are playing right now, in song seconds.
func _audio_time() -> float:
	return player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()


func _process(delta: float) -> void:
	if not playing:
		return
	advance(delta)


## Moves forward by `seconds`, firing every beat and note passed. Public so
## tests and tools can drive the clock without real time.
func advance(seconds: float) -> void:
	var before := beat
	time += seconds
	if player.playing:
		var at := _audio_time()
		if absf(at - time) > RESYNC_SEC:
			time = at
	elif player.stream and time >= 0.0 and time < player.stream.get_length():
		player.play(time) # the song starts after a count-in before beat 0
	beat = level.sec_to_beat(time)
	if beat <= before:
		return
	for b in range(floori(before) + 1, floori(beat) + 1):
		beat_crossed.emit(b)
		if metronome:
			Sfx.play("tick", 1.5 if posmod(b, 4) == 0 else 1.0)
	for n in level.notes_between(before, beat):
		_fire(int(n.lane), float(n.b), false)
		note_passed.emit(n)
		if hitsounds:
			Sfx.play(Registry.LANES[int(n.lane)].sound)


# --- hits ------------------------------------------------------------------

## x = number of hits on `lane` so far, y = beats since the latest one.
func hits(lane: int) -> Vector2:
	return Vector2(_count[lane], maxf(0.0, beat - _last[lane]))


## The player pressed a lane by hand (judging is Judge's business).
func tap(lane: int) -> void:
	_fire(lane, beat, true)


func _fire(lane: int, at_beat: float, manual: bool) -> void:
	if lane < 0 or lane >= _count.size():
		return
	_count[lane] += 1
	_last[lane] = at_beat
	hit.emit(lane, manual)
