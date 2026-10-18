extends "res://tests/app_test.gd"
## Re-throw modes, step 3: storage and resolution. Global default and damaged
## values, per-set override and Table default, quick rolls using the global
## setting, Duplicate copying the choice, locks surviving a mode-only edit, and
## the effective mode recorded in history (old entries still load).

func _init() -> void:
	test_name = "RE-THROW MODES"


func run() -> void:
	_storage_checks()
	await _app_checks()


func _storage_checks() -> void:
	# Settings: default, unknown, valid.
	var path: String = "user://test_rethrow_settings.json"
	var s: AppSettings = AppSettings.new(path)
	check(s.rethrow_mode == RethrowMode.CLEAR, "a fresh install defaults to Clear the table")
	JsonFile.write(path, { "version": 1, "sound": true })
	s.load_settings()
	check(s.rethrow_mode == RethrowMode.CLEAR, "settings without a mode load as Clear the table")
	JsonFile.write(path, { "version": 1, "rethrow_mode": "sideways" })
	s.load_settings()
	var unknown_ok: bool = s.rethrow_mode == RethrowMode.CLEAR
	JsonFile.write(path, { "version": 1, "rethrow_mode": 7 })
	s.load_settings()
	check(unknown_ok and s.rethrow_mode == RethrowMode.CLEAR, "an unknown or non-text mode becomes Clear the table")
	s.rethrow_mode = RethrowMode.COUNT
	s.save()
	var again: AppSettings = AppSettings.new(path)
	again.load_settings()
	check(again.rethrow_mode == RethrowMode.COUNT, "a chosen mode is saved and loaded")
	DirAccess.remove_absolute(path)

	# Sets: missing, unknown, valid; never rejected because of the field.
	var dice: Array = [{ "type": "d6" }]
	var missing: Dictionary = DiceSetStore.sanitize_set({ "name": "A", "dice": dice })
	var junk: Dictionary = DiceSetStore.sanitize_set({ "name": "B", "dice": dice, "rethrow_mode": "zzz" })
	var wrong_type: Dictionary = DiceSetStore.sanitize_set({ "name": "C", "dice": dice, "rethrow_mode": ["live"] })
	var live: Dictionary = DiceSetStore.sanitize_set({ "name": "D", "dice": dice, "rethrow_mode": "live" })
	check(missing["rethrow_mode"] == RethrowMode.TABLE_DEFAULT, "a set without the field loads as Table default")
	check(not junk.is_empty() and junk["rethrow_mode"] == RethrowMode.TABLE_DEFAULT
			and not wrong_type.is_empty() and wrong_type["rethrow_mode"] == RethrowMode.TABLE_DEFAULT,
			"unknown values become Table default, and the set is kept")
	check(live["rethrow_mode"] == RethrowMode.LIVE, "a set's own mode is kept")
	var examples_ok: bool = true
	for e: Dictionary in DiceSetStore.example_sets():
		examples_ok = examples_ok and e["rethrow_mode"] == RethrowMode.TABLE_DEFAULT
	check(examples_ok, "the example sets use Table default")

	# Resolution.
	check(RethrowMode.resolve("default", "count") == "count" and RethrowMode.resolve("live", "count") == "live"
			and RethrowMode.resolve(null, "live") == "live" and RethrowMode.resolve("default", "junk") == "clear",
			"Table default follows the global mode; a set's own mode wins")

	# History: effective mode stored, old entries fine, "default" never stored.
	var result: Array[Dictionary] = [{ "type": "d6", "value": 4, "color": "#f2edd9" }]
	var entry: Dictionary = RollHistory.make_entry("x", "X", result, 100, "count")
	var defaulted: Dictionary = RollHistory.make_entry("x", "X", result, 100, "default")
	var old: Dictionary = RollHistory.sanitize_entry({ "time": 5, "set_name": "Old", "dice": result })
	var bad: Dictionary = RollHistory.sanitize_entry({ "time": 5, "dice": result, "rethrow_mode": "nope" })
	check(RollHistory.sanitize_entry(entry)["rethrow_mode"] == "count" and not defaulted.has("rethrow_mode"),
			"history keeps the effective mode, never 'Table default'")
	check(not old.is_empty() and not old.has("rethrow_mode") and not bad.has("rethrow_mode"),
			"old entries without a mode still load; an unknown mode is dropped")


func _app_checks() -> void:
	var main: Node = launch_main()
	await frames(2)
	var store: DiceSetStore = main.get("_store")
	var settings: AppSettings = main.get("_settings")
	var roller: DiceRoller = main.get_node("DiceRoller")
	var history: RollHistory = main.get("_history")
	var editor: SetEditor = main.get_node("UI/Root/SetEditor")
	var menu: StartMenu = main.get_node("UI/Root/StartMenu")
	menu.continue_pressed.emit()
	await frames(5)
	var fireball: Dictionary = store.sets[0]
	main.call("_on_set_chosen", fireball["id"])
	check(main.call("effective_rethrow_mode") == RethrowMode.CLEAR, "a Table default set uses the global mode (Clear the table)")

	main.call("set_global_rethrow_mode", RethrowMode.LIVE)
	var saved: AppSettings = AppSettings.new(settings.path)
	saved.load_settings()
	check(main.call("effective_rethrow_mode") == RethrowMode.LIVE and saved.rethrow_mode == RethrowMode.LIVE,
			"changing the global mode moves Table default sets with it, and is saved")

	# A set with its own mode ignores the global one.
	editor.open(fireball)
	editor.set_rethrow_mode(RethrowMode.COUNT)
	editor.call("_save")
	await frames(3)
	var stored: Dictionary = store.get_set(fireball["id"])
	var reloaded: DiceSetStore = DiceSetStore.new(store.path)
	reloaded.load_sets()
	check(stored["rethrow_mode"] == RethrowMode.COUNT and reloaded.get_set(fireball["id"])["rethrow_mode"] == RethrowMode.COUNT,
			"a set's own mode is saved")
	main.call("set_global_rethrow_mode", RethrowMode.CLEAR)
	check(main.call("effective_rethrow_mode") == RethrowMode.COUNT, "changing the global mode leaves a set with its own mode alone")

	# The roll uses and records the effective mode.
	main.call("_start_roll")
	await roller.roll_finished
	await frames(3)
	check(roller.rethrow_mode == RethrowMode.COUNT and history.entries[0].get("rethrow_mode") == RethrowMode.COUNT,
			"the roll uses the set's mode and history records it")

	# Quick rolls always use the global mode.
	menu.quick_roll.emit(["d6", "d6"] as Array[String])
	await frames(5)
	check(main.call("effective_rethrow_mode") == RethrowMode.CLEAR, "a quick roll uses the global mode, not the last set's")

	# Duplicate copies the choice.
	editor.open(store.get_set(fireball["id"]))
	editor.duplicate_set()
	editor.call("_save")
	await frames(3)
	check(store.sets[-1]["name"] == "Fireball (copy)" and store.sets[-1]["rethrow_mode"] == RethrowMode.COUNT,
			"Duplicate copies the set's re-throw choice")
	editor.open({})
	check(editor.get("_rethrow_mode") == RethrowMode.TABLE_DEFAULT, "a new set starts on Table default")
	editor.cancel_editing()

	# Locks: a mode-only edit keeps them; other edits reset them.
	var risk: Dictionary = store.sets[1]
	var locks: Dictionary = main.get("_locks")
	locks[risk["id"]] = { 0: true }
	editor.open(risk)
	editor.set_rethrow_mode(RethrowMode.LIVE)
	editor.call("_save")
	await frames(3)
	check(locks.has(risk["id"]), "changing only the re-throw choice keeps the set's long-press locks")
	editor.open(store.get_set(risk["id"]))
	(editor.get("_name_edit") as LineEdit).text = "Risk 2"
	editor.call("_save")
	await frames(3)
	check(not locks.has(risk["id"]), "other edits still reset the locks")
