extends "res://tests/app_test.gd"
## First-run tips: hidden on the menu, "tap to pick up" on the table, "flick to
## throw" while holding the dice, gone (and remembered) after the first throw;
## "Show tips again" brings them back.

func _init() -> void:
	test_name = "TUTORIAL"


func run() -> void:
	var main: Node = launch_main()
	await frames(2)
	var tip: TutorialOverlay = main.get_node("UI/Root/TutorialOverlay")
	var label: Label = tip.get("_label")
	var menu: StartMenu = main.get_node("UI/Root/StartMenu")
	var roller: DiceRoller = main.get_node("DiceRoller")
	var settings: AppSettings = main.get("_settings")
	check(not tip.visible, "no tip over the start menu")

	menu.continue_pressed.emit()
	await frames(10)
	check(tip.visible and label.text.begins_with("Tap the table") and tip.get("_kind") == "tap",
			"on the table: 'Tap the table to pick up the dice' with a tap animation")
	snap("tip_tap")
	main.call("_on_roll_button_pressed")
	await frames(30)
	check(tip.visible and label.text.contains("flick up") and tip.get("_kind") == "flick",
			"holding the dice: 'flick up to throw' with a flick animation")
	snap("tip_flick")
	main.call("_on_roll_button_pressed")
	await frames(3)
	check(not tip.visible, "the tip disappears once the dice are thrown")
	await roller.roll_finished
	await frames(10)
	var saved: AppSettings = AppSettings.new(settings.path)
	saved.load_settings()
	check(not tip.visible and saved.tutorial_done, "after the first throw the tips stay gone, and that's saved")

	main.queue_free()
	await frames(2)
	main = launch_main()
	await frames(2)
	tip = main.get_node("UI/Root/TutorialOverlay")
	(main.get_node("UI/Root/StartMenu") as StartMenu).continue_pressed.emit()
	await frames(10)
	check(not tip.visible, "no tips on the next launch")

	(main.get_node("UI/Root/SettingsSheet") as SettingsSheet).replay_tips_pressed.emit()
	await frames(3)
	check(tip.visible, "'Show tips again' brings them back")
	(main.get_node("UI/Root/SettingsSheet") as SettingsSheet).changed.emit("tap_to_roll", false)
	await frames(3)
	check(tip.visible and (tip.get("_label") as Label).text.begins_with("Press Roll") and tip.get("_kind") == "",
			"with Tap or swipe off, the tip says Press Roll, without the gesture")
