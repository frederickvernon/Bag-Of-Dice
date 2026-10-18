extends "res://tests/app_test.gd"
## Start menu: opens first over a silent practice throw, quick rolls aren't
## saved as sets, and Back returns to the menu.

func _init() -> void:
	test_name = "START MENU"


func run() -> void:
	var main: Node = launch_main()
	await frames(2)
	var menu: StartMenu = main.get_node("UI/Root/StartMenu")
	var roller: DiceRoller = main.get_node("DiceRoller")
	var history: RollHistory = main.get("_history")
	var store: DiceSetStore = main.get("_store")
	var sets_button: Button = main.get_node("UI/Root/BottomBar/SetsButton")
	check(menu.visible, "the app opens on the menu")
	snap("menu")

	var waited_ms: int = Time.get_ticks_msec()
	while main.get("_warming") and Time.get_ticks_msec() - waited_ms < 20000:
		await process_frame
	check(not main.get("_warming") and history.entries.is_empty(), "the practice throw finished and wasn't logged")

	menu.quick_roll.emit(["d6", "d6"] as Array[String])
	await frames(5)
	check(not menu.visible and roller.get_dice().size() == 2 and sets_button.text == "Quick roll",
			"Quick roll 2d6 goes to the table with 2 dice")
	main.call("_on_roll_button_pressed")
	main.call("_on_roll_button_pressed")
	var results: Array = await roller.roll_finished
	check(results.size() == 2 and history.entries[0]["set_name"] == "Quick roll", "a quick roll is logged as 'Quick roll'")

	press_back(main)
	await frames(5)
	check(menu.visible and (menu.get("_continue_button") as Button).text == "Continue: Quick roll",
			"Back goes to the menu, and Continue offers the quick roll")

	menu.custom_quick_pressed.emit()
	var editor: SetEditor = main.get_node("UI/Root/SetEditor")
	editor.call("_add_die", "d20")
	editor.call("_add_die", "d4")
	editor.call("_save")
	await frames(5)
	check(not menu.visible and roller.get_dice().size() == 2 and store.sets.size() == 3,
			"a custom quick roll goes to the table and isn't saved as a set")

	press_back(main)
	menu.sets_pressed.emit()
	await frames(20)
	(main.get_node("UI/Root/SetDrawer") as SetDrawer).set_chosen.emit(store.sets[1]["id"])
	await frames(5)
	check(not menu.visible and sets_button.text == "Risk", "choosing a set from the menu goes to the table")

	press_back(main)
	menu.settings_pressed.emit()
	await frames(20)
	var settings: SettingsSheet = main.get_node("UI/Root/SettingsSheet")
	settings.changed.emit("sound", false)
	await frames(3)
	check(not (main.get_node("DiceSounds") as DiceSounds).enabled and not (main.get("_settings") as AppSettings).sound,
			"muting in Settings turns the sounds off")
	press_back(main)
	await frames(20)
	check(not settings.is_open() and menu.visible, "Back closes Settings, leaving the menu")

	# Android sends one Back press as two events; it must only step back once.
	menu.continue_pressed.emit()
	await frames(5)
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	main.set("_last_back_ms", -1000)
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	main.call("_unhandled_input", cancel)
	await frames(5)
	check(menu.visible, "one Back press on the table (sent twice, as Android does) goes to the menu, not out of the app")
