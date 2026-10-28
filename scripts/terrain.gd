class_name Terrain
extends MeshInstance3D
## Procedural heightfield: a rolling meadow with a pond, ringed by wooded hills.

const SIZE := 480.0
const RES := 200
const MEADOW_RADIUS := 135.0
const WORLD_RADIUS := 165.0
const POND_CENTER := Vector2(46.0, -40.0)
const POND_RADIUS := 17.0
const WATER_LEVEL := 0.0

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _patch := FastNoiseLite.new()
var _heights := PackedFloat32Array()
var _step := SIZE / RES


func _init() -> void:
	_noise.seed = 1337
	_noise.frequency = 0.007
	_noise.fractal_octaves = 4
	_detail.seed = 7
	_detail.frequency = 0.045
	_patch.seed = 21
	_patch.frequency = 0.025
	var w := RES + 1
	_heights.resize(w * w)
	for j in w:
		for i in w:
			_heights[j * w + i] = _compute(-SIZE * 0.5 + i * _step, -SIZE * 0.5 + j * _step)


func _ready() -> void:
	mesh = _build_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("detail", Fx.noise_texture(0.03, 256))
	material_override = mat


func height_at(x: float, z: float) -> float:
	var fx := clampf((x + SIZE * 0.5) / _step, 0.0, RES - 0.001)
	var fz := clampf((z + SIZE * 0.5) / _step, 0.0, RES - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var w := RES + 1
	var a := _heights[j * w + i]
	var b := _heights[j * w + i + 1]
	var c := _heights[(j + 1) * w + i]
	var d := _heights[(j + 1) * w + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## 0..1 noise used to vary grass height and colour in patches.
func patch_noise(q: Vector2) -> float:
	return clampf(_patch.get_noise_2d(q.x, q.y) * 0.7 + 0.5, 0.0, 1.0)


func _compute(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var r := p.length()
	var h := 1.8 + _noise.get_noise_2d(x, z) * 5.0 + _detail.get_noise_2d(x, z) * 0.35
	h = lerpf(1.6, h, smoothstep(5.0, 24.0, r)) # flat clearing around the hive
	h += pow(smoothstep(MEADOW_RADIUS - 15.0, SIZE * 0.5, r), 1.5) * 38.0 # hills at the edge
	h = maxf(h, 0.5)
	var pond := 1.0 - smoothstep(POND_RADIUS * 0.35, POND_RADIUS * 1.2, p.distance_to(POND_CENTER))
	return lerpf(h, -1.8, pond)


func _h(i: int, j: int) -> float:
	return _heights[clampi(j, 0, RES) * (RES + 1) + clampi(i, 0, RES)]


func _color(x: float, z: float, h: float, n: Vector3) -> Color:
	var q := Vector2(x, z)
	var patch := patch_noise(q)
	var c := Color(0.30, 0.50, 0.15).lerp(Color(0.50, 0.62, 0.21), patch)
	c = c.lerp(Color(0.60, 0.58, 0.32), smoothstep(5.0, 16.0, h) * 0.55) # drier hills
	c = c.lerp(Color(0.45, 0.36, 0.22), (1.0 - smoothstep(2.5, 6.0, q.length())) * 0.7) # trodden earth by the hive
	var near_pond := 1.0 - smoothstep(POND_RADIUS * 1.2, POND_RADIUS * 1.6, q.distance_to(POND_CENTER))
	c = c.lerp(Color(0.66, 0.58, 0.40), (1.0 - smoothstep(0.3, 0.9, h)) * near_pond) # sandy shore
	c = c.lerp(Color(0.26, 0.23, 0.16), 1.0 - smoothstep(-0.6, 0.1, h)) # mud under the water
	c = c.lerp(Color(0.46, 0.45, 0.42), smoothstep(0.82, 0.65, n.y)) # rocky slopes
	return c


func _build_mesh() -> ArrayMesh:
	var w := RES + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(w * w)
	normals.resize(w * w)
	colors.resize(w * w)
	for j in w:
		for i in w:
			var k := j * w + i
			var x := -SIZE * 0.5 + i * _step
			var z := -SIZE * 0.5 + j * _step
			var n := Vector3(_h(i - 1, j) - _h(i + 1, j), 2.0 * _step, _h(i, j - 1) - _h(i, j + 1)).normalized()
			verts[k] = Vector3(x, _heights[k], z)
			normals[k] = n
			colors[k] = _color(x, z, _heights[k], n).srgb_to_linear()
	var indices := PackedInt32Array()
	for j in RES:
		for i in RES:
			var a := j * w + i
			var c := a + w
			indices.append_array([a, a + 1, c, a + 1, c + 1, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
