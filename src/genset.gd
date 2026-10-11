# The moving half of a diesel generator set (props.gd builds the static half around it): an open-frame
# four-cylinder engine you can see working. Crankshaft throws turn, connecting rods swing, crossheads
# slide in their guides, piston rods go up into the cylinders, rockers nod on the cam, the flyball
# governor spins and flares, the flywheel and the belt-driven radiator fan turn, the RPM needle sits
# on the dial. A power failure stalls it (it spins down and stops); the breaker starts it again.
extends Node3D

const A = preload("res://src/art.gd")
const Sfx = preload("res://src/sfx.gd")
const Merge = preload("res://src/merge.gd")

const RC := 0.11        # crank throw
const ROD := 0.45       # connecting rod length
const CY := 0.62        # crankshaft height
const CYL_X := [-0.95, -0.55, -0.15, 0.25]
const PHASE := [0.0, PI, PI, 0.0]          # inline four
const FIRE := [0.0, PI, 3.0 * PI, 2.0 * PI]   # 1-3-4-2, over the 720 degree cycle
const RUN_RATE := TAU * 4.0                   # rad/s at speed (240 rpm: slow enough to read)

var running := true
var rate := RUN_RATE
var _theta := 0.0
var _throws: Array[Node3D] = []
var _rods: Array[Node3D] = []
var _heads: Array[Node3D] = []     # crosshead + piston rod, slides vertically
var _rockers: Array[Node3D] = []   # [exhaust, inlet] per cylinder
var _pushrods: Array[Node3D] = []
var _flywheel: Node3D
var _fan: Node3D
var _alt_rotor: Node3D
var _gov: Node3D
var _gov_arms: Array[Node3D] = []
var _block: Node3D
var _needle: Node3D
var _hum: AudioStreamPlayer3D


func build(paint: Color, needle_at: Vector3) -> void:
	add_to_group("gensets")
	var steel := Color(0.62, 0.62, 0.6)
	var dark := Color(0.2, 0.2, 0.2)
	var bright := Color(0.78, 0.78, 0.76)
	for i in CYL_X.size():
		var x: float = CYL_X[i]
		# Crank throw: two webs and the pin, turning about the crankshaft.
		var th := Node3D.new()
		add_child(th)
		th.position = Vector3(x, CY, 0)
		for s in [-1, 1]:
			A.box(th, Vector3(0.035, RC + 0.12, 0.13), Vector3(s * 0.055, RC / 2.0, 0), "metal", steel, false, 0.4)
		A.cyl(th, 0.035, 0.11, Vector3(0, RC, 0), "metal", bright, false, "x")
		A.cyl(th, 0.045, 0.06, Vector3(0, 0, 0), "metal", bright, false, "x")
		_throws.append(th)
		# Connecting rod (big end on the pin, small end on the crosshead pin).
		var rod := Node3D.new()
		add_child(rod)
		A.box(rod, Vector3(0.04, ROD, 0.05), Vector3(0, 0, 0), "metal", steel, false, 0.4)
		A.cyl(rod, 0.055, 0.06, Vector3(0, -ROD / 2.0, 0), "metal", steel, false, "x")
		A.cyl(rod, 0.035, 0.06, Vector3(0, ROD / 2.0, 0), "metal", steel, false, "x")
		_rods.append(rod)
		# Crosshead block with the piston rod rising into the cylinder.
		var head := Node3D.new()
		add_child(head)
		A.box(head, Vector3(0.12, 0.08, 0.1), Vector3.ZERO, "metal", steel, false, 0.4)
		A.cyl(head, 0.038, 0.66, Vector3(0, 0.37, 0), "metal", bright)   # piston rod: always well up inside the cylinder
		_heads.append(head)
		# Valve gear on top of the head: two rockers with their pushrods running down the side.
		for v in 2:
			var rk := Node3D.new()
			add_child(rk)
			rk.position = Vector3(x - 0.07 + v * 0.14, 2.12, 0.0)
			A.box(rk, Vector3(0.035, 0.035, 0.3), Vector3(0, 0, 0.05), "metal", steel, false, 0.4)
			A.cyl(rk, 0.02, 0.06, Vector3(0, -0.04, -0.09), "metal", bright)   # valve stem cap
			_rockers.append(rk)
			var pr := Node3D.new()
			add_child(pr)
			pr.position = Vector3(x - 0.07 + v * 0.14, 1.36, 0.19)
			A.cyl(pr, 0.012, 1.5, Vector3(0, 0, 0), "metal", bright)
			_pushrods.append(pr)
	# Flywheel: rim, spokes and hub.
	_flywheel = Node3D.new()
	add_child(_flywheel)
	_flywheel.position = Vector3(0.62, CY, 0)
	A.ring(_flywheel, 0.44, 0.36, Vector3.ZERO, "metal", paint.darkened(0.3), Vector3(0, 0, PI / 2))
	A.cyl(_flywheel, 0.44, 0.1, Vector3.ZERO, "metal", paint.darkened(0.3), false, "x", 0.44).scale = Vector3(1, 0.2, 1)
	for k in 5:
		var sp := A.box(_flywheel, Vector3(0.05, 0.36, 0.05), Vector3(0, 0.2, 0).rotated(Vector3.RIGHT, k * TAU / 5.0), "metal", paint.darkened(0.3), false, 0.4)
		sp.rotation.x = k * TAU / 5.0
	A.cyl(_flywheel, 0.08, 0.16, Vector3.ZERO, "metal", dark, false, "x")
	A.box(_flywheel, Vector3(0.11, 0.06, 0.06), Vector3(0, 0.41, 0), "hazard", Color.WHITE, false, 0.3)   # a painted mark, so you see it turn
	# Alternator rotor end: a slotted fan behind the end guard.
	_alt_rotor = Node3D.new()
	add_child(_alt_rotor)
	_alt_rotor.position = Vector3(1.37, CY, 0)
	for k in 8:
		var b := A.box(_alt_rotor, Vector3(0.02, 0.26, 0.05), Vector3(0, 0.14, 0).rotated(Vector3.RIGHT, k * TAU / 8.0), "metal", steel, false, 0.3)
		b.rotation.x = k * TAU / 8.0
	# Radiator fan, belt-driven off the crank nose.
	_fan = Node3D.new()
	add_child(_fan)
	_fan.position = Vector3(-1.22, 1.05, 0)
	for i in 6:
		A.box(_fan, Vector3(0.02, 0.42, 0.12), Vector3(0, 0.22, 0).rotated(Vector3.RIGHT, i * TAU / 6), "metal", steel, false, 0.3, Vector3(i * TAU / 6, 0.4, 0))
	A.cyl(_fan, 0.07, 0.08, Vector3.ZERO, "metal", dark, false, "x")
	A.cyl(_fan, 0.09, 0.05, Vector3(0.08, 0, 0), "metal", dark, false, "x")   # pulley
	# Flyball governor on its spindle.
	_gov = Node3D.new()
	add_child(_gov)
	_gov.position = Vector3(-1.08, 1.55, 0.26)
	A.cyl(_gov, 0.012, 0.32, Vector3(0, 0.16, 0), "metal", bright)
	A.cyl(_gov, 0.03, 0.04, Vector3(0, 0.32, 0), "brass", Color.WHITE)
	for s in [-1, 1]:
		var arm := Node3D.new()
		_gov.add_child(arm)
		arm.position = Vector3(0, 0.3, 0)
		A.seg(arm, Vector3.ZERO, Vector3(s * 0.12, -0.12, 0), 0.008, 0.008, "metal", bright)
		A.sphere(arm, 0.035, Vector3(s * 0.12, -0.12, 0), "brass", Color.WHITE)
		_gov_arms.append(arm)
	# The RPM needle on the control cabinet's first dial.
	_needle = Node3D.new()
	add_child(_needle)
	_needle.position = needle_at
	A.box(_needle, Vector3(0.006, 0.07, 0.008), Vector3(0, 0.025, 0), "metal", Color(0.8, 0.1, 0.1), false, 0.2)
	# Its sound: the idle rumble, pitched by speed.
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = Sfx.stream("diesel_idle")
	_hum.bus = "World"
	_hum.unit_size = 4.0
	_hum.max_distance = 28.0
	_hum.volume_db = -8.0
	add_child(_hum)
	_hum.position = Vector3(-0.3, 1.0, 0)
	_hum.play.call_deferred(randf() * 1.5)
	_theta = randf() * TAU
	# Each moving part to one mesh (it was ninety-odd pieces an engine, every one costing a draw and
	# its own culling): parts inside parts stay their own, marked live so the outer one leaves them.
	var parts: Array[Node3D] = []
	parts.append_array(_throws)
	parts.append_array(_rods)
	parts.append_array(_heads)
	parts.append_array(_rockers)
	parts.append_array(_pushrods)
	parts.append_array(_gov_arms)
	parts.append_array([_flywheel, _fan, _alt_rotor, _gov, _needle])
	for p in parts:
		p.set_meta("live", true)
	for p in parts:
		Merge.bake(p, 1000.0)
	Merge.bake(self, 1000.0)


func _process(delta: float) -> void:
	var want := RUN_RATE if running else 0.0
	rate = move_toward(rate, want, delta * (RUN_RATE / 1.5 if running else RUN_RATE / 3.5))   # catches quick, runs down slow
	_theta += rate * delta
	var k := rate / RUN_RATE
	for i in _throws.size():
		var a: float = _theta + PHASE[i]
		_throws[i].rotation.x = a
		var pin := Vector3(CYL_X[i], CY + RC * cos(a), RC * sin(a))
		var xh := Vector3(CYL_X[i], CY + RC * cos(a) + sqrt(ROD * ROD - pow(RC * sin(a), 2.0)), 0)
		_heads[i].position = xh
		_rods[i].position = (pin + xh) / 2.0
		_rods[i].rotation.x = atan2(xh.z - pin.z, xh.y - pin.y)
		# Four-stroke valve timing: each valve opens for a quarter of the 720 degree cycle.
		var cyc := fmod(_theta + FIRE[i], 4.0 * PI)
		for v in 2:
			var open_at := PI * (2.9 if v == 0 else 3.9)
			var u := fmod(cyc - open_at + 8.0 * PI, 4.0 * PI)
			var lift := sin(u * 2.0) if u < PI / 2.0 else 0.0
			_rockers[i * 2 + v].rotation.x = -0.12 * lift
			_pushrods[i * 2 + v].position.y = 1.36 + 0.02 * lift
	_flywheel.rotation.x = _theta
	_alt_rotor.rotation.x = _theta
	_fan.rotation.x = _theta * 1.6
	_gov.rotation.y = _theta * 0.5
	for j in _gov_arms.size():
		_gov_arms[j].rotation.z = (1.0 if j == 0 else -1.0) * 0.5 * k * k
	_needle.rotation.x = deg_to_rad(120.0 - 240.0 * k * (0.96 + 0.02 * sin(_theta * 3.0)))
	position.y = 0.0015 * k * sin(_theta * 2.0)   # it shakes on its mounts
	_hum.pitch_scale = maxf(0.3, 0.55 + 0.45 * k)
	_hum.volume_db = lerpf(-60.0, -8.0, minf(1.0, k * 1.5))
