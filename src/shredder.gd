# The checkpoint shredder: a twin-shaft industrial shredder like the real ones, in Bureau green.
# A heavy riveted cutting chamber on a concrete plinth; the hopper rises off it (a raked front you
# feed over from the step, cheek plates climbing to a tall back plate under a dust hood whose duct
# goes out through the roof). Inside, two shafts of hooked cutter discs turn into each other at
# different speeds (so the teeth meet in a new place every turn), stripper combs between the discs
# keep them clean, and wear liners rake everything down onto them. Bearing housings stand out of the
# flanks; the gearbox is behind, the motor lies on top of it, a V-belt runs down the side in its
# guard. What it chews drops onto a discharge conveyor that carries the shreds up into the skip.
#
# The control desk beside it: a steel cabinet with a sloped desk (the ammeter, the pilot lamps,
# the emergency stop, the DIVERTER), the MAIN DRIVE lever on its quadrant at the end, the readout
# in a hooded screen on the raised back. Throwing the lever runs a cycle: the klaxon and the beacon,
# the motor spooling up, then each item in the hopper is dragged down into the cutters and chewed
# (metal shrieks and sparks, soft stuff cracks and snaps), the ammeter swinging with the load.
# Heavy scrap jams the cutters: the drive bogs, kicks into reverse, then goes back at it. Credits
# tick up on the readout as it goes. Anyone in the throat while it runs gets hurt and thrown clear.
#
# The host runs the cycle (items, money); everyone sees and hears it through "shredder" events.
# Static parts are built straight into the level so they merge; this node keeps the moving ones.
extends Node

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Data = preload("res://src/data.gd")
const Sfx = preload("res://src/sfx.gd")

const CZ := 13.0                  # the cutting chamber's centre (level coordinates)
const SHAFT_Y := 0.72
const NIP := Vector3(0.0, 1.0, 13.0)   # where things are dragged down into the cutters
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
var _dial: Node3D   # the DIVERTER's handle
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
#
# Bureau green over riveted plate, weathered: a heavy cutting chamber on a concrete plinth, the
# hopper rising off it (a raked front you feed over from the step, cheek plates climbing to a tall
# back plate under the dust hood), bearing housings standing out of its flanks, the gearbox behind
# with the motor lying on top of it and the belt drive in its guard down the side.

const GREEN := Color(0.5, 0.6, 0.48)
const STEEL := Color(0.55, 0.55, 0.53)
const YELLOW := Color(0.86, 0.66, 0.14)
const LIP_Y := 1.88               # the hopper's front lip (you feed over it from the step)
const LIP_Z := 11.15
const BACK_Y := 3.05              # ...and the top of its back plate


## An invisible wall (the plates are drawn separately, or are too thin to stand on).
func _block(size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	level.add_child(body)
	body.position = pos
	body.rotation = rot


## A flat plate through four points (seen from both sides).
func _plate(pts: Array, kind: String, tint: Color, parent: Node3D = null) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for side in [1.0, -1.0]:
			st.set_normal(n * side)
			var order: Array = tri if side < 0.0 else [tri[0], tri[2], tri[1]]
			for k in order:
				st.add_vertex(pts[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = A.mat(kind, tint, 0.8)
	(parent if parent != null else level).add_child(mi)


## A row of bolt heads from a to b, standing out along `axis`.
func _bolts(parent: Node3D, a: Vector3, b: Vector3, n: int, axis: String, r := 0.022) -> void:
	for i in n:
		A.cyl(parent, r, 0.022, a.lerp(b, (i + 0.5) / n), "metal", Color(0.22, 0.22, 0.22), false, axis)


## Where the hopper's cheek plates top out, z along the side.
static func _cheek_top(z: float) -> float:
	return LIP_Y + (z - LIP_Z) / (14.5 - LIP_Z) * (BACK_Y - LIP_Y)


func _housing() -> void:
	var dark := GREEN.darkened(0.35)
	# The plinth, a hazard edge on it, and the feed step along the front.
	A.box(level, Vector3(4.6, 0.18, 5.7), Vector3(0, 0.15, 13.55), "concrete", Color(0.58, 0.56, 0.52), true, 1.0)
	A.box(level, Vector3(4.62, 0.1, 0.02), Vector3(0, 0.15, 10.695), "hazard", Color.WHITE, false, 0.5)
	A.box(level, Vector3(3.9, 0.05, 0.6), Vector3(0, 0.265, 11.05), "metal", Color(0.12, 0.12, 0.12), true, 0.5)
	A.box(level, Vector3(3.9, 0.02, 0.6), Vector3(0, 0.3, 11.05), "grate", Color(0.7, 0.7, 0.66), false, 0.4)
	A.box(level, Vector3(3.92, 0.04, 0.05), Vector3(0, 0.29, 10.76), "metal", YELLOW, false, 0.5)   # nosing
	# The cutting chamber: heavy riveted walls (what goes in stays in), stiffener ribs, a foot
	# flange bolted to the plinth, a flange round its top where the hopper sits.
	A.box(level, Vector3(3.8, 1.06, 0.2), Vector3(0, 0.77, 11.5), "riveted", GREEN, true, 0.8)
	A.box(level, Vector3(3.8, 1.06, 0.2), Vector3(0, 0.77, 14.5), "riveted", GREEN, true, 0.8)
	for x in [-1.8, 1.8]:
		A.box(level, Vector3(0.2, 1.06, 2.8), Vector3(x, 0.77, CZ), "riveted", GREEN, true, 0.8)
	A.box(level, Vector3(4.0, 0.06, 3.4), Vector3(0, 0.27, CZ), "metal", dark, false, 0.6)
	_bolts(level, Vector3(-1.9, 0.31, 11.32), Vector3(1.9, 0.31, 11.32), 12, "y", 0.025)
	_bolts(level, Vector3(-1.9, 0.31, 14.68), Vector3(1.9, 0.31, 14.68), 12, "y", 0.025)
	for z in [11.36, 14.64]:
		A.box(level, Vector3(4.0, 0.08, 0.14), Vector3(0, 1.3, z), "metal", dark, false, 0.5)
	for x in [-1.94, 1.94]:
		A.box(level, Vector3(0.14, 0.08, 3.4), Vector3(x, 1.3, CZ), "metal", dark, false, 0.5)
	_bolts(level, Vector3(-1.85, 1.35, 11.33), Vector3(1.85, 1.35, 11.33), 14, "y")
	for x in [-1.5, -0.95, 0.95, 1.5]:   # front ribs
		A.box(level, Vector3(0.07, 0.94, 0.1), Vector3(x, 0.77, 11.36), "metal", GREEN.darkened(0.15), false, 0.5)
	for x in [-1.92, 1.92]:   # flank ribs, clear of the bearings
		for z in [11.85, 14.15]:
			A.box(level, Vector3(0.1, 0.94, 0.07), Vector3(x, 0.77, z), "metal", GREEN.darkened(0.15), false, 0.5)
	A.box(level, Vector3(1.8, 0.11, 0.012), Vector3(0, 1.17, 11.393), "hazard", Color.WHITE, false, 0.5)   # chevrons over the lettering
	var warn := B.label(level, "KEEP HANDS CLEAR", Vector3(0, 0.82, 11.392), 38, Color(0.1, 0.09, 0.07), "stencil", 0.0048)
	warn.rotation.y = PI
	var no := B.label(level, "No.7", Vector3(-1.23, 0.82, 11.392), 54, Color(0.1, 0.09, 0.07), "stencil", 0.006)
	no.rotation.y = PI
	var danger := B.label(level, "DANGER  ·  ROTATING CUTTERS", Vector3(-1.905, 1.12, CZ), 22, Color(0.85, 0.2, 0.1), "stencil", 0.0048)
	danger.rotation.y = -PI / 2
	for p in [[Vector3(1.3, 0.5, 11.393), Vector3(0.5, 0.35, 0.006)], [Vector3(-0.5, 0.42, 11.393), Vector3(0.7, 0.2, 0.006)], [Vector3(-1.905, 0.55, 14.0), Vector3(0.006, 0.3, 0.6)]]:
		A.box(level, p[1], p[0], "rust", Color(0.75, 0.6, 0.5), false, 0.6)   # where the paint's gone
	# The bearing housings on both flanks: a pillow block per side, a round cap for each shaft with
	# its bolt ring, grease nipples and their lines up to a manifold on the flange.
	for s in [-1.0, 1.0]:
		A.box(level, Vector3(0.18, 0.56, 1.15), Vector3(s * 1.99, SHAFT_Y, CZ), "metal", dark, false, 0.5)
		A.box(level, Vector3(0.22, 0.08, 1.3), Vector3(s * 2.0, SHAFT_Y - 0.3, CZ), "metal", dark.darkened(0.2), false, 0.5)
		for k in 2:
			var z := CZ + (k - 0.5) * 0.5
			A.cyl(level, 0.19, 0.12, Vector3(s * 2.13, SHAFT_Y, z), "metal", STEEL.darkened(0.15), false, "x")
			A.cyl(level, 0.1, 0.05, Vector3(s * 2.21, SHAFT_Y, z), "metal", STEEL, false, "x")
			for b in 6:
				var a := TAU * b / 6.0
				A.cyl(level, 0.018, 0.03, Vector3(s * 2.2, SHAFT_Y + cos(a) * 0.145, z + sin(a) * 0.145), "metal", Color(0.2, 0.2, 0.2), false, "x")
			A.cyl(level, 0.016, 0.05, Vector3(s * 2.1, SHAFT_Y + 0.22, z), "brass", Color(0.85, 0.7, 0.35))
			A.seg(level, Vector3(s * 2.1, SHAFT_Y + 0.25, z), Vector3(s * 2.0, 1.22, CZ + (k - 0.5) * 0.16), 0.008, 0.008, "copper", Color.WHITE)
		A.box(level, Vector3(0.1, 0.1, 0.36), Vector3(s * 2.0, 1.22, CZ), "brass", Color(0.8, 0.65, 0.3), false, 0.4)   # the manifold
	# Inside: a dark floor under the cutters (what's thrown in rests in their teeth, on an unseen
	# floor at their middle), and wear liners raked down onto the cutters from every side.
	A.box(level, Vector3(3.4, 0.04, 2.8), Vector3(0, 0.32, CZ), "metal", Color(0.05, 0.05, 0.05), false)
	_block(Vector3(3.4, 0.1, 2.8), Vector3(0, SHAFT_Y + 0.03, CZ))
	A.box(level, Vector3(3.3, 0.04, 0.74), Vector3(0, 1.1, 11.93), "rust", Color(0.5, 0.44, 0.38), true, 0.6, Vector3(0.52, 0, 0))
	A.box(level, Vector3(3.3, 0.04, 0.74), Vector3(0, 1.1, 14.07), "rust", Color(0.5, 0.44, 0.38), true, 0.6, Vector3(-0.52, 0, 0))
	for s in [-1.0, 1.0]:
		A.box(level, Vector3(0.5, 0.04, 2.0), Vector3(s * 1.5, 1.1, CZ), "rust", Color(0.5, 0.44, 0.38), true, 0.6, Vector3(0, 0, s * 0.76))
	# The hopper: a raked front plate up to the lip, cheek plates climbing to the back plate.
	var front := Node3D.new()
	level.add_child(front)
	front.position = Vector3(0, (1.3 + LIP_Y) / 2.0, (11.5 + LIP_Z) / 2.0)
	front.rotation.x = -atan2(11.5 - LIP_Z, LIP_Y - 1.3)
	var fh := Vector2(11.5 - LIP_Z, LIP_Y - 1.3).length()
	A.box(front, Vector3(3.72, fh, 0.06), Vector3.ZERO, "riveted", GREEN, true, 0.8)
	A.box(front, Vector3(3.5, 0.12, 0.01), Vector3(0, fh / 2.0 - 0.12, -0.036), "hazard", Color.WHITE, false, 0.5)
	for x in [-1.2, 0.0, 1.2]:
		A.box(front, Vector3(0.06, fh - 0.1, 0.06), Vector3(x, 0, -0.06), "metal", GREEN.darkened(0.15), false, 0.5)
	A.seg(level, Vector3(-1.86, LIP_Y, LIP_Z), Vector3(1.86, LIP_Y, LIP_Z), 0.05, 0.05, "metal", dark)   # the rolled lip
	for s in [-1.0, 1.0]:
		var x: float = s * 1.83
		_plate([Vector3(x, 1.3, 11.5), Vector3(x, 1.3, 14.56), Vector3(x, BACK_Y, 14.56), Vector3(x, LIP_Y, LIP_Z)], "riveted", GREEN)
		_plate([Vector3(x + s * 0.03, 1.3, 11.5), Vector3(x + s * 0.03, 1.3, 14.56), Vector3(x + s * 0.03, BACK_Y, 14.56), Vector3(x + s * 0.03, LIP_Y, LIP_Z)], "riveted", GREEN.darkened(0.1))
		A.seg(level, Vector3(s * 1.85, LIP_Y, LIP_Z), Vector3(s * 1.85, BACK_Y, 14.56), 0.045, 0.045, "metal", dark)
		A.seg(level, Vector3(s * 1.85, 1.3, 11.5), Vector3(s * 1.85, LIP_Y, LIP_Z), 0.035, 0.035, "metal", dark)
		for z in [12.2, 13.0, 13.8]:   # stiffeners up the cheeks
			var top := _cheek_top(z) - 0.06
			A.box(level, Vector3(0.06, top - 1.34, 0.08), Vector3(s * 1.89, (top + 1.34) / 2.0, z), "metal", GREEN.darkened(0.15), false, 0.5)
		_block(Vector3(0.12, 0.8, 3.4), Vector3(s * 1.83, 1.7, 12.85))
		_block(Vector3(0.12, 1.0, 1.6), Vector3(s * 1.83, 2.55, 13.75))
	A.box(level, Vector3(3.72, BACK_Y - 1.3, 0.08), Vector3(0, (BACK_Y + 1.3) / 2.0, 14.56), "riveted", GREEN, true, 0.8)
	for y in [2.15, 2.75]:
		A.box(level, Vector3(3.74, 0.07, 0.07), Vector3(0, y, 14.64), "metal", GREEN.darkened(0.15), false, 0.5)
	A.seg(level, Vector3(-1.86, BACK_Y, 14.56), Vector3(1.86, BACK_Y, 14.56), 0.045, 0.045, "metal", dark)
	A.box(level, Vector3(3.3, 0.9, 0.012), Vector3(0, 1.85, 14.512), "rust", Color(0.48, 0.42, 0.36), false, 0.6)   # the back plate's worn face
	# Rubber flap curtain hung inside the front (stops chips flying back out).
	A.seg(level, Vector3(-1.75, 1.82, 11.5), Vector3(1.75, 1.82, 11.5), 0.025, 0.025, "metal", STEEL)
	for i in 10:
		var flap := A.box(level, Vector3(0.33, 0.42, 0.015), Vector3(-1.5 + i * 0.335, 1.6, 11.53), "rubber", Color(0.3, 0.3, 0.3), false, 0.5)
		flap.rotation.x = 0.12 + (i % 3) * 0.05


## Two shafts of hooked cutter discs, interleaved, with stripper combs reaching in between them.
func _cutters() -> void:
	var disc_c := Color(0.6, 0.6, 0.58)
	var tooth_c := Color(0.82, 0.8, 0.74)
	for k in 2:
		var shaft := Node3D.new()
		level.add_child(shaft)
		shaft.position = Vector3(0, SHAFT_Y, CZ + (k - 0.5) * 0.5)
		A.cyl(shaft, 0.1, 3.5, Vector3.ZERO, "metal", Color(0.3, 0.3, 0.32), false, "x")
		for i in 10:
			var x := -1.38 + i * 0.29 + k * 0.145
			if absf(x) > 1.5:
				continue
			A.cyl(shaft, 0.27, 0.075, Vector3(x, 0, 0), "metal", disc_c.darkened(0.12 * (i % 2)), false, "x")
			A.cyl(shaft, 0.15, 0.075, Vector3(x + 0.145, 0, 0), "metal", Color(0.36, 0.36, 0.38), false, "x")   # spacer collar
			for t in 6:   # hooked teeth: a raked tooth with a hook at its tip
				var a := TAU * t / 6.0 + i * 0.9 + k * 0.4
				var hold := Node3D.new()
				shaft.add_child(hold)
				hold.position = Vector3(x, 0, 0)
				hold.rotation.x = a
				A.box(hold, Vector3(0.075, 0.12, 0.1), Vector3(0, 0.29, 0.02), "metal", tooth_c, false, 0.3, Vector3(0.45, 0, 0))
				A.box(hold, Vector3(0.075, 0.05, 0.07), Vector3(0, 0.345, -0.03), "metal", tooth_c.lightened(0.1), false, 0.3, Vector3(-0.5, 0, 0))
		shaft.set_meta("live", true)
		_shafts.append(shaft)
		# The stripper comb along the outside of this shaft: fingers between its discs.
		var side := -1.0 if k == 0 else 1.0
		var cz := CZ + side * 0.6
		A.box(level, Vector3(3.3, 0.1, 0.08), Vector3(0, SHAFT_Y + 0.08, cz), "metal", Color(0.45, 0.45, 0.43), false, 0.5)
		for i in 10:
			var gap := -1.38 + i * 0.29 + k * 0.145 + 0.145
			if absf(gap) < 1.5:
				A.box(level, Vector3(0.18, 0.08, 0.3), Vector3(gap, SHAFT_Y + 0.05, cz - side * 0.18), "metal", Color(0.38, 0.38, 0.36), false, 0.4)


## The drive: the gearbox behind the chamber, the motor lying on top of it on its stool, a V-belt
## down the side in a mesh guard; the dust duct from the hood out through the roof.
const MOTOR := Vector3(-0.35, 2.2, 15.45)

func _drive() -> void:
	var dark := GREEN.darkened(0.35)
	var motor_c := Color(0.34, 0.42, 0.5)
	# Gearbox: a ribbed riveted case, couplings into the chamber, breathers and an inspection cover on top.
	A.box(level, Vector3(3.0, 1.4, 1.4), Vector3(0, 0.94, 15.45), "riveted", GREEN, true, 0.9)
	A.box(level, Vector3(3.1, 0.08, 1.5), Vector3(0, 1.66, 15.45), "metal", dark, false, 0.6)
	A.box(level, Vector3(3.1, 0.08, 1.5), Vector3(0, 0.28, 15.45), "metal", dark, false, 0.6)
	_bolts(level, Vector3(-1.5, 1.71, 16.17), Vector3(1.5, 1.71, 16.17), 10, "y")
	for x in [-1.0, -0.33, 0.33, 1.0]:
		A.box(level, Vector3(0.07, 1.25, 0.06), Vector3(x, 0.94, 16.18), "metal", GREEN.darkened(0.15), false, 0.5)
	for x in [-0.6, 0.6]:
		A.cyl(level, 0.17, 0.2, Vector3(x, SHAFT_Y, 14.68), "metal", YELLOW, false, "z")   # coupling guards
		A.cyl(level, 0.19, 0.03, Vector3(x, SHAFT_Y, 14.75), "metal", dark, false, "z")
	A.box(level, Vector3(0.9, 0.03, 0.6), Vector3(0.85, 1.715, 15.45), "metal", GREEN.darkened(0.1), false, 0.5)   # inspection cover
	_bolts(level, Vector3(0.45, 1.74, 15.18), Vector3(1.25, 1.74, 15.18), 5, "y", 0.016)
	_bolts(level, Vector3(0.45, 1.74, 15.72), Vector3(1.25, 1.74, 15.72), 5, "y", 0.016)
	A.cyl(level, 0.055, 0.14, Vector3(1.35, 1.78, 15.85), "metal", Color(0.22, 0.22, 0.22))   # breather
	A.cyl(level, 0.07, 0.03, Vector3(1.51, 1.1, 15.2), "metal", Color(0.9, 0.55, 0.1), false, "x")   # oil sight glass
	A.ring(level, 0.085, 0.065, Vector3(1.515, 1.1, 15.2), "metal", Color(0.3, 0.3, 0.3), Vector3(0, 0, PI / 2))
	var plate := B.label(level, "B.R.M. RECLAMATION  /  MODEL 7  /  480 V", Vector3(0, 1.3, 16.165), 28, Color(0.92, 0.88, 0.75), "plate", 0.0045)
	A.box(level, Vector3(1.75, 0.16, 0.01), Vector3(0, 1.3, 16.158), "metal", Color(0.12, 0.12, 0.12), false, 0.5)
	plate.rotation.y = 0.0
	# The motor on its stool: a finned body, feet, the fan cowl and grille at its outer end, a
	# terminal box on top with its conduit, the shaft out to the small pulley.
	A.box(level, Vector3(1.7, 0.12, 0.8), Vector3(MOTOR.x, 1.76, MOTOR.z), "metal", Color(0.2, 0.2, 0.2), false, 0.5)
	for x in [-0.55, 0.55]:
		A.box(level, Vector3(0.18, 0.2, 0.7), Vector3(MOTOR.x + x, 1.9, MOTOR.z), "metal", motor_c.darkened(0.2), false, 0.4)
	A.cyl(level, 0.42, 1.3, MOTOR, "metal", motor_c, false, "x")
	for k in 10:
		A.ring(level, 0.48, 0.4, MOTOR + Vector3(-0.58 + k * 0.13, 0, 0), "metal", motor_c, Vector3(0, 0, PI / 2))
	A.cyl(level, 0.46, 0.28, MOTOR + Vector3(0.78, 0, 0), "metal", motor_c.darkened(0.2), false, "x")   # fan cowl
	for r in [0.12, 0.24, 0.36]:
		A.ring(level, r + 0.025, r, MOTOR + Vector3(0.93, 0, 0), "metal", Color(0.12, 0.12, 0.12), Vector3(0, 0, PI / 2))
	A.cyl(level, 0.46, 0.06, MOTOR + Vector3(-0.68, 0, 0), "metal", motor_c.darkened(0.15), false, "x")   # end shield
	A.box(level, Vector3(0.3, 0.2, 0.3), MOTOR + Vector3(0.1, 0.5, 0), "metal", motor_c.darkened(0.15), false, 0.4)   # terminal box
	A.pipe(level, MOTOR + Vector3(0.1, 0.6, 0.0), MOTOR + Vector3(0.1, 0.6, 0.75), 0.035, "metal", Color(0.5, 0.5, 0.5))
	A.pipe(level, MOTOR + Vector3(0.1, 0.6, 0.75), Vector3(MOTOR.x + 0.1, 0.06, MOTOR.z + 0.75), 0.035, "metal", Color(0.5, 0.5, 0.5))
	var name_p := B.label(level, "480V  3PH  110 kW", MOTOR + Vector3(-0.1, -0.1, -0.425), 18, Color(0.88, 0.86, 0.8), "plate", 0.0045)
	name_p.rotation.y = PI
	A.cyl(level, 0.06, 0.6, MOTOR + Vector3(-0.98, 0, 0), "metal", Color(0.5, 0.5, 0.5), false, "x")   # the shaft
	# V-belt drive down the side: a small pulley on the motor, a big spoked one on the gearbox's
	# input shaft, the belt's two runs between, all inside a yellow mesh guard.
	var px := -1.66
	var small := Node3D.new()
	level.add_child(small)
	small.position = Vector3(px, MOTOR.y, MOTOR.z)
	A.cyl(small, 0.13, 0.12, Vector3.ZERO, "metal", Color(0.3, 0.3, 0.3), false, "x")
	A.box(small, Vector3(0.13, 0.05, 0.27), Vector3.ZERO, "metal", Color(0.75, 0.2, 0.1), false, 0.3)   # (a mark you can see turn)
	var big := Node3D.new()
	level.add_child(big)
	big.position = Vector3(px, 0.98, MOTOR.z)
	A.ring(big, 0.38, 0.32, Vector3.ZERO, "metal", Color(0.3, 0.3, 0.3), Vector3(0, 0, PI / 2))
	A.cyl(big, 0.07, 0.14, Vector3.ZERO, "metal", Color(0.4, 0.4, 0.4), false, "x")
	for s in 5:
		var spoke := Node3D.new()
		big.add_child(spoke)
		spoke.rotation.x = TAU * s / 5.0
		A.box(spoke, Vector3(0.05, 0.27, 0.05), Vector3(0, 0.18, 0), "metal", Color(0.35, 0.35, 0.35), false, 0.3)
	for n in [small, big]:
		n.set_meta("live", true)
		_pulleys.append(n)
	A.cyl(level, 0.06, 0.2, Vector3(-1.56, 0.98, MOTOR.z), "metal", Color(0.45, 0.45, 0.45), false, "x")   # input shaft
	for s in [-1.0, 1.0]:   # the belt's two runs
		A.seg(level, Vector3(px, MOTOR.y, MOTOR.z + s * 0.13), Vector3(px, 0.98, MOTOR.z + s * 0.36), 0.025, 0.025, "rubber", Color(0.25, 0.25, 0.25))
	var gx := px - 0.12
	A.box(level, Vector3(0.02, 1.9, 1.0), Vector3(gx - 0.04, 1.58, MOTOR.z), "grate", YELLOW, false, 0.5)
	for z in [-0.5, 0.5]:
		A.box(level, Vector3(0.22, 1.9, 0.02), Vector3(px, 1.58, MOTOR.z + z), "grate", YELLOW, false, 0.5)
		A.box(level, Vector3(0.04, 1.92, 0.04), Vector3(gx - 0.04, 1.58, MOTOR.z + z), "metal", YELLOW.darkened(0.2), false, 0.5)
	A.box(level, Vector3(0.24, 0.03, 1.02), Vector3(px - 0.02, 2.53, MOTOR.z), "metal", YELLOW.darkened(0.2), false, 0.5)


## The dust hood over the back of the hopper, its duct out through the roof lantern, the sign on
## its brow, a caged lamp under it, the beacon and the klaxon on its roof.
func _gantry() -> void:
	var dark := GREEN.darkened(0.35)
	var hz0 := 13.45
	A.box(level, Vector3(3.8, 0.06, 14.62 - hz0), Vector3(0, BACK_Y + 0.42, (hz0 + 14.62) / 2.0), "riveted", GREEN, false, 0.8)
	A.box(level, Vector3(3.8, 0.5, 0.06), Vector3(0, BACK_Y + 0.17, hz0), "riveted", GREEN, false, 0.8)
	for s in [-1.0, 1.0]:
		A.box(level, Vector3(0.06, 0.5, 14.62 - hz0), Vector3(s * 1.87, BACK_Y + 0.17, (hz0 + 14.62) / 2.0), "riveted", GREEN, false, 0.8)
		A.seg(level, Vector3(s * 1.85, BACK_Y - 0.08, hz0), Vector3(s * 1.85, _cheek_top(hz0), hz0), 0.04, 0.04, "metal", dark)   # its legs down to the cheeks
	A.seg(level, Vector3(-1.9, BACK_Y - 0.08, hz0), Vector3(1.9, BACK_Y - 0.08, hz0), 0.035, 0.035, "metal", dark)
	# The sign: an enamel board on the hood's brow, cream with a red border.
	A.box(level, Vector3(2.7, 0.44, 0.03), Vector3(0, BACK_Y + 0.17, hz0 - 0.045), "metal", Color(0.2, 0.2, 0.2), false, 0.5)
	A.box(level, Vector3(2.6, 0.36, 0.012), Vector3(0, BACK_Y + 0.17, hz0 - 0.066), "cream", Color(0.72, 0.16, 0.1), false, 0.5)
	A.box(level, Vector3(2.48, 0.26, 0.008), Vector3(0, BACK_Y + 0.17, hz0 - 0.075), "cream", Color(0.88, 0.84, 0.72), false, 0.5)
	var sign := B.label(level, "SHREDDER", Vector3(0, BACK_Y + 0.17, hz0 - 0.081), 60, Color(0.62, 0.12, 0.08), "plate", 0.0042)
	sign.rotation.y = PI
	for x in [-1.25, 1.25]:
		A.sphere(level, 0.022, Vector3(x, BACK_Y + 0.17, hz0 - 0.07), "metal", Color(0.7, 0.7, 0.7))
	# A caged lamp under the brow, looking into the hopper.
	A.cyl(level, 0.1, 0.08, Vector3(0.9, BACK_Y - 0.12, hz0 + 0.12), "metal", Color(0.2, 0.2, 0.2))
	A.sphere(level, 0.06, Vector3(0.9, BACK_Y - 0.2, hz0 + 0.12), "cream", Color(1, 0.85, 0.6), 3.0)
	for k in 4:
		A.seg(level, Vector3(0.9, BACK_Y - 0.12, hz0 + 0.12), Vector3(0.9 + cos(k * TAU / 4.0) * 0.08, BACK_Y - 0.27, hz0 + 0.12 + sin(k * TAU / 4.0) * 0.08), 0.006, 0.006, "metal", Color(0.2, 0.2, 0.2))
	# The duct: up from the hood through the roof lantern, flanged joints, a damper, a rain cap.
	var dx := 0.6
	var dz := 14.05
	A.box(level, Vector3(0.8, 0.25, 0.8), Vector3(dx, BACK_Y + 0.56, dz), "metal", GREEN.darkened(0.1), false, 0.5)   # the transition
	A.pipe(level, Vector3(dx, BACK_Y + 0.65, dz), Vector3(dx, 11.6, dz), 0.28, "metal", Color(0.58, 0.58, 0.56))
	var y := BACK_Y + 1.4
	while y < 11.0:
		A.cyl(level, 0.33, 0.05, Vector3(dx, y, dz), "metal", Color(0.4, 0.4, 0.4))
		y += 1.8
	A.box(level, Vector3(0.12, 0.12, 0.72), Vector3(dx, BACK_Y + 1.1, dz), "metal", Color(0.3, 0.3, 0.3), false, 0.4)   # the damper's spindle
	A.box(level, Vector3(0.05, 0.25, 0.04), Vector3(dx, BACK_Y + 1.1, dz - 0.38), "metal", Color(0.8, 0.15, 0.08), false, 0.4)
	A.cyl(level, 0.5, 0.08, Vector3(dx, 11.95, dz), "metal", Color(0.4, 0.4, 0.4), false)
	for k in 3:
		A.seg(level, Vector3(dx + cos(k * TAU / 3.0) * 0.28, 11.6, dz + sin(k * TAU / 3.0) * 0.28), Vector3(dx + cos(k * TAU / 3.0) * 0.45, 11.92, dz + sin(k * TAU / 3.0) * 0.45), 0.02, 0.02, "metal", Color(0.4, 0.4, 0.4))
	# Rotating beacon on the hood's roof: an amber dome on a black base with a lamp turning inside.
	var bp := Vector3(-1.45, BACK_Y + 0.45, 14.2)
	A.cyl(level, 0.13, 0.1, bp + Vector3(0, 0.05, 0), "metal", Color(0.1, 0.1, 0.1))
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
	dome.position = bp + Vector3(0, 0.21, 0)
	dome.set_meta("live", true)
	_beacon = Node3D.new()
	level.add_child(_beacon)
	_beacon.position = bp + Vector3(0, 0.21, 0)
	_beacon.set_meta("live", true)
	_beacon_light = SpotLight3D.new()
	_beacon_light.light_color = Color(1.0, 0.55, 0.15)
	_beacon_light.spot_range = 16.0
	_beacon_light.spot_angle = 22.0
	_beacon_light.light_energy = 0.0
	_beacon.add_child(_beacon_light)
	_beacon_light.rotation.x = -0.35
	# The klaxon: a horn speaker on a bracket at the hood's other corner.
	A.box(level, Vector3(0.08, 0.3, 0.08), Vector3(1.55, BACK_Y + 0.6, 14.3), "metal", Color(0.25, 0.25, 0.25), false)
	A.seg(level, Vector3(1.55, BACK_Y + 0.75, 14.35), Vector3(1.55, BACK_Y + 0.7, 13.95), 0.05, 0.17, "metal", Color(0.3, 0.3, 0.3))


## The discharge conveyor: out of a chute in the chamber's flank, up over the head drum into the skip.
func _conveyor() -> void:
	var from := Vector3(2.15, 0.45, 14.05)
	var to := Vector3(4.75, 1.72, 16.05)
	_conv_len = from.distance_to(to)
	_conv = Node3D.new()
	level.add_child(_conv)
	_conv.position = from
	_conv.look_at_from_position(from, to, Vector3.UP)
	_conv.rotate_object_local(Vector3.UP, PI)   # (local +z up the belt)
	_conv.set_meta("live", true)
	var L := _conv_len
	var frame_c := GREEN.darkened(0.1)
	for s in [-1.0, 1.0]:
		A.box(_conv, Vector3(0.07, 0.22, L), Vector3(s * 0.43, -0.02, L / 2.0), "metal", frame_c, false, 0.6)   # channel sides
		A.box(_conv, Vector3(0.02, 0.13, L - 0.4), Vector3(s * 0.36, 0.08, L / 2.0 + 0.1), "rubber", Color(0.3, 0.3, 0.3), false, 0.5)   # skirt boards
		A.box(_conv, Vector3(0.02, 0.06, L - 0.4), Vector3(s * 0.39, 0.14, L / 2.0 + 0.1), "metal", frame_c.darkened(0.2), false, 0.5)
	A.box(_conv, Vector3(0.78, 0.03, L), Vector3(0, -0.02, L / 2.0), "rubber", Color(0.2, 0.2, 0.2), false, 0.5)   # the belt
	A.box(_conv, Vector3(0.78, 0.02, L), Vector3(0, -0.2, L / 2.0), "rubber", Color(0.18, 0.18, 0.18), false, 0.5)   # its return run
	for z in [0.0, L]:   # tail and head drums
		A.cyl(_conv, 0.11, 0.84, Vector3(0, -0.11, z), "metal", STEEL, false, "x")
		A.cyl(_conv, 0.05, 0.98, Vector3(0, -0.11, z), "metal", Color(0.3, 0.3, 0.3), false, "x")
	var k := 0.4
	while k < L - 0.2:
		A.cyl(_conv, 0.045, 0.82, Vector3(0, -0.075, k), "metal", Color(0.45, 0.45, 0.45), false, "x")
		k += 0.4
	for i in int(L / 0.3):   # cleats on the belt (they move)
		var c := A.box(_conv, Vector3(0.66, 0.035, 0.03), Vector3(0, 0.01, i * 0.3), "rubber", Color(0.12, 0.12, 0.12), false, 0.4)
		_cleats.append(c)
	A.box(_conv, Vector3(0.95, 0.42, 0.6), Vector3(0, 0.16, 0.15), "riveted", GREEN, false, 0.6)   # the hood over the tail
	A.box(_conv, Vector3(0.9, 0.04, 0.5), Vector3(0, 0.2, L - 0.05), "metal", frame_c, false, 0.5, Vector3(-0.4, 0, 0))   # the head's spill plate
	# The chute out of the chamber's flank down onto the tail.
	A.box(level, Vector3(0.36, 0.45, 0.7), Vector3(2.0, 0.6, 14.05), "riveted", GREEN, false, 0.6)
	_bolts(level, Vector3(1.92, 0.86, 13.72), Vector3(1.92, 0.86, 14.38), 5, "y", 0.016)
	# Legs: a trestle at each third, braced, on foot plates.
	for t in [0.33, 0.85]:
		var p := from.lerp(to, t)
		var side: Vector3 = _conv.global_basis.x * 0.43
		for s in [-1.0, 1.0]:
			A.seg(level, p + side * s - Vector3(0, 0.12, 0), Vector3(p.x, 0.06, p.z) + side * s, 0.035, 0.035, "metal", frame_c)
			A.box(level, Vector3(0.16, 0.02, 0.16), Vector3(p.x, 0.07, p.z) + side * s, "metal", frame_c.darkened(0.3), false)
		A.seg(level, p + side - Vector3(0, 0.12, 0), Vector3(p.x, 0.3, p.z) - side, 0.02, 0.02, "metal", frame_c)
		A.seg(level, p - side - Vector3(0, 0.12, 0), Vector3(p.x, 0.3, p.z) + side, 0.02, 0.02, "metal", frame_c)
	_skip()


## The skip the conveyor fills: a tapered roll-off skip on its skids, ribbed, with lifting lugs,
## heaped with shred (the belt's shreds land on the heap).
func _skip() -> void:
	var at := Vector3(5.2, 0.06, 16.3)
	var paint := Color(0.62, 0.32, 0.15)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7007
	for x in [-0.9, 0.9]:
		A.box(level, Vector3(0.12, 0.14, 2.5), at + Vector3(x, 0.07, 0), "metal", Color(0.2, 0.2, 0.2), false, 0.5)
	A.box(level, Vector3(2.3, 0.08, 1.9), at + Vector3(0, 0.18, 0), "rust", paint.darkened(0.3), true, 0.8)
	for s in [-1.0, 1.0]:
		A.box(level, Vector3(2.6, 0.95, 0.06), at + Vector3(0, 0.66, s * 1.05), "rust", paint, true, 0.8, Vector3(s * -0.2, 0, 0))   # raked ends
		A.box(level, Vector3(0.06, 0.95, 2.1), at + Vector3(s * 1.27, 0.66, 0), "rust", paint, true, 0.8)
		for z in [-0.6, 0.0, 0.6]:
			A.box(level, Vector3(0.06, 0.9, 0.07), at + Vector3(s * 1.31, 0.64, z), "rust", paint.darkened(0.2), false, 0.6)
		A.box(level, Vector3(0.08, 0.22, 0.2), at + Vector3(s * 1.34, 1.0, 0.85), "metal", Color(0.3, 0.3, 0.3), false, 0.4)   # lifting lugs
		A.box(level, Vector3(0.08, 0.22, 0.2), at + Vector3(s * 1.34, 1.0, -0.85), "metal", Color(0.3, 0.3, 0.3), false, 0.4)
		A.seg(level, at + Vector3(-1.3, 1.14, s * 1.15), at + Vector3(1.3, 1.14, s * 1.15), 0.035, 0.035, "rust", paint.darkened(0.25))
		A.seg(level, at + Vector3(s * 1.3, 1.14, -1.15), at + Vector3(s * 1.3, 1.14, 1.15), 0.035, 0.035, "rust", paint.darkened(0.25))
	var brm := B.label(level, "B.R.M.  SKIP 14", at + Vector3(1.345, 0.62, 0), 32, Color(0.92, 0.86, 0.66), "stencil", 0.0055)
	brm.rotation.y = PI / 2
	A.box(level, Vector3(2.4, 0.55, 2.0), at + Vector3(0, 0.62, 0), "rust", Color(0.32, 0.28, 0.24), false, 0.6)   # the heap
	for i in 22:
		var kinds := ["rust", "metal", "copper", "plastic", "rubber"]
		var kind: String = kinds[rng.randi() % kinds.size()]
		A.box(level, Vector3(rng.randf_range(0.06, 0.2), rng.randf_range(0.03, 0.08), rng.randf_range(0.06, 0.18)), at + Vector3(rng.randf_range(-1.1, 1.1), rng.randf_range(0.88, 0.97), rng.randf_range(-0.9, 0.9)),
			kind, Color.from_hsv(rng.randf(), 0.4, 0.75) if kind == "plastic" else Color.WHITE, false, 0.3, Vector3(rng.randf(), rng.randf() * 3.0, rng.randf()))


## The control desk by the hopper: a steel cabinet with a sloped desk (the ammeter, the pilot
## lamps, the emergency stop, the DIVERTER), the MAIN DRIVE lever on its own quadrant at the end
## nearest the machine, and a raised back with the readout in its hooded screen and a desk lamp.
const DESK := Vector3(3.25, 0.06, 11.0)

func _controls() -> void:
	var con := Node3D.new()
	con.name = "ControlDesk"
	level.add_child(con)
	con.position = DESK
	var dark := GREEN.darkened(0.35)
	var face := Color(0.24, 0.28, 0.26)
	# The cabinet: a kick plinth, riveted sides, two louvred doors with chrome handles.
	A.box(con, Vector3(1.44, 0.1, 0.6), Vector3(0, 0.05, 0.05), "metal", Color(0.12, 0.12, 0.12), false, 0.5)
	A.box(con, Vector3(1.4, 0.75, 0.56), Vector3(0, 0.475, 0.05), "riveted", GREEN, true, 0.8)
	for x in [-0.34, 0.34]:
		A.box(con, Vector3(0.62, 0.62, 0.02), Vector3(x, 0.48, -0.235), "metal", GREEN.lightened(0.05), false, 0.6)
		for r in 5:
			A.box(con, Vector3(0.38, 0.022, 0.025), Vector3(x, 0.32 + r * 0.06, -0.25), "metal", dark, false, 0.4)
		A.box(con, Vector3(0.025, 0.12, 0.03), Vector3(x + (0.24 if x < 0 else -0.24), 0.62, -0.255), "metal", Color(0.75, 0.75, 0.72), false, 0.2)
	B.label(con, "B.R.M.", Vector3(0, 0.78, -0.246), 22, Color(0.85, 0.8, 0.62), "stencil", 0.004).rotation.y = PI
	# The desk: sloped to whoever stands at it, chrome-edged, side cheeks under it.
	for s in [-1.0, 1.0]:
		_plate([Vector3(s * 0.7, 0.85, -0.23), Vector3(s * 0.7, 0.85, 0.33), Vector3(s * 0.7, 1.19, 0.33), Vector3(s * 0.7, 0.87, -0.27)], "metal", GREEN, con)
	A.box(con, Vector3(1.4, 0.36, 0.05), Vector3(0, 1.02, 0.31), "metal", GREEN, false, 0.6)
	var panel := Node3D.new()   # the sloped face (local +y out of it, -z towards whoever stands there)
	con.add_child(panel)
	panel.position = Vector3(0, 1.02, -0.02)
	panel.rotation.x = -0.5
	A.box(panel, Vector3(1.46, 0.04, 0.62), Vector3.ZERO, "metal", face, true, 0.4)
	A.seg(panel, Vector3(-0.73, 0.0, -0.31), Vector3(0.73, 0.0, -0.31), 0.018, 0.018, "metal", Color(0.75, 0.75, 0.72))
	# The ammeter: a chrome bezel, a cream face with a red zone, a needle that swings with the load.
	var am := Vector3(0.0, 0.02, 0.04)
	A.cyl(panel, 0.165, 0.035, am, "metal", Color(0.75, 0.75, 0.72))
	A.cyl(panel, 0.145, 0.02, am + Vector3(0, 0.012, 0), "cream", Color(0.92, 0.9, 0.82))
	for i in 9:
		var tick := Node3D.new()
		panel.add_child(tick)
		tick.position = am + Vector3(0, 0.024, 0)
		tick.rotation.y = -1.1 + i * 0.275
		A.box(tick, Vector3(0.007, 0.003, 0.03 if i % 2 == 0 else 0.018), Vector3(0, 0, -0.11), "metal", Color(0.85, 0.15, 0.1) if i >= 7 else Color(0.1, 0.1, 0.1), false)
	_needle = Node3D.new()
	panel.add_child(_needle)
	_needle.position = am + Vector3(0, 0.03, 0)
	_needle.set_meta("live", true)
	A.box(_needle, Vector3(0.006, 0.004, 0.125), Vector3(0, 0, -0.055), "metal", Color(0.05, 0.05, 0.05), false)
	A.cyl(_needle, 0.012, 0.008, Vector3.ZERO, "metal", Color(0.1, 0.1, 0.1))
	_needle.rotation.y = 1.1
	var amps := B.label(panel, "AMPS", am + Vector3(0, 0.025, 0.06), 16, Color(0.2, 0.2, 0.2), "plate", 0.003)
	amps.basis = FLAT
	# Pilot lamps on the right: POWER green, RUNNING amber, OVERLOAD red, in chrome bezels.
	var names := ["power", "run", "over"]
	var cols := [Color(0.2, 1, 0.3), Color(1, 0.65, 0.1), Color(1, 0.15, 0.1)]
	var words := ["POWER", "RUN", "OVERLOAD"]
	for i in 3:
		var lp := Vector3(-0.27 - i * 0.14, 0.02, 0.14)
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[i].darkened(0.5)
		m.emission_enabled = true
		m.emission = cols[i]
		m.emission_energy_multiplier = 2.5 if i == 0 else 0.0
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.03
		sm.height = 0.045
		lamp.mesh = sm
		lamp.material_override = m
		panel.add_child(lamp)
		lamp.position = lp + Vector3(0, 0.03, 0)
		lamp.set_meta("live", true)
		A.cyl(panel, 0.045, 0.03, lp, "metal", Color(0.75, 0.75, 0.72))
		var w := B.label(panel, words[i], lp + Vector3(0, 0.005, -0.07), 12, Color(0.92, 0.9, 0.84), "plate", 0.0028)
		w.basis = FLAT
		_lamps[names[i]] = m
	# Emergency stop: a red mushroom on a yellow collar (for show: the Bureau removed the wiring).
	var es := Vector3(-0.41, 0.02, -0.14)
	A.box(panel, Vector3(0.16, 0.04, 0.16), es, "plastic", Color(0.95, 0.8, 0.1), false, 0.3)
	A.cyl(panel, 0.03, 0.05, es + Vector3(0, 0.04, 0), "metal", Color(0.3, 0.3, 0.3))
	A.sphere(panel, 0.055, es + Vector3(0, 0.08, 0), "plastic", Color(0.8, 0.08, 0.06), 0.0, 0.6)
	var key := B.label(panel, "EMERGENCY STOP", es + Vector3(0, 0.003, -0.11), 12, Color(0.92, 0.9, 0.84), "plate", 0.0027)
	key.basis = FLAT
	_diverter(panel, Vector3(0.43, 0.02, 0.0))
	# The MAIN DRIVE lever on its own cast quadrant at the end nearest the machine: up (back) is
	# off; thrown down towards you, it runs.
	var box_at := Vector3(-0.8, 0.95, 0.0)
	A.box(con, Vector3(0.16, 0.42, 0.34), box_at, "metal", dark, false, 0.4)
	A.box(con, Vector3(0.17, 0.05, 0.35), box_at + Vector3(0, 0.23, 0), "metal", dark.darkened(0.2), false, 0.4)
	A.box(con, Vector3(0.14, 0.6, 0.2), Vector3(-0.78, 0.45, 0.0), "metal", dark, false, 0.4)   # its pedestal
	for i in 9:   # the ratchet quadrant's teeth, round the pivot
		var a := LEVER_REST - (LEVER_REST - LEVER_THROWN) * i / 8.0
		A.box(con, Vector3(0.03, 0.035, 0.035), box_at + Vector3(-0.1, 0.0, 0.0) + Vector3(0, cos(a), sin(a)) * 0.21, "metal", Color(0.6, 0.6, 0.56), false, 0.3, Vector3(a, 0, 0))
	A.box(con, Vector3(0.006, 0.07, 0.3), box_at + Vector3(-0.083, -0.1, 0), "brass", Color(0.85, 0.7, 0.4), false, 0.3)
	var lbl := B.label(con, "MAIN DRIVE", box_at + Vector3(-0.087, -0.1, 0), 16, Color(0.15, 0.12, 0.08), "plate", 0.0036)
	lbl.rotation.y = -PI / 2
	_lever = Node3D.new()
	con.add_child(_lever)
	_lever.position = box_at + Vector3(-0.13, 0, 0)
	_lever.rotation.x = LEVER_REST
	_lever.set_meta("live", true)
	A.cyl(_lever, 0.05, 0.06, Vector3.ZERO, "metal", Color(0.3, 0.3, 0.3), false, "x")   # pivot boss
	var grip := B.interactable(_lever, Vector3(0.12, 0.95, 0.12), Vector3(0, 0.45, 0), Color(0, 0, 0, 0), "Throw MAIN DRIVE: shred & submit", Callable(), 0.0, 0.0)
	A.box(_lever, Vector3(0.045, 0.85, 0.045), Vector3(0, 0.42, 0), "metal", Color(0.62, 0.62, 0.6), false, 0.4)
	A.cyl(_lever, 0.035, 0.18, Vector3(0, 0.78, 0), "rubber", Color(0.25, 0.25, 0.25))   # the grip
	A.sphere(_lever, 0.07, Vector3(0, 0.9, 0), "plastic", Color(0.85, 0.08, 0.06))
	A.box(_lever, Vector3(0.06, 0.12, 0.06), Vector3(0, 0.12, 0), "metal", Color(0.25, 0.25, 0.25), false, 0.3)   # the pawl housing
	grip.action = func(): main.shred()
	# The raised back: the readout in a hooded screen, a plate over it, a desk lamp on an arm.
	A.box(con, Vector3(1.4, 1.25, 0.22), Vector3(0, 1.82, 0.42), "riveted", GREEN, true, 0.8)
	A.box(con, Vector3(1.46, 0.06, 0.28), Vector3(0, 2.47, 0.42), "metal", dark, false, 0.5)
	B.box(con, Vector3(1.2, 0.74, 0.03), Vector3(0, 1.84, 0.3), Color(0.07, 0.045, 0.015), false, 0.35)   # the screen, faintly lit
	for b in [[Vector3(1.3, 0.06, 0.07), Vector3(0, 2.24, 0.28)], [Vector3(1.3, 0.06, 0.07), Vector3(0, 1.44, 0.28)], [Vector3(0.06, 0.86, 0.07), Vector3(-0.63, 1.84, 0.28)], [Vector3(0.06, 0.86, 0.07), Vector3(0.63, 1.84, 0.28)]]:
		A.box(con, b[0], b[1], "metal", Color(0.14, 0.15, 0.14), false, 0.4)   # the bezel
	A.box(con, Vector3(1.36, 0.035, 0.24), Vector3(0, 2.29, 0.17), "metal", dark, false, 0.5)   # its hood
	for x in [-0.665, 0.665]:
		A.box(con, Vector3(0.035, 0.12, 0.24), Vector3(x, 2.23, 0.17), "metal", dark, false, 0.5)
	_bolts(con, Vector3(-0.6, 1.32, 0.305), Vector3(0.6, 1.32, 0.305), 6, "z", 0.014)
	board = B.display(con, "", Vector3(0, 1.84, 0.28), 27, Color(1, 0.72, 0.3))
	board.rotation.y = PI
	board.pixel_size = 0.0019
	board.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS   # (drawn in depth order: never through the machine)
	B.omni(con, Vector3(0, 1.84, 0.0), Color(1, 0.7, 0.35), 0.22, 1.5)
	A.box(con, Vector3(0.9, 0.09, 0.01), Vector3(0, 2.38, 0.305), "brass", Color(0.85, 0.7, 0.4), false, 0.3)
	B.label(con, "RECLAMATION CONTROL  ·  No.7", Vector3(0, 2.38, 0.298), 16, Color(0.15, 0.12, 0.08), "plate", 0.0034).rotation.y = PI
	A.seg(con, Vector3(0.5, 2.5, 0.45), Vector3(0.5, 2.62, 0.1), 0.018, 0.018, "metal", Color(0.2, 0.2, 0.2))   # the lamp's arm
	A.seg(con, Vector3(0.5, 2.62, 0.1), Vector3(0.5, 2.5, -0.12), 0.018, 0.018, "metal", Color(0.2, 0.2, 0.2))
	A.cyl(con, 0.11, 0.1, Vector3(0.5, 2.46, -0.14), "metal", GREEN.darkened(0.1), false, "y", 0.03)
	A.sphere(con, 0.04, Vector3(0.5, 2.41, -0.14), "cream", Color(1, 0.88, 0.65), 3.0)
	B.omni(con, Vector3(0.5, 2.3, -0.2), Color(1, 0.85, 0.62), 0.6, 2.2)
	# The cable down the back into a trench cover across to the machine.
	A.pipe(con, Vector3(-0.4, 2.0, 0.54), Vector3(-0.4, 0.0, 0.54), 0.04, "metal", Color(0.45, 0.45, 0.45))
	A.box(level, Vector3(1.0, 0.012, 0.3), Vector3(2.35, 0.066, 11.55), "metal", Color(0.35, 0.35, 0.33), false, 0.5)
	A.box(level, Vector3(0.3, 0.012, 0.32), DESK + Vector3(-0.4, 0.006, 0.55), "metal", Color(0.35, 0.35, 0.33), false, 0.5)


## The DIVERTER on the desk: a brass escutcheon with a cream dial, a yellow cam-switch handle
## turning between SELL (left, green lamp: everything goes to the Bureau's buyers) and BANK
## (right, amber lamp: whatever's past the quota goes into the bonded stock).
func _diverter(panel: Node3D, at: Vector3) -> void:
	A.box(panel, Vector3(0.3, 0.012, 0.4), at + Vector3(0, 0, -0.03), "brass", Color(0.85, 0.7, 0.4), false, 0.3)
	A.cyl(panel, 0.11, 0.008, at + Vector3(0, 0.008, 0), "cream", Color(0.92, 0.88, 0.76))
	for i in 7:   # its scale, from SELL round to BANK
		var tick := Node3D.new()
		panel.add_child(tick)
		tick.position = at + Vector3(0, 0.013, 0)
		tick.rotation.y = 0.75 - 1.5 * i / 6.0
		A.box(tick, Vector3(0.005, 0.003, 0.022), Vector3(0, 0, 0.088), "metal", Color(0.12, 0.1, 0.08), false, 0.2)
	for s in [1.0, -1.0]:   # (+x is on the left of whoever stands at it)
		var word: String = "SELL" if s > 0.0 else "BANK"
		var col := Color(0.25, 1.0, 0.35) if s > 0.0 else Color(1.0, 0.62, 0.12)
		var w := B.label(panel, word, at + Vector3(s * 0.075, 0.0075, -0.185), 13, Color(0.15, 0.12, 0.08), "plate", 0.0028)
		w.basis = FLAT
		var m := StandardMaterial3D.new()
		m.albedo_color = col.darkened(0.55)
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.0
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.022
		sm.height = 0.032
		lamp.mesh = sm
		lamp.material_override = m
		panel.add_child(lamp)
		lamp.position = at + Vector3(s * 0.075, 0.03, -0.14)
		lamp.set_meta("live", true)
		A.cyl(panel, 0.03, 0.02, at + Vector3(s * 0.075, 0.012, -0.14), "metal", Color(0.75, 0.75, 0.72))
		_lamps[word] = m
	var plate := B.label(panel, "DIVERTER", at + Vector3(0, 0.0075, 0.14), 13, Color(0.15, 0.12, 0.08), "plate", 0.0028)
	plate.basis = FLAT
	_dial = Node3D.new()
	panel.add_child(_dial)
	_dial.position = at + Vector3(0, 0.012, 0)
	_dial.set_meta("live", true)
	A.cyl(_dial, 0.04, 0.03, Vector3(0, 0.015, 0), "metal", Color(0.25, 0.25, 0.25))   # the boss
	A.box(_dial, Vector3(0.045, 0.05, 0.16), Vector3(0, 0.05, 0.02), "plastic", Color(0.95, 0.72, 0.1), false, 0.3)   # the handle
	A.box(_dial, Vector3(0.012, 0.004, 0.06), Vector3(0, 0.077, 0.06), "metal", Color(0.08, 0.08, 0.08), false)   # the pointer line
	var it := B.interactable(panel, Vector3(0.3, 0.14, 0.3), at + Vector3(0, 0.06, 0), Color(0, 0, 0, 0), "Turn the DIVERTER: sell or bank the surplus", Callable(), 0.0, 0.0)
	it.action = func(): main.toggle_divert()
	set_divert(main.divert_bank, true)


## The diverter's handle and lamps follow where it's turned (everyone's, from the state).
func set_divert(bank: bool, instant := false) -> void:
	if _dial == null:
		return
	var a := -0.75 if bank else 0.75
	_lamps.SELL.emission_energy_multiplier = 0.0 if bank else 3.0
	_lamps.BANK.emission_energy_multiplier = 3.0 if bank else 0.0
	if instant:
		_dial.rotation.y = a
		return
	var tw := _dial.create_tween()
	tw.tween_property(_dial, "rotation:y", a, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play(level, "clunk", _dial.global_position, -6.0, 1.6)


func _fx() -> void:
	_sparks = _particles(70, 0.9, Vector3(0, 1, 0), 55.0, 2.5, 6.5, -12.0, Vector3(0.025, 0.025, 0.07), B.mat(Color(1, 0.6, 0.2), 6.0))
	_dust = _particles(40, 1.6, Vector3(0, 1, 0), 40.0, 0.6, 1.8, -1.0, Vector3(0.09, 0.09, 0.09), B.mat(Color(0.45, 0.42, 0.38)))
	for p in [_sparks, _dust]:
		level.add_child(p)
		p.position = NIP + Vector3(0, -0.15, 0)
	_motor = _loop_player("shred_motor", Vector3(0, 1.0, 14.6), 9.0)
	_belt_snd = _loop_player("conveyor", Vector3(3.3, 1.0, 14.4), 4.0)
	B.omni(level, Vector3(0.9, 2.75, 13.6), Color(1, 0.8, 0.55), 1.0, 5.0)   # (the caged lamp under the hood)


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
	await _wait(1.0 * pace)
	_got = {}
	_total = 0.0
	_count = 0
	_busy = 0
	# The cutters take several at once along their length: a new one is dragged in every 0.2 s
	# (a heavy one jams them first and gets a moment to itself).
	for p in items:
		if not is_instance_valid(p):
			continue
		var heavy := Data.is_heavy(p.id)
		if heavy:
			while _busy > 0:   # (clear the throat first)
				await get_tree().physics_frame
		_chew(p)
		await _wait((1.0 if heavy else 0.2) * pace)
	while _busy > 0:
		await get_tree().physics_frame
	await _wait(0.4 * pace)
	_say(["stop"])
	await _wait(1.2 * pace)
	running = false
	main.shred_done(_count, _got, _total)


var _got := {}
var _total := 0.0
var _count := 0
var _busy := 0   # items going through the cutters right now


## One item: dragged down into the nip, (a heavy one jams the cutters first), shudders and sinks
## into the teeth, paid for.
func _chew(p: Node3D) -> void:
	_busy += 1
	var pace := Data.pace()
	var id: String = p.id
	var res: Dictionary = Data.ITEMS[id].res
	var metal: int = res.get("steel", 0) + res.get("copper", 0)
	var hard: bool = metal > res.get("plastic", 0) + res.get("rubber", 0)
	var heavy := Data.is_heavy(id)
	var nip := NIP + Vector3(clampf(p.global_position.x - level.global_position.x, -0.9, 0.9), 0, randf_range(-0.08, 0.08))
	var tw: Tween = p.create_tween().set_parallel()
	tw.tween_property(p, "global_position", level.to_global(nip), 0.3 * pace).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "rotation", p.rotation + Vector3(randf_range(-1, 1), randf_range(-2, 2), randf_range(-1, 1)), 0.3 * pace)
	await _wait(0.3 * pace)
	if heavy:   # too much for it in one bite: the cutters stall, back off, and go at it again
		_say(["jam"])
		await _wait(1.0 * pace)
	var dur: float = (0.45 + minf(p.mass, 12.0) * 0.03) * (1.5 if heavy else 1.0)
	_say(["chew", hard, dur, Data.color(id), _size(p)])
	var t := 0.0
	var top: Vector3 = p.global_position if is_instance_valid(p) else Vector3.ZERO
	while t < dur * pace and is_instance_valid(p):   # it shudders, and sinks into the teeth
		var k := t / (dur * pace)
		p.global_position = top + Vector3(randf_range(-0.04, 0.04), -0.75 * k, randf_range(-0.03, 0.03))
		p.rotation += Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.1), randf_range(-0.2, 0.2))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	if is_instance_valid(p):
		p.queue_free()
	_total += main.shred_item(id)
	run_pay = roundi(_total)
	for r in res:
		_got[r] = _got.get(r, 0) + res[r]
	_count += 1
	_say(["paid", run_pay])
	_busy -= 1


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
			Sfx.play(level, "power_up", level.to_global(MOTOR), -2.0, 0.6)
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
			Sfx.play(level, "power_down", level.to_global(MOTOR), -4.0, 0.7)
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
	if running and absf(_speed) > 0.3 and _hurt_t <= 0.0 and main.net.authority():   # (the host hurts everyone in it)
		for p in main.players():
			var local: Vector3 = level.to_local(p.global_position)
			if not p.dead and absf(local.x) < 1.45 and absf(local.z - CZ) < 1.45 and local.y < 1.6:
				_hurt_t = 0.8
				p.hurt(30.0, "The shredder. The Bureau did ask.")
				var fling := level.global_basis * Vector3(0, 7.5, -4.0)
				if p == main.player:
					p.velocity = fling
					main.hud.alert("KEEP HANDS CLEAR")
				else:   # thrown clear on their own machine
					main.net.to_owner(p.peer, "fling", fling)
					main.net.to_owner(p.peer, "alert", "KEEP HANDS CLEAR")
				Sfx.play(level, "shred_soft", p.global_position, 4.0, 0.7)
