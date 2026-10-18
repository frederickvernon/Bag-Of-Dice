extends "res://tests/app_test.gd"
## Re-throw modes in the app: the Settings choice, the set editor option and its
## "Table default (…)" name, the drawer note, the "Re-rolling" note, Clear the
## table lifting dice mid-roll, and Count where they land showing a knocked
## counted die's recorded result in the result bar, the lifted row and history.

func _init() -> void:
	test_name = "RE-THROW SCREENS"


func run() -> void:
	var main: Node = launch_main()
	await frames(2)
	var settings: AppSettings = main.get("_settings")
	var store: DiceSetStore = main.get("_store")
	var roller: DiceRoller = main.get_node("DiceRoller")
	var sheet: SettingsSheet = main.get_node("UI/Root/SettingsSheet")
	var editor: SetEditor = main.get_node("UI/Root/SetEditor")
	var drawer: SetDrawer = main.get_node("UI/Root/SetDrawer")
	var menu: StartMenu = main.get_node("UI/Root/StartMenu")
	var history: RollHistory = main.get("_history")
	var label: Label = main.get("_result_label")

	# Settings: three choices, Clear the table chosen on a fresh install.
	menu.settings_pressed.emit()
	await frames(5)
	var buttons: Dictionary = sheet.get("_mode_buttons")
	check(buttons.size() == 3 and (buttons[RethrowMode.CLEAR] as Button).button_pressed
			and not (buttons[RethrowMode.LIVE] as Button).button_pressed,
			"Settings offers the three modes, with Clear the table chosen")
	var texts: Array[String] = []
	_collect_texts(sheet, texts)
	check(texts.has("Re-throws") and texts.has(RethrowMode.DESCRIPTIONS[RethrowMode.COUNT])
			and texts.has("You can override this for individual dice sets in the set editor."),
			"each mode has its description, with the tip about sets below")
	(buttons[RethrowMode.LIVE] as Button).button_pressed = true
	await frames(2)
	var saved: AppSettings = AppSettings.new(settings.path)
	saved.load_settings()
	check(saved.rethrow_mode == RethrowMode.LIVE and editor.global_rethrow_mode == RethrowMode.LIVE,
			"choosing Live table saves it")
	press_back(main)
	await frames(3)

	# Set editor: four choices; Table default names the global mode and follows it.
	var option: OptionButton = editor.get("_rethrow_option")
	editor.open(store.sets[0])
	check(option.item_count == 4 and option.selected == 0 and option.get_item_text(0) == "Table default (Live table)",
			"the editor offers Table default (Live table) plus the three modes")
	main.call("set_global_rethrow_mode", RethrowMode.CLEAR)
	check(option.get_item_text(0) == "Table default (Clear the table)", "Table default updates when the global mode changes")
	option.select(2)
	option.item_selected.emit(2)
	editor.call("_save")
	await frames(3)
	check(store.sets[0]["rethrow_mode"] == RethrowMode.COUNT, "choosing Count where they land in the editor saves it on the set")
	editor.open_quick()
	check(not (editor.get("_rethrow_row") as Control).visible, "quick rolls have no re-throw option")
	editor.cancel_editing()

	# Drawer note only when a set overrides the default.
	main.call("_open_drawer")
	await frames(3)
	var notes: Array[String] = []
	_collect_texts(drawer, notes)
	var fireball_note: bool = false
	var others_plain: bool = true
	for t: String in notes:
		if t.begins_with("8d6"):
			fireball_note = t.ends_with("·  count where they land")
		elif t.contains("·  live table") or t.contains("·  clear the table") or t.contains("·  count where"):
			others_plain = false
	check(fireball_note and others_plain, "drawer cards note the mode only for a set with its own: %s" % [notes])
	drawer.close()
	await frames(3)

	# Count where they land in the app: knock a counted die; bar, lifted row and history keep its result.
	main.call("_on_set_chosen", store.sets[0]["id"])
	await frames(5)
	var knocked: Array[Die] = []
	var note: Array[String] = []
	roller.rethrow_started.connect(func(_count: int) -> void:
		note.append(label.text)
		if not knocked.is_empty():
			return
		for d: Die in roller.in_play_dice():
			if not d.locked_entry.is_empty():
				d.global_basis = Basis(Vector3.RIGHT, PI * 0.5) * d.global_basis
				d.global_position += Vector3.UP * 0.6
				d.sleeping = false
				knocked.append(d)
				break)
	var got_count: bool = false
	for attempt: int in 4:
		roller.debug_force = "stack"
		main.call("_start_roll")
		await roller.roll_finished
		if not knocked.is_empty():
			got_count = true
			break
	roller.debug_force = ""
	check(got_count and not note.is_empty() and note[0].begins_with("Re-rolling "),
			"a full re-throw shows \"%s\"" % [note[0] if not note.is_empty() else "nothing"])
	await create_timer(1.2).timeout
	if got_count:
		var d: Die = knocked[0]
		var camera: Camera3D = main.get_node("Camera3D")
		var show: Vector3 = (d.global_basis * (d.locked_entry["show_normal"] as Vector3)).normalized()
		var to_camera: Vector3 = (camera.global_position - d.global_position).normalized()
		check(show.dot(to_camera) > 0.95, "the lifted counted die shows its recorded face to the player")
		var sum: int = 0
		for die: Die in roller.get_active_dice():
			sum += int(die.result_entry()["value"])
		var entry: Dictionary = history.entries[0]
		var any_locked: bool = false
		for hd: Dictionary in entry["dice"]:
			any_locked = any_locked or hd.get("locked", false)
		check(entry["total"] == sum and label.text.ends_with("Total: %d" % sum) and entry["rethrow_mode"] == RethrowMode.COUNT
				and any_locked, "result bar, lifted dice and history agree (total %d), and history marks locked dice" % sum)

	# Clear the table in the app: dice slide into the drawer during the re-throw, then everything lifts together.
	var risk: Dictionary = store.sets[1]
	main.call("_on_set_chosen", risk["id"])
	main.set("_pick_mode", false)
	await frames(5)
	var lifted_mid_roll: Array[bool] = [false]
	var in_drawer: Array[bool] = [false]
	var watched: Array[Die] = []
	roller.dice_cleared.connect(func(dice: Array[Die]) -> void:
		if not watched.is_empty():
			return
		var d: Die = dice[0]
		watched.append(d)
		await create_timer(roller.drawer_slide_time + 0.1).timeout
		var p: Vector3 = roller.to_local(d.global_position)
		if roller.is_rolling() and p.z > roller.drawer_z.x and p.z < roller.drawer_z.y and p.y < 1.0:
			in_drawer[0] = true)
	for attempt: int in 4:
		roller.debug_force = "stack"
		main.call("_start_roll")
		await roller.roll_finished
		await create_timer(1.0).timeout
		if in_drawer[0]:
			var camera: Camera3D = main.get_node("Camera3D")
			var p: Vector2 = camera.unproject_position(watched[0].global_position)
			lifted_mid_roll[0] = p.y < (main.get("_roll_button") as Button).get_global_rect().position.y \
					and watched[0].global_position.y > 2.0
			break
	roller.debug_force = ""
	check(in_drawer[0], "Clear the table: settled dice slide into the drawer while the re-throw happens")
	check(lifted_mid_roll[0], "and lift to the result row with the others when the roll ends")
	await _manual_checks(main)


## Re-roll by hand: the bank comes back to the player's hand; Back and the menu
## can't abandon it; throwing it finishes the roll.
func _manual_checks(main: Node) -> void:
	var roller: DiceRoller = main.get_node("DiceRoller")
	var sheet: SettingsSheet = main.get_node("UI/Root/SettingsSheet")
	var settings: AppSettings = main.get("_settings")
	var hand: DiceHand = main.get_node("DiceHand")
	var label: Label = main.get("_result_label")
	var store: DiceSetStore = main.get("_store")
	main.call("_on_set_chosen", store.sets[0]["id"])
	sheet.changed.emit("manual_rethrow", true)
	var saved: AppSettings = AppSettings.new(settings.path)
	saved.load_settings()
	check(saved.manual_rethrow and roller.manual_rethrow, "Re-roll by hand can be switched on, and is saved")
	var ready: Array[int] = []
	roller.bank_ready.connect(func(dice: Array[Die]) -> void: ready.append(dice.size()))
	for attempt: int in 4:
		roller.debug_force = "stack"
		main.call("_start_roll")
		var steps: int = 0
		while ready.is_empty() and roller.is_rolling() and steps < 2400:
			await process_frame
			steps += 1
		if not ready.is_empty():
			break
		await create_timer(0.5).timeout
	roller.debug_force = ""
	await frames(3)
	var held: Array = hand.get("_dice")
	check(not ready.is_empty() and roller.is_waiting_for_throw() and main.get("_state") == 2 and held.size() == ready[0]
			and label.text.begins_with("Re-roll "), "the banked dice come back to the hand and wait: \"%s\"" % label.text)
	press_back(main)
	main.call("_show_menu")
	await frames(3)
	check(roller.is_waiting_for_throw() and not (main.get_node("UI/Root/StartMenu") as Control).visible
			and (main.get("_sets_button") as Button).disabled, "Back, the menu and the sets button can't abandon a roll waiting on a hand re-roll")
	var done: Array[bool] = [false]
	roller.roll_finished.connect(func(_r: Array[Dictionary]) -> void: done[0] = true, CONNECT_ONE_SHOT)
	main.call("_on_roll_button_pressed")  # Throw
	var steps: int = 0
	while not done[0] and steps < 3000:
		if roller.is_waiting_for_throw():
			main.call("_on_roll_button_pressed")  # it landed badly again: throw again
		await process_frame
		steps += 1
	check(done[0], "throwing them finishes the roll")
	sheet.changed.emit("manual_rethrow", false)


func _collect_texts(node: Node, out: Array[String]) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for child: Node in node.get_children():
		_collect_texts(child, out)
