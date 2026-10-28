class_name BeeModel
extends Node3D
## Procedural honeybee with flapping wings. Faces -Z.

var simple := false ## Fewer parts, for worker bees.
var pollen_amount := 0.0 ## 0..1, fills the pollen baskets on the hind legs.

var _wings: Array[Node3D] = []
var _baskets: Array[Node3D] = []
var _t := 0.0

static var _materials := {}
static var _meshes := {}


func _ready() -> void:
	_t = randf() * 10.0
	_sphere(Vector3(0.0, 0.0, -0.01), Vector3(0.17, 0.16, 0.18), _mat("thorax"))
	var abdomen := _sphere(Vector3(0.0, -0.03, 0.16), Vector3(0.2, 0.18, 0.3), _mat("abdomen"))
	abdomen.rotation.x = 0.28
	_sphere(Vector3(0.0, 0.01, -0.125), Vector3(0.13, 0.12, 0.1), _mat("dark"))
	for side in [-1.0, 1.0]:
		_sphere(Vector3(0.045 * side, 0.02, -0.135), Vector3(0.045, 0.075, 0.06), _mat("eye"))
		_wing(Vector3(0.035 * side, 0.075, -0.03), side, 0.13, 0.05)
		if not simple:
			_wing(Vector3(0.03 * side, 0.07, 0.02), side, 0.09, 0.035)
			var basket := _sphere(Vector3(0.11 * side, -0.15, 0.1), Vector3.ONE * 0.001, _mat("pollen"))
			_baskets.append(basket)
	if not simple:
		var limbs := MeshInstance3D.new()
		limbs.mesh = _limbs_mesh()
		limbs.material_override = _mat("dark")
		add_child(limbs)


func _process(delta: float) -> void:
	_t += delta
	var flap := sin(_t * 62.0) * 0.8
	for w in _wings:
		var side: float = w.get_meta("side")
		w.rotation = Vector3(0.0, -side * 0.3, side * (flap + 0.2))
	var s := clampf(pollen_amount, 0.0, 1.0)
	for b in _baskets:
		b.visible = s > 0.02
		b.scale = Vector3.ONE * (0.02 + 0.05 * sqrt(s))


func _sphere(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	if not _meshes.has("sphere"):
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 20
		sphere.rings = 10
		_meshes["sphere"] = sphere
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes["sphere"]
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	add_child(mi)
	return mi


func _wing(hinge: Vector3, side: float, length: float, width: float) -> void:
	var key := "wing_%s_%s" % [side, length]
	if not _meshes.has(key):
		var st := MeshKit.begin()
		MeshKit.disc(st, Transform3D(Basis(), Vector3(side * length, 0.0, width * 0.6)), length, width, 18, 1,
			func(_t: float) -> Color: return Color.WHITE)
		_meshes[key] = st.commit()
	var pivot := Node3D.new()
	pivot.position = hinge
	pivot.set_meta("side", side)
	add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = _mat("wing")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	_wings.append(pivot)


static func _limbs_mesh() -> ArrayMesh:
	if _meshes.has("limbs"):
		return _meshes["limbs"]
	var st := MeshKit.begin()
	var dark := MeshKit.lin(Color(0.08, 0.06, 0.04))
	for side in [-1.0, 1.0]:
		# antenna
		MeshKit.tube(st, PackedVector3Array([Vector3(0.02 * side, 0.05, -0.165), Vector3(0.035 * side, 0.12, -0.2),
			Vector3(0.06 * side, 0.14, -0.27)]), PackedFloat32Array([0.006, 0.005, 0.007]), 5, dark, dark)
		# three legs
		for k in 3:
			var z := -0.05 + k * 0.05
			MeshKit.tube(st, PackedVector3Array([Vector3(0.04 * side, -0.05, z), Vector3(0.1 * side, -0.08, z + 0.02 * k),
				Vector3(0.11 * side, -0.16, z + 0.05 + 0.03 * k)]), PackedFloat32Array([0.011, 0.009, 0.006]), 5, dark, dark)
	# stinger
	MeshKit.tube(st, PackedVector3Array([Vector3(0, -0.07, 0.29), Vector3(0, -0.09, 0.34)]),
		PackedFloat32Array([0.014, 0.001]), 6, dark, dark)
	var mesh := st.commit()
	_meshes["limbs"] = mesh
	return mesh


static func _mat(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	var m: Material
	match key:
		"abdomen", "thorax":
			var body := ShaderMaterial.new()
			body.shader = load("res://shaders/bee_body.gdshader")
			body.set_shader_parameter("banded", 1.0 if key == "abdomen" else 0.0)
			m = body
		"dark":
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.09, 0.06, 0.04)
			dark.roughness = 0.6
			m = dark
		"eye":
			var eye := StandardMaterial3D.new()
			eye.albedo_color = Color(0.05, 0.03, 0.02)
			eye.roughness = 0.12
			eye.metallic_specular = 0.9
			m = eye
		"wing":
			var wing := ShaderMaterial.new()
			wing.shader = load("res://shaders/wing.gdshader")
			m = wing
		"pollen":
			var pollen := StandardMaterial3D.new()
			pollen.albedo_color = Color(1.0, 0.7, 0.08)
			pollen.roughness = 0.85
			pollen.emission_enabled = true
			pollen.emission = Color(0.35, 0.22, 0.0)
			m = pollen
	_materials[key] = m
	return m
