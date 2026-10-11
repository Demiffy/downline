# The Warden: flesh bolted into a steel frame, a searchlight for a head, scythes for hands.
# It can only see what its beam touches. Step into the light and it runs you down; get up on
# something it can't reach and it loses interest. Its footsteps carry a long way.
extends "res://src/monster.gd"

enum { PATROL, HUNT, SEARCH }
const WALK := 1.7
const RUN := 6.0
const SIGHT := 18.0
const CONE := 22.0   # half-angle of the beam, degrees

var state := PATROL
var _goal := Vector3.ZERO
var _last_seen := Vector3.ZERO
var _lost := 0.0
var _unreachable := 0.0
var _swing := 0.0
var _step := 0.0
var _head: Node3D
var _beam: SpotLight3D
var _lens: MeshInstance3D
var _lens_mat: StandardMaterial3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _prey


func _ready() -> void:
	_setup_body(0.45, 2.4)
	health = 160.0
	presence("searchlight", -8.0, 5.0)
	var steel := Color(0.55, 0.52, 0.5)
	# Digitigrade steel legs.
	for side in [-1, 1]:
		var thigh := limb(self, Vector3(side * 0.22, 1.35, 0), 0.7, 0.14, "metal", steel)
		var shin := limb(thigh, Vector3(0, -0.7, 0), 0.75, 0.11, "rust", Color.WHITE)
		A.box(shin, Vector3(0.18, 0.06, 0.34), Vector3(0, -0.76, -0.08), "metal", steel.darkened(0.3), false)
		A.sphere(thigh, 0.1, Vector3(0, -0.7, 0), "metal", steel.darkened(0.2))
		_legs.append(thigh)
		_legs.append(shin)
	# Flesh torso in a cage of steel bands.
	A.sphere(self, 0.42, Vector3(0, 1.75, 0), "flesh", Color(0.72, 0.42, 0.4), 0.05, 1.2)
	A.cyl(self, 0.09, 0.3, Vector3(0, 2.3, 0), "metal", Color(0.2, 0.2, 0.2))
	for side in [-1, 1]:
		var plate := A.box(self, Vector3(0.36, 0.12, 0.42), Vector3(side * 0.42, 2.12, 0), "riveted", Color(0.6, 0.55, 0.5), false, 0.6)
		plate.rotation.z = side * -0.35
	A.box(self, Vector3(0.5, 0.5, 0.06), Vector3(0, 1.8, -0.4), "riveted", Color(0.55, 0.5, 0.45), false, 0.6)
	for i in 4:
		A.cyl(self, 0.025, 0.7, Vector3(-0.25 + i * 0.16, 1.45, -0.3), "metal", Color(0.12, 0.12, 0.12), false, "y")
	for y in [1.5, 1.75, 2.0]:
		A.cyl(self, 0.43, 0.06, Vector3(0, y, 0), "rust", Color.WHITE)
	A.box(self, Vector3(0.1, 0.9, 0.5), Vector3(0, 1.75, 0.38), "metal", steel, false)
	for i in 3:
		A.cyl(self, 0.03, 0.5, Vector3(0.1 - i * 0.1, 2.15, 0.35), "metal", Color(0.2, 0.2, 0.2), false, "y")
	# Searchlight head.
	_head = Node3D.new()
	add_child(_head)
	_head.position = Vector3(0, 2.52, 0)
	A.cyl(_head, 0.24, 0.42, Vector3(0, 0, 0.0), "metal", Color(0.3, 0.3, 0.32), false, "z")
	A.cyl(_head, 0.27, 0.06, Vector3(0, 0, -0.21), "rust", Color.WHITE, false, "z")
	_lens = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.21
	cm.bottom_radius = 0.21
	cm.height = 0.02
	_lens.mesh = cm
	_lens_mat = glow_mat(Color(1, 0.95, 0.8), 6.0)
	_lens.material_override = _lens_mat
	_head.add_child(_lens)
	_lens.position.z = -0.25   # proud of the rim, or the rim hides it
	_lens.rotation.x = PI / 2
	_beam = SpotLight3D.new()
	_beam.light_color = Color(1, 0.95, 0.8)
	_beam.light_energy = 6.0
	_beam.spot_range = SIGHT + 4.0
	_beam.spot_angle = CONE
	_beam.shadow_enabled = true
	_beam.light_volumetric_fog_energy = 3.0
	_head.add_child(_beam)
	_beam.position.z = -0.3    # outside the housing so it isn't self-shadowed
	_beam.rotation.x = -0.12
	# Scythe arms.
	for side in [-1, 1]:
		var upper := limb(self, Vector3(side * 0.5, 2.0, 0), 0.6, 0.1, "metal", steel)
		var fore := limb(upper, Vector3(0, -0.6, 0), 0.55, 0.08, "rust", Color.WHITE)
		var blade := A.box(fore, Vector3(0.03, 1.1, 0.16), Vector3(0, -0.85, -0.25), "metal", Color(0.85, 0.85, 0.82), false, 0.4)
		blade.rotation.x = 0.5
		A.box(fore, Vector3(0.04, 0.4, 0.08), Vector3(0, -1.35, -0.55), "metal", Color(0.85, 0.85, 0.82), false, 0.3, Vector3(1.4, 0, 0))
		upper.rotation = Vector3(0.3, 0, side * 0.25)
		fore.rotation.x = -0.32   # (the scythe tip carried just clear of the floor)
		_arms.append(upper)
		_arms.append(fore)
	_goal = global_position


## Is the player standing in the beam (and not behind a wall)?
func _in_beam(p) -> bool:
	var target: Vector3 = p.global_position + Vector3(0, 1.0, 0)
	var origin := _beam.global_position
	var to := target - origin
	if to.length() > SIGHT:
		return false
	var fwd := -_beam.global_transform.basis.z
	if rad_to_deg(fwd.angle_to(to)) > CONE * 0.95:
		return false
	var q := PhysicsRayQueryParameters3D.create(origin, target, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _physics_process(delta: float) -> void:
	var seen = null
	for p in alive_players():
		if _in_beam(p):
			seen = p
			break
	if seen != null:
		if state != HUNT:
			Sfx.play(self, "roar", global_position + Vector3.UP * 2.0, 6.0, 1.3)
		state = HUNT
		_prey = seen
		_last_seen = seen.global_position
		_lost = 0.0
	match state:
		PATROL:
			_head.rotation.y = sin(Time.get_ticks_msec() / 1000.0 * 0.8) * 0.7
			if walk_to(_goal, WALK, delta, 3.0) == Vector3.ZERO:
				_goal = level.wander_point(global_position) if level else global_position
		HUNT, SEARCH:
			_head.rotation.y = lerpf(_head.rotation.y, 0.0, delta * 6.0)
			_lost += delta
			if _lost > 4.0:
				state = PATROL
				_goal = level.wander_point(global_position) if level else global_position
			var dist := _last_seen.distance_to(global_position)
			if is_instance_valid(_prey) and not _prey.dead and _prey.global_position.distance_to(global_position) < 2.0:
				_strike(delta)
			elif dist > 1.0:
				walk_to(_last_seen, RUN, delta, 8.0)
			else:
				stand_still(delta)
			# Can't climb: if they're up on something, it gives up after a moment.
			if is_instance_valid(_prey) and _prey.global_position.y > global_position.y + 0.9 and Vector2(_prey.global_position.x - global_position.x, _prey.global_position.z - global_position.z).length() < 3.0:
				_unreachable += delta
				if _unreachable > 2.5:
					state = PATROL
					_unreachable = 0.0
					_goal = level.wander_point(global_position) if level else global_position
			else:
				_unreachable = 0.0
	var red := state != PATROL
	_beam.light_color = Color(1, 0.25, 0.15) if red else Color(1, 0.95, 0.8)
	_lens_mat.emission = _beam.light_color
	_animate(delta)


func _strike(delta: float) -> void:
	stand_still(delta)
	face(_prey.global_position, delta, 12.0)
	_swing -= delta
	if _swing <= 0.0:
		_swing = 1.1
		show_act("swing", [randi() % 2])
		Sfx.play(self, "snap", global_position + Vector3.UP * 1.5, 2.0, 0.5)
		if _prey.global_position.distance_to(global_position) < 2.3:
			_prey.hurt(50.0, "Cut down by the warden.")
			_prey.shake(0.05)


func act(what: String, args: Array) -> void:
	if what == "swing":
		var tw := create_tween()
		tw.tween_property(_arms[args[0] * 2], "rotation:x", -1.6, 0.18)
		tw.tween_property(_arms[args[0] * 2], "rotation:x", 0.3, 0.4)


func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var s := sin(_anim * 2.2)
	for k in 2:
		var side := 1.0 if k == 0 else -1.0
		_legs[k * 2].rotation.x = 0.35 + s * 0.5 * side * minf(1.0, speed)
		_legs[k * 2 + 1].rotation.x = -0.7 + maxf(0.0, s * side) * 0.6 * minf(1.0, speed)
	# The planted leg straightens past its hip height: lift both legs' roots (inside the body)
	# by however far its foot would sink.
	var lowest := INF
	for k in 2:
		var shin: Node3D = _legs[k * 2 + 1]
		for q in [Vector3(0, -0.79, -0.25), Vector3(0, -0.79, 0.09)]:
			lowest = minf(lowest, (shin.global_transform * q).y)
	var lift := maxf(0.0, global_position.y - (lowest - (_legs[0].position.y - 1.35)))   # (measured from where the legs hang unlifted)
	for k in 2:
		_legs[k * 2].position.y = 1.35 + lift
	_step -= delta
	if speed > 0.5 and _step <= 0.0:
		_step = 0.55 if state == PATROL else 0.28
		Sfx.play(self, "thud", global_position, 6.0 if state == PATROL else 10.0, randf_range(0.8, 1.0))
		for p in alive_players():
			if p.global_position.distance_to(global_position) < 8.0:
				p.shake(0.01)


# --- hits and death ---

func react_to_hit(by) -> void:
	if by != null:   # it knows where that came from
		if state != HUNT:
			Sfx.play(self, "roar", global_position + Vector3.UP * 2.0, 6.0, 1.3)
		state = HUNT
		_prey = by
		_last_seen = by.global_position
		_lost = 0.0


## The searchlight stutters out; it drops to its knees, then pitches forward onto its face.
func death_anim() -> void:
	Sfx.play(self, "roar", global_position + Vector3.UP * 2.0, 6.0, 0.6)
	var tw := create_tween()
	for k in 5:
		tw.tween_callback(func(): _beam.visible = not _beam.visible)
		tw.tween_interval(0.07 + k * 0.03)
	tw.tween_callback(func():
		_beam.visible = false
		_lens_mat.emission_energy_multiplier = 0.0)
	var fall := create_tween().set_parallel()
	for k in 2:
		fall.tween_property(_legs[k * 2], "rotation:x", -1.3, 0.5).set_delay(0.2)
		fall.tween_property(_legs[k * 2 + 1], "rotation:x", 2.2, 0.5).set_delay(0.2)
		fall.tween_property(_arms[k * 2], "rotation", Vector3(-0.4, 0, (k * 2 - 1) * 0.9), 0.6).set_delay(0.2)
	fall.tween_property(self, "position:y", position.y - 0.85, 0.5).set_delay(0.2).set_ease(Tween.EASE_IN)
	fall.tween_property(self, "rotation:x", -1.35, 0.55).set_delay(0.75).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	fall.tween_property(self, "position:y", position.y + 0.05, 0.55).set_delay(0.75).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(0.7, false).timeout.connect(Sfx.play.bind(self, "thud", global_position, 8.0, 0.8))
	get_tree().create_timer(1.15, false).timeout.connect(Sfx.play.bind(self, "clang_big", global_position, 2.0, 1.4))


func is_hunting() -> bool:
	return state != PATROL


func net_visual(delta: float) -> void:
	super(delta)
	var red := state != PATROL
	_beam.light_color = Color(1, 0.25, 0.15) if red else Color(1, 0.95, 0.8)
	_lens_mat.emission = _beam.light_color
	if state == PATROL:
		_head.rotation.y = sin(Time.get_ticks_msec() / 1000.0 * 0.8) * 0.7
