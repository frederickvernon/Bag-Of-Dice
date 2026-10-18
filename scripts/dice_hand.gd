class_name DiceHand
extends Node3D
## While armed, holds the dice as real physics bodies in an invisible cup above the near half of the table.
## Shaking kicks them around (the rattle is real collisions); on the throw the cup vanishes and they launch from there.
##
## Fairness: the cup only sets start position and motion; the throw still gives each die a uniformly random orientation.

## Seconds.
@export var gather_time: float = 0.35
## Inside height of the cup; x and z fit the dice plus cup_margin on each side.
@export var cup_height: float = 3.5
@export var cup_margin: float = 0.9
## Kick speed (units/s) at the hardest shake, and kicks per die per second.
@export var shake_kick: float = 11.0
@export var shake_kicks_per_second: float = 22.0
## Speed cap (units/s) in the cup, kicks included. Faster dice move so far between frames
## that they seem to jump (about 0.2 units a frame at 60 fps at this cap).
@export var max_speed_in_cup: float = 11.0
## Spin added with each kick, as a fraction of the kick speed, so dice tumble rather than slide.
@export var kick_spin: float = 0.16
## Small occasional nudges while held still, so the dice don't look frozen.
@export var idle_kick: float = 0.8
@export var idle_kicks_per_second: float = 0.6

## 0–1, set every frame from the shake detector.
var shake_level: float = 0.0
## Dice put back in the middle after getting outside the cup (shows as a jump), for tests.
var rescues: int = 0

var _dice: Array[Die] = []
var _cup: StaticBody3D
## Cup interior (world space), for putting back any die that escapes.
var _inside: AABB
var _tween: Tween
var _holding: bool = false
var _gathered: bool = false


func _ready() -> void:
	_cup = StaticBody3D.new()
	_cup.name = "Cup"
	var phys: PhysicsMaterial = PhysicsMaterial.new()
	phys.friction = 0.4
	phys.bounce = 0.5
	_cup.physics_material_override = phys
	add_child(_cup)
	_set_cup_enabled(false)


## `homes`: one world start position per die; the cup is built around them.
func gather(dice: Array[Die], homes: Array[Vector3]) -> void:
	release()
	if dice.is_empty():
		return
	_dice = dice.duplicate()
	_holding = true
	_gathered = false
	_build_cup(homes)

	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i: int in _dice.size():
		var die: Die = _dice[i]
		die.freeze = true
		var from: Transform3D = die.global_transform
		var to: Transform3D = Transform3D(Basis(_random_rotation()), homes[i])
		_tween.tween_method(
				func(t: float) -> void: die.global_transform = from.interpolate_with(to, t),
				0.0, 1.0, gather_time)
	_tween.chain().tween_callback(_drop_into_cup)


## Removes the cup and leaves the dice where they are, for the roller to throw or the set to reset.
func release() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_holding = false
	_gathered = false
	_dice.clear()
	_set_cup_enabled(false)


func _drop_into_cup() -> void:
	_gathered = true
	for die: Die in _dice:
		if not is_instance_valid(die):
			continue
		die.freeze = false
		die.sleeping = false
		die.linear_velocity = Vector3.ZERO
		die.angular_velocity = _random_unit_vector() * 3.0


func _physics_process(delta: float) -> void:
	if not _holding or not _gathered:
		return
	var kick_speed: float = lerpf(idle_kick, shake_kick, shake_level)
	var rate: float = idle_kicks_per_second if shake_level < 0.05 \
			else shake_kicks_per_second * shake_level
	for die: Die in _dice:
		if not is_instance_valid(die):
			continue
		_contain(die)
		# A near-still die during a shake is probably pinned; kick it more often so it mixes in.
		var die_rate: float = rate * (3.0 if shake_level >= 0.05 and die.linear_velocity.length() < 1.0 else 1.0)
		if randf() > die_rate * delta:
			continue
		# Mostly upward so dice hop and tumble, plus a random sideways part to mix them.
		var dir: Vector3 = (_random_unit_vector() + Vector3.UP * 0.8).normalized()
		die.sleeping = false
		# Set the speed directly, so a kick can't take a die past the cap.
		die.linear_velocity = (die.linear_velocity + dir * kick_speed * randf_range(0.6, 1.0)).limit_length(max_speed_in_cup)
		die.apply_torque_impulse(_random_unit_vector() * kick_speed * kick_spin * die.mass)


## Caps a die's speed and puts it back in the middle if it escapes anyway.
func _contain(die: Die) -> void:
	if die.linear_velocity.length() > max_speed_in_cup:
		die.linear_velocity = die.linear_velocity.limit_length(max_speed_in_cup)
	if not _inside.grow(0.3).has_point(die.global_position):
		rescues += 1
		die.global_position = _inside.get_center()
		die.linear_velocity = Vector3.ZERO


## Closed box (floor, walls, lid) around `homes`. Walls are thick and overlap at the corners, so there are no gaps.
func _build_cup(homes: Array[Vector3]) -> void:
	for child: Node in _cup.get_children():
		_cup.remove_child(child)
		child.queue_free()
	var lo: Vector3 = homes[0]
	var hi: Vector3 = homes[0]
	for p: Vector3 in homes:
		lo = lo.min(p)
		hi = hi.max(p)
	var centre: Vector3 = (lo + hi) * 0.5
	var inner: Vector3 = Vector3(hi.x - lo.x + 2.0 * cup_margin, cup_height, hi.z - lo.z + 2.0 * cup_margin)
	var floor_y: float = lo.y - 1.0
	var t: float = 1.0  # wall thickness
	var mid_y: float = floor_y + inner.y * 0.5
	var outer: Vector3 = inner + Vector3(2.0 * t, 2.0 * t, 2.0 * t)
	_inside = AABB(Vector3(centre.x - inner.x * 0.5, floor_y, centre.z - inner.z * 0.5), inner)
	_cup_box(Vector3(outer.x, t, outer.z), Vector3(centre.x, floor_y - t * 0.5, centre.z))
	_cup_box(Vector3(outer.x, t, outer.z), Vector3(centre.x, floor_y + inner.y + t * 0.5, centre.z))
	_cup_box(Vector3(t, outer.y, outer.z), Vector3(centre.x - (inner.x + t) * 0.5, mid_y, centre.z))
	_cup_box(Vector3(t, outer.y, outer.z), Vector3(centre.x + (inner.x + t) * 0.5, mid_y, centre.z))
	_cup_box(Vector3(outer.x, outer.y, t), Vector3(centre.x, mid_y, centre.z - (inner.z + t) * 0.5))
	_cup_box(Vector3(outer.x, outer.y, t), Vector3(centre.x, mid_y, centre.z + (inner.z + t) * 0.5))
	_set_cup_enabled(true)


func _cup_box(box_size: Vector3, global_pos: Vector3) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	_cup.add_child(shape)
	shape.global_position = global_pos


func _set_cup_enabled(enabled: bool) -> void:
	# Off the collision layers when not holding, so thrown dice pass through.
	_cup.collision_layer = 1 if enabled else 0
	_cup.collision_mask = 1 if enabled else 0
	for shape: Node in _cup.get_children():
		(shape as CollisionShape3D).disabled = not enabled


## Uniformly random orientation (Shoemake's method).
static func _random_rotation() -> Quaternion:
	var u1: float = randf()
	var u2: float = randf() * TAU
	var u3: float = randf() * TAU
	var a: float = sqrt(1.0 - u1)
	var b: float = sqrt(u1)
	return Quaternion(a * sin(u2), a * cos(u2), b * sin(u3), b * cos(u3))


static func _random_unit_vector() -> Vector3:
	return Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0)).normalized()
