# The Pulsator: a veined flesh egg that walks on three human arms. Blind — it hears footsteps
# (crouch-walking is silent to it). Once it hears you it locks on, swells, its pustules strobe
# faster and faster, and it bursts ~5 s later or on contact. Run, or never be heard.
extends "res://src/monster.gd"

const FUSE := 5.0
const CHASE_SPEED := 5.0
const WANDER_SPEED := 1.2

var chasing := false
var target := Vector3.ZERO
var prey
var fuse := 0.0
var _wander := 0.0
var _step := 0.0
var _body: Node3D
var _pustules: Array[StandardMaterial3D] = []
var _veins: Node3D
var _arms: Array[Node3D] = []   # [upper, fore] x3
var _breath := 0.0
var _beat: AudioStreamPlayer3D


func _ready() -> void:
	_setup_body(0.4, 1.1, true)
	health = 45.0
	_beat = presence("heartbeat", -6.0, 4.0)
	add_to_group("pulsators")
	_body = Node3D.new()
	add_child(_body)
	_body.position.y = 1.05
	A.sphere(_body, 0.45, Vector3.ZERO, "flesh", Color(1, 0.82, 0.8), 0.12, 1.25)
	A.sphere(_body, 0.3, Vector3(0, -0.32, 0), "flesh", Color(0.8, 0.55, 0.55), 0.05, 0.8)
	# Dark veins wrapped over the shell.
	_veins = Node3D.new()
	_body.add_child(_veins)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for k in 26:
		var a := rng.randf() * TAU
		var lat := rng.randf_range(-0.9, 0.9)
		var p := Vector3(cos(a) * cos(lat), sin(lat) * 1.25, sin(a) * cos(lat)) * 0.452
		var vein := A.box(_veins, Vector3(0.022, rng.randf_range(0.12, 0.3), 0.022), p, "flesh", Color(0.4, 0.04, 0.1), false, 0.3)
		vein.look_at_from_position(p, p * 2.0, Vector3.UP)
		vein.rotate_object_local(Vector3.FORWARD, rng.randf() * TAU)
		vein.position = p
	# Glowing pustules that blink with the fuse.
	for k in 8:
		var a := TAU * k / 8.0 + 0.3
		var lat := 0.3 if k % 2 == 0 else -0.15
		var pm := glow_mat(Color(1, 0.55, 0.2), 1.0)
		var bump := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.1
		bump.mesh = sm
		bump.material_override = pm
		_body.add_child(bump)
		bump.position = Vector3(cos(a) * cos(lat), sin(lat) * 1.2, sin(a) * cos(lat)) * 0.45
		_pustules.append(pm)
	# Three human arms for legs: shoulder at the body, elbow, hand planted on the floor.
	for i in 3:
		var a := TAU * i / 3.0
		var root := Node3D.new()
		add_child(root)
		root.position = Vector3(sin(a) * 0.38, 0.92, cos(a) * 0.38)
		root.rotation.y = a
		var upper := limb(root, Vector3.ZERO, 0.55, 0.1, "flesh", Color(0.95, 0.75, 0.7))
		A.sphere(upper, 0.07, Vector3.ZERO, "flesh", Color(0.9, 0.7, 0.65))
		var fore := limb(upper, Vector3(0, -0.55, 0), 0.52, 0.085, "flesh", Color(0.95, 0.78, 0.72))
		A.sphere(fore, 0.06, Vector3.ZERO, "flesh", Color(0.9, 0.7, 0.65))
		A.box(fore, Vector3(0.13, 0.04, 0.15), Vector3(0, -0.54, 0.04), "flesh", Color(0.92, 0.74, 0.68), false, 0.3)
		for f in 4:
			A.box(fore, Vector3(0.022, 0.022, 0.1), Vector3(-0.05 + f * 0.033, -0.55, 0.14), "flesh", Color(0.9, 0.72, 0.66), false, 0.3)
		upper.rotation.x = -0.7
		fore.rotation.x = 1.2
		_arms.append(upper)
		_arms.append(fore)
	target = global_position


func hear(pos: Vector3) -> void:
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
	for p in alive_players():
		if p.global_position.distance_to(global_position) < 1.2:
			_explode()
			return
	if chasing:
		fuse += delta
		if is_instance_valid(prey) and not prey.dead:
			target = prey.global_position
		if fuse > FUSE:
			_explode()
			return
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
		Sfx.play(self, "step", global_position, -4.0 if chasing else -12.0, 1.8)


func _animate(delta: float, moving: bool) -> void:
	_breath += delta * (6.0 + fuse * 6.0 if chasing else 1.5)
	var swell := 1.0 + (fuse / FUSE) * 0.55 if chasing else 1.0
	var pulse := 1.0 + sin(_breath) * (0.06 if chasing else 0.03)
	_body.scale = Vector3.ONE * swell * pulse
	_beat.pitch_scale = 1.0 + (fuse / FUSE) * 1.6 if chasing else 0.9   # the heartbeat races as it swells
	_beat.volume_db = 0.0 if chasing else -8.0
	_veins.scale = Vector3.ONE * (1.0 + (fuse / FUSE) * 0.06 if chasing else 1.0)
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
	main.explode(global_position, 4.5, 150.0, "A pulsator burst next to you.")
	queue_free()


# --- hits and death ---

func react_to_hit(by) -> void:
	if by != null:
		hear(by.global_position)


## Kill it and it bursts anyway: from close up, that's your problem.
func death_anim() -> void:
	_explode()
