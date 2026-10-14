class_name Die
extends RigidBody3D
## A single physics die. The result is read from the die's orientation once it
## has stopped moving — there is no random number involved in the result.

## The die bumped into `other` (the table, or another die) at `speed`
## (units/s, relative to the other die if it was one). For sound effects.
signal impact(die: Die, other: Node, speed: float)

## Speeds below these (units/s and rad/s) count as "not moving".
@export var rest_linear_threshold: float = 0.1
@export var rest_angular_threshold: float = 0.1
## How long the die must stay below both thresholds to count as settled.
@export var rest_time_required: float = 0.4

## e.g. "d6", or "d10" for each half of a d100. Set by DiceFactory.
var die_type: String = ""
## Each entry: { "direction": Vector3 (in the die's local space), "value": int }.
## The entry whose world-space direction points most nearly up is the result.
## For most dice the directions are face normals; for the d4 they point at
## the vertices, because a d4 is read from its top point.
## Also "show_normal" / "show_up" (local): the face to turn toward the viewer
## when presenting this result, and which way is "up" for its number.
var faces: Array[Dictionary] = []
## If the best direction is tilted more than this from straight up, the die is
## "cocked" (leaning on a wall or another die) and has no clear result.
var cocked_dot_threshold: float = cos(deg_to_rad(10.0))
## Which entry of the roller's dice list this die belongs to (a d100 is two
## dice sharing one index). Set by DiceRoller.
var group_index: int = 0
## Nudges used on the current roll. Managed by DiceRoller.
var nudges: int = 0
## Corners of the collision shape (local space). Set by DiceFactory.
var corners: PackedVector3Array = PackedVector3Array()

var _rest_timer: float = 0.0
var _moving_time: float = 0.0
## Velocity before the latest physics step — by the time a collision is
## reported, the solver has already slowed the die down.
var _prev_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Report collisions (needed for impact sounds).
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	_prev_velocity = Vector3.ZERO if freeze else linear_velocity


func get_prev_velocity() -> Vector3:
	return _prev_velocity


func _on_body_entered(other: Node) -> void:
	if freeze:
		return
	var other_velocity: Vector3 = Vector3.ZERO
	if other is Die:
		# Both dice report the same hit; let only one of them make a sound.
		if not (other as Die).freeze and other.get_instance_id() < get_instance_id():
			return
		other_velocity = (other as Die).get_prev_velocity()
	impact.emit(self, other, (_prev_velocity - other_velocity).length())


## Teleports the die and launches it.
func throw(start_position: Vector3, start_rotation: Basis, lin_vel: Vector3, ang_vel: Vector3) -> void:
	# Teleport first, while still frozen if it was being presented, then hand
	# it back to physics.
	global_transform = Transform3D(start_rotation, start_position)
	freeze = false
	sleeping = false
	linear_velocity = lin_vel
	angular_velocity = ang_vel
	_rest_timer = 0.0
	_moving_time = 0.0


## Call once per physics frame. Returns true once the die has been still for
## rest_time_required seconds.
func update_rest(delta: float) -> bool:
	if linear_velocity.length() < rest_linear_threshold \
			and angular_velocity.length() < rest_angular_threshold:
		_rest_timer += delta
		_moving_time = 0.0
	else:
		_rest_timer = 0.0
		_moving_time += delta
	return is_resting()


## How long this die has been moving without a break since it was last
## thrown, nudged or still.
func get_moving_time() -> float:
	return _moving_time


func is_resting() -> bool:
	return _rest_timer >= rest_time_required


## Returns the value facing up, or -1 if the die is cocked.
func get_top_face() -> int:
	var i: int = _top_face_index()
	return -1 if i == -1 else faces[i]["value"]


## The full faces entry for the result facing up ({} if cocked).
func get_top_face_entry() -> Dictionary:
	var i: int = _top_face_index()
	return {} if i == -1 else faces[i]


func _top_face_index() -> int:
	var best_dot: float = -2.0
	var best: int = -1
	for i: int in faces.size():
		var world_dir: Vector3 = (global_basis * (faces[i]["direction"] as Vector3)).normalized()
		var d: float = world_dir.dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best = i
	if best_dot < cocked_dot_threshold:
		return -1
	return best


## World-space height of the die's lowest corner. A die lying on the table
## has its lowest corner at table height; one resting on another die is
## well above it.
func get_lowest_point() -> float:
	var lowest: float = INF
	for c: Vector3 in corners:
		lowest = minf(lowest, (global_transform * c).y)
	return lowest


## An orientation lying flat on the table (showing its first face, turned
## by `yaw` radians), for placing a die neatly by code.
func resting_basis(yaw: float = 0.0) -> Basis:
	var up_dir: Vector3 = (faces[0]["direction"] as Vector3).normalized()
	return Basis(Vector3.UP, yaw) * Basis(Quaternion(up_dir, Vector3.UP))


## How high the centre sits above the table when the die has `basis`.
func rest_height(basis: Basis) -> float:
	var lowest: float = INF
	for c: Vector3 in corners:
		lowest = minf(lowest, (basis * c).y)
	return -lowest


## Greys out the die (body and numbers) to show it's sitting out.
func set_dimmed(dimmed: bool) -> void:
	var mesh: Mesh = (get_node("Body") as MeshInstance3D).mesh
	if not has_meta("base_colors"):
		var colors: Array[Color] = []
		for i: int in mesh.get_surface_count():
			colors.append((mesh.surface_get_material(i) as StandardMaterial3D).albedo_color)
		set_meta("base_colors", colors)
	var base: Array = get_meta("base_colors")
	var body: Color = base[0]
	var grey: Color = Color.from_hsv(body.h, body.s * 0.25, body.v * 0.4)
	for i: int in mesh.get_surface_count():
		var target: Color = grey if i == 0 else (base[i] as Color).lerp(grey, 0.6)
		(mesh.surface_get_material(i) as StandardMaterial3D).albedo_color = target if dimmed else base[i]


## Small hop and random twist to free a cocked die.
func nudge() -> void:
	sleeping = false
	apply_central_impulse(Vector3.UP * mass * 4.0)
	var axis: Vector3 = Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0)).normalized()
	apply_torque_impulse(axis * mass * 0.5)
	_rest_timer = 0.0
	_moving_time = 0.0
