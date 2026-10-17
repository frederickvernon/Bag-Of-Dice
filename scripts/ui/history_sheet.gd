class_name HistorySheet
extends BottomSheet
## Bottom sheet of past rolls: set name, time, a coloured chip per die, total,
## and a Copy button. "Clear history" asks for confirmation first.

signal clear_confirmed

var _count: Label
var _list: VBoxContainer
var _empty_hint: Label
var _clear_button: Button
var _confirm: ConfirmationDialog


func _build_content(column: VBoxContainer) -> void:
	set_title("History")

	_count = Label.new()
	_count.theme_type_variation = "MutedLabel"
	column.add_child(_count)

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
	_empty_hint.text = "No rolls yet."
	_empty_hint.theme_type_variation = "MutedLabel"
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_empty_hint)

	_clear_button = Button.new()
	_clear_button.text = "Clear history"
	_clear_button.theme_type_variation = "DangerButton"
	_clear_button.custom_minimum_size.y = 80
	_clear_button.pressed.connect(_ask_clear)
	column.add_child(_clear_button)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Clear history?"
	_confirm.ok_button_text = "Clear"
	_confirm.confirmed.connect(func() -> void: clear_confirmed.emit())
	add_child(_confirm)


## `entries` are newest first.
func open(entries: Array[Dictionary]) -> void:
	refresh(entries)
	_show_sheet()


func refresh(entries: Array[Dictionary]) -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var now: int = int(Time.get_unix_time_from_system())
	for e: Dictionary in entries:
		_list.add_child(_make_entry(e, now))
	_empty_hint.visible = entries.is_empty()
	_clear_button.disabled = entries.is_empty()
	_count.text = "%d roll%s · the last %d are kept" % [entries.size(),
			"" if entries.size() == 1 else "s", RollHistory.MAX_ENTRIES]


## Lets Back close the "clear history?" confirmation first.
func is_confirming() -> bool:
	return _confirm.visible


func cancel_confirm() -> void:
	_confirm.hide()


func _ask_clear() -> void:
	var n: int = _list.get_child_count()
	_confirm.dialog_text = "Clear all %d roll%s?\nThis can't be undone." % [n, "" if n == 1 else "s"]
	_confirm.popup_centered()


func _make_entry(e: Dictionary, now: int) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = (get_theme_stylebox("normal", "CardButton") as StyleBoxFlat).duplicate()
	card.add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)

	var top: HBoxContainer = HBoxContainer.new()
	column.add_child(top)
	var name_label: Label = Label.new()
	name_label.text = e["set_name"] if not str(e["set_name"]).is_empty() else "Roll"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var time_label: Label = Label.new()
	time_label.text = RollHistory.format_time(e["time"], now)
	time_label.theme_type_variation = "MutedLabel"
	top.add_child(time_label)

	var chips: HFlowContainer = HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	column.add_child(chips)
	# Name the die type on each chip only when the roll mixes types.
	var types: Dictionary = {}
	for d: Dictionary in e["dice"]:
		types[d["type"]] = true
	for d: Dictionary in e["dice"]:
		chips.add_child(_make_chip(d, types.size() > 1))

	var bottom: HBoxContainer = HBoxContainer.new()
	column.add_child(bottom)
	var total: Label = Label.new()
	total.text = "Total: %d" % e["total"]
	total.theme_type_variation = "MutedLabel"
	total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(total)
	var copy: Button = Button.new()
	copy.text = "Copy"
	copy.add_theme_font_size_override("font_size", 24)
	copy.custom_minimum_size = Vector2(110, 56)
	var text: String = RollHistory.format_entry(e, now)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(text)
		copy.text = "Copied"
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			if is_instance_valid(copy):
				copy.text = "Copy"))
	bottom.add_child(copy)
	return card


## Value on the die's colour, label in front; a d100 also shows its two parts.
func _make_chip(d: Dictionary, show_type: bool) -> PanelContainer:
	var color: Color = DicePalette.from_hex(d["color"])
	var chip: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = BottomSheet.color_box(color, 10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", style)
	var text: String = str(d["value"])
	if d["type"] == "d100" and d["parts"].size() == 2:
		text += " (%02d+%d)" % [d["parts"][0], d["parts"][1]]
	if show_type:
		text = "%s: %s" % [d["type"], text]
	if not str(d["label"]).is_empty():
		text = "%s %s" % [d["label"], text]
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color.BLACK if color.get_luminance() > 0.5 else Color.WHITE)
	label.tooltip_text = d["type"]
	chip.add_child(label)
	return chip
