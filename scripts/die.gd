class_name Die
extends RigidBody3D
## A single physics die. The result is read from the die's orientation once it
## has stopped moving — there is no random number involved in the result.

## The die bumped into `other` (the table, or another die) at `speed`
## (units/s, relative to the other die if it was one). For sound effects.
signal impact(die: Die, other: Node, speed: float)

## A die can be read when the direction pointing most nearly up is within this fraction
## of its ambiguity angle: half the angle between neighbouring face directions (45° on a
## d6, so 22.5°). Past that it's too close to tipping either way and gets a hop.
## The d4 uses its corners (54.7°, so 27.4°). Tune each type here.
const READABLE_FRACTION: Dictionary = {
	"d4": 0.5, "d6": 0.5, "d8": 0.5, "d10": 0.5, "d12": 0.5, "d20": 0.5,
}
## The hop for a die that can't be read: mostly lift (impulse per unit mass) with
## a little spin, so it drops onto one of the faces it was leaning between.
const HOP_LIFT: float = 3.5
const HOP_SPIN: float = 0.12
## How long a readable but tilted die takes to ease flat (purely visual).
const EASE_FLAT_SECONDS: float = 0.25

## Speeds below these (units/s and rad/s) count as "not moving".
@export var rest_linear_threshold: float = 0.1
@export var rest_angular_threshold: float = 0.1
## How long the die must stay below both thresholds to count as settled.
@export var rest_time_required: float = 0.4

## e.g. "d6", or "d10" for each half of a d100. Set by DiceFactory.
var die_type: String = ""
## { "direction": Vector3 (local), "value": int, "show_normal", "show_up" }. The direction
## pointing most nearly up wins; it's a face normal, or a vertex for the d4 (read from its top).
## show_normal/show_up: the face turned to the viewer when presenting, and its number's up.
var faces: Array[Dictionary] = []
## Entry in the roller's dice list (a d100's two dice share one). Set by DiceRoller.
var group_index: int = 0
## Nudges used on the current roll. Managed by DiceRoller.
var nudges: int = 0
## Corners of the collision shape (local space). Set by DiceFactory.
var corners: PackedVector3Array = PackedVector3Array()

var _limit_degrees: float = -1.0
## Eases the Body mesh flat; the physics body itself never moves.
var _ease_tween: Tween
var _eased: bool = false
var _rest_timer: float = 0.0
var _moving_time: float = 0.0
## Velocity before the latest step; by the time a collision is reported the solver has slowed the die.
var _prev_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Report collisions (needed for impact sounds).
	contact_monitor = true
	# 8, so a die resting on a face (4 contacts) can still report a wall or die it leans on.
	max_contacts_reported = 8
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	_prev_velocity = Vector3.ZERO if freeze else linear_velocity
	# Knocked after easing flat: show the real pose again.
	if _eased and not freeze and (linear_velocity.length() > rest_linear_threshold * 3.0
			or angular_velocity.length() > rest_angular_threshold * 3.0):
		reset_visual()


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
	# Teleport while still frozen (if it was being presented), then hand back to physics.
	reset_visual()
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


## Returns the value facing up, or -1 if the die is tilted too far to read (cocked).
func get_top_face() -> int:
	var i: int = _top_face_index()
	return -1 if i == -1 else faces[i]["value"]


## Largest tilt (degrees) at which the die still counts as readable (see READABLE_FRACTION).
func readable_limit_degrees() -> float:
	if _limit_degrees < 0.0:
		var smallest: float = PI
		for i: int in faces.size():
			for j: int in range(i + 1, faces.size()):
				smallest = minf(smallest, (faces[i]["direction"] as Vector3).angle_to(faces[j]["direction"]))
		_limit_degrees = rad_to_deg(smallest * 0.5) * float(READABLE_FRACTION.get(die_type, 0.5))
	return _limit_degrees


## How far (degrees) the face pointing most nearly up is from straight up.
func get_tilt_degrees() -> float:
	var best_dot: float = -1.0
	for f: Dictionary in faces:
		best_dot = maxf(best_dot, (global_basis * (f["direction"] as Vector3)).normalized().dot(Vector3.UP))
	return rad_to_deg(acos(clampf(best_dot, -1.0, 1.0)))


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
	if rad_to_deg(acos(clampf(best_dot, -1.0, 1.0))) > readable_limit_degrees():
		return -1
	return best


## World-space height of the lowest corner; well above table height means it's resting on another die.
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


## Eases the visible die flat onto the face it was read from, tipping over its
## lowest corner. Visual only: the physics body and the reading don't change.
func ease_flat() -> void:
	var entry: Dictionary = get_top_face_entry()
	if entry.is_empty() or _eased:
		return
	var dir: Vector3 = (global_basis * (entry["direction"] as Vector3)).normalized()
	if dir.angle_to(Vector3.UP) < deg_to_rad(1.0):
		return
	var pivot: Vector3 = Vector3(0.0, INF, 0.0)
	for c: Vector3 in corners:
		var p: Vector3 = global_transform * c
		if p.y < pivot.y:
			pivot = p
	var tip: Transform3D = Transform3D(Basis(Quaternion(dir, Vector3.UP)), Vector3.ZERO)
	var flat: Transform3D = Transform3D(Basis.IDENTITY, pivot) * tip \
			* Transform3D(Basis.IDENTITY, -pivot) * global_transform
	var body: Node3D = get_node("Body")
	_eased = true
	_ease_tween = create_tween()
	_ease_tween.tween_property(body, "transform", global_transform.affine_inverse() * flat, EASE_FLAT_SECONDS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Puts the visible die back on the physics body.
func reset_visual() -> void:
	if _ease_tween != null:
		_ease_tween.kill()
	_eased = false
	(get_node("Body") as Node3D).transform = Transform3D.IDENTITY


## Moves the body to where the eased-flat die is shown, so presenting it starts
## from what the player sees. Only for a die about to be frozen.
func bake_visual() -> void:
	if not _eased:
		return
	if _ease_tween != null:
		_ease_tween.kill()
	var shown: Transform3D = global_transform * (get_node("Body") as Node3D).transform
	(get_node("Body") as Node3D).transform = Transform3D.IDENTITY
	_eased = false
	global_transform = shown


## Gentle hop to free a die that can't be read: mostly lift, little spin.
func nudge() -> void:
	reset_visual()
	sleeping = false
	apply_central_impulse(Vector3.UP * mass * HOP_LIFT)
	var axis: Vector3 = Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0)).normalized()
	apply_torque_impulse(axis * mass * HOP_SPIN)
	_rest_timer = 0.0
	_moving_time = 0.0
