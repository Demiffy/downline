# The surface biomes past the desert and the snow (level.gd and line.gd call these): what grows,
# stands and rots in each. Every model is built from primitives like the rest of the world.
#   FOREST  oaks and birches over ferns, fallen timber, stumps with fungus, mossy rocks
#   SWAMP   black water in the hollows, buttressed cypress hung with moss, reeds and cattails,
#           boardwalks on stilts, shacks on piles, a sunk rowboat, lily pads
#   CITY    a dead town: storeys of brick and concrete with the windows out and the floors fallen
#           in, cracked streets, streetlamps, traffic lights, a bus, rubble, a billboard
# Line scenery and skylines for each are here too. Randomness comes only from the rng passed in.
extends RefCounted

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")

const WATER := -0.32       # the swamp's water level (its hollows fill to here)


# --- the forest ----------------------------------------------------------------------------------

## A broadleaf tree: a tapering trunk forking into limbs, the crown a mass of leaf clumps round
## their ends. Some are dead, some lean. Height 8-14 m.
static func oak(parent: Node, pos: Vector3, rng: RandomNumberGenerator, scale := 1.0) -> void:
	var r := Node3D.new()
	parent.add_child(r)
	r.position = pos
	r.rotation = Vector3(rng.randf_range(-0.05, 0.05), rng.randf() * TAU, rng.randf_range(-0.05, 0.05))
	var h := rng.randf_range(4.0, 6.0) * scale
	var bark := Color(0.62, 0.58, 0.52).darkened(rng.randf() * 0.2)
	var girth := rng.randf_range(0.28, 0.42) * scale
	A.seg(r, Vector3(0, -0.3, 0), Vector3(0, h, 0), girth, girth * 0.62, "bark", bark, 0.6)
	for k in 4:   # root flare
		var a := TAU * k / 4.0 + rng.randf() * 0.6
		A.seg(r, Vector3(cos(a) * girth * 0.4, 0.5, sin(a) * girth * 0.4), Vector3(cos(a) * girth * 2.2, -0.15, sin(a) * girth * 2.2), girth * 0.45, girth * 0.15, "bark", bark, 0.5)
	var b := StaticBody3D.new()   # (you walk round the trunk, not through it)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = girth
	cy.height = h
	cs.shape = cy
	b.add_child(cs)
	r.add_child(b)
	b.position.y = h / 2.0
	var dead := rng.randf() < 0.12
	var leaf := Color(0.48, 0.58, 0.36).lerp(Color(0.78, 0.6, 0.32), rng.randf() * 0.45 if rng.randf() < 0.25 else 0.0)
	var ends: Array[Vector3] = []
	for i in rng.randi_range(3, 5):   # limbs: out and up from the fork
		var a := TAU * i / 4.0 + rng.randf_range(-0.5, 0.5)
		var up := rng.randf_range(0.6, 1.1)
		var l := rng.randf_range(2.2, 3.6) * scale
		var from := Vector3(0, h * rng.randf_range(0.82, 1.0), 0)
		var to := from + Vector3(cos(a) * l * cos(up), l * sin(up), sin(a) * l * cos(up))
		A.seg(r, from, to, girth * 0.48, girth * 0.18, "bark", bark, 0.5)
		ends.append(to)
		var twig := to + Vector3(cos(a + 0.8), 0.6, sin(a + 0.8)) * rng.randf_range(0.8, 1.4) * scale
		A.seg(r, to, twig, girth * 0.16, girth * 0.06, "bark", bark, 0.3)
		if dead:
			continue
		ends.append(twig)
	if dead:
		return
	var mid := Vector3.ZERO   # the crown: a dark heart and lighter clumps round every limb's end
	for e in ends:
		mid += e
	mid /= maxf(ends.size(), 1)
	A.sphere(r, 2.3 * scale, mid + Vector3(0, 0.4, 0) * scale, "foliage", leaf.darkened(0.35), 0.0, 0.85)
	for e in ends:
		for c in rng.randi_range(3, 4):
			var rad := rng.randf_range(1.1, 1.9) * scale
			var off := Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.4, 0.9), rng.randf_range(-1.2, 1.2)) * scale
			var s := A.sphere(r, rad, e + off, "foliage", leaf.darkened(rng.randf() * 0.3), 0.0, rng.randf_range(0.85, 1.0))
			s.rotation = Vector3(rng.randf() * 0.4, rng.randf() * TAU, rng.randf() * 0.4)


## A birch: a slim white trunk with black scars, a light airy crown.
static func birch(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var r := Node3D.new()
	parent.add_child(r)
	r.position = pos
	r.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.08, 0.08))
	var h := rng.randf_range(7.0, 11.0)
	A.seg(r, Vector3(0, -0.2, 0), Vector3(0, h, 0), 0.16, 0.06, "cream", Color(0.88, 0.86, 0.8), 0.6)
	for i in int(h * 1.6):   # the black marks
		var y := rng.randf_range(0.3, h * 0.8)
		var a := rng.randf() * TAU
		var w := lerpf(0.16, 0.06, y / h)
		A.box(r, Vector3(rng.randf_range(0.06, 0.14), 0.03, 0.02), Vector3(cos(a) * w, y, sin(a) * w), "metal", Color(0.08, 0.08, 0.08), false, 0.2, Vector3(0, -a, 0))
	var leaf := Color(0.75, 0.82, 0.5).lerp(Color(0.95, 0.8, 0.35), rng.randf() * 0.4)
	for i in rng.randi_range(5, 8):
		var y := rng.randf_range(h * 0.5, h * 1.02)
		var a := rng.randf() * TAU
		var o := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.3, 1.3)
		A.seg(r, Vector3(0, y - 0.8, 0), o + Vector3(0, y, 0), 0.04, 0.015, "cream", Color(0.7, 0.68, 0.62), 0.3)
		A.sphere(r, rng.randf_range(0.8, 1.3), o + Vector3(0, y + 0.2, 0), "foliage", leaf, 0.0, rng.randf_range(0.7, 1.0))


## A fern: fronds arching out from the middle, each a stem with leaflets down it.
static func fern(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var c := Color(0.55, 0.72, 0.4).lerp(Color(0.8, 0.7, 0.4), rng.randf() * 0.3)
	var n := rng.randi_range(6, 10)
	var size := rng.randf_range(0.6, 1.1)
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var fr := Node3D.new()
		parent.add_child(fr)
		fr.position = pos
		fr.rotation = Vector3(-rng.randf_range(0.5, 0.9), a, 0)
		for k in 6:   # the frond: a narrowing strip of leaflets, curling down at the tip
			var t := k / 6.0
			A.box(fr, Vector3(lerpf(0.34, 0.08, t) * size, 0.01, 0.16 * size), Vector3(0, -t * t * 0.25 * size, t * size), "leaf", c, false, 0.3, Vector3(t * 0.5, 0, 0))


## A fallen trunk: bark, moss along its top, broken branch stubs, the root plate torn up at one end.
static func fallen_log(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := A.root(parent, pos, rot_y)
	var l := rng.randf_range(5.0, 9.0)
	var rad := rng.randf_range(0.3, 0.5)
	A.cyl(r, rad, l, Vector3(0, rad * 0.8, 0), "bark", Color(0.55, 0.5, 0.44), true, "x")
	A.box(r, Vector3(l * 0.8, 0.06, rad * 1.2), Vector3(0, rad * 1.72, 0), "moss", Color(0.85, 1.0, 0.75), false, 0.5)
	for i in rng.randi_range(2, 4):
		var x := rng.randf_range(-l * 0.35, l * 0.4)
		var a := rng.randf_range(0.3, 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)
		A.seg(r, Vector3(x, rad, 0), Vector3(x + 0.4, rad + cos(a) * 0.9, sin(a) * 0.9), rad * 0.25, rad * 0.1, "bark", Color(0.5, 0.45, 0.4), 0.3)
	var plate := A.cyl(r, rad * 3.2, 0.35, Vector3(-l / 2.0 - 0.1, rad * 2.4, 0), "dirt", Color(0.9, 0.85, 0.8), false, "x")
	plate.rotation.y = rng.randf_range(-0.2, 0.2)
	for i in 6:   # roots sticking out of it
		var a := TAU * i / 6.0
		A.seg(r, Vector3(-l / 2.0 - 0.2, rad * 2.4 + sin(a) * rad * 2.0, cos(a) * rad * 2.0), Vector3(-l / 2.0 - 0.6, rad * 2.4 + sin(a) * rad * 3.6, cos(a) * rad * 3.6), 0.06, 0.02, "bark", Color(0.45, 0.4, 0.35), 0.3)
	if rng.randf() < 0.6:
		_fungus(r, Vector3(rng.randf_range(-l * 0.3, l * 0.3), rad * 0.6, rad * 0.95), rng, 3)


## A cut or snapped stump, its rings on top, fungus at its foot.
static func stump(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var rad := rng.randf_range(0.3, 0.55)
	var h := rng.randf_range(0.3, 0.9)
	A.cyl(parent, rad, h, pos + Vector3(0, h / 2.0 - 0.05, 0), "bark", Color(0.55, 0.5, 0.45), true)
	A.cyl(parent, rad * 0.92, 0.02, pos + Vector3(0, h - 0.04, 0), "wood", Color(0.85, 0.72, 0.55), false)
	for k in 3:
		A.ring(parent, rad * (0.25 + k * 0.22) + 0.01, rad * (0.25 + k * 0.22), pos + Vector3(0, h - 0.025, 0), "wood", Color(0.55, 0.42, 0.3))
	_fungus(parent, pos + Vector3(rad, 0.05, 0).rotated(Vector3.UP, rng.randf() * TAU), rng, rng.randi_range(2, 5))


## Toadstools: pale stems under red or brown caps.
static func _fungus(parent: Node, at: Vector3, rng: RandomNumberGenerator, n: int) -> void:
	var red := rng.randf() < 0.4
	for i in n:
		var p := at + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var h := rng.randf_range(0.06, 0.16)
		A.cyl(parent, 0.012, h, p + Vector3(0, h / 2.0, 0), "cream", Color(0.92, 0.88, 0.8))
		var cap := A.sphere(parent, rng.randf_range(0.03, 0.06), p + Vector3(0, h, 0), "plastic", Color(0.75, 0.12, 0.08) if red else Color(0.55, 0.4, 0.25), 0.0, 0.45)
		cap.rotation.z = rng.randf_range(-0.2, 0.2)


## A low shrub: a few leaf clumps on the ground.
static func bush(parent: Node, pos: Vector3, rng: RandomNumberGenerator, tint := Color(0.6, 0.7, 0.45)) -> void:
	for i in rng.randi_range(3, 5):
		A.sphere(parent, rng.randf_range(0.4, 0.8), pos + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.2, 0.5), rng.randf_range(-0.6, 0.6)), "foliage", tint.darkened(rng.randf() * 0.2), 0.0, 0.7)


# --- the swamp -----------------------------------------------------------------------------------

## A bald cypress: a flared, fluted base standing in the water, a tall straight trunk, flat
## branches with moss hanging off them in grey-green beards, knees poking up round it.
static func cypress(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var r := Node3D.new()
	parent.add_child(r)
	r.position = pos
	r.rotation.y = rng.randf() * TAU
	var h := rng.randf_range(8.0, 13.0)
	var bark := Color(0.5, 0.46, 0.42)
	A.seg(r, Vector3(0, -0.4, 0), Vector3(0, h, 0), 0.32, 0.12, "bark", bark, 0.6)
	for k in 6:   # the buttress flutes
		var a := TAU * k / 6.0 + rng.randf() * 0.4
		A.seg(r, Vector3(cos(a) * 0.15, 1.6, sin(a) * 0.15), Vector3(cos(a) * 1.0, -0.3, sin(a) * 1.0), 0.22, 0.1, "bark", bark.darkened(0.1), 0.5)
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.45
	cy.height = h
	cs.shape = cy
	b.add_child(cs)
	r.add_child(b)
	b.position.y = h / 2.0
	for k in rng.randi_range(3, 7):   # knees
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.3, 2.6)
		var kh := rng.randf_range(0.25, 0.6)
		A.seg(r, Vector3(cos(a) * d, -0.3, sin(a) * d), Vector3(cos(a) * d, kh, sin(a) * d), 0.12, 0.04, "bark", bark, 0.3)
	var moss := Color(0.62, 0.66, 0.52)
	var dead := rng.randf() < 0.35
	for i in rng.randi_range(4, 7):
		var y := rng.randf_range(h * 0.45, h * 0.95)
		var a := rng.randf() * TAU
		var l := rng.randf_range(1.4, 3.2)
		var tip := Vector3(cos(a) * l, y + rng.randf_range(-0.2, 0.5), sin(a) * l)
		A.seg(r, Vector3(0, y, 0), tip, 0.08, 0.025, "bark", bark, 0.3)
		for k in rng.randi_range(2, 5):   # beards of moss hanging off the branch
			var p := Vector3(0, y, 0).lerp(tip, rng.randf_range(0.3, 1.0))
			var hl := rng.randf_range(0.6, 1.8)
			A.box(r, Vector3(0.12, hl, 0.04), p - Vector3(0, hl / 2.0, 0), "leaf", moss, false, 0.3, Vector3(0, rng.randf() * TAU, rng.randf_range(-0.1, 0.1)))
		if not dead:   # feathery tufts along the branch, not a lid on it
			for k in 3:
				var tp: Vector3 = Vector3(0, y, 0).lerp(tip, 0.45 + k * 0.27) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, 0.4), rng.randf_range(-0.3, 0.3))
				A.sphere(r, rng.randf_range(0.45, 0.75), tp, "foliage", Color(0.42, 0.5, 0.32).darkened(rng.randf() * 0.25), 0.0, rng.randf_range(0.7, 0.95))
	if not dead:   # and a ragged crown at the top
		for k in 4:
			A.sphere(r, rng.randf_range(0.6, 1.0), Vector3(rng.randf_range(-0.8, 0.8), h + rng.randf_range(-0.6, 0.4), rng.randf_range(-0.8, 0.8)), "foliage", Color(0.4, 0.48, 0.3).darkened(rng.randf() * 0.25), 0.0, 0.8)


## A clump of reeds, some with cattail heads, leaning every way.
static func reeds(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(12, 22)
	for i in n:
		var p := pos + Vector3(rng.randf_range(-0.7, 0.7), -0.25, rng.randf_range(-0.7, 0.7))
		var h := rng.randf_range(1.0, 2.2)
		var lean := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		var top := p + Vector3(0, h, 0) + lean
		A.seg(parent, p, top, 0.018, 0.006, "leaf", Color(0.75, 0.75, 0.45).lerp(Color(0.6, 0.66, 0.35), rng.randf()), 0.2)
		if rng.randf() < 0.3:   # a cattail
			var hd := p.lerp(top, 0.82)
			A.cyl(parent, 0.035, 0.22, hd, "wood", Color(0.5, 0.32, 0.18))


## A boardwalk from a to b: planks across two stringers on posts driven into the mud, a few
## planks gone, a handrail along one side for a stretch. Walkable (`top` is the deck's height).
static func boardwalk(parent: Node, a: Vector3, b: Vector3, top: float, rng: RandomNumberGenerator, ground: Callable) -> void:
	var d := b - a
	d.y = 0.0
	var l := d.length()
	if l < 1.0:
		return
	var r := A.root(parent, Vector3(a.x, top, a.z), atan2(d.x, d.z))
	var wood := Color(0.7, 0.62, 0.52)
	var deck := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.5, 0.1, l)
	cs.shape = bs
	deck.add_child(cs)
	r.add_child(deck)
	deck.position = Vector3(0, -0.05, l / 2.0)
	for s in [-0.6, 0.6]:
		A.box(r, Vector3(0.12, 0.16, l), Vector3(s, -0.16, l / 2.0), "wood", wood.darkened(0.25), false, 0.6)
	var z := 0.15
	while z < l:
		if rng.randf() > 0.06:
			A.box(r, Vector3(1.5 + rng.randf_range(-0.05, 0.05), 0.05, 0.24), Vector3(rng.randf_range(-0.04, 0.04), -0.025, z), "wood", wood.darkened(rng.randf() * 0.25), false, 0.4, Vector3(0, rng.randf_range(-0.03, 0.03), 0))
		z += 0.27
	var pz := 0.0
	while pz <= l:
		for s in [-0.66, 0.66]:
			var wp: Vector3 = r.position + Vector3(s, 0, pz).rotated(Vector3.UP, r.rotation.y)
			var gy: float = ground.call(wp.x, wp.z) - 0.5
			A.cyl(r, 0.08, top - gy, Vector3(s, -(top - gy) / 2.0 - 0.1, pz), "wood", wood.darkened(0.35), false)
		pz += 2.2
	if l > 6.0 and rng.randf() < 0.7:   # a handrail for a stretch
		var z0 := rng.randf_range(0.0, l * 0.4)
		var z1 := minf(z0 + rng.randf_range(5.0, 10.0), l)
		var x := 0.66 * (1.0 if rng.randf() < 0.5 else -1.0)
		var q := z0
		while q <= z1:
			A.box(r, Vector3(0.07, 0.95, 0.07), Vector3(x, 0.47, q), "wood", wood.darkened(0.3), false, 0.4)
			q += 1.8
		A.box(r, Vector3(0.06, 0.06, z1 - z0), Vector3(x, 0.95, (z0 + z1) / 2.0), "wood", wood.darkened(0.2), false, 0.4)


## A shack up on piles over the water: posts, a platform, a tin shed on it, a ladder down.
static func stilt_shack(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var lift := 1.4
	var r := A.root(parent, pos, rot_y)
	var wood := Color(0.62, 0.55, 0.48)
	for x in [-2.6, 0.0, 2.6]:
		for z in [-2.1, 0.0, 2.1]:
			A.cyl(r, 0.1, lift + 0.8, Vector3(x, (lift - 0.8) / 2.0, z), "wood", wood.darkened(0.3), x != 0.0 or z != 0.0)
	A.box(r, Vector3(6.4, 0.15, 5.2), Vector3(0, lift, 0), "wood", wood, true, 0.6)
	for s in [-1.0, 1.0]:   # a cross brace each side
		A.seg(r, Vector3(-2.6, -0.3, s * 2.1), Vector3(2.6, lift - 0.1, s * 2.1), 0.05, 0.05, "wood", wood.darkened(0.3))
	P.tin_shed(r, Vector3(0, lift + 0.08, 0), 0.0, rng)
	for i in 6:   # the ladder down off the end
		A.box(r, Vector3(0.6, 0.05, 0.06), Vector3(0, lift - 0.2 - i * 0.28, 2.75 + i * 0.06), "wood", wood.darkened(0.2), false, 0.3)
	for s in [-0.3, 0.3]:
		A.seg(r, Vector3(s, lift + 0.4, 2.7), Vector3(s, -0.4, 3.1), 0.035, 0.035, "wood", wood.darkened(0.3))


## A rowboat half sunk at the water's edge: a planked hull, a thwart, an oar.
static func rowboat(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := A.root(parent, pos, rot_y)
	r.rotation.x = rng.randf_range(0.1, 0.25)
	r.rotation.z = rng.randf_range(-0.2, 0.2)
	var hull := Color(0.45, 0.55, 0.5).lerp(Color(0.6, 0.3, 0.2), rng.randf())
	A.box(r, Vector3(1.0, 0.06, 3.0), Vector3(0, 0, 0), "wood", hull.darkened(0.3), false, 0.5)
	for s in [-1.0, 1.0]:
		A.box(r, Vector3(0.05, 0.42, 3.1), Vector3(s * 0.62, 0.17, 0), "wood", hull, false, 0.5, Vector3(0, 0, s * 0.35))
	A.prism(r, Vector3(1.3, 0.45, 0.6), Vector3(0, 0.18, 1.75), "wood", hull, Vector3(PI / 2, 0, 0), 0.5)   # the bow
	A.box(r, Vector3(1.24, 0.42, 0.05), Vector3(0, 0.18, -1.52), "wood", hull, false, 0.5)   # transom
	A.box(r, Vector3(1.1, 0.04, 0.22), Vector3(0, 0.25, 0.2), "wood", Color(0.6, 0.5, 0.4), false, 0.4)
	A.seg(r, Vector3(-0.4, 0.3, -0.6), Vector3(0.9, 0.05, 1.3), 0.025, 0.025, "wood", Color(0.62, 0.52, 0.4))


## Black water over the hollows: one big sheet at WATER, dark and glossy, with lily pads and
## scum on it here and there.
static func water(parent: Node, size: float, rng: RandomNumberGenerator, ground: Callable) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	var m := StandardMaterial3D.new()   # (murky: it shows the sky dully, not as a mirror)
	m.albedo_color = Color(0.035, 0.045, 0.03)
	m.roughness = 0.32
	m.metallic_specular = 0.35
	mi.material_override = m
	mi.position.y = WATER
	mi.set_meta("live", true)
	parent.add_child(mi)
	for i in 260:   # pads and scum where it's wet
		var p := Vector3(rng.randf_range(-size / 2.0, size / 2.0), 0, rng.randf_range(-size / 2.0, size / 2.0))
		if ground.call(p.x, p.z) > WATER - 0.05:
			continue
		if rng.randf() < 0.65:
			var pad := A.cyl(parent, rng.randf_range(0.12, 0.3), 0.01, Vector3(p.x, WATER + 0.006, p.z), "leaf", Color(0.55, 0.7, 0.38), false)
			pad.scale.z = rng.randf_range(0.8, 1.0)
		else:
			A.box(parent, Vector3(rng.randf_range(0.4, 1.4), 0.004, rng.randf_range(0.3, 1.0)), Vector3(p.x, WATER + 0.004, p.z), "moss", Color(0.75, 0.85, 0.55), false, 0.8, Vector3(0, rng.randf() * TAU, 0))


# --- the dead town -------------------------------------------------------------------------------

## A ruined block: two to five storeys of brick or concrete, the windows empty (some boarded),
## floors showing through, the top broken off in steps, rubble heaped at its foot, rebar.
## `w`/`d` the footprint; returns nothing, solid where it stands.
static func ruin_block(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator, w := 0.0, d := 0.0, floors := 0) -> void:
	var r := A.root(parent, pos, rot_y)
	if w <= 0.0:
		w = rng.randf_range(9.0, 15.0)
	if d <= 0.0:
		d = rng.randf_range(7.0, 11.0)
	if floors <= 0:
		floors = rng.randi_range(2, 5)
	var fh := 3.2
	var brick := rng.randf() < 0.55
	var kind := "brick" if brick else "concrete"
	var tint := Color.WHITE if brick else Color(0.82, 0.8, 0.76).darkened(rng.randf() * 0.15)
	var trim := Color(0.62, 0.6, 0.56)
	# Each wall, storey by storey, the top storeys broken back: a broken wall's top is ragged.
	var walls := [[-w / 2.0, w / 2.0, -d / 2.0, true], [-w / 2.0, w / 2.0, d / 2.0, true], [-d / 2.0, d / 2.0, -w / 2.0, false], [-d / 2.0, d / 2.0, w / 2.0, false]]
	var lost := rng.randi_range(0, 3)   # a corner gone from the top storeys down
	for wi in walls.size():
		var wl: Array = walls[wi]
		var span: float = wl[1] - wl[0]
		var bays := maxi(int(span / 3.0), 2)
		for f in floors:
			var top_broken := f >= floors - 1 - (1 if wi == lost else 0)
			var holes := []
			for k in bays:
				var c: float = wl[0] + span * (k + 0.5) / bays
				if f == 0 and k == bays / 2 and wi == 0:
					holes.append([c, 1.6, 0.0, 2.4])   # the street door
				else:
					holes.append([c, 1.2, 0.9, 2.4])
			var h := fh
			if top_broken and wi == lost:
				h = rng.randf_range(0.6, 1.8)
			A.wall(r, wl[0], wl[1], wl[2], h, 0.3, holes, kind, tint, wl[3], f * fh, f == 0, 1.5)
			if f > 0:   # the floor line: a band of stone
				var band := Vector3(span + 0.06, 0.18, 0.36) if wl[3] else Vector3(0.36, 0.18, span + 0.06)
				var bp := Vector3((wl[0] + wl[1]) / 2.0, f * fh, wl[2]) if wl[3] else Vector3(wl[2], f * fh, (wl[0] + wl[1]) / 2.0)
				A.box(r, band, bp, "concrete", trim, false, 1.0)
			for k in bays:   # sills, and boards over some of the holes
				var c: float = wl[0] + span * (k + 0.5) / bays
				if f == 0 and k == bays / 2 and wi == 0:
					continue
				var out := 0.2 * signf(wl[2])
				var sp := Vector3(c, f * fh + 0.88, wl[2] + out) if wl[3] else Vector3(wl[2] + out, f * fh + 0.88, c)
				A.box(r, Vector3(1.35, 0.08, 0.12) if wl[3] else Vector3(0.12, 0.08, 1.35), sp, "concrete", trim, false, 0.8)
				if f == 0 and rng.randf() < 0.45:
					for b in rng.randi_range(2, 3):
						var bpos := Vector3(c, f * fh + 1.2 + b * 0.45, wl[2] + out * 0.8) if wl[3] else Vector3(wl[2] + out * 0.8, f * fh + 1.2 + b * 0.45, c)
						A.box(r, Vector3(1.4, 0.18, 0.04) if wl[3] else Vector3(0.04, 0.18, 1.4), bpos, "wood", Color(0.6, 0.52, 0.42), false, 0.5, Vector3(0, 0, rng.randf_range(-0.12, 0.12)) if wl[3] else Vector3(rng.randf_range(-0.12, 0.12), 0, 0))
	# Floors inside: slabs, some of them fallen in at a slant.
	for f in range(1, floors):
		if rng.randf() < 0.3:
			A.box(r, Vector3(w * 0.5, 0.22, d - 0.6), Vector3(-w * 0.2, f * fh - 1.2, 0), "concrete", trim.darkened(0.2), false, 1.0, Vector3(0, 0, 0.45))
		else:
			A.box(r, Vector3(w - 0.6, 0.22, d - 0.6), Vector3(0, f * fh, 0), "concrete", trim.darkened(0.2), false, 1.0)
	A.box(r, Vector3(w - 0.6, 0.08, d - 0.6), Vector3(0, 0.04, 0), "concrete", Color(0.5, 0.48, 0.45), true, 1.0)
	# A cornice on what's left of the top, rebar sticking up from the broken corner.
	A.box(r, Vector3(w + 0.4, 0.3, 0.45), Vector3(0, floors * fh - (fh if lost == 0 else 0.0) + 0.1, -d / 2.0 - 0.05), "concrete", trim, false, 1.0)
	for i in rng.randi_range(4, 8):
		var x := rng.randf_range(-w / 2.0, w / 2.0)
		var y := (floors - 1) * fh + rng.randf_range(0.5, 1.6)
		A.seg(r, Vector3(x, y, -d / 2.0), Vector3(x + rng.randf_range(-0.3, 0.3), y + rng.randf_range(0.6, 1.4), -d / 2.0 + rng.randf_range(-0.3, 0.3)), 0.015, 0.012, "rust", Color.WHITE, 0.3)
	for i in rng.randi_range(2, 4):   # rubble at its foot
		var a := rng.randf() * TAU
		rubble(r, Vector3(cos(a) * (w / 2.0 + 1.2), 0, sin(a) * (d / 2.0 + 1.2)), rng, rng.randf_range(1.0, 2.2))
	if rng.randf() < 0.5:   # a painted sign on the front, faded
		var signs := ["HARDWARE", "PHARMACY", "HOTEL", "BANK", "DRY GOODS", "CINEMA", "POST OFFICE", "GROCER", "BAR"]
		B.label(r, signs[rng.randi() % signs.size()], Vector3(0, fh * 0.94, -d / 2.0 - 0.16), 70, Color(0.88, 0.84, 0.72, 0.85), "stencil", 0.012).rotation.y = PI


## A heap of broken concrete and brick, rebar through it.
static func rubble(parent: Node, pos: Vector3, rng: RandomNumberGenerator, size := 1.5) -> void:
	A.sphere(parent, size, pos - Vector3(0, size * 0.55, 0), "concrete", Color(0.6, 0.58, 0.54), 0.0, 0.55)
	for i in int(size * 7):
		var p := pos + Vector3(rng.randf_range(-size, size), rng.randf_range(-0.1, size * 0.35), rng.randf_range(-size, size))
		var k: String = ["concrete", "brick", "concrete", "rust"][rng.randi() % 4]
		A.box(parent, Vector3(rng.randf_range(0.2, 0.7), rng.randf_range(0.1, 0.35), rng.randf_range(0.2, 0.6)), p, k, Color(0.8, 0.78, 0.74), false, 0.6, Vector3(rng.randf(), rng.randf() * 3.0, rng.randf()))
	for i in 3:
		var p := pos + Vector3(rng.randf_range(-size, size) * 0.6, 0, rng.randf_range(-size, size) * 0.6)
		A.seg(parent, p, p + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.5, 1.2), rng.randf_range(-0.6, 0.6)), 0.015, 0.012, "rust", Color.WHITE, 0.3)


## A street from a to b: cracked asphalt, kerbs and a pavement each side, the centre line worn off.
static func street(parent: Node, a: Vector3, b: Vector3, rng: RandomNumberGenerator, width := 7.0) -> void:
	var d := b - a
	d.y = 0.0
	var l := d.length()
	var r := A.root(parent, Vector3(a.x, a.y, a.z), atan2(d.x, d.z))
	A.box(r, Vector3(width, 0.06, l), Vector3(0, 0.03, l / 2.0), "asphalt", Color(0.95, 0.95, 0.95), false, 2.0)
	for s in [-1.0, 1.0]:
		A.box(r, Vector3(0.25, 0.16, l), Vector3(s * (width / 2.0 + 0.12), 0.08, l / 2.0), "concrete", Color(0.7, 0.68, 0.64), false, 1.0)
		A.box(r, Vector3(2.0, 0.12, l), Vector3(s * (width / 2.0 + 1.25), 0.06, l / 2.0), "tiles", Color(0.62, 0.6, 0.56), false, 1.5)
	var z := 1.0
	while z < l - 1.0:   # dashes down the middle, mostly worn away
		if rng.randf() < 0.55:
			A.box(r, Vector3(0.14, 0.005, 1.6), Vector3(0, 0.063, z), "cream", Color(0.85, 0.8, 0.6), false, 1.0)
		z += 3.2
	for i in int(l / 6.0):   # cracks and weeds
		A.box(r, Vector3(rng.randf_range(0.04, 0.08), 0.004, rng.randf_range(0.8, 2.5)), Vector3(rng.randf_range(-width / 2.0, width / 2.0), 0.062, rng.randf_range(0, l)), "metal", Color(0.06, 0.06, 0.06), false, 0.5, Vector3(0, rng.randf_range(-1, 1), 0))
		if rng.randf() < 0.5:
			bush(r, Vector3(s_side(rng) * (width / 2.0 + 0.3), 0, rng.randf_range(0, l)), rng, Color(0.62, 0.66, 0.42))


static func s_side(rng: RandomNumberGenerator) -> float:
	return 1.0 if rng.randf() < 0.5 else -1.0


## A streetlamp: a fluted cast pole, a swan-neck arm, the lantern dark (the glass gone in some).
static func streetlamp(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := A.root(parent, pos, rot_y)
	var iron := Color(0.24, 0.27, 0.25)
	r.rotation.z = rng.randf_range(-0.05, 0.05) if rng.randf() < 0.3 else 0.0
	A.cyl(r, 0.2, 0.6, Vector3(0, 0.3, 0), "metal", iron, true)
	A.seg(r, Vector3(0, 0.6, 0), Vector3(0, 4.8, 0), 0.09, 0.06, "metal", iron, 0.5)
	A.seg(r, Vector3(0, 4.7, 0), Vector3(0.5, 5.3, 0), 0.05, 0.045, "metal", iron, 0.4)
	A.seg(r, Vector3(0.5, 5.3, 0), Vector3(1.1, 5.15, 0), 0.045, 0.04, "metal", iron, 0.4)
	A.cyl(r, 0.22, 0.12, Vector3(1.15, 5.05, 0), "metal", iron, false, "y", 0.08)
	A.box(r, Vector3(0.24, 0.3, 0.24), Vector3(1.15, 4.84, 0), "metal", Color(0.3, 0.32, 0.3) if rng.randf() < 0.5 else Color(0.75, 0.72, 0.6), false, 0.4)


## A traffic light on its post, bent, its three lamps dead.
static func traffic_light(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := A.root(parent, pos, rot_y)
	r.rotation.x = rng.randf_range(-0.12, 0.12)
	A.cyl(r, 0.07, 3.4, Vector3(0, 1.7, 0), "metal", Color(0.5, 0.52, 0.5), true)
	A.box(r, Vector3(0.36, 0.95, 0.3), Vector3(0, 3.3, -0.2), "metal", Color(0.22, 0.24, 0.2), false, 0.4)
	for i in 3:
		var c: Color = [Color(0.5, 0.1, 0.08), Color(0.5, 0.36, 0.08), Color(0.12, 0.4, 0.15)][i]
		A.cyl(r, 0.1, 0.03, Vector3(0, 3.6 - i * 0.3, -0.36), "plastic", c, false, "z")
		A.cyl(r, 0.13, 0.12, Vector3(0, 3.66 - i * 0.3, -0.42), "metal", Color(0.2, 0.22, 0.18), false, "z", 0.11)   # its visor


## A bus off its wheels: a long rusted body with the windows out, the doors open, a destination
## board over the windscreen.
static func bus(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := A.root(parent, pos, rot_y, Vector3(2.5, 3.0, 10.5))
	r.rotation.z = rng.randf_range(-0.08, 0.08)
	var paint: Color = [Color(0.75, 0.6, 0.25), Color(0.6, 0.2, 0.15), Color(0.35, 0.45, 0.55)][rng.randi() % 3]
	A.box(r, Vector3(2.5, 1.1, 10.4), Vector3(0, 0.95, 0), "paint", paint, false, 1.0)
	A.box(r, Vector3(2.5, 0.25, 10.4), Vector3(0, 2.75, 0), "paint", paint.darkened(0.1), false, 1.0)
	A.box(r, Vector3(2.4, 0.12, 10.2), Vector3(0, 2.9, 0), "metal", Color(0.6, 0.6, 0.58), false, 1.0)
	for s in [-1.0, 1.0]:
		A.wall(r, -5.2, 5.2, s * 1.22, 1.35, 0.05, [[-3.9, 1.1, 0.1, 1.2], [-2.6, 1.1, 0.1, 1.2], [-1.3, 1.1, 0.1, 1.2], [0.0, 1.1, 0.1, 1.2], [1.3, 1.1, 0.1, 1.2], [2.6, 1.1, 0.1, 1.2], [3.9, 1.1, 0.1, 1.2]], "metal", paint.lightened(0.15), false, 1.5, false, 0.6)
	A.box(r, Vector3(2.4, 1.3, 0.06), Vector3(0, 2.1, -5.2), "metal", Color(0.1, 0.1, 0.1), false, 0.5)   # the empty windscreen
	A.box(r, Vector3(1.8, 0.28, 0.05), Vector3(0, 2.92, -5.22), "metal", Color(0.05, 0.05, 0.05), false, 0.5)
	B.label(r, "NOT IN SERVICE", Vector3(0, 2.92, -5.25), 40, Color(0.85, 0.6, 0.25), "plate", 0.004).rotation.y = PI
	A.box(r, Vector3(2.5, 1.3, 0.08), Vector3(0, 2.1, 5.2), "paint", paint, false, 1.0)
	A.box(r, Vector3(2.55, 0.3, 0.3), Vector3(0, 0.45, -5.25), "metal", Color(0.3, 0.3, 0.3), false, 0.5)   # bumper
	for z in [-3.6, 3.4]:   # wheels, the tyres flat
		for s in [-1.0, 1.0]:
			A.cyl(r, 0.5, 0.3, Vector3(s * 1.1, 0.4, z), "rubber", Color(0.5, 0.5, 0.5), false, "x")
	for i in 5:   # seats inside
		A.box(r, Vector3(0.9, 0.5, 0.4), Vector3(-0.6, 1.4, -3.5 + i * 1.6), "fabric_tint", Color(0.4, 0.2, 0.15), false, 0.4)
	A.box(r, Vector3(2.4, 0.06, 10.2), Vector3(0, 1.05, 0), "metal", Color(0.2, 0.2, 0.2), false, 1.0)


## A billboard on two posts with a faded advertisement.
static func billboard(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := A.root(parent, pos, rot_y)
	for x in [-2.6, 2.6]:
		A.box(r, Vector3(0.3, 6.5, 0.3), Vector3(x, 3.25, 0.2), "wood", Color(0.55, 0.5, 0.45), true, 0.8)
		A.seg(r, Vector3(x, 0, 1.4), Vector3(x, 3.5, 0.3), 0.07, 0.07, "wood", Color(0.5, 0.45, 0.4))
	A.box(r, Vector3(6.8, 3.4, 0.12), Vector3(0, 5.0, 0.0), "paper", Color(0.9, 0.85, 0.72), false, 2.0)
	var ads := [["THE BUREAU NEEDS YOU", "RECLAIM  ·  RENEW  ·  REWARD"], ["SUNSHINE COLA", "TASTE THE FUTURE"], ["ELECTRIFY YOUR HOME", "MODEL 7 APPLIANCES"], ["VISIT THE COAST", "BY RAIL, OF COURSE"]]
	var ad: Array = ads[rng.randi() % ads.size()]
	A.box(r, Vector3(6.4, 0.9, 0.01), Vector3(0, 4.3, -0.07), "cream", [Color(0.7, 0.2, 0.15), Color(0.2, 0.35, 0.5), Color(0.75, 0.55, 0.2)][rng.randi() % 3], false, 1.0)
	B.label(r, ad[0], Vector3(0, 5.6, -0.07), 90, Color(0.18, 0.14, 0.12), "plate", 0.0075).rotation.y = PI
	B.label(r, ad[1], Vector3(0, 4.3, -0.08), 60, Color(0.95, 0.9, 0.8), "plate", 0.0065).rotation.y = PI
	for i in rng.randi_range(2, 5):   # torn off in strips
		A.box(r, Vector3(rng.randf_range(0.4, 1.4), rng.randf_range(0.6, 2.0), 0.012), Vector3(rng.randf_range(-3, 3), rng.randf_range(3.8, 6.2), -0.075), "wood", Color(0.45, 0.4, 0.35), false, 0.5)
	A.box(r, Vector3(7.0, 0.2, 0.2), Vector3(0, 6.75, 0), "wood", Color(0.5, 0.45, 0.4), false, 0.5)
	A.box(r, Vector3(7.0, 0.15, 0.8), Vector3(0, 3.25, -0.3), "grate", Color(0.6, 0.6, 0.58), false, 0.5)   # the catwalk


# --- skylines --------------------------------------------------------------------------------------

## A wooded ridge far off: a long low hump of dark trees, its edge broken by crowns.
static func tree_ridge(parent: Node, pos: Vector3, rng: RandomNumberGenerator, tint := Color(0.3, 0.38, 0.3)) -> void:
	var l := rng.randf_range(40.0, 90.0)
	var h := rng.randf_range(10.0, 22.0)
	var hill := A.sphere(parent, 0.5, pos, "foliage", tint, 0.0, 1.0)
	hill.scale = Vector3(l, h * 2.0, l * 0.5)
	hill.rotation.y = rng.randf() * TAU
	for i in int(l / 6.0):
		var a := rng.randf_range(-0.5, 0.5)
		var p := pos + Vector3(a * l, h * (1.0 - a * a * 3.0) * 0.85, rng.randf_range(-l * 0.15, l * 0.15)).rotated(Vector3.UP, hill.rotation.y)
		A.sphere(parent, rng.randf_range(3.0, 6.0), p, "foliage", tint.darkened(rng.randf() * 0.2), 0.0, 0.8)


## A tower block far off, broken at the top, its windows dark rows.
static func tower(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(10.0, 18.0)
	var h := rng.randf_range(25.0, 60.0)
	var r := A.root(parent, pos, rng.randf() * TAU)
	var c := Color(0.5, 0.49, 0.47).darkened(rng.randf() * 0.25)
	A.box(r, Vector3(w, h, w * 0.8), Vector3(0, h / 2.0, 0), "concrete", c, false, 4.0)
	var fl := int(h / 3.5)
	for f in fl:   # rows of dark windows all round, some floors gutted black right through
		var gutted := rng.randf() < 0.15
		for sd in [-1.0, 1.0]:
			A.box(r, Vector3(w * 0.9, 1.3 if not gutted else 2.6, 0.05), Vector3(0, 1.8 + f * 3.5, sd * (w * 0.4 + 0.03)), "metal", Color(0.06, 0.06, 0.06), false, 2.0)
			A.box(r, Vector3(0.05, 1.3 if not gutted else 2.6, w * 0.7), Vector3(sd * (w / 2.0 + 0.03), 1.8 + f * 3.5, 0), "metal", Color(0.06, 0.06, 0.06), false, 2.0)
	for i in rng.randi_range(2, 4):   # the broken crown: stubs of the top floors
		A.box(r, Vector3(rng.randf_range(2.0, w * 0.5), rng.randf_range(2.0, 7.0), rng.randf_range(2.0, w * 0.4)), Vector3(rng.randf_range(-w / 3.0, w / 3.0), h + 1.5, rng.randf_range(-w / 4.0, w / 4.0)), "concrete", c, false, 2.0)
