class_name StartMenu
extends Control
## The menu shown when the app opens (and when Back is pressed on the table):
## continue with the current dice, a one-tap quick roll, the dice sets,
## history and settings. The table stays loaded behind it.

signal continue_pressed
## A quick roll of these die types, e.g. ["d6", "d6"].
signal quick_roll(types: Array[String])
signal custom_quick_pressed
signal sets_pressed
signal history_pressed
signal settings_pressed

const QUICK_ROLLS: Array[Dictionary] = [
	{ "label": "1d6", "dice": ["d6"] },
	{ "label": "2d6", "dice": ["d6", "d6"] },
	{ "label": "1d20", "dice": ["d20"] },
]

var _continue_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Background: the splash art, dimmed so the buttons read clearly on it.
	var art: TextureRect = TextureRect.new()
	art.texture = load("res://assets/splash.png")
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(art)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.05, 0.07, 0.06, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var title: Label = Label.new()
	title.text = "Bag of Dice"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	column.add_child(title)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	_continue_button = _button("Continue", "AccentButton", 96)
	_continue_button.add_theme_font_size_override("font_size", 34)
	_continue_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_continue_button.pressed.connect(func() -> void: continue_pressed.emit())
	column.add_child(_continue_button)

	var quick_label: Label = Label.new()
	quick_label.text = "Quick roll"
	quick_label.theme_type_variation = "MutedLabel"
	column.add_child(quick_label)
	# Four equal columns, so the buttons never squeeze into each other.
	var quick_row: GridContainer = GridContainer.new()
	quick_row.columns = 4
	quick_row.add_theme_constant_override("h_separation", 12)
	column.add_child(quick_row)
	for q: Dictionary in QUICK_ROLLS:
		var b: Button = _quick_button(q["label"])
		var types: Array[String] = []
		types.assign(q["dice"])
		b.pressed.connect(func() -> void: quick_roll.emit(types))
		quick_row.add_child(b)
	var custom: Button = _quick_button("Custom")
	custom.pressed.connect(func() -> void: custom_quick_pressed.emit())
	quick_row.add_child(custom)

	var gap: Control = Control.new()
	gap.custom_minimum_size.y = 8
	column.add_child(gap)

	for entry: Array in [["Dice sets", sets_pressed], ["History", history_pressed], ["Settings", settings_pressed]]:
		var b: Button = _button(entry[0], "", 84)
		var sig: Signal = entry[1]
		b.pressed.connect(func() -> void: sig.emit())
		column.add_child(b)


## Shows "Continue: <name>", or hides the button when there's nothing to
## continue with ("" name).
func set_continue_name(set_name: String) -> void:
	_continue_button.visible = not set_name.is_empty()
	_continue_button.text = "Continue: %s" % set_name


func _quick_button(text: String) -> Button:
	var b: Button = _button(text, "", 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 28)
	b.custom_minimum_size.x = 0
	# Less side padding than normal buttons, so four fit across a phone.
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var style: StyleBox = get_theme_stylebox(state, "Button").duplicate()
		style.content_margin_left = 4
		style.content_margin_right = 4
		b.add_theme_stylebox_override(state, style)
	return b


func _button(text: String, variation: String, height: float) -> Button:
	var b: Button = Button.new()
	b.text = text
	if not variation.is_empty():
		b.theme_type_variation = variation
	b.custom_minimum_size.y = height
	return b
