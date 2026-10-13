# The employee, as everyone else sees them. Every piece is a smooth surface (suit_mesh.gd) shaped to
# lie on what's under it, so nothing floats, cuts in or shows a flat end:
#   the coverall  a one-piece work suit over a broad chest and narrow waist: a stand collar, the zip
#                 under a storm flap, two chest pockets with flaps and a name tape, a Bureau patch on
#                 the left sleeve, cargo pockets on the thighs, elastic cuffs and hems; reflective
#                 tape round the chest, waist, upper arms, thighs and shins
#   the joints    every limb ends in a half-sphere round its joint, and the next one starts in the
#                 same: bent any way, a joint stays a rounded elbow or knee, never a gap
#   the helmet    an enclosed shell with the visor set into a real opening behind a rubber gasket, a
#                 neck seal under it, ear cups, a lamp on a bracket with its cable running back over
#                 the shell to a battery pack (crest, brim or sun-visor housing by style)
#   the hands     gloves with a gauntlet over the cuff, a shaped palm, three-jointed fingers curled
#                 easy and a thumb, the palm toward the thigh
#   the boots     lofted work boots: a padded collar, the trouser hem over it, a laced front up the
#                 shaft and over the instep, a toe cap, a lugged sole with a heel
#   the kit       a belt with buckle, pouches, a holstered torch and a carabiner; knee pads; what's on
#                 the back (pack, air tanks, a tool pack, a radio pack or nothing) with its harness;
#                 what's on the chest (radio, chest lamp, ID badge, knife or nothing)
# Eleven parts, each in its own frame with its pivot at the joint it hangs from, so the same parts
# make the standing figure (photos, security feeds, crewmates), the ragdoll and the body you carry.
# PARTS gives every part's joint in the standing pose. Each mesh carries the slot it's coloured by
# ("lk": suit, trim, helmet, visor, glove, boot, ...); apply_look recolours them and rebuilds the
# pieces that change shape (helmet style, pack, chest kit, marking, name patch).
extends RefCounted

const A = preload("res://src/art.gd")
const M = preload("res://src/suit_mesh.gd")
const Cracks = preload("res://src/cracks.gd")

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

# --- the looks ---------------------------------------------------------------------------------------
# A look is an array of indices into these, in LOOK order; [] (or a short one) is the Bureau's issue.
const SUITS := [["BUREAU ORANGE", Color.WHITE], ["HI-VIS YELLOW", Color(1.0, 0.92, 0.25)], ["OLIVE DRAB", Color(0.48, 0.52, 0.3)],
	["NAVY", Color(0.26, 0.32, 0.55)], ["SIGNAL RED", Color(0.85, 0.2, 0.15)], ["CLEAN-ROOM WHITE", Color(0.98, 0.98, 0.95)],
	["CHARCOAL", Color(0.3, 0.3, 0.32)], ["TEAL", Color(0.2, 0.6, 0.58)], ["SAND", Color(0.86, 0.76, 0.56)],
	["SKY BLUE", Color(0.45, 0.68, 0.9)], ["FOREST GREEN", Color(0.22, 0.4, 0.24)], ["PLUM", Color(0.45, 0.22, 0.42)],
	["RUST BROWN", Color(0.55, 0.3, 0.18)], ["MIDNIGHT", Color(0.12, 0.12, 0.15)]]
const HELMETS := [["CREAM", HELMET], ["WHITE", Color(0.92, 0.92, 0.9)], ["SAFETY YELLOW", Color(0.98, 0.78, 0.15)],
	["RED", Color(0.78, 0.16, 0.12)], ["BLUE", Color(0.22, 0.38, 0.75)], ["BLACK", Color(0.14, 0.14, 0.15)],
	["ORANGE", Color(0.98, 0.48, 0.12)], ["GREEN", Color(0.3, 0.52, 0.26)], ["GUNMETAL", Color(0.38, 0.4, 0.43)],
	["PINK", Color(0.92, 0.5, 0.62)], ["PURPLE", Color(0.42, 0.28, 0.62)], ["SKY", Color(0.55, 0.78, 0.92)]]
const MARKS := ["NONE", "STRIPE", "TWIN STRIPES", "MEDIC CROSS", "CHECKER", "CREW NUMBER", "CHEVRON", "BAND", "HAZARD BAND"]
const VISORS := [["SMOKE", Color(0.05, 0.07, 0.09), 0.75, 0.08], ["GOLD", Color(0.85, 0.6, 0.18), 1.0, 0.14], ["BLUE MIRROR", Color(0.16, 0.32, 0.62), 0.9, 0.1],
	["AMBER", Color(0.55, 0.3, 0.05), 0.5, 0.1], ["EMERALD", Color(0.05, 0.32, 0.18), 0.8, 0.1], ["SILVER", Color(0.72, 0.74, 0.78), 1.0, 0.12]]
const PACKS := ["RUCKSACK", "AIR TANKS", "TOOL PACK", "RADIO PACK", "NONE"]
const GLOVES := [["WORK LEATHER", "leather", Color.WHITE], ["BLACK", "leather", Color(0.3, 0.3, 0.3)], ["YELLOW RUBBER", "plastic", Color(0.95, 0.78, 0.15)],
	["ORANGE RUBBER", "plastic", Color(0.95, 0.42, 0.12)], ["WHITE COTTON", "canvas", Color(0.95, 0.94, 0.9)], ["GREEN NITRILE", "plastic", Color(0.3, 0.6, 0.35)]]
const BOOTS := [["BROWN LEATHER", "leather", Color.WHITE], ["BLACK", "leather", Color(0.32, 0.3, 0.3)], ["TAN", "leather", Color(1.35, 1.15, 0.85)],
	["YELLOW RUBBER", "plastic", Color(0.95, 0.78, 0.15)], ["GREY RUBBER", "rubber", Color(1.6, 1.6, 1.6)]]
const TRIMS := [["SILVER", Color(0.86, 0.87, 0.82)], ["YELLOW", Color(0.95, 0.85, 0.2)], ["LIME", Color(0.72, 0.95, 0.2)],
	["RED", Color(0.85, 0.15, 0.1)], ["BLACK", Color(0.13, 0.13, 0.13)], ["NONE", Color.WHITE]]
const STYLES := ["RESCUE", "MINER", "PILOT"]
const CHESTS := ["RADIO", "CHEST LAMP", "ID BADGE", "KNIFE", "NONE"]
const WEARS := [["CLEAN", Color(1, 1, 1)], ["WORN", Color(0.86, 0.84, 0.8)], ["FILTHY", Color(0.64, 0.58, 0.5)]]
## What each look slot is, in order (and its settings key: "look_" + name).
const LOOK := ["suit", "helmet", "mark", "visor", "pack", "gloves", "boots", "trim", "style", "chest", "wear"]


static func lists() -> Dictionary:
	return {"suit": SUITS, "helmet": HELMETS, "mark": MARKS, "visor": VISORS, "pack": PACKS, "gloves": GLOVES,
		"boots": BOOTS, "trim": TRIMS, "style": STYLES, "chest": CHESTS, "wear": WEARS}


## A look's choice for `slot` (clamped, missing: 0).
static func pick(look: Array, slot: String) -> int:
	var i := LOOK.find(slot)
	var n: int = lists()[slot].size()
	return clampi(int(look[i]) if i < look.size() else 0, 0, n - 1)


# --- the body's shapes ---------------------------------------------------------------------------------
# Trunk sections [y, half width, half depth, z offset, squareness] in the part's own frame.
const PEL := [[-0.13, 0.112, 0.085, 0.0, 2.3], [-0.07, 0.148, 0.1, 0.0, 2.4], [0.0, 0.157, 0.106, 0.0, 2.4], [0.07, 0.151, 0.104, 0.0, 2.4], [0.15, 0.141, 0.099, 0.0, 2.4]]
const TOR := [[-0.09, 0.14, 0.099, 0.0, 2.4], [0.05, 0.143, 0.101, 0.0, 2.4], [0.16, 0.158, 0.107, -0.004, 2.5], [0.26, 0.176, 0.113, -0.008, 2.7],
	[0.33, 0.194, 0.111, -0.006, 2.9], [0.385, 0.202, 0.104, 0.0, 3.0], [0.425, 0.19, 0.096, 0.0, 2.8], [0.452, 0.13, 0.081, 0.004, 2.2], [0.474, 0.074, 0.065, 0.008, 2.0]]
const ARM := [0.29, 0.07, 0.058, 0.95]   # upper arm: length, top radius, bottom, depth
const FORE := [0.2, 0.058, 0.049, 0.95]   # (the sleeve: it ends under the glove's gauntlet)
const LEG := [0.42, 0.088, 0.07, 0.95]
const SHANK := [0.4, 0.07, 0.058, 0.97]
const HELM_C := Vector3(0, 0.19, 0.01)    # the helmet shell: an ellipsoid round the head
const HELM_R := Vector3(0.152, 0.158, 0.166)
const WIN := [1.05, -0.14, 0.49]          # its window: half width (rad round), centre and half height (rad up)
const FRONT := PI / 2.0                   # (a trunk's angle that faces forward, -z)
const BACK := -PI / 2.0


## Dress a built figure (or the first-person sleeve) in a look; `who` goes on the name patch.
static func apply_look(root: Node, look: Array, who := "") -> void:
	if root == null:
		return
	var head := root.find_child("head", true, false) as Node3D
	var torso := root.find_child("torso", true, false) as Node3D
	if head != null:
		_variant(head, "Style", _style.bind(pick(look, "style")))
		_variant(head, "Marking", _marking.bind(pick(look, "mark"), pick(look, "helmet"), pick(look, "style"), who))
	if torso != null:
		_variant(torso, "Pack", _pack.bind(pick(look, "pack")))
		_variant(torso, "ChestKit", _chest.bind(pick(look, "chest"), pick(look, "pack")))
		_variant(torso, "BackName", _name_patch.bind(who, pick(look, "pack")))
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if _held(mi, root):   # (what's held, a body over the shoulder included, keeps its own)
			continue
		var slot := String(mi.get_meta("lk", ""))
		if slot == "":   # (the first-person sleeve: its suit and gloves by their textures)
			var m0 = mi.get_meta("look_orig", mi.material_override)
			if not (m0 is StandardMaterial3D):
				continue
			if m0.albedo_texture == A.texture("fabric"):
				slot = "suit"
			elif m0.albedo_texture == A.texture("leather"):
				slot = "glove"
			else:
				continue
			mi.set_meta("look_orig", m0)
			mi.set_meta("lk", slot)
			mi.set_meta("shade", m0.albedo_color.v / 1.0 if slot == "suit" else 1.0)
			mi.set_meta("tile", 1.0 / m0.uv1_scale.x)
		mi.material_override = look_mat(slot, look, float(mi.get_meta("shade", 1.0)), float(mi.get_meta("tile", 0.5)))
		if slot == "trim":
			mi.visible = pick(look, "trim") != TRIMS.size() - 1


## Is `n` part of something held (not the arm itself)?
static func _held(n: Node, root: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != root:
		if p.name in ["Item", "HeldItem"]:
			return true
		p = p.get_parent()
	return false


## A slot's material in a look, `shade` darker for seams and the like.
static func look_mat(slot: String, look: Array, shade := 1.0, tile := 0.5) -> Material:
	var wear: Color = WEARS[pick(look, "wear")][1]
	match slot:
		"suit":
			var s := pick(look, "suit")
			var c: Color = (SUITS[s][1] as Color) * wear * shade
			return A.mat("fabric" if s == 0 else "fabric_tint", Color(c.r, c.g, c.b), tile)
		"webbing":
			var c2: Color = CANVAS * wear.lerp(Color.WHITE, 0.4) * shade
			return A.mat("canvas", Color(c2.r, c2.g, c2.b), tile)
		"trim":
			var tc: Color = (TRIMS[pick(look, "trim")][1] as Color) * shade
			return A.mat("canvas", Color(tc.r, tc.g, tc.b) * 1.08, 0.2)
		"helmet":
			var hc: Color = (HELMETS[pick(look, "helmet")][1] as Color) * shade
			return A.mat("plastic", Color(hc.r, hc.g, hc.b), tile)
		"visor":
			return _visor_mat(pick(look, "visor"))
		"glove":
			var g: Array = GLOVES[pick(look, "gloves")]
			var gc: Color = (g[2] as Color) * shade
			return A.mat(g[1], Color(gc.r, gc.g, gc.b), tile)
		"boot":
			var b: Array = BOOTS[pick(look, "boots")]
			var bc: Color = (b[2] as Color) * shade
			return A.mat(b[1], Color(bc.r, bc.g, bc.b), tile)
	return A.mat("plastic", Color.WHITE)


static var _visors := {}
static func _visor_mat(i: int) -> StandardMaterial3D:
	if not _visors.has(i):
		var v: Array = VISORS[i]
		var m := StandardMaterial3D.new()
		m.albedo_color = v[1]
		m.metallic = v[2]
		m.roughness = v[3]
		m.metallic_specular = 0.8
		_visors[i] = m
	return _visors[i]


## Rebuild a piece that changes shape with the look: `host`'s child `name`, made fresh by `make`.
static func _variant(host: Node3D, name: String, make: Callable) -> void:
	var old := host.get_node_or_null(name)
	if old != null:
		host.remove_child(old)
		old.free()
	var n := Node3D.new()
	n.name = name
	host.add_child(n)
	make.call(n)
	var lay := 0   # (on your own body's layer, if it's on one)
	for mi: MeshInstance3D in host.find_children("*", "MeshInstance3D", false, false):
		if mi.get_parent() != n:
			lay = mi.layers
			break
	if lay != 0 and lay != 1:
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			mi.layers = lay
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Build one part into `n` (its own frame: pivot at the origin, limbs hanging along -y), in the
## Bureau's issue (apply_look dresses it otherwise).
static func part(n: Node3D, name: String) -> void:
	var side := -1.0 if name.ends_with("_l") else 1.0
	match name.trim_suffix("_l").trim_suffix("_r"):
		"pelvis": _pelvis(n)
		"torso":
			_torso(n)
			_variant(n, "Pack", _pack.bind(0))
			_variant(n, "ChestKit", _chest.bind(0, 0))
		"head":
			_head(n)
			_variant(n, "Style", _style.bind(0))
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
		n.name = name   # (so a part can be found by name: armour, cracks, the look)
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


# --- building blocks ------------------------------------------------------------------------------------

## A MeshInstance of the cached mesh `key` (made by `make`), coloured by look slot `slot` (or a
## fixed material: slot "" and `kind`/`tint`), `shade` darker for seams.
static func _put(n: Node3D, key: String, make: Callable, slot: String, shade := 1.0, pos := Vector3.ZERO, basis := Basis.IDENTITY, kind := "", tint := Color.WHITE, tile := 0.5) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var args := []   # (the key names the piece; its arguments tell its shapes apart)
	for a in make.get_bound_arguments():
		if not (a is Callable):
			args.append(a)
	mi.mesh = M.cached(key + str(args), make)
	if slot != "":
		mi.set_meta("lk", slot)
		mi.set_meta("shade", shade)
		mi.set_meta("tile", tile)
		mi.material_override = look_mat(slot, [], shade, tile)
	else:
		mi.material_override = A.mat(kind, tint, tile)
	n.add_child(mi)
	mi.transform = Transform3D(basis, pos)
	return mi


## A small rounded box (pouches, buckles, radios): `size`, edges rounded by `rad`.
static func _rb(n: Node3D, size: Vector3, rad: float, pos: Vector3, slot: String, shade := 1.0, basis := Basis.IDENTITY, kind := "", tint := Color.WHITE) -> MeshInstance3D:
	var key := "rb%s%.4f" % [size, rad]
	return _put(n, key, M.rbox.bind(size, rad), slot, shade, pos, basis, kind, tint, 0.3)


## A basis whose -z points along `fwd` and +y as near `up` as it can (for things set on a surface).
static func _facing(fwd: Vector3, up := Vector3.UP) -> Basis:
	var z := -fwd.normalized()
	if absf(z.dot(up.normalized())) > 0.98:
		up = Vector3.FORWARD
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x), z)


## A basis whose +y points along `along` (a limb mesh laid down a direction).
static func _along(along: Vector3, hint := Vector3.FORWARD) -> Basis:
	var y := along.normalized()
	if absf(y.dot(hint)) > 0.95:
		hint = Vector3.RIGHT
	var x := hint.cross(y).normalized()
	return Basis(x, y, x.cross(y))


## A band round a trunk at `y`, `h` tall, `lift` off it (tape, belts): the trunk's own sections, a
## little bigger, so it wraps it exactly.
static func _band_keys(keys: Array, y: float, h: float, lift: float) -> Array:
	var out := []
	for k in 4:
		var yy := y - h / 2.0 + h * k / 3.0
		var s := M.section(keys, yy)
		out.append([yy, s[0] + lift, s[1] + lift, s[2], s[3]])
	return out


## The same for a limb (made by M.limb): a band at `v` down it.
static func _limb_band(spec: Array, v: float, h: float, lift: float) -> ArrayMesh:
	var keys := [[-spec[0], spec[2], spec[2] * spec[3], 0.0, 2.0], [0.0, spec[1], spec[1] * spec[3], 0.0, 2.0]]
	var bk := _band_keys(keys, -v, h, lift)
	return M.trunk(bk, 22, 4)


static func _limb_mesh(spec: Array) -> ArrayMesh:
	return M.limb(spec[0], spec[1], spec[2], spec[3], 22, 26)


# --- the coverall ----------------------------------------------------------------------------------------

static func _pelvis(n: Node3D) -> void:
	_put(n, "pel", M.trunk.bind(PEL, 28, 24, 0.06, 0.0), "suit", 1.0, Vector3.ZERO, Basis.IDENTITY, "", Color.WHITE, 1.0)
	# The belt, wrapping the hips, its buckle, the loops it runs through.
	_put(n, "belt", func(): return M.trunk(_band_keys(PEL, 0.095, 0.045, 0.007), 28, 4), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "leather", Color(0.55, 0.42, 0.3), 0.3)
	var front := M.on_trunk(PEL, FRONT, 0.095, 0.012)
	_rb(n, Vector3(0.064, 0.05, 0.014), 0.005, front, "", 1.0, Basis.IDENTITY, "metal", Color(0.62, 0.6, 0.55))   # buckle
	_rb(n, Vector3(0.03, 0.026, 0.01), 0.003, front + Vector3(0, 0, -0.006), "", 1.0, Basis.IDENTITY, "leather", Color(0.45, 0.33, 0.24))
	for u in [FRONT - 0.75, FRONT + 0.75, BACK - 0.45, BACK + 0.45]:   # belt loops
		var p := M.on_trunk(PEL, u, 0.095, 0.009)
		_rb(n, Vector3(0.014, 0.055, 0.008), 0.003, p, "suit", 0.8, _facing(-M.trunk_normal(PEL, u, 0.095)))
	# Pouches either side at the front, hung from the belt, flaps buttoned.
	for s in [-1.0, 1.0]:
		var u: float = FRONT - s * 1.05
		var nrm := M.trunk_normal(PEL, u, 0.04)
		var p := M.on_trunk(PEL, u, 0.04, 0.032)
		var b := _facing(-nrm)
		_rb(n, Vector3(0.07, 0.085, 0.05), 0.012, p, "webbing", 1.0, b)
		_rb(n, Vector3(0.074, 0.03, 0.054), 0.01, p + Vector3(0, 0.035, 0) - nrm * 0.002, "webbing", 0.82, b)
		A.sphere(n, 0.006, p + Vector3(0, 0.022, 0) + nrm * 0.028, "metal", STEEL)
	# A torch holstered on the right hip, behind; a carabiner on the left.
	var hu := -0.55
	var hn := M.trunk_normal(PEL, hu, 0.03)
	var hp := M.on_trunk(PEL, hu, 0.03, 0.03)
	_rb(n, Vector3(0.052, 0.07, 0.05), 0.01, hp, "", 1.0, _facing(-hn), "leather", Color(0.4, 0.3, 0.22))
	_put(n, "torch", M.lathe.bind([[-0.09, 0.019], [0.04, 0.019], [0.05, 0.025], [0.085, 0.026]], 16), "", 1.0, hp + Vector3(0, 0.015, 0) + hn * 0.002, Basis.IDENTITY, "plastic", Color(0.95, 0.75, 0.15), 0.3)
	_put(n, "torchlens", M.lathe.bind([[0.084, 0.021], [0.09, 0.019]], 16), "", 1.0, hp + Vector3(0, 0.015, 0) + hn * 0.002, Basis.IDENTITY, "metal", Color(0.85, 0.85, 0.8), 0.3)
	var cp := M.on_trunk(PEL, PI - 0.55, 0.08, 0.016)
	var ring := A.ring(n, 0.024, 0.017, cp + Vector3(0, -0.025, 0), "metal", Color(0.7, 0.7, 0.72), Vector3(0, PI - 0.55 + PI / 2.0, PI / 2.0))
	ring.scale = Vector3(1.0, 1.0, 1.4)


static func _torso(n: Node3D) -> void:
	_put(n, "tor", M.trunk.bind(TOR, 32, 40, 0.04, 0.0), "suit", 1.0, Vector3.ZERO, Basis.IDENTITY, "", Color.WHITE, 1.0)
	# Stand collar, the neck seal of the helmet sits down inside it.
	_put(n, "collar", M.trunk.bind([[0.425, 0.104, 0.086, 0.004, 2.3], [0.455, 0.1, 0.083, 0.006, 2.2], [0.5, 0.09, 0.078, 0.008, 2.0]], 26, 8), "suit", 0.78)
	# Storm flap over the zip, its pull at the top; the pocket on each breast with its flap; name tape.
	var tf := M.trunk_fn(TOR)
	_put(n, "storm", M.slab.bind(tf, FRONT - 0.05, FRONT + 0.05, -0.05, 0.43, 3, 18, -0.001, 0.005, 0.3), "suit", 0.92)
	_rb(n, Vector3(0.012, 0.026, 0.006), 0.002, M.on_trunk(TOR, FRONT, 0.42, 0.008), "", 1.0, Basis.IDENTITY, "metal", Color(0.65, 0.65, 0.62))
	for s in [-1.0, 1.0]:
		var u0: float = FRONT + (0.16 if s < 0.0 else -0.68)
		_put(n, "pocket%d" % int(s), M.slab.bind(tf, u0, u0 + 0.52, 0.215, 0.33, 8, 6, -0.001, 0.007, 0.18), "suit", 0.9)
		_put(n, "pflap%d" % int(s), M.slab.bind(tf, u0 - 0.02, u0 + 0.54, 0.3, 0.345, 8, 3, 0.004, 0.006, 0.3), "suit", 0.8)
		A.sphere(n, 0.006, M.on_trunk(TOR, u0 + 0.26, 0.307, 0.012), "plastic", Color(0.15, 0.15, 0.15))
	_put(n, "nametape", M.slab.bind(tf, FRONT - 0.72, FRONT - 0.1, 0.358, 0.387, 8, 2, -0.001, 0.004, 0.2), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "canvas", Color(0.92, 0.9, 0.82), 0.2)
	# Reflective tape round the chest and the waist.
	for y in [0.06, 0.18]:   # (below the pockets: nothing pokes through it)
		_put(n, "ttape%.3f" % y, func(): return M.trunk(_band_keys(TOR, y, 0.036, 0.0065), 32, 4), "trim")
	# Seams: the yoke across the back and over the shoulders.
	_put(n, "yoke", M.slab.bind(tf, BACK - 1.3, BACK + 1.3, 0.37, 0.378, 20, 1, -0.0015, 0.003, 0.0), "suit", 0.7)


static func _upper_arm(arm: Node3D, side: float) -> void:
	# Built along the line from the shoulder to the elbow (the elbow is a little further out than
	# the shoulder: hung straight down, the forearm started beside the sleeve, not under it).
	var s_ := "_l" if side < 0.0 else "_r"
	var to_elbow: Vector3 = (PARTS["forearm" + s_][1] as Vector3) - (PARTS["upper_arm" + s_][1] as Vector3)
	var n := Node3D.new()
	n.name = "Sleeve"
	arm.add_child(n)
	n.basis = _along(-to_elbow, Vector3.FORWARD) * Basis.from_scale(Vector3.ONE * (to_elbow.length() / ARM[0]))
	_put(n, "uarm", _limb_mesh.bind(ARM), "suit", 1.0, Vector3.ZERO, Basis.IDENTITY, "", Color.WHITE, 1.0)
	_put(n, "uarmtape", _limb_band.bind(ARM, 0.13, 0.034, 0.004), "trim")
	# The Bureau's patch on the left sleeve, below the shoulder; a pen pocket on the right.
	var lf := M.limb_fn(ARM[0], ARM[1], ARM[2], ARM[3])
	var out := PI if side < 0.0 else 0.0
	if side < 0.0:
		_put(n, "patch", M.slab.bind(lf, out - 0.42, out + 0.42, 0.035, 0.1, 6, 4, -0.001, 0.003, 0.35), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "canvas", Color(0.13, 0.17, 0.26), 0.2)
		_put(n, "patchrim", M.slab.bind(lf, out - 0.3, out + 0.3, 0.05, 0.085, 4, 3, 0.001, 0.003, 0.4), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "plastic", Color(0.95, 0.62, 0.15), 0.2)
	else:
		_put(n, "penpocket", M.slab.bind(lf, out - 0.35, out + 0.35, 0.05, 0.13, 5, 5, -0.001, 0.006, 0.2), "suit", 0.85)
		_rb(n, Vector3(0.008, 0.03, 0.008), 0.003, (lf.call(out - 0.12, 0.04)[0] as Vector3) + Vector3(side * 0.006, 0.0, 0), "", 1.0, Basis.IDENTITY, "plastic", Color(0.15, 0.25, 0.6))


static func _forearm(n: Node3D, side: float) -> void:
	_put(n, "farm", _limb_mesh.bind(FORE), "suit", 1.0, Vector3.ZERO, Basis.IDENTITY, "", Color.WHITE, 1.0)
	# The glove's gauntlet over the sleeve's end, narrowing to the wrist, a hem round its top.
	_put(n, "gaunt", M.lathe.bind([[-0.272, 0.036], [-0.256, 0.042], [-0.232, 0.0505], [-0.21, 0.0522], [-0.2, 0.0518]], 20), "glove")
	_put(n, "gauntrim", M.lathe.bind([[-0.207, 0.0527], [-0.2, 0.0532], [-0.194, 0.0522]], 20), "glove", 0.8)
	_hand(n, side)


## The gloved hand, at the end of the forearm (wrist at y -0.272): palm toward the thigh (-side x).
static func _hand(n: Node3D, side: float) -> void:
	var w := -0.272
	var palm := [[w - 0.088, 0.016, 0.042, 0.0, 2.6], [w - 0.06, 0.018, 0.044, 0.0, 2.6], [w - 0.03, 0.019, 0.041, 0.0, 2.7], [w, 0.019, 0.033, 0.0, 2.4]]
	_put(n, "palm", M.trunk.bind(palm, 20, 12, 0.012, 0.0), "glove", 1.0, Vector3(-side * 0.002, 0, 0))
	var inward := Vector3(-side, 0, 0)
	var knuck := w - 0.084
	var lens := [0.92, 1.0, 0.95, 0.82]
	for f in 4:
		var z := -0.03 + f * 0.02
		var at := Vector3(-side * 0.002, knuck, z)
		var dir := Vector3(0, -1, -0.12 + f * 0.08).normalized()
		var segs := [0.036, 0.025, 0.02]
		var rads := [0.0105, 0.0098, 0.009]
		var curl := 0.16
		for k in 3:
			var l: float = segs[k] * lens[f]
			dir = dir.rotated(Vector3(0, 0, 1), -side * curl).normalized()   # (curling toward the palm)
			_put(n, "finger%.4f%.4f" % [l, rads[k]], M.limb.bind(l, rads[k], rads[k] * 0.94, 0.92, 10, 8), "glove", 1.0, at, _along(-dir, Vector3.FORWARD))
			at += dir * l
			curl = 0.27
	# The thumb, from the heel of the palm, forward and across toward the fingers.
	var tb := Vector3(-side * 0.012, w - 0.022, -0.03)
	var td := Vector3(-side * 0.22, -0.82, -0.5).normalized()
	_put(n, "thumbpad", M.trunk.bind([[-0.012, 0.012, 0.016, 0.0, 2.0], [0.012, 0.014, 0.018, 0.0, 2.0]], 12, 6, 0.008, 0.008), "glove", 1.0, tb + td * 0.004, _along(-td))
	for k in 2:
		var l2: float = [0.032, 0.026][k]
		_put(n, "thumb%d" % k, M.limb.bind(l2, 0.0115 - k * 0.001, 0.0105 - k * 0.001, 0.92, 10, 8), "glove", 1.0, tb, _along(-td))
		tb += td * l2
		td = td.rotated(Vector3(0, 0, 1), -side * 0.22).normalized()
	# Stitching over the back of the hand.
	_put(n, "gstitch", M.tube.bind([Vector3(side * 0.019, w - 0.01, -0.03), Vector3(side * 0.02, w - 0.05, -0.02), Vector3(side * 0.02, w - 0.07, 0.0)], 0.0018, 5), "glove", 0.7)


static func _thigh(n: Node3D, side: float) -> void:
	_put(n, "thigh", _limb_mesh.bind(LEG), "suit", 1.0, Vector3.ZERO, Basis.IDENTITY, "", Color.WHITE, 1.0)
	_put(n, "thightape", _limb_band.bind(LEG, 0.3, 0.036, 0.004), "trim")
	# A cargo pocket on the outside, its flap and a snap.
	var lf := M.limb_fn(LEG[0], LEG[1], LEG[2], LEG[3])
	var out := 0.0 if side > 0.0 else PI
	_put(n, "cargo", M.slab.bind(lf, out - 0.55, out + 0.55, 0.12, 0.26, 8, 8, -0.001, 0.012, 0.2), "suit", 0.9)
	_put(n, "cargoflap", M.slab.bind(lf, out - 0.57, out + 0.57, 0.11, 0.145, 8, 3, 0.006, 0.004, 0.4), "suit", 0.8)
	A.sphere(n, 0.006, (lf.call(out, 0.14)[0] as Vector3) + Vector3(side * 0.02, 0, 0), "metal", STEEL)


static func _shin(n: Node3D, side: float) -> void:
	_put(n, "shin", _limb_mesh.bind(SHANK), "suit", 1.0, Vector3.ZERO, Basis.IDENTITY, "", Color.WHITE, 1.0)
	_put(n, "shintape", _limb_band.bind(SHANK, 0.2, 0.036, 0.004), "trim")
	# The knee pad: a moulded cup over the front of the knee, its strap round behind.
	var kf := M.ellipsoid_fn(Vector3(0, -0.02, 0), Vector3(0.072, 0.086, 0.074))
	_put(n, "kneepad", M.slab.bind(kf, -0.95, 0.95, -0.8, 0.55, 12, 10, -0.001, 0.016, 0.3), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "rubber", Color(0.9, 0.9, 0.9), 0.3)
	_put(n, "kneestrap", func(): return M.trunk([[-0.11, 0.0705, 0.0685, 0.0, 2.0], [-0.085, 0.0715, 0.0695, 0.0, 2.0]], 20, 3), "webbing", 0.8)
	# The trouser leg's hem, hanging over the boot's collar.
	_put(n, "hem", M.lathe.bind([[-0.335, 0.076], [-0.325, 0.078], [-0.29, 0.07], [-0.26, 0.067]], 22), "suit", 0.85)
	_boot(n, side)


## A work boot on the shin (ankle at -SHIN): the shaft up the leg to a padded collar, the foot along
## -z to a toe cap, a lugged sole and heel, laces from the toe cap up to the collar.
static func _boot(n: Node3D, side: float) -> void:
	_put(n, "shaft", M.lathe.bind([[-0.47, 0.061], [-0.44, 0.063], [-0.38, 0.066], [-0.335, 0.069], [-0.32, 0.072], [-0.31, 0.068]], 22), "boot")
	_put(n, "bcollar", M.lathe.bind([[-0.325, 0.074], [-0.316, 0.077], [-0.306, 0.073]], 22), "boot", 0.8)
	# The foot: sections [z, half width, half height, centre height, squareness] heel to toe.
	var foot := [[0.085, 0.042, 0.03, -0.48, 2.6], [0.06, 0.05, 0.045, -0.468, 2.6], [0.02, 0.053, 0.05, -0.462, 2.6], [-0.03, 0.055, 0.042, -0.47, 2.8],
		[-0.08, 0.057, 0.033, -0.478, 3.0], [-0.13, 0.056, 0.027, -0.483, 3.0], [-0.17, 0.051, 0.024, -0.486, 2.8], [-0.195, 0.042, 0.021, -0.488, 2.4]]
	_put(n, "foot", _foot_mesh.bind(foot, 0.012, 0.016), "boot")
	var cap := []
	for k in foot:
		if k[0] <= -0.11:
			cap.append([k[0], k[1] + 0.003, k[2] + 0.003, k[3], k[4]])
	cap.push_front([-0.11, 0.0565, 0.0302, -0.4805, 3.0])
	_put(n, "toecap", _foot_mesh.bind(cap, 0.0, 0.019), "boot", 0.82)
	var sole := [[0.092, 0.047, 0.016, -0.499, 5.0], [0.03, 0.056, 0.016, -0.499, 5.0], [0.005, 0.059, 0.0095, -0.5055, 6.0], [-0.12, 0.062, 0.0095, -0.5055, 6.0],
		[-0.18, 0.056, 0.0095, -0.5055, 6.0], [-0.205, 0.045, 0.0095, -0.5055, 5.0]]
	_put(n, "sole", _foot_mesh.bind(sole, 0.006, 0.01), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "rubber", Color(0.6, 0.58, 0.55), 0.3)
	for k in 6:   # lugs across the sole
		var z := 0.07 - k * 0.05
		_rb(n, Vector3(0.09 if k > 1 else 0.08, 0.005, 0.012), 0.002, Vector3(0, -0.5145, z), "", 1.0, Basis.IDENTITY, "rubber", Color(0.45, 0.43, 0.4))
	# Laces: crossing over the tongue up the instep, then up the front of the shaft.
	var lace := Color(0.32, 0.27, 0.2)
	var top := func(z: float) -> float:
		var s := _fsec(foot, z, 0.0, 0.0)
		return s[2] + s[1] + 0.003
	for k in 4:
		var z0 := -0.105 + k * 0.03
		var z1 := z0 + 0.03
		for sx in [-1.0, 1.0]:
			_put(n, "lace%d%d" % [k, int(sx)], M.tube.bind([Vector3(sx * 0.026, top.call(z0), z0), Vector3(0, top.call((z0 + z1) / 2.0) + 0.002, (z0 + z1) / 2.0), Vector3(-sx * 0.026, top.call(z1), z1)], 0.0028, 5), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "canvas", lace, 0.2)
			A.sphere(n, 0.0045, Vector3(sx * 0.03, top.call(z0) - 0.002, z0), "metal", Color(0.6, 0.58, 0.5))
	_put(n, "tongue", func(): return M.tube([Vector3(0, top.call(-0.11) - 0.004, -0.11), Vector3(0, top.call(-0.06) - 0.004, -0.06), Vector3(0, -0.43, -0.045), Vector3(0, -0.34, -0.062)], 0.004, 8, 0.05), "boot", 0.9)
	for k in 4:   # up the shaft, hooks either side
		var y0 := -0.43 + k * 0.03
		for sx in [-1.0, 1.0]:
			var a := Vector3(sx * 0.03, y0, -0.058 - k * 0.002)
			var b := Vector3(-sx * 0.03, y0 + 0.03, -0.06 - k * 0.002)
			_put(n, "slace%d%d" % [k, int(sx)], M.tube.bind([a, (a + b) / 2.0 + Vector3(0, 0, -0.006), b], 0.0026, 5), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "canvas", lace, 0.2)
			A.sphere(n, 0.0045, a + Vector3(sx * 0.004, 0, 0.003), "metal", Color(0.6, 0.58, 0.5))
	_put(n, "pull", M.tube.bind([Vector3(-0.012, -0.31, 0.066), Vector3(0, -0.285, 0.07), Vector3(0.012, -0.31, 0.066)], 0.0035, 6, 0.012), "boot", 0.7)


## A foot loft: sections [z, half width, half height, centre height, squareness] along -z, rounded
## shut at the heel and toe.
static func _foot_mesh(keys: Array, close0: float, close1: float) -> ArrayMesh:
	var fn := func(u: float, z: float) -> Vector3:
		var k := _fsec(keys, z, close0, close1)
		var q := M.sq(u, k[0], k[1], k[3])
		return Vector3(q.x, k[2] - q.y, z)
	var inside := func(_u: float, z: float) -> Vector3:
		var k := _fsec(keys, z, close0, close1)
		return Vector3(0, k[2], clampf(z, keys[-1][0], keys[0][0]))
	return M.grid(fn, 0.0, TAU, 24, keys[0][0] + close0, keys[-1][0] - close1, 26, inside, true)


## A foot section at `z` (keys run from the heel, +z, toward the toe, -z).
static func _fsec(keys: Array, z: float, close0: float, close1: float) -> Array:
	var flipped := []   # (as -z they run up from the heel: what M.section wants)
	for k: Array in keys:
		flipped.append([-k[0], k[1], k[2], k[3], k[4]])
	return M.section(flipped, -z, close0, close1)


# --- the helmet ----------------------------------------------------------------------------------------

## A point on the helmet shell: `az` round from the front, `el` up; `scale` out from its centre.
static func helm_pt(az: float, el: float, scale := 1.0) -> Vector3:
	return HELM_C + Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * HELM_R * scale


static func helm_n(az: float, el: float) -> Vector3:
	var d := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	return Vector3(d.x / HELM_R.x, d.y / HELM_R.y, d.z / HELM_R.z).normalized()


static func _in_window(az: float, el: float, grow := 0.0) -> bool:
	var a := wrapf(az, -PI, PI) / (WIN[0] + grow)
	var e := (el - WIN[1]) / (WIN[2] + grow)
	return a * a * a * a + e * e * e * e < 1.0


## The shell's lowest edge at `az` (lower at the back, over the nape).
static func _helm_low(az: float) -> float:
	return lerpf(-0.86, -1.0, (1.0 - cos(az)) / 2.0)


static func _shell(scale: float) -> ArrayMesh:
	var fn := func(az: float, t: float) -> Vector3:
		return helm_pt(az, lerpf(_helm_low(az), PI / 2.0 - 0.01, t), scale)
	var inside := func(az: float, t: float) -> Vector3:
		var p := helm_pt(az, lerpf(_helm_low(az), PI / 2.0 - 0.01, t), scale)
		return HELM_C if scale >= 1.0 else HELM_C + (p - HELM_C) * 3.0   # (the inner skin faces in)
	var skip := func(az: float, t: float) -> bool:
		return _in_window(az, lerpf(_helm_low(az), PI / 2.0 - 0.01, t))
	return M.grid(fn, -PI, PI, 96, 0.0, 1.0, 44, inside, true, skip)


static func _head(n: Node3D) -> void:
	# The neck seal: a rubber bellows from the collar up into the shell.
	_put(n, "neck", M.lathe.bind([[-0.05, 0.077], [-0.02, 0.081], [0.01, 0.077], [0.04, 0.083], [0.075, 0.088]], 22, 0.92, 0.008), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "rubber", Color(0.55, 0.55, 0.55), 0.3)
	_put(n, "shell", _shell.bind(1.0), "helmet", 1.0, Vector3.ZERO, Basis.IDENTITY, "", Color.WHITE, 0.3)
	_put(n, "shellin", _shell.bind(0.94), "helmet", 0.55, Vector3.ZERO, Basis.IDENTITY, "", Color.WHITE, 0.3)
	# The rolled rim round the bottom, the gasket round the window.
	var rim := []
	for k in 49:
		var az := -PI + TAU * k / 48.0
		rim.append(helm_pt(az, _helm_low(az), 0.97))
	_put(n, "rim", M.tube.bind(rim, 0.011, 10, 0.0, [], false), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "rubber", Color(0.7, 0.7, 0.7), 0.3)
	var gasket := []
	for k in 65:
		var t := TAU * k / 64.0
		var c := cos(t)
		var s := sin(t)
		var az := signf(c) * sqrt(absf(c)) * WIN[0]
		var el := WIN[1] + signf(s) * sqrt(absf(s)) * WIN[2]
		gasket.append(helm_pt(az, el, 0.995))
	_put(n, "gasket", M.tube.bind(gasket, 0.0115, 10, 0.0, [], false), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "rubber", Color(0.5, 0.5, 0.5), 0.3)
	# The visor, set in behind the gasket.
	var vfn := func(az: float, el: float) -> Vector3:
		return helm_pt(az, el, 0.982)
	var vskip := func(az: float, el: float) -> bool:
		return not _in_window(az, el, 0.06)
	var visor := _put(n, "visor", M.grid.bind(vfn, -WIN[0] - 0.08, WIN[0] + 0.08, 40, WIN[1] - WIN[2] - 0.08, WIN[1] + WIN[2] + 0.08, 24, HELM_C, false, vskip), "visor")
	visor.name = "Visor"
	var crack := MeshInstance3D.new()   # (set_cracks shows it)
	crack.name = "VisorCracks"
	crack.mesh = visor.mesh
	n.add_child(crack)
	crack.position = HELM_C - HELM_C * 1.004
	crack.scale = Vector3.ONE * 1.004
	crack.visible = false
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Ear cups flush on the sides, a bolt in each.
	for s in [-1.0, 1.0]:
		var az: float = s * PI / 2.0
		var p := helm_pt(az, -0.12, 0.985)
		var b := _along(helm_n(az, -0.12))
		_put(n, "earcup", M.lathe.bind([[0.0, 0.046], [0.012, 0.047], [0.02, 0.042], [0.025, 0.03], [0.027, 0.004]], 22), "helmet", 0.82, p, b)
		_put(n, "earbolt", M.lathe.bind([[0.0, 0.011], [0.032, 0.011], [0.034, 0.006]], 12), "", 1.0, p, b, "metal", STEEL, 0.2)
	# The battery for the lamp (the style puts the lamp on), its cable back over the shell to it.
	var bat_n := helm_n(PI, -0.42)   # (low on the back, at the nape)
	_rb(n, Vector3(0.062, 0.04, 0.024), 0.009, helm_pt(PI, -0.42) + bat_n * 0.01, "", 1.0, _facing(-bat_n), "plastic", Color(0.18, 0.18, 0.18))
	var cable := []   # from the lamp back over the crown, beside the crest, down to it
	for k in 25:
		var sa := lerpf(0.8, PI + 0.42, k / 24.0)
		var w := 0.085
		var d := Vector3(sin(w), sin(sa) * cos(w), -cos(sa) * cos(w))
		cable.append(HELM_C + d * HELM_R * 1.03)
	_put(n, "cable", M.tube.bind(cable, 0.004, 6), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "rubber", Color(0.3, 0.3, 0.3), 0.2)


## The helmet lamp at `az`, `el` on the shell, `big` for a miner's cap lamp. The lens is named
## HeadlampLens (set_headlamp lights it).
static func _lamp(n: Node3D, az: float, el: float, big: float) -> void:
	var p := helm_pt(az, el)
	var nrm := helm_n(az, el)
	var fwd := (Vector3(0, -0.12, -1.0)).normalized()   # (aimed a touch down, ahead)
	_put(n, "lampbracket", M.slab.bind(M.ellipsoid_fn(HELM_C, HELM_R), az - 0.2 * big, az + 0.2 * big, el - 0.13, el + 0.11, 6, 5, -0.001, 0.006, 0.3), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "metal", Color(0.3, 0.3, 0.3), 0.2)
	var at := p + nrm * 0.026 * big
	var b := _along(fwd)
	var r := 0.024 * big
	_put(n, "lamp%.2f" % big, M.lathe.bind([[0.0, r * 0.75], [0.03 * big, r], [0.046 * big, r * 1.12], [0.054 * big, r * 1.1]], 18), "", 1.0, at - fwd * 0.012, b, "metal", Color(0.24, 0.24, 0.24), 0.2)
	var lens := _put(n, "lens%.2f" % big, M.lathe.bind([[0.0, r * 0.92], [0.003, r * 0.9]], 18), "", 1.0, at + fwd * 0.044 * big, b, "metal", Color(0.9, 0.9, 0.82), 0.2)
	lens.name = "HeadlampLens"
	lens.set_meta("live", true)


## The helmet's style: RESCUE (a crest along the crown), MINER (a brim all round, a big cap lamp
## lower down), PILOT (a sun-visor housing over the brow, bigger ear cups).
static func _style(n: Node3D, style: int) -> void:
	var ef := M.ellipsoid_fn(HELM_C, HELM_R)
	match style:
		0:   # the crest: a raised rib over the crown, front to back; the lamp over the brow
			_lamp(n, 0.0, 0.66, 1.0)
			var mer := func(s: float, w: float) -> Array:
				var d := Vector3(sin(w), sin(s) * cos(w), -cos(s) * cos(w))
				return [HELM_C + d * HELM_R, Vector3(d.x / HELM_R.x, d.y / HELM_R.y, d.z / HELM_R.z).normalized()]
			_put(n, "crest", M.slab.bind(mer, 0.95, PI - 0.6, -0.045, 0.045, 24, 3, -0.002, 0.012, 0.25), "helmet", 0.9, Vector3.ZERO, Basis.IDENTITY, "", Color.WHITE, 0.3)
			for s in [-1.0, 1.0]:   # vent slots each side of it
				for k in 3:
					_put(n, "vent%d" % k, M.slab.bind(mer, 1.35 + k * 0.18, 1.45 + k * 0.18, s * 0.16 - 0.025, s * 0.16 + 0.025, 2, 2, -0.004, 0.004, 0.0), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "rubber", Color(0.2, 0.2, 0.2), 0.2)
		1:   # a hard hat's brim, all round above the window
			var y0 := HELM_C.y + sin(0.6) * HELM_R.y
			var rx := cos(0.6) * HELM_R.x
			var rz := cos(0.6) * HELM_R.z
			var keys := [[y0 - 0.012, rx + 0.002, rz + 0.002, HELM_C.z, 2.0], [y0 - 0.006, rx + 0.04, rz + 0.05, HELM_C.z - 0.012, 2.0], [y0 + 0.002, rx + 0.042, rz + 0.052, HELM_C.z - 0.012, 2.0], [y0 + 0.012, rx - 0.004, rz - 0.004, HELM_C.z, 2.0]]
			_put(n, "brim", M.trunk.bind(keys, 40, 8), "helmet", 0.92, Vector3.ZERO, Basis.IDENTITY, "", Color.WHITE, 0.3)
			_lamp(n, 0.0, 0.78, 1.35)
		2:   # the sun-visor housing over the brow, its knobs; the lamp on top of it
			_lamp(n, 0.0, 1.06, 1.0)
			_put(n, "housing", M.slab.bind(ef, -1.2, 1.2, 0.42, 0.98, 24, 8, -0.002, 0.022, 0.18), "helmet", 0.9, Vector3.ZERO, Basis.IDENTITY, "", Color.WHITE, 0.3)
			for s in [-1.0, 1.0]:
				var p := helm_pt(s * 1.28, 0.6)
				_put(n, "knob", M.lathe.bind([[0.0, 0.016], [0.018, 0.016], [0.024, 0.01]], 14), "", 1.0, p, _along(helm_n(s * 1.28, 0.6)), "plastic", Color(0.2, 0.2, 0.2), 0.2)


## The helmet's marking, in a colour that stands out from it.
static func _marking(m: Node3D, mark: int, helm: int, style: int, who: String) -> void:
	if mark == 0:
		return
	var hc: Color = HELMETS[helm][1]
	var paint := Color(0.12, 0.12, 0.12) if hc.v > 0.6 else Color(0.92, 0.9, 0.85)
	if mark == 3:
		paint = Color(0.8, 0.1, 0.08) if hc.r < 0.7 or hc.g > 0.5 else Color(0.95, 0.95, 0.92)
	var ef := M.ellipsoid_fn(HELM_C, HELM_R)
	var mer := func(s: float, w: float) -> Array:
		var d := Vector3(sin(w), sin(s) * cos(w), -cos(s) * cos(w))
		return [HELM_C + d * HELM_R, Vector3(d.x / HELM_R.x, d.y / HELM_R.y, d.z / HELM_R.z).normalized()]
	var put := func(key: String, make: Callable, c: Color) -> void:
		_put(m, key, make, "", 1.0, Vector3.ZERO, Basis.IDENTITY, "plastic", c, 0.2)
	var s_end := PI - 0.4
	var s_start := 0.98 if style != 2 else 1.05
	match mark:
		1:
			put.call("mk_stripe", M.slab.bind(mer, s_start, s_end, -0.075, 0.075, 28, 3, 0.0006, 0.0018, 0.0), paint)
		2:
			for w in [-0.12, 0.12]:
				put.call("mk_twin%.2f" % w, M.slab.bind(mer, s_start, s_end, w - 0.032, w + 0.032, 28, 2, 0.0006, 0.0018, 0.0), paint)
		3:
			for s in [-1.0, 1.0]:
				var az: float = s * PI / 2.0
				put.call("mk_disc%d" % int(s), M.slab.bind(ef, az - 0.28, az + 0.28, 0.24, 0.72, 8, 8, 0.0006, 0.0016, 0.5), Color(0.95, 0.95, 0.92) if paint.r < 0.9 else Color(0.8, 0.1, 0.08))
				put.call("mk_cv%d" % int(s), M.slab.bind(ef, az - 0.065, az + 0.065, 0.31, 0.65, 3, 8, 0.0016, 0.0016, 0.0), paint)
				put.call("mk_ch%d" % int(s), M.slab.bind(ef, az - 0.2, az + 0.2, 0.44, 0.52, 8, 3, 0.0016, 0.0016, 0.0), paint)
		4, 8:   # a band of squares round the back and sides (black and yellow: hazard)
			var cols := [paint, hc] if mark == 4 else [Color(0.1, 0.1, 0.1), Color(0.95, 0.78, 0.12)]
			var k := 0
			var az := WIN[0] + 0.12
			while az < TAU - WIN[0] - 0.12 - 0.05:
				put.call("mk_sq%d" % (k % 2), M.slab.bind(ef, az, az + 0.18, 0.06, 0.2, 3, 3, 0.0006, 0.0018, 0.0), cols[k % 2])
				az += 0.18
				k += 1
		5:
			for s in [-1.0, 1.0]:
				var l := Label3D.new()
				l.text = "%02d" % (absi(who.hash()) % 90 + 10)
				l.font_size = 48
				l.pixel_size = 0.0011
				l.modulate = paint
				l.outline_size = 0
				l.double_sided = false
				l.shaded = true
				m.add_child(l)
				var az2: float = s * PI / 2.0
				l.position = helm_pt(az2, 0.36, 1.012)
				l.basis = _facing(-helm_n(az2, 0.36))
		6:   # a chevron on the back, pointing up
			for s in [-1.0, 1.0]:
				for k in 6:
					var t := k / 6.0
					var az3: float = PI + s * (0.05 + t * 0.55)
					var el := 0.62 - t * 0.42
					put.call("mk_chev", M.slab.bind(ef, az3 - 0.06, az3 + 0.06, el - 0.05, el + 0.05, 3, 3, 0.0006, 0.0018, 0.0), paint)
		7:   # a solid band round the back and sides
			put.call("mk_band", M.slab.bind(ef, WIN[0] + 0.1, TAU - WIN[0] - 0.1, 0.08, 0.17, 40, 2, 0.0006, 0.0018, 0.0), paint)


# --- the back and the chest --------------------------------------------------------------------------------

## A shoulder strap's path on the torso: up the chest at `uf`, over the shoulder, down the back.
static func _strap_path(side: float, lift: float, down_to := 0.06) -> Array:
	var pts := []
	var uf := FRONT - side * 0.62
	var ub := BACK + side * 0.62 + (TAU if side < 0.0 else 0.0)   # (round over its own shoulder: through +x on the right, -x on the left)
	for k in 8:
		pts.append(M.on_trunk(TOR, uf, lerpf(down_to, 0.4, k / 7.0), lift))
	for k in range(1, 8):
		var u := uf + (ub - uf) * k / 8.0
		pts.append(M.on_trunk(TOR, u, 0.43, lift + 0.004))
	for k in 6:
		pts.append(M.on_trunk(TOR, ub, lerpf(0.4, 0.3, k / 5.0), lift))
	return pts


static func _strap_ups(path: Array) -> Array:
	var ups := []
	for p: Vector3 in path:
		var c := Vector3(0, p.y, M.section(TOR, p.y)[2])
		ups.append((p - c).normalized())
	return ups


## What's on the back: a rucksack, air tanks, a tool pack, a radio pack, or only the harness.
static func _pack(n: Node3D, pack: int) -> void:
	if pack != 4:   # shoulder straps and the sternum strap (every pack has them)
		for s in [-1.0, 1.0]:
			var path := _strap_path(s, 0.007)
			_put(n, "strap%d" % s, M.tube.bind(path, 0.007, 8, 0.044, _strap_ups(path)), "webbing", 0.9)
			_rb(n, Vector3(0.05, 0.03, 0.012), 0.004, M.on_trunk(TOR, FRONT - s * 0.62, 0.2, 0.016), "", 1.0, _facing(-M.trunk_normal(TOR, FRONT - s * 0.62, 0.2)), "metal", Color(0.3, 0.3, 0.3))
		var st := []
		for k in 9:
			st.append(M.on_trunk(TOR, FRONT - 0.62 + 1.24 * k / 8.0, 0.29, 0.016))
		_put(n, "sternum", M.tube.bind(st, 0.005, 8, 0.022, _strap_ups(st)), "webbing", 0.8)
		_rb(n, Vector3(0.032, 0.024, 0.012), 0.004, M.on_trunk(TOR, FRONT, 0.29, 0.022), "", 1.0, Basis.IDENTITY, "plastic", Color(0.15, 0.15, 0.15))
	match pack:
		0:   # a rucksack: the bag, its lid, a front pocket, side pockets, a mat rolled under it
			_rb(n, Vector3(0.28, 0.34, 0.13), 0.04, Vector3(0, 0.255, 0.18), "webbing", 1.0)
			_rb(n, Vector3(0.29, 0.075, 0.15), 0.03, Vector3(0, 0.425, 0.182), "webbing", 0.86, Basis(Vector3.RIGHT, 0.08))
			_rb(n, Vector3(0.19, 0.15, 0.045), 0.02, Vector3(0, 0.21, 0.25), "webbing", 0.92)
			for s in [-1.0, 1.0]:
				_rb(n, Vector3(0.045, 0.15, 0.095), 0.016, Vector3(s * 0.15, 0.2, 0.18), "webbing", 0.9)
				_rb(n, Vector3(0.018, 0.2, 0.006), 0.003, Vector3(s * 0.06, 0.29, 0.247), "", 1.0, Basis.IDENTITY, "leather", Color(0.5, 0.38, 0.27))
				_rb(n, Vector3(0.026, 0.02, 0.008), 0.003, Vector3(s * 0.06, 0.39, 0.25), "", 1.0, Basis.IDENTITY, "metal", Color(0.6, 0.58, 0.55))
			_put(n, "mat", M.lathe.bind([[-0.15, 0.002], [-0.148, 0.04], [-0.14, 0.048], [0.14, 0.048], [0.148, 0.04], [0.15, 0.002]], 18), "", 1.0, Vector3(0, 0.05, 0.2), Basis(Vector3(0, 0, 1), PI / 2.0), "canvas", Color(0.36, 0.42, 0.5), 0.3)
			for s in [-1.0, 1.0]:
				_put(n, "matstrap", M.lathe.bind([[-0.009, 0.05], [0.009, 0.05]], 18), "", 1.0, Vector3(s * 0.08, 0.05, 0.2), Basis(Vector3(0, 0, 1), PI / 2.0), "leather", Color(0.45, 0.34, 0.25), 0.2)
		1:   # twin air tanks on a backplate, valves up top, a hose round to the chest
			_rb(n, Vector3(0.24, 0.4, 0.02), 0.008, Vector3(0, 0.25, 0.122), "", 1.0, Basis.IDENTITY, "metal", Color(0.3, 0.3, 0.32))
			for s in [-1.0, 1.0]:
				var at := Vector3(s * 0.062, 0.05, 0.19)
				_put(n, "tank", M.limb.bind(0.36, 0.057, 0.057, 1.0, 22, 24), "", 1.0, at + Vector3(0, 0.38, 0), Basis.IDENTITY, "metal", Color(0.75, 0.75, 0.78), 0.4)
				for y in [0.12, 0.3]:
					_put(n, "tankband", M.lathe.bind([[-0.011, 0.0585], [0.011, 0.0585]], 22), "", 1.0, at + Vector3(0, y, 0), Basis.IDENTITY, "metal", Color(0.25, 0.25, 0.25), 0.2)
				_put(n, "valve", M.lathe.bind([[0.0, 0.02], [0.03, 0.018], [0.04, 0.012], [0.06, 0.012]], 12), "", 1.0, at + Vector3(0, 0.43, 0), Basis.IDENTITY, "brass", Color.WHITE, 0.2)
				_put(n, "knob", M.lathe.bind([[0.0, 0.02], [0.01, 0.02]], 14), "", 1.0, at + Vector3(0, 0.49, 0), Basis.IDENTITY, "plastic", Color(0.15, 0.15, 0.15), 0.2)
			var hose := [Vector3(0.062, 0.5, 0.19), Vector3(0.12, 0.54, 0.12), Vector3(0.2, 0.48, 0.0), Vector3(0.17, 0.38, -0.1), Vector3(0.11, 0.25, -0.135)]
			_put(n, "hose", M.tube.bind(hose, 0.011, 10), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "rubber", Color(0.25, 0.25, 0.25), 0.2)
			_rb(n, Vector3(0.05, 0.05, 0.03), 0.012, M.on_trunk(TOR, FRONT - 0.45, 0.24, 0.02), "", 1.0, Basis.IDENTITY, "metal", Color(0.3, 0.3, 0.32))
		2:   # a tool pack: a flat bag with handles out of the top, a rope coiled under it
			_rb(n, Vector3(0.28, 0.3, 0.085), 0.025, Vector3(0, 0.25, 0.165), "webbing", 0.85)
			_rb(n, Vector3(0.26, 0.12, 0.02), 0.01, Vector3(0, 0.22, 0.212), "webbing", 0.75)
			_put(n, "hammer", M.limb.bind(0.2, 0.012, 0.012, 1.0, 10, 10), "", 1.0, Vector3(-0.08, 0.5, 0.17), Basis(Vector3(0, 0, 1), 0.12), "wood", Color(0.7, 0.55, 0.38), 0.2)
			_rb(n, Vector3(0.08, 0.03, 0.025), 0.006, Vector3(-0.086, 0.52, 0.17), "", 1.0, Basis(Vector3(0, 0, 1), 0.12), "metal", Color(0.35, 0.35, 0.37))
			_rb(n, Vector3(0.02, 0.17, 0.008), 0.004, Vector3(0.0, 0.43, 0.175), "", 1.0, Basis(Vector3(0, 0, 1), -0.05), "metal", Color(0.65, 0.65, 0.68))   # a wrench
			_put(n, "wrenchjaw", M.lathe.bind([[0.0, 0.02], [0.01, 0.02]], 10), "", 1.0, Vector3(0.004, 0.52, 0.175), Basis(Vector3.RIGHT, PI / 2.0), "metal", Color(0.65, 0.65, 0.68), 0.2)
			for k in 2:
				_put(n, "driver%d" % k, M.limb.bind(0.07, 0.011, 0.01, 1.0, 10, 8), "", 1.0, Vector3(0.06 + k * 0.035, 0.46, 0.17), Basis.IDENTITY, "plastic", [Color(0.85, 0.15, 0.1), Color(0.95, 0.75, 0.12)][k], 0.2)
			var coil := A.ring(n, 0.07, 0.05, Vector3(0, 0.065, 0.19), "canvas", Color(0.75, 0.68, 0.48), Vector3(PI / 2.0, 0, 0))
			coil.scale = Vector3(1.6, 1.0, 1.0)
		3:   # a radio pack: the set with its dials on top, a whip aerial, the handset on a coiled cord
			_rb(n, Vector3(0.26, 0.32, 0.12), 0.02, Vector3(0, 0.26, 0.175), "", 1.0, Basis.IDENTITY, "metal", Color(0.33, 0.36, 0.28))
			_rb(n, Vector3(0.22, 0.012, 0.09), 0.004, Vector3(0, 0.424, 0.175), "", 1.0, Basis.IDENTITY, "metal", Color(0.2, 0.22, 0.18))
			for k in 3:
				_put(n, "dial%d" % k, M.lathe.bind([[0.0, 0.014], [0.014, 0.014], [0.018, 0.009]], 14), "", 1.0, Vector3(-0.06 + k * 0.05, 0.43, 0.17), Basis.IDENTITY, "plastic", Color(0.12, 0.12, 0.12), 0.2)
			var whip := []
			for k in 9:
				whip.append(Vector3(-0.1 + k * 0.004, 0.43 + k * 0.075, 0.2 + k * k * 0.0012))
			_put(n, "whip", M.tube.bind(whip, 0.0035, 6), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "metal", Color(0.2, 0.2, 0.2), 0.2)
			var cord := []
			for k in 40:   # coiled cord over the left shoulder to the handset
				var t := k / 39.0
				var base := Vector3(-0.12, 0.42, 0.14).lerp(Vector3(-0.16, 0.48, -0.02), t)
				cord.append(base + Vector3(cos(k * 1.4) * 0.008, sin(k * 1.4) * 0.008, 0))
			_put(n, "cord", M.tube.bind(cord, 0.0025, 5), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "rubber", Color(0.15, 0.15, 0.15), 0.2)
			var hn := M.trunk_normal(TOR, FRONT + 0.75, 0.38)
			_rb(n, Vector3(0.045, 0.15, 0.035), 0.014, M.on_trunk(TOR, FRONT + 0.75, 0.36, 0.03), "", 1.0, _facing(-hn), "plastic", Color(0.15, 0.15, 0.15))


## What's on the chest: a radio, a chest lamp, an ID badge, a knife, or nothing.
static func _chest(n: Node3D, chest: int, pack: int) -> void:
	var u := FRONT + 0.62   # (the left strap, or where it'd be)
	var nrm := M.trunk_normal(TOR, u, 0.33)
	var b := _facing(-nrm)
	var lift := 0.02 if pack != 4 else 0.012
	match chest:
		0:   # the radio, clipped to the left strap: antenna, a knob, the light
			var p := M.on_trunk(TOR, u, 0.33, lift + 0.016)
			_rb(n, Vector3(0.056, 0.09, 0.03), 0.009, p, "", 1.0, b, "rubber", Color(0.85, 0.85, 0.85))
			_rb(n, Vector3(0.04, 0.028, 0.004), 0.002, p + b * Vector3(0, 0.022, -0.016), "", 1.0, b, "plastic", Color(0.25, 0.3, 0.28))
			_put(n, "aerial", M.limb.bind(0.07, 0.0045, 0.0035, 1.0, 8, 8), "", 1.0, p + b * Vector3(-0.016, 0.115, 0.0), b, "rubber", Color(0.6, 0.6, 0.6), 0.2)
			_put(n, "knob", M.lathe.bind([[0.0, 0.007], [0.012, 0.007]], 10), "", 1.0, p + b * Vector3(0.012, 0.045, 0.0), b, "plastic", Color(0.12, 0.12, 0.12), 0.2)
			A.sphere(n, 0.004, p + b * Vector3(0.0, 0.045, -0.012), "metal", Color(0.9, 0.2, 0.1), 2.0)
		1:   # a chest lamp on the sternum
			var p2 := M.on_trunk(TOR, FRONT, 0.33, 0.012)
			_rb(n, Vector3(0.06, 0.05, 0.016), 0.008, p2, "", 1.0, Basis.IDENTITY, "plastic", Color(0.18, 0.18, 0.18))
			_put(n, "clamp", M.lathe.bind([[0.0, 0.022], [0.03, 0.024], [0.038, 0.026], [0.042, 0.025]], 16), "", 1.0, p2 + Vector3(0, 0, -0.008), Basis(Vector3.RIGHT, -PI / 2.0), "metal", Color(0.85, 0.65, 0.12), 0.2)
			_put(n, "clens", M.lathe.bind([[0.0, 0.021], [0.003, 0.02]], 16), "", 1.0, p2 + Vector3(0, 0, -0.049), Basis(Vector3.RIGHT, -PI / 2.0), "metal", Color(0.9, 0.9, 0.82), 0.2)
		2:   # an ID badge in a holder on a clip
			var p3 := M.on_trunk(TOR, FRONT + 0.4, 0.27, 0.014)
			var nb := _facing(-M.trunk_normal(TOR, FRONT + 0.4, 0.27))
			_rb(n, Vector3(0.056, 0.078, 0.004), 0.004, p3, "", 1.0, nb, "plastic", Color(0.92, 0.92, 0.9))
			_rb(n, Vector3(0.018, 0.024, 0.002), 0.001, p3 + nb * Vector3(-0.012, 0.012, -0.003), "", 1.0, nb, "canvas", Color(0.3, 0.32, 0.36))
			_rb(n, Vector3(0.03, 0.006, 0.002), 0.001, p3 + nb * Vector3(0.01, 0.018, -0.003), "", 1.0, nb, "plastic", Color(0.15, 0.15, 0.15))
			_rb(n, Vector3(0.03, 0.006, 0.002), 0.001, p3 + nb * Vector3(0.01, 0.008, -0.003), "", 1.0, nb, "plastic", Color(0.15, 0.15, 0.15))
			_rb(n, Vector3(0.056, 0.012, 0.004), 0.002, p3 + nb * Vector3(0, -0.03, -0.0025), "", 1.0, nb, "plastic", Color(0.85, 0.35, 0.1))
			_rb(n, Vector3(0.014, 0.02, 0.006), 0.002, p3 + nb * Vector3(0, 0.048, 0.0), "", 1.0, nb, "metal", Color(0.7, 0.7, 0.72))
		3:   # a knife in its sheath, upside down on the left strap
			var p4 := M.on_trunk(TOR, u, 0.28, lift + 0.012)
			_rb(n, Vector3(0.034, 0.13, 0.014), 0.006, p4, "", 1.0, b * Basis(Vector3(0, 0, 1), 0.25), "leather", Color(0.32, 0.24, 0.18))
			_put(n, "handle", M.limb.bind(0.06, 0.011, 0.012, 0.9, 12, 10), "", 1.0, p4 + b * Basis(Vector3(0, 0, 1), 0.25) * Vector3(0, -0.06, -0.004), b * Basis(Vector3(0, 0, 1), 0.25), "rubber", Color(0.25, 0.25, 0.25), 0.2)


## Your name, on a patch on the pack (or between the shoulders, with nothing on your back).
static func _name_patch(n: Node3D, who: String, pack: int) -> void:
	if who == "":
		return
	var tu := FRONT - 0.4   # on the chest's name tape too
	var tl := Label3D.new()
	var tt := who.to_upper().left(10)
	tl.text = tt
	tl.font_size = 32
	tl.pixel_size = minf(0.0006, 0.07 / (maxf(tt.length(), 4) * 19.0))
	tl.modulate = Color(0.1, 0.09, 0.08)
	tl.outline_size = 0
	tl.double_sided = false
	tl.shaded = true
	n.add_child(tl)
	var tn := M.trunk_normal(TOR, tu, 0.3725)
	tl.position = M.on_trunk(TOR, tu, 0.3725, 0.0062)
	tl.basis = _facing(-tn)
	var at: Vector3
	var b := Basis.IDENTITY
	match pack:
		0: at = Vector3(0, 0.255, 0.2735)
		1:
			at = M.on_trunk(TOR, BACK, -0.04, 0.003)   # (below the tanks)
			b = _facing(M.trunk_normal(TOR, BACK, -0.04) * -1.0)
		2: at = Vector3(0, 0.33, 0.2085)
		3: at = Vector3(0, 0.3, 0.2355)
		_:
			at = M.on_trunk(TOR, BACK, 0.3, 0.003)
			b = _facing(M.trunk_normal(TOR, BACK, 0.3) * -1.0)
	_rb(n, Vector3(0.124, 0.036, 0.004), 0.003, at, "", 1.0, b, "canvas", Color(0.95, 0.92, 0.82))
	var l := Label3D.new()
	var t := who.to_upper().left(12)
	l.text = t
	l.font_size = 32
	l.pixel_size = minf(0.0009, 0.11 / (maxf(t.length(), 4) * 19.0))
	l.modulate = Color(0.1, 0.09, 0.08)
	l.outline_size = 0
	l.double_sided = false
	l.shaded = true
	n.add_child(l)
	l.position = at + b * Vector3(0, 0, 0.0025)
	l.basis = b


# --- what other code puts on the suit ------------------------------------------------------------------------

## ARMORED_SUIT: steel plates strapped over the coverall (chest, belly, shoulders, shins), each one
## shaped to what it covers.
static func set_armor(root: Node, on: bool) -> void:
	var old := root.find_child("Armor*", true, false)
	while old != null:
		old.get_parent().remove_child(old)
		old.free()
		old = root.find_child("Armor*", true, false)
	if not on:
		return
	var steel := Color(0.7, 0.72, 0.74)
	var pieces := {
		"torso": [[M.trunk_fn(TOR), FRONT - 0.85, FRONT + 0.85, 0.16, 0.34, 0.022], [M.trunk_fn(TOR), FRONT - 0.7, FRONT + 0.7, 0.02, 0.145, 0.02]],
		"upper_arm_l": [[M.ellipsoid_fn(Vector3.ZERO, Vector3(0.074, 0.074, 0.074)), -PI / 2.0 - 1.2, -PI / 2.0 + 1.2, -0.5, 1.2, 0.012]],
		"upper_arm_r": [[M.ellipsoid_fn(Vector3.ZERO, Vector3(0.074, 0.074, 0.074)), PI / 2.0 - 1.2, PI / 2.0 + 1.2, -0.5, 1.2, 0.012]],
		"shin_l": [[M.limb_fn(SHANK[0], SHANK[1], SHANK[2], SHANK[3]), FRONT - 0.75, FRONT + 0.75, 0.07, 0.27, 0.012]],
		"shin_r": [[M.limb_fn(SHANK[0], SHANK[1], SHANK[2], SHANK[3]), FRONT - 0.75, FRONT + 0.75, 0.07, 0.27, 0.012]],
	}
	for pname in pieces:
		var host := root.find_child(pname, true, false) as Node3D
		if host == null:
			continue
		var a := Node3D.new()
		a.name = "Armor_" + pname
		host.add_child(a)
		var k := 0
		for spec in pieces[pname]:
			var lift: float = spec[5]
			_put(a, "armor%s%d" % [pname, k], M.slab.bind(spec[0], spec[1], spec[2], spec[3], spec[4], 12, 10, lift, 0.008, 0.2), "", 1.0, Vector3.ZERO, Basis.IDENTITY, "metal", steel, 0.3)
			for cu in [0.15, 0.85]:   # rivets near the corners
				for cv in [0.15, 0.85]:
					var s: Array = spec[0].call(lerpf(spec[1], spec[2], cu), lerpf(spec[3], spec[4], cv))
					A.sphere(a, 0.006, s[0] + (s[1] as Vector3) * (lift + 0.008), "metal", Color(0.5, 0.52, 0.55))
			k += 1


## The headlamp on the helmet, lit or dark: the lens glows and throws a soft glow round it.
static func set_headlamp(root: Node, on: bool) -> void:
	var lens := root.find_child("HeadlampLens", true, false) as Node3D
	if lens == null:
		return
	var mi: MeshInstance3D = lens if lens is MeshInstance3D else lens.find_children("*", "MeshInstance3D", true, false)[0]
	if not mi.has_meta("lit_mat"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.97, 0.85)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.95, 0.8)
		m.emission_energy_multiplier = 8.0
		mi.set_meta("lit_mat", m)
		mi.set_meta("dark_mat", mi.material_override)
	mi.material_override = mi.get_meta("lit_mat") if on else mi.get_meta("dark_mat")
	var glow := lens.get_node_or_null("Glow") as OmniLight3D
	if glow == null:
		glow = OmniLight3D.new()
		glow.name = "Glow"
		glow.light_color = Color(1.0, 0.95, 0.8)
		glow.light_energy = 0.6
		glow.omni_range = 0.8
		lens.add_child(glow)
		glow.position = Vector3(0, 0.05, 0)
	glow.visible = on


## What a body holds, the way a crewmate's puppet holds it (the camera-feed and photo suit of your
## own player uses this): the item in the right fist, or both hands for the shotgun, the axe and
## heavy things, or a body over the shoulder. `layer` (0 = keep) is applied to what it adds.
static func set_held(root: Node, parts: Dictionary, id: String, layer := 0) -> void:
	var Data = load("res://src/data.gd")   # (loaded here: items.gd preloads this file)
	var Items = load("res://src/items.gd")
	var old := root.find_child("HeldItem", true, false)
	if old != null:
		old.get_parent().remove_child(old)
		old.free()
	var ur := Vector3(0.06, 0, 0.1)
	var fr := Vector3(0.28, 0, -0.05)
	var ul := Vector3(0.06, 0, -0.1)
	var fl := Vector3(0.28, 0, 0.05)
	if id != "" and Data.ITEMS.has(id):
		var held: Node3D
		var heavy: bool = Data.ITEMS[id].get("heavy", false)
		if Data.ITEMS[id].get("kind", "") == "remains":
			held = Node3D.new()
			parts.torso.add_child(held)
			held.position = Vector3(0.17, 0.52, 0.02)
			carried(held)
			ur = Vector3(1.05, 0, -0.35)
			fr = Vector3(1.7, 0, 0)
		else:
			held = Items.build(id)
			var size: Vector3 = Data.ITEMS[id].size
			if heavy:
				parts.torso.add_child(held)
				held.position = Vector3(0, -0.1 - size.y * 0.25, -0.16 - size.z * 0.5)
				ur = Vector3(0.95, 0, -0.2)
				fr = Vector3(0.9, 0, 0)
				ul = Vector3(0.95, 0, 0.2)
				fl = Vector3(0.9, 0, 0)
			else:
				parts.forearm_r.add_child(held)
				var fist := Vector3(-0.012, -0.32, -0.02)
				held.basis = Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)) * Basis.from_scale(held.scale)
				held.position = fist + Vector3(0, {"SHOTGUN": -0.14, "FIRE_AXE": -0.36, "CROWBAR": -0.2, "FLASHLIGHT": -0.06}.get(id, 0.0), 0)
				if id == "FLASHLIGHT":
					held.rotate_object_local(Vector3.UP, PI)
				ur = Vector3(0.9, 0, 0)
				fr = Vector3(0.5, 0, 0)
				if id in ["SHOTGUN", "FIRE_AXE"]:
					ur = Vector3(0.75, 0, 0.1)
					fr = Vector3(1.0, 0, 0)
					ul = Vector3(1.25, 0, 0.55)
					fl = Vector3(0.35, 0, 0.3)
		held.name = "HeldItem"
		if layer != 0:
			for mi: MeshInstance3D in held.find_children("*", "MeshInstance3D", true, false):
				mi.layers = layer
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parts.upper_arm_r.rotation = ur
	parts.forearm_r.rotation = fr
	parts.upper_arm_l.rotation = ul
	parts.forearm_l.rotation = fl


## NIGHT_VISION: a twin-tube goggle on a hinged mount on the helmet's brow (flipped up out of the
## way when it's off, down over the visor when it's on).
static func set_goggles(root: Node, owned: bool, down := false) -> void:
	var old := root.find_child("Goggles", true, false)
	if old != null:
		old.get_parent().remove_child(old)
		old.free()
	if not owned:
		return
	var head := root.find_child("head", true, false) as Node3D
	if head == null:
		return
	var mount := Node3D.new()
	mount.name = "Goggles"
	head.add_child(mount)
	var el := WIN[1] + WIN[2] + 0.07   # (just over the window)
	mount.position = helm_pt(0.0, el, 1.02)
	mount.rotation.x = 0.0 if down else -1.35
	var dark := Color(0.13, 0.14, 0.13)
	_rb(mount, Vector3(0.05, 0.026, 0.03), 0.006, Vector3(0, 0, -0.008), "", 1.0, Basis.IDENTITY, "metal", dark)   # hinge block
	_rb(mount, Vector3(0.026, 0.07, 0.016), 0.005, Vector3(0, -0.04, -0.03), "", 1.0, Basis(Vector3.RIGHT, 0.4), "metal", dark)   # arm
	_rb(mount, Vector3(0.13, 0.036, 0.04), 0.01, Vector3(0, -0.075, -0.06), "", 1.0, Basis.IDENTITY, "metal", dark)   # bridge
	for s in [-1.0, 1.0]:
		_put(mount, "nvtube", M.lathe.bind([[0.0, 0.024], [0.06, 0.026], [0.07, 0.028], [0.074, 0.027]], 16), "", 1.0, Vector3(s * 0.038, -0.075, -0.07), Basis(Vector3.RIGHT, -PI / 2.0), "metal", dark, 0.2)
		_put(mount, "nvlens", M.lathe.bind([[0.0, 0.021], [0.002, 0.02]], 16), "", 1.0, Vector3(s * 0.038, -0.075, -0.145), Basis(Vector3.RIGHT, -PI / 2.0), "glow", Color(0.3, 0.9, 0.4), 0.2)


# --- grime: mud, snow, wet, blood -----------------------------------------------------------------------

## Drawn over every piece of the suit (material_overlay), one material per figure so each has its own:
## mud climbing from the boots (splashed, higher the muddier), snow settled on whatever faces up and
## crusted round the boots, the whole suit darkened and glossy when wet, blood spattered over the
## front. Heights are the standing pose's (`row`: each mesh's own row of its transform to the feet,
## set once), so the mud stays on the cloth however the body bends.
const GRIME := """shader_type spatial;
render_mode blend_mix, depth_draw_never, specular_schlick_ggx;
uniform vec4 amount = vec4(0.0);   // mud, snow, wet, blood (0..1)
// (colours here are linear: a mud that reads dark brown is a few hundredths)
instance uniform vec4 row = vec4(0.0, 1.0, 0.0, 0.0);   // the standing pose's height of a local point: dot(row.xyz, v) + row.w
varying float h;
varying vec3 lp;
varying vec3 wn;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	h = dot(row.xyz, VERTEX) + row.w;
	lp = VERTEX + vec3(row.w * 7.0);
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float n1 = noise(lp * 38.0);
	float n2 = noise(lp * 110.0);
	float mud = amount.x, snow = amount.y, wet = amount.z, blood = amount.w;
	// Mud: solid on the boots, splashed up the legs as it builds.
	float line = mix(0.0, 0.75, mud) + (n1 - 0.5) * 0.18;
	float m_mud = (1.0 - smoothstep(line - 0.06, line + 0.02, h)) * step(0.02, mud);
	m_mud = max(m_mud, step(0.82, n2 + mud * 0.25 - h * 0.35) * step(0.05, mud) * (1.0 - smoothstep(0.3, 1.1, h)));   // splashes
	// Snow: on what faces up, and crusted round the boots.
	float up = smoothstep(0.35, 0.85, wn.y);
	float m_snow = clamp(up * smoothstep(0.25, 0.7, n1 + snow * 0.6) * smoothstep(0.0, 0.3, snow), 0.0, 1.0);
	m_snow = max(m_snow, (1.0 - smoothstep(0.06, 0.16 + snow * 0.12, h + (n2 - 0.5) * 0.05)) * smoothstep(0.1, 0.5, snow));
	// Blood: spatter over the front and the arms, more as it builds.
	float front = smoothstep(0.75, 1.0, h) * (1.0 - smoothstep(1.55, 1.7, h));
	float m_blood = step(1.0 - blood * 0.45, n1 * 0.6 + n2 * 0.5) * front * step(0.02, blood);
	vec3 col = vec3(0.0);
	float a = 0.0;
	float rough = 0.6;
	if (wet > 0.01) { a = wet * 0.55; col = vec3(0.0); rough = mix(0.6, 0.1, wet); }   // darker, and it shines
	if (m_snow > 0.01) { col = mix(col, vec3(0.85, 0.88, 0.95), m_snow); a = max(a, m_snow * 0.95); rough = mix(rough, 0.85, m_snow); }
	if (m_mud > 0.01) { col = mix(col, mix(vec3(0.045, 0.028, 0.015), vec3(0.085, 0.055, 0.03), n2), m_mud); a = max(a, m_mud * 0.92); rough = mix(rough, 0.9 - wet * 0.5, m_mud); }
	if (m_blood > 0.01) { col = mix(col, vec3(0.13, 0.004, 0.004), m_blood); a = max(a, m_blood * 0.9); rough = mix(rough, 0.3, m_blood); }
	ALBEDO = col;
	ALPHA = a;
	ROUGHNESS = rough;
}
"""

static var _grime_shader: Shader


## Put grime on a suit built under `root`: `g` is (mud, snow, wet, blood), each 0..1. Sets every
## piece up the first time (its overlay and its height row); after that it only moves the numbers.
static func set_grime(root: Node, g: Color) -> void:
	var mat: ShaderMaterial = root.get_meta("grime_mat", null) if root.has_meta("grime_mat") else null
	if mat == null:
		if g.r + g.g + g.b + g.a < 0.001:
			return   # (clean: nothing to set up yet)
		if _grime_shader == null:
			_grime_shader = Shader.new()
			_grime_shader.code = GRIME
		mat = ShaderMaterial.new()
		mat.shader = _grime_shader
		root.set_meta("grime_mat", mat)
	if not root.has_meta("grime_n") or int(root.get_meta("grime_n")) != _mesh_count(root):
		_grime_rows(root, mat)
	mat.set_shader_parameter("amount", Vector4(g.r, g.g, g.b, g.a))


static func _mesh_count(root: Node) -> int:
	return root.find_children("*", "MeshInstance3D", true, false).size()


## Each mesh's row: how high (in the standing pose, from the feet) a point of it is.
static func _grime_rows(root: Node, mat: ShaderMaterial) -> void:
	var n := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		n += 1
		if _held(mi, root) or mi.name == "VisorCracks" or mi.name == "Visor" or mi.name == "HeadlampLens":
			continue
		var part := mi.get_parent()   # the part it belongs to
		while part != null and part != root and not PARTS.has(String(part.name)):
			part = part.get_parent()
		if part == null or part == root:
			continue
		var t: Transform3D = (part as Node3D).global_transform.affine_inverse() * mi.global_transform   # mesh -> part
		var y0: float = (PARTS[String(part.name)][1] as Vector3).y   # the part's joint, standing
		mi.material_overlay = mat
		mi.set_instance_shader_parameter("row", Vector4(t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y + y0))
	root.set_meta("grime_n", n)


## Vapour coming off a suit in the cold, `rate` 0 (none) to about 1 (working hard): faint wisps
## rising off the shoulders and the helmet. `layer` (0 = keep) for the puffs.
static func set_vapour(root: Node, rate: float, layer := 0) -> void:
	var torso := root.find_child("torso", true, false) as Node3D
	if torso == null:
		return
	var v := torso.get_node_or_null("Vapour") as GPUParticles3D
	if v == null:
		if rate <= 0.0:
			return
		v = GPUParticles3D.new()
		v.name = "Vapour"
		v.amount = 24
		v.lifetime = 2.2
		v.local_coords = false
		var m := ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(0.16, 0.04, 0.08)
		m.direction = Vector3.UP
		m.spread = 12.0
		m.initial_velocity_min = 0.15
		m.initial_velocity_max = 0.35
		m.gravity = Vector3(0, 0.12, 0)
		m.damping_min = 0.2
		m.damping_max = 0.4
		m.scale_min = 0.12
		m.scale_max = 0.2
		var grow := Curve.new()
		grow.max_value = 3.0
		grow.add_point(Vector2(0, 1.0))
		grow.add_point(Vector2(1, 3.0))
		var gt := CurveTexture.new()
		gt.curve = grow
		m.scale_curve = gt
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.0))
		g.add_point(0.2, Color(1, 1, 1, 0.18))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
		var rt := GradientTexture1D.new()
		rt.gradient = g
		m.color_ramp = rt
		v.process_material = m
		load("res://src/blast.gd")._puff_material(v, false)
		((v.draw_pass_1 as QuadMesh).material as StandardMaterial3D).billboard_keep_scale = true
		v.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
		torso.add_child(v)
		v.position = Vector3(0, 0.44, 0.0)
		if layer != 0:
			v.layers = layer
	v.emitting = rate > 0.0
	v.amount_ratio = clampf(rate, 0.05, 1.0)


## Crack the visor of a suit built under `root` (0 = whole again).
static func set_cracks(root: Node, tier: int) -> void:
	var crack := root.find_child("VisorCracks", true, false) as MeshInstance3D
	if crack == null:
		return
	crack.visible = tier > 0
	if tier <= 0:
		return
	var m := Cracks.visor_material(tier)   # projected straight on from the front: cracks across the glass
	m.set_shader_parameter("centre", Vector2(0.0, HELM_C.y + sin(WIN[1]) * HELM_R.y))
	m.set_shader_parameter("scale", 0.5 / (sin(WIN[0]) * HELM_R.x + 0.02))
	crack.material_override = m
