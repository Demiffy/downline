# Procedural underground facility: a grid of 12 m rooms grown from the elevator room.
# The layout is pure data from one seed, so every client can rebuild the same map later.
extends Node3D

const Data = preload("res://src/data.gd")
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
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	layout = gen_layout(seed, rooms, int(theme.bulkheads) + rng.randi() % 2)
	var door_at := {}
	for code in layout.doors:
		door_at[layout.doors[code]] = code
	for c: Vector2i in layout.cells:
		var o := Vector3(c.x * CELL, 0, c.y * CELL)
		B.box(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, -0.1, 0), theme.floor)
		B.box(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, H + 0.1, 0), theme.ceiling)
		for d: Vector2i in DIRS:
			var n := c + d
			# Shared walls are built once, by the cell on the -x / -z side.
			if layout.links.has(n) and (d.x < 0 or d.y < 0):
				continue
			var linked: bool = layout.links[c].has(n)
			var center := o + Vector3(d.x, 0, d.y) * (CELL / 2.0)
			_wall(center, d.y != 0, linked)
			if linked and door_at.has(edge(c, n)):
				_bulkhead(center, d.y != 0, door_at[edge(c, n)])
		if c != Vector2i.ZERO:
			_furnish(o, rng)
		if c == Vector2i.ZERO or rng.randf() < theme.light_chance:
			_light(o, rng)
		ids[c] = ids.size()
		cell_of_id[ids[c]] = c
		astar.add_point(ids[c], Vector3(c.x, 0, c.y))
	for c in layout.cells:
		for n in layout.links[c]:
			if not astar.are_points_connected(ids[c], ids[n]):
				astar.connect_points(ids[c], ids[n])


func _wall(center: Vector3, along_x: bool, door: bool) -> void:
	var t := 0.3
	var c: Color = theme.wall
	if not door:
		B.box(self, Vector3(CELL, H, t) if along_x else Vector3(t, H, CELL), center + Vector3(0, H / 2, 0), c)
		return
	var seg := (CELL - DOOR_W) / 2.0
	for s: float in [-1.0, 1.0]:
		var off := (DOOR_W + seg) / 2.0 * s
		var p := center + (Vector3(off, H / 2, 0) if along_x else Vector3(0, H / 2, off))
		B.box(self, Vector3(seg, H, t) if along_x else Vector3(t, H, seg), p, c)
	var lh := H - DOOR_H
	B.box(self, Vector3(DOOR_W, lh, t) if along_x else Vector3(t, lh, DOOR_W), center + Vector3(0, DOOR_H + lh / 2, 0), c)


func _bulkhead(center: Vector3, along_x: bool, code: String) -> void:
	var size := Vector3(DOOR_W, DOOR_H, 0.18) if along_x else Vector3(0.18, DOOR_H, DOOR_W)
	var door := B.interactable(self, size, center + Vector3(0, DOOR_H / 2, 0), Color(0.55, 0.45, 0.1),
		"Manual override on bulkhead %s (LOUD)" % code, set_door.bind(code, true, true), 6.0)
	door.set_meta("open", false)
	for s in [-1, 1]:
		var l := B.label(door, code, Vector3(0, 0.6, 0.1 * s) if along_x else Vector3(0.1 * s, 0.6, 0), 96, Color(1, 0.9, 0.2), false)
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


func _furnish(o: Vector3, rng: RandomNumberGenerator) -> void:
	# Props stay in the room quadrants so the lanes between doorways are always clear.
	for i in rng.randi_range(0, theme.props):
		var s := Vector3(rng.randf_range(0.8, 1.6), rng.randf_range(0.6, 2.0), rng.randf_range(0.8, 1.6))
		var lim := CELL / 2 - 0.6 - maxf(s.x, s.z) / 2
		var q := Vector3(_side(rng) * rng.randf_range(2.2, lim), s.y / 2, _side(rng) * rng.randf_range(2.2, lim))
		var c: Color = theme.prop
		B.box(self, s, o + q, c.darkened(rng.randf() * 0.35))
		crates.append(AABB(o + q - s / 2, s))


func _light(o: Vector3, rng: RandomNumberGenerator) -> void:
	var c: Color = theme.light
	var l := B.omni(self, o + Vector3(0, H - 0.5, 0), c, rng.randf_range(0.7, 1.3), 10.0, true)
	B.box(self, Vector3(1.2, 0.08, 0.3), o + Vector3(0, H - 0.04, 0), c, false, 2.0)
	if rng.randf() < 0.3:
		l.set_meta("base", l.light_energy)
		flicker.append(l)


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
