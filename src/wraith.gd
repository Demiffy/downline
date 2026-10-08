# The Wraith: what's left of a miner who was down here when the lights went out. A tall hunched
# shroud of rotten canvas, hovering, its cracked hard hat still on, its lamp long dead, a chain
# dragging behind it. It carries the dark with it: lamps gutter and die as it passes, your visor
# frosts over, you hear whispering. It drifts after you a little slower than you walk.
# Light is the answer. Hold a flashlight beam on it and it shrieks, recoils and, held long enough,
# comes apart (the beam drains your battery fast while you do). A lit lantern keeps it at arm's
# length but no closer. Let it reach you in the dark and it takes a heavy, cold bite out of you,
# then is gone, to come back somewhere else. A power failure makes it faster.
extends "res://src/monster.gd"

enum { DRIFT, STALK, BURN, GONE }
const DRIFT_SPEED := 1.0
const STALK_SPEED := 3.0     # you walk at 4
const DARK_SPEED := 3.8      # ...and during a power failure
const BEAM_RANGE := 15.0
const BURN_T := 1.6          # seconds of beam to drive it off
const LANTERN_R := 3.4
const HIT := 45.0
const SHROUD := Color(0.24, 0.23, 0.22)
const SKIN := Color(0.62, 0.66, 0.7)   # long-dead grey

var _dropped := false   # its helmet came off the first time the light took it apart
var state := DRIFT
var burn := 0.0
var _goal := Vector3.ZERO
var _gone_t := 0.0
var _shrieked := false
var _float: Node3D
var _torso: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []    # [l_upper, l_fore, r_upper, r_fore]
var _fingers: Array[Node3D] = []
var _tail: Array[Node3D] = []    # dragging chain links
var _eye_mat: StandardMaterial3D
var _dark: OmniLight3D
var _mist: GPUParticles3D
var _voice: AudioStreamPlayer3D
var _rattle: AudioStreamPlayer3D
var _t := 0.0
var _haunted := {}   # light -> true, lights it is currently dimming
var _lights: Array = []


func _ready() -> void:
	_setup_body(0.4, 2.2)
	add_to_group("wraiths")
	_voice = presence("whisper", -4.0, 4.0)
	_rattle = presence("rattle", -16.0, 2.0)
	_float = Node3D.new()
	add_child(_float)
	_float.position.y = 0.3
	_build()
	_goal = global_position
	_t = randf() * 10.0


# --- model -------------------------------------------------------------------------------

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()   # (seeded by net.gd for a crewmate's copy)
	# Shroud: a long skirt of rotten canvas, narrowing to a hunched cowl.
	A.cyl(_float, 0.44, 1.1, Vector3(0, 0.6, 0), "canvas", SHROUD, false, "y", 0.27)
	A.cyl(_float, 0.36, 0.9, Vector3(0, 0.5, 0.04), "canvas", SHROUD.darkened(0.2), false, "y", 0.22)   # under-layer
	for i in 10:   # fold ridges down the skirt
		var a := TAU * i / 10.0 + rng.randf() * 0.3
		var fold := A.cyl(_float, 0.035, 1.0, Vector3(sin(a) * 0.36, 0.62, cos(a) * 0.36), "canvas", SHROUD.darkened(0.12), false, "y", 0.015)
		fold.rotation = Vector3(-0.17 * cos(a), 0, 0.17 * sin(a))
	# Rags hanging off the hem: thin tapering strips of different lengths, each swaying on its own.
	for i in 30:
		var a := TAU * i / 30.0 + rng.randf_range(-0.08, 0.08)
		var r := 0.41 + rng.randf() * 0.05
		var hang := Node3D.new()
		_float.add_child(hang)
		hang.position = Vector3(sin(a) * r, 0.1 + rng.randf() * 0.12, cos(a) * r)
		hang.rotation.y = a
		var length := rng.randf_range(0.2, 0.75)
		var w := rng.randf_range(0.05, 0.13)
		var rag := A.prism(hang, Vector3(w, length, 0.006), Vector3(0, -length / 2.0, 0), "canvas", SHROUD.darkened(rng.randf() * 0.35), Vector3(0.1 + rng.randf() * 0.1, 0, PI + rng.randf_range(-0.12, 0.12)), 0.4)
		rag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		A.sway(hang, rng.randf_range(0.06, 0.18), rng.randf_range(0.7, 1.5))
	# Upper body, leaning in.
	_torso = Node3D.new()
	_float.add_child(_torso)
	_torso.position.y = 1.1
	_torso.rotation.x = -0.32
	A.cyl(_torso, 0.27, 0.6, Vector3(0, 0.3, 0), "canvas", SHROUD, false, "y", 0.2)
	var cowl := A.sphere(_torso, 0.28, Vector3(0, 0.62, 0.03), "canvas", SHROUD.darkened(0.1), 0.0, 0.8)
	cowl.scale = Vector3(1.25, 1.0, 1.05)
	for side in [-1, 1]:   # bony shoulder points under the cloth
		A.sphere(_torso, 0.09, Vector3(side * 0.27, 0.64, 0.02), "canvas", SHROUD)
	# Chain: a loop round the waist and a length dragging behind, ending in a broken padlock.
	var rust := Color(0.75, 0.55, 0.42)
	for k in 16:
		var a := TAU * k / 16.0
		A.ring(_float, 0.042, 0.026, Vector3(sin(a) * 0.36, 0.95 + sin(a * 2.0) * 0.03, cos(a) * 0.36), "rust", rust, Vector3(PI / 2 * (k % 2), a, 0.3))
	var prev := Vector3(0.1, 0.9, 0.38)
	for k in 12:
		var link := Node3D.new()
		_float.add_child(link)
		link.position = prev
		A.ring(link, 0.042, 0.026, Vector3.ZERO, "rust", rust, Vector3(PI / 2 * (k % 2), 0, PI / 2))
		_tail.append(link)
		prev += Vector3(0.01, -0.1 if k < 9 else -0.02, 0.06 if k < 9 else 0.07)
	A.box(_tail[-1], Vector3(0.07, 0.08, 0.035), Vector3(0, -0.06, 0.02), "brass", Color(0.6, 0.5, 0.35), false, 0.2)
	A.ring(_tail[-1], 0.03, 0.02, Vector3(0, -0.01, 0.02), "metal", Color(0.5, 0.5, 0.5), Vector3(PI / 2, 0, 0))
	# Head: a deep hood with nothing in it but two cold points of light, under a cracked hard hat.
	_head = Node3D.new()
	_torso.add_child(_head)
	_head.position = Vector3(0, 0.84, -0.06)
	var hood := A.sphere(_head, 0.2, Vector3(0, 0, 0.04), "canvas", SHROUD.darkened(0.15), 0.0, 1.1)
	hood.scale = Vector3(1.0, 1.0, 1.15)
	A.cyl(_head, 0.16, 0.22, Vector3(0, 0.0, -0.12), "canvas", SHROUD.darkened(0.25), false, "z", 0.19)   # hood mouth
	var void_mat := StandardMaterial3D.new()
	void_mat.albedo_color = Color.BLACK
	void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var hole := MeshInstance3D.new()
	var vm := SphereMesh.new()
	vm.radius = 0.15
	vm.height = 0.26
	hole.mesh = vm
	hole.material_override = void_mat
	_head.add_child(hole)
	hole.position = Vector3(0, -0.01, -0.14)
	_eye_mat = glow_mat(Color(0.7, 0.88, 1.0), 5.0)
	for x in [-0.045, 0.045]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.016
		em.height = 0.022
		eye.mesh = em
		eye.material_override = _eye_mat
		_head.add_child(eye)
		eye.position = Vector3(x, 0.02, -0.24)
	var hat := Node3D.new()
	_head.add_child(hat)
	hat.position = Vector3(0, 0.15, 0.0)
	hat.rotation = Vector3(-0.15, 0, 0.12)
	var yellow := Color(0.78, 0.63, 0.26)
	A.sphere(hat, 0.17, Vector3(0, 0.02, 0), "plastic", yellow, 0.0, 0.75)
	A.cyl(hat, 0.21, 0.016, Vector3(0, -0.03, -0.02), "plastic", yellow.darkened(0.1))
	A.box(hat, Vector3(0.03, 0.11, 0.33), Vector3(0, 0.07, 0), "plastic", yellow.darkened(0.05), false, 0.2)   # ridge
	A.box(hat, Vector3(0.006, 0.09, 0.006), Vector3(0.07, 0.06, -0.12), "metal", Color(0.08, 0.08, 0.08), false, 0.1, Vector3(0.3, 0, 0.5))   # crack
	A.box(hat, Vector3(0.006, 0.06, 0.006), Vector3(0.1, 0.03, -0.09), "metal", Color(0.08, 0.08, 0.08), false, 0.1, Vector3(-0.2, 0, -0.6))
	A.box(hat, Vector3(0.05, 0.05, 0.02), Vector3(0, 0.03, -0.165), "metal", Color(0.3, 0.3, 0.3), false, 0.2)   # lamp bracket
	A.cyl(hat, 0.032, 0.05, Vector3(0, 0.04, -0.19), "metal", Color(0.4, 0.4, 0.38), false, "z")   # dead headlamp
	var lens := A.cyl(hat, 0.026, 0.004, Vector3(0, 0.04, -0.216), "metal", Color(0.12, 0.13, 0.12), false, "z")
	lens.rotation.x = PI / 2
	A.seg(hat, Vector3(0, 0.04, -0.16), Vector3(0.12, -0.25, 0.1), 0.006, 0.006, "rubber")   # lamp cord
	A.seg(_torso, Vector3(0.14, 0.62, 0.05), Vector3(0.2, 0.05, 0.12), 0.006, 0.006, "rubber")
	A.box(_torso, Vector3(0.12, 0.16, 0.06), Vector3(0.2, 0.02, 0.17), "rubber", Color.WHITE, false, 0.2)   # battery pack
	# Arms: ragged sleeves, then long grey forearms and hands with too-long fingers, reaching.
	for side in [-1, 1]:
		var upper := Node3D.new()
		_torso.add_child(upper)
		upper.position = Vector3(side * 0.3, 0.6, 0)
		A.cyl(upper, 0.075, 0.5, Vector3(0, -0.25, 0), "canvas", SHROUD, false, "y", 0.065)
		A.cyl(upper, 0.085, 0.06, Vector3(0, -0.5, 0), "canvas", SHROUD.darkened(0.2), false, "y", 0.075)   # frayed cuff
		for k in 4:   # short ragged ends round the cuff, following the arm
			var ca := TAU * k / 4.0 + 0.4
			A.prism(upper, Vector3(0.05, 0.1 + 0.03 * (k % 2), 0.005), Vector3(sin(ca) * 0.08, -0.57, cos(ca) * 0.08), "canvas", SHROUD.darkened(0.25), Vector3(0, ca, PI), 0.3)
		var fore := Node3D.new()
		upper.add_child(fore)
		fore.position.y = -0.48
		A.sphere(fore, 0.04, Vector3.ZERO, "cream", SKIN)
		A.seg(fore, Vector3.ZERO, Vector3(0, -0.52, 0), 0.03, 0.022, "cream", SKIN)
		A.seg(fore, Vector3(0.012, -0.05, 0.01), Vector3(0.014, -0.48, 0.008), 0.012, 0.01, "cream", SKIN.darkened(0.15))   # second bone showing
		var hand := Node3D.new()
		fore.add_child(hand)
		hand.position.y = -0.54
		A.box(hand, Vector3(0.07, 0.09, 0.025), Vector3(0, -0.04, 0), "cream", SKIN, false, 0.2)
		for f in 4:
			var knuckle := Node3D.new()
			hand.add_child(knuckle)
			knuckle.position = Vector3(-0.027 + f * 0.018, -0.085, 0)
			A.seg(knuckle, Vector3.ZERO, Vector3(0, -0.12 + absf(f - 1.5) * 0.015, 0), 0.008, 0.006, "cream", SKIN)
			var tip := Node3D.new()
			knuckle.add_child(tip)
			tip.position.y = -0.12 + absf(f - 1.5) * 0.015
			A.seg(tip, Vector3.ZERO, Vector3(0, -0.09, 0), 0.006, 0.003, "cream", SKIN.darkened(0.3))
			_fingers.append(knuckle)
			_fingers.append(tip)
		var thumb := A.seg(hand, Vector3(side * -0.035, -0.03, -0.01), Vector3(side * -0.06, -0.12, -0.04), 0.008, 0.005, "cream", SKIN)
		thumb.set_meta("live", true)
		_arms.append(upper)
		_arms.append(fore)
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# The dark it carries: a negative light that eats the light around it, and a cold mist off the hem.
	_dark = OmniLight3D.new()
	_dark.light_negative = true
	_dark.light_energy = 2.2
	_dark.omni_range = 4.5
	_dark.light_color = Color(1, 0.95, 0.85)
	add_child(_dark)
	_dark.position.y = 1.2
	_mist = GPUParticles3D.new()
	_mist.amount = 28
	_mist.lifetime = 2.6
	_mist.local_coords = false
	_mist.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.42
	pm.emission_ring_inner_radius = 0.2
	pm.emission_ring_height = 0.1
	pm.direction = Vector3(0, -0.3, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3(0, -0.15, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	var fade := Gradient.new()
	fade.set_color(0, Color(0.55, 0.6, 0.66, 0.0))
	fade.add_point(0.25, Color(0.55, 0.6, 0.66, 0.22))
	fade.set_color(fade.get_point_count() - 1, Color(0.55, 0.6, 0.66, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	_mist.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.6, 0.6)
	var mm := StandardMaterial3D.new()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_texture = _puff()
	qm.material = mm
	_mist.draw_pass_1 = qm
	_float.add_child(_mist)
	_mist.position.y = 0.05


## A soft round puff for the mist (so the particles aren't hard squares).
static func _puff() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2))
	return ImageTexture.create_from_image(img)


# --- behaviour ---------------------------------------------------------------------------

## Who's holding a lit flashlight on it (beam, range, nothing in between)?
func _in_beam(p) -> bool:
	if p.dead or not p.light_on or not p.spot.visible:
		return false
	var at := global_position + Vector3(0, 1.4, 0)
	var from: Vector3 = p.spot.global_position
	var to := at - from
	if to.length() > BEAM_RANGE:
		return false
	var fwd: Vector3 = -p.spot.global_transform.basis.z
	if rad_to_deg(fwd.angle_to(to)) > p.spot.spot_angle * 0.9:
		return false
	return seen_by(p, at, -1.0, BEAM_RANGE)


func _lantern_near(p) -> bool:
	return p.lamp.visible and p.global_position.distance_to(global_position) < LANTERN_R + 1.2


func _physics_process(delta: float) -> void:
	_t += delta
	if state == GONE:
		_gone_t -= delta
		if _gone_t <= 0.0:
			_reform()
		return
	var prey = nearest_player(20.0)
	if prey != null and absf(prey.global_position.y - global_position.y) > 3.0:
		prey = null
	var burner = null
	for p in alive_players():
		if _in_beam(p):
			burner = p
	if burner != null:
		state = BURN
	elif state == BURN:
		burn = maxf(0.0, burn - delta * 0.5)
		if burn <= 0.2:
			state = STALK if prey != null else DRIFT
			_shrieked = false
	elif prey != null:
		state = STALK
	elif state == STALK:
		state = DRIFT
	match state:
		DRIFT:
			if walk_to(_goal, DRIFT_SPEED, delta, 2.0) == Vector3.ZERO:
				_goal = level.wander_point(global_position) if level else global_position
		STALK:
			_stalk(prey, delta)
		BURN:
			if burner != null:
				_burn(burner, delta)
			else:
				stand_still(delta)
	_haunt_lights()
	_animate(delta)
	if state == GONE:
		return
	for p in alive_players():   # the cold reaches you before it does
		var d: float = p.global_position.distance_to(global_position)
		if d < 6.0 and p == main.player:
			main.hud.fog_visor(0.45 * (1.0 - d / 6.0))


func _stalk(prey, delta: float) -> void:
	var dist: float = prey.global_position.distance_to(global_position)
	if _lantern_near(prey) and dist < LANTERN_R + 0.4:   # lamplight: it hangs at the edge of it
		stand_still(delta)
		face(prey.global_position, delta, 3.0)
		_drain(prey, delta * 1.5)
		return
	var dark: bool = level != null and level.has_method("powered") and not level.powered()
	walk_to(prey.global_position, DARK_SPEED if dark else STALK_SPEED, delta, 4.0)
	if dist < 1.25:
		Sfx.play(self, "wraith_grab", global_position + Vector3.UP * 1.5, 6.0)
		prey.hurt(HIT, "Taken by the cold.")
		prey.shake(0.08)
		prey.light_on = false
		prey.fog_visor(1.0)
		_vanish(25.0)


func _burn(p, delta: float) -> void:
	if not _shrieked:
		_shrieked = true
		Sfx.play(self, "wraith_shriek", global_position + Vector3.UP * 1.8, 6.0, randf_range(0.9, 1.1))
	burn += delta
	_drain(p, delta * 3.0)
	# Recoil: back away from the light, writhing.
	var away: Vector3 = global_position - p.global_position
	away.y = 0.0
	velocity = away.normalized() * 1.6
	velocity.y = -1.0
	move_and_slide()
	face(p.global_position, delta, 6.0)
	if burn >= BURN_T:
		_vanish(35.0)


## Whatever light you're holding runs down faster near it.
func _drain(p, amount: float) -> void:
	if p.has_method("drain"):   # a crewmate's light: theirs to run down
		p.drain(amount)
		return
	var it = p.slots[p.sel]
	if it != null and it.get("charge", -1.0) > 0.0:
		it.charge = maxf(0.0, it.charge - amount)


## Comes apart into mist, and is gone for a while.
func _vanish(secs: float) -> void:
	state = GONE
	_gone_t = secs
	burn = 0.0
	_shrieked = false
	Sfx.play(self, "dissolve", global_position + Vector3.UP * 1.2, 2.0)
	collision_layer = 0
	remove_from_group("monsters")
	if not _dropped and main.net.authority() and level != null:   # the first time: its cracked helmet falls
		_dropped = true
		main.spawn_item("MINERS_HELMET", global_position + Vector3(0, 1.4, 0), -1.0, level)
	_dissolve()


## The look of it coming apart (here, and on a crewmate's copy).
func _dissolve() -> void:
	_release_lights()
	_voice.stop()
	_rattle.stop()
	_float.visible = false
	_dark.visible = false
	var puff := _mist.duplicate() as GPUParticles3D   # a last burst of mist where it stood
	get_parent().add_child(puff)
	puff.global_position = global_position + Vector3(0, 1.0, 0)
	puff.one_shot = true
	puff.amount = 40
	puff.explosiveness = 0.9
	puff.emitting = true
	get_tree().create_timer(4.0, false).timeout.connect(puff.queue_free)


## Back again: somewhere far from everyone.
func _reform() -> void:
	var at := global_position
	if level != null and level.facility != null:
		for i in 12:
			at = level.facility.random_point(level.rng, true)
			if alive_players().all(func(p): return p.global_position.distance_to(at) > 22.0):
				break
	global_position = at
	velocity = Vector3.ZERO
	_route.clear()
	state = DRIFT
	_goal = at
	_float.visible = true
	_dark.visible = true
	collision_layer = 8
	add_to_group("monsters")
	_voice.play()
	_rattle.play()


## Lamps near it gutter and die; they come back once it has passed.
func _haunt_lights() -> void:
	if level == null or level.facility == null or Engine.get_physics_frames() % 6 != 0:
		return
	var fac = level.facility
	var near := {}
	if _lights.is_empty():
		_lights = fac.find_children("*", "Light3D", true, false)
	if state != GONE:
		for l: Light3D in _lights:
			if not is_instance_valid(l):
				continue
			var d := l.global_position.distance_to(global_position)
			if d < 9.0:
				near[l] = true
				var k := clampf((d - 3.0) / 6.0, 0.0, 1.0)
				fac.haunt(l, k * randf_range(0.5, 1.0) if k > 0.0 else 0.0)
	for l in _haunted:
		if not near.has(l) and is_instance_valid(l):
			fac.haunt(l, 1.0)
	_haunted = near


func _release_lights() -> void:
	if is_instance_valid(level) and not level.is_queued_for_deletion() and is_instance_valid(level.facility):
		for l in _haunted:
			if is_instance_valid(l):
				level.facility.haunt(l, 1.0)
	_haunted = {}


func _exit_tree() -> void:
	_release_lights()


func _animate(delta: float) -> void:
	_float.position.y = 0.3 + sin(_t * 1.3) * 0.06
	_float.rotation.z = sin(_t * 0.7) * 0.04
	var reach := 1.0 if state == STALK else 0.45
	var writhe := 1.0 if state == BURN else 0.0
	for k in 2:
		var side := -1.0 if k == 0 else 1.0
		var sway := sin(_t * 1.1 + k * 1.7) * 0.12
		_arms[k * 2].rotation = Vector3(lerpf(_arms[k * 2].rotation.x, lerpf(0.25, 1.15, reach) + sway - writhe * 0.9, minf(1.0, delta * 3.0)),
			0, side * (0.18 + writhe * 0.5 + sin(_t * 7.0 + k) * 0.25 * writhe))
		_arms[k * 2 + 1].rotation.x = lerpf(_arms[k * 2 + 1].rotation.x, lerpf(0.3, 0.55, reach) + writhe * 0.8, minf(1.0, delta * 3.0))
	for i in _fingers.size():   # fingers curl and uncurl, slowly; clench when it burns
		_fingers[i].rotation.x = 0.35 + sin(_t * 1.6 + i * 0.7) * 0.25 + writhe * 0.6
	_head.rotation = Vector3(-0.1 + sin(_t * 0.5) * 0.08 + writhe * 0.4, sin(_t * 0.37) * 0.25, sin(_t * 0.9) * 0.1 + sin(_t * 9.0) * 0.15 * writhe)
	_torso.rotation.x = lerpf(_torso.rotation.x, -0.32 - writhe * -0.45, minf(1.0, delta * 4.0))
	for i in _tail.size():   # the chain drags and jerks behind it
		_tail[i].rotation.x = sin(_t * 2.0 + i * 0.6) * 0.1
	_eye_mat.emission_energy_multiplier = 9.0 + sin(_t * 3.0) * 2.0 + writhe * 8.0
	_dark.light_energy = 2.2 - writhe * 1.5
	_voice.volume_db = -4.0 if state != BURN else -14.0


# --- hits ---

## Steel and shot go straight through it. Only light hurts it.
func take_hit(_dmg: float, from: Vector3, by = null) -> void:
	if state == GONE:
		return
	var at := global_position + Vector3(0, 1.3, 0)
	hit_fx(self, at, (from - at).normalized(), "cloth")
	var key := "told_%d" % (by.get_instance_id() if by != null else 0)
	if not get_meta(key, false):
		set_meta(key, true)
		tell(by, "It goes straight through cold cloth. It wants light, not steel.")


func is_hunting() -> bool:
	return state == STALK


var _shown := -1

## A copy: it drifts and writhes, our lamps die as it passes, our visor frosts when it's close, it
## comes apart in mist and forms again.
func net_visual(delta: float) -> void:
	_t += delta
	if state != _shown:
		if state == GONE and _shown != -1:
			_dissolve()
		elif _shown == GONE or _shown == -1:
			_float.visible = state != GONE
			_dark.visible = state != GONE
			if state != GONE and not _voice.playing:
				_voice.play()
				_rattle.play()
		_shown = state
	if state == GONE:
		return
	_animate(delta)
	_haunt_lights()
	var p = main.player
	if p != null and not p.dead:
		var d: float = p.global_position.distance_to(global_position)
		if d < 6.0:
			main.hud.fog_visor(0.45 * (1.0 - d / 6.0))
