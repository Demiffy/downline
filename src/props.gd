# Furniture + outdoor set dressing, all built from primitives (see art.gd for textures).
# Every builder takes (parent, position, rotation_y, rng) where it makes sense. "Solid" props get one
# simple collision box; small decor is visual only.
extends RefCounted

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")

const POSTERS := ["QUOTA IS QUOTA", "SAFETY FIRST*\n*after quota", "WATCH YOUR STEP", "NO LOITERING", "REPORT\nANOMALIES",
	"SMILE :)", "EYES DOWN\nKEEP WORKING", "YOU HAVE BEEN\nFACTORED IN", "LOST TIME\nIS LOST SCRAP", "DO NOT FEED\nTHE BARRELS"]
const SIGNS := ["SECTOR 7", "B-3", "MAINTENANCE", "STORAGE", "STAFF ONLY", "AUTHORIZED\nPERSONNEL ONLY", "LAB 2", "DANGER", "HIGH VOLTAGE"]


static func _root(parent: Node, pos: Vector3, rot_y: float, solid_size := Vector3.ZERO) -> Node3D:
	var r: Node3D = StaticBody3D.new() if solid_size != Vector3.ZERO else Node3D.new()
	parent.add_child(r)
	r.position = pos
	r.rotation.y = rot_y
	if solid_size != Vector3.ZERO:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = solid_size
		cs.shape = sh
		cs.position.y = solid_size.y / 2
		r.add_child(cs)
	return r


static func _blink(node: MeshInstance3D, c: Color, secs: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	node.material_override = m
	node.set_meta("live", true)
	var tw := node.create_tween().set_loops()
	tw.tween_property(m, "emission_energy_multiplier", 6.0, secs * 0.5)
	tw.tween_property(m, "emission_energy_multiplier", 0.2, secs * 0.5)


# --- interior furniture -------------------------------------------------------------------

static func chair(parent: Node, pos: Vector3, rot_y: float, kind := "metal") -> void:
	var r := _root(parent, pos, rot_y, Vector3(0.45, 0.9, 0.45))
	var frame := Color(0.28, 0.28, 0.3)
	var pads := [Color(0.35, 0.4, 0.55), Color(0.55, 0.3, 0.25), Color(0.3, 0.45, 0.35), Color(0.5, 0.48, 0.42)]
	var pad: Color = pads[randi() % pads.size()]
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			A.seg(r, Vector3(sx * 0.2, 0.0, sz * 0.2), Vector3(sx * 0.18, 0.44, sz * 0.18), 0.013, 0.013, "metal", frame)
			A.cyl(r, 0.018, 0.02, Vector3(sx * 0.2, 0.01, sz * 0.2), "rubber", Color.WHITE)
		A.seg(r, Vector3(sx * 0.195, 0.12, -0.19), Vector3(sx * 0.195, 0.12, 0.19), 0.009, 0.009, "metal", frame)
		A.seg(r, Vector3(sx * 0.18, 0.44, 0.18), Vector3(sx * 0.18, 0.92, 0.23), 0.012, 0.012, "metal", frame)
	A.box(r, Vector3(0.42, 0.02, 0.4), Vector3(0, 0.445, 0), "metal", frame, false, 0.5)
	A.box(r, Vector3(0.44, 0.05, 0.42), Vector3(0, 0.48, -0.005), "canvas" if kind == "metal" else kind, pad, false, 0.3)
	var back := A.box(r, Vector3(0.4, 0.25, 0.035), Vector3(0, 0.78, 0.215), "canvas" if kind == "metal" else kind, pad, false, 0.3)
	back.rotation.x = -0.1
	if randf() < 0.3:   # split seat
		A.box(r, Vector3(0.12, 0.052, 0.08), Vector3(0.08, 0.481, -0.05), "cream", Color(0.85, 0.8, 0.65), false, 0.2)


static func table(parent: Node, pos: Vector3, rot_y: float, w := 1.6, d := 0.9, kind := "wood") -> Node3D:
	var r := _root(parent, pos, rot_y, Vector3(w, 0.78, d))
	A.box(r, Vector3(w, 0.045, d), Vector3(0, 0.757, 0), kind, Color.WHITE, false, 1.0)
	A.box(r, Vector3(w + 0.01, 0.025, d + 0.01), Vector3(0, 0.725, 0), "metal", Color(0.3, 0.3, 0.3), false, 0.5)
	for s in [-1, 1]:
		A.box(r, Vector3(w - 0.2, 0.08, 0.02), Vector3(0, 0.67, s * (d / 2 - 0.06)), "metal", Color(0.35, 0.35, 0.35), false, 0.5)
		A.box(r, Vector3(0.02, 0.08, d - 0.2), Vector3(s * (w / 2 - 0.06), 0.67, 0), "metal", Color(0.35, 0.35, 0.35), false, 0.5)
		A.seg(r, Vector3(s * (w / 2 - 0.08), 0.15, -(d / 2 - 0.08)), Vector3(s * (w / 2 - 0.08), 0.15, d / 2 - 0.08), 0.012, 0.012, "metal", Color(0.35, 0.35, 0.35))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			A.cyl(r, 0.025, 0.71, Vector3(sx * (w / 2 - 0.08), 0.36, sz * (d / 2 - 0.08)), "metal", Color(0.4, 0.4, 0.42))
			A.cyl(r, 0.035, 0.02, Vector3(sx * (w / 2 - 0.08), 0.01, sz * (d / 2 - 0.08)), "rubber", Color.WHITE)
	return r


static func filing_cabinet(parent: Node, pos: Vector3, rot_y: float) -> void:
	var r := _root(parent, pos, rot_y, Vector3(0.5, 1.3, 0.6))
	var t: Color = [Color(0.6, 0.62, 0.55), Color(0.45, 0.5, 0.45), Color(0.62, 0.58, 0.5)][randi() % 3]
	A.box(r, Vector3(0.5, 1.3, 0.6), Vector3(0, 0.65, 0), "metal", t, false, 1.0)
	A.box(r, Vector3(0.48, 0.06, 0.02), Vector3(0, 0.03, -0.3), "metal", t.darkened(0.4), false, 0.5)
	var open := randi() % 6
	for i in 4:
		var y := 0.2 + i * 0.3
		var z := -0.305 - (0.22 if i == open else 0.0)
		if i == open:   # pulled out, papers sticking up
			for s in [-1, 1]:
				A.box(r, Vector3(0.01, 0.2, 0.22), Vector3(s * 0.2, y, -0.41), "metal", t.darkened(0.2), false, 0.5)
			for k in 5:
				A.box(r, Vector3(0.38, 0.22, 0.005), Vector3(0, y + 0.04, -0.33 - k * 0.04), "paper", Color(0.9, 0.86, 0.72).darkened(randf() * 0.2), false, 0.3, Vector3(randf_range(-0.15, 0.15), 0, 0))
		A.box(r, Vector3(0.45, 0.27, 0.02), Vector3(0, y + 0.08, z), "metal", t.lightened(0.06), false, 0.5)
		A.seg(r, Vector3(-0.07, y + 0.12, z - 0.02), Vector3(0.07, y + 0.12, z - 0.02), 0.008, 0.008, "metal", Color(0.8, 0.8, 0.75))
		A.box(r, Vector3(0.09, 0.04, 0.005), Vector3(0, y + 0.19, z - 0.012), "paper", Color(0.92, 0.9, 0.8), false, 0.2)


static func vending(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var tints := [Color(0.75, 0.2, 0.15), Color(0.2, 0.35, 0.6), Color(0.3, 0.5, 0.3)]
	var t: Color = tints[rng.randi() % tints.size()]
	var r := _root(parent, pos, rot_y, Vector3(0.95, 1.95, 0.8))
	var lit := rng.randf() < 0.7
	A.box(r, Vector3(0.95, 1.95, 0.8), Vector3(0, 0.975, 0), "metal", t, false, 1.0)
	A.box(r, Vector3(0.66, 1.3, 0.06), Vector3(-0.1, 1.15, -0.39), "metal", Color(0.08, 0.08, 0.08), false, 0.5)   # inside
	for i in 5:   # spiral shelves with snacks and cans
		var y := 0.62 + i * 0.25
		A.box(r, Vector3(0.62, 0.012, 0.05), Vector3(-0.1, y, -0.405), "metal", Color(0.6, 0.6, 0.6), false, 0.3)
		for j in 5:
			var c := Color.from_hsv(rng.randf(), 0.65, 0.95)
			if rng.randf() < 0.15:
				continue
			if i % 2 == 0:
				A.cyl(r, 0.035, 0.12, Vector3(-0.35 + j * 0.125, y + 0.07, -0.41), "metal", c)
			else:
				A.box(r, Vector3(0.09, 0.15, 0.03), Vector3(-0.35 + j * 0.125, y + 0.085, -0.41), "plastic", c, false, 0.2)
	var glass = A.box(r, Vector3(0.68, 1.32, 0.01), Vector3(-0.1, 1.15, -0.425), "metal", Color.WHITE, false)
	glass.material_override = A.glass()
	if lit:
		A.glow(r, Vector3(0.64, 0.02, 0.04), Vector3(-0.1, 1.79, -0.41), Color(0.95, 0.9, 0.8), 3.0)
	A.box(r, Vector3(0.2, 1.3, 0.02), Vector3(0.36, 1.15, -0.41), "metal", t.darkened(0.3), false, 0.5)   # side panel
	for k in 12:
		A.box(r, Vector3(0.035, 0.03, 0.01), Vector3(0.32 + (k % 3) * 0.04, 1.35 - (k / 3) * 0.045, -0.423), "plastic", Color(0.85, 0.85, 0.8), false, 0.2)
	A.glow(r, Vector3(0.13, 0.05, 0.01), Vector3(0.36, 1.48, -0.423), Color(0.3, 1, 0.4) if lit else Color(0.05, 0.08, 0.05), 2.0 if lit else 0.0)
	A.box(r, Vector3(0.04, 0.08, 0.01), Vector3(0.36, 1.1, -0.423), "metal", Color(0.75, 0.7, 0.4), false, 0.2)   # coin slot
	A.box(r, Vector3(0.6, 0.2, 0.03), Vector3(-0.1, 0.3, -0.41), "metal", Color(0.12, 0.12, 0.12), false, 0.5)    # pickup flap
	A.glow(r, Vector3(0.9, 0.16, 0.02), Vector3(0, 1.88, -0.405), t.lightened(0.4), 2.0 if lit else 0.15)
	if lit:
		B.omni(r, Vector3(0, 1.2, -0.9), Color(0.9, 0.85, 0.7), 0.6, 4.0)


static func fridge(parent: Node, pos: Vector3, rot_y: float) -> void:
	var r := _root(parent, pos, rot_y, Vector3(0.75, 1.75, 0.7))
	var c := Color(0.92, 0.9, 0.82)
	A.box(r, Vector3(0.75, 1.72, 0.66), Vector3(0, 0.88, 0.02), "plastic", c, false, 1.0)
	A.box(r, Vector3(0.73, 0.5, 0.04), Vector3(0, 1.48, -0.33), "plastic", c.lightened(0.04), false, 1.0)
	A.box(r, Vector3(0.73, 1.12, 0.04), Vector3(0, 0.66, -0.33), "plastic", c.lightened(0.04), false, 1.0)
	A.box(r, Vector3(0.74, 0.012, 0.045), Vector3(0, 1.225, -0.33), "rubber", Color.WHITE, false, 0.3)
	for y in [[1.32, 1.6], [0.95, 1.18]]:
		A.seg(r, Vector3(0.3, y[0], -0.375), Vector3(0.3, y[1], -0.375), 0.012, 0.012, "metal", Color(0.75, 0.75, 0.75))
		for e in y:
			A.box(r, Vector3(0.02, 0.02, 0.04), Vector3(0.3, e, -0.36), "metal", Color(0.75, 0.75, 0.75), false, 0.2)
	A.box(r, Vector3(0.6, 0.08, 0.01), Vector3(0, 0.06, -0.352), "grille", Color.WHITE, false, 0.2)
	for k in randi_range(1, 4):   # notes and magnets
		var p := Vector3(randf_range(-0.25, 0.2), randf_range(0.7, 1.6), -0.354)
		A.box(r, Vector3(0.12, 0.15, 0.003), p, "paper", Color(0.95, 0.92, 0.7).darkened(randf() * 0.2), false, 0.2, Vector3(0, 0, randf_range(-0.2, 0.2)))
		A.cyl(r, 0.012, 0.01, p + Vector3(0, 0.06, -0.004), "plastic", Color.from_hsv(randf(), 0.7, 0.9), false, "z")


static func server_rack(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rot_y, Vector3(0.65, 2.1, 1.0))
	A.box(r, Vector3(0.65, 2.1, 1.0), Vector3(0, 1.05, 0), "metal", Color(0.22, 0.22, 0.24), false, 1.0)
	for s in [-1, 1]:
		A.box(r, Vector3(0.04, 2.06, 0.03), Vector3(s * 0.3, 1.05, -0.51), "metal", Color(0.15, 0.15, 0.16), false, 0.5)
	for i in 9:
		var y := 0.25 + i * 0.2
		var unit: Color = [Color(0.3, 0.3, 0.32), Color(0.75, 0.75, 0.72), Color(0.2, 0.2, 0.22)][rng.randi() % 3]
		A.box(r, Vector3(0.55, 0.17, 0.02), Vector3(0, y, -0.51), "metal", unit, false, 0.3)
		A.box(r, Vector3(0.3, 0.1, 0.005), Vector3(-0.08, y, -0.522), "grille", Color(0.6, 0.6, 0.6), false, 0.15)
		for s in [-1, 1]:
			A.box(r, Vector3(0.015, 0.1, 0.02), Vector3(s * 0.25, y, -0.53), "metal", Color(0.7, 0.7, 0.7), false, 0.2)
		for j in 3:
			var led := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.02, 0.02, 0.01)
			led.mesh = bm
			r.add_child(led)
			led.position = Vector3(0.12 + j * 0.03, y + 0.03, -0.525)
			var c: Color = [Color(0.2, 1, 0.3), Color(1, 0.6, 0.1), Color(0.2, 0.6, 1)][rng.randi() % 3]
			if rng.randf() < 0.3:
				_blink(led, c, rng.randf_range(0.3, 1.5))
			else:
				led.material_override = B.mat(c, 4.0)
	for k in rng.randi_range(2, 5):   # cables dangling out of the front
		var x := rng.randf_range(-0.2, 0.2)
		var y0 := rng.randf_range(0.6, 1.9)
		var c: Color = [Color(0.2, 0.3, 0.8), Color(0.85, 0.75, 0.2), Color(0.8, 0.2, 0.2), Color(0.15, 0.15, 0.15)][rng.randi() % 4]
		A.seg(r, Vector3(x, y0, -0.53), Vector3(x + rng.randf_range(-0.1, 0.1), y0 - 0.3, -0.6), 0.008, 0.008, "plastic", c)
		A.seg(r, Vector3(x, y0 - 0.3, -0.6), Vector3(x + rng.randf_range(-0.2, 0.2), 0.02, -0.65), 0.008, 0.008, "plastic", c)
	for x in [-0.15, 0.15]:
		A.ring(r, 0.1, 0.085, Vector3(x, 2.11, 0.2), "metal", Color(0.3, 0.3, 0.3))


## Generator / pump: big machine with a tank, pipes into the ceiling, gauges, a spinning fan and a beacon.
static func generator(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator, ceiling := 4.0) -> void:
	var r := _root(parent, pos, rot_y, Vector3(2.2, 1.6, 1.4))
	var t := Color(0.75, 0.6, 0.3) if rng.randf() < 0.5 else Color(0.45, 0.55, 0.5)
	A.box(r, Vector3(2.2, 1.2, 1.4), Vector3(0, 0.6, 0), "metal", t, false)
	A.box(r, Vector3(2.3, 0.15, 1.5), Vector3(0, 0.07, 0), "rust", Color.WHITE, false, 1.0)
	A.cyl(r, 0.45, 1.6, Vector3(0.1, 1.55, 0), "rust", Color.WHITE, false, "x")
	A.pipe(r, Vector3(-0.7, 1.6, 0.3), Vector3(-0.7, ceiling, 0.3), 0.12, "metal")
	A.pipe(r, Vector3(0.8, 1.2, -0.3), Vector3(0.8, ceiling, -0.3), 0.08, "rust")
	for i in 3:
		A.cyl(r, 0.1, 0.03, Vector3(-0.6 + i * 0.3, 0.9, -0.71), "cream", Color(0.95, 0.95, 0.9), false, "z")
	var fan := Node3D.new()
	r.add_child(fan)
	fan.position = Vector3(0.75, 0.65, -0.72)
	A.cyl(r, 0.32, 0.04, Vector3(0.75, 0.65, -0.71), "grille", Color.WHITE, false, "z")
	for i in 4:
		var blade := A.box(fan, Vector3(0.52, 0.09, 0.01), Vector3.ZERO, "metal", Color(0.5, 0.5, 0.5), false)
		blade.rotation.z = i * PI / 4
	A.spin(fan, "z", 0.5)
	var beacon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	beacon.mesh = sm
	r.add_child(beacon)
	beacon.position = Vector3(-0.9, 1.3, -0.5)
	_blink(beacon, Color(1, 0.2, 0.1), 1.0)


static func control_panel(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rot_y, Vector3(1.6, 1.1, 0.7))
	var body := Color(0.5, 0.52, 0.48) if rng.randf() < 0.5 else Color(0.45, 0.5, 0.55)
	A.box(r, Vector3(1.6, 0.9, 0.7), Vector3(0, 0.45, 0), "metal", body, false, 1.0)
	A.box(r, Vector3(1.5, 0.06, 0.02), Vector3(0, 0.05, -0.355), "metal", body.darkened(0.4), false, 0.5)
	var deck := Node3D.new()   # sloped face; children laid out on its surface
	r.add_child(deck)
	deck.position = Vector3(0, 1.0, -0.05)
	deck.rotation.x = -0.4   # low at the front (-z), high at the back
	A.box(deck, Vector3(1.6, 0.05, 0.62), Vector3.ZERO, "metal", body.darkened(0.25), false, 1.0)
	for i in 3:   # gauges
		var gx := -0.6 + i * 0.22
		A.cyl(deck, 0.07, 0.02, Vector3(gx, 0.03, 0.12), "paper", Color(0.92, 0.9, 0.82))
		A.ring(deck, 0.075, 0.065, Vector3(gx, 0.04, 0.12), "metal", Color(0.7, 0.7, 0.7))
		A.box(deck, Vector3(0.006, 0.005, 0.06), Vector3(gx + 0.01, 0.045, 0.11), "metal", Color(0.8, 0.1, 0.1), false, 0.2, Vector3(0, rng.randf_range(-1.2, 1.2), 0))
	for i in 8:   # status lamps
		var c := Color.from_hsv(rng.randf(), 0.8, 1.0)
		A.glow(deck, Vector3(0.05, 0.02, 0.05), Vector3(-0.65 + i * 0.09, 0.03, -0.12), c, 3.0 if rng.randf() < 0.6 else 0.2)
	for i in 5:   # knobs
		A.cyl(deck, 0.025, 0.03, Vector3(-0.1 + i * 0.08, 0.04, -0.15), "plastic", Color(0.15, 0.15, 0.15))
	for i in 4:   # toggle switches
		A.seg(deck, Vector3(-0.1 + i * 0.08, 0.025, 0.1), Vector3(-0.1 + i * 0.08, 0.07, 0.1 + (0.02 if rng.randf() < 0.5 else -0.02)), 0.005, 0.004, "metal", Color(0.8, 0.8, 0.8))
	A.cyl(deck, 0.05, 0.03, Vector3(0.45, 0.04, -0.12), "plastic", Color(0.85, 0.1, 0.08))   # the big red button
	A.ring(deck, 0.06, 0.05, Vector3(0.45, 0.03, -0.12), "hazard", Color.WHITE)
	A.seg(r, Vector3(0.72, 0.9, -0.2), Vector3(0.72, 1.25, -0.32), 0.015, 0.015, "metal", Color(0.6, 0.6, 0.6))   # lever
	A.sphere(r, 0.035, Vector3(0.72, 1.26, -0.33), "plastic", Color(0.1, 0.1, 0.1))
	A.crt(r, Vector3(0.45, 1.13, 0.28), rng.randf() < 0.5, Color(0.3, 1, 0.5))


static func lab_bench(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := table(parent, pos, rot_y, 2.0, 0.8, "tiles")
	for i in rng.randi_range(3, 6):   # beakers: glass, liquid inside
		var c: Color = [Color(0.3, 1, 0.4), Color(0.3, 0.6, 1), Color(1, 0.5, 0.9), Color(1, 0.9, 0.3)][rng.randi() % 4]
		var h := rng.randf_range(0.12, 0.26)
		var rad := rng.randf_range(0.04, 0.07)
		var p := Vector3(rng.randf_range(-0.85, 0.2), 0.78, rng.randf_range(-0.25, 0.25))
		var liquid = A.cyl(r, rad * 0.9, h * 0.6, p + Vector3(0, h * 0.3, 0), "cream", c)
		liquid.material_override = A.mat("cream", c, 1.0, 1.5)
		var g = A.cyl(r, rad, h, p + Vector3(0, h / 2, 0), "metal")
		g.material_override = A.glass()
	var rack := Vector3(0.45, 0.78, 0.2)   # test tube rack
	A.box(r, Vector3(0.3, 0.02, 0.08), rack + Vector3(0, 0.06, 0), "wood", Color.WHITE, false, 0.3)
	A.box(r, Vector3(0.3, 0.02, 0.08), rack + Vector3(0, 0.01, 0), "wood", Color.WHITE, false, 0.3)
	for k in 5:
		var t = A.cyl(r, 0.012, 0.13, rack + Vector3(-0.12 + k * 0.06, 0.07, 0), "metal")
		t.material_override = A.glass()
		var fill = A.cyl(r, 0.01, 0.06, rack + Vector3(-0.12 + k * 0.06, 0.04, 0), "cream", Color.from_hsv(rng.randf(), 0.7, 0.9))
		fill.material_override = A.mat("cream", Color.from_hsv(rng.randf(), 0.7, 0.9), 1.0, 1.2)
	var m := Vector3(0.75, 0.78, -0.1)   # microscope
	A.box(r, Vector3(0.14, 0.03, 0.18), m + Vector3(0, 0.015, 0), "metal", Color(0.85, 0.85, 0.82), false, 0.3)
	A.seg(r, m + Vector3(0, 0.03, 0.06), m + Vector3(0, 0.25, 0.04), 0.02, 0.018, "metal", Color(0.85, 0.85, 0.82))
	A.seg(r, m + Vector3(0, 0.27, 0.05), m + Vector3(0, 0.15, -0.04), 0.022, 0.015, "metal", Color(0.2, 0.2, 0.2))
	A.box(r, Vector3(0.1, 0.01, 0.1), m + Vector3(0, 0.11, -0.02), "metal", Color(0.2, 0.2, 0.2), false, 0.2)


static func specimen_tank(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, 0.0, Vector3(1.1, 2.4, 1.1))
	A.cyl(r, 0.55, 0.3, Vector3(0, 0.15, 0), "metal", Color(0.4, 0.4, 0.4))
	A.cyl(r, 0.55, 0.25, Vector3(0, 2.3, 0), "metal", Color(0.4, 0.4, 0.4))
	var fluid = A.cyl(r, 0.46, 1.85, Vector3(0, 1.25, 0), "cream", Color(0.3, 0.9, 0.5))
	fluid.material_override = A.mat("cream", Color(0.25, 0.85, 0.45), 1.0, 1.2)
	var glass := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 1.9
	glass.mesh = cm
	glass.material_override = A.glass()
	r.add_child(glass)
	glass.position.y = 1.25
	if rng.randf() < 0.6:
		A.sphere(r, 0.22, Vector3(0, 1.3, 0), "flesh", Color(0.8, 0.7, 0.6), 0.3, 1.4)
	B.omni(r, Vector3(0, 1.3, -0.8), Color(0.3, 1, 0.5), 0.5, 4.0)


static func gurney(parent: Node, pos: Vector3, rot_y: float) -> void:
	var r := _root(parent, pos, rot_y, Vector3(0.7, 0.9, 1.9))
	var steel := Color(0.72, 0.72, 0.72)
	A.box(r, Vector3(0.66, 0.04, 1.86), Vector3(0, 0.78, 0), "metal", steel, false, 0.8)
	A.box(r, Vector3(0.62, 0.1, 1.72), Vector3(0, 0.85, 0.03), "canvas", Color(0.75, 0.82, 0.8), false, 0.5)
	A.box(r, Vector3(0.45, 0.07, 0.3), Vector3(0, 0.93, 0.72), "canvas", Color(0.92, 0.92, 0.88), false, 0.3)   # pillow
	if randf() < 0.5:
		A.box(r, Vector3(0.4, 0.004, 0.5), Vector3(randf_range(-0.1, 0.1), 0.902, randf_range(-0.4, 0.2)), "dirt", Color(0.35, 0.05, 0.04), false, 0.3, Vector3(0, randf() * TAU, 0))
	for s in [-1, 1]:   # side rails
		A.seg(r, Vector3(s * 0.34, 0.98, -0.7), Vector3(s * 0.34, 0.98, 0.7), 0.012, 0.012, "metal", steel)
		for z in [-0.7, 0.0, 0.7]:
			A.seg(r, Vector3(s * 0.34, 0.8, z), Vector3(s * 0.34, 0.98, z), 0.01, 0.01, "metal", steel)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			A.seg(r, Vector3(sx * 0.28, 0.1, sz * 0.8), Vector3(sx * 0.28, 0.77, sz * 0.8), 0.018, 0.018, "metal", steel)
			A.cyl(r, 0.055, 0.03, Vector3(sx * 0.28, 0.055, sz * 0.8), "rubber", Color.WHITE, false, "x")
	A.seg(r, Vector3(-0.28, 0.25, -0.8), Vector3(-0.28, 0.25, 0.8), 0.012, 0.012, "metal", steel)
	A.seg(r, Vector3(0.28, 0.25, -0.8), Vector3(0.28, 0.25, 0.8), 0.012, 0.012, "metal", steel)
	if randf() < 0.5:   # IV pole with an old bag
		A.seg(r, Vector3(0.3, 0.8, 0.85), Vector3(0.3, 1.9, 0.85), 0.01, 0.01, "metal", steel)
		A.seg(r, Vector3(0.2, 1.9, 0.85), Vector3(0.4, 1.9, 0.85), 0.007, 0.007, "metal", steel)
		var bag = A.box(r, Vector3(0.1, 0.16, 0.03), Vector3(0.22, 1.78, 0.85), "metal", Color.WHITE, false)
		bag.material_override = A.glass()
		A.seg(r, Vector3(0.22, 1.7, 0.85), Vector3(0.1, 1.0, 0.7), 0.003, 0.003, "plastic", Color(0.85, 0.85, 0.8))


static func counter(parent: Node, pos: Vector3, rot_y: float, w := 2.4) -> void:
	var r := _root(parent, pos, rot_y, Vector3(w, 0.95, 0.65))
	var wood := Color(0.75, 0.7, 0.65)
	A.box(r, Vector3(w, 0.82, 0.6), Vector3(0, 0.49, 0.01), "wood", wood, false, 1.0)
	A.box(r, Vector3(w, 0.08, 0.55), Vector3(0, 0.04, 0.04), "wood", wood.darkened(0.5), false, 1.0)   # kickboard
	var n := int(w / 0.6)
	for i in n:
		var x := -w / 2 + 0.3 + i * (w / n)
		A.box(r, Vector3(w / n - 0.04, 0.68, 0.02), Vector3(x, 0.5, -0.3), "wood", wood.lightened(0.05), false, 1.0)
		A.seg(r, Vector3(x + 0.18, 0.72, -0.32), Vector3(x + 0.18, 0.62, -0.32), 0.008, 0.008, "metal", Color(0.75, 0.75, 0.72))
	A.box(r, Vector3(w + 0.05, 0.05, 0.66), Vector3(0, 0.92, 0), "tiles", Color(0.9, 0.9, 0.85), false, 0.5)
	var sx := -w / 4   # sink + tap
	A.box(r, Vector3(0.5, 0.012, 0.4), Vector3(sx, 0.946, 0), "metal", Color(0.75, 0.75, 0.75), false, 0.3)
	A.box(r, Vector3(0.44, 0.01, 0.34), Vector3(sx, 0.95, 0), "metal", Color(0.25, 0.25, 0.25), false, 0.3)
	A.seg(r, Vector3(sx, 0.95, 0.22), Vector3(sx, 1.15, 0.22), 0.015, 0.015, "metal", Color(0.75, 0.75, 0.75))
	A.seg(r, Vector3(sx, 1.15, 0.22), Vector3(sx, 1.12, 0.08), 0.013, 0.01, "metal", Color(0.75, 0.75, 0.75))
	for s in [-1, 1]:
		A.cyl(r, 0.02, 0.03, Vector3(sx + s * 0.08, 0.97, 0.22), "plastic", Color(0.8, 0.2, 0.2) if s < 0 else Color(0.2, 0.4, 0.8))
	if randf() < 0.6:   # microwave
		var mx := w / 4
		A.box(r, Vector3(0.5, 0.3, 0.36), Vector3(mx, 1.1, 0.05), "plastic", Color(0.85, 0.85, 0.82), false, 0.4)
		A.box(r, Vector3(0.32, 0.22, 0.01), Vector3(mx - 0.06, 1.1, -0.13), "plastic", Color(0.08, 0.08, 0.08), false, 0.3)
		A.box(r, Vector3(0.1, 0.22, 0.01), Vector3(mx + 0.17, 1.1, -0.13), "keys", Color.WHITE, false, 0.15)
	else:   # kettle
		var kx := w / 4
		A.sphere(r, 0.09, Vector3(kx, 1.03, 0.0), "metal", Color(0.75, 0.75, 0.75), 0.0, 1.1)
		A.seg(r, Vector3(kx + 0.06, 1.02, 0), Vector3(kx + 0.13, 1.1, 0), 0.015, 0.008, "metal", Color(0.75, 0.75, 0.75))
		A.ring(r, 0.05, 0.04, Vector3(kx - 0.02, 1.13, 0), "plastic", Color(0.1, 0.1, 0.1), Vector3(PI / 2, 0, 0))
	for k in randi_range(0, 3):
		A.cyl(r, 0.035, 0.09, Vector3(randf_range(-w / 2 + 0.1, w / 2 - 0.1), 0.99, randf_range(-0.2, 0.1)), "plastic", Color.from_hsv(randf(), 0.3, 0.9))


# --- wall / floor / ceiling decor ------------------------------------------------------------

## Something flat on a wall. normal = direction the wall faces (into the room).
static func wall_decor(parent: Node, pos: Vector3, normal: Vector3, rng: RandomNumberGenerator) -> void:
	var rot := atan2(normal.x, normal.z)
	var r := Node3D.new()
	parent.add_child(r)
	r.position = pos
	r.rotation.y = rot
	match rng.randi() % 7:
		0, 1:
			A.box(r, Vector3(0.6, 0.8, 0.02), Vector3(0, 0, 0.01), "paper", Color.WHITE.darkened(rng.randf() * 0.3), false, 0.7)
			var t := B.label(r, POSTERS[rng.randi() % POSTERS.size()], Vector3(0, 0.05, 0.03), 36, Color(0.15, 0.1, 0.1), "type", 0.0035)
			A.box(r, Vector3(0.4, 0.15, 0.021), Vector3(0, -0.25, 0.012), "hazard", Color.WHITE, false, 0.4)
		2:
			A.box(r, Vector3(1.0, 0.35, 0.03), Vector3(0, 0.6, 0.015), "metal", Color(0.85, 0.75, 0.3), false)
			var s := B.label(r, SIGNS[rng.randi() % SIGNS.size()], Vector3(0, 0.6, 0.035), 40, Color(0.08, 0.08, 0.08), "plate", 0.0035)
		3:
			A.box(r, Vector3(0.5, 0.65, 0.18), Vector3(0, 0, 0.09), "metal", Color(0.55, 0.57, 0.55), false)
			A.box(r, Vector3(0.15, 0.15, 0.01), Vector3(0, 0.15, 0.185), "hazard", Color.WHITE, false, 0.3)
			A.pipe(r, Vector3(0.15, 0.33, 0.06), Vector3(0.15, 2.8, 0.06), 0.03, "metal")
		4:
			A.cyl(r, 0.09, 0.5, Vector3(0, -0.5, 0.12), "metal", Color(0.85, 0.1, 0.08))
			A.box(r, Vector3(0.25, 0.04, 0.12), Vector3(0, -0.15, 0.08), "metal", Color(0.3, 0.3, 0.3), false)
			A.glow(r, Vector3(0.3, 0.12, 0.02), Vector3(0, 0.35, 0.02), Color(1, 0.2, 0.1), 1.5)
		5:
			A.box(r, Vector3(0.7, 0.4, 0.04), Vector3(0, 0.9, 0.02), "grille", Color.WHITE, false, 0.3)
		6:
			A.box(r, Vector3(1.0, 0.7, 0.04), Vector3(0, 0.1, 0.02), "wood", Color(0.7, 0.55, 0.4), false, 0.5)
			for i in 4:
				A.box(r, Vector3(0.22, 0.28, 0.01), Vector3(-0.3 + i * 0.2 + rng.randf() * 0.05, 0.1 + rng.randf_range(-0.12, 0.12), 0.045), "paper", Color.WHITE, false, 0.3, Vector3(0, 0, rng.randf_range(-0.2, 0.2)))


static func papers(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(3, 8):
		A.box(parent, Vector3(0.21, 0.004, 0.29), pos + Vector3(rng.randf_range(-1, 1), 0.005 + i * 0.001, rng.randf_range(-1, 1)), "paper", Color.WHITE.darkened(rng.randf() * 0.3), false, 0.3, Vector3(0, rng.randf() * TAU, 0))


static func stain(parent: Node, pos: Vector3, rng: RandomNumberGenerator, c := Color(0.15, 0.12, 0.1)) -> void:
	A.box(parent, Vector3(rng.randf_range(0.8, 2.5), 0.006, rng.randf_range(0.8, 2.5)), pos + Vector3(0, 0.004, 0), "dirt", c, false, 1.0, Vector3(0, rng.randf() * TAU, 0))


static func cable_tray(parent: Node, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var along_x := absf(d.x) > absf(d.z)
	A.box(parent, Vector3(d.length(), 0.08, 0.45) if along_x else Vector3(0.45, 0.08, d.length()), (a + b) / 2.0, "grate", Color.WHITE, false, 0.5)
	for i in 3:
		var off := Vector3(0, 0.07, -0.12 + i * 0.12) if along_x else Vector3(-0.12 + i * 0.12, 0.07, 0)
		A.cyl(parent, 0.03, d.length(), (a + b) / 2.0 + off, "metal", [Color(0.2, 0.2, 0.2), Color(0.6, 0.2, 0.1), Color(0.2, 0.3, 0.5)][i], false, "x" if along_x else "z")


static func duct(parent: Node, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var along_x := absf(d.x) > absf(d.z)
	A.box(parent, Vector3(d.length(), 0.55, 0.7) if along_x else Vector3(0.7, 0.55, d.length()), (a + b) / 2.0, "metal", Color(0.65, 0.65, 0.65), false, 1.0)
	var n := int(d.length() / 1.5)
	for i in n + 1:
		var p := a + d * (float(i) / maxf(n, 1))
		A.box(parent, Vector3(0.06, 0.6, 0.75) if along_x else Vector3(0.75, 0.6, 0.06), p, "rust", Color.WHITE, false, 0.5)


## Steel truss beam between two points at the same height.
static func truss(parent: Node, a: Vector3, b: Vector3, h := 0.5) -> void:
	var d := b - a
	var along_x := absf(d.x) > absf(d.z)
	var length := d.length()
	for y in [0.0, -h]:
		A.box(parent, Vector3(length, 0.08, 0.12) if along_x else Vector3(0.12, 0.08, length), (a + b) / 2.0 + Vector3(0, y, 0), "rust", Color.WHITE, false, 1.0)
	var n := maxi(2, int(length / h))
	var diag := sqrt(h * h + (length / n) * (length / n))
	var ang := atan2(h, length / n)
	for i in n:
		var p := a + d * ((i + 0.5) / n) + Vector3(0, -h / 2, 0)
		var bar := A.box(parent, Vector3(diag, 0.05, 0.05) if along_x else Vector3(0.05, 0.05, diag), p, "rust", Color(0.8, 0.8, 0.8), false, 1.0)
		var s := 1.0 if i % 2 == 0 else -1.0
		if along_x:
			bar.rotation.z = ang * s
		else:
			bar.rotation.x = ang * s


## Stairs from `top` going `dir` (unit axis vector) down `drop` metres over `run`. Visual steps + a ramp collider.
static func stairs(parent: Node, top: Vector3, dir: Vector3, drop: float, run: float, width := 1.2) -> void:
	var n := int(drop / 0.22)
	var side := Vector3(-dir.z, 0, dir.x)
	for i in n:
		var p := top + dir * (run * (i + 0.5) / n) + Vector3(0, -drop * (i + 1) / n + 0.04, 0)
		var size := Vector3(run / n + 0.02, 0.06, width) if absf(dir.x) > 0.5 else Vector3(width, 0.06, run / n + 0.02)
		A.box(parent, size, p, "grate", Color.WHITE, false, 0.5)
	for s in [-1, 1]:
		railing_slope(parent, top + side * (s * width / 2), dir, drop, run)
	var length := sqrt(run * run + drop * drop)
	var ang := atan2(drop, run)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(length, 0.1, width) if absf(dir.x) > 0.5 else Vector3(width, 0.1, length)
	cs.shape = sh
	body.add_child(cs)
	parent.add_child(body)
	body.position = top + dir * (run / 2) + Vector3(0, -drop / 2 - 0.05, 0)
	if dir.x > 0.5: body.rotation.z = -ang
	elif dir.x < -0.5: body.rotation.z = ang
	elif dir.z > 0.5: body.rotation.x = ang
	else: body.rotation.x = -ang


static func railing_slope(parent: Node, top: Vector3, dir: Vector3, drop: float, run: float) -> void:
	var length := sqrt(run * run + drop * drop)
	var ang := atan2(drop, run)
	var rail := A.box(parent, Vector3(length, 0.05, 0.05) if absf(dir.x) > 0.5 else Vector3(0.05, 0.05, length), top + dir * (run / 2) + Vector3(0, -drop / 2 + 0.95, 0), "rust", Color.WHITE, false, 1.0)
	if dir.x > 0.5: rail.rotation.z = -ang
	elif dir.x < -0.5: rail.rotation.z = ang
	elif dir.z > 0.5: rail.rotation.x = ang
	else: rail.rotation.x = -ang
	for t in [0.0, 0.5, 1.0]:
		A.box(parent, Vector3(0.05, 0.95, 0.05), top + dir * (run * t) + Vector3(0, -drop * t + 0.47, 0), "rust", Color.WHITE, false, 1.0)


# --- outdoor --------------------------------------------------------------------------------

static func car_wreck(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rot_y, Vector3(4.2, 1.5, 1.9))
	r.rotation.z = rng.randf_range(-0.06, 0.06)
	var t := Color.from_hsv(rng.randf(), 0.35, 0.75)
	var chrome := Color(0.7, 0.7, 0.68)
	A.box(r, Vector3(4.1, 0.5, 1.8), Vector3(0, 0.6, 0), "rust", t, false, 1.5)                  # lower body
	var hood := A.box(r, Vector3(1.25, 0.12, 1.75), Vector3(1.4, 0.88, 0), "rust", t, false, 1.5)
	hood.rotation.z = -0.06
	A.box(r, Vector3(0.9, 0.18, 1.75), Vector3(-1.6, 0.92, 0), "rust", t, false, 1.5)            # trunk
	var cab := Node3D.new()
	r.add_child(cab)
	cab.position = Vector3(-0.25, 0.85, 0)
	A.box(cab, Vector3(1.9, 0.06, 1.65), Vector3(0, 0.62, 0), "rust", t.darkened(0.1), false, 1.5)  # roof
	for x in [-0.9, 0.0, 0.92]:   # pillars
		for z in [-0.8, 0.8]:
			var p := A.box(cab, Vector3(0.08, 0.62, 0.06), Vector3(x, 0.31, z), "rust", t, false, 1.0)
			if x > 0.5:
				p.rotation.z = 0.35
			elif x < -0.5:
				p.rotation.z = -0.3
	A.box(cab, Vector3(1.9, 0.1, 1.7), Vector3(0, 0.02, 0), "rust", t, false, 1.5)
	for x in [-0.45, 0.45]:   # broken side windows (frames only, a shard left)
		for z in [-0.82, 0.82]:
			if rng.randf() < 0.4:
				var g = A.box(cab, Vector3(0.6, 0.35, 0.01), Vector3(x, 0.3, z), "metal", Color.WHITE, false)
				g.material_override = A.glass()
	var ws = A.box(cab, Vector3(0.01, 0.55, 1.5), Vector3(1.05, 0.3, 0), "metal", Color.WHITE, false)
	ws.rotation.z = 0.35
	ws.material_override = A.glass()
	A.box(cab, Vector3(1.6, 0.25, 1.5), Vector3(-0.1, 0.12, 0), "canvas", Color(0.35, 0.25, 0.2), false, 0.5)   # seats
	for s in [-1, 1]:   # bumpers, lights
		A.box(r, Vector3(0.12, 0.16, 1.85), Vector3(s * 2.08, 0.42, 0), "metal", chrome, false, 0.5)
		for z in [-0.65, 0.65]:
			if s > 0:
				A.cyl(r, 0.1, 0.05, Vector3(2.06, 0.7, z), "cream", Color(0.85, 0.85, 0.75), false, "x")
				A.ring(r, 0.11, 0.09, Vector3(2.07, 0.7, z), "metal", chrome, Vector3(0, 0, PI / 2))
			else:
				A.box(r, Vector3(0.04, 0.12, 0.3), Vector3(-2.06, 0.75, z), "plastic", Color(0.6, 0.1, 0.08), false, 0.3)
	A.box(r, Vector3(0.03, 0.25, 0.8), Vector3(2.07, 0.72, 0), "grille", chrome, false, 0.3)
	for x in [-1.35, 1.35]:   # wheels: tyre, rim, arch
		for z in [-0.9, 0.9]:
			A.box(r, Vector3(0.95, 0.35, 0.06), Vector3(x, 0.72, z * 1.0), "rust", t.darkened(0.3), false, 1.0)
			if rng.randf() < 0.8:
				A.ring(r, 0.36, 0.2, Vector3(x, 0.36, z), "rubber", Color.WHITE, Vector3(PI / 2, 0, 0))
				A.cyl(r, 0.22, 0.18, Vector3(x, 0.36, z), "metal", chrome.darkened(0.3), false, "z")
			else:
				A.cyl(r, 0.2, 0.1, Vector3(x, 0.25, z), "rust", Color.WHITE, false, "z")   # bare hub on the ground
	for z in [-0.9, 0.9]:
		A.box(r, Vector3(0.04, 0.03, 0.12), Vector3(0.3, 0.8, z * 1.0), "metal", chrome, false, 0.2)   # door handles


static func water_tower(parent: Node, pos: Vector3) -> void:
	var r := _root(parent, pos, 0.0)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var leg := A.box(r, Vector3(0.25, 10.5, 0.25), Vector3(sx * 1.9, 5.1, sz * 1.9), "rust", Color.WHITE, true, 1.0)
			leg.rotation = Vector3(-sz * 0.06, 0, sx * 0.06)
			A.box(r, Vector3(0.6, 0.3, 0.6), Vector3(sx * 2.2, 0.15, sz * 2.2), "concrete", Color(0.75, 0.72, 0.68), false, 1.0)
	for y in [3.0, 6.5]:
		for s in [-1, 1]:
			A.box(r, Vector3(4.2, 0.12, 0.12), Vector3(0, y, s * 1.95), "rust", Color.WHITE, false, 1.0)
			A.box(r, Vector3(0.12, 0.12, 4.2), Vector3(s * 1.95, y, 0), "rust", Color.WHITE, false, 1.0)
			var d := A.box(r, Vector3(0.06, 4.4, 0.06), Vector3(0, y - 1.7, s * 1.95), "rust", Color(0.8, 0.8, 0.8), false, 1.0)
			d.rotation.z = 0.7 * s
	A.cyl(r, 2.7, 0.25, Vector3(0, 10.0, 0), "grate", Color.WHITE)   # catwalk
	A.ring(r, 2.8, 2.74, Vector3(0, 11.0, 0), "rust", Color.WHITE)
	for i in 12:
		var a := TAU * i / 12.0
		A.seg(r, Vector3(cos(a) * 2.77, 10.1, sin(a) * 2.77), Vector3(cos(a) * 2.77, 11.0, sin(a) * 2.77), 0.03, 0.03, "rust")
	A.cyl(r, 2.6, 3.4, Vector3(0, 11.7, 0), "corrugated", Color(0.75, 0.55, 0.4))
	for y in [10.3, 11.7, 13.1]:
		A.ring(r, 2.63, 2.58, Vector3(0, y, 0), "rust", Color(0.7, 0.7, 0.7))
	A.cyl(r, 2.7, 1.2, Vector3(0, 14.0, 0), "rust", Color(0.7, 0.7, 0.7), false, "y", 0.2)
	A.sphere(r, 0.2, Vector3(0, 14.7, 0), "rust", Color(0.7, 0.7, 0.7))
	for i in 34:   # ladder up a leg
		A.box(r, Vector3(0.45, 0.04, 0.04), Vector3(0, 0.3 + i * 0.3, -2.2), "metal", Color(0.5, 0.5, 0.5), false, 0.5)
	for s in [-1, 1]:
		A.box(r, Vector3(0.05, 10.2, 0.05), Vector3(s * 0.22, 5.1, -2.2), "metal", Color(0.5, 0.5, 0.5), false, 0.5)


static func windmill(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rng.randf() * TAU)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var leg := A.box(r, Vector3(0.12, 9.5, 0.12), Vector3(sx * 0.7, 4.6, sz * 0.7), "metal", Color(0.55, 0.5, 0.45), true, 1.0)
			leg.rotation = Vector3(-sz * 0.07, 0, sx * 0.07)
	for y in [2.5, 5.0, 7.5]:
		var w: float = 1.4 - y * 0.12
		for s in [-1, 1]:
			A.box(r, Vector3(w * 2, 0.06, 0.06), Vector3(0, y, s * w), "metal", Color(0.55, 0.5, 0.45), false, 1.0)
	var rotor := Node3D.new()
	r.add_child(rotor)
	rotor.position = Vector3(0, 9.6, -0.4)
	for i in 12:
		var blade := A.box(rotor, Vector3(0.28, 1.6, 0.03), Vector3(0, 1.2, 0).rotated(Vector3.BACK, i * TAU / 12), "metal", Color(0.75, 0.7, 0.6), false, 1.0)
		blade.rotation.z = i * TAU / 12
	A.cyl(rotor, 0.2, 0.3, Vector3.ZERO, "rust", Color.WHITE, false, "z")
	A.spin(rotor, "z", rng.randf_range(3.0, 6.0))
	A.box(r, Vector3(0.05, 0.8, 1.6), Vector3(0, 9.6, 1.2), "metal", Color(0.75, 0.7, 0.6), false)


static func pumpjack(parent: Node, pos: Vector3, rot_y: float) -> void:
	var r := _root(parent, pos, rot_y, Vector3(5.0, 1.0, 1.6))
	A.box(r, Vector3(5.0, 0.4, 1.4), Vector3(0, 0.2, 0), "metal", Color(0.4, 0.4, 0.38))
	for s in [-1, 1]:
		var leg := A.box(r, Vector3(0.18, 3.6, 0.18), Vector3(0.3, 2.1, s * 0.5), "metal", Color(0.75, 0.6, 0.2), false)
		leg.rotation.x = -s * 0.15
	var beam := Node3D.new()
	r.add_child(beam)
	beam.position = Vector3(0.3, 3.8, 0)
	A.box(beam, Vector3(5.0, 0.35, 0.3), Vector3(0, 0, 0), "metal", Color(0.75, 0.6, 0.2), false)
	A.box(beam, Vector3(0.5, 1.4, 0.4), Vector3(2.5, -0.4, 0), "metal", Color(0.75, 0.6, 0.2), false)
	beam.set_meta("live", true)
	var tw := beam.create_tween().set_loops()
	tw.tween_property(beam, "rotation:z", 0.28, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(beam, "rotation:z", -0.28, 1.6).set_trans(Tween.TRANS_SINE)
	var crank := Node3D.new()
	r.add_child(crank)
	crank.position = Vector3(-1.8, 1.2, 0)
	A.box(crank, Vector3(1.6, 0.4, 0.2), Vector3(0, 0, 0.45), "metal", Color(0.3, 0.3, 0.3), false)
	A.spin(crank, "z", 3.2)
	A.cyl(r, 0.08, 1.2, Vector3(2.8, 0.6, 0), "metal", Color(0.6, 0.6, 0.6))


static func rock_spire(parent: Node, pos: Vector3, rng: RandomNumberGenerator, tint := Color.WHITE) -> void:
	var h := 0.0
	var s := rng.randf_range(7.0, 14.0)
	while s > 1.5:
		var tall := s * rng.randf_range(0.8, 1.5)
		A.box(parent, Vector3(s, tall, s * rng.randf_range(0.7, 1.2)), pos + Vector3(rng.randf_range(-1, 1), h + tall / 2, rng.randf_range(-1, 1)), "rock", tint, false, 6.0,
			Vector3(rng.randf_range(-0.1, 0.1), rng.randf() * TAU, rng.randf_range(-0.1, 0.1)))
		h += tall * 0.85
		s *= rng.randf_range(0.6, 0.8)


static func rock_arch(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator, tint := Color.WHITE) -> void:
	var r := _root(parent, pos, rot_y)
	var span := rng.randf_range(18, 30)
	var h := rng.randf_range(16, 26)
	for s in [-1, 1]:
		A.box(r, Vector3(7, h, 8), Vector3(s * span / 2, h / 2, 0), "rock", tint, false, 6.0, Vector3(0, 0, -s * 0.12))
	A.box(r, Vector3(span + 10, 7, 8), Vector3(0, h + 2, 0), "rock", tint, false, 6.0, Vector3(0, 0, rng.randf_range(-0.06, 0.06)))


static func ruin_wall(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rot_y)
	var x := -4.0
	while x < 4.0:
		var w := rng.randf_range(0.6, 1.8)
		var h := rng.randf_range(0.5, 4.5)
		if rng.randf() < 0.8:
			A.box(r, Vector3(w, h, 0.35), Vector3(x + w / 2, h / 2, 0), "concrete", Color(0.85, 0.75, 0.65), true, 2.0)
		x += w
	A.rubble(r, Vector3(rng.randf_range(-3, 3), 0, -1.0), rng)


## Arched steel frame (like a gutted hangar or station canopy).
static func arch_frame(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rot_y)
	var radius := rng.randf_range(4.0, 6.0)
	var ribs := rng.randi_range(3, 5)
	for k in ribs:
		var z := (k - (ribs - 1) / 2.0) * 3.0
		if rng.randf() < 0.15:
			continue
		for i in 12:
			var a0 := PI * i / 12.0
			var a1 := PI * (i + 1) / 12.0
			var p0 := Vector3(cos(a0) * radius, sin(a0) * radius * 0.8 + 3.0, z)
			var p1 := Vector3(cos(a1) * radius, sin(a1) * radius * 0.8 + 3.0, z)
			var seg := A.box(r, Vector3(p0.distance_to(p1) + 0.05, 0.18, 0.18), (p0 + p1) / 2.0, "rust", Color.WHITE, false, 1.0)
			seg.rotation.z = atan2(p1.y - p0.y, p1.x - p0.x)
		for s in [-1, 1]:
			A.box(r, Vector3(0.2, 3.0, 0.2), Vector3(s * radius, 1.5, z), "rust", Color.WHITE, true, 1.0)
	for i in 5:
		var a := PI * (i + 0.5) / 5.0
		A.box(r, Vector3(0.1, 0.1, ribs * 3.0), Vector3(cos(a) * radius, sin(a) * radius * 0.8 + 3.0, 0), "rust", Color.WHITE, false, 1.0)


static func fence(parent: Node, a: Vector3, b: Vector3, rng: RandomNumberGenerator) -> void:
	var d := b - a
	var n := maxi(1, int(d.length() / 2.5))
	var ang := -atan2(d.z, d.x)
	for i in n + 1:
		var p0 := a + d * (float(i) / n)
		A.cyl(parent, 0.05, 2.1, p0 + Vector3(0, 1.05, 0), "rust", Color.WHITE, true)
		A.sphere(parent, 0.06, p0 + Vector3(0, 2.12, 0), "rust", Color.WHITE)
		if i == n:
			break
		var p1 := a + d * (float(i + 1) / n)
		var mid := (p0 + p1) / 2.0
		if rng.randf() < 0.85:
			var panel := A.box(parent, Vector3(p0.distance_to(p1), 1.8, 0.03), mid + Vector3(0, 0.95, 0), "grate", Color(0.8, 0.8, 0.8), false, 0.8)
			panel.rotation.y = ang
			if rng.randf() < 0.2:
				panel.rotation.x = rng.randf_range(-0.5, 0.5)
		A.seg(parent, p0 + Vector3(0, 1.9, 0), p1 + Vector3(0, 1.9, 0), 0.025, 0.025, "rust")
		for k in 2:   # barbed wire on top
			A.seg(parent, p0 + Vector3(0, 2.0 + k * 0.1, 0), p1 + Vector3(0, 2.0 + k * 0.1, 0), 0.006, 0.006, "metal", Color(0.4, 0.4, 0.4))


static func scrap_heap(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(8, 16):
		var s := rng.randf_range(0.3, 1.4)
		var kinds := ["rust", "metal", "wood", "corrugated"]
		var p := pos + Vector3(rng.randf_range(-2, 2), rng.randf_range(0, 1.2), rng.randf_range(-2, 2))
		if rng.randf() < 0.3:
			A.cyl(parent, s * 0.4, s, p, "rust", Color.WHITE, false, ["x", "z", "y"][rng.randi() % 3])
		else:
			A.box(parent, Vector3(s, s * rng.randf_range(0.2, 1.0), s * rng.randf_range(0.5, 1.5)), p, kinds[rng.randi() % kinds.size()], Color.WHITE, false, 1.0,
				Vector3(rng.randf(), rng.randf() * TAU, rng.randf()))
	for i in 3:
		A.cyl(parent, 0.4, 0.25, pos + Vector3(rng.randf_range(-2.5, 2.5), 0.12 + i * 0.25, rng.randf_range(-2.5, 2.5)), "metal", Color(0.1, 0.1, 0.1))


## Shipping-container shop with a neon sign (checkpoint).
static func shop_container(parent: Node, pos: Vector3, rot_y: float) -> Node3D:
	var r := _root(parent, pos, rot_y)
	var c := Color(0.75, 0.25, 0.18)
	A.box(r, Vector3(6.0, 2.6, 0.1), Vector3(0, 1.3, 1.2), "corrugated", c, true, 1.2)
	for s in [-1, 1]:
		A.box(r, Vector3(0.1, 2.6, 2.4), Vector3(s * 3.0, 1.3, 0), "corrugated", c, true, 1.2)
	A.box(r, Vector3(6.1, 0.1, 2.5), Vector3(0, 2.65, 0), "corrugated", c.darkened(0.2), true, 1.2)
	A.box(r, Vector3(6.0, 0.12, 2.4), Vector3(0, 0.06, 0), "wood", Color.WHITE, true, 1.0)
	A.box(r, Vector3(6.0, 0.15, 1.2), Vector3(0, 2.4, -1.6), "metal", Color(0.4, 0.4, 0.4), false)
	var neon := B.display(r, "SHOP", Vector3(0, 3.3, -1.0), 200, Color(1, 0.75, 0.35))
	neon.rotation.y = PI
	neon.modulate = Color(2.5, 1.6, 0.6)
	B.omni(r, Vector3(0, 3.0, -1.6), Color(1, 0.7, 0.35), 1.5, 8.0)
	B.omni(r, Vector3(0, 2.2, 0.2), Color(1, 0.85, 0.6), 1.0, 6.0)
	return r
