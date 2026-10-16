class_name SettingsSheet
extends BottomSheet
## Settings switches. The main screen saves and applies each `changed` value.

## `key` is the AppSettings field ("sound", "haptics", "fast_roll" or "tap_to_roll").
signal changed(key: String, on: bool)

var _switches: Dictionary = {}  # key -> CheckButton


func _build_content(column: VBoxContainer) -> void:
	set_title("Settings")
	_add_switch(column, "sound", "Sound effects", "")
	_add_switch(column, "haptics", "Vibration", "A short buzz when dice hit something")
	_add_switch(column, "fast_roll", "Fast roll", "Dice roll and show their result faster")
	_add_switch(column, "tap_to_roll", "Tap or swipe to roll", "Tap the table to roll or throw; flick up to throw held dice")
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)


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
