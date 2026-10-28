class_name Hive
extends Node3D
## The straw skep on a tree stump that the bee calls home.

const STRAW := Color(0.86, 0.66, 0.30)
const STRAW_DARK := Color(0.60, 0.42, 0.16)

var terrain: Terrain
var entrance := Vector3.ZERO ## Where bees deliver nectar.
var hole := Vector3.ZERO ## Fly into this to go inside.
var light: OmniLight3D


func _ready() -> void:
	position = Vector3(0.0, terrain.height_at(0.0, 0.0), 0.0)
	var st := MeshKit.begin()

	# Tree stump with growth rings on top.
	MeshKit.tube(st, PackedVector3Array([Vector3(0, -0.6, 0), Vector3(0, 0.4, 0), Vector3(0, 1.1, 0)]),
		PackedFloat32Array([1.65, 1.3, 1.25]), 20, MeshKit.lin(Color(0.30, 0.21, 0.13)), MeshKit.lin(Color(0.42, 0.30, 0.19)))
	MeshKit.disc(st, Transform3D(Basis(), Vector3(0, 1.1, 0)), 1.25, 1.25, 20, 8,
		func(t: float) -> Color:
			var ring := 0.5 + 0.5 * sin(t * 30.0)
			return MeshKit.lin(Color(0.78, 0.62, 0.42).lerp(Color(0.62, 0.46, 0.3), ring * 0.6).lerp(Color(0.4, 0.28, 0.17), smoothstep(0.85, 1.0, t))))

	# Skep: stacked coils of straw forming a dome.
	var coils := 11
	for i in coils:
		var t := float(i) / (coils - 1)
		var radius := 1.5 * sqrt(maxf(1.0 - pow(t * 0.97, 2.0), 0.0)) + 0.1
		var bright := 0.9 + 0.1 * sin(i * 2.3)
		MeshKit.torus(st, Transform3D(Basis(), Vector3(0, 1.27 + t * 2.2, 0)), radius, 0.19, 40, 8,
			func(a: float, b: float) -> Color:
				var twist := 0.5 + 0.5 * sin(a * 44.0 + b * 1.5)
				return MeshKit.lin(MeshKit.shade(STRAW.lerp(STRAW_DARK, twist * 0.55), bright)))
	MeshKit.ellipsoid(st, Transform3D(Basis(), Vector3(0, 3.55, 0)), Vector3(0.42, 0.3, 0.42), 5, 12,
		MeshKit.lin(STRAW), MeshKit.lin(STRAW_DARK))

	# Entrance hole and landing board.
	MeshKit.disc(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.2, 1.72)), 0.42, 0.34, 16, 1,
		func(_t: float) -> Color: return MeshKit.lin(Color(0.04, 0.025, 0.01)), PI, TAU)
	MeshKit.ellipsoid(st, Transform3D(Basis(), Vector3(0, 1.13, 1.7)), Vector3(0.7, 0.06, 0.35), 4, 12,
		MeshKit.lin(Color(0.6, 0.45, 0.28)), MeshKit.lin(Color(0.4, 0.28, 0.17)))

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)

	# Honey dripping down the stump.
	var honey := MeshKit.begin()
	for drip in [Vector3(-0.45, 0.95, 1.12), Vector3(0.3, 0.85, 1.16), Vector3(0.75, 0.98, 0.9)]:
		MeshKit.ellipsoid(honey, Transform3D(Basis(), drip), Vector3(0.09, 0.2, 0.09), 6, 10,
			MeshKit.lin(Color(1.0, 0.7, 0.12)), MeshKit.lin(Color(0.85, 0.45, 0.02)))
	MeshKit.ellipsoid(honey, Transform3D(Basis(), Vector3(0, 1.1, 1.1)), Vector3(0.5, 0.05, 0.22), 4, 12,
		MeshKit.lin(Color(1.0, 0.7, 0.12)), MeshKit.lin(Color(0.85, 0.45, 0.02)))
	var honey_mat := StandardMaterial3D.new()
	honey_mat.vertex_color_use_as_albedo = true
	honey_mat.roughness = 0.08
	honey_mat.emission_enabled = true
	honey_mat.emission = Color(0.35, 0.18, 0.0)
	honey.commit(mesh)
	mesh.surface_set_material(1, honey_mat)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	var body := StaticBody3D.new()
	add_child(body)
	var stump := CylinderShape3D.new()
	stump.radius = 1.35
	stump.height = 1.8
	_add_shape(body, stump, Vector3(0, 0.2, 0))
	var dome := SphereShape3D.new()
	dome.radius = 1.65
	_add_shape(body, dome, Vector3(0, 2.1, 0))

	entrance = global_position + Vector3(0.0, 1.6, 2.6)
	hole = global_position + Vector3(0.0, 1.25, 1.85)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3)
	light.omni_range = 7.0
	light.position = Vector3(0, 1.6, 2.4)
	add_child(light)

	_build_beacon()


func set_night(amount: float) -> void:
	light.light_energy = 0.2 + amount * 1.6
	light.visible = amount > 0.05


func _add_shape(body: StaticBody3D, shape: Shape3D, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


## A soft column of golden light above the hive, visible from across the meadow.
func _build_beacon() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.45
	cyl.height = 32.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 16
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/beacon.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 3.8 + 16.0, 0)
	add_child(mi)
