# Procedural underground facility: a grid of 12 m rooms grown from the elevator room.
# The layout is pure data from one seed, so every client can rebuild the same map later.
extends Node3D

const TwinLever = preload("res://src/twin_lever.gd")

const Data = preload("res://src/data.gd")
const Merge = preload("res://src/merge.gd")
const OfficeChair = preload("res://src/office_chair.gd")
const Grime = preload("res://src/grime.gd")
const A = preload("res://src/art.gd")
const P = preload("res://src/props.gd")
const Door = preload("res://src/door.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const Halls = preload("res://src/halls.gd")
const Interact = preload("res://src/interact.gd")

const CELL := 12.0
const H := 4.0
const DOOR_W := 2.4
const DOOR_H := 2.8
const PIT := 3.0
const NAV_CELL := 0.15
const NAV_CELL_H := 0.05
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
var nav: NavigationRegion3D   # the baked walkable surface (_bake_nav)
var _nav_links := {}   # bulkhead code -> NavigationLink3D across its doorway
var crates: Array[AABB] = []
var supplies: Array = []   # the supply crates (a save remembers which are open)
var flicker: Array[OmniLight3D] = []
var theme_id := ""
var jackpot := Vector3.INF   # a landmark's prize, where its set piece left room for it (dam_halls.gd)
var overgrown := false
var kinds := {}         # cell -> room archetype
var groups: Array = []  # big rooms: [{cells, shape, kind}] (halls.gd)
var group_of := {}      # cell -> index into groups
var cell_walls := {}    # cell -> its walls [center, along_x, normal, keep_clear, open_to_the_same_room]
var cameras: Array = []  # [{name, node, light}] security cameras for the terminal
var _wet := StandardMaterial3D.new()
var vault_cell := Vector2i(999, 999)   # dead end behind its own bulkhead, best loot inside
var vault_code := ""
var secure_code := ""                  # the records room's door: a four-digit keypad code, chalked on a wall somewhere
var secure_cell := Vector2i(999, 999)
var secure_lamp: StandardMaterial3D
var twin_code := ""                    # a blast door opened by two levers pulled together (twin_lever.gd)
var twin_cell := Vector2i(999, 999)
var twin_levers: Array = []
var vault_spots: Array[Vector3] = []   # where the vault's loot goes (local)
var vault_lamp: StandardMaterial3D     # the reader's lamp: red, green once a card goes in
var loot_spots: Array[Vector3] = []    # raised spots worth checking: mezzanines (local)
var vents := {}                        # edge -> offset along the shared wall
var _on_wall: Array[Vector3] = []     # wall spots already used by fixtures / decor in the room being dressed
var stairs := {}                       # cell -> {low, high (local points at each end), mid (y between the levels), exit_high, vertical}
var lower := {}                        # lower floor (B-2): cell -> linked lower cells. Pits and stairwells are its way in.
var low_kinds := {}                    # lower cell -> room archetype ("pit"/"stairwell" for the ways down)
var low_ids := {}                      # lower cell -> astar id
var layer_of_id := {}                  # astar id -> 0 upper, 1 lower
var low_root: Node3D                   # lower-floor rooms, on their own render layer
var holes: Array[AABB] = []            # stairwell openings (local): nothing but the stairs may sit in them
const NO_VENT := ["start", "pit", "tunnel", "vault", "stairwell"]
const LOW_H := PIT - 0.2        # headroom on the lower floor (its ceiling is the upper floor's slab)
const LOWER_BIT := 1 << 5        # render layer for the lower floor: upper rooms' lights skip it   # puddles: dark and glossy, catch the flashlight


## cells: Array[Vector2i]; links: cell -> Array of linked neighbour cells; doors: code -> [a, b] edge.
static func gen_layout(seed: int, rooms: int, n_doors: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var links := {Vector2i.ZERO: []}
	var corridor := {}   # cells laid as a straight run: long corridors (tunnels) between the wings
	# A core round the lift, then wings: a long corridor out from somewhere, a cluster of rooms at its
	# end, and again, so the place sprawls and its far ends are a long walk from each other.
	_grow_cluster(rng, cells, links, Vector2i.ZERO, mini(rng.randi_range(3, 5), rooms - 1), rooms)
	var tries := 0
	while cells.size() < rooms and tries < 400:
		tries += 1
		var from: Vector2i = cells[rng.randi() % cells.size()]
		if corridor.has(from):
			continue
		var d: Vector2i = DIRS[rng.randi() % 4]
		var run := mini(rng.randi_range(2, 6), rooms - cells.size())
		var ok := run > 0
		for k in range(1, run + 2):   # (the run, and room for the cluster at its end)
			if links.has(from + d * k):
				ok = false
				break
		if not ok:
			if tries > 300:   # (boxed in: grow a room anywhere instead)
				_grow_cluster(rng, cells, links, from, 1, rooms)
			continue
		var prev := from
		for k in range(1, run + 1):
			var c: Vector2i = from + d * k
			cells.append(c)
			links[c] = []
			_link(links, prev, c)
			if k < run:
				corridor[c] = true
			prev = c
		_grow_cluster(rng, cells, links, prev, rng.randi_range(2, 5), rooms)
	while cells.size() < rooms:   # (never short: whatever's left grows on anywhere)
		_grow_cluster(rng, cells, links, cells[rng.randi() % cells.size()], 1, rooms)
	# A few extra loops so it's not a pure tree (escape routes matter); corridors stay straight runs.
	for c in cells:
		if corridor.has(c):
			continue
		for d in DIRS:
			if links.has(c + d) and not corridor.has(c + d) and rng.randf() < 0.12:
				_link(links, c, c + d)
	var groups := _pick_groups(rng, cells, links, rooms, corridor)
	var group_of := {}
	for gi in groups.size():
		for c in groups[gi].cells:
			group_of[c] = gi
	var door_edges := {}
	for i in 60:
		if door_edges.size() >= n_doors or rooms < 3:
			break
		var a: Vector2i = cells[rng.randi() % cells.size()]
		if a == Vector2i.ZERO:
			continue
		var b: Vector2i = links[a][rng.randi() % links[a].size()]
		if b == Vector2i.ZERO or (group_of.has(a) and group_of.get(b, -1) == group_of[a]):
			continue   # (no bulkhead inside a big room)
		var code := "%s%d%d" % [char(65 + rng.randi() % 26), rng.randi() % 10, rng.randi() % 10]
		if not door_edges.has(code) and not door_edges.values().has(edge(a, b)):
			door_edges[code] = edge(a, b)
	return {"cells": cells, "links": links, "doors": door_edges, "groups": groups, "group_of": group_of, "corridor": corridor}


## Rooms grown out from `at` one by one, each onto one already there (a cluster, not a line).
static func _grow_cluster(rng: RandomNumberGenerator, cells: Array, links: Dictionary, at: Vector2i, n: int, cap: int) -> void:
	var mine: Array = [at]
	var added := 0
	for i in n * 12:
		if added >= n or cells.size() >= cap:
			return
		var from: Vector2i = mine[rng.randi() % mine.size()]
		var to: Vector2i = from + DIRS[rng.randi() % 4]
		if links.has(to):
			continue
		cells.append(to)
		links[to] = []
		_link(links, from, to)
		mine.append(to)
		added += 1


## Big rooms: a few cells merged into one 2x1, L-shaped (3 cells) or, rarely, 2x2 room. No walls
## between their cells; the lift room never joins one. [{cells, shape}]
static func _pick_groups(rng: RandomNumberGenerator, cells: Array, links: Dictionary, rooms: int, corridor := {}) -> Array:
	var groups := []
	var taken := {Vector2i.ZERO: true}
	for c in corridor:   # (corridors stay corridors)
		taken[c] = true
	var want := clampi(rooms / 8, 1, 4)
	for attempt in 80:
		if groups.size() >= want:
			break
		var c: Vector2i = cells[rng.randi() % cells.size()]
		if taken.has(c):
			continue
		var roll := rng.randf()
		var d1: Vector2i = DIRS[rng.randi() % 4]
		var d2 := Vector2i(d1.y, d1.x) * (1 if rng.randf() < 0.5 else -1)   # perpendicular to d1
		var shape := "2x1"
		var mine: Array = [c, c + d1]
		if roll < 0.12 and rooms >= 16:
			shape = "2x2"
			mine = [c, c + d1, c + d2, c + d1 + d2]
		elif roll < 0.5:
			shape = "L"
			mine = [c, c + d1, c + d2]   # c is the corner
		if mine.any(func(x): return not links.has(x) or taken.has(x)):
			continue
		for x in mine:
			taken[x] = true
			for y in mine:   # every cell in it opens onto its neighbours in it
				if x != y and (x - y).length_squared() == 1:
					_link(links, x, y)
		groups.append({"cells": mine, "shape": shape})
	return groups


static func _link(links: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not links[a].has(b):
		links[a].append(b)
		links[b].append(a)


static func edge(a: Vector2i, b: Vector2i) -> Array:
	return [a, b] if (a.x < b.x or (a.x == b.x and a.y < b.y)) else [b, a]


## `mark` (level.gd's): awaited between rooms, so a build can be spread over frames; it also
## reseeds the global dice from the place it's called, so the result is the same either way.
var _mark := Callable()
var _sliced := false

func _m(tag: String) -> void:
	if _mark.is_valid():
		await _mark.call(tag)


func build(seed: int, rooms: int, theme_name: String, mark := Callable(), sliced := false) -> void:
	_mark = mark
	_sliced = sliced
	var merge_mark := mark if sliced else Callable()   # (merging on a worker thread only when spread over frames)
	theme = Data.THEMES[theme_name]
	_wet.albedo_color = Color(0.03, 0.035, 0.04, 0.7)
	_wet.roughness = 0.04
	_wet.metallic = 0.2
	_wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var wg := GradientTexture2D.new()   # soft edges
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.5, Color(1, 1, 1, 0.8))
	wg.gradient = grad
	wg.fill = GradientTexture2D.FILL_RADIAL
	wg.fill_from = Vector2(0.5, 0.5)
	wg.fill_to = Vector2(0.5, 0.0)
	_wet.albedo_texture = wg
	theme_id = theme_name
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	overgrown = theme_name in ["FACTORY", "LAB"] and rng.randf() < 0.35
	layout = gen_layout(seed, rooms, int(theme.bulkheads) + rng.randi() % 2)
	groups = layout.groups
	group_of = layout.group_of
	var used_kinds: Array = []
	for g in groups:
		g.kind = Halls.pick_kind(theme_name, g.shape, rng, used_kinds)
	_pick_vault(rng)
	_pick_secure(rng)
	_pick_twin(rng)
	var door_at := {}
	for code in layout.doors:
		door_at[layout.doors[code]] = code
	for c: Vector2i in layout.cells:
		kinds[c] = "vault" if c == vault_cell else (groups[group_of[c]].kind if group_of.has(c) else _pick_kind(c, rng))
	_place_stairwells(rng)
	_gen_lower(rng)
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
				crates.append(AABB(mid - Vector3(1.0, 0, 1.0), Vector3(2.0, 1.4, 2.0)))   # keep it clear
	for c: Vector2i in layout.cells:
		await _m("room %d %d" % [c.x, c.y])
		var o := Vector3(c.x * CELL, 0, c.y * CELL)
		var kind: String = kinds[c]
		if kind != "pit" and kind != "stairwell":   # (those two build their own floor, with the way down in it)
			A.sbox(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, -0.1, 0), theme.floor_kind, theme.floor, true, 2.0)
		if c == Vector2i.ZERO:
			_ceiling_with_hole(o)
		elif theme_id == "BACKROOMS":
			_drop_ceiling(o, rng)
		else:
			A.sbox(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, H + 0.1, 0), theme.ceil_kind, theme.ceiling, true, 2.0)
		var walls := []  # [center, along_x, normal_into_room, has_door]
		for d: Vector2i in DIRS:
			var n := c + d
			var linked: bool = layout.links[c].has(n)
			var center := o + Vector3(d.x, 0, d.y) * (CELL / 2.0)
			var inside: bool = group_of.has(c) and group_of.get(n, -1) == group_of[c]
			walls.append([center, d.y != 0, -Vector3(d.x, 0, d.y), linked or vents.has(edge(c, n)), inside])   # [3] = keep clear (door or vent), [4] = open to the same big room
			if inside:   # no wall inside a big room: a header across the seam instead (built once)
				if d.x > 0 or d.y > 0:
					Halls.header(self, center, d.y != 0, theme, theme_id)
				continue
			# Shared walls are built once, by the cell on the -x / -z side.
			if layout.links.has(n) and (d.x < 0 or d.y < 0):
				continue
			_wall(center, d.y != 0, linked, vents.get(edge(c, n), INF))
			if linked and door_at.has(edge(c, n)):
				_bulkhead(center, d.y != 0, door_at[edge(c, n)])
			elif linked and rng.randf() < 0.55 and kinds[c] != "tunnel" and kinds[n] != "tunnel" \
					and not (kinds[c] in ["atrium", "pit", "stairwell"] and kinds[n] in ["atrium", "pit", "stairwell"]):   # (a leaf would swing over stairs either way)
				_hinged_door(center, d.y != 0, rng, kinds[c], kinds[n])
		cell_walls[c] = walls
		if group_of.has(c):   # big rooms are dressed whole, below; every cell of one is lit
			Halls.light(self, o, kind, theme, theme_id, rng)
			if groups[group_of[c]].cells[0] == c:
				_camera(o, rng)
		else:
			if c != Vector2i.ZERO:
				_dress(c, o, walls, rng)
				_puddles(c, o)
				if not kinds[c] in ["pit", "tunnel", "vault"] and rng.randf() < 0.35:
					_supply_crate(o, walls, rng)
			if c == Vector2i.ZERO or kind in ["pit", "tunnel"] or rng.randf() < theme.light_chance:
				_light(o, walls, rng)
			if kind != "tunnel" and (c == Vector2i.ZERO or rng.randf() < 0.35):
				_camera(o, rng)
		ids[c] = ids.size()
		cell_of_id[ids[c]] = c
		astar.add_point(ids[c], Vector3(c.x, 0, c.y))
		layer_of_id[ids[c]] = 0
	for g in groups:   # the set pieces, now every wall and doorway of each big room is known
		await _m("hall %d %d" % [g.cells[0].x, g.cells[0].y])
		await Halls.dress(self, g, rng)
		var gc: Vector2i = g.cells[0]
		if rng.randf() < 0.5:
			_supply_crate(Vector3(gc.x * CELL, 0, gc.y * CELL), cell_walls[gc].filter(func(w): return not w[4]), rng)
	for c in layout.cells:
		for n in layout.links[c]:
			if not astar.are_points_connected(ids[c], ids[n]):
				astar.connect_points(ids[c], ids[n])
	for code in doors:   # bulkheads start shut: nothing plans a route through one
		_door_link(code, false)
	_secure_clue(rng)
	_place_twin_levers(rng)
	await _m("grime")
	Grime.dress(self, cell_walls, kinds, H, CELL)   # (rust, stains, peeling paint: from each room's own dice)
	if not _walls_seen:
		_see_walls()   # (hazards.gd's breaker looks too, after the merge)
	await _build_lower(rng)
	await _m("holes")
	_clear_holes()
	await Merge.bake(low_root, 12.0, true, Merge.FAR, merge_mark)
	Merge.live(low_root)   # baked on its own, so its meshes keep their own render layer
	for mi: MeshInstance3D in low_root.find_children("*", "MeshInstance3D", true, false):
		B.set_layers(mi, LOWER_BIT)   # (the merge has let frames go by: they may be lit already)
	await Merge.bake(self, 12.0, true, Merge.FAR, merge_mark)   # thousands of primitives -> a mesh or two per room
	await _m("occluders")
	_occluders()
	for l: Light3D in find_children("*", "Light3D", true, false):   # upstairs lights don't shine through the floor
		if not low_root.is_ancestor_of(l):
			B.set_cull_mask(l, l.light_cull_mask & ~LOWER_BIT)
	await _m("nav")
	await _bake_nav()
	_mark = Callable()


func _pick_kind(c: Vector2i, rng: RandomNumberGenerator) -> String:
	if c == Vector2i.ZERO:
		return "start"
	var l: Array = layout.links[c]
	var straight: bool = l.size() == 2 and (l[0] - c) == -(l[1] - c)
	if straight and theme_id != "BACKROOMS" and rng.randf() < (0.95 if layout.get("corridor", {}).has(c) else 0.6):
		return "tunnel"
	var table: Dictionary = {
		"FACTORY": {"storage": 3, "machine": 3, "pit": 2, "collapsed": 1, "break": 1, "office": 1, "atrium": 2},
		"LAB": {"lab": 3, "office": 3, "server": 2, "storage": 1, "break": 1, "atrium": 1},
		"FLESH": {"lab": 2, "machine": 2, "pit": 1, "storage": 1, "collapsed": 1, "atrium": 1},
		"BACKROOMS": {"empty": 4, "office": 1, "storage": 1},
		"DAM": {"machine": 3, "storage": 2, "pit": 2, "office": 1, "break": 1, "atrium": 1, "collapsed": 1},
	}[theme_id]
	var pool := []
	for k in table:
		for i in table[k]:
			pool.append(k)
	return pool[rng.randi() % pool.size()]


func _drop_ceiling(o: Vector3, rng: RandomNumberGenerator) -> void:
	A.sbox(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, H + 0.1, 0), "ceiling_tile", Color.WHITE, true, 2.0)
	for p in [Vector3(-3, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, 3), Vector3(3, 0, -3)]:
		if rng.randf() < 0.7:
			A.glow(self, Vector3(1.2, 0.03, 1.2), o + p + Vector3(0, H - 0.01, 0), Color(1, 0.95, 0.75), 2.5)


## Hinged door in a doorway; half of them start open. `from_kind` is the room on the -x/-z side,
## `to_kind` the other. Leaves never swing into a room with stairs (they'd land across the flight).
func _hinged_door(center: Vector3, along_x: bool, rng: RandomNumberGenerator, from_kind := "", to_kind := "") -> void:
	var d := Door.new()
	add_child(d)
	if along_x:
		d.position = center + Vector3(-DOOR_W / 2 + 0.015, 0, 0)   # the jambs stand 1.5 cm into the opening
	else:
		d.position = center + Vector3(0, 0, -DOOR_W / 2 + 0.015)
		d.rotation.y = -PI / 2
	var kind: String = {"FACTORY": "riveted", "LAB": "cream", "FLESH": "riveted", "BACKROOMS": "wood", "DAM": "riveted"}[theme_id]
	var tint: Color = {"FACTORY": Color(0.7, 0.65, 0.55), "LAB": Color.WHITE, "FLESH": Color(0.7, 0.45, 0.4), "BACKROOMS": Color(0.85, 0.75, 0.6), "DAM": Color(0.5, 0.6, 0.55)}[theme_id]
	var swing := 1.0 if rng.randf() < 0.5 else -1.0
	var stairy := ["atrium", "pit", "stairwell"]
	# swing +1 opens the leaves toward the door's local -z; which room is that?
	var toward: Vector3 = d.basis * Vector3(0, 0, -1)
	var toward_from := toward.dot(Vector3(0, 0, -1) if along_x else Vector3(-1, 0, 0)) > 0.0
	if from_kind in stairy and not to_kind in stairy:
		swing = -1.0 if toward_from else 1.0
	elif to_kind in stairy and not from_kind in stairy:
		swing = 1.0 if toward_from else -1.0
	d.setup(DOOR_W - 0.03, DOOR_H - 0.02, kind, tint, rng.randf() < 0.5, swing, 0.15)


func _ceiling_with_hole(o: Vector3) -> void:
	# The elevator shaft comes down through the middle of the start room.
	var hole := 2.3
	var side := (CELL / 2.0 - hole)
	for s in [-1, 1]:
		A.sbox(self, Vector3(CELL, 0.2, side), o + Vector3(0, H + 0.1, s * (hole + side / 2.0)), theme.ceil_kind, theme.ceiling, true)
		A.sbox(self, Vector3(side, 0.2, hole * 2), o + Vector3(s * (hole + side / 2.0), H + 0.1, 0), theme.ceil_kind, theme.ceiling, true)


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
			A.sbox(self, Vector3(0.12, DOOR_H - 0.015, 0.42) if along_x else Vector3(0.42, DOOR_H - 0.015, 0.12), p, "metal", fc, false)
		A.sbox(self, Vector3(DOOR_W + 0.24, 0.14, 0.42) if along_x else Vector3(0.42, 0.14, DOOR_W + 0.24), center + Vector3(0, DOOR_H + 0.055, 0), "metal", fc, false)


func _bulkhead(center: Vector3, along_x: bool, code: String) -> void:
	var size := Vector3(DOOR_W, DOOR_H, 0.18) if along_x else Vector3(0.18, DOOR_H, DOOR_W)
	var vault := code == vault_code
	var secure := code == secure_code
	var twin := code == twin_code
	var door := B.interactable(self, size, center + Vector3(0, DOOR_H / 2, 0), Color.WHITE,
		"VAULT: sealed. Swipe the vault keycard at the reader" if vault else ("SECURED: keypad locked" if secure else ("TWIN-KEY BLAST DOOR" if twin else "Manual override on bulkhead %s (LOUD)" % code)),
		_vault_sealed if vault else (_secure_denied if secure else (_twin_denied if twin else set_door.bind(code, true, true))), 0.0 if vault or secure or twin else 6.0)
	door.get_child(1).material_override = A.mat("riveted", Color(0.5, 0.52, 0.54), 0.8) if vault else (A.mat("riveted", Color(0.36, 0.45, 0.38), 0.8) if secure else A.mat("hazard", Color(0.9, 0.85, 0.8), 1.2))
	if vault:
		_vault_door(door, center, along_x)
	if secure:
		_secure_door(door, center, along_x)
	if twin:   # a heavier door: a steel frame, TWO-MAN RULE stencilled over it
		for s in [-1.0, 1.0]:
			var sd := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
			A.sbox(self, Vector3(0.26, DOOR_H + 0.26, 0.4) if along_x else Vector3(0.4, DOOR_H + 0.26, 0.26), center + sd * s * (DOOR_W / 2 + 0.13) + Vector3(0, (DOOR_H + 0.26) / 2, 0), "riveted", Color(0.4, 0.4, 0.38), false, 0.6)
			var nz := Vector3(0, 0, s * 0.21) if along_x else Vector3(s * 0.21, 0, 0)
			var t := B.label(self, "TWO-MAN RULE", center + nz + Vector3(0, DOOR_H + 0.13, 0), 26, Color(0.95, 0.85, 0.3), "stencil", 0.005)
			t.rotation.y = (0.0 if s > 0 else PI) if along_x else (PI / 2 if s > 0 else -PI / 2)
		A.sbox(self, Vector3(DOOR_W + 0.52, 0.26, 0.4) if along_x else Vector3(0.4, 0.26, DOOR_W + 0.52), center + Vector3(0, DOOR_H + 0.13, 0), "riveted", Color(0.4, 0.4, 0.38), false, 0.6)
	door.set_meta("open", false)
	for s in [-1, 1]:
		A.sbox(door, Vector3(0.8, 0.5, 0.02) if along_x else Vector3(0.02, 0.5, 0.8), Vector3(0, 0.6, 0.1 * s) if along_x else Vector3(0.1 * s, 0.6, 0), "metal", Color(0.1, 0.1, 0.1), false)
		var l := B.label(door, "SECURED" if secure else code, Vector3(0, 0.6, 0.12 * s) if along_x else Vector3(0.12 * s, 0.6, 0), 40 if secure else 80, Color(0.95, 0.8, 0.25))
		if code == vault_code:   # the vault door says so
			var v := B.label(door, "VAULT", Vector3(0, 1.75, 0.12 * s) if along_x else Vector3(0.12 * s, 1.75, 0), 60, Color(0.85, 0.15, 0.1))
			v.rotation.y = (0.0 if s > 0 else PI) if along_x else (PI / 2 if s > 0 else -PI / 2)
		if along_x:
			l.rotation.y = 0.0 if s > 0 else PI
		else:
			l.rotation.y = PI / 2 if s > 0 else -PI / 2
	doors[code] = door


## The records room's door: a steel frame, a keypad on the wall outside with its little screen and
## a lamp (red, green once the code's gone in), RECORDS stencilled over the door.
func _secure_door(door: Node3D, center: Vector3, along_x: bool) -> void:
	var sc := Vector3(secure_cell.x * CELL, 0, secure_cell.y * CELL)
	var n := Vector3(0, 0, signf(center.z - sc.z)) if along_x else Vector3(signf(center.x - sc.x), 0, 0)   # out of the room
	var side := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var steel := Color(0.32, 0.38, 0.34)
	for s in [-1.0, 1.0]:
		A.sbox(self, Vector3(0.22, DOOR_H + 0.2, 0.34) if along_x else Vector3(0.34, DOOR_H + 0.2, 0.22), center + side * s * (DOOR_W / 2 + 0.11) + Vector3(0, (DOOR_H + 0.2) / 2, 0), "riveted", steel, false, 0.6)
	A.sbox(self, Vector3(DOOR_W + 0.44, 0.22, 0.34) if along_x else Vector3(0.34, 0.22, DOOR_W + 0.44), center + Vector3(0, DOOR_H + 0.11, 0), "riveted", steel, false, 0.6)
	var warn := B.label(self, "RECORDS  ·  KEYPAD ACCESS", center + n * 0.18 + Vector3(0, DOOR_H + 0.11, 0), 24, Color(0.92, 0.88, 0.75), "stencil", 0.005)
	warn.rotation.y = atan2(n.x, n.z)
	var pad := Node3D.new()
	add_child(pad)
	pad.position = center + n * 0.2 + side * (DOOR_W / 2 + 0.5) + Vector3(0, 1.35, 0)
	pad.rotation.y = atan2(n.x, n.z)
	A.sbox(pad, Vector3(0.22, 0.32, 0.05), Vector3.ZERO, "metal", Color(0.55, 0.56, 0.54), false, 0.4)
	A.sbox(pad, Vector3(0.16, 0.05, 0.01), Vector3(0, 0.1, 0.027), "metal", Color(0.05, 0.08, 0.05), false)   # the screen
	for r in 4:
		for k in 3:
			A.sbox(pad, Vector3(0.04, 0.03, 0.012), Vector3(-0.05 + k * 0.05, 0.03 - r * 0.045, 0.028), "plastic", Color(0.2, 0.2, 0.2) if not (r == 3 and k != 1) else Color(0.6, 0.15, 0.1), false, 0.2)
	secure_lamp = StandardMaterial3D.new()
	secure_lamp.albedo_color = Color(0.6, 0.05, 0.05)
	secure_lamp.emission_enabled = true
	secure_lamp.emission = Color(1, 0.12, 0.08)
	secure_lamp.emission_energy_multiplier = 3.0
	var lamp := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.03, 0.03, 0.012)
	lamp.mesh = lm
	lamp.material_override = secure_lamp
	pad.add_child(lamp)
	lamp.position = Vector3(0.07, 0.135, 0.028)
	pad.set_meta("live", true)


## The vault's own door dressing: a heavy steel surround with hazard chevrons, the locking wheel
## and bolts on the door, and the keycard reader on the wall outside, its lamp red until a card
## goes in.
func _vault_door(door: Node3D, center: Vector3, along_x: bool) -> void:
	var vc := Vector3(vault_cell.x * CELL, 0, vault_cell.y * CELL)
	var n := Vector3(0, 0, signf(center.z - vc.z)) if along_x else Vector3(signf(center.x - vc.x), 0, 0)   # out of the vault
	var side := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var steel := Color(0.38, 0.4, 0.42)
	for s in [-1.0, 1.0]:   # the surround: thick jambs and a lintel, both faces of the wall
		for f in [-1.0, 1.0]:
			A.sbox(self, Vector3(0.32, DOOR_H + 0.3, 0.12) if along_x else Vector3(0.12, DOOR_H + 0.3, 0.32), center + side * s * (DOOR_W / 2 + 0.16) + n * f * 0.2 + Vector3(0, (DOOR_H + 0.3) / 2, 0), "riveted", steel, false, 0.6)
			A.sbox(self, Vector3(0.06, DOOR_H, 0.02) if along_x else Vector3(0.02, DOOR_H, 0.06), center + side * s * (DOOR_W / 2 + 0.16) + n * f * 0.265 + Vector3(0, DOOR_H / 2, 0), "hazard", Color.WHITE, false, 0.5)
	for f in [-1.0, 1.0]:
		A.sbox(self, Vector3(DOOR_W + 0.64, 0.3, 0.12) if along_x else Vector3(0.12, 0.3, DOOR_W + 0.64), center + n * f * 0.2 + Vector3(0, DOOR_H + 0.15, 0), "riveted", steel, false, 0.6)
	# On the door itself, both faces: a locking wheel and a ring of bolt heads.
	for f in [-1.0, 1.0]:
		var face := Node3D.new()
		door.add_child(face)
		face.position = (Vector3(0, 0, f * 0.1) if along_x else Vector3(f * 0.1, 0, 0)) + Vector3(0, -0.32, 0)   # (below the door's code)
		face.rotation.y = (0.0 if f > 0 else PI) if along_x else (PI / 2 if f > 0 else -PI / 2)
		A.sring(face, 0.42, 0.38, Vector3(0, 0, 0.02), "metal", Color(0.62, 0.62, 0.6), Vector3(PI / 2, 0, 0))
		for k in 4:
			var spoke := Node3D.new()
			face.add_child(spoke)
			spoke.rotation.z = PI / 4 + k * PI / 2
			A.sbox(spoke, Vector3(0.05, 0.4, 0.04), Vector3(0, 0.2, 0.03), "metal", Color(0.55, 0.55, 0.53), false)
		A.scyl(face, 0.09, 0.08, Vector3(0, 0, 0.05), "brass", Color(0.8, 0.62, 0.3), false, "z")
		for k in 12:
			var a := TAU * k / 12.0
			A.scyl(face, 0.03, 0.03, Vector3(cos(a) * 0.62, sin(a) * 0.62, 0.0), "metal", Color(0.3, 0.3, 0.32), false, "z")
	# The keycard reader, outside, by the door: a black box, a slot, a lamp.
	var at := center + n * 0.24 + side * (DOOR_W / 2 + 0.55) + Vector3(0, 1.35, 0)
	var reader := Node3D.new()
	add_child(reader)
	reader.position = at
	reader.rotation.y = atan2(n.x, n.z)   # (its face towards whoever comes up to the door)
	A.sbox(reader, Vector3(0.16, 0.24, 0.06), Vector3.ZERO, "plastic", Color(0.08, 0.08, 0.08), false, 0.4)
	A.sbox(reader, Vector3(0.11, 0.012, 0.012), Vector3(0, 0.05, 0.032), "metal", Color(0.02, 0.02, 0.02), false)   # the slot
	var lamp_m := StandardMaterial3D.new()
	lamp_m.albedo_color = Color(0.6, 0.05, 0.05)
	lamp_m.emission_enabled = true
	lamp_m.emission = Color(1, 0.12, 0.08)
	lamp_m.emission_energy_multiplier = 3.0
	var lamp := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.05, 0.02, 0.012)
	lamp.mesh = lm
	lamp.material_override = lamp_m
	reader.add_child(lamp)
	lamp.position = Vector3(0, -0.06, 0.032)
	reader.set_meta("live", true)
	var lbl := B.label(reader, "VAULT ACCESS", Vector3(0, 0.15, 0.031), 18, Color(0.85, 0.85, 0.8), "plate", 0.004)
	vault_lamp = lamp_m
	var it := B.interactable(reader, Vector3(0.22, 0.3, 0.14), Vector3.ZERO, Color(0, 0, 0, 0), "Swipe the vault keycard", _vault_swipe, 0.0)
	it.set_meta("vault_reader", true)
	var warn := B.label(self, "AUTHORISED PERSONNEL ONLY", center + n * 0.27 + Vector3(0, DOOR_H + 0.15, 0), 26, Color(0.9, 0.85, 0.75), "stencil", 0.005)
	warn.rotation.y = atan2(n.x, n.z)
	# A caged lamp over the door, outside: amber, so you can find it from down the corridor.
	var lamp_at := center + n * 0.4 + Vector3(0, DOOR_H + 0.55, 0)
	A.scyl(self, 0.09, 0.14, lamp_at, "glow", Color(1.0, 0.6, 0.2), false)
	A.sring(self, 0.11, 0.095, lamp_at, "metal", Color(0.2, 0.2, 0.2))
	B.omni(self, lamp_at + n * 0.2, Color(1.0, 0.62, 0.3), 1.4, 6.0)


## E on the sealed vault door.
func _vault_sealed() -> void:
	if main and main.net.authority() and not doors[vault_code].get_meta("open"):
		main.hud.msg("The vault door won't move. There's a keycard reader beside it.")
		Sfx.play(self, "error", doors[vault_code].global_position, -6.0)


## A keycard in hand, swiped at the reader: the vault opens (the host decides). The card stays in
## the reader.
func _vault_swipe() -> void:
	if main == null or not main.net.authority() or doors[vault_code].get_meta("open"):
		return
	var who = Interact.who_now
	var held = who.slots[who.sel] if who != null and "slots" in who and who.slots[who.sel] != null else null
	if held == null or held.id != "VAULT_KEYCARD":
		main.hud.msg("ACCESS DENIED. Vault keycard required (hold it in your hand).")
		Sfx.play(self, "error", doors[vault_code].global_position, -2.0, 0.8)
		return
	if who == main.player:
		who.consume("VAULT_KEYCARD")
	else:
		main.net.to_owner(who.peer, "take", "VAULT_KEYCARD")
	open_vault()


## The card's accepted: the lamp goes green, bolts draw back, the door rises.
func open_vault() -> void:
	if vault_lamp:
		vault_lamp.emission = Color(0.2, 1, 0.3)
		vault_lamp.albedo_color = Color(0.1, 0.5, 0.1)
	Sfx.play(self, "ding", doors[vault_code].global_position, -4.0, 1.2)
	Sfx.play(self, "breaker", doors[vault_code].global_position, 0.0, 0.7)
	set_door(vault_code, true)
	if main:
		main.hud.msg("ACCESS GRANTED.")


## Opens/closes a bulkhead. loud = the manual override, which alarms the whole area.
func set_door(code: String, open: bool, loud := false) -> bool:
	if not doors.has(code):
		return false
	var door: Node3D = doors[code]
	if door.get_meta("open") == open:
		return true
	door.set_meta("open", open)
	_door_link(code, open)
	if code == vault_code and open and vault_lamp:
		vault_lamp.emission = Color(0.2, 1, 0.3)
	if code == secure_code and secure_lamp:
		secure_lamp.emission = Color(0.2, 1, 0.3) if open else Color(1, 0.12, 0.08)
	if main:
		main.net.event("door", [code, open, loud])   # (the crew's bulkheads move too)
	var tw := create_tween()
	tw.tween_property(door, "position:y", DOOR_H / 2 + (DOOR_H if open else 0.0), 1.2)
	Sfx.play(self, "bulkhead", door.global_position, -3.0, randf_range(0.95, 1.05))
	if loud:
		Sfx.play(self, "klaxon", door.global_position, -2.0)
		if main:
			main.noise(door.global_position, 35.0)
	return true


# --- occlusion ------------------------------------------------------------------------------

## Occluders for the solid walls, floors and ceilings (big flat boxes that never move): the
## renderer skips whatever is behind them, so the rooms you can't see cost nothing to draw.
func _occluders() -> void:
	for body in get_children() + low_root.get_children():
		if not body is StaticBody3D or body.get_script() != null or body.collision_layer & 1 == 0:
			continue
		for cs in body.get_children():
			if not cs is CollisionShape3D or not cs.shape is BoxShape3D:
				continue
			var s: Vector3 = cs.shape.size
			var dims := [s.x, s.y, s.z]
			dims.sort()
			if dims[0] > 0.6 or dims[1] < 2.4:   # thin, and big both other ways
				continue
			var oc := OccluderInstance3D.new()
			var bo := BoxOccluder3D.new()
			bo.size = s * Vector3(0.96, 0.96, 0.96)   # (a hair inside: never hide what peeks round an edge)
			oc.occluder = bo
			cs.add_child(oc)


# --- navigation mesh -----------------------------------------------------------------------

## The walkable surface of the whole site, both floors, baked once from the real collision
## geometry: monsters route round crates, barrels, railings and the lift shaft, and up and down
## the stairs, instead of walking straight lines between doorways. Swing doors are read standing open
## (read standing open, as monsters will shove them). Bulkheads stay solid; an open one gets a link across its doorway.
func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = NAV_CELL
	nm.cell_height = NAV_CELL_H
	nm.agent_radius = 0.3   # (any wider and the 1 m stair flights erode away; nav_path keeps bends off corners instead)
	nm.agent_height = 1.4
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 46.0
	nm.region_min_size = 1.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1 | 16   # world + railing panels
	nm.filter_low_hanging_obstacles = true
	nm.filter_ledge_spans = false   # (would eat the open-sided stair wedges from both edges)
	nm.filter_walkable_low_height_spans = true
	var swung := []   # swing doors: read standing open (monsters shove them open), so routes go round the leaves
	for d in get_children():
		if d.has_method("set_open"):
			swung.append([d, d.open])
			d._apply(true, false)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	await _m("nav parsed")
	# The lift shaft stands in the start room but belongs to the elevator, not to us: block it out.
	var sh := 2.65
	src.add_projected_obstruction(PackedVector3Array([Vector3(-sh, 0, -sh), Vector3(sh, 0, -sh), Vector3(sh, 0, sh), Vector3(-sh, 0, sh)]), -0.5, H + 1.0, true)
	for d in swung:
		d[0]._apply(d[1], false)
	if _sliced:   # (a stop built on the way: baked on a worker thread while the train runs on; built at once, it's done before build returns)
		var done := [false]
		NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func(): done[0] = true)
		while not done[0]:
			await get_tree().process_frame
	else:
		NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, NAV_CELL)
	NavigationServer3D.map_set_cell_height(map, NAV_CELL_H)
	nav = NavigationRegion3D.new()
	add_child(nav)
	nav.navigation_mesh = nm
	for code in doors:   # a link across each bulkhead's doorway, live while it's open
		var e: Array = layout.doors[code]
		var a := Vector3(e[0].x * CELL, 0.0, e[0].y * CELL)
		var b := Vector3(e[1].x * CELL, 0.0, e[1].y * CELL)
		var mid := (a + b) / 2.0
		var dir := (b - a).normalized()
		var link := NavigationLink3D.new()
		link.bidirectional = true
		link.start_position = mid - dir * 1.0
		link.end_position = mid + dir * 1.0
		link.enabled = doors[code].get_meta("open")
		add_child(link)
		_nav_links[code] = link


## A route over the navigation mesh (empty if there's no mesh here or no way there: the
## old room-graph pathing takes over then).
func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if nav == null or not nav.is_inside_tree():
		return PackedVector3Array()
	var path := NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)
	# Each bend in the route hugs the corner it goes round (at the baked 0.3 m clearance); bodies
	# are up to 0.45 m, so push every bend out from its corner by the difference.
	for i in range(1, path.size() - 1):
		var b := path[i]
		var u := path[i - 1] - b
		var w := path[i + 1] - b
		if absf(u.y) > 0.3 or absf(w.y) > 0.3:
			continue   # on the stairs: leave it on the flight
		u.y = 0.0
		w.y = 0.0
		if u.length() < 0.05 or w.length() < 0.05:
			continue
		var out := u.normalized() + w.normalized()   # into the open angle, away from the corner
		if out.length() < 0.05:
			continue   # dead straight
		var half := u.normalized().angle_to(w.normalized()) / 2.0
		path[i] = b + out.normalized() * minf(0.18 / maxf(sin(half), 0.2), 0.35)
	return path


## A shut bulkhead cuts the room graph between its two rooms (and an open one joins them again).
func _door_link(code: String, open: bool) -> void:
	var e: Array = layout.doors.get(code, [])
	if e.size() < 2 or not ids.has(e[0]) or not ids.has(e[1]):
		return
	var a: int = ids[e[0]]
	var b: int = ids[e[1]]
	if _nav_links.has(code):
		_nav_links[code].enabled = open
	if open and not astar.are_points_connected(a, b):
		astar.connect_points(a, b)
	elif not open and astar.are_points_connected(a, b):
		astar.disconnect_points(a, b)


## Can something walk from one point to the other right now (shut bulkheads in the way)?
func reachable(from: Vector3, to: Vector3) -> bool:
	var na := _node(from)
	var nb := _node(to)
	return na >= 0 and nb >= 0 and (na == nb or not astar.get_id_path(na, nb).is_empty())


static func _side(rng: RandomNumberGenerator) -> float:
	return 1.0 if rng.randf() < 0.5 else -1.0


## A failing light: steady for a while, then it struggles (catching and dropping out, the starter
## ticking), now and then dies for a few seconds; buzzing when it's lit, as a bad tube does.
## Which lamps cast shadows is main's (main._shadow_tick: the few nearest the camera, anywhere);
## here, the far ones are taken out of the renderer.
var _budget_t := 0.0


var _lamps: Array = []
const LAMP_REACH := 32.0   # past this a lamp is switched off in the renderer (it still pairs with everything round it otherwise)


func _shadow_budget(cam: Camera3D) -> void:
	if _lamps.is_empty():
		_lamps = find_children("*", "Light3D", true, false)
	var at := cam.global_position
	# Far lamps out of the renderer. Only ever shown here if the node itself is lit, so flicker and a
	# power failure (which switch the node) still have the last word; they re-show it themselves.
	for l: Light3D in _lamps:
		if is_instance_valid(l) and l.is_visible_in_tree():
			var near := l.global_position.distance_to(at) < LAMP_REACH
			l.set_meta("far", not near)   # (B.set_cull_mask keeps it so)
			RenderingServer.instance_set_visible(l.get_instance(), near)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	_budget_t -= delta
	if _budget_t <= 0.0 and cam != null:
		_budget_t = 0.25
		_shadow_budget(cam)
	for dr in _drips:   # (only the ones near enough to see)
		dr[2] -= delta
		if dr[2] <= 0.0:
			dr[2] = randf_range(0.7, 1.8)
			if cam and cam.global_position.distance_to(dr[0]) < 22.0:
				_drop(dr[1], dr[0])
	for l in flicker:
		var st: Array = l.get_meta("fl", [0, randf_range(2.0, 14.0), 0.0, true])   # [mode, time left, next switch, on]
		st[1] -= delta
		var on: bool = st[3]
		match st[0]:
			0:   # steady
				on = true
				if st[1] <= 0.0:
					st = [1, randf_range(0.4, 2.2), 0.0, on]
			1:   # struggling
				st[2] -= delta
				if st[2] <= 0.0:
					on = randf() < 0.55
					st[2] = randf_range(0.03, 0.16)
					if on and not st[3] and randf() < 0.18:   # catching: now and then it spits a few sparks
						lamp_sparks(l, false, cam)
				if st[1] <= 0.0:
					st = [2, randf_range(1.0, 5.0), 0.0, false] if randf() < 0.25 else [0, randf_range(5.0, 20.0), 0.0, true]
					on = st[3]
					if st[0] == 2:   # it dies: a shower of sparks out of the fitting
						lamp_sparks(l, true, cam)
			2:   # dead for now
				on = false
				if st[1] <= 0.0:
					st = [1, randf_range(0.3, 1.0), 0.0, false]
		var dim: float = l.get_meta("haunt", 1.0)
		var e: float = l.get_meta("base") * dim * (randf_range(0.92, 1.0) if on else 0.04)
		if on != st[3] or st[0] == 1 or absf(l.light_energy - e) > l.get_meta("base") * 0.1:
			l.light_energy = e
			_dim_bulb(l)
		st[3] = on
		l.set_meta("fl", st)
		var buzz: AudioStreamPlayer3D = l.get_meta("buzz") if l.has_meta("buzz") else null
		if buzz:
			var want := on and l.is_visible_in_tree()
			if want != buzz.playing:
				if want:
					buzz.play(randf() * 2.0)
				else:
					buzz.stop()


## Sparks out of a failing lamp's fitting: a few spat out as it catches, a shower falling to the floor
## (and a zap) as it dies. Only near enough to see.
func lamp_sparks(l: Light3D, shower: bool, cam: Camera3D) -> void:
	var at := l.global_position + Vector3(0, 0.15, 0)
	if cam == null or cam.global_position.distance_to(at) > 25.0 or not l.is_visible_in_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85 if shower else 1.0
	p.amount = 70 if shower else 16
	p.lifetime = 1.1 if shower else 0.45
	p.local_coords = false
	p.direction = Vector3(0, -1, 0) if shower else Vector3(0, 0.3, 0)
	p.spread = 70.0 if shower else 180.0
	p.initial_velocity_min = 0.6 if shower else 1.0
	p.initial_velocity_max = 2.6 if shower else 2.8
	p.gravity = Vector3(0, -9.0, 0)
	p.damping_min = 0.4
	p.damping_max = 1.2
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	p.mesh = q
	var g := Gradient.new()   # white-hot to orange to nothing (brighter than white: they glow)
	g.set_color(0, Color(4.0, 3.4, 2.2))
	g.add_point(0.35, Color(3.0, 1.4, 0.35))
	g.set_color(g.get_point_count() - 1, Color(0.9, 0.2, 0.03, 0.0))
	p.color_ramp = g
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	Sfx.play(self, "zap" if shower else "crackle", at, -6.0 if shower else -14.0, randf_range(0.9, 1.15))


## The bulb (and reflector) go dark along with their light.
static func _dim_bulb(l: Light3D) -> void:
	var k: float = l.light_energy / maxf(0.001, l.get_meta("base"))
	for g in l.get_meta("glow_mats", []):
		g[0].emission_energy_multiplier = g[1] * k
		g[0].albedo_color = g[2].darkened(0.8 * (1.0 - k))
	var cone := l.get_node_or_null("Cone") as Light3D   # (a hanging lamp's shaft of light)
	if cone != null:
		cone.light_energy = float(cone.get_meta("cone_base")) * k


## A light that flickers: its bulb and reflector get their own materials to dim along with it.
func _flicker(l: Light3D) -> void:
	_own_glow(l)
	flicker.append(l)
	var buzz := AudioStreamPlayer3D.new()   # (heard close by: a bad tube hums and ticks)
	buzz.stream = Sfx.stream("flicker_buzz")
	buzz.volume_db = -20.0
	buzz.unit_size = 2.0
	buzz.max_distance = 12.0
	buzz.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	l.add_child(buzz)
	l.set_meta("buzz", buzz)


static func _own_glow(l: Light3D) -> void:
	if l.has_meta("glow_mats"):
		return
	l.set_meta("base", l.light_energy)
	var mats := []
	for mi in l.get_meta("glow", []):
		if mi is MeshInstance3D and mi.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = mi.material_override.duplicate()
			mi.material_override = m
			mats.append([m, m.emission_energy_multiplier, m.albedo_color])
	l.set_meta("glow_mats", mats)


## Something cold is passing: dim this light (and its bulb) to k (0..1) on top of its own flicker.
func haunt(l: Light3D, k: float) -> void:
	_own_glow(l)
	l.set_meta("haunt", k)
	if not (l is OmniLight3D and flicker.has(l)):
		l.light_energy = l.get_meta("base") * k
		_dim_bulb(l)


## lane = a clear spot on a corridor axis (for monsters); otherwise a room spot, on top of any crate there.
func random_point(rng: RandomNumberGenerator, lane := false) -> Vector3:
	var rooms_down: Array = lower.keys().filter(func(c): return not low_kinds[c] in ["pit"])
	if not rooms_down.is_empty() and rng.randf() < float(rooms_down.size()) / float(rooms_down.size() + layout.cells.size()):
		var lc: Vector2i = rooms_down[rng.randi() % rooms_down.size()]
		var lo := Vector3(lc.x * CELL, -PIT, lc.y * CELL)
		var lp: Vector3
		if lane:
			var la := rng.randf_range(-4.0, 4.0)
			lp = lo + (Vector3(la, 0.6, 0) if rng.randf() < 0.5 else Vector3(0, 0.6, la))
		else:
			lp = lo + Vector3(_side(rng) * rng.randf_range(1.5, 5.0), 0.6, _side(rng) * rng.randf_range(1.5, 5.0))
		for box in crates:
			if box.grow(0.2).has_point(Vector3(lp.x, lp.y - 0.5, lp.z)) and box.size.y < 2.5:
				lp.y = box.end.y + 0.3
		return to_global(lp)
	var cells: Array = layout.cells
	var c: Vector2i = cells[rng.randi() % cells.size()]
	for i in 20:
		if not lane or c != Vector2i.ZERO or cells.size() == 1:
			break
		c = cells[rng.randi() % cells.size()]
	var o := Vector3(c.x * CELL, 0, c.y * CELL)
	var p: Vector3
	if group_of.has(c):   # a big room: anywhere on its open floor, never inside its furniture
		for tries in 16:
			p = o + Vector3(rng.randf_range(-5.0, 5.0), 0.6, rng.randf_range(-5.0, 5.0))
			if not crates.any(func(box): return box.grow(0.35).has_point(Vector3(p.x, 0.05, p.z))):
				return to_global(p)
		return to_global(o + Vector3(0, 0.6, 0))
	if lane and kinds.get(c, "") == "pit":
		p = o + Vector3(rng.randf_range(-1.4, 1.4), 0.6, rng.randf_range(-1.4, 1.4))
	elif lane or kinds.get(c, "") == "tunnel":
		var a := rng.randf_range(-4.0, 4.0)
		p = o + (Vector3(a, 0.6, 0) if rng.randf() < 0.5 else Vector3(0, 0.6, a))
	else:
		var lo := 3.0 if c == Vector2i.ZERO else 1.5   # the start room has the lift shaft in its middle
		p = o + Vector3(_side(rng) * rng.randf_range(lo, 5.0), 0.6, _side(rng) * rng.randf_range(lo, 5.0))
		if kinds.get(c, "") == "pit":
			p.y = -PIT + 0.6
		for box in crates:
			if box.grow(0.2).has_point(Vector3(p.x, p.y - 0.5, p.z)) and box.size.y < 2.5:
				p.y = box.end.y + 0.3
	return to_global(p)


func cell_at(pos: Vector3) -> Vector2i:
	var l := to_local(pos)
	return Vector2i(roundi(l.x / CELL), roundi(l.z / CELL))


## Up/down a flight of stairs as a fixed route of points (monster.gd follows it to the end, so it never
## dithers on a step): line up in front of the end you're at, onto it, the other end, step off.
## Empty if this room doesn't need you to change floors right now.
func stair_route(from: Vector3, to: Vector3) -> Array:
	var a := cell_at(from)
	if not stairs.has(a):
		return []
	var s: Dictionary = stairs[a]
	var up_from: bool = to_local(from).y > s.mid
	var up_to: bool
	var next_id := _next_node(from, to)
	if next_id < 0:
		up_to = (to_local(to).y > s.mid) if cell_at(to) == a else s.exit_high
	elif cell_of_id[next_id] == a:
		up_to = layer_of_id[next_id] == 0   # the next room is this one's other floor
	elif s.vertical:
		up_to = layer_of_id[_node(from)] == 0   # leaving by a doorway on the floor you're on
	else:
		up_to = s.exit_high
	if up_from == up_to:
		return []
	var e0: Vector3 = s.high if up_from else s.low   # the end you're at
	var e1: Vector3 = s.low if up_from else s.high
	var d := e1 - e0
	d.y = 0.0
	d = d.normalized()
	var route: Array = []
	var rel := to_local(from) - e0
	rel.y = 0.0
	var along := rel.dot(d)
	var lat := rel - d * along
	if along > -0.3 and lat.length() > 0.5:   # beside the flight: round past its end first
		route.append(e0 - d * 1.0 + lat.normalized() * maxf(lat.length(), 1.3))
	route.append(e0 - d * 0.7)   # lined up in front of it
	route.append(e0)
	route.append(e1)
	route.append(e1 + d * 0.7)   # stepped off
	var o := Vector3(a.x * CELL, 0, a.y * CELL)
	var lim := CELL / 2.0 - 0.6   # never against a wall: a body can't stand there
	return route.map(func(p): return to_global(Vector3(clampf(p.x, o.x - lim, o.x + lim), p.y, clampf(p.z, o.z - lim, o.z + lim))))


func _door_point(a: Vector2i, next_id: int) -> Vector3:
	var n: Vector2i = cell_of_id[next_id]
	if n == a:
		return Vector3(a.x * CELL, 0.5, a.y * CELL)
	return Vector3((a.x + n.x) * CELL * 0.5, 0.5, (a.y + n.y) * CELL * 0.5)


## Around the lift shaft (a 4.6 m square in the start room): the nearest corner that sees both ends.
func _round_shaft(f: Vector3, g: Vector3) -> Variant:
	var half := 2.65
	var seg_hits := func(p: Vector3, q: Vector3) -> bool:
		for i in 9:   # sample the segment (cheap, and plenty for a square)
			var x: Vector3 = p.lerp(q, (i + 0.5) / 9.0)
			if absf(x.x) < half and absf(x.z) < half:
				return true
		return false
	if not seg_hits.call(f, g):
		return null
	var best = null
	var best_d := INF
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var c := Vector3(cx * 3.2, f.y, cz * 3.2)
			if seg_hits.call(f, c) or Vector2(c.x - f.x, c.z - f.z).length() < 0.6:
				continue   # blocked, or the corner we're already standing at
			var d := f.distance_to(c) + c.distance_to(g)
			if d < best_d:
				best_d = d
				best = c
	return best


func _next_node(from: Vector3, to: Vector3) -> int:
	var na := _node(from)
	var nb := _node(to)
	if na < 0 or nb < 0 or na == nb:
		return -1
	var route := astar.get_id_path(na, nb)
	return route[1] if route.size() >= 2 else -1


## If the straight line from -> to runs through the flight (seen from above), a point off the foot of
## the flight on `from`'s side to go round by.
func _round_stair(s: Dictionary, from: Vector3, to: Vector3) -> Variant:
	var hi: Vector3 = to_global(s.high)
	var lo: Vector3 = to_global(s.low)
	var ax := Vector2(lo.x - hi.x, lo.z - hi.z)
	var L := ax.length()
	var d := ax / L
	var n := Vector2(-d.y, d.x)
	var f := Vector2(from.x - hi.x, from.z - hi.z)
	var g := Vector2(to.x - hi.x, to.z - hi.z)
	var half := 0.9   # half the flight's width, plus a body
	var fu := f.dot(d)
	var fv := f.dot(n)
	var gu := g.dot(d)
	var gv := g.dot(n)
	if absf(fv) <= half:   # in line with the flight: standing off its foot?
		if fu > L - 1.2 and gu < fu - 0.5:   # ...and heading back past it: step out to the side first
			var side := signf(gv) if absf(gv) > 0.01 else 1.0
			var q := Vector2(hi.x, hi.z) + d * (L + 0.3) + n * side * 1.2
			return Vector3(q.x, from.y, q.y)
		return null
	if signf(fv) == signf(gv) and absf(gv) > half:
		return null   # both on the same side
	# Where the line crosses the centre line of the flight, along it.
	var t := fv / (fv - gv) if absf(fv - gv) > 0.001 else 0.0
	var u := lerpf(fu, gu, t)
	if u < -0.2 or u > L - 0.5:
		return null   # passes beyond the top or the foot
	var p := Vector2(hi.x, hi.z) + d * (L + 0.4) + n * signf(fv) * 1.1
	return Vector3(p.x, from.y, p.y)


func path_next(from: Vector3, to: Vector3) -> Vector3:
	var r := _path_core(from, to)
	var a := cell_at(from)
	if kinds.get(a, "") == "pit" and to_local(from).y > -0.12:   # up on the catwalks: stay on them
		if Vector2(r.x - from.x, r.z - from.z).length() > 1.2:   # close to the waypoint: just step onto it
			var o := Vector3(a.x * CELL, 0, a.y * CELL)
			var via = _pit_route(o, to_local(from), to_local(r))
			if via != null:
				return to_global(via)
	return r


## Up in a pit room you can only walk the catwalk arms and the middle platform. From one arm to
## another you go back to the platform; on an arm you keep to its middle.
func _pit_route(o: Vector3, f: Vector3, g: Vector3) -> Variant:
	var fa := _arm(f - o)
	var ga := _arm(g - o)
	if fa != Vector3.ZERO and fa != ga:   # on the wrong arm: back to the platform
		return o + fa * 1.2 + Vector3(0, 0.5, 0)
	if fa == Vector3.ZERO and ga != Vector3.ZERO:   # on the platform: line up with the arm first
		var rel := f - o
		var lat := rel - ga * rel.dot(ga)
		lat.y = 0.0
		if lat.length() > 0.6:
			return o + ga * 1.4 + Vector3(0, 0.5, 0)
	elif fa != Vector3.ZERO and fa == ga:   # on the right arm: keep to its middle
		var rel := f - o
		var lat := rel - fa * rel.dot(fa)
		lat.y = 0.0
		if lat.length() > 0.35:
			return o + fa * (rel.dot(fa) + 0.3) + Vector3(0, 0.5, 0)
	return null


static func _arm(v: Vector3) -> Vector3:
	if maxf(absf(v.x), absf(v.z)) < 2.0:
		return Vector3.ZERO   # the platform
	return Vector3(signf(v.x), 0, 0) if absf(v.x) > absf(v.z) else Vector3(0, 0, signf(v.z))


## The room-graph node a point is in: the upper room, or the lower-floor room under it.
func _node(pos: Vector3) -> int:
	var c := cell_at(pos)
	if lower.has(c) and (to_local(pos).y < -1.0 or not ids.has(c)):
		return low_ids[c]
	return ids.get(c, -1)


func _path_core(from: Vector3, to: Vector3) -> Vector3:
	var a := cell_at(from)
	var next_id := _next_node(from, to)
	if stairs.has(a) and to_local(from).y < stairs[a].mid:   # down by a flight: walk round it, not into its side
		var aim := to
		if next_id >= 0 and cell_of_id[next_id] != a:
			var nn: Vector2i = cell_of_id[next_id]
			aim = to_global(Vector3((a.x + nn.x) * CELL * 0.5, 0.5 if layer_of_id[next_id] == 0 else -PIT + 0.5, (a.y + nn.y) * CELL * 0.5))
		if from.distance_to(aim) > 2.5:   # (by the doorway: just go through it)
			var detour = _round_stair(stairs[a], from, aim)
			if detour != null:
				return detour
	if a == Vector2i.ZERO and to_local(from).y > -1.0:   # the lift shaft stands in the middle of the start room
		var round = _round_shaft(to_local(from), to_local(to) if next_id < 0 else _door_point(a, next_id))
		if round != null:
			return to_global(round)
	if next_id < 0 and not reachable(from, to):
		return from   # sealed off behind a bulkhead: nowhere to go
	if next_id < 0 or cell_of_id[next_id] == a:
		return to   # same room (changing floors goes by stair_route)
	var n: Vector2i = cell_of_id[next_id]
	var y := 0.5 if layer_of_id[next_id] == 0 else -PIT + 0.5
	var dl := Vector3((a.x + n.x) * CELL * 0.5, y, (a.y + n.y) * CELL * 0.5)
	var doorway := to_global(dl)
	# Come at a doorway from the front: an open door leaf stands out beside it, and from the side
	# you'd walk into it (or get stuck behind it, against the wall).
	var into := Vector3(a.x - n.x, 0, a.y - n.y)
	var rel := to_local(from) - dl
	rel.y = 0.0
	var depth := rel.dot(into)
	var lat := rel - into * depth
	if depth > 0.25 and lat.length() > 0.6:
		if lat.length() > 1.0 and depth < 1.5:   # tucked in beside the doorway: straight out from the wall first
			return to_global(dl + into * 2.1 + lat)
		return to_global(dl + into * clampf(lat.length() * 1.1, 0.8, 2.0))
	if Vector2(doorway.x - from.x, doorway.z - from.z).length() < 0.8:
		return to_global(Vector3(n.x * CELL, y, n.y * CELL))
	return doorway


# --- dressing ------------------------------------------------------------------------

## Point in a room quadrant (keeps the cross-shaped walkways between doors clear).
func _quad(o: Vector3, rng: RandomNumberGenerator, margin := 0.8) -> Vector3:
	var lim := CELL / 2 - 0.6 - margin
	return o + Vector3(_side(rng) * rng.randf_range(2.4, lim), 0, _side(rng) * rng.randf_range(2.4, lim))


## A wet patch on the floor: glossy, darker in the middle, fading out to nothing at the edges.
func _sheen(at: Vector3, size: Vector2, rng: RandomNumberGenerator) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = _wet
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = at + Vector3(0, 0.008, 0)
	mi.rotation.y = rng.randf() * TAU
	Merge.live(mi)   # transparent: keep it out of the opaque merge


## Pulls a floor-decal centre in so something spreading `reach` metres round it stays inside its room
## (a stain or a fan of papers must never hang out over a pit or through a wall).
func _inside(p: Vector3, reach: float) -> Vector3:
	var c := cell_at(to_global(p))
	var o := Vector3(c.x * CELL, p.y, c.y * CELL)
	var lim := CELL / 2.0 - 0.2 - reach
	return Vector3(clampf(p.x, o.x - lim, o.x + lim), p.y, clampf(p.z, o.z - lim, o.z + lim))


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
	_on_wall.clear()
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
		"stairwell": _stairwell(o, walls, rng)
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
			A.sbox(self, Vector3(CELL, 0.25, 0.2), o + Vector3(0, H - 0.13, z), "rust", Color(0.8, 0.8, 0.8), false, 1.0)
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
		var at := _wall_spot(w, off, 0.0)
		if (w[3] and absf(off) < 4.0) or _on_wall.any(func(q): return q.distance_to(at) < 1.3):
			continue   # a doorway, a vent, or something already hangs there
		_on_wall.append(at)
		P.wall_decor(self, _wall_spot(w, off, 0.155) + Vector3(0, rng.randf_range(1.4, 1.9), 0), w[2], rng)
	if rng.randf() < 0.5:
		P.stain(self, _inside(_quad(o, rng, 0.0), 1.9), rng)
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
		A.sbox(self, Vector3(0.03, l, 0.03), o + Vector3(rng.randf_range(-4, 4), H - l / 2, rng.randf_range(-4, 4)), "metal", Color(0.1, 0.1, 0.1), false)


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
	A.sbox(self, Vector3(1.0, 0.4, 0.55), (sp + tv) / 2.0 + Vector3(0, 0.2, 0), "wood", Color(0.55, 0.42, 0.3), false, 0.6)   # coffee table
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
	P.papers(self, _inside(_quad(o, rng, 0.0), 1.3), rng)


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
	P.papers(self, _inside(_quad(o, rng, 0.0), 1.3), rng)


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
				A.sbox(r, Vector3(0.9, 1.8, 0.8), Vector3(0, 0.9, 0), "metal", Color(0.18, 0.18, 0.2), false, 1.0)
				A.sbox(r, Vector3(0.7, 0.5, 0.01), Vector3(0, 1.3, -0.405), "grille", Color(0.6, 0.6, 0.6), false, 0.3)
				A.glow(r, Vector3(0.16, 0.06, 0.01), Vector3(0.2, 0.8, -0.405), Color(0.3, 1, 0.4) if rng.randf() < 0.6 else Color(1, 0.4, 0.1), 2.5)
				_solid(up, Vector3(0.9, 1.8, 0.9))
			break
	for k in rng.randi_range(3, 6):   # cable bundles across the floor
		var a := o + Vector3(rng.randf_range(-4, 4), 0.03, -5.2)
		var b := o + Vector3(rng.randf_range(-4, 4), 0.03, 5.2)
		A.sseg(self, a, b, 0.025, 0.025, "rubber", [Color(0.2, 0.3, 0.8), Color(0.85, 0.75, 0.2), Color(1, 1, 1)][rng.randi() % 3])
	P.cable_tray(self, o + Vector3(-CELL / 2 + 0.3, H - 0.4, 3.5), o + Vector3(CELL / 2 - 0.3, H - 0.4, 3.5))
	P.cable_tray(self, o + Vector3(-CELL / 2 + 0.3, H - 0.4, -3.5), o + Vector3(CELL / 2 - 0.3, H - 0.4, -3.5))


## Catwalks over a 3 m pit, a centre platform, stairs down, junk at the bottom.
func _pit(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	A.sbox(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, -PIT - 0.1, 0), "dirt", Color(0.8, 0.75, 0.7), true, 2.0)
	var plat := 2.0   # (the walls down here are the lower floor's, built in _build_lower)
	A.sbox(self, Vector3(plat * 2, 0.1, plat * 2), o + Vector3(0, -0.05, 0), "grate", Color.WHITE, true, 0.6)
	var stair_out := Vector3.ZERO   # the catwalk the stairs leave from
	for w in walls:
		if w[3]:
			stair_out = -w[2]
			break
	var run := 3.6
	var st_side := Vector3(-stair_out.z, 0, stair_out.x)
	var st_at := plat + 0.6   # how far out along the catwalk the stairs leave it
	var stair_box := AABB()
	for w in walls:
		var inward: Vector3 = w[2]
		var out := -inward
		var side := Vector3(-out.z, 0, out.x)
		if w[3]:
			var cw := CELL / 2 - plat
			var mid := o + out * (plat + cw / 2) + Vector3(0, -0.05, 0)
			A.sbox(self, Vector3(cw, 0.1, 1.8) if absf(out.x) > 0.5 else Vector3(1.8, 0.1, cw), mid, "grate", Color.WHITE, true, 0.6)
			for s in [-1, 1]:
				var from_out := plat
				if out == stair_out and s == 1:
					from_out = st_at + 0.55   # gap in the rail where the stairs go down
				A.railing(self, o + out * from_out + side * (0.9 * s), o + out * (CELL / 2 - 0.2) + side * (0.9 * s), 1.0, "rust", true)
			# Carried on two stringers under its edges, on posts at the edges (nothing under the middle of the walk).
			for s in [-1, 1]:
				A.sbox(self, Vector3(cw, 0.14, 0.1) if absf(out.x) > 0.5 else Vector3(0.1, 0.14, cw), mid + side * (0.85 * s) + Vector3(0, -0.17, 0), "rust", Color.WHITE, false, 1.0)
				var post: Vector3 = o + out * (plat + cw * 0.55) + side * (0.85 * s)
				A.sbox(self, Vector3(0.14, PIT - 0.24, 0.14), Vector3(post.x, -PIT / 2.0 - 0.12, post.z), "rust", Color.WHITE, true, 1.0)
			A.sbox(self, Vector3(0.1, 0.12, 1.8) if absf(out.x) > 0.5 else Vector3(1.8, 0.12, 0.1), o + out * (plat + cw * 0.55) + Vector3(0, -0.3, 0), "rust", Color.WHITE, false, 1.0)   # cross beam
			A.railing(self, o + out * plat - side * plat, o + out * plat - side * 0.9, 1.0, "rust", true)
			A.railing(self, o + out * plat + side * 0.9, o + out * plat + side * plat, 1.0, "rust", true)
		else:
			A.railing(self, o + out * plat - side * plat, o + out * plat + side * plat, 1.0, "rust", true)
	# Stairs off the side of the catwalk, running parallel to the wall, with room to step off at the bottom.
	var st_top := o + stair_out * st_at + st_side * 0.9
	P.stairs(self, st_top, st_side, PIT, run, 1.0)
	var low := st_top + st_side * (run + 0.6) + Vector3(0, -PIT + 0.5, 0)
	stairs[cell_at(to_global(o))] = {"high": st_top - st_side * 0.45 + Vector3(0, 0.5, 0), "low": low, "mid": -1.0, "exit_high": true, "vertical": true}
	var c0 := st_top - stair_out * 0.6 + Vector3(0, -PIT, 0)
	var c1 := st_top + stair_out * 0.6 + st_side * (run + 1.2)
	stair_box = AABB(Vector3(minf(c0.x, c1.x), -PIT - 1.0, minf(c0.z, c1.z)), Vector3(absf(c1.x - c0.x), PIT + 2.0, absf(c1.z - c0.z)))
	crates.append(stair_box)
	for sx in [-1, 1]:   # platform: corner posts stopping under the deck, edge beams carrying it
		for sz in [-1, 1]:
			A.sbox(self, Vector3(0.2, PIT - 0.24, 0.2), o + Vector3(sx * (plat - 0.12), -PIT / 2 - 0.12, sz * (plat - 0.12)), "rust", Color.WHITE, true, 1.0)
		A.sbox(self, Vector3(0.14, 0.14, plat * 2 - 0.1), o + Vector3(sx * (plat - 0.12), -0.17, 0), "rust", Color.WHITE, false, 1.0)
		A.sbox(self, Vector3(plat * 2 - 0.1, 0.14, 0.14), o + Vector3(0, -0.17, sx * (plat - 0.12)), "rust", Color.WHITE, false, 1.0)
	# A work light down in the pit, so the bottom isn't just a black hole.
	A.wall_lamp(self, o + st_side * (CELL / 2 - 0.35) - stair_out * 2.5 + Vector3(0, -PIT + 2.2, 0), -st_side, theme.light, 0.9, false)
	for i in rng.randi_range(3, 6):
		var p := _quad(o, rng) + Vector3(0, -PIT, 0)
		if stair_box.grow(1.0).has_point(p + Vector3(0, 0.1, 0)):
			continue
		_solid(p, Vector3(1.2, 1.0, 1.2))
		match rng.randi() % 3:
			0: A.barrel(self, p, rng)
			1: A.crate(self, p, rng.randf_range(0.6, 1.1), rng)
			2: A.rubble(self, p, rng)
	_sheen(_inside(_quad(o, rng, 0.0), 2.2) + Vector3(0, -PIT, 0), Vector2(3.6, 2.8), rng)


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
		A.sbox(self, Vector3(CELL, 2.2, 0.2) if along_x else Vector3(0.2, 2.2, CELL), o + side * (s * r) + Vector3(0, 1.1, 0), "riveted", Color(0.6, 0.55, 0.5), true, 1.5)
	A.sbox(self, Vector3(CELL, 0.05, 1.6) if along_x else Vector3(1.6, 0.05, CELL), o + Vector3(0, 0.025, 0), "grate", Color.WHITE, false, 0.6)   # walk-over: the floor under it is solid
	A.sbox(self, Vector3(CELL, 0.01, 1.5) if along_x else Vector3(1.5, 0.01, CELL), o + Vector3(0, 0.006, 0), "metal", Color(0.16, 0.15, 0.14), false, 1.0)   # dark channel under it, so it still reads at range
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
			A.sbox(self, Vector3(0.18, 2.17, 0.18), o + axis * x + side * (s * (r - 0.1)) + Vector3(0, 1.085, 0), "rust", Color(0.8, 0.75, 0.7), false, 1.0)
		x += 1.5
	P.cable_tray(self, o - axis * (CELL / 2 - 0.2) + side * 1.7 + Vector3(0, 2.0, 0), o + axis * (CELL / 2 - 0.2) + side * 1.7 + Vector3(0, 2.0, 0))
	for k in [-3.0, 3.0]:
		A.glow(self, Vector3(0.3, 0.1, 0.3), o + axis * k + Vector3(0, 3.75, 0), Color(1, 0.6, 0.3), 5.0)


func _tendrils(top: Vector3, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(2, 5):
		var l := rng.randf_range(0.8, 2.5)
		A.scyl(self, 0.06, l, top + Vector3(rng.randf_range(-0.5, 0.5), -l / 2, rng.randf_range(-0.5, 0.5)), "flesh", Color(0.8, 0.6, 0.6), false, "y", 0.02)


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
			"DAM":   # cold tubes, one bare bulk-head lamp sweating on a wall
				for z in [-2.5, 2.5]:
					lights.append(A.fluorescent(self, o + Vector3(0, H - 0.05, z), c, 1.1))
				if rng.randf() < 0.5:
					var w: Array = walls[rng.randi() % 4]
					lights.append(A.wall_lamp(self, _wall_spot(w, 2.4, 0.2) + Vector3(0, 2.4, 0), w[2], Color(1, 0.8, 0.55), 0.8, false))
			"FLESH":
				A.ssphere(self, 0.2, o + Vector3(rng.randf_range(-3, 3), H - 0.15, rng.randf_range(-3, 3)), "flesh", c, 3.0)
				lights.append(B.omni(self, o + Vector3(0, H - 0.6, 0), c, 1.0, 9.0, true))
	if not lights.is_empty() and kind != "tunnel":
		lights[0].shadow_enabled = true
		for l in lights:   # (any of them may cast shadows when it's among the nearest)
			l.set_meta("budget_shadow", true)
	for l in lights:
		if rng.randf() < 0.3:
			_flicker(l)
	var hv := hash(Vector2i(int(o.x), int(o.z)))   # (not the site's dice: the rest of the layout stays as it was)
	if not kind in ["tunnel", "pit", "server", "vault", "stairwell", "atrium"] and _grates < 5 and hv % 100 < 30 and theme_id != "FLESH":
		_grate(o + Vector3(float(hv % 7) - 3.0, 0, float((hv / 7) % 7) - 3.0) * 0.8, c)


var _grates := 0
var _drips: Array = []   # [floor point, ceiling point, seconds to the next drop]


## Water on the floor here and there, now and then with a leak above it dripping in. (Picked by the
## room's place, not the site's dice: the rest of the layout stays as it was.)
func _puddles(c: Vector2i, o: Vector3) -> void:
	if theme_id == "FLESH" or kinds.get(c, "") in ["pit", "tunnel", "vault", "stairwell"]:
		return
	var hv: int = absi(hash(Vector2i(c.x * 31 + 7, c.y * 17 + 3)))
	if hv % 100 >= 38:
		return
	for i in 1 + hv % 2:
		var h2: int = absi(hash(Vector3i(c.x, c.y, i)))
		var at := o + Vector3(float(h2 % 9) - 4.0, 0.0, float((h2 / 9) % 9) - 4.0) * 0.85
		A.puddle(self, to_global(at), 1.2 + float(h2 % 5) * 0.35, float(h2 % 628) / 100.0)
		if (h2 / 81) % 3 == 0:   # a leak over it
			A.sbox(self, Vector3(0.5, 0.02, 0.4), at + Vector3(0, H - 0.02, 0), "rust", Color(0.35, 0.3, 0.26), false)
			_drips.append([to_global(at), to_global(at + Vector3(0, H - 0.05, 0)), randf() * 2.0])
			var snd := AudioStreamPlayer3D.new()
			snd.stream = Sfx.stream("drip_loop")
			snd.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
			snd.volume_db = -20.0
			snd.unit_size = 2.5
			snd.max_distance = 12.0
			snd.autoplay = true
			add_child(snd)
			snd.position = at + Vector3(0, 0.3, 0)


## A drop: it falls from the leak and rings out on the puddle.
func _drop(from: Vector3, to: Vector3) -> void:
	var d := A.box(self, Vector3(0.012, 0.045, 0.012), Vector3.ZERO, "cream", Color(0.7, 0.75, 0.8), false, 0.6)
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.set_meta("transient", true)
	d.global_position = from
	var tw := d.create_tween()
	tw.tween_property(d, "global_position", to, sqrt(2.0 * (from.y - to.y) / 9.8)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		if is_instance_valid(d) and d.is_inside_tree() and not is_queued_for_deletion():
			A.ripple(self, to, 0.7, 1.0)
		d.queue_free())


## A ceiling vent with a lamp in the duct above it: light falls through the slats in stripes, and
## shows as shafts in the haze.
func _grate(o: Vector3, c: Color) -> void:
	_grates += 1
	var y := H - 0.04
	for k in 4:   # the frame (a ring: a plate would shut its own lamp in)
		var along := Vector3(1, 0, 0) if k < 2 else Vector3(0, 0, 1)
		var across := Vector3(0, 0, 1) if k < 2 else Vector3(1, 0, 0)
		A.sbox(self, along * 1.3 + across * 0.1 + Vector3(0, 0.06, 0), o + Vector3(0, y, 0) + across * (0.6 if k % 2 == 0 else -0.6), "metal", Color(0.3, 0.3, 0.3), false)
	var lit: Color = c.lerp(Color(0.85, 0.9, 1.0), 0.4)
	var inner := A.glow(self, Vector3(1.1, 0.02, 1.1), o + Vector3(0, y + 0.03, 0), lit, 5.0)   # the light in the duct, seen between the slats
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 7:   # the slats
		A.sbox(self, Vector3(1.1, 0.05, 0.06), o + Vector3(0, y - 0.05, -0.48 + i * 0.16), "metal", Color(0.35, 0.35, 0.33), false)
	var l := SpotLight3D.new()
	l.light_color = lit
	l.light_energy = 30.0
	l.spot_range = H * 2.4   # (light fades to nothing at its range: well past the floor)
	l.spot_angle = 30.0
	l.spot_attenuation = 0.5
	l.light_volumetric_fog_energy = 2.5
	add_child(l)
	l.position = o + Vector3(0, y - 0.08, 0)
	l.rotation.x = -PI / 2.0



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
				if box.grow(0.25).has_point(Vector3(foot.x, foot.y + 0.05, foot.z)):
					blocked = true
					break
			if not blocked:
				if rng.randf() < 0.45:
					P.wall_fixture(self, _wall_spot(w, off, 0.175), w[2], rng, wet)
					_on_wall.append(_wall_spot(w, off, 0.0))   # from the wall face (0.15 up top, 0.17 at the band)
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
			if box.grow(0.35).has_point(Vector3(q.x, q.y + 0.05, q.z)):
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
						A.sbox(self, Vector3(0.5, 0.4, 0.45), q + Vector3(((k % 2) - 0.5) * 0.55, 0.36 + (k / 2) * 0.41, rng.randf_range(-0.2, 0.2)), "cardboard", Color.WHITE.darkened(rng.randf() * 0.3), false, 0.5, Vector3(0, rng.randf_range(-0.15, 0.15), 0))
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
				_sheen(_inside(q, 1.0), Vector2(rng.randf_range(1.0, 1.8), rng.randf_range(0.8, 1.4)), rng)
			5:   # cardboard box pile
				for k in rng.randi_range(2, 4):
					var sz := Vector3(rng.randf_range(0.35, 0.55), rng.randf_range(0.25, 0.4), rng.randf_range(0.3, 0.5))
					A.sbox(self, sz, q + Vector3(rng.randf_range(-0.3, 0.3), sz.y / 2 + (0.3 if k == 3 else 0.0), rng.randf_range(-0.3, 0.3)), "cardboard", Color.WHITE.darkened(rng.randf() * 0.3), false, 0.5, Vector3(0, rng.randf() * TAU, 0))
				_solid(q, Vector3(1.0, 0.7, 1.0))
			6:   # tyre stack / cable drum
				if rng.randf() < 0.5:
					for k in rng.randi_range(1, 3):
						A.sring(self, 0.35, 0.18, q + Vector3(rng.randf_range(-0.05, 0.05), 0.09 + k * 0.17, 0), "rubber")
				else:
					var d := Node3D.new()
					add_child(d)
					d.position = q
					d.rotation.y = rng.randf() * TAU
					for sx in [-1, 1]:
						A.scyl(d, 0.45, 0.06, Vector3(sx * 0.3, 0.45, 0), "wood", Color(0.75, 0.6, 0.45), false, "x")
					A.scyl(d, 0.25, 0.6, Vector3(0, 0.45, 0), "rubber", Color.WHITE, false, "x")
					_solid(q, Vector3(0.9, 0.9, 0.9))
			_:
				P.papers(self, _inside(q, 1.3), rng)
				P.stain(self, _inside(q, 1.9), rng)


## Make sure no quadrant is bare, and line some walls with furniture.
func _fill(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var q := o + Vector3(sx * 3.6, 0, sz * 3.6)
			var taken := false
			for box in crates:
				if box.grow(0.8).has_point(Vector3(q.x, q.y + 0.05, q.z)):
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
						A.sbox(self, Vector3(0.45, 0.35, 0.35), q + Vector3(rng.randf_range(-0.35, 0.35), 0.33 + i * 0.36, rng.randf_range(-0.3, 0.3)), "cream", Color(0.75, 0.6, 0.45), false, 0.5, Vector3(0, rng.randf(), 0))
					_solid(q, Vector3(1.3, 1.2, 1.3))
				3:
					P.table(self, q, rng.randf() * TAU, 1.4, 0.8, "metal" if theme_id == "LAB" else "wood")
					OfficeChair.make(self, q + Vector3(0.9, 0, 0.2), rng.randf() * TAU, [Color(0.16, 0.16, 0.17), Color(0.25, 0.3, 0.42), Color(0.4, 0.2, 0.16)][rng.randi() % 3])   # (one you can sit in and roll about)
					if rng.randf() < 0.5:
						A.crt(self, q + Vector3(0, 0.79, 0), rng.randf() < 0.5)
					_solid(q, Vector3(1.6, 0.8, 1.6))
				4:
					P.filing_cabinet(self, q, rng.randf() * TAU)
					P.papers(self, _inside(q, 1.3), rng)
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
	A.sbox(cam, Vector3(0.22, 0.18, 0.4), Vector3(0, 0, 0.05), "cream", Color(0.8, 0.8, 0.78), false, 0.3)
	A.scyl(cam, 0.07, 0.08, Vector3(0, 0, -0.18), "metal", Color(0.05, 0.05, 0.05), false, "z")
	A.sbox(cam, Vector3(0.05, 0.05, 0.35), Vector3(0, 0.12, 0.3), "metal", Color(0.3, 0.3, 0.3), false)
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
## The records room: the next dead end out after the vault, behind a keypad door. Its code isn't on
## the map; it's chalked on a wall somewhere else on the site (_secure_clue). Someone finds it and
## reads it out to whoever's on the train terminal (OPEN_BULKHEAD ####).
func _pick_secure(rng: RandomNumberGenerator) -> void:
	if layout.cells.size() < 9:
		return
	var best_d := -1
	for c: Vector2i in layout.cells:
		if c == Vector2i.ZERO or c == vault_cell or layout.links[c].size() != 1 or group_of.has(c) or layout.links[c][0] == vault_cell:
			continue
		var d := absi(c.x) + absi(c.y)
		if d > best_d:
			best_d = d
			secure_cell = c
	if best_d < 2:
		secure_cell = Vector2i(999, 999)
		return
	var e := edge(secure_cell, layout.links[secure_cell][0])
	for code in layout.doors.keys():
		if layout.doors[code] == e:
			layout.doors.erase(code)
	secure_code = "%04d" % (1000 + rng.randi() % 9000)
	layout.doors[secure_code] = e


## The twin-key room: another dead end, behind a blast door with two levers on opposite walls of the
## room in front of it. Two people pull them together (or one wedges a lever down and runs).
func _pick_twin(rng: RandomNumberGenerator) -> void:
	if layout.cells.size() < 12:
		return
	var options: Array = []
	for c: Vector2i in layout.cells:
		if c == Vector2i.ZERO or c == vault_cell or c == secure_cell or layout.links[c].size() != 1 or group_of.has(c):
			continue
		var n: Vector2i = layout.links[c][0]
		if n == Vector2i.ZERO or n == vault_cell or n == secure_cell or group_of.has(n) or absi(c.x) + absi(c.y) < 2:
			continue
		options.append(c)
	if options.is_empty():
		return
	twin_cell = options[rng.randi() % options.size()]
	var e := edge(twin_cell, layout.links[twin_cell][0])
	for code in layout.doors.keys():
		if layout.doors[code] == e:
			layout.doors.erase(code)
	twin_code = "T%d%d" % [rng.randi() % 10, rng.randi() % 10]
	layout.doors[twin_code] = e


func _twin_denied() -> void:
	if main:
		main.hud.msg("TWIN-KEY BLAST DOOR: pull both levers in the room at the same time.")
		Sfx.play(self, "error", doors[twin_code].global_position, -4.0, 0.9)


## The pair of levers: on two different walls of the room in front of the door (opposite ones if it
## can), away from its doorways.
func _place_twin_levers(rng: RandomNumberGenerator) -> void:
	if twin_code == "":
		return
	var ante: Vector2i = layout.links[twin_cell][0]
	var walls: Array = cell_walls.get(ante, []).filter(func(w): return not w[3] and not w[4])
	if walls.size() < 2:   # (no two clear walls: one lever beside each side of the door instead)
		walls = cell_walls.get(ante, []).filter(func(w): return not w[4])
	if walls.size() < 2:
		return
	var a: Array = walls[0]
	var b: Array = walls[1]
	for w in walls:   # the pair furthest apart
		for v in walls:
			if (w[0] as Vector3).distance_to(v[0]) > (a[0] as Vector3).distance_to(b[0]):
				a = w
				b = v
	var made: Array = []
	for w in [a, b]:
		var n: Vector3 = w[2]
		var along := Vector3(n.z, 0, -n.x)
		var tries: Array = [4.2, -4.2] if w[3] else [0.0, 1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0, 1.5, -1.5, 2.5, -2.5, 3.5, -3.5]
		var off: float = tries[0]
		for t: float in tries:   # a bare stretch of wall: not over a shelf, a sign, a cabinet, a pipe
			if _clear_spot(w[0] + along * t, n, 0.7, 0.6, 1.9, 0.75):
				off = t
				break
		_reserve(w[0] + along * off, n, 0.7, 0.6, 1.9, 0.75)
		var lv := TwinLever.new()
		add_child(lv)
		lv.position = w[0] + n * 0.16 + along * off + Vector3(0, 1.25, 0)
		lv.rotation.y = atan2(n.x, n.z)
		lv.fac = self
		lv.code = twin_code
		lv.set_meta("live", true)
		lv.build()
		made.append(lv)
	made[0].other = made[1]
	made[1].other = made[0]
	twin_levers = made


## E on the secured door: a keypad, nothing to override.
func _secure_denied() -> void:
	if main:
		main.hud.msg("SECURED: keypad locked. Enter its four-digit code at the train terminal: OPEN_BULKHEAD ####.")
		Sfx.play(self, "error", doors[secure_code].global_position, -4.0, 1.2)


## The code, chalked on a wall in a room well away from the door: RECORDS and the four digits, an
## arrow, a ring round the number.
func _secure_clue(rng: RandomNumberGenerator) -> void:
	if secure_code == "":
		return
	var options: Array = []
	for c: Vector2i in cell_walls:
		if c == Vector2i.ZERO or c == secure_cell or c == vault_cell or group_of.has(c) or kinds[c] in ["pit", "stairwell", "tunnel", "atrium"]:
			continue
		if absi(c.x - secure_cell.x) + absi(c.y - secure_cell.y) < 3:
			continue
		for w in cell_walls[c]:
			if not w[3] and not w[4]:
				options.append([c, w])
	if options.is_empty():
		return
	_shuffle_with(options, rng)
	var w: Array = options[0]
	var off := rng.randf_range(-2.5, 2.5)
	var found := false
	for o in options:   # a bare stretch of wall, so it can be read: nothing hung over it or stood in front
		for t: float in [0.0, 1.5, -1.5, 3.0, -3.0, 0.8, -0.8, 2.2, -2.2, 3.8, -3.8]:
			if _clear_spot(o[1][0] + Vector3(o[1][2].z, 0, -o[1][2].x) * t, o[1][2], 1.4, 0.9, 2.5, 0.9):
				w = o
				off = t
				found = true
				break
		if found:
			break
	w = w[1]
	var n: Vector3 = w[2]
	_reserve(w[0] + Vector3(n.z, 0, -n.x) * off, n, 1.4, 0.0, 2.5, 0.9)
	var at: Vector3 = w[0] + n * 0.165 + Vector3(0, 1.75, 0) + Vector3(n.z, 0, -n.x) * off
	var face := atan2(n.x, n.z)
	var chalk := Color(0.92, 0.92, 0.88, 0.9)
	var t1 := B.label(self, "RECORDS", at + Vector3(0, 0.52, 0), 52, chalk, "chalk", 0.007)
	t1.rotation.y = face
	var t2 := B.label(self, secure_code, at, 80, chalk, "chalk", 0.008)
	t2.rotation.y = face
	var ring := Node3D.new()   # a ring round the number, scrawled
	add_child(ring)
	ring.position = at + n * 0.004
	ring.rotation.y = face
	for k in 14:
		var a := TAU * k / 14.0
		var b := TAU * (k + 1) / 14.0
		A.sseg(ring, Vector3(cos(a) * 0.55, sin(a) * 0.32, 0), Vector3(cos(b) * 0.55, sin(b) * 0.32, 0), 0.012, 0.012, "cream", Color(0.9, 0.9, 0.86), 0.2)
	var t3 := B.label(self, "DON'T FORGET", at + Vector3(0, -0.44, 0), 30, chalk, "chalk", 0.006)
	t3.rotation.y = face
	clue_at = to_global(at)
	clue_n = global_transform.basis * n


var clue_at := Vector3.INF
var clue_n := Vector3.FORWARD   # (the way the wall it's on faces)
var _on_walls: Array = []   # AABBs (in our space) of the small things already in the rooms, for _clear_spot
var _walls_seen := false


## Is this stretch of wall bare: `w` wide from `y0` to `y1` high and `depth` out into the room from
## the wall at `at` (facing `n`), with nothing in it: shelves, signs, clocks, cabinets, pipes, crates
## (anything smaller than a whole wall or floor).
func _clear_spot(at: Vector3, n: Vector3, w: float, y0: float, y1: float, depth: float) -> bool:
	if not _walls_seen:
		_see_walls()
	var spot := _spot_box(at, n, w, y0, y1, depth)
	return not _on_walls.any(func(b): return spot.intersects(b))


## What's on the walls, gathered once the rooms are dressed (before merge.gd bakes them into a mesh
## or two a room and the small things can't be told apart any more).
func _see_walls() -> void:
	_walls_seen = true
	var inv := global_transform.affine_inverse()
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if low_root != null and low_root.is_ancestor_of(mi):
			continue
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if int(b.size.x > 3.0) + int(b.size.y > 3.0) + int(b.size.z > 3.0) < 2:
			_on_walls.append(b)
	if Merge.sinks > 0:   # (and the meshes that aren't nodes: art.gd's s-primitives, waiting for the merge)
		for p: Array in ClassDB.class_call_static(&"MeshMerge", &"pieces_under", self):
			var owner_: Node = p[1]
			if low_root != null and (owner_ == low_root or low_root.is_ancestor_of(owner_)):
				continue
			var gt: Transform3D = p[2]
			var pb: AABB = p[3]
			var b: AABB = (inv * gt) * pb
			if int(b.size.x > 3.0) + int(b.size.y > 3.0) + int(b.size.z > 3.0) < 2:
				_on_walls.append(b)


## Keep a stretch of wall for something (the next _clear_spot avoids it, and so does anything that
## keeps off `crates`, the breaker among them).
func _reserve(at: Vector3, n: Vector3, w: float, y0: float, y1: float, depth: float) -> void:
	_on_walls.append(_spot_box(at, n, w, y0, y1, depth))
	crates.append(_spot_box(at, n, w, 0.0, y1, depth))


func _spot_box(at: Vector3, n: Vector3, w: float, y0: float, y1: float, depth: float) -> AABB:
	var along := Vector3(absf(n.z), 0, absf(n.x))
	var lo := at + Vector3(0, y0, 0) + n * 0.17 - along * w / 2.0   # (0.17: the wall's own face)
	var hi := at + Vector3(0, y1, 0) + n * (0.17 + depth) + along * w / 2.0
	return AABB(Vector3(minf(lo.x, hi.x), lo.y, minf(lo.z, hi.z)), Vector3(absf(hi.x - lo.x), hi.y - lo.y, absf(hi.z - lo.z)))


func _shuffle_with(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _pick_vault(rng: RandomNumberGenerator) -> void:
	if layout.cells.size() < 6:
		return
	var best_d := -1
	for c: Vector2i in layout.cells:
		if c == Vector2i.ZERO or layout.links[c].size() != 1 or group_of.has(c):
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


## Vault: a Bureau strongroom. Brushed-steel plate walls with a trim rail, the walls lined with
## deposit boxes (a few big ones you can pry open), a diamond-plate floor with a yellow line round
## the door, a long steel table under a hanging lamp with the best of it laid out, a wire-mesh
## cage at the back round the heavy prize, cold strip lights and two red emergency lamps.
func _vault(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var steel := Color(0.74, 0.76, 0.78)
	var dark := Color(0.3, 0.31, 0.33)
	A.sbox(self, Vector3(CELL - 0.6, 0.02, CELL - 0.6), o + Vector3(0, 0.012, 0), "metal", Color(0.42, 0.43, 0.45), false, 0.5)   # steel floor plate
	var door_wall: Array = []
	for w in walls:
		if w[3]:
			door_wall = w
			continue
		var face: Vector3 = w[0] + w[2] * 0.2
		A.sbox(self, Vector3(CELL - 0.4, H - 0.2, 0.05) if w[1] else Vector3(0.05, H - 0.2, CELL - 0.4), face + Vector3(0, H / 2, 0), "metal", steel, false, 1.2)
		var wall_root := Node3D.new()
		add_child(wall_root)
		wall_root.position = face + w[2] * 0.03
		wall_root.rotation.y = _facing(w) + PI
		A.sbox(wall_root, Vector3(CELL - 0.5, 0.08, 0.06), Vector3(0, 0.45, 0.02), "metal", dark, false, 0.5)   # kick rail
		A.sbox(wall_root, Vector3(CELL - 0.5, 0.06, 0.05), Vector3(0, 3.25, 0.02), "metal", dark, false, 0.5)   # top rail
		# Deposit boxes: a bank of steel doors in recessed frames, a brass keyhole and a pull each.
		A.sbox(wall_root, Vector3(4.9, 2.45, 0.05), Vector3(0, 1.88, 0.02), "metal", dark, false, 0.5)
		for col in 8:
			for row in 4:
				var p := Vector3(-2.1 + col * 0.6, 1.1 + row * 0.52, 0.06)
				if row == 0 and col in [1, 5]:
					continue   # (the big ones go here)
				A.sbox(wall_root, Vector3(0.54, 0.46, 0.03), p, "metal", steel.lightened(0.12), false, 0.3)
				A.scyl(wall_root, 0.016, 0.012, p + Vector3(0.18, 0.04, 0.02), "brass", Color(0.75, 0.6, 0.3), false, "z")
				A.sbox(wall_root, Vector3(0.12, 0.02, 0.02), p + Vector3(0, -0.15, 0.025), "metal", dark, false)
				if rng.randf() < 0.12:   # a few hang open, rifled
					A.sbox(wall_root, Vector3(0.48, 0.4, 0.02), p + Vector3(-0.2, 0, 0.24), "metal", steel, false, 0.3, Vector3(0, 1.25, 0))
		for col in [1, 5]:   # two big boxes on the bottom row: pry them open
			_deposit_box(wall_root, Vector3(-2.1 + col * 0.6 + 0.3, 1.1, 0.06), rng)
	# The long table with a lamp over it: the best of it laid out.
	var table := o + Vector3(0, 0, 0.9)
	A.sbox(self, Vector3(2.6, 0.06, 0.9), table + Vector3(0, 0.9, 0), "metal", steel.lightened(0.15), true, 0.6)
	for sx in [-1.2, 1.2]:
		for sz in [-0.38, 0.38]:
			A.sbox(self, Vector3(0.06, 0.9, 0.06), table + Vector3(sx, 0.45, sz), "metal", dark, false)
	A.sbox(self, Vector3(2.5, 0.04, 0.8), table + Vector3(0, 0.25, 0), "metal", dark, true, 0.5)   # lower shelf
	_solid(table, Vector3(2.7, 0.95, 1.0))
	for k in 3:
		vault_spots.append(table + Vector3(-0.8 + k * 0.8, 1.0, rng.randf_range(-0.2, 0.2)))
	A.sseg(self, table + Vector3(0, H, 0), table + Vector3(0, 2.3, 0), 0.01, 0.01, "metal", dark)
	A.scyl(self, 0.24, 0.14, table + Vector3(0, 2.25, 0), "metal", Color(0.2, 0.32, 0.25), false, "y", 0.08)   # green enamel shade
	B.omni(self, table + Vector3(0, 2.05, 0), Color(1.0, 0.88, 0.7), 1.4, 5.0, true)
	A.ssphere(self, 0.06, table + Vector3(0, 2.17, 0), "cream", Color(1, 0.9, 0.7), 5.0)
	# The cage at the back: mesh panels on posts round the heavy prize, its door ajar.
	var cage := o + Vector3(0, 0, -3.4)
	for x in [-2.6, -1.3, 1.3, 2.6]:
		A.sbox(self, Vector3(0.06, 2.6, 0.06), cage + Vector3(x, 1.3, 1.2), "metal", dark, false)
	for x in [-1.95, 1.95]:
		A.sbox(self, Vector3(1.24, 2.5, 0.04), cage + Vector3(x, 1.3, 1.2), "grate", Color(0.6, 0.62, 0.64), true, 0.5)
	A.sbox(self, Vector3(5.3, 0.06, 0.06), cage + Vector3(0, 2.6, 1.2), "metal", dark, false)
	var gate := A.box(self, Vector3(1.24, 2.4, 0.02), cage + Vector3(-1.3 + 0.62 * cos(0.9), 1.25, 1.2 + 0.62 * sin(0.9)), "grate", Color(0.6, 0.62, 0.64), false, 0.5, Vector3(0, -0.9, 0))
	vault_spots.insert(0, cage + Vector3(rng.randf_range(-0.8, 0.8), 0.5, 0.2))   # (the heavy prize: first)
	A.shelf_unit(self, cage + Vector3(-1.9, 0, -0.3), 0.0, rng, 1.2, 2.2, 0.5)
	A.shelf_unit(self, cage + Vector3(1.9, 0, -0.3), 0.0, rng, 1.2, 2.2, 0.5)
	vault_spots.append(cage + Vector3(1.9, 1.0, -0.3))
	# Floor markings: a yellow line in from the door, and a stencil.
	if not door_wall.is_empty():
		var dw: Vector3 = door_wall[0]
		var inward: Vector3 = (o - dw).normalized()
		var across := Vector3(inward.z, 0, -inward.x)
		for s in [-1.0, 1.0]:
			A.sbox(self, Vector3(0.08, 0.005, 1.6) if absf(inward.z) > 0.5 else Vector3(1.6, 0.005, 0.08), dw + inward * 1.1 + across * s * 1.1 + Vector3(0, 0.025, 0), "cream", Color(0.9, 0.75, 0.15), false)
		A.sbox(self, Vector3(2.28, 0.005, 0.08) if absf(inward.z) > 0.5 else Vector3(0.08, 0.005, 2.28), dw + inward * 1.9 + Vector3(0, 0.025, 0), "cream", Color(0.9, 0.75, 0.15), false)
		var st := B.label(self, "STRONGROOM 7", dw + inward * 1.2 + Vector3(0, 0.03, 0), 60, Color(0.85, 0.7, 0.2), "stencil", 0.008)
		st.basis = Basis.looking_at(-Vector3.UP, inward)
	# Light: cold strips overhead and two red emergency lamps.
	for x in [-2.5, 2.5]:
		A.sbox(self, Vector3(0.14, 0.06, 2.4), o + Vector3(x, H - 0.05, 0), "metal", dark, false)
		A.glow(self, Vector3(0.1, 0.03, 2.3), o + Vector3(x, H - 0.09, 0), Color(0.85, 0.92, 1.0), 4.0)
		B.omni(self, o + Vector3(x, H - 0.5, 0), Color(0.82, 0.9, 1.0), 2.0, 9.0)
	B.omni(self, o + Vector3(0, H - 0.6, -2.0), Color(0.82, 0.9, 1.0), 1.2, 8.0)   # (the cage end)
	for k in 2:
		var lp := o + Vector3(_side(rng) * 4.6, H - 0.4, _side(rng) * 4.6)
		B.omni(self, lp, Color(1, 0.22, 0.12), 0.6, 6.0)
		A.ssphere(self, 0.08, lp, "cream", Color(1, 0.3, 0.15), 4.0)


## A big deposit box on the vault wall (local to `wall_root`): pry it open (hold E) for what's in it.
func _deposit_box(wall_root: Node3D, p: Vector3, rng: RandomNumberGenerator) -> void:
	var box := Node3D.new()
	wall_root.add_child(box)
	box.position = p
	A.sbox(box, Vector3(1.14, 0.46, 0.06), Vector3(0, 0, -0.01), "metal", Color(0.08, 0.08, 0.09), false)   # (the dark inside)
	var hinge := Node3D.new()   # the door, hinged on its left edge
	box.add_child(hinge)
	hinge.position = Vector3(-0.56, 0, 0.03)
	hinge.set_meta("live", true)
	A.sbox(hinge, Vector3(1.12, 0.44, 0.035), Vector3(0.56, 0, 0), "riveted", Color(0.6, 0.62, 0.64), false, 0.4)
	A.scyl(hinge, 0.04, 0.02, Vector3(0.9, 0.06, 0.025), "brass", Color(0.8, 0.62, 0.3), false, "z")
	A.scyl(hinge, 0.04, 0.02, Vector3(1.0, 0.06, 0.025), "brass", Color(0.8, 0.62, 0.3), false, "z")
	A.sbox(hinge, Vector3(0.24, 0.035, 0.03), Vector3(0.56, -0.14, 0.03), "metal", Color(0.3, 0.3, 0.32), false)
	box.set_meta("lid", hinge)
	box.set_meta("deposit", true)
	supplies.append(box)
	var it := B.interactable(box, Vector3(1.1, 0.42, 0.2), Vector3(0, 0, 0.1), Color(0, 0, 0, 0), "Pry open the deposit box", Callable(self, "_open_deposit").bind(box), 1.6)
	it.set_meta("crate", true)


func _open_deposit(box: Node3D) -> void:
	if box.get_meta("opened", false):
		return
	box.set_meta("opened", true)
	var hinge: Node3D = box.get_meta("lid")
	create_tween().tween_property(hinge, "rotation:y", -1.9, 0.5).set_trans(Tween.TRANS_BACK)
	Sfx.play(self, "clank", box.global_position, 2.0, 0.8)
	Sfx.play(self, "creak", box.global_position, -4.0, 1.3)
	if main:
		main.noise(box.global_position, 9.0)
	for c in box.get_children():
		if c.has_meta("crate"):
			c.queue_free()
	if main == null or not main.net.authority():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out: Vector3 = box.global_transform.basis.z
	for k in (1 if rng.randf() < 0.6 else 2):
		var id: String = ["GOLD_BAR", "GOLD_BAR", "CASH_BOX", "BEARER_BONDS"][rng.randi() % 4]
		main.spawn_item(id, box.global_position + out * (0.45 + k * 0.15) + Vector3(randf_range(-0.2, 0.2), 0.2, 0), -1.0, main.level)


## Two-level room: a steel mezzanine along a solid wall, stairs up, shelves and loot on top.
func _atrium(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var w: Array = []
	for cand in walls:
		if not cand[3]:
			w = cand
			break
	if w.is_empty():   # no blank wall to hang a deck on: it's a storeroom after all
		kinds[cell_at(to_global(o))] = "storage"
		_storage(o, walls, rng)
		return
	var top := 1.9
	var depth := 2.8
	var inward: Vector3 = w[2]
	var along := Vector3(1, 0, 0) if w[1] else Vector3(0, 0, 1)
	var len := CELL - 0.6
	var deck_c: Vector3 = w[0] + inward * (0.15 + depth / 2.0)
	A.sbox(self, Vector3(len, 0.12, depth) if w[1] else Vector3(depth, 0.12, len), deck_c + Vector3(0, top - 0.06, 0), "grate", Color.WHITE, true, 0.6)
	A.sbox(self, Vector3(len, 0.14, 0.1) if w[1] else Vector3(0.1, 0.14, len), deck_c + inward * (depth / 2.0) + Vector3(0, top - 0.1, 0), "metal", Color(0.85, 0.65, 0.15), false)
	var stair_end := 1 if rng.randf() < 0.5 else -1
	for side_w in walls:   # come down at the end whose side wall has no doorway, if there is one
		if side_w[3] and absf(side_w[2].dot(along)) > 0.5:
			stair_end = 1 if side_w[2].dot(along) > 0.0 else -1   # the doorway wall faces back into the room: go the other way
	for k in 5:   # columns + knee braces (none where the stairs come up)
		var cp := deck_c + inward * (depth / 2.0 - 0.1) + along * (-len / 2.0 + 0.3 + k * (len - 0.6) / 4.0)
		if absf((cp - deck_c).dot(along) - stair_end * (len / 2.0 - 0.8)) < 1.0:
			continue
		A.sbox(self, Vector3(0.14, top - 0.13, 0.14), cp + Vector3(0, (top - 0.13) / 2.0, 0), "rust", Color.WHITE, true, 1.0)   # stops under the deck
		var brace := A.box(self, Vector3(0.06, 0.9, 0.06), cp + Vector3(0, top - 0.4, 0) - inward * 0.3, "rust", Color.WHITE, false, 1.0)
		brace.rotation = Vector3(0.6 * (1 if inward.z > 0 else -1), 0, 0) if w[1] else Vector3(0, 0, -0.6 * (1 if inward.x > 0 else -1))
	# Stairs down from one end of the deck's front edge, railing along the rest.
	var stair_top: Vector3 = deck_c + inward * (depth / 2.0) + along * (stair_end * (len / 2.0 - 0.8)) + Vector3(0, top, 0)
	P.stairs(self, stair_top, inward, top, 3.0, 1.1)
	stairs[cell_at(to_global(o))] = {"high": stair_top - inward * 0.6 + Vector3(0, 0.5, 0), "low": stair_top + inward * 3.6 + Vector3(0, -top + 0.5, 0), "mid": 1.0, "exit_high": false, "vertical": false}
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
		if absf((p - stair_top).dot(along)) < 1.8:
			continue   # keep the foot of the stairs clear
		if rng.randf() < 0.5:
			A.crate(self, p, rng.randf_range(0.6, 0.9), rng)
		else:
			A.barrel(self, p, rng)
	_solid(deck_c, Vector3(len, top, depth) if w[1] else Vector3(depth, top, len))
	var foot_sz := Vector3(3.0, 1.0, 4.4) if absf(inward.z) > 0.5 else Vector3(4.4, 1.0, 3.0)   # the flight and a landing, kept clear
	_solid(stair_top + inward * 2.0 - Vector3(0, top, 0), foot_sz)
	A.fluorescent(self, deck_c + Vector3(0, H - 0.08, 0), theme.light, 0.9)


## Themes without pits get stairwells: a room with an opening in the floor along one wall and stairs
## down it. Big sites get two. They (and pits) are the ways down to the lower floor.
func _place_stairwells(rng: RandomNumberGenerator) -> void:
	var have := kinds.values().count("pit")
	var want := (2 if layout.cells.size() >= 18 else 1) - have
	if layout.cells.size() < 7:
		return
	var cands: Array = layout.cells.filter(func(c): return kinds[c] in ["storage", "office", "lab", "break", "empty", "machine", "server", "collapsed"] \
		and c.distance_squared_to(Vector2i.ZERO) > 1 and DIRS.any(func(d): return not layout.links[c].has(c + d)))
	for i in range(cands.size() - 1, 0, -1):   # seeded shuffle, so a site always rebuilds the same
		var j := rng.randi() % (i + 1)
		var t = cands[i]
		cands[i] = cands[j]
		cands[j] = t
	for c in cands.slice(0, maxi(want, 0)):
		kinds[c] = "stairwell"


## The lower floor grows out from the ways down (pits, stairwells) through the rock under and
## between the upper rooms: a small maze of basement rooms with its own doorways.
func _gen_lower(rng: RandomNumberGenerator) -> void:
	for c in layout.cells:
		if kinds[c] in ["pit", "stairwell"]:
			lower[c] = []
			low_kinds[c] = kinds[c]
	if lower.is_empty():
		return
	var target: int = lower.size() + clampi(layout.cells.size() / 3, 3, 9)
	for attempt in 400:
		if lower.size() >= target:
			break
		var keys := lower.keys()
		var c: Vector2i = keys[rng.randi() % keys.size()]
		var n: Vector2i = c + DIRS[rng.randi() % 4]
		if lower.has(n) or n == Vector2i.ZERO or kinds.get(n, "") in ["pit", "stairwell"]:
			continue
		if kinds.get(c, "") == "stairwell" and n - c == _stair_dir(c):
			continue   # the stairs run along that wall down here
		lower[n] = [c]
		lower[c].append(n)
		var pool := ["boiler", "storage", "pipes", "maintenance", "storage", "flooded"]
		low_kinds[n] = pool[rng.randi() % pool.size()]
	for c in lower:   # a few loops, so it isn't all dead ends
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = c + d
			var blocked: bool = (kinds.get(c, "") == "stairwell" and d == _stair_dir(c)) or (kinds.get(n, "") == "stairwell" and -d == _stair_dir(n))
			if lower.has(n) and not lower[c].has(n) and not blocked and rng.randf() < 0.3:
				lower[c].append(n)
				lower[n].append(c)


## Which wall a stairwell's stairs run along: its first wall without a doorway (as _stairwell picks it).
func _stair_dir(c: Vector2i) -> Vector2i:
	for d in DIRS:
		if not layout.links[c].has(c + d):
			return d
	return DIRS[0]


func _stairwell(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var w: Array = walls[0]
	for cand in walls:
		if not cand[3]:
			w = cand
			break
	var inward: Vector3 = w[2]
	var along := Vector3(1, 0, 0) if w[1] else Vector3(0, 0, 1)
	var run := 4.6
	var a0 := -2.65   # the opening, along the wall (from the wall's centre)
	var a1 := 3.0
	var deep := 1.75  # ...and out from the wall line
	# Floor with the opening cut out of it.
	var first := get_child_count()
	set_meta("no_pieces", true)   # (everything made on us from here is a node, so it can be told apart below)
	var flo := func(a_lo: float, a_hi: float, i_lo: float, i_hi: float) -> void:
		var cen: Vector3 = w[0] + along * ((a_lo + a_hi) / 2.0) + inward * ((i_lo + i_hi) / 2.0) + Vector3(0, -0.1, 0)
		var sz := Vector3(a_hi - a_lo, 0.2, i_hi - i_lo) if w[1] else Vector3(i_hi - i_lo, 0.2, a_hi - a_lo)
		A.sbox(self, sz, cen, theme.floor_kind, theme.floor, true, 2.0)
	flo.call(-CELL / 2.0, CELL / 2.0, deep, CELL)
	flo.call(-CELL / 2.0, a0, 0.0, deep)
	flo.call(a1, CELL / 2.0, 0.0, deep)
	# Edge trim round the opening, and a rail along it (the top end stays open: that's the way on).
	var trim := Color(0.85, 0.65, 0.15)
	A.sbox(self, Vector3(a1 - a0, 0.06, 0.08) if w[1] else Vector3(0.08, 0.06, a1 - a0), w[0] + along * ((a0 + a1) / 2.0) + inward * deep + Vector3(0, 0.03, 0), "hazard", Color.WHITE, false, 0.4)
	A.railing(self, w[0] + along * (a0 + 0.75) + inward * (deep - 0.05), w[0] + along * a1 + inward * (deep - 0.05), 1.0, "metal", true)
	A.railing(self, w[0] + along * (a1 - 0.05) + inward * 0.2, w[0] + along * (a1 - 0.05) + inward * deep, 1.0, "metal", true)
	var top: Vector3 = w[0] + inward * 0.95 + along * (a0 + 0.05)
	P.stairs(self, top, along, PIT, run, 1.2)
	stairs[cell_at(to_global(o))] = {"high": top - along * 0.6 + Vector3(0, 0.5, 0), "low": top + along * (run + 0.6) + Vector3(0, -PIT + 0.5, 0),
		"mid": -1.0, "exit_high": true, "vertical": true}
	var sign_at: Vector3 = w[0] + inward * 0.17 + along * (a0 - 0.9) + Vector3(0, 1.8, 0)
	var sign := B.label(self, "B-2  DOWN", sign_at, 40, Color(0.92, 0.88, 0.75), "stencil", 0.008)
	sign.rotation.y = atan2(inward.x, inward.z)
	for i in range(first, get_child_count()):
		get_child(i).set_meta("stairwell", true)
	remove_meta("no_pieces")
	var h0: Vector3 = w[0] + along * (a0 + 0.05) + inward * 0.3
	var h1: Vector3 = w[0] + along * (a1 - 0.05) + inward * (deep - 0.05)
	holes.append(AABB(Vector3(minf(h0.x, h1.x), -PIT + 0.6, minf(h0.z, h1.z)), Vector3(absf(h1.x - h0.x), PIT + 0.4, absf(h1.z - h0.z))))
	# Keep furniture off the opening and the top landing, up here and down there.
	var c0: Vector3 = w[0] + along * (a0 - 1.2)
	var c1: Vector3 = w[0] + along * (a1 + 0.9) + inward * (deep + 0.9)
	crates.append(AABB(Vector3(minf(c0.x, c1.x), -PIT - 0.5, minf(c0.z, c1.z)), Vector3(absf(c1.x - c0.x), PIT + 2.0, absf(c1.z - c0.z))))


## Litter, papers, cable trays, lamps... anything that ended up in a stairwell opening (or hangs
## into it from the basement ceiling below) goes; the stairs and their rails stay.
func _clear_holes() -> void:
	if holes.is_empty():
		return
	var doomed := {}
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		var top: Node = mi
		while top.get_parent() != self and top.get_parent() != low_root:
			top = top.get_parent()
		if top.has_meta("stairwell") or doomed.has(top) or top.get_script() != null:
			continue
		var box: AABB = global_transform.affine_inverse() * (mi.global_transform * mi.get_aabb())
		for h in holes:
			if h.intersects(box):
				doomed[top] = true
				break
	if Merge.sinks > 0:   # (the meshes that aren't nodes yet, art.gd's s-primitives: the same, one on us goes alone)
		for p: Array in ClassDB.class_call_static(&"MeshMerge", &"pieces_under", self):
			var top: Node = p[1]
			if top != self and top != low_root:
				while top.get_parent() != self and top.get_parent() != low_root:
					top = top.get_parent()
				if top.has_meta("stairwell") or doomed.has(top) or top.get_script() != null:
					continue
			var gt: Transform3D = p[2]
			var pb: AABB = p[3]
			var box: AABB = global_transform.affine_inverse() * (gt * pb)
			for h in holes:
				if h.intersects(box):
					if top == self or top == low_root:
						ClassDB.class_call_static(&"MeshMerge", &"drop", p[0])
					else:
						doomed[top] = true
					break
		ClassDB.class_call_static(&"MeshMerge", &"forget", doomed.keys())
	for n in doomed:
		n.free()


## Builds the lower floor: walls (with doorways), floors, ceilings where there's no room above,
## lights and dressing. Pits keep their walls on the main layer (their own lamp lights them).
## Down on B-2 a fog lies on the floor: knee deep, thick at the floor and thinning upward, in patches
## that creep slowly across it (one fog shader for all of it, `LOW_FOG`, in world space so it runs on
## from room to room). It shows where light falls on it: a lamp, your torch.
const LOW_FOG := """
shader_type fog;
uniform float density = 0.3;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fog() {
	vec2 p = WORLD_POSITION.xz * 0.11;   // (patches metres across: the fog's grid is too coarse for finer)
	float drift = n(p + vec2(TIME * 0.05, TIME * 0.03)) * 0.65 + n(p * 2.3 - vec2(TIME * 0.04, -TIME * 0.06)) * 0.35;
	float lie = 1.0 - smoothstep(0.05, 1.0, UVW.y + (drift - 0.5) * 0.35);   // thick at the floor, a ragged top
	DENSITY = density * lie * smoothstep(0.25, 0.75, drift);
	ALBEDO = vec3(0.72, 0.74, 0.76);
}
"""
static var _low_fog_mat: ShaderMaterial


func _floor_fog(o: Vector3) -> void:
	if _low_fog_mat == null:
		_low_fog_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = LOW_FOG
		_low_fog_mat.shader = sh
	var fog := FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog.size = Vector3(CELL, 1.3, CELL)
	fog.material = _low_fog_mat
	add_child(fog)   # (into the lower floor's own node with the rest of the room: _build_lower)
	fog.position = o + Vector3(0, 0.65, 0)


func _build_lower(rng: RandomNumberGenerator) -> void:
	low_root = Node3D.new()
	low_root.name = "Lower"
	add_child(low_root)
	if lower.is_empty():
		return
	var steel := Color(0.45, 0.43, 0.4)
	set_meta("no_pieces", true)   # (what's made on us here moves to low_root below: nodes, so it can)
	for c: Vector2i in lower:
		await _m("low %d %d" % [c.x, c.y])
		var o := Vector3(c.x * CELL, -PIT, c.y * CELL)
		var kind: String = low_kinds[c]
		var start := get_child_count()
		if kind != "pit":
			A.sbox(self, Vector3(CELL, 0.2, CELL), o + Vector3(0, -0.1, 0), "concrete", Color(0.62, 0.6, 0.56), true, 2.0)
		if not layout.links.has(c):   # nothing upstairs: its own ceiling slab
			A.sbox(self, Vector3(CELL + 0.28, 0.2, CELL + 0.28), o + Vector3(0, PIT - 0.12, 0), "concrete", Color(0.5, 0.48, 0.45), true, 2.0)
		var lwalls := []
		for d: Vector2i in DIRS:
			var n := c + d
			var linked: bool = lower[c].has(n)
			var center := o + Vector3(d.x, 0, d.y) * (CELL / 2.0)
			lwalls.append([center, d.y != 0, -Vector3(d.x, 0, d.y), linked])
			if lower.has(n) and (d.x < 0 or d.y < 0):
				continue   # shared: the other side builds it
			var pit_side: bool = kind == "pit" or low_kinds.get(n, "") == "pit"
			var wstart := get_child_count()
			_low_wall(center, d.y != 0, linked, steel)
			if pit_side:   # stays on the main layer, lit by the pit's own lamp
				for i in range(wstart, get_child_count()):
					get_child(i).set_meta("main_layer", true)
		if kind != "pit":
			_basement(c, o, lwalls, rng)
			_floor_fog(o)
		var made := []
		for i in range(start, get_child_count()):
			if not get_child(i).has_meta("main_layer"):
				made.append(get_child(i))
		for n in made:
			n.reparent(low_root)
	remove_meta("no_pieces")
	var next := ids.size()
	for c in lower:
		low_ids[c] = next
		cell_of_id[next] = c
		layer_of_id[next] = 1
		astar.add_point(next, Vector3(c.x, -1, c.y))
		next += 1
	for c in lower:
		for n in lower[c]:
			if not astar.are_points_connected(low_ids[c], low_ids[n]):
				astar.connect_points(low_ids[c], low_ids[n])
		if ids.has(c) and stairs.has(c) and stairs[c].vertical:   # pit / stairwell stairs: this room's two floors
			astar.connect_points(ids[c], low_ids[c])


func _low_wall(center: Vector3, along_x: bool, door: bool, steel: Color) -> void:
	var a := (center.x if along_x else center.z)
	var cc := (center.z if along_x else center.x)
	var top := PIT - 0.005   # stops just under the upper floor's surface
	var holes := [[a, 2.2, 0.0, 2.4]] if door else []
	A.wall(self, a - CELL / 2, a + CELL / 2, cc, 1.0, 0.32, holes, "rust", Color(0.75, 0.7, 0.65), along_x, -PIT, true, 1.5)
	A.wall(self, a - CELL / 2, a + CELL / 2, cc, top - 1.0, 0.3, [[a, 2.2, -10.0, 1.4]] if door else [], "concrete", Color(0.62, 0.6, 0.57), along_x, -PIT + 1.0, true, 2.0)
	if door:   # steel frame, 1.5 cm proud of the opening's faces so nothing lies flush
		for s in [-1, 1]:
			var p := center + (Vector3(s * 1.13, 1.1925, 0) if along_x else Vector3(0, 1.1925, s * 1.13))
			A.sbox(self, Vector3(0.09, 2.385, 0.42) if along_x else Vector3(0.42, 2.385, 0.09), p, "metal", steel, false)
		A.sbox(self, Vector3(2.35, 0.12, 0.42) if along_x else Vector3(0.42, 0.12, 2.35), center + Vector3(0, 2.445, 0), "hazard", Color.WHITE, false, 0.5)


## A basement room. o is its floor centre (y = -PIT).
func _basement(c: Vector2i, o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	var kind: String = low_kinds[c]
	var ceil_y := o.y + LOW_H
	match kind:
		"boiler":
			var q := _quad(o, rng, 1.4)
			P.generator(self, q, (PI / 2) * rng.randi_range(0, 3), rng, LOW_H)
			_solid(q, Vector3(4.2, 2.2, 4.2))
			for k in 2:
				var a := o + Vector3(-CELL / 2 + 0.4, LOW_H - 0.35 - k * 0.25, -CELL / 2 + 0.6 + k * 0.3)
				A.pipe(self, a, a + Vector3(CELL - 0.8, 0, 0), 0.09, "rust")
		"pipes":
			for k in 4:
				var z := -4.5 + k * 3.0
				A.pipe(self, o + Vector3(-CELL / 2 + 0.3, LOW_H - 0.3 - (k % 2) * 0.25, z), o + Vector3(CELL / 2 - 0.3, LOW_H - 0.3 - (k % 2) * 0.25, z), 0.07 + (k % 2) * 0.05, "rust" if k % 2 == 0 else "metal")
			for w in walls:
				if not w[3] and rng.randf() < 0.7:
					var foot := _wall_spot(w, _side(rng) * rng.randf_range(2.5, 4.5), 0.5)
					A.scyl(self, 0.3, 1.6, foot + Vector3(0, 0.8, 0), "metal", Color(0.55, 0.58, 0.55), true)   # tank
					A.scyl(self, 0.32, 0.06, foot + Vector3(0, 1.0, 0), "hazard", Color.WHITE, false)
					_solid(foot, Vector3(0.8, 1.6, 0.8))
		"maintenance":
			var w: Array = walls[rng.randi() % 4]
			for wc in walls:
				if not wc[3]:
					w = wc
					break
			P.workbench(self, _wall_spot(w, _side(rng) * 2.5, 0.5), _facing(w), rng)
			_solid(_wall_spot(w, 0.0, 0.5), Vector3(CELL - 1.0, 1.0, 1.0) if w[1] else Vector3(1.0, 1.0, CELL - 1.0))
			for k in 3:
				A.locker(self, _wall_spot(w, 3.4 + k * 0.62, 0.4), _facing(w))
		"flooded":
			var water := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(CELL - 0.3, CELL - 0.3)
			water.mesh = pm
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color(0.08, 0.1, 0.08, 0.85)
			wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			wm.roughness = 0.05
			water.material_override = wm
			add_child(water)
			water.position = o + Vector3(0, 0.12, 0)
	if kind != "flooded":
		_fill(o, walls, rng)
	P.litter(self, o, CELL / 2 - 0.8, rng, rng.randi_range(8, 16))
	for w in walls:   # things standing against the walls, never in a doorway
		if rng.randf() < 0.6:
			var off := _side(rng) * rng.randf_range(2.0, 4.8)
			var foot := _wall_spot(w, off, 0.45)
			if not crates.any(func(b): return b.grow(0.3).has_point(Vector3(foot.x, foot.y + 0.05, foot.z))):
				var size := P.wall_floor_item(self, foot, _facing(w), rng)
				if size != Vector3.ZERO:
					_solid(foot, Vector3(0.9, 1.2, 0.9))
	# Light: a caged lamp on a short drop (some are dead), and pipes and junk overhead.
	if rng.randf() < 0.75 or kind == "stairwell":
		var l := A.hanging_lamp(self, Vector3(o.x, ceil_y, o.z) + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)), theme.light, 0.35, 1.3, true)
		l.omni_range = 9.0
		if rng.randf() < 0.3:
			_flicker(l)
	else:
		B.omni(self, o + Vector3(0, LOW_H - 0.3, 0), Color(1, 0.15, 0.08), 0.35, 6.0)   # emergency red only
	P.ceiling_junk(self, o, LOW_H, rng)
	var cable := o + Vector3(-CELL / 2 + 0.3, LOW_H - 0.15, rng.randf_range(-4, 4))
	P.cable_tray(self, cable, cable + Vector3(CELL - 0.6, 0, 0))


## A low vent through a wall: steel frame both sides, the grille cover pulled off and leaning beside it.
func _vent(at: Vector3, along_x: bool) -> void:
	var frame := Color(0.5, 0.5, 0.48)
	for s in [-1, 1]:
		var n := Vector3(0, 0, s * 0.2) if along_x else Vector3(s * 0.2, 0, 0)
		var across := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		A.sbox(self, (Vector3(VENT_W + 0.16, 0.08, 0.06) if along_x else Vector3(0.06, 0.08, VENT_W + 0.16)), at + n + Vector3(0, VENT_H + 0.04, 0), "metal", frame, false)
		for e in [-1, 1]:
			A.sbox(self, Vector3(0.08, VENT_H, 0.06) if along_x else Vector3(0.06, VENT_H, 0.08), at + n + across * (e * (VENT_W / 2.0 + 0.04)) + Vector3(0, VENT_H / 2.0, 0), "metal", frame, false)
		if s > 0:
			var cover := A.box(self, Vector3(VENT_W - 0.1, VENT_H - 0.1, 0.03) if along_x else Vector3(0.03, VENT_H - 0.1, VENT_W - 0.1), at + n * 3.0 + across * (VENT_W * 0.9) + Vector3(0, VENT_H / 2.0 - 0.1, 0), "grille", Color(0.7, 0.7, 0.7), false, 0.3)
			cover.rotation = Vector3(-0.25, 0, 0) if along_x else Vector3(0, 0, 0.25)
	# Galvanised duct lining through the wall: floor, roof, sides, ribs, dark at the middle.
	var depth := 0.5
	var lin := Color(0.55, 0.56, 0.55)
	var sz_floor := Vector3(VENT_W, 0.03, depth) if along_x else Vector3(depth, 0.03, VENT_W)
	A.sbox(self, sz_floor, at + Vector3(0, 0.015, 0), "corrugated", lin, false, 0.4)
	A.sbox(self, sz_floor, at + Vector3(0, VENT_H - 0.015, 0), "corrugated", lin.darkened(0.3), false, 0.4)
	var across2 := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	for e in [-1, 1]:
		A.sbox(self, Vector3(0.03, VENT_H, depth) if along_x else Vector3(depth, VENT_H, 0.03), at + across2 * (e * VENT_W / 2.0) + Vector3(0, VENT_H / 2.0, 0), "corrugated", lin.darkened(0.15), false, 0.4)
	A.box(self, Vector3(VENT_W, VENT_H, 0.01) if along_x else Vector3(0.01, VENT_H, VENT_W), at + Vector3(0, VENT_H / 2.0, 0), "metal", Color(0.02, 0.02, 0.02), false).visible = false
	# Hazard tape over the opening on one side.
	A.sbox(self, Vector3(VENT_W + 0.2, 0.1, 0.02) if along_x else Vector3(0.02, 0.1, VENT_W + 0.2), at + Vector3(0, VENT_H + 0.14, 0) + (Vector3(0, 0, 0.21) if along_x else Vector3(0.21, 0, 0)), "hazard", Color.WHITE, false, 0.3)


## A sealed supply crate against a wall: pry it open (hold E) for whatever the last crew left.
func _supply_crate(o: Vector3, walls: Array, rng: RandomNumberGenerator) -> void:
	for tries in 8:
		var w: Array = walls[rng.randi() % walls.size()]
		var off := _side(rng) * rng.randf_range(2.4, 4.8)
		var spot := _wall_spot(w, off, 0.55)
		var blocked: bool = w[3] and absf(off) < 2.0
		for box in crates:
			if box.grow(0.4).has_point(Vector3(spot.x, spot.y + 0.05, spot.z)):
				blocked = true
		if blocked:
			continue
		var crate := P.supply_crate(self, spot, _facing(w), rng)
		supplies.append(crate)
		_solid(spot, Vector3(1.2, 0.7, 1.2))
		var loot := Callable(self, "_open_supply").bind(crate)
		var it := B.interactable(crate, Vector3(1.0, 0.6, 0.62), Vector3(0, 0.32, 0), Color(0, 0, 0, 0), "Pry open the supply crate", loot, 1.1)
		it.set_meta("crate", true)
		return


## Already pried open (a continued run): lid up (or the deposit box door swung), nothing inside.
func mark_opened(crate: Node3D) -> void:
	crate.set_meta("opened", true)
	if crate.has_meta("deposit"):
		(crate.get_meta("lid") as Node3D).rotation.y = -1.9
	else:
		(crate.get_meta("lid") as Node3D).rotation.x = 1.9
	for c in crate.get_children():
		if c.has_meta("crate"):
			c.queue_free()


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
	if main == null or not main.net.authority():
		return   # (what's inside is the host's to decide; its items come over the network)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n := 0 if rng.randf() < 0.12 else (1 if rng.randf() < 0.6 else 2)
	if n == 0:
		main.hud.msg("Empty. Somebody got here first.")
	for k in n:
		var id: String = "SHELLS" if rng.randf() < 0.15 else (Data.valuable_scrap(rng, false) if rng.randf() < 0.5 else Data.random_scrap(rng))
		main.spawn_item(id, crate.global_position + crate.global_transform.basis.z * -0.1 + Vector3(randf_range(-0.2, 0.2), 0.75 + k * 0.3, 0), -1.0, main.level)
