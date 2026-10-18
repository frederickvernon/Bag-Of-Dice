class_name PowerSaver
extends Node
## Low-power mode: once nothing has happened for `idle_after` seconds (no touch,
## no dice moving, nothing animating), the app draws only IDLE_FPS frames and
## runs IDLE_PHYSICS_TICKS physics steps a second, to save battery and keep the
## phone cool. Any touch, key or activity switches straight back to full speed.

const IDLE_FPS: int = 10
const IDLE_PHYSICS_TICKS: int = 30
## Full speed: no frame cap (the screen's own rate), physics as set in the project.
const ACTIVE_FPS: int = 0

## Seconds of quiet before going low-power.
@export var idle_after: float = 3.0

## Returns true while something needs full speed (dice moving, held or animating). Set by the main screen.
var busy_check: Callable = func() -> bool: return false
var idle: bool = false

var _quiet: float = 0.0
var _active_ticks: int = 120


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_active_ticks = Engine.physics_ticks_per_second


func _input(_event: InputEvent) -> void:
	wake()


func _process(delta: float) -> void:
	# A finger resting or dragging on the screen counts as activity too.
	if busy_check.call() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		wake()
		return
	# Real seconds, even while fast roll speeds the game up.
	_quiet += delta / maxf(Engine.time_scale, 0.01)
	if not idle and _quiet >= idle_after:
		_set_idle(true)


## Back to full speed now, and restart the quiet timer.
func wake() -> void:
	_quiet = 0.0
	if idle:
		_set_idle(false)


func _set_idle(on: bool) -> void:
	idle = on
	Engine.max_fps = IDLE_FPS if on else ACTIVE_FPS
	Engine.physics_ticks_per_second = IDLE_PHYSICS_TICKS if on else _active_ticks
