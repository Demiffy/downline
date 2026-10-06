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
var _stuck := 0.0      # how long we've been pushing without getting anywhere
var _side_t := 0.0     # sidestepping round whatever was in the way
var _side_dir := 1.0
var _route: Array = []   # a stair route being followed (facility.stair_route)
var _route_t := 0.0
var _glide_to := Vector3.INF   # the far end of the flight in _route: taken in one smooth move, not by physics
var _anchor := Vector3.INF   # where we were when we last made real progress
var _anchor_t := 0.0
static var unstuck_count := 0   # how often the failsafe below has fired (tests watch this)
static var unstuck_log: Array = []


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


## A looping sound that lives on the monster (so you can hear it coming). Returns the player.
func presence(sound: String, db := -6.0, unit := 4.0) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.stream = Sfx.stream(sound)
	a.volume_db = db
	a.unit_size = unit
	a.max_distance = 40.0
	a.bus = "World"
	add_child(a)
	a.position.y = 0.8
	a.play.call_deferred(randf() * 1.5)
	return a


## Walks toward `target` along the facility room graph (straight line on the surface).
## Returns the horizontal velocity used (zero when arrived).
func walk_to(target: Vector3, speed: float, delta: float, turn := 10.0) -> Vector3:
	if level and level.facility and global_position.y < level.facility.global_position.y - 8.0:
		unstuck_log.append("FELL at %s" % level.facility.to_local(global_position).snapped(Vector3.ONE * 0.1))
		global_position = level.facility.random_point(level.rng, true)   # fell out of the world: back in
		velocity = Vector3.ZERO
		_route.clear()
		unstuck_count += 1
	var next := target
	if level:
		if _route.is_empty() and level.has_method("stair_route"):
			_route = level.stair_route(global_position, target)
			_route_t = 0.0
			_glide_to = _route[-2] if _route.size() >= 2 else Vector3.INF
		if not _route.is_empty() and _route[0] == _glide_to:   # on the flight: up/down it like a lift carries you
			var goal: Vector3 = _glide_to - Vector3(0, 0.5, 0)   # (route points are 0.5 above the floor)
			var step := goal - global_position
			var flat := Vector2(step.x, step.z).length()
			var move := speed * 0.8 * delta
			if flat <= move:
				global_position = goal + Vector3(0, 0.05, 0)
				_route.pop_front()
			else:
				var k := move / flat
				global_position += Vector3(step.x * k, step.y * k, step.z * k)
				rotation.y = lerp_angle(rotation.y, atan2(-step.x, -step.z), minf(1.0, turn * delta))
			velocity = Vector3.ZERO
			_route_t = 0.0
			_anchor = Vector3.INF
			_anim += move
			return Vector3(step.x, 0, step.z).normalized() * speed
		while not _route.is_empty() and Vector2(_route[0].x - global_position.x, _route[0].z - global_position.z).length() < 0.4:
			_route.pop_front()
			_route_t = 0.0
		_route_t += delta
		if _route_t > 5.0:   # not getting anywhere on it: think again
			_route.clear()
		next = _route[0] if not _route.is_empty() else level.next_point(global_position, target)
	var to := next - global_position
	to.y = 0.0
	var left := target - global_position   # stop when at the target (same floor), not at every waypoint
	var arrived := Vector2(left.x, left.z).length() < 0.35 and absf(left.y) < 1.5
	var v := to.normalized() * speed if not arrived and to.length() > 0.01 else Vector3.ZERO
	if _side_t > 0.0 and v != Vector3.ZERO:   # blocked a moment ago: veer off to one side
		_side_t -= delta
		v = (v.normalized() + v.normalized().cross(Vector3.UP) * _side_dir * 1.3).normalized() * speed
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	if v != Vector3.ZERO:
		var want := atan2(-v.x, -v.z)
		rotation.y = lerp_angle(rotation.y, want, minf(1.0, turn * delta))
	var before := global_position
	move_and_slide()
	if v != Vector3.ZERO and delta > 0.0:
		var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
		_stuck = _stuck + delta if moved < speed * delta * 0.25 else maxf(0.0, _stuck - delta)
		if _stuck > 0.4:   # pinned on a crate corner or a rail: sidestep for a bit
			_stuck = 0.0
			_side_t = 0.7
			_side_dir = -_side_dir if randf() < 0.5 else _side_dir
		# Failsafe: no real progress for 3 s and nobody watching: step onto the next waypoint.
		if _anchor == Vector3.INF or global_position.distance_to(_anchor) > 0.8:
			_anchor = global_position
			_anchor_t = 0.0
		else:
			_anchor_t += delta
			if _anchor_t > 3.0 and not _watched():
				if level and level.facility:
					var f = level.facility
					var c: Vector2i = f.cell_at(global_position)
					unstuck_log.append("%s %s y%.1f route%d -> %s" % [c, f.kinds.get(c, "?"), f.to_local(global_position).y, _route.size(), f.to_local(next).snapped(Vector3.ONE * 0.1)])
				global_position = next + Vector3(0, 0.1, 0)
				velocity = Vector3.ZERO
				_anchor = Vector3.INF
				_route.clear()
				unstuck_count += 1
	_anim += v.length() * delta
	return v


func _watched() -> bool:
	for p in alive_players():
		if seen_by(p, global_position + Vector3(0, 1.0, 0), 0.4, 30.0):
			return true
	return false


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
