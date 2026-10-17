class_name SetDrawer
extends BottomSheet
## Bottom sheet of dice sets. Tapping a card puts that set on the table.

signal set_chosen(set_id: String)
signal edit_requested(set_id: String)
signal new_requested

var _list: VBoxContainer
var _empty_hint: Label


func _build_content(column: VBoxContainer) -> void:
	set_title("Dice sets")

	var new_button: Button = Button.new()
	new_button.text = "+  New set"
	new_button.theme_type_variation = "AccentButton"
	new_button.custom_minimum_size.y = 84
	new_button.pressed.connect(func() -> void: new_requested.emit())
	column.add_child(new_button)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	scroll.add_child(DragScroll.new())
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_list)

	_empty_hint = Label.new()
	_empty_hint.text = "No dice sets yet.\nTap \"New set\" to make one."
	_empty_hint.theme_type_variation = "MutedLabel"
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_empty_hint)


func open(sets: Array[Dictionary], current_id: String) -> void:
	_rebuild(sets, current_id)
	_show_sheet()


func _rebuild(sets: Array[Dictionary], current_id: String) -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_empty_hint.visible = sets.is_empty()
	for s: Dictionary in sets:
		_list.add_child(_make_card(s, s["id"] == current_id))


## The whole card is a button; Edit sits on top of it.
func _make_card(set_data: Dictionary, is_current: bool) -> Button:
	var card: Button = Button.new()
	card.theme_type_variation = "CardButton"
	card.custom_minimum_size.y = 128
	if is_current:
		# Looked up on the drawer: the new card isn't in the themed tree yet.
		var style: StyleBoxFlat = (get_theme_stylebox("normal", "CardButton") as StyleBoxFlat).duplicate()
		style.border_color = UITheme.ACCENT
		style.set_border_width_all(3)
		card.add_theme_stylebox_override("normal", style)
	var id: String = set_data["id"]
	card.pressed.connect(func() -> void: set_chosen.emit(id))

	# Overlay ignores the mouse so taps reach the card; only Edit takes its own.
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20 if side in ["left", "right"] else 14)
	card.add_child(margin)
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	var info: VBoxContainer = VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var name_label: Label = Label.new()
	name_label.text = set_data["name"]
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_label)
	var detail: HBoxContainer = HBoxContainer.new()
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_theme_constant_override("separation", 10)
	info.add_child(detail)
	for hex: String in _distinct_colors(set_data):
		detail.add_child(_color_dot(DicePalette.from_hex(hex)))
	var summary: Label = Label.new()
	summary.text = DiceSetStore.summary(set_data)
	if set_data.get("pick_dice", false):
		summary.text += "  ·  pick dice"
	summary.theme_type_variation = "MutedLabel"
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(summary)

	var edit: Button = Button.new()
	edit.text = "Edit"
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.custom_minimum_size = Vector2(110, 72)
	edit.pressed.connect(func() -> void: edit_requested.emit(id))
	row.add_child(edit)
	return card


func _color_dot(color: Color) -> Panel:
	var dot: Panel = Panel.new()
	dot.custom_minimum_size = Vector2(24, 24)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", BottomSheet.color_box(color, 12))
	return dot


static func _distinct_colors(set_data: Dictionary) -> PackedStringArray:
	var seen: PackedStringArray = PackedStringArray()
	for d: Dictionary in set_data["dice"]:
		if not seen.has(d["color"]) and seen.size() < 6:
			seen.append(d["color"])
	return seen
