class_name Vegetation
extends Node3D
## Grass, trees, bushes and rocks, drawn with MultiMeshes.

const GRASS_CHUNK := 16.0
const BARK := Color(0.36, 0.25, 0.16)
const BARK_LIGHT := Color(0.52, 0.40, 0.27)

var terrain: Terrain
var grass_material: ShaderMaterial
var density := 1.0

var _grass_mesh: ArrayMesh
var _grass_root: Node3D
var _foliage_mat: ShaderMaterial
var _bark_mat: ShaderMaterial
var _rock_mat: StandardMaterial3D
var _obstacles: Array[Vector3] = [] # (x, z, radius)


func _ready() -> void:
	var detail := Fx.noise_texture(0.04, 256)
	grass_material = ShaderMaterial.new()
	grass_material.shader = load("res://shaders/grass.gdshader")
	_foliage_mat = ShaderMaterial.new()
	_foliage_mat.shader = load("res://shaders/foliage.gdshader")
	_foliage_mat.set_shader_parameter("detail", detail)
	_bark_mat = ShaderMaterial.new()
	_bark_mat.shader = load("res://shaders/bark.gdshader")
	_bark_mat.set_shader_parameter("detail", detail)
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.vertex_color_use_as_albedo = true
	_rock_mat.roughness = 0.9
	_grass_mesh = _build_grass_mesh()
	_build_trees()
	build_grass()


## True when nothing solid (trunk, rock, bush) is within margin of q.
func is_clear(q: Vector2, margin: float) -> bool:
	for o in _obstacles:
		if Vector2(o.x, o.y).distance_to(q) < o.z + margin:
			return false
	return true


func set_density(d: float) -> void:
	if is_equal_approx(d, density) and _grass_root:
		return
	density = d
	build_grass()


func build_grass() -> void:
	if _grass_root:
		_grass_root.queue_free()
	_grass_root = Node3D.new()
	add_child(_grass_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var half := int(ceilf((Terrain.MEADOW_RADIUS + 12.0) / GRASS_CHUNK))
	var per_chunk := int(GRASS_CHUNK * GRASS_CHUNK * 0.7 * density)
	for cx in range(-half, half):
		for cz in range(-half, half):
			var origin := Vector2(cx, cz) * GRASS_CHUNK
			var center := origin + Vector2.ONE * GRASS_CHUNK * 0.5
			if center.length() > Terrain.MEADOW_RADIUS + 24.0:
				continue
			var xfs: Array[Transform3D] = []
			var dry := PackedFloat32Array()
			for i in per_chunk:
				var q := origin + Vector2(rng.randf(), rng.randf()) * GRASS_CHUNK
				var r := q.length()
				if r < 3.0 or r > Terrain.MEADOW_RADIUS + 12.0:
					continue
				if q.distance_to(Terrain.POND_CENTER) < Terrain.POND_RADIUS:
					continue
				var patch := terrain.patch_noise(q)
				if rng.randf() > 0.45 + patch * 0.8:
					continue
				var s := rng.randf_range(0.7, 1.15) * lerpf(0.75, 1.5, patch)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
				xfs.append(Transform3D(basis, Vector3(q.x, terrain.height_at(q.x, q.y) - 0.03, q.y)))
				dry.append(clampf(0.75 - patch + rng.randf_range(-0.15, 0.15), 0.0, 0.7))
			if not xfs.is_empty():
				_grass_chunk(Vector3(center.x, 0.0, center.y), xfs, dry, 70.0 if density > 0.75 else 45.0)
	# Tall reeds around the pond.
	var reeds: Array[Transform3D] = []
	var reed_dry := PackedFloat32Array()
	for i in int(220 * density):
		var q := Terrain.POND_CENTER + Vector2.from_angle(rng.randf() * TAU) * Terrain.POND_RADIUS * rng.randf_range(0.72, 1.05)
		var y := terrain.height_at(q.x, q.y)
		if y < -0.5:
			continue
		var s := rng.randf_range(0.8, 1.2)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 0.7, s * rng.randf_range(2.2, 3.2), s * 0.7))
		reeds.append(Transform3D(basis, Vector3(q.x, y - 0.05, q.y)))
		reed_dry.append(0.0)
	var pc := Vector3(Terrain.POND_CENTER.x, 0.0, Terrain.POND_CENTER.y)
	_grass_chunk(pc, reeds, reed_dry, 120.0)


func _grass_chunk(center: Vector3, xfs: Array[Transform3D], dry: PackedFloat32Array, range_end: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _grass_mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		var xf := xfs[i]
		xf.origin -= center
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, Color(dry[i], 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = center
	mmi.material_override = grass_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = range_end
	mmi.visibility_range_end_margin = 6.0
	_grass_root.add_child(mmi)


func _build_grass_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for b in 9:
		var root := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
		var h := rng.randf_range(0.45, 1.0)
		var w := rng.randf_range(0.035, 0.06)
		var lean := Vector3.RIGHT.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(0.08, 0.3) * h
		var side := Vector3.RIGHT.rotated(Vector3.UP, rng.randf() * TAU)
		var normal := (side.cross(Vector3.UP) * 0.4 + Vector3.UP).normalized()
		var tip := Color(0.50, 0.74, 0.24).lerp(Color(0.74, 0.76, 0.32), rng.randf() * 0.5)
		var pts := PackedVector3Array()
		var nrm := PackedVector3Array()
		var col := PackedColorArray()
		var uvs := PackedVector2Array()
		for r in 4:
			var t := r / 3.0
			var center := root + lean * t * t + Vector3.UP * h * t
			var half := w * (1.0 - t * 0.85)
			for c in 2:
				var u := float(c) * 2.0 - 1.0
				pts.append(center + side * half * u)
				nrm.append(normal)
				col.append(MeshKit.lin(Color(0.13, 0.25, 0.06).lerp(tip, t)))
				uvs.append(Vector2(u * 0.5 + 0.5, t))
		MeshKit.grid(st, pts, nrm, col, 4, 2, uvs)
	return st.commit()


# --- trees, bushes and rocks -------------------------------------------------

func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var oaks: Array[ArrayMesh] = [_broadleaf(11), _broadleaf(23), _broadleaf(37)]
	var pines: Array[ArrayMesh] = [_pine(5), _pine(9)]
	var bushes: Array[ArrayMesh] = [_bush(3), _bush(8)]
	var rocks: Array[ArrayMesh] = [_rock(4), _rock(6)]
	var place := {}
	var trunk := 0.6

	# A few big shade trees out in the meadow.
	var count := 0
	var tries := 0
	while count < 9 and tries < 400:
		tries += 1
		var q := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(28.0, 115.0)
		if q.distance_to(Terrain.POND_CENTER) < Terrain.POND_RADIUS * 1.7 or not is_clear(q, 24.0):
			continue
		_place(place, oaks[rng.randi() % oaks.size()], q, rng.randf_range(0.95, 1.3), rng, trunk, true)
		count += 1
	# Woodland ringing the meadow.
	for i in 90:
		var q := Vector2.from_angle(TAU * i / 90.0 + rng.randf_range(-0.03, 0.03)) * rng.randf_range(128.0, 178.0)
		if not is_clear(q, 3.5):
			continue
		if q.length() > 152.0 or rng.randf() < 0.3:
			_place(place, pines[rng.randi() % pines.size()], q, rng.randf_range(0.9, 1.4), rng, trunk * 0.7, true)
		else:
			_place(place, oaks[rng.randi() % oaks.size()], q, rng.randf_range(0.9, 1.35), rng, trunk, true)
	# Pines on the hills beyond.
	for i in 220:
		var q := Vector2(rng.randf_range(-232.0, 232.0), rng.randf_range(-232.0, 232.0))
		if q.length() < 172.0 or not is_clear(q, 3.0):
			continue
		_place(place, pines[rng.randi() % pines.size()], q, rng.randf_range(1.0, 1.7), rng, trunk * 0.7, false)
	# Bushes and rocks scattered through the meadow.
	for i in 50:
		var q := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(14.0, 150.0)
		if q.distance_to(Terrain.POND_CENTER) < Terrain.POND_RADIUS * 1.3 or not is_clear(q, 2.5):
			continue
		_place(place, bushes[rng.randi() % bushes.size()], q, rng.randf_range(0.8, 1.5), rng, 1.2, false)
	for i in 30:
		var q := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, 150.0)
		if i < 7:
			q = Terrain.POND_CENTER + Vector2.from_angle(rng.randf() * TAU) * Terrain.POND_RADIUS * rng.randf_range(0.9, 1.2)
		if not is_clear(q, 2.0):
			continue
		_place(place, rocks[rng.randi() % rocks.size()], q, rng.randf_range(0.6, 1.6), rng, 1.0, true, true)

	for mesh in place:
		var xfs: Array = place[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func _place(place: Dictionary, mesh: ArrayMesh, q: Vector2, s: float, rng: RandomNumberGenerator,
		radius: float, collide: bool, round_shape := false) -> void:
	var y := terrain.height_at(q.x, q.y) - 0.25 * s
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(q.x, y, q.y))
	if not place.has(mesh):
		place[mesh] = []
	place[mesh].append(xf)
	_obstacles.append(Vector3(q.x, q.y, radius * s))
	if not collide or q.length() > Terrain.WORLD_RADIUS + 10.0:
		return
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	if round_shape:
		var sphere := SphereShape3D.new()
		sphere.radius = radius * s
		shape.shape = sphere
	else:
		var cyl := CylinderShape3D.new()
		cyl.radius = radius * s
		cyl.height = 9.0 * s
		shape.shape = cyl
		shape.position.y = cyl.height * 0.5
	body.add_child(shape)
	body.position = Vector3(q.x, y, q.y)
	add_child(body)


func _finish(bark: SurfaceTool, leaves: SurfaceTool, leaf_mat: Material) -> ArrayMesh:
	var mesh := bark.commit()
	leaves.commit(mesh)
	mesh.surface_set_material(0, _bark_mat)
	mesh.surface_set_material(1, leaf_mat)
	return mesh


func _broadleaf(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := MeshKit.begin()
	var leaves := MeshKit.begin()
	var h := rng.randf_range(9.0, 12.0)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var drift := Vector3.ZERO
	for i in 9:
		var t := i / 8.0
		drift += Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3)) * t
		path.append(Vector3(drift.x, h * t, drift.z))
		radii.append(lerpf(0.7, 0.28, t) + 0.5 * pow(1.0 - t, 8.0))
	MeshKit.tube(bark, path, radii, 10, MeshKit.lin(BARK), MeshKit.lin(BARK_LIGHT))
	var crowns: Array[Vector3] = [path[8] + Vector3(0.0, 1.2, 0.0)]
	var branches := rng.randi_range(4, 6)
	for b in branches:
		var start := path[rng.randi_range(4, 6)]
		var a := TAU * b / branches + rng.randf_range(-0.4, 0.4)
		var dir := Vector3(cos(a), rng.randf_range(0.45, 0.9), sin(a)).normalized()
		var length := rng.randf_range(3.2, 5.0)
		var mid := start + dir * length * 0.5 + Vector3(0.0, 0.4, 0.0)
		var tip := start + dir * length
		MeshKit.tube(bark, PackedVector3Array([start, mid, tip]), PackedFloat32Array([0.26, 0.17, 0.09]), 6,
			MeshKit.lin(BARK), MeshKit.lin(BARK_LIGHT))
		crowns.append(tip + Vector3(0.0, 0.6, 0.0))
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.45
	for i in crowns.size():
		var r := rng.randf_range(2.6, 3.6) * (1.3 if i == 0 else 1.0)
		var tint := rng.randf_range(-0.05, 0.05)
		MeshKit.ellipsoid(leaves, Transform3D(Basis(), crowns[i]), Vector3(r, r * 0.78, r), 7, 12,
			MeshKit.lin(Color(0.44 + tint, 0.64 + tint, 0.2)), MeshKit.lin(Color(0.1, 0.24, 0.07)), noise, r * 0.32)
	return _finish(bark, leaves, _foliage_mat)


func _pine(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := MeshKit.begin()
	var leaves := MeshKit.begin()
	var h := rng.randf_range(11.0, 15.0)
	MeshKit.tube(bark, PackedVector3Array([Vector3.ZERO, Vector3(0, h * 0.5, 0), Vector3(0, h, 0)]),
		PackedFloat32Array([0.5, 0.3, 0.06]), 8, MeshKit.lin(BARK), MeshKit.lin(BARK_LIGHT))
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.9
	var layers := 6
	for l in layers:
		var t := float(l) / (layers - 1)
		var y := h * 0.2 + t * h * 0.72
		MeshKit.cone(leaves, Vector3(0, y, 0), lerpf(3.6, 1.0, t), lerpf(3.4, 2.4, t), 14,
			MeshKit.lin(Color(0.10, 0.25, 0.12)), MeshKit.lin(Color(0.24, 0.42, 0.2)), noise, 0.6)
	return _finish(bark, leaves, _foliage_mat)


func _bush(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := MeshKit.begin()
	var leaves := MeshKit.begin()
	MeshKit.tube(bark, PackedVector3Array([Vector3.ZERO, Vector3(0, 0.6, 0)]), PackedFloat32Array([0.15, 0.1]), 5,
		MeshKit.lin(BARK), MeshKit.lin(BARK))
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.8
	for i in rng.randi_range(3, 5):
		var c := Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.7, 1.2), rng.randf_range(-0.9, 0.9))
		var r := rng.randf_range(0.9, 1.4)
		MeshKit.ellipsoid(leaves, Transform3D(Basis(), c), Vector3(r, r * 0.8, r), 6, 10,
			MeshKit.lin(Color(0.36, 0.56, 0.18)), MeshKit.lin(Color(0.08, 0.2, 0.06)), noise, r * 0.3)
	return _finish(bark, leaves, _foliage_mat)


func _rock(seed_value: int) -> ArrayMesh:
	var st := MeshKit.begin()
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.9
	MeshKit.ellipsoid(st, Transform3D(Basis(), Vector3(0, 0.2, 0)), Vector3(1.3, 0.8, 1.1), 7, 10,
		MeshKit.lin(Color(0.48, 0.52, 0.36)), MeshKit.lin(Color(0.38, 0.36, 0.34)), noise, 0.35)
	var mesh := st.commit()
	mesh.surface_set_material(0, _rock_mat)
	return mesh
