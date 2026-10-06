# Furniture + outdoor set dressing, all built from primitives (see art.gd for textures).
# Every builder takes (parent, position, rotation_y, rng) where it makes sense. "Solid" props get one
# simple collision box; small decor is visual only.
extends RefCounted

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Items = preload("res://src/items.gd")
const Data = preload("res://src/data.gd")

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


## Diesel generator set: radiator + fan at one end, a six-cylinder engine with rocker covers and
## an exhaust manifold, an alternator drum, a control cabinet with gauges, muffler and stack up into
## the ceiling, a day tank, cables off to the wall. Faces -z (the control side).
static func generator(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator, ceiling := 4.0) -> void:
	var r := _root(parent, pos, rot_y, Vector3(3.2, 1.8, 1.5))
	var paint: Color = [Color(0.3, 0.42, 0.32), Color(0.82, 0.6, 0.15), Color(0.32, 0.36, 0.42)][rng.randi() % 3]
	var dark := Color(0.18, 0.18, 0.18)
	var steel := Color(0.6, 0.6, 0.6)
	# Skid with drip tray and anti-vibration mounts.
	A.box(r, Vector3(3.4, 0.18, 1.5), Vector3(0, 0.09, 0), "metal", dark, false, 0.8)
	A.box(r, Vector3(3.2, 0.03, 1.3), Vector3(0, 0.195, 0), "metal", Color(0.06, 0.06, 0.07), false, 0.5)
	for x in [-1.1, -0.2, 0.7, 1.4]:
		for z in [-0.45, 0.45]:
			A.cyl(r, 0.07, 0.12, Vector3(x, 0.26, z), "rubber", Color.WHITE)
	# Radiator end (-x): frame, core grille, fan behind it.
	A.box(r, Vector3(0.35, 1.5, 1.3), Vector3(-1.45, 1.05, 0), "metal", paint, false, 0.6)
	A.box(r, Vector3(0.02, 1.2, 1.05), Vector3(-1.63, 1.05, 0), "grille", Color.WHITE, false, 0.25)
	A.ring(r, 0.5, 0.45, Vector3(-1.25, 1.05, 0), "metal", dark, Vector3(0, 0, PI / 2))
	var fan := Node3D.new()
	r.add_child(fan)
	fan.position = Vector3(-1.2, 1.05, 0)
	for i in 6:
		A.box(fan, Vector3(0.02, 0.42, 0.12), Vector3(0, 0.22, 0).rotated(Vector3.RIGHT, i * TAU / 6), "metal", steel, false, 0.3, Vector3(i * TAU / 6, 0.4, 0))
	A.cyl(fan, 0.07, 0.08, Vector3.ZERO, "metal", dark, false, "x")
	A.spin(fan, "x", 0.35)
	A.cyl(r, 0.06, 0.12, Vector3(-1.45, 1.86, 0.4), "metal", steel)   # radiator cap
	# Engine block, six cylinders, rocker covers, exhaust manifold.
	A.box(r, Vector3(1.6, 0.8, 0.9), Vector3(-0.3, 0.7, 0), "metal", paint, false, 0.6)
	A.box(r, Vector3(1.5, 0.35, 0.6), Vector3(-0.3, 1.27, 0), "metal", paint.darkened(0.15), false, 0.6)
	for i in 3:
		A.box(r, Vector3(0.46, 0.14, 0.45), Vector3(-0.83 + i * 0.52, 1.52, 0), "metal", steel, false, 0.4)
		for k in 2:
			A.cyl(r, 0.025, 0.05, Vector3(-0.95 + i * 0.52 + k * 0.24, 1.6, 0), "metal", dark)
	A.cyl(r, 0.08, 1.4, Vector3(-0.3, 1.25, 0.45), "rust", Color.WHITE, false, "x")
	for i in 6:
		A.seg(r, Vector3(-0.92 + i * 0.25, 1.25, 0.32), Vector3(-0.92 + i * 0.25, 1.25, 0.45), 0.04, 0.04, "rust")
	A.cyl(r, 0.18, 0.35, Vector3(-0.3, 0.75, -0.55), "metal", dark, false, "z")   # oil filter
	A.box(r, Vector3(0.3, 0.25, 0.15), Vector3(0.2, 0.75, -0.52), "metal", steel, false, 0.3)   # injection pump
	# Alternator drum with fins and a terminal box.
	A.cyl(r, 0.48, 0.9, Vector3(0.95, 0.8, 0), "metal", paint, false, "x")
	for i in 5:
		A.ring(r, 0.5, 0.44, Vector3(0.6 + i * 0.18, 0.8, 0), "metal", paint.darkened(0.25), Vector3(0, 0, PI / 2))
	A.box(r, Vector3(0.4, 0.3, 0.3), Vector3(0.95, 1.35, 0), "metal", dark, false, 0.4)
	A.box(r, Vector3(0.6, 0.1, 0.02), Vector3(0.95, 0.8, -0.49), "paper", Color(0.85, 0.82, 0.7), false, 0.2)
	# Control cabinet standing at the end.
	A.box(r, Vector3(0.45, 1.6, 0.9), Vector3(1.62, 0.98, 0), "metal", paint.darkened(0.1), false, 0.6)
	A.box(r, Vector3(0.02, 0.9, 0.7), Vector3(1.86, 1.15, 0), "metal", Color(0.15, 0.15, 0.15), false, 0.4)
	for i in 3:
		A.cyl(r, 0.08, 0.02, Vector3(1.875, 1.4, -0.22 + i * 0.22), "paper", Color(0.95, 0.95, 0.9), false, "x")
		A.ring(r, 0.085, 0.07, Vector3(1.88, 1.4, -0.22 + i * 0.22), "metal", steel, Vector3(0, 0, PI / 2))
		A.box(r, Vector3(0.005, 0.07, 0.008), Vector3(1.89, 1.42, -0.22 + i * 0.22), "metal", Color(0.8, 0.1, 0.1), false, 0.2, Vector3(rng.randf_range(-1.0, 1.0), 0, 0))
	for i in 4:
		A.glow(r, Vector3(0.02, 0.05, 0.05), Vector3(1.88, 1.1, -0.27 + i * 0.18), [Color(0.2, 1, 0.3), Color(0.2, 1, 0.3), Color(1, 0.7, 0.1), Color(1, 0.15, 0.1)][i], 3.0 if rng.randf() < 0.7 else 0.2)
	A.cyl(r, 0.06, 0.06, Vector3(1.9, 0.9, 0.1), "plastic", Color(0.85, 0.1, 0.08), false, "x")   # e-stop
	A.box(r, Vector3(0.02, 0.12, 0.2), Vector3(1.89, 0.9, -0.2), "hazard", Color.WHITE, false, 0.2)
	# Muffler on brackets and the stack into the ceiling.
	A.cyl(r, 0.24, 1.1, Vector3(-0.2, 2.0, 0.25), "rust", Color.WHITE, false, "x")
	for x in [-0.6, 0.2]:
		A.seg(r, Vector3(x, 1.4, 0.25), Vector3(x, 1.8, 0.25), 0.03, 0.03, "metal", dark)
	A.seg(r, Vector3(-0.3, 1.33, 0.45), Vector3(-0.75, 2.0, 0.25), 0.07, 0.07, "rust")
	A.pipe(r, Vector3(0.35, 2.0, 0.25), Vector3(0.35, ceiling, 0.25), 0.11, "rust")
	# Day tank on the side and a fuel line.
	A.box(r, Vector3(0.9, 0.55, 0.4), Vector3(-0.4, 0.5, 0.95), "metal", Color(0.75, 0.15, 0.1), false, 0.5)
	A.cyl(r, 0.06, 0.05, Vector3(-0.2, 0.8, 0.95), "metal", steel)
	A.seg(r, Vector3(-0.4, 0.45, 0.75), Vector3(-0.2, 0.55, 0.45), 0.015, 0.015, "rubber")
	# Fat cables in a sweep off the alternator, to the floor and away.
	for k in 3:
		var z := -0.12 + k * 0.12
		A.seg(r, Vector3(0.95, 1.45, z), Vector3(1.2, 1.9, z), 0.03, 0.03, "rubber")
		A.seg(r, Vector3(1.2, 1.9, z), Vector3(1.2, ceiling, z), 0.03, 0.03, "rubber")
	var beacon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	beacon.mesh = sm
	r.add_child(beacon)
	beacon.position = Vector3(1.62, 1.85, 0.3)
	_blink(beacon, Color(1, 0.6, 0.1), 1.0)
	A.box(r, Vector3(3.6, 0.01, 0.12), Vector3(0, 0.005, -1.05), "hazard", Color.WHITE, false, 0.6)
	B.label(r, "DANGER  HIGH VOLTAGE", Vector3(0.95, 1.08, -0.495), 30, Color(0.12, 0.1, 0.08), "stencil", 0.005).rotation.y = PI


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
	var steel := Color(0.45, 0.47, 0.5)
	A.cyl(r, 0.58, 0.32, Vector3(0, 0.16, 0), "metal", steel)
	A.cyl(r, 0.55, 0.28, Vector3(0, 2.28, 0), "metal", steel, false, "y", 0.4)
	for y in [0.33, 2.15]:
		A.ring(r, 0.53, 0.48, Vector3(0, y, 0), "metal", Color(0.3, 0.3, 0.32))
	for k in 4:   # vertical struts
		var a := TAU * k / 4.0 + PI / 4
		A.seg(r, Vector3(cos(a) * 0.52, 0.3, sin(a) * 0.52), Vector3(cos(a) * 0.52, 2.2, sin(a) * 0.52), 0.025, 0.025, "metal", steel)
	var c := [Color(0.25, 0.85, 0.45), Color(0.3, 0.6, 1.0), Color(0.9, 0.6, 0.2)][rng.randi() % 3] as Color
	var fluid = A.cyl(r, 0.46, 1.75, Vector3(0, 1.2, 0), "cream", c)
	fluid.material_override = A.mat("cream", c, 1.0, 1.2)
	var glass := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 1.85
	glass.mesh = cm
	glass.material_override = A.glass()
	r.add_child(glass)
	glass.position.y = 1.24
	for k in 8:   # bubbles
		A.sphere(r, rng.randf_range(0.015, 0.04), Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.5, 2.0), rng.randf_range(-0.3, 0.3)), "cream", c.lightened(0.5), 2.0)
	match rng.randi() % 3:
		0:   # something curled up inside
			A.sphere(r, 0.24, Vector3(0, 1.25, 0), "flesh", Color(0.85, 0.72, 0.62), 0.3, 1.3)
			A.sphere(r, 0.13, Vector3(0.05, 1.6, 0.05), "flesh", Color(0.85, 0.72, 0.62), 0.3)
			for s in [-1, 1]:
				A.seg(r, Vector3(s * 0.15, 1.3, 0), Vector3(s * 0.25, 0.9, 0.1), 0.04, 0.03, "flesh", Color(0.85, 0.72, 0.62))
		1:   # a brain on wires
			A.sphere(r, 0.16, Vector3(0, 1.3, 0), "flesh", Color(0.9, 0.65, 0.65), 0.4, 0.8)
		_:
			pass
	for k in 3:   # tubes from the cap
		var a := rng.randf() * TAU
		A.seg(r, Vector3(cos(a) * 0.3, 2.4, sin(a) * 0.3), Vector3(cos(a) * 0.4, 4.0, sin(a) * 0.4), 0.03, 0.03, "rubber")
	A.box(r, Vector3(0.25, 0.15, 0.02), Vector3(0, 0.25, -0.59), "metal", Color(0.2, 0.2, 0.2), false, 0.3)
	A.glow(r, Vector3(0.18, 0.07, 0.01), Vector3(0, 0.25, -0.6), c, 2.0)
	B.omni(r, Vector3(0, 1.3, -0.8), c, 0.5, 4.0)


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


## A mound of scrap: a dirt-and-rust heap with junk half buried in it.
static func scrap_heap(parent: Node, pos: Vector3, rng: RandomNumberGenerator, size := 1.0) -> void:
	var mound := A.sphere(parent, 3.0 * size, pos + Vector3(0, -0.6 * size, 0), "dirt", Color(0.95, 0.85, 0.75), 0.0, 0.55)
	mound.scale = Vector3(1.0, 1.0, rng.randf_range(0.8, 1.2))
	B.invisible_wall(parent, Vector3(3.4, 1.4, 3.4) * size, pos + Vector3(0, 0.5 * size, 0))   # rough collision
	var kinds := ["rust", "metal", "wood", "corrugated", "copper", "plastic"]
	for i in int(rng.randi_range(34, 48) * size):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 2.7 * size
		var h := maxf(0.0, (1.0 - d / (2.9 * size)) * 1.6 * size)
		var p := pos + Vector3(cos(a) * d, h, sin(a) * d)
		var s := rng.randf_range(0.25, 1.1)
		var k: String = kinds[rng.randi() % kinds.size()]
		var tint := Color.WHITE if k != "plastic" else Color.from_hsv(rng.randf(), 0.5, 0.75)
		match rng.randi() % 4:
			0:
				A.cyl(parent, s * 0.25, s * 1.6, p, "rust", Color.WHITE, false, ["x", "z"][rng.randi() % 2])
			1:
				A.ring(parent, s * 0.45, s * 0.25, p, "rubber", Color.WHITE, Vector3(rng.randf(), rng.randf() * TAU, rng.randf()))
			_:
				A.box(parent, Vector3(s, s * rng.randf_range(0.1, 0.6), s * rng.randf_range(0.5, 1.5)), p, k, tint, false, 1.0, Vector3(rng.randf() - 0.5, rng.randf() * TAU, rng.randf() - 0.5))


## Supply depot in a shipping container: roll-up shutter, awning, counter with a terminal, a robot clerk,
## the stock on the back wall with price tags, a neon sign on the roof. Front (-z) is open.
static func shop_container(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator, on_use: Callable) -> Node3D:
	var r := _root(parent, pos, rot_y)
	var c := Color(0.72, 0.24, 0.16)
	var frame := c.darkened(0.4)
	A.box(r, Vector3(6.0, 2.6, 0.08), Vector3(0, 1.3, 1.2), "corrugated", c, true, 0.9)
	for s in [-1, 1]:
		A.box(r, Vector3(0.08, 2.6, 2.4), Vector3(s * 3.0, 1.3, 0), "corrugated", c, true, 0.9)
		for sz in [-1, 1]:
			A.box(r, Vector3(0.16, 2.75, 0.16), Vector3(s * 2.98, 1.37, sz * 1.18), "metal", frame, false, 0.5)
			for y in [0.07, 2.68]:
				A.box(r, Vector3(0.2, 0.14, 0.2), Vector3(s * 2.98, y, sz * 1.18), "metal", Color(0.22, 0.22, 0.22), false, 0.3)
	A.box(r, Vector3(6.1, 0.1, 2.5), Vector3(0, 2.68, 0), "corrugated", c.darkened(0.2), true, 1.2)
	A.box(r, Vector3(5.9, 0.12, 2.3), Vector3(0, 0.06, 0), "riveted", Color(0.55, 0.55, 0.55), true, 1.0)
	# Roll-up shutter, mostly up.
	A.box(r, Vector3(5.9, 0.4, 0.4), Vector3(0, 2.4, -1.15), "metal", Color(0.35, 0.35, 0.35), false, 0.5)
	for k in 2:
		A.box(r, Vector3(5.8, 0.1, 0.03), Vector3(0, 2.15 - k * 0.1, -1.18), "metal", Color(0.6, 0.6, 0.58).darkened((k % 2) * 0.1), false, 0.4)
	A.box(r, Vector3(5.8, 0.06, 0.06), Vector3(0, 2.02, -1.18), "metal", Color(0.25, 0.25, 0.25), false)
	# Awning on two brackets, a strip light under it.
	var awn := A.box(r, Vector3(6.6, 0.05, 1.8), Vector3(0, 2.72, -2.0), "corrugated", Color(0.85, 0.8, 0.65), false, 0.8)
	awn.rotation.x = 0.22
	A.box(r, Vector3(6.6, 0.25, 0.04), Vector3(0, 2.42, -2.88), "metal", Color(0.85, 0.72, 0.2), false, 0.5)
	for s in [-1, 1]:
		A.seg(r, Vector3(s * 2.9, 2.0, -1.22), Vector3(s * 2.9, 2.55, -2.8), 0.03, 0.03, "metal", frame)
	A.glow(r, Vector3(4.0, 0.04, 0.1), Vector3(0, 2.52, -2.1), Color(1, 0.9, 0.7), 4.0)
	# Counter.
	A.box(r, Vector3(4.6, 1.0, 0.5), Vector3(0, 0.62, -0.75), "wood", Color(0.7, 0.58, 0.45), true, 0.8)
	A.box(r, Vector3(4.8, 0.06, 0.65), Vector3(0, 1.15, -0.78), "metal", Color(0.65, 0.65, 0.62), false, 0.5)
	A.box(r, Vector3(4.6, 0.08, 0.02), Vector3(0, 0.2, -1.01), "metal", Color(0.3, 0.3, 0.3), false)
	var plate := B.label(r, "SUPPLIES", Vector3(0, 0.75, -1.01), 60, Color(0.95, 0.85, 0.55), "stencil", 0.007)
	plate.rotation.y = PI
	var term := Node3D.new()
	r.add_child(term)
	term.position = Vector3(-1.4, 1.18, -0.75)
	A.crt(term, Vector3.ZERO, true)
	B.interactable(r, Vector3(0.42, 0.34, 0.1), Vector3(-1.4, 1.43, -1.03), Color(1, 0.6, 0.2), "Use shop terminal (upgrades)", on_use, 0.0, 1.4)
	# Cash register, bell, ledger.
	A.box(r, Vector3(0.4, 0.2, 0.35), Vector3(0.2, 1.28, -0.75), "metal", Color(0.3, 0.32, 0.3), false, 0.3)
	A.box(r, Vector3(0.36, 0.12, 0.2), Vector3(0.2, 1.42, -0.82), "keys", Color.WHITE, false, 0.2, Vector3(-0.4, 0, 0))
	A.glow(r, Vector3(0.22, 0.07, 0.02), Vector3(0.2, 1.52, -0.66), Color(0.3, 1, 0.45), 2.5)
	A.cyl(r, 0.06, 0.05, Vector3(1.5, 1.2, -0.9), "brass")
	A.sphere(r, 0.02, Vector3(1.5, 1.25, -0.9), "brass")
	A.box(r, Vector3(0.3, 0.03, 0.22), Vector3(0.2, 1.19, -0.8), "paper", Color(0.9, 0.86, 0.72), false, 0.3, Vector3(0, 0.3, 0))
	# Clerk.
	A.robot(r, Vector3(-2.3, 0.12, -0.25), PI - 0.4)
	# Stock on the back wall: real item models on a shelf, price tags under each.
	for y in [1.6, 2.15]:
		A.box(r, Vector3(5.4, 0.05, 0.45), Vector3(0, y, 0.92), "wood", Color(0.65, 0.55, 0.45), false, 0.6)
		for x in [-2.6, 0.3, 2.6]:
			A.box(r, Vector3(0.05, 0.3, 0.42), Vector3(x, y - 0.15, 0.92), "metal", Color(0.3, 0.3, 0.3), false)
	var stock := ["FLASHLIGHT", "LANTERN", "SCANNER", "BACKPACK"]
	for i in stock.size():
		var id: String = stock[i]
		var x := -1.5 + i * 1.2
		var m := Items.build(id)
		r.add_child(m)
		var sz: Vector3 = Data.ITEMS[id].size
		m.scale = Vector3.ONE * 1.6   # display pieces, so they read from the counter
		m.position = Vector3(x, 1.63 + sz.y * 0.8, 0.88)
		m.rotation.y = PI + rng.randf_range(-0.4, 0.4)
		var tag := B.label(r, "%dc" % int(Data.ITEMS[id].price), Vector3(x, 1.52, 0.68), 40, Color(0.12, 0.1, 0.08), "type", 0.004)
		tag.rotation.y = PI
		A.box(r, Vector3(0.22, 0.09, 0.005), Vector3(x, 1.52, 0.685), "paper", Color(0.95, 0.92, 0.8), false, 0.2)
	for k in 7:   # boxed spares on the top shelf
		var s := Vector3(rng.randf_range(0.3, 0.5), rng.randf_range(0.2, 0.3), 0.35)
		A.box(r, s, Vector3(-2.4 + k * 0.75, 2.18 + s.y * 0.45, 0.92), "cardboard", Color.WHITE.darkened(rng.randf() * 0.3), false, 0.5)
	# Neon sign on a frame on the roof.
	for s in [-1, 1]:
		A.box(r, Vector3(0.1, 1.2, 0.1), Vector3(s * 1.4, 3.3, -0.6), "metal", frame, false)
	A.box(r, Vector3(3.2, 0.9, 0.1), Vector3(0, 3.55, -0.6), "metal", Color(0.12, 0.12, 0.13), false, 0.5)
	var neon := B.display(r, "SHOP", Vector3(0, 3.55, -0.66), 140, Color(1, 0.75, 0.35))
	neon.rotation.y = PI
	neon.modulate = Color(2.5, 1.6, 0.6)
	for x in [-1.45, 1.45]:
		A.glow(r, Vector3(0.06, 0.8, 0.02), Vector3(x, 3.55, -0.66), Color(1, 0.4, 0.15), 4.0)
	# Out front: a chalk board, stools, barrels.
	var board := _root(r, Vector3(-2.2, 0.06, -3.3), 0.3)
	for side in [-1, 1]:   # A-frame: two boards leaning together at the top
		var leaf := Node3D.new()
		board.add_child(leaf)
		leaf.position = Vector3(0, 0.55, side * 0.14)
		leaf.rotation.x = -side * 0.26
		A.box(leaf, Vector3(0.62, 1.1, 0.03), Vector3.ZERO, "wood", Color(0.55, 0.42, 0.3), false, 0.5)
		A.box(leaf, Vector3(0.52, 0.85, 0.01), Vector3(0, 0.03, side * 0.02), "board", Color.WHITE, false, 0.5)
		if side < 0:
			var chalk := B.label(leaf, "TODAY\n\nlights\nscanners\npacks\n\nno refunds", Vector3(0, 0.05, -0.03), 40, Color(0.92, 0.94, 0.9), "chalk", 0.0035)
			chalk.rotation.y = PI
	for x in [0.6, 1.6]:
		A.cyl(r, 0.18, 0.04, Vector3(x, 0.72, -1.4), "canvas", Color(0.5, 0.15, 0.12))
		A.seg(r, Vector3(x, 0, -1.4), Vector3(x, 0.7, -1.4), 0.03, 0.03, "metal", Color(0.4, 0.4, 0.4))
	A.barrel(r, Vector3(3.6, 0, -0.5), rng)
	A.barrel(r, Vector3(3.5, 0, 0.3), rng)
	B.omni(r, Vector3(0, 2.2, 0.2), Color(1, 0.85, 0.6), 1.2, 6.0)
	B.omni(r, Vector3(0, 2.3, -2.4), Color(1, 0.75, 0.45), 1.4, 8.0, true)
	return r


# --- room clutter -----------------------------------------------------------------------------

const CAN_COLORS := [Color(0.8, 0.15, 0.1), Color(0.2, 0.4, 0.8), Color(0.25, 0.6, 0.25), Color(0.75, 0.75, 0.75), Color(0.9, 0.75, 0.2)]


## Floor litter scattered over a square of half-size `half`: papers, cans, bottles, flattened boxes, rags, bits of debris.
static func litter(parent: Node, o: Vector3, half: float, rng: RandomNumberGenerator, n: int) -> void:
	for i in n:
		var p := o + Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half))
		var a := rng.randf() * TAU
		match rng.randi() % 9:
			0, 1:
				A.box(parent, Vector3(0.21, 0.003, 0.29), p + Vector3(0, 0.003, 0), "paper", Color.WHITE.darkened(rng.randf() * 0.35), false, 0.3, Vector3(0, a, 0))
			2:
				var can := A.cyl(parent, 0.033, 0.12, p + Vector3(0, 0.033, 0), "metal", CAN_COLORS[rng.randi() % CAN_COLORS.size()], false, "x")
				can.rotation.y = a
			3:
				var bottle = A.cyl(parent, 0.035, 0.22, p + Vector3(0, 0.035, 0), "metal", Color.WHITE, false, "x")
				bottle.rotation.y = a
				bottle.material_override = A.glass()
			4:
				A.box(parent, Vector3(0.6, 0.012, 0.45), p + Vector3(0, 0.006, 0), "cardboard", Color.WHITE.darkened(rng.randf() * 0.3), false, 0.5, Vector3(0, a, 0))
			5:
				A.box(parent, Vector3(0.32, 0.025, 0.25), p + Vector3(0, 0.012, 0), "canvas", Color.from_hsv(rng.randf(), 0.25, 0.35), false, 0.3, Vector3(0.1, a, 0.05))
			6:
				var s := rng.randf_range(0.06, 0.18)
				A.box(parent, Vector3(s, s * 0.7, s), p + Vector3(0, s * 0.3, 0), "concrete", Color.WHITE, false, 0.5, Vector3(rng.randf(), a, rng.randf()))
			7:
				var cup := A.cyl(parent, 0.04, 0.1, p + Vector3(0, 0.04, 0), "paper", Color(0.92, 0.9, 0.85), false, "x", 0.03)
				cup.rotation.y = a
			8:
				A.box(parent, Vector3(0.5, 0.04, 0.08), p + Vector3(0, 0.02, 0), "wood", Color(0.7, 0.65, 0.6), false, 0.5, Vector3(0, a, 0))   # broken plank


## Something fixed to a wall. pos = foot of the wall (y = floor), normal = into the room.
static func wall_fixture(parent: Node, pos: Vector3, normal: Vector3, rng: RandomNumberGenerator, wet := false) -> void:
	var r := Node3D.new()
	parent.add_child(r)
	r.position = pos
	r.rotation.y = atan2(normal.x, normal.z)   # +z points into the room
	var grey := Color(0.55, 0.57, 0.55)
	match rng.randi() % (11 if wet else 10):
		0:   # electrical box with a conduit up into the ceiling
			A.box(r, Vector3(0.42, 0.55, 0.16), Vector3(0, 1.5, 0.08), "metal", grey, false, 0.5)
			A.box(r, Vector3(0.004, 0.5, 0.004), Vector3(0, 1.5, 0.162), "metal", Color(0.1, 0.1, 0.1), false)
			A.box(r, Vector3(0.12, 0.1, 0.004), Vector3(0, 1.66, 0.162), "hazard", Color.WHITE, false, 0.2)
			A.seg(r, Vector3(0.1, 1.78, 0.05), Vector3(0.1, 4.0, 0.05), 0.02, 0.02, "metal", grey)
			A.box(r, Vector3(0.03, 0.06, 0.03), Vector3(0.2, 1.45, 0.17), "metal", Color(0.2, 0.2, 0.2), false)
		1:   # radiator
			for k in 9:
				A.box(r, Vector3(0.07, 0.6, 0.1), Vector3(-0.42 + k * 0.105, 0.5, 0.08), "metal", Color(0.85, 0.82, 0.72), false, 0.5)
			A.seg(r, Vector3(-0.5, 0.25, 0.08), Vector3(0.5, 0.25, 0.08), 0.02, 0.02, "metal", Color(0.85, 0.82, 0.72))
			A.cyl(r, 0.03, 0.04, Vector3(0.52, 0.75, 0.08), "metal", Color(0.6, 0.6, 0.6), false, "x")
		2:   # wall shelf with stuff on it
			for x in [-0.45, 0.45]:
				A.box(r, Vector3(0.03, 0.2, 0.25), Vector3(x, 1.5, 0.13), "metal", Color(0.3, 0.3, 0.3), false)
			A.box(r, Vector3(1.2, 0.03, 0.28), Vector3(0, 1.62, 0.14), "wood", Color(0.75, 0.65, 0.55), false, 0.5)
			var x := -0.5
			while x < 0.45:
				if rng.randf() < 0.5:
					var s := Vector3(rng.randf_range(0.12, 0.25), rng.randf_range(0.1, 0.25), 0.2)
					A.box(r, s, Vector3(x + s.x / 2, 1.635 + s.y / 2, 0.14), "cardboard", Color.WHITE.darkened(rng.randf() * 0.3), false, 0.4)
					x += s.x + 0.04
				else:
					A.cyl(r, 0.04, 0.12, Vector3(x + 0.05, 1.695, 0.12), "metal", CAN_COLORS[rng.randi() % CAN_COLORS.size()])
					x += 0.11
		3:   # whiteboard with scribbles
			A.box(r, Vector3(1.5, 0.95, 0.03), Vector3(0, 1.55, 0.015), "metal", Color(0.75, 0.75, 0.75), false, 0.5)
			A.box(r, Vector3(1.42, 0.87, 0.01), Vector3(0, 1.55, 0.032), "paper", Color(0.95, 0.95, 0.93), false, 1.0)
			for k in rng.randi_range(3, 7):
				A.box(r, Vector3(rng.randf_range(0.2, 0.7), 0.012, 0.002), Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(1.2, 1.9), 0.038), "metal",
					[Color(0.1, 0.1, 0.4), Color(0.6, 0.05, 0.05), Color(0.05, 0.3, 0.1)][rng.randi() % 3], false, 0.2, Vector3(0, 0, rng.randf_range(-0.3, 0.3)))
			A.box(r, Vector3(0.8, 0.03, 0.05), Vector3(0, 1.08, 0.04), "metal", Color(0.6, 0.6, 0.6), false)
		4:   # cork board with pinned notes
			A.box(r, Vector3(1.0, 0.7, 0.03), Vector3(0, 1.6, 0.015), "cardboard", Color(0.8, 0.6, 0.4), false, 0.3)
			for k in rng.randi_range(4, 9):
				A.box(r, Vector3(rng.randf_range(0.12, 0.22), rng.randf_range(0.12, 0.25), 0.003), Vector3(rng.randf_range(-0.38, 0.38), rng.randf_range(1.35, 1.85), 0.033 + k * 0.0005), "paper",
					Color(0.95, 0.93, 0.8).darkened(rng.randf() * 0.25), false, 0.2, Vector3(0, 0, rng.randf_range(-0.25, 0.25)))
		5:   # wall clock, stopped
			A.cyl(r, 0.17, 0.05, Vector3(0, 2.5, 0.025), "plastic", Color(0.2, 0.2, 0.2), false, "z")
			A.cyl(r, 0.15, 0.01, Vector3(0, 2.5, 0.051), "paper", Color(0.95, 0.93, 0.85), false, "z")
			for k in 2:
				var a := rng.randf() * TAU
				var l := 0.07 if k == 0 else 0.11
				A.box(r, Vector3(0.01, l, 0.003), Vector3(sin(a) * l / 2, 2.5 + cos(a) * l / 2, 0.058), "metal", Color(0.05, 0.05, 0.05), false, 0.2, Vector3(0, 0, -a))
		6:   # extinguisher on a bracket, sign above
			A.box(r, Vector3(0.15, 0.04, 0.08), Vector3(0, 1.1, 0.04), "metal", Color(0.3, 0.3, 0.3), false)
			A.cyl(r, 0.07, 0.42, Vector3(0, 0.95, 0.1), "plastic", Color(0.8, 0.1, 0.08))
			A.sphere(r, 0.07, Vector3(0, 1.16, 0.1), "plastic", Color(0.8, 0.1, 0.08), 0.0, 0.6)
			A.box(r, Vector3(0.05, 0.05, 0.05), Vector3(0, 1.22, 0.1), "metal", Color(0.2, 0.2, 0.2), false)
			A.box(r, Vector3(0.3, 0.3, 0.01), Vector3(0, 1.6, 0.005), "plastic", Color(0.8, 0.1, 0.08), false, 0.2)
		7:   # first aid box
			A.box(r, Vector3(0.4, 0.35, 0.14), Vector3(0, 1.45, 0.07), "plastic", Color(0.92, 0.92, 0.88), false, 0.3)
			A.box(r, Vector3(0.18, 0.05, 0.004), Vector3(0, 1.47, 0.142), "plastic", Color(0.8, 0.1, 0.08), false)
			A.box(r, Vector3(0.05, 0.18, 0.004), Vector3(0, 1.47, 0.142), "plastic", Color(0.8, 0.1, 0.08), false)
		8:   # coat hooks, coats nobody came back for
			A.box(r, Vector3(1.0, 0.08, 0.03), Vector3(0, 1.75, 0.015), "wood", Color(0.6, 0.45, 0.35), false, 0.3)
			for k in 4:
				var x := -0.36 + k * 0.24
				A.seg(r, Vector3(x, 1.75, 0.03), Vector3(x, 1.8, 0.1), 0.008, 0.008, "metal", Color(0.6, 0.6, 0.6))
				if rng.randf() < 0.55:
					A.box(r, Vector3(0.36, 0.75, 0.1), Vector3(x, 1.4, 0.1), "canvas", Color.from_hsv(rng.randf(), 0.3, rng.randf_range(0.25, 0.5)), false, 0.4)
					A.box(r, Vector3(0.12, 0.08, 0.1), Vector3(x, 1.76, 0.1), "canvas", Color(0.3, 0.3, 0.3), false, 0.3)
		9:   # pipes running floor to ceiling, with a valve
			for k in 2:
				var x := -0.15 + k * 0.3
				A.seg(r, Vector3(x, 0, 0.12), Vector3(x, 4.0, 0.12), 0.06, 0.06, "rust" if k == 0 else "metal")
				for y in [0.3, 3.6]:
					A.cyl(r, 0.085, 0.06, Vector3(x, y, 0.12), "metal", Color(0.4, 0.4, 0.4))
			A.ring(r, 0.13, 0.11, Vector3(-0.15, 1.2, 0.26), "metal", Color(0.75, 0.12, 0.08), Vector3(PI / 2, 0, 0))
			A.seg(r, Vector3(-0.15, 1.2, 0.12), Vector3(-0.15, 1.2, 0.26), 0.02, 0.02, "metal", Color(0.4, 0.4, 0.4))
		10:  # sink with a mirror
			A.box(r, Vector3(0.55, 0.18, 0.42), Vector3(0, 0.85, 0.22), "plastic", Color(0.92, 0.92, 0.9), false, 0.3)
			A.box(r, Vector3(0.45, 0.01, 0.32), Vector3(0, 0.945, 0.24), "metal", Color(0.35, 0.35, 0.35), false)
			A.seg(r, Vector3(0, 0.6, 0.15), Vector3(0, 0.76, 0.15), 0.03, 0.03, "metal", Color(0.75, 0.75, 0.75))
			A.seg(r, Vector3(0, 0.94, 0.06), Vector3(0, 1.05, 0.06), 0.012, 0.012, "metal", Color(0.75, 0.75, 0.75))
			A.seg(r, Vector3(0, 1.05, 0.06), Vector3(0, 1.03, 0.16), 0.011, 0.009, "metal", Color(0.75, 0.75, 0.75))
			var m = A.box(r, Vector3(0.5, 0.65, 0.01), Vector3(0, 1.6, 0.006), "metal", Color.WHITE, false)
			m.material_override = A.glass()
			A.box(r, Vector3(0.54, 0.69, 0.008), Vector3(0, 1.6, 0.002), "metal", Color(0.4, 0.4, 0.4), false)


## Something standing against a wall. -z faces into the room. Returns its footprint (for collision bookkeeping).
static func wall_floor_item(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> Vector3:
	match rng.randi() % 9:
		0:   # bin, maybe overflowing
			var r := _root(parent, pos, rot_y)
			A.cyl(r, 0.2, 0.55, Vector3(0, 0.275, 0), "metal", Color(0.45, 0.47, 0.45), false, "y", 0.22)
			A.ring(r, 0.225, 0.2, Vector3(0, 0.55, 0), "metal", Color(0.35, 0.35, 0.35))
			if rng.randf() < 0.6:
				litter(r, Vector3(0, 0, -0.3), 0.3, rng, 4)
			return Vector3(0.5, 0.6, 0.5)
		1:   # mop bucket + mop
			var r := _root(parent, pos, rot_y)
			A.box(r, Vector3(0.45, 0.32, 0.35), Vector3(0, 0.2, 0), "plastic", Color(0.95, 0.8, 0.1), false, 0.3)
			A.box(r, Vector3(0.4, 0.01, 0.3), Vector3(0, 0.355, 0), "dirt", Color(0.3, 0.28, 0.2), false, 0.3)
			for x in [-0.18, 0.18]:
				A.cyl(r, 0.03, 0.03, Vector3(x, 0.02, 0.14), "rubber", Color.WHITE, false, "x")
			A.seg(r, Vector3(0.05, 0.25, 0.0), Vector3(0.15, 1.45, 0.2), 0.012, 0.012, "wood")
			A.box(r, Vector3(0.12, 0.15, 0.12), Vector3(0.04, 0.3, 0.0), "canvas", Color(0.7, 0.65, 0.55), false, 0.3)
			return Vector3(0.5, 0.4, 0.4)
		2:   # stack of boxes
			var r := _root(parent, pos, rot_y + rng.randf_range(-0.2, 0.2))
			var y := 0.0
			for k in rng.randi_range(2, 4):
				var s := Vector3(rng.randf_range(0.4, 0.6), rng.randf_range(0.25, 0.4), rng.randf_range(0.35, 0.5))
				var bx := A.box(r, s, Vector3(rng.randf_range(-0.04, 0.04), y + s.y / 2, 0), "cardboard", Color.WHITE.darkened(rng.randf() * 0.3), false, 0.5, Vector3(0, rng.randf_range(-0.2, 0.2), 0))
				A.box(bx, Vector3(s.x * 1.01, 0.004, 0.05), Vector3(0, s.y / 2, 0), "plastic", Color(0.75, 0.65, 0.45), false, 0.3)
				y += s.y
			return Vector3(0.6, y, 0.5)
		3:   # broom leaning on the wall
			var r := _root(parent, pos, rot_y)
			A.seg(r, Vector3(0, 0.15, 0.0), Vector3(0, 1.45, 0.3), 0.013, 0.013, "wood")
			A.box(r, Vector3(0.3, 0.18, 0.06), Vector3(0, 0.09, -0.02), "wood", Color(0.75, 0.6, 0.35), false, 0.3, Vector3(-0.22, 0, 0))
			return Vector3.ZERO
		4:   # rolling tool cabinet
			var r := _root(parent, pos, rot_y)
			var c := Color(0.75, 0.12, 0.08) if rng.randf() < 0.6 else Color(0.2, 0.3, 0.6)
			A.box(r, Vector3(0.7, 0.85, 0.45), Vector3(0, 0.52, 0), "metal", c, false, 0.5)
			for k in 5:
				A.box(r, Vector3(0.64, 0.12, 0.01), Vector3(0, 0.25 + k * 0.155, -0.226), "metal", c.lightened(0.1), false, 0.3)
				A.box(r, Vector3(0.3, 0.015, 0.02), Vector3(0, 0.29 + k * 0.155, -0.235), "metal", Color(0.75, 0.75, 0.75), false)
			for x in [-0.3, 0.3]:
				for z in [-0.18, 0.18]:
					A.cyl(r, 0.045, 0.03, Vector3(x, 0.045, z), "rubber", Color.WHITE, false, "x")
			return Vector3(0.75, 1.0, 0.5)
		5:   # gas cylinders chained to the wall
			var r := _root(parent, pos, rot_y)
			for k in rng.randi_range(2, 3):
				var c: Color = [Color(0.2, 0.4, 0.25), Color(0.6, 0.6, 0.6), Color(0.15, 0.2, 0.45), Color(0.75, 0.55, 0.1)][rng.randi() % 4]
				var x := -0.25 + k * 0.25
				A.cyl(r, 0.11, 1.25, Vector3(x, 0.625, 0), "metal", c)
				A.sphere(r, 0.11, Vector3(x, 1.25, 0), "metal", c, 0.0, 0.7)
				A.cyl(r, 0.035, 0.1, Vector3(x, 1.36, 0), "brass")
			A.seg(r, Vector3(-0.4, 1.0, 0.12), Vector3(0.4, 1.0, 0.12), 0.008, 0.008, "metal", Color(0.4, 0.4, 0.4))
			return Vector3(0.8, 1.4, 0.3)
		6:   # water cooler
			var r := _root(parent, pos, rot_y)
			A.box(r, Vector3(0.32, 0.95, 0.32), Vector3(0, 0.475, 0), "plastic", Color(0.9, 0.9, 0.86), false, 0.3)
			for x in [-0.06, 0.06]:
				A.box(r, Vector3(0.03, 0.04, 0.04), Vector3(x, 0.8, -0.17), "plastic", Color(0.8, 0.15, 0.1) if x > 0 else Color(0.2, 0.4, 0.8), false)
			var jug = A.cyl(r, 0.14, 0.42, Vector3(0, 1.17, 0), "metal", Color.WHITE)
			jug.material_override = A.mat("plastic", Color(0.55, 0.75, 0.95), 0.3)
			A.cyl(r, 0.04, 0.05, Vector3(0, 0.97, 0), "plastic", Color(0.55, 0.75, 0.95))
			return Vector3(0.35, 1.4, 0.35)
		7:   # dead potted plant
			var r := _root(parent, pos, rot_y)
			A.cyl(r, 0.2, 0.4, Vector3(0, 0.2, 0), "concrete", Color(0.7, 0.45, 0.35), false, "y", 0.24)
			A.cyl(r, 0.21, 0.02, Vector3(0, 0.39, 0), "dirt", Color(0.4, 0.3, 0.2))
			for k in rng.randi_range(4, 7):
				var a := rng.randf() * TAU
				var tip := Vector3(cos(a) * rng.randf_range(0.1, 0.35), rng.randf_range(0.8, 1.4), sin(a) * rng.randf_range(0.1, 0.35))
				A.seg(r, Vector3(0, 0.4, 0), tip, 0.012, 0.004, "wood", Color(0.55, 0.45, 0.3))
				A.box(r, Vector3(0.08, 0.005, 0.04), tip, "leaf", Color(0.6, 0.5, 0.3), false, 0.2, Vector3(rng.randf(), a, 0.6))
			return Vector3(0.45, 0.4, 0.45)
		_:   # pile of lumber / pipe offcuts
			var r := _root(parent, pos, rot_y)
			for k in rng.randi_range(4, 8):
				if rng.randf() < 0.5:
					A.box(r, Vector3(1.4, 0.06, 0.12), Vector3(rng.randf_range(-0.1, 0.1), 0.03 + k * 0.05, rng.randf_range(-0.15, 0.15)), "wood", Color.WHITE.darkened(rng.randf() * 0.3), false, 1.0, Vector3(0, rng.randf_range(-0.15, 0.15), 0))
				else:
					A.cyl(r, 0.04, 1.4, Vector3(rng.randf_range(-0.1, 0.1), 0.04 + k * 0.05, rng.randf_range(-0.15, 0.15)), "rust", Color.WHITE, false, "x")
			return Vector3(1.5, 0.4, 0.5)


## Office cubicle: two fabric partitions in an L around a desk spot. -z = open side.
static func partition(parent: Node, pos: Vector3, rot_y: float, side := 1.0) -> void:
	var r := _root(parent, pos, rot_y)
	var fab: Color = [Color(0.4, 0.45, 0.55), Color(0.5, 0.48, 0.42), Color(0.45, 0.5, 0.45)][randi() % 3]
	var frame := Color(0.7, 0.7, 0.68)
	for p in [[Vector3(0, 0.7, 0.95), Vector3(2.0, 1.4, 0.06)], [Vector3(1.05 * side, 0.7, 0.0), Vector3(0.06, 1.4, 1.9)]]:
		var c: Vector3 = p[0]
		var s: Vector3 = p[1]
		A.box(r, s, c, "canvas", fab, false, 0.6)
		A.box(r, Vector3(s.x + 0.02, 0.04, s.z + 0.02), c + Vector3(0, 0.72, 0), "metal", frame, false, 0.5)
	A.box(r, Vector3(0.3, 0.2, 0.003), Vector3(randf_range(-0.6, 0.6), 1.05, 0.915), "paper", Color(0.95, 0.93, 0.8), false, 0.2, Vector3(0, PI, randf_range(-0.2, 0.2)))


## Tall pallet rack: orange uprights, blue beams, pallets with boxed or wrapped loads. -z faces the aisle.
static func pallet_rack(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator, w := 2.7) -> void:
	var r := _root(parent, pos, rot_y, Vector3(w, 3.2, 1.1))
	for x in [-w / 2, w / 2]:
		for z in [-0.5, 0.5]:
			A.box(r, Vector3(0.08, 3.2, 0.08), Vector3(x, 1.6, z), "metal", Color(0.85, 0.45, 0.1), false, 0.5)
		for y in [0.4, 1.2, 2.0, 2.8]:
			A.box(r, Vector3(0.04, 0.04, 1.0), Vector3(x, y, 0), "metal", Color(0.85, 0.45, 0.1), false, 0.5)
	for y in [0.15, 1.25, 2.35]:
		for z in [-0.5, 0.5]:
			A.box(r, Vector3(w, 0.1, 0.06), Vector3(0, y, z), "metal", Color(0.2, 0.3, 0.6), false, 0.5)
		for k in 2:
			if rng.randf() < 0.75:
				var px := (k - 0.5) * w * 0.5
				A.pallet(r, Vector3(px, y + 0.05, 0))
				var top: float = y + 0.2
				if rng.randf() < 0.5:   # shrink-wrapped load
					var h := rng.randf_range(0.5, 0.9)
					A.box(r, Vector3(1.1, h, 0.95), Vector3(px, top + h / 2, 0), "plastic", Color(0.85, 0.85, 0.82).darkened(rng.randf() * 0.2), false, 0.6)
				else:
					for b in rng.randi_range(2, 5):
						var s := Vector3(0.5, rng.randf_range(0.3, 0.45), 0.45)
						A.box(r, s, Vector3(px + ((b % 2) - 0.5) * 0.52, top + (b / 2) * 0.45 + s.y / 2, rng.randf_range(-0.2, 0.2)), "cardboard", Color.WHITE.darkened(rng.randf() * 0.3), false, 0.5)


## Workbench against a wall: pegboard of tools, vice, clutter. -z faces into the room.
static func workbench(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rot_y, Vector3(2.0, 0.95, 0.8))
	A.box(r, Vector3(2.0, 0.08, 0.8), Vector3(0, 0.9, 0), "wood", Color(0.7, 0.55, 0.4), false, 1.0)
	A.box(r, Vector3(1.9, 0.04, 0.7), Vector3(0, 0.25, 0), "wood", Color(0.6, 0.48, 0.35), false, 1.0)
	for x in [-0.9, 0.9]:
		for z in [-0.33, 0.33]:
			A.box(r, Vector3(0.07, 0.86, 0.07), Vector3(x, 0.43, z), "metal", Color(0.3, 0.3, 0.3), false)
	A.box(r, Vector3(2.0, 1.1, 0.03), Vector3(0, 1.6, 0.39), "cardboard", Color(0.7, 0.6, 0.45), false, 0.4)   # pegboard
	for k in rng.randi_range(5, 9):   # tools on the pegboard
		var x := rng.randf_range(-0.85, 0.85)
		var y := rng.randf_range(1.2, 2.0)
		match rng.randi() % 3:
			0:
				A.box(r, Vector3(0.025, 0.25, 0.01), Vector3(x, y, 0.36), "metal", Color(0.75, 0.75, 0.75), false, 0.2)
			1:
				A.box(r, Vector3(0.03, 0.22, 0.02), Vector3(x, y, 0.36), "wood", Color.WHITE, false, 0.2)
				A.box(r, Vector3(0.1, 0.035, 0.03), Vector3(x, y + 0.12, 0.36), "metal", Color(0.45, 0.45, 0.45), false, 0.2)
			2:
				A.ring(r, 0.05, 0.03, Vector3(x, y, 0.36), "plastic", Color(0.8, 0.2, 0.15), Vector3(PI / 2, 0, 0))
	A.box(r, Vector3(0.2, 0.12, 0.15), Vector3(-0.7, 1.0, -0.3), "metal", Color(0.25, 0.35, 0.5), false, 0.2)   # vice
	A.seg(r, Vector3(-0.7, 1.0, -0.38), Vector3(-0.7, 1.0, -0.48), 0.012, 0.012, "metal", Color(0.75, 0.75, 0.75))
	for k in rng.randi_range(3, 6):
		var s := rng.randf_range(0.05, 0.15)
		A.box(r, Vector3(s, s * 0.6, s * 1.5), Vector3(rng.randf_range(-0.4, 0.8), 0.94 + s * 0.3, rng.randf_range(-0.3, 0.3)), ["metal", "rust", "wood", "plastic"][rng.randi() % 4], Color.WHITE, false, 0.3, Vector3(0, rng.randf() * TAU, 0))
	A.cyl(r, 0.08, 0.12, Vector3(0.6, 1.0, 0.1), "metal", Color(0.6, 0.6, 0.6))   # can of screws


## Lumpy old sofa. -z = seat front.
static func sofa(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rot_y, Vector3(2.0, 0.85, 0.9))
	var c := Color.from_hsv(rng.randf(), 0.35, 0.4)
	A.box(r, Vector3(2.0, 0.3, 0.9), Vector3(0, 0.25, 0), "canvas", c.darkened(0.2), false, 0.6)
	for k in 3:
		var cushion := A.box(r, Vector3(0.6, 0.14, 0.7), Vector3(-0.62 + k * 0.62, 0.46, -0.05), "canvas", c, false, 0.5)
		cushion.rotation = Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.06, 0.06), rng.randf_range(-0.05, 0.05))
	A.box(r, Vector3(2.0, 0.5, 0.2), Vector3(0, 0.6, 0.35), "canvas", c, false, 0.6, Vector3(-0.15, 0, 0))
	for s in [-1, 1]:
		A.box(r, Vector3(0.2, 0.55, 0.9), Vector3(s * 0.95, 0.4, 0), "canvas", c.darkened(0.1), false, 0.6)
	if rng.randf() < 0.5:
		A.box(r, Vector3(0.25, 0.08, 0.2), Vector3(0.3, 0.55, -0.1), "canvas", Color(0.85, 0.82, 0.7), false, 0.3)   # stuffing poking out


## Low table + old TV on a stand.
static func tv_corner(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rot_y, Vector3(1.0, 1.1, 0.6))
	A.box(r, Vector3(1.0, 0.5, 0.5), Vector3(0, 0.25, 0), "wood", Color(0.5, 0.38, 0.28), false, 0.8)
	A.box(r, Vector3(0.65, 0.5, 0.45), Vector3(0, 0.75, 0.05), "wood", Color(0.35, 0.25, 0.2), false, 0.5)
	A.glow(r, Vector3(0.48, 0.36, 0.02), Vector3(-0.05, 0.75, -0.18), Color(0.4, 0.5, 0.55) if rng.randf() < 0.2 else Color(0.06, 0.07, 0.07), 1.0)
	for k in 2:
		A.cyl(r, 0.025, 0.02, Vector3(0.24, 0.85 - k * 0.1, -0.18), "plastic", Color(0.2, 0.2, 0.2), false, "z")
	A.seg(r, Vector3(-0.1, 1.0, 0.1), Vector3(-0.3, 1.35, 0.15), 0.005, 0.005, "metal", Color(0.6, 0.6, 0.6))
	A.seg(r, Vector3(0.1, 1.0, 0.1), Vector3(0.3, 1.35, 0.15), 0.005, 0.005, "metal", Color(0.6, 0.6, 0.6))


## Fume hood for labs. -z faces into the room.
static func fume_hood(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rot_y, Vector3(1.6, 2.4, 0.9))
	var c := Color(0.85, 0.85, 0.8)
	A.box(r, Vector3(1.6, 0.9, 0.85), Vector3(0, 0.45, 0), "plastic", c, false, 0.6)
	for x in [-0.4, 0.4]:
		A.box(r, Vector3(0.7, 0.7, 0.01), Vector3(x, 0.45, -0.43), "plastic", c.darkened(0.08), false, 0.5)
	A.box(r, Vector3(1.6, 1.3, 0.1), Vector3(0, 1.55, 0.38), "plastic", c, false, 0.6)
	for s in [-1, 1]:
		A.box(r, Vector3(0.1, 1.3, 0.85), Vector3(s * 0.75, 1.55, 0), "plastic", c, false, 0.6)
	A.box(r, Vector3(1.6, 0.3, 0.85), Vector3(0, 2.25, 0), "plastic", c, false, 0.6)
	var sash = A.box(r, Vector3(1.4, 0.7, 0.01), Vector3(0, 1.75, -0.4), "metal", Color.WHITE, false)
	sash.material_override = A.glass()
	A.box(r, Vector3(1.4, 0.02, 0.6), Vector3(0, 0.91, 0.0), "tiles", Color(0.3, 0.3, 0.32), false, 0.3)
	A.seg(r, Vector3(0, 2.4, 0.1), Vector3(0, 4.0, 0.1), 0.15, 0.15, "metal", Color(0.65, 0.65, 0.65))   # exhaust duct
	for k in rng.randi_range(2, 4):
		var c2: Color = [Color(0.3, 1, 0.4), Color(1, 0.5, 0.2), Color(0.4, 0.5, 1)][rng.randi() % 3]
		var p := Vector3(rng.randf_range(-0.5, 0.5), 0.92, rng.randf_range(-0.15, 0.2))
		var liquid = A.cyl(r, 0.035, 0.08, p + Vector3(0, 0.04, 0), "cream", c2)
		liquid.material_override = A.mat("cream", c2, 1.0, 1.5)
		var g = A.cyl(r, 0.04, 0.16, p + Vector3(0, 0.08, 0), "metal")
		g.material_override = A.glass()
	A.glow(r, Vector3(1.3, 0.02, 0.05), Vector3(0, 2.08, -0.1), Color(0.85, 0.95, 1.0), 2.0 if rng.randf() < 0.5 else 0.1)


## Somebody lived down here: mattress, sleeping bag, a fire in a barrel, cans everywhere.
static func camp(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rng.randf() * TAU)
	A.box(r, Vector3(0.95, 0.15, 1.9), Vector3(0, 0.075, 0), "canvas", Color(0.75, 0.72, 0.6), false, 0.6)
	A.box(r, Vector3(0.9, 0.04, 1.85), Vector3(0, 0.16, 0), "canvas", Color(0.55, 0.5, 0.4), false, 0.5)
	A.box(r, Vector3(0.75, 0.12, 1.3), Vector3(0.05, 0.22, 0.2), "canvas", Color(0.25, 0.35, 0.3), false, 0.5, Vector3(0, 0.1, 0))   # sleeping bag
	A.cyl(r, 0.15, 0.4, Vector3(0.05, 0.22, -0.7), "canvas", Color(0.25, 0.35, 0.3), false, "x")
	A.box(r, Vector3(0.4, 0.12, 0.3), Vector3(0, 0.2, -0.75), "canvas", Color(0.85, 0.82, 0.75), false, 0.3)   # pillow
	var fire := Vector3(1.4, 0, 0.3)
	A.cyl(r, 0.3, 0.75, fire + Vector3(0, 0.375, 0), "rust", Color(0.6, 0.5, 0.45))
	for k in 6:
		var a := TAU * k / 6.0
		A.box(r, Vector3(0.06, 0.06, 0.08), fire + Vector3(cos(a) * 0.3, 0.55, sin(a) * 0.3), "rust", Color(0.2, 0.15, 0.1), false, 0.2)
	if rng.randf() < 0.5:
		A.glow(r, Vector3(0.4, 0.05, 0.4), fire + Vector3(0, 0.74, 0), Color(1, 0.4, 0.1), 3.0)
		B.omni(r, fire + Vector3(0, 1.0, 0), Color(1, 0.45, 0.15), 1.2, 5.0, true)
	else:
		A.cyl(r, 0.27, 0.02, fire + Vector3(0, 0.7, 0), "rust", Color(0.12, 0.1, 0.1))
	litter(r, Vector3(0.6, 0, 0), 1.3, rng, 14)
	A.cyl(r, 0.1, 0.4, Vector3(-0.8, 0.2, 0.7), "metal", Color(0.7, 0.7, 0.7))   # pot


## Ceiling junk over a room: sagging cables, dead strip lights, a vent grille, a water stain.
static func ceiling_junk(parent: Node, o: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	for k in rng.randi_range(1, 3):   # sagging cable runs
		var a := o + Vector3(rng.randf_range(-5, 5), h - 0.05, -5.5)
		var b := o + Vector3(rng.randf_range(-5, 5), h - 0.05, 5.5)
		if rng.randf() < 0.5:
			a = o + Vector3(-5.5, h - 0.05, rng.randf_range(-5, 5))
			b = o + Vector3(5.5, h - 0.05, rng.randf_range(-5, 5))
		var sag := rng.randf_range(0.4, 1.2)
		var prev := a
		for i in range(1, 7):
			var t := i / 6.0
			var p := a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0)
			A.seg(parent, prev, p, 0.015, 0.015, "rubber")
			prev = p
	if rng.randf() < 0.5:   # dead strip light hanging on one chain
		var p := o + Vector3(rng.randf_range(-3, 3), h, rng.randf_range(-3, 3))
		var hang := rng.randf_range(0.6, 1.4)
		A.seg(parent, p, p + Vector3(-0.6, -hang, 0), 0.006, 0.006, "metal", Color(0.4, 0.4, 0.4))
		var l := A.box(parent, Vector3(1.3, 0.07, 0.22), p + Vector3(-0.05, -hang - 0.35, 0), "metal", Color(0.6, 0.6, 0.6), false, 0.5)
		l.rotation.z = -0.9
	if rng.randf() < 0.6:   # vent grille
		A.box(parent, Vector3(0.7, 0.02, 0.7), o + Vector3(rng.randf_range(-4, 4), h - 0.01, rng.randf_range(-4, 4)), "grille", Color(0.75, 0.75, 0.75), false, 0.3)
	if rng.randf() < 0.5:   # water stain
		A.box(parent, Vector3(rng.randf_range(1.0, 2.5), 0.005, rng.randf_range(1.0, 2.5)), o + Vector3(rng.randf_range(-3, 3), h - 0.004, rng.randf_range(-3, 3)), "dirt", Color(0.35, 0.3, 0.22), false, 1.0, Vector3(0, rng.randf() * TAU, 0))


# --- yard kit (checkpoint) --------------------------------------------------------------------

## 20 ft shipping container, doors on the -z end. `open` swings one door out.
static func shipping_container(parent: Node, pos: Vector3, rot_y: float, c: Color, rng: RandomNumberGenerator, solid := true) -> Node3D:
	var r := _root(parent, pos, rot_y, Vector3(2.44, 2.6, 6.06) if solid else Vector3.ZERO)
	c = c.darkened(rng.randf() * 0.2)
	for s in [-1, 1]:
		A.box(r, Vector3(0.05, 2.4, 5.9), Vector3(s * 1.19, 1.3, 0), "corrugated", c, false, 0.9, Vector3(0, 0, 0))
	A.box(r, Vector3(2.34, 0.06, 5.9), Vector3(0, 2.57, 0), "corrugated", c.darkened(0.1), false, 1.2)
	A.box(r, Vector3(2.34, 2.4, 0.05), Vector3(0, 1.3, 2.97), "corrugated", c, false, 0.9)
	var frame := c.darkened(0.35)
	for sx in [-1, 1]:   # corner posts, rails, castings
		for sz in [-1, 1]:
			A.box(r, Vector3(0.14, 2.6, 0.14), Vector3(sx * 1.15, 1.3, sz * 2.96), "metal", frame, false, 0.5)
			for y in [0.07, 2.53]:
				A.box(r, Vector3(0.18, 0.14, 0.18), Vector3(sx * 1.15, y, sz * 2.96), "metal", Color(0.25, 0.25, 0.25), false, 0.3)
		for y in [0.08, 2.52]:
			A.box(r, Vector3(0.12, 0.16, 5.8), Vector3(sx * 1.15, y, 0), "metal", frame, false, 0.5)
	for y in [0.08, 2.52]:
		for sz in [-1, 1]:
			A.box(r, Vector3(2.2, 0.16, 0.12), Vector3(0, y, sz * 2.96), "metal", frame, false, 0.5)
	# Door end: two leaves with locking bars.
	for s in [-1, 1]:
		var hinge := Node3D.new()
		r.add_child(hinge)
		hinge.position = Vector3(s * 1.12, 0, -2.98)
		if s > 0 and rng.randf() < 0.3:
			hinge.rotation.y = rng.randf_range(1.2, 2.4)
		A.box(hinge, Vector3(1.1, 2.36, 0.05), Vector3(-s * 0.56, 1.3, 0), "corrugated", c, false, 0.9)
		for k in 2:
			var x: float = -s * (0.25 + k * 0.6)
			A.seg(hinge, Vector3(x, 0.15, -0.05), Vector3(x, 2.45, -0.05), 0.022, 0.022, "metal", Color(0.55, 0.55, 0.55))
			A.box(hinge, Vector3(0.05, 0.12, 0.05), Vector3(x + s * 0.08, 1.2, -0.07), "metal", Color(0.5, 0.5, 0.5), false, 0.2)
	var tag := B.label(r, ["BRM-%04d" % rng.randi_range(1000, 9999), "RECLAIMED", "HAZMAT", "SCRAP"][rng.randi() % 4], Vector3(1.22, 2.1, 1.0), 40, Color(0.92, 0.9, 0.82), "stencil", 0.008)
	tag.rotation.y = PI / 2
	return r


## Lattice floodlight mast. The head points along -z, tilted down.
static func floodlight_tower(parent: Node, pos: Vector3, rot_y: float, h := 11.0, lit := true) -> void:
	var r := _root(parent, pos, rot_y, Vector3(1.0, h, 1.0))
	var steel := Color(0.6, 0.6, 0.6)
	A.box(r, Vector3(1.6, 0.4, 1.6), Vector3(0, 0.2, 0), "concrete", Color(0.75, 0.72, 0.68), false, 1.0)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			A.seg(r, Vector3(sx * 0.5, 0.4, sz * 0.5), Vector3(sx * 0.22, h, sz * 0.22), 0.04, 0.035, "metal", steel)
	var n := int(h / 1.2)
	for i in n:
		var y0 := 0.4 + i * (h - 0.4) / n
		var y1 := 0.4 + (i + 1) * (h - 0.4) / n
		var w0 := lerpf(0.5, 0.22, (y0 - 0.4) / (h - 0.4))
		var w1 := lerpf(0.5, 0.22, (y1 - 0.4) / (h - 0.4))
		for k in 4:
			var a := Vector3(1, 0, 1).rotated(Vector3.UP, k * PI / 2)
			var b := Vector3(1, 0, 1).rotated(Vector3.UP, (k + 1) * PI / 2)
			A.seg(r, a * w0 + Vector3(0, y0, 0), b * w1 + Vector3(0, y1, 0), 0.018, 0.018, "metal", steel)
	A.box(r, Vector3(1.8, 0.08, 0.8), Vector3(0, h, -0.1), "grate", Color.WHITE, false, 0.5)
	A.railing(r, Vector3(-0.9, h, -0.5), Vector3(0.9, h, -0.5), 0.7, "metal")
	for k in 4:
		var x := -0.66 + k * 0.44
		var head := A.box(r, Vector3(0.38, 0.32, 0.2), Vector3(x, h + 0.85, -0.25), "metal", Color(0.3, 0.3, 0.32), false, 0.3, Vector3(-0.5, 0, 0))
		A.glow(r, Vector3(0.3, 0.24, 0.02), Vector3(x, h + 0.8, -0.36), Color(1, 0.92, 0.75) if lit else Color(0.15, 0.15, 0.15), 6.0 if lit else 0.0)
	A.box(r, Vector3(1.9, 0.08, 0.08), Vector3(0, h + 0.65, -0.2), "metal", steel, false)
	if lit:
		var s := SpotLight3D.new()
		s.light_color = Color(1, 0.9, 0.72)
		s.light_energy = 6.0
		s.spot_range = h * 4.0
		s.spot_angle = 48.0
		s.shadow_enabled = true
		r.add_child(s)
		s.position = Vector3(0, h + 0.8, -0.6)
		s.rotation.x = -0.75


## Gantry crane over a scrap pile: two A-frame legs, a box girder, a trolley with a hook.
static func gantry_crane(parent: Node, pos: Vector3, rot_y: float, span := 14.0, h := 8.0) -> void:
	var r := _root(parent, pos, rot_y)
	var y := Color(0.85, 0.62, 0.15)
	for sx in [-1, 1]:
		var x: float = sx * span / 2
		A.box(r, Vector3(0.6, 0.5, 4.2), Vector3(x, 0.25, 0), "metal", y.darkened(0.4), true, 1.0)
		for wz in [-1.6, 1.6]:
			A.cyl(r, 0.25, 0.2, Vector3(x, 0.25, wz), "metal", Color(0.2, 0.2, 0.2), false, "x")
		for sz in [-1, 1]:
			A.seg(r, Vector3(x, 0.5, sz * 1.8), Vector3(x, h, sz * 0.4), 0.16, 0.14, "metal", y)
		A.seg(r, Vector3(x, h * 0.45, -1.15), Vector3(x, h * 0.45, 1.15), 0.08, 0.08, "metal", y)
		A.box(r, Vector3(0.9, 0.5, 1.4), Vector3(x, h, 0), "metal", y, false, 0.5)
	A.box(r, Vector3(span + 1.2, 0.9, 0.7), Vector3(0, h + 0.65, 0), "riveted", y, true, 1.0)
	A.box(r, Vector3(span + 1.2, 0.08, 0.9), Vector3(0, h + 1.12, 0), "metal", y.darkened(0.2), false, 0.5)
	A.railing(r, Vector3(-span / 2, h + 1.12, 0.45), Vector3(span / 2, h + 1.12, 0.45), 0.9, "metal")
	var t := span * 0.18
	A.box(r, Vector3(1.4, 0.7, 1.3), Vector3(t, h - 0.1, 0), "metal", y.darkened(0.15), false, 0.5)
	A.box(r, Vector3(0.7, 0.5, 0.6), Vector3(t, h - 0.3, -0.75), "metal", Color(0.3, 0.3, 0.3), false, 0.3)
	var drop := h * 0.55
	for s in [-1, 1]:
		A.seg(r, Vector3(t + s * 0.12, h - 0.45, 0), Vector3(t + s * 0.12, h - 0.45 - drop, 0), 0.02, 0.02, "metal", Color(0.25, 0.25, 0.25))
	A.box(r, Vector3(0.6, 0.45, 0.35), Vector3(t, h - 0.65 - drop, 0), "metal", y, false, 0.3)
	A.ring(r, 0.22, 0.13, Vector3(t, h - 1.1 - drop, 0), "metal", Color(0.4, 0.4, 0.4), Vector3(PI / 2, 0, 0))
	B.label(r, "SWL 20 T", Vector3(0, h + 0.65, -0.36), 40, Color(0.12, 0.1, 0.08), "stencil", 0.012).rotation.y = 0.0


## Yellow warehouse forklift. -z is the fork end.
static func forklift(parent: Node, pos: Vector3, rot_y: float) -> void:
	var r := _root(parent, pos, rot_y, Vector3(1.2, 2.2, 2.6))
	var y := Color(0.92, 0.7, 0.12)
	A.box(r, Vector3(1.1, 0.7, 1.9), Vector3(0, 0.6, 0.2), "metal", y, false, 0.6)
	A.box(r, Vector3(1.05, 0.55, 0.5), Vector3(0, 0.8, 1.05), "metal", Color(0.25, 0.25, 0.25), false, 0.4)   # counterweight
	A.box(r, Vector3(0.5, 0.12, 0.45), Vector3(0, 1.0, 0.45), "canvas", Color(0.15, 0.15, 0.15), false, 0.3)   # seat
	A.box(r, Vector3(0.5, 0.45, 0.1), Vector3(0, 1.25, 0.68), "canvas", Color(0.15, 0.15, 0.15), false, 0.3)
	A.seg(r, Vector3(0, 0.95, -0.25), Vector3(0, 1.35, -0.15), 0.025, 0.025, "metal", Color(0.2, 0.2, 0.2))
	A.ring(r, 0.16, 0.13, Vector3(0, 1.37, -0.13), "rubber", Color.WHITE, Vector3(-0.6, 0, 0))
	for sx in [-1, 1]:   # overhead guard
		for z in [-0.6, 0.85]:
			A.seg(r, Vector3(sx * 0.5, 0.95, z), Vector3(sx * 0.5, 2.15, z * 0.9), 0.035, 0.035, "metal", Color(0.2, 0.2, 0.2))
	A.box(r, Vector3(1.1, 0.06, 1.5), Vector3(0, 2.15, 0.12), "grate", Color.WHITE, false, 0.4)
	for sx in [-1, 1]:   # mast + forks
		A.box(r, Vector3(0.1, 2.3, 0.12), Vector3(sx * 0.35, 1.2, -0.85), "metal", Color(0.25, 0.25, 0.25), false, 0.4)
		A.box(r, Vector3(0.1, 0.06, 1.0), Vector3(sx * 0.25, 0.08, -1.4), "metal", Color(0.3, 0.3, 0.3), false, 0.3)
		A.box(r, Vector3(0.1, 0.5, 0.06), Vector3(sx * 0.25, 0.3, -0.92), "metal", Color(0.3, 0.3, 0.3), false, 0.3)
		for z in [-0.5, 0.8]:
			A.cyl(r, 0.27 if z < 0 else 0.22, 0.22, Vector3(sx * 0.55, 0.27 if z < 0 else 0.22, z), "rubber", Color.WHITE, false, "x")
	A.box(r, Vector3(0.8, 0.1, 0.1), Vector3(0, 0.6, -0.92), "metal", Color(0.3, 0.3, 0.3), false)
	A.sphere(r, 0.06, Vector3(0, 2.22, 0.6), "cream", Color(1, 0.55, 0.1), 3.0)


## A compressed scrap bale: a crushed cube of mixed junk, strapped.
static func bale(parent: Node, pos: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var kinds := ["rust", "metal", "copper", "corrugated", "plastic"]
	var k: String = kinds[rng.randi() % kinds.size()]
	var tint := Color.WHITE if k != "plastic" else Color.from_hsv(rng.randf(), 0.25, 0.55)
	var b := A.box(parent, Vector3(s, s * 0.8, s), pos + Vector3(0, s * 0.4, 0), k, tint, false, 0.4, Vector3(0, rng.randf_range(-0.2, 0.2), 0))
	for i in 5:   # junk sticking out of the faces
		var face := Vector3([-1, 1][rng.randi() % 2] * s * 0.5, rng.randf_range(-0.3, 0.3) * s, rng.randf_range(-0.4, 0.4) * s)
		if rng.randf() < 0.5:
			face = Vector3(face.z, face.y, face.x)
		A.box(b, Vector3(rng.randf_range(0.05, 0.2), rng.randf_range(0.03, 0.12), rng.randf_range(0.05, 0.2)), face, kinds[rng.randi() % kinds.size()], Color.WHITE, false, 0.2, Vector3(rng.randf(), rng.randf(), rng.randf()))
	for y in [-0.2, 0.2]:
		A.box(b, Vector3(s + 0.02, 0.03, s + 0.02), Vector3(0, y * s, 0), "metal", Color(0.3, 0.3, 0.3), false, 0.2)


## Horizontal fuel tank on saddles, with a ladder and a hose stand.
static func fuel_tank(parent: Node, pos: Vector3, rot_y: float, c := Color(0.85, 0.82, 0.75)) -> void:
	var r := _root(parent, pos, rot_y, Vector3(7.0, 3.0, 2.8))
	A.cyl(r, 1.25, 6.4, Vector3(0, 1.6, 0), "metal", c, false, "x")
	for sx in [-1, 1]:
		A.sphere(r, 1.25, Vector3(sx * 3.2, 1.6, 0), "metal", c, 0.0, 1.0).scale = Vector3(0.35, 1, 1)
		A.box(r, Vector3(0.4, 0.6, 2.2), Vector3(sx * 2.2, 0.3, 0), "concrete", Color(0.7, 0.68, 0.65), false, 1.0)
	for x in [-1.6, 0.0, 1.6]:
		A.ring(r, 1.27, 1.22, Vector3(x, 1.6, 0), "metal", c.darkened(0.25), Vector3(0, 0, PI / 2))
	A.box(r, Vector3(2.4, 0.4, 0.02), Vector3(0, 1.7, -1.26), "hazard", Color.WHITE, false, 0.5)
	B.label(r, "DIESEL", Vector3(0, 2.25, -1.26), 50, Color(0.75, 0.12, 0.08), "stencil", 0.012).rotation.y = PI
	A.cyl(r, 0.25, 0.3, Vector3(1.0, 2.95, 0), "metal", c.darkened(0.2))
	A.seg(r, Vector3(-2.6, 0, -1.3), Vector3(-2.6, 2.9, -1.0), 0.03, 0.03, "metal", Color(0.4, 0.4, 0.4))
	A.seg(r, Vector3(-2.1, 0, -1.3), Vector3(-2.1, 2.9, -1.0), 0.03, 0.03, "metal", Color(0.4, 0.4, 0.4))
	for i in 8:
		A.box(r, Vector3(0.5, 0.03, 0.03), Vector3(-2.35, 0.3 + i * 0.35, -1.3 + i * 0.035), "metal", Color(0.4, 0.4, 0.4), false)
	A.seg(r, Vector3(2.0, 0.6, -1.0), Vector3(2.6, 0.6, -2.2), 0.05, 0.05, "rubber")
	A.box(r, Vector3(0.4, 1.2, 0.3), Vector3(2.6, 0.6, -2.4), "metal", Color(0.75, 0.12, 0.08), false, 0.3)


## Guard booth: small cabin with windows on three sides, a desk and a lamp inside. Door on +x.
static func guard_booth(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rot_y)
	var c := Color(0.85, 0.82, 0.72)
	A.box(r, Vector3(2.8, 0.25, 2.4), Vector3(0, 0.12, 0), "concrete", Color(0.7, 0.68, 0.65), true, 1.0)
	A.wall(r, -1.3, 1.3, -1.1, 2.4, 0.08, [[0.0, 2.0, 1.0, 2.0]], "metal", c, true, 0.25, true, 1.0)
	A.wall(r, -1.3, 1.3, 1.1, 2.4, 0.08, [[-0.6, 1.0, 1.0, 2.0]], "metal", c, true, 0.25, true, 1.0)
	A.wall(r, -1.1, 1.1, -1.3, 2.4, 0.08, [[0.0, 1.4, 1.0, 2.0]], "metal", c, false, 0.25, true, 1.0)
	A.wall(r, -1.1, 1.1, 1.3, 2.4, 0.08, [[0.3, 0.9, 0.0, 2.1]], "metal", c, false, 0.25, true, 1.0)
	A.box(r, Vector3(3.2, 0.15, 2.8), Vector3(0, 2.75, 0), "corrugated", Color(0.45, 0.42, 0.4), true, 1.0)
	for w in [[Vector3(2.0, 1.0, 0.02), Vector3(0, 1.75, -1.1)], [Vector3(0.02, 1.0, 1.4), Vector3(-1.3, 1.75, 0)]]:
		var g = A.box(r, w[0], w[1], "metal", Color.WHITE, false)
		g.material_override = A.glass()
	A.box(r, Vector3(2.0, 0.06, 0.6), Vector3(0, 1.0, -0.75), "wood", Color(0.6, 0.5, 0.4), false, 0.5)
	A.crt(r, Vector3(0.3, 1.03, -0.75), true, Color(0.3, 1, 0.5))
	chair(r, Vector3(0.3, 0.25, -0.1), PI)
	B.omni(r, Vector3(0, 2.3, 0), Color(1, 0.85, 0.6), 0.8, 5.0)
	A.glow(r, Vector3(0.3, 0.05, 0.3), Vector3(0, 2.6, 0), Color(1, 0.9, 0.7), 3.0)
	var sign := B.label(r, "GATEHOUSE", Vector3(0, 2.55, -1.15), 40, Color(0.12, 0.1, 0.08), "plate", 0.008)
	sign.rotation.y = PI


## Old freight wagon left on a siding.
static func boxcar(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var r := _root(parent, pos, rot_y, Vector3(10.0, 3.6, 3.0))
	var c := [Color(0.55, 0.22, 0.15), Color(0.35, 0.4, 0.35), Color(0.5, 0.4, 0.3)][rng.randi() % 3] as Color
	A.box(r, Vector3(10, 2.6, 2.9), Vector3(0, 2.4, 0), "corrugated", c, false, 1.2)
	A.box(r, Vector3(10.2, 0.15, 3.1), Vector3(0, 3.75, 0), "rust", Color.WHITE, false, 1.0)
	A.box(r, Vector3(10.2, 0.3, 2.6), Vector3(0, 1.0, 0), "metal", Color(0.2, 0.2, 0.2), false, 0.5)
	for s in [-1, 1]:
		A.box(r, Vector3(2.0, 2.3, 0.06), Vector3(rng.randf_range(-1.5, 1.5), 2.35, s * 1.47), "corrugated", c.darkened(0.15), false, 1.0)
		for bx in [-3.4, 3.4]:
			A.box(r, Vector3(2.2, 0.3, 0.3), Vector3(bx, 0.65, s * 0.9), "rust", Color.WHITE, false, 0.5)
			for wx in [-0.7, 0.7]:
				A.cyl(r, 0.42, 0.12, Vector3(bx + wx, 0.42, s * 0.75), "metal", Color(0.25, 0.25, 0.25), false, "z")
	var tag := B.label(r, "BRM %d" % rng.randi_range(100, 999), Vector3(-3.2, 3.0, -1.47), 60, Color(0.9, 0.88, 0.8), "stencil", 0.01)
	tag.rotation.y = PI
