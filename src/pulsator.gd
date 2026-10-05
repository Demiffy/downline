# Blind egg on legs. Hears footsteps (and later: voice). Once it hears you it locks on,
# swells, and explodes ~5 s later or on contact. Crouch-walking is silent to it.
extends CharacterBody3D

const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

const FUSE := 5.0
const CHASE_SPEED := 5.0
const WANDER_SPEED := 1.2

var main
var level
var chasing := false
var target := Vector3.ZERO
var prey
var fuse := 0.0
var _wander := 0.0
var _step := 0.0
var body: MeshInstance3D
var skin := StandardMaterial3D.new()
var legs: Array[Node3D] = []
var _t := 0.0


func _ready() -> void:
	add_to_group("monsters")
	add_to_group("hearing")
	add_to_group("pulsators")
	collision_layer = 8
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.4
	sh.height = 1.1
	cs.shape = sh
	cs.position.y = 0.55
	add_child(cs)
	skin.albedo_color = Color(0.75, 0.45, 0.45)
	skin.roughness = 0.4
	skin.emission_enabled = true
	skin.emission = Color(1, 0.2, 0.15)
	skin.emission_energy_multiplier = 0.3
	body = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 1.0
	body.mesh = sm
	body.material_override = skin
	body.position.y = 0.75
	add_child(body)
	for i in 3:
		var leg := B.box(self, Vector3(0.07, 0.6, 0.07), Vector3(0, 0.3, 0.3).rotated(Vector3.UP, TAU * i / 3.0), Color(0.6, 0.4, 0.38), false)
		leg.rotation.y = TAU * i / 3.0
		leg.rotation.x = 0.35
		legs.append(leg)
	target = global_position


func hear(pos: Vector3) -> void:
	if not chasing:
		chasing = true
		fuse = 0.0
		Sfx.play(self, "screech", global_position, 4.0)
		var best := INF
		for p in main.players():
			var d: float = p.global_position.distance_to(pos)
			if d < best and not p.dead:
				best = d
				prey = p
	target = pos


func _physics_process(delta: float) -> void:
	for p in main.players():
		if not p.dead and p.global_position.distance_to(global_position) < 1.2:
			_explode()
			return
	if chasing:
		fuse += delta
		if is_instance_valid(prey) and not prey.dead:
			target = prey.global_position
		body.scale = Vector3.ONE * (1.0 + fuse * 0.12)
		var rate := 2.0 + fuse * 2.0
		skin.emission_energy_multiplier = 4.0 if fmod(fuse * rate, 1.0) < 0.5 else 0.2
		if fuse > FUSE:
			_explode()
			return
	else:
		_wander -= delta
		if _wander <= 0.0:
			_wander = randf_range(4.0, 9.0)
			target = level.wander_point(global_position)
	var next: Vector3 = level.next_point(global_position, target)
	var to := next - global_position
	to.y = 0.0
	var speed := CHASE_SPEED if chasing else WANDER_SPEED
	var v := to.normalized() * speed if to.length() > 0.3 else Vector3.ZERO
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	if v != Vector3.ZERO:
		rotation.y = atan2(-v.x, -v.z)
	move_and_slide()
	_t += delta * (14.0 if chasing else 6.0) * (1.0 if v != Vector3.ZERO else 0.15)
	for i in legs.size():
		legs[i].rotation.x = 0.35 + sin(_t + i * 2.1) * 0.35
	if not chasing:
		body.scale = Vector3.ONE * (1.0 + sin(_t * 0.5) * 0.04)
	_step -= delta
	if v != Vector3.ZERO and _step <= 0.0:
		_step = 0.2 if chasing else 0.45
		Sfx.play(self, "step", global_position, -4.0 if chasing else -12.0, 1.8)


func _explode() -> void:
	main.explode(global_position, 4.5, 150.0, "A pulsator burst next to you.")
	queue_free()
