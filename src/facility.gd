# Procedural underground facility: a grid of 12 m rooms grown from the elevator room.
# The layout is pure data from one seed, so every client can rebuild the same map later.
extends Node3D

const Data = preload("res://src/data.gd")
const Merge = preload("res://src/merge.gd")
const A = preload("res://src/art.gd")
const P = preload("res://src/props.gd")
const Door = preload("res://src/door.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

const CELL := 12.0
const H := 4.0
const DOOR_W := 2.4
const DOOR_H := 2.8
const PIT := 3.0
const VENT_W := 1.1
const VENT_H := 1.3
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var main
var layout := {}
var theme := {}
var astar := AStar3D.new()
var ids := {}          # Vector2i -> astar id
var cell_of_id := {}   # astar id -> Vector2i
var doors := {}        # bulkhead code -> door body
var crates: Array[AABB] = []
var flicker: Array[OmniLight3D] = []
var theme_id := ""
var overgrown := false
var kinds := {}         # cell -> room archetype
var cameras: Array = []  # [{name, node, light}] security cameras for the terminal
var _wet := StandardMaterial3D.new()
var vault_cell := Vector2i(999, 999)   # dead end behind its own bulkhead, best loot inside
var vault_code := ""
var vault_spots: Array[Vector3] = []   # where the vault's loot goes (local)
var loot_spots: Array[Vector3] = []    # raised spots worth checking: mezzanines (local)
var vents := {}                        # edge -> offset along the shared wall
const NO_VENT := ["start", "pit", "tunnel", "vault"]   # puddles: dark and glossy, catch the flashlight


## cells: Array[Vector2i]; links: cell -> Array of linked neighbour cells; doors: code -> [a, b] edge.
static func gen_layout(seed: int, rooms: int, n_doors: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var links := {Vector2i.ZERO: []}
	while cells.size() < rooms:
		var from: Vector2i = cells[rng.randi() % cells.size()]
		var to: Vector2i = from + DIRS[rng.randi() % 4]
		if links.has(to):
			continue
		cells.append(to)
		links[to] = []
		_link(links, from, to)
	# A few extra loops so it's not a pure tree (escape routes matter).
	for c in cells:
		for d in DIRS:
			if links.has(c + d) and rng.randf() < 0.12:
				_link(links, c, c + d)
	var door_edges := {}
	for i in 60:
		if door_edges.size() >= n_doors or rooms < 3:
			break
		var a: Vector2i = cells[rng.randi() % cells.size()]
		if a == Vector2i.ZERO:
			continue
		var b: Vector2i = links[a][rng.randi() % links[a].size()]
		if b == Vector2i.ZERO:
			continue
		var code := "%s%d%d" % [char(65 + rng.randi() % 26), rng.randi() % 10, rng.randi() % 10]
		if not door_edges.has(code) and not door_edges.values().has(edge(a, b)):
			door_edges[code] = edge(a, b)
	return {"cells": cells, "links": links, "doors": door_edges}


static func _link(links: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not links[a].has(b):
		links[a].append(b)
		links[b].append(a)


static func edge(a: Vector2i, b: Vector2i) -> Array:
	return [a, b] if (a.x < b.x or (a.x == b.x and a.y < b.y)) else [b, a]


func build(seed: int, rooms: int, theme_name: String) -> void:
	theme = Data.THEMES[theme_name]
	_wet.albedo_color = Color(0.04, 0.045, 0.05)
	_wet.roughness = 0.04
	_wet.metallic = 0.2
	theme_id = theme_name
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	overgrown = theme_name in ["FACTORY", "LAB"] and rng.randf() < 0.35
	layout = gen_layout(seed, rooms, int(theme.bulkheads) + rng.randi() % 2)
	_pick_vault(rng)
	var door_at := {}
	for code in layout.doors:
		door_at[layout.doors[code]] = code
	for c: Vector2i in layout.cells:
		kinds[c] = "vault" if c == vault_cell else _pick_kind(c, rng)
	# Crawl vents through some walls between rooms that don't connect: shortcuts for crouching people.
	for c: Vector2i in layout.cells:
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = c + d
			if not layout.links.has(n) or layout.links[c].has(n) or kinds[c] in NO_VENT or kinds[n] in NO_VENT:
				continue
			if rng.randf() < 0.45:
				var off := _side(rng) * rng.randf_range(1.8, 3.6)
				vents[edge(c, n)] = off
				var mid := Vector3(c.x * CELL, 0, c.y * CELL) + Vector3(d.x, 0, d.y) * (CELL / 2.0) + (Vector3(off, 0, 0) if d.y != 0 else Vector3(0, 0, off))
				crates.append(AABB(mid - Vector3(1.0, 0, 1.0), Vector3(2.0, 0.01, 2.0)))   # keep it clear
	for c: Vector2i in layout.cells:
		var o := Vector3(c.x * CELL, 0, c.y * CELL)
		var kind: String = kinds[c]
		if kind != "pit":
			A.box(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, -0.1, 0), theme.floor_kind, theme.floor, true, 2.0)
		if c == Vector2i.ZERO:
			_ceiling_with_hole(o)
		elif theme_id == "BACKROOMS":
			_drop_ceiling(o, rng)
		else:
			A.box(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, H + 0.1, 0), theme.ceil_kind, theme.ceiling, true, 2.0)
		var walls := []  # [center, along_x, normal_into_room, has_door]
		for d: Vector2i in DIRS:
			var n := c + d
			var linked: bool = layout.links[c].has(n)
			var center := o + Vector3(d.x, 0, d.y) * (CELL / 2.0)
			walls.append([center, d.y != 0, -Vector3(d.x, 0, d.y), linked or vents.has(edge(c, n))])   # [3] = keep clear (door or vent)
			# Shared walls are built once, by the cell on the -x / -z side.
			if layout.links.has(n) and (d.x < 0 or d.y < 0):
				continue
			_wall(center, d.y != 0, linked, vents.get(edge(c, n), INF))
			if linked and door_at.has(edge(c, n)):
				_bulkhead(center, d.y != 0, door_at[edge(c, n)])
			elif linked and rng.randf() < 0.55 and kinds[c] != "tunnel" and kinds[n] != "tunnel":
				_hinged_door(center, d.y != 0, rng)
		if c != Vector2i.ZERO:
			_dress(c, o, walls, rng)
			if not kinds[c] in ["pit", "tunnel", "vault"] and rng.randf() < 0.35:
				_supply_crate(o, walls, rng)
		if c == Vector2i.ZERO or kind in ["pit", "tunnel"] or rng.randf() < theme.light_chance:
			_light(o, walls, rng)
		if kind != "tunnel" and (c == Vector2i.ZERO or rng.randf() < 0.35):
			_camera(o, rng)
		ids[c] = ids.size()
		cell_of_id[ids[c]] = c
		astar.add_point(ids[c], Vector3(c.x, 0, c.y))
	for c in layout.cells:
		for n in layout.links[c]:
			if not astar.are_points_connected(ids[c], ids[n]):
				astar.connect_points(ids[c], ids[n])
	Merge.bake(self, 6.0)   # thousands of primitives -> a few meshes per room


func _pick_kind(c: Vector2i, rng: RandomNumberGenerator) -> String:
	if c == Vector2i.ZERO:
		return "start"
	var l: Array = layout.links[c]
	var straight: bool = l.size() == 2 and (l[0] - c) == -(l[1] - c)
	if straight and theme_id != "BACKROOMS" and rng.randf() < 0.6:
		return "tunnel"
	var table: Dictionary = {
		"FACTORY": {"storage": 3, "machine": 3, "pit": 2, "collapsed": 1, "break": 1, "office": 1, "atrium": 2},
		"LAB": {"lab": 3, "office": 3, "server": 2, "storage": 1, "break": 1, "atrium": 1},
		"FLESH": {"lab": 2, "machine": 2, "pit": 1, "storage": 1, "collapsed": 1, "atrium": 1},
		"BACKROOMS": {"empty": 4, "office": 1, "storage": 1},
	}[theme_id]
	var pool := []
	for k in table:
		for i in table[k]:
			pool.append(k)
	return pool[rng.randi() % pool.size()]


func _drop_ceiling(o: Vector3, rng: RandomNumberGenerator) -> void:
	A.box(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, H + 0.1, 0), "ceiling_tile", Color.WHITE, true, 2.0)
	for p in [Vector3(-3, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, 3), Vector3(3, 0, -3)]:
		if rng.randf() < 0.7:
			A.glow(self, Vector3(1.2, 0.03, 1.2), o + p + Vector3(0, H - 0.01, 0), Color(1, 0.95, 0.75), 2.5)


## Hinged door in a doorway; half of them start open.
func _hinged_door(center: Vector3, along_x: bool, rng: RandomNumberGenerator) -> void:
	var d := Door.new()
	add_child(d)
	if along_x:
		d.position = center + Vector3(-DOOR_W / 2 + 0.12, 0, 0)   # hinges clear of the frame, so open leaves never lie flush on it
	else:
		d.position = center + Vector3(0, 0, -DOOR_W / 2 + 0.12)
		d.rotation.y = -PI / 2
	var kind: String = {"FACTORY": "riveted", "LAB": "cream", "FLESH": "riveted", "BACKROOMS": "wood"}[theme_id]
	var tint: Color = {"FACTORY": Color(0.7, 0.65, 0.55), "LAB": Color.WHITE, "FLESH": Color(0.7, 0.45, 0.4), "BACKROOMS": Color(0.85, 0.75, 0.6)}[theme_id]
	d.setup(DOOR_W - 0.24, DOOR_H - 0.05, kind, tint, rng.randf() < 0.5, 1.0 if rng.randf() < 0.5 else -1.0)


func _ceiling_with_hole(o: Vector3) -> void:
	# The elevator shaft comes down through the middle of the start room.
	var hole := 2.3
	var side := (CELL / 2.0 - hole)
	for s in [-1, 1]:
		A.box(self, Vector3(CELL, 0.2, side), o + Vector3(0, H + 0.1, s * (hole + side / 2.0)), theme.ceil_kind, theme.ceiling, true)
		A.box(self, Vector3(side, 0.2, hole * 2), o + Vector3(s * (hole + side / 2.0), H + 0.1, 0), theme.ceil_kind, theme.ceiling, true)


func _wall(center: Vector3, along_x: bool, door: bool, vent := INF) -> void:
	var a := (center.x if along_x else center.z)
	var c := (center.z if along_x else center.x)
	var band := 1.1
	var holes := [[a, DOOR_W, 0.0, DOOR_H]] if door else []
	var holes_up := [[a, DOOR_W, -10.0, DOOR_H - band]] if door else []
	if vent != INF:
		holes.append([a + vent, VENT_W, 0.0, VENT_H])
		holes_up.append([a + vent, VENT_W, -10.0, VENT_H - band])
		_vent(center + (Vector3(vent, 0, 0) if along_x else Vector3(0, 0, vent)), along_x)
	A.wall(self, a - CELL / 2, a + CELL / 2, c, band, 0.34, holes, theme.band_kind, theme.band, along_x, 0.0, true, 1.5)
	A.wall(self, a - CELL / 2, a + CELL / 2, c, H - band, 0.3, holes_up, theme.wall_kind, theme.wall, along_x, band, true, 2.0)
	if door:
		var fc := Color(0.45, 0.42, 0.4)
		for s in [-1, 1]:
			# Frame faces sit 1.5 cm proud of the opening's own faces: never flush, never flickering.
			var p := center + (Vector3(s * (DOOR_W / 2 + 0.045), DOOR_H / 2 - 0.0075, 0) if along_x else Vector3(0, DOOR_H / 2 - 0.0075, s * (DOOR_W / 2 + 0.045)))
			A.box(self, Vector3(0.12, DOOR_H - 0.015, 0.42) if along_x else Vector3(0.42, DOOR_H - 0.015, 0.12), p, "metal", fc, false)
		A.box(self, Vector3(DOOR_W + 0.24, 0.14, 0.42) if along_x else Vector3(0.42, 0.14, DOOR_W + 0.24), center + Vector3(0, DOOR_H + 0.055, 0), "metal", fc, false)


func _bulkhead(center: Vector3, along_x: bool, code: String) -> void:
	var size := Vector3(DOOR_W, DOOR_H, 0.18) if along_x else Vector3(0.18, DOOR_H, DOOR_W)
	var door := B.interactable(self, size, center + Vector3(0, DOOR_H / 2, 0), Color.WHITE,
		"Manual override on bulkhead %s (LOUD)" % code, set_door.bind(code, true, true), 6.0)
	door.get_child(1).material_override = A.mat("hazard", Color(0.9, 0.85, 0.8), 1.2)
	door.set_meta("open", false)
	for s in [-1, 1]:
		A.box(door, Vector3(0.8, 0.5, 0.02) if along_x else Vector3(0.02, 0.5, 0.8), Vector3(0, 0.6, 0.1 * s) if along_x else Vector3(0.1 * s, 0.6, 0), "metal", Color(0.1, 0.1, 0.1), false)
		var l := B.label(door, code, Vector3(0, 0.6, 0.12 * s) if along_x else Vector3(0.12 * s, 0.6, 0), 80, Color(0.95, 0.8, 0.25))
		if code == vault_code:   # the vault door says so
			var v := B.label(door, "VAULT", Vector3(0, 1.75, 0.12 * s) if along_x else Vector3(0.12 * s, 1.75, 0), 60, Color(0.85, 0.15, 0.1))
			v.rotation.y = (0.0 if s > 0 else PI) if along_x else (PI / 2 if s > 0 else -PI / 2)
		if along_x:
			l.rotation.y = 0.0 if s > 0 else PI
		else:
			l.rotation.y = PI / 2 if s > 0 else -PI / 2
	doors[code] = door


## Opens/closes a bulkhead. loud = the manual override, which alarms the whole area.
func set_door(code: String, open: bool, loud := false) -> bool:
	if not doors.has(code):
		return false
	var door: Node3D = doors[code]
	if door.get_meta("open") == open:
		return true
	door.set_meta("open", open)
	var tw := create_tween()
	tw.tween_property(door, "position:y", DOOR_H / 2 + (DOOR_H if open else 0.0), 1.2)
	Sfx.play(self, "door", door.global_position, 2.0)
	if loud:
		Sfx.play(self, "alarm", door.global_position, 4.0)
		if main:
			main.noise(door.global_position, 35.0)
	return true


static func _side(rng: RandomNumberGenerator) -> float:
	return 1.0 if rng.randf() < 0.5 else -1.0


func _process(_delta: float) -> void:
	for l in flicker:
		var r := randf()
		if r < 0.03:
			l.light_energy = l.get_meta("base") * randf_range(0.0, 0.25)
		elif r < 0.12:
			l.light_energy = l.get_meta("base")


## lane = a clear spot on a corridor axis (for monsters); otherwise a room spot, on top of any crate there.
func random_point(rng: RandomNumberGenerator, lane := false) -> Vector3:
	var cells: Array = layout.cells
	var c: Vector2i = cells[rng.randi() % cells.size()]
	for i in 20:
		if not lane or c != Vector2i.ZERO or cells.size() == 1:
			break
		c = cells[rng.randi() % cells.size()]
	var o := Vector3(c.x * CELL, 0, c.y * CELL)
	var p: Vector3
	if lane or kinds.get(c, "") == "tunnel":
		var a := rng.randf_range(-4.0, 4.0)
		p = o + (Vector3(a, 0.6, 0) if rng.randf() < 0.5 else Vector3(0, 0.6, a))
	else:
		var lo := 3.0 if c == Vector2i.ZERO else 1.5   # the start room has the lift shaft in its middle
		p = o + Vector3(_side(rng) * rng.randf_range(lo, 5.0), 0.6, _side(rng) * rng.randf_range(lo, 5.0))
		if kinds.get(c, "") == "pit":
			p.y = -PIT + 0.6
		for box in crates:
			if box.grow(0.2).has_point(Vector3(p.x, box.position.y + 0.01, p.z)):
				p.y = box.end.y + 0.3
	return to_global(p)


func cell_at(pos: Vector3) -> Vector2i:
	var l := to_local(pos)
	return Vector2i(roundi(l.x / CELL), roundi(l.z / CELL))


## Next waypoint from `from` toward `to`: the doorway into the next room on the cell path.
func path_next(from: Vector3, to: Vector3) -> Vector3:
	var a := cell_at(from)
	var b := cell_at(to)
	if a == b or not ids.has(a) or not ids.has(b):
		return to
	var path := astar.get_id_path(ids[a], ids[b])
	if path.size() < 2:
		return to
	var n: Vector2i = cell_of_id[path[1]]
	var doorway := to_global(Vector3((a.x + n.x) * CELL * 0.5, 0.5, (a.y + n.y) * CELL * 0.5))
	if Vector2(doorway.x - from.x, doorway.z - from.z).length() < 0.8:
		return to_global(Vector3(n.x * CELL, 0.5, n.y * CELL))
	return doorway


# --- dressing ------------------------------------------------------------------------

## Point in a room quadrant (keeps the cross-shaped walkways between doors clear).
func _quad(o: Vector3, rng: RandomNumberGenerator, margin := 0.8) -> Vector3:
	var lim := CELL / 2 - 0.6 - margin
	return o + Vector3(_side(rng) * rng.randf_range(2.4, lim), 0, _side(rng) * rng.randf_range(2.4, lim))


func _solid(pos: Vector3, size: Vector3) -> void:
	crates.append(AABB(pos - Vector3(size.x / 2, 0, size.z / 2), size))


## A spot against a wall, `off` metres along it from the wall centre, `inset` metres into the room.
func _wall_spot(w: Array, off: float, inset: float) -> Vector3:
	var along := Vector3(off, 0, 0) if w[1] else Vector3(0, 0, off)
	return w[0] + w[2] * inset + along


func _facing(w: Array) -> float:
	# rotation_y that makes a prop's -z face point into the room.
	return atan2(-w[2].x, -w[2].z)


func _dress(c: Vector2i, o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var kind: String = kinds[c]
	match kind:
		"pit": _pit(o, walls, rng)
		"tunnel": _tunnel(o, walls, rng)
		"storage": _storage(o, walls, rng)
		"machine": _machine(o, walls, rng)
		"collapsed": _collapsed(o, walls, rng)
		"break": _break_room(o, walls, rng)
		"office": _office(o, walls, rng)
		"lab": _lab(o, walls, rng)
		"server": _server(o, walls, rng)
		"empty": _empty(o, walls, rng)
		"vault": _vault(o, walls, rng)
		"atrium": _atrium(o, walls, rng)
	if kind == "tunnel":
		P.litter(self, o, 1.5, rng, rng.randi_range(3, 8))
		return
	if kind == "vault":
		P.litter(self, o, CELL / 2 - 0.8, rng, 8)
	elif kind != "pit":
		_fill(o, walls, rng)
		_wall_layer(walls, rng)
		_scatter(o, rng)
		P.litter(self, o, CELL / 2 - 0.8, rng, rng.randi_range(14, 26))
	else:
		P.litter(self, o + Vector3(0, -PIT, 0), CELL / 2 - 0.8, rng, rng.randi_range(8, 16))
	if theme_id != "BACKROOMS":
		P.ceiling_junk(self, o, H, rng)
	# Ceiling: beams / trusses, a pipe run, sometimes a duct or cable tray.
	if theme_id == "LAB":
		for z in [-3.0, 3.0]:
			P.truss(self, o + Vector3(-CELL / 2, H - 0.05, z), o + Vector3(CELL / 2, H - 0.05, z), 0.6)
	elif theme_id != "BACKROOMS":
		for z in [-3.0, 3.0]:
			A.box(self, Vector3(CELL, 0.25, 0.2), o + Vector3(0, H - 0.13, z), "rust", Color(0.8, 0.8, 0.8), false, 1.0)
	if theme_id != "BACKROOMS":
		var w: Array = walls[rng.randi() % 4]
		var along := Vector3(CELL / 2 - 0.3, 0, 0) if w[1] else Vector3(0, 0, CELL / 2 - 0.3)
		var pk := "flesh" if theme_id == "FLESH" else "metal"
		for y in [H - 0.45, H - 0.75]:
			A.pipe(self, w[0] + w[2] * 0.35 - along + Vector3(0, y, 0), w[0] + w[2] * 0.35 + along + Vector3(0, y, 0), 0.07 + rng.randf() * 0.05, pk)
		if rng.randf() < 0.4:
			var x0 := o + Vector3(-CELL / 2 + 0.3, H - 0.6, 1.6)
			if rng.randf() < 0.5:
				P.duct(self, x0, x0 + Vector3(CELL - 0.6, 0, 0))
			else:
				P.cable_tray(self, x0 + Vector3(0, 0.2, 0), x0 + Vector3(CELL - 0.6, 0.2, 0))
	# Things on the walls (never in a doorway).
	for i in rng.randi_range(2, 4):
		var w: Array = walls[rng.randi() % 4]
		var off := _side(rng) * rng.randf_range(2.0, 4.8)
		P.wall_decor(self, _wall_spot(w, off, 0.155) + Vector3(0, rng.randf_range(1.4, 1.9), 0), w[2], rng)
	if rng.randf() < 0.5:
		P.stain(self, _quad(o, rng, 0.0), rng)
	if theme_id == "FLESH":
		for i in rng.randi_range(2, 5):
			A.blob(self, _quad(o, rng, 0.0) + Vector3(0, rng.randf_range(-0.2, 0.2), 0), rng.randf_range(0.4, 1.1), rng)
		for i in rng.randi_range(1, 3):
			var b := A.sphere(self, rng.randf_range(0.8, 1.6), o + Vector3(rng.randf_range(-4, 4), H, rng.randf_range(-4, 4)), "flesh", Color(1, 0.8, 0.8), 0.2, 0.5)
			b.rotation.y = rng.randf() * TAU
		for i in rng.randi_range(1, 3):
			_tendrils(o + Vector3(rng.randf_range(-5, 5), H, rng.randf_range(-5, 5)), rng)
	if overgrown:
		for i in rng.randi_range(2, 5):
			A.vines(self, o + Vector3(rng.randf_range(-5, 5), H, rng.randf_range(-5, 5)), 2.5, rng)
		for i in rng.randi_range(1, 4):
			A.fern(self, _quad(o, rng, 0.0), rng)


func _storage(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	for w in walls:
		if not w[3] and rng.randf() < 0.8:
			for off in [-2.6, 2.6]:
				var spot := _wall_spot(w, off, 0.65)
				P.pallet_rack(self, spot, _facing(w), rng)
				_solid(spot, Vector3(2.8, 1.3, 2.8))
	for sz in [-1, 1]:
		for sx in [-1, 1]:
			if rng.randf() < 0.8:
				var p := o + Vector3(sx * 3.3, 0, sz * 3.6)
				A.shelf_unit(self, p, 0.0, rng, 2.2, 2.4, 0.6)
				_solid(p, Vector3(2.2, 2.4, 0.6))
	for i in rng.randi_range(1, 3):
		var p := o + Vector3(_side(rng) * rng.randf_range(4.6, 5.0), 0, _side(rng) * rng.randf_range(2.2, 2.8))
		A.crate(self, p, rng.randf_range(0.6, 1.0), rng)
		_solid(p, Vector3(1, 1, 1))
	if rng.randf() < 0.6:
		var p := o + Vector3(_side(rng) * 4.8, 0, _side(rng) * 4.8)
		A.pallet(self, p)
		A.crate(self, p + Vector3(0, 0.15, 0), 0.7, rng)
		A.crate(self, p + Vector3(0, 0.85, 0), 0.5, rng, false)
		_solid(p, Vector3(1.2, 1.4, 1.2))


func _machine(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(1, 2):
		var p := o + Vector3(_side(rng) * 3.6, 0, _side(rng) * 3.6)
		P.generator(self, p, (PI / 2) * rng.randi_range(0, 3), rng, H)
		_solid(p, Vector3(3.8, 1.8, 3.8))
	var w: Array = walls[rng.randi() % 4]
	var p2 := _wall_spot(w, _side(rng) * 3.5, 0.6)
	P.control_panel(self, p2, _facing(w), rng)
	_solid(p2, Vector3(1.6, 1.1, 1.6))
	var w3: Array = walls[(walls.find(w) + 2) % 4]
	var p3 := _wall_spot(w3, _side(rng) * 3.4, 0.45)
	P.workbench(self, p3, _facing(w3), rng)
	_solid(p3, Vector3(2.0, 0.95, 2.0))
	if rng.randf() < 0.5:
		A.barrel(self, _quad(o, rng), rng)


func _collapsed(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(3, 6):
		A.rubble(self, _quad(o, rng, 0.0), rng, "concrete")
	var beam := A.box(self, Vector3(0.3, 0.35, 5.5), o + Vector3(_side(rng) * 3.4, 1.8, _side(rng) * 2.5), "rust", Color.WHITE, false, 1.0)
	beam.rotation = Vector3(rng.randf_range(0.5, 0.8), rng.randf() * TAU, 0)
	var slab := A.box(self, Vector3(3.0, 0.25, 2.5), _quad(o, rng) + Vector3(0, 0.5, 0), theme.ceil_kind, theme.ceiling, true, 2.0)
	slab.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
	for i in rng.randi_range(2, 5):
		var l := rng.randf_range(1.0, 2.6)
		A.box(self, Vector3(0.03, l, 0.03), o + Vector3(rng.randf_range(-4, 4), H - l / 2, rng.randf_range(-4, 4)), "metal", Color(0.1, 0.1, 0.1), false)


func _break_room(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var t := _quad(o, rng, 1.3)
	P.table(self, t, 0.0, 1.6, 0.9)
	_solid(t, Vector3(1.6, 0.8, 0.9))
	for s in [-1, 1]:
		P.chair(self, t + Vector3(s * 0.4, 0, -0.75), 0.0)
		P.chair(self, t + Vector3(s * 0.4, 0, 0.75), PI)
	var w: Array = walls[rng.randi() % 4]
	var off := _side(rng) * 3.3
	P.vending(self, _wall_spot(w, off, 0.6), _facing(w), rng)
	_solid(_wall_spot(w, off, 0.6), Vector3(1, 2, 1))
	var w2: Array = walls[(walls.find(w) + 1) % 4]
	P.counter(self, _wall_spot(w2, 3.4, 0.5), _facing(w2))
	P.fridge(self, _wall_spot(w2, 5.0, 0.55), _facing(w2))
	_solid(_wall_spot(w2, 4.0, 0.5), Vector3(3.5, 1.8, 3.5))
	var w3: Array = walls[(walls.find(w2) + 2) % 4]
	var sp := _wall_spot(w3, -3.4, 0.6)
	P.sofa(self, sp, _facing(w3), rng)
	_solid(sp, Vector3(2.0, 0.85, 2.0))
	var tv := _wall_spot(w3, -3.4, 2.6)
	P.tv_corner(self, tv, _facing(w3) + PI, rng)
	A.box(self, Vector3(1.0, 0.4, 0.55), (sp + tv) / 2.0 + Vector3(0, 0.2, 0), "wood", Color(0.55, 0.42, 0.3), false, 0.6)   # coffee table
	_solid(tv, Vector3(1.0, 1.1, 1.0))


func _office(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			if rng.randf() < 0.75:
				var p := o + Vector3(sx * 3.4, 0, sz * 3.2)
				var rot := PI if sz < 0 else 0.0
				A.desk(self, p, rot, rng)
				P.chair(self, p + Vector3(0, 0, -0.75 * sz), 0.0 if sz < 0 else PI)
				if rng.randf() < 0.7:
					P.partition(self, p + Vector3(0, 0, 0.1 * sz), rot, sx * (1.0 if sz > 0 else -1.0))
				_solid(p, Vector3(2.2, 0.8, 2.0))
	for i in rng.randi_range(1, 3):
		var w: Array = walls[rng.randi() % 4]
		var off := _side(rng) * rng.randf_range(4.6, 5.2)
		P.filing_cabinet(self, _wall_spot(w, off, 0.45), _facing(w))
		_solid(_wall_spot(w, off, 0.45), Vector3(0.8, 1.3, 0.8))
	if rng.randf() < 0.5:
		var w: Array = walls[rng.randi() % 4]
		for k in 3:
			A.locker(self, _wall_spot(w, 2.0 + k * 0.62, 0.4), _facing(w))
			_solid(_wall_spot(w, 2.0 + k * 0.62, 0.4), Vector3(0.7, 1.9, 0.7))
	P.papers(self, _quad(o, rng, 0.0), rng)


func _lab(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	for sz in [-1, 1]:
		var p := o + Vector3(_side(rng) * 3.4, 0, sz * 3.4)
		P.lab_bench(self, p, 0.0, rng)
		_solid(p, Vector3(2.0, 0.8, 0.8))
	for i in rng.randi_range(1, 2):
		var p := o + Vector3(_side(rng) * 4.6, 0, _side(rng) * 4.6)
		P.specimen_tank(self, p, rng)
		_solid(p, Vector3(1.1, 2.4, 1.1))
	if rng.randf() < 0.5:
		var p := _quad(o, rng, 1.0)
		P.gurney(self, p, rng.randf() * TAU)
	for w in walls:
		if not w[3]:
			var hp := _wall_spot(w, _side(rng) * 1.6, 0.5)
			P.fume_hood(self, hp, _facing(w), rng)
			_solid(hp, Vector3(1.6, 2.4, 1.6))
			break
	P.papers(self, _quad(o, rng, 0.0), rng)


func _server(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			for k in 3:
				var p := o + Vector3(sx * (2.6 + k * 0.7), 0, sz * 3.5)
				P.server_rack(self, p, 0.0 if sz > 0 else PI, rng)
			_solid(o + Vector3(sx * 3.3, 0, sz * 3.5), Vector3(2.2, 2.1, 1.0))
	for w in walls:
		if not w[3]:
			for k in 2:
				var up := _wall_spot(w, -1.0 + k * 1.0, 0.45)
				var r := A.root(self, up, _facing(w), Vector3(0.9, 1.8, 0.8))
				A.box(r, Vector3(0.9, 1.8, 0.8), Vector3(0, 0.9, 0), "metal", Color(0.18, 0.18, 0.2), false, 1.0)
				A.box(r, Vector3(0.7, 0.5, 0.01), Vector3(0, 1.3, -0.405), "grille", Color(0.6, 0.6, 0.6), false, 0.3)
				A.glow(r, Vector3(0.16, 0.06, 0.01), Vector3(0.2, 0.8, -0.405), Color(0.3, 1, 0.4) if rng.randf() < 0.6 else Color(1, 0.4, 0.1), 2.5)
				_solid(up, Vector3(0.9, 1.8, 0.9))
			break
	for k in rng.randi_range(3, 6):   # cable bundles across the floor
		var a := o + Vector3(rng.randf_range(-4, 4), 0.03, -5.2)
		var b := o + Vector3(rng.randf_range(-4, 4), 0.03, 5.2)
		A.seg(self, a, b, 0.025, 0.025, "rubber", [Color(0.2, 0.3, 0.8), Color(0.85, 0.75, 0.2), Color(1, 1, 1)][rng.randi() % 3])
	P.cable_tray(self, o + Vector3(-CELL / 2 + 0.3, H - 0.4, 3.5), o + Vector3(CELL / 2 - 0.3, H - 0.4, 3.5))
	P.cable_tray(self, o + Vector3(-CELL / 2 + 0.3, H - 0.4, -3.5), o + Vector3(CELL / 2 - 0.3, H - 0.4, -3.5))


## Catwalks over a 3 m pit, a centre platform, stairs down, junk at the bottom.
func _pit(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	A.box(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, -PIT - 0.1, 0), "dirt", Color(0.8, 0.75, 0.7), true, 2.0)
	for w in walls:
		var size := Vector3(CELL, PIT, 0.3) if w[1] else Vector3(0.3, PIT, CELL)
		A.box(self, size, w[0] + w[2] * 0.15 + Vector3(0, -PIT / 2, 0), "concrete", Color(0.6, 0.55, 0.5), true, 2.0)
	var plat := 2.0
	A.box(self, Vector3(plat * 2, 0.1, plat * 2), o + Vector3(0, -0.05, 0), "grate", Color.WHITE, true, 0.6)
	var stair_dir := Vector3.ZERO
	for w in walls:
		var inward: Vector3 = w[2]
		var out := -inward
		var side := Vector3(-out.z, 0, out.x)
		if w[3]:
			var run := CELL / 2 - plat
			var mid := o + out * (plat + run / 2) + Vector3(0, -0.05, 0)
			A.box(self, Vector3(run, 0.1, 1.8) if absf(out.x) > 0.5 else Vector3(1.8, 0.1, run), mid, "grate", Color.WHITE, true, 0.6)
			for s in [-1, 1]:
				A.railing(self, o + out * plat + side * (0.9 * s), o + out * (CELL / 2 - 0.2) + side * (0.9 * s), 1.0, "rust", true)
			A.box(self, Vector3(0.2, PIT, 0.2), mid + Vector3(0, -PIT / 2, 0), "rust", Color.WHITE, true, 1.0)
			if stair_dir == Vector3.ZERO:
				stair_dir = out
			# Platform edge rails, leaving the catwalk (and maybe the stair) open.
			A.railing(self, o + out * plat - side * plat, o + out * plat - side * 0.9, 1.0, "rust", true)
			if stair_dir != out:
				A.railing(self, o + out * plat + side * 0.9, o + out * plat + side * plat, 1.0, "rust", true)
		else:
			A.railing(self, o + out * plat - side * plat, o + out * plat + side * plat, 1.0, "rust", true)
	var sside := Vector3(-stair_dir.z, 0, stair_dir.x)
	P.stairs(self, o + stair_dir * plat + sside * 1.5, stair_dir, PIT, 3.6, 1.0)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			A.box(self, Vector3(0.2, PIT, 0.2), o + Vector3(sx * (plat - 0.1), -PIT / 2, sz * (plat - 0.1)), "rust", Color.WHITE, true, 1.0)
	for i in rng.randi_range(3, 6):
		var p := _quad(o, rng) + Vector3(0, -PIT, 0)
		match rng.randi() % 3:
			0: A.barrel(self, p, rng)
			1: A.crate(self, p, rng.randf_range(0.6, 1.1), rng)
			2: A.rubble(self, p, rng)
	A.box(self, Vector3(4.0, 0.02, 3.0), _quad(o, rng, 0.0) + Vector3(0, -PIT + 0.01, 0), "metal", Color(0.05, 0.06, 0.07), false)


## Ribbed tunnel along the corridor axis, with a grate walkway and a cable tray.
func _tunnel(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var along_x := false
	for w in walls:
		if w[3]:
			along_x = not w[1]
	var axis := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var side := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var r := 2.2
	for s in [-1, 1]:
		A.box(self, Vector3(CELL, 2.2, 0.2) if along_x else Vector3(0.2, 2.2, CELL), o + side * (s * r) + Vector3(0, 1.1, 0), "riveted", Color(0.6, 0.55, 0.5), true, 1.5)
	A.box(self, Vector3(CELL, 0.05, 1.6) if along_x else Vector3(1.6, 0.05, CELL), o + Vector3(0, 0.025, 0), "grate", Color.WHITE, false, 0.6)   # walk-over: the floor under it is solid
	A.box(self, Vector3(CELL, 0.01, 1.5) if along_x else Vector3(1.5, 0.01, CELL), o + Vector3(0, 0.006, 0), "metal", Color(0.16, 0.15, 0.14), false, 1.0)   # dark channel under it, so it still reads at range
	var x := -CELL / 2 + 0.6
	while x < CELL / 2:
		for i in 7:
			var a0 := PI * i / 7.0
			var a1 := PI * (i + 1) / 7.0
			var p0 := side * (cos(a0) * r) + Vector3(0, 2.2 + sin(a0) * 1.6, 0)
			var p1 := side * (cos(a1) * r) + Vector3(0, 2.2 + sin(a1) * 1.6, 0)
			var seg := A.box(self, Vector3(0.18, 0.18, p0.distance_to(p1) + 0.05), o + axis * x + (p0 + p1) / 2.0, "rust", Color(0.8, 0.75, 0.7), false, 1.0)
			seg.look_at_from_position(seg.global_position, to_global(o + axis * x + p1), axis)
		for s in [-1, 1]:
			A.box(self, Vector3(0.18, 2.2, 0.18), o + axis * x + side * (s * (r - 0.1)) + Vector3(0, 1.1, 0), "rust", Color(0.8, 0.75, 0.7), false, 1.0)
		x += 1.5
	P.cable_tray(self, o - axis * (CELL / 2 - 0.2) + side * 1.7 + Vector3(0, 2.0, 0), o + axis * (CELL / 2 - 0.2) + side * 1.7 + Vector3(0, 2.0, 0))
	for k in [-3.0, 3.0]:
		A.glow(self, Vector3(0.3, 0.1, 0.3), o + axis * k + Vector3(0, 3.75, 0), Color(1, 0.6, 0.3), 5.0)


func _tendrils(top: Vector3, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(2, 5):
		var l := rng.randf_range(0.8, 2.5)
		A.cyl(self, 0.06, l, top + Vector3(rng.randf_range(-0.5, 0.5), -l / 2, rng.randf_range(-0.5, 0.5)), "flesh", Color(0.8, 0.6, 0.6), false, "y", 0.02)


func _light(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var c: Color = theme.light
	var kind: String = kinds.get(cell_at(to_global(o)), "")
	var lights: Array[OmniLight3D] = []
	if kind == "tunnel":
		lights.append(B.omni(self, o + Vector3(0, 3.2, 0), Color(1, 0.6, 0.3), 1.0, 8.0, true))
	elif kind == "pit":
		lights.append(A.hanging_lamp(self, o + Vector3(0, H, 0), c, 1.4, 1.8, true))
		var w: Array = walls[rng.randi() % 4]
		lights.append(A.wall_lamp(self, _wall_spot(w, 2.4, 0.3) + Vector3(0, -1.0, 0), w[2], c, 1.0, false))
	elif kind == "server":
		for z in [-2.5, 2.5]:
			lights.append(A.fluorescent(self, o + Vector3(0, H - 0.05, z), Color(0.5, 0.75, 1.0), 0.8))
	else:
		match theme_id:
			"FACTORY":
				if rng.randf() < 0.5:
					lights.append(A.hanging_lamp(self, o + Vector3(0, H, 0), c, 1.0, rng.randf_range(1.8, 2.6), true))
				else:
					var w: Array = walls[rng.randi() % 4]
					lights.append(A.wall_lamp(self, _wall_spot(w, 2.4, 0.2) + Vector3(0, 2.7, 0), w[2], c, 2.2, true))
					var w2: Array = walls[(walls.find(w) + 2) % 4]
					lights.append(A.wall_lamp(self, _wall_spot(w2, -2.4, 0.2) + Vector3(0, 2.7, 0), w2[2], c, 1.4, false))
			"LAB":
				for z in [-2.5, 2.5]:
					lights.append(A.fluorescent(self, o + Vector3(0, H - 0.05, z), c, 1.3))
			"BACKROOMS":
				lights.append(B.omni(self, o + Vector3(0, H - 0.5, 0), c, 1.2, 11.0, false))
			"FLESH":
				A.sphere(self, 0.2, o + Vector3(rng.randf_range(-3, 3), H - 0.15, rng.randf_range(-3, 3)), "flesh", c, 3.0)
				lights.append(B.omni(self, o + Vector3(0, H - 0.6, 0), c, 1.0, 9.0, true))
	if not lights.is_empty() and kind != "tunnel":
		lights[0].shadow_enabled = true
	for l in lights:
		if rng.randf() < 0.3:
			l.set_meta("base", l.light_energy)
			flicker.append(l)


## Unused room: somebody's camp, or just a dumping ground.
func _empty(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	if rng.randf() < 0.45:
		var p := _quad(o, rng, 1.2)
		P.camp(self, p, rng)
		_solid(p, Vector3(2.4, 0.8, 2.4))
	else:
		P.scrap_heap(self, _quad(o, rng, 1.5), rng)
	if rng.randf() < 0.5:
		P.chair(self, _quad(o, rng), rng.randf() * TAU)


## Line the walls: fixtures on them, things stood against them. Doorways and furniture stay clear.
func _wall_layer(walls: Array, rng: RandomNumberGenerator) -> void:
	var wet: bool = theme_id in ["LAB", "BACKROOMS"]
	for w in walls:
		var off := -5.0
		while off <= 5.0:
			var doorway: bool = w[3] and absf(off) < 1.9
			var foot := _wall_spot(w, off, 0.45)
			var blocked := doorway
			for box in crates:
				if box.grow(0.25).has_point(Vector3(foot.x, box.position.y + 0.05, foot.z)):
					blocked = true
					break
			if not blocked:
				if rng.randf() < 0.45:
					P.wall_fixture(self, _wall_spot(w, off, 0.175), w[2], rng, wet)   # from the wall face (0.15 up top, 0.17 at the band)
				elif rng.randf() < 0.55:
					var size := P.wall_floor_item(self, foot, _facing(w) + rng.randf_range(-0.15, 0.15), rng)
					if size != Vector3.ZERO:
						_solid(foot, Vector3(size.z, minf(size.y, 1.2), size.x) if not w[1] else Vector3(size.x, minf(size.y, 1.2), size.z))
			off += rng.randf_range(1.2, 1.7)


## Smaller things across the open floor, off the walkways through the middle (x = 0, z = 0) and off furniture.
func _scatter(o: Vector3, rng: RandomNumberGenerator) -> void:
	var placed := 0
	var want := rng.randi_range(9, 14)
	for attempt in 60:
		if placed >= want:
			break
		var lx := _side(rng) * rng.randf_range(1.4, CELL / 2 - 1.0)
		var lz := _side(rng) * rng.randf_range(1.4, CELL / 2 - 1.0)
		var q := o + Vector3(lx, 0, lz)
		var taken := false
		for box in crates:
			if box.grow(0.35).has_point(Vector3(q.x, box.position.y + 0.05, q.z)):
				taken = true
				break
		if taken:
			continue
		placed += 1
		var roll := rng.randi() % 13
		if roll >= 8:   # medium pieces: these are what actually fill a room
			var rot := (PI / 2) * rng.randi_range(0, 3) + rng.randf_range(-0.2, 0.2)
			match roll:
				8:
					A.pallet(self, q)
					for k in rng.randi_range(2, 5):
						A.box(self, Vector3(0.5, 0.4, 0.45), q + Vector3(((k % 2) - 0.5) * 0.55, 0.36 + (k / 2) * 0.41, rng.randf_range(-0.2, 0.2)), "cardboard", Color.WHITE.darkened(rng.randf() * 0.3), false, 0.5, Vector3(0, rng.randf_range(-0.15, 0.15), 0))
					_solid(q, Vector3(1.3, 1.2, 1.3))
				9:
					A.shelf_unit(self, q, rot, rng, 1.6, 1.8, 0.5)
					_solid(q, Vector3(1.7, 1.8, 1.7))
				10:
					P.table(self, q, rot, 1.4, 0.8, "wood")
					P.litter(self, q + Vector3(0, 0.78, 0), 0.5, rng, 3)
					P.chair(self, q + Vector3(0.9, 0, 0).rotated(Vector3.UP, rot), rot + PI / 2 + rng.randf_range(-0.6, 0.6))
					_solid(q, Vector3(1.5, 0.8, 1.5))
				11:
					for k in rng.randi_range(2, 4):
						A.barrel(self, q + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)), rng)
					_solid(q, Vector3(1.4, 0.9, 1.4))
				_:
					for k in rng.randi_range(2, 3):
						var s := rng.randf_range(0.6, 0.9)
						A.crate(self, q + Vector3(rng.randf_range(-0.45, 0.45), 0, rng.randf_range(-0.45, 0.45)), s, rng, false)
					A.crate(self, q + Vector3(0, 0.75, 0), 0.55, rng, false)
					_solid(q, Vector3(1.5, 1.3, 1.5))
			continue
		match roll:
			0:   # toppled chair
				var c := Node3D.new()
				add_child(c)
				c.position = q
				c.rotation = Vector3(0, rng.randf() * TAU, 0)
				P.chair(c, Vector3(0, 0.22, 0), 0.0)
				c.get_child(0).rotation.x = PI / 2
				c.get_child(0).position = Vector3(0, 0.22, 0.45)
			1:   # knocked-over crate + spilled contents
				A.crate(self, q, rng.randf_range(0.5, 0.7), rng, false)
				P.litter(self, q, 0.8, rng, 4)
			2:
				A.rubble(self, q, rng, "concrete")
			3:
				A.barrel(self, q, rng)
				_solid(q, Vector3(0.7, 0.9, 0.7))
			4:   # puddle
				var pd = A.box(self, Vector3(rng.randf_range(0.8, 1.8), 0.004, rng.randf_range(0.6, 1.4)), q + Vector3(0, 0.004, 0), "metal", Color(0.05, 0.06, 0.07), false, 1.0, Vector3(0, rng.randf() * TAU, 0))
				pd.material_override = _wet
			5:   # cardboard box pile
				for k in rng.randi_range(2, 4):
					var sz := Vector3(rng.randf_range(0.35, 0.55), rng.randf_range(0.25, 0.4), rng.randf_range(0.3, 0.5))
					A.box(self, sz, q + Vector3(rng.randf_range(-0.3, 0.3), sz.y / 2 + (0.3 if k == 3 else 0.0), rng.randf_range(-0.3, 0.3)), "cardboard", Color.WHITE.darkened(rng.randf() * 0.3), false, 0.5, Vector3(0, rng.randf() * TAU, 0))
				_solid(q, Vector3(1.0, 0.7, 1.0))
			6:   # tyre stack / cable drum
				if rng.randf() < 0.5:
					for k in rng.randi_range(1, 3):
						A.ring(self, 0.35, 0.18, q + Vector3(rng.randf_range(-0.05, 0.05), 0.09 + k * 0.17, 0), "rubber")
				else:
					var d := Node3D.new()
					add_child(d)
					d.position = q
					d.rotation.y = rng.randf() * TAU
					for sx in [-1, 1]:
						A.cyl(d, 0.45, 0.06, Vector3(sx * 0.3, 0.45, 0), "wood", Color(0.75, 0.6, 0.45), false, "x")
					A.cyl(d, 0.25, 0.6, Vector3(0, 0.45, 0), "rubber", Color.WHITE, false, "x")
					_solid(q, Vector3(0.9, 0.9, 0.9))
			_:
				P.papers(self, q, rng)
				P.stain(self, q, rng)


## Make sure no quadrant is bare, and line some walls with furniture.
func _fill(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var q := o + Vector3(sx * 3.6, 0, sz * 3.6)
			var taken := false
			for box in crates:
				if box.grow(0.8).has_point(Vector3(q.x, box.position.y + 0.05, q.z)):
					taken = true
					break
			if taken or rng.randf() < 0.15:
				continue
			match rng.randi() % 7 if theme_id != "BACKROOMS" else 6:
				0:
					for i in rng.randi_range(2, 4):
						var s := rng.randf_range(0.5, 0.9)
						A.crate(self, q + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8)), s, rng)
					_solid(q, Vector3(2, 1, 2))
				1:
					for i in rng.randi_range(2, 4):
						A.barrel(self, q + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8)), rng)
					_solid(q, Vector3(2, 1, 2))
				2:
					A.pallet(self, q)
					for i in rng.randi_range(1, 3):
						A.box(self, Vector3(0.45, 0.35, 0.35), q + Vector3(rng.randf_range(-0.35, 0.35), 0.33 + i * 0.36, rng.randf_range(-0.3, 0.3)), "cream", Color(0.75, 0.6, 0.45), false, 0.5, Vector3(0, rng.randf(), 0))
					_solid(q, Vector3(1.3, 1.2, 1.3))
				3:
					P.table(self, q, rng.randf() * TAU, 1.4, 0.8, "metal" if theme_id == "LAB" else "wood")
					P.chair(self, q + Vector3(0.9, 0, 0.2), rng.randf() * TAU)
					if rng.randf() < 0.5:
						A.crt(self, q + Vector3(0, 0.79, 0), rng.randf() < 0.5)
					_solid(q, Vector3(1.6, 0.8, 1.6))
				4:
					P.filing_cabinet(self, q, rng.randf() * TAU)
					P.papers(self, q, rng)
					_solid(q, Vector3(0.7, 1.3, 0.7))
				5:
					A.rubble(self, q, rng, "concrete")
					A.crate(self, q + Vector3(0.6, 0, 0.4), 0.7, rng)
				6:
					P.chair(self, q, rng.randf() * TAU, "wood")
	# Something along one or two walls, beside (not in) the doorway.
	for i in rng.randi_range(1, 2):
		var w: Array = walls[rng.randi() % 4]
		var off := _side(rng) * rng.randf_range(4.2, 5.0)
		var spot := _wall_spot(w, off, 0.45)
		match rng.randi() % 3:
			0: A.locker(self, spot, _facing(w))
			1: P.filing_cabinet(self, spot, _facing(w))
			2: A.crate(self, spot, 0.8, rng)
		_solid(spot, Vector3(0.9, 1.3, 0.9))


## Wall-mounted security camera in a room corner, watching the middle of the room.
func _camera(o: Vector3, rng: RandomNumberGenerator) -> void:
	var corner := Vector3(_side(rng) * (CELL / 2 - 0.45), H - 0.45, _side(rng) * (CELL / 2 - 0.45))
	var cam := Node3D.new()
	add_child(cam)
	cam.position = o + corner
	cam.look_at(to_global(o + Vector3(-corner.x * 0.6, 0.0, -corner.z * 0.6)), Vector3.UP)
	A.box(cam, Vector3(0.22, 0.18, 0.4), Vector3(0, 0, 0.05), "cream", Color(0.8, 0.8, 0.78), false, 0.3)
	A.cyl(cam, 0.07, 0.08, Vector3(0, 0, -0.18), "metal", Color(0.05, 0.05, 0.05), false, "z")
	A.box(cam, Vector3(0.05, 0.05, 0.35), Vector3(0, 0.12, 0.3), "metal", Color(0.3, 0.3, 0.3), false)
	var led := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, 0.02)
	led.mesh = bm
	cam.add_child(led)
	led.position = Vector3(0.07, 0.06, -0.15)
	P._blink(led, Color(1, 0.1, 0.05), 1.2)
	var light := SpotLight3D.new()
	light.light_color = Color(1, 0.95, 0.85)
	light.light_energy = 4.0
	light.spot_range = 16.0
	light.spot_angle = 35.0
	light.visible = false
	cam.add_child(light)
	cameras.append({"name": "CAM_%d" % (cameras.size() + 1), "node": cam, "light": light})



# --- layout features -------------------------------------------------------------------------

## The furthest dead end becomes the vault, sealed by a bulkhead of its own.
func _pick_vault(rng: RandomNumberGenerator) -> void:
	if layout.cells.size() < 6:
		return
	var best_d := -1
	for c: Vector2i in layout.cells:
		if c == Vector2i.ZERO or layout.links[c].size() != 1:
			continue
		var d := absi(c.x) + absi(c.y)
		if d > best_d:
			best_d = d
			vault_cell = c
	if best_d < 2:
		vault_cell = Vector2i(999, 999)
		return
	var e := edge(vault_cell, layout.links[vault_cell][0])
	for code in layout.doors:
		if layout.doors[code] == e:
			vault_code = code
			return
	vault_code = "V%d%d" % [rng.randi() % 10, rng.randi() % 10]
	layout.doors[vault_code] = e


## Vault: steel-plated walls lined with deposit boxes, a caged rack, crates, red work lights.
func _vault(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var steel := Color(0.42, 0.44, 0.44)
	for w in walls:
		if w[3]:
			continue
		var ax := Vector3(1, 0, 0) if w[1] else Vector3(0, 0, 1)
		var face: Vector3 = w[0] + w[2] * 0.2
		A.box(self, Vector3(CELL - 0.4, H - 0.2, 0.05) if w[1] else Vector3(0.05, H - 0.2, CELL - 0.4), face + Vector3(0, H / 2, 0), "riveted", steel, false, 1.2)
		# Deposit boxes: a grid of little numbered doors with keyholes.
		var wall_root := Node3D.new()
		add_child(wall_root)
		wall_root.position = face + w[2] * 0.03
		wall_root.rotation.y = _facing(w) + PI
		for col in 8:
			for row in 4:
				var p := Vector3(-2.1 + col * 0.6, 1.0 + row * 0.5, 0)
				A.box(wall_root, Vector3(0.54, 0.44, 0.04), p, "metal", steel.lightened(0.1), false, 0.3)
				A.box(wall_root, Vector3(0.05, 0.05, 0.02), p + Vector3(0.17, 0, 0.03), "brass", Color.WHITE, false)
				if rng.randf() < 0.18:   # a few hang open
					A.box(wall_root, Vector3(0.48, 0.38, 0.02), p + Vector3(-0.1, 0, 0.25), "metal", steel, false, 0.3, Vector3(0, 1.2, 0))
	# Caged rack in the middle, the loot on it and around it.
	A.shelf_unit(self, o + Vector3(0, 0, -1.4), 0.0, rng, 3.0, 2.2, 0.7)
	_solid(o + Vector3(0, 0, -1.4), Vector3(3.2, 2.2, 0.9))
	for k in 4:
		vault_spots.append(o + Vector3(rng.randf_range(-2.5, 2.5), 0.5, rng.randf_range(0.6, 3.6) * (1 if k % 2 == 0 else -1)))
	vault_spots.append(o + Vector3(rng.randf_range(-1.0, 1.0), 1.0, -1.4))
	for k in 3:
		var p := o + Vector3(_side(rng) * rng.randf_range(3.6, 4.8), 0, _side(rng) * rng.randf_range(3.6, 4.8))
		A.crate(self, p, rng.randf_range(0.7, 1.0), rng)
		_solid(p, Vector3(1.1, 1.0, 1.1))
	for k in 2:
		var lp := o + Vector3(_side(rng) * 4.5, H - 0.3, _side(rng) * 4.5)
		B.omni(self, lp, Color(1, 0.25, 0.12), 0.9, 7.0)
		A.sphere(self, 0.1, lp, "cream", Color(1, 0.3, 0.15), 4.0)


## Two-level room: a steel mezzanine along a solid wall, stairs up, shelves and loot on top.
func _atrium(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var w: Array = []
	for cand in walls:
		if not cand[3]:
			w = cand
			break
	if w.is_empty():
		_storage(o, walls, rng)
		return
	var top := 1.9
	var depth := 2.8
	var inward: Vector3 = w[2]
	var along := Vector3(1, 0, 0) if w[1] else Vector3(0, 0, 1)
	var len := CELL - 0.6
	var deck_c: Vector3 = w[0] + inward * (0.15 + depth / 2.0)
	A.box(self, Vector3(len, 0.12, depth) if w[1] else Vector3(depth, 0.12, len), deck_c + Vector3(0, top - 0.06, 0), "grate", Color.WHITE, true, 0.6)
	A.box(self, Vector3(len, 0.14, 0.1) if w[1] else Vector3(0.1, 0.14, len), deck_c + inward * (depth / 2.0) + Vector3(0, top - 0.1, 0), "metal", Color(0.85, 0.65, 0.15), false)
	for k in 5:   # columns + knee braces
		var cp := deck_c + inward * (depth / 2.0 - 0.1) + along * (-len / 2.0 + 0.3 + k * (len - 0.6) / 4.0)
		A.box(self, Vector3(0.14, top, 0.14), cp + Vector3(0, top / 2.0, 0), "rust", Color.WHITE, true, 1.0)
		var brace := A.box(self, Vector3(0.06, 0.9, 0.06), cp + Vector3(0, top - 0.4, 0) - inward * 0.3, "rust", Color.WHITE, false, 1.0)
		brace.rotation = Vector3(0.6 * (1 if inward.z > 0 else -1), 0, 0) if w[1] else Vector3(0, 0, -0.6 * (1 if inward.x > 0 else -1))
	# Stairs down from one end of the deck's front edge, railing along the rest.
	var stair_end := 1 if rng.randf() < 0.5 else -1
	var stair_top: Vector3 = deck_c + inward * (depth / 2.0) + along * (stair_end * (len / 2.0 - 0.8)) + Vector3(0, top, 0)
	P.stairs(self, stair_top, inward, top, 3.0, 1.1)
	var rail_a: Vector3 = deck_c + inward * (depth / 2.0) + along * (-stair_end * (len / 2.0)) + Vector3(0, top, 0)
	var rail_b: Vector3 = stair_top - along * stair_end * 0.65
	A.railing(self, rail_a, rail_b, 1.0, "rust", true)
	for s in [-1, 1]:   # end rails
		var e: Vector3 = deck_c + along * (s * len / 2.0) + Vector3(0, top, 0)
		A.railing(self, e - inward * (depth / 2.0 - 0.2), e + inward * (depth / 2.0), 1.0, "rust", true)
	# On the deck: shelves against the wall, loot spots; under it: crates and barrels.
	for k in 3:
		var sp: Vector3 = w[0] + inward * 0.5 + along * (-3.6 + k * 3.6) + Vector3(0, top, 0)
		A.shelf_unit(self, sp, _facing(w), rng, 2.0, 1.8, 0.5)
		loot_spots.append(w[0] + inward * 1.6 + along * (-3.6 + k * 3.6 + rng.randf_range(-0.8, 0.8)) + Vector3(0, top + 0.5, 0))
	for k in rng.randi_range(2, 4):
		var p: Vector3 = w[0] + inward * rng.randf_range(0.8, 2.2) + along * rng.randf_range(-4.5, 4.5)
		if rng.randf() < 0.5:
			A.crate(self, p, rng.randf_range(0.6, 0.9), rng)
		else:
			A.barrel(self, p, rng)
	_solid(deck_c, Vector3(len, top, depth) if w[1] else Vector3(depth, top, len))
	_solid(stair_top + inward * 1.5 - Vector3(0, top, 0), Vector3(1.4, 1.0, 3.2))
	A.fluorescent(self, deck_c + Vector3(0, H - 0.08, 0), theme.light, 0.9)


## A low vent through a wall: steel frame both sides, the grille cover pulled off and leaning beside it.
func _vent(at: Vector3, along_x: bool) -> void:
	var frame := Color(0.5, 0.5, 0.48)
	for s in [-1, 1]:
		var n := Vector3(0, 0, s * 0.2) if along_x else Vector3(s * 0.2, 0, 0)
		var across := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		A.box(self, (Vector3(VENT_W + 0.16, 0.08, 0.06) if along_x else Vector3(0.06, 0.08, VENT_W + 0.16)), at + n + Vector3(0, VENT_H + 0.04, 0), "metal", frame, false)
		for e in [-1, 1]:
			A.box(self, Vector3(0.08, VENT_H, 0.06) if along_x else Vector3(0.06, VENT_H, 0.08), at + n + across * (e * (VENT_W / 2.0 + 0.04)) + Vector3(0, VENT_H / 2.0, 0), "metal", frame, false)
		if s > 0:
			var cover := A.box(self, Vector3(VENT_W - 0.1, VENT_H - 0.1, 0.03) if along_x else Vector3(0.03, VENT_H - 0.1, VENT_W - 0.1), at + n * 3.0 + across * (VENT_W * 0.9) + Vector3(0, VENT_H / 2.0 - 0.1, 0), "grille", Color(0.7, 0.7, 0.7), false, 0.3)
			cover.rotation = Vector3(-0.25, 0, 0) if along_x else Vector3(0, 0, 0.25)
	# Galvanised duct lining through the wall: floor, roof, sides, ribs, dark at the middle.
	var depth := 0.5
	var lin := Color(0.55, 0.56, 0.55)
	var sz_floor := Vector3(VENT_W, 0.03, depth) if along_x else Vector3(depth, 0.03, VENT_W)
	A.box(self, sz_floor, at + Vector3(0, 0.015, 0), "corrugated", lin, false, 0.4)
	A.box(self, sz_floor, at + Vector3(0, VENT_H - 0.015, 0), "corrugated", lin.darkened(0.3), false, 0.4)
	var across2 := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	for e in [-1, 1]:
		A.box(self, Vector3(0.03, VENT_H, depth) if along_x else Vector3(depth, VENT_H, 0.03), at + across2 * (e * VENT_W / 2.0) + Vector3(0, VENT_H / 2.0, 0), "corrugated", lin.darkened(0.15), false, 0.4)
	A.box(self, Vector3(VENT_W, VENT_H, 0.01) if along_x else Vector3(0.01, VENT_H, VENT_W), at + Vector3(0, VENT_H / 2.0, 0), "metal", Color(0.02, 0.02, 0.02), false).visible = false
	# Hazard tape over the opening on one side.
	A.box(self, Vector3(VENT_W + 0.2, 0.1, 0.02) if along_x else Vector3(0.02, 0.1, VENT_W + 0.2), at + Vector3(0, VENT_H + 0.14, 0) + (Vector3(0, 0, 0.21) if along_x else Vector3(0.21, 0, 0)), "hazard", Color.WHITE, false, 0.3)


## A sealed supply crate against a wall: pry it open (hold E) for whatever the last crew left.
func _supply_crate(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	for tries in 8:
		var w: Array = walls[rng.randi() % 4]
		var off := _side(rng) * rng.randf_range(2.4, 4.8)
		var spot := _wall_spot(w, off, 0.55)
		var blocked: bool = w[3] and absf(off) < 2.0
		for box in crates:
			if box.grow(0.4).has_point(Vector3(spot.x, box.position.y + 0.05, spot.z)):
				blocked = true
		if blocked:
			continue
		var crate := P.supply_crate(self, spot, _facing(w), rng)
		_solid(spot, Vector3(1.2, 0.7, 1.2))
		var loot := Callable(self, "_open_supply").bind(crate)
		var it := B.interactable(crate, Vector3(1.0, 0.6, 0.62), Vector3(0, 0.32, 0), Color(0, 0, 0, 0), "Pry open the supply crate", loot, 1.1)
		it.set_meta("crate", true)
		return


func _open_supply(crate: Node3D) -> void:
	if crate.get_meta("opened", false):
		return
	crate.set_meta("opened", true)
	var lid: Node3D = crate.get_meta("lid")
	create_tween().tween_property(lid, "rotation:x", 1.9, 0.5).set_trans(Tween.TRANS_BACK)
	Sfx.play(self, "open_box", crate.global_position + Vector3(0, 0.5, 0), 0.0)
	if main:
		main.noise(crate.global_position, 7.0)
	for c in crate.get_children():
		if c.has_meta("crate"):
			c.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n := 0 if rng.randf() < 0.12 else (1 if rng.randf() < 0.6 else 2)
	if n == 0:
		main.hud.msg("Empty. Somebody got here first.")
	for k in n:
		var id: String = Data.valuable_scrap(rng, false) if rng.randf() < 0.5 else Data.random_scrap(rng)
		main.spawn_item(id, crate.global_position + crate.global_transform.basis.z * -0.1 + Vector3(randf_range(-0.2, 0.2), 0.75 + k * 0.3, 0), -1.0, main.level)
