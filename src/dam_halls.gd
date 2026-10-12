# The big rooms under a dam (the DAM facility, halls.gd's set pieces for it):
#   turbine_hall   the generator floor: the units in a row, each a ribbed stator housing standing out
#                  of its pit inside a railing, the spider and the exciter on top with its slip rings,
#                  a governor cabinet beside it; a crane on runways overhead, walkways painted on the
#                  floor. One unit is open, its windings lifted out onto a cradle under a chain hoist:
#                  the jackpot (fac.jackpot, level.populate puts the WINDINGS there).
#   control_room   the mimic board along a wall (the dam, the river, the units, lamps lit), the desks
#                  in a curve facing it with their consoles, telephones and logbooks, the clock.
extends RefCounted

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")
const Halls = preload("res://src/halls.gd")

const H := 4.0
const MACHINE := Color(0.52, 0.62, 0.56)   # machinery green
const CREAM := Color(0.86, 0.82, 0.7)
const STEEL := Color(0.4, 0.42, 0.42)
const YELLOW := Color(0.92, 0.72, 0.12)


## Where the units stand, in frame coordinates, by the room's shape.
static func _units(f: Dictionary) -> Array:
	match f.shape:
		"2x1": return [Vector2(-6.0, 0.0), Vector2(6.0, 0.0)]
		"L": return [Vector2(0.0, 0.0), Vector2(12.0, 0.0), Vector2(0.0, 12.0)]
		_: return [Vector2(-6.0, -6.0), Vector2(6.0, -6.0), Vector2(-6.0, 6.0), Vector2(6.0, 6.0)]


static func turbine_hall(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator) -> void:
	var units := _units(f)
	var open := rng.randi() % units.size()   # the one under repair
	for i in units.size():
		var u: Vector2 = units[i]
		var p := Vector3.INF
		var k := 1.0
		for sc in [1.0, 0.78]:   # (shifted off a doorway's way in if it has to be; a smaller unit if that won't do)
			for d in [0.0, 1.4, 2.4]:
				for off in ([Vector2.ZERO] if d == 0.0 else [Vector2(0, d), Vector2(0, -d), Vector2(d, 0), Vector2(-d, 0), Vector2(d, d) * 0.75, Vector2(-d, -d) * 0.75, Vector2(d, -d) * 0.75, Vector2(-d, d) * 0.75]):
					var q := Halls.at(f, u.x + off.x, u.y + off.y)
					if p == Vector3.INF and Halls.room_for(fac, zones, q, Vector3(5.6, 1.0, 5.6) * sc):
						p = q
						k = sc
			if p != Vector3.INF:
				break
		if p == Vector3.INF:
			continue
		_unit(fac, p, i + 1, i == open, rng, k)
		Halls.claim(fac, p, Vector3(6.8, 2.0, 6.8) * k)
		var g: Vector3 = p + (f.ax * 3.9 if f.shape != "L" or i != 2 else f.sd * 3.9) + (f.sd * 2.4 if f.shape != "L" or i != 2 else f.ax * 2.4)
		if Halls.room_for(fac, zones, g, Vector3(1.0, 1.0, 1.0)):
			_governor(fac, g, Halls.face(f, -1, 0), i + 1)
			Halls.claim(fac, g, Vector3(1.1, 2.0, 1.1))
	# The crane: runways along the hall's long sides, the bridge across, its trolley and hook.
	var runs: Array = []
	match f.shape:
		"2x1": runs = [[Vector2(-11.6, -5.4), Vector2(11.6, -5.4)], [Vector2(-11.6, 5.4), Vector2(11.6, 5.4)]]
		"L": runs = [[Vector2(-5.4, -5.4), Vector2(17.6, -5.4)], [Vector2(-5.4, 5.4), Vector2(17.6, 5.4)]]
		_: runs = [[Vector2(-11.6, -11.4), Vector2(11.6, -11.4)], [Vector2(-11.6, 11.4), Vector2(11.6, 11.4)]]
	for rw in runs:
		var a := Halls.at(f, rw[0].x, rw[0].y, H - 0.35)
		var b := Halls.at(f, rw[1].x, rw[1].y, H - 0.35)
		var r := A.root(fac, (a + b) / 2.0, atan2(b.x - a.x, b.z - a.z))
		A.box(r, Vector3(0.3, 0.4, a.distance_to(b)), Vector3.ZERO, "riveted", YELLOW.darkened(0.25), false, 0.8)
		A.box(r, Vector3(0.08, 0.06, a.distance_to(b)), Vector3(0, 0.23, 0), "metal", STEEL, false)
	var cu := 2.0 if f.shape != "L" else 9.0
	var span: float = absf(runs[0][0].y - runs[1][0].y)
	var bridge := A.root(fac, Halls.at(f, cu, (runs[0][0].y + runs[1][0].y) / 2.0, H - 0.25), Halls.face(f, 1, 0))
	for s: float in [-0.6, 0.6]:
		A.box(bridge, Vector3(span, 0.45, 0.35), Vector3(0, 0, s), "riveted", YELLOW, false, 0.8)
	A.box(bridge, Vector3(1.6, 0.35, 1.6), Vector3(rng.randf_range(-2.0, 2.0), -0.35, 0), "metal", STEEL.darkened(0.2), false)   # the trolley
	B.label(bridge, "15 TONNE", Vector3(span * 0.3, 0, 0.79), 40, Color(0.12, 0.1, 0.08), "stencil", 0.006)
	# Walkways painted on the floor between the units, and a sign.
	for k in units.size() - 1:
		var a := Halls.at(f, units[k].x, units[k].y)
		var b := Halls.at(f, units[k + 1].x, units[k + 1].y)
		if f.shape == "L" and k == 1:
			a = Halls.at(f, units[0].x, units[0].y)
		for s: float in [-1.0, 1.0]:
			var side: Vector3 = (b - a).normalized().cross(Vector3.UP) * (s * 3.9)
			Halls.stripe(fac, a + side, b + side, 0.12, YELLOW)
	Halls.hanging_sign(fac, f, 0.0 if f.shape != "L" else 6.0, -4.0 if f.shape != "2x2" else 0.0, "GENERATOR FLOOR", 1, 0, Color(0.95, 0.85, 0.5))
	for i in 3:
		Halls._against_walls(fac, f, zones, rng, func(p: Vector3, rot_y: float, n: Vector3) -> bool:
			if not Halls.room_for(fac, zones, p, Vector3(1.6, 1.2, 1.6), rot_y):
				return false
			P.control_panel(fac, p, rot_y, rng)
			Halls.claim(fac, p, Vector3(1.6, 1.2, 1.6), rot_y)
			return true)


## One generating unit at `p` (floor centre): the pit and its curb, the stator housing, the spider, the
## exciter and slip rings, a railing round it. Open: its top off, the windings out on a cradle.
static func _unit(fac, p: Vector3, number: int, open: bool, rng: RandomNumberGenerator, size := 1.0) -> void:
	var r := A.root(fac, p, rng.randi() % 4 * PI / 2.0)
	r.scale = Vector3.ONE * size
	A.cyl(r, 3.3, 0.3, Vector3(0, 0.15, 0), "concrete", Color(0.55, 0.56, 0.52), true)   # the curb round the pit
	A.ring(r, 3.32, 3.18, Vector3(0, 0.3, 0), "paint", YELLOW)
	A.cyl(r, 3.05, 0.02, Vector3(0, 0.31, 0), "metal", Color(0.08, 0.08, 0.08))   # the gap down into the pit
	var top := 1.1 if open else 1.75
	A.cyl(r, 2.55, top, Vector3(0, 0.3 + top / 2.0, 0), "enamel", MACHINE, true)   # the stator housing
	for k in 16:   # its ribs
		var a := TAU * k / 16.0
		A.box(r, Vector3(0.12, top - 0.1, 0.22), Vector3(cos(a) * 2.6, 0.3 + top / 2.0, sin(a) * 2.6), "enamel", MACHINE.darkened(0.15), false, 0.6, Vector3(0, -a, 0))
	A.ring(r, 2.66, 2.5, Vector3(0, 0.32 + top, 0), "metal", MACHINE.darkened(0.25))
	var plate := A.root(r, Vector3(0, 0.3 + top * 0.55, 2.66), 0.0)
	A.box(plate, Vector3(0.8, 0.36, 0.02), Vector3.ZERO, "brass", Color(0.8, 0.64, 0.36), false, 0.4)
	B.label(plate, "UNIT %d" % number, Vector3(0, 0.02, 0.012), 40, Color(0.25, 0.18, 0.1), "plate", 0.005)
	if open:
		# The top's off: the windings show in the slot, the rotor's pole pieces round the shaft.
		A.cyl(r, 2.3, 0.04, Vector3(0, 0.32 + top, 0), "metal", Color(0.12, 0.12, 0.12))
		for k in 24:
			var a := TAU * k / 24.0
			A.box(r, Vector3(0.12, 0.16, 0.34), Vector3(cos(a) * 2.2, 0.36 + top, sin(a) * 2.2), "copper", Color(0.9, 0.58, 0.36), false, 0.3, Vector3(0, -a, 0))
		A.cyl(r, 0.5, 1.0, Vector3(0, 0.3 + top + 0.4, 0), "metal", STEEL)   # the shaft, standing up out of it
		# The cradle beside it, the chain hoist over, caution tape round.
		var c := Vector3(4.6, 0.0, 0.0)
		for s: float in [-1.0, 1.0]:
			A.box(r, Vector3(0.24, 0.24, 1.6), c + Vector3(s * 0.55, 0.12, 0), "wood", Color(0.6, 0.48, 0.34), false)
		A.box(r, Vector3(1.6, 0.06, 1.7), c + Vector3(0, 0.27, 0), "wood", Color(0.55, 0.44, 0.32), false)
		A.seg(r, c + Vector3(0, H - 0.4, 0), c + Vector3(0, 1.5, 0), 0.02, 0.02, "metal", Color(0.3, 0.3, 0.3))
		A.box(r, Vector3(0.3, 0.4, 0.2), c + Vector3(0, 1.4, 0), "metal", YELLOW.darkened(0.2), false)
		A.box(r, Vector3(0.06, 0.12, 0.06), c + Vector3(0, 1.1, 0), "metal", Color(0.3, 0.3, 0.3), false)   # the hook
		for k in 4:
			var a := TAU * k / 4.0 + PI / 4.0
			var post := c + Vector3(cos(a) * 1.5, 0, sin(a) * 1.5)
			A.cyl(r, 0.05, 1.0, post + Vector3(0, 0.5, 0), "plastic", Color(0.9, 0.5, 0.1))
			var nxt := c + Vector3(cos(a + PI / 2.0) * 1.5, 0, sin(a + PI / 2.0) * 1.5)
			A.seg(r, post + Vector3(0, 0.9, 0), nxt + Vector3(0, 0.9, 0), 0.015, 0.015, "paint", Color(0.95, 0.85, 0.15))
		fac.jackpot = fac.to_local(r.to_global(c + Vector3(0, 0.5, 0)))
	else:
		for k in 6:   # the spider's arms out to the rim
			var a := TAU * k / 6.0
			A.box(r, Vector3(2.4, 0.28, 0.3), Vector3(cos(a) * 1.3, 0.45 + top, sin(a) * 1.3), "enamel", MACHINE.darkened(0.1), false, 0.6, Vector3(0, -a, 0))
		A.cyl(r, 0.95, 1.05, Vector3(0, 0.95 + top, 0), "enamel", MACHINE.lightened(0.05))   # the exciter
		for k in 3:   # its slip rings and brush gear
			A.cyl(r, 0.98, 0.06, Vector3(0, 0.62 + top + k * 0.3, 0), "copper", Color(0.85, 0.55, 0.35))
		A.cyl(r, 1.0, 0.1, Vector3(0, 1.5 + top, 0), "metal", MACHINE.darkened(0.3))
		A.box(r, Vector3(0.3, 0.5, 0.2), Vector3(0, 1.0 + top, 0.95), "metal", Color(0.2, 0.2, 0.2), false)
	for k in 14:   # the railing round the pit (a gap at the steps)
		var a := TAU * k / 14.0
		if k == 0:
			continue
		var pt := Vector3(cos(a) * 3.35, 0.3, sin(a) * 3.35)
		A.box(r, Vector3(0.05, 1.0, 0.05), pt + Vector3(0, 0.5, 0), "metal", YELLOW, false)
		var nxt := Vector3(cos(a + TAU / 14.0) * 3.35, 0.3, sin(a + TAU / 14.0) * 3.35)
		if k < 13:
			A.seg(r, pt + Vector3(0, 1.0, 0), nxt + Vector3(0, 1.0, 0), 0.025, 0.025, "metal", YELLOW)
			A.seg(r, pt + Vector3(0, 0.55, 0), nxt + Vector3(0, 0.55, 0), 0.02, 0.02, "metal", YELLOW)
	A.box(r, Vector3(0.9, 0.3, 0.6), Vector3(3.5, 0.15, 0.25), "concrete", Color(0.55, 0.56, 0.52), true)   # a step up at the gap


## The governor cabinet: a tall green cabinet, dials and a lamp, a handwheel, the unit number.
static func _governor(fac, p: Vector3, rot_y: float, number: int) -> void:
	var r := A.root(fac, p, rot_y)
	A.box(r, Vector3(0.9, 1.9, 0.6), Vector3(0, 0.95, 0), "enamel", MACHINE, true, 0.6)
	A.box(r, Vector3(0.94, 0.08, 0.64), Vector3(0, 1.94, 0), "metal", MACHINE.darkened(0.3), false)
	for k in 2:   # dials, live
		var dx := -0.2 + k * 0.4
		A.cyl(r, 0.13, 0.04, Vector3(dx, 1.5, -0.31), "cream", CREAM, false, "z")
		A.box(r, Vector3(0.012, 0.1, 0.01), Vector3(dx, 1.53, -0.335), "metal", Color(0.1, 0.1, 0.1), false, 1.0, Vector3(0, 0, 0.4 - k * 0.9))
	A.glow(r, Vector3(0.06, 0.06, 0.02), Vector3(0.3, 1.2, -0.31), Color(0.3, 1.0, 0.4), 3.0)
	A.ring(r, 0.2, 0.17, Vector3(0, 0.95, -0.36), "metal", Color(0.75, 0.12, 0.1), Vector3(PI / 2.0, 0, 0))   # the handwheel
	A.seg(r, Vector3(0, 0.95, -0.3), Vector3(0, 0.95, -0.36), 0.03, 0.03, "metal", STEEL)
	B.label(r, "GOV %d" % number, Vector3(0, 1.78, -0.305), 30, Color(0.9, 0.86, 0.75), "stencil", 0.004).rotation.y = PI


## The control room: the mimic board, the desks facing it, the clock.
static func control_room(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator) -> void:
	var walls := Halls._outside_walls(fac, f)
	var board_wall = null
	var best := 0.0
	for w in walls:   # the longest clear stretch of wall for the board: its middle away from doors
		var p: Vector3 = fac._wall_spot(w, 0.0, 0.3)
		var free := true
		for z in zones:
			if z.grow(1.2).has_point(Vector3(p.x, 0.5, p.z)):
				free = false
		var d: float = (p - f.o).length()
		if free and d > best:
			best = d
			board_wall = w
	if board_wall == null:
		return
	var n: Vector3 = board_wall[2]
	var bp: Vector3 = fac._wall_spot(board_wall, 0.0, 0.12)
	var r := A.root(fac, bp, atan2(-n.x, -n.z) + PI)   # +z into the room
	_mimic(r, rng)
	fac.set_meta("mimic", [bp, n])   # (for the shot scripts)
	Halls.claim(fac, bp + n * 0.4, Vector3(9.0, 3.0, 0.8) if absf(n.z) > 0.5 else Vector3(0.8, 3.0, 9.0))
	# The desks: a shallow arc facing the board.
	for k in 4:
		var a := (k - 1.5) * 0.32
		var dp := bp + n * 4.2 + Vector3(-n.z, 0, n.x) * sin(a) * 6.0 + n * (1.0 - cos(a)) * 6.0
		var face := atan2(n.x, n.z) + a
		if Halls.room_for(fac, zones, dp, Vector3(2.0, 1.0, 1.0), face):
			_desk(fac, dp, face, rng)
			Halls.claim(fac, dp, Vector3(2.0, 1.2, 1.4), face)
	var clock := A.root(fac, bp + Vector3(0, H - 0.65, 0) + n * 0.05, atan2(-n.x, -n.z) + PI)
	A.cyl(clock, 0.32, 0.06, Vector3(0, 0, 0.03), "cream", CREAM, false, "z")
	A.ring(clock, 0.34, 0.3, Vector3(0, 0, 0.04), "metal", Color(0.2, 0.2, 0.2), Vector3(PI / 2.0, 0, 0))
	A.box(clock, Vector3(0.02, 0.2, 0.01), Vector3(0, 0.08, 0.07), "metal", Color(0.1, 0.1, 0.1), false, 1.0, Vector3(0, 0, 0.6))
	A.box(clock, Vector3(0.02, 0.26, 0.01), Vector3(0, 0.1, 0.075), "metal", Color(0.1, 0.1, 0.1), false, 1.0, Vector3(0, 0, -1.9))
	for i in 3:
		Halls._against_walls(fac, f, zones, rng, func(p: Vector3, rot_y: float, wn: Vector3) -> bool:
			if not Halls.room_for(fac, zones, p, Vector3(1.0, 1.4, 0.7), rot_y):
				return false
			P.filing_cabinet(fac, p, rot_y)
			Halls.claim(fac, p, Vector3(1.0, 1.4, 0.7), rot_y)
			return true)
	Halls.hanging_sign(fac, f, 0.0 if f.shape != "L" else 6.0, 0.0, "CONTROL ROOM", 1, 0, Color(0.95, 0.85, 0.5))


## The mimic board: a long grey-green panel with the scheme painted on it (the reservoir, the dam,
## the penstocks down to the units, the river out), a lamp at every valve and unit (some lit), meters
## along the top, the dam's name.
static func _mimic(r: Node3D, rng: RandomNumberGenerator) -> void:
	var w := 8.4
	A.box(r, Vector3(w, 2.6, 0.2), Vector3(0, 1.6, 0.1), "enamel", Color(0.5, 0.56, 0.52), true, 0.8)
	A.box(r, Vector3(w + 0.2, 0.14, 0.35), Vector3(0, 2.95, 0.15), "metal", Color(0.3, 0.32, 0.3), false)
	A.box(r, Vector3(w + 0.2, 0.3, 0.6), Vector3(0, 0.15, 0.3), "metal", Color(0.3, 0.32, 0.3), false)
	var z := 0.215
	var water := Color(0.25, 0.45, 0.7)
	A.box(r, Vector3(2.0, 0.5, 0.01), Vector3(-3.0, 2.3, z), "paint", water, false)   # the reservoir
	A.box(r, Vector3(0.3, 1.0, 0.012), Vector3(-1.85, 2.0, z), "paint", Color(0.85, 0.85, 0.8), false)   # the dam
	for k in 4:   # penstocks down to the units, a unit each
		var ux := -1.0 + k * 1.3
		A.box(r, Vector3(ux + 1.7, 0.06, 0.012), Vector3((-1.7 + ux) / 2.0, 1.95 - k * 0.0, z), "paint", water, false)
		A.box(r, Vector3(0.06, 0.7, 0.012), Vector3(ux, 1.6, z), "paint", water, false)
		A.cyl(r, 0.22, 0.02, Vector3(ux, 1.15, z), "paint", Color(0.85, 0.85, 0.8), false, "z")
		var lit := rng.randf() < 0.6
		A.glow(r, Vector3(0.08, 0.08, 0.02), Vector3(ux, 1.15, z + 0.015), Color(0.2, 1.0, 0.3) if lit else Color(1.0, 0.2, 0.15), 3.0 if lit else 2.0)
	A.box(r, Vector3(5.6, 0.08, 0.012), Vector3(1.1, 0.75, z), "paint", water, false)   # the tailrace to the river
	for k in 8:   # meters along the top
		var mx := -3.6 + k * 1.03
		A.cyl(r, 0.18, 0.04, Vector3(mx, 2.72, z), "cream", CREAM, false, "z")
		A.box(r, Vector3(0.012, 0.13, 0.01), Vector3(mx, 2.74, z + 0.02), "metal", Color(0.1, 0.1, 0.1), false, 1.0, Vector3(0, 0, rng.randf_range(-0.8, 0.8)))
	for k in 12:   # valve lamps along the lines
		var lx := rng.randf_range(-3.8, 3.8)
		A.glow(r, Vector3(0.05, 0.05, 0.02), Vector3(lx, rng.randf_range(0.6, 2.4), z + 0.012), [Color(1.0, 0.75, 0.2), Color(0.2, 1.0, 0.3), Color(1, 0.2, 0.15)][rng.randi() % 3], 2.5)
	B.label(r, "STATION SCHEME", Vector3(2.6, 2.38, z + 0.005), 40, Color(0.9, 0.88, 0.8), "stencil", 0.005)


## A control desk facing the board: sloped console with switches and lamps, a telephone, a logbook,
## a chair pulled back.
static func _desk(fac, p: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := A.root(fac, p, rot_y)   # (+z the operator's side, -z toward the board)
	A.box(r, Vector3(1.9, 0.75, 0.8), Vector3(0, 0.375, 0), "enamel", Color(0.46, 0.52, 0.48), true, 0.6)
	A.box(r, Vector3(1.9, 0.36, 0.06), Vector3(0, 0.93, -0.39), "enamel", Color(0.42, 0.48, 0.44), false, 0.6)   # the console's back
	for s in [-1.0, 1.0]:
		A.box(r, Vector3(0.05, 0.36, 0.42), Vector3(s * 0.93, 0.93, -0.2), "enamel", Color(0.42, 0.48, 0.44), false, 0.6, Vector3(0.62, 0, 0))   # cheeks
	var panel := Node3D.new()   # the sloped face, rising toward the board
	r.add_child(panel)
	panel.position = Vector3(0, 0.95, -0.2)
	panel.rotation.x = 0.62
	A.box(panel, Vector3(1.86, 0.05, 0.46), Vector3.ZERO, "enamel", Color(0.52, 0.58, 0.54), false, 0.6)
	for k in 6:
		A.box(panel, Vector3(0.05, 0.05, 0.07), Vector3(-0.7 + k * 0.28, 0.04, 0.08), "plastic", Color(0.1, 0.1, 0.1), false)   # switches
		A.glow(panel, Vector3(0.05, 0.02, 0.05), Vector3(-0.7 + k * 0.28, 0.035, -0.1), [Color(1, 0.75, 0.2), Color(0.2, 1, 0.3), Color(1, 0.2, 0.15)][(k + rng.randi()) % 3], 2.0)
	A.cyl(panel, 0.07, 0.02, Vector3(0.75, 0.035, -0.05), "cream", CREAM)   # a meter
	A.box(r, Vector3(0.22, 0.08, 0.16), Vector3(0.7, 0.79, 0.22), "plastic", Color(0.1, 0.1, 0.1), false)   # telephone
	A.box(r, Vector3(0.34, 0.04, 0.24), Vector3(-0.4, 0.77, 0.2), "paper", Color(0.85, 0.82, 0.68), false, 1.0, Vector3(0, rng.randf_range(-0.3, 0.3), 0))   # the log
	var n := Vector3(sin(rot_y), 0, cos(rot_y))
	P.chair(fac, p + n * 0.95, rot_y + rng.randf_range(-0.5, 0.5))   # pulled back, facing the board
