# Shared monster plumbing: refs, gravity + pathing movement, "is anyone looking at me?", nearest player.
# Each monster extends this and only writes its own senses/rules.
extends CharacterBody3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")
const Sfx = preload("res://src/sfx.gd")
const Data = preload("res://src/data.gd")

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
var health := 100.0
var dead := false
var hit_kind := "flesh"   # what a hit sounds/sprays like: flesh, metal, wood, stone
var nav_path := PackedVector3Array()   # current route over the facility's navigation mesh
var _nav_goal := Vector3.INF
var _nav_t := 0.0
var _nav_glide := Vector3.INF   # a stair segment being glided along: finished before anything else
var dbg_target := Vector3.INF   # where walk_to was last asked to go, and the waypoint it took (path gizmos)
var dbg_next := Vector3.INF
static var unstuck_spots: Array = []   # [position, kind] each time the failsafe fired (path gizmos, probe)
static var unstuck_count := 0   # how often the failsafe below has fired (tests watch this)
static var unstuck_log: Array = []


func _setup_body(radius: float, height: float, hearing := false) -> void:
	add_to_group("monsters")
	if hearing:
		add_to_group("hearing")
	collision_layer = 8
	collision_mask = 1 | 16 | B.MOB_BARRIER   # world + railing panels + the walls round the train and the lift
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = radius
	sh.height = maxf(height, radius * 2.0)
	cs.shape = sh
	cs.position.y = sh.height / 2.0
	add_child(cs)
	_hit_r = radius
	_make_hitbox.call_deferred()   # (once the creature has built its body)


const HITBOX := 64   # collision layer weapons aim at: a box round what you can actually see of it
var hitbox: StaticBody3D
var _hit_r := 0.4


## What a weapon hits: a box fitted to the creature's model as built (its rest pose), on its own
## layer, so a pellet through the body counts even where the walking capsule doesn't reach. Glowing
## see-through things (beams, haze) don't count.
func _make_hitbox() -> void:
	if not is_inside_tree() or dead:
		return
	var inv := global_transform.affine_inverse()
	var box := AABB()
	var any := false
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.visible or mi.has_meta("no_hit"):
			continue
		var m := mi.material_override as BaseMaterial3D
		if m != null and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		box = b if not any else box.merge(b)
		any = true
	if not any:
		return
	var cap := _hit_r * 3.0   # (sprawling limbs don't make it a barn door)
	box.position.x = maxf(box.position.x, -cap)
	box.position.z = maxf(box.position.z, -cap)
	box.end = Vector3(minf(box.end.x, cap), box.end.y, minf(box.end.z, cap))
	box.position.y = maxf(box.position.y, 0.0)
	hitbox = StaticBody3D.new()
	hitbox.collision_layer = HITBOX
	hitbox.collision_mask = 0
	hitbox.set_meta("monster", self)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = box.size
	cs.shape = sh
	cs.position = box.get_center()
	hitbox.add_child(cs)
	add_child(hitbox)


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
	var nav_next := _nav_next(target, delta)
	if nav_next != Vector3.INF:
		var rise := nav_next - global_position
		if absf(rise.y) > 0.6 and absf(rise.y) > Vector2(rise.x, rise.z).length() * 1.3:
			nav_next = Vector3.INF   # the route snapped to another floor right above or below: not a way to walk
			nav_path.clear()
	if nav_next != Vector3.INF:
		next = nav_next
		var climb := next - global_position
		var flat_d := Vector2(climb.x, climb.z).length()
		if _nav_glide == Vector3.INF and absf(climb.y) > 0.25 and absf(climb.y) > flat_d * 0.2:
			_nav_glide = next   # a flight of stairs: taken in one smooth move to its end, not by physics
		if _nav_glide != Vector3.INF:
			next = _nav_glide
			climb = next - global_position
			flat_d = Vector2(climb.x, climb.z).length()
			var mv := speed * 0.8 * delta
			var dist := climb.length()
			if dist <= mv:
				global_position = next + Vector3(0, 0.05, 0)
				_nav_glide = Vector3.INF
				_nav_t = 0.0   # re-plan from the top (or bottom) of the flight
			else:
				global_position += climb / dist * mv
			if flat_d > 0.01:
				rotation.y = lerp_angle(rotation.y, atan2(-climb.x, -climb.z), minf(1.0, turn * delta))
			velocity = Vector3.ZERO
			_anchor = Vector3.INF
			_anim += mv
			dbg_target = target
			dbg_next = next
			return Vector3(climb.x, 0, climb.z).normalized() * speed
	elif level:
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
	dbg_target = target
	dbg_next = next
	var to := next - global_position
	to.y = 0.0
	var left := target - global_position   # stop when at the target (same floor), not at every waypoint
	var arrived := Vector2(left.x, left.z).length() < 0.35 and absf(left.y) < 1.5
	if nav_next != Vector3.INF and nav_path.size() == 1:   # at the end of the route: as close as it gets (the target may be in a crate)
		var end := nav_path[0] - global_position
		arrived = arrived or (Vector2(end.x, end.z).length() < 0.35 and absf(end.y) < 1.2)
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
				unstuck_spots.append([global_position, get_script().resource_path.get_file().get_basename()])
				if not forbidden(next):
					global_position = next + Vector3(0, 0.1, 0)
				velocity = Vector3.ZERO
				_anchor = Vector3.INF
				_route.clear()
				unstuck_count += 1
	_anim += v.length() * delta
	return v


## The next point of a route over the facility's navigation mesh (re-planned every half second, or
## when the target moves), or INF where there's no mesh (the surface) or no route.
func _nav_next(target: Vector3, delta: float) -> Vector3:
	var fac = level.facility if level else null
	if fac == null or fac.nav == null or global_position.y > fac.global_position.y + 8.0 or target.y > fac.global_position.y + 8.0:
		return Vector3.INF
	_nav_t -= delta
	if _nav_t <= 0.0 or nav_path.is_empty() or _nav_goal.distance_to(target) > 0.8:
		nav_path = fac.nav_path(global_position, target)
		_nav_goal = target
		_nav_t = 0.5
		_route.clear()
	while nav_path.size() > 1:
		var p := nav_path[0]
		if Vector2(p.x - global_position.x, p.z - global_position.z).length() < 0.3 and absf(p.y - global_position.y) < 0.6:
			nav_path.remove_at(0)
		else:
			break
	if nav_path.is_empty():
		return Vector3.INF
	return nav_path[0]


## Places creatures never go: aboard the train, inside the lift cab.
func forbidden(pos: Vector3) -> bool:
	if main and main.train and main.train.on_board(pos):
		return true
	return level != null and level.get("elevator") != null and level.elevator.inside(pos)


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


func nearest_player(max_dist := INF, need_sight := false):
	var best = null
	var bd := max_dist
	for p in alive_players():
		var d: float = p.global_position.distance_to(global_position)
		if d < bd and (not need_sight or sees(p)):
			bd = d
			best = p
	return best


## Can this monster see player p (nothing solid in between)? Walls, doors and floors block it.
func sees(p) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.6, 0), p.global_position + Vector3(0, 1.0, 0), 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


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


## Anyone looking at this monster? Any sliver of it in view counts: a grid of points over the body
## (four heights, across its width as you see it), so a shoulder past a shelf or a head over a crate
## is enough.
func observed(height := 1.5, cone := 0.55) -> bool:
	for p in alive_players():
		var side: Vector3 = p.cam.global_transform.basis.x * 0.24
		for f in [0.12, 0.4, 0.68, 0.92]:
			for s in [0.0, -1.0, 1.0]:
				if seen_by(p, global_position + Vector3(0, height * f, 0) + side * s, cone):
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


# --- fighting back -----------------------------------------------------------------------

## Hit by a weapon. Spray, flinch, react (react_to_hit), and die at 0 health.
func take_hit(dmg: float, from: Vector3, by = null) -> void:
	if dead:
		return
	health -= dmg
	var at := global_position + Vector3(0, 0.9, 0)
	hit_fx(self, at, (from - at).normalized(), hit_kind)
	var away := global_position - from
	away.y = 0.0
	if not is_inside_tree():
		return
	var tw := create_tween()   # flinch back a little
	tw.tween_property(self, "global_position", global_position + away.normalized() * minf(0.25, dmg * 0.006), 0.08)
	if health <= 0.0:
		die()
	else:
		react_to_hit(by)


## Override: is it after someone right now (raises the player's heartbeat more)?
func is_hunting() -> bool:
	return false


## Override: what being hit makes it do (hunt you, flee...).
func react_to_hit(_by) -> void:
	pass


## Dead for good: out of every group (no scanner, no spawn caps, no AI), sounds stop, it falls
## (death_anim) and the body stays where it dropped.
func die(how := -1) -> void:
	if dead:
		return
	dead = true
	if how < 0:
		how = randi()   # the fall's random choices (which way it keels over...), the same on every copy
	if main:
		main.guide_killed(main.creature_kind(self))
		main.net.ent_event(self, "die", [how])
		var drop: String = Data.DROPS.get(main.creature_kind(self), "")
		if drop != "" and main.net.authority() and level != null:   # something worth carrying home
			var p = main.spawn_item(drop, global_position + Vector3(0, 0.6, 0), -1.0, level)
			if p != null and "linear_velocity" in p:
				p.linear_velocity = Vector3(randf_range(-1, 1), 2.5, randf_range(-1, 1))
	for g in get_groups():
		remove_from_group(g)
	add_to_group("corpses")
	collision_layer = 0
	if hitbox:
		hitbox.collision_layer = 0
	velocity = Vector3.ZERO
	set_physics_process(false)
	set_process(false)
	for a in find_children("*", "AudioStreamPlayer3D", true, false):
		a.stop()
	seed(how)
	death_anim()
	randomize()


## Override per creature. Default: keels over sideways and lies still.
func death_anim() -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "rotation:z", PI / 2.0 * (1.0 if randf() < 0.5 else -1.0), 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", position.y + 0.2, 0.6)


## A burst of whatever it's made of, thrown back toward the attacker.
static func hit_fx(parent: Node, at: Vector3, toward: Vector3, kind: String) -> void:
	var cols := {"flesh": Color(0.45, 0.04, 0.03), "metal": Color(1.0, 0.75, 0.35), "wood": Color(0.62, 0.45, 0.28), "stone": Color(0.7, 0.68, 0.64), "cloth": Color(0.3, 0.3, 0.32)}
	var snd := {"flesh": "thud", "metal": "clank", "wood": "clack", "stone": "clank", "cloth": "rustle"}
	if "main" in parent and parent.main and parent.main.net.is_host:   # the crew sees the hit too
		parent.main.net.ent_event(parent, "hitfx", [at, toward, kind])
	var c: Color = cols.get(kind, cols.flesh)
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 18
	p.lifetime = 0.7
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.direction = toward
	m.spread = 45.0
	m.initial_velocity_min = 1.5
	m.initial_velocity_max = 4.0
	m.gravity = Vector3(0, -9.0, 0)
	m.scale_min = 0.5
	m.scale_max = 1.2
	p.process_material = m
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.025
	bm.material = B.mat(c, 4.0 if kind == "metal" else 0.0)
	p.draw_pass_1 = bm
	parent.get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	p.get_tree().create_timer(1.5, false).timeout.connect(p.queue_free)
	Sfx.play(parent.get_parent(), snd.get(kind, "thud"), at, 2.0, randf_range(0.6, 0.8) if kind == "stone" else randf_range(0.85, 1.15))


# --- as a mirror of the host's creature (multiplayer clients) -------------------------------------

## Runs every frame on a mirror, after its position and state vars arrive from the host: whatever
## makes it look alive (its own _animate, where it has one). Creatures override this as needed.
var _mirror_prev := Vector3.INF

func net_visual(delta: float) -> void:
	if dead:
		return
	var moved := 0.0 if _mirror_prev == Vector3.INF else global_position.distance_to(_mirror_prev)
	_mirror_prev = global_position
	velocity = Vector3(0, 0, -moved / maxf(delta, 0.001)).rotated(Vector3.UP, rotation.y)
	_anim += moved
	if has_method("_animate") and get_method_argument_count("_animate") == 1:
		call("_animate", delta)


## The host says something happened to it.
func net_event(ev: String, args: Array) -> void:
	match ev:
		"die": die(args[0] if not args.is_empty() else -1)
		"hitfx": hit_fx(self, args[0], args[1], args[2])
		"act": act(args[0], args[1])


## A one-off thing it visibly does (a swing, a bite, a new pose): done here, and on every
## crewmate's copy of it.
func show_act(what: String, args: Array = []) -> void:
	if main:
		main.net.ent_event(self, "act", [what, args])
	act(what, args)


## Override: carry out a show_act.
func act(_what: String, _args: Array) -> void:
	pass


## A line for whoever hit it (or you, if nobody did).
func tell(by, text: String) -> void:
	if by != null and by.has_method("say"):
		by.say(text)
	elif main:
		main.hud.msg(text)
