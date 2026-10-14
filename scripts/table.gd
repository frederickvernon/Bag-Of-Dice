class_name Table
extends StaticBody3D
## Flat table with invisible walls and ceiling, built in code.
## The playing surface is the rectangle size.x by size.y, centred on the
## origin, with its top at y = 0. A low wooden rim is drawn along the walls;
## the collision walls themselves are much taller but invisible.

## Keep in step with DiceRoller.table_size.
@export var size: Vector2 = Vector2(9.0, 15.0)
@export var wall_height: float = 8.0
@export var thickness: float = 1.0
@export var felt_color: Color = Color(0.09, 0.32, 0.2)
@export var rim_color: Color = Color(0.36, 0.22, 0.12)
@export var rim_width: float = 0.5
@export var rim_height: float = 0.6


func _ready() -> void:
	var phys: PhysicsMaterial = PhysicsMaterial.new()
	# Felt is grippy: high friction makes dice catch and tumble rather than
	# skate across the surface.
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
	_add_mesh(Vector3(size.x + 2.0 * rim_width, 0.2, size.y + 2.0 * rim_width),
			Vector3(0.0, -0.1, 0.0), _felt_material())
	# Wooden rim, drawn inside the space of the invisible walls. The grain
	# runs along each piece's length.
	var rw: float = rim_width
	var rh: float = rim_height
	var outer_x: float = size.x + 2.0 * rw
	var wood_along_z: StandardMaterial3D = _wood_material(Vector3(1.5, 1.5, 0.12))
	var wood_along_x: StandardMaterial3D = _wood_material(Vector3(0.12, 1.5, 1.5))
	_add_mesh(Vector3(rw, rh, size.y), Vector3(-(size.x + rw) * 0.5, rh * 0.5, 0.0), wood_along_z)
	_add_mesh(Vector3(rw, rh, size.y), Vector3((size.x + rw) * 0.5, rh * 0.5, 0.0), wood_along_z)
	_add_mesh(Vector3(outer_x, rh, rw), Vector3(0.0, rh * 0.5, -(size.y + rw) * 0.5), wood_along_x)
	_add_mesh(Vector3(outer_x, rh, rw), Vector3(0.0, rh * 0.5, (size.y + rw) * 0.5), wood_along_x)


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
	# Project the texture from all three sides, so it isn't stretched oddly
	# across the box faces.
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
