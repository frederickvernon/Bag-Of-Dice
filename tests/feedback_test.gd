extends "res://tests/app_test.gd"
## Sound effects and vibration: which hits make a sound, harder is louder, at most
## 5 sounds per 50 ms, muting stops what's playing; buzz length 8–30 ms by hit
## strength, at most one buzz per 60 ms, none for soft hits or dice in the hand.

func _init() -> void:
	test_name = "SOUND & VIBRATION"
	uses_app = false


func run() -> void:
	var sounds: DiceSounds = DiceSounds.new()
	root.add_child(sounds)
	await frames(2)
	var players: Array = sounds.get("_players")

	sounds.play_impact("felt", 0.5)
	check(_playing(players) == 0, "settling jitter (below 1 unit/s) is silent")
	for kind: String in ["felt", "wood", "click", "cup"]:
		sounds.stop_all()
		await create_timer(0.06).timeout
		sounds.play_impact(kind, 8.0)
		check(_playing(players) == 1, "a %s hit plays a sound" % kind)

	sounds.stop_all()
	await create_timer(0.06).timeout
	sounds.play_impact("felt", 2.0)
	var soft: float = _latest(sounds, players).volume_db
	await create_timer(0.06).timeout
	sounds.play_impact("felt", 14.0)
	var hard: float = _latest(sounds, players).volume_db
	check(hard > soft + 6.0, "harder hits are louder (%.1f dB vs %.1f dB)" % [hard, soft])

	sounds.stop_all()
	await create_timer(0.06).timeout
	for i: int in 9:
		sounds.play_impact("click", 10.0)
	check(_playing(players) == 5, "many hits at once play at most 5 sounds (%d)" % _playing(players))
	sounds.stop_all()
	check(_playing(players) == 0, "muting stops anything playing")
	sounds.enabled = false
	await create_timer(0.06).timeout
	sounds.play_impact("felt", 10.0)
	check(_playing(players) == 0, "with sound off, nothing plays")

	var haptics: DiceHaptics = DiceHaptics.new()
	root.add_child(haptics)
	haptics.play_impact("felt", 2.0)
	check(haptics.last_duration_ms == 0, "a soft hit (below 2.5 units/s) doesn't vibrate")
	haptics.play_impact("cup", 14.0)
	check(haptics.last_duration_ms == 0, "dice hitting the hand don't vibrate")
	haptics.play_impact("felt", 3.0)
	var weak: int = haptics.last_duration_ms
	haptics.play_impact("felt", 14.0)
	check(haptics.last_duration_ms == weak, "at most one buzz per 60 ms")
	await create_timer(0.08).timeout
	haptics.play_impact("felt", 14.0)
	check(weak >= 8 and weak < 12 and haptics.last_duration_ms == 30, "buzzes last 8–30 ms by hit strength (%d, %d)" % [weak, haptics.last_duration_ms])
	haptics.enabled = false
	haptics.last_duration_ms = 0
	await create_timer(0.08).timeout
	haptics.play_impact("felt", 14.0)
	check(haptics.last_duration_ms == 0, "with vibration off, nothing buzzes")


func _playing(players: Array) -> int:
	var n: int = 0
	for p: AudioStreamPlayer in players:
		if p.playing:
			n += 1
	return n


func _latest(sounds: DiceSounds, players: Array) -> AudioStreamPlayer:
	var next: int = sounds.get("_next_player")
	return players[(next - 1 + players.size()) % players.size()]
