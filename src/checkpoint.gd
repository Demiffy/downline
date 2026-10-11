# The checkpoint as a whole site (level._checkpoint builds its core: platform, reclamation hall,
# shredder, shop, gate). This lays out everything round it: a basin ringed by banded rock ridges,
# the main line coming in and out through tunnel portals, and the Bureau's works filling the
# floor: the head office over a parking lot, a container terminal, the scrap works (crusher,
# conveyor, stacks), the classification yard with its repair shed, a fuel depot. The moving parts
# (people, vehicles, the shunter, cranes, smoke) are yard_life.gd's.
#   x runs along the main line (the train leaves toward +x); +z is the hall side.
extends RefCounted

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")

const X_EDGE := 172.0      # the ridges the line tunnels through
const Z_NORTH := 150.0
const Z_SOUTH := -128.0
const FAR_LINE := -78.0    # the through line at the far side of the yard (yard_life runs trains on it)
const SIDINGS := [-24.0, -30.0, -36.0, -42.0, -48.0, -54.0]
const SHUNT_Z := -24.0     # the siding the shunter works (kept clear of standing wagons between these)
const SHUNT_X := Vector2(-112.0, -8.0)
const CONV_A := Vector3(86, 0.5, 52)    # the conveyor, foot to head
const CONV_B := Vector3(112, 11.0, 84)
const STACKS := [Vector3(116, 34.5, 96), Vector3(125, 34.5, 96)]
const CC := [Color(0.25, 0.4, 0.55), Color(0.65, 0.25, 0.15), Color(0.3, 0.45, 0.3), Color(0.75, 0.6, 0.2), Color(0.5, 0.5, 0.5), Color(0.2, 0.25, 0.3), Color(0.55, 0.35, 0.2)]


static func build(lv: Node3D, rng: RandomNumberGenerator) -> void:
	_ground(lv)
	_edges(lv, rng)
	_main_line(lv)
	_yard_south(lv, rng)
	_admin(lv, rng)
	_terminal(lv, rng)
	_scrapworks(lv, rng)
	_fuel(lv, rng)
	_lights(lv)


# --- the ground and its edges ---------------------------------------------------------------------

static func _ground(lv: Node3D) -> void:
	A.box(lv, Vector3(560, 1.0, 460), Vector3(0, -0.5, 10), "sand", Color(0.8, 0.72, 0.62), true, 3.0)
	# Pavement: asphalt roads and lots, concrete aprons, gravel round the tracks.
	A.box(lv, Vector3(300, 0.05, 66), Vector3(-5, 0.025, -48), "gravel", Color(0.75, 0.72, 0.68), true, 2.0)   # the yard's ballast bed
	A.box(lv, Vector3(110, 0.05, 50), Vector3(0, 0.03, 70), "asphalt", Color.WHITE, true, 4.0)    # admin + parking
	A.box(lv, Vector3(105, 0.05, 92), Vector3(-102, 0.03, 58), "concrete", Color(0.7, 0.68, 0.64), true, 4.0)   # container terminal
	A.box(lv, Vector3(105, 0.05, 92), Vector3(102, 0.03, 58), "dirt", Color(0.9, 0.85, 0.8), true, 3.0)   # scrap works
	A.box(lv, Vector3(320, 0.05, 9), Vector3(-5, 0.035, 40.5), "asphalt", Color.WHITE, true, 4.0)   # the ring road
	for x in [-52.0, 52.0]:
		A.box(lv, Vector3(9, 0.05, 100), Vector3(x, 0.036, 64), "asphalt", Color.WHITE, true, 4.0)
	for x in range(-150, 150, 12):   # dashed centre line along the ring road
		A.box(lv, Vector3(5.0, 0.01, 0.18), Vector3(x + 3.0, 0.065, 40.5), "cream", Color(0.95, 0.85, 0.3), false, 1.0)
	for k in 12:   # parking bays
		A.box(lv, Vector3(0.15, 0.01, 5.0), Vector3(-33.0 + k * 3.2, 0.06, 52.5), "cream", Color(0.92, 0.92, 0.88), false, 1.0)


## Banded rock all round: long ridges with mesas and spires in front of them to break the line,
## talus at their feet, and a far skyline of mesas fading in the haze.
static func _edges(lv: Node3D, rng: RandomNumberGenerator) -> void:
	var rock := Color(0.95, 0.9, 0.85)
	# A solid back to each side (so nothing shows through), well behind the faces built in front.
	for s in [-1.0, 1.0]:
		var x: float = s * (X_EDGE + 16.0)
		A.wall(lv, Z_SOUTH - 30.0, Z_NORTH + 30.0, x, 30.0, 24.0, [[0.0, 7.6, 0.0, 7.0], [FAR_LINE, 7.6, 0.0, 7.0]], "mesa", rock.darkened(0.15), false, 0.0, true, 11.0)
		for z in [0.0, FAR_LINE]:
			_portal(lv, Vector3(s * X_EDGE, 0, z), s)
			for side in [-1.0, 1.0]:   # the cliff face round the mouth, cut back square
				A.box(lv, Vector3(10.0, 26.0, 12.0), Vector3(s * (X_EDGE + 5.5), 13.0, z + side * 10.5), "mesa", rock, true, 11.0)
			A.box(lv, Vector3(10.0, 18.0, 9.2), Vector3(s * (X_EDGE + 5.5), 17.5, z), "mesa", rock, true, 11.0)
	for side in [[Z_NORTH, 1.0], [Z_SOUTH, -1.0]]:
		A.wall(lv, -X_EDGE - 40.0, X_EDGE + 40.0, side[0] + side[1] * 20.0, 28.0, 24.0, [], "mesa", rock.darkened(0.15), true, 0.0, true, 11.0)
	# The faces: rock in blocks of every size, set at angles, staggered in and out, some leaning,
	# stepped up in ledges; then fallen rock heaped along their feet.
	var runs := [[Vector3(-X_EDGE, 0, Z_NORTH), Vector3(X_EDGE, 0, Z_NORTH), Vector3(0, 0, -1)], [Vector3(-X_EDGE, 0, Z_SOUTH), Vector3(X_EDGE, 0, Z_SOUTH), Vector3(0, 0, 1)],
		[Vector3(-X_EDGE, 0, Z_SOUTH), Vector3(-X_EDGE, 0, Z_NORTH), Vector3(1, 0, 0)], [Vector3(X_EDGE, 0, Z_SOUTH), Vector3(X_EDGE, 0, Z_NORTH), Vector3(-1, 0, 0)]]
	for run in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var inward: Vector3 = run[2]
		var along := (b - a).normalized()
		var t := 0.0
		var total := a.distance_to(b)
		while t < total:
			var w := rng.randf_range(12.0, 26.0)
			var p: Vector3 = a + along * (t + w / 2.0)
			t += w * rng.randf_range(0.55, 0.85)
			if absf(inward.x) > 0.5 and (absf(p.z) < 16.0 or absf(p.z - FAR_LINE) < 16.0):
				continue   # (clear of the tunnel mouths)
			var h := rng.randf_range(14.0, 34.0)
			var d := rng.randf_range(12.0, 22.0)
			var back := rng.randf_range(-2.0, 7.0)
			var blk := A.box(lv, Vector3(w, h, d) if absf(along.x) > 0.5 else Vector3(d, h, w), p - inward * (back + d / 2.0 - 4.0) + Vector3(0, h / 2.0 - 1.0, 0), "mesa", rock.darkened(rng.randf() * 0.18), true, 11.0)
			blk.rotation = Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.35, 0.35), rng.randf_range(-0.05, 0.05))
			if rng.randf() < 0.55:   # a ledge stepped back on top
				var h2 := rng.randf_range(5.0, 14.0)
				var top := A.box(lv, Vector3(w * 0.7, h2, d * 0.7) if absf(along.x) > 0.5 else Vector3(d * 0.7, h2, w * 0.7), p - inward * (back + d / 2.0 + 1.0) + Vector3(0, h + h2 / 2.0 - 1.5, 0), "mesa", rock.darkened(rng.randf() * 0.15), false, 11.0)
				top.rotation.y = rng.randf_range(-0.3, 0.3)
			for k in rng.randi_range(1, 2):   # scree at its foot
				var q := p + inward * rng.randf_range(4.0, 9.0) + along * rng.randf_range(-w / 2.0, w / 2.0)
				P.boulder(lv, q, Vector3(rng.randf_range(3, 7), rng.randf_range(1.5, 3.5), rng.randf_range(3, 6)), rng, Color(0.82, 0.72, 0.64), false)
			if rng.randf() < 0.35:
				P.boulder(lv, p + inward * rng.randf_range(6.0, 12.0), Vector3(rng.randf_range(1.5, 4), rng.randf_range(1, 3), rng.randf_range(1.5, 4)), rng, Color(0.85, 0.75, 0.68), true)
	for k in 6:   # spires standing out from the walls
		P.rock_spire(lv, Vector3(rng.randf_range(-140, 140), 0, Z_NORTH - 10.0 if k % 2 == 0 else Z_SOUTH + 10.0), rng, Color(0.85, 0.75, 0.68))
	# The skyline: mesas a long way off in every direction.
	for k in 16:
		var ang := TAU * k / 16.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(320, 420)
		P.mesa(lv, Vector3(cos(ang) * r, 0, sin(ang) * r * 0.85), rng, Color(0.82, 0.72, 0.64))
	# You stay inside.
	for s in [-1.0, 1.0]:
		B.invisible_wall(lv, Vector3(2, 40, 420), Vector3(s * (X_EDGE - 4.0), 20, 10))
	B.invisible_wall(lv, Vector3(420, 40, 2), Vector3(0, 20, Z_NORTH - 6.0))
	B.invisible_wall(lv, Vector3(420, 40, 2), Vector3(0, 20, Z_SOUTH + 6.0))


## A tunnel mouth: a concrete portal with its name cut over the arch, a lamp, and the dark beyond.
static func _portal(lv: Node3D, at: Vector3, s: float) -> void:
	var c := Color(0.62, 0.6, 0.56)
	var face := at.x
	for z in [-4.6, 4.6]:
		A.box(lv, Vector3(2.0, 8.5, 1.6), Vector3(face, 4.25, at.z + z), "concrete", c, true, 2.0)
	A.box(lv, Vector3(2.2, 2.6, 11.0), Vector3(face, 8.2, at.z), "concrete", c, true, 2.0)
	A.box(lv, Vector3(2.3, 0.4, 11.4), Vector3(face, 9.6, at.z), "concrete", c.darkened(0.1), false, 2.0)
	var nm := B.label(lv, "BRM  TUNNEL  %s" % ("EAST" if s > 0 else "WEST"), Vector3(face - s * 1.16, 8.2, at.z), 60, Color(0.25, 0.23, 0.2), "stencil", 0.01)
	nm.rotation.y = -PI / 2.0 * s
	A.box(lv, Vector3(30.0, 7.4, 8.0), Vector3(face + s * 16.0, 3.7, at.z), "rubber", Color(0.05, 0.05, 0.05), false, 1.0)   # the dark inside
	A.box(lv, Vector3(30.0, 0.4, 9.2), Vector3(face + s * 16.0, 7.2, at.z), "concrete", c.darkened(0.5), false, 2.0)
	A.wall_lamp(lv, Vector3(face - s * 1.05, 6.8, at.z + 3.2), Vector3(-s, 0, 0), Color(1, 0.85, 0.6), 1.2, false)


static func _track(lv: Node3D, z: float, x0: float, x1: float) -> void:
	var ln := x1 - x0
	var xc := (x0 + x1) / 2.0
	A.box(lv, Vector3(ln, 0.12, 3.2), Vector3(xc, 0.06, z), "gravel", Color(0.7, 0.66, 0.6), false, 1.5)
	for k in int(ln / 2.2):
		A.box(lv, Vector3(0.26, 0.08, 2.5), Vector3(x0 + 1.1 + k * 2.2, 0.13, z), "wood", Color(0.45, 0.4, 0.35), false, 1.0)
	for dz in [-0.72, 0.72]:
		A.box(lv, Vector3(ln, 0.13, 0.08), Vector3(xc, 0.22, z + dz), "metal", Color(0.62, 0.6, 0.58), false, 1.0)


## The main line out to both tunnels (the core's own rails stop at ±100).
static func _main_line(lv: Node3D) -> void:
	for s in [-1.0, 1.0]:
		_track(lv, 0.0, minf(s * 99.0, s * (X_EDGE + 30.0)), maxf(s * 99.0, s * (X_EDGE + 30.0)))
	_track(lv, FAR_LINE, -X_EDGE - 30.0, X_EDGE + 30.0)
	for x in range(-150, 151, 25):   # catenary-less line poles with their wires
		for z in [5.0, FAR_LINE - 5.0]:
			A.cyl(lv, 0.12, 8.0, Vector3(x, 4.0, z), "wood", Color(0.45, 0.38, 0.3), false)
			A.box(lv, Vector3(0.12, 0.12, 1.6), Vector3(x, 7.6, z), "wood", Color(0.45, 0.38, 0.3), false, 1.0)


# --- the classification yard (south of the main line) -----------------------------------------------

static func _yard_south(lv: Node3D, rng: RandomNumberGenerator) -> void:
	for z in SIDINGS:
		_track(lv, z, -140.0, 130.0)
	# Wagons standing on the sidings, in cuts with gaps between.
	for z in SIDINGS:
		var x := -135.0 + rng.randf_range(0, 20)
		while x < 120.0:
			if rng.randf() < 0.22 or (z == SHUNT_Z and x > SHUNT_X.x - 6.0 and x < SHUNT_X.y + 6.0):
				x += rng.randf_range(12, 30) if z != SHUNT_Z else 11.2
				continue
			var kind := rng.randi() % 4
			match kind:
				0: P.boxcar(lv, Vector3(x, 0.06, z), 0.0, rng)
				1: _tank_car(lv, Vector3(x, 0.06, z), rng)
				2: _flatcar(lv, Vector3(x, 0.06, z), rng)
				3: _hopper(lv, Vector3(x, 0.06, z), rng)
			x += 11.2
	# The repair shed straddling two sidings: a long steel shed, open at both ends.
	_shed(lv, Vector3(80, 0, -39), 48.0, 22.0, 11.0, "WAGON REPAIR")
	# Signal gantries over the throat, the switchman's tower.
	for x in [-140.0, 128.0]:
		_signal_gantry(lv, Vector3(x, 0, -39), 36.0)
	_tower(lv, Vector3(-60.0, 0, -62.0), "YARD CONTROL")
	P.tin_shed(lv, Vector3(30.0, 0.06, -63.0), 0.0, rng)
	P.tin_shed(lv, Vector3(-100.0, 0.06, -63.0), PI, rng)


static func _bogies(r: Node3D, ln: float) -> void:
	for sx in [-1.0, 1.0]:
		var bx: float = sx * (ln / 2.0 - 1.8)
		A.box(r, Vector3(2.4, 0.5, 1.9), Vector3(bx, 0.55, 0), "metal", Color(0.2, 0.2, 0.2), false, 0.5)
		for wx in [-0.7, 0.7]:
			for wz in [-0.72, 0.72]:
				A.cyl(r, 0.42, 0.12, Vector3(bx + wx, 0.48, wz), "metal", Color(0.25, 0.24, 0.23), false, "z")


static func _tank_car(lv: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var r := P._root(lv, at, 0.0, Vector3(10.4, 4.2, 3.0))
	var c: Color = [Color(0.18, 0.18, 0.18), Color(0.75, 0.72, 0.65), Color(0.45, 0.2, 0.15)][rng.randi() % 3]
	A.box(r, Vector3(10.2, 0.3, 2.6), Vector3(0, 1.05, 0), "metal", Color(0.2, 0.2, 0.2), false, 0.6)
	A.cyl(r, 1.35, 9.6, Vector3(0, 2.55, 0), "enamel", c, false, "x")
	for sx in [-1.0, 1.0]:
		A.sphere(r, 1.35, Vector3(sx * 4.8, 2.55, 0), "enamel", c).scale = Vector3(0.35, 1, 1)
	A.cyl(r, 0.45, 0.4, Vector3(0, 4.0, 0), "metal", c.darkened(0.2), false)   # the dome
	A.box(r, Vector3(2.0, 0.04, 0.5), Vector3(0, 3.92, 0.6), "grate", Color.WHITE, false, 0.4)
	B.label(r, ["BRM FUEL", "CORROSIVE", "WATER", "OIL"][rng.randi() % 4], Vector3(0, 2.55, 1.37), 40, Color(0.9, 0.88, 0.8) if c.v < 0.5 else Color(0.15, 0.13, 0.11), "stencil", 0.012)
	_bogies(r, 10.2)


static func _flatcar(lv: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var r := P._root(lv, at, 0.0, Vector3(10.4, 1.4, 3.0))
	A.box(r, Vector3(10.4, 0.35, 2.7), Vector3(0, 1.1, 0), "rust", Color(0.7, 0.65, 0.6), false, 0.8)
	_bogies(r, 10.4)
	if rng.randf() < 0.8:
		P.shipping_container(r, Vector3(0, 1.28, 0), PI / 2.0, CC[rng.randi() % CC.size()], rng, true)


static func _hopper(lv: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var r := P._root(lv, at, 0.0, Vector3(10.2, 3.8, 3.0))
	var c: Color = [Color(0.45, 0.3, 0.2), Color(0.3, 0.32, 0.3), Color(0.5, 0.45, 0.3)][rng.randi() % 3]
	A.box(r, Vector3(10.0, 2.3, 2.9), Vector3(0, 2.45, 0), "riveted", c, false, 1.2)
	for k in 3:   # the hoppers underneath
		var h := A.prism(r, Vector3(2.6, 0.9, 2.6), Vector3(-3.0 + k * 3.0, 0.9, 0), "riveted", c.darkened(0.15), Vector3(PI, 0, 0), 1.2)
		h.scale = Vector3(1, 1, 1)
	A.box(r, Vector3(9.8, 0.3, 2.7), Vector3(0, 3.6, 0), "rust", Color(0.55, 0.4, 0.3), false, 1.0)   # (a load of ore heaped in it)
	_bogies(r, 10.0)


## A long open-ended steel shed: columns, a pitched roof of corrugated sheet, skylights, its name.
static func _shed(lv: Node3D, at: Vector3, ln: float, wid: float, h: float, title: String) -> void:
	var c := Color(0.72, 0.7, 0.66)
	for sz in [-1.0, 1.0]:
		A.wall(lv, at.x - ln / 2.0, at.x + ln / 2.0, at.z + sz * wid / 2.0, h, 0.3, [], "corrugated", c, true, 0.0, true, 2.0)
		for k in 9:
			var x := at.x - ln / 2.0 + k * ln / 8.0
			A.box(lv, Vector3(0.4, h, 0.4), Vector3(x, h / 2.0, at.z + sz * (wid / 2.0 - 0.4)), "metal", Color(0.4, 0.42, 0.4), false, 0.8)
		var roof := A.box(lv, Vector3(ln + 1.0, 0.25, wid / 2.0 + 1.2), Vector3(at.x, h + 1.6, at.z + sz * wid / 4.0), "corrugated", c.darkened(0.15), true, 2.0)
		roof.rotation.x = sz * 0.28
	for x in [at.x - ln / 4.0, at.x + ln / 4.0]:
		A.glow(lv, Vector3(6.0, 0.05, wid * 0.6), Vector3(x, h - 0.2, at.z), Color(1, 0.88, 0.7), 0.5)
	var sg := B.label(lv, title, Vector3(at.x, h + 0.6, at.z - wid / 2.0 - 0.2), 120, Color(0.9, 0.86, 0.75), "plate", 0.02)
	sg.rotation.y = PI
	for k in 3:   # lamps inside
		B.omni(lv, Vector3(at.x - ln / 3.0 + k * ln / 3.0, h - 1.5, at.z), Color(1, 0.85, 0.65), 2.0, 18.0)


static func _signal_gantry(lv: Node3D, at: Vector3, span: float) -> void:
	var g := Color(0.3, 0.32, 0.3)
	for sz in [-1.0, 1.0]:
		A.box(lv, Vector3(0.6, 9.0, 0.6), Vector3(at.x, 4.5, at.z + sz * span / 2.0), "metal", g, true, 0.8)
	A.box(lv, Vector3(0.8, 0.8, span + 0.6), Vector3(at.x, 9.0, at.z), "metal", g, false, 0.8)
	for z in SIDINGS:   # a signal head over each road
		A.box(lv, Vector3(0.5, 1.4, 0.6), Vector3(at.x, 8.0, z), "enamel", Color(0.1, 0.1, 0.1), false, 0.4)
		var lit := Color(0.2, 1.0, 0.3) if int(absf(z)) % 12 == 0 else Color(1.0, 0.2, 0.15)
		A.glow(lv, Vector3(0.52, 0.22, 0.22), Vector3(at.x, 8.3 if lit.g > 0.5 else 7.8, z), lit, 3.0)


## A control tower: a concrete stalk with a glazed cab on top, lit inside.
static func _tower(lv: Node3D, at: Vector3, title: String) -> void:
	A.box(lv, Vector3(4.0, 12.0, 4.0), at + Vector3(0, 6.0, 0), "concrete", Color(0.7, 0.68, 0.64), true, 2.0)
	A.box(lv, Vector3(7.0, 0.4, 7.0), at + Vector3(0, 12.2, 0), "concrete", Color(0.6, 0.58, 0.55), true, 2.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			A.box(lv, Vector3(0.2, 3.0, 0.2), at + Vector3(sx * 3.3, 13.9, sz * 3.3), "metal", Color(0.3, 0.3, 0.3), false, 0.5)
	A.glow(lv, Vector3(6.4, 2.6, 6.4), at + Vector3(0, 13.8, 0), Color(1.0, 0.85, 0.6), 0.6)   # the lit glazing
	A.box(lv, Vector3(7.4, 0.5, 7.4), at + Vector3(0, 15.6, 0), "metal", Color(0.35, 0.35, 0.33), false, 1.0)
	B.label(lv, title, at + Vector3(0, 10.5, -2.02), 60, Color(0.25, 0.23, 0.2), "stencil", 0.012).rotation.y = PI
	for k in 2:
		A.box(lv, Vector3(1.2, 0.2, 2.5), at + Vector3(2.6, 1.0 + k * 2.4, 0), "grate", Color.WHITE, false, 0.5)


# --- the head office and its lot (north) -----------------------------------------------------------

static func _admin(lv: Node3D, rng: RandomNumberGenerator) -> void:
	_office(lv, Vector3(0, 0, 80), Vector3(44, 12.5, 14), rng)
	_clock_tower(lv, Vector3(26.5, 0, 74.5))
	# The canteen and the bunkhouses.
	_block(lv, Vector3(-36, 0, 86), Vector3(18, 4.5, 10), Color(0.75, 0.68, 0.55), "CANTEEN", rng)
	for k in 3:
		_block(lv, Vector3(36 + k * 0.0, 0, 62 + k * 12.0) + Vector3(6, 0, 0), Vector3(14, 3.6, 7), Color(0.55, 0.6, 0.55), "BUNKHOUSE %d" % (k + 1), rng)
	# The lot: trucks parked in the bays, a fuel bowser, a flagpole row.
	for k in 12:
		if rng.randf() < 0.65:
			truck(lv, Vector3(-31.4 + k * 3.2, 0.05, 53.5), PI + rng.randf_range(-0.04, 0.04), rng)   # (nose out of its bay)
	for k in 3:
		var fx := -12.0 + k * 12.0
		A.cyl(lv, 0.08, 14.0, Vector3(fx, 7.0, 66.0), "metal", Color(0.8, 0.8, 0.8), false)
		var flag := A.box(lv, Vector3(2.4, 1.4, 0.03), Vector3(fx + 1.2, 13.0, 66.0), "canvas", [Color(0.7, 0.2, 0.12), Color(0.85, 0.65, 0.15), Color(0.2, 0.3, 0.5)][k], false, 0.5)
		flag.set_meta("flag", true)
		flag.set_meta("live", true)
	_mast(lv, Vector3(-46, 0, 76), 46.0)
	P.water_tower(lv, Vector3(48.0, 0.06, 88.0))


## A Bureau office block: storeys of windows (some lit), a recessed entrance with steps and a sign,
## parapet, rooftop plant, downpipes.
static func _office(lv: Node3D, at: Vector3, size: Vector3, rng: RandomNumberGenerator) -> void:
	var c := Color(0.78, 0.74, 0.66)
	A.box(lv, size, at + Vector3(0, size.y / 2.0, 0), "concrete", c, true, 3.0)
	A.box(lv, Vector3(size.x + 0.6, 0.6, size.z + 0.6), at + Vector3(0, size.y + 0.3, 0), "concrete", c.darkened(0.12), false, 3.0)
	var floors := int(size.y / 3.8)
	for f in floors:
		var y := 2.2 + f * 3.8
		A.box(lv, Vector3(size.x + 0.12, 0.25, 0.3), at + Vector3(0, y - 1.3, -size.z / 2.0), "concrete", c.darkened(0.2), false, 2.0)   # floor band
		for k in int(size.x / 2.8):
			var x := -size.x / 2.0 + 1.6 + k * 2.8
			if f == 0 and absf(x) < 4.0:
				continue
			for side in [-1.0, 1.0]:
				var lit := rng.randf() < 0.45
				var w := Vector3(1.6, 1.8, 0.08)
				var pos := at + Vector3(x, y, side * (size.z / 2.0 + 0.02))
				if lit:
					A.glow(lv, w, pos, Color(1.0, 0.86, 0.62), 0.9)
				else:
					A.box(lv, w, pos, "metal", Color(0.12, 0.14, 0.16), false, 0.5)
				A.box(lv, Vector3(1.8, 0.12, 0.25), pos + Vector3(0, -0.98, side * 0.08), "concrete", c.darkened(0.1), false, 1.0)   # sill
	# The entrance: a dark recess, glass doors lit from inside, steps, the canopy and the sign.
	var door := at + Vector3(0, 0, -size.z / 2.0)
	A.box(lv, Vector3(6.0, 3.4, 0.2), door + Vector3(0, 1.7, -0.05), "metal", Color(0.15, 0.15, 0.15), false, 1.0)
	A.glow(lv, Vector3(4.0, 2.6, 0.1), door + Vector3(0, 1.4, -0.12), Color(1.0, 0.9, 0.7), 0.7)
	A.box(lv, Vector3(8.0, 0.3, 3.0), door + Vector3(0, 3.6, -1.4), "concrete", c.darkened(0.25), false, 2.0)
	for k in 3:
		A.box(lv, Vector3(9.0, 0.18, 1.0 - k * 0.3), door + Vector3(0, 0.09 + k * 0.18, -0.7 - (2 - k) * 0.3), "concrete", c.darkened(0.15), true, 2.0)
	var sg := B.label(lv, "BUREAU OF RECLAIMED MATERIALS", door + Vector3(0, size.y - 1.0, -0.35), 110, Color(0.9, 0.86, 0.75), "plate", 0.02)
	sg.rotation.y = PI
	var sub := B.label(lv, "DISTRICT OFFICE  -  CHECKPOINT 4", door + Vector3(0, 4.4, -0.32), 50, Color(0.85, 0.8, 0.7), "stencil", 0.012)
	sub.rotation.y = PI
	B.omni(lv, door + Vector3(0, 3.2, -2.0), Color(1, 0.86, 0.65), 1.5, 9.0)
	# Rooftop plant and the pipes down the walls.
	for k in 3:
		A.box(lv, Vector3(3.0, 1.6, 2.4), at + Vector3(-12.0 + k * 12.0, size.y + 0.8, 2.0), "metal", Color(0.55, 0.56, 0.55), false, 1.0)
		A.cyl(lv, 0.6, 0.3, at + Vector3(-12.0 + k * 12.0, size.y + 1.75, 2.0), "metal", Color(0.4, 0.4, 0.4), false)
	for x in [-size.x / 2.0 + 0.3, size.x / 2.0 - 0.3]:
		A.cyl(lv, 0.1, size.y, at + Vector3(x, size.y / 2.0, -size.z / 2.0 - 0.15), "metal", Color(0.45, 0.45, 0.42), false)


static func _clock_tower(lv: Node3D, at: Vector3) -> void:
	A.box(lv, Vector3(5, 22, 5), at + Vector3(0, 11, 0), "brick", Color(0.85, 0.7, 0.62), true, 2.0)
	A.box(lv, Vector3(5.8, 0.6, 5.8), at + Vector3(0, 22.3, 0), "concrete", Color(0.7, 0.66, 0.6), false, 2.0)
	A.prism(lv, Vector3(5.6, 3.5, 5.6), at + Vector3(0, 24.4, 0), "shingle", Color(0.5, 0.4, 0.35))
	var face := at + Vector3(0, 18.5, -2.52)
	A.cyl(lv, 1.7, 0.1, face, "cream", Color(0.95, 0.92, 0.84), false, "z")
	A.ring(lv, 1.8, 1.65, face + Vector3(0, 0, -0.06), "metal", Color(0.2, 0.2, 0.2), Vector3(PI / 2.0, 0, 0))
	for k in 12:
		var a := TAU * k / 12.0
		A.box(lv, Vector3(0.12, 0.35, 0.03), face + Vector3(sin(a) * 1.4, cos(a) * 1.4, -0.07), "metal", Color(0.1, 0.1, 0.1), false, 0.2, Vector3(0, 0, -a))
	var hands := Node3D.new()   # (yard_life turns them to the shift's hour)
	hands.name = "ClockHands"
	hands.set_meta("live", true)
	lv.add_child(hands)
	hands.position = face + Vector3(0, 0, -0.09)
	for k in 2:
		var hand := Node3D.new()
		hand.name = "H%d" % k
		hands.add_child(hand)
		A.box(hand, Vector3(0.12 if k == 0 else 0.08, 0.85 if k == 0 else 1.25, 0.03), Vector3(0, (0.85 if k == 0 else 1.25) * 0.4, -0.01 * k), "metal", Color(0.08, 0.08, 0.08), false, 0.2)


static func _block(lv: Node3D, at: Vector3, size: Vector3, c: Color, title: String, rng: RandomNumberGenerator) -> void:
	A.box(lv, size, at + Vector3(0, size.y / 2.0, 0), "siding", c, true, 2.0)
	var roof := A.box(lv, Vector3(size.x + 0.8, 0.2, size.z + 0.8), at + Vector3(0, size.y + 0.1, 0), "corrugated", Color(0.5, 0.48, 0.45), false, 2.0)
	roof.rotation.z = 0.04
	for k in int(size.x / 3.0):
		var x := -size.x / 2.0 + 1.5 + k * 3.0
		var lit := rng.randf() < 0.5
		var pos := at + Vector3(x, size.y * 0.55, -size.z / 2.0 - 0.02)
		if lit:
			A.glow(lv, Vector3(1.2, 1.0, 0.06), pos, Color(1.0, 0.85, 0.6), 0.8)
		else:
			A.box(lv, Vector3(1.2, 1.0, 0.06), pos, "metal", Color(0.12, 0.13, 0.14), false, 0.5)
	A.box(lv, Vector3(1.2, 2.2, 0.08), at + Vector3(size.x / 2.0 - 2.0, 1.1, -size.z / 2.0 - 0.03), "wood", Color(0.5, 0.4, 0.3), false, 0.6)
	var sg := B.label(lv, title, at + Vector3(0, size.y - 0.6, -size.z / 2.0 - 0.06), 60, Color(0.2, 0.18, 0.15), "stencil", 0.012)
	sg.rotation.y = PI


## A lattice radio mast with its red warning lamps (yard_life blinks the top one).
static func _mast(lv: Node3D, at: Vector3, h: float) -> void:
	var g := Color(0.75, 0.3, 0.2)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			A.seg(lv, at + Vector3(sx * 1.6, 0, sz * 1.6), at + Vector3(sx * 0.3, h, sz * 0.3), 0.08, 0.06, "paint", g)
	for k in int(h / 3.0):
		var y := k * 3.0
		var w := lerpf(1.6, 0.3, y / h)
		for e in 4:
			var a := Vector3(-w, y, -w).rotated(Vector3.UP, e * PI / 2.0)
			var b := Vector3(w, y + 3.0, -w).rotated(Vector3.UP, e * PI / 2.0) * Vector3(lerpf(1.0, 0.9, 0.1), 1, 1)
			A.seg(lv, at + a, at + b, 0.03, 0.03, "paint", g)
	var lamp := A.sphere(lv, 0.35, at + Vector3(0, h + 0.3, 0), "cream", Color(1, 0.15, 0.1), 6.0)
	lamp.name = "MastLamp"
	lamp.set_meta("live", true)
	A.sphere(lv, 0.25, at + Vector3(0, h * 0.5, 0.4), "cream", Color(1, 0.15, 0.1), 4.0)


## A lorry: cab, chassis, a box or flat bed, wheels. Parked here; yard_life drives some about.
static func truck(parent: Node, at: Vector3, yaw: float, rng: RandomNumberGenerator, solid := true) -> Node3D:
	var r := P._root(parent, at, yaw, Vector3(2.5, 3.2, 7.4) if solid else Vector3.ZERO)
	var cab: Color = [Color(0.85, 0.65, 0.15), Color(0.7, 0.2, 0.12), Color(0.25, 0.35, 0.5), Color(0.85, 0.85, 0.82)][rng.randi() % 4]
	A.box(r, Vector3(2.3, 0.35, 7.2), Vector3(0, 0.75, 0), "metal", Color(0.15, 0.15, 0.15), false, 0.6)
	A.box(r, Vector3(2.4, 1.8, 2.0), Vector3(0, 1.9, -2.6), "enamel", cab, false, 0.6)   # cab
	A.box(r, Vector3(2.3, 0.9, 0.08), Vector3(0, 2.3, -3.62), "metal", Color(0.1, 0.12, 0.14), false, 0.5)   # windscreen
	A.box(r, Vector3(2.0, 0.5, 0.1), Vector3(0, 1.2, -3.65), "grille", Color(0.6, 0.6, 0.6), false, 0.4)
	for sx in [-1.0, 1.0]:
		A.glow(r, Vector3(0.3, 0.2, 0.05), Vector3(sx * 0.9, 1.15, -3.68), Color(1, 0.95, 0.8), 1.5)
	if rng.randf() < 0.5:
		A.box(r, Vector3(2.45, 2.4, 4.8), Vector3(0, 2.15, 0.9), "corrugated", [Color(0.8, 0.78, 0.72), Color(0.4, 0.45, 0.5)][rng.randi() % 2], false, 1.0)
	else:
		A.box(r, Vector3(2.4, 0.15, 4.8), Vector3(0, 1.0, 0.9), "wood", Color(0.6, 0.5, 0.4), false, 0.8)
		for k in rng.randi_range(0, 2):
			P.bale(r, Vector3(-0.5 + k * 1.0, 1.08, 0.9 + k * 0.6), 0.9, rng)
	for wz in [-2.6, 1.0, 2.4]:
		for sx in [-1.0, 1.0]:
			A.cyl(r, 0.48, 0.35, Vector3(sx * 1.05, 0.48, wz), "rubber", Color.WHITE, false, "x")
	return r


# --- the container terminal (west) ----------------------------------------------------------------

static func _terminal(lv: Node3D, rng: RandomNumberGenerator) -> void:
	# Blocks of stacks with lanes between, highest in the middle.
	for bx in 4:
		for bz in 3:
			var x0 := -142.0 + bx * 22.0
			var z0 := 22.0 + bz * 28.0
			for i in 6:
				for j in 2:
					var h := rng.randi_range(1, 4)
					if rng.randf() < 0.12:
						continue
					for k in h:
						P.shipping_container(lv, Vector3(x0 + i * 2.6, 0.06 + k * 2.62, z0 + j * 6.4), rng.randf_range(-0.02, 0.02), CC[rng.randi() % CC.size()], rng)
	# The big gantry crane straddling the stacks (yard_life runs its trolley).
	var gx := -102.0
	var g := Color(0.85, 0.6, 0.12)
	for sz in [-1.0, 1.0]:
		var z: Variant = 58.0 + sz * 42.0
		A.box(lv, Vector3(110.0, 0.2, 0.4), Vector3(gx, 0.1, z), "metal", Color(0.4, 0.4, 0.4), false, 1.0)   # its rails
	var crane := Node3D.new()
	crane.name = "TerminalCrane"
	crane.set_meta("live", true)
	lv.add_child(crane)
	crane.position = Vector3(gx, 0, 58.0)
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			A.box(crane, Vector3(0.9, 18.0, 0.9), Vector3(sx * 4.5, 9.0, sz * 42.0), "enamel", g, false, 0.8)
		A.box(crane, Vector3(11.0, 1.2, 1.4), Vector3(0, 0.9, sz * 42.0), "enamel", g.darkened(0.3), false, 0.8)
	for sx in [-1.0, 1.0]:
		A.box(crane, Vector3(1.2, 2.0, 86.0), Vector3(sx * 4.5, 18.6, 0), "enamel", g, false, 1.0)
	var trolley := Node3D.new()
	trolley.name = "Trolley"
	crane.add_child(trolley)
	A.box(trolley, Vector3(10.0, 1.8, 4.0), Vector3(0, 17.8, 0), "enamel", g.darkened(0.15), false, 0.8)
	A.box(trolley, Vector3(2.6, 2.4, 2.4), Vector3(0, 15.6, -1.0), "metal", Color(0.3, 0.3, 0.3), false, 0.5)   # the cab
	A.glow(trolley, Vector3(2.4, 1.0, 0.05), Vector3(0, 15.9, -2.22), Color(1, 0.85, 0.6), 0.6)
	var spreader := Node3D.new()
	spreader.name = "Spreader"
	trolley.add_child(spreader)
	spreader.position.y = 12.0
	A.box(spreader, Vector3(2.6, 0.5, 6.2), Vector3.ZERO, "enamel", g, false, 0.5)
	for sx in [-1.0, 1.0]:
		A.seg(spreader, Vector3(sx * 0.8, 0.25, 0), Vector3(sx * 0.8, 5.0, 0), 0.03, 0.03, "metal", Color(0.2, 0.2, 0.2))


# --- the scrap works (east) -------------------------------------------------------------------------

static func _scrapworks(lv: Node3D, rng: RandomNumberGenerator) -> void:
	for p in [[Vector3(80, 0, 45), 4.0], [Vector3(118, 0, 60), 3.4], [Vector3(92, 0, 88), 3.0], [Vector3(135, 0, 30), 2.2]]:
		P.scrap_heap(lv, p[0], rng, p[1])
	# The crusher hall, its stacks, the conveyor running up into it from the biggest heap.
	var ch := Vector3(122, 0, 90)
	A.box(lv, Vector3(26, 16, 18), ch + Vector3(0, 8, 0), "corrugated", Color(0.6, 0.55, 0.5), true, 2.0)
	A.box(lv, Vector3(27, 0.5, 19), ch + Vector3(0, 16.2, 0), "rust", Color(0.7, 0.6, 0.55), false, 2.0)
	var nm := B.label(lv, "CRUSHER  No. 2", ch + Vector3(0, 13.0, -9.06), 120, Color(0.9, 0.86, 0.75), "plate", 0.02)
	nm.rotation.y = PI
	for k in 2:
		var sx := ch + Vector3(-6.0 + k * 9.0, 0, 6.0)
		A.cyl(lv, 1.4, 34.0, sx + Vector3(0, 17.0, 0), "brick", Color(0.65, 0.45, 0.38), true)
		A.cyl(lv, 1.6, 1.0, sx + Vector3(0, 33.8, 0), "metal", Color(0.25, 0.22, 0.2), false)
		for b in 3:
			A.cyl(lv, 1.5, 0.4, sx + Vector3(0, 30.0 - b * 2.0, 0), "paint", Color(0.85, 0.85, 0.82) if b % 2 == 0 else Color(0.8, 0.2, 0.15), false)
	var a := CONV_A
	var b := CONV_B
	var belt := Node3D.new()
	belt.name = "Conveyor"
	lv.add_child(belt)
	var d := b - a
	belt.position = (a + b) / 2.0
	belt.look_at_from_position(belt.position, b, Vector3.UP)
	A.box(belt, Vector3(1.6, 0.25, d.length()), Vector3.ZERO, "runner", Color.WHITE, false, 1.0)
	for sx in [-1.0, 1.0]:
		A.box(belt, Vector3(0.12, 0.6, d.length()), Vector3(sx * 0.86, 0.2, 0), "enamel", Color(0.85, 0.6, 0.12), false, 1.0)
	belt.set_meta("from", a)
	belt.set_meta("to", b)
	for k in 6:   # legs under it
		var p := a.lerp(b, (k + 0.5) / 6.0)
		A.box(lv, Vector3(0.4, p.y, 0.4), Vector3(p.x, p.y / 2.0, p.z), "metal", Color(0.4, 0.4, 0.38), false, 0.8)
	# Bales stacked in rows, a weighbridge, a magnet crane on a tower.
	for row in 3:
		for k in 8:
			for lvl in rng.randi_range(1, 3):
				P.bale(lv, Vector3(60.0 + k * 1.3, 0.06 + lvl * 0.95 - 0.95, 70.0 + row * 2.6), 1.15, rng)
	A.box(lv, Vector3(4.0, 0.3, 14.0), Vector3(66, 0.15, 28), "riveted", Color(0.6, 0.58, 0.55), true, 1.0)
	_block(lv, Vector3(74, 0, 24), Vector3(7, 3.2, 4), Color(0.75, 0.7, 0.5), "WEIGHBRIDGE", rng)
	P.gantry_crane(lv, Vector3(104, 0.06, 64), 0.2, 22.0, 12.0)


# --- fuel and power --------------------------------------------------------------------------------

static func _fuel(lv: Node3D, rng: RandomNumberGenerator) -> void:
	for k in 4:
		var p := Vector3(120.0 + (k % 2) * 14.0, 0.06, 12.0 + (k / 2) * 0.0 + (k % 2) * 0.0)
		p.x = 108.0 + k * 13.0
		A.cyl(lv, 5.0, 9.0, p + Vector3(0, 4.5, 0), "enamel", Color(0.85, 0.83, 0.78), true)
		A.cyl(lv, 5.1, 0.4, p + Vector3(0, 9.2, 0), "metal", Color(0.5, 0.5, 0.48), false)
		B.label(lv, "BRM DIESEL %d" % (k + 1), p + Vector3(0, 5.0, -5.02), 60, Color(0.15, 0.13, 0.11), "stencil", 0.014).rotation.y = PI
		A.cyl(lv, 0.15, 9.5, p + Vector3(5.1, 4.75, 0), "metal", Color(0.6, 0.6, 0.58), false)   # ladder rail
	A.pipe(lv, Vector3(100, 1.0, 6.0), Vector3(150, 1.0, 6.0), 0.25, "metal", Color(0.75, 0.6, 0.2))
	# A transformer yard behind a fence on the west side.
	for k in 3:
		var t := Vector3(-128.0 + k * 9.0, 0.06, 9.0)
		A.box(lv, Vector3(3.5, 3.0, 2.5), t + Vector3(0, 1.5, 0), "enamel", Color(0.5, 0.55, 0.5), true, 0.8)
		for f in 5:
			A.box(lv, Vector3(0.08, 2.6, 2.6), t + Vector3(-1.4 + f * 0.7, 1.5, 0), "metal", Color(0.4, 0.42, 0.4), false, 0.5)
		for i in 3:
			A.cyl(lv, 0.15, 1.2, t + Vector3(-0.9 + i * 0.9, 3.6, 0), "cream", Color(0.75, 0.55, 0.35), false)
	P.fence(lv, Vector3(-134, 0, 4.5), Vector3(-104, 0, 4.5), rng)


# --- light -----------------------------------------------------------------------------------------

static func _lights(lv: Node3D) -> void:
	for p in [[Vector3(-70, 0.06, 30), PI * 0.8], [Vector3(-130, 0.06, 95), PI * 0.2], [Vector3(70, 0.06, 30), -PI * 0.8], [Vector3(140, 0.06, 95), -PI * 0.2],
			[Vector3(-110, 0.06, -60), PI * 0.75], [Vector3(10, 0.06, -60), PI], [Vector3(110, 0.06, -60), -PI * 0.75]]:
		var before := lv.get_child_count()
		P.floodlight_tower(lv, p[0], p[1], 16.0, true)
		for i in range(before, lv.get_child_count()):   # (no shadows from these: each one would draw the whole site again)
			for l: SpotLight3D in lv.get_child(i).find_children("*", "SpotLight3D", true, false):
				l.shadow_enabled = false
	for x in range(-140, 141, 20):   # street lamps along the ring road
		var at := Vector3(x, 0, 45.5)
		A.cyl(lv, 0.1, 7.0, at + Vector3(0, 3.5, 0), "metal", Color(0.35, 0.36, 0.35), false)
		A.box(lv, Vector3(0.2, 0.15, 1.4), at + Vector3(0, 7.0, -0.7), "metal", Color(0.35, 0.36, 0.35), false, 0.4)
		A.glow(lv, Vector3(0.4, 0.08, 0.6), at + Vector3(0, 6.9, -1.2), Color(1, 0.85, 0.6), 2.0)
