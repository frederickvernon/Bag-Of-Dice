class_name Table
extends StaticBody3D
## Flat table with invisible walls and ceiling, built in code. The play area is
## size.x by size.y, centred on the origin, top at y = 0. The visible rim is low;
## the collision walls are much taller.
## Along the near edge (+z), past a thin divider rail, is the drawer: a shallow felt
## tray where dice wait while they're out of play (sitting out, or already counted).
## Dice are placed there by code; the play area's invisible wall keeps thrown dice out.

## Keep in step with DiceRoller.table_size.
@export var size: Vector2 = Vector2(9.0, 15.0)
@export var wall_height: float = 8.0
@export var thickness: float = 1.0
@export var felt_color: Color = Color(0.09, 0.32, 0.2)
@export var rim_color: Color = Color(0.36, 0.22, 0.12)
@export var rim_width: float = 0.5
@export var rim_height: float = 0.6
## Drawer: inside depth, the divider rail between it and the play area, and how far
## its felt sits below the table's.
@export var drawer_depth: float = 2.7
@export var divider_width: float = 0.22
@export var drawer_drop: float = 0.06


func _ready() -> void:
	var phys: PhysicsMaterial = PhysicsMaterial.new()
	# High friction so dice catch and tumble rather than skate across the felt.
	phys.friction = 1.0
	phys.bounce = 0.1
	physics_material_override = phys

	var t: float = thickness
	var h: float = wall_height
	# Floor.
	_add_collision(Vector3(size.x + 2.0 * t, t, size.y + 2.0 * t), Vector3(0.0, -t * 0.5, 0.0))
	# Left / right walls.
	_add_collision(Vector3(t, h, size.y + 2.0 * t), Vector3(-(size.x + t) * 0.5, h * 0.5, 0.0))
	_add_collision(Vector3(t, h, size.y + 2.0 * t), Vector3((size.x + t) * 0.5, h * 0.5, 0.0))
	# Far / near walls.
	_add_collision(Vector3(size.x + 2.0 * t, h, t), Vector3(0.0, h * 0.5, -(size.y + t) * 0.5))
	_add_collision(Vector3(size.x + 2.0 * t, h, t), Vector3(0.0, h * 0.5, (size.y + t) * 0.5))
	# Ceiling.
	_add_collision(Vector3(size.x + 2.0 * t, t, size.y + 2.0 * t), Vector3(0.0, h + t * 0.5, 0.0))

	# Visible felt, slightly larger than the play area so it runs under the rim.
	var rw: float = rim_width
	var rh: float = rim_height
	var near: float = size.y * 0.5
	_add_mesh(Vector3(size.x + 2.0 * rw, 0.2, size.y + rw),
			Vector3(0.0, -0.1, -rw * 0.5), _felt_material())
	# The drawer's felt: a touch darker and a little lower, running under the divider.
	var drawer_felt: StandardMaterial3D = _felt_material()
	drawer_felt.albedo_color = Color(0.92, 0.92, 0.92)
	var drawer_len: float = divider_width + drawer_depth
	_add_mesh(Vector3(size.x, 0.2, drawer_len), Vector3(0.0, -drawer_drop - 0.1, near + drawer_len * 0.5), drawer_felt)
	# Wooden rim inside the invisible walls, grain running along each piece. The sides run
	# unbroken from the far end past the drawer, so table and drawer read as one tray.
	var outer_x: float = size.x + 2.0 * rw
	var back: float = drawer_back()
	var wood_along_z: StandardMaterial3D = _wood_material(Vector3(1.5, 1.5, 0.12))
	var wood_along_x: StandardMaterial3D = _wood_material(Vector3(0.12, 1.5, 1.5))
	var side_len: float = back + near
	for side: float in [-1.0, 1.0]:
		_add_mesh(Vector3(rw, rh, side_len), Vector3(side * (size.x + rw) * 0.5, rh * 0.5, (back - near) * 0.5), wood_along_z)
	_add_mesh(Vector3(outer_x, rh, rw), Vector3(0.0, rh * 0.5, -(size.y + rw) * 0.5), wood_along_x)
	_add_mesh(Vector3(outer_x, rh, rw), Vector3(0.0, rh * 0.5, back + rw * 0.5), wood_along_x)
	# The divider: a thin, low rail, like a cutlery-tray partition.
	_add_mesh(Vector3(size.x, rh * 0.45, divider_width), Vector3(0.0, rh * 0.225, near + divider_width * 0.5), wood_along_x)


## Local z where the drawer's felt starts (just past the divider).
func drawer_front() -> float:
	return size.y * 0.5 + divider_width


## Local z of the drawer's back edge (the inside of the outer rim).
func drawer_back() -> float:
	return drawer_front() + drawer_depth


## Local height of the drawer's felt.
func drawer_floor() -> float:
	return -drawer_drop


## Green felt with a subtle mottled texture so the surface doesn't look flat.
func _felt_material() -> StandardMaterial3D:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.frequency = 0.08
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, felt_color.darkened(0.12))
	ramp.set_color(1, felt_color.lightened(0.08))
	var tex: NoiseTexture2D = NoiseTexture2D.new()
	tex.noise = noise
	tex.color_ramp = ramp
	tex.seamless = true
	tex.width = 256
	tex.height = 256

	# Fine bumps so light catches the surface like woven cloth.
	var weave_noise: FastNoiseLite = FastNoiseLite.new()
	weave_noise.frequency = 0.35
	var weave: NoiseTexture2D = NoiseTexture2D.new()
	weave.noise = weave_noise
	weave.seamless = true
	weave.as_normal_map = true
	weave.bump_strength = 4.0
	weave.width = 256
	weave.height = 256

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.normal_enabled = true
	mat.normal_texture = weave
	mat.normal_scale = 0.6
	mat.roughness = 1.0
	mat.uv1_scale = Vector3(4.5, 4.5, 4.5)
	return mat


## Brown wood with streaky grain. `grain_scale` squashes the pattern along
## one axis (a small value there stretches the streaks along it).
func _wood_material(grain_scale: Vector3) -> StandardMaterial3D:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, rim_color.darkened(0.25))
	ramp.add_point(0.5, rim_color)
	ramp.set_color(ramp.get_point_count() - 1, rim_color.lightened(0.15))
	var tex: NoiseTexture2D = NoiseTexture2D.new()
	tex.noise = noise
	tex.color_ramp = ramp
	tex.seamless = true
	tex.width = 256
	tex.height = 256

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = tex
	# Triplanar so the grain isn't stretched across the box faces.
	mat.uv1_triplanar = true
	mat.uv1_scale = grain_scale
	mat.roughness = 0.55
	return mat


func _add_collision(box_size: Vector3, box_position: Vector3) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	shape.position = box_position
	add_child(shape)


func _add_mesh(box_size: Vector3, box_position: Vector3, mat: Material) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	mesh.material = mat
	mesh_instance.mesh = mesh
	mesh_instance.position = box_position
	add_child(mesh_instance)
