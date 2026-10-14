class_name BottomSheet
extends Control
## A panel that slides up from the bottom of the screen over a dimmed
## background, with a title and a Close button. Tapping the dimmed area also
## closes it. Subclasses add their content in _build_content().

signal closed

## Fraction of the screen height the sheet covers.
@export var sheet_height: float = 0.78
@export var slide_time: float = 0.25

var _dim: ColorRect
var _sheet: PanelContainer
var _title: Label
var _tween: Tween
var _closing: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	_sheet = PanelContainer.new()
	_sheet.anchor_left = 0.0
	_sheet.anchor_right = 1.0
	_sheet.anchor_top = 1.0 - sheet_height
	_sheet.anchor_bottom = 1.0
	# Square off the bottom corners; only the top ones are rounded.
	var style: StyleBoxFlat = (get_theme_stylebox("panel", "PanelContainer") as StyleBoxFlat).duplicate()
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	_sheet.add_theme_stylebox_override("panel", style)
	add_child(_sheet)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_sheet.add_child(column)

	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.theme_type_variation = "HeaderLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	header.add_child(close_button)

	_build_content(column)


## Override to add the sheet's content below the header.
func _build_content(_column: VBoxContainer) -> void:
	pass


func set_title(text: String) -> void:
	_title.text = text


## True while showing, false as soon as it starts sliding away.
func is_open() -> bool:
	return visible and not _closing


func close() -> void:
	if not is_open():
		return
	_slide(false)
	closed.emit()


## Shows the sheet, sliding it up.
func _show_sheet() -> void:
	visible = true
	_slide(true)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close()


func _slide(show_sheet: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_closing = not show_sheet
	var hidden_offset: float = get_viewport_rect().size.y * sheet_height
	if show_sheet:
		_sheet.offset_top = hidden_offset
		_sheet.offset_bottom = hidden_offset
		_dim.modulate.a = 0.0
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var target: float = 0.0 if show_sheet else hidden_offset
	_tween.tween_property(_sheet, "offset_top", target, slide_time)
	_tween.tween_property(_sheet, "offset_bottom", target, slide_time)
	_tween.tween_property(_dim, "modulate:a", 1.0 if show_sheet else 0.0, slide_time)
	if not show_sheet:
		_tween.chain().tween_callback(func() -> void:
			visible = false
			_closing = false)


## A small rounded patch of colour (e.g. a die colour dot or result chip).
static func color_box(color: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = Color(1, 1, 1, 0.45)
	style.set_border_width_all(1)
	return style
