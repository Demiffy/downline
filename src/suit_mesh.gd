# Smooth surfaces for the crew suit (suit.gd), made from parameter grids instead of boxes and
# cylinders, so it has no flat caps, no edges showing and nothing hanging off it:
#   grid   any surface fn(u, v) -> point, smooth normals, turned to face away from `inside`
#   loft   rings of points joined up (trunks, limbs, boots); rounded shut at the ends
#   lathe  a profile turned round the y axis, oval if you like (cuffs, collars, the neck seal)
#   tube   a round or flat section swept along a path (cables, laces, piping, straps)
#   slab   a thin piece lying on another surface, its own thickness and edges (pockets, pads,
#          straps, plates, the paint on a helmet), so it hugs the body and never floats or cuts in
# All of it is cached by key: a figure only builds MeshInstances over shared meshes.
extends RefCounted

static var _cache := {}


## The cached mesh for `key`, made by `make` the first time.
static func cached(key: String, make: Callable) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


## A surface from fn(u, v) -> Vector3 over u0..u1 (nu steps) by v0..v1 (nv steps). `wrap_u` closes
## it round in u. `inside` (Callable(u, v) -> Vector3, or a Vector3) is a point the surface faces
## away from. `skip` (Callable(u, v) -> bool) leaves out cells (a window cut in a shell).
static func grid(fn: Callable, u0: float, u1: float, nu: int, v0: float, v1: float, nv: int, inside, wrap_u := false, skip := Callable()) -> ArrayMesh:
	var cols := nu if wrap_u else nu + 1
	var pts := PackedVector3Array()
	var ins := PackedVector3Array()
	for j in nv + 1:
		var v := lerpf(v0, v1, float(j) / nv)
		for i in cols:
			var u := lerpf(u0, u1, float(i) / nu)
			pts.append(fn.call(u, v))
			ins.append(inside if inside is Vector3 else inside.call(u, v))
	var tris := PackedInt32Array()
	for j in nv:
		for i in nu:
			if skip.is_valid() and skip.call(lerpf(u0, u1, (i + 0.5) / nu), lerpf(v0, v1, (j + 0.5) / nv)):
				continue
			var i1 := (i + 1) % cols if wrap_u else i + 1
			var a := j * cols + i
			var b := j * cols + i1
			var c := (j + 1) * cols + i1
			var d := (j + 1) * cols + i
			tris.append_array([a, b, c, a, c, d])
	return build(pts, tris, ins)


## Vertices, triangles and for each vertex a point it should face away from: smooth normals, and
## every triangle wound so it faces out (Godot draws clockwise faces).
static func build(pts: PackedVector3Array, tris: PackedInt32Array, ins: PackedVector3Array) -> ArrayMesh:
	var nrm := PackedVector3Array()
	nrm.resize(pts.size())
	for t in range(0, tris.size(), 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var fn := (pts[b] - pts[a]).cross(pts[c] - pts[a])
		var mid := (pts[a] + pts[b] + pts[c]) / 3.0
		var out := mid - (ins[a] + ins[b] + ins[c]) / 3.0
		if fn.dot(out) < 0.0:
			fn = -fn
		nrm[a] += fn
		nrm[b] += fn
		nrm[c] += fn
	for i in nrm.size():
		var n := nrm[i]
		nrm[i] = n.normalized() if n.length_squared() > 1e-14 else (pts[i] - ins[i]).normalized()
	var idx := PackedInt32Array()
	for t in range(0, tris.size(), 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var fn := (pts[b] - pts[a]).cross(pts[c] - pts[a])
		if fn.dot(nrm[a] + nrm[b] + nrm[c]) > 0.0:   # (counter-clockwise from outside: turn it)
			idx.append_array([a, c, b])
		else:
			idx.append_array([a, b, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	if idx.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## A superellipse point at angle `t` (0 = +x, going toward -z): radii `rx`, `rz`, squareness `p`
## (2 = an ellipse, higher squarer).
static func sq(t: float, rx: float, rz: float, p := 2.0) -> Vector2:
	var c := cos(t)
	var s := sin(t)
	return Vector2(signf(c) * pow(absf(c), 2.0 / p) * rx, -signf(s) * pow(absf(s), 2.0 / p) * rz)


## A trunk lofted up y through sections [y, half width, half depth, z offset, squareness]
## (interpolated smoothly between), shut at each end by `close0`/`close1` (how far it rounds over).
static func trunk(keys: Array, nu := 28, nv := 30, close0 := 0.0, close1 := 0.0) -> ArrayMesh:
	var y0: float = keys[0][0] - close0
	var y1: float = keys[-1][0] + close1
	var fn := func(u: float, y: float) -> Vector3:
		var k := section(keys, y, close0, close1)
		var p := sq(u, k[0], k[1], k[3])
		return Vector3(p.x, y, p.y + k[2])
	var inside := func(_u: float, y: float) -> Vector3:
		var k := section(keys, y, close0, close1)
		return Vector3(0, clampf(y, keys[0][0], keys[-1][0]), k[2])
	return grid(fn, 0.0, TAU, nu, y0, y1, nv, inside, true)


## [half width, half depth, z offset, squareness] of a trunk at `y` (smoothstepped between keys;
## past the ends, rounded over to a point like the end of an egg).
static func section(keys: Array, y: float, close0 := 0.0, close1 := 0.0) -> Array:
	if y <= keys[0][0]:
		var k: Array = keys[0]
		var f := sqrt(maxf(0.0, 1.0 - pow((keys[0][0] - y) / maxf(close0, 0.0001), 2.0))) if close0 > 0.0 else 1.0
		return [k[1] * f + 0.0005, k[2] * f + 0.0005, k[3], k[4]]
	if y >= keys[-1][0]:
		var k: Array = keys[-1]
		var f := sqrt(maxf(0.0, 1.0 - pow((y - keys[-1][0]) / maxf(close1, 0.0001), 2.0))) if close1 > 0.0 else 1.0
		return [k[1] * f + 0.0005, k[2] * f + 0.0005, k[3], k[4]]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if y <= b[0]:
			var t := smoothstep(0.0, 1.0, (y - a[0]) / (b[0] - a[0]))
			return [lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t), lerpf(a[4], b[4], t)]
	var k: Array = keys[-1]
	return [k[1], k[2], k[3], k[4]]


## A point on a trunk's surface (for things that lie on it): angle `u`, height `y`, `lift` out from it.
static func on_trunk(keys: Array, u: float, y: float, lift := 0.0) -> Vector3:
	var k := section(keys, y)
	var p := sq(u, k[0], k[1], k[3])
	var base := Vector3(p.x, y, p.y + k[2])
	return base + trunk_normal(keys, u, y) * lift


static func trunk_normal(keys: Array, u: float, y: float) -> Vector3:
	var e := 0.002
	var pu := _tp(keys, u + e, y) - _tp(keys, u - e, y)
	var pv := _tp(keys, u, y + e) - _tp(keys, u, y - e)
	var n := pu.cross(pv).normalized()
	var k := section(keys, y)
	var c := Vector3(0, y, k[2])
	return n if n.dot(_tp(keys, u, y) - c) > 0.0 else -n


static func _tp(keys: Array, u: float, y: float) -> Vector3:
	var k := section(keys, y)
	var p := sq(u, k[0], k[1], k[3])
	return Vector3(p.x, y, p.y + k[2])


## A limb: a tapered round bar from the origin down -y to -`length`, radius `r0` to `r1`, front to
## back `depth` of its width, each end rounded over in a half-sphere (so a joint stays round
## whichever way it bends).
static func limb(length: float, r0: float, r1: float, depth := 1.0, nu := 20, nv := 22) -> ArrayMesh:
	var keys := [[-length, r1, r1 * depth, 0.0, 2.0], [0.0, r0, r0 * depth, 0.0, 2.0]]
	return trunk(keys, nu, nv, r1, r0)


## A profile [[y, r], ...] turned round y (`depth` squashes it front to back, `dz` shifts it), shut
## at both ends (a thin rounded cap: no ring to see into).
static func lathe(profile: Array, nu := 24, depth := 1.0, dz := 0.0) -> ArrayMesh:
	var keys := []
	for p in profile:
		keys.append([p[0], p[1], p[1] * depth, dz, 2.0])
	var cap0 := minf(0.004, float(profile[0][1]) * 0.5)
	var cap1 := minf(0.004, float(profile[-1][1]) * 0.5)
	return trunk(keys, nu, maxi(profile.size() * 3, 6) + 4, cap0, cap1)


## A tube along `path`: a round section `r` (or flat: `w` wide, `r` thick, its flat side facing
## `ups[i]`), `n` sides. Ends left open unless `cap`.
static func tube(path: Array, r: float, n := 8, w := 0.0, ups := [], cap := true) -> ArrayMesh:
	var pts := PackedVector3Array()
	var ins := PackedVector3Array()
	var tris := PackedInt32Array()
	var count := path.size()
	var prev_side := Vector3.ZERO
	for i in count:
		var p: Vector3 = path[i]
		var t: Vector3 = ((path[mini(i + 1, count - 1)] as Vector3) - (path[maxi(i - 1, 0)] as Vector3)).normalized()
		var up: Vector3 = ups[i] if i < ups.size() else Vector3.UP
		if absf(up.dot(t)) > 0.98:
			up = Vector3.FORWARD if absf(t.z) < 0.9 else Vector3.RIGHT
		var side := t.cross(up).normalized()
		if prev_side != Vector3.ZERO and side.dot(prev_side) < 0.0 and ups.is_empty():
			side = -side
		prev_side = side
		var nup := side.cross(t).normalized()
		for k in n:
			var a := TAU * k / n
			var off: Vector3
			if w > 0.0:   # a flat strap: a stadium section
				var q := sq(a, w / 2.0, r / 2.0, 4.0)
				off = side * q.x - nup * q.y
			else:
				off = side * cos(a) * r + nup * sin(a) * r
			pts.append(p + off)
			ins.append(p)
	for i in count - 1:
		for k in n:
			var k1 := (k + 1) % n
			tris.append_array([i * n + k, i * n + k1, (i + 1) * n + k1, i * n + k, (i + 1) * n + k1, (i + 1) * n + k])
	if cap:
		for e in [0, count - 1]:
			var c := pts.size()
			var pe: Vector3 = path[e]
			var dir: Vector3 = (pe - (path[1] if e == 0 else path[count - 2])).normalized()
			pts.append(pe + dir * minf(r, 0.004))
			ins.append(pe - dir * r)
			for k in n:
				tris.append_array([c, e * n + k, e * n + (k + 1) % n])
	return build(pts, tris, ins)


## A thin piece lying on a surface: fn(u, v) -> [point, outward normal] over the patch, `lift` off
## it to its underside (negative sinks it in a little, so no seam shows) and `thick` thick, its
## top's edge rounded down by `round` of the patch. Closed all round.
static func slab(fn: Callable, u0: float, u1: float, v0: float, v1: float, nu: int, nv: int, lift: float, thick: float, round := 0.25) -> ArrayMesh:
	var pts := PackedVector3Array()
	var ins := PackedVector3Array()
	var tris := PackedInt32Array()
	var cols := nu + 1
	for layer in 2:   # top, then underside
		for j in nv + 1:
			for i in cols:
				var u := float(i) / nu
				var v := float(j) / nv
				var e := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))   # (how far in from the edge)
				var dome := smoothstep(0.0, round, e) if round > 0.0 else 1.0
				var s: Array = fn.call(lerpf(u0, u1, u), lerpf(v0, v1, v))
				var p: Vector3 = s[0]
				var n: Vector3 = s[1]
				var h := lift + (thick * (0.35 + 0.65 * dome) if layer == 0 else 0.0)
				pts.append(p + n * h)
				ins.append(p + n * (lift - 0.05) if layer == 0 else p + n * (lift + thick + 0.05))
	var off := cols * (nv + 1)
	for j in nv:
		for i in nu:
			var a := j * cols + i
			tris.append_array([a, a + 1, a + cols + 1, a, a + cols + 1, a + cols])
			tris.append_array([off + a, off + a + cols + 1, off + a + 1, off + a, off + a + cols, off + a + cols + 1])
	var rim := []   # the edge, all the way round
	for i in nu:
		rim.append(i)
	for j in nv:
		rim.append(j * cols + nu)
	for i in range(nu, 0, -1):
		rim.append(nv * cols + i)
	for j in range(nv, 0, -1):
		rim.append(j * cols)
	var base := pts.size()
	for k in rim.size():   # its own vertices, facing out sideways (a crisp edge)
		var t: int = rim[k]
		pts.append(pts[t])
		pts.append(pts[off + t])
		var c := (pts[t] + pts[off + t]) / 2.0
		var mid: Vector3 = fn.call(lerpf(u0, u1, 0.5), lerpf(v0, v1, 0.5))[0]
		var lean := (c - mid)
		ins.append(c - lean * 0.2)
		ins.append(c - lean * 0.2)
	for k in rim.size():
		var k1 := (k + 1) % rim.size()
		var a := base + k * 2
		var b := base + k1 * 2
		tris.append_array([a, b, b + 1, a, b + 1, a + 1])
	return build(pts, tris, ins)


## The surface function of an ellipsoid (centre `c`, radii `r`) for slab(): u is the angle round
## from the front (-z) toward +x, v the angle up from the equator.
static func ellipsoid_fn(c: Vector3, r: Vector3) -> Callable:
	return func(u: float, v: float) -> Array:
		var d := Vector3(sin(u) * cos(v), sin(v), -cos(u) * cos(v))
		var p := c + d * r
		var n := Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized()
		return [p, n]


## The surface function of a trunk for slab(): u the angle (0 = +x, PI/2 = front), v the height.
static func trunk_fn(keys: Array) -> Callable:
	return func(u: float, y: float) -> Array:
		return [_tp(keys, u, y), trunk_normal(keys, u, y)]


## The surface function of a limb (as limb() makes it) for slab(): u round from +x, v down it (0..length).
static func limb_fn(length: float, r0: float, r1: float, depth := 1.0) -> Callable:
	var keys := [[-length, r1, r1 * depth, 0.0, 2.0], [0.0, r0, r0 * depth, 0.0, 2.0]]
	return func(u: float, v: float) -> Array:
		return [_tp(keys, u, -v), trunk_normal(keys, u, -v)]


## A box with its edges and corners rounded by `rad` (pouches, packs, radios): lofted up y.
static func rbox(size: Vector3, rad: float, nu := 20) -> ArrayMesh:
	var hx := size.x / 2.0
	var hz := size.z / 2.0
	var hy := size.y / 2.0 - rad
	var p := clampf(2.0 + 10.0 * (1.0 - rad / minf(hx, hz)), 2.2, 9.0)
	var keys := [[-hy, hx, hz, 0.0, p], [hy, hx, hz, 0.0, p]]
	return trunk(keys, nu, 10, rad, rad)
