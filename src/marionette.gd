# The Marionette: a jointed wooden mannequin crouched in a corner. The reverse of the statue —
# it only moves while someone IS looking at it (even a sliver counts), sprinting straight at you.
# Look away and it locks in place. Touch = death. Trap it in a dead end and walk away backwards.
extends "res://src/monster.gd"

const SPEED := 7.0
const WOOD := Color(0.88, 0.7, 0.5)

var standing := false
var _rise := 0.0           # 0 crouched .. 1 standing
var _hips: Node3D
var _legs: Array[Node3D] = []   # [l_thigh, l_shin, r_thigh, r_shin]
var _arms: Array[Node3D] = []   # [l_upper, l_fore, r_upper, r_fore]
var _head: Node3D
var _torso: Node3D
var _step := 0.0


func _ready() -> void:
	_setup_body(0.3, 1.8)
	health = 50.0
	hit_kind = "wood"
	_hips = Node3D.new()
	add_child(_hips)
	_torso = Node3D.new()
	_hips.add_child(_torso)
	_torso.position.y = 0.05
	A.box(_hips, Vector3(0.34, 0.16, 0.2), Vector3.ZERO, "cream", WOOD, false, 0.6)
	A.box(_torso, Vector3(0.24, 0.32, 0.17), Vector3(0, 0.22, 0), "cream", WOOD, false, 0.6)
	A.box(_torso, Vector3(0.4, 0.26, 0.2), Vector3(0, 0.5, 0), "cream", WOOD, false, 0.6)
	A.sphere(_torso, 0.05, Vector3(0, 0.66, 0), "cream", WOOD.darkened(0.3))
	_head = Node3D.new()
	_torso.add_child(_head)
	_head.position.y = 0.72
	A.sphere(_head, 0.13, Vector3(0, 0.13, 0), "cream", WOOD, 0.0, 1.35)
	# Painted-on face: two black dots and a crooked line. That's all it needs.
	for x in [-0.045, 0.045]:
		A.sphere(_head, 0.018, Vector3(x, 0.16, -0.115), "metal", Color(0.02, 0.02, 0.02))
	A.box(_head, Vector3(0.07, 0.01, 0.01), Vector3(0.01, 0.07, -0.12), "metal", Color(0.05, 0.02, 0.02), false, 0.3, Vector3(0, 0, 0.25))
	for side in [-1, 1]:
		var upper := limb(_torso, Vector3(side * 0.24, 0.6, 0), 0.32, 0.07, "cream", WOOD)
		A.sphere(upper, 0.05, Vector3.ZERO, "cream", WOOD.darkened(0.3))
		var fore := limb(upper, Vector3(0, -0.32, 0), 0.3, 0.06, "cream", WOOD)
		A.sphere(fore, 0.045, Vector3.ZERO, "cream", WOOD.darkened(0.3))
		A.box(fore, Vector3(0.07, 0.12, 0.03), Vector3(0, -0.36, 0), "cream", WOOD, false, 0.4)
		_arms.append(upper)
		_arms.append(fore)
		var thigh := limb(_hips, Vector3(side * 0.11, -0.05, 0), 0.45, 0.09, "cream", WOOD)
		A.sphere(thigh, 0.06, Vector3.ZERO, "cream", WOOD.darkened(0.3))
		var shin := limb(thigh, Vector3(0, -0.45, 0), 0.44, 0.075, "cream", WOOD)
		A.sphere(shin, 0.055, Vector3.ZERO, "cream", WOOD.darkened(0.3))
		A.box(shin, Vector3(0.09, 0.05, 0.2), Vector3(0, -0.46, -0.05), "cream", WOOD, false, 0.4)
		_legs.append(thigh)
		_legs.append(shin)
	_apply_pose(0.0)


## Blend between a folded crouch (0) and a running stance (1), plus a run cycle.
func _apply_pose(run: float) -> void:
	var r := _rise
	_hips.position.y = lerpf(0.42, 0.98, r)
	_torso.rotation.x = lerpf(-0.9, -0.25, r)
	_head.rotation = Vector3(lerpf(-0.5, -0.1, r), 0, lerpf(0.4, 0.0, r) + sin(_anim * 0.7) * 0.15 * r)
	var s := sin(_anim * 3.2) * run
	for k in 2:
		var side := -1.0 if k == 0 else 1.0
		_legs[k * 2].rotation.x = lerpf(1.9, 0.0, r) + s * 0.9 * side
		_legs[k * 2 + 1].rotation.x = lerpf(-2.3, -0.15, r) - maxf(0.0, s * side) * 1.2
		_arms[k * 2].rotation = Vector3(lerpf(0.6, 0.2, r) - s * 0.9 * side, 0, side * lerpf(0.25, 0.12, r))
		_arms[k * 2 + 1].rotation.x = lerpf(1.4, 0.5, r)


func _physics_process(delta: float) -> void:
	var watched := observed(1.6, 0.42)
	var prey = nearest_player()
	if not watched or prey == null:
		stand_still(delta)   # frozen mid-stride; no animation either
		return
	if not standing:
		standing = true
		Sfx.play(self, "creak", global_position + Vector3.UP, 2.0, 0.6)
	_rise = minf(1.0, _rise + delta * 2.5)
	var dist: float = prey.global_position.distance_to(global_position)
	if dist < 1.1:
		prey.hurt(200.0, "The marionette got you.")
		stand_still(delta)
	elif _rise >= 0.95:
		walk_to(prey.global_position, SPEED, delta, 20.0)
		_step -= delta
		if _step <= 0.0:
			_step = 0.16
			Sfx.play(self, "clack", global_position, -2.0, randf_range(0.8, 1.2))
	else:
		face(prey.global_position, delta)
		stand_still(delta)
	_apply_pose(1.0 if _rise >= 0.95 else 0.0)


# --- death ---

## The strings are cut: it folds up into a heap of jointed limbs, head lolling.
func death_anim() -> void:
	Sfx.play(self, "creak", global_position + Vector3.UP, 2.0, 0.5)
	var tw := create_tween().set_parallel()
	tw.tween_property(_hips, "position:y", 0.14, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_torso, "rotation", Vector3(-1.25, 0.3, 0.5), 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_head, "rotation", Vector3(-0.6, 0.9, 1.1), 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var legs := [Vector3(1.4, 0, 0.5), Vector3(-1.6, 0, 0), Vector3(1.55, 0, -0.35), Vector3(-0.4, 0, 0)]
	for i in 4:
		tw.tween_property(_legs[i], "rotation", legs[i], 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var arms := [Vector3(0.3, 0, 1.4), Vector3(1.2, 0, 0), Vector3(-0.4, 0, -1.2), Vector3(0.2, 0, 0)]
	for i in 4:
		tw.tween_property(_arms[i], "rotation", arms[i], 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	for k in 3:
		get_tree().create_timer(0.12 + k * 0.13, false).timeout.connect(Sfx.play.bind(self, "clack", global_position, -2.0, randf_range(0.7, 1.1)))


func is_hunting() -> bool:
	return standing


func net_visual(delta: float) -> void:
	var moved := 0.0 if _mirror_prev == Vector3.INF else global_position.distance_to(_mirror_prev)
	_mirror_prev = global_position
	if moved > 0.001:
		_anim += moved
	_apply_pose(1.0 if moved > 0.002 else 0.0)
