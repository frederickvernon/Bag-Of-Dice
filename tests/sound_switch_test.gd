extends "res://tests/app_test.gd"
## The sound switch: on by default, muting silences a whole roll, and the
## choice is remembered on the next launch.

func _init() -> void:
	test_name = "SOUND SWITCH"


func run() -> void:
	var main: Node = launch_main()
	await frames(2)
	var toggle: SoundToggle = main.get_node("UI/Root/SoundToggle")
	var sounds: DiceSounds = main.get_node("DiceSounds")
	var settings: AppSettings = main.get("_settings")
	# (The sound engine itself is briefly off during the start menu's silent
	# practice throw, so check the setting and the button.)
	check(toggle.button_pressed and settings.sound, "sound is on by default")

	toggle.button_pressed = false  # same as a tap
	await frames(5)
	check(not sounds.enabled, "tapping the speaker mutes the sounds")
	main.call("_on_set_chosen", (main.get("_store") as DiceSetStore).sets[0]["id"])
	main.call("_start_roll")
	var players: Array = sounds.get("_players")
	var roller: DiceRoller = main.get_node("DiceRoller")
	var any_played: bool = false
	while roller.is_rolling():
		for p: AudioStreamPlayer in players:
			if p.playing:
				any_played = true
		await process_frame
	check(not any_played, "a whole roll makes no sound while muted")

	main.queue_free()
	await frames(2)
	var again: Node = launch_main()
	await frames(2)
	check(not (again.get_node("UI/Root/SoundToggle") as SoundToggle).button_pressed
			and not (again.get_node("DiceSounds") as DiceSounds).enabled, "muted is remembered on the next launch")
