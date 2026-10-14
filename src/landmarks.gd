# A station's landmark: one big thing out on the surface worth the walk (level.gd picks one per
# station that suits the country, flattens the ground for it and adds its loot spots).
#   CHAPEL    stone or board nave under a steep roof, a bell tower with its bell and spire, pews,
#             the altar, a graveyard behind a low wall
#   LOOKOUT   a fire lookout: a steel tower with stairs you can climb, round a well, to a glazed
#             cab with a catwalk; the fire finder, the radio, a strongbox
#   FARM      a red gambrel barn with its doors run open, hay, a tractor; a silo; a stock tank
#   FUEL      a filling station: a canopy over two pump islands, the kiosk with its till and shelves,
#             the price sign on its pole
# Each has a safe or strongbox to pry open (loud), registered with the facility's crates so a save
# remembers it. `build` returns the loot spots inside (level coordinates).
extends RefCounted

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")
const Biomes = preload("res://src/biomes.gd")
const Sfx = preload("res://src/sfx.gd")

const RADIUS := {"CHAPEL": 15.0, "LOOKOUT": 8.0, "FARM": 15.0, "FUEL": 13.0}

## Which landmarks suit a biome.
const FOR := {"DESERT": ["FUEL", "CHAPEL", "LOOKOUT"], "ARCTIC": ["CHAPEL", "LOOKOUT"], "FOREST": ["LOOKOUT", "FARM", "CHAPEL"],
	"SWAMP": ["CHAPEL", "FARM"], "CITY": ["FUEL", "CHAPEL"]}


static func build(lv: Node3D, kind: String, pos: Vector3, rot_y: float, rng: RandomNumberGenerator, bio: String) -> Array:
	var r := A.root(lv, pos, rot_y)
	r.name = "Landmark"
	var spots: Array = []
	match kind:
		"CHAPEL": spots = _chapel(lv, r, rng, bio)
		"LOOKOUT": spots = _lookout(lv, r, rng)
		"FARM": spots = _farm(lv, r, rng)
		"FUEL": spots = _fuel(lv, r, rng)
	var out: Array = []
	for s in spots:
		out.append(lv.to_local(r.to_global(s)))
	return out


# --- the safe ------------------------------------------------------------------------------------

## A heavy iron safe on its plinth: a dial, a handle, a painted maker's name. Hold E to pry it open
## (loud); the door swings, and what was inside drops out (the host's dice). Kept in `lv.safes`.
static func safe(lv: Node3D, parent: Node3D, at: Vector3, rot_y: float, small := false) -> void:
	var s := Node3D.new()
	parent.add_child(s)
	s.position = at
	s.rotation.y = rot_y
	var k := 0.6 if small else 1.0
	var body := Color(0.22, 0.26, 0.24)
	A.sbox(s, Vector3(0.7, 0.8, 0.6) * k, Vector3(0, 0.4 * k, 0), "riveted", body, true, 0.4)
	A.sbox(s, Vector3(0.76, 0.06, 0.66) * k, Vector3(0, 0.03 * k, 0), "metal", body.darkened(0.4), false, 0.4)
	A.sbox(s, Vector3(0.6, 0.66, 0.02) * k, Vector3(0, 0.42 * k, -0.3 * k - 0.005), "metal", Color(0.05, 0.05, 0.05), false)   # (the dark inside)
	var hinge := Node3D.new()
	s.add_child(hinge)
	hinge.position = Vector3(-0.3 * k, 0.42 * k, -0.3 * k - 0.02)
	hinge.set_meta("live", true)
	A.sbox(hinge, Vector3(0.6, 0.66, 0.06) * k, Vector3(0.3 * k, 0, 0), "metal", body.lightened(0.05), false, 0.4)
	A.scyl(hinge, 0.07 * k, 0.03, Vector3(0.3 * k, 0.08 * k, -0.04), "brass", Color(0.85, 0.7, 0.4), false, "z")   # the dial
	A.scyl(hinge, 0.05 * k, 0.03, Vector3(0.3 * k, 0.08 * k, -0.06), "metal", Color(0.15, 0.15, 0.15), false, "z")
	A.sbox(hinge, Vector3(0.16, 0.03, 0.03) * k, Vector3(0.3 * k, -0.12 * k, -0.05), "metal", Color(0.75, 0.75, 0.72), false, 0.3)   # handle
	B.label(hinge, "ACME", Vector3(0.3 * k, 0.24 * k, -0.035), 24, Color(0.85, 0.72, 0.4), "plate", 0.004 * k).rotation.y = PI
	s.set_meta("lid", hinge)
	s.set_meta("deposit", true)   # (the facility's mark_opened swings it the same way)
	var it := B.interactable(s, Vector3(0.8, 0.9, 0.3) * k, Vector3(0, 0.42 * k, -0.4 * k), Color(0, 0, 0, 0), "Pry the safe open (loud)", Callable(), 3.0)
	it.set_meta("crate", true)
	it.action = func(): open_safe(lv, s)
	lv.safes.append(s)


static func open_safe(lv: Node3D, s: Node3D) -> void:
	if s.get_meta("opened", false):
		return
	s.set_meta("opened", true)
	var hinge: Node3D = s.get_meta("lid")
	hinge.create_tween().tween_property(hinge, "rotation:y", -1.9, 0.6).set_trans(Tween.TRANS_BACK)
	Sfx.play(lv, "clang_big", s.global_position, 2.0, 1.1)
	Sfx.play(lv, "creak", s.global_position, -2.0, 0.8)
	for c in s.get_children():
		if c.has_meta("crate"):
			c.queue_free()
	var main = lv.main
	if main == null:
		return
	main.noise(s.global_position, 22.0)
	if not main.net.authority():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out: Vector3 = -s.global_transform.basis.z
	var Data = load("res://src/data.gd")
	for k in rng.randi_range(2, 3):
		var id: String = ["GOLD_BAR", "CASH_BOX", "BEARER_BONDS"][rng.randi() % 3] if rng.randf() < 0.45 else Data.valuable_scrap(rng, false)
		main.spawn_item(id, s.global_position + out * (0.6 + k * 0.2) + Vector3(randf_range(-0.2, 0.2), 0.3, 0), -1.0, lv)


# --- the chapel ----------------------------------------------------------------------------------

## Nave along local z, the door (in the tower) at -z, the altar at +z. 8 m wide, 14 long.
static func _chapel(lv: Node3D, r: Node3D, rng: RandomNumberGenerator, bio: String) -> Array:
	var stone := bio in ["DESERT", "CITY", "SWAMP"]
	var kind := "ashlar" if stone else "siding"
	var tint := Color(0.86, 0.8, 0.72) if stone else Color(0.85, 0.84, 0.8)
	var w := 8.0
	var l := 14.0
	var h := 5.5
	var trim := Color(0.62, 0.58, 0.52)
	# Walls: tall windows down both sides, the end walls under the gables.
	var win := []
	for k in 4:
		win.append([-l / 2.0 + 2.6 + k * 3.0, 1.1, 1.6, 4.4])
	A.wall(r, -l / 2.0, l / 2.0, -w / 2.0, h, 0.4, win, kind, tint, false, 0.0, true, 1.5)
	A.wall(r, -l / 2.0, l / 2.0, w / 2.0, h, 0.4, win, kind, tint, false, 0.0, true, 1.5)
	A.wall(r, -w / 2.0, w / 2.0, l / 2.0, h, 0.4, [[0.0, 1.4, 2.0, 4.6]], kind, tint, true, 0.0, true, 1.5)
	A.wall(r, -w / 2.0, w / 2.0, -l / 2.0, h, 0.4, [[0.0, 1.6, 0.0, 2.8]], kind, tint, true, 0.0, true, 1.5)
	for s in [-1.0, 1.0]:   # gables and a steep roof, slates
		A.sprism(r, Vector3(w + 0.4, 3.6, 0.4), Vector3(0, h + 1.8, s * l / 2.0), kind, tint, Vector3.ZERO, 1.5)
		var pitch := atan2(3.8, w / 2.0)
		var slab := A.box(r, Vector3(sqrt(3.8 * 3.8 + 16.0) + 0.6, 0.18, l + 0.9), Vector3(s * w / 4.0, h + 1.85, 0), "shingle", Color(0.6, 0.62, 0.66), true, 1.0)
		slab.rotation.z = -s * pitch
		for k in 4:   # buttresses between the windows
			A.sbox(r, Vector3(0.5, h * 0.75, 0.6), Vector3(s * (w / 2.0 + 0.3), h * 0.375, -l / 2.0 + 1.1 + k * 3.0), kind, tint.darkened(0.08), false, 1.5)
	A.sbox(r, Vector3(0.25, 0.25, l + 1.0), Vector3(0, h + 3.75, 0), "metal", Color(0.25, 0.25, 0.25), false, 0.5)   # ridge
	for k in 4:   # what's left of the glass: dark, a few coloured panes
		for s in [-1.0, 1.0]:
			var z: float = -l / 2.0 + 2.6 + k * 3.0
			A.sbox(r, Vector3(0.04, 3.3, 0.06), Vector3(s * w / 2.0, 2.75, z), "metal", Color(0.15, 0.15, 0.15), false, 0.3)   # mullion
			A.sbox(r, Vector3(0.04, 0.06, 1.6), Vector3(s * w / 2.0, 3.0, z), "metal", Color(0.15, 0.15, 0.15), false, 0.3)
			if rng.randf() < 0.5:
				A.glow(r, Vector3(0.02, 0.9, 0.7), Vector3(s * (w / 2.0 - 0.02), 3.6, z - 0.4), [Color(0.6, 0.15, 0.1), Color(0.15, 0.25, 0.6), Color(0.6, 0.5, 0.15)][rng.randi() % 3], 0.35)
	# The rose window over the altar end, from outside: a ring and spokes.
	A.sring(r, 0.9, 0.75, Vector3(0, h + 1.1, l / 2.0 + 0.21), "stone", trim, Vector3(PI / 2, 0, 0))
	for k in 8:
		var a := TAU * k / 8.0
		A.sseg(r, Vector3(0, h + 1.1, l / 2.0 + 0.22), Vector3(cos(a) * 0.8, h + 1.1 + sin(a) * 0.8, l / 2.0 + 0.22), 0.04, 0.04, "stone", trim)
	A.sbox(r, Vector3(w - 0.4, 0.1, l - 0.4), Vector3(0, 0.05, 0), "wood", Color(0.6, 0.5, 0.42), true, 1.0)   # floor boards
	# The tower at the door end: a square tower, a belfry with louvres, the bell, a spire and its cross.
	var tz := -l / 2.0 - 1.6
	var th := 10.0
	A.wall(r, -1.8, 1.8, tz - 1.6, th, 0.35, [[0.0, 1.6, 0.0, 2.8], [0.0, 1.4, 7.6, 9.4]], kind, tint, true, 0.0, true, 1.5)
	for s in [-1.0, 1.0]:
		A.wall(r, tz - 1.6, tz + 1.6, s * 1.8, th, 0.35, [[tz, 1.4, 7.6, 9.4]], kind, tint, false, 0.0, true, 1.5)
	A.wall(r, -1.8, 1.8, tz + 1.6, th, 0.35, [[0.0, 1.6, 0.0, 2.8], [0.0, 1.4, 7.6, 9.4]], kind, tint, true, 0.0, false, 1.5)
	for s in [-1.0, 1.0]:   # louvres in the belfry openings
		for k in 4:
			A.sbox(r, Vector3(1.4, 0.06, 0.25), Vector3(0, 7.9 + k * 0.42, tz + s * 1.6), "wood", Color(0.45, 0.4, 0.35), false, 0.3, Vector3(s * 0.5, 0, 0))
	A.sbox(r, Vector3(3.9, 0.3, 3.5), Vector3(0, th, tz), "stone", trim, false, 1.0)
	A.scyl(r, 2.3, 5.0, Vector3(0, th + 2.6, tz), "shingle", Color(0.6, 0.62, 0.66), false, "y", 0.02)   # the spire
	A.scyl(r, 0.04, 1.4, Vector3(0, th + 5.6, tz), "metal", Color(0.3, 0.3, 0.3))
	A.sbox(r, Vector3(0.6, 0.06, 0.06), Vector3(0, th + 6.0, tz), "metal", Color(0.3, 0.3, 0.3), false)
	A.sseg(r, Vector3(0, 9.2, tz), Vector3(0, 8.95, tz), 0.06, 0.06, "metal", Color(0.3, 0.3, 0.3))
	A.sseg(r, Vector3(0, 8.95, tz), Vector3(0, 8.3, tz), 0.16, 0.42, "brass", Color(0.7, 0.55, 0.3), 0.5)   # the bell
	A.sbox(r, Vector3(3.2, 0.2, 0.2), Vector3(0, 9.25, tz), "wood", Color(0.4, 0.33, 0.28), false, 0.4)
	A.sbox(r, Vector3(3.2, 0.1, 3.0), Vector3(0, 0.05, tz), "stone", Color(0.6, 0.58, 0.55), true, 1.0)
	# Inside: pews in two banks, a few overturned; the altar under a cloth with candles; a lectern.
	for k in 6:
		for s in [-1.0, 1.0]:
			var pz := -l / 2.0 + 2.2 + k * 1.5
			var p := Node3D.new()
			r.add_child(p)
			p.position = Vector3(s * 1.9, 0, pz)
			if rng.randf() < 0.15:
				p.rotation = Vector3(-1.3, rng.randf_range(-0.3, 0.3), 0)
				p.position.y = 0.25
			var wood := Color(0.55, 0.38, 0.25)
			A.sbox(p, Vector3(2.6, 0.06, 0.42), Vector3(0, 0.46, 0), "wood", wood, false, 0.5)
			A.sbox(p, Vector3(2.6, 0.5, 0.05), Vector3(0, 0.75, 0.2), "wood", wood, false, 0.5)
			for x in [-1.25, 1.25]:
				A.sbox(p, Vector3(0.06, 0.95, 0.5), Vector3(x, 0.48, 0.02), "wood", wood.darkened(0.15), false, 0.5)
	A.sbox(r, Vector3(w - 0.4, 0.3, 2.6), Vector3(0, 0.15, l / 2.0 - 1.5), "wood", Color(0.5, 0.4, 0.32), true, 0.8)   # the chancel step
	A.sbox(r, Vector3(2.0, 1.0, 0.8), Vector3(0, 0.8, l / 2.0 - 1.1), "stone", Color(0.8, 0.78, 0.72), true, 1.0)
	A.sbox(r, Vector3(2.1, 0.03, 0.9), Vector3(0, 1.31, l / 2.0 - 1.1), "fabric_tint", Color(0.85, 0.82, 0.72), false, 0.5)
	A.sbox(r, Vector3(0.3, 0.8, 0.02), Vector3(0, 0.9, l / 2.0 - 1.52), "fabric_tint", Color(0.55, 0.12, 0.1), false, 0.5)
	for x in [-0.7, 0.7]:
		A.scyl(r, 0.05, 0.3, Vector3(x, 1.47, l / 2.0 - 1.1), "metal", Color(0.75, 0.62, 0.3))
		A.scyl(r, 0.025, 0.12, Vector3(x, 1.68, l / 2.0 - 1.1), "cream", Color(0.92, 0.9, 0.82))
	A.sseg(r, Vector3(-2.6, 0.3, l / 2.0 - 2.6), Vector3(-2.6, 1.3, l / 2.0 - 2.6), 0.05, 0.05, "wood", Color(0.45, 0.32, 0.22))   # lectern
	A.sbox(r, Vector3(0.5, 0.04, 0.4), Vector3(-2.6, 1.35, l / 2.0 - 2.6), "wood", Color(0.45, 0.32, 0.22), false, 0.4, Vector3(-0.4, 0, 0))
	safe(lv, r, Vector3(2.9, 0.3, l / 2.0 - 1.6), PI, true)   # the poor box
	# The graveyard behind, inside a low stone wall.
	var gz := l / 2.0 + 1.5
	for s in [-1.0, 1.0]:
		A.sbox(r, Vector3(0.4, 0.8, 9.0), Vector3(s * 6.5, 0.4, gz + 4.5), "stone", trim, true, 1.0)
	A.sbox(r, Vector3(13.4, 0.8, 0.4), Vector3(0, 0.4, gz + 9.0), "stone", trim, true, 1.0)
	for i in rng.randi_range(12, 18):
		var gp := Vector3(rng.randf_range(-5.5, 5.5), 0, gz + rng.randf_range(1.0, 8.2))
		var stone_c := Color(0.62, 0.62, 0.6).darkened(rng.randf() * 0.3)
		var t := Node3D.new()
		r.add_child(t)
		t.position = gp
		t.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.15, 0.15), rng.randf_range(-0.1, 0.1))
		if rng.randf() < 0.3:   # a cross
			A.sbox(t, Vector3(0.14, 1.1, 0.12), Vector3(0, 0.5, 0), "stone", stone_c, false, 0.5)
			A.sbox(t, Vector3(0.6, 0.12, 0.12), Vector3(0, 0.75, 0), "stone", stone_c, false, 0.5)
		else:   # a headstone, round-topped
			var hh := rng.randf_range(0.6, 1.0)
			A.sbox(t, Vector3(0.55, hh, 0.12), Vector3(0, hh / 2.0 - 0.05, 0), "stone", stone_c, false, 0.5)
			A.scyl(t, 0.275, 0.12, Vector3(0, hh - 0.05, 0), "stone", stone_c, false, "z")
		A.sbox(t, Vector3(0.7, 0.06, 1.6), Vector3(0, 0.03, 0.9), "dirt", Color(0.8, 0.75, 0.7), false, 0.5)   # the grave
	if bio == "FOREST":
		Biomes.oak(r, Vector3(-4.0, -0.1, gz + 6.0), rng, 0.9)
	else:
		A.dead_tree(r, Vector3(-4.0, 0, gz + 6.0), rng)
	return [Vector3(0, 1.4, l / 2.0 - 1.1), Vector3(1.9, 0.6, 0.0), Vector3(-1.9, 0.6, -3.0), Vector3(0, 0.3, tz)]


# --- the lookout ---------------------------------------------------------------------------------

## A steel fire lookout: four legs, cross-braced, a square stair climbing round inside to a glazed
## cab on top with a catwalk all round. Walkable all the way up.
static func _lookout(lv: Node3D, r: Node3D, rng: RandomNumberGenerator) -> Array:
	var steel := Color(0.5, 0.52, 0.5)
	var half := 2.5
	var rise := 1.8
	var flights := 7
	var top := rise * flights
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			A.sbox(r, Vector3(0.18, top + 0.2, 0.18), Vector3(sx * half, (top + 0.2) / 2.0, sz * half), "metal", steel, true, 0.6)
			A.sbox(r, Vector3(0.6, 0.5, 0.6), Vector3(sx * half, 0.2, sz * half), "concrete", Color(0.7, 0.68, 0.64), true, 1.0)
	for lvl in flights:   # cross bracing between the legs on every face
		var y0 := lvl * rise
		for f in 4:
			var a := Vector3(half, 0, half).rotated(Vector3.UP, f * PI / 2.0)
			var b := Vector3(half, 0, -half).rotated(Vector3.UP, f * PI / 2.0)
			A.sseg(r, a + Vector3(0, y0, 0), b + Vector3(0, y0 + rise, 0), 0.03, 0.03, "metal", steel.darkened(0.15))
			A.sseg(r, b + Vector3(0, y0, 0), a + Vector3(0, y0 + rise, 0), 0.03, 0.03, "metal", steel.darkened(0.15))
			A.sseg(r, a + Vector3(0, y0 + rise, 0), b + Vector3(0, y0 + rise, 0), 0.04, 0.04, "metal", steel)
	# The stair: a flight up each side in turn, between corner landings, a rail on the outside.
	var land := 1.0
	var run := half * 2.0 - land * 2.0
	var wood := Color(0.55, 0.45, 0.35)
	for i in flights:
		var side := i % 4
		var y0 := i * rise
		var rot := -side * PI / 2.0
		var fl := Node3D.new()
		r.add_child(fl)
		fl.rotation.y = rot
		# In the flight's frame: it runs along +x on the z = -(half - 0.5) side, from x = -half+land to half-land.
		var x0 := -half + land
		var z := -(half - 0.55)
		var slope := atan2(rise, run)
		var ramp := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(sqrt(run * run + rise * rise), 0.1, 1.0)
		cs.shape = bs
		ramp.add_child(cs)
		fl.add_child(ramp)
		ramp.position = Vector3(0, y0 + rise / 2.0 - 0.05, z)
		ramp.rotation.z = slope
		var steps := 9
		for k in steps:   # treads and the stringers under them
			A.sbox(fl, Vector3(run / steps + 0.04, 0.04, 0.95), Vector3(x0 + (k + 0.5) * run / steps, y0 + (k + 1) * rise / steps - 0.02, z), "grate", Color.WHITE, false, 0.4)
		for zz in [z - 0.48, z + 0.48]:
			A.sseg(fl, Vector3(x0, y0, zz), Vector3(x0 + run, y0 + rise, zz), 0.04, 0.04, "metal", steel)
		A.sseg(fl, Vector3(x0, y0 + 1.0, z - 0.5), Vector3(x0 + run, y0 + rise + 1.0, z - 0.5), 0.025, 0.025, "metal", Color(0.85, 0.65, 0.15))   # handrail
		# The landing at the top of this flight (the next one starts from it).
		A.sbox(fl, Vector3(land, 0.08, land), Vector3(half - land / 2.0, y0 + rise - 0.04, -(half - land / 2.0)), "grate", Color.WHITE, true, 0.4)
	A.sbox(r, Vector3(land, 0.08, land), Vector3(-half + land / 2.0, -0.04 + 0.08, -(half - land / 2.0)), "concrete", Color(0.7, 0.68, 0.64), true, 1.0)   # the foot
	# The cab: a floor with a hatch where the stair comes up, windows all round, a roof, the catwalk.
	var cy := top
	var cw := half + 0.2
	# (the floor, with the hatch the stair comes up through along its +z side)
	A.sbox(r, Vector3(cw * 2.0, 0.15, cw + 1.4), Vector3(0, cy, -cw + (cw + 1.4) / 2.0), "wood", wood, true, 0.6)
	A.railing(r, Vector3(-0.5, cy + 0.07, 1.4), Vector3(cw, cy + 0.07, 1.4), 1.0, "metal", true)   # round the hatch
	for q in [[Vector3(half * 2.0 + 2.6, 0.08, 1.15), Vector3(0, cy - 0.08, half + 0.73)], [Vector3(half * 2.0 + 2.6, 0.08, 1.15), Vector3(0, cy - 0.08, -half - 0.73)],
			[Vector3(1.15, 0.08, half * 2.0 + 0.4), Vector3(half + 0.73, cy - 0.08, 0)], [Vector3(1.15, 0.08, half * 2.0 + 0.4), Vector3(-half - 0.73, cy - 0.08, 0)]]:
		A.sbox(r, q[0], q[1], "grate", Color.WHITE, false, 0.4)   # the catwalk
	var cb := StaticBody3D.new()   # (the catwalk round the cab: walkable, outside the cab's floor)
	for q in [[Vector3(half * 2.0 + 2.6, 0.1, 1.2), Vector3(0, cy - 0.1, half + 0.7)], [Vector3(half * 2.0 + 2.6, 0.1, 1.2), Vector3(0, cy - 0.1, -half - 0.7)],
			[Vector3(1.2, 0.1, half * 2.0 + 2.6), Vector3(half + 0.7, cy - 0.1, 0)], [Vector3(1.2, 0.1, half * 2.0 + 2.6), Vector3(-half - 0.7, cy - 0.1, 0)]]:
		var c2 := CollisionShape3D.new()
		var b2 := BoxShape3D.new()
		b2.size = q[0]
		c2.shape = b2
		c2.position = q[1]
		cb.add_child(c2)
	r.add_child(cb)
	A.railing(r, Vector3(-half - 1.25, cy, -half - 1.25), Vector3(half + 1.25, cy, -half - 1.25), 1.05, "metal", true)
	A.railing(r, Vector3(half + 1.25, cy, -half - 1.25), Vector3(half + 1.25, cy, half + 1.25), 1.05, "metal", true)
	A.railing(r, Vector3(half + 1.25, cy, half + 1.25), Vector3(-half - 1.25, cy, half + 1.25), 1.05, "metal", true)
	A.railing(r, Vector3(-half - 1.25, cy, half + 1.25), Vector3(-half - 1.25, cy, -half - 1.25), 1.05, "metal", true)
	var paint := Color(0.85, 0.82, 0.74)
	for f in 4:   # walls: waist high, then glass to the roof (glass mostly gone), a door on one side
		var cr := Node3D.new()
		r.add_child(cr)
		cr.rotation.y = f * PI / 2.0
		var holes: Array = [[0.0, cw * 2.0 - 0.6, 1.0, 2.2]] if f != 1 else [[-0.9, 0.9, 0.0, 2.1], [0.9, 1.6, 1.0, 2.2]]
		A.wall(cr, -cw, cw, -cw, 2.5, 0.1, holes, "siding", paint, true, cy + 0.08, true, 0.8)
		for k in 4:
			A.sbox(cr, Vector3(0.06, 1.2, 0.06), Vector3(-cw + 0.3 + k * (cw * 2.0 - 0.6) / 3.0, cy + 1.68, -cw), "wood", paint.darkened(0.1), false, 0.3)
		if rng.randf() < 0.5:
			var gl = A.box(cr, Vector3(0.9, 1.1, 0.02), Vector3(rng.randf_range(-1.0, 1.0), cy + 1.68, -cw + 0.02), "metal", Color.WHITE, false)
			gl.material_override = A.glass()
	var pitch := 0.25
	for s in [-1.0, 1.0]:
		var rf := A.box(r, Vector3(cw * 2.0 + 1.2, 0.12, cw + 0.7), Vector3(0, cy + 2.75, s * (cw + 0.7) / 2.0), "corrugated", Color(0.62, 0.62, 0.6), false, 1.0)
		rf.rotation.x = s * pitch
	A.scyl(r, 0.02, 1.4, Vector3(0, cy + 3.6, 0), "copper", Color.WHITE)   # lightning rod
	# Inside the cab: the fire finder on its stand, a stool, the radio, the strongbox.
	A.scyl(r, 0.12, 1.0, Vector3(0, cy + 0.6, 0.0), "wood", wood.darkened(0.2))
	A.scyl(r, 0.5, 0.08, Vector3(0, cy + 1.12, 0.0), "paper", Color(0.9, 0.86, 0.72))
	A.sring(r, 0.52, 0.48, Vector3(0, cy + 1.17, 0.0), "brass", Color(0.85, 0.7, 0.4))
	A.sbox(r, Vector3(0.9, 0.04, 0.06), Vector3(0, 1.2 + cy, 0), "brass", Color(0.85, 0.7, 0.4), false, 0.3, Vector3(0, 0.6, 0))
	P.chair(r, Vector3(0.9, cy + 0.08, -0.6), 2.5, "wood")
	P.table(r, Vector3(-1.4, cy + 0.08, -1.4), 0.0, 1.1, 0.6, "wood")
	A.sbox(r, Vector3(0.5, 0.3, 0.3), Vector3(-1.4, cy + 0.98, -1.4), "metal", Color(0.3, 0.33, 0.3), false, 0.4)   # the radio
	A.sseg(r, Vector3(-1.2, cy + 1.13, -1.4), Vector3(-1.2, cy + 2.0, -1.5), 0.006, 0.006, "metal", Color(0.6, 0.6, 0.6))
	safe(lv, r, Vector3(1.4, cy + 0.08, 1.3), PI * 0.75, true)
	return [Vector3(0, cy + 1.3, 0), Vector3(-1.4, cy + 0.9, -1.2), Vector3(0.6, 0.2, 0.6)]


# --- the farm ------------------------------------------------------------------------------------

static func _farm(lv: Node3D, r: Node3D, rng: RandomNumberGenerator) -> Array:
	var red := Color(0.62, 0.22, 0.16)
	var w := 9.0
	var l := 12.0
	var eave := 4.0
	# The barn's walls: board siding, the big doors in each end (the front run open), a loft door.
	A.wall(r, -l / 2.0, l / 2.0, -w / 2.0, eave, 0.2, [[0.0, 1.2, 1.2, 2.2]], "siding", red, false, 0.0, true, 0.8)
	A.wall(r, -l / 2.0, l / 2.0, w / 2.0, eave, 0.2, [[-2.0, 1.2, 1.2, 2.2], [2.0, 1.2, 1.2, 2.2]], "siding", red, false, 0.0, true, 0.8)
	for s in [-1.0, 1.0]:
		A.wall(r, -w / 2.0, w / 2.0, s * l / 2.0, eave, 0.2, [[0.0, 3.6, 0.0, 3.4]], "siding", red, true, 0.0, true, 0.8)
		# The gambrel gable: a lower steep pair and a shallow top pair of slopes, filled with boards.
		A.sprism(r, Vector3(w, 3.2, 0.2), Vector3(0, eave + 1.6, s * l / 2.0), "siding", red, Vector3.ZERO, 0.8)
		A.sbox(r, Vector3(1.4, 1.2, 0.05), Vector3(0, eave + 1.0, s * (l / 2.0 + 0.1)), "wood", Color(0.85, 0.8, 0.7), false, 0.6)   # loft door
	for s in [-1.0, 1.0]:   # the roof: steep lower slopes, shallow upper ones
		var lo := A.box(r, Vector3(2.6, 0.12, l + 0.8), Vector3(s * (w / 2.0 - 0.55), eave + 1.15, 0), "corrugated", Color(0.55, 0.55, 0.52), true, 1.0)
		lo.rotation.z = -s * 1.05
		var hi := A.box(r, Vector3(3.2, 0.12, l + 0.8), Vector3(s * 1.45, eave + 2.75, 0), "corrugated", Color(0.55, 0.55, 0.52), true, 1.0)
		hi.rotation.z = -s * 0.35
	for s in [-1.0, 1.0]:   # white trim round the door openings, the X braces on the doors
		A.sbox(r, Vector3(3.8, 0.15, 0.06), Vector3(0, 3.45, s * (l / 2.0 + 0.11)), "cream", Color(0.92, 0.9, 0.84), false, 0.5)
	for dx in [-2.75, 2.85]:   # the front doors, run open on their track
		var door := A.box(r, Vector3(1.8, 3.3, 0.1), Vector3(dx, 1.7, -l / 2.0 - 0.2), "siding", red.lightened(0.05), false, 0.8)
		A.sseg(door, Vector3(-0.85, -1.6, -0.06), Vector3(0.85, 1.6, -0.06), 0.04, 0.04, "cream", Color(0.92, 0.9, 0.84))
		A.sseg(door, Vector3(0.85, -1.6, -0.06), Vector3(-0.85, 1.6, -0.06), 0.04, 0.04, "cream", Color(0.92, 0.9, 0.84))
	A.sbox(r, Vector3(7.4, 0.1, 0.1), Vector3(0, 3.5, -l / 2.0 - 0.25), "metal", Color(0.3, 0.3, 0.3), false)   # the track
	A.sbox(r, Vector3(w - 0.4, 0.08, l - 0.4), Vector3(0, 0.04, 0), "dirt", Color(0.9, 0.85, 0.75), true, 1.0)
	# Inside: hay bales stacked and loose, a loft along one side, a tractor.
	for i in 10:
		var hb := A.box(r, Vector3(1.0, 0.5, 0.6), Vector3(3.2 - (i % 3) * 1.05, 0.25 + (i / 3) * 0.5, 4.5 - (i / 6) * 0.65), "canvas", Color(0.85, 0.72, 0.4), true, 0.5)
		hb.rotation.y = rng.randf_range(-0.05, 0.05)
	A.sbox(r, Vector3(w - 0.4, 0.12, 3.2), Vector3(0, 2.8, 4.1), "wood", Color(0.55, 0.45, 0.35), false, 0.6)   # the loft
	for x in [-3.5, 0.0, 3.5]:
		A.sbox(r, Vector3(0.18, 2.8, 0.18), Vector3(x, 1.4, 2.6), "wood", Color(0.45, 0.38, 0.3), false, 0.5)
	_tractor(r, Vector3(-1.6, 0, -1.5), 0.3, rng)
	safe(lv, r, Vector3(-3.6, 0.08, 4.8), PI, true)   # (the farmer's strongbox)
	# The silo and a stock tank outside.
	var sp := Vector3(w / 2.0 + 3.2, 0, 2.0)
	A.scyl(r, 2.2, 12.0, sp + Vector3(0, 6.0, 0), "corrugated", Color(0.7, 0.7, 0.68), true)
	for k in 6:
		A.sring(r, 2.26, 2.2, sp + Vector3(0, 1.0 + k * 2.0, 0), "metal", Color(0.5, 0.5, 0.48), Vector3.ZERO)
	var dome := A.sphere(r, 2.25, sp + Vector3(0, 12.0, 0), "metal", Color(0.6, 0.6, 0.58), 0.0, 0.6)
	dome.scale.y = 0.6
	for k in 18:   # its ladder
		A.sbox(r, Vector3(0.5, 0.04, 0.04), sp + Vector3(-2.3, 0.5 + k * 0.62, 0), "metal", Color(0.4, 0.4, 0.4), false)
	A.scyl(r, 1.0, 0.6, Vector3(-w / 2.0 - 2.2, 0.3, -2.0), "metal", Color(0.55, 0.57, 0.55), true, "x")   # stock tank
	for i in 4:
		P.bale(r, Vector3(-w / 2.0 - 2.0 + (i % 2) * 1.2, 0, 3.0 + (i / 2) * 1.2), 1.0, rng)
	return [Vector3(3.0, 1.8, 4.5), Vector3(-1.6, 1.2, -1.5), Vector3(1.0, 0.3, -3.0), Vector3(-2.0, 3.0, 4.0)]


## An old tractor: big rear wheels, small front ones, the engine hood, a seat and the stack.
static func _tractor(parent: Node3D, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := A.root(parent, pos, rot_y, Vector3(1.8, 1.8, 3.2))
	var paint := [Color(0.25, 0.42, 0.22), Color(0.65, 0.25, 0.15), Color(0.7, 0.55, 0.2)][rng.randi() % 3] as Color
	A.sbox(r, Vector3(0.8, 0.8, 2.0), Vector3(0, 1.1, -0.5), "paint", paint, false, 0.6)
	A.sbox(r, Vector3(0.7, 0.6, 0.06), Vector3(0, 1.1, -1.52), "grille", Color.WHITE, false, 0.3)
	A.sseg(r, Vector3(0.2, 1.5, -0.9), Vector3(0.2, 2.3, -0.9), 0.05, 0.05, "rust", Color.WHITE)
	A.sbox(r, Vector3(0.5, 0.1, 0.4), Vector3(0, 1.4, 0.9), "metal", Color(0.2, 0.2, 0.2), false)
	A.sseg(r, Vector3(0, 1.4, 0.4), Vector3(0, 1.9, 0.1), 0.02, 0.02, "metal", Color(0.2, 0.2, 0.2))
	A.scyl(r, 0.22, 0.04, Vector3(0, 1.9, 0.08), "metal", Color(0.15, 0.15, 0.15), false, "y")   # wheel
	for s in [-1.0, 1.0]:
		A.scyl(r, 0.75, 0.4, Vector3(s * 0.75, 0.75, 0.6), "rubber", Color(0.4, 0.4, 0.4), false, "x")
		A.scyl(r, 0.4, 0.42, Vector3(s * 0.75, 0.75, 0.6), "paint", paint, false, "x")
		A.scyl(r, 0.38, 0.25, Vector3(s * 0.45, 0.38, -1.2), "rubber", Color(0.4, 0.4, 0.4), false, "x")
		A.sbox(r, Vector3(0.5, 0.06, 0.9), Vector3(s * 0.75, 1.55, 0.6), "paint", paint.darkened(0.2), false, 0.5)   # mudguards


# --- the filling station -------------------------------------------------------------------------

static func _fuel(lv: Node3D, r: Node3D, rng: RandomNumberGenerator) -> Array:
	var white := Color(0.88, 0.86, 0.8)
	var brand := [Color(0.75, 0.18, 0.12), Color(0.15, 0.3, 0.55), Color(0.85, 0.6, 0.15)][rng.randi() % 3] as Color
	A.sbox(r, Vector3(16.0, 0.12, 12.0), Vector3(0, 0.06, 0), "concrete", Color(0.75, 0.72, 0.68), true, 2.0)   # the forecourt
	# The canopy on four posts over the pumps.
	for x in [-4.0, 4.0]:
		for z in [-2.6, 1.0]:
			A.sbox(r, Vector3(0.3, 4.4, 0.3), Vector3(x, 2.3, z), "metal", white, true, 0.6)
	A.sbox(r, Vector3(11.0, 0.6, 6.0), Vector3(0, 4.7, -0.8), "metal", white, false, 1.0)
	A.sbox(r, Vector3(11.1, 0.4, 6.1), Vector3(0, 4.55, -0.8), "paint", brand, false, 1.0)   # its fascia
	for z in [-3.86, 2.26]:
		B.label(r, "PETROL", Vector3(0, 4.55, z + (-0.0 if z < 0 else 0.0)), 80, Color(0.95, 0.92, 0.85), "plate", 0.006).rotation.y = PI if z < 0 else 0.0
	for k in 3:   # lamps under it, dead
		A.sbox(r, Vector3(1.2, 0.05, 0.4), Vector3(-3.5 + k * 3.5, 4.36, -0.8), "cream", Color(0.7, 0.7, 0.65), false, 0.5)
	# Two pump islands with old pumps: a round dial face, the hose on its hook.
	for x in [-2.0, 2.0]:
		A.sbox(r, Vector3(1.0, 0.25, 3.4), Vector3(x, 0.24, -0.8), "concrete", Color(0.8, 0.78, 0.74), true, 1.0)
		for z in [-1.8, 0.2]:
			var pump := A.root(r, Vector3(x, 0.36, z), 0.0, Vector3(0.6, 1.8, 0.5))
			A.sbox(pump, Vector3(0.6, 1.5, 0.45), Vector3(0, 0.75, 0), "paint", brand, false, 0.6)
			A.sbox(pump, Vector3(0.5, 0.35, 0.47), Vector3(0, 1.62, 0), "cream", white, false, 0.6)
			for s in [-1.0, 1.0]:
				A.scyl(pump, 0.16, 0.02, Vector3(0, 1.62, s * 0.24), "cream", Color(0.95, 0.93, 0.85), false, "z")
				A.sbox(pump, Vector3(0.012, 0.12, 0.004), Vector3(0, 1.66, s * 0.25), "metal", Color(0.1, 0.1, 0.1), false)
			A.ssphere(pump, 0.18, Vector3(0, 1.95, 0), "cream", Color(0.95, 0.9, 0.8), 0.0, 1.0)   # the globe
			A.sseg(pump, Vector3(0.3, 1.2, 0), Vector3(0.45, 0.2, 0.1), 0.03, 0.03, "rubber", Color(0.4, 0.4, 0.4))
			A.sbox(pump, Vector3(0.08, 0.25, 0.08), Vector3(0.32, 1.1, 0), "metal", Color(0.3, 0.3, 0.3), false)
	P.car_wreck(r, Vector3(-5.5, 0.12, 2.0), 0.4, rng)
	# The kiosk: block walls, a shopfront of empty window frames, a flat roof with a sign.
	var kz := 4.8
	A.wall(r, -4.0, 4.0, kz - 2.0, 3.0, 0.25, [[-2.0, 2.4, 0.9, 2.6], [1.6, 1.0, 0.0, 2.2], [2.9, 1.0, 0.9, 2.6]], "concrete", white, true, 0.06, true, 1.2)
	A.wall(r, -4.0, 4.0, kz + 2.0, 3.0, 0.25, [[0.0, 1.0, 1.2, 2.0]], "concrete", white, true, 0.06, true, 1.2)
	for s in [-1.0, 1.0]:
		A.wall(r, kz - 2.0, kz + 2.0, s * 4.0, 3.0, 0.25, [], "concrete", white, false, 0.06, true, 1.2)
	A.sbox(r, Vector3(8.6, 0.25, 4.6), Vector3(0, 3.18, kz), "concrete", Color(0.7, 0.68, 0.64), true, 1.0)
	A.sbox(r, Vector3(5.0, 0.8, 0.12), Vector3(0, 3.7, kz - 2.1), "paint", brand, false, 0.6)
	B.label(r, "SERVICE  ·  SNACKS", Vector3(0, 3.7, kz - 2.17), 50, Color(0.95, 0.92, 0.85), "plate", 0.0055).rotation.y = PI
	A.sbox(r, Vector3(2.4, 0.08, 0.3), Vector3(-2.0, 0.92, kz - 2.0), "wood", Color(0.5, 0.42, 0.35), false, 0.4)
	A.sbox(r, Vector3(2.8, 1.0, 0.7), Vector3(-1.4, 0.56, kz + 0.2), "wood", Color(0.55, 0.42, 0.3), true, 0.6)   # the counter
	A.sbox(r, Vector3(0.45, 0.3, 0.4), Vector3(-0.6, 1.21, kz + 0.2), "metal", Color(0.4, 0.42, 0.4), false, 0.4)   # the till
	A.shelf_unit(r, Vector3(2.2, 0.06, kz + 1.6), PI, rng, 2.4, 1.8, 0.45)
	A.shelf_unit(r, Vector3(-3.0, 0.06, kz + 1.6), PI, rng, 1.6, 1.8, 0.45)
	safe(lv, r, Vector3(-3.3, 0.06, kz + 0.2), PI / 2.0, true)
	# The price sign on its pole by the road.
	var pp := Vector3(7.0, 0, -5.0)
	A.scyl(r, 0.12, 6.0, pp + Vector3(0, 3.0, 0), "metal", Color(0.5, 0.52, 0.5), true)
	A.sbox(r, Vector3(2.2, 2.6, 0.2), pp + Vector3(0, 5.8, 0), "paint", brand, false, 0.6)
	A.sbox(r, Vector3(1.9, 0.6, 0.22), pp + Vector3(0, 6.6, 0), "cream", white, false, 0.5)
	B.label(r, "PETROL", pp + Vector3(0, 6.6, -0.12), 46, brand.darkened(0.3), "plate", 0.005).rotation.y = PI
	for k in 2:
		A.sbox(r, Vector3(1.9, 0.5, 0.22), pp + Vector3(0, 5.6 - k * 0.65, 0), "metal", Color(0.08, 0.08, 0.08), false, 0.5)
		B.label(r, ["REG  0.89", "SUPER  0.97"][k], pp + Vector3(0, 5.6 - k * 0.65, -0.12), 40, Color(0.95, 0.85, 0.5), "plate", 0.005).rotation.y = PI
	return [Vector3(-1.4, 1.2, kz + 0.2), Vector3(2.2, 1.0, kz + 1.4), Vector3(0, 0.5, -0.8), Vector3(-3.0, 1.0, kz + 1.4)]
