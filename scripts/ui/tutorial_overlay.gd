class_name TutorialOverlay
extends Control
## First-run tip over the table: a short line of text with an animated
## gesture (a tap ripple or an upward flick). Never blocks input.

## Seconds per loop of the gesture animation.
const LOOP_TIME: float = 1.4

var _panel: PanelContainer
var _label: Label
var _gesture: Control
var _kind: String = ""
var _time: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.12
	_panel.anchor_right = 0.88
	# Upper part of the table, clear of the dice lying in the middle.
	_panel.anchor_top = 0.3
	_panel.anchor_bottom = 0.3
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.62)
	style.set_corner_radius_all(22)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)
	_gesture = Control.new()
	_gesture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gesture.custom_minimum_size = Vector2(0, 110)
	_gesture.draw.connect(_draw_gesture)
	column.add_child(_gesture)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 30)
	column.add_child(_label)


## `gesture`: "tap", "flick" or "" (text only).
func show_tip(text: String, gesture: String) -> void:
	_label.text = text
	_kind = gesture
	_gesture.visible = not gesture.is_empty()
	if not visible:
		_time = 0.0
	visible = true


func hide_tip() -> void:
	visible = false


func _process(delta: float) -> void:
	if visible and not _kind.is_empty():
		_time += delta
		_gesture.queue_redraw()


func _draw_gesture() -> void:
	var t: float = fmod(_time, LOOP_TIME) / LOOP_TIME
	var c: Vector2 = _gesture.size * 0.5
	var ink: Color = UITheme.ACCENT
	if _kind == "tap":
		# Fingertip dot with a ripple spreading out from it.
		_gesture.draw_circle(c, 14.0, ink)
		var ripple: Color = ink
		ripple.a = 1.0 - t
		_gesture.draw_arc(c, 18.0 + t * 42.0, 0.0, TAU, 48, ripple, 4.0, true)
	elif _kind == "flick":
		# A dot sliding upward, leaving a fading trail, with an arrow head.
		var top: Vector2 = c + Vector2(0, -42)
		var bottom: Vector2 = c + Vector2(0, 42)
		var eased: float = ease(minf(t / 0.7, 1.0), 0.4)
		var dot: Vector2 = bottom.lerp(top, eased)
		var fade: Color = ink
		fade.a = 1.0 - maxf(t - 0.7, 0.0) / 0.3
		_gesture.draw_line(bottom, dot, Color(ink, 0.35 * fade.a), 10.0, true)
		_gesture.draw_circle(dot, 14.0, fade)
		_gesture.draw_polyline(PackedVector2Array([top + Vector2(-16, 18), top, top + Vector2(16, 18)]),
				Color(ink, 0.8), 5.0, true)
