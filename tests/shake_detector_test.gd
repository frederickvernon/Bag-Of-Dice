extends "res://tests/app_test.gd"
## Shake detector with simulated readings, with and without a gravity sensor:
## real shakes throw; a bump, tilt, flip, or shake while not armed doesn't.

const DT: float = 1.0 / 60.0
const G: Vector3 = Vector3(0, -9.8, 0)

var _detector: ShakeDetector
var _events: Array[String] = []
var _use_sensor: bool = false


func _init() -> void:
	test_name = "SHAKE DETECTOR"
	uses_app = false


func run() -> void:
	_detector = ShakeDetector.new()
	_detector.set_process(false)
	root.add_child(_detector)
	_detector.shake_started.connect(func() -> void: _events.append("started"))
	_detector.shake_finished.connect(func(_s: float) -> void: _events.append("finished"))

	var still: Callable = func(_t: float) -> Vector3: return G
	var tilt: Callable = func(t: float) -> Vector3: return G.rotated(Vector3.RIGHT, t * PI / 2.0)
	var flip: Callable = func(t: float) -> Vector3: return G.rotated(Vector3.RIGHT, minf(t / 0.3, 1.0) * PI)
	for sensor: bool in [true, false]:
		_use_sensor = sensor
		var how: String = "with gravity sensor" if sensor else "without gravity sensor"
		_expect_throw(true, "gentle shake throws (%s)" % how, true,
				func(t: float) -> Vector3: return G + Vector3(sin(t * TAU * 5), 0, 0) * 18.0, still)
		_expect_throw(true, "hard shake throws (%s)" % how, true,
				func(t: float) -> Vector3: return G + Vector3(sin(t * TAU * 6), cos(t * TAU * 6) * 0.5, 0) * 45.0, still)
		_expect_throw(false, "a single bump doesn't throw (%s)" % how, true,
				func(t: float) -> Vector3: return G + (Vector3(20, 0, 0) if t < 0.05 else Vector3.ZERO), still)
		_expect_throw(false, "tilting the phone slowly doesn't throw (%s)" % how, true, tilt, tilt)
		_expect_throw(false, "flipping the phone over doesn't throw (%s)" % how, true, flip, flip)
		_expect_throw(false, "shaking while not armed is ignored (%s)" % how, false,
				func(t: float) -> Vector3: return G + Vector3(sin(t * TAU * 5), 0, 0) * 30.0, still)


## 1 s still, then 1 s of `reading` (armed or not), then 1 s held still.
func _expect_throw(should_throw: bool, what: String, armed: bool, reading: Callable, gravity: Callable) -> void:
	_events.clear()
	_detector.armed = false
	_feed(1.0, func(_t: float) -> Vector3: return G, func(_t: float) -> Vector3: return G)
	_detector.armed = armed
	_feed(1.0, reading, gravity)
	var end: Vector3 = gravity.call(1.0)
	_feed(1.0, func(_t: float) -> Vector3: return end, func(_t: float) -> Vector3: return end)
	var threw: bool = _events == ["started", "finished"]
	check(threw == should_throw and (should_throw or _events.is_empty()), what)


func _feed(seconds: float, reading: Callable, gravity: Callable) -> void:
	var t: float = 0.0
	while t < seconds:
		_detector.process_reading(reading.call(t), DT, gravity.call(t) if _use_sensor else Vector3.ZERO)
		t += DT
