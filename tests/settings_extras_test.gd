extends "res://tests/app_test.gd"
## Vibration and fast roll settings, duplicating a set, copying a roll as text.

func _init() -> void:
	test_name = "SETTINGS & EXTRAS"


func run() -> void:
	var main: Node = launch_main()
	await frames(2)
	var settings: AppSettings = main.get("_settings")
	var haptics: DiceHaptics = main.get_node("DiceHaptics")
	var sheet: SettingsSheet = main.get_node("UI/Root/SettingsSheet")
	var store: DiceSetStore = main.get("_store")
	var roller: DiceRoller = main.get_node("DiceRoller")
	check(settings.haptics and haptics.enabled and not settings.fast_roll, "vibration starts on and fast roll off")

	# Settings switches are applied and saved.
	(main.get_node("UI/Root/StartMenu") as StartMenu).settings_pressed.emit()
	await frames(10)
	sheet.changed.emit("haptics", false)
	sheet.changed.emit("fast_roll", true)
	var saved: AppSettings = AppSettings.new(settings.path)
	saved.load_settings()
	check(not haptics.enabled and not saved.haptics and saved.fast_roll, "vibration off and fast roll on are applied and saved")
	main.call("_go_back")

	# Fast roll speeds up only the roll itself.
	main.call("_on_set_chosen", store.sets[0]["id"])
	main.call("_start_roll")
	await frames(2)
	var fast_while_rolling: bool = is_equal_approx(Engine.time_scale, 1.75)
	await roller.roll_finished
	await frames(2)
	check(fast_while_rolling and is_equal_approx(Engine.time_scale, 1.0), "fast roll runs at 1.75x while rolling, normal speed after")
	sheet.changed.emit("fast_roll", false)
	main.call("_start_roll")
	await frames(2)
	check(is_equal_approx(Engine.time_scale, 1.0), "with fast roll off, rolls run at normal speed")
	await roller.roll_finished

	# Duplicate a set.
	var editor: SetEditor = main.get_node("UI/Root/SetEditor")
	var risk: Dictionary = store.sets[1]
	editor.open(risk)
	editor.duplicate_set()
	editor.call("_save")
	await frames(3)
	var copy: Dictionary = store.sets[-1]
	check(store.sets.size() == 4 and copy["name"] == "Risk (copy)" and copy["id"] != risk["id"]
			and copy["dice"] == risk["dice"] and copy["pick_dice"] == risk["pick_dice"],
			"Duplicate saves a new 'Risk (copy)' with the same dice and options")
	check(store.get_set(risk["id"])["name"] == "Risk", "the original set is unchanged")
	editor.open(copy)
	editor.duplicate_set()
	editor.cancel_editing()
	check(store.sets.size() == 4, "Duplicate then Cancel adds nothing")

	# Copy a roll as text.
	var entry: Dictionary = RollHistory.make_entry("", "Risk", [
		{ "type": "d6", "value": 6, "color": "#d23333", "label": "Attack", "parts": [6] },
		{ "type": "d6", "value": 5, "color": "#d23333", "label": "Attack", "parts": [5] },
		{ "type": "d6", "value": 4, "color": "#f2edd9", "label": "Defend", "parts": [4] },
	], 1_000_000)
	var text: String = RollHistory.format_entry(entry, 1_000_000)
	check(text.begins_with("Risk (") and text.ends_with("): Attack (d6): 6  5, Defend (d6): 4  (total 15)"),
			"a roll copies as plain text: %s" % text)
	var hist: HistorySheet = main.get_node("UI/Root/HistorySheet")
	hist.open((main.get("_history") as RollHistory).entries)
	await frames(5)
	var copy_button: Button = _find_button(hist, "Copy")
	copy_button.pressed.emit()
	check(copy_button.text == "Copied", "the Copy button confirms with 'Copied'")
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.clipboard_get().begins_with("Fireball"), "the clipboard holds the copied roll")


func _find_button(node: Node, text: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text == text:
			return child
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null
