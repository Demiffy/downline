# The employee, as everyone else sees them: worn orange coverall with reflective tape, zip and
# patch pockets, kneepads, a tool belt with pouches and a holstered torch, harness straps with a
# chest radio, a pack with a bedroll, leather gloves with fingers, laced work boots, and a helmet
# with a smoked visor and headlamp.
# Built as eleven parts, each in its own frame with its pivot at the joint it hangs from, so the
# same parts make the standing figure (photos, security feeds), the ragdoll (ragdoll.gd) and the
# body you carry. PARTS gives every part's joint position in the standing pose.
extends RefCounted

const A = preload("res://src/art.gd")
const Cracks = preload("res://src/cracks.gd")

const SUIT := Color(1, 1, 1)                 # the "fabric" texture is the orange suit
const DARK := Color(0.72, 0.68, 0.66)        # shadowed fabric: seams, cuffs, collar
const TAPE := Color(0.86, 0.87, 0.82)
const HELMET := Color(0.86, 0.8, 0.55)
const CANVAS := Color(0.47, 0.47, 0.38)
const STEEL := Color(0.5, 0.5, 0.5)

const UPPER_ARM := 0.29
const FOREARM := 0.26
const THIGH := 0.42
const SHIN := 0.43

## part -> [parent, joint position in the standing pose (relative to the feet, facing -z)]
const PARTS := {
	"pelvis": ["", Vector3(0, 0.96, 0)],
	"torso": ["pelvis", Vector3(0, 1.06, 0)],
	"head": ["torso", Vector3(0, 1.51, 0)],
	"upper_arm_l": ["torso", Vector3(-0.215, 1.44, 0.0)],
	"upper_arm_r": ["torso", Vector3(0.215, 1.44, 0.0)],
	"forearm_l": ["upper_arm_l", Vector3(-0.235, 1.15, 0.0)],
	"forearm_r": ["upper_arm_r", Vector3(0.235, 1.15, 0.0)],
	"thigh_l": ["pelvis", Vector3(-0.1, 0.94, 0)],
	"thigh_r": ["pelvis", Vector3(0.1, 0.94, 0)],
	"shin_l": ["thigh_l", Vector3(-0.1, 0.52, 0)],
	"shin_r": ["thigh_r", Vector3(0.1, 0.52, 0)],
}


## Build one part into `n` (its own frame: pivot at the origin, limbs hanging along -y).
static func part(n: Node3D, name: String) -> void:
	var side := -1.0 if name.ends_with("_l") else 1.0
	match name.trim_suffix("_l").trim_suffix("_r"):
		"pelvis": _pelvis(n)
		"torso": _torso(n)
		"head": _head(n)
		"upper_arm": _upper_arm(n, side)
		"forearm": _forearm(n, side)
		"thigh": _thigh(n, side)
		"shin": _shin(n, side)


## The whole figure standing, built under `root` (feet on its origin, facing -z). Returns the
## part nodes by name so a caller can pose them.
static func standing(root: Node3D) -> Dictionary:
	var nodes := {}
	for name in PARTS:
		var n := Node3D.new()
		var parent: String = PARTS[name][0]
		var host: Node3D = root if parent == "" else nodes[parent]
		host.add_child(n)
		var at: Vector3 = PARTS[name][1]
		n.position = at - (Vector3.ZERO if parent == "" else PARTS[parent][1])
		part(n, name)
		nodes[name] = n
	# A natural stance: arms hanging a touch out and bent, one knee easy.
	nodes.upper_arm_l.rotation = Vector3(0.06, 0, -0.1)
	nodes.upper_arm_r.rotation = Vector3(0.06, 0, 0.1)
	nodes.forearm_l.rotation = Vector3(0.28, 0, 0.05)
	nodes.forearm_r.rotation = Vector3(0.28, 0, -0.05)
	nodes.thigh_r.rotation = Vector3(0.06, 0, 0.02)
	nodes.shin_r.rotation = Vector3(-0.1, 0, 0)
	return nodes


## Limp, lying on its back (the body you carry): feet toward +z, face up.
static func limp(root: Node3D) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	holder.rotation.x = -PI / 2.0
	holder.position = Vector3(0, -0.12, -0.92)
	var nodes := standing(holder)
	nodes.head.rotation = Vector3(0.25, 0.5, 0.2)
	nodes.upper_arm_l.rotation = Vector3(0.1, 0, -0.35)
	nodes.upper_arm_r.rotation = Vector3(-0.2, 0, 0.25)
	nodes.forearm_l.rotation = Vector3(0.6, 0, 0)
	nodes.forearm_r.rotation = Vector3(0.2, 0, 0)
	nodes.thigh_l.rotation = Vector3(0.1, 0, -0.08)
	nodes.thigh_r.rotation = Vector3(0.35, 0, 0.1)
	nodes.shin_r.rotation = Vector3(-0.5, 0, 0)


## Over the shoulder (a fireman's carry), built under `root` with its hips on root's origin: belly
## down across the shoulder, head and arms hanging down the carrier's back (+z), legs down the
## front (-z). Root it at the carrier's right shoulder.
static func carried(root: Node3D) -> Node3D:
	var holder := Node3D.new()
	root.add_child(holder)
	holder.basis = Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))   # its up runs back, its front faces down
	holder.position = holder.basis * -PARTS.pelvis[1]
	var nodes := standing(holder)
	nodes.torso.rotation = Vector3(-1.25, 0.12, 0.08)       # folded down the back
	nodes.head.rotation = Vector3(-0.35, 0.3, 0.15)
	nodes.upper_arm_l.rotation = Vector3(1.15, 0, -0.2)      # arms dangling
	nodes.upper_arm_r.rotation = Vector3(1.3, 0, 0.25)
	nodes.forearm_l.rotation = Vector3(0.3, 0, 0)
	nodes.forearm_r.rotation = Vector3(0.15, 0, 0)
	nodes.thigh_l.rotation = Vector3(1.25, 0, -0.06)         # legs down the front, knees easy
	nodes.thigh_r.rotation = Vector3(1.15, 0, 0.08)
	nodes.shin_l.rotation = Vector3(-0.25, 0, 0)
	nodes.shin_r.rotation = Vector3(-0.4, 0, 0)
	return holder


## Crack the visor of a suit built under `root` (0 = whole again).
static func set_cracks(root: Node, tier: int) -> void:
	var crack := root.find_child("VisorCracks", true, false) as MeshInstance3D
	if crack == null:
		return
	crack.visible = tier > 0
	if tier <= 0:
		return
	var m := StandardMaterial3D.new()   # projected straight on from the front: cracks across the glass
	m.albedo_texture = Cracks.texture(tier, 256)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 3.6
	m.uv1_offset = Vector3(0.5, 0.5, 0.0)
	m.roughness = 0.2
	m.emission_enabled = true   # (the light catches the edges)
	m.emission = Color(0.25, 0.27, 0.3)
	crack.material_override = m


# --- parts ------------------------------------------------------------------------------------

## A tapered limb or trunk section with an oval cross-section (`depth` squashes it front to back).
static func _oval(n: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, depth: float, kind: String, tint := Color.WHITE) -> Node3D:
	var holder := Node3D.new()
	n.add_child(holder)
	holder.scale = Vector3(1, 1, depth)
	A.seg(holder, a, b, r0, r1, kind, tint)
	return holder


## A band round an oval section (tape, belts, cuffs).
static func _band(n: Node3D, y: float, r: float, h: float, depth: float, kind: String, tint := Color.WHITE) -> void:
	var holder := Node3D.new()
	n.add_child(holder)
	holder.scale = Vector3(1, 1, depth)
	A.cyl(holder, r, h, Vector3(0, y, 0), kind, tint)


static func _pelvis(n: Node3D) -> void:
	_oval(n, Vector3(0, -0.12, 0), Vector3(0, 0.11, 0), 0.148, 0.143, 0.72, "fabric", SUIT)
	A.sphere(n, 0.1, Vector3(0, -0.11, 0.0), "fabric", DARK, 0.0, 0.7)                 # crotch
	_band(n, 0.085, 0.151, 0.05, 0.73, "leather")                                         # belt
	A.box(n, Vector3(0.058, 0.042, 0.012), Vector3(0, 0.085, -0.111), "metal", STEEL, false, 0.2)   # buckle
	A.box(n, Vector3(0.028, 0.02, 0.014), Vector3(0, 0.085, -0.114), "leather", Color.WHITE, false, 0.2)
	for s in [-1.0, 1.0]:
		A.box(n, Vector3(0.05, 0.1, 0.085), Vector3(s * 0.165, 0.03, -0.03), "canvas", CANVAS, false, 0.3)   # pouch
		A.box(n, Vector3(0.055, 0.032, 0.09), Vector3(s * 0.166, 0.082, -0.03), "canvas", CANVAS.darkened(0.15), false, 0.3)   # flap
		A.box(n, Vector3(0.008, 0.015, 0.012), Vector3(s * 0.192, 0.068, -0.03), "metal", STEEL, false, 0.2)   # snap
	# Holstered torch on the right hip, a hammer loop on the left.
	A.cyl(n, 0.02, 0.17, Vector3(0.155, -0.02, 0.075), "plastic", Color(0.95, 0.75, 0.15))
	A.cyl(n, 0.026, 0.035, Vector3(0.155, 0.075, 0.075), "plastic", Color(0.95, 0.75, 0.15))
	A.box(n, Vector3(0.05, 0.06, 0.05), Vector3(0.155, 0.02, 0.075), "leather", Color.WHITE, false, 0.2)
	A.ring(n, 0.028, 0.02, Vector3(-0.155, 0.05, 0.085), "metal", STEEL, Vector3(0, 0, PI / 2.0))


static func _torso(n: Node3D) -> void:
	_oval(n, Vector3(0, -0.01, 0), Vector3(0, 0.2, 0), 0.138, 0.152, 0.7, "fabric", SUIT)     # waist
	_oval(n, Vector3(0, 0.16, 0), Vector3(0, 0.42, 0), 0.155, 0.19, 0.62, "fabric", SUIT)     # chest, broadening to the shoulders
	var yoke := A.sphere(n, 0.19, Vector3(0, 0.415, 0), "fabric", SUIT, 0.0, 0.42)           # rounded over the shoulders
	yoke.scale = Vector3(1, 1, 0.62)
	for s in [-1.0, 1.0]:
		A.sphere(n, 0.072, Vector3(s * 0.19, 0.39, 0), "fabric", SUIT)                          # shoulder caps
		A.box(n, Vector3(0.085, 0.085, 0.012), Vector3(s * 0.085, 0.31, -0.112), "fabric", DARK, false, 0.3, Vector3(0, s * 0.15, 0))   # chest pockets
		A.box(n, Vector3(0.089, 0.028, 0.016), Vector3(s * 0.085, 0.35, -0.115), "fabric", SUIT, false, 0.3, Vector3(0, s * 0.15, 0))   # flaps
		A.box(n, Vector3(0.04, 0.44, 0.014), Vector3(s * 0.08, 0.24, -0.118), "canvas", CANVAS, false, 0.3, Vector3(0.06, 0, 0))   # harness straps
		A.box(n, Vector3(0.04, 0.3, 0.014), Vector3(s * 0.08, 0.3, 0.118), "canvas", CANVAS, false, 0.3, Vector3(-0.06, 0, 0))
		A.box(n, Vector3(0.048, 0.028, 0.02), Vector3(s * 0.08, 0.14, -0.123), "metal", STEEL, false, 0.2)   # strap buckles
	_band(n, 0.2, 0.166, 0.04, 0.635, "plastic", TAPE)                                      # reflective bands
	_band(n, 0.06, 0.142, 0.035, 0.71, "plastic", TAPE)
	A.box(n, Vector3(0.012, 0.34, 0.006), Vector3(0, 0.22, -0.11), "metal", STEEL.darkened(0.3), false, 0.2, Vector3(0.08, 0, 0))   # zip
	A.box(n, Vector3(0.012, 0.022, 0.012), Vector3(0, 0.385, -0.118), "metal", STEEL, false, 0.2)   # zip pull
	A.box(n, Vector3(0.16, 0.016, 0.018), Vector3(0, 0.23, -0.127), "canvas", CANVAS, false, 0.3)   # chest strap
	A.box(n, Vector3(0.068, 0.032, 0.008), Vector3(0.085, 0.395, -0.112), "paper", Color(0.9, 0.88, 0.8), false, 0.2, Vector3(-0.3, 0.15, 0))   # name tape
	# Chest radio clipped to the left strap.
	A.box(n, Vector3(0.055, 0.085, 0.03), Vector3(-0.08, 0.33, -0.142), "rubber", Color.WHITE, false, 0.2)
	A.seg(n, Vector3(-0.095, 0.37, -0.142), Vector3(-0.105, 0.47, -0.137), 0.004, 0.003, "rubber")
	A.sphere(n, 0.006, Vector3(-0.065, 0.355, -0.158), "metal", Color(0.9, 0.2, 0.1), 2.0)
	# Collar, folded open.
	A.cyl(n, 0.078, 0.06, Vector3(0, 0.465, 0.005), "fabric", DARK, false, "y", 0.072)
	for s in [-1.0, 1.0]:
		A.box(n, Vector3(0.065, 0.05, 0.01), Vector3(s * 0.048, 0.45, -0.07), "fabric", SUIT, false, 0.3, Vector3(-0.4, s * 0.45, 0))
	# Pack: body, lid, side pockets, bedroll on top.
	A.box(n, Vector3(0.29, 0.35, 0.14), Vector3(0, 0.27, 0.185), "canvas", CANVAS, false, 0.4)
	A.box(n, Vector3(0.3, 0.08, 0.15), Vector3(0, 0.44, 0.19), "canvas", CANVAS.darkened(0.12), false, 0.4, Vector3(0.12, 0, 0))
	for s in [-1.0, 1.0]:
		A.box(n, Vector3(0.05, 0.15, 0.095), Vector3(s * 0.165, 0.2, 0.185), "canvas", CANVAS.darkened(0.08), false, 0.3)
		A.box(n, Vector3(0.02, 0.2, 0.012), Vector3(s * 0.07, 0.27, 0.258), "leather", Color.WHITE, false, 0.2)   # lid straps
	A.cyl(n, 0.058, 0.33, Vector3(0, 0.505, 0.195), "canvas", Color(0.42, 0.3, 0.25), false, "x")
	for s in [-1.0, 1.0]:
		A.cyl(n, 0.06, 0.018, Vector3(s * 0.1, 0.505, 0.195), "leather", Color.WHITE, false, "x")


static func _head(n: Node3D) -> void:
	A.cyl(n, 0.07, 0.07, Vector3(0, 0.035, 0.005), "rubber", Color.WHITE, false, "y", 0.085)   # neck seal
	var shell := A.sphere(n, 0.152, Vector3(0, 0.175, 0.012), "plastic", HELMET)              # shell, a touch long front to back
	shell.scale = Vector3(1.0, 1.02, 1.08)
	A.ring(n, 0.155, 0.143, Vector3(0, 0.1, 0.012), "rubber", Color.WHITE)                    # rim seal
	var crest := A.box(n, Vector3(0.03, 0.022, 0.24), Vector3(0, 0.322, 0.02), "plastic", HELMET.darkened(0.08), false, 0.2)   # moulded crest
	crest.rotation.x = 0.05
	var brow := A.sphere(n, 0.15, Vector3(0, 0.235, -0.05), "plastic", HELMET.darkened(0.04), 0.0, 0.32)   # brow over the visor
	brow.scale = Vector3(1.0, 1.0, 0.75)
	_band(n, 0.205, 0.1545, 0.03, 1.08, "hazard", Color(0.95, 0.9, 0.85))                   # hazard band round the shell
	for s in [-1.0, 1.0]:
		A.cyl(n, 0.044, 0.028, Vector3(s * 0.153, 0.165, 0.015), "rubber", Color.WHITE, false, "x")    # ear cups
		A.cyl(n, 0.016, 0.032, Vector3(s * 0.161, 0.165, 0.015), "metal", STEEL, false, "x")
	# Smoked visor, framed along its edge.
	var visor := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.135
	sm.height = 0.2
	visor.mesh = sm
	var vm := StandardMaterial3D.new()
	vm.albedo_color = Color(0.05, 0.07, 0.09)
	vm.metallic = 0.75
	vm.roughness = 0.08
	visor.material_override = vm
	n.add_child(visor)
	visor.position = Vector3(0, 0.155, -0.085)
	visor.scale = Vector3(1.0, 0.86, 0.66)
	var crack := MeshInstance3D.new()   # (set_cracks shows it)
	crack.name = "VisorCracks"
	crack.mesh = sm
	n.add_child(crack)
	crack.position = visor.position + Vector3(0, 0, -0.002)
	crack.scale = visor.scale * 1.012
	crack.visible = false
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var frame := A.ring(n, 0.139, 0.129, Vector3(0, 0.155, -0.088), "metal", STEEL.darkened(0.45), Vector3(PI / 2.0, 0, 0))
	frame.scale = Vector3(1.0, 1.0, 0.86)
	# Headlamp on a bracket above the brow, cable running back.
	A.box(n, Vector3(0.05, 0.035, 0.03), Vector3(0, 0.3, -0.135), "metal", STEEL.darkened(0.3), false, 0.2)
	A.cyl(n, 0.026, 0.05, Vector3(0, 0.3, -0.165), "metal", STEEL, false, "z")
	A.cyl(n, 0.021, 0.004, Vector3(0, 0.3, -0.191), "metal", Color(0.9, 0.9, 0.8), false, "z")
	A.seg(n, Vector3(0.02, 0.29, -0.14), Vector3(0.09, 0.28, 0.12), 0.004, 0.004, "rubber")


static func _upper_arm(n: Node3D, side: float) -> void:
	A.sphere(n, 0.068, Vector3.ZERO, "fabric", SUIT)
	A.seg(n, Vector3.ZERO, Vector3(0, -UPPER_ARM, 0), 0.063, 0.054, "fabric", SUIT)
	A.cyl(n, 0.064, 0.035, Vector3(0, -0.11, 0), "plastic", TAPE)                     # tape band
	A.box(n, Vector3(0.012, 0.07, 0.06), Vector3(side * 0.06, -0.05, 0), "fabric", DARK, false, 0.2)   # sleeve pocket


static func _forearm(n: Node3D, side: float) -> void:
	A.sphere(n, 0.055, Vector3.ZERO, "fabric", SUIT)
	A.seg(n, Vector3.ZERO, Vector3(0, -0.22, 0), 0.053, 0.046, "fabric", SUIT)
	A.cyl(n, 0.05, 0.035, Vector3(0, -0.205, 0), "fabric", DARK)                       # elastic cuff
	A.seg(n, Vector3(0, -0.2, 0), Vector3(0, -FOREARM, 0), 0.047, 0.041, "leather")     # gauntlet
	# Gloved hand, palm in, fingers loosely curled forward, thumb in front.
	var h := Node3D.new()
	n.add_child(h)
	h.position = Vector3(0, -FOREARM, 0)
	A.box(h, Vector3(0.03, 0.085, 0.08), Vector3(0, -0.045, 0), "leather", Color.WHITE, false, 0.2)
	for f in 4:
		var z := -0.03 + f * 0.02
		var a := Vector3(0, -0.085, z)
		var b := a + Vector3(-side * 0.004, -0.045, -0.008)
		var c := b + Vector3(-side * 0.008, -0.03, -0.022)
		A.seg(h, a, b, 0.0095, 0.009, "leather")
		A.seg(h, b, c, 0.009, 0.008, "leather")
		A.sphere(h, 0.009, b, "leather")
	A.seg(h, Vector3(-side * 0.012, -0.03, -0.04), Vector3(-side * 0.02, -0.07, -0.06), 0.011, 0.009, "leather")   # thumb


static func _thigh(n: Node3D, side: float) -> void:
	A.seg(n, Vector3.ZERO, Vector3(0, -THIGH, 0), 0.084, 0.068, "fabric", SUIT)
	A.box(n, Vector3(0.03, 0.13, 0.11), Vector3(side * 0.08, -0.2, 0.0), "fabric", DARK, false, 0.3)   # cargo pocket
	A.box(n, Vector3(0.032, 0.03, 0.115), Vector3(side * 0.081, -0.14, 0.0), "fabric", SUIT, false, 0.3)
	A.cyl(n, 0.074, 0.035, Vector3(0, -0.3, 0), "plastic", TAPE)
	A.box(n, Vector3(0.1, 0.12, 0.035), Vector3(0, -THIGH + 0.01, -0.07), "rubber", Color.WHITE, false, 0.2)   # kneepad
	A.box(n, Vector3(0.11, 0.02, 0.02), Vector3(0, -THIGH + 0.04, -0.055), "rubber", Color.WHITE, false, 0.2)


static func _shin(n: Node3D, side: float) -> void:
	A.sphere(n, 0.066, Vector3.ZERO, "fabric", SUIT)
	A.seg(n, Vector3.ZERO, Vector3(0, -0.32, 0), 0.066, 0.058, "fabric", SUIT)
	A.cyl(n, 0.068, 0.03, Vector3(0, -0.24, 0), "plastic", TAPE)
	# Work boot: shaft, foot, toe cap, sole, heel, laces.
	A.cyl(n, 0.066, 0.13, Vector3(0, -0.36, 0), "leather", Color.WHITE)
	A.cyl(n, 0.068, 0.02, Vector3(0, -0.3, 0), "leather", Color(0.8, 0.8, 0.8))      # boot top roll
	A.box(n, Vector3(0.115, 0.085, 0.22), Vector3(0, -SHIN - 0.0, -0.04), "leather", Color.WHITE, false, 0.3)
	A.cyl(n, 0.055, 0.115, Vector3(0, -SHIN - 0.012, -0.15), "leather", Color.WHITE, false, "x")   # rounded toe
	A.box(n, Vector3(0.125, 0.025, 0.29), Vector3(0, -SHIN - 0.055, -0.06), "rubber", Color.WHITE, false, 0.3)   # sole
	A.box(n, Vector3(0.12, 0.02, 0.07), Vector3(0, -SHIN - 0.075, 0.04), "rubber", Color.WHITE, false, 0.2)    # heel
	for k in 4:
		A.box(n, Vector3(0.07, 0.008, 0.008), Vector3(0, -SHIN + 0.01 + k * 0.03, -0.068 - k * 0.002), "paper", Color(0.35, 0.3, 0.25), false, 0.1, Vector3(0, 0, 0.3 * (k % 2) - 0.15))
	A.box(n, Vector3(0.04, 0.1, 0.012), Vector3(0, -SHIN + 0.04, -0.062), "leather", Color(0.8, 0.8, 0.8), false, 0.2)   # tongue
