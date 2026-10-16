class_name DiceFactory
extends RefCounted
## Builds dice in code: collision shape, mesh, face labels and the
## direction→value table the Die reads its result from.
##
## Every face plane is the same distance from the centre, so the centre of
## mass sits at the origin and no face is favoured.

const TYPES: Array[String] = ["d4", "d6", "d8", "d10", "d12", "d20", "d100"]
## Face styles per type; the first is the default (the common real-world look).
##   d6:  "pips" (dots, like a standard d6) or "numbers"
##   d10: "zero" (0–9, the 0 counting as 10, like most real d10s) or "ten" (1–10)
const STYLES: Dictionary = {
	"d6": ["pips", "numbers"],
	"d10": ["zero", "ten"],
}
const STYLE_NAMES: Dictionary = { "pips": "pips", "numbers": "numbers", "zero": "0–9", "ten": "1–10" }
## Standard d6 pip positions in pip-spacing units (2, 3 and 6 run corner to corner).
const PIP_LAYOUT: Dictionary = {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	6: [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)],
}
const DEFAULT_COLOR: Color = Color(0.95, 0.93, 0.85)
const PHI: float = 1.6180339887  # golden ratio, used by the d12 and d20

## Overall die size; 1.0 = a d6 with 1-unit edges. Smaller dice have more room to tumble.
const SCALE: float = 0.8
## Centre-to-furthest-corner distance per type, at SCALE 1.0.
const RADIUS: Dictionary = {
	"d4": 1.1, "d6": 0.866, "d8": 0.9, "d10": 0.88, "d12": 0.92, "d20": 0.98,
}
## Edge rounding as a fraction of the die's radius. Visual only; collision keeps sharp edges.
const BEVEL_FRACTION: float = 0.07
## Bold version of Godot's built-in font, shared by every face label.
static var _label_font: FontVariation
## Number shapes already built, by "text|height" (dice of one type share them).
static var _glyph_cache: Dictionary = {}
## Tilt of a d10 face from horizontal-ish; gives the classic kite shape.
const D10_FACE_ELEVATION_DEG: float = 42.0


## Dice for one set entry: usually one, but a d100 is two d10s (tens, then units).
## `style` is a STYLES entry; "" means the default.
static func create(type: String, body_color: Color = DEFAULT_COLOR, style: String = "") -> Array[Die]:
	if not is_valid_style(type, style):
		style = default_style(type)
	var ink: Color = Color.BLACK if body_color.get_luminance() > 0.5 else Color.WHITE
	var dice: Array[Die] = []
	match type:
		"d4":
			dice.append(_build_d4(body_color, ink))
		"d6":
			dice.append(_build_standard("d6", _d6_normals(), _range(1, 6), body_color, ink, false, style))
		"d8":
			dice.append(_build_standard("d8", _d8_normals(), _range(1, 8), body_color, ink))
		"d10":
			dice.append(_build_standard("d10", _d10_normals(), _range(1, 10), body_color, ink, false, style))
		"d12":
			dice.append(_build_standard("d12", _d12_normals(), _range(1, 12), body_color, ink))
		"d20":
			dice.append(_build_standard("d20", _d20_normals(), _range(1, 20), body_color, ink))
		"d100":
			var tens: Array[int] = []
			for i: int in 10:
				tens.append(i * 10)
			var tens_die: Die = _build_standard("d10", _d10_normals(), tens, body_color, ink, true)
			tens_die.name = "D100Tens"
			var units_die: Die = _build_standard("d10", _d10_normals(), _range(0, 9), body_color, ink)
			units_die.name = "D100Units"
			dice.append(tens_die)
			dice.append(units_die)
		_:
			push_error("Unknown die type: %s" % type)
	return dice


## Physical dice per entry of `type` (a d100 is rolled as two d10s).
static func dice_count(type: String) -> int:
	return 2 if type == "d100" else 1


static func default_style(type: String) -> String:
	return STYLES[type][0] if STYLES.has(type) else ""


static func is_valid_style(type: String, style: String) -> bool:
	return STYLES.has(type) and (STYLES[type] as Array).has(style)


## Every die choice for pickers: one per type, or one per style, e.g.
## { "type": "d6", "style": "pips", "label": "d6 · pips" }.
static func variants() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for type: String in TYPES:
		if STYLES.has(type):
			for style: String in STYLES[type]:
				list.append({ "type": type, "style": style, "label": "%s · %s" % [type, STYLE_NAMES[style]] })
		else:
			list.append({ "type": type, "style": "", "label": type })
	return list


# Face normals

static func _d6_normals() -> Array[Vector3]:
	return [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]


static func _d8_normals() -> Array[Vector3]:
	var n: Array[Vector3] = []
	for x: float in [1.0, -1.0]:
		for y: float in [1.0, -1.0]:
			for z: float in [1.0, -1.0]:
				n.append(Vector3(x, y, z))
	return n


## Pentagonal trapezohedron: five faces up, five down, the lower ring rotated 36°
## so every face is a kite.
static func _d10_normals() -> Array[Vector3]:
	var n: Array[Vector3] = []
	var e: float = deg_to_rad(D10_FACE_ELEVATION_DEG)
	for k: int in 5:
		var a: float = deg_to_rad(36.0 + 72.0 * k)
		n.append(Vector3(cos(e) * cos(a), sin(e), cos(e) * sin(a)))
	for k: int in 5:
		var a: float = deg_to_rad(72.0 * k)
		n.append(Vector3(cos(e) * cos(a), -sin(e), cos(e) * sin(a)))
	return n


## Dodecahedron faces point at the corners of an icosahedron.
static func _d12_normals() -> Array[Vector3]:
	var n: Array[Vector3] = []
	for a: float in [1.0, -1.0]:
		for b: float in [PHI, -PHI]:
			n.append(Vector3(0.0, a, b))
			n.append(Vector3(a, b, 0.0))
			n.append(Vector3(b, 0.0, a))
	return n


## Icosahedron faces point at the corners of a dodecahedron.
static func _d20_normals() -> Array[Vector3]:
	var n: Array[Vector3] = _d8_normals()
	for a: float in [1.0 / PHI, -1.0 / PHI]:
		for b: float in [PHI, -PHI]:
			n.append(Vector3(0.0, a, b))
			n.append(Vector3(a, b, 0.0))
			n.append(Vector3(b, 0.0, a))
	return n


# Builders

## Any die read from its top face. Opposite faces pair up the standard way (1↔N, 2↔N-1, ...).
static func _build_standard(type: String, normals: Array[Vector3], values: Array[int],
		body_color: Color, ink: Color, two_digit: bool = false, style: String = "") -> Die:
	var solid: Dictionary = _make_solid(normals, RADIUS[type] * SCALE)
	var die: Die = _new_die(type, solid, body_color)
	var face_values: Array[int] = _assign_opposite_values(normals, values)
	var ink_tool: SurfaceTool = _begin_ink()

	for i: int in normals.size():
		var normal: Vector3 = normals[i].normalized()
		var value: int = face_values[i]

		var text: String = ("%02d" % value) if two_digit else str(value)
		if style == "zero" and value == 10:
			text = "0"  # still counts as 10
		# Mark 6 and 9 so they can't be confused when upside down.
		if text == "6" or text == "9":
			if normals.size() > 8:
				text += "."
		var poly: PackedVector3Array = solid["faces"][i]
		var centre: Vector3 = _centroid(poly)
		var room: float = _inradius(poly, centre) - solid["bevel"]
		var digits: int = text.replace(".", "").length()
		var height: float = room * (1.45 if digits > 1 else 1.9)
		# Number top points at the furthest corner (the d10 kite tip). The d6 uses an
		# edge instead, so a presented d6 sits square rather than as a diamond.
		var up: Vector3 = _furthest(poly, centre) - centre
		if type == "d6":
			up = (poly[0] + poly[1]) * 0.5 - centre
		if style == "pips":
			_add_pips(ink_tool, value, centre, normal, up, poly[0].distance_to(poly[1]))
		else:
			_add_text(ink_tool, text, centre, normal, up, height)
		die.faces.append({
			"direction": normal, "value": value,
			"show_normal": normal, "show_up": _flatten(up, normal),
		})
	_attach_ink(die, ink_tool, ink)
	return die


## The d4 is read from its top corner. Each face prints every corner's value next
## to that corner, so the top value reads upright on all three visible faces.
static func _build_d4(body_color: Color, ink: Color) -> Die:
	var corners: Array[Vector3] = [
		Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1),
	]
	var normals: Array[Vector3] = []
	for c: Vector3 in corners:
		normals.append(-c)  # the face opposite each corner
	var solid: Dictionary = _make_solid(normals, RADIUS["d4"] * SCALE)
	var die: Die = _new_die("d4", solid, body_color)
	for i: int in corners.size():
		# Present corner i on any face touching it, with that corner at the top.
		var show_face: int = (i + 1) % corners.size()
		var show_normal: Vector3 = normals[show_face].normalized()
		var to_corner: Vector3 = corners[i] * RADIUS["d4"] * SCALE / corners[i].length() \
				- _centroid(solid["faces"][show_face])
		die.faces.append({
			"direction": corners[i].normalized(), "value": i + 1,
			"show_normal": show_normal, "show_up": _flatten(to_corner, show_normal),
		})

	var ink_tool: SurfaceTool = _begin_ink()
	for f: int in normals.size():
		var poly: PackedVector3Array = solid["faces"][f]
		var centre: Vector3 = _centroid(poly)
		var height: float = (_inradius(poly, centre) - solid["bevel"]) * 0.85
		for v: Vector3 in poly:
			var value: int = _closest_index(corners, v) + 1
			var pos: Vector3 = centre + (v - centre) * 0.55
			_add_text(ink_tool, str(value), pos, normals[f].normalized(), v - centre, height)
	_attach_ink(die, ink_tool, ink)
	return die


static func _new_die(type: String, solid: Dictionary, body_color: Color) -> Die:
	var die: Die = Die.new()
	die.name = type.to_upper()
	die.die_type = type
	die.mass = 1.0
	# Code moves the frozen die while presenting a result. Static mode makes those
	# moves teleports, so no momentum carries over when it is thrown again.
	die.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	# Continuous collision detection stops a fast die tunnelling through walls.
	die.continuous_cd = true

	var phys: PhysicsMaterial = PhysicsMaterial.new()
	phys.friction = 0.9
	phys.bounce = 0.15
	die.physics_material_override = phys

	var shape: CollisionShape3D = CollisionShape3D.new()
	var convex: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	convex.points = solid["vertices"]
	die.corners = solid["vertices"]
	shape.shape = convex
	die.add_child(shape)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Body"
	mesh_instance.mesh = _make_mesh(solid, body_color)
	die.add_child(mesh_instance)
	return die


# Geometry helpers

## Intersects one equidistant plane per normal, scaled so the furthest corner is `radius` out.
##   "vertices", "faces" (corners per face in `normals` order, CCW from outside),
##   "face_indices" (same, as indices), "normals" (unit), "bevel" (edge rounding width)
static func _make_solid(normals: Array[Vector3], radius: float) -> Dictionary:
	var planes: Array[Plane] = []
	for n: Vector3 in normals:
		planes.append(Plane(n.normalized(), 1.0))
	var raw: PackedVector3Array = Geometry3D.compute_convex_mesh_points(planes)

	# Several planes meet at each corner, so drop duplicate points.
	var verts: PackedVector3Array = PackedVector3Array()
	for p: Vector3 in raw:
		var dup: bool = false
		for q: Vector3 in verts:
			if p.distance_to(q) < 0.001:
				dup = true
				break
		if not dup:
			verts.append(p)

	var max_len: float = 0.0
	for v: Vector3 in verts:
		max_len = maxf(max_len, v.length())
	var s: float = radius / max_len

	var scaled: PackedVector3Array = PackedVector3Array()
	for v: Vector3 in verts:
		scaled.append(v * s)

	var faces: Array[PackedVector3Array] = []
	var face_indices: Array[PackedInt32Array] = []
	var face_normals: Array[Vector3] = []
	for plane: Plane in planes:
		var on_plane: Array[int] = []
		for i: int in verts.size():
			if absf(plane.distance_to(verts[i])) < 0.001:
				on_plane.append(i)
		var sorted: Array[int] = _sort_ccw(on_plane, scaled, plane.normal)
		var poly: PackedVector3Array = PackedVector3Array()
		for i: int in sorted:
			poly.append(scaled[i])
		faces.append(poly)
		face_indices.append(PackedInt32Array(sorted))
		face_normals.append(plane.normal)
	return {
		"vertices": scaled, "faces": faces, "face_indices": face_indices,
		"normals": face_normals, "bevel": radius * BEVEL_FRACTION,
	}


## Sorts point indices counter-clockwise around `normal` (as seen from outside).
static func _sort_ccw(indices: Array[int], points: PackedVector3Array, normal: Vector3) -> Array[int]:
	var centre: Vector3 = Vector3.ZERO
	for i: int in indices:
		centre += points[i]
	centre /= indices.size()
	var u: Vector3 = (points[indices[0]] - centre).normalized()
	var w: Vector3 = normal.cross(u)
	var angle: Callable = func(i: int) -> float:
		return atan2((points[i] - centre).dot(w), (points[i] - centre).dot(u))
	indices.sort_custom(func(a: int, b: int) -> bool: return angle.call(a) < angle.call(b))
	return indices


## Bevelled mesh: faces are inset and the gaps filled with strips shaded between
## neighbouring faces. That edge highlight is what makes the faces readable.
static func _make_mesh(solid: Dictionary, body_color: Color) -> ArrayMesh:
	var verts: PackedVector3Array = solid["vertices"]
	var face_indices: Array[PackedInt32Array] = solid["face_indices"]
	var normals: Array[Vector3] = solid["normals"]
	var bevel: float = solid["bevel"]

	# Inset corner of face f at vertex v, keyed by Vector2i(f, v).
	var inset: Dictionary = {}
	# Faces touching each vertex, and faces sharing each edge.
	var vertex_faces: Dictionary = {}
	var edge_faces: Dictionary = {}
	for f: int in face_indices.size():
		var poly: PackedInt32Array = face_indices[f]
		var centre: Vector3 = Vector3.ZERO
		for v: int in poly:
			centre += verts[v]
		centre /= poly.size()
		for k: int in poly.size():
			var v: int = poly[k]
			inset[Vector2i(f, v)] = verts[v] + (centre - verts[v]).normalized() * bevel
			vertex_faces.get_or_add(v, []).append(f)
			var w: int = poly[(k + 1) % poly.size()]
			edge_faces.get_or_add(Vector2i(mini(v, w), maxi(v, w)), []).append(f)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Flat faces.
	for f: int in face_indices.size():
		var poly: PackedInt32Array = face_indices[f]
		var n: Vector3 = normals[f]
		for k: int in range(1, poly.size() - 1):
			_tri(st, inset[Vector2i(f, poly[0])], inset[Vector2i(f, poly[k])],
					inset[Vector2i(f, poly[k + 1])], n, n, n)

	# Edge strips between the two faces sharing each edge.
	for edge: Vector2i in edge_faces:
		var fs: Array = edge_faces[edge]
		var f: int = fs[0]
		var g: int = fs[1]
		var af: Vector3 = inset[Vector2i(f, edge.x)]
		var bf: Vector3 = inset[Vector2i(f, edge.y)]
		var ag: Vector3 = inset[Vector2i(g, edge.x)]
		var bg: Vector3 = inset[Vector2i(g, edge.y)]
		_tri(st, af, bf, bg, normals[f], normals[f], normals[g])
		_tri(st, af, bg, ag, normals[f], normals[g], normals[g])

	# Corner caps where several faces meet.
	for v: int in vertex_faces:
		var around: Array = vertex_faces[v]
		var axis: Vector3 = verts[v].normalized()
		var u: Vector3 = (inset[Vector2i(around[0], v)] - verts[v]).normalized()
		var w: Vector3 = axis.cross(u)
		around.sort_custom(func(a: int, b: int) -> bool:
			var pa: Vector3 = inset[Vector2i(a, v)] - verts[v]
			var pb: Vector3 = inset[Vector2i(b, v)] - verts[v]
			return atan2(pa.dot(w), pa.dot(u)) < atan2(pb.dot(w), pb.dot(u)))
		for k: int in range(1, around.size() - 1):
			var f0: int = around[0]
			var f1: int = around[k]
			var f2: int = around[k + 1]
			_tri(st, inset[Vector2i(f0, v)], inset[Vector2i(f1, v)], inset[Vector2i(f2, v)],
					normals[f0], normals[f1], normals[f2])

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = body_color
	# Satin, not shiny: a face turned to the light would flash white and hide its pips.
	mat.roughness = 0.62
	mat.metallic_specular = 0.3
	# A thin glossy coat on top, like polished plastic.
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.25
	mat.clearcoat_roughness = 0.5
	st.set_material(mat)
	return st.commit()


## Adds one triangle, flipping it if needed so its front faces outward
## (Godot treats clockwise triangles as front-facing).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		var t: Vector3 = b
		b = c
		c = t
		var tn: Vector3 = nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


# Numbers
# Labels are flat TextMesh shapes merged into one extra mesh surface, so a die is
# two draw pieces however many faces it has. Much cheaper on phones.

static func _begin_ink() -> SurfaceTool:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Adds `text`, `height` tall, centred at `pos` on the face with `normal`,
## its top pointing along `up` (flattened onto the face).
static func _add_text(ink: SurfaceTool, text: String, pos: Vector3, normal: Vector3,
		up: Vector3, height: float) -> void:
	var arrays: Array = _glyphs(text, height)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var y: Vector3 = _flatten(up, normal)
	# Text is built facing +Z; point it out of the face, just above it to avoid z-fighting.
	var xform: Transform3D = Transform3D(Basis(y.cross(normal), y, normal), pos + normal * 0.002)
	ink.set_normal(normal)
	if indices.is_empty():
		for v: Vector3 in verts:
			ink.add_vertex(xform * v)
	else:
		for i: int in indices:
			ink.add_vertex(xform * verts[i])


## Adds `count` round pips to a square face of side `edge`, in the standard
## d6 layout, lined up with `up`.
static func _add_pips(ink: SurfaceTool, count: int, centre: Vector3, normal: Vector3,
		up: Vector3, edge: float) -> void:
	var y: Vector3 = _flatten(up, normal)
	var x: Vector3 = y.cross(normal)
	var spread: float = edge * 0.26
	var radius: float = edge * 0.09
	var segments: int = 24
	ink.set_normal(normal)
	for spot: Vector2 in PIP_LAYOUT[count]:
		var c: Vector3 = centre + (x * spot.x + y * spot.y) * spread + normal * 0.002
		for k: int in segments:
			var a0: float = TAU * k / segments
			var a1: float = TAU * (k + 1) / segments
			ink.add_vertex(c)
			ink.add_vertex(c + (x * cos(a0) + y * sin(a0)) * radius)
			ink.add_vertex(c + (x * cos(a1) + y * sin(a1)) * radius)


static func _glyphs(text: String, height: float) -> Array:
	var key: String = "%s|%.4f" % [text, height]
	if not _glyph_cache.has(key):
		var tm: TextMesh = TextMesh.new()
		tm.text = text
		# Plain built-in font: artificial bolding overlaps outlines, which TextMesh can't triangulate.
		tm.font = ThemeDB.fallback_font
		tm.font_size = 128
		tm.pixel_size = height / 128.0
		tm.depth = 0.0
		_glyph_cache[key] = tm.get_mesh_arrays()
	return _glyph_cache[key]


## Adds the numbers as a second surface of the die's mesh, in `color`.
static func _attach_ink(die: Die, ink: SurfaceTool, color: Color) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	ink.set_material(mat)
	var body: MeshInstance3D = die.get_node("Body")
	ink.commit(body.mesh as ArrayMesh)


## `v` with its component along `normal` removed, normalised.
static func _flatten(v: Vector3, normal: Vector3) -> Vector3:
	return (v - normal * v.dot(normal)).normalized()


static func _get_label_font() -> FontVariation:
	if _label_font == null:
		_label_font = FontVariation.new()
		_label_font.base_font = ThemeDB.fallback_font
		_label_font.variation_embolden = 0.9
	return _label_font


## Value per face; opposite faces take values from opposite ends of `values` (1↔6, 2↔5, 3↔4).
static func _assign_opposite_values(normals: Array[Vector3], values: Array[int]) -> Array[int]:
	var result: Array[int] = []
	result.resize(normals.size())
	result.fill(-1)
	var low: int = 0
	var high: int = values.size() - 1
	for i: int in normals.size():
		if result[i] != -1:
			continue
		var opposite: int = _closest_index(normals, -normals[i])
		result[i] = values[low]
		result[opposite] = values[high]
		low += 1
		high -= 1
	return result


static func _closest_index(dirs: Array[Vector3], target: Vector3) -> int:
	var best: int = 0
	var best_dot: float = -INF
	for i: int in dirs.size():
		var d: float = dirs[i].normalized().dot(target.normalized())
		if d > best_dot:
			best_dot = d
			best = i
	return best


static func _centroid(poly: PackedVector3Array) -> Vector3:
	var c: Vector3 = Vector3.ZERO
	for p: Vector3 in poly:
		c += p
	return c / poly.size()


## Shortest distance from `centre` to a face edge, i.e. the room a label has.
static func _inradius(poly: PackedVector3Array, centre: Vector3) -> float:
	var best: float = INF
	for i: int in poly.size():
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[(i + 1) % poly.size()]
		var closest: Vector3 = Geometry3D.get_closest_point_to_segment(centre, a, b)
		best = minf(best, centre.distance_to(closest))
	return best


static func _furthest(poly: PackedVector3Array, centre: Vector3) -> Vector3:
	var best: Vector3 = poly[0]
	for p: Vector3 in poly:
		if p.distance_to(centre) > best.distance_to(centre) + 0.0001:
			best = p
	return best


static func _range(from: int, to: int) -> Array[int]:
	var r: Array[int] = []
	for i: int in range(from, to + 1):
		r.append(i)
	return r
