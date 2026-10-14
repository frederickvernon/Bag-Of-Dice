class_name DicePicker
extends Node3D
## "Pick up" step for sets with pick_dice on: lays the set's dice out on the
## table and lets the player choose which to throw.
##
##   Tap a die        — pick it for this throw (it lifts and brightens), or
##                      put it back (it settles and dims).
##   Long-press a die — lock it: picked automatically for every throw, shown
##                      with a ring, until long-pressed again.
##
## Works per entry of the set (a d100's two dice count as one). Dice with a
## label show it above them so e.g. attack and defend dice are easy to tell
## apart. Purely a selection step: it doesn't touch the physics or results.

## The set of picked entries changed; `count` is how many are picked.
signal selection_changed(count: int)

## Seconds a press must be held to count as a long press.
@export var long_press_time: float = 0.5
## How close (screen pixels) a tap must land to a die's centre.
@export var tap_radius: float = 60.0
## Taps that move further than this are drags, not taps.
@export var tap_slop: float = 24.0
## Gap between dice centres (for full-size dice; scaled with the dice). Wide
## enough that the biggest dice (d20, d12) don't touch.
@export var spacing: float = 2.3
## An even number, so a d100's two dice always share a row.
@export var max_columns: int = 4
## How far picked dice lift off the table.
@export var lift: float = 0.6

var _roller: DiceRoller
var _camera: Camera3D
var _active: bool = false
var _picked: Dictionary = {}  # entry index -> true
var _locked: Dictionary = {}  # entry index -> true
var _home: Dictionary = {}    # Die -> Transform3D resting in the layout
var _rings: Dictionary = {}   # entry index -> MeshInstance3D
var _tags: Array[Label3D] = []
var _press_pos: Vector2 = Vector2.ZERO
var _press_time: float = -1.0
var _press_group: int = -1
var _long_fired: bool = false
var _tween: Tween


## Lay out `roller`'s dice and start picking. `locked` (entry -> true) are
## locked from before and start picked.
func begin(roller: DiceRoller, camera: Camera3D, locked: Dictionary) -> void:
	end()
	_roller = roller
	_camera = camera
	_active = true
	_locked = locked.duplicate()
	_picked = _locked.duplicate()
	_layout()
	_refresh()


## Stop picking and remove the rings and tags (dice stay where they are).
func end() -> void:
	_active = false
	_press_time = -1.0
	for ring: MeshInstance3D in _rings.values():
		ring.queue_free()
	_rings.clear()
	for tag: Label3D in _tags:
		tag.queue_free()
	_tags.clear()
	_home.clear()
	if _tween != null and _tween.is_valid():
		_tween.kill()


func is_active() -> bool:
	return _active


func picked_groups() -> Array[int]:
	var groups: Array[int] = []
	for g: int in _picked.keys():
		groups.append(g)
	groups.sort()
	return groups


func locked_groups() -> Dictionary:
	return _locked.duplicate()


## Feed input here while picking. Returns true if it was used.
func handle_input(event: InputEvent) -> bool:
	if not _active or not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return false
	if event is InputEventMouseMotion:
		if _press_time >= 0.0 and (event as InputEventMouseMotion).position.distance_to(_press_pos) > tap_slop:
			_press_time = -1.0  # became a drag
		return false
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return false
	if mb.pressed:
		_press_group = _group_at(mb.position)
		if _press_group < 0:
			return false
		_press_pos = mb.position
		_press_time = 0.0
		_long_fired = false
		return true
	# Released: a tap, unless it was a long press (already handled) or a drag.
	var was_tap: bool = _press_time >= 0.0 and not _long_fired
	_press_time = -1.0
	if was_tap and _press_group >= 0:
		_toggle_picked(_press_group)
		return true
	return false


func _process(delta: float) -> void:
	if not _active or _press_time < 0.0 or _long_fired:
		return
	_press_time += delta
	if _press_time >= long_press_time:
		_long_fired = true
		_toggle_locked(_press_group)


func _toggle_picked(group: int) -> void:
	if _picked.has(group):
		_picked.erase(group)
	else:
		_picked[group] = true
	_refresh()


## Locking also picks the die; unlocking leaves it picked for this throw
## (tap to put it back).
func _toggle_locked(group: int) -> void:
	if _locked.has(group):
		_locked.erase(group)
	else:
		_locked[group] = true
		_picked[group] = true
	_refresh()


## Which entry's die is under `screen_pos` (nearest centre within
## tap_radius), or -1.
func _group_at(screen_pos: Vector2) -> int:
	var best: int = -1
	var best_dist: float = tap_radius
	for d: Die in _roller.get_dice():
		if _camera.is_position_behind(d.global_position):
			continue
		var dist: float = _camera.unproject_position(d.global_position).distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best = d.group_index
	return best


## Places every die neatly in a grid in the middle of the table, lying flat.
func _layout() -> void:
	var dice: Array[Die] = _roller.get_dice()
	var count: int = dice.size()
	var max_cols: int = max_columns
	for d: Die in dice:
		if d.name.begins_with("D100"):
			# Even rows, so each d100's two dice stay side by side.
			max_cols = max_columns - max_columns % 2
			break
	var columns: int = mini(count, max_cols)
	var rows: int = ceili(float(count) / columns)
	for i: int in count:
		var d: Die = dice[i]
		var row: int = int(i / float(columns))
		var col: int = i % columns
		var in_row: int = mini(columns, count - row * columns)
		var basis: Basis = d.resting_basis()
		var local: Vector3 = Vector3(
				(col - (in_row - 1) * 0.5) * spacing * DiceFactory.SCALE,
				d.rest_height(basis),
				(row - (rows - 1) * 0.5) * spacing * DiceFactory.SCALE)
		d.freeze = true
		_home[d] = Transform3D(_roller.global_basis * basis, _roller.to_global(local))
		var label: String = _roller.get_spec(d.group_index).get("label", "")
		if not label.is_empty() and _first_die_of_group(d):
			_tags.append(_make_tag(label))
	_tween = null


## Moves dice to show picked (lifted, bright) / not picked (on the table,
## dimmed), and shows a ring under locked ones.
func _refresh() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var tag_index: int = 0
	for d: Die in _roller.get_dice():
		var picked: bool = _picked.has(d.group_index)
		var target: Transform3D = _home[d]
		if picked:
			target.origin += Vector3.UP * lift * DiceFactory.SCALE
		_tween.tween_property(d, "global_transform", target, 0.18)
		d.set_dimmed(not picked)
		if _first_die_of_group(d):
			_update_ring(d, _locked.has(d.group_index))
			var label: String = _roller.get_spec(d.group_index).get("label", "")
			if not label.is_empty():
				# Just beyond the die on screen (the camera looks almost
				# straight down, so "above" would sit on top of it).
				var centre: Vector3 = _group_centre(d.group_index) + (target.origin - _home[d].origin)
				_tags[tag_index].global_position = centre + Vector3(0.0, 0.8, -1.0) * DiceFactory.SCALE
				_tags[tag_index].modulate.a = 1.0 if picked else 0.6
				tag_index += 1
	selection_changed.emit(_picked.size())


func _update_ring(d: Die, show_ring: bool) -> void:
	var g: int = d.group_index
	if not show_ring:
		if _rings.has(g):
			_rings[g].queue_free()
			_rings.erase(g)
		return
	if not _rings.has(g):
		var ring: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.78 * DiceFactory.SCALE
		torus.outer_radius = 0.92 * DiceFactory.SCALE
		ring.mesh = torus
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = UITheme.ACCENT
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		_rings[g] = ring
	# One ring around the whole entry: a circle for a single die, an oval
	# stretched around both dice of a d100.
	var members: Array[Vector3] = []
	for other: Die in _roller.get_dice():
		if other.group_index == g:
			members.append((_home[other] as Transform3D).origin)
	var centre: Vector3 = _group_centre(g)
	var ring_basis: Basis = Basis.IDENTITY
	if members.size() > 1:
		var along: Vector3 = Vector3(members[-1].x - members[0].x, 0.0, members[-1].z - members[0].z)
		var outer: float = 0.92 * DiceFactory.SCALE
		var stretch: float = (outer + along.length() * 0.5) / outer
		var x_axis: Vector3 = along.normalized()
		ring_basis = Basis(x_axis * stretch, Vector3.UP, x_axis.cross(Vector3.UP))
	_rings[g].global_transform = Transform3D(ring_basis,
			Vector3(centre.x, _roller.global_position.y + 0.03, centre.z))


## Middle of an entry's dice in the layout (its two dice for a d100).
func _group_centre(group: int) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var n: int = 0
	for d: Die in _roller.get_dice():
		if d.group_index == group:
			sum += (_home[d] as Transform3D).origin
			n += 1
	return sum / maxi(n, 1)


## A floating name above a labelled die (always faces the camera).
func _make_tag(text: String) -> Label3D:
	var tag: Label3D = Label3D.new()
	tag.text = text
	tag.font_size = 64
	tag.pixel_size = 0.005
	tag.outline_size = 16
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tag)
	return tag


func _first_die_of_group(d: Die) -> bool:
	for other: Die in _roller.get_dice():
		if other.group_index == d.group_index:
			return other == d
	return false
