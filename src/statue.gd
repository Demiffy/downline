# The Statue: a weathered stone figure. Dormant until someone sees it for the first time.
# From then on it only moves while NOBODY is looking — fast, grinding — and freezes the instant
# you look back, in a different pose than before. Each hit is >50 damage, so it ruins your regen.
extends "res://src/monster.gd"

const SPEED := 7.5
const HIT := 55.0
const STONE := Color(0.78, 0.76, 0.72)

var awake := false
var _moving := false
var _cooldown := 0.0
var _grind: AudioStreamPlayer3D
var _arms: Array[Node3D] = []      # [l_upper, l_fore, r_upper, r_fore]
var _head: Node3D
var _poses := [
	# [l_upper, l_fore, r_upper, r_fore] rotations. Weeping (hands over face), reaching, grasping, pointing.
	[Vector3(2.2, 0.3, 0.45), Vector3(1.75, 0, 0), Vector3(2.2, -0.3, -0.45), Vector3(1.75, 0, 0)],
	[Vector3(1.45, 0, 0.12), Vector3(0.15, 0, 0), Vector3(1.45, 0, -0.12), Vector3(0.15, 0, 0)],
	[Vector3(0.9, 0, 0.5), Vector3(1.3, 0, 0), Vector3(1.1, 0, -0.5), Vector3(1.1, 0, 0)],
	[Vector3(0.15, 0, 0.12), Vector3(0.2, 0, 0), Vector3(2.6, 0, -0.15), Vector3(0.1, 0, 0)],
]


func _ready() -> void:
	_setup_body(0.38, 2.0)
	add_to_group("statues")
	var c := STONE
	# Robe: three layered tapers with draped folds running down them.
	A.cyl(self, 0.5, 0.55, Vector3(0, 0.27, 0), "concrete", c, false, "y", 0.4)
	A.cyl(self, 0.41, 0.65, Vector3(0, 0.85, 0), "concrete", c, false, "y", 0.3)
	A.cyl(self, 0.31, 0.42, Vector3(0, 1.36, 0), "concrete", c, false, "y", 0.26)
	for i in 12:
		var a := TAU * i / 12.0 + 0.13
		# Wedge folds hugging the taper: wide at the hem, leaning inward toward the waist.
		var fold := A.cyl(self, 0.06, 1.25, Vector3(sin(a) * 0.43, 0.62, cos(a) * 0.43), "concrete", c.darkened(0.08), false, "y", 0.025)
		fold.rotation = Vector3(-0.11 * cos(a), 0, 0.11 * sin(a))
	# Chest, sloped shoulders, neck.
	A.sphere(self, 0.27, Vector3(0, 1.62, 0), "concrete", c, 0.0, 1.25)
	for side in [-1, 1]:
		A.sphere(self, 0.13, Vector3(side * 0.24, 1.8, 0), "concrete", c)
	A.cyl(self, 0.07, 0.16, Vector3(0, 1.92, 0), "concrete", c)
	# Folded stone wings along the back.
	for side in [-1, 1]:
		var wing := Node3D.new()
		add_child(wing)
		wing.position = Vector3(side * 0.16, 1.75, 0.22)
		wing.rotation = Vector3(0.12, side * 0.35, side * 0.12)
		for f in 5:
			var feather := A.box(wing, Vector3(0.13, 1.15 - f * 0.17, 0.2), Vector3(side * f * 0.07, -0.5 + f * 0.06, 0.05 + f * 0.04), "concrete", c.darkened(0.05 * f), false, 0.6)
			feather.rotation.z = side * (0.05 + f * 0.05)
	# Head under a hood, face tilted down, hollow eyes.
	_head = Node3D.new()
	add_child(_head)
	_head.position = Vector3(0, 2.0, 0)
	A.sphere(_head, 0.14, Vector3(0, 0.08, -0.01), "concrete", c, 0.0, 1.15)
	var hood := A.sphere(_head, 0.2, Vector3(0, 0.12, 0.05), "concrete", c.darkened(0.12), 0.0, 1.15)
	hood.scale = Vector3(1.0, 1.05, 1.0)
	A.box(_head, Vector3(0.3, 0.32, 0.1), Vector3(0, 0.0, 0.14), "concrete", c.darkened(0.12), false, 0.5)
	for x in [-0.05, 0.05]:
		A.sphere(_head, 0.028, Vector3(x, 0.11, -0.13), "metal", Color(0.03, 0.03, 0.03))
	A.box(_head, Vector3(0.025, 0.06, 0.03), Vector3(0, 0.06, -0.15), "concrete", c, false, 0.3)
	# Arms with real hands.
	for side in [-1, 1]:
		var upper := limb(self, Vector3(side * 0.3, 1.8, 0), 0.4, 0.12, "concrete", c)
		var fore := limb(upper, Vector3(0, -0.4, 0), 0.36, 0.1, "concrete", c)
		A.sphere(fore, 0.065, Vector3.ZERO, "concrete", c)
		var hand := Node3D.new()
		fore.add_child(hand)
		hand.position = Vector3(0, -0.38, 0)
		A.box(hand, Vector3(0.1, 0.1, 0.04), Vector3(0, -0.04, 0), "concrete", c, false, 0.3)
		for f in 4:
			A.box(hand, Vector3(0.018, 0.09, 0.02), Vector3(-0.036 + f * 0.024, -0.13, 0), "concrete", c, false, 0.3)
		A.box(hand, Vector3(0.02, 0.06, 0.02), Vector3(side * -0.06, -0.06, -0.01), "concrete", c, false, 0.3, Vector3(0, 0, side * 0.6))
		_arms.append(upper)
		_arms.append(fore)
	# Cracks + moss so it reads as old stone.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 12:
		var a := rng.randf() * TAU
		var y := rng.randf_range(0.3, 1.7)
		var r := 0.47 - y * 0.12
		A.box(self, Vector3(0.012, rng.randf_range(0.1, 0.35), 0.012), Vector3(sin(a) * r, y, cos(a) * r), "metal", Color(0.15, 0.14, 0.13), false, 0.3, Vector3(0, a, rng.randf_range(-0.6, 0.6)))
	for i in 5:
		var a := rng.randf() * TAU
		A.box(self, Vector3(rng.randf_range(0.1, 0.25), 0.04, rng.randf_range(0.08, 0.16)), Vector3(sin(a) * 0.45, rng.randf_range(0.05, 0.35), cos(a) * 0.45), "leaf", Color(0.55, 0.65, 0.45), false, 0.4, Vector3(0, a, 0))
	_pose(0)
	_grind = AudioStreamPlayer3D.new()
	_grind.stream = Sfx.stream("grind")
	_grind.volume_db = -6.0
	_grind.unit_size = 5.0
	add_child(_grind)


func _pose(i: int) -> void:
	var p: Array = _poses[i]
	for k in 4:
		_arms[k].rotation = p[k]
	_head.rotation = Vector3(randf_range(-0.6, -0.15), randf_range(-0.6, 0.6), randf_range(-0.2, 0.2))


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	var watched := observed(2.0, 0.5)
	if not awake:
		awake = watched
		stand_still(delta)
		return
	var prey = nearest_player()
	if watched or prey == null:
		if _moving:
			_moving = false
			_grind.stop()
			_pose(randi() % _poses.size())
		stand_still(delta)
		return
	if not _moving:
		_moving = true
		_grind.play()
	var dist: float = prey.global_position.distance_to(global_position)
	if dist < 1.3:
		stand_still(delta)
		face(prey.global_position, delta, 30.0)
		if _cooldown <= 0.0:
			_cooldown = 1.4
			Sfx.play(self, "thud", global_position + Vector3.UP, 4.0, 0.7)
			prey.hurt(HIT, "Strangled by the statue.")
			prey.shake(0.06)
		return
	walk_to(prey.global_position, SPEED, delta, 30.0)


# --- hits ---

## Stone: chips fly, nothing else happens.
func take_hit(_dmg: float, from: Vector3, _by = null) -> void:
	var at := global_position + Vector3(0, 1.2, 0)
	hit_fx(self, at, (from - at).normalized(), "stone")
	if not get_meta("told", false):
		set_meta("told", true)
		main.hud.msg("It's solid stone. Nothing down here can break it.")


func is_hunting() -> bool:
	return awake
