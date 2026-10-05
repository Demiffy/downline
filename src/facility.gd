# Procedural underground facility: a grid of 12 m rooms grown from the elevator room.
# The layout is pure data from one seed, so every client can rebuild the same map later.
extends Node3D

const Data = preload("res://src/data.gd")
const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

const CELL := 12.0
const H := 4.0
const DOOR_W := 2.4
const DOOR_H := 2.8
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
	theme_id = theme_name
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	overgrown = theme_name in ["FACTORY", "LAB"] and rng.randf() < 0.35
	layout = gen_layout(seed, rooms, int(theme.bulkheads) + rng.randi() % 2)
	var door_at := {}
	for code in layout.doors:
		door_at[layout.doors[code]] = code
	for c: Vector2i in layout.cells:
		var o := Vector3(c.x * CELL, 0, c.y * CELL)
		A.box(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, -0.1, 0), theme.floor_kind, theme.floor, true, 2.0)
		if c == Vector2i.ZERO:
			_ceiling_with_hole(o)
		else:
			A.box(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, H + 0.1, 0), theme.ceil_kind, theme.ceiling, true, 2.0)
		var walls := []  # [center, along_x, normal_into_room, has_door]
		for d: Vector2i in DIRS:
			var n := c + d
			var linked: bool = layout.links[c].has(n)
			var center := o + Vector3(d.x, 0, d.y) * (CELL / 2.0)
			walls.append([center, d.y != 0, -Vector3(d.x, 0, d.y), linked])
			# Shared walls are built once, by the cell on the -x / -z side.
			if layout.links.has(n) and (d.x < 0 or d.y < 0):
				continue
			_wall(center, d.y != 0, linked)
			if linked and door_at.has(edge(c, n)):
				_bulkhead(center, d.y != 0, door_at[edge(c, n)])
		if c != Vector2i.ZERO:
			_dress(o, walls, rng)
		if c == Vector2i.ZERO or rng.randf() < theme.light_chance:
			_light(o, walls, rng)
		ids[c] = ids.size()
		cell_of_id[ids[c]] = c
		astar.add_point(ids[c], Vector3(c.x, 0, c.y))
	for c in layout.cells:
		for n in layout.links[c]:
			if not astar.are_points_connected(ids[c], ids[n]):
				astar.connect_points(ids[c], ids[n])


func _ceiling_with_hole(o: Vector3) -> void:
	# The elevator shaft comes down through the middle of the start room.
	var hole := 2.3
	var side := (CELL / 2.0 - hole)
	for s in [-1, 1]:
		A.box(self, Vector3(CELL, 0.2, side), o + Vector3(0, H + 0.1, s * (hole + side / 2.0)), theme.ceil_kind, theme.ceiling, true)
		A.box(self, Vector3(side, 0.2, hole * 2), o + Vector3(s * (hole + side / 2.0), H + 0.1, 0), theme.ceil_kind, theme.ceiling, true)


func _wall(center: Vector3, along_x: bool, door: bool) -> void:
	var a := (center.x if along_x else center.z)
	var c := (center.z if along_x else center.x)
	var band := 1.1
	var holes := [[a, DOOR_W, 0.0, DOOR_H]] if door else []
	var holes_up := [[a, DOOR_W, -10.0, DOOR_H - band]] if door else []
	A.wall(self, a - CELL / 2, a + CELL / 2, c, band, 0.34, holes, theme.band_kind, theme.band, along_x, 0.0, true, 1.5)
	A.wall(self, a - CELL / 2, a + CELL / 2, c, H - band, 0.3, holes_up, theme.wall_kind, theme.wall, along_x, band, true, 2.0)
	if door:
		var fc := Color(0.45, 0.42, 0.4)
		for s in [-1, 1]:
			var p := center + (Vector3(s * (DOOR_W / 2 + 0.06), DOOR_H / 2, 0) if along_x else Vector3(0, DOOR_H / 2, s * (DOOR_W / 2 + 0.06)))
			A.box(self, Vector3(0.12, DOOR_H, 0.42) if along_x else Vector3(0.42, DOOR_H, 0.12), p, "metal", fc, false)
		A.box(self, Vector3(DOOR_W + 0.24, 0.14, 0.42) if along_x else Vector3(0.42, 0.14, DOOR_W + 0.24), center + Vector3(0, DOOR_H + 0.07, 0), "metal", fc, false)


func _bulkhead(center: Vector3, along_x: bool, code: String) -> void:
	var size := Vector3(DOOR_W, DOOR_H, 0.18) if along_x else Vector3(0.18, DOOR_H, DOOR_W)
	var door := B.interactable(self, size, center + Vector3(0, DOOR_H / 2, 0), Color.WHITE,
		"Manual override on bulkhead %s (LOUD)" % code, set_door.bind(code, true, true), 6.0)
	door.get_child(1).material_override = A.mat("hazard", Color(0.9, 0.85, 0.8), 1.2)
	door.set_meta("open", false)
	for s in [-1, 1]:
		A.box(door, Vector3(0.7, 0.32, 0.02) if along_x else Vector3(0.02, 0.32, 0.7), Vector3(0, 0.6, 0.1 * s) if along_x else Vector3(0.1 * s, 0.6, 0), "metal", Color(0.1, 0.1, 0.1), false)
		var l := B.label(door, code, Vector3(0, 0.6, 0.12 * s) if along_x else Vector3(0.12 * s, 0.6, 0), 96, Color(1, 0.85, 0.2), false)
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
	if lane:
		var a := rng.randf_range(-4.0, 4.0)
		p = o + (Vector3(a, 0.6, 0) if rng.randf() < 0.5 else Vector3(0, 0.6, a))
	else:
		p = o + Vector3(_side(rng) * rng.randf_range(1.5, 5.0), 0.6, _side(rng) * rng.randf_range(1.5, 5.0))
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
	return o + Vector3(_side(rng) * rng.randf_range(2.2, lim), 0, _side(rng) * rng.randf_range(2.2, lim))


func _solid(pos: Vector3, size: Vector3) -> void:
	crates.append(AABB(pos - Vector3(size.x / 2, 0, size.z / 2), size))


func _dress(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	# Ceiling beams + a pipe run along one wall.
	if theme_id != "BACKROOMS":
		for z in [-3.0, 3.0]:
			A.box(self, Vector3(CELL, 0.25, 0.2), o + Vector3(0, H - 0.13, z), "rust", Color(0.8, 0.8, 0.8), false, 1.0)
		var w: Array = walls[rng.randi() % 4]
		var inward: Vector3 = w[2] * 0.35
		var along := Vector3(CELL / 2 - 0.3, 0, 0) if w[1] else Vector3(0, 0, CELL / 2 - 0.3)
		var kind := "flesh" if theme_id == "FLESH" else "metal"
		for y in [H - 0.45, H - 0.75]:
			A.pipe(self, w[0] + inward - along + Vector3(0, y, 0), w[0] + inward + along + Vector3(0, y, 0), 0.07 + rng.randf() * 0.05, kind)
	match theme_id:
		"FACTORY":
			for i in rng.randi_range(1, theme.props):
				var p := _quad(o, rng)
				match rng.randi() % 6:
					0, 1:
						var s := rng.randf_range(0.7, 1.2)
						A.crate(self, p, s, rng)
						_solid(p, Vector3(s, s, s))
						if rng.randf() < 0.5:
							A.crate(self, p + Vector3(0, s, 0), s * 0.7, rng)
							_solid(p, Vector3(s, s * 1.7, s))
					2:
						A.barrel(self, p, rng)
						_solid(p, Vector3(0.7, 0.9, 0.7))
					3:
						A.pallet(self, p)
						A.crate(self, p + Vector3(0, 0.15, 0), 0.6, rng)
						_solid(p, Vector3(0.7, 0.8, 0.7))
					4:
						A.rubble(self, p, rng)
					5:
						_wall_shelf(o, walls, rng)
			if rng.randf() < 0.12:
				A.tripod_light(self, _quad(o, rng, 1.5), rng.randf() * TAU, Color(1, 0.8, 0.5))
		"LAB":
			for i in rng.randi_range(1, theme.props):
				var p := _quad(o, rng, 1.2)
				match rng.randi() % 4:
					0, 1:
						A.desk(self, p, rng.randf_range(-0.2, 0.2) + (PI if rng.randf() < 0.5 else 0.0), rng)
						_solid(p, Vector3(1.6, 0.8, 1.6))
					2:
						_wall_shelf(o, walls, rng)
					3:
						var w: Array = walls[rng.randi() % 4]
						if not w[3]:
							var off := Vector3(rng.randf_range(-4, 4), 0, 0) if w[1] else Vector3(0, 0, rng.randf_range(-4, 4))
							A.locker(self, w[0] + w[2] * 0.45 + off, atan2(-w[2].x, -w[2].z))
		"FLESH":
			for i in rng.randi_range(2, theme.props + 2):
				A.blob(self, _quad(o, rng, 0.0) + Vector3(0, rng.randf_range(-0.2, 0.3), 0), rng.randf_range(0.4, 1.2), rng)
			for i in rng.randi_range(1, 3):
				var vp := o + Vector3(rng.randf_range(-5, 5), H, rng.randf_range(-5, 5))
				_tendrils(vp, rng)
			if rng.randf() < 0.4:
				var p := _quad(o, rng)
				A.crate(self, p, 0.9, rng)
				_solid(p, Vector3(0.9, 0.9, 0.9))
		"BACKROOMS":
			if rng.randf() < 0.25:
				A.box(self, Vector3(0.5, 0.45, 0.5), _quad(o, rng) + Vector3(0, 0.22, 0), "carpet", Color(0.6, 0.5, 0.4), true, 0.5)
			if rng.randf() < 0.3:
				A.box(self, Vector3(rng.randf_range(1, 2.5), 0.01, rng.randf_range(1, 2.5)), _quad(o, rng) + Vector3(0, 0.01, 0), "dirt", Color(0.4, 0.35, 0.3), false)
	if overgrown:
		for i in rng.randi_range(1, 4):
			A.vines(self, o + Vector3(rng.randf_range(-5, 5), H, rng.randf_range(-5, 5)), 2.5, rng)
		for i in rng.randi_range(0, 3):
			A.fern(self, _quad(o, rng, 0.0), rng)


func _wall_shelf(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var w: Array = walls[rng.randi() % 4]
	var off := Vector3(_side(rng) * 3.6, 0, 0) if w[1] else Vector3(0, 0, _side(rng) * 3.6)
	var p: Vector3 = w[0] + w[2] * 0.45 + off
	A.shelf_unit(self, p, atan2(w[2].x, w[2].z), rng, 2.0, 2.2, 0.5)
	_solid(p, Vector3(2.0, 2.2, 2.0))


func _tendrils(top: Vector3, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(2, 5):
		var l := rng.randf_range(0.8, 2.5)
		A.cyl(self, 0.06, l, top + Vector3(rng.randf_range(-0.5, 0.5), -l / 2, rng.randf_range(-0.5, 0.5)), "flesh", Color(0.8, 0.6, 0.6), false, "y", 0.02)


func _light(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var c: Color = theme.light
	var lights: Array[OmniLight3D] = []
	match theme_id:
		"FACTORY":
			if rng.randf() < 0.5:
				lights.append(A.hanging_lamp(self, o + Vector3(0, H, 0), c, 1.0, rng.randf_range(1.0, 1.6), true))
			else:
				var w: Array = walls[rng.randi() % 4]
				var off := Vector3(2.4, 0, 0) if w[1] else Vector3(0, 0, 2.4)
				lights.append(A.wall_lamp(self, w[0] + w[2] * 0.2 + off + Vector3(0, 2.7, 0), w[2], c, 1.3, true))
		"LAB", "BACKROOMS":
			for z in [-2.5, 2.5]:
				lights.append(A.fluorescent(self, o + Vector3(0, H - 0.05, z), c, 0.8))
			lights[0].shadow_enabled = true
		"FLESH":
			A.sphere(self, 0.2, o + Vector3(rng.randf_range(-3, 3), H - 0.15, rng.randf_range(-3, 3)), "flesh", c, 3.0)
			lights.append(B.omni(self, o + Vector3(0, H - 0.6, 0), c, 1.0, 9.0, true))
	for l in lights:
		if rng.randf() < 0.3:
			l.set_meta("base", l.light_energy)
			flicker.append(l)
