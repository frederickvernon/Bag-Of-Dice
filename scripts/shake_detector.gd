class_name ShakeDetector
extends Node
## Reports a deliberate accelerometer shake once it stops; only listens while `armed`.
## Gravity is removed using the phone's gravity sensor, or a slow running average if it has none.

## For UI feedback.
signal shake_started
## `strength` is 0–1, from the hardest jolt in the shake.
signal shake_finished(strength: float)

## Movement (m/s², gravity removed) that counts as shaking.
@export var threshold: float = 12.0
## Movement (m/s²) treated as the hardest possible shake (strength 1.0).
@export var max_movement: float = 40.0
## A shake needs this many separate jolts above the threshold...
@export var min_jolts: int = 2
## ...or this many seconds above it in total, for circular shakes that never dip.
## A single bump meets neither, so it doesn't throw.
@export var min_shake_time: float = 0.35
## Seconds below the threshold before the shake counts as over.
@export var stop_delay: float = 0.25
## Gravity estimate time constant (seconds): longer is steadier mid-shake, slower to follow a tilt.
@export var gravity_time_constant: float = 0.6

## 0–1, 0 when disarmed. Rises instantly, fades over about 0.5 s; visual feedback only.
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


## One accelerometer reading (m/s²) plus the gravity sensor's (zero if none).
## Public so tests can feed simulated readings.
func process_reading(reading: Vector3, delta: float, sensor_gravity: Vector3 = Vector3.ZERO) -> void:
	if sensor_gravity != Vector3.ZERO:
		_gravity = sensor_gravity
	else:
		# Track even while disarmed so the estimate has settled before arming.
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


## Debug desktop builds only: hold S to fake a shake, since a Mac has no accelerometer.
func _debug_shake(delta: float) -> Vector3:
	if not OS.is_debug_build() or OS.has_feature("mobile"):
		return Vector3.ZERO
	if not Input.is_physical_key_pressed(KEY_S):
		_debug_phase = 0.0
		return Vector3.ZERO
	_debug_phase += delta * TAU * 6.0  # about 6 shakes per second
	return Vector3(sin(_debug_phase), 0.0, 0.0) * 25.0
