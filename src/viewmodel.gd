# First-person arm: orange suit sleeve running off-screen to the elbow, gloved fist wrapped around
# whatever you're holding (a real flashlight / lantern model, or the item's shape for scrap).
# Built at real scale on `rig`, then shrunk to half size at half the distance: it looks the same
# on screen but sits inside the player capsule, so it never pokes through walls.
extends Node3D

const A = preload("res://src/art.gd")
const Data = preload("res://src/data.gd")
const Items = preload("res://src/items.gd")
const Pickup = preload("res://src/pickup.gd")
const Suit = preload("res://src/suit.gd")

const SUIT := Color(1, 1, 1)
const HAND := Vector3(0.25, -0.26, -0.54)     # fist position in camera space (full scale)
const ELBOW := Vector3(0.2, -0.32, 0.42)     # elbow in grip space: down, right and behind, off-screen

const LAYER := 2   # render layer for the first-person model (lights can skip it)

var rig: Node3D
var grip: Node3D
var item: Node3D
var _lens_mat: StandardMaterial3D
var _id := "-"
var _muzzle: OmniLight3D
var _inspect := false
var _pose_tw: Tween
var _sleeve: Node3D   # the forearm, rebuilt per item (its angle depends on what you're holding)
var _rest_grip := [HAND, Vector3(0.06, 0.14, -0.08)]   # this item's resting fist pose
var _carry: Node3D    # a body over your shoulder


func _ready() -> void:
	rig = Node3D.new()
	add_child(rig)
	rig.scale = Vector3.ONE * 0.5
	grip = Node3D.new()
	rig.add_child(grip)
	grip.position = HAND
	grip.rotation = Vector3(0.06, 0.14, -0.08)
	_fist()
	_arm(ELBOW)
	item = Node3D.new()
	grip.add_child(item)
	_lens_mat = StandardMaterial3D.new()
	_lens_mat.albedo_color = Color(0.9, 0.88, 0.75)
	_lens_mat.emission_enabled = true
	_lens_mat.emission = Color(1, 0.92, 0.7)


func set_item(id: String, extra := {}) -> void:
	if id == _id:
		return
	_id = id
	_inspect = false
	grip.position = HAND
	grip.rotation = Vector3(0.06, 0.14, -0.08)
	rig.rotation = Vector3.ZERO
	item.rotation = Vector3.ZERO
	_muzzle = null
	for c in item.get_children():
		c.queue_free()
	if _carry:
		_carry.queue_free()
		_carry = null
	grip.visible = true
	visible = id != ""
	if id == "":
		return
	grip.position = HAND + (Vector3(-0.03, 0.2, 0.02) if id == "LANTERN" else Vector3.ZERO)
	if id in ["CROWBAR", "FIRE_AXE", "SHOTGUN"] or _sleeve.get_meta("elbow", ELBOW) != ELBOW:
		_arm(ELBOW)
	match id:
		"FLASHLIGHT": _flashlight()
		"LANTERN": _lantern()
		"CROWBAR", "FIRE_AXE", "SHOTGUN": _weapon(id)
		"PHOTO": _photo(extra)
		"REMAINS": _remains()
		_: _generic(id)
	_rest_grip = [grip.position, grip.rotation]
	_no_shadows(rig)
	# Bring it up into view.
	rig.position.y = -0.12
	create_tween().tween_property(rig, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func set_lit(on: bool) -> void:
	_lens_mat.emission_energy_multiplier = 1.6 if on else 0.0
	_lens_mat.albedo_color = Color(1, 0.95, 0.8) if on else Color(0.35, 0.35, 0.33)


## A weapon swing; returns when (seconds in) it lands, for the hit. The weapon pivots in the
## fist (item rotation) while the hand travels a short way (grip offset): the arm stays an arm.
## Crowbar: cocked back over the right shoulder, slashed down and across to the left.
## Axe: both hands lift it, then chop straight down through the middle, a beat, back up.
func swing(id: String, secs: float) -> float:
	_pose(null)
	var tw := _pose_tw
	var p0: Vector3 = _rest_grip[0]
	var r0: Vector3 = _rest_grip[1]
	var keys: Array   # [item rotation, grip offset, grip rotation offset, fraction of secs, trans, ease]
	if id == "FIRE_AXE":
		keys = [[Vector3(0.28, 0, 0), Vector3(-0.03, 0.16, 0.0), Vector3(0.08, 0, 0), 0.42, Tween.TRANS_BACK, Tween.EASE_OUT],
			[Vector3(-0.85, 0, 0), Vector3(-0.06, -0.1, -0.08), Vector3(-0.35, 0, 0), 0.14, Tween.TRANS_EXPO, Tween.EASE_IN],
			[Vector3(-0.9, 0, 0.02), Vector3(-0.06, -0.11, -0.08), Vector3(-0.38, 0, 0), 0.1, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT],
			[Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 0.34, Tween.TRANS_SINE, Tween.EASE_IN_OUT]]
	else:
		keys = [[Vector3(0.85, 0, -0.25), Vector3(0.05, 0.09, 0.05), Vector3(0.15, -0.1, -0.3), 0.4, Tween.TRANS_BACK, Tween.EASE_OUT],
			[Vector3(-0.8, 0, 0.35), Vector3(-0.14, -0.06, -0.06), Vector3(-0.2, 0.2, 0.45), 0.16, Tween.TRANS_EXPO, Tween.EASE_IN],
			[Vector3(-0.85, 0, 0.38), Vector3(-0.15, -0.07, -0.06), Vector3(-0.22, 0.22, 0.48), 0.08, Tween.TRANS_SINE, Tween.EASE_OUT],
			[Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 0.36, Tween.TRANS_SINE, Tween.EASE_IN_OUT]]
	var landed := 0.0
	for i in keys.size():
		var k: Array = keys[i]
		var t: float = secs * k[3]
		tw.tween_property(item, "rotation", k[0], t).set_trans(k[4]).set_ease(k[5])
		tw.parallel().tween_property(grip, "position", p0 + k[1], t).set_trans(k[4]).set_ease(k[5])
		tw.parallel().tween_property(grip, "rotation", r0 + k[2], t).set_trans(k[4]).set_ease(k[5])
		if i < 2:
			landed += t
	return landed


## Shotgun kick, and a muzzle flash that lights the room for a frame or two.
func recoil() -> void:
	_pose(null)
	var tw := _pose_tw
	tw.tween_property(rig, "rotation", Vector3(0.42, 0.04, 0.0), 0.05).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rig, "position", Vector3(0, 0.02, 0.09), 0.05)
	tw.tween_property(rig, "rotation", Vector3.ZERO, 0.45).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(rig, "position", Vector3.ZERO, 0.45)
	if _muzzle:
		var flash := _muzzle
		flash.visible = true
		get_tree().create_timer(0.06, false).timeout.connect(func():
			if is_instance_valid(flash):
				flash.visible = false)


## Hold the photo right up in front of your face (or put it back down).
func set_inspect(on: bool) -> void:
	if _id != "PHOTO":
		return
	_inspect = on
	_pose(null)
	var tw := _pose_tw.set_parallel()
	tw.tween_property(grip, "position", Vector3(0.1, -0.12, -0.3) if on else HAND, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(grip, "rotation", Vector3(0.0, 0.0, 0.0) if on else Vector3(0.06, 0.14, -0.08), 0.25)
	tw.tween_property(item, "rotation", Vector3(PI / 2.0, 0.0, 0.0) if on else Vector3(1.25, 0.15, 0.0), 0.25)


func _pose(_x) -> void:
	if _pose_tw and _pose_tw.is_valid():
		_pose_tw.kill()
	_pose_tw = create_tween()


# --- model -------------------------------------------------------------------------------

func _fist() -> void:
	# Back of the hand: a rounded pad on the right of the grip, knuckles along its top.
	var back := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.046
	sm.height = 0.092
	back.mesh = sm
	back.material_override = A.mat("leather", Color.WHITE, 0.2)
	grip.add_child(back)
	back.position = Vector3(0.03, 0.004, 0.02)
	back.rotation.z = 0.35
	back.scale = Vector3(0.55, 0.9, 1.0)
	# Four fingers curled under the grip and around its left side, each in three joints.
	var pts := [-15.0, -70.0, -125.0, -165.0]
	for i in 4:
		var z := -0.011 + i * 0.0195
		var r := 0.0098 if i < 3 else 0.0088
		var prev := Vector3.ZERO
		for j in pts.size():
			var t := deg_to_rad(pts[j] + i * 4.0)
			var p := Vector3(cos(t), sin(t), 0) * (0.028 + r * 0.2) + Vector3(0, 0, z)
			if j > 0:
				_cap(grip, prev, p, r)
			prev = p
	# Thumb over the top, its tip resting by the switch.
	var thumb := [Vector3(0.036, 0.02, 0.02), Vector3(0.024, 0.03, -0.006), Vector3(0.002, 0.031, -0.026), Vector3(-0.016, 0.026, -0.034)]
	for j in thumb.size() - 1:
		_cap(grip, thumb[j], thumb[j + 1], 0.0115 - j * 0.0008)


## The forearm from the wrist back to `elbow` (grip space).
func _arm(elbow: Vector3) -> void:
	if _sleeve:
		_sleeve.free()
	_sleeve = Node3D.new()
	grip.add_child(_sleeve)
	var wrist := Vector3(0.035, -0.012, 0.072)
	var d := (elbow - wrist).normalized()
	_seg(_sleeve, wrist - d * 0.01, wrist + d * 0.085, 0.032, 0.042, "leather")            # glove cuff
	_seg(_sleeve, wrist + d * 0.07, wrist + d * 0.1, 0.048, 0.05, "fabric", Color(0.55, 0.5, 0.48))  # elastic cuff
	_seg(_sleeve, wrist + d * 0.095, elbow, 0.047, 0.06, "fabric", SUIT)                  # sleeve
	_seg(_sleeve, wrist + d * 0.22, wrist + d * 0.25, 0.0525, 0.0535, "plastic", Color(0.85, 0.85, 0.8))  # reflective tape
	for i in 3:   # fabric folds bunched at the wrist
		var c := wrist + d * (0.13 + i * 0.045)
		_seg(_sleeve, c, c + d * 0.012, 0.0505 + i * 0.002, 0.0505 + i * 0.002, "fabric", Color(0.8, 0.8, 0.8))


func _flashlight() -> void:
	var body := Color(0.95, 0.75, 0.15)
	_seg(item, Vector3(0, 0, 0.065), Vector3(0, 0, -0.105), 0.017, 0.017, "plastic", body)
	_seg(item, Vector3(0, 0, 0.0), Vector3(0, 0, 0.06), 0.0178, 0.0178, "knurl")                 # grip band
	_seg(item, Vector3(0, 0, -0.105), Vector3(0, 0, -0.155), 0.0175, 0.027, "plastic", body)     # flared head
	_seg(item, Vector3(0, 0, -0.152), Vector3(0, 0, -0.166), 0.029, 0.029, "metal", Color(0.6, 0.6, 0.6))  # bezel
	_seg(item, Vector3(0, 0, 0.062), Vector3(0, 0, 0.086), 0.0185, 0.0175, "rubber", Color(0.12, 0.12, 0.12))  # tail cap
	_box(item, Vector3(0.012, 0.008, 0.02), Vector3(0, 0.019, -0.055), 0.0, "rubber", Color(0.1, 0.1, 0.1))   # switch
	_box(item, Vector3(0.016, 0.003, 0.024), Vector3(0, 0.0165, -0.055), 0.0, "metal", Color(0.3, 0.3, 0.3))
	var lens := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.024
	cm.bottom_radius = 0.024
	cm.height = 0.002
	lens.mesh = cm
	lens.material_override = _lens_mat
	item.add_child(lens)
	lens.position.z = -0.1665
	lens.rotation.x = PI / 2


func _lantern() -> void:   # the same lantern you see lying about, hanging from your fist by its bail
	var m := Items.build("LANTERN")
	item.add_child(m)
	m.scale = Vector3.ONE * 0.8   # (it sits close to the eye)
	m.position = Vector3(0, -0.076, 0.017)
	var flame := MeshInstance3D.new()   # the mantle: dark until you light it
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.05
	flame.mesh = sm
	flame.material_override = _lens_mat
	m.add_child(flame)
	flame.position = Vector3(0, -0.04, 0)


## A body over your right shoulder: its legs hang down in front of you, your arm round them.
func _remains() -> void:
	grip.visible = false
	_carry = Node3D.new()
	rig.add_child(_carry)
	_carry.position = Vector3(0.42, -0.3, 0.02)
	_carry.rotation = Vector3(0.45, 0.55, 0.1)
	Suit.carried(_carry)
	_no_shadows(_carry)


## Weapons at real size, their handle running through the fist exactly where the flashlight's
## body does (the fingers wrap it), with the whole fist turned to hold them. The shotgun gets a
## second hand under the forend.
const GRIP_AT := Vector3(0, 0, 0.025)   # the middle of the fist, on its grip axis (z)


func _weapon(id: String) -> void:
	var m := Items.build(id)
	item.add_child(m)
	match id:
		"CROWBAR":   # by the rubber grip, the claw end up and hooked forward, ready to come down
			m.rotation = Vector3(0, PI, PI)
			m.position = GRIP_AT - m.basis * Vector3(0, 0, -0.2)
			grip.rotation = Vector3(0.82, 0.12, -0.12)
		"FIRE_AXE":   # two hands: right at the butt, left up the haft, carried across the body, blade out
			m.rotation = Vector3(0, PI, PI)
			m.position = GRIP_AT - m.basis * Vector3(0, -0.02, -0.38)
			grip.position = HAND + Vector3(-0.04, -0.03, 0.06)
			grip.rotation = Vector3(0.87, 0.68, 0.25)
			_pole_hand(m, Vector3(0, -0.012, -0.06), Vector3(-0.3, -0.85, -0.3))
		"SHOTGUN":   # right hand round the pistol grip (forearm below it), left under the forend, levelled
			var g := (Vector3(0, -0.085, -0.172) - Vector3(0, 0.005, -0.112)).normalized()   # up the pistol grip is the fist's forward
			var src := Basis(Vector3.RIGHT, (-g).cross(Vector3.RIGHT), -g)
			var dst := Basis(Vector3.LEFT, Vector3.FORWARD.cross(Vector3.LEFT), Vector3.FORWARD)
			m.basis = dst * src.inverse()
			m.position = GRIP_AT - m.basis * Vector3(0, -0.04, -0.142)
			grip.rotation = Vector3(atan2(-g.y, -g.z), 0.1, -0.03)   # tilt the fist so the barrels come level
			grip.position = HAND + Vector3(-0.08, 0.06, 0.04)
			_arm(Vector3(0.36, -0.12, 0.36))   # forearm runs back along the right side of the stock, not through it
			_sleeve.set_meta("elbow", Vector3.ONE)
			_support_hand(m)
			_muzzle = OmniLight3D.new()
			_muzzle.light_color = Color(1, 0.75, 0.4)
			_muzzle.light_energy = 6.0
			_muzzle.omni_range = 8.0
			_muzzle.visible = false
			m.add_child(_muzzle)
			_muzzle.position = Vector3(0, 0.04, 0.58)


## A second gloved hand closed round a pole running along the model's z axis at `at` (model
## space), its forearm reaching in from `elbow_rig` (a point in view space, down and to the left).
func _pole_hand(m: Node3D, at: Vector3, elbow_rig: Vector3) -> void:
	var to_m := (grip.transform * item.transform * m.transform).affine_inverse()
	var elbow: Vector3 = to_m * elbow_rig
	var axis := Vector3(0, 0, 1)
	var u := ((elbow - at) - axis * (elbow - at).dot(axis)).normalized()   # toward the wrist side
	var v := axis.cross(u)
	var h := Node3D.new()
	m.add_child(h)
	var r := 0.017
	for f in 4:   # fingers: from the palm round the far side of the pole
		var off := axis * (-0.03 + f * 0.0195)
		var prev := Vector3.ZERO
		for k in 5:
			var ang := deg_to_rad(10.0 + k * 55.0)
			var p := at + off + (u * cos(ang) + v * sin(ang)) * (r + 0.0095)
			if k > 0:
				_cap(h, prev, p, 0.0098 - k * 0.0004)
			prev = p
	var t0 := at + axis * 0.045 + (u * cos(-0.3) + v * sin(-0.3)) * (r + 0.01)   # thumb wraps the other way
	var t1 := at + axis * 0.035 + (u * cos(-1.4) + v * sin(-1.4)) * (r + 0.01)
	var t2 := at + axis * 0.02 + (u * cos(-2.3) + v * sin(-2.3)) * (r + 0.01)
	_cap(h, t0, t1, 0.0108)
	_cap(h, t1, t2, 0.0102)
	var back := MeshInstance3D.new()   # back of the hand over the knuckles
	var sm := SphereMesh.new()
	sm.radius = 0.046
	sm.height = 0.092
	back.mesh = sm
	back.material_override = A.mat("leather", Color.WHITE, 0.2)
	h.add_child(back)
	back.position = at + u * (r + 0.022) - axis * 0.002
	back.basis = Basis(v, u, axis) * Basis.from_scale(Vector3(0.9, 0.55, 1.0))
	var wrist := at + u * (r + 0.03) - axis * 0.01
	var d := (elbow - wrist).normalized()
	_seg(h, wrist - d * 0.01, wrist + d * 0.08, 0.034, 0.042, "leather")
	_seg(h, wrist + d * 0.07, wrist + d * 0.1, 0.047, 0.05, "fabric", Color(0.55, 0.5, 0.48))
	_seg(h, wrist + d * 0.095, elbow, 0.046, 0.054, "fabric", SUIT)
	_seg(h, wrist + d * 0.2, wrist + d * 0.23, 0.0495, 0.05, "plastic", Color(0.85, 0.85, 0.8))


## The left hand cradling the shotgun's forend (built in the gun's own frame, so it stays on it):
## palm under the wood, fingers curled over the far side, thumb along the near side, sleeve
## running back and down out of view.
func _support_hand(gun: Node3D) -> void:
	var h := Node3D.new()
	gun.add_child(h)
	var palm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.062, 0.024, 0.085)
	palm.mesh = bm
	palm.material_override = A.mat("leather", Color.WHITE, 0.2)
	h.add_child(palm)
	palm.position = Vector3(0.008, -0.012, 0.19)
	palm.rotation.z = -0.25
	for f in 4:   # fingers: up the far side (-x, screen right) and over the top edge
		var z := 0.158 + f * 0.021
		var pts := [Vector3(-0.022, -0.012, z), Vector3(-0.032, 0.004, z + 0.002), Vector3(-0.028, 0.022, z + 0.004), Vector3(-0.014, 0.03, z + 0.005)]
		for j in pts.size() - 1:
			_cap(h, pts[j], pts[j + 1], 0.0095 - j * 0.0006)
	var thumb := [Vector3(0.03, -0.016, 0.17), Vector3(0.034, 0.004, 0.19), Vector3(0.028, 0.02, 0.215)]
	for j in thumb.size() - 1:
		_cap(h, thumb[j], thumb[j + 1], 0.0105)
	var wrist := Vector3(0.03, -0.03, 0.155)
	var elbow := Vector3(0.12, -0.36, 0.1)   # down and a little back: out of view, not across it
	var d := (elbow - wrist).normalized()
	_seg(h, wrist - d * 0.01, wrist + d * 0.08, 0.033, 0.042, "leather")
	_seg(h, wrist + d * 0.07, wrist + d * 0.1, 0.047, 0.05, "fabric", Color(0.55, 0.5, 0.48))
	_seg(h, wrist + d * 0.095, elbow, 0.046, 0.052, "fabric", SUIT)
	_seg(h, wrist + d * 0.2, wrist + d * 0.23, 0.0495, 0.05, "plastic", Color(0.85, 0.85, 0.8))


## The photo, held up a little toward you; its picture is the one that was taken.
func _photo(extra: Dictionary) -> void:
	var m := Items.build("PHOTO")
	item.add_child(m)
	Pickup.show_picture(m, extra)
	var pic := m.find_child("Pic", true, false) as MeshInstance3D
	if pic:   # you can always make it out: it's right in front of your visor
		var pm := (pic.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.albedo_color = Color(0.85, 0.82, 0.78) if extra.has("tex") else Color(0.15, 0.13, 0.12)
		pic.material_override = pm
	m.position = Vector3(-0.085, 0.004, -0.07)   # held by its lower right corner
	item.rotation = Vector3(1.25, 0.15, 0.0)


func _generic(id: String) -> void:
	var size: Vector3 = Data.ITEMS[id].size
	if Data.is_heavy(id):   # hugged low in front of you, both arms under it
		var hm := Items.build(id)
		hm.scale = Vector3.ONE * (0.5 / maxf(size.x, maxf(size.y, size.z)))
		item.add_child(hm)
		hm.position = Vector3(-0.26, -0.02, -0.12)
		hm.rotation.y = 0.15
		return
	var longest := maxf(size.x, maxf(size.y, size.z))
	var m := Items.build(id)
	item.add_child(m)
	if longest > 0.3:   # bigger things: held out in front in both hands, near their real size
		var big := minf(1.0, 0.42 / longest)
		m.scale = Vector3.ONE * big
		m.position = Vector3(-0.24, 0.0 + size.y * big * 0.2, -0.1 - size.z * big * 0.3)
		m.rotation.y = 0.12
		return
	var s := minf(1.0, 0.24 / longest)   # in the hand
	m.scale = Vector3.ONE * s
	m.position = Vector3(-0.015, 0.01, -0.05 - size.z * s * 0.3)


# --- helpers -------------------------------------------------------------------------------

func _box(parent: Node3D, size: Vector3, pos: Vector3, rot_z: float, kind: String, tint := Color.WHITE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = A.mat(kind, tint, 0.12)
	parent.add_child(mi)
	mi.position = pos
	mi.rotation.z = rot_z
	return mi


## Rounded finger segment from a to b.
func _cap(parent: Node3D, a: Vector3, b: Vector3, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = a.distance_to(b) + r * 2.0
	cm.radial_segments = 10
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = A.mat("leather", Color.WHITE, 0.2)
	parent.add_child(mi)
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) / 2.0)
	return mi


## Tapered cylinder from a (radius r0) to b (radius r1).
func _seg(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, kind: String, tint := Color.WHITE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = a.distance_to(b)
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = A.mat(kind, tint, 0.2)
	parent.add_child(mi)
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) / 2.0)
	return mi


## No shadows, and on their own render layer (2) so the flashlight beam never lights the hand holding it.
func _no_shadows(n: Node) -> void:
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.layers = LAYER
