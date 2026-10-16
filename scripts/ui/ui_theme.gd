class_name UITheme
extends RefCounted
## App-wide theme, built in code and applied once at the UI root.
##
## Variations (via theme_type_variation):
##   AccentButton — the main action (Roll, Save)
##   DangerButton — destructive actions (Delete)
##   CardButton   — a tappable card in a list
##   HeaderLabel / MutedLabel — large titles / secondary text

const ACCENT: Color = Color(0.85, 0.55, 0.15)
const ACCENT_TEXT: Color = Color(0.1, 0.06, 0.02)
const SURFACE: Color = Color(0.12, 0.12, 0.14)
const RAISED: Color = Color(0.2, 0.2, 0.23)
const FIELD: Color = Color(0.07, 0.07, 0.08)
const TEXT: Color = Color(0.95, 0.95, 0.95)
const MUTED: Color = Color(0.68, 0.68, 0.72)
const DANGER: Color = Color(0.9, 0.35, 0.35)

const RADIUS: int = 18


static func build() -> Theme:
	var t: Theme = Theme.new()
	t.default_font_size = 30

	_button(t, "Button", RAISED, TEXT)
	_button(t, "OptionButton", RAISED, TEXT)
	t.set_type_variation("AccentButton", "Button")
	_button(t, "AccentButton", ACCENT, ACCENT_TEXT)
	t.set_type_variation("DangerButton", "Button")
	_button(t, "DangerButton", Color(0.32, 0.12, 0.12), Color(1.0, 0.82, 0.82))
	t.set_type_variation("CardButton", "Button")
	_button(t, "CardButton", RAISED, TEXT, 20, 18)

	t.set_color("font_color", "Label", TEXT)
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font_size("font_size", "HeaderLabel", 40)
	t.set_type_variation("MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", MUTED)
	t.set_font_size("font_size", "MutedLabel", 24)
	t.set_type_variation("ErrorLabel", "Label")
	t.set_color("font_color", "ErrorLabel", DANGER)
	t.set_font_size("font_size", "ErrorLabel", 24)

	var field: StyleBoxFlat = _box(FIELD, 12, 16, 12)
	var field_focus: StyleBoxFlat = field.duplicate()
	field_focus.border_color = ACCENT
	field_focus.set_border_width_all(2)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", ACCENT)

	t.set_stylebox("panel", "PanelContainer", _box(SURFACE, RADIUS, 24, 24))
	t.set_stylebox("panel", "PopupPanel", _box(RAISED, RADIUS, 16, 16))
	t.set_stylebox("panel", "PopupMenu", _box(RAISED, 12, 8, 8))
	t.set_font_size("font_size", "PopupMenu", 32)
	t.set_constant("v_separation", "PopupMenu", 18)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_stylebox("panel", "AcceptDialog", _box(RAISED, RADIUS, 24, 24))
	return t


static func _box(color: Color, radius: int, pad_h: float, pad_v: float) -> StyleBoxFlat:
	var b: StyleBoxFlat = StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	b.content_margin_left = pad_h
	b.content_margin_right = pad_h
	b.content_margin_top = pad_v
	b.content_margin_bottom = pad_v
	return b


static func _button(t: Theme, type: String, color: Color, text: Color,
		pad_h: float = 20.0, pad_v: float = 12.0) -> void:
	var normal: StyleBoxFlat = _box(color, RADIUS, pad_h, pad_v)
	var hover: StyleBoxFlat = _box(color.lightened(0.08), RADIUS, pad_h, pad_v)
	var pressed: StyleBoxFlat = _box(color.darkened(0.15), RADIUS, pad_h, pad_v)
	var disabled: StyleBoxFlat = _box(Color(0.3, 0.3, 0.32, 0.9), RADIUS, pad_h, pad_v)
	# Keyboard focus shows as an outline drawn over the normal look.
	var focus: StyleBoxFlat = _box(Color.TRANSPARENT, RADIUS, pad_h, pad_v)
	focus.draw_center = false
	focus.border_color = TEXT
	focus.set_border_width_all(2)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, focus)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		t.set_color(state, type, text)
	t.set_color("font_disabled_color", type, Color(0.72, 0.72, 0.72))
