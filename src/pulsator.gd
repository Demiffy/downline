# The Pulsator: a glowing flesh sac that walks on three human arms. It lights up the dark round it
# in a slow red pulse and you hear it long before you see it: a heartbeat and a wet gurgle. Blind:
# it hears footsteps (crouch-walking is silent to it). Once it hears you it locks on, swells, its
# glow and pustules strobe faster and faster, and it bursts when the fuse runs out if anyone is
# close, or on contact. Out of reach when the fuse runs out, it deflates and loses interest.
extends "res://src/monster.gd"

const FUSE := 6.5
const CHASE_SPEED := 4.3     # faster than a walk, slower than a sprint
const WANDER_SPEED := 1.1
const BURST_REACH := 3.5     # bursts at the end of its fuse only if someone is this close
const GLOW := Color(1.0, 0.32, 0.16)

var chasing := false
var target := Vector3.ZERO
var prey
var fuse := 0.0
var calm := 0.0              # after giving up: a few deaf seconds
var _wander := 0.0
var _step := 0.0
var _gurgle := 2.0
var _body: Node3D
var _skin: StandardMaterial3D
var _vein_mat: StandardMaterial3D
var _pustules: Array[StandardMaterial3D] = []
var _arms: Array[Node3D] = []   # [upper, fore] x3
var _breath := 0.0
var _beat: AudioStreamPlayer3D
var _light: OmniLight3D


func _ready() -> void:
	_setup_body(0.4, 1.1, true)
	health = 45.0
	_beat = presence("heartbeat", -2.0, 7.0)
	_beat.max_distance = 30.0
	add_to_group("pulsators")
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()   # (seeded by net.gd for a crewmate's copy)
	_body = Node3D.new()
	add_child(_body)
	_body.position.y = 1.05
	# Wet, translucent-looking skin with the glow coming through it.
	_skin = StandardMaterial3D.new()
	_skin.albedo_texture = A.texture("flesh")
	_skin.albedo_color = Color(0.9, 0.58, 0.55)
	_skin.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_skin.uv1_triplanar = true
	_skin.uv1_scale = Vector3.ONE * 2.0
	_skin.roughness = 0.3
	_skin.metallic_specular = 0.8
	_skin.rim_enabled = true
	_skin.rim = 0.6
	_skin.rim_tint = 0.3
	_skin.emission_enabled = true
	_skin.emission = GLOW
	_skin.emission_texture = A.texture("flesh")
	_skin.emission_energy_multiplier = 0.5
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.46
	sm.height = 1.1
	sm.radial_segments = 24
	sm.rings = 12
	shell.mesh = sm
	shell.material_override = _skin
	_body.add_child(shell)
	# A lumpier lower lobe and the puckered vent underneath.
	var lobe := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.36
	lm.height = 0.5
	lobe.mesh = lm
	lobe.material_override = _skin
	_body.add_child(lobe)
	lobe.position = Vector3(0.05, -0.3, -0.04)
	A.ring(_body, 0.1, 0.05, Vector3(0, -0.53, 0), "flesh", Color(0.45, 0.06, 0.08))
	# Glowing veins running over the shell: chains of short strands along arcs of the sphere.
	_vein_mat = StandardMaterial3D.new()
	_vein_mat.albedo_color = Color(0.35, 0.03, 0.05)
	_vein_mat.emission_enabled = true
	_vein_mat.emission = Color(0.9, 0.12, 0.06)
	_vein_mat.emission_energy_multiplier = 1.2
	for k in 11:
		var p := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var axis := p.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		var prev := _on_shell(p)
		var thick := rng.randf_range(0.014, 0.024)
		for s in rng.randi_range(4, 7):
			p = p.rotated(axis, rng.randf_range(0.18, 0.3)).rotated(p, rng.randf_range(-0.3, 0.3))
			var cur := _on_shell(p)
			var v := A.seg(_body, prev, cur, thick, thick * 0.85, "flesh")
			v.material_override = _vein_mat
			prev = cur
			thick *= 0.88
	# Pustules that blink with the fuse.
	for k in 9:
		var a := TAU * k / 9.0 + 0.3
		var lat := 0.35 if k % 2 == 0 else -0.1
		var pm := glow_mat(Color(1, 0.62, 0.25), 1.0)
		var bump := MeshInstance3D.new()
		var bmesh := SphereMesh.new()
		bmesh.radius = rng.randf_range(0.05, 0.08)
		bmesh.height = bmesh.radius * 1.4
		bump.mesh = bmesh
		bump.material_override = pm
		_body.add_child(bump)
		bump.position = _on_shell(Vector3(cos(a) * cos(lat), sin(lat), sin(a) * cos(lat)))
		_pustules.append(pm)
	_light = OmniLight3D.new()   # it lights the corridor round it: you see it coming
	_light.light_color = GLOW
	_light.omni_range = 4.5
	_light.light_energy = 0.6
	_light.shadow_enabled = false
	B.fade(_light)
	_body.add_child(_light)
	# Three human arms for legs: shoulder at the body, elbow, hand planted on the floor.
	var skin := Color(0.95, 0.76, 0.7)
	for i in 3:
		var a := TAU * i / 3.0
		var root := Node3D.new()
		add_child(root)
		root.position = Vector3(sin(a) * 0.36, 0.92, cos(a) * 0.36)
		root.rotation.y = a
		var upper := Node3D.new()
		root.add_child(upper)
		A.seg(upper, Vector3.ZERO, Vector3(0, -0.55, 0), 0.075, 0.058, "flesh", skin)
		A.sphere(upper, 0.08, Vector3.ZERO, "flesh", skin.darkened(0.08))
		var fore := Node3D.new()
		upper.add_child(fore)
		fore.position = Vector3(0, -0.55, 0)
		A.sphere(fore, 0.062, Vector3.ZERO, "flesh", skin.darkened(0.05))   # elbow
		A.seg(fore, Vector3.ZERO, Vector3(0, -0.5, 0), 0.058, 0.045, "flesh", skin)
		var hand := Node3D.new()   # palm down, fingers spread forward
		fore.add_child(hand)
		hand.position = Vector3(0, -0.52, 0.02)
		var palm := A.sphere(hand, 0.07, Vector3(0, 0, 0.03), "flesh", skin, 0.0, 0.45)
		palm.scale = Vector3(1.0, 1.0, 1.3)
		for f in 4:
			var fx := -0.045 + f * 0.03
			A.seg(hand, Vector3(fx, -0.005, 0.08), Vector3(fx * 1.2, -0.02, 0.15), 0.014, 0.012, "flesh", skin)
			A.seg(hand, Vector3(fx * 1.2, -0.02, 0.15), Vector3(fx * 1.3, -0.04, 0.19), 0.012, 0.01, "flesh", skin.darkened(0.1))
		A.seg(hand, Vector3(0.06, 0, 0.02), Vector3(0.1, -0.02, 0.08), 0.015, 0.012, "flesh", skin)   # thumb
		upper.rotation.x = -0.7
		fore.rotation.x = 1.2
		_arms.append(upper)
		_arms.append(fore)
	target = global_position


## A point just proud of the shell (the shell is a sphere stretched up a little).
static func _on_shell(dir: Vector3) -> Vector3:
	return Vector3(dir.x * 0.47, dir.y * 0.56, dir.z * 0.47)


func hear(pos: Vector3) -> void:
	if calm > 0.0:
		return
	if not chasing:
		chasing = true
		fuse = 0.0
		Sfx.play(self, "screech", global_position, 4.0)
		var best := INF
		for p in alive_players():
			var d: float = p.global_position.distance_to(pos)
			if d < best:
				best = d
				prey = p
	target = pos


func _physics_process(delta: float) -> void:
	calm -= delta
	for p in alive_players():   # touching distance, nothing in between: it bursts on you
		if p.global_position.distance_to(global_position) < 1.0 and sees(p):
			_explode()
			return
	if chasing:
		fuse += delta
		if is_instance_valid(prey) and not prey.dead:
			target = prey.global_position
		if fuse > FUSE:
			var near = nearest_player(BURST_REACH)
			if near != null and sees(near):
				_explode()
				return
			chasing = false   # out of reach: it deflates and loses interest for a bit
			fuse = 0.0
			calm = 6.0
			prey = null
			Sfx.play(self, "slurp", global_position, -2.0, 0.6)
	else:
		_wander -= delta
		if _wander <= 0.0:
			_wander = randf_range(4.0, 9.0)
			target = level.wander_point(global_position)
	var v := walk_to(target, CHASE_SPEED if chasing else WANDER_SPEED, delta, 6.0)
	_animate(delta, v != Vector3.ZERO)
	_step -= delta
	if v != Vector3.ZERO and _step <= 0.0:
		_step = 0.2 if chasing else 0.45
		Sfx.play(self, "step_flesh", global_position, -4.0 if chasing else -9.0, 1.4)
	_gurgle -= delta
	if _gurgle <= 0.0:   # it gurgles now and then, so you know where it is
		_gurgle = randf_range(1.5, 3.0) if chasing else randf_range(3.0, 6.0)
		Sfx.play(self, "gurgle", global_position + Vector3(0, 1.0, 0), 2.0 if chasing else -2.0, randf_range(0.8, 1.1))


func is_hunting() -> bool:
	return chasing


func _animate(delta: float, moving: bool) -> void:
	_breath += delta * (6.0 + fuse * 6.0 if chasing else 1.5)
	var swell := 1.0 + (fuse / FUSE) * 0.5 if chasing else 1.0
	var pulse := 1.0 + sin(_breath) * (0.06 if chasing else 0.035)
	_body.scale = Vector3.ONE * swell * pulse
	_beat.pitch_scale = 1.0 + (fuse / FUSE) * 1.6 if chasing else 0.9   # the heartbeat races as it swells
	_beat.volume_db = 2.0 if chasing else -2.0
	var glow := 0.5 + 0.5 * sin(_breath)   # 0..1, with the heartbeat
	_skin.emission_energy_multiplier = (0.3 + glow * 0.3 + fuse * 0.25) if chasing else (0.06 + glow * 0.12)
	_vein_mat.emission_energy_multiplier = (1.2 + glow * 1.6 + fuse * 0.5) if chasing else (0.4 + glow * 0.7)
	_light.light_energy = (1.2 + glow * 1.0 + fuse * 0.5) if chasing else (0.4 + glow * 0.4)
	var rate := 0.6 + (fuse * fuse if chasing else 0.0)
	for i in _pustules.size():
		var on := fmod(Time.get_ticks_msec() / 1000.0 * rate + i * 0.13, 1.0) < 0.5
		_pustules[i].emission_energy_multiplier = (6.0 if on else 0.6) if chasing else (1.2 + sin(_breath + i) * 0.6)
	var gait := _anim * (5.0 if chasing else 3.5)
	for i in 3:
		var ph := gait + i * TAU / 3.0
		var lift := maxf(0.0, sin(ph)) if moving else 0.0
		_arms[i * 2].rotation.x = -(0.7 + cos(ph) * 0.35 * (1.0 if moving else 0.0) - lift * 0.3)
		_arms[i * 2 + 1].rotation.x = 1.2 - lift * 0.5


func _explode() -> void:
	main.explode(global_position, 4.5, 110.0, "A pulsator burst next to you.")
	queue_free()


# --- hits and death ---

func react_to_hit(by) -> void:
	calm = 0.0
	if by != null:
		hear(by.global_position)


## Kill it and it bursts anyway: from close up, that's your problem.
func death_anim() -> void:
	if main.net.puppet_mirror(self):
		queue_free()   # (the host's blast is sent to everyone)
		return
	_explode()


func net_visual(delta: float) -> void:
	var moved := 0.0 if _mirror_prev == Vector3.INF else global_position.distance_to(_mirror_prev)
	_mirror_prev = global_position
	_anim += moved
	_animate(delta, moved > 0.002)
