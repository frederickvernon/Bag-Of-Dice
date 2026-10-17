class_name SettingsSheet
extends BottomSheet
## Settings switches. The main screen saves and applies each `changed` value.

## `key` is the AppSettings field ("sound", "haptics", "fast_roll", "tap_to_roll" or "menu_button").
signal changed(key: String, on: bool)
signal replay_tips_pressed
## Debug builds only: "" (off), "lean" or "stack"; see DiceRoller.debug_force.
signal debug_force_changed(kind: String)

const DEBUG_FORCES: Array[String] = ["", "lean", "stack"]
const DEBUG_FORCE_NAMES: Dictionary = { "": "off", "lean": "lean on rim", "stack": "stack" }

var _switches: Dictionary = {}  # key -> CheckButton
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
	_show_sheet()


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
