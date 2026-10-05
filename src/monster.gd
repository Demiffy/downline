# Shared monster plumbing: refs, gravity + pathing movement, "is anyone looking at me?", nearest player.
# Each monster extends this and only writes its own senses/rules.
extends CharacterBody3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")
const Sfx = preload("res://src/sfx.gd")

var main
var level
var _anim := 0.0  # animation clock, advanced by distance moved


func _setup_body(radius: float, height: float, hearing := false) -> void:
	add_to_group("monsters")
	if hearing:
		add_to_group("hearing")
	collision_layer = 8
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = radius
	sh.height = maxf(height, radius * 2.0)
	cs.shape = sh
	cs.position.y = sh.height / 2.0
	add_child(cs)


## Walks toward `target` along the facility room graph (straight line on the surface).
## Returns the horizontal velocity used (zero when arrived).
func walk_to(target: Vector3, speed: float, delta: float, turn := 10.0) -> Vector3:
	var next: Vector3 = level.next_point(global_position, target) if level else target
	var to := next - global_position
	to.y = 0.0
	var v := to.normalized() * speed if to.length() > 0.35 else Vector3.ZERO
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	if v != Vector3.ZERO:
		var want := atan2(-v.x, -v.z)
		rotation.y = lerp_angle(rotation.y, want, minf(1.0, turn * delta))
	move_and_slide()
	_anim += v.length() * delta
	return v


func stand_still(delta: float) -> void:
	velocity = Vector3(0, -1.0 if is_on_floor() else velocity.y - 20.0 * delta, 0)
	move_and_slide()


func face(pos: Vector3, delta: float, turn := 8.0) -> void:
	var d := pos - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), minf(1.0, turn * delta))


func alive_players() -> Array:
	return main.players().filter(func(p): return not p.dead)


func nearest_player(max_dist := INF):
	var best = null
	var bd := max_dist
	for p in alive_players():
		var d: float = p.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = p
	return best


## True if player p can see the point (in view cone + nothing solid in between).
func seen_by(p, point: Vector3, cone := 0.55, max_dist := 45.0) -> bool:
	var cam: Camera3D = p.cam
	var eye := cam.global_position
	var to := point - eye
	var dist := to.length()
	if dist > max_dist or dist < 0.01:
		return false
	if (-cam.global_transform.basis.z).dot(to / dist) < cone:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, point, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Anyone looking at this monster? Checks a couple of points on the body so peeking edges count.
func observed(height := 1.5, cone := 0.55) -> bool:
	for p in alive_players():
		for f in [0.3, 0.6, 0.9]:
			if seen_by(p, global_position + Vector3(0, height * f, 0), cone):
				return true
	return false


func roofed(pos: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.9, 0), pos + Vector3(0, 40, 0), 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Unlit-friendly emissive material we can animate per monster.
static func glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## A limb segment hanging from a pivot: returns the pivot (rotate it to swing the limb).
static func limb(parent: Node, at: Vector3, length: float, thick: float, kind: String, tint: Color) -> Node3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.position = at
	A.box(pivot, Vector3(thick, length, thick), Vector3(0, -length / 2.0, 0), kind, tint, false, 0.5)
	return pivot
