class_name SoundToggle
extends Button
## Small round button showing a speaker: with sound waves when sound is on,
## with a cross when it's off. The icon is drawn in code (no image files).
## Use `button_pressed` for on/off; `toggled` fires when tapped.


func _ready() -> void:
	toggle_mode = true
	custom_minimum_size = Vector2(72, 72)
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Sound on / off"
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_corner_radius_all(18)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		add_theme_stylebox_override(state, style)
	toggled.connect(func(_on: bool) -> void: queue_redraw())


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var u: float = minf(size.x, size.y) / 72.0  # drawn on a 72 x 72 grid
	var ink: Color = Color(1, 1, 1, 0.95) if button_pressed else Color(1, 1, 1, 0.6)
	var left: float = c.x - 20 * u
	# Speaker: a small box with a cone opening to the right.
	draw_rect(Rect2(left, c.y - 7 * u, 9 * u, 14 * u), ink)
	draw_colored_polygon(PackedVector2Array([
		Vector2(left + 8 * u, c.y - 7 * u), Vector2(left + 20 * u, c.y - 16 * u),
		Vector2(left + 20 * u, c.y + 16 * u), Vector2(left + 8 * u, c.y + 7 * u),
	]), ink)
	var wx: float = left + 24 * u
	if button_pressed:
		# Two sound waves.
		draw_arc(Vector2(wx, c.y), 7 * u, -PI / 3.5, PI / 3.5, 16, ink, 3.5 * u, true)
		draw_arc(Vector2(wx, c.y), 15 * u, -PI / 3.5, PI / 3.5, 16, ink, 3.5 * u, true)
	else:
		# A cross: muted.
		var x0: float = wx + 3 * u
		draw_line(Vector2(x0, c.y - 9 * u), Vector2(x0 + 16 * u, c.y + 9 * u), ink, 3.5 * u, true)
		draw_line(Vector2(x0, c.y + 9 * u), Vector2(x0 + 16 * u, c.y - 9 * u), ink, 3.5 * u, true)
