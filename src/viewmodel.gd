# First-person arm: orange suit sleeve running off-screen to the elbow, gloved fist wrapped around
# whatever you're holding (a real flashlight / lantern model, or the item's shape for scrap).
# Built at real scale on `rig`, then shrunk to half size at half the distance: it looks the same
# on screen but sits inside the player capsule, so it never pokes through walls.
extends Node3D

const A = preload("res://src/art.gd")
const Data = preload("res://src/data.gd")
const Items = preload("res://src/items.gd")

const SUIT := Color(1, 1, 1)
const HAND := Vector3(0.25, -0.26, -0.54)     # fist position in camera space (full scale)
const ELBOW := Vector3(0.2, -0.32, 0.42)     # elbow in grip space: down, right and behind, off-screen

const LAYER := 2   # render layer for the first-person model (lights can skip it)

var rig: Node3D
var grip: Node3D
var item: Node3D
var _lens_mat: StandardMaterial3D
var _id := "-"


func _ready() -> void:
	rig = Node3D.new()
	add_child(rig)
	rig.scale = Vector3.ONE * 0.5
	grip = Node3D.new()
	rig.add_child(grip)
	grip.position = HAND
	grip.rotation = Vector3(0.06, 0.14, -0.08)
	_fist()
	_arm()
	item = Node3D.new()
	grip.add_child(item)
	_lens_mat = StandardMaterial3D.new()
	_lens_mat.albedo_color = Color(0.9, 0.88, 0.75)
	_lens_mat.emission_enabled = true
	_lens_mat.emission = Color(1, 0.92, 0.7)


func set_item(id: String) -> void:
	if id == _id:
		return
	_id = id
	for c in item.get_children():
		c.queue_free()
	visible = id != ""
	if id == "":
		return
	grip.position = HAND + (Vector3(-0.02, 0.13, 0.0) if id == "LANTERN" else Vector3.ZERO)
	match id:
		"FLASHLIGHT": _flashlight()
		"LANTERN": _lantern()
		_: _generic(id)
	_no_shadows(rig)
	# Bring it up into view.
	rig.position.y = -0.12
	create_tween().tween_property(rig, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func set_lit(on: bool) -> void:
	_lens_mat.emission_energy_multiplier = 1.6 if on else 0.0
	_lens_mat.albedo_color = Color(1, 0.95, 0.8) if on else Color(0.35, 0.35, 0.33)


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


func _arm() -> void:
	var wrist := Vector3(0.035, -0.012, 0.072)
	var d := (ELBOW - wrist).normalized()
	_seg(grip, wrist - d * 0.01, wrist + d * 0.085, 0.032, 0.042, "leather")            # glove cuff
	_seg(grip, wrist + d * 0.07, wrist + d * 0.1, 0.048, 0.05, "fabric", Color(0.55, 0.5, 0.48))  # elastic cuff
	_seg(grip, wrist + d * 0.095, ELBOW, 0.047, 0.06, "fabric", SUIT)                  # sleeve
	_seg(grip, wrist + d * 0.22, wrist + d * 0.25, 0.0525, 0.0535, "plastic", Color(0.85, 0.85, 0.8))  # reflective tape
	for i in 3:   # fabric folds bunched at the wrist
		var c := wrist + d * (0.13 + i * 0.045)
		_seg(grip, c, c + d * 0.012, 0.0505 + i * 0.002, 0.0505 + i * 0.002, "fabric", Color(0.8, 0.8, 0.8))


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


func _lantern() -> void:
	var brass := Color(0.75, 0.55, 0.25)
	_box(item, Vector3(0.006, 0.006, 0.09), Vector3(0, 0.0, 0.017), 0.0, "metal", Color(0.4, 0.4, 0.4))   # bail in the fist
	for z in [-0.03, 0.065]:
		_seg(item, Vector3(0, 0, z), Vector3(0, -0.07, z * 0.5 + 0.008), 0.003, 0.003, "metal", Color(0.4, 0.4, 0.4))
	var top := Vector3(0, -0.075, 0.017)
	_seg(item, top, top + Vector3(0, -0.025, 0), 0.025, 0.045, "metal", brass)          # cap
	var glass := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.038
	cm.bottom_radius = 0.038
	cm.height = 0.09
	glass.mesh = cm
	glass.material_override = _lens_mat
	item.add_child(glass)
	glass.position = top + Vector3(0, -0.07, 0)
	for i in 4:   # cage bars
		var a := TAU * i / 4.0 + 0.4
		var p := top + Vector3(cos(a) * 0.043, -0.025, sin(a) * 0.043)
		_seg(item, p, p + Vector3(0, -0.09, 0), 0.004, 0.004, "metal", brass)
	_seg(item, top + Vector3(0, -0.115, 0), top + Vector3(0, -0.14, 0), 0.047, 0.047, "metal", brass)  # base


func _generic(id: String) -> void:
	var size: Vector3 = Data.ITEMS[id].size
	var s := minf(1.0, 0.16 / maxf(size.x, maxf(size.y, size.z)))   # big things shrink to a hand-sized preview
	var m := Items.build(id)
	m.scale = Vector3.ONE * s
	item.add_child(m)
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
