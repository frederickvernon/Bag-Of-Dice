class_name DiceSounds
extends Node
## Dice sounds synthesised in code (no audio files): felt thud, rim knock, die-on-die click.
## Pitch varies slightly each time so repeated hits don't sound mechanical.

@export var enabled: bool = true
## Overall volume (dB).
@export var volume_db: float = -4.0
## Impacts slower than this (units/s) are silent — settling jitter.
@export var min_impact_speed: float = 1.0
## Impact speed that plays at full volume.
@export var max_impact_speed: float = 14.0
## Cap on sounds per burst window (s), so many dice landing at once don't turn into noise.
@export var max_sounds_per_burst: int = 5
@export var burst_window: float = 0.05

const MIX_RATE: int = 22050
const VOICES: int = 10

var _streams: Dictionary = {}  # kind -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _burst_start: float = -1.0
var _burst_count: int = 0
var _time: float = 0.0


func _ready() -> void:
	_streams["felt"] = _make_sound(0.11, _felt_sample)
	_streams["wood"] = _make_sound(0.09, _wood_sample)
	_streams["click"] = _make_sound(0.06, _click_sample)
	for i: int in VOICES:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func _process(delta: float) -> void:
	_time += delta


## Stops and releases streams so quitting mid-sound doesn't leave the audio engine holding them.
func _exit_tree() -> void:
	stop_all()
	for p: AudioStreamPlayer in _players:
		p.stream = null


func stop_all() -> void:
	for p: AudioStreamPlayer in _players:
		p.stop()


## A die hit something at `speed` (units/s). `kind`: "felt", "wood",
## "click" (another die) or "cup" (the hand: a softer click).
func play_impact(kind: String, speed: float) -> void:
	if speed < min_impact_speed:
		return
	var strength: float = clampf((speed - min_impact_speed) / (max_impact_speed - min_impact_speed), 0.0, 1.0)
	if kind == "cup":
		play("click", strength * 0.6)
	else:
		play(kind, strength)


## Plays `kind` at `strength` 0–1.
func play(kind: String, strength: float) -> void:
	if not enabled or not _streams.has(kind):
		return
	if _time - _burst_start > burst_window:
		_burst_start = _time
		_burst_count = 0
	if _burst_count >= max_sounds_per_burst:
		return
	_burst_count += 1
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _streams[kind]
	p.volume_db = volume_db + linear_to_db(lerpf(0.12, 1.0, strength))
	p.pitch_scale = randf_range(0.88, 1.15)
	p.play()


# Sound synthesis: each sound is noise plus a few tones with a fast decay.

static func _make_sound(seconds: float, sample_at: Callable) -> AudioStreamWAV:
	var count: int = int(seconds * MIX_RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	var state: Dictionary = { "low": 0.0 }
	for i: int in count:
		var t: float = float(i) / MIX_RATE
		var s: float = clampf(sample_at.call(t, state), -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


## Soft, muffled thud: low-passed noise plus a low tone.
static func _felt_sample(t: float, state: Dictionary) -> float:
	state["low"] = lerpf(state["low"], randf_range(-1.0, 1.0), 0.12)
	var env: float = exp(-t / 0.022)
	return (state["low"] * 1.6 + sin(TAU * 150.0 * t) * 0.5) * env * 0.8


## Hollow wooden knock: two mid tones and a little noise.
static func _wood_sample(t: float, _state: Dictionary) -> float:
	var env: float = exp(-t / 0.018)
	return (sin(TAU * 620.0 * t) * 0.6 + sin(TAU * 1130.0 * t) * 0.35
			+ randf_range(-1.0, 1.0) * 0.25 * exp(-t / 0.004)) * env


## Sharp plastic click: bright tones and a burst of noise.
static func _click_sample(t: float, _state: Dictionary) -> float:
	var env: float = exp(-t / 0.007)
	return (sin(TAU * 2900.0 * t) * 0.5 + sin(TAU * 4700.0 * t) * 0.3
			+ randf_range(-1.0, 1.0) * 0.5) * env
