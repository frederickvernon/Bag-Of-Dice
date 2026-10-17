class_name SetEditor
extends Control
## Full-screen dice set editor. Quick-add buttons reuse the last die's colour,
## so "3 red d6" is: pick red once, tap +d6 three times.
## Works on a copy; nothing changes until Save.

signal saved(set_data: Dictionary)
signal deleted(set_id: String)
signal cancelled
## Quick-roll mode only; the dice are never saved.
signal quick_ready(dice: Array[Dictionary])

var _set_id: String = ""
var _is_new: bool = true
## One-off quick roll: no name, no saving, "Roll" instead of "Save".
var _quick: bool = false
var _name_label: Label
var _duplicate_button: Button
## Working copy: [{ "type", "style", "color" (hex), "label" }]
var _dice: Array[Dictionary] = []

var _title: Label
var _name_edit: LineEdit
var _pick_toggle: CheckButton
var _count_label: Label
var _rows: VBoxContainer
var _empty_hint: Label
var _add_buttons: Array[Button] = []
var _error: Label
var _save_button: Button
var _delete_button: Button
var _color_popup: PopupPanel
var _color_target: int = -1
var _confirm_delete: ConfirmationDialog


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var background: ColorRect = ColorRect.new()
	background.color = UITheme.SURFACE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.theme_type_variation = "HeaderLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_duplicate_button = Button.new()
	_duplicate_button.text = "Duplicate"
	_duplicate_button.tooltip_text = "Make a copy of this set to change"
	_duplicate_button.pressed.connect(duplicate_set)
	header.add_child(_duplicate_button)

	_name_label = _muted("Name")
	column.add_child(_name_label)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. Fireball"
	_name_edit.max_length = DiceSetStore.MAX_NAME_LENGTH
	_name_edit.custom_minimum_size.y = 76
	_name_edit.text_changed.connect(func(_t: String) -> void: _validate())
	column.add_child(_name_edit)

	_pick_toggle = CheckButton.new()
	_pick_toggle.text = "Pick dice before each throw"
	# Wrap so the label can't push the editor off-screen.
	_pick_toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pick_toggle.custom_minimum_size.x = 0
	_pick_toggle.add_theme_font_size_override("font_size", 26)
	_pick_toggle.tooltip_text = "Choose which of the set's dice to throw each time, e.g. attack or defend dice"
	column.add_child(_pick_toggle)

	_count_label = _muted("")
	column.add_child(_count_label)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	scroll.add_child(DragScroll.new())
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 12)
	scroll.add_child(_rows)
	_empty_hint = _muted("No dice yet — tap a die below to add it.")
	_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(_empty_hint)

	column.add_child(_muted("Add a die"))
	# Wraps onto a second line on narrow screens.
	var add_grid: HFlowContainer = HFlowContainer.new()
	add_grid.add_theme_constant_override("h_separation", 12)
	add_grid.add_theme_constant_override("v_separation", 12)
	column.add_child(add_grid)
	for type: String in DiceFactory.TYPES:
		var b: Button = Button.new()
		b.text = "+ " + type
		b.custom_minimum_size = Vector2(104, 72)
		b.pressed.connect(_add_die.bind(type))
		add_grid.add_child(b)
		_add_buttons.append(b)

	_error = Label.new()
	_error.theme_type_variation = "ErrorLabel"
	column.add_child(_error)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	_delete_button = Button.new()
	_delete_button.text = "Delete"
	_delete_button.theme_type_variation = "DangerButton"
	_delete_button.custom_minimum_size.y = 84
	_delete_button.pressed.connect(_ask_delete)
	footer.add_child(_delete_button)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(150, 84)
	cancel.pressed.connect(func() -> void: cancel_editing())
	footer.add_child(cancel)
	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.theme_type_variation = "AccentButton"
	_save_button.custom_minimum_size = Vector2(150, 84)
	_save_button.pressed.connect(_save)
	footer.add_child(_save_button)

	_build_color_popup()

	_confirm_delete = ConfirmationDialog.new()
	_confirm_delete.title = "Delete set?"
	_confirm_delete.ok_button_text = "Delete"
	_confirm_delete.confirmed.connect(func() -> void:
		visible = false
		deleted.emit(_set_id))
	add_child(_confirm_delete)


func is_open() -> bool:
	return visible


## An empty `set_data` starts a blank new set.
func open(set_data: Dictionary) -> void:
	_set_quick(false)
	_is_new = set_data.is_empty()
	_set_id = DiceSetStore.new_id() if _is_new else str(set_data["id"])
	_title.text = "New set" if _is_new else "Edit set"
	_name_edit.text = "" if _is_new else str(set_data["name"])
	_pick_toggle.button_pressed = set_data.get("pick_dice", false)
	_dice.clear()
	for d: Dictionary in set_data.get("dice", []):
		_dice.append(d.duplicate())
	_delete_button.visible = not _is_new
	_duplicate_button.visible = not _is_new
	_rebuild_rows()
	visible = true
	if _is_new:
		_name_edit.grab_focus()


func open_quick() -> void:
	_set_quick(true)
	_is_new = true
	_title.text = "Quick roll"
	_name_edit.text = ""
	_pick_toggle.button_pressed = false
	_dice.clear()
	_delete_button.visible = false
	_duplicate_button.visible = false
	_rebuild_rows()
	visible = true


## Turns the edits so far into an unsaved "<name> (copy)". Cancel leaves the
## original untouched.
func duplicate_set() -> void:
	_is_new = true
	_set_id = DiceSetStore.new_id()
	_title.text = "New set"
	var copy_name: String = "%s (copy)" % _name_edit.text.strip_edges()
	_name_edit.text = copy_name.left(DiceSetStore.MAX_NAME_LENGTH)
	_delete_button.visible = false
	_duplicate_button.visible = false
	_name_edit.grab_focus()
	_name_edit.select_all()
	_validate()


func _set_quick(quick: bool) -> void:
	_quick = quick
	_name_label.visible = not quick
	_name_edit.visible = not quick
	_pick_toggle.visible = not quick
	_save_button.text = "Roll" if quick else "Save"


func cancel_editing() -> void:
	if _color_popup.visible:
		_color_popup.hide()
		return
	visible = false
	cancelled.emit()


func _save() -> void:
	if not _validate():
		return
	visible = false
	if _quick:
		quick_ready.emit(_dice.duplicate(true))
		return
	saved.emit({
		"id": _set_id, "name": _name_edit.text.strip_edges(),
		"pick_dice": _pick_toggle.button_pressed, "dice": _dice.duplicate(true),
	})


func _ask_delete() -> void:
	_confirm_delete.dialog_text = "Delete \"%s\"?\nThis can't be undone." % _name_edit.text.strip_edges()
	_confirm_delete.popup_centered()


func _add_die(type: String) -> void:
	if _room_left() < DiceFactory.dice_count(type):
		return
	var color: String = _dice[-1]["color"] if not _dice.is_empty() else DicePalette.DEFAULT_HEX
	_dice.append({ "type": type, "style": DiceFactory.default_style(type), "color": color, "label": "" })
	_rebuild_rows()


func _rebuild_rows() -> void:
	for child: Node in _rows.get_children():
		if child != _empty_hint:
			_rows.remove_child(child)
			child.queue_free()
	_empty_hint.visible = _dice.is_empty()
	for i: int in _dice.size():
		_rows.add_child(_make_row(i))
	var used: int = DiceSetStore.MAX_DICE - _room_left()
	_count_label.text = "Dice (%d of %d max · a d100 counts as 2)" % [used, DiceSetStore.MAX_DICE]
	for i: int in _add_buttons.size():
		_add_buttons[i].disabled = _room_left() < DiceFactory.dice_count(DiceFactory.TYPES[i])
	_validate()


## Physical dice still free (a d100 takes 2).
func _room_left() -> int:
	var used: int = 0
	for d: Dictionary in _dice:
		used += DiceFactory.dice_count(d["type"])
	return DiceSetStore.MAX_DICE - used


func _make_row(index: int) -> HBoxContainer:
	var d: Dictionary = _dice[index]
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var swatch: Button = Button.new()
	swatch.custom_minimum_size = Vector2(72, 72)
	_paint_swatch(swatch, DicePalette.from_hex(d["color"]))
	swatch.tooltip_text = "Colour"
	swatch.pressed.connect(_pick_color.bind(index))
	row.add_child(swatch)

	# Type and face style in one list: d4, d6 · pips, d6 · numbers, …
	var type_picker: OptionButton = OptionButton.new()
	var variants: Array[Dictionary] = DiceFactory.variants()
	var style: String = d.get("style", "")
	if not DiceFactory.is_valid_style(d["type"], style):
		style = DiceFactory.default_style(d["type"])
	for i: int in variants.size():
		type_picker.add_item(variants[i]["label"])
		if variants[i]["type"] == d["type"] and variants[i]["style"] == style:
			type_picker.select(i)
	type_picker.custom_minimum_size = Vector2(170, 72)
	type_picker.clip_text = true
	# Widening to "d6 · numbers" would push the row off-screen.
	type_picker.fit_to_longest_item = false
	type_picker.add_theme_font_size_override("font_size", 26)
	type_picker.item_selected.connect(func(i: int) -> void:
		var extra: int = DiceFactory.dice_count(variants[i]["type"]) - DiceFactory.dice_count(_dice[index]["type"])
		if extra > _room_left():
			_rebuild_rows()  # put the dropdown back
			_error.text = "No room for a d100 — it counts as 2 dice (max %d)." % DiceSetStore.MAX_DICE
			return
		_dice[index]["type"] = variants[i]["type"]
		_dice[index]["style"] = variants[i]["style"]
		_rebuild_rows())
	row.add_child(type_picker)

	var label_edit: LineEdit = LineEdit.new()
	label_edit.text = d["label"]
	label_edit.placeholder_text = "Label"
	label_edit.max_length = DiceSetStore.MAX_LABEL_LENGTH
	label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_edit.text_changed.connect(func(t: String) -> void: _dice[index]["label"] = t)
	row.add_child(label_edit)

	var remove: Button = Button.new()
	remove.text = "×"
	remove.theme_type_variation = "DangerButton"
	remove.custom_minimum_size = Vector2(72, 72)
	remove.pressed.connect(func() -> void:
		_dice.remove_at(index)
		_rebuild_rows())
	row.add_child(remove)
	return row


## Shows the reason when the set can't be saved.
func _validate() -> bool:
	var problem: String = ""
	if not _quick and _name_edit.text.strip_edges().is_empty():
		problem = "Give the set a name."
	elif _dice.is_empty():
		problem = "Add at least one die."
	_error.text = problem
	_save_button.disabled = not problem.is_empty()
	return problem.is_empty()


func _build_color_popup() -> void:
	_color_popup = PopupPanel.new()
	var grid: GridContainer = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	_color_popup.add_child(grid)
	for entry: Dictionary in DicePalette.COLORS:
		var b: Button = Button.new()
		b.custom_minimum_size = Vector2(76, 76)
		b.tooltip_text = entry["name"]
		_paint_swatch(b, entry["color"])
		var hex: String = DicePalette.to_hex(entry["color"])
		b.pressed.connect(func() -> void:
			if _color_target >= 0 and _color_target < _dice.size():
				_dice[_color_target]["color"] = hex
				_rebuild_rows()
			_color_popup.hide())
		grid.add_child(b)
	add_child(_color_popup)


func _pick_color(index: int) -> void:
	_color_target = index
	_color_popup.popup_centered()


func _paint_swatch(button: Button, color: Color) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(14)
		style.border_color = Color(1, 1, 1, 0.9 if state == "focus" else 0.35)
		style.set_border_width_all(3 if state == "focus" else 2)
		button.add_theme_stylebox_override(state, style)


func _muted(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = "MutedLabel"
	return l
