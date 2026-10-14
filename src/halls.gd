# Big rooms: two to four grid cells merged into one space (2x1, L or 2x2) with a set piece of its
# own: a lab reception, a canteen, a lab hall of specimen tanks, a server hall, a warehouse of
# pallet racks, an assembly line, a flesh "gut hall", a backrooms pillar hall or an open-plan office.
# The merged cells have no walls between them: a ceiling header and wall pilasters mark the seams.
# Everything is placed in a room frame (u along the room's axis, v across it) and checked against
# the doorways and whatever is already there, so no set piece ever blocks a way in or out.
extends RefCounted

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")
const Merge = preload("res://src/merge.gd")
const DamHalls = preload("res://src/dam_halls.gd")

const CELL := 12.0
const H := 4.0


## What a big room is, by theme and shape.
static func pick_kind(theme_id: String, shape: String, rng: RandomNumberGenerator, used: Array) -> String:
	var pools := {
		"LAB": {"2x1": ["reception", "canteen", "lab_hall", "server_hall"], "L": ["reception", "lab_hall", "canteen"], "2x2": ["server_hall", "lab_hall"]},
		"FACTORY": {"2x1": ["warehouse", "assembly", "canteen"], "L": ["assembly", "warehouse"], "2x2": ["warehouse"]},
		"FLESH": {"2x1": ["gut_hall", "canteen"], "L": ["gut_hall"], "2x2": ["gut_hall"]},
		"BACKROOMS": {"2x1": ["pillar_hall", "open_office"], "L": ["pillar_hall", "open_office"], "2x2": ["pillar_hall"]},
		"DAM": {"2x1": ["turbine_hall", "control_room"], "L": ["turbine_hall", "control_room"], "2x2": ["turbine_hall"]},
	}
	var pool: Array = pools[theme_id][shape].duplicate()
	var fresh: Array = pool.filter(func(k): return not k in used)   # a site doesn't repeat one if it can help it
	if not fresh.is_empty():
		pool = fresh
	var k: String = pool[rng.randi() % pool.size()]
	if k == "reception":
		used.append(k)   # there's only ever one front desk
	used.append(k)
	return k


# --- the room frame -----------------------------------------------------------------------------

## origin + u * ax + v * sd. 2x1: origin between the two cells, u along them (-12..12), v -6..6.
## L: origin at the corner cell's centre, arm 1 along +u (6..18), arm 2 along +v (6..18).
## 2x2: origin in the middle, u and v -12..12.
static func frame(g: Dictionary) -> Dictionary:
	var cells: Array = g.cells
	var o := func(c: Vector2i) -> Vector3: return Vector3(c.x * CELL, 0, c.y * CELL)
	var ax: Vector3
	var sd: Vector3
	var origin: Vector3
	match g.shape:
		"2x1":
			var d: Vector2i = cells[1] - cells[0]
			ax = Vector3(d.x, 0, d.y)
			sd = Vector3(-ax.z, 0, ax.x)
			origin = (o.call(cells[0]) + o.call(cells[1])) / 2.0
		"L":
			var d1: Vector2i = cells[1] - cells[0]
			var d2: Vector2i = cells[2] - cells[0]
			ax = Vector3(d1.x, 0, d1.y)
			sd = Vector3(d2.x, 0, d2.y)
			origin = o.call(cells[0])
		_:
			var d1: Vector2i = cells[1] - cells[0]
			var d2: Vector2i = cells[2] - cells[0]
			ax = Vector3(d1.x, 0, d1.y)
			sd = Vector3(d2.x, 0, d2.y)
			origin = (o.call(cells[0]) + o.call(cells[3])) / 2.0
	return {"o": origin, "ax": ax, "sd": sd, "shape": g.shape, "cells": cells}


## The grid cell a local point is in.
static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / CELL), roundi(p.z / CELL))


static func at(f: Dictionary, u: float, v: float, y := 0.0) -> Vector3:
	return f.o + f.ax * u + f.sd * v + Vector3(0, y, 0)


## rotation_y that turns a prop's -z (its front) toward frame direction (du, dv).
static func face(f: Dictionary, du: float, dv: float) -> float:
	var d: Vector3 = f.ax * du + f.sd * dv
	return atan2(-d.x, -d.z)


## Keep-clear zones (local AABBs, floor-level) in front of every way into the room, inside it.
static func door_zones(fac, g: Dictionary) -> Array:
	var zones := []
	for c in g.cells:
		for w in fac.cell_walls[c]:
			if w[3] and not w[4]:   # a doorway or a vent on an outside wall
				var n: Vector3 = w[2]
				var mid: Vector3 = w[0] + n * 1.6
				var ext := Vector3(1.8, 1.0, 1.7) if w[1] else Vector3(1.7, 1.0, 1.8)
				zones.append(AABB(mid - ext, ext * 2.0))
	return zones


## Is a footprint (centre, size along the prop's own x/z, rotation) free of doorways and furniture?
static func room_for(fac, zones: Array, pos: Vector3, size: Vector3, rot := 0.0) -> bool:
	var c := absf(cos(rot))
	var s := absf(sin(rot))
	var half := Vector3(c * size.x / 2.0 + s * size.z / 2.0, 0.5, s * size.x / 2.0 + c * size.z / 2.0)
	var box := AABB(pos - Vector3(half.x, 0, half.z), Vector3(half.x * 2.0, 1.0, half.z * 2.0))
	for z in zones:
		if box.intersects(z):
			return false
	for k in fac.crates:
		if box.intersects(k.grow(0.05)):
			return false
	return true


static func claim(fac, pos: Vector3, size: Vector3, rot := 0.0) -> void:
	var c := absf(cos(rot))
	var s := absf(sin(rot))
	fac._solid(pos, Vector3(c * size.x + s * size.z, size.y, s * size.x + c * size.z))


# --- building it --------------------------------------------------------------------------------

## The seam between two merged cells: a ceiling header across it, pilasters where it meets the walls.
static func header(fac, center: Vector3, along_x: bool, theme: Dictionary, theme_id: String) -> void:
	if theme_id == "BACKROOMS":   # one endless ceiling: just a soffit strip
		A.sbox(fac, Vector3(CELL, 0.12, 0.5) if along_x else Vector3(0.5, 0.12, CELL), center + Vector3(0, H - 0.06, 0), "wallpaper", theme.band, false, 2.0)
		return
	var kind: String = "riveted" if theme_id == "FACTORY" else ("flesh" if theme_id == "FLESH" else theme.wall_kind)
	A.sbox(fac, Vector3(CELL, 0.55, 0.45) if along_x else Vector3(0.45, 0.55, CELL), center + Vector3(0, H - 0.275, 0), kind, theme.wall if theme_id != "FACTORY" else Color(0.8, 0.75, 0.7), false, 2.0)
	if theme_id == "FACTORY":   # an I-beam flange along the bottom
		A.sbox(fac, Vector3(CELL, 0.06, 0.6) if along_x else Vector3(0.6, 0.06, CELL), center + Vector3(0, H - 0.58, 0), "rust", Color.WHITE, false, 1.0)
	for s in [-1, 1]:   # pilasters on the walls at each end of the seam
		var end: Vector3 = center + (Vector3(s * (CELL / 2.0 - 0.3), 0, 0) if along_x else Vector3(0, 0, s * (CELL / 2.0 - 0.3)))
		A.sbox(fac, Vector3(0.6, H, 0.7) if along_x else Vector3(0.7, H, 0.6), end + Vector3(0, H / 2.0, 0), theme.wall_kind, theme.wall, true, 2.0)
		A.sbox(fac, Vector3(0.64, 1.1, 0.74) if along_x else Vector3(0.74, 1.1, 0.64), end + Vector3(0, 0.55, 0), theme.band_kind, theme.band, false, 1.5)
		fac._solid(end, Vector3(0.7, H, 0.7))


## Ceiling lights for one cell of a big room (no walls to hang them on in the middle of it).
static func light(fac, o: Vector3, kind: String, theme: Dictionary, theme_id: String, rng: RandomNumberGenerator) -> void:
	var c: Color = theme.light
	var lights: Array = []
	if kind == "server_hall":
		for z in [-3.0, 3.0]:
			lights.append(A.fluorescent(fac, o + Vector3(0, H - 0.05, z), Color(0.5, 0.75, 1.0), 0.9))
	else:
		match theme_id:
			"FACTORY":
				lights.append(A.hanging_lamp(fac, o + Vector3(0, H, 0), c, 1.2, 2.2, true))
			"LAB":
				for z in [-2.5, 2.5]:
					lights.append(A.fluorescent(fac, o + Vector3(0, H - 0.05, z), c, 1.3))
			"BACKROOMS":
				lights.append(B.omni(fac, o + Vector3(0, H - 0.5, 0), c, 1.2, 11.0, false))
			"DAM":
				for z in [-3.0, 0.0, 3.0]:
					lights.append(A.fluorescent(fac, o + Vector3(0, H - 0.05, z), c, 1.1))
			"FLESH":
				lights.append(B.omni(fac, o + Vector3(0, H - 0.6, 0), c, 1.0, 9.0, true))
	if not lights.is_empty():
		lights[0].shadow_enabled = true
		for l in lights:   # (any of them may cast shadows when it's among the nearest)
			l.set_meta("budget_shadow", true)
	for l in lights:
		if rng.randf() < 0.25:
			fac._flicker(l)


## Fill a big room: its set piece, then the usual wall fittings, litter and ceiling clutter.
static func dress(fac, g: Dictionary, rng: RandomNumberGenerator) -> void:
	var f := frame(g)
	var zones := door_zones(fac, g)
	if g.shape == "2x2" and fac.theme_id != "FLESH":   # the four cells meet on a column
		var cp: Vector3 = f.o
		A.sbox(fac, Vector3(0.7, H, 0.7), cp + Vector3(0, H / 2.0, 0), fac.theme.wall_kind, fac.theme.wall, true, 2.0)
		A.sbox(fac, Vector3(0.74, 1.1, 0.74), cp + Vector3(0, 0.55, 0), fac.theme.band_kind, fac.theme.band, false, 1.5)
		fac._solid(cp, Vector3(0.8, H, 0.8))
	match g.kind:
		"reception": _reception(fac, f, zones, rng)
		"canteen": _canteen(fac, f, zones, rng)
		"lab_hall": _lab_hall(fac, f, zones, rng)
		"server_hall": _server_hall(fac, f, zones, rng)
		"warehouse": _warehouse(fac, f, zones, rng)
		"assembly": _assembly(fac, f, zones, rng)
		"gut_hall": _gut_hall(fac, f, zones, rng)
		"pillar_hall": _pillar_hall(fac, f, zones, rng)
		"open_office": _open_office(fac, f, zones, rng)
		"turbine_hall": DamHalls.turbine_hall(fac, f, zones, rng)
		"control_room": DamHalls.control_room(fac, f, zones, rng)
	for c in g.cells:
		await fac._m("hall dress %d %d" % [c.x, c.y])   # (a cell a slice: a whole hall at once was a hitch)
		var o := Vector3(c.x * CELL, 0, c.y * CELL)
		var outside: Array = fac.cell_walls[c].filter(func(w): return not w[4])
		fac._on_wall.clear()
		fac._wall_layer(outside, rng)
		P.litter(fac, o, CELL / 2 - 0.8, rng, rng.randi_range(8, 16))
		if fac.theme_id != "BACKROOMS":
			P.ceiling_junk(fac, o, H, rng)
		if fac.overgrown:
			for i in rng.randi_range(1, 3):
				A.vines(fac, o + Vector3(rng.randf_range(-5, 5), H, rng.randf_range(-5, 5)), 2.5, rng)


## The cells of each arm/half, in frame coordinates: [[u0, u1, v0, v1], ...].
static func regions(f: Dictionary) -> Array:
	match f.shape:
		"2x1": return [[-12.0, 0.0, -6.0, 6.0], [0.0, 12.0, -6.0, 6.0]]
		"L": return [[-6.0, 6.0, -6.0, 6.0], [6.0, 18.0, -6.0, 6.0], [-6.0, 6.0, 6.0, 18.0]]
		_: return [[-12.0, 0.0, -12.0, 0.0], [0.0, 12.0, -12.0, 0.0], [-12.0, 0.0, 0.0, 12.0], [0.0, 12.0, 0.0, 12.0]]


## A painted sign on a free-standing board hung from the ceiling, facing frame direction (du, dv).
static func hanging_sign(fac, f: Dictionary, u: float, v: float, text: String, du: float, dv: float, c := Color(0.92, 0.9, 0.85)) -> void:
	var r := Node3D.new()
	fac.add_child(r)
	r.position = at(f, u, v, H - 0.9)
	r.rotation.y = face(f, du, dv) + PI   # the paint faces +z
	A.sbox(r, Vector3(2.4, 0.5, 0.04), Vector3.ZERO, "metal", Color(0.16, 0.18, 0.2), false, 0.5)
	for s in [-1, 1]:
		A.sseg(r, Vector3(s * 0.9, 0.25, 0), Vector3(s * 0.9, 0.9, 0), 0.008, 0.008, "metal", Color(0.3, 0.3, 0.3))
	B.label(r, text, Vector3(0, 0, 0.025), 46, c, "plate", 0.006)
	var back := B.label(r, text, Vector3(0, 0, -0.025), 46, c, "plate", 0.006)
	back.rotation.y = PI


## Floor paint: a straight strip from a to b (local), `w` wide.
static func stripe(fac, a: Vector3, b: Vector3, w: float, c: Color) -> void:
	var d := b - a
	var mi := A.box(fac, Vector3(w, 0.004, d.length()), (a + b) / 2.0 + Vector3(0, 0.003, 0), "paint", c, false, 1.0)
	mi.rotation.y = atan2(d.x, d.z)


# --- reception ------------------------------------------------------------------------------------

static func _reception(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator) -> void:
	# Where things go: the desk at the far end of the room (or in the L's corner), waiting at the other.
	var desk_u := 7.0
	var desk_v := 0.0
	var wait_u := -6.5
	var wait_v := 0.0
	var gate_u := 1.8
	var gate_v := 0.0
	var gate_axis := true   # the turnstiles stand in a line across u
	if f.shape == "L":
		desk_u = 0.0
		wait_u = 12.0
		gate_u = 0.0
		gate_v = 7.6
		gate_axis = false
	# The front desk: a long counter with a raised transaction ledge, a return at one end.
	var dp := at(f, desk_u, desk_v)
	var rot := face(f, -1, 0) if f.shape != "L" else face(f, 1, 1)
	if room_for(fac, zones, dp, Vector3(4.6, 1.2, 2.2), rot):
		_front_desk(fac, dp, rot, rng)
		claim(fac, dp, Vector3(4.6, 1.2, 2.2), rot)
		# The company on a feature panel behind it.
		var back := dp + Vector3(sin(rot), 0, cos(rot)) * 2.4
		if room_for(fac, zones, back, Vector3(5.0, 3.2, 0.4), rot):
			var r := A.root(fac, back, rot, Vector3(5.0, 3.0, 0.3))
			A.sbox(r, Vector3(5.0, 3.0, 0.28), Vector3(0, 1.5, 0), "wood", Color(0.55, 0.4, 0.3), false, 1.0)
			A.sbox(r, Vector3(5.1, 0.12, 0.34), Vector3(0, 3.02, 0), "metal", Color(0.3, 0.3, 0.32), false, 0.5)
			A.sbox(r, Vector3(5.0, 0.35, 0.3), Vector3(0, 0.17, 0), "metal", Color(0.25, 0.25, 0.27), false, 0.5)
			A.sbox(r, Vector3(4.2, 0.08, 0.02), Vector3(0, 1.45, -0.15), "paint", Color(0.9, 0.5, 0.12), false, 0.5)   # orange line
			B.label(r, "B.R.M.", Vector3(0, 2.15, -0.146), 160, Color(0.92, 0.88, 0.78), "plate", 0.007).rotation.y = PI
			B.label(r, "RESEARCH DIVISION", Vector3(0, 1.15, -0.146), 60, Color(0.85, 0.8, 0.7), "plate", 0.006).rotation.y = PI
			for s in [-1, 1]:   # two spotlights over the logo
				A.sseg(r, Vector3(s * 1.6, 3.0, -0.15), Vector3(s * 1.6, 3.15, -0.45), 0.02, 0.02, "metal", Color(0.2, 0.2, 0.2))
				A.scyl(r, 0.06, 0.12, Vector3(s * 1.6, 3.12, -0.5), "metal", Color(0.2, 0.2, 0.2), false, "z")
			claim(fac, back, Vector3(5.0, 3.0, 0.4), rot)
		hanging_sign(fac, f, desk_u + (-1.6 if f.shape != "L" else 0.0), desk_v, "RECEPTION", -1, 0)
	# Waiting area: beam seating in two rows facing the desk, a low table, plants, a rug.
	var wp := at(f, wait_u, wait_v)
	var wrot := face(f, 1, 0) if f.shape != "L" else face(f, -1, 0)
	A.sbox(fac, Vector3(5.4, 0.012, 4.6) if absf(sin(wrot)) < 0.5 else Vector3(4.6, 0.012, 5.4), wp + Vector3(0, 0.006, 0), "carpet", Color(0.5, 0.18, 0.15), false, 2.0)   # rug
	for row in [-1.2, 1.2]:
		var rp: Vector3 = wp + Vector3(-sin(wrot), 0, -cos(wrot)) * row
		if room_for(fac, zones, rp, Vector3(3.4, 0.9, 0.7), wrot):
			_beam_seat(fac, rp, wrot, 4)
			claim(fac, rp, Vector3(3.4, 0.9, 0.7), wrot)
	var side := Vector3(cos(wrot), 0, -sin(wrot))
	for s in [-1, 1]:
		var tp: Vector3 = wp + side * (s * 2.6)
		if room_for(fac, zones, tp, Vector3(0.6, 0.5, 1.2), wrot):
			var r := A.root(fac, tp, wrot, Vector3(0.6, 0.45, 1.2))
			A.sbox(r, Vector3(0.6, 0.04, 1.2), Vector3(0, 0.44, 0), "wood", Color(0.5, 0.36, 0.26), false, 0.6)
			A.sbox(r, Vector3(0.5, 0.02, 1.1), Vector3(0, 0.15, 0), "wood", Color(0.45, 0.32, 0.22), false, 0.6)
			for k in rng.randi_range(2, 4):   # magazines
				A.sbox(r, Vector3(0.22, 0.008, 0.3), Vector3(rng.randf_range(-0.15, 0.15), 0.465 + k * 0.009, rng.randf_range(-0.4, 0.4)), "paper",
					Color.from_hsv(rng.randf(), 0.4, 0.85), false, 0.2, Vector3(0, rng.randf_range(-0.6, 0.6), 0))
			claim(fac, tp, Vector3(0.6, 0.5, 1.2), wrot)
	for s in [-1, 1]:   # plants in big pots at the corners of the rug
		for t in [-1, 1]:
			var pp: Vector3 = wp + side * (s * 2.6) + Vector3(-sin(wrot), 0, -cos(wrot)) * (t * 2.4)
			if room_for(fac, zones, pp, Vector3(0.7, 1.4, 0.7)):
				_planter(fac, pp, rng)
				claim(fac, pp, Vector3(0.7, 1.4, 0.7))
	# Security turnstiles between the public end and the rest.
	for k in [-3.4, 0.0, 3.4]:
		var gp := at(f, gate_u, gate_v + k) if gate_axis else at(f, gate_u + k, gate_v)
		var grot := face(f, 1, 0) if gate_axis else face(f, 0, 1)
		if room_for(fac, zones, gp, Vector3(0.4, 1.0, 1.0), grot):
			_turnstile(fac, gp, grot)
			claim(fac, gp, Vector3(0.4, 1.0, 1.0), grot)
	# A water cooler and a directory board on whichever outside wall is free.
	_against_walls(fac, f, zones, rng, func(p: Vector3, rot_y: float, n: Vector3) -> bool:
		if not room_for(fac, zones, p, Vector3(0.5, 1.4, 0.5)):
			return false
		_water_cooler(fac, p, rot_y)
		claim(fac, p, Vector3(0.5, 1.4, 0.5))
		var board: Vector3 = p + Vector3(cos(rot_y), 0, -sin(rot_y)) * 1.6 - n * 0.27 + Vector3(0, 1.6, 0)
		var r := Node3D.new()
		fac.add_child(r)
		r.position = board
		r.rotation.y = rot_y + PI
		A.sbox(r, Vector3(1.4, 1.0, 0.04), Vector3.ZERO, "metal", Color(0.12, 0.13, 0.15), false, 0.4)
		B.label(r, "DIRECTORY", Vector3(0, 0.36, 0.025), 30, Color(0.9, 0.85, 0.7), "plate", 0.006)
		var lines := ["B-1  LABS  ARCHIVE", "B-2  PLANT  STORES", "B-3  ACCESS DENIED"]
		for i in lines.size():
			B.label(r, lines[i], Vector3(0, 0.12 - i * 0.18, 0.025), 22, Color(0.85, 0.82, 0.72), "type", 0.006)
		return true)


## The front desk: a front panel with a raised ledge, a work surface behind, a return at one end,
## monitors, a phone, a bell, the sign-in book, a lamp and a chair. -z faces the visitors.
static func _front_desk(fac, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := A.root(fac, pos, rot_y, Vector3(4.4, 1.15, 0.9))
	var panel := Color(0.88, 0.86, 0.8)
	var wood := Color(0.55, 0.38, 0.26)
	A.sbox(r, Vector3(4.4, 1.1, 0.12), Vector3(0, 0.55, -0.4), "cream", panel, false, 1.0)          # front
	A.sbox(r, Vector3(4.5, 0.05, 0.42), Vector3(0, 1.12, -0.32), "wood", wood, false, 1.0)           # ledge
	A.sbox(r, Vector3(4.42, 0.12, 0.02), Vector3(0, 0.75, -0.47), "paint", Color(0.9, 0.5, 0.12), false, 0.5)   # stripe
	A.sbox(r, Vector3(4.42, 0.06, 0.14), Vector3(0, 0.03, -0.42), "rubber", Color.WHITE, false, 0.5)  # kick
	B.label(r, "B.R.M.", Vector3(0, 0.45, -0.471), 70, Color(0.3, 0.28, 0.25), "plate", 0.006).rotation.y = PI
	A.sbox(r, Vector3(4.3, 0.04, 0.75), Vector3(0, 0.76, 0.05), "wood", Color(0.82, 0.78, 0.7), false, 1.0)  # work surface
	for x in [-2.1, 2.1]:
		A.sbox(r, Vector3(0.06, 0.74, 0.75), Vector3(x, 0.37, 0.05), "cream", panel, false, 1.0)
	var ret := A.box(r, Vector3(0.12, 1.1, 1.4), Vector3(2.15, 0.55, 0.65), "cream", panel, true, 1.0)   # return
	ret.name = "Return"
	A.sbox(r, Vector3(0.42, 0.05, 1.45), Vector3(2.15, 1.12, 0.65), "wood", wood, false, 1.0)
	for k in 2:   # monitors, one still on
		var mp := Vector3(-1.2 + k * 1.6, 0.78, 0.1)
		A.crt(r, mp, k == 0, Color(0.4, 1.0, 0.6) if k == 0 else Color(1, 0.6, 0.2))
	A.sbox(r, Vector3(0.45, 0.02, 0.16), Vector3(-1.2, 0.79, -0.2), "keys", Color.WHITE, false, 0.15)
	A.sbox(r, Vector3(0.22, 0.08, 0.18), Vector3(0.8, 0.82, -0.05), "plastic", Color(0.15, 0.15, 0.16), false, 0.2)   # phone
	A.sbox(r, Vector3(0.22, 0.04, 0.05), Vector3(0.8, 0.885, -0.05), "plastic", Color(0.12, 0.12, 0.13), false, 0.2)
	A.ssphere(r, 0.05, Vector3(-0.3, 1.16, -0.3), "metal", Color(0.85, 0.75, 0.45), 0.0, 0.7)   # bell
	A.sbox(r, Vector3(0.32, 0.03, 0.24), Vector3(0.3, 1.16, -0.32), "paper", Color(0.92, 0.9, 0.82), false, 0.2, Vector3(0, 0.2, 0))   # sign-in book
	A.sseg(r, Vector3(0.45, 1.17, -0.3), Vector3(0.6, 1.17, -0.38), 0.005, 0.005, "plastic", Color(0.1, 0.2, 0.6))
	A.sseg(r, Vector3(1.6, 0.78, 0.2), Vector3(1.55, 1.15, 0.15), 0.01, 0.01, "metal", Color(0.2, 0.2, 0.2))   # desk lamp
	A.scyl(r, 0.08, 0.1, Vector3(1.5, 1.15, 0.1), "metal", Color(0.15, 0.3, 0.2), false, "y", 0.03)
	P.chair(r, Vector3(-0.4, 0, 0.75), PI + rng.randf_range(-0.4, 0.4))
	P.papers(r, Vector3(-0.2, 0.79, 0.2), rng)


## A row of linked waiting-room seats on one beam. -z faces forward.
static func _beam_seat(fac, pos: Vector3, rot_y: float, n: int) -> void:
	var r := A.root(fac, pos, rot_y, Vector3(0.62 * n, 0.85, 0.6))
	var w := 0.62 * n
	var fr := Color(0.3, 0.3, 0.32)
	var seat: Color = [Color(0.25, 0.35, 0.55), Color(0.55, 0.25, 0.2), Color(0.3, 0.45, 0.4)][randi() % 3]
	A.sbox(r, Vector3(w, 0.06, 0.06), Vector3(0, 0.38, 0.05), "metal", fr, false, 0.5)
	for x in [-w / 2 + 0.25, w / 2 - 0.25]:
		A.sbox(r, Vector3(0.06, 0.38, 0.5), Vector3(x, 0.19, 0.05), "metal", fr, false, 0.5)
		A.sbox(r, Vector3(0.1, 0.02, 0.55), Vector3(x, 0.01, 0.05), "rubber", Color.WHITE, false, 0.3)
	for i in n:
		var x := -w / 2 + 0.31 + i * 0.62
		A.sbox(r, Vector3(0.54, 0.07, 0.48), Vector3(x, 0.45, 0.0), "canvas", seat, false, 0.3)
		var b := A.box(r, Vector3(0.54, 0.42, 0.06), Vector3(x, 0.72, 0.24), "canvas", seat, false, 0.3)
		b.rotation.x = -0.12
		if i > 0:
			A.sbox(r, Vector3(0.05, 0.05, 0.4), Vector3(x - 0.31, 0.62, 0.02), "plastic", Color(0.15, 0.15, 0.15), false, 0.2)   # armrest
	if randf() < 0.4:   # one seat torn
		A.sbox(r, Vector3(0.2, 0.072, 0.15), Vector3(-w / 2 + 0.31 + 0.62 * (randi() % n), 0.452, -0.05), "cream", Color(0.85, 0.8, 0.6), false, 0.2)


static func _planter(fac, pos: Vector3, rng: RandomNumberGenerator) -> void:
	A.scyl(fac, 0.3, 0.6, pos + Vector3(0, 0.3, 0), "plastic", Color(0.85, 0.83, 0.78), true, "y", 0.34)
	A.scyl(fac, 0.31, 0.02, pos + Vector3(0, 0.59, 0), "dirt", Color(0.5, 0.4, 0.3))
	if rng.randf() < 0.5:   # a dead plant: bare stems
		for k in 6:
			var a := TAU * k / 6.0 + rng.randf()
			A.sseg(fac, pos + Vector3(0, 0.6, 0), pos + Vector3(cos(a) * 0.25, rng.randf_range(1.1, 1.5), sin(a) * 0.25), 0.012, 0.004, "wood", Color(0.4, 0.3, 0.2))
	else:
		A.fern(fac, pos + Vector3(0, 0.58, 0), rng)


static func _turnstile(fac, pos: Vector3, rot_y: float) -> void:
	var r := A.root(fac, pos, rot_y, Vector3(0.3, 1.0, 0.9))
	var steel := Color(0.72, 0.73, 0.75)
	A.sbox(r, Vector3(0.3, 1.0, 0.9), Vector3(0, 0.5, 0), "metal", steel, false, 0.5)
	A.sbox(r, Vector3(0.32, 0.04, 0.92), Vector3(0, 1.01, 0), "metal", Color(0.2, 0.2, 0.22), false, 0.3)
	A.sbox(r, Vector3(0.12, 0.08, 0.2), Vector3(0, 1.05, -0.2), "plastic", Color(0.1, 0.1, 0.1), false, 0.2)   # card reader
	A.ssphere(r, 0.015, Vector3(0, 1.1, -0.25), "metal", Color(1, 0.15, 0.1), 3.0)
	for k in 3:   # tripod arms on the walkway side
		var a := TAU * k / 3.0
		A.sseg(r, Vector3(0.15, 0.85, 0), Vector3(0.6, 0.85 + sin(a) * 0.3, cos(a) * 0.3), 0.018, 0.018, "metal", steel)


static func _water_cooler(fac, pos: Vector3, rot_y: float) -> void:
	var r := A.root(fac, pos, rot_y, Vector3(0.4, 1.4, 0.4))
	A.sbox(r, Vector3(0.36, 0.95, 0.36), Vector3(0, 0.475, 0), "plastic", Color(0.9, 0.9, 0.88), false, 0.4)
	A.sbox(r, Vector3(0.2, 0.12, 0.02), Vector3(0, 0.82, -0.19), "metal", Color(0.3, 0.3, 0.3), false, 0.2)
	for s in [-1, 1]:
		A.scyl(r, 0.018, 0.05, Vector3(s * 0.05, 0.8, -0.2), "plastic", Color(0.8, 0.2, 0.2) if s < 0 else Color(0.2, 0.4, 0.85), false, "z")
	A.scyl(r, 0.15, 0.42, Vector3(0, 1.18, 0), "glass", Color(0.6, 0.8, 1.0))
	A.scyl(r, 0.13, 0.3, Vector3(0, 1.13, 0), "plastic", Color(0.55, 0.75, 0.95))


## Calls fn(position against the wall, rotation facing into the room, wall normal) along the room's
## outside walls until it returns true.
static func _against_walls(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator, fn: Callable) -> void:
	var spots := []
	for w in _outside_walls(fac, f):
		for off in [-3.5, 3.5, -1.0, 1.0]:
			spots.append([fac._wall_spot(w, off, 0.45), fac._facing(w), w[2]])
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = spots[i]
		spots[i] = spots[j]
		spots[j] = t
	for sp in spots:
		if fn.call(sp[0], sp[1], sp[2]):
			return


static func _outside_walls(fac, f: Dictionary) -> Array:
	var out := []
	for c in f.get("cells", []):
		for w in fac.cell_walls[c]:
			if not w[4] and not w[3]:
				out.append(w)
	return out


# --- canteen ---------------------------------------------------------------------------------------

static func _canteen(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator) -> void:
	var regs := regions(f)
	# The serving line goes against the first outside wall with room for it: a counter with a hot
	# plate and steel pans, a sneeze guard, a tray rail, and the menu chalked on a board above it.
	var serve: Array = regs[0]
	var mid_u := 0.0
	var sv := 0.0
	var run := 0.0
	var placed_line := false
	for reg in (regs if f.shape != "L" else [regs[1], regs[2], regs[0]]):
		for side in [-1.0, 1.0]:
			var wall_v: float = reg[2] if side < 0 else reg[3]
			if cell_of(at(f, (reg[0] + reg[1]) / 2.0, wall_v - side * 0.5) + f.ax * 0 + f.sd * (side * 1.0)) in f.cells:
				continue   # that side opens into more of the room: not a wall
			for length in [7.0, 5.5, 4.0]:
				for shift in [0.0, -1.8, 1.8, -3.0, 3.0]:
					var mu: float = (reg[0] + reg[1]) / 2.0 + shift
					var v: float = wall_v - side * 1.0
					var cp := at(f, mu, v)
					var crot := face(f, 0, -side)
					if absf(shift) + length / 2.0 > 5.5 or not room_for(fac, zones, cp, Vector3(length, 1.0, 1.2), crot):
						continue
					_serving_line(fac, cp, crot, length, rng)
					claim(fac, cp, Vector3(length, 1.0, 1.2), crot)
					var r := Node3D.new()
					fac.add_child(r)
					r.position = at(f, mu, wall_v - side * 0.17, 2.4)
					r.rotation.y = crot + PI
					A.sbox(r, Vector3(2.6, 1.0, 0.05), Vector3.ZERO, "board", Color(0.18, 0.22, 0.2), false, 0.6)
					A.sbox(r, Vector3(2.7, 1.1, 0.03), Vector3(0, 0, -0.02), "wood", Color(0.45, 0.3, 0.2), false, 0.6)
					B.label(r, "TODAY", Vector3(0, 0.32, 0.03), 40, Color(0.95, 0.95, 0.9), "chalk", 0.006)
					var dishes := ["PROTEIN LOAF   2cr", "GREY SOUP      1cr", "COFFEE (?)     1cr"]
					for i in dishes.size():
						B.label(r, dishes[i], Vector3(0, 0.05 - i * 0.17, 0.03), 24, Color(0.9, 0.92, 0.88), "chalk", 0.006)
					hanging_sign(fac, f, mu, v - side * 2.2, "CANTEEN", 0, -side)
					serve = reg
					mid_u = mu
					sv = v
					run = length
					placed_line = true
					break
				if placed_line:
					break
			if placed_line:
				break
		if placed_line:
			break
	# Rows of long tables with benches wherever there's room.
	var placed := 0
	for reg in regs:
		var tv0: float = reg[2] + 1.8
		var tv1: float = reg[3] - 1.8
		var v := tv0
		while v <= tv1 + 0.01:
			for u in [reg[0] + 3.2, reg[1] - 3.2]:
				var tp := at(f, u, v)
				var trot := face(f, 0, 1)
				if room_for(fac, zones, tp, Vector3(2.6, 0.8, 2.0), trot):
					_canteen_table(fac, tp, trot, rng)
					claim(fac, tp, Vector3(2.6, 0.8, 2.0), trot)
					placed += 1
			v += 2.9
	# Vending machines, side by side, on a free wall.
	_against_walls(fac, f, zones, rng, func(p: Vector3, rot_y: float, n: Vector3) -> bool:
		var p2: Vector3 = p + Vector3(cos(rot_y), 0, -sin(rot_y)) * 1.1
		if not room_for(fac, zones, p, Vector3(1, 2, 1), rot_y) or not room_for(fac, zones, p2, Vector3(1, 2, 1), rot_y):
			return false
		P.vending(fac, p, rot_y, rng)
		P.vending(fac, p2, rot_y, rng)
		claim(fac, p, Vector3(1, 2, 1), rot_y)
		claim(fac, p2, Vector3(1, 2, 1), rot_y)
		return true)
	# A stack of trays and a bin by the way out.
	var tp2 := at(f, mid_u + run / 2.0 + 0.8, sv)
	if placed_line and room_for(fac, zones, tp2, Vector3(0.6, 1.0, 0.6)):
		A.scyl(fac, 0.28, 0.75, tp2 + Vector3(0, 0.375, 0), "plastic", Color(0.3, 0.32, 0.3), true)
		A.scyl(fac, 0.3, 0.05, tp2 + Vector3(0, 0.77, 0), "plastic", Color(0.2, 0.2, 0.2))
		claim(fac, tp2, Vector3(0.6, 1.0, 0.6))


static func _serving_line(fac, pos: Vector3, rot_y: float, w: float, rng: RandomNumberGenerator) -> void:
	var r := A.root(fac, pos, rot_y, Vector3(w, 0.95, 0.9))
	var steel := Color(0.74, 0.75, 0.77)
	A.sbox(r, Vector3(w, 0.9, 0.8), Vector3(0, 0.45, 0.05), "metal", steel, false, 1.0)
	A.sbox(r, Vector3(w + 0.04, 0.04, 0.84), Vector3(0, 0.92, 0.05), "metal", steel.lightened(0.1), false, 0.6)
	A.sbox(r, Vector3(w, 0.05, 0.3), Vector3(0, 0.82, -0.5), "metal", steel.darkened(0.2), false, 0.6)   # tray rail
	for x in range(int(w / 0.6)):
		A.sseg(r, Vector3(-w / 2 + 0.3 + x * 0.6, 0.8, -0.38), Vector3(-w / 2 + 0.3 + x * 0.6, 0.8, -0.62), 0.008, 0.008, "metal", steel)
	var pans := int((w - 0.6) / 0.55)
	for i in pans:   # steel pans: some still with something in them
		var x := -w / 2 + 0.55 + i * 0.55
		A.sbox(r, Vector3(0.48, 0.02, 0.5), Vector3(x, 0.945, 0.05), "metal", Color(0.3, 0.3, 0.32), false, 0.3)
		A.sbox(r, Vector3(0.44, 0.03, 0.46), Vector3(x, 0.94, 0.05), "metal", steel.darkened(0.1), false, 0.3)
		if rng.randf() < 0.5:
			A.sbox(r, Vector3(0.4, 0.025, 0.42), Vector3(x, 0.945, 0.05), "flesh" if rng.randf() < 0.3 else "dirt",
				[Color(0.55, 0.45, 0.3), Color(0.45, 0.4, 0.2), Color(0.5, 0.25, 0.2)][rng.randi() % 3], false, 0.3)
	for s in [-1, 1]:   # sneeze guard on posts
		A.sseg(r, Vector3(s * (w / 2 - 0.1), 0.94, -0.15), Vector3(s * (w / 2 - 0.1), 1.45, -0.15), 0.015, 0.015, "metal", steel)
	var g := A.box(r, Vector3(w - 0.2, 0.02, 0.45), Vector3(0, 1.45, -0.05), "glass", Color.WHITE, false, 0.5)
	g.rotation.x = 0.35
	for k in rng.randi_range(4, 9):   # trays stacked at one end
		A.sbox(r, Vector3(0.45, 0.02, 0.33), Vector3(-w / 2 + 0.3, 0.84 + k * 0.022, -0.5), "plastic", Color(0.55, 0.42, 0.3), false, 0.3)


static func _canteen_table(fac, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := P.table(fac, pos, rot_y, 2.4, 0.85, "wood")
	for s in [-1, 1]:   # benches
		var bench := Node3D.new()
		r.add_child(bench)
		bench.position = Vector3(0, 0, s * 0.75)
		if rng.randf() < 0.15:   # knocked over
			bench.rotation = Vector3(s * 1.4, 0, 0)
			bench.position.y = 0.2
		A.sbox(bench, Vector3(2.3, 0.05, 0.3), Vector3(0, 0.45, 0), "wood", Color(0.6, 0.45, 0.3), false, 0.6)
		for x in [-0.95, 0.95]:
			A.sbox(bench, Vector3(0.05, 0.43, 0.25), Vector3(x, 0.215, 0), "metal", Color(0.3, 0.3, 0.32), false, 0.5)
	for k in rng.randi_range(0, 3):   # trays, cups
		var x := rng.randf_range(-1.0, 1.0)
		var z := rng.randf_range(-0.25, 0.25)
		if rng.randf() < 0.5:
			A.sbox(r, Vector3(0.45, 0.02, 0.33), Vector3(x, 0.79, z), "plastic", Color(0.55, 0.42, 0.3), false, 0.3, Vector3(0, rng.randf_range(-0.4, 0.4), 0))
		else:
			A.scyl(r, 0.04, 0.1, Vector3(x, 0.83, z), "plastic", Color(0.9, 0.9, 0.85))


# --- lab hall ------------------------------------------------------------------------------------------

static func _lab_hall(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator) -> void:
	# A spine of specimen tanks down the middle, joined by a pipe run above them; benches either side.
	var runs: Array = []   # [[u0, v0], [u1, v1]] straight runs for the spine
	match f.shape:
		"2x1": runs = [[Vector2(-8.5, 0), Vector2(8.5, 0)]]
		"L": runs = [[Vector2(0, 0), Vector2(15, 0)], [Vector2(0, 2.8), Vector2(0, 15)]]
		_: runs = [[Vector2(-9, 0), Vector2(9, 0)], [Vector2(0, -9), Vector2(0, -2.8)], [Vector2(0, 2.8), Vector2(0, 9)]]
	for run in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var n := int(a.distance_to(b) / 2.8) + 1
		var tanks := []
		for i in n:
			var q: Vector2 = a.lerp(b, float(i) / maxf(1.0, n - 1))
			var tp := at(f, q.x, q.y)
			if room_for(fac, zones, tp, Vector3(1.3, 2.4, 1.3)):
				P.specimen_tank(fac, tp, rng)
				claim(fac, tp, Vector3(1.3, 2.4, 1.3))
				tanks.append(tp)
		for i in tanks.size() - 1:   # pipe run from tank top to tank top, and a hazard ring round each
			A.pipe(fac, tanks[i] + Vector3(0, 2.6, 0), tanks[i + 1] + Vector3(0, 2.6, 0), 0.08, "metal", Color(0.6, 0.62, 0.65))
		for tp in tanks:
			A.sseg(fac, tp + Vector3(0, 2.42, 0), tp + Vector3(0, 2.6, 0), 0.06, 0.06, "metal", Color(0.4, 0.4, 0.42))
			A.sseg(fac, tp + Vector3(0, 2.6, 0), tp + Vector3(0, H, 0), 0.05, 0.05, "metal", Color(0.4, 0.4, 0.42))
			A.sring(fac, 0.95, 0.85, tp + Vector3(0, 0.004, 0), "hazard", Color(0.95, 0.9, 0.8))
	# Benches parallel to the spine.
	for reg in regions(f):
		for v in [reg[2] + 2.2, reg[3] - 2.2]:
			for u in [reg[0] + 3.0, reg[1] - 3.0]:
				var bp := at(f, u, v)
				var brot := face(f, 0, -signf(v - (reg[2] + reg[3]) / 2.0))
				if absf(v) < 2.6 or not room_for(fac, zones, bp, Vector3(2.2, 0.9, 1.0), brot):
					continue
				P.lab_bench(fac, bp, brot, rng)
				claim(fac, bp, Vector3(2.2, 0.9, 1.0), brot)
	hanging_sign(fac, f, 2.0 if f.shape != "L" else 5.0, 2.5, "CONTAINMENT", 1, 0, Color(0.95, 0.85, 0.3))
	_against_walls(fac, f, zones, rng, func(p: Vector3, rot_y: float, n: Vector3) -> bool:
		if not room_for(fac, zones, p, Vector3(1.6, 2.4, 1.0), rot_y):
			return false
		P.fume_hood(fac, p, rot_y, rng)
		claim(fac, p, Vector3(1.6, 2.4, 1.0), rot_y)
		return true)


# --- server hall ------------------------------------------------------------------------------------------

static func _server_hall(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator) -> void:
	# Raised-floor tile grid, rows of racks with a cable tray over each, an operator console.
	for reg in regions(f):
		var u0: float = reg[0]
		var v0: float = reg[2]
		for k in 13:
			stripe(fac, at(f, u0 + k, v0 + 0.2), at(f, u0 + k, v0 + 11.8), 0.03, Color(0.2, 0.22, 0.25))
			stripe(fac, at(f, u0 + 0.2, v0 + k), at(f, u0 + 11.8, v0 + k), 0.03, Color(0.2, 0.22, 0.25))
	var span_v: Array = [-6.0, 6.0] if f.shape == "2x1" else ([-6.0, 18.0] if f.shape == "L" else [-12.0, 12.0])
	var v: float = span_v[0] + 2.4
	var row := 0
	while v <= span_v[1] - 2.0:
		var face_dir := 1.0 if row % 2 == 0 else -1.0
		var first := Vector3.INF
		var last := Vector3.INF
		for reg in regions(f):
			if v < reg[2] + 0.8 or v > reg[3] - 0.8:
				continue
			var u: float = reg[0] + 1.5
			var placed := []
			while u <= reg[1] - 1.5:
				var rp := at(f, u, v)
				var rrot := face(f, 0, face_dir)
				if room_for(fac, zones, rp, Vector3(0.7, 2.1, 1.05), rrot):   # (checked against what was there before this row)
					P.server_rack(fac, rp, rrot, rng)
					placed.append([rp, rrot])
					if first == Vector3.INF:
						first = rp
					last = rp
				u += 0.72
			for pr in placed:
				claim(fac, pr[0], Vector3(0.7, 2.1, 1.05), pr[1])
		if first != Vector3.INF and first.distance_to(last) > 1.0:
			P.cable_tray(fac, first + Vector3(0, 2.5, 0), last + Vector3(0, 2.5, 0))
		v += 2.4 if row % 2 == 0 else 3.0
		row += 1
	# The console: a curved desk of monitors, all still on.
	var cpos := at(f, 0.0, 0.0) if f.shape != "L" else at(f, -2.0, -2.0)
	for dv in [0.0, 1.2, -1.2, 2.4]:
		var cp: Vector3 = cpos + f.sd * dv
		if room_for(fac, zones, cp, Vector3(2.6, 1.0, 1.2)):
			var r := P.table(fac, cp, face(f, -1, 0) if f.shape != "L" else face(f, 1, 0), 2.4, 0.9, "metal")
			for k in 3:
				A.crt(r, Vector3(-0.75 + k * 0.75, 0.78, 0.1), true, Color(0.4, 0.85, 1.0))
			P.chair(fac, cp + f.ax * (-1.0 if f.shape != "L" else 1.0), 0.0)
			claim(fac, cp, Vector3(2.6, 1.0, 1.2))
			break
	hanging_sign(fac, f, 0.0, span_v[0] + 1.2, "DATA CORE", 0, 1, Color(0.6, 0.85, 1.0))


# --- warehouse ------------------------------------------------------------------------------------------

static func _warehouse(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator) -> void:
	var lanes: Array = []   # [u0, u1, v] rack runs (pairs back to back), along u
	match f.shape:
		"2x1": lanes = [[-10.0, 10.0, 0.0]]
		"L": lanes = [[-3.5, 16.0, 0.0], [-3.5, 3.5, 12.0]]
		_: lanes = [[-10.0, 10.0, -6.0], [-10.0, 10.0, 6.0]]
	for ln in lanes:
		var u: float = ln[0] + 1.35
		while u <= ln[1] - 1.35:
			for s in [-1, 1]:
				var rp := at(f, u, ln[2] + s * 0.6)
				var rrot := face(f, 0, s)
				if room_for(fac, zones, rp, Vector3(2.7, 3.2, 1.1), rrot):
					P.pallet_rack(fac, rp, rrot, rng)
					claim(fac, rp, Vector3(2.7, 3.2, 1.1), rrot)
			u += 2.8
	# Single racks along the long outside walls.
	for w in _outside_walls(fac, f):
		for off in [-3.0, 3.0]:
			var sp: Vector3 = fac._wall_spot(w, off, 0.65)
			var rot: float = fac._facing(w)
			if room_for(fac, zones, sp, Vector3(2.7, 3.2, 1.1), rot):
				P.pallet_rack(fac, sp, rot, rng)
				claim(fac, sp, Vector3(2.7, 3.2, 1.1), rot)
	# Yellow lane lines either side of each aisle, and a forklift parked in one.
	for ln in lanes:
		for s in [-1, 1]:
			var v: float = ln[2] + s * 1.35
			stripe(fac, at(f, ln[0], v), at(f, ln[1], v), 0.1, Color(0.95, 0.75, 0.1))
	for tries in 8:
		var ln: Array = lanes[rng.randi() % lanes.size()]
		var fp := at(f, rng.randf_range(ln[0] + 2.0, ln[1] - 2.0), ln[2] + (3.0 if rng.randf() < 0.5 else -3.0))
		var frot := face(f, 1 if rng.randf() < 0.5 else -1, 0) + rng.randf_range(-0.3, 0.3)
		if room_for(fac, zones, fp, Vector3(1.3, 2.2, 2.8), frot):
			P.forklift(fac, fp, frot)
			claim(fac, fp, Vector3(1.3, 2.2, 2.8), frot)
			break
	# Loose pallets and wrapped loads waiting by the way in.
	for k in rng.randi_range(2, 4):
		for tries in 6:
			var reg: Array = regions(f)[rng.randi() % regions(f).size()]
			var pp := at(f, rng.randf_range(reg[0] + 1.5, reg[1] - 1.5), rng.randf_range(reg[2] + 1.5, reg[3] - 1.5))
			if room_for(fac, zones, pp, Vector3(1.3, 1.4, 1.3)):
				A.pallet(fac, pp)
				var h := rng.randf_range(0.6, 1.2)
				A.sbox(fac, Vector3(1.1, h, 1.0), pp + Vector3(0, 0.15 + h / 2.0, 0), "plastic", Color(0.85, 0.85, 0.82).darkened(rng.randf() * 0.2), true, 0.6)
				claim(fac, pp, Vector3(1.3, 1.4, 1.3))
				break
	hanging_sign(fac, f, 0.0 if f.shape != "L" else 8.0, 3.0, "STORES  BAY 4", 1, 0, Color(0.95, 0.8, 0.3))


# --- assembly line ------------------------------------------------------------------------------------------

static func _assembly(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator) -> void:
	var segs: Array = []   # conveyor runs [Vector2 a, Vector2 b] in frame coords
	match f.shape:
		"2x1": segs = [[Vector2(-9.5, 0), Vector2(9.5, 0)]]
		"L": segs = [[Vector2(0, 0), Vector2(15.5, 0)], [Vector2(0, 0), Vector2(0, 15.5)]]
		_: segs = [[Vector2(-9.5, 0), Vector2(9.5, 0)]]
	for sg in segs:
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		# Shorten from the far end until it's clear of the doorways.
		while a.distance_to(b) > 4.0:
			var pa := at(f, a.x, a.y)
			var pb := at(f, b.x, b.y)
			var mid := (pa + pb) / 2.0
			var rot := atan2(pb.x - pa.x, pb.z - pa.z)
			if room_for(fac, zones, mid, Vector3(1.1, 1.0, pa.distance_to(pb)), rot):
				_conveyor(fac, pa, pb, rng)
				claim(fac, mid, Vector3(1.1, 1.0, pa.distance_to(pb)), rot)
				# Presses straddling it, workstations along it.
				var n := int(pa.distance_to(pb) / 6.0)
				for i in n:
					var t := (i + 0.5) / n
					_press(fac, pa.lerp(pb, t), rot)
				var side := Vector3(cos(rot), 0, -sin(rot))
				var k := 1.5
				while k < pa.distance_to(pb) - 1.0:
					for s in [-1, 1]:
						var wp: Vector3 = pa.lerp(pb, k / pa.distance_to(pb)) + side * (s * 1.5)
						if rng.randf() < 0.55 and room_for(fac, zones, wp, Vector3(0.9, 0.9, 0.9)):
							P.chair(fac, wp, rot + (PI / 2 if s > 0 else -PI / 2) + rng.randf_range(-0.5, 0.5))
							A.crate(fac, wp + side * (s * 0.7), 0.5, rng)
							claim(fac, wp, Vector3(1.0, 0.9, 1.0))
					k += 2.4
				for s in [-1, 1]:   # hazard stripes either side of the line
					stripe(fac, pa + side * (s * 0.9), pb + side * (s * 0.9), 0.12, Color(0.95, 0.75, 0.1))
				var ep := pb + (pb - pa).normalized() * 1.0   # finished parts piling up at the end
				if room_for(fac, zones, ep, Vector3(1.2, 1.0, 1.2)):
					for c in rng.randi_range(2, 3):
						A.crate(fac, ep + Vector3(rng.randf_range(-0.3, 0.3), c * 0.0, rng.randf_range(-0.3, 0.3)), rng.randf_range(0.5, 0.8), rng)
					claim(fac, ep, Vector3(1.2, 1.0, 1.2))
				break
			b = a.move_toward(b, a.distance_to(b) - 1.5)
	if f.shape == "L":   # the turn: a roller turntable in the corner
		var tp := at(f, 0, 0)
		A.scyl(fac, 0.75, 0.9, tp + Vector3(0, 0.45, 0), "metal", Color(0.35, 0.35, 0.37), true)
		A.scyl(fac, 0.72, 0.04, tp + Vector3(0, 0.92, 0), "grate", Color.WHITE)
	_against_walls(fac, f, zones, rng, func(p: Vector3, rot_y: float, n: Vector3) -> bool:
		if not room_for(fac, zones, p, Vector3(1.6, 1.2, 1.6), rot_y):
			return false
		P.control_panel(fac, p, rot_y, rng)
		claim(fac, p, Vector3(1.6, 1.2, 1.6), rot_y)
		return true)
	hanging_sign(fac, f, 4.0 if f.shape != "L" else 9.0, 3.0, "LINE 2   KEEP CLEAR", 1, 0, Color(0.95, 0.8, 0.3))


## A belt conveyor from a to b (local, on the floor): legs, side rails, rollers under a rubber belt.
static func _conveyor(fac, a: Vector3, b: Vector3, rng: RandomNumberGenerator) -> void:
	var length := a.distance_to(b)
	var r := A.root(fac, (a + b) / 2.0, atan2(b.x - a.x, b.z - a.z), Vector3(0.95, 0.95, length))
	var steel := Color(0.5, 0.52, 0.55)
	A.sbox(r, Vector3(0.8, 0.03, length), Vector3(0, 0.92, 0), "rubber", Color.WHITE, false, 1.0)    # belt
	for s in [-1, 1]:
		A.sbox(r, Vector3(0.06, 0.16, length), Vector3(s * 0.44, 0.88, 0), "metal", steel, false, 1.0)   # side rails
		A.sbox(r, Vector3(0.04, 0.06, length), Vector3(s * 0.47, 1.0, 0), "paint", Color(0.95, 0.75, 0.1), false, 1.0)
	var z := -length / 2 + 0.3
	while z < length / 2:
		A.scyl(r, 0.045, 0.82, Vector3(0, 0.86, z), "metal", Color(0.7, 0.7, 0.72), false, "x")
		z += 0.3
	z = -length / 2 + 0.4
	while z < length / 2:
		for s in [-1, 1]:
			A.sbox(r, Vector3(0.06, 0.8, 0.06), Vector3(s * 0.38, 0.4, z), "metal", steel.darkened(0.2), false, 0.5)
		A.sbox(r, Vector3(0.82, 0.05, 0.05), Vector3(0, 0.25, z), "metal", steel.darkened(0.2), false, 0.5)
		z += 1.8
	for k in rng.randi_range(2, 5):   # parts left on the belt
		A.sbox(r, Vector3(rng.randf_range(0.2, 0.4), rng.randf_range(0.1, 0.25), rng.randf_range(0.2, 0.4)), Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-length / 2 + 0.5, length / 2 - 0.5)), "metal",
			Color(0.6, 0.55, 0.5), false, 0.3, Vector3(0, rng.randf() * TAU, 0))


## A stamping press over the belt: two columns, a crown with the motor, the ram stopped half way down.
static func _press(fac, pos: Vector3, rot_y: float) -> void:
	var r := A.root(fac, pos, rot_y)
	var green := Color(0.35, 0.45, 0.35)
	for s in [-1, 1]:
		A.sbox(r, Vector3(0.35, 2.7, 0.6), Vector3(s * 0.75, 1.35, 0), "metal", green, true, 1.0)
		A.sbox(r, Vector3(0.36, 0.3, 0.62), Vector3(s * 0.75, 0.15, 0), "hazard", Color(0.95, 0.9, 0.8), false, 0.5)
	A.sbox(r, Vector3(1.9, 0.6, 0.8), Vector3(0, 3.0, 0), "metal", green, false, 1.0)
	A.scyl(r, 0.3, 0.5, Vector3(0.5, 3.45, 0), "metal", Color(0.3, 0.3, 0.32), false, "x")   # motor
	A.scyl(r, 0.12, 0.8, Vector3(0, 2.3, 0), "metal", Color(0.75, 0.75, 0.78))                # ram
	A.sbox(r, Vector3(0.7, 0.2, 0.5), Vector3(0, 1.85, 0), "metal", Color(0.3, 0.3, 0.32), false, 0.5)
	A.ssphere(r, 0.06, Vector3(-0.75, 2.8, -0.32), "cream", Color(1, 0.4, 0.1), 3.0)          # warning lamp


# --- gut hall (flesh) ------------------------------------------------------------------------------------

static func _gut_hall(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator) -> void:
	var meat := Color(0.62, 0.32, 0.3)
	var pale := Color(0.92, 0.62, 0.6)     # the heart is paler and wetter than the walls round it
	var dark := Color(0.35, 0.12, 0.12)
	var bone := Color(0.88, 0.82, 0.7)
	# The heart: a swollen mass, lumps round its base, great arteries rising into the ceiling. It beats.
	var hc := at(f, 0, 0)
	if room_for(fac, zones, hc, Vector3(3.6, 3.0, 3.6)):
		var heart := Node3D.new()
		fac.add_child(heart)
		heart.position = hc
		Merge.live(heart)
		var mass := Node3D.new()
		heart.add_child(mass)
		A.ssphere(mass, 1.35, Vector3(0, 1.25, 0), "flesh", pale, 0.0, 1.15)
		for k in 6:   # chambers bulging out of it
			var a := TAU * k / 6.0 + rng.randf()
			A.ssphere(mass, rng.randf_range(0.55, 0.85), Vector3(cos(a) * 0.95, rng.randf_range(0.7, 1.9), sin(a) * 0.95), "flesh", pale.darkened(rng.randf_range(0.05, 0.25)), 0.0, rng.randf_range(0.8, 1.15))
		for k in 8:   # lumps holding it to the floor
			var a := TAU * k / 8.0 + rng.randf()
			A.ssphere(mass, rng.randf_range(0.35, 0.6), Vector3(cos(a) * 1.4, 0.2, sin(a) * 1.4), "flesh", meat, 0.0, 0.6)
		for k in 9:   # glowing sores
			var a := rng.randf() * TAU
			var y := rng.randf_range(0.6, 2.0)
			A.ssphere(mass, rng.randf_range(0.07, 0.14), Vector3(cos(a) * 1.3, y, sin(a) * 1.3), "flesh", Color(1, 0.75, 0.4), 3.0)
		for k in 3:   # arteries: up out of the top, bending into the ceiling
			var a := TAU * k / 3.0 + rng.randf()
			var p0 := Vector3(cos(a) * 0.5, 2.3, sin(a) * 0.5)
			var p1 := Vector3(cos(a) * 0.9, 3.2, sin(a) * 0.9)
			var p2 := Vector3(cos(a) * 1.9, H - 0.15, sin(a) * 1.9)
			A.sseg(heart, p0, p1, 0.32, 0.28, "flesh", meat)
			A.sseg(heart, p1, p2, 0.28, 0.24, "flesh", meat)
			A.ssphere(heart, 0.3, p1, "flesh", meat)
			A.ssphere(heart, 0.5, p2 + Vector3(0, 0.15, 0), "flesh", meat.darkened(0.15), 0.0, 0.5)   # where it grows into the ceiling
		var glow := OmniLight3D.new()   # it lights the room from inside, faintly
		glow.light_color = Color(1, 0.45, 0.3)
		glow.light_energy = 0.8
		glow.omni_range = 7.0
		heart.add_child(glow)
		glow.position.y = 1.3
		var tw := mass.create_tween().set_loops()   # lub-dub
		tw.tween_property(mass, "scale", Vector3(1.07, 1.05, 1.07), 0.12).set_trans(Tween.TRANS_SINE)
		tw.tween_property(mass, "scale", Vector3(1.0, 1.0, 1.0), 0.16).set_trans(Tween.TRANS_SINE)
		tw.tween_property(mass, "scale", Vector3(1.04, 1.03, 1.04), 0.1).set_trans(Tween.TRANS_SINE)
		tw.tween_property(mass, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(0.5)
		var gt := glow.create_tween().set_loops()
		gt.tween_property(glow, "light_energy", 1.4, 0.12)
		gt.tween_property(glow, "light_energy", 0.7, 0.9)
		gt.tween_interval(0.3)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 1.6
		sh.height = 2.8
		cs.shape = sh
		cs.position.y = 1.4
		body.add_child(cs)
		heart.add_child(body)
		claim(fac, hc, Vector3(3.6, 2.8, 3.6))
		for k in 10:   # veins out across the floor, wandering, thinning, never leaving the room
			var a := TAU * k / 10.0 + rng.randf_range(-0.2, 0.2)
			var dir := Vector3(cos(a), 0, sin(a))
			var p1 := hc + dir * 1.5 + Vector3(0, 0.06, 0)
			for step in 9:
				dir = (dir + Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))).normalized()
				var nx := p1 + dir * 1.1
				if not cell_of(nx) in f.cells:
					break
				var rad := 0.09 - step * 0.008
				A.sseg(fac, p1, nx, rad, rad - 0.006, "flesh", dark)
				p1 = nx
	# Pillars of flesh, floor to ceiling, swelling and pinching as they go.
	for reg in regions(f):
		for k in 2:
			var pp := at(f, rng.randf_range(reg[0] + 2.5, reg[1] - 2.5), rng.randf_range(reg[2] + 2.5, reg[3] - 2.5))
			if not room_for(fac, zones, pp, Vector3(1.4, H, 1.4)):
				continue
			var prev := pp
			for st in 6:
				var nxt := pp + Vector3(rng.randf_range(-0.2, 0.2), (st + 1) * H / 6.0, rng.randf_range(-0.2, 0.2))
				var rad := 0.5 + absf(st - 2.5) * 0.09 + rng.randf_range(-0.05, 0.05)
				A.sseg(fac, prev, nxt, rad, rad * 0.95, "flesh", meat.darkened(rng.randf() * 0.2))
				A.ssphere(fac, rad * 1.05, nxt, "flesh", meat.darkened(rng.randf() * 0.2), 0.0, 0.7)
				prev = nxt
			A.ssphere(fac, 0.75, pp + Vector3(0, 0.15, 0), "flesh", meat.darkened(0.1), 0.0, 0.5)   # spreading foot
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var sh := CylinderShape3D.new()
			sh.radius = 0.6
			sh.height = H
			cs.shape = sh
			cs.position = pp + Vector3(0, H / 2.0, 0)
			body.add_child(cs)
			fac.add_child(body)
			claim(fac, pp, Vector3(1.4, H, 1.4))
	# Ribs: up each wall from the floor, over the ceiling, and down the other side, like being
	# inside a ribcage. Where the room carries on past a side, the rib just runs on overhead.
	for reg in regions(f):
		var u: float = reg[0] + 1.3
		while u <= reg[1] - 1.0:
			var clear := func(v: float) -> bool: return zones.all(func(z): return not z.grow(0.3).has_point(at(f, u, v, 0.5)))   # (not down across a doorway)
			var lo_wall: bool = not cell_of(at(f, u, reg[2] - 0.5)) in f.cells and clear.call(reg[2] + 0.6)
			var hi_wall: bool = not cell_of(at(f, u, reg[3] + 0.5)) in f.cells and clear.call(reg[3] - 0.6)
			var pts: Array = []
			if lo_wall:
				pts += [Vector2(reg[2] + 0.25, 0.15), Vector2(reg[2] + 0.3, 1.5), Vector2(reg[2] + 0.55, 2.8), Vector2(reg[2] + 1.3, 3.6)]
			else:
				pts.append(Vector2(reg[2], H - 0.25))
			for t in [0.3, 0.5, 0.7]:
				pts.append(Vector2(lerpf(reg[2], reg[3], t), H - 0.18))
			if hi_wall:
				pts += [Vector2(reg[3] - 1.3, 3.6), Vector2(reg[3] - 0.55, 2.8), Vector2(reg[3] - 0.3, 1.5), Vector2(reg[3] - 0.25, 0.15)]
			else:
				pts.append(Vector2(reg[3], H - 0.25))
			for i in pts.size() - 1:
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				A.sseg(fac, at(f, u, a.x, a.y), at(f, u, b.x, b.y), 0.13, 0.12, "cream", bone)
				A.ssphere(fac, 0.13, at(f, u, b.x, b.y), "cream", bone)
			u += 2.4
	for k in rng.randi_range(3, 6):   # pools of something on the floor
		var reg: Array = regions(f)[rng.randi() % regions(f).size()]
		fac._sheen(at(f, rng.randf_range(reg[0] + 1, reg[1] - 1), rng.randf_range(reg[2] + 1, reg[3] - 1)), Vector2(rng.randf_range(1.5, 3.0), rng.randf_range(1.0, 2.2)), rng)


# --- pillar hall (backrooms) ------------------------------------------------------------------------------

static func _pillar_hall(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator) -> void:
	var theme: Dictionary = fac.theme
	for reg in regions(f):
		for su in [0.3, 0.7]:
			for sv in [0.3, 0.7]:
				var pp := at(f, lerpf(reg[0], reg[1], su), lerpf(reg[2], reg[3], sv))
				if not room_for(fac, zones, pp, Vector3(1.0, H, 1.0)):
					continue
				A.sbox(fac, Vector3(0.9, H, 0.9), pp + Vector3(0, H / 2.0, 0), theme.wall_kind, theme.wall, true, 2.0)
				A.sbox(fac, Vector3(0.94, 1.1, 0.94), pp + Vector3(0, 0.55, 0), theme.band_kind, theme.band, false, 1.5)
				A.sbox(fac, Vector3(0.96, 0.08, 0.96), pp + Vector3(0, 0.04, 0), "wood", Color(0.55, 0.45, 0.32), false, 1.0)   # skirting
				claim(fac, pp, Vector3(1.0, H, 1.0))
				if rng.randf() < 0.3:   # a damp patch at its foot
					fac._sheen(pp + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8)), Vector2(1.4, 1.0), rng)
	# The things that make it wrong: a doorframe standing on its own, a chair facing nothing,
	# an EXIT sign over a blank wall, soaked carpet.
	for tries in 10:
		var reg: Array = regions(f)[rng.randi() % regions(f).size()]
		var dp := at(f, rng.randf_range(reg[0] + 2.5, reg[1] - 2.5), rng.randf_range(reg[2] + 2.5, reg[3] - 2.5))
		var rot := rng.randf_range(-0.2, 0.2) + (PI / 2.0 if rng.randf() < 0.5 else 0.0)
		if room_for(fac, zones, dp, Vector3(1.6, 2.4, 0.5), rot):
			var r := A.root(fac, dp, rot)
			for s in [-1, 1]:
				A.sbox(r, Vector3(0.12, 2.2, 0.18), Vector3(s * 0.55, 1.1, 0), "wood", Color(0.7, 0.6, 0.45), true, 1.0)
			A.sbox(r, Vector3(1.22, 0.14, 0.18), Vector3(0, 2.27, 0), "wood", Color(0.7, 0.6, 0.45), false, 1.0)
			var door := A.root(r, Vector3(-0.5, 0, 0), 0.9)
			A.sbox(door, Vector3(0.98, 2.1, 0.04), Vector3(0.49, 1.05, 0), "wood", Color(0.75, 0.65, 0.5), false, 1.0)
			A.ssphere(door, 0.03, Vector3(0.88, 1.0, -0.04), "brass")
			claim(fac, dp, Vector3(1.4, 2.4, 0.4), rot)
			break
	for tries in 10:
		var reg: Array = regions(f)[rng.randi() % regions(f).size()]
		var cp := at(f, rng.randf_range(reg[0] + 1.5, reg[1] - 1.5), rng.randf_range(reg[2] + 1.5, reg[3] - 1.5))
		if room_for(fac, zones, cp, Vector3(0.6, 0.9, 0.6)):
			P.chair(fac, cp, rng.randf() * TAU, "wood")
			claim(fac, cp, Vector3(0.6, 0.9, 0.6))
			break
	var walls := _outside_walls(fac, f)
	if not walls.is_empty():
		var w: Array = walls[rng.randi() % walls.size()]
		var sp: Vector3 = fac._wall_spot(w, rng.randf_range(-2.5, 2.5), 0.16) + Vector3(0, 2.6, 0)
		var plate := Node3D.new()
		fac.add_child(plate)
		plate.position = sp
		plate.rotation.y = fac._facing(w) + PI
		A.sbox(plate, Vector3(0.7, 0.25, 0.06), Vector3.ZERO, "plastic", Color(0.12, 0.12, 0.12), false, 0.3)
		A.glow(plate, Vector3(0.6, 0.17, 0.01), Vector3(0, 0, 0.032), Color(0.2, 1.0, 0.35), 2.5)
		B.label(plate, "EXIT", Vector3(0, 0, 0.04), 30, Color(0.05, 0.12, 0.05), "plate", 0.006)
	for k in rng.randi_range(2, 4):
		var reg: Array = regions(f)[rng.randi() % regions(f).size()]
		fac._sheen(at(f, rng.randf_range(reg[0] + 1, reg[1] - 1), rng.randf_range(reg[2] + 1, reg[3] - 1)), Vector2(rng.randf_range(1.5, 3.5), rng.randf_range(1.2, 2.5)), rng)
	for reg in regions(f):   # fluorescent ceiling panels on a grid (the real lights are in the middle)
		for su in [0.25, 0.75]:
			for sv in [0.25, 0.75]:
				if rng.randf() < 0.8:
					A.glow(fac, Vector3(1.2, 0.03, 0.6), at(f, lerpf(reg[0], reg[1], su), lerpf(reg[2], reg[3], sv), H - 0.02), Color(1, 0.97, 0.82), 2.0 if rng.randf() < 0.85 else 0.2)


# --- open office (backrooms) -------------------------------------------------------------------------------

static func _open_office(fac, f: Dictionary, zones: Array, rng: RandomNumberGenerator) -> void:
	for reg in regions(f):
		for su in [0.27, 0.73]:
			for sv in [0.28, 0.72]:
				var p := at(f, lerpf(reg[0], reg[1], su), lerpf(reg[2], reg[3], sv))
				var dirv := -1.0 if sv < 0.5 else 1.0
				var rot := face(f, 0, -dirv)
				if not room_for(fac, zones, p, Vector3(2.2, 1.4, 2.2), rot):
					continue
				A.desk(fac, p, rot + PI, rng)
				P.partition(fac, p + Vector3(sin(rot), 0, cos(rot)) * -0.1, rot + PI, 1.0 if su < 0.5 else -1.0)
				if rng.randf() < 0.8:
					P.chair(fac, p + Vector3(-sin(rot), 0, -cos(rot)) * -0.75, rot + rng.randf_range(-0.6, 0.6))
				if rng.randf() < 0.5:
					A.crt(fac, p + Vector3(0, 0.79, 0), rng.randf() < 0.3)
				claim(fac, p, Vector3(2.2, 1.4, 2.2), rot)
	for k in rng.randi_range(2, 4):
		var reg: Array = regions(f)[rng.randi() % regions(f).size()]
		P.papers(fac, fac._inside(at(f, rng.randf_range(reg[0] + 1, reg[1] - 1), rng.randf_range(reg[2] + 1, reg[3] - 1)), 1.3), rng)
