class_name HiveInterior
extends Node3D
## Inside the hive: honeycomb walls that fill with your honey, the brood nest,
## the queen and her workers. It sits far below the meadow and is only shown
## while the player is inside.

const ORIGIN := Vector3(0.0, -300.0, 0.0)
const HEIGHT := 12.0
const DOME := 10.0
const COIL := 0.45
const RING := 7.7 # radius of the cell openings lining the wall
const RING_TOP := 6.4
const SHEET_X := 4.2
const PLATFORM_R := 2.6
const PLATFORM_Y := 0.8
const CELL_R := 0.19
const CELL_DEPTH := 0.28
const EXIT_ANGLE := PI * 0.5 # the tunnel to the outside is on the +Z side, like the entrance

enum Cell { EMPTY, HONEY, CAPPED, POLLEN, EGG, LARVA, BROOD }

var spawn_point: Vector3 ## Where the bee appears after entering.
var exit_point: Vector3 ## Fly here to leave.
var queen: BeeModel

var _cells: MultiMesh
var _cell_y := PackedFloat32Array()
var _state := PackedByteArray()
var _honey_order: Array[int] = []
var _pollen_order: Array[int] = []
var _brood: Array[int] = []
var _shown := Vector2i(-1, -1)
var _store_timer := 0.0
var _brood_timer := 0.0
var _queen_target := Vector3.ZERO
var _queen_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _hum: AudioStreamPlayer
var _extra: Array[InteriorBee] = []


func _ready() -> void:
	position = ORIGIN
	_rng.seed = 77
	spawn_point = ORIGIN + Vector3(0.0, 1.8, 4.3)
	exit_point = ORIGIN + Vector3(0.0, 1.3, 7.1)
	_build_shell()
	_build_cells()
	_build_lights()
	_build_bees()
	_hum = AudioStreamPlayer.new()
	_hum.stream = AudioSynth.buzz()
	_hum.pitch_scale = 0.62
	_hum.volume_db = -19.0
	add_child(_hum)
	set_active(false)


func set_active(on: bool) -> void:
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		_sync_population()
		_shown = Vector2i(-1, -1)
		_update_stores()
		_hum.play()
	else:
		_hum.stop()


## The hive gets busier as the colony grows.
func _sync_population() -> void:
	var want: int = Game.stage * 6
	while _extra.size() < want:
		var b := InteriorBee.new()
		b.interior = self
		b.mode = InteriorBee.Mode.FLY if _extra.size() % 2 == 0 else InteriorBee.Mode.CRAWL
		b.surface = _extra.size() % 5
		add_child(b)
		_extra.append(b)
	while _extra.size() > want:
		_extra.pop_back().queue_free()


func queen_position() -> Vector3:
	return queen.global_position


## Keeps a world-space point inside the hive's open space.
func constrain(p: Vector3, margin: float) -> Vector3:
	var l := p - ORIGIN
	l.y = clampf(l.y, 0.3 + margin, HEIGHT - 1.5)
	var max_r := _inner_radius(l.y) - margin
	if l.y < RING_TOP + 0.3:
		max_r = minf(max_r, RING - 0.3 - margin)
	var flat := Vector2(l.x, l.z)
	if flat.length() > max_r:
		flat = flat.limit_length(maxf(max_r, 0.1))
		l.x = flat.x
		l.z = flat.y
	return ORIGIN + l


## Random open point, in local space, for bees flying about.
func random_air_point() -> Vector3:
	var p := Vector3.RIGHT.rotated(Vector3.UP, _rng.randf() * TAU) * _rng.randf_range(2.0, 6.5)
	p.y = _rng.randf_range(1.6, 7.5)
	return constrain(p + ORIGIN, 0.5) - ORIGIN


## Point and outward normal on a comb surface, for crawling bees.
## Surface 0 is the wall (uv = angle, height); 1-4 are the faces of the two hanging sheets (uv = z, height).
func surface_point(surface: int, uv: Vector2) -> Array:
	if surface == 0:
		var out := Vector3(cos(uv.x), 0.0, sin(uv.x))
		return [out * RING + Vector3.UP * uv.y, -out]
	var sx := -1.0 if surface <= 2 else 1.0
	var side := -1.0 if surface % 2 == 1 else 1.0
	return [Vector3(sx * SHEET_X + side * CELL_DEPTH, uv.y, uv.x), Vector3(side, 0.0, 0.0)]


func _process(delta: float) -> void:
	_store_timer -= delta
	if _store_timer <= 0.0:
		_store_timer = 0.5
		_update_stores()
	# The queen strolls around the brood nest, and the brood slowly grows.
	_queen_timer -= delta
	if _queen_timer <= 0.0:
		_queen_timer = _rng.randf_range(4.0, 8.0)
		_queen_target = Vector3.RIGHT.rotated(Vector3.UP, _rng.randf() * TAU) * _rng.randf_range(0.0, 1.4)
	var to := _queen_target - Vector3(queen.position.x, 0.0, queen.position.z)
	if to.length() > 0.05:
		queen.position += to.normalized() * minf(0.2 * delta, to.length())
		queen.rotation.y = lerp_angle(queen.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-2.0 * delta))
	_brood_timer -= delta
	if _brood_timer <= 0.0:
		_brood_timer = 0.4
		var i: int = _brood[_rng.randi() % _brood.size()]
		var next := {Cell.EMPTY: Cell.EGG, Cell.EGG: Cell.LARVA, Cell.LARVA: Cell.BROOD, Cell.BROOD: Cell.EMPTY}
		_set_cell(i, next[_state[i]])


func _inner_radius(y: float) -> float:
	var t := clampf(y / HEIGHT * 0.97, 0.0, 1.0)
	return DOME * sqrt(maxf(1.0 - t * t, 0.0)) + 0.3 - COIL - 0.25


func _facing(z: Vector3) -> Basis:
	var up: Vector3 = Vector3.UP if absf(z.y) < 0.9 else Vector3.BACK
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x), z)


func _hash(i: int) -> float:
	return fposmod(sin(i * 12.9898) * 43758.5453, 1.0)


# --- building ---------------------------------------------------------------

func _build_shell() -> void:
	var st := MeshKit.begin()
	# Floor of old wax and propolis.
	MeshKit.disc(st, Transform3D(), DOME + 0.6, DOME + 0.6, 40, 10,
		func(t: float) -> Color: return MeshKit.lin(Color(0.34, 0.2, 0.08).lerp(Color(0.22, 0.13, 0.05), t)))
	# Coiled straw walls, seen from the inside.
	var coils := int(HEIGHT / (COIL * 1.6))
	for i in coils:
		var t := float(i) / (coils - 1)
		var radius := DOME * sqrt(maxf(1.0 - pow(t * 0.97, 2.0), 0.0)) + 0.3
		var bright := 0.85 + 0.15 * sin(i * 2.1)
		MeshKit.torus(st, Transform3D(Basis(), Vector3(0, t * HEIGHT, 0)), radius, COIL, 56, 8,
			func(a: float, b: float) -> Color:
				var twist := 0.5 + 0.5 * sin(a * 70.0 + b * 1.5)
				return MeshKit.lin(MeshKit.shade(Hive.STRAW.lerp(Hive.STRAW_DARK, twist * 0.6), bright * 0.8)))
	# Wax pedestal for the brood nest.
	MeshKit.tube(st, PackedVector3Array([Vector3(0, -0.1, 0), Vector3(0, PLATFORM_Y - 0.25, 0)]),
		PackedFloat32Array([PLATFORM_R + 0.3, PLATFORM_R]), 28,
		MeshKit.lin(Color(0.7, 0.5, 0.2)), MeshKit.lin(Color(0.9, 0.7, 0.32)))
	var wax := StandardMaterial3D.new()
	wax.vertex_color_use_as_albedo = true
	wax.roughness = 0.8
	var mesh := st.commit()
	mesh.surface_set_material(0, wax)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	# Daylight pouring in through the tunnel.
	var glow := MeshKit.begin()
	MeshKit.disc(glow, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 1.3, RING + 1.9)), 0.8, 0.6, 20, 1,
		func(t: float) -> Color: return Color(1, 1, 1, 1.0 - t * 0.6))
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(3.0, 2.6, 1.9)
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow_mesh := glow.commit()
	glow_mesh.surface_set_material(0, glow_mat)
	var gi := MeshInstance3D.new()
	gi.mesh = glow_mesh
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)

	# Solid parts the bee bumps into: the hanging combs and the pedestal.
	var body := StaticBody3D.new()
	add_child(body)
	for sx in [-1.0, 1.0]:
		var box := BoxShape3D.new()
		box.size = Vector3(CELL_DEPTH * 2.0, 8.0, 8.4)
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position = Vector3(sx * SHEET_X, 6.5, 0.0)
		body.add_child(cs)
	var pedestal := CylinderShape3D.new()
	pedestal.radius = PLATFORM_R + 0.1
	pedestal.height = PLATFORM_Y * 2.0
	var ps := CollisionShape3D.new()
	ps.shape = pedestal
	body.add_child(ps)


func _build_cells() -> void:
	var xfs: Array[Transform3D] = []
	var brood_flags := PackedByteArray()
	var row_h := sqrt(3.0) * CELL_R
	# Comb lining the wall. Lower rows are nursery cells, the rest store honey and pollen.
	var cols := int(TAU * RING / (1.5 * CELL_R))
	cols -= cols % 2
	for c in cols:
		var a := TAU * c / cols
		var out := Vector3(cos(a), 0.0, sin(a))
		for r in int((RING_TOP - 0.4) / row_h):
			var y := 0.4 + (r + (0.5 if c % 2 == 1 else 0.0)) * row_h
			if absf(angle_difference(a, EXIT_ANGLE)) < 0.32 and y < 3.4:
				continue # gap for the exit tunnel
			xfs.append(Transform3D(_facing(-out), out * RING + Vector3.UP * y))
			brood_flags.append(1 if y < 1.3 else 0)
	# Two sheets of comb hanging from the roof, cells on both faces.
	for sx in [-1.0, 1.0]:
		for side in [-1.0, 1.0]:
			var n := int(8.0 / (1.5 * CELL_R))
			for c in n:
				var z := -4.0 + c * 1.5 * CELL_R
				for r in 60:
					var y := 2.6 + (r + (0.5 if c % 2 == 1 else 0.0)) * row_h
					if Vector2(SHEET_X + CELL_DEPTH, z).length() + CELL_R > _inner_radius(y) + 0.2:
						break
					xfs.append(Transform3D(_facing(Vector3(side, 0, 0)), Vector3(sx * SHEET_X + side * CELL_DEPTH, y, z)))
					brood_flags.append(0)
	# The brood nest on top of the pedestal, where the queen lives.
	for i in range(-14, 15):
		for j in range(-14, 15):
			var x := i * 1.5 * CELL_R
			var z := (j + (0.5 if absi(i) % 2 == 1 else 0.0)) * row_h
			if Vector2(x, z).length() < PLATFORM_R - CELL_R:
				xfs.append(Transform3D(_facing(Vector3.UP), Vector3(x, PLATFORM_Y, z)))
				brood_flags.append(1)

	_cells = MultiMesh.new()
	_cells.transform_format = MultiMesh.TRANSFORM_3D
	_cells.use_custom_data = true
	_cells.mesh = _cell_mesh()
	_cells.instance_count = xfs.size()
	_state.resize(xfs.size())
	var store: Array[int] = []
	for i in xfs.size():
		_cells.set_instance_transform(i, xfs[i])
		_cell_y.append(xfs[i].origin.y)
		if brood_flags[i]:
			_brood.append(i)
			var roll := _hash(i)
			_set_cell(i, Cell.EMPTY if roll < 0.2 else Cell.EGG if roll < 0.35 else Cell.LARVA if roll < 0.65 else Cell.BROOD)
		else:
			store.append(i)
			_set_cell(i, Cell.EMPTY)
	# Honey fills from the top down, pollen from the bottom up (with some randomness).
	_honey_order = store.duplicate()
	_honey_order.sort_custom(func(a: int, b: int) -> bool: return _cell_y[a] + _hash(a) * 2.0 > _cell_y[b] + _hash(b) * 2.0)
	_pollen_order = store.duplicate()
	_pollen_order.sort_custom(func(a: int, b: int) -> bool: return _cell_y[a] + _hash(a + 7) * 1.5 < _cell_y[b] + _hash(b + 7) * 1.5)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/comb.gdshader")
	mat.set_shader_parameter("depth", CELL_DEPTH)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _cells
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## One hexagonal wax cell opening toward +Z, plus a "contents" cap the shader slides along it.
## The walls are inset and a rim closes the gap, so neighbouring cells never overlap.
func _cell_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var wax_front := MeshKit.lin(Color(0.98, 0.8, 0.4))
	var wax_back := MeshKit.lin(Color(0.62, 0.42, 0.14))
	var inner := CELL_R * 0.9
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uvs := PackedVector2Array()
	for row in 2:
		for k in 7:
			var a := TAU * k / 6.0
			var corner := Vector3(cos(a), sin(a), 0.0) * inner
			pts.append(corner + Vector3(0, 0, -CELL_DEPTH * row))
			nrm.append(-corner.normalized())
			col.append(wax_front if row == 0 else wax_back)
			uvs.append(Vector2.ZERO)
	MeshKit.grid(st, pts, nrm, col, 2, 7, uvs)
	pts = PackedVector3Array()
	nrm = PackedVector3Array()
	col = PackedColorArray()
	uvs = PackedVector2Array()
	for radius in [inner, CELL_R]:
		for k in 7:
			var a := TAU * k / 6.0
			pts.append(Vector3(cos(a), sin(a), 0.0) * radius)
			nrm.append(Vector3.BACK)
			col.append(wax_front)
			uvs.append(Vector2.ZERO)
	MeshKit.grid(st, pts, nrm, col, 2, 7, uvs)
	for content in 2:
		pts = PackedVector3Array()
		nrm = PackedVector3Array()
		col = PackedColorArray()
		uvs = PackedVector2Array()
		for ring in 2:
			for k in 7:
				var a := TAU * k / 6.0
				pts.append(Vector3(cos(a), sin(a), 0.0) * inner * ring + Vector3(0, 0, -CELL_DEPTH + 0.004))
				nrm.append(Vector3.BACK)
				col.append(wax_back)
				uvs.append(Vector2(content, 0.0))
		MeshKit.grid(st, pts, nrm, col, 2, 7, uvs)
	return st.commit()


func _set_cell(i: int, state: int) -> void:
	_state[i] = state
	var h := _hash(i)
	var c: Color
	var fill := 0.0
	match state:
		Cell.EMPTY:
			c = Color(0.42, 0.27, 0.1)
		Cell.HONEY:
			c = Color(1.0, 0.72, 0.1).lerp(Color(1.0, 0.52, 0.02), h)
			fill = 0.45 + 0.4 * h
		Cell.CAPPED:
			c = Color(1.0, 0.93, 0.7)
			fill = 1.0
		Cell.POLLEN:
			c = [Color(1.0, 0.75, 0.1), Color(0.95, 0.45, 0.1), Color(0.85, 0.78, 0.25), Color(0.75, 0.3, 0.15)][int(h * 4.0)]
			fill = 0.5
		Cell.EGG:
			c = Color(0.95, 0.93, 0.85)
			fill = 0.06
		Cell.LARVA:
			c = Color(1.0, 0.98, 0.92)
			fill = 0.4
		Cell.BROOD:
			c = Color(0.78, 0.56, 0.3)
			fill = 1.0
	var lc := c.srgb_to_linear()
	_cells.set_instance_custom_data(i, Color(lc.r, lc.g, lc.b, fill))


## Shows the colony's real stores: one cell of honey per honey, one of pollen per pollen.
func _update_stores() -> void:
	var total := _honey_order.size()
	var honey_cells := mini(int(Game.honey) + 30, int(total * 0.75))
	var pollen_cells := mini(int(Game.hive_pollen) + 6, total - honey_cells)
	var shown := Vector2i(honey_cells, pollen_cells)
	if shown == _shown:
		return
	_shown = shown
	var want := {}
	for k in honey_cells:
		want[_honey_order[k]] = Cell.CAPPED if k < honey_cells * 0.4 else Cell.HONEY
	var added := 0
	for i in _pollen_order:
		if added >= pollen_cells:
			break
		if not want.has(i):
			want[i] = Cell.POLLEN
			added += 1
	for i in _honey_order:
		var s: int = want.get(i, Cell.EMPTY)
		if _state[i] != s:
			_set_cell(i, s)


func _build_lights() -> void:
	for p in [Vector3(4.5, 6.5, 4.5), Vector3(-4.5, 6.5, 4.5), Vector3(4.5, 6.5, -4.5), Vector3(-4.5, 6.5, -4.5)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.58)
		l.light_energy = 1.3
		l.omni_range = 10.0
		l.position = p
		add_child(l)
	var crown := OmniLight3D.new()
	crown.light_color = Color(1.0, 0.9, 0.7)
	crown.light_energy = 1.6
	crown.omni_range = 6.0
	crown.position = Vector3(0, 4.0, 0)
	add_child(crown)
	var day := OmniLight3D.new()
	day.light_color = Color(1.0, 0.95, 0.85)
	day.light_energy = 2.0
	day.omni_range = 6.0
	day.position = Vector3(0, 1.6, RING + 0.6)
	add_child(day)


func _build_bees() -> void:
	queen = BeeModel.new()
	queen.queen = true
	queen.flying = false
	queen.scale = Vector3.ONE * 1.5
	queen.position = Vector3(0, PLATFORM_Y + 0.22, 0)
	add_child(queen)
	for i in 8:
		var b := InteriorBee.new()
		b.interior = self
		b.mode = InteriorBee.Mode.ATTEND
		b.angle = TAU * i / 8.0
		add_child(b)
	for i in 16:
		var b := InteriorBee.new()
		b.interior = self
		b.mode = InteriorBee.Mode.CRAWL
		b.surface = 0 if i < 8 else 1 + i % 4
		add_child(b)
	for i in 8:
		var b := InteriorBee.new()
		b.interior = self
		b.mode = InteriorBee.Mode.FLY
		add_child(b)
