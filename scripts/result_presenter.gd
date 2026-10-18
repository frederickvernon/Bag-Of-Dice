class_name ResultPresenter
extends Node
## After a roll, lifts the dice to the top of the screen with results facing the viewer, so small dice are readable.
## Purely visual: results are read before the dice are lifted, so lifting can't change them.

## Seconds.
@export var duration: float = 0.6
## Gap between dice centres in the display grid (full-size units).
@export var spacing: float = 2.0
@export var max_columns: int = 5
## Closest the dice come to the camera, capping their on-screen size; at 14 one die is about 1/6 of screen width.
@export var min_depth: float = 14.0
## Gap (pixels) between `top_px` and the first row of dice.
@export var top_gap: float = 10.0
## Optional turn (degrees, about screen x and y) to show the dice's sides; face-on reads best.
@export var tilt: Vector2 = Vector2.ZERO
## Delay (seconds) between each die starting to move, for a ripple effect.
@export var stagger: float = 0.05

var _tween: Tween


## Lines up settled dice between screen heights `top_px` and `bottom_px` (e.g. result bar and buttons).
## Each die must have a clear top face.
func present(dice: Array[Die], camera: Camera3D, top_px: float, bottom_px: float) -> void:
	cancel()
	if dice.is_empty():
		return

	var count: int = dice.size()
	var max_cols: int = max_columns
	for die: Die in dice:
		if die.name.begins_with("D100"):
			# Even column count keeps each d100's tens and units dice side by side.
			max_cols = max_columns - max_columns % 2
			break
	var columns: int = mini(count, max_cols)
	var rows: int = ceili(float(count) / columns)
	# Sizes are for full-size dice; scaling by k keeps results the same on-screen size.
	# The camera keeps its width fixed, so `fov` is the horizontal angle.
	var k: float = DiceFactory.SCALE
	var gap: float = spacing * k
	var screen: Vector2 = camera.get_viewport().get_visible_rect().size
	var half_fov_tan: float = tan(deg_to_rad(camera.fov) * 0.5)
	var grid_width: float = (columns * spacing + 1.2) * k
	# Far enough back that the grid fits across the screen and all rows fit between top_px and bottom_px.
	var depth: float = maxf(min_depth * k, grid_width / (2.0 * half_fov_tan))
	var grid_height: float = (rows - 1) * gap + 2.0 * k
	var room_px: float = maxf(bottom_px - top_px - 2.0 * top_gap, 100.0)
	depth = maxf(depth, screen.x * grid_height / (2.0 * half_fov_tan * room_px))
	# Pixels per unit at that depth, to keep a die's radius (about 1 unit) clear of top_px.
	var px_per_unit: float = screen.x / (2.0 * depth * half_fov_tan)
	var first_row_y: float = top_px + top_gap + px_per_unit * k
	var first_row: Vector3 = camera.project_position(Vector2(screen.x * 0.5, first_row_y), depth)
	var cam_basis: Basis = camera.global_basis

	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i: int in count:
		var die: Die = dice[i]
		var row: int = int(i / float(columns))
		var col: int = i % columns
		var in_this_row: int = mini(columns, count - row * columns)
		var x: float = (col - (in_this_row - 1) * 0.5) * gap
		var y: float = -row * gap
		var turn: Basis = Basis(cam_basis.x.normalized(), deg_to_rad(tilt.x)) \
				* Basis(cam_basis.y.normalized(), deg_to_rad(tilt.y))
		var pos: Vector3 = first_row + cam_basis.x * x + cam_basis.y * y
		# Face the camera position, not its view direction, so off-centre dice don't show their sides.
		var to_camera: Vector3 = (camera.global_position - pos).normalized()
		var right: Vector3 = cam_basis.y.cross(to_camera).normalized()
		var view: Basis = Basis(right, to_camera.cross(right), to_camera)
		var target: Transform3D = Transform3D(
				turn * _facing_basis(die.result_entry(), view), pos)

		die.freeze = true
		var from: Transform3D = die.global_transform
		_tween.tween_method(
				func(t: float) -> void: die.global_transform = from.interpolate_with(target, t),
				0.0, 1.0, duration).set_delay(i * stagger)


func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## Turns the result face toward the viewer, number upright. `cam_basis`: x right, y up, z toward the viewer.
static func _facing_basis(face: Dictionary, cam_basis: Basis) -> Basis:
	if face.is_empty():
		return cam_basis
	var n: Vector3 = face["show_normal"]
	var up: Vector3 = face["show_up"]
	# The face's frame in die space (x right, y up, z out of the face), mapped onto the camera's.
	var face_frame: Basis = Basis(up.cross(n), up, n)
	return cam_basis.orthonormalized() * face_frame.transposed()
