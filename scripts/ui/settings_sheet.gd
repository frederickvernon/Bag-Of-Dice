class_name SettingsSheet
extends BottomSheet
## App settings. For now just sound; more options (haptics, fast roll, text
## size, backup) go here later.

signal sound_changed(on: bool)

var _sound: CheckButton


func _build_content(column: VBoxContainer) -> void:
	set_title("Settings")
	_sound = CheckButton.new()
	_sound.text = "Sound effects"
	_sound.custom_minimum_size.y = 80
	_sound.toggled.connect(func(on: bool) -> void: sound_changed.emit(on))
	column.add_child(_sound)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)


func open(sound_on: bool) -> void:
	_sound.set_pressed_no_signal(sound_on)
	_show_sheet()
