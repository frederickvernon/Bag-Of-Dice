class_name MenuIconButton
extends Button
## Small round button with a "≡" icon (drawn in code), for going back to the
## start menu from the table.


func _ready() -> void:
	custom_minimum_size = Vector2(72, 72)
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Menu"
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_corner_radius_all(18)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		add_theme_stylebox_override(state, style)


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var u: float = minf(size.x, size.y) / 72.0
	var ink: Color = Color(1, 1, 1, 0.95)
	for dy: float in [-11.0, 0.0, 11.0]:
		draw_line(Vector2(c.x - 16 * u, c.y + dy * u), Vector2(c.x + 16 * u, c.y + dy * u), ink, 4.0 * u, true)
