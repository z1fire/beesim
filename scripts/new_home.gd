class_name NewHome
extends Node3D
## The great hollow oak at the edge of the meadow, where the swarm finds its new home.

const SPOT := Vector2(-80.0, 78.0)
const HOLE_Y := 4.2

var terrain: Terrain
var hole: Vector3 ## Just inside the hollow.
var front: Vector3 ## In front of the hollow.

var _beacon: MeshInstance3D


func _ready() -> void:
	position = Vector3(SPOT.x, terrain.height_at(SPOT.x, SPOT.y) - 0.4, SPOT.y)
	var to_hive := -Vector3(SPOT.x, 0.0, SPOT.y).normalized()
	rotation.y = atan2(to_hive.x, to_hive.z) # the hollow faces the hive

	var detail := Fx.noise_texture(0.04, 256, false, 5)
	var bark_mat := ShaderMaterial.new()
	bark_mat.shader = load("res://shaders/bark.gdshader")
	bark_mat.set_shader_parameter("detail", detail)
	var leaf_mat := ShaderMaterial.new()
	leaf_mat.shader = load("res://shaders/foliage.gdshader")
	leaf_mat.set_shader_parameter("detail", detail)

	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var bark := MeshKit.begin()
	var leaves := MeshKit.begin()
	var dark := MeshKit.lin(Color(0.3, 0.24, 0.17))
	var light := MeshKit.lin(Color(0.46, 0.4, 0.3))
	var h := 14.0
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 10:
		var t := i / 9.0
		path.append(Vector3(sin(t * 2.0) * 0.4, h * t, 0.0))
		radii.append(lerpf(2.1, 0.8, t) + 0.9 * pow(1.0 - t, 8.0))
	MeshKit.tube(bark, path, radii, 16, dark, light)
	# The hollow: a dark opening ringed by a lip of bark.
	var face := Basis(Vector3.RIGHT, PI * 0.5)
	MeshKit.disc(bark, Transform3D(face, Vector3(0.0, HOLE_Y, 1.76)), 0.62, 0.85, 18, 1,
		func(_t: float) -> Color: return MeshKit.lin(Color(0.04, 0.025, 0.015)))
	MeshKit.torus(bark, Transform3D(face * Basis.from_scale(Vector3(0.68, 1.0, 0.92)), Vector3(0.0, HOLE_Y, 1.68)),
		1.0, 0.2, 24, 8, func(_a: float, _b: float) -> Color: return light)
	var crowns: Array[Vector3] = [path[9] + Vector3(0, 1.5, 0)]
	for b in 6:
		var start := path[rng.randi_range(5, 7)]
		var a := TAU * b / 6.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), rng.randf_range(0.4, 0.8), sin(a)).normalized()
		var tip := start + dir * rng.randf_range(4.5, 6.5)
		MeshKit.tube(bark, PackedVector3Array([start, (start + tip) * 0.5 + Vector3.UP * 0.5, tip]),
			PackedFloat32Array([0.45, 0.3, 0.14]), 7, dark, light)
		crowns.append(tip + Vector3.UP * 0.8)
	var noise := FastNoiseLite.new()
	noise.seed = 404
	noise.frequency = 0.35
	for c in crowns:
		var r := rng.randf_range(3.6, 4.8)
		MeshKit.ellipsoid(leaves, Transform3D(Basis(), c), Vector3(r, r * 0.75, r), 7, 12,
			MeshKit.lin(Color(0.5, 0.64, 0.22)), MeshKit.lin(Color(0.14, 0.26, 0.08)), noise, r * 0.3)
	var mesh := bark.commit()
	leaves.commit(mesh)
	mesh.surface_set_material(0, bark_mat)
	mesh.surface_set_material(1, leaf_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.7
	cyl.height = h
	shape.shape = cyl
	shape.position.y = h * 0.5
	body.add_child(shape)
	add_child(body)

	hole = to_global(Vector3(0.0, HOLE_Y, 1.2))
	front = to_global(Vector3(0.0, HOLE_Y, 4.5))

	var beam := CylinderMesh.new()
	beam.top_radius = 0.9
	beam.bottom_radius = 0.6
	beam.height = 32.0
	beam.cap_top = false
	beam.cap_bottom = false
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = load("res://shaders/beacon.gdshader")
	beam_mat.set_shader_parameter("color", Color(0.6, 1.0, 0.55))
	_beacon = MeshInstance3D.new()
	_beacon.mesh = beam
	_beacon.material_override = beam_mat
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.position = Vector3(0, h + 18.0, 0)
	_beacon.visible = false
	add_child(_beacon)


func set_beacon(on: bool) -> void:
	_beacon.visible = on
