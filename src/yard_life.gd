# The checkpoint going about its business: the Bureau's clerk behind the shop window (watching you,
# shuffling forms, stamping one when you shop), the gantry crane at work over the scrap mountain
# (its trolley running the beam, the hook going down for a bale and carrying it across), and
# freight trains rolling by on the far line now and then, headlights on, wheels clacking, a horn
# from a long way off. All for looks: each machine runs its own, nothing to collide with.
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")
const Suit = preload("res://src/suit.gd")
const Sfx = preload("res://src/sfx.gd")

const SPAN := 18.0
const CRANE_H := 9.0
const FAR_LINE := -27.0   # z of the through line, past the fence
const LINE_Y := 0.06

var main
var crane: Node3D
var _clerk: Node3D
var _clerk_parts := {}
var _stamp_t := 0.0
var _papers := 0.0
var _trolley: Node3D
var _hook: Node3D
var _cable: MeshInstance3D
var _load: Node3D
var _job := 0          # the crane's step
var _job_t := 0.0
var _x := -4.0         # trolley along the beam
var _drop := 2.0       # how far the hook hangs below the trolley
var _train: Node3D
var _train_x := 0.0
var _train_dir := 1.0
var _next_train := 20.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "YardLife"
	_rng.seed = 2207   # (its own dice: the yard itself is built the same as ever)
	_build_clerk()
	_build_trolley()
	_build_line()


# --- the clerk ------------------------------------------------------------------------------------

func _build_clerk() -> void:
	_clerk = Node3D.new()
	add_child(_clerk)
	_clerk.position = Vector3(-14.0, 0.18, 13.05)   # behind the counter of the shop container
	var body := Node3D.new()
	body.name = "Body"
	_clerk.add_child(body)
	_clerk_parts = Suit.standing(body)
	Suit.apply_look(body, [6, 5, 5], "BUREAU")   # charcoal, black helmet, a number
	_clerk_parts.upper_arm_l.rotation = Vector3(-0.9, 0, -0.1)   # (forearms on the counter)
	_clerk_parts.upper_arm_r.rotation = Vector3(-0.9, 0, 0.1)
	_clerk_parts.forearm_l.rotation = Vector3(-0.7, 0, 0)
	_clerk_parts.forearm_r.rotation = Vector3(-0.7, 0, 0)
	var lamp := OmniLight3D.new()   # a desk lamp on him
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 1.2
	lamp.omni_range = 3.0
	_clerk.add_child(lamp)
	lamp.position = Vector3(0.5, 1.9, -0.4)
	for i in 3:   # forms on the counter
		var f := A.box(_clerk, Vector3(0.21, 0.004, 0.29), Vector3(-0.35 + i * 0.3, 1.02, -0.55), "paper", Color(0.92, 0.9, 0.82), false, 0.2)
		f.rotation.y = _rng.randf_range(-0.3, 0.3)


## Shopping: he stamps your form.
func clerk_stamp() -> void:
	_stamp_t = 0.5


func _clerk_tick(delta: float) -> void:
	var p = main.player if main else null
	var t := Time.get_ticks_msec() / 1000.0
	_clerk_parts.torso.rotation.x = sin(t * 1.4) * 0.015   # (breathing)
	# Watching whoever's near the window; otherwise looking down at the forms.
	var look := Vector2(0.35, 0.0)
	if p != null and p.global_position.distance_to(_clerk.global_position) < 9.0:
		var to: Vector3 = _clerk.to_local(p.global_position + Vector3(0, 1.5, 0)) - Vector3(0, 1.66, 0)
		look = Vector2(clampf(-atan2(to.y, Vector2(to.x, to.z).length()), -0.5, 0.5), clampf(atan2(-to.x, -to.z), -1.0, 1.0))
	var head: Node3D = _clerk_parts.head
	head.rotation.x = lerpf(head.rotation.x, look.x, minf(1.0, delta * 3.0))
	head.rotation.y = lerpf(head.rotation.y, look.y, minf(1.0, delta * 3.0))
	# Now and then he shuffles the forms; when you shop, the stamp comes down.
	_papers -= delta
	var arm: Node3D = _clerk_parts.upper_arm_r
	var want := -0.9
	if _stamp_t > 0.0:
		_stamp_t -= delta
		want = -1.6 if _stamp_t > 0.25 else -0.75
		if _stamp_t <= 0.25 and _stamp_t + delta > 0.25:
			Sfx.play(self, "stamp", _clerk.global_position + Vector3(0, 1.0, -0.5), -6.0)
	elif _papers < 0.0:
		if _papers < -1.2:
			_papers = _rng.randf_range(4.0, 9.0)
		want = -0.9 + sin(_papers * 9.0) * 0.12
		_clerk_parts.upper_arm_l.rotation.z = -0.1 + sin(_papers * 7.0) * 0.1
	arm.rotation.x = lerpf(arm.rotation.x, want, minf(1.0, delta * 14.0))


# --- the crane ------------------------------------------------------------------------------------

func _build_trolley() -> void:
	if crane == null:
		return
	var y := Color(0.85, 0.62, 0.15)
	_trolley = Node3D.new()
	_trolley.set_meta("live", true)   # (moves: not merged into the crane's static mesh)
	crane.add_child(_trolley)
	_trolley.position = Vector3(_x, CRANE_H - 0.1, 0)
	A.box(_trolley, Vector3(1.4, 0.7, 1.3), Vector3.ZERO, "metal", y.darkened(0.15), false, 0.5)
	A.box(_trolley, Vector3(0.7, 0.5, 0.6), Vector3(0, -0.2, -0.75), "metal", Color(0.3, 0.3, 0.3), false, 0.3)
	var beacon := A.sphere(_trolley, 0.08, Vector3(0.5, 0.42, 0), "cream", Color(1.0, 0.55, 0.1), 3.0)
	beacon.name = "Beacon"
	_cable = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = 1.0
	_cable.mesh = cm
	_cable.material_override = A.mat("metal", Color(0.25, 0.25, 0.25))
	_trolley.add_child(_cable)
	_hook = Node3D.new()
	_trolley.add_child(_hook)
	A.box(_hook, Vector3(0.6, 0.45, 0.35), Vector3.ZERO, "metal", y, false, 0.3)
	A.ring(_hook, 0.22, 0.13, Vector3(0, -0.45, 0), "metal", Color(0.4, 0.4, 0.4), Vector3(PI / 2, 0, 0))
	_load = Node3D.new()   # a strapped bale of crushed scrap
	_hook.add_child(_load)
	A.box(_load, Vector3(1.1, 0.9, 1.1), Vector3(0, -1.3, 0), "rust", Color(0.75, 0.7, 0.65), false, 0.6)
	for s in [-1, 1]:
		A.seg(_load, Vector3(s * 0.4, -0.85, 0), Vector3(0, -0.45, 0), 0.015, 0.015, "metal", Color(0.3, 0.3, 0.3))
	_load.visible = false
	var hum := AudioStreamPlayer3D.new()
	hum.stream = Sfx.stream("motor")
	hum.volume_db = -14.0
	hum.unit_size = 6.0
	hum.max_distance = 45.0
	hum.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	hum.autoplay = true
	_trolley.add_child(hum)


## Out over the heap, down, pick up, up, across to the bale stack, down, let go, up, back.
func _crane_tick(delta: float) -> void:
	if _trolley == null:
		return
	_job_t -= delta
	var steps := [[-4.0, 2.0, false], [-4.0, 6.6, false], [-4.0, 6.6, true], [-4.0, 2.0, true],
		[5.5, 2.0, true], [5.5, 6.3, true], [5.5, 6.3, false], [5.5, 2.0, false]]
	var s: Array = steps[_job]
	var moved := false
	var nx := move_toward(_x, s[0], delta * 1.2)
	var nd := move_toward(_drop, s[1], delta * 0.9)
	moved = nx != _x or nd != _drop
	_x = nx
	_drop = nd
	if not moved:
		if _job_t <= 0.0:
			_load.visible = s[2]
			_job = (_job + 1) % steps.size()
			_job_t = 1.5 if _job % 2 == 0 else 0.6
			if _job == 3 or _job == 7:
				Sfx.play(self, "clank", _hook.global_position, -6.0, 0.8)
	_trolley.position.x = _x
	_hook.position.y = -0.45 - _drop
	_cable.position.y = -0.45 - _drop / 2.0
	_cable.scale.y = maxf(_drop, 0.05)
	_hook.rotation.z = sin(Time.get_ticks_msec() / 700.0) * 0.03 * (1.0 if moved else 0.3)   # (swinging a little)
	var bc: MeshInstance3D = _trolley.get_node("Beacon")
	if bc:
		bc.visible = moved and fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0


# --- the far line ---------------------------------------------------------------------------------

func _build_line() -> void:
	var line := Node3D.new()
	add_child(line)
	for s in [-1, 1]:   # rails
		A.box(line, Vector3(400.0, 0.12, 0.08), Vector3(0, LINE_Y + 0.2, FAR_LINE + s * 0.72), "metal", Color(0.45, 0.42, 0.4), false, 2.0)
	A.box(line, Vector3(400.0, 0.12, 3.2), Vector3(0, LINE_Y + 0.02, FAR_LINE), "dirt", Color(0.6, 0.55, 0.5), false, 2.0)
	for i in 160:   # sleepers
		A.box(line, Vector3(0.25, 0.1, 2.4), Vector3(-200.0 + i * 2.5, LINE_Y + 0.12, FAR_LINE), "wood", Color(0.45, 0.38, 0.3), false, 1.0)


func _send_train() -> void:
	_train = Node3D.new()
	add_child(_train)
	_train_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_train_x = -170.0 * _train_dir
	var cars := _rng.randi_range(5, 9)
	# The engine at the front: a long hood, a cab, a headlight burning.
	var eng := Node3D.new()
	_train.add_child(eng)
	var ec := [Color(0.25, 0.3, 0.4), Color(0.55, 0.2, 0.12), Color(0.3, 0.32, 0.28)][_rng.randi() % 3] as Color
	A.box(eng, Vector3(12.0, 2.4, 2.8), Vector3(0, 2.3, 0), "metal", ec, false, 1.0)
	A.box(eng, Vector3(3.0, 1.2, 3.0), Vector3(3.6 * _train_dir, 4.0, 0), "metal", ec.darkened(0.2), false, 1.0)
	A.box(eng, Vector3(12.4, 0.5, 2.6), Vector3(0, 0.9, 0), "metal", Color(0.15, 0.15, 0.15), false, 0.5)
	var hl := SpotLight3D.new()
	hl.light_color = Color(1.0, 0.92, 0.75)
	hl.light_energy = 6.0
	hl.spot_range = 40.0
	hl.spot_angle = 18.0
	hl.light_volumetric_fog_energy = 2.0
	eng.add_child(hl)
	hl.position = Vector3(6.1 * _train_dir, 3.0, 0)
	hl.rotation.y = -PI / 2.0 * _train_dir
	A.glow(eng, Vector3(0.05, 0.3, 0.3), Vector3(6.05 * _train_dir, 3.0, 0), Color(1.0, 0.95, 0.8), 6.0)
	for i in cars:
		var car := Node3D.new()
		_train.add_child(car)
		car.position.x = -_train_dir * (12.0 + i * 10.6)
		P.boxcar(car, Vector3.ZERO, 0.0, _rng)
	_train.position = Vector3(_train_x, LINE_Y + 0.2, FAR_LINE)
	var rumble := AudioStreamPlayer3D.new()
	rumble.stream = Sfx.stream("rail_clack")
	rumble.volume_db = -2.0
	rumble.unit_size = 14.0
	rumble.max_distance = 140.0
	rumble.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	_train.add_child(rumble)
	rumble.play()
	_train.set_meta("length", 12.0 + cars * 10.6)
	_train.set_meta("horn", false)


func _train_tick(delta: float) -> void:
	if _train == null:
		_next_train -= delta
		if _next_train <= 0.0:
			_send_train()
		return
	_train_x += _train_dir * 13.0 * delta
	_train.position.x = _train_x
	if not _train.get_meta("horn") and absf(_train_x) < 70.0:   # blowing for the yard
		_train.set_meta("horn", true)
		Sfx.play(self, "horn", _train.global_position + Vector3(0, 4, 0), -4.0, 0.85)
	if _train_x * _train_dir > 170.0 + float(_train.get_meta("length")):
		_train.queue_free()
		_train = null
		_next_train = _rng.randf_range(50.0, 110.0)


func _process(delta: float) -> void:
	if main == null or not main.at_checkpoint:
		return
	_clerk_tick(delta)
	_crane_tick(delta)
	_train_tick(delta)
