class_name RethrowDebugOverlay
extends Node3D
## Debug builds only: tags every die that is hopped or re-thrown with a number,
## and lists those numbers in a panel with the rule that fired, the tilt against
## the limit, how high the lowest corner sits and what the die is touching.
## The panel clears a few seconds after the last event. Hidden unless `enabled`.

const SHOW_SECONDS: float = 6.0
const MAX_LINES: int = 8

## Shows nothing while false; turning it off also clears what's showing.
var enabled: bool = false:
	set(value):
		enabled = value
		if not enabled and _panel != null:
			_lines.clear()
			_count = 0
			_panel.text = ""
			for child: Node in get_children():
				if child is Label3D:
					child.queue_free()

var _panel: Label
var _lines: Array[String] = []
var _count: int = 0
var _clear_timer: SceneTreeTimer


func watch(roller: DiceRoller) -> void:
	roller.debug_event.connect(_on_debug_event)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_panel = Label.new()
	_panel.add_theme_font_size_override("font_size", 17)
	_panel.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_panel.add_theme_color_override("font_outline_color", Color.BLACK)
	_panel.add_theme_constant_override("outline_size", 6)
	_panel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_left = 12
	_panel.offset_right = -12
	_panel.offset_top = 120
	layer.add_child(_panel)


func _on_debug_event(d: Die, info: Dictionary) -> void:
	if not enabled:
		return
	_count += 1
	var contacts: Array = info["touching"]
	_lines.append("%d  %s %s → %s · tilt %.1f° (limit %.1f°) · lowest %.2f · %s" % [
			_count, info["die"], info["rule"], info["action"], info["tilt"], info["threshold"],
			info["lowest"], "touching nothing" if contacts.is_empty() else ", ".join(contacts)])
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	_panel.text = "\n".join(_lines)
	_tag(d, str(_count))
	_clear_timer = get_tree().create_timer(SHOW_SECONDS, true, false, true)
	_clear_timer.timeout.connect(_clear_if_quiet.bind(_clear_timer))


func _tag(d: Die, text: String) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 96
	label.outline_size = 24
	label.pixel_size = 0.005
	label.modulate = Color(1.0, 0.85, 0.3)
	label.render_priority = 10
	label.outline_render_priority = 9
	add_child(label)
	label.global_position = d.global_position + Vector3.UP * 0.9
	var tween: Tween = label.create_tween()
	tween.tween_interval(SHOW_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func _clear_if_quiet(timer: SceneTreeTimer) -> void:
	if timer == _clear_timer:
		_lines.clear()
		_count = 0
		_panel.text = ""
