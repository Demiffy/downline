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
const CP = preload("res://src/checkpoint.gd")
const Merge = preload("res://src/merge.gd")
const FAR_LINE := CP.FAR_LINE   # z of the through line, past the yard
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
	_build_people.call_deferred()
	_build_vehicles.call_deferred()
	_build_shunter.call_deferred()
	_build_smoke.call_deferred()
	_build_works.call_deferred()


# --- the clerk ------------------------------------------------------------------------------------

const CLERK_ARM := 0.45


func _build_clerk() -> void:
	_clerk = Node3D.new()
	add_child(_clerk)
	_clerk.position = Vector3(-14.0, 0.18, 13.05)   # behind the counter of the shop container
	var body := Node3D.new()
	body.name = "Body"
	_clerk.add_child(body)
	_clerk_parts = Suit.standing(body)
	Suit.apply_look(body, [6, 5, 5], "BUREAU")   # charcoal, black helmet, a number
	_bake_suit(body, _clerk_parts)
	_clerk_parts.upper_arm_l.rotation = Vector3(CLERK_ARM, 0, -0.1)   # (forearms forward on the counter: + is forward on these joints)
	_clerk_parts.upper_arm_r.rotation = Vector3(CLERK_ARM, 0, 0.1)
	_clerk_parts.forearm_l.rotation = Vector3(1.1, 0, 0)
	_clerk_parts.forearm_r.rotation = Vector3(1.1, 0, 0)
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
	var want := CLERK_ARM
	if _stamp_t > 0.0:
		_stamp_t -= delta
		want = 1.3 if _stamp_t > 0.25 else CLERK_ARM - 0.1
		if _stamp_t <= 0.25 and _stamp_t + delta > 0.25:
			Sfx.play(self, "stamp", _clerk.global_position + Vector3(0, 1.0, -0.5), -6.0)
	elif _papers < 0.0:
		if _papers < -1.2:
			_papers = _rng.randf_range(4.0, 9.0)
		want = CLERK_ARM + sin(_papers * 9.0) * 0.12
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

func _send_train() -> void:
	_train = Node3D.new()
	add_child(_train)
	_train_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_train_x = -240.0 * _train_dir   # (out of the tunnel)
	var cars := _rng.randi_range(5, 9)
	# The engine at the front, nose first, headlight burning.
	var eng := Node3D.new()
	_train.add_child(eng)
	var ec := [Color(0.25, 0.3, 0.4), Color(0.55, 0.2, 0.12), Color(0.3, 0.32, 0.28)][_rng.randi() % 3] as Color
	CP.loco(eng, 13.0, ec, "BRM %d" % _rng.randi_range(200, 899))
	eng.rotation.y = 0.0 if _train_dir > 0.0 else PI
	var hl := SpotLight3D.new()
	hl.light_color = Color(1.0, 0.92, 0.75)
	hl.light_energy = 6.0
	hl.spot_range = 40.0
	hl.spot_angle = 18.0
	hl.light_volumetric_fog_energy = 2.0
	eng.add_child(hl)
	hl.position = Vector3(6.4, 2.4, 0)
	hl.rotation.y = -PI / 2.0
	for i in cars:
		var car := Node3D.new()
		_train.add_child(car)
		car.position.x = -_train_dir * (12.0 + i * 10.6)
		P.boxcar(car, Vector3.ZERO, 0.0, _rng)
	Merge.bake(_train, 140.0, false, 800.0)
	_train.position = Vector3(_train_x, CP.RAIL_TOP, FAR_LINE)
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
	if _train_x * _train_dir > 240.0 + float(_train.get_meta("length")):
		_train.queue_free()
		_train = null
		_next_train = _rng.randf_range(50.0, 110.0)


func _process(delta: float) -> void:
	if main == null or not main.at_checkpoint:
		return
	_clerk_tick(delta)
	_crane_tick(delta)
	_train_tick(delta)
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else Vector3.ZERO
	for w in _people:
		_person_tick(w, delta, eye)
	for v in _vehicles:
		_vehicle_tick(v, delta)
	_shunter_tick(delta)
	_works_tick(delta)


# --- the people at work ----------------------------------------------------------------------------
# Each walks a round of its own (some stop to work along it), or stays put at one job.

const ROUNDS := [
	[[Vector3(-60, 0, 42), 0.0], [Vector3(60, 0, 42), 4.0]],
	[[Vector3(-20, 0, 59), 0.0], [Vector3(20, 0, 59), 0.0], [Vector3(20, 0, 63), 6.0], [Vector3(-20, 0, 63), 0.0]],
	[[Vector3(-123, 0, 30), 5.0], [Vector3(-123, 0, 96), 0.0], [Vector3(-101, 0, 96), 5.0], [Vector3(-101, 0, 30), 0.0]],
	[[Vector3(-79, 0, 38), 0.0], [Vector3(-130, 0, 38), 6.0]],
	[[Vector3(62, 0, 30), 0.0], [Vector3(118, 0, 30), 5.0], [Vector3(118, 0, 40), 0.0], [Vector3(62, 0, 40), 7.0]],
	[[Vector3(-130, 0, -60), 0.0], [Vector3(-20, 0, -60), 8.0], [Vector3(120, 0, -60), 0.0]],
	[[Vector3(-90, 0, -27), 0.0], [Vector3(40, 0, -27), 6.0]],
	[[Vector3(30, 0, -33), 9.0], [Vector3(-60, 0, -33), 0.0]],
	[[Vector3(-45, 0, 22), 0.0], [Vector3(-45, 0, 34), 5.0], [Vector3(-60, 0, 34), 0.0]],
	[[Vector3(140, 0, 20), 0.0], [Vector3(140, 0, 4), 6.0]],
	[[Vector3(70, 0, -39), 9999.0]],    # welding in the repair shed
	[[GATE_SEAT, SITS]],                # the gate's man at his desk in the booth
	[[Vector3(-30, 0, 47), 9999.0]],    # on a break by the trucks
]
var _people: Array = []


const SITS := -2.0                       # (a round's wait that means: seated here)
const GATE_SEAT := Vector3(20.1, 0, 5.32)  # the gatehouse chair (props.guard_booth at (20, 5), turned -90 degrees)
const SEAT_Y := 0.815                      # its seat, above the ground


func _build_people() -> void:
	var looks := [[0, 2, 0], [1, 2, 1], [1, 6, 5], [0, 0, 2], [6, 1, 3], [0, 2, 5]]
	var names := ["KOVAC", "HALE", "ORTIZ", "BREN", "MAKI", "OSEI", "DVORAK", "LUND", "REYES", "NOVAK", "PRICE", "VANCE", "SATO"]
	for i in ROUNDS.size():
		var r: Array = ROUNDS[i]
		var n := AnimatableBody3D.new()   # (you bump into them; they don't push you about)
		n.sync_to_physics = false
		add_child(n)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.32
		cap.height = 1.8
		cs.shape = cap
		cs.position.y = 0.9
		n.add_child(cs)
		var body := Node3D.new()
		n.add_child(body)
		var parts := Suit.standing(body)
		Suit.apply_look(body, looks[i % looks.size()], names[i])
		n.position = r[0][0] + Vector3(0, 0.06, 0)
		_bake_suit(body, parts)
		var sits: bool = r.size() == 1 and r[0][1] == SITS
		if sits:
			n.rotation.y = -PI / 2.0   # (facing +x: the desk, the window, the gate)
		_people.append({"node": n, "parts": parts, "round": r, "i": 0, "wait": _rng.randf_range(0.0, 4.0), "step": 0.0, "work": r.size() == 1 and not sits, "sit": sits})
	# The welder's torch: a flickering blue-white light and sparks.
	var w: Dictionary = _people[10]
	_torch = OmniLight3D.new()
	_torch.light_color = Color(0.7, 0.85, 1.0)
	_torch.omni_range = 6.0
	add_child(_torch)
	_torch.position = w.node.position + Vector3(0.0, 1.1, -0.7)
	var sp := GPUParticles3D.new()
	sp.amount = 40
	sp.lifetime = 0.6
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, -9.8, 0)
	sp.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.02
	bm.material = A.mat("cream", Color(1, 0.8, 0.4), 1.0, 8.0)
	sp.draw_pass_1 = bm
	add_child(sp)
	sp.position = _torch.position
	var crackle := AudioStreamPlayer3D.new()
	crackle.stream = Sfx.stream("crackle")
	crackle.volume_db = -10.0
	crackle.unit_size = 4.0
	crackle.max_distance = 30.0
	crackle.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	crackle.autoplay = true
	add_child(crackle)
	crackle.position = _torch.position


var _torch: OmniLight3D


## Each limb folded into one mesh (its joints still move), and none drawn from far off.
static func _bake_suit(body: Node3D, parts: Dictionary) -> void:
	for p: Node3D in parts.values():
		p.set_meta("live", true)
	for p: Node3D in parts.values():
		Merge.bake(p, 10.0, false, 800.0)
	for mi: GeometryInstance3D in body.find_children("*", "GeometryInstance3D", true, false):
		mi.visibility_range_end = 75.0


func _person_tick(w: Dictionary, delta: float, eye: Vector3) -> void:
	var n: Node3D = w.node
	if n.position.distance_to(eye) > 120.0:
		return   # (nobody to see them: let them be)
	var parts: Dictionary = w.parts
	var moving := false
	if w.sit:   # in the chair: thighs on the seat, shins down, forearms on the desk, looking about
		parts.thigh_l.rotation.x = 1.5
		parts.thigh_r.rotation.x = 1.45
		parts.shin_l.rotation.x = -1.45
		parts.shin_r.rotation.x = -1.35
		(n.get_child(1) as Node3D).position.y = SEAT_Y + 0.08 - 0.94 - n.position.y
		for a in [parts.upper_arm_l, parts.upper_arm_r]:
			a.rotation.x = 0.5
		parts.forearm_l.rotation.x = 1.0
		parts.forearm_r.rotation.x = 1.0 + sin(Time.get_ticks_msec() / 900.0) * 0.08
		parts.head.rotation.y = sin(Time.get_ticks_msec() / 3100.0) * 0.6
		parts.head.rotation.x = 0.15
		return
	if w.work:
		w.step += delta * 6.0   # at a job: crouched, an arm going
		parts.thigh_l.rotation.x = 1.2
		parts.thigh_r.rotation.x = 1.2
		parts.shin_l.rotation.x = -2.0
		parts.shin_r.rotation.x = -2.0
		(n.get_child(1) as Node3D).position.y = -0.45
		parts.upper_arm_r.rotation.x = 0.9 + sin(w.step) * 0.25
		return
	if w.wait > 0.0:
		w.wait -= delta
	else:
		var r: Array = w.round
		var target: Vector3 = r[w.i][0] + Vector3(0, 0.06, 0)
		var to := target - n.position
		to.y = 0.0
		if to.length() < 0.15:
			w.wait = r[w.i][1] if r[w.i][1] > 0.0 else _rng.randf_range(0.0, 1.0)
			w.i = (w.i + 1) % r.size()
		else:
			var stepv := to.normalized() * minf(1.35 * delta, to.length())
			n.position += stepv
			n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 6.0))
			w.step += stepv.length()
			moving = true
	var g: float = w.step * 2.6
	var amt := 1.0 if moving else 0.0
	var s := sin(g)
	parts.thigh_l.rotation.x = lerpf(parts.thigh_l.rotation.x, s * 0.55 * amt, minf(1.0, delta * 10.0))
	parts.thigh_r.rotation.x = lerpf(parts.thigh_r.rotation.x, -s * 0.55 * amt, minf(1.0, delta * 10.0))
	parts.shin_l.rotation.x = -maxf(0.0, -s) * 0.8 * amt
	parts.shin_r.rotation.x = -maxf(0.0, s) * 0.8 * amt
	parts.upper_arm_l.rotation.x = -s * 0.4 * amt
	parts.upper_arm_r.rotation.x = s * 0.4 * amt
	parts.head.rotation.y = sin(Time.get_ticks_msec() / 2300.0 + n.position.x) * 0.4 * (1.0 - amt)


# --- vehicles --------------------------------------------------------------------------------------

const DRIVES := [
	["truck", [Vector3(-150, 0, 38.5), Vector3(150, 0, 38.5), Vector3(150, 0, 42.5), Vector3(-150, 0, 42.5)], 7.0],
	["truck", [Vector3(-50, 0, 36), Vector3(-50, 0, 110), Vector3(-54, 0, 110), Vector3(-54, 0, 36)], 5.0],
	["truck", [Vector3(54, 0, 110), Vector3(54, 0, 36), Vector3(50, 0, 36), Vector3(50, 0, 110)], 5.5],
	["forklift", [Vector3(62, 0, 64), Vector3(78, 0, 64), Vector3(78, 0, 67), Vector3(62, 0, 67)], 2.2],
	["forklift", [Vector3(-138, 0, 34), Vector3(-138, 0, 46), Vector3(-134, 0, 46), Vector3(-134, 0, 34)], 2.0],
]
var _vehicles: Array = []


func _build_vehicles() -> void:
	for d in DRIVES:
		var holder := Node3D.new()
		holder.set_meta("live", true)
		add_child(holder)
		if d[0] == "truck":
			CP.truck(holder, Vector3(0, 0.08, 0), 0.0, _rng, false)   # (on the road's surface)
		else:
			P.forklift(holder, Vector3(0, 0.05, 0), 0.0)   # (on the lot's)
		var lamp := SpotLight3D.new()   # headlights
		lamp.light_color = Color(1.0, 0.92, 0.75)
		lamp.light_energy = 2.0
		lamp.spot_range = 22.0
		lamp.spot_angle = 30.0
		holder.add_child(lamp)
		lamp.position = Vector3(0, 1.2, -3.8 if d[0] == "truck" else -1.4)
		var hum := AudioStreamPlayer3D.new()
		hum.stream = Sfx.stream("diesel_idle" if d[0] == "truck" else "motor")
		hum.volume_db = -12.0
		hum.unit_size = 5.0
		hum.max_distance = 40.0
		hum.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
		hum.autoplay = true
		holder.add_child(hum)
		Merge.bake(holder, 50.0, false, 800.0)   # (one mesh that drives about, not a hundred)
		holder.position = d[1][0]
		_vehicles.append({"node": holder, "path": d[1], "i": 1, "speed": d[2], "lamp": lamp, "wait": 0.0})


func _vehicle_tick(v: Dictionary, delta: float) -> void:
	var n: Node3D = v.node
	var lamp: SpotLight3D = v.lamp
	lamp.visible = main.hours > 18.0 or main.hours < 7.0 or main.at_checkpoint
	if v.wait > 0.0:
		v.wait -= delta
		return
	var target: Vector3 = v.path[v.i]
	var to := target - n.position
	if to.length() < 0.3:
		v.i = (v.i + 1) % v.path.size()
		v.wait = 1.5 if v.speed < 3.0 else 0.0
		return
	var want := atan2(-to.x, -to.z)
	n.rotation.y = lerp_angle(n.rotation.y, want, minf(1.0, delta * 2.5))
	var fwd := -n.global_transform.basis.z
	var go = v.speed * clampf(fwd.dot(to.normalized()), 0.15, 1.0)
	n.position += to.normalized() * minf(go * delta, to.length())


# --- the shunter -----------------------------------------------------------------------------------
# A little yard engine pushing a cut of wagons up and down the clear siding, pausing at each end.

var _shunt: Node3D
var _shunt_dir := 1.0
var _shunt_wait := 3.0


func _build_shunter() -> void:
	_shunt = Node3D.new()
	_shunt.set_meta("live", true)
	add_child(_shunt)
	CP.loco(_shunt, 9.0, Color(0.88, 0.68, 0.12), "BRM 3", true)   # an end-cab yard switcher, its cab by the wagons
	for k in 3:
		var car := Node3D.new()
		_shunt.add_child(car)
		car.position.x = -10.6 - k * 11.0
		P.boxcar(car, Vector3.ZERO, 0.0, _rng)
	Merge.bake(_shunt, 80.0, false, 800.0)
	_shunt.position = Vector3(CP.SHUNT_X.y, CP.RAIL_TOP, CP.SHUNT_Z)
	var hum := AudioStreamPlayer3D.new()
	hum.stream = Sfx.stream("diesel_idle")
	hum.volume_db = -6.0
	hum.unit_size = 8.0
	hum.max_distance = 70.0
	hum.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	hum.autoplay = true
	_shunt.add_child(hum)
	_shunt_dir = -1.0


func _shunter_tick(delta: float) -> void:
	if _shunt == null:
		return
	if _shunt_wait > 0.0:
		_shunt_wait -= delta
		return
	_shunt.position.x += _shunt_dir * 2.2 * delta
	var lo := CP.SHUNT_X.x + 33.0   # (its wagons trail behind it toward -x)
	if (_shunt_dir < 0.0 and _shunt.position.x <= lo) or (_shunt_dir > 0.0 and _shunt.position.x >= CP.SHUNT_X.y):
		_shunt_dir = -_shunt_dir
		_shunt_wait = _rng.randf_range(6.0, 14.0)
		Sfx.play(self, "clank", _shunt.global_position, -2.0, 0.7)


# --- the works: the terminal crane, the conveyor, smoke, the mast lamp, the clock, the flags ------

var _tcrane: Node3D
var _tc_x := -102.0
var _tc_to := -120.0
var _tc_phase := 0.0
var _belt_items: Array = []
var _mast_lamp: Node3D
var _hands: Node3D
var _flags: Array = []
var _pa := 40.0


func _build_works() -> void:
	var lv := get_parent()
	_tcrane = lv.get_node_or_null("TerminalCrane")
	if _tcrane:   # the frame, the trolley and the spreader each one mesh, moving apart
		var tr: Node3D = _tcrane.get_node("Trolley")
		var spr: Node3D = tr.get_node("Spreader")
		tr.set_meta("live", true)
		spr.set_meta("live", true)
		Merge.bake(_tcrane, 120.0, false, 800.0)
		Merge.bake(tr, 40.0, false, 800.0)
		Merge.bake(spr, 20.0, false, 800.0)
	_mast_lamp = lv.get_node_or_null("MastLamp")
	_hands = lv.get_node_or_null("ClockHands")
	for c in lv.get_children():
		if c.has_meta("flag"):
			_flags.append(c)
	for k in 14:   # lumps of scrap riding the belt
		var b := A.box(self, Vector3(_rng.randf_range(0.3, 0.6), 0.3, _rng.randf_range(0.3, 0.6)), Vector3.ZERO, ["rust", "metal", "rubber"][k % 3], Color.WHITE, false, 0.5)
		b.set_meta("t", k / 14.0)
		_belt_items.append(b)
	var hum := AudioStreamPlayer3D.new()
	hum.stream = Sfx.stream("conveyor")
	hum.volume_db = -6.0
	hum.unit_size = 6.0
	hum.max_distance = 50.0
	hum.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	hum.autoplay = true
	add_child(hum)
	hum.position = (CP.CONV_A + CP.CONV_B) / 2.0


func _build_smoke() -> void:
	for at in CP.STACKS:
		var p := GPUParticles3D.new()
		p.amount = 50
		p.lifetime = 9.0
		p.preprocess = 9.0
		p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 60, 60))
		var m := ParticleProcessMaterial.new()
		m.direction = Vector3(0.25, 1, 0.1)
		m.spread = 10.0
		m.initial_velocity_min = 1.5
		m.initial_velocity_max = 2.5
		m.gravity = Vector3(0.4, 0.15, 0.1)
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.4))
		curve.add_point(Vector2(1, 2.4))
		var ct := CurveTexture.new()
		ct.curve = curve
		m.scale_curve = ct
		var g := Gradient.new()
		g.set_color(0, Color(0.32, 0.3, 0.28, 0.75))
		g.set_color(1, Color(0.5, 0.48, 0.45, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		m.color_ramp = gt
		p.process_material = m
		var q := QuadMesh.new()
		q.size = Vector2(3.0, 3.0)
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var rg := Gradient.new()
		rg.set_color(0, Color(1, 1, 1, 1))
		rg.set_color(1, Color(1, 1, 1, 0))
		var rt := GradientTexture2D.new()
		rt.gradient = rg
		rt.fill = GradientTexture2D.FILL_RADIAL
		rt.fill_from = Vector2(0.5, 0.5)
		rt.fill_to = Vector2(1.0, 0.5)
		mat.albedo_texture = rt
		q.material = mat
		p.draw_pass_1 = q
		add_child(p)
		p.position = at


func _works_tick(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if _tcrane:   # along its rails to a stack, the spreader down and up, on to the next
		var spreader: Node3D = _tcrane.get_node("Trolley/Spreader")
		if absf(_tc_x - _tc_to) > 0.05:
			_tc_x = move_toward(_tc_x, _tc_to, delta * 3.0)
			_tc_phase = 0.0
		else:
			_tc_phase += delta
			spreader.position.y = 12.0 - sin(clampf(_tc_phase / 8.0, 0.0, 1.0) * PI) * 8.0
			if _tc_phase > 9.0:
				_tc_to = _rng.randf_range(-140.0, -64.0)
				Sfx.play(self, "clang_big", spreader.global_position, -8.0, 0.8)
		_tcrane.position.x = _tc_x
	for b: Node3D in _belt_items:
		var k: float = fmod(float(b.get_meta("t")) + delta * 0.03, 1.0)
		b.set_meta("t", k)
		b.position = CP.CONV_A.lerp(CP.CONV_B, k) + Vector3(0, 0.3, 0)
	if _mast_lamp:
		_mast_lamp.visible = fmod(t, 1.6) < 0.5
	if _hands:
		var h: float = main.hours
		_hands.get_node("H0").rotation.z = -TAU * fmod(h, 12.0) / 12.0
		_hands.get_node("H1").rotation.z = -TAU * fmod(h, 1.0)
	for f: Node3D in _flags:
		f.rotation.y = sin(t * 1.7 + f.position.x) * 0.25
	if _torch:
		_torch.light_energy = 0.0 if randf() < 0.25 else randf_range(1.5, 4.0)
	_pa -= delta   # the yard's public address: the chime, then something heavy far off
	if _pa <= 0.0:
		_pa = _rng.randf_range(45.0, 90.0)
		Sfx.play(main, "chime", null, -16.0, 0.9)
		var far := Vector3(_rng.randf_range(-140, 140), 2.0, _rng.randf_range(-60, 110))
		Sfx.play(self, ["clang_big", "far_bang", "horn"][_rng.randi() % 3], far, -6.0, _rng.randf_range(0.7, 0.9))
