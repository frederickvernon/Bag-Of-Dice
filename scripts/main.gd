extends Node3D
## Main screen. Opens on the start menu (continue, quick roll, dice sets,
## history, settings) with the table loaded behind it.
## On the table: open Sets to pull a dice set out of the drawer, press Roll to
## arm, then shake the phone (or press Throw) to throw. Sets with "pick dice"
## on show Pick up first, to choose which of the set's dice to throw. Once everything has
## settled the result is logged to the history, the dice are lifted up to
## show it, and rolling disarms. History shows past rolls.
##
## Desktop testing: in a debug run on a computer, hold S to fake a shake.
## Space presses the Roll / Throw button; Escape acts as Android's Back.
##
## Headless self-test: run with user args --autoroll=N (and optionally
## --set=K to pick the K-th saved set) to throw N times, print the results
## and quit. --autoroll or --set skip the start menu. --sets-file=user://other.json, --history-file=user://… and
## --settings-file=user://… use different files (so tests never touch the
## real ones).

## IDLE: waiting for Roll / Pick up. PICKING: choosing dice to throw.
## ARMED: listening for a shake. ROLLING: dice moving.
enum State { IDLE, PICKING, ARMED, ROLLING }

const ARMED_HINT: String = "Shake to roll\nor tap Throw"
const PICK_HINT: String = "Tap the dice to throw\nHold a die to lock it"

@onready var _roller: DiceRoller = $DiceRoller
@onready var _presenter: ResultPresenter = $ResultPresenter
@onready var _shake: ShakeDetector = $ShakeDetector
@onready var _hand: DiceHand = $DiceHand
@onready var _picker: DicePicker = $DicePicker
@onready var _sounds: DiceSounds = $DiceSounds
@onready var _camera: Camera3D = $Camera3D
@onready var _result_label: Label = $UI/Root/ResultLabel
@onready var _sets_button: Button = $UI/Root/BottomBar/SetsButton
@onready var _roll_button: Button = $UI/Root/BottomBar/RollButton
@onready var _history_button: Button = $UI/Root/BottomBar/HistoryButton
@onready var _history_sheet: HistorySheet = $UI/Root/HistorySheet
@onready var _sound_toggle: SoundToggle = $UI/Root/SoundToggle
@onready var _drawer: SetDrawer = $UI/Root/SetDrawer
@onready var _editor: SetEditor = $UI/Root/SetEditor
@onready var _menu: StartMenu = $UI/Root/StartMenu
@onready var _menu_button: MenuIconButton = $UI/Root/MenuButton
@onready var _settings_sheet: SettingsSheet = $UI/Root/SettingsSheet

var _store: DiceSetStore = DiceSetStore.new()
var _history: RollHistory = RollHistory.new()
var _settings: AppSettings = AppSettings.new()
## The dice on the table: a saved set, or a one-off quick roll.
var _current_set: Dictionary = {}
## Id of the saved set on the table ("" for a quick roll or nothing).
var _current_set_id: String = ""
## A hidden practice throw behind the start menu, to warm up physics and
## rendering so the player's first roll doesn't stutter. Not logged or heard.
var _warming: bool = false
## Whether the current set asks the player to pick dice before each throw.
var _pick_mode: bool = false
## Locked (always-picked) entries per set, for this session: set id -> {entry: true}.
var _locks: Dictionary = {}
var _state: State = State.IDLE
var _autoroll_remaining: int = 0


func _ready() -> void:
	_roll_button.pressed.connect(_on_roll_button_pressed)
	_sets_button.pressed.connect(_open_drawer)
	_history_button.pressed.connect(_open_history)
	_history_sheet.clear_confirmed.connect(func() -> void:
		_history.clear()
		_history_sheet.refresh(_history.entries))
	_roller.roll_finished.connect(_on_roll_finished)
	_shake.shake_started.connect(_on_shake_started)
	_shake.shake_finished.connect(_on_shake_finished)
	_picker.selection_changed.connect(_on_pick_changed)
	_roller.die_impact.connect(_sounds.play_impact)
	_drawer.set_chosen.connect(_on_set_chosen)
	_drawer.edit_requested.connect(func(id: String) -> void: _editor.open(_store.get_set(id)))
	_drawer.new_requested.connect(func() -> void: _editor.open({}))
	_editor.saved.connect(_on_set_saved)
	_editor.deleted.connect(_on_set_deleted)
	_editor.quick_ready.connect(func(dice: Array[Dictionary]) -> void:
		_load_quick(dice)
		_show_table())
	# Cancelling the editor just reveals the drawer (or menu) underneath.
	_menu.continue_pressed.connect(_show_table)
	_menu.quick_roll.connect(func(types: Array[String]) -> void:
		var dice: Array[Dictionary] = []
		for t: String in types:
			dice.append({ "type": t, "style": DiceFactory.default_style(t), "color": DicePalette.DEFAULT_HEX, "label": "" })
		_load_quick(dice)
		_show_table())
	_menu.custom_quick_pressed.connect(func() -> void: _editor.open_quick())
	_menu.sets_pressed.connect(_open_drawer)
	_menu.history_pressed.connect(_open_history)
	_menu.settings_pressed.connect(func() -> void: _settings_sheet.open(_settings.sound))
	_settings_sheet.sound_changed.connect(_set_sound)
	_menu_button.pressed.connect(_show_menu)

	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--sets-file="):
			_store = DiceSetStore.new(arg.get_slice("=", 1))
		elif arg.begins_with("--history-file="):
			_history = RollHistory.new(arg.get_slice("=", 1))
		elif arg.begins_with("--settings-file="):
			_settings = AppSettings.new(arg.get_slice("=", 1))
	_store.load_sets()
	_history.load_entries()
	_settings.load_settings()
	_sounds.enabled = _settings.sound
	_sound_toggle.set_pressed_no_signal(_settings.sound)
	_sound_toggle.toggled.connect(_set_sound)
	var start_id: String = _store.last_set_id
	var skip_menu: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--autoroll="):
			_autoroll_remaining = arg.get_slice("=", 1).to_int()
			skip_menu = true
		elif arg.begins_with("--set="):
			skip_menu = true
			var k: int = arg.get_slice("=", 1).to_int()
			if k >= 0 and k < _store.sets.size():
				start_id = _store.sets[k]["id"]
	if _store.get_set(start_id).is_empty() and not _store.sets.is_empty():
		start_id = _store.sets[0]["id"]
	_load_set(start_id)
	if skip_menu:
		_show_table()
	else:
		_show_menu()
		_warm_up()

	if _autoroll_remaining > 0 and not _current_set_id.is_empty():
		print("Autoroll: %d throws of %s" % [_autoroll_remaining, _store.get_set(_current_set_id)["name"]])
		_start_roll()


func _process(_delta: float) -> void:
	_hand.shake_level = _shake.level


func _unhandled_input(event: InputEvent) -> void:
	if _menu.visible:
		if event.is_action_pressed("ui_cancel"):
			_go_back()
		return
	if _state == State.PICKING and _picker.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_go_back()
	elif event.is_action_pressed("ui_accept") and not _roll_button.disabled \
			and not _drawer.is_open() and not _editor.is_open() and not _history_sheet.is_open() \
			and not _settings_sheet.is_open():
		_on_roll_button_pressed()


func _notification(what: int) -> void:
	# Android's Back button / gesture.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


## Back closes whatever is on top (confirmation, editor, sheet), then on the
## table cancels picking / arming, then goes to the start menu; Back on the
## menu leaves the app.
func _go_back() -> void:
	if _settings_sheet.is_open():
		_settings_sheet.close()
	elif _history_sheet.is_open():
		if _history_sheet.is_confirming():
			_history_sheet.cancel_confirm()
		else:
			_history_sheet.close()
	elif _editor.is_open():
		_editor.cancel_editing()
	elif _drawer.is_open():
		_drawer.close()
	elif _menu.visible:
		get_tree().quit()
	elif _state == State.PICKING or _state == State.ARMED:
		_disarm()
	else:
		_show_menu()


# --- Start menu ------------------------------------------------------------

func _show_menu() -> void:
	if _state == State.ARMED or _state == State.PICKING:
		_disarm()
	_menu.set_continue_name(_current_set.get("name", ""))
	_menu.visible = true


func _show_table() -> void:
	if _warming:
		_put_on_table(_current_set, _current_set_id)  # stop the practice throw
	_menu.visible = false


func _warm_up() -> void:
	if _roller.get_dice().is_empty():
		return
	_warming = true
	_sounds.enabled = false
	_roller.roll()


func _end_warm_up() -> void:
	_warming = false
	_sounds.enabled = _settings.sound


# --- Dice sets -------------------------------------------------------------

func _open_drawer() -> void:
	if _state == State.ARMED or _state == State.PICKING:
		_disarm()
	_drawer.open(_store.sets, _current_set_id)


## Sound on/off, from the table's speaker button or the settings sheet.
func _set_sound(on: bool) -> void:
	_settings.sound = on
	_settings.save()
	_sound_toggle.set_pressed_no_signal(on)
	_sound_toggle.queue_redraw()
	if not _warming:
		_sounds.enabled = on
	if not on:
		_sounds.stop_all()


func _open_history() -> void:
	if _state == State.ARMED or _state == State.PICKING:
		_disarm()
	_history_sheet.open(_history.entries)


func _on_set_chosen(id: String) -> void:
	_load_set(id)
	_drawer.close()
	_show_table()


func _on_set_saved(set_data: Dictionary) -> void:
	var stored: Dictionary = _store.upsert(set_data)
	if stored.is_empty():
		return
	_locks.erase(stored["id"])  # its dice may have changed
	# Pull the saved set straight out onto the table.
	_load_set(stored["id"])
	_drawer.close()
	_show_table()


func _on_set_deleted(id: String) -> void:
	_store.delete(id)
	_locks.erase(id)
	if id == _current_set_id:
		_load_set("" if _store.sets.is_empty() else _store.sets[0]["id"])
	_menu.set_continue_name(_current_set.get("name", ""))
	_drawer.open(_store.sets, _current_set_id)


## Puts a saved set's dice on the table (or clears the table if `id` is "").
func _load_set(id: String) -> void:
	var set_data: Dictionary = _store.get_set(id)
	if not set_data.is_empty():
		_store.set_last_used(id)
	_put_on_table(set_data, id)


## Puts a one-off quick roll on the table (never saved as a set).
func _load_quick(dice: Array[Dictionary]) -> void:
	_put_on_table({ "name": "Quick roll", "pick_dice": false, "dice": dice }, "")


func _put_on_table(set_data: Dictionary, id: String) -> void:
	if _warming:
		_end_warm_up()
	_presenter.cancel()
	_hand.release()
	_picker.end()
	_current_set = set_data
	_current_set_id = id if not set_data.is_empty() else ""
	_pick_mode = set_data.get("pick_dice", false)
	_roller.set_dice(DiceSetStore.to_roller_specs(set_data))
	_set_state(State.IDLE)
	if set_data.is_empty():
		_sets_button.text = "Sets"
		_result_label.text = "Open Sets to make a dice set"
	else:
		_sets_button.text = set_data["name"]
		_result_label.text = "%s\nPress %s" % [DiceSetStore.summary(set_data), "Pick up" if _pick_mode else "Roll"]


## Stop picking / listening for a shake and put the dice back on the table.
func _disarm() -> void:
	_put_on_table(_current_set, _current_set_id)


# --- Rolling -----------------------------------------------------------------

func _on_roll_button_pressed() -> void:
	match _state:
		State.IDLE:
			_set_state(State.PICKING if _pick_mode else State.ARMED)
		State.PICKING:
			var picked: Array[int] = _picker.picked_groups()
			if picked.is_empty():
				return
			_locks[_current_set_id] = _picker.locked_groups()
			_picker.end()
			_roller.set_active_groups(picked)
			_set_state(State.ARMED)
		State.ARMED:
			_start_roll()  # throw without shaking


func _on_pick_changed(count: int) -> void:
	if _state != State.PICKING:
		return
	_roll_button.disabled = count == 0
	_result_label.text = PICK_HINT if count == 0 else "%d picked — tap Roll\nHold a die to lock it" % count


func _on_shake_started() -> void:
	if _state == State.ARMED:
		_result_label.text = "Shaking…"


func _on_shake_finished(strength: float) -> void:
	if _state == State.ARMED:
		print("Shake detected, strength %.2f" % strength)
		_start_roll(strength)


## `power` 0–1 scales how hard the dice are thrown (0.5 = normal).
func _start_roll(power: float = 0.5) -> void:
	# If the dice are being held (armed), throw them from the hand.
	var from_hand: bool = _state == State.ARMED
	_presenter.cancel()
	_hand.release()
	_roller.roll(power, from_hand)
	_set_state(State.ROLLING)


func _on_roll_finished(results: Array[Dictionary]) -> void:
	if _warming:
		_put_on_table(_current_set, _current_set_id)  # tidy up after the practice throw
		return
	var set_name: String = _current_set.get("name", "")
	print("Rolled %s: %s" % [set_name, _format_results(results, false)])
	_history.add(RollHistory.make_entry(_current_set_id, set_name, results))
	# Result logged — disarm until Roll is pressed again.
	_set_state(State.IDLE)
	_result_label.text = _format_results(results, true)
	_present_results()

	if _autoroll_remaining > 0:
		_autoroll_remaining -= 1
		if _autoroll_remaining > 0:
			_start_roll()
		else:
			print("Autoroll done")
			# Let the last impact sounds finish before quitting.
			await get_tree().create_timer(0.3).timeout
			get_tree().quit()


## Results as text. Consecutive dice of the same type and label are grouped
## ("d6: 4  2  5"), and a total is added when there's more than one die.
## For the screen, non-breaking spaces keep "d6:" with its first value when
## the line wraps.
static func _format_results(results: Array[Dictionary], for_screen: bool) -> String:
	var groups: Array[Dictionary] = []
	var total: int = 0
	for r: Dictionary in results:
		var label: String = r["label"]
		var die_name: String = r["type"] if label.is_empty() else "%s (%s)" % [label, r["type"]]
		var value: String = str(r["value"])
		if r["type"] == "d100":
			value += " (%02d + %d)" % [r["parts"][0], r["parts"][1]]
		total += r["value"]
		if not groups.is_empty() and groups[-1]["name"] == die_name:
			groups[-1]["values"].append(value)
		else:
			# A plain Array: a PackedStringArray read out of a Dictionary is a
			# copy, so appending to it later would be lost.
			groups.append({ "name": die_name, "values": [value] })

	var nbsp: String = "\u00a0" if for_screen else " "
	var parts: PackedStringArray = PackedStringArray()
	for g: Dictionary in groups:
		var values: PackedStringArray = PackedStringArray()
		for v: String in g["values"] as Array:
			values.append(v.replace(" ", nbsp))
		parts.append(("%s:" % g["name"]).replace(" ", nbsp) + nbsp + "  ".join(values))
	var text: String = ("   " if for_screen else ", ").join(parts)
	if results.size() > 1:
		text += ("\nTotal: %d" if for_screen else "  (total %d)") % total
	return text


## Lift the dice up below the result bar. Waits one frame so the bar has
## resized to fit the new text first.
func _present_results() -> void:
	await get_tree().process_frame
	if _state != State.IDLE or _roller.is_rolling():
		return  # a new roll started in the meantime
	_presenter.present(_roller.get_active_dice(), _camera,
			_result_label.get_global_rect().end.y, _roll_button.get_global_rect().position.y)


func _set_state(new_state: State) -> void:
	_state = new_state
	# The accelerometer is ignored unless armed.
	_shake.armed = new_state == State.ARMED
	var has_dice: bool = not _roller.get_dice().is_empty()
	match new_state:
		State.IDLE:
			_roll_button.text = "Pick up" if _pick_mode else "Roll"
			_roll_button.disabled = not has_dice
			_sets_button.disabled = false
			_history_button.disabled = false
		State.PICKING:
			_presenter.cancel()
			_hand.release()
			_roll_button.text = "Roll"
			_sets_button.disabled = false
			_history_button.disabled = false
			_picker.begin(_roller, _camera, _locks.get(_current_set_id, {}))
		State.ARMED:
			_presenter.cancel()
			_hand.gather(_roller.get_active_dice(), _roller.hand_positions())
			_roll_button.text = "Throw"
			_roll_button.disabled = false
			_sets_button.disabled = false
			_history_button.disabled = false
			_result_label.text = ARMED_HINT
		State.ROLLING:
			_roll_button.text = "Rolling…"
			_roll_button.disabled = true
			_sets_button.disabled = true
			_history_button.disabled = true
			_result_label.text = "Rolling…"
