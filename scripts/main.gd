extends Node3D
## Main screen. Opens on the start menu with the table loaded behind it.
## Roll arms, then a shake (or Throw) throws; "pick dice" sets show Pick up first to choose dice.
## Once settled, the result is logged to history, the dice are lifted to show it, and rolling disarms.
##
## Desktop (debug build): hold S to fake a shake, Space presses Roll / Throw, Escape is Android Back.
##
## Self-test user args: --autoroll=N rolls N times then quits; --set=K picks the K-th set
## (either skips the menu). --sets-file / --history-file / --settings-file keep tests off real data.

## IDLE: waiting for Roll / Pick up. PICKING: choosing dice to throw.
## ARMED: listening for a shake. ROLLING: dice moving.
enum State { IDLE, PICKING, ARMED, ROLLING }

const ARMED_HINT: String = "Shake to roll\nor tap Throw"
const ARMED_HINT_TAP: String = "Shake or swipe to rattle,\nflick or tap to throw"
## A press that moves further than this (pixels) or lasts longer than
## TAP_MAX_TIME is a drag or hold, not a tap on the table.
const TAP_SLOP: float = 24.0
const TAP_MAX_TIME: float = 0.4
## Back events closer together than this (ms) count as one press.
const BACK_REPEAT_MS: int = 300
## An upward flick at least this long (pixels) and this quick (seconds) throws
## held dice; its speed (pixels/s, between the two values) sets the throw power.
const SWIPE_MIN_DISTANCE: float = 90.0
const SWIPE_MAX_TIME: float = 0.6
const SWIPE_SPEED_RANGE: Vector2 = Vector2(400.0, 2500.0)
## A flick at the end of a longer drag (e.g. after rattling) is judged on the
## last FLICK_WINDOW seconds of movement, which must go at least FLICK_MIN_DISTANCE up.
const FLICK_WINDOW: float = 0.15
const FLICK_MIN_DISTANCE: float = 60.0
## Sideways finger speed (pixels/s) that rattles held dice gently, and hardest.
const RATTLE_SPEED_RANGE: Vector2 = Vector2(250.0, 2200.0)
## Engine time scale while rolling with Fast roll on.
const FAST_ROLL_SPEED: float = 1.75
const PICK_HINT: String = "Tap the dice to throw\nHold a die to lock it"

@onready var _roller: DiceRoller = $DiceRoller
@onready var _presenter: ResultPresenter = $ResultPresenter
@onready var _shake: ShakeDetector = $ShakeDetector
@onready var _hand: DiceHand = $DiceHand
@onready var _picker: DicePicker = $DicePicker
@onready var _sounds: DiceSounds = $DiceSounds
@onready var _haptics: DiceHaptics = $DiceHaptics
@onready var _camera: Camera3D = $Camera3D
@onready var _result_label: Label = $UI/Root/ResultLabel
@onready var _sets_button: Button = $UI/Root/BottomBar/SetsButton
@onready var _roll_button: Button = $UI/Root/BottomBar/RollButton
@onready var _history_button: Button = $UI/Root/BottomBar/HistoryButton
@onready var _history_sheet: HistorySheet = $UI/Root/HistorySheet
@onready var _drawer: SetDrawer = $UI/Root/SetDrawer
@onready var _editor: SetEditor = $UI/Root/SetEditor
@onready var _menu: StartMenu = $UI/Root/StartMenu
@onready var _menu_button: MenuIconButton = $UI/Root/MenuButton
@onready var _settings_sheet: SettingsSheet = $UI/Root/SettingsSheet
@onready var _tutorial: TutorialOverlay = $UI/Root/TutorialOverlay

var _store: DiceSetStore = DiceSetStore.new()
var _history: RollHistory = RollHistory.new()
var _settings: AppSettings = AppSettings.new()
## The dice on the table: a saved set, or a one-off quick roll.
var _current_set: Dictionary = {}
## Id of the saved set on the table ("" for a quick roll or nothing).
var _current_set_id: String = ""
## A silent, unlogged practice throw behind the start menu so the first real roll doesn't stutter.
var _warming: bool = false
## The current set asks the player to pick dice before each throw.
var _pick_mode: bool = false
## Locked (always-picked) entries per set, session only: set id -> {entry: true}.
var _locks: Dictionary = {}
var _state: State = State.IDLE
var _autoroll_remaining: int = 0
var _press_pos: Vector2 = Vector2.ZERO
var _last_back_ms: int = -1000
var _press_ms: int = -1
## Recent finger positions during a press: [msec, Vector2], for judging flicks.
var _drag_samples: Array = []
## 0–1: how hard the held dice are being rattled by swiping (fades when you stop).
var _drag_rattle: float = 0.0


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
	# No cancel handler: closing the editor reveals the drawer or menu underneath.
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
	_menu.settings_pressed.connect(func() -> void: _settings_sheet.open(_settings))
	_settings_sheet.changed.connect(_on_setting_changed)
	_settings_sheet.replay_tips_pressed.connect(func() -> void:
		_settings.tutorial_done = false
		_settings.save()
		_update_tutorial())
	_roller.die_impact.connect(func(kind: String, speed: float) -> void:
		if not _warming:
			_haptics.play_impact(kind, speed))
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
	_haptics.enabled = _settings.haptics
	_apply_menu_button()
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


func _process(delta: float) -> void:
	_drag_rattle = maxf(0.0, _drag_rattle - delta * 2.0)
	_hand.shake_level = maxf(_shake.level, _drag_rattle)


func _unhandled_input(event: InputEvent) -> void:
	if _menu.visible:
		if event.is_action_pressed("ui_cancel"):
			_go_back()
		return
	if _state == State.PICKING and _picker.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if _settings.tap_to_roll:
		if event is InputEventMouseMotion and _press_ms >= 0:
			_on_drag(event as InputEventMouseMotion)
			return
		var gesture: Dictionary = _table_gesture(event)
		if gesture.get("kind") == "tap":
			get_viewport().set_input_as_handled()
			if (_state == State.IDLE or _state == State.ARMED) and not _roll_button.disabled:
				_on_roll_button_pressed()
			return
		if gesture.get("kind") == "swipe":
			get_viewport().set_input_as_handled()
			if _state == State.ARMED:
				_start_roll(gesture["power"])
			return
	if event.is_action_pressed("ui_cancel"):
		_go_back()
	elif event.is_action_pressed("ui_accept") and not _roll_button.disabled \
			and not _drawer.is_open() and not _editor.is_open() and not _history_sheet.is_open() \
			and not _settings_sheet.is_open():
		_on_roll_button_pressed()


## On the release of a press on the table: { "kind": "tap" }, an upward flick
## { "kind": "swipe", "power": 0–1 }, or {} for anything else. Presses on buttons
## and sheets never get here (the UI takes them). Touch arrives as emulated mouse.
func _table_gesture(event: InputEvent) -> Dictionary:
	if not event is InputEventMouseButton or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return {}
	var mb: InputEventMouseButton = event
	var now: int = Time.get_ticks_msec()
	if mb.pressed:
		_press_pos = mb.position
		_press_ms = now
		_drag_samples = [[now, mb.position]]
		return {}
	if _press_ms < 0:
		return {}
	var seconds: float = (now - _press_ms) / 1000.0
	var moved: Vector2 = mb.position - _press_pos
	_press_ms = -1
	if moved.length() <= TAP_SLOP:
		return { "kind": "tap" } if seconds <= TAP_MAX_TIME else {}
	# A quick swipe up from the press...
	var upward: bool = -moved.y >= SWIPE_MIN_DISTANCE and -moved.y > absf(moved.x) * 1.2
	if upward and seconds <= SWIPE_MAX_TIME:
		return { "kind": "swipe", "power": _flick_power(moved.length() / maxf(seconds, 0.016)) }
	# ...or a flick up at the end of a longer drag, such as after rattling.
	var start: Array = _drag_samples[0]
	for sample: Array in _drag_samples:
		if now - (sample[0] as int) <= int(FLICK_WINDOW * 1000.0):
			break
		start = sample
	var recent: Vector2 = mb.position - (start[1] as Vector2)
	var recent_seconds: float = maxf((now - (start[0] as int)) / 1000.0, 0.016)
	if -recent.y >= FLICK_MIN_DISTANCE and -recent.y > absf(recent.x) * 1.2 and recent_seconds <= FLICK_WINDOW * 2.0:
		return { "kind": "swipe", "power": _flick_power(recent.length() / recent_seconds) }
	return {}


## Finger moving while pressed: kept for flick detection, and swiping side to
## side over held dice rattles them like a shake.
func _on_drag(mm: InputEventMouseMotion) -> void:
	var now: int = Time.get_ticks_msec()
	_drag_samples.append([now, mm.position])
	while _drag_samples.size() > 2 and now - (_drag_samples[1][0] as int) > int(FLICK_WINDOW * 2000.0):
		_drag_samples.pop_front()
	if _state == State.ARMED:
		var sideways: float = absf(mm.velocity.x)
		if sideways > absf(mm.velocity.y) and sideways >= RATTLE_SPEED_RANGE.x:
			_drag_rattle = maxf(_drag_rattle, clampf(inverse_lerp(RATTLE_SPEED_RANGE.x, RATTLE_SPEED_RANGE.y, sideways), 0.15, 1.0))
			_result_label.text = "Rattling…"


func _flick_power(speed: float) -> float:
	return clampf(inverse_lerp(SWIPE_SPEED_RANGE.x, SWIPE_SPEED_RANGE.y, speed), 0.0, 1.0)


func _notification(what: int) -> void:
	# Android's Back button / gesture.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


## Closes whatever is on top, else cancels picking / arming, else opens the menu;
## from the menu it quits.
## Back on the menu quits.
func _go_back() -> void:
	# On Android one Back press arrives twice (go-back notification and ui_cancel);
	# act once, or it would step back twice and quit from the menu.
	var now: int = Time.get_ticks_msec()
	if now - _last_back_ms < BACK_REPEAT_MS:
		return
	_last_back_ms = now
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


# Start menu

func _show_menu() -> void:
	if _state == State.ARMED or _state == State.PICKING:
		_disarm()
	_menu.set_continue_name(_current_set.get("name", ""))
	_menu.visible = true
	_update_tutorial()


func _show_table() -> void:
	if _warming:
		_put_on_table(_current_set, _current_set_id)  # stop the practice throw
	_menu.visible = false
	_update_tutorial()


func _warm_up() -> void:
	if _roller.get_dice().is_empty():
		return
	_warming = true
	_sounds.enabled = false
	_roller.roll()


func _end_warm_up() -> void:
	_warming = false
	_sounds.enabled = _settings.sound
	_haptics.enabled = _settings.haptics


# Dice sets, settings and history

func _open_drawer() -> void:
	if _state == State.ARMED or _state == State.PICKING:
		_disarm()
	_drawer.open(_store.sets, _current_set_id)


func _on_setting_changed(key: String, on: bool) -> void:
	match key:
		"sound":
			_set_sound(on)
		"haptics":
			_settings.haptics = on
			_haptics.enabled = on
			_settings.save()
		"tap_to_roll":
			_settings.tap_to_roll = on
			_update_tutorial()
			_settings.save()
			_put_on_table(_current_set, _current_set_id)  # refresh the hint text
		"fast_roll":
			_settings.fast_roll = on
			_settings.save()
		"menu_button":
			_settings.menu_button = on
			_settings.save()
			_apply_menu_button()


## Shows or hides the table's menu button; the result bar uses the space when hidden.
func _apply_menu_button() -> void:
	_menu_button.visible = _settings.menu_button
	_result_label.offset_left = 108.0 if _settings.menu_button else 24.0


func _set_sound(on: bool) -> void:
	_settings.sound = on
	_settings.save()
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
		var action: String = "pick up" if _pick_mode else "roll"
		_result_label.text = "%s\n%s" % [DiceSetStore.summary(set_data),
				("Tap to %s" % action) if _settings.tap_to_roll else ("Press %s" % action.capitalize())]


## Stop picking / listening for a shake and put the dice back on the table.
func _disarm() -> void:
	_put_on_table(_current_set, _current_set_id)


# Rolling

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
	print("Rolled %s: %s" % [set_name, RollHistory.format_dice(results, false)])
	_history.add(RollHistory.make_entry(_current_set_id, set_name, results))
	# Disarm until Roll is pressed again.
	_set_state(State.IDLE)
	_result_label.text = RollHistory.format_dice(results, true)
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


## Lifts the dice below the result bar, one frame late so the bar has resized to the new text.
func _present_results() -> void:
	await get_tree().process_frame
	if _state != State.IDLE or _roller.is_rolling():
		return  # a new roll started in the meantime
	_presenter.present(_roller.get_active_dice(), _camera,
			_result_label.get_global_rect().end.y, _roll_button.get_global_rect().position.y)


## First-run tips: how to pick up the dice, then how to throw them. Done (and
## saved) once the player throws for the first time; never during self-tests.
func _update_tutorial() -> void:
	if _settings.tutorial_done or _menu.visible or _autoroll_remaining > 0:
		_tutorial.hide_tip()
		return
	var tap: bool = _settings.tap_to_roll
	match _state:
		State.IDLE:
			if _roller.get_dice().is_empty():
				_tutorial.hide_tip()
			elif _pick_mode:
				_tutorial.show_tip("Tap the table to choose\nwhich dice to throw" if tap else "Press Pick up to choose\nwhich dice to throw", "tap" if tap else "")
			else:
				_tutorial.show_tip("Tap the table to\npick up the dice" if tap else "Press Roll to\npick up the dice", "tap" if tap else "")
		State.ARMED:
			_tutorial.show_tip("Shake the phone, or swipe\nside to side to rattle.\nFlick up to throw." if tap else "Shake the phone,\nor press Throw", "flick" if tap else "")
		State.PICKING:
			_tutorial.hide_tip()  # the picking hint explains it
		State.ROLLING:
			_tutorial.hide_tip()
			_settings.tutorial_done = true
			_settings.save()


func _set_state(new_state: State) -> void:
	_state = new_state
	# Fast roll keeps the same physics steps, just more per frame, so results are unaffected.
	Engine.time_scale = FAST_ROLL_SPEED if new_state == State.ROLLING and _settings.fast_roll else 1.0
	_presenter.duration = 0.3 if _settings.fast_roll else 0.6
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
			_result_label.text = ARMED_HINT_TAP if _settings.tap_to_roll else ARMED_HINT
		State.ROLLING:
			_roll_button.text = "Rolling…"
			_roll_button.disabled = true
			_sets_button.disabled = true
			_history_button.disabled = true
			_result_label.text = "Rolling…"
	_update_tutorial()
