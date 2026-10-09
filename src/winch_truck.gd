# The Bureau's winch truck (LIFT_MOTOR upgrade): a cab-over three-axle work truck in Bureau
# yellow, parked by the headframe. Built along +x (the nose at -x, the platform side +z), feet on
# the origin. A rounded cab with a split windscreen, doors with windows and grab handles, a grille
# with slats, a bumper with tow hooks and lamps, fenders over every wheel, a fuel tank and steps;
# behind it a flatbed with side rails, a big cable drum spooled with wire, a diesel power pack
# with an exhaust stack, an A-frame boom at the tail with a sheave the cable runs over, and
# stabiliser legs down. Returns the point the cable leaves the boom's sheave (local).
extends RefCounted

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")

const PAINT := Color(0.9, 0.66, 0.16)
const DARK := Color(0.13, 0.13, 0.14)
const STEEL := Color(0.62, 0.63, 0.64)
const RUBBER := Color(0.09, 0.09, 0.09)


static func build(t: Node3D) -> Vector3:
	_chassis(t)
	_cab(t)
	for x in [-2.35, 0.95, 2.2]:   # front axle, twin rear axles
		for s in [-1.0, 1.0]:
			_wheel(t, Vector3(x, 0.52, s * 1.02), s)
	_fenders(t)
	_bed(t)
	_drum(t)
	_power_pack(t)
	return _boom(t)


static func _chassis(t: Node3D) -> void:
	for s in [-1.0, 1.0]:   # two frame rails with cross members
		A.box(t, Vector3(6.6, 0.24, 0.12), Vector3(0.2, 0.86, s * 0.45), "metal", DARK, false, 0.5)
	for x in [-2.4, -1.0, 0.4, 1.6, 2.9]:
		A.box(t, Vector3(0.1, 0.18, 0.9), Vector3(x, 0.86, 0), "metal", DARK, false)
	A.box(t, Vector3(6.6, 0.3, 1.0), Vector3(0.2, 0.86, 0), "metal", DARK, true)   # (the collision)
	# Fuel tank and battery box on the platform side, steps up to the cab.
	A.cyl(t, 0.26, 0.9, Vector3(-0.9, 0.72, 0.82), "metal", STEEL, false, "x")
	for x in [-1.25, -0.55]:
		A.ring(t, 0.275, 0.255, Vector3(x, 0.72, 0.82), "metal", DARK, Vector3(0, 0, PI / 2))
	A.cyl(t, 0.07, 0.06, Vector3(-0.6, 0.98, 0.82), "metal", DARK)   # filler cap
	A.box(t, Vector3(0.5, 0.4, 0.45), Vector3(-0.85, 0.72, -0.8), "metal", DARK, false)   # battery box
	for s in [-1.0, 1.0]:
		for k in 2:
			A.box(t, Vector3(0.38, 0.04, 0.22), Vector3(-1.75, 0.42 + k * 0.32, s * 1.12), "grate", STEEL, false, 0.4)


static func _cab(t: Node3D) -> void:
	var cx := -2.25
	var w := 2.3
	# The box of the cab, its corners rounded with half-cylinders.
	A.box(t, Vector3(1.55, 1.55, w - 0.3), Vector3(cx, 1.92, 0), "paint", PAINT, true, 0.6)
	A.box(t, Vector3(1.25, 1.55, w), Vector3(cx + 0.15, 1.92, 0), "paint", PAINT, false, 0.6)
	for s in [-1.0, 1.0]:
		A.cyl(t, 0.15, 1.55, Vector3(cx - 0.62, 1.92, s * (w * 0.5 - 0.15)), "paint", PAINT)   # rounded front corners
	A.box(t, Vector3(1.4, 0.12, w - 0.1), Vector3(cx + 0.05, 2.75, 0), "paint", PAINT.darkened(0.08), false, 0.6)   # roof
	A.box(t, Vector3(0.9, 0.2, 1.2), Vector3(cx + 0.2, 2.9, 0), "paint", PAINT.darkened(0.12), false)   # roof pod
	A.box(t, Vector3(0.12, 0.14, 1.9), Vector3(cx - 0.62, 2.82, 0), "metal", DARK, false)   # light bar
	for z in [-0.6, -0.2, 0.2, 0.6]:
		A.sphere(t, 0.055, Vector3(cx - 0.69, 2.82, z), "cream", Color(1, 0.95, 0.8), 1.5)
	# Split windscreen (a pillar down the middle), wipers under it.
	for s in [-1.0, 1.0]:
		var g = A.box(t, Vector3(0.02, 0.62, 0.95), Vector3(cx - 0.78, 2.28, s * 0.5), "metal", Color.WHITE, false)
		g.material_override = A.glass()
		g.rotation.z = 0.12
		A.box(t, Vector3(0.02, 0.012, 0.5), Vector3(cx - 0.8, 1.98, s * 0.45), "metal", DARK, false, 0.2, Vector3(0.3 * s, 0, 0))   # wiper
	A.box(t, Vector3(0.06, 0.66, 0.08), Vector3(cx - 0.77, 2.28, 0), "metal", DARK, false)   # centre pillar
	A.box(t, Vector3(0.06, 0.06, w - 0.2), Vector3(cx - 0.75, 2.6, 0), "metal", DARK, false)
	A.box(t, Vector3(0.06, 0.06, w - 0.2), Vector3(cx - 0.75, 1.96, 0), "metal", DARK, false)
	# Grille, badge, bumper, lamps, tow hooks.
	A.box(t, Vector3(0.05, 0.55, 1.4), Vector3(cx - 0.78, 1.45, 0), "metal", DARK, false)
	for k in 6:
		A.box(t, Vector3(0.03, 0.03, 1.36), Vector3(cx - 0.81, 1.22 + k * 0.09, 0), "metal", STEEL, false)
	B.label(t, "B.R.M.", Vector3(cx - 0.82, 1.78, 0), 40, Color(0.15, 0.12, 0.1), "stencil", 0.005).rotation.y = -PI / 2
	A.box(t, Vector3(0.22, 0.26, w + 0.1), Vector3(cx - 0.86, 1.0, 0), "metal", DARK, true, 0.5)   # bumper
	for s in [-1.0, 1.0]:
		A.cyl(t, 0.1, 0.06, Vector3(cx - 0.97, 1.0, s * 0.85), "cream", Color(1, 0.95, 0.8), false, "x")   # headlamps
		A.ring(t, 0.115, 0.095, Vector3(cx - 0.98, 1.0, s * 0.85), "metal", STEEL, Vector3(0, 0, PI / 2))
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1, 0.92, 0.75)
		lamp.light_energy = 0.0
		t.add_child(lamp)
		A.ring(t, 0.06, 0.035, Vector3(cx - 1.0, 0.86, s * 0.45), "metal", Color(0.75, 0.2, 0.1), Vector3(0, 0, PI / 2))   # tow hook
		A.box(t, Vector3(0.05, 0.08, 0.16), Vector3(cx - 0.8, 1.35, s * 1.12), "cream", Color(1, 0.6, 0.1), false, 0.5)   # indicator
	# Doors: a seam, a window, a handle, a mirror on an arm, and the Bureau's number.
	for s in [-1.0, 1.0]:
		var z: float = s * (w * 0.5 + 0.005)
		A.box(t, Vector3(0.02, 1.3, 0.01), Vector3(cx - 0.45, 1.85, z), "metal", DARK, false)
		A.box(t, Vector3(0.02, 1.3, 0.01), Vector3(cx + 0.55, 1.85, z), "metal", DARK, false)
		var win = A.box(t, Vector3(0.8, 0.5, 0.012), Vector3(cx + 0.05, 2.3, z), "metal", Color.WHITE, false)
		win.material_override = A.glass()
		A.box(t, Vector3(0.18, 0.04, 0.04), Vector3(cx + 0.4, 1.95, z + s * 0.02), "metal", STEEL, false)
		A.seg(t, Vector3(cx - 0.6, 2.35, z), Vector3(cx - 0.75, 2.4, z + s * 0.35), 0.015, 0.015, "metal", DARK)
		A.box(t, Vector3(0.05, 0.32, 0.18), Vector3(cx - 0.75, 2.3, z + s * 0.4), "metal", DARK, false)
		var num := B.label(t, "WINCH 3", Vector3(cx + 0.05, 1.6, z + s * 0.004), 48, Color(0.15, 0.12, 0.1), "stencil", 0.005)
		num.rotation.y = 0.0 if s > 0 else PI


static func _wheel(t: Node3D, at: Vector3, s: float) -> void:
	A.cyl(t, 0.5, 0.36, at, "rubber", RUBBER, false, "z")
	for k in 12:   # tread lugs
		var a := TAU * k / 12.0
		A.box(t, Vector3(0.07, 0.05, 0.36), at + Vector3(cos(a) * 0.5, sin(a) * 0.5, 0), "rubber", RUBBER, false, 0.3, Vector3(0, 0, a))
	A.cyl(t, 0.3, 0.38, at, "metal", STEEL, false, "z")   # rim
	A.cyl(t, 0.12, 0.42, at, "metal", DARK, false, "z")   # hub
	for k in 6:   # wheel nuts
		var a := TAU * k / 6.0
		A.cyl(t, 0.022, 0.43, at + Vector3(cos(a) * 0.19, sin(a) * 0.19, 0), "metal", DARK, false, "z")


static func _fenders(t: Node3D) -> void:
	for x in [-2.35, 1.575]:
		var len := 1.25 if x < 0 else 2.6
		for s in [-1.0, 1.0]:
			for k in 5:   # an arch over the wheels, in five flat plates
				var a := PI * (0.12 + 0.76 * k / 4.0)
				var p := Vector3(x - cos(a) * len * 0.45, 0.52 + sin(a) * 0.62, s * 1.04)
				var plate := A.box(t, Vector3(len * 0.32, 0.03, 0.42), p, "metal", DARK if x > 0 else PAINT, false, 0.5)
				plate.rotation.z = a - PI / 2
			A.box(t, Vector3(0.02, 0.35, 0.4), Vector3(x + len * 0.5, 0.4, s * 1.04), "rubber", RUBBER, false)   # mud flap


static func _bed(t: Node3D) -> void:
	A.box(t, Vector3(4.4, 0.12, 2.3), Vector3(1.35, 1.08, 0), "grate", Color(0.55, 0.55, 0.55), false, 0.5)   # diamond-plate deck
	A.box(t, Vector3(4.4, 0.1, 2.3), Vector3(1.35, 1.0, 0), "paint", PAINT.darkened(0.25), true, 0.5)
	for s in [-1.0, 1.0]:   # side rails on stakes
		A.box(t, Vector3(4.3, 0.06, 0.06), Vector3(1.35, 1.6, s * 1.12), "paint", PAINT, false)
		for x in [-0.7, 0.4, 1.5, 2.6, 3.4]:
			A.box(t, Vector3(0.06, 0.5, 0.06), Vector3(x, 1.38, s * 1.12), "paint", PAINT, false)
	A.box(t, Vector3(0.08, 0.8, 2.2), Vector3(-0.85, 1.5, 0), "paint", PAINT.darkened(0.15), false)   # headboard
	for k in 4:
		A.box(t, Vector3(0.09, 0.04, 2.1), Vector3(-0.86, 1.2 + k * 0.17, 0), "metal", DARK, false)
	A.box(t, Vector3(0.12, 0.1, 2.3), Vector3(3.55, 1.08, 0), "hazard", Color.WHITE, false, 0.6)   # chevron tail
	for s in [-1.0, 1.0]:
		A.box(t, Vector3(0.05, 0.1, 0.18), Vector3(3.6, 0.95, s * 0.95), "cream", Color(1, 0.15, 0.1), false, 1.5)   # tail lamps


static func _drum(t: Node3D) -> void:
	var c := Vector3(0.6, 1.95, 0)
	for s in [-1.0, 1.0]:   # stands
		var p := c + Vector3(0, 0, s * 0.85)
		A.seg(t, Vector3(c.x - 0.55, 1.12, p.z), p, 0.06, 0.05, "paint", PAINT)
		A.seg(t, Vector3(c.x + 0.55, 1.12, p.z), p, 0.06, 0.05, "paint", PAINT)
		A.cyl(t, 0.82, 0.07, c + Vector3(0, 0, s * 0.72), "paint", PAINT.darkened(0.1), false, "z")   # flange
		A.cyl(t, 0.16, 0.12, c + Vector3(0, 0, s * 0.82), "metal", DARK, false, "z")   # bearing
	A.cyl(t, 0.62, 1.38, c, "metal", Color(0.22, 0.22, 0.22), false, "z")   # the wound cable
	for k in 11:   # the wraps of wire showing
		A.ring(t, 0.63, 0.6, c + Vector3(0, 0, -0.62 + k * 0.124), "metal", Color(0.42, 0.42, 0.42), Vector3(PI / 2, 0, 0))
	A.box(t, Vector3(0.5, 0.5, 0.35), c + Vector3(-0.2, -0.45, 0.95), "metal", DARK, false)   # the drum's gearbox
	A.box(t, Vector3(0.3, 0.4, 0.06), Vector3(-0.4, 1.6, 1.1), "metal", Color(0.3, 0.32, 0.3), false)   # control box with levers
	for k in 2:
		A.seg(t, Vector3(-0.45 + k * 0.1, 1.7, 1.14), Vector3(-0.45 + k * 0.1, 1.95, 1.2), 0.012, 0.012, "metal", STEEL)
		A.sphere(t, 0.025, Vector3(-0.45 + k * 0.1, 1.96, 1.2), "plastic", Color(0.8, 0.1, 0.08))


static func _power_pack(t: Node3D) -> void:
	var p := Vector3(2.25, 1.6, -0.35)
	A.box(t, Vector3(1.0, 0.9, 1.2), p, "paint", PAINT, true, 0.6)
	A.box(t, Vector3(1.04, 0.06, 1.24), p + Vector3(0, 0.48, 0), "paint", PAINT.darkened(0.25), false)
	for k in 5:   # louvres
		A.box(t, Vector3(0.7, 0.04, 0.03), p + Vector3(0, -0.25 + k * 0.12, 0.61), "metal", DARK, false)
	A.pipe(t, p + Vector3(0.3, 0.45, -0.4), p + Vector3(0.3, 1.5, -0.4), 0.06, "metal", DARK)   # exhaust stack
	A.cyl(t, 0.075, 0.06, p + Vector3(0.3, 1.52, -0.4), "metal", DARK)   # rain cap
	A.cyl(t, 0.18, 0.3, p + Vector3(-0.3, 0.6, -0.4), "metal", STEEL)   # air cleaner


## The A-frame boom over the tail: two legs and a cross head, a sheave on it, a guy back to the
## headboard. Returns where the cable leaves the sheave, going up to the lift.
static func _boom(t: Node3D) -> Vector3:
	var top := Vector3(3.6, 3.7, 0)
	for s in [-1.0, 1.0]:
		A.seg(t, Vector3(3.1, 1.15, s * 0.95), top + Vector3(0, 0, s * 0.3), 0.07, 0.06, "paint", PAINT)
		A.seg(t, Vector3(-0.8, 1.9, s * 0.9), top + Vector3(0, 0, s * 0.3), 0.025, 0.025, "metal", DARK)   # guy wires
	A.box(t, Vector3(0.18, 0.18, 0.8), top, "paint", PAINT.darkened(0.1), false)
	var sheave := Node3D.new()
	t.add_child(sheave)
	sheave.position = top + Vector3(0.05, 0.25, 0)
	A.cyl(sheave, 0.32, 0.08, Vector3.ZERO, "metal", STEEL, false, "z")
	A.ring(sheave, 0.33, 0.26, Vector3.ZERO, "metal", DARK, Vector3(PI / 2, 0, 0))
	for s in [-1.0, 1.0]:
		A.box(sheave, Vector3(0.12, 0.5, 0.03), Vector3(0, -0.12, s * 0.06), "paint", PAINT, false)
	# The cable from the drum's top up to the sheave.
	A.seg(t, Vector3(0.6, 2.57, 0), sheave.position + Vector3(-0.05, 0.32, 0), 0.022, 0.022, "metal", Color(0.3, 0.3, 0.3))
	var beacon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	beacon.mesh = sm
	t.add_child(beacon)
	beacon.position = top + Vector3(0, 0.15, 0.45)
	P._blink(beacon, Color(1, 0.6, 0.1), 0.8)
	return sheave.position + Vector3(0.3, 0.1, 0)
