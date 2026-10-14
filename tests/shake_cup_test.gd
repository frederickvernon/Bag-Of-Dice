extends "res://tests/app_test.gd"
## Shaking dice in the hand (Fireball, 8d6), with simulated accelerometer
## readings: every die moves around while shaking, none escapes the cup,
## and stopping the shake throws them onto the table. Repeated 5 times.

var _main: Node
var _roller: DiceRoller
var _shake: ShakeDetector
var _shaking: bool = false
var _time: float = 0.0
## Die -> distance travelled while shaking.
var _travel: Dictionary = {}


func _init() -> void:
	test_name = "SHAKE CUP"


func _process(delta: float) -> bool:
	if _shake == null:
		return false
	# Like a real phone, the sensor always reports: shaking, or held still.
	_time += delta
	var reading: Vector3 = Vector3(sin(_time * TAU * 5.0) * 30.0, -9.8, 0.0) if _shaking else Vector3(0.0, -9.8, 0.0)
	_shake.process_reading(reading, delta)
	if _shaking:
		for d: Die in _travel:
			_travel[d] += d.linear_velocity.length() * delta
	return false


func run() -> void:
	_main = launch_main()
	await frames(2)
	_roller = _main.get_node("DiceRoller")
	_shake = _main.get_node("ShakeDetector")
	_shake.set_process(false)  # the test feeds it readings instead
	_main.call("_on_set_chosen", (_main.get("_store") as DiceSetStore).sets[0]["id"])

	for attempt: int in 5:
		_main.call("_on_roll_button_pressed")  # Roll: dice go into the hand
		await frames(60)
		_travel.clear()
		for d: Die in _roller.get_active_dice():
			_travel[d] = 0.0
		_shaking = true
		await frames(80)
		if attempt == 0:
			snap("shaking")
		var least: float = INF
		for d: Die in _travel:
			least = minf(least, _travel[d])
		check(least > 1.0, "attempt %d: every die moved while shaking (least %.1f units)" % [attempt, least])

		var inside: AABB = (_main.get_node("DiceHand").get("_inside") as AABB).grow(0.4)
		_shaking = false
		var escaped: bool = false
		for i: int in 30:
			if _roller.is_rolling():
				break
			for d: Die in _roller.get_active_dice():
				if not inside.has_point(d.global_position):
					escaped = true
			await process_frame
		check(not escaped, "attempt %d: no die escaped the cup" % attempt)

		var results: Array = await _roller.roll_finished  # stopping the shake throws
		var on_table: bool = true
		for d: Die in _roller.get_active_dice():
			var p: Vector3 = _roller.to_local(d.global_position)
			if absf(p.x) > 4.5 or absf(p.z) > 7.5 or p.y > 2.0:
				on_table = false
		check(results.size() == 8 and on_table, "attempt %d: stopping the shake threw all dice onto the table" % attempt)
		await frames(30)
