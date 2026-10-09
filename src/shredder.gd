# The checkpoint shredder: a twin-shaft industrial shredder like the real ones. A flared hopper
# feeds the cutting chamber, where two shafts of hooked cutter discs turn into each other at
# different speeds (so the teeth meet in a new place every turn), stripper combs between the discs
# keep them clean, and a motor drives it all through a V-belt and a gearbox. What it chews drops
# onto a discharge conveyor that carries the shreds up and over into the skip.
#
# Throwing the MAIN DRIVE lever (a heavy ratcheting handle on the control pedestal) runs a cycle:
# the klaxon and the beacon, the motor spooling up, then each item in the hopper is dragged down
# into the cutters and chewed (metal shrieks and sparks, soft stuff cracks and snaps), the ammeter
# swinging with the load. Heavy scrap jams the cutters: the drive bogs, kicks into reverse,
# then goes back at it. Credits tick up on the readout as it goes. Anyone in the throat while it
# runs gets hurt and thrown clear.
#
# The host runs the cycle (items, money); everyone sees and hears it through "shredder" events.
# Static parts are built straight into the level so they merge; this node keeps the moving ones.
extends Node

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Data = preload("res://src/data.gd")
const Sfx = preload("res://src/sfx.gd")

const CZ := 13.0                  # the cutting chamber's centre (level coordinates)
const SHAFT_Y := 0.62
const NIP := Vector3(0.0, 0.95, 13.0)   # where things are dragged down into the cutters
const LEVER_REST := 0.45          # the lever's angle, up (tilted back)
const LEVER_THROWN := -1.3        # ...and thrown down towards you
const SPIN := 5.5
const FLAT := Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))   # a label lying face up, read from -z                 # rad/s of the faster shaft at full speed

var main
var level: Node3D
var board: Label3D
var running := false
var run_pay := 0                  # credits paid so far this cycle (on the readout)

var _shafts: Array[Node3D] = []
var _pulleys: Array[Node3D] = []
var _lever: Node3D
var _needle: Node3D
var _lamps := {}                  # "power"/"run"/"over" -> StandardMaterial3D
var _beacon: Node3D
var _beacon_m: StandardMaterial3D
var _beacon_light: SpotLight3D
var _motor: AudioStreamPlayer3D
var _belt_snd: AudioStreamPlayer3D
var _sparks: GPUParticles3D
var _dust: GPUParticles3D
var _cleats: Array[Node3D] = []
var _conv: Node3D                 # the conveyor's frame: local z runs up the belt
var _conv_len := 0.0
var _chunks: Array = []           # [node, state 0 on belt / 1 falling / 2 resting, velocity]
var _pile := 0

var _speed := 0.0                 # the cutters: 1 = full ahead, negative = reversing
var _target := 0.0
var _load := 0.0                  # 0..1: how hard the motor's working (the ammeter)
var _load_t := 0.0
var _hurt_t := 0.0


func build(lvl: Node3D) -> void:
	level = lvl
	main = lvl.main
	name = "Shredder"
	_housing()
	_cutters()
	_drive()
	_conveyor()
	_gantry()
	_controls()
	_fx()


# --- the machine -------------------------------------------------------------------------------

func _housing() -> void:
	var steel := Color(0.55, 0.56, 0.54)
	var paint := Color(0.86, 0.64, 0.16)
	var rim := 1.31
	# Plinth and the cutting box (solid walls: what you throw in stays in).
	A.box(level, Vector3(3.9, 0.25, 3.9), Vector3(0, 0.185, CZ), "concrete", Color(0.58, 0.56, 0.52), true, 1.0)
	for z in [11.4, 14.6]:
		A.box(level, Vector3(3.4, 1.0, 0.2), Vector3(0, 0.81, z), "riveted", paint, true, 0.8)
	for x in [-1.6, 1.6]:
		A.box(level, Vector3(0.2, 1.0, 3.0), Vector3(x, 0.81, CZ), "riveted", paint, true, 0.8)
	for x in [-1.72, 1.72]:   # corner posts, bolted to the plinth
		for z in [11.28, 14.72]:
			A.box(level, Vector3(0.14, 1.06, 0.14), Vector3(x, 0.84, z), "metal", paint.darkened(0.35), false, 0.6)
			for k in 2:
				A.cyl(level, 0.035, 0.05, Vector3(x + 0.1 * signf(x), 0.33, z + (k - 0.5) * 0.08), "metal", Color(0.3, 0.3, 0.3))
	A.box(level, Vector3(3.44, 0.1, 0.24), Vector3(0, 0.36, 11.4), "hazard", Color.WHITE, false, 0.6)   # kick stripe
	var warn := B.label(level, "KEEP HANDS CLEAR", Vector3(0, 0.72, 11.29), 46, Color(0.12, 0.1, 0.08), "stencil", 0.006)
	warn.rotation.y = PI
	var danger := B.label(level, "DANGER  ·  ROTATING CUTTERS", Vector3(-1.71, 0.95, CZ), 30, Color(0.62, 0.1, 0.06), "stencil", 0.005)
	danger.rotation.y = -PI / 2
	# The hopper: flared sides up from the rim, and a throat sloping down inside to the cutters.
	level._funnel(Vector3(0, rim, CZ), Vector2(1.7, 1.7), Vector2(2.15, 2.15), 0.55, "riveted", steel)
	level._funnel(Vector3(0, 0.78, CZ), Vector2(1.2, 0.75), Vector2(1.5, 1.5), rim - 0.78, "rust", Color(0.42, 0.38, 0.34))
	for s in [-1, 1]:   # angle iron round the top of the flare
		A.box(level, Vector3(4.42, 0.08, 0.08), Vector3(0, rim + 0.57, CZ + s * 2.17), "metal", steel.darkened(0.25), false, 0.6)
		A.box(level, Vector3(0.08, 0.08, 4.26), Vector3(s * 2.17, rim + 0.57, CZ), "metal", steel.darkened(0.25), false, 0.6)
	# Rubber flap curtain hung inside the front of the throat (stops chips flying back out).
	for i in 10:
		var flap := A.box(level, Vector3(0.27, 0.32, 0.015), Vector3(-1.22 + i * 0.27, 1.12, 12.26), "metal", Color(0.08, 0.08, 0.08), false, 0.5)
		flap.rotation.x = 0.35
	A.box(level, Vector3(3.0, 0.04, 3.0), Vector3(0, 0.33, CZ), "metal", Color(0.06, 0.06, 0.06), true)   # the pit floor, dark (scrap lands on it)


## Two shafts of hooked cutter discs, interleaved, with stripper combs reaching in between them.
func _cutters() -> void:
	var disc_c := Color(0.62, 0.62, 0.6)
	var tooth_c := Color(0.82, 0.8, 0.74)
	for k in 2:
		var shaft := Node3D.new()
		level.add_child(shaft)
		shaft.position = Vector3(0, SHAFT_Y, CZ + (k - 0.5) * 0.5)
		A.cyl(shaft, 0.1, 2.9, Vector3.ZERO, "metal", Color(0.3, 0.3, 0.32), false, "x")
		for i in 9:
			var x := -1.2 + i * 0.3 + k * 0.15
			A.cyl(shaft, 0.27, 0.075, Vector3(x, 0, 0), "metal", disc_c, false, "x")
			A.cyl(shaft, 0.15, 0.075, Vector3(x + 0.15, 0, 0), "metal", Color(0.4, 0.4, 0.42), false, "x")   # spacer collar
			for t in 5:   # hooked teeth: a raked tooth with a hook at its tip
				var a := TAU * t / 5.0 + i * 0.9 + k * 0.4
				var hold := Node3D.new()
				shaft.add_child(hold)
				hold.position = Vector3(x, 0, 0)
				hold.rotation.x = a
				A.box(hold, Vector3(0.075, 0.12, 0.1), Vector3(0, 0.29, 0.02), "metal", tooth_c, false, 0.3, Vector3(0.45, 0, 0))
				A.box(hold, Vector3(0.075, 0.05, 0.07), Vector3(0, 0.345, -0.03), "metal", tooth_c.lightened(0.1), false, 0.3, Vector3(-0.5, 0, 0))
		for x in [-1.45, 1.45]:   # bearing blocks in the side walls
			A.box(level, Vector3(0.14, 0.28, 0.3), Vector3(x, SHAFT_Y, shaft.position.z), "metal", Color(0.28, 0.28, 0.3), false, 0.4)
			A.cyl(level, 0.05, 0.16, Vector3(x, SHAFT_Y + 0.17, shaft.position.z), "metal", Color(0.75, 0.6, 0.2))   # grease nipple
		shaft.set_meta("live", true)
		_shafts.append(shaft)
		# The stripper comb along the outside of this shaft: fingers between its discs.
		var side := -1.0 if k == 0 else 1.0
		var cz := CZ + side * 0.6
		A.box(level, Vector3(2.9, 0.1, 0.08), Vector3(0, SHAFT_Y + 0.08, cz), "metal", Color(0.52, 0.52, 0.5), false, 0.5)
		for i in 9:
			var gap := -1.2 + i * 0.3 + k * 0.15 + 0.15
			if gap < 1.35:
				A.box(level, Vector3(0.18, 0.08, 0.3), Vector3(gap, SHAFT_Y + 0.05, cz - side * 0.18), "metal", Color(0.4, 0.4, 0.38), false, 0.4)


## The drive: a big electric motor on its own base, a V-belt up to the gearbox's input pulley,
## the gearbox housing behind the chamber with an inspection plate, an oil sight glass.
func _drive() -> void:
	var paint := Color(0.86, 0.64, 0.16)
	var motor_c := Color(0.34, 0.46, 0.58)
	# Gearbox.
	A.box(level, Vector3(3.4, 1.5, 1.6), Vector3(0, 1.06, 15.6), "riveted", paint, true, 0.9)
	A.box(level, Vector3(3.5, 0.12, 1.7), Vector3(0, 1.87, 15.6), "metal", paint.darkened(0.3), false, 0.8)
	for x in [-1.1, 0.0, 1.1]:   # cooling louvres
		for r in 4:
			A.box(level, Vector3(0.7, 0.04, 0.06), Vector3(x, 0.55 + r * 0.12, 14.78), "metal", paint.darkened(0.45), false, 0.4)
	for x in [-1.25, 1.25]:   # breather caps and the oil sight glass
		A.cyl(level, 0.06, 0.12, Vector3(x, 1.98, 15.6), "metal", Color(0.25, 0.25, 0.25))
	A.cyl(level, 0.07, 0.03, Vector3(0.9, 1.45, 14.79), "metal", Color(0.9, 0.55, 0.1), false, "z")
	A.ring(level, 0.085, 0.065, Vector3(0.9, 1.45, 14.775), "metal", Color(0.3, 0.3, 0.3), Vector3(PI / 2, 0, 0))
	var plate := B.label(level, "B.R.M. RECLAMATION  /  MODEL 7  /  480 V", Vector3(-0.3, 1.45, 14.79), 30, Color(0.85, 0.82, 0.72), "plate", 0.005)
	plate.rotation.y = PI
	A.pipe(level, Vector3(1.2, 1.9, 16.0), Vector3(1.2, 7.4, 16.0), 0.3, "metal", Color(0.6, 0.6, 0.6))   # dust stack
	# The motor: a finned cylinder on a base, the fan cowl with its grille at the back end, a
	# terminal box on top and the conduit down into the floor.
	A.box(level, Vector3(1.5, 0.3, 1.1), Vector3(-2.65, 0.3, 15.6), "metal", Color(0.22, 0.22, 0.22), true, 0.5)
	A.cyl(level, 0.46, 1.2, Vector3(-2.6, 0.95, 15.6), "metal", motor_c, true, "x")
	for k in 9:
		A.ring(level, 0.53, 0.44, Vector3(-3.1 + k * 0.12, 0.95, 15.6), "metal", motor_c, Vector3(0, 0, PI / 2))
	A.cyl(level, 0.5, 0.3, Vector3(-3.35, 0.95, 15.6), "metal", motor_c.darkened(0.2), false, "x")   # fan cowl
	for r in [0.12, 0.24, 0.36, 0.46]:
		A.ring(level, r + 0.02, r, Vector3(-3.51, 0.95, 15.6), "metal", Color(0.12, 0.12, 0.12), Vector3(0, 0, PI / 2))
	A.box(level, Vector3(0.3, 0.2, 0.3), Vector3(-2.55, 1.5, 15.6), "metal", motor_c.darkened(0.15), false, 0.4)   # terminal box
	A.pipe(level, Vector3(-2.55, 1.6, 15.6), Vector3(-2.55, 2.0, 16.3), 0.04, "metal", Color(0.5, 0.5, 0.5))
	A.pipe(level, Vector3(-2.55, 2.0, 16.3), Vector3(-2.55, 0.0, 16.3), 0.04, "metal", Color(0.5, 0.5, 0.5))
	var name_p := B.label(level, "480V  3PH  110 kW", Vector3(-2.65, 0.32, 15.04), 22, Color(0.85, 0.85, 0.8), "plate", 0.005)
	name_p.rotation.y = PI
	A.cyl(level, 0.06, 0.25, Vector3(-1.9, 0.95, 15.6), "metal", Color(0.45, 0.45, 0.45), false, "x")   # motor shaft
	# V-belt drive: a small pulley on the motor, a big spoked one on the gearbox, the belt between.
	var small := Node3D.new()
	level.add_child(small)
	small.position = Vector3(-1.82, 0.95, 15.6)
	A.cyl(small, 0.13, 0.12, Vector3.ZERO, "metal", Color(0.3, 0.3, 0.3), false, "x")
	A.box(small, Vector3(0.13, 0.05, 0.27), Vector3.ZERO, "metal", Color(0.75, 0.2, 0.1), false, 0.3)   # (a mark you can see turn)
	var big := Node3D.new()
	level.add_child(big)
	big.position = Vector3(-1.82, 1.62, 15.6)
	A.ring(big, 0.36, 0.3, Vector3.ZERO, "metal", Color(0.3, 0.3, 0.3), Vector3(0, 0, PI / 2))
	A.cyl(big, 0.07, 0.14, Vector3.ZERO, "metal", Color(0.4, 0.4, 0.4), false, "x")
	for s in 5:
		var spoke := Node3D.new()
		big.add_child(spoke)
		spoke.rotation.x = TAU * s / 5.0
		A.box(spoke, Vector3(0.05, 0.25, 0.05), Vector3(0, 0.17, 0), "metal", Color(0.35, 0.35, 0.35), false, 0.3)
	for n in [small, big]:
		n.set_meta("live", true)
		_pulleys.append(n)
	for s in [-1.0, 1.0]:   # the belt's two runs
		A.seg(level, Vector3(-1.82, 0.95, 15.6 + s * 0.13), Vector3(-1.82, 1.62, 15.6 + s * 0.33), 0.025, 0.025, "metal", Color(0.07, 0.07, 0.07))
	# A belt guard: an open mesh cage on the far side.
	A.box(level, Vector3(0.02, 1.1, 0.9), Vector3(-1.98, 1.28, 15.6), "grate", Color(0.75, 0.6, 0.15), false, 0.5)


## The discharge conveyor: up from the slot in the chamber's side, over into the skip.
func _conveyor() -> void:
	var from := Vector3(1.9, 0.42, 13.0)
	var to := Vector3(4.7, 1.72, 15.9)
	_conv_len = from.distance_to(to)
	_conv = Node3D.new()
	level.add_child(_conv)
	_conv.position = from
	_conv.look_at_from_position(from, to, Vector3.UP)
	_conv.rotate_object_local(Vector3.UP, PI)   # (local +z up the belt)
	_conv.set_meta("live", true)
	var L := _conv_len
	var frame_c := Color(0.3, 0.38, 0.3)
	for s in [-1.0, 1.0]:
		A.box(_conv, Vector3(0.06, 0.16, L), Vector3(s * 0.42, 0.02, L / 2.0), "metal", frame_c, false, 0.6)
	A.box(_conv, Vector3(0.78, 0.03, L), Vector3(0, -0.02, L / 2.0), "metal", Color(0.07, 0.07, 0.07), false, 0.5)   # the belt
	var k := 0.0
	while k < L:
		A.cyl(_conv, 0.05, 0.86, Vector3(0, -0.07, k), "metal", Color(0.45, 0.45, 0.45), false, "x")
		k += 0.35
	for i in int(L / 0.3):   # cleats on the belt (they move)
		var c := A.box(_conv, Vector3(0.74, 0.035, 0.03), Vector3(0, 0.01, i * 0.3), "metal", Color(0.12, 0.12, 0.12), false, 0.4)
		_cleats.append(c)
	A.box(_conv, Vector3(0.95, 0.4, 0.5), Vector3(0, 0.15, 0.1), "riveted", Color(0.86, 0.64, 0.16).darkened(0.1), false, 0.6)   # the hood over the slot
	# Legs down to the floor.
	for t in [0.35, 0.95]:
		var p := from.lerp(to, t)
		for s in [-0.4, 0.4]:
			var side: Vector3 = _conv.global_basis.x * s
			A.seg(level, p + side - Vector3(0, 0.1, 0), Vector3(p.x, 0.0, p.z) + side, 0.035, 0.035, "metal", frame_c)
	# The skip it fills, and what's already in it.
	A.box(level, Vector3(2.6, 1.0, 2.2), Vector3(5.2, 0.55, 16.3), "rust", Color(0.4, 0.5, 0.35), true, 1.0)
	for i in 4:
		level.P.bale(level, Vector3(4.7 + (i % 2) * 0.9, 0.5 + (i / 2) * 0.5, 15.9 + (i / 2) * 0.6), 0.8, level.rng)


## The gantry over it all: columns, braces, the catwalk, the ladder, the sign, the beacon and
## the klaxon's horn speaker.
func _gantry() -> void:
	var red := Color(0.75, 0.25, 0.18)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			level._ibeam_col(Vector3(sx * 2.6, 0, 13.8 + sz * 2.6), 5.0, red)
		A.seg(level, Vector3(sx * 2.6, 0.3, 11.2), Vector3(sx * 2.6, 4.6, 16.4), 0.06, 0.06, "metal", red)
	for sz in [-1, 1]:
		A.box(level, Vector3(5.4, 0.25, 0.2), Vector3(0, 4.9, 13.8 + sz * 2.6), "metal", red, false, 0.6)
	A.box(level, Vector3(5.2, 0.06, 1.2), Vector3(0, 5.05, 11.8), "grate", Color.WHITE, false, 0.5)
	A.railing(level, Vector3(-2.6, 5.05, 11.2), Vector3(2.6, 5.05, 11.2), 1.0, "metal")
	for k in 16:
		A.box(level, Vector3(0.5, 0.04, 0.04), Vector3(2.85, 0.35 + k * 0.3, 16.6), "metal", Color(0.6, 0.6, 0.6), false)
	for s in [-0.22, 0.22]:
		A.box(level, Vector3(0.05, 5.0, 0.05), Vector3(2.85 + s, 2.5, 16.6), "metal", Color(0.6, 0.6, 0.6), false)
	# The sign: an enamel board on the gantry, cream with a red border.
	A.box(level, Vector3(2.9, 0.7, 0.06), Vector3(0, 4.62, 11.12), "metal", Color(0.2, 0.2, 0.2), false, 0.5)
	A.box(level, Vector3(2.76, 0.56, 0.02), Vector3(0, 4.62, 11.08), "cream", Color(0.72, 0.16, 0.1), false, 0.5)
	A.box(level, Vector3(2.62, 0.44, 0.012), Vector3(0, 4.62, 11.066), "cream", Color(0.88, 0.84, 0.72), false, 0.5)
	var sign := B.label(level, "SHREDDER", Vector3(0, 4.62, 11.058), 80, Color(0.62, 0.12, 0.08), "plate", 0.0045)
	sign.rotation.y = PI
	for x in [-1.32, 1.32]:
		A.sphere(level, 0.025, Vector3(x, 4.62, 11.055), "metal", Color(0.7, 0.7, 0.7))
	# Rotating beacon: an amber dome on a black base with a lamp and mirror turning inside.
	A.cyl(level, 0.13, 0.1, Vector3(-1.6, 5.08, 16.4), "metal", Color(0.1, 0.1, 0.1))
	_beacon_m = StandardMaterial3D.new()
	_beacon_m.albedo_color = Color(1.0, 0.55, 0.1, 0.75)
	_beacon_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_m.emission_enabled = true
	_beacon_m.emission = Color(1.0, 0.5, 0.1)
	_beacon_m.emission_energy_multiplier = 0.2
	var dome := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.09
	dm.bottom_radius = 0.12
	dm.height = 0.22
	dome.mesh = dm
	dome.material_override = _beacon_m
	level.add_child(dome)
	dome.position = Vector3(-1.6, 5.24, 16.4)
	dome.set_meta("live", true)
	_beacon = Node3D.new()
	level.add_child(_beacon)
	_beacon.position = Vector3(-1.6, 5.24, 16.4)
	_beacon.set_meta("live", true)
	_beacon_light = SpotLight3D.new()
	_beacon_light.light_color = Color(1.0, 0.55, 0.15)
	_beacon_light.spot_range = 16.0
	_beacon_light.spot_angle = 22.0
	_beacon_light.light_energy = 0.0
	_beacon.add_child(_beacon_light)
	_beacon_light.rotation.x = -0.35
	# The klaxon: a horn speaker under the beam.
	A.seg(level, Vector3(1.6, 4.72, 16.35), Vector3(1.6, 4.5, 16.0), 0.05, 0.16, "metal", Color(0.3, 0.3, 0.3))


## The control pedestal by the hopper: a sloped panel with the ammeter, the lamps and the
## emergency stop, the MAIN DRIVE lever on its side, the readout on a post above.
func _controls() -> void:
	var grey := Color(0.4, 0.43, 0.42)
	var at := Vector3(3.45, 0.0, 11.0)
	A.box(level, Vector3(0.9, 0.95, 0.55), at + Vector3(0, 0.5, 0.05), "metal", grey, true, 0.6)
	A.box(level, Vector3(1.0, 0.06, 0.65), at + Vector3(0, 0.05, 0.05), "metal", grey.darkened(0.4), false, 0.5)   # plinth
	var panel := Node3D.new()   # the sloped face, tilted up towards whoever stands at it (at -z)
	level.add_child(panel)
	panel.position = at + Vector3(0, 1.02, -0.05)
	panel.rotation.x = -0.55
	A.box(panel, Vector3(0.95, 0.04, 0.62), Vector3.ZERO, "metal", Color(0.3, 0.31, 0.3), false, 0.4)
	# The ammeter: a white face, a red zone, a needle that swings with the load.
	A.cyl(panel, 0.15, 0.03, Vector3(-0.22, 0.03, 0.02), "metal", Color(0.15, 0.15, 0.15))
	A.cyl(panel, 0.13, 0.02, Vector3(-0.22, 0.04, 0.02), "cream", Color(0.92, 0.9, 0.82))
	for i in 5:
		var tick := Node3D.new()
		panel.add_child(tick)
		tick.position = Vector3(-0.22, 0.052, 0.02)
		tick.rotation.y = -1.1 + i * 0.55
		A.box(tick, Vector3(0.008, 0.004, 0.03), Vector3(0, 0, -0.095), "metal", Color(0.85, 0.15, 0.1) if i == 4 else Color(0.1, 0.1, 0.1), false)
	var red_zone := Node3D.new()
	panel.add_child(red_zone)
	red_zone.position = Vector3(-0.22, 0.051, 0.02)
	red_zone.rotation.y = -1.0
	A.box(red_zone, Vector3(0.05, 0.003, 0.012), Vector3(-0.07, 0, -0.08), "cream", Color(0.85, 0.15, 0.1), false)
	_needle = Node3D.new()
	panel.add_child(_needle)
	_needle.position = Vector3(-0.22, 0.058, 0.02)
	_needle.set_meta("live", true)
	A.box(_needle, Vector3(0.006, 0.004, 0.11), Vector3(0, 0, -0.05), "metal", Color(0.05, 0.05, 0.05), false)
	_needle.rotation.y = 1.1
	var amps := B.label(panel, "AMPS", Vector3(-0.22, 0.056, -0.05), 12, Color(0.2, 0.2, 0.2), "plate", 0.0035)
	amps.basis = FLAT   # (lying on the panel, the right way up for whoever stands at it)
	# Lamps: POWER green, RUNNING amber, OVERLOAD red.
	var names := ["power", "run", "over"]
	var cols := [Color(0.2, 1, 0.3), Color(1, 0.65, 0.1), Color(1, 0.15, 0.1)]
	var words := ["POWER", "RUN", "OVERLOAD"]
	for i in 3:
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[i].darkened(0.5)
		m.emission_enabled = true
		m.emission = cols[i]
		m.emission_energy_multiplier = 2.5 if i == 0 else 0.0
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.028
		sm.height = 0.04
		lamp.mesh = sm
		lamp.material_override = m
		panel.add_child(lamp)
		lamp.position = Vector3(0.0 + i * 0.13, 0.04, 0.14)
		lamp.set_meta("live", true)
		A.cyl(panel, 0.038, 0.02, Vector3(0.0 + i * 0.13, 0.025, 0.14), "metal", Color(0.6, 0.6, 0.6))
		var w := B.label(panel, words[i], Vector3(0.0 + i * 0.13, 0.024, 0.085), 10, Color(0.9, 0.9, 0.85), "plate", 0.003)
		w.basis = FLAT
		_lamps[names[i]] = m
	# Emergency stop: a red mushroom on a yellow collar (for show: the Bureau removed the wiring).
	A.cyl(panel, 0.06, 0.03, Vector3(0.13, 0.035, -0.12), "plastic", Color(0.95, 0.8, 0.1))
	A.sphere(panel, 0.05, Vector3(0.13, 0.07, -0.12), "plastic", Color(0.8, 0.08, 0.06), 0.0, 0.6)
	var key := B.label(panel, "EMERGENCY STOP", Vector3(0.13, 0.024, -0.2), 10, Color(0.95, 0.85, 0.2), "plate", 0.003)
	key.basis = FLAT
	# The MAIN DRIVE lever: a cast switch box on the pedestal's side, a toothed quadrant, and a
	# long handle with a red ball, pivoting at the box. Up (back) is off; thrown down, it runs.
	var box_at := at + Vector3(0.52, 0.95, 0.0)
	A.box(level, Vector3(0.16, 0.36, 0.3), box_at, "metal", Color(0.24, 0.3, 0.26), false, 0.4)
	A.box(level, Vector3(0.17, 0.05, 0.31), box_at + Vector3(0, 0.2, 0), "metal", Color(0.2, 0.24, 0.22), false, 0.4)
	for i in 9:   # the ratchet quadrant's teeth, round the pivot
		var a := LEVER_REST - (LEVER_REST - LEVER_THROWN) * i / 8.0
		A.box(level, Vector3(0.03, 0.035, 0.035), box_at + Vector3(0.1, 0.0, 0.0) + Vector3(0, cos(a), sin(a)) * 0.2, "metal", Color(0.55, 0.55, 0.52), false, 0.3, Vector3(a, 0, 0))
	var lbl := B.label(level, "MAIN DRIVE", box_at + Vector3(0.081, -0.08, 0), 16, Color(0.9, 0.85, 0.7), "plate", 0.004)
	lbl.rotation.y = PI / 2
	_lever = Node3D.new()
	level.add_child(_lever)
	_lever.position = box_at + Vector3(0.13, 0, 0)
	_lever.rotation.x = LEVER_REST
	_lever.set_meta("live", true)
	A.cyl(_lever, 0.05, 0.06, Vector3.ZERO, "metal", Color(0.3, 0.3, 0.3), false, "x")   # pivot boss
	var grip := B.interactable(_lever, Vector3(0.12, 0.95, 0.12), Vector3(0, 0.45, 0), Color(0, 0, 0, 0), "Throw MAIN DRIVE: shred & submit", Callable(), 0.0, 0.0)
	A.box(_lever, Vector3(0.045, 0.85, 0.045), Vector3(0, 0.42, 0), "metal", Color(0.62, 0.62, 0.6), false, 0.4)
	A.sphere(_lever, 0.075, Vector3(0, 0.88, 0), "plastic", Color(0.85, 0.08, 0.06))
	A.box(_lever, Vector3(0.06, 0.12, 0.06), Vector3(0, 0.12, 0), "metal", Color(0.25, 0.25, 0.25), false, 0.3)   # the pawl housing
	grip.action = func(): main.shred()
	# The readout on its post.
	A.box(level, Vector3(0.1, 1.1, 0.1), Vector3(3.45, 1.6, 11.28), "metal", Color(0.3, 0.3, 0.3), false, 0.5)   # post
	A.box(level, Vector3(1.16, 0.8, 0.24), Vector3(3.45, 2.45, 11.2), "metal", Color(0.32, 0.33, 0.31), false, 0.5)   # readout cabinet
	A.box(level, Vector3(1.04, 0.66, 0.02), Vector3(3.45, 2.45, 11.075), "metal", Color(0.02, 0.025, 0.02), false)
	A.box(level, Vector3(1.2, 0.08, 0.3), Vector3(3.45, 2.88, 11.18), "metal", Color(0.22, 0.22, 0.22), false, 0.5)   # hood
	board = B.display(level, "", Vector3(3.45, 2.45, 11.06), 26, Color(1, 0.72, 0.3))
	board.rotation.y = PI
	board.pixel_size = 0.0019
	board.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS   # (drawn in depth order: never through the machine)
	B.omni(level, Vector3(3.45, 2.45, 10.7), Color(1, 0.7, 0.35), 0.25, 1.6)


func _fx() -> void:
	_sparks = _particles(70, 0.9, Vector3(0, 1, 0), 55.0, 2.5, 6.5, -12.0, Vector3(0.025, 0.025, 0.07), B.mat(Color(1, 0.6, 0.2), 6.0))
	_dust = _particles(40, 1.6, Vector3(0, 1, 0), 40.0, 0.6, 1.8, -1.0, Vector3(0.09, 0.09, 0.09), B.mat(Color(0.45, 0.42, 0.38)))
	for p in [_sparks, _dust]:
		level.add_child(p)
		p.position = NIP + Vector3(0, -0.15, 0)
	_motor = _loop_player("shred_motor", Vector3(0, 1.0, 14.6), 9.0)
	_belt_snd = _loop_player("conveyor", Vector3(3.3, 1.0, 14.4), 4.0)
	B.omni(level, Vector3(0, 3.0, 12.5), Color(1, 0.75, 0.45), 1.0, 6.0)


func _particles(n: int, life: float, dir: Vector3, spread: float, v0: float, v1: float, g: float, size: Vector3, m: Material) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = n
	p.lifetime = life
	p.explosiveness = 0.3
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = v0
	pm.initial_velocity_max = v1
	pm.gravity = Vector3(0, g, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.05, 0.2)
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	p.draw_pass_1 = bm
	return p


func _loop_player(sound: String, at: Vector3, unit: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.stream = Sfx.stream(sound)
	a.unit_size = unit
	a.max_distance = 60.0
	a.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	a.volume_db = -80.0
	level.add_child(a)
	a.position = at
	return a


# --- the cycle (host) --------------------------------------------------------------------------

## Host: chew through `items` (pickups in the hopper). main.shred_item pays for each one as it
## goes; main.shred_done sums it up.
func run(items: Array) -> void:
	if running:
		return
	running = true
	run_pay = 0
	var pace := Data.pace()
	items.sort_custom(func(a, b): return (100.0 if Data.is_heavy(a.id) else 0.0) + a.mass < (100.0 if Data.is_heavy(b.id) else 0.0) + b.mass)   # light things first
	for p in items:   # nobody takes them back out now
		p.remove_from_group("pickups")
		p.remove_from_group("movable")
		p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		p.freeze = true
		p.set_meta("shredding", true)
	_say(["start"])
	await _wait(1.8 * pace)
	var got := {}
	var total := 0.0
	var n := 0
	for p in items:
		if not is_instance_valid(p):
			continue
		var id: String = p.id
		var res: Dictionary = Data.ITEMS[id].res
		var metal: int = res.get("steel", 0) + res.get("copper", 0)
		var hard: bool = metal > res.get("plastic", 0) + res.get("rubber", 0)
		var heavy := Data.is_heavy(id)
		# Dragged down into the nip.
		var nip := NIP + Vector3(clampf(p.global_position.x - level.global_position.x, -0.8, 0.8), 0, randf_range(-0.08, 0.08))
		var tw: Tween = p.create_tween().set_parallel()
		tw.tween_property(p, "global_position", level.to_global(nip), 0.45 * pace).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(p, "rotation", p.rotation + Vector3(randf_range(-1, 1), randf_range(-2, 2), randf_range(-1, 1)), 0.45 * pace)
		await _wait(0.45 * pace)
		if heavy:   # too much for it in one bite: the cutters stall, back off, and go at it again
			_say(["jam"])
			await _wait(1.3 * pace)
		var dur: float = (1.0 + minf(p.mass, 12.0) * 0.06) * (1.4 if heavy else 1.0)
		_say(["chew", hard, dur, Data.color(id), _size(p)])
		var t := 0.0
		var top: Vector3 = p.global_position
		while t < dur * pace and is_instance_valid(p):   # it shudders, and sinks into the teeth
			var k := t / (dur * pace)
			p.global_position = top + Vector3(randf_range(-0.04, 0.04), -0.75 * k, randf_range(-0.03, 0.03))
			p.rotation += Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.1), randf_range(-0.2, 0.2))
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		if is_instance_valid(p):
			p.queue_free()
		var pay: float = main.shred_item(id)
		total += pay
		run_pay = roundi(total)
		for r in res:
			got[r] = got.get(r, 0) + res[r]
		n += 1
		_say(["paid", run_pay])
	await _wait(0.6 * pace)
	_say(["stop"])
	await _wait(1.6 * pace)
	running = false
	main.shred_done(n, got, total)


## Throwing the lever over an empty hopper: it runs up, finds nothing, and stops.
func dry_run() -> void:
	if running:
		return
	running = true
	_say(["start"])
	await _wait(1.5 * Data.pace())
	_say(["stop"])
	await _wait(1.0 * Data.pace())
	running = false


func _size(p: Node) -> float:
	var s: Vector3 = Data.ITEMS[p.id].size
	return s.x * s.y * s.z


func _wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout


## Host: tell everyone (and ourselves).
func _say(args: Array) -> void:
	if main.net.active:
		main.net.event("shredder", args)
	net_event(args)


# --- what everyone sees and hears ----------------------------------------------------------------

func net_event(args: Array) -> void:
	var pace := Data.pace()
	match args[0]:
		"start":
			running = true
			run_pay = 0
			_throw_lever(true)
			Sfx.play(level, "alarm", level.to_global(Vector3(1.6, 4.5, 16.0)), 2.0, 0.9)
			_lamps.run.emission_energy_multiplier = 3.0
			_beacon_light.light_energy = 6.0
			_beacon_m.emission_energy_multiplier = 4.0
			Sfx.play(level, "power_up", level.to_global(Vector3(-2.6, 1.0, 15.6)), -2.0, 0.6)
			_motor.play()
			_belt_snd.play()
			_target = 1.0
		"jam":
			_target = 0.0
			_speed = 0.0
			_load = 1.0
			_load_t = 1.3 * pace
			_lamps.over.emission_energy_multiplier = 4.0
			Sfx.play(level, "shred_jam", level.to_global(NIP), 4.0)
			_shake(0.05, 6.0)
			get_tree().create_timer(0.45 * pace, false).timeout.connect(func(): _target = -0.55)   # the drive kicks into reverse
			get_tree().create_timer(1.1 * pace, false).timeout.connect(func():
				_target = 1.0
				_lamps.over.emission_energy_multiplier = 0.0)
		"chew":
			var hard: bool = args[1]
			var dur: float = args[2]
			Sfx.play(level, "shred_metal" if hard else "shred_soft", level.to_global(NIP), 4.0 if hard else 1.0, randf_range(0.85, 1.1) * (1.15 / maxf(0.8, dur)) * 1.1)
			if dur > 1.3:
				get_tree().create_timer(0.6 * dur * pace, false).timeout.connect(func(): Sfx.play(level, "shred_metal" if hard else "shred_soft", level.to_global(NIP), 2.0, randf_range(0.8, 1.0)))
			_load = clampf(0.45 + dur * 0.25, 0.0, 1.0)
			_load_t = dur * pace
			_target = 0.8   # (it slows under the load)
			get_tree().create_timer(dur * pace, false).timeout.connect(func(): _target = 1.0 if running else 0.0)
			if hard:
				_sparks.restart()
				_sparks.emitting = true
			_dust.restart()
			_dust.emitting = true
			_shake(0.025 if not hard else 0.04, 7.0)
			var count := clampi(int(args[4] * 400.0) + 3, 3, 14)
			for i in count:   # the shreds come out onto the belt over the next while
				get_tree().create_timer(dur * pace * (0.4 + 0.9 * i / count), false).timeout.connect(_chunk.bind(args[3]))
		"paid":
			run_pay = args[1]
		"stop":
			_target = 0.0
			Sfx.play(level, "power_down", level.to_global(Vector3(-2.6, 1.0, 15.6)), -4.0, 0.7)
			get_tree().create_timer(1.6 * pace, false).timeout.connect(func():
				_motor.stop()
				_belt_snd.stop()
				_lamps.run.emission_energy_multiplier = 0.0
				_beacon_light.light_energy = 0.0
				_beacon_m.emission_energy_multiplier = 0.2
				_throw_lever(false)
				running = false)


func _throw_lever(down: bool) -> void:
	var tw := _lever.create_tween()
	if down:
		tw.tween_property(_lever, "rotation:x", LEVER_REST + 0.08, 0.08)   # (taken in hand)
		tw.tween_property(_lever, "rotation:x", LEVER_THROWN, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		Sfx.play(level, "ratchet", _lever.global_position, -2.0)
		tw.tween_callback(func(): Sfx.play(level, "clunk", _lever.global_position, 0.0, 1.3))
		tw.tween_property(_lever, "rotation:x", LEVER_THROWN + 0.06, 0.06)   # bounce off the stop
		tw.tween_property(_lever, "rotation:x", LEVER_THROWN, 0.1)
	else:   # the spring takes it back up
		Sfx.play(level, "ratchet", _lever.global_position, -6.0, 0.8)
		tw.tween_property(_lever, "rotation:x", LEVER_REST, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): Sfx.play(level, "clack", _lever.global_position, -4.0, 0.7))


func _shake(amount: float, within: float) -> void:
	var p = main.player
	if p != null and p.global_position.distance_to(level.to_global(NIP)) < within:
		p.shake(amount)


## A shred dropped onto the belt (local to every machine: these are just for show).
func _chunk(tint: Color) -> void:
	if not is_instance_valid(_conv):
		return
	var c := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(randf_range(0.05, 0.13), randf_range(0.02, 0.06), randf_range(0.05, 0.12))
	c.mesh = bm
	c.material_override = A.mat("rust", tint.lerp(Color(0.4, 0.38, 0.35), 0.35), 1.0)
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_conv.add_child(c)
	c.position = Vector3(randf_range(-0.3, 0.3), 0.04, 0.25)
	c.rotation.y = randf() * TAU
	_chunks.append([c, 0, Vector3.ZERO])


# --- per frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if level == null:
		return
	var rate := 1.0 / Data.pace()
	_speed = move_toward(_speed, _target, delta * rate * (0.7 if _target > _speed else 0.9))
	var w := _speed * SPIN * delta
	if not _shafts.is_empty():
		_shafts[0].rotation.x += w
		_shafts[1].rotation.x -= w * 0.78   # (slower: the teeth meet somewhere new each turn)
		_pulleys[0].rotation.x += w * 4.0
		_pulleys[1].rotation.x += w * 4.0 * 0.36
	var mag := absf(_speed)
	_motor.pitch_scale = 0.35 + 0.65 * mag
	_motor.volume_db = linear_to_db(maxf(mag, 0.001)) + 2.0
	_belt_snd.volume_db = linear_to_db(maxf(mag, 0.001)) - 6.0
	# The ammeter: idle current running free, a swing up under load.
	_load_t -= delta
	if _load_t <= 0.0:
		_load = move_toward(_load, 0.0, delta * 2.0 * rate)
	var amps := mag * 0.3 + _load * 0.7
	_needle.rotation.y = lerpf(_needle.rotation.y, 1.1 - amps * 2.2 + randf_range(-0.03, 0.03) * mag, minf(1.0, delta * 10.0))
	_beacon.rotation.y += delta * 9.0 * (1.0 if running else 0.0)
	# The belt: cleats creep up it and wrap round; shreds ride it to the top and drop off.
	var belt := _speed * 0.9 * delta * rate if _speed > 0.0 else 0.0
	for c in _cleats:
		c.position.z = fposmod(c.position.z + belt, _conv_len)
	for ch in _chunks.duplicate():
		var n: Node3D = ch[0]
		if not is_instance_valid(n):
			_chunks.erase(ch)
			continue
		match ch[1]:
			0:
				n.position.z += belt
				if n.position.z > _conv_len:   # over the end: falling into the skip
					var g := n.global_transform
					n.reparent(level)
					n.global_transform = g
					ch[1] = 1
					ch[2] = (_conv.global_basis.z * 0.9 + Vector3(randf_range(-0.2, 0.2), 0.3, randf_range(-0.2, 0.2))) * rate
			1:
				ch[2] += Vector3(0, -9.8 * rate * rate, 0) * delta
				n.global_position += ch[2] * delta
				var floor_y: float = level.global_position.y + 1.06 + minf(_pile, 60) * 0.004
				if n.global_position.y < floor_y:
					n.global_position.y = floor_y + randf_range(0.0, 0.03)
					ch[1] = 2
					_pile += 1
					Sfx.play(level, "clank" if randf() < 0.5 else "thunk", n.global_position, -18.0, randf_range(1.2, 1.6))
	while _chunks.filter(func(ch): return ch[1] == 2).size() > 70:   # (the skip doesn't fill forever)
		for ch in _chunks:
			if ch[1] == 2:
				ch[0].queue_free()
				_chunks.erase(ch)
				break
	# Anyone down in the throat while it's turning.
	_hurt_t -= delta
	if running and absf(_speed) > 0.3 and _hurt_t <= 0.0:
		var p = main.player
		var local: Vector3 = level.to_local(p.global_position)
		if not p.dead and absf(local.x) < 1.45 and absf(local.z - CZ) < 1.45 and local.y < 1.6:
			_hurt_t = 0.8
			p.hurt(30.0, "The shredder. The Bureau did ask.")
			p.velocity = Vector3(0, 7.5, -4.0)
			Sfx.play(level, "shred_soft", p.global_position, 4.0, 0.7)
			main.hud.alert("KEEP HANDS CLEAR")
