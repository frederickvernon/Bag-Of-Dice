class_name DragScroll
extends Node
## Lets a finger drag scroll the parent ScrollContainer even when the drag starts
## on a switch or button inside it (Godot only scrolls drags that start on empty
## space). Once the finger has moved far enough to be a drag, the press on the
## control underneath is cancelled so it doesn't toggle when the finger lifts.
## Touch arrives as emulated mouse, so this reads mouse events.

const DRAG_START_PX: float = 14.0

var _scroll: ScrollContainer
var _tracking: bool = false
var _dragging: bool = false
var _cancelling: bool = false
var _start: Vector2
var _start_scroll: int


func _ready() -> void:
	_scroll = get_parent()


func _input(event: InputEvent) -> void:
	if _cancelling or not _scroll.is_visible_in_tree():
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_tracking = _scroll.get_global_rect().has_point(button.position)
			_dragging = false
			_start = button.position
			_start_scroll = _scroll.scroll_vertical
		elif _tracking:
			_tracking = false
			if _dragging:
				_dragging = false
				get_viewport().set_input_as_handled()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null or not _tracking:
		return
	var dy: float = motion.position.y - _start.y
	if not _dragging and absf(dy) > DRAG_START_PX:
		_dragging = true
		_cancel_press()
	if _dragging:
		_scroll.scroll_vertical = _start_scroll - int(dy)
		get_viewport().set_input_as_handled()


## Slides the pointer far off screen and releases it there: the pressed control
## sees the press end outside itself, so it lets go without firing.
func _cancel_press() -> void:
	var away: Vector2 = Vector2(-10000.0, -10000.0)
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	move.position = away
	move.global_position = away
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = away
	up.global_position = away
	_cancelling = true
	get_viewport().push_input(move)
	get_viewport().push_input(up)
	_cancelling = false
