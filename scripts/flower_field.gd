class_name FlowerField
extends Node3D
## Every flower in the meadow. Drawn with one MultiMesh per species; the gameplay
## data (nectar, pollen, pollination) lives in parallel arrays indexed by flower.

const SPARE := 120 # free slots per species for flowers that sprout during play
const CELL := 8.0
const LILY := 5
const STEM_DARK := Color(0.16, 0.34, 0.09)
const STEM_LIGHT := Color(0.33, 0.55, 0.16)

const SPECIES := [
	{"name": "Daisy", "petal": Color(0.98, 0.97, 0.94), "base": Color(0.95, 0.88, 0.5), "center": Color(1.0, 0.74, 0.08),
		"petals": 18, "len": 0.34, "width": 0.07, "cup": 0.15, "layers": 1, "core": 0.12, "stem": 1.7,
		"nectar": 4.0, "pollen": 3.0, "weight": 3.0},
	{"name": "Sunflower", "petal": Color(1.0, 0.78, 0.08), "base": Color(0.95, 0.52, 0.05), "center": Color(0.32, 0.18, 0.06),
		"petals": 20, "len": 0.5, "width": 0.12, "cup": 0.1, "layers": 2, "core": 0.3, "stem": 3.2,
		"nectar": 9.0, "pollen": 7.0, "weight": 1.0},
	{"name": "Poppy", "petal": Color(0.93, 0.13, 0.08), "base": Color(0.25, 0.04, 0.05), "center": Color(0.15, 0.12, 0.1),
		"petals": 5, "len": 0.36, "width": 0.3, "cup": 0.9, "layers": 1, "core": 0.07, "stem": 1.4,
		"nectar": 5.0, "pollen": 6.0, "weight": 2.0},
	{"name": "Cornflower", "petal": Color(0.27, 0.45, 0.96), "base": Color(0.35, 0.15, 0.6), "center": Color(0.3, 0.15, 0.45),
		"petals": 12, "len": 0.26, "width": 0.09, "cup": 0.35, "layers": 1, "core": 0.07, "stem": 1.5,
		"nectar": 6.0, "pollen": 3.0, "weight": 2.0},
	{"name": "Cosmos", "petal": Color(0.98, 0.47, 0.74), "base": Color(0.75, 0.15, 0.4), "center": Color(1.0, 0.8, 0.15),
		"petals": 8, "len": 0.36, "width": 0.17, "cup": 0.2, "layers": 1, "core": 0.08, "stem": 2.0,
		"nectar": 5.0, "pollen": 4.0, "weight": 2.0},
	{"name": "Water Lily", "petal": Color(1.0, 0.84, 0.92), "base": Color(0.95, 0.5, 0.7), "center": Color(1.0, 0.85, 0.2),
		"petals": 12, "len": 0.32, "width": 0.13, "cup": 0.7, "layers": 2, "core": 0.08, "stem": 0.0,
		"nectar": 12.0, "pollen": 5.0, "weight": 0.0},
]

var terrain: Terrain
var vegetation: Vegetation

# Per-flower data.
var hover := PackedVector3Array() # where a bee hovers to feed
var species := PackedInt32Array()
var nectar := PackedFloat32Array()
var pollen := PackedFloat32Array()
var pollinated := PackedByteArray()

var _slot := PackedInt32Array()
var _xf: Array[Transform3D] = []
var _mm: Array[MultiMesh] = []
var _head_local: Array[Vector3] = []
var _grid := {}
var _growing := {}
var _highlight := -1
var _regen_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _material: ShaderMaterial


func _ready() -> void:
	_rng.seed = 4242
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/flower.gdshader")
	for s in SPECIES.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _build_mesh(s)
		_mm.append(mm)

	var plan := _plan()
	var counts := PackedInt32Array()
	counts.resize(SPECIES.size())
	for entry in plan:
		counts[entry[0]] += 1
	for s in SPECIES.size():
		_mm[s].instance_count = counts[s] + SPARE
		_mm[s].visible_instance_count = 0
	for entry in plan:
		_add(entry[0], entry[1], _rng.randf_range(0.8, 1.25))

	for s in SPECIES.size():
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = _mm[s]
		mmi.material_override = _material
		add_child(mmi)


func set_night(amount: float) -> void:
	_material.set_shader_parameter("night_glow", amount)


func set_shadows(enabled: bool) -> void:
	for child in get_children():
		if child is MultiMeshInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func species_name(i: int) -> String:
	return SPECIES[species[i]]["name"]


## Index of the closest flower whose feeding point is within radius of p, or -1.
func nearest(p: Vector3, radius: float) -> int:
	var best := -1
	var best_d := radius * radius
	var c := _cell(p)
	var reach := int(ceilf(radius / CELL))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			if not _grid.has(key):
				continue
			for i in _grid[key]:
				var d: float = hover[i].distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = i
	return best


func random_with_nectar(rng: RandomNumberGenerator) -> int:
	for attempt in 24:
		var i := rng.randi() % species.size()
		if nectar[i] > 2.0 and Vector2(hover[i].x, hover[i].z).length() < 100.0:
			return i
	return -1


## Removes up to the wanted amounts from flower i and returns (nectar, pollen) taken.
func take(i: int, want_nectar: float, want_pollen: float) -> Vector2:
	var n := minf(want_nectar, nectar[i])
	var p := minf(want_pollen, pollen[i])
	nectar[i] -= n
	pollen[i] -= p
	if n > 0.0 or p > 0.0:
		_update_visual(i)
	return Vector2(n, p)


func set_highlight(i: int) -> void:
	if i == _highlight:
		return
	var old := _highlight
	_highlight = i
	if old >= 0:
		_update_visual(old)
	if i >= 0:
		_update_visual(i)


## Pollinates flower i. Returns 0 if it already was, 1 if pollinated, 2 if a new flower also sprouted.
func pollinate(i: int) -> int:
	if pollinated[i]:
		return 0
	pollinated[i] = 1
	var info: Dictionary = SPECIES[species[i]]
	nectar[i] = info["nectar"]
	pollen[i] = info["pollen"]
	_update_visual(i)
	if species[i] == LILY or _rng.randf() > 0.7:
		return 1
	for attempt in 8:
		var q := Vector2(hover[i].x, hover[i].z) + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(1.5, 4.0)
		if not _valid(q):
			continue
		if nearest(Vector3(q.x, terrain.height_at(q.x, q.y) + 1.5, q.y), 1.2) >= 0:
			continue
		var j := _add(species[i], q, _rng.randf_range(0.9, 1.3))
		if j >= 0:
			_growing[j] = 0.0
			_mm[species[j]].set_instance_transform(_slot[j], Transform3D(_xf[j].basis.scaled(Vector3.ONE * 0.02), _xf[j].origin))
			return 2
	return 1


func _process(delta: float) -> void:
	_regen_timer += delta
	if _regen_timer >= 1.0:
		for i in species.size():
			var info: Dictionary = SPECIES[species[i]]
			var max_n: float = info["nectar"]
			var max_p: float = info["pollen"]
			if nectar[i] < max_n or pollen[i] < max_p:
				nectar[i] = minf(max_n, nectar[i] + max_n / 50.0 * _regen_timer)
				pollen[i] = minf(max_p, pollen[i] + max_p / 70.0 * _regen_timer)
				_update_visual(i)
		_regen_timer = 0.0
	for i in _growing.keys():
		var t: float = minf(_growing[i] + delta / 2.5, 1.0)
		var s := 1.0 - pow(1.0 - t, 3.0)
		var xf := _xf[i]
		_mm[species[i]].set_instance_transform(_slot[i], Transform3D(xf.basis.scaled(Vector3.ONE * maxf(s, 0.02)), xf.origin))
		if t >= 1.0:
			_growing.erase(i)
		else:
			_growing[i] = t


func _update_visual(i: int) -> void:
	var info: Dictionary = SPECIES[species[i]]
	var fresh: float = nectar[i] / info["nectar"] * 0.7 + pollen[i] / info["pollen"] * 0.3
	var glow := 1.0 if i == _highlight else 0.0
	_mm[species[i]].set_instance_custom_data(_slot[i], Color(fresh, glow, float(pollinated[i]), 0.0))


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _valid(q: Vector2) -> bool:
	var r := q.length()
	if r < 4.5 or r > Terrain.MEADOW_RADIUS:
		return false
	if q.distance_to(Terrain.POND_CENTER) < Terrain.POND_RADIUS * 1.15:
		return false
	return vegetation.is_clear(q, 1.0)


func _pick_species() -> int:
	var total := 0.0
	for info in SPECIES:
		total += info["weight"]
	var r := _rng.randf() * total
	for s in SPECIES.size():
		r -= SPECIES[s]["weight"]
		if r <= 0.0:
			return s
	return 0


func _random_point(min_r: float, max_r: float) -> Vector2:
	return Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf_range(min_r * min_r, max_r * max_r))


## Returns an Array of [species, Vector2 position].
func _plan() -> Array:
	var list := []
	for patch in 38:
		var center := _random_point(14.0, 128.0)
		var main := _pick_species()
		var spread := _rng.randf_range(2.5, 6.5)
		for i in _rng.randi_range(8, 22):
			var q := center + Vector2(_rng.randfn(0.0, spread), _rng.randfn(0.0, spread))
			if _valid(q):
				list.append([main if _rng.randf() < 0.85 else _pick_species(), q])
	for i in 140:
		var q := _random_point(5.0, 130.0)
		if _valid(q):
			list.append([_pick_species(), q])
	# A ring of flowers around the hive so the first trip is easy.
	for i in 16:
		var q := Vector2.from_angle(TAU * i / 16.0 + _rng.randf_range(-0.1, 0.1)) * _rng.randf_range(6.0, 11.0)
		if _valid(q):
			list.append([i % 5, q])
	for i in 14:
		var q := Terrain.POND_CENTER + _random_point(0.0, Terrain.POND_RADIUS * 0.6)
		list.append([LILY, q])
	return list


func _add(s: int, q: Vector2, scl: float) -> int:
	var mm := _mm[s]
	var k := mm.visible_instance_count
	if k >= mm.instance_count:
		return -1
	var y := Terrain.WATER_LEVEL + 0.02 if s == LILY else terrain.height_at(q.x, q.y) - 0.05
	var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scl), Vector3(q.x, y, q.y))
	mm.visible_instance_count = k + 1
	mm.set_instance_transform(k, xf)
	var i := species.size()
	species.append(s)
	_slot.append(k)
	_xf.append(xf)
	hover.append(xf * _head_local[s])
	var info: Dictionary = SPECIES[s]
	nectar.append(info["nectar"])
	pollen.append(info["pollen"])
	pollinated.append(0)
	var cell := _cell(hover[i])
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append(i)
	_update_visual(i)
	return i


# --- meshes ------------------------------------------------------------------

func _build_mesh(s: int) -> ArrayMesh:
	var info: Dictionary = SPECIES[s]
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + s
	var st := MeshKit.begin()
	var stem_h: float = info["stem"]
	var head := Vector3(0.0, 0.04, 0.0)
	var face := Vector3.UP
	if stem_h > 0.0:
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		var lean := Vector3(0.18, 0.0, 0.06) * stem_h * 0.5
		var thick := 1.5 if s == 1 else 1.0
		for i in 8:
			var t := i / 7.0
			path.append(Vector3(lean.x * t * t, stem_h * t, lean.z * t * t))
			radii.append(lerpf(0.04, 0.025, t) * thick)
		MeshKit.tube(st, path, radii, 6, MeshKit.lin(STEM_DARK), MeshKit.lin(STEM_LIGHT))
		_leaf(st, path[2], 0.4, 0.45 * thick + stem_h * 0.06)
		_leaf(st, path[4], PI + 0.7, 0.38 * thick + stem_h * 0.05)
		head = path[7]
		face = Vector3(0.35, 1.0, 0.12).normalized()
	else:
		MeshKit.disc(st, Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), 0.75, 0.75, 20, 2,
			func(t: float) -> Color: return MeshKit.lin(Color(0.2, 0.42, 0.12).lerp(Color(0.3, 0.55, 0.18), t)),
			0.25, TAU)
	var xf := Transform3D(Basis(Quaternion(Vector3.UP, face)), head)
	var core: float = info["core"]
	var center: Color = info["center"]
	MeshKit.ellipsoid(st, xf, Vector3(core, core * 0.45, core), 5, 12,
		MeshKit.lin(center.lightened(0.15)), MeshKit.lin(center.darkened(0.35)))
	var petal_c := MeshKit.lin(info["petal"])
	var base_c := MeshKit.lin(info["base"])
	var n: int = info["petals"]
	var layers: int = info["layers"]
	for layer in layers:
		for k in n:
			var a := TAU * (k + 0.5 * layer) / n + rng.randf_range(-0.08, 0.08)
			var length: float = info["len"] * (1.0 - 0.18 * layer) * rng.randf_range(0.9, 1.1)
			var tint := rng.randf_range(0.9, 1.05)
			_petal(st, xf, a, core * 0.8, length, info["width"], info["cup"] + layer * 0.2,
				-0.01 + layer * 0.015, base_c, MeshKit.shade(petal_c, tint))
	_head_local.append(xf * Vector3(0.0, core * 0.45 + 0.2, 0.0))
	return st.commit()


func _petal(st: SurfaceTool, xf: Transform3D, angle: float, start: float, length: float, width: float,
		cup: float, lift: float, base: Color, tip: Color) -> void:
	var d := Vector3(cos(angle), 0.0, sin(angle))
	var side := Vector3(-d.z, 0.0, d.x)
	var rows := 5
	var cols := 3
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for r in rows:
		var t := float(r) / (rows - 1)
		var w := width * pow(sin(PI * (0.12 + 0.86 * t)), 0.6)
		var rise := cup * t * t * length
		for c in cols:
			var u := float(c) / (cols - 1) * 2.0 - 1.0
			var p := d * (start + t * length * (1.0 - cup * 0.3)) + side * (u * w) \
				+ Vector3.UP * (lift + rise + absf(u) * w * 0.25)
			pts.append(xf * p)
			nrm.append((xf.basis * (Vector3.UP - d * cup * 2.0 * t)).normalized())
			col.append(base.lerp(tip, smoothstep(0.0, 0.45, t)))
	MeshKit.grid(st, pts, nrm, col, rows, cols)


func _leaf(st: SurfaceTool, at: Vector3, angle: float, length: float) -> void:
	var d := Vector3(cos(angle), 0.0, sin(angle))
	var side := Vector3(-d.z, 0.0, d.x)
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for r in 5:
		var t := r / 4.0
		var w := 0.09 * length * 2.0 * sin(PI * t)
		for c in 3:
			var u := c - 1.0
			pts.append(at + d * t * length + side * u * w + Vector3.UP * (t * length * 0.5 - t * t * length * 0.45 + absf(u) * w * 0.3))
			nrm.append((Vector3.UP - d * 0.3).normalized())
			col.append(MeshKit.lin(STEM_DARK.lerp(Color(0.36, 0.6, 0.18), t)))
	MeshKit.grid(st, pts, nrm, col, 5, 3)
