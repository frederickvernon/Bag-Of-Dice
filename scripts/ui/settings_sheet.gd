class_name SettingsSheet
extends BottomSheet
## Settings switches. The main screen saves and applies each `changed` value.

## `key` is the AppSettings field ("sound", "haptics", "fast_roll", "tap_to_roll", "menu_button" or "manual_rethrow").
signal changed(key: String, on: bool)
signal replay_tips_pressed
## The global re-throw mode was chosen (a RethrowMode id).
signal rethrow_mode_changed(mode: String)
## Debug builds only: "" (off), "lean" or "stack"; see DiceRoller.debug_force.
signal debug_force_changed(kind: String)

const DEBUG_FORCES: Array[String] = ["", "lean", "stack"]
const DEBUG_FORCE_NAMES: Dictionary = { "": "off", "lean": "lean on rim", "stack": "stack" }

var _switches: Dictionary = {}  # key -> CheckButton
var _mode_buttons: Dictionary = {}  # RethrowMode id -> Button
var _debug_force: String = ""


func _build_content(column: VBoxContainer) -> void:
	set_title("Settings")
	# Scrolls once the options outgrow the sheet on shorter phones.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	scroll.add_child(DragScroll.new())
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 18)
	scroll.add_child(list)
	_add_switch(list, "sound", "Sound effects", "")
	_add_switch(list, "haptics", "Vibration", "A short buzz when dice hit something")
	_add_switch(list, "fast_roll", "Fast roll", "Dice roll and show their result faster")
	_add_switch(list, "tap_to_roll", "Tap or swipe to roll", "Tap the table to roll or throw; swipe side to side to rattle held dice, flick up to throw")
	_add_switch(list, "menu_button", "Menu button on table", "Back also returns to the menu")
	_add_rethrow_choice(list)
	_add_switch(list, "manual_rethrow", "Re-roll by hand", "Dice that need re-throwing come back to your hand to throw yourself")
	var replay: Button = Button.new()
	replay.text = "Show tips again"
	replay.custom_minimum_size.y = 76
	replay.pressed.connect(func() -> void:
		replay_tips_pressed.emit()
		close())
	list.add_child(replay)
	if OS.is_debug_build():
		_add_debug_force(list)


## Debug builds: cycles the problem landing forced on every throw, to try out hops and re-throws.
func _add_debug_force(list: VBoxContainer) -> void:
	var button: Button = Button.new()
	button.custom_minimum_size.y = 76
	# Never let the label widen the sheet.
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.text = "Debug landing: %s" % DEBUG_FORCE_NAMES[_debug_force]
	button.pressed.connect(func() -> void:
		_debug_force = DEBUG_FORCES[(DEBUG_FORCES.find(_debug_force) + 1) % DEBUG_FORCES.size()]
		button.text = "Debug landing: %s" % DEBUG_FORCE_NAMES[_debug_force]
		debug_force_changed.emit(_debug_force))
	list.add_child(button)


func open(settings: AppSettings) -> void:
	for key: String in _switches:
		(_switches[key] as CheckButton).set_pressed_no_signal(settings.get(key))
	for mode: String in _mode_buttons:
		(_mode_buttons[mode] as Button).set_pressed_no_signal(mode == settings.rethrow_mode)
	_show_sheet()


## What happens to the other dice when one has to be re-thrown: one of three, each explained.
func _add_rethrow_choice(list: VBoxContainer) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	list.add_child(box)
	var title: Label = Label.new()
	title.text = "Re-throws"
	box.add_child(title)
	var group: ButtonGroup = ButtonGroup.new()
	for mode: String in RethrowMode.MODES:
		var button: Button = Button.new()
		button.text = RethrowMode.NAMES[mode]
		button.theme_type_variation = "ChoiceButton"
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 72
		button.toggled.connect(func(on: bool) -> void:
			if on:
				rethrow_mode_changed.emit(mode))
		box.add_child(button)
		box.add_child(_muted(RethrowMode.DESCRIPTIONS[mode]))
		_mode_buttons[mode] = button
	var tip: Label = _muted("You can override this for individual dice sets in the set editor.")
	box.add_child(tip)


func _muted(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = "MutedLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _add_switch(column: VBoxContainer, key: String, title: String, hint: String) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	column.add_child(box)
	var switch: CheckButton = CheckButton.new()
	switch.text = title
	switch.custom_minimum_size.y = 80
	switch.toggled.connect(func(on: bool) -> void: changed.emit(key, on))
	box.add_child(switch)
	if not hint.is_empty():
		var label: Label = Label.new()
		label.text = hint
		label.theme_type_variation = "MutedLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
	_switches[key] = switch
