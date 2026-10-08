# Your remains: the suit (suit.gd) as eleven rigid bodies on joints, so it falls, folds and sprawls
# however it lands. It stands in for a REMAINS pickup: E on any part lifts it as a heavy item,
# dropping that item lays a new ragdoll down, and the scanner points to it.
# The parts are top-level bodies; this node just follows the pelvis, so code that asks a pickup
# where it is (scanner, "is it on the train?") gets the body's real position.
# A body left lying in the lift cab rides with it (elevator.gd holds its parts still and carries them).
extends Node3D

const Suit = preload("res://src/suit.gd")

var id := "REMAINS"
var charge := -1.0
var extra := {}
var pose := "drop"    # "drop": laid down flat a little above the floor; "stand": upright, collapses
var puppet := false   # a copy of the host's body (multiplayer): parts follow the host, no physics
var parts := {}       # name -> RigidBody3D
var linear_velocity := Vector3.ZERO:
	set(v):
		linear_velocity = v
		for b in parts.values():
			b.linear_velocity = v

## part -> [mass, shape, shape centre (part frame)]
const BODY := {
	"pelvis": [12.0, ["box", Vector3(0.3, 0.2, 0.2)], Vector3(0, -0.01, 0)],
	"torso": [16.0, ["box", Vector3(0.34, 0.44, 0.24)], Vector3(0, 0.23, 0.03)],
	"head": [4.0, ["sphere", 0.15], Vector3(0, 0.16, 0)],
	"upper_arm": [2.5, ["capsule", 0.055, 0.29], Vector3(0, -0.145, 0)],
	"forearm": [2.0, ["capsule", 0.05, 0.38], Vector3(0, -0.19, 0)],
	"thigh": [7.0, ["capsule", 0.075, 0.42], Vector3(0, -0.21, 0)],
	"shin": [4.0, ["capsule", 0.065, 0.5], Vector3(0, -0.25, 0)],
}


func _ready() -> void:
	add_to_group("pickups")
	add_to_group("scan_targets")
	set_meta("scan_name", "YOUR REMAINS")
	_build.call_deferred()   # after whoever spawned us has placed us


func set_extra(e: Dictionary) -> void:
	extra = e


func _build() -> void:
	var base := global_transform
	if pose == "drop":   # flat on its back, a little above the floor, so it settles where it lands
		base = Transform3D(base.basis * Basis(Vector3.RIGHT, PI / 2.0), base.origin + Vector3(0, 0.45, 0)).translated_local(Vector3(0, -0.95, 0))
	var push := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)) if pose == "stand" else Vector3.ZERO
	for name in Suit.PARTS:
		var b := RigidBody3D.new()
		b.top_level = true
		b.collision_layer = 2     # E and the scanner find it like any pickup...
		b.collision_mask = 1      # ...and it only lands on the world (no fighting itself or you)
		var kind: String = name.trim_suffix("_l").trim_suffix("_r")
		var spec: Array = BODY[kind]
		b.mass = spec[0]
		b.linear_damp = 0.4
		b.angular_damp = 3.0
		b.set_meta("ragdoll", self)
		if puppet:
			b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			b.freeze = true
		var cs := CollisionShape3D.new()
		var sh: Array = spec[1]
		match sh[0]:
			"box":
				cs.shape = BoxShape3D.new()
				cs.shape.size = sh[1]
			"sphere":
				cs.shape = SphereShape3D.new()
				cs.shape.radius = sh[1]
			"capsule":
				cs.shape = CapsuleShape3D.new()
				cs.shape.radius = sh[1]
				cs.shape.height = sh[2]
		cs.position = spec[2]
		b.add_child(cs)
		var look := Node3D.new()
		b.add_child(look)
		Suit.part(look, name)
		add_child(b)
		b.global_transform = base * Transform3D(Basis.IDENTITY, Suit.PARTS[name][1])
		b.linear_velocity = linear_velocity + push * (1.0 if name in ["torso", "head"] else 0.2)
		parts[name] = b
	if puppet:
		return   # (its parts go where the host says)
	_cone("pelvis", "torso", Vector3.UP, 0.5, 0.4)
	_cone("torso", "head", Vector3.UP, 0.7, 0.8)
	for s in ["_l", "_r"]:
		_cone("torso", "upper_arm" + s, Vector3.DOWN, 1.3, 0.6)
		_hinge("upper_arm" + s, "forearm" + s, -2.3, 0.05)   # elbows fold forward
		_cone("pelvis", "thigh" + s, Vector3.DOWN, 0.9, 0.3)
		_hinge("thigh" + s, "shin" + s, -0.05, 2.3)          # knees fold back


func _physics_process(_delta: float) -> void:
	var p: RigidBody3D = parts.get("pelvis")
	if p:
		global_position = p.global_position


## A ball-and-socket joint at `b`'s pivot; `axis` is the bone's rest direction (the twist axis).
func _cone(a: String, b: String, axis: Vector3, swing: float, twist: float) -> void:
	var j := ConeTwistJoint3D.new()
	var basis: Basis = parts[b].global_transform.basis * Basis(Vector3.FORWARD, -PI / 2.0 if axis == Vector3.UP else PI / 2.0)
	_joint(j, a, b, basis)
	j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, swing)
	j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, twist)


## A hinge across the body (elbow, knee) at `b`'s pivot, limited to bending one way.
func _hinge(a: String, b: String, lo: float, hi: float) -> void:
	var j := HingeJoint3D.new()
	_joint(j, a, b, parts[b].global_transform.basis * Basis(Vector3.UP, PI / 2.0))
	j.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	j.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, lo)
	j.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, hi)


func _joint(j: Joint3D, a: String, b: String, basis: Basis) -> void:
	j.top_level = true
	add_child(j)
	j.global_transform = Transform3D(basis, parts[b].global_position)
	j.node_a = j.get_path_to(parts[a])
	j.node_b = j.get_path_to(parts[b])
