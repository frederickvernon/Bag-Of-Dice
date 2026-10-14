class_name ShakeDetector
extends Node
## Watches the phone's accelerometer for a deliberate shake and reports it when
## the shaking stops. Only listens while `armed` is true.
##
## The accelerometer always includes gravity (about 9.8 m/s² pointing down),
## which must be subtracted to leave the phone's own movement. Most phones
## have a "gravity" sensor that reports it directly; if not, a slowly-updated
## average of the readings is used as the estimate instead.

## Shaking has begun (for UI feedback).
signal shake_started
## Shaking has stopped. `strength` is 0–1, from the hardest jolt in the shake.
signal shake_finished(strength: float)

## Movement (m/s², gravity removed) that counts as shaking.
@export var threshold: float = 12.0
## Movement treated as the hardest possible shake (strength 1.0).
@export var max_movement: float = 40.0
## It counts as a shake after this many separate jolts above the threshold...
@export var min_jolts: int = 2
## ...or after this long above it in total (a vigorous circular shake can
## stay above the threshold the whole time). A single bump of the phone
## meets neither, so it doesn't throw.
@export var min_shake_time: float = 0.35
## How long movement must stay below the threshold for the shake to be over.
@export var stop_delay: float = 0.25
## How quickly the gravity estimate follows the readings, in seconds. Longer
## is steadier during a shake but slower to adapt when the phone is tilted.
@export var gravity_time_constant: float = 0.6

## 0–1: how hard the phone is moving right now (0 when not armed). Rises
## instantly and fades over about half a second; for visual feedback only.
var level: float = 0.0

var armed: bool = false:
	set(value):
		armed = value
		_reset()

var _gravity: Vector3 = Vector3.ZERO
var _has_gravity: bool = false
var _jolts: int = 0
var _above: bool = false
var _peak: float = 0.0
var _quiet_time: float = 0.0
var _time_above: float = 0.0
var _started: bool = false
var _debug_phase: float = 0.0


func _process(delta: float) -> void:
	process_reading(Input.get_accelerometer() + _debug_shake(delta), delta, Input.get_gravity())


## Handles one accelerometer reading (m/s²), plus the gravity sensor's reading
## if the phone has one (zero if not). Called every frame; public so tests can
## feed in simulated readings.
func process_reading(reading: Vector3, delta: float, sensor_gravity: Vector3 = Vector3.ZERO) -> void:
	if sensor_gravity != Vector3.ZERO:
		_gravity = sensor_gravity
	else:
		# Keep the estimate up to date even while disarmed, so it's already
		# settled by the time the player arms a roll.
		if not _has_gravity:
			_gravity = reading
			_has_gravity = true
		_gravity = _gravity.lerp(reading, 1.0 - exp(-delta / gravity_time_constant))

	var movement: float = (reading - _gravity).length()
	var target: float = 0.0
	if armed:
		target = clampf((movement - threshold * 0.5) / (max_movement - threshold * 0.5), 0.0, 1.0)
	level = maxf(target, level - delta * 2.0)

	if not armed:
		return

	if movement >= threshold:
		if not _above:
			_above = true
			_jolts += 1
		_time_above += delta
		_peak = maxf(_peak, movement)
		_quiet_time = 0.0
		if not _started and _is_shake():
			_started = true
			shake_started.emit()
		return

	_above = false
	if _jolts == 0:
		return
	_quiet_time += delta
	if _quiet_time < stop_delay:
		return
	if _is_shake():
		var strength: float = clampf((_peak - threshold) / (max_movement - threshold), 0.0, 1.0)
		_reset()
		shake_finished.emit(strength)
	else:
		_reset()  # just a bump — ignore it


func _is_shake() -> bool:
	return _jolts >= min_jolts or _time_above >= min_shake_time


func _reset() -> void:
	_time_above = 0.0
	_started = false
	_jolts = 0
	_above = false
	_peak = 0.0
	_quiet_time = 0.0


## Desktop testing aid (debug builds on computers only): hold S to fake a
## shake, since a Mac has no accelerometer.
func _debug_shake(delta: float) -> Vector3:
	if not OS.is_debug_build() or OS.has_feature("mobile"):
		return Vector3.ZERO
	if not Input.is_physical_key_pressed(KEY_S):
		_debug_phase = 0.0
		return Vector3.ZERO
	_debug_phase += delta * TAU * 6.0  # about 6 shakes per second
	return Vector3(sin(_debug_phase), 0.0, 0.0) * 25.0
