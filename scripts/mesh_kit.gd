class_name MeshKit
extends RefCounted
## Helpers for building procedural meshes with SurfaceTool.
## All colours passed in are expected to already be linear (see lin()).


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func lin(c: Color) -> Color:
	return c.srgb_to_linear()


static func shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


## Emits a grid of quads from row-major arrays (rows * cols). Triangles are wound
## so their front faces point along the supplied normals.
static func grid(st: SurfaceTool, pts: PackedVector3Array, nrm: PackedVector3Array,
		col: PackedColorArray, rows: int, cols: int, uvs := PackedVector2Array()) -> void:
	for r in rows - 1:
		for c in cols - 1:
			var i00 := r * cols + c
			var i01 := i00 + 1
			var i10 := i00 + cols
			var i11 := i10 + 1
			tri(st, pts, nrm, col, uvs, i00, i01, i10)
			tri(st, pts, nrm, col, uvs, i01, i11, i10)


static func tri(st: SurfaceTool, pts: PackedVector3Array, nrm: PackedVector3Array,
		col: PackedColorArray, uvs: PackedVector2Array, a: int, b: int, c: int) -> void:
	var face := (pts[b] - pts[a]).cross(pts[c] - pts[a])
	if face.length_squared() < 1e-14:
		return
	# Godot treats clockwise triangles as front-facing.
	if face.dot(nrm[a] + nrm[b] + nrm[c]) > 0.0:
		var t := b
		b = c
		c = t
	for i in [a, b, c]:
		st.set_color(col[i])
		st.set_normal(nrm[i])
		st.set_uv(uvs[i] if not uvs.is_empty() else Vector2.ZERO)
		st.add_vertex(pts[i])


## Ellipsoid, optionally lumpy. Colour fades from bottom to top.
static func ellipsoid(st: SurfaceTool, xf: Transform3D, radii: Vector3, rings: int, segs: int,
		top: Color, bottom: Color, noise: FastNoiseLite = null, amp := 0.0) -> void:
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for r in rings + 1:
		var phi := PI * r / rings
		for s in segs + 1:
			var th := TAU * s / segs
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var p := d * radii
			if noise:
				p += d * noise.get_noise_3dv(xf * p) * amp
			pts.append(xf * p)
			nrm.append((xf.basis * (d / radii)).normalized())
			col.append(bottom.lerp(top, d.y * 0.5 + 0.5))
	grid(st, pts, nrm, col, rings + 1, segs + 1)


## Tube following a path, tapering by radii. Colour fades from c0 to c1 along it.
static func tube(st: SurfaceTool, path: PackedVector3Array, radii: PackedFloat32Array, sides: int,
		c0: Color, c1: Color) -> void:
	var n := path.size()
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for i in n:
		var t := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var ref: Vector3 = Vector3.UP if absf(t.y) < 0.95 else Vector3.RIGHT
		var side := t.cross(ref).normalized()
		var up := side.cross(t).normalized()
		var c := c0.lerp(c1, float(i) / (n - 1))
		for s in sides + 1:
			var a := TAU * s / sides
			var d := side * cos(a) + up * sin(a)
			pts.append(path[i] + d * radii[i])
			nrm.append(d)
			col.append(c)
	grid(st, pts, nrm, col, n, sides + 1)


## Torus lying in the XZ plane. color_fn(angle_around, angle_tube) -> Color.
static func torus(st: SurfaceTool, xf: Transform3D, major: float, minor: float, segs: int,
		sides: int, color_fn: Callable) -> void:
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for i in segs + 1:
		var a := TAU * i / segs
		var out := Vector3(cos(a), 0.0, sin(a))
		for j in sides + 1:
			var b := TAU * j / sides
			var d := out * cos(b) + Vector3.UP * sin(b)
			pts.append(xf * (out * major + d * minor))
			nrm.append((xf.basis * d).normalized())
			col.append(color_fn.call(a, b))
	grid(st, pts, nrm, col, segs + 1, sides + 1)


## Flat elliptical disc (or arc of one) facing local +Y. color_fn(radial_t) -> Color.
static func disc(st: SurfaceTool, xf: Transform3D, rx: float, rz: float, segs: int, rings: int,
		color_fn: Callable, a0 := 0.0, a1 := TAU) -> void:
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uvs := PackedVector2Array()
	var n := (xf.basis * Vector3.UP).normalized()
	for r in rings + 1:
		var t := float(r) / rings
		for s in segs + 1:
			var a := lerpf(a0, a1, float(s) / segs)
			var p := Vector3(cos(a) * rx * t, 0.0, sin(a) * rz * t)
			pts.append(xf * p)
			nrm.append(n)
			col.append(color_fn.call(t))
			uvs.append(Vector2(p.x, p.z))
	grid(st, pts, nrm, col, rings + 1, segs + 1, uvs)


## Cone layer for conifers: a drooping, ragged skirt with a point on top.
static func cone(st: SurfaceTool, base: Vector3, radius: float, height: float, segs: int,
		bottom: Color, top: Color, noise: FastNoiseLite = null, amp := 0.0) -> void:
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for row in 3:
		for s in segs + 1:
			var a := TAU * s / segs
			var d := Vector3(cos(a), 0.0, sin(a))
			match row:
				0:
					pts.append(base + Vector3.UP * height * 0.3)
					nrm.append(Vector3.DOWN)
					col.append(shade(bottom, 0.6))
				1:
					var j: float = noise.get_noise_3dv(base + d * radius) * amp if noise else 0.0
					pts.append(base + d * (radius + j) - Vector3.UP * (0.3 + absf(j) * 0.5))
					nrm.append((d * height + Vector3.UP * radius).normalized())
					col.append(bottom)
				2:
					pts.append(base + Vector3.UP * height)
					nrm.append(Vector3.UP)
					col.append(top)
	grid(st, pts, nrm, col, 3, segs + 1)
