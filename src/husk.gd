# A Husk: a dead employee's body that lay too long in the dark, and got up again. It passes for one
# of the crew. It wears their suit; over its helmet, each of you sees the name of someone else on
# the crew (you see it as your crewmate, they see it as you). It moves like a player: walks room to
# room at a walking pace, sprints now and then, stops to crouch over scrap and pick through it,
# looks about, carries a flashlight with the beam on. Footsteps like anyone's, nothing else.
#
# When it finds one of you it tags along like a crewmate would: keeps a few metres off, wanders
# near, glances at you, looks where you look. It waits for its moment (your back turned while it's
# close, or long enough), then sprints in and hits hard, and runs off out of sight to blend in
# somewhere else. Hit it and it turns on you at once. Kill it and it falls, just a body again.
extends "res://src/monster.gd"

const Suit = preload("res://src/suit.gd")
const Pickup = preload("res://src/pickup.gd")

enum { ROAM, TAG_ALONG, STRIKE, SLINK }
const SIGHT := 20.0
const DAMAGE := 40.0
const WALK := 3.6        # a player's walk is 4.0, a sprint 6.5
const RUN := 6.4

var state := ROAM
var prey
var who := ""            # the name of whoever's body it was (kept with it)
var crouch := 0.0        # 0..1 (synced: copies crouch too)
var look := 0.0          # head turn, radians (synced)
var lit := true          # its flashlight (synced)
var _t := 0.0
var _goal := Vector3.ZERO
var _until := 0.0        # when the current errand ends
var _sprint := false
var _patience := 12.0    # how long it plays along before it goes for you
var _parts := {}
var _tag: Label3D
var _step := 0.0
var _beam: SpotLight3D
var _look_to := 0.0
var _worn: Array = []
var _worn_by := ""
var _spot := Vector3.ZERO   # (tagging along) where it keeps itself, relative to the one it's with
var _moving := false        # walking to that spot, until it's there (and not before it's a way off)
var _backing := false       # giving them room, until there's room
var _dest := Vector3.ZERO   # where on the floor it set off for (not chasing every step you take)
var _dest_from := Vector3.ZERO   # where you were then
var _dest_best := 0.0   # the nearest it's got to it (a way there that leads off elsewhere is given up)
var _flat := Vector3.ZERO   # its own sideways speed, eased (a person doesn't stop or start dead)


func _ready() -> void:
	_setup_body(0.32, 1.8)
	health = 90.0
	hit_kind = "cloth"
	var body := Node3D.new()
	add_child(body)
	body.name = "Body"
	_parts = Suit.standing(body)   # (just as they were)
	Suit.set_held(body, _parts, "FLASHLIGHT")
	_beam = SpotLight3D.new()   # its torch, like anyone's down here
	_beam.spot_range = 18.0
	_beam.spot_angle = 26.0
	_beam.light_energy = 3.5
	_beam.shadow_enabled = false
	add_child(_beam)
	_beam.position = Vector3(0.25, 1.25, -0.4)
	_tag = Label3D.new()   # a name over the helmet, as over any crewmate's
	_tag.font_size = 22
	_tag.pixel_size = 0.0011
	_tag.fixed_size = true
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.modulate = Color(1.0, 0.85, 0.55, 0.9)
	_tag.outline_size = 8
	_tag.visible = false
	add_child(_tag)
	_tag.position.y = 2.05
	_goal = global_position


func set_who(n: String) -> void:
	who = n


func net_event(ev: String, args: Array) -> void:
	if ev == "who":
		set_who(args[0])
	else:
		super.net_event(ev, args)


func _physics_process(delta: float) -> void:
	_t += delta
	var v := Vector3.ZERO
	match state:
		ROAM:   # going about its business like any of you
			if _t > _until or global_position.distance_to(_goal) < 1.2:
				_errand()
			if crouch > 0.5:   # going through some scrap
				stand_still(delta)
			else:
				v = walk_to(_goal, RUN if _sprint else WALK, delta, 6.0)
			var p = nearest_player(SIGHT, true)
			if p != null and _t > 2.0:
				prey = p
				state = TAG_ALONG
				_t = 0.0
				crouch = 0.0
				_patience = randf_range(8.0, 22.0)
				_pick_spot()
		TAG_ALONG:   # a crewmate who's joined you: near, not too near, doing its own thing
			if not _valid():
				return
			var d: float = global_position.distance_to(prey.global_position)
			if _t > _until:
				_pick_spot()
			var goal: Vector3 = prey.global_position + _spot
			var off: float = global_position.distance_to(goal)
			# Room first: walked into, it steps back facing you, until there's a pace or two between you.
			if d < 1.9 and _t < _patience:
				_backing = true
			elif d > 3.2:
				_backing = false
			if _backing:
				var away: Vector3 = (global_position - prey.global_position) * Vector3(1, 0, 1)
				_ease(away.normalized() * 2.2, delta)
				face(prey.global_position, delta, 3.0)
				v = _flat
				_moving = false
			else:
				# Then its spot: set off when it's a way from it, stop once there. (Between the two it
				# stays put: no shuffling to and fro over a few centimetres.)
				if not _moving and off > (2.4 if d < 9.0 else 1.2):
					_moving = true
					_dest = goal
					_dest_from = prey.global_position
					_dest_best = INF
				if _moving and prey.global_position.distance_to(_dest_from) > 3.0:
					_dest = goal   # (you've gone on somewhere: so does it)
					_dest_from = prey.global_position
					_dest_best = INF
				if _moving:
					var left := global_position.distance_to(_dest)
					_dest_best = minf(_dest_best, left)
					if left > _dest_best + 3.0 and d < 12.0:
						_moving = false   # the only way there is the long way round: somewhere else
						_pick_spot()
				if _moving and global_position.distance_to(_dest) < 0.8:
					_moving = false
				if _moving:
					v = walk_to(_dest, RUN if d > 12.0 else WALK, delta, 5.0)
					_flat = Vector3(velocity.x, 0, velocity.z)
				else:
					_ease(Vector3.ZERO, delta)
					v = _flat
					if randf() < delta * 0.5 or _flat.length() > 0.1:
						face(prey.global_position, delta, 2.5)
			# Its moment: close, and your back's to it; or it has waited long enough.
			var behind: bool = not _looked_at_by(prey)
			if (d < 3.5 and behind and _t > 3.0) or _t > _patience:
				state = STRIKE
				_t = 0.0
		STRIKE:
			if prey == null or not is_instance_valid(prey) or prey.dead:
				_slink()
			else:
				v = walk_to(prey.global_position, RUN + 0.6, delta, 14.0)
				var dd: float = global_position.distance_to(prey.global_position)
				if dd < 1.3 or (v == Vector3.ZERO and dd < 2.2):
					prey.hurt(DAMAGE, "That wasn't your crewmate.")
					Sfx.play(self, "thud", global_position + Vector3.UP * 1.2, 0.0, 1.1)
					_slink()
				elif _t > 4.0:
					_slink()
		SLINK:   # gone again, out of sight, to turn up as someone else later
			v = walk_to(_goal, RUN, delta, 10.0)
			if global_position.distance_to(_goal) < 1.5 or _t > 10.0:
				state = ROAM
				_t = 0.0
				_errand()
	_mannerisms(delta)
	_animate(delta)


## Something to do: walk to another room (now and then at a run), or stop and go through scrap.
func _errand() -> void:
	_t = 0.0
	_sprint = randf() < 0.18
	crouch = 0.0
	var scrap: Array = get_tree().get_nodes_in_group("pickups").filter(func(q): return Data.kind(q.id) == "scrap" and q.global_position.distance_to(global_position) < 9.0 and absf(q.global_position.y - global_position.y) < 1.5)
	if not scrap.is_empty() and randf() < 0.35:
		var q = scrap[randi() % scrap.size()]
		_goal = q.global_position
		_until = randf_range(6.0, 10.0)
		set_meta("rummage", q)
	else:
		_goal = level.wander_point(global_position) if level else global_position
		_until = randf_range(8.0, 16.0)
		if has_meta("rummage"):
			remove_meta("rummage")


## Somewhere a few metres from them, off to one side: where a crewmate would stand. On the side it's
## already on, so it never has to cross in front of them to get there; kept relative to them, so it
## comes along when they move.
func _pick_spot() -> void:
	var from: Vector3 = (global_position - prey.global_position) * Vector3(1, 0, 1)
	var space := get_world_3d().direct_space_state
	var eye: Vector3 = prey.global_position + Vector3.UP * 1.2
	_spot = from.normalized() * clampf(from.length(), 3.0, 5.0) if from.length() > 0.1 else Vector3(4, 0, 0)
	for k in 10:   # somewhere in plain sight of them with floor under it (not behind a wall: the long way round)
		var a := atan2(from.z, from.x) + randf_range(-0.9, 0.9) * (1.0 + k * 0.2)
		var r := randf_range(3.4, 5.6) * (1.0 - k * 0.05)
		var off := Vector3(cos(a) * r, 0, sin(a) * r)
		var to: Vector3 = eye + off
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, to + off.normalized() * 0.5, 1)).is_empty():
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(to, to + Vector3.DOWN * 2.2, 1)).is_empty():
			continue
		_spot = off
		break
	_until = _t + randf_range(6.0, 11.0)


## Move at `want` (sideways), easing toward it: it can't go from a walk to a stop, or turn about, in a frame.
func _ease(want: Vector3, delta: float) -> void:
	_flat = _flat.move_toward(want, 9.0 * delta)
	velocity = Vector3(_flat.x, velocity.y - 9.8 * delta if not is_on_floor() else -1.0, _flat.z)
	move_and_slide()
	_anim += _flat.length() * delta


func _slink() -> void:
	state = SLINK
	_t = 0.0
	crouch = 0.0
	prey = null
	_goal = global_position
	if level != null and level.facility != null and main.net.authority():
		var hide: Vector3 = level._hidden_spot(14.0)
		if hide != Vector3.INF:
			_goal = hide


## Is that player looking our way?
func _looked_at_by(p) -> bool:
	var fwd: Vector3 = -p.cam.global_transform.basis.z if "cam" in p and p.cam else -p.global_transform.basis.z
	var to: Vector3 = (global_position + Vector3.UP * 1.4 - p.global_position - Vector3.UP * 1.6).normalized()
	return fwd.dot(to) > 0.55


## Looking about, crouching over scrap, the torch on in the dark.
func _mannerisms(delta: float) -> void:
	var rum = get_meta("rummage", null)
	var at_scrap: bool = state == ROAM and rum != null and is_instance_valid(rum) and global_position.distance_to(rum.global_position) < 1.4
	crouch = move_toward(crouch, 1.0 if at_scrap else 0.0, delta * 3.0)
	if at_scrap:
		face(rum.global_position, delta, 5.0)
	if randf() < delta * 0.6:
		_look_to = randf_range(-0.9, 0.9)
	if state == TAG_ALONG and prey != null and is_instance_valid(prey) and randf() < delta * 0.8:
		var to: Vector3 = to_local(prey.global_position)
		_look_to = clampf(atan2(-to.x, -to.z), -1.0, 1.0)   # a glance at you
	look = lerp_angle(look, _look_to if state != STRIKE else 0.0, minf(1.0, delta * 4.0))
	lit = level == null or not level.has_method("powered") or level.facility == null or global_position.y < level.facility.global_position.y + 6.0


func _valid() -> bool:
	if prey == null or not is_instance_valid(prey) or prey.dead or global_position.distance_to(prey.global_position) > SIGHT * 1.5:
		state = ROAM
		prey = null
		_errand()
		return false
	return true


func is_hunting() -> bool:
	return state == STRIKE


## Hit it and the act drops: it comes at you.
func react_to_hit(by) -> void:
	if by != null and is_instance_valid(by) and by.is_in_group("players"):
		prey = by
		state = STRIKE
		_t = 0.0


func act(_what: String, _args: Array) -> void:
	pass


## A crewmate's walk: legs and arms with the stride, a run leaning in, crouching to look at
## something, the head turning on its own; the torch in the right hand.
func _animate(delta: float) -> void:
	var g := _anim * 2.6
	var speed := Vector2(velocity.x, velocity.z).length()
	var amt := clampf(speed / 4.0, 0.0, 1.0)
	var run := clampf((speed - WALK) / (RUN - WALK), 0.0, 1.0)
	var s := sin(g)
	_parts.thigh_l.rotation.x = s * (0.6 + 0.3 * run) * amt + crouch * 1.4
	_parts.thigh_r.rotation.x = -s * (0.6 + 0.3 * run) * amt + crouch * 1.4
	_parts.shin_l.rotation.x = -maxf(0.0, -s) * 0.9 * amt - crouch * 2.2
	_parts.shin_r.rotation.x = -maxf(0.0, s) * 0.9 * amt - crouch * 2.2
	var body := get_node("Body") as Node3D
	body.position.y = -crouch * 0.55 + absf(cos(g)) * 0.03 * amt
	_parts.torso.rotation = Vector3(-0.08 * amt - 0.2 * run - crouch * 0.35, look * 0.15, 0)
	_parts.head.rotation = Vector3(0.35 * crouch, look * 0.85, 0)
	if state == STRIKE:
		_parts.upper_arm_l.rotation.x = lerpf(_parts.upper_arm_l.rotation.x, 1.3, minf(1.0, delta * 8.0))
		_parts.upper_arm_r.rotation.x = lerpf(_parts.upper_arm_r.rotation.x, 1.3, minf(1.0, delta * 8.0))
	else:
		_parts.upper_arm_l.rotation.x = lerpf(_parts.upper_arm_l.rotation.x, -s * 0.45 * amt + crouch * 0.6, minf(1.0, delta * 8.0))
		_parts.upper_arm_r.rotation.x = lerpf(_parts.upper_arm_r.rotation.x, 0.85 + s * 0.15 * amt, minf(1.0, delta * 8.0))   # (holding the torch out)
	_beam.visible = lit and not dead
	_beam.rotation = Vector3(-0.15 - crouch * 0.5, look * 0.7, 0)
	if speed > 0.4 and level != null and main.net.authority():   # footsteps, as a crewmate's (the crew hear the host's)
		_step += speed * delta
		if _step > (0.95 if run > 0.5 else 0.75):
			_step = 0.0
			Sfx.play(self, "step_" + main.surface_at(global_position), global_position, -9.0 if run < 0.5 else -6.0, randf_range(0.88, 1.12))
	_name_tag()


## Over its helmet, the name of one of the crew who isn't you: you see it as your crewmate. (Each
## machine picks for itself; on your own there's nobody for it to be.)
func _name_tag() -> void:
	var cam := get_viewport().get_camera_3d()
	var net = main.net if main != null else null
	if net == null or not net.active or dead or cam == null or cam.global_position.distance_to(global_position) > 14.0:
		_tag.visible = false
		return
	var others: Array = []
	for id in net.roster:
		if id != net.me():
			others.append(id)
	if others.is_empty():
		_tag.visible = false
		return
	others.sort()
	var as_id: int = others[int(get_meta("net_id", get_instance_id())) % others.size()]
	_tag.text = net.name_of(as_id)
	_tag.visible = true
	var look: Array = net.look_of(as_id)   # ...in their suit, their helmet, their name on its pack
	if look != _worn or _tag.text != _worn_by:
		_worn = look
		_worn_by = _tag.text
		Suit.apply_look(get_node("Body"), look, _tag.text)


func net_visual(delta: float) -> void:
	_t += delta
	super.net_visual(delta)


## It drops: a body again.
func death_anim() -> void:
	_beam.visible = false
	if main and main.net.authority() and level != null:
		var r = main.spawn_item("REMAINS", global_position + Vector3(0, 0.3, 0), -1.0, level)
		if r:
			r.set_meta("no_possess", true)
	queue_free()
