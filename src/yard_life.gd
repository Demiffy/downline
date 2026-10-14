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
const BodyAnim = preload("res://src/body_anim.gd")
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

const CLERK_FORE := 0.83
const CLERK_ARM := 0.42   # upper arms forward, forearms bent on (CLERK_FORE): the hands on the counter top


func _build_clerk() -> void:
	_clerk = Node3D.new()
	add_child(_clerk)
	_clerk.position = Vector3(-14.0, 0.18, 12.35)   # right behind the counter of the shop container (its back edge is 0.3 m in front)
	var body := Node3D.new()
	body.name = "Body"
	_clerk.add_child(body)
	_clerk_parts = Suit.standing(body)
	Suit.apply_look(body, [6, 5, 5], "BUREAU")   # charcoal, black helmet, a number
	_bake_suit(body, _clerk_parts)
	_clerk_parts.upper_arm_l.rotation = Vector3(CLERK_ARM, 0, -0.1)   # (forearms forward on the counter: + is forward on these joints)
	_clerk_parts.upper_arm_r.rotation = Vector3(CLERK_ARM, 0, 0.1)
	_clerk_parts.forearm_l.rotation = Vector3(CLERK_FORE, 0, 0)
	_clerk_parts.forearm_r.rotation = Vector3(CLERK_FORE, 0, 0)
	var lamp := OmniLight3D.new()   # a desk lamp on him
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 1.2
	lamp.omni_range = 3.0
	_clerk.add_child(lamp)
	lamp.position = Vector3(0.5, 1.9, -0.4)
	for x in [-0.75, -0.45, 0.6]:   # forms on the counter top (clear of the cash register)
		var f := A.box(_clerk, Vector3(0.21, 0.004, 0.29), Vector3(x, 1.065, -0.5), "paper", Color(0.92, 0.9, 0.82), false, 0.2)
		f.rotation.y = _rng.randf_range(-0.3, 0.3)


## Shopping: he stamps your form.
func clerk_stamp() -> void:
	_stamp_t = 0.5


var _beckon_t := -30.0
func _clerk_tick(delta: float) -> void:
	var p = main.player if main else null
	var t := Time.get_ticks_msec() / 1000.0
	_clerk_parts.torso.rotation.x = 0.06 + sin(t * 1.4) * 0.015   # (leaning on the counter, breathing)
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
	# Credits on you, out there in the yard: he waves you over to the window (a beckon, a murmur).
	_beckon_t -= delta
	var far: float = p.global_position.distance_to(_clerk.global_position) if p != null else 99.0
	if _beckon_t < -25.0 and far > 4.0 and far < 14.0 and int(main.credits) >= 15 and absf(look.y) < 0.9:
		_beckon_t = 1.8
		Sfx.play(self, "mumble", _clerk.global_position + Vector3(0, 1.6, 0), -14.0, 1.1)
	var la: Node3D = _clerk_parts.upper_arm_l
	var lf: Node3D = _clerk_parts.forearm_l
	var up := clampf(minf(_beckon_t, 1.8 - _beckon_t) / 0.3, 0.0, 1.0) if _beckon_t > 0.0 else 0.0
	la.rotation.x = lerpf(la.rotation.x, lerpf(CLERK_ARM, 1.5, up), minf(1.0, delta * 10.0))
	lf.rotation.x = lerpf(CLERK_FORE, 1.0 + sin(t * 9.0) * 0.6, up)


# --- the crane ------------------------------------------------------------------------------------

func _build_trolley() -> void:
	if crane == null:
		return
	var y := Color(0.85, 0.62, 0.15)
	_trolley = Node3D.new()
	_trolley.set_meta("live", true)   # (moves: not merged into the crane's static mesh)
	crane.add_child(_trolley)
	_trolley.position = Vector3(_x, CRANE_H - 0.1, 0)
	A.sbox(_trolley, Vector3(1.4, 0.7, 1.3), Vector3.ZERO, "metal", y.darkened(0.15), false, 0.5)
	A.sbox(_trolley, Vector3(0.7, 0.5, 0.6), Vector3(0, -0.2, -0.75), "metal", Color(0.3, 0.3, 0.3), false, 0.3)
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
	A.sbox(_hook, Vector3(0.6, 0.45, 0.35), Vector3.ZERO, "metal", y, false, 0.3)
	A.sring(_hook, 0.22, 0.13, Vector3(0, -0.45, 0), "metal", Color(0.4, 0.4, 0.4), Vector3(PI / 2, 0, 0))
	_load = Node3D.new()   # a strapped bale of crushed scrap
	_hook.add_child(_load)
	A.sbox(_load, Vector3(1.1, 0.9, 1.1), Vector3(0, -1.3, 0), "rust", Color(0.75, 0.7, 0.65), false, 0.6)
	for s in [-1, 1]:
		A.sseg(_load, Vector3(s * 0.4, -0.85, 0), Vector3(0, -0.45, 0), 0.015, 0.015, "metal", Color(0.3, 0.3, 0.3))
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
	_eye = eye
	for v in _vehicles:
		_vehicle_tick(v, delta)
	_shunter_tick(delta)
	_works_tick(delta)


# --- the people at work ----------------------------------------------------------------------------
# Each walks a round of its own (some stop to work along it), or stays put at one job.

const ROUNDS := [
	[[Vector3(-60, 0, 46.5), 0.0], [Vector3(60, 0, 46.5), 4.0]],   # (along the kerb, off the road)
	[[Vector3(-20, 0, 59), 0.0], [Vector3(20, 0, 59), 0.0], [Vector3(20, 0, 63), 6.0], [Vector3(-20, 0, 63), 0.0]],
	[[Vector3(-123, 0, 30), 5.0], [Vector3(-123, 0, 96), 0.0], [Vector3(-101, 0, 96), 5.0], [Vector3(-101, 0, 30), 0.0]],
	[[Vector3(-79, 0, 46.5), 0.0], [Vector3(-130, 0, 46.5), 6.0]],
	[[Vector3(62, 0, 30), 0.0], [Vector3(118, 0, 30), 5.0], [Vector3(118, 0, 40), 0.0], [Vector3(62, 0, 40), 7.0]],
	[[Vector3(-130, 0, -60), 0.0], [Vector3(-20, 0, -60), 8.0], [Vector3(120, 0, -60), 0.0]],
	[[Vector3(-90, 0, -27), 0.0], [Vector3(40, 0, -27), 6.0]],
	[[Vector3(30, 0, -33), 9.0], [Vector3(-60, 0, -33), 0.0]],
	[[Vector3(-45, 0, 22), 0.0], [Vector3(-45, 0, 34), 5.0], [Vector3(-60, 0, 34), 0.0]],
	[[Vector3(140, 0, 20), 0.0], [Vector3(140, 0, 4), 6.0]],
	[[Vector3(70, 0, -39), 9999.0]],    # welding in the repair shed
	[[GATE_SEAT, SITS]],                # the gate's man at his desk in the booth
	[[Vector3(-30, 0, 47), 9999.0]],    # on a break by the trucks
	[[Vector3(-18, 0, 68.5), 1.5], [Vector3(18, 0, 68.5), 1.5]],   # 13: sweeping the office forecourt
	[[Vector3(-26.2, 0, 47.4), 9999.0]],   # 14: a smoke by the trucks, beside the one on his break
	[[Vector3(-16, 0, 61), 4.0], [Vector3(16, 0, 61), 4.0]],   # 15: a pallet on a hand truck, to and fro
]
const SPECIAL := {13: "sweep", 14: "smoke", 15: "jack"}
var _people: Array = []


const SITS := -2.0                       # (a round's wait that means: seated here)
const GATE_SEAT := Vector3(20.1, 0, 5.32)  # the gatehouse chair (props.guard_booth at (20, 5), turned -90 degrees)
const SEAT_Y := 0.815                      # its seat, above the ground


func _build_people() -> void:
	var looks := [[0, 2, 0], [1, 2, 1], [1, 6, 5], [0, 0, 2], [6, 1, 3], [0, 2, 5]]
	var names := ["KOVAC", "HALE", "ORTIZ", "BREN", "MAKI", "OSEI", "DVORAK", "LUND", "REYES", "NOVAK", "PRICE", "VANCE", "SATO", "IBARRA", "FENN", "QUILL"]
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
		Suit.hand_curl = 2.6   # (hands half closed, as people's are, not held open)
		var parts := Suit.standing(body)
		Suit.hand_curl = 1.0
		var look: Array = looks[i % looks.size()].duplicate()
		if i == WELDER:
			look = [5, 2, 0, 0]   # (the visor smoked dark: his welding mask)
		Suit.apply_look(body, look, names[i])
		n.position = r[0][0] + Vector3(0, 0.06, 0)
		_bake_suit(body, parts)
		var sits: bool = r.size() == 1 and r[0][1] == SITS
		if sits:
			n.rotation.y = -PI / 2.0   # (facing +x: the desk, the window, the gate)
		var kit: String = KITS.get(i, "")
		if kit != "":
			Suit.set_held(body, parts, kit)
		var special: String = SPECIAL.get(i, "")
		_people.append({"special": special, "cover": Vector3.INF, "prop": null, "kit": kit, "act": "", "act_t": 0.0, "act_len": 0.0, "conv": null, "talked": -99.0, "voice": _rng.randf_range(0.85, 1.2), "node": n, "parts": parts, "round": r, "i": 0, "wait": _rng.randf_range(0.0, 4.0), "step": 0.0, "work": r.size() == 1 and not sits, "sit": sits,
			"anim": BodyAnim.new(), "vel": Vector3.ZERO, "pace": _rng.randf_range(1.15, 1.5), "neck": 0.0, "pitch": 0.0,
			"greeted": -99.0, "idle": _rng.randf_range(2.0, 6.0), "doze": 0.0, "page": _rng.randf_range(3.0, 8.0), "skip": 0.0})
		var w_new: Dictionary = _people[-1]
		match special:
			"sweep":
				w_new.pace = 0.55
				w_new.prop = _broom()
				n.add_child(w_new.prop)
			"smoke":
				w_new.work = false   # (stood, not sat)
				w_new.prop = _cigarette(parts)
			"jack":
				w_new.pace = 1.0
				w_new.prop = _pallet_truck()
	# The welder's work: a steel beam on two trestles right in front of him, a bead of weld along it,
	# his torch on it: a flickering blue-white arc, sparks off it.
	var w: Dictionary = _people[WELDER]
	var wp: Vector3 = w.node.position
	var steel := Color(0.42, 0.4, 0.38)
	A.sbox(self, Vector3(1.7, 0.14, 0.14), wp + Vector3(0.0, 0.72, -0.62), "rust", steel, true)
	A.sbox(self, Vector3(1.7, 0.02, 0.03), wp + Vector3(0.0, 0.8, -0.56), "metal", Color(0.25, 0.24, 0.22), false)   # the weld bead
	for x in [-0.7, 0.7]:   # the trestles: an A of angle iron each side
		for z in [-0.12, 0.12]:
			var leg := A.box(self, Vector3(0.04, 0.72, 0.04), wp + Vector3(x, 0.33, -0.62 + z), "metal", Color(0.2, 0.22, 0.24), false)
			leg.rotation.x = z * 1.6
	var gun := Node3D.new()   # his welding torch, in his right fist
	(w.parts.forearm_r as Node3D).add_child(gun)
	gun.position = Vector3(-0.012, -0.3, -0.03)
	gun.rotation.x = -1.2
	A.scyl(gun, 0.018, 0.16, Vector3(0, -0.06, 0), "plastic", Color(0.15, 0.15, 0.15), false)
	A.scyl(gun, 0.009, 0.08, Vector3(0, -0.17, 0), "copper", Color.WHITE, false)
	_torch = OmniLight3D.new()
	_torch.light_color = Color(0.7, 0.85, 1.0)
	_torch.omni_range = 6.0
	add_child(_torch)
	_torch.position = wp + Vector3(0.05, 0.84, -0.52)
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
	bm.size = Vector3.ONE * 0.01
	bm.material = A.mat("cream", Color(1, 0.8, 0.4), 1.0, 3.0)
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
const WELDER := 10
const BREAK := 12
const KITS := {0: "TOOLBOX", 1: "THERMOS", 3: "WRENCH", 4: "COFFEE_MUG", 6: "TOOLBOX", 7: "HAMMER", 8: "THERMOS", 9: "WRENCH", BREAK: "THERMOS"}


## Each limb folded into one mesh (its joints still move), and none drawn from far off.
static func _bake_suit(body: Node3D, parts: Dictionary) -> void:
	for p: Node3D in parts.values():
		p.set_meta("live", true)
	for p: Node3D in parts.values():
		Merge.bake(p, 10.0, false, 800.0)
	for mi: GeometryInstance3D in body.find_children("*", "GeometryInstance3D", true, false):
		mi.visibility_range_end = 75.0


## Each of them, every frame: walking its round with the crew's own walk (body_anim.gd: a real gait,
## breathing and weight shifts standing, glances about), easing in and out of a walk and round
## corners; at a stop something to do (a shrug, a point, a look round, a word with whoever's there);
## noticing you as you go by (a look, now and then a wave or a nod). The gate's man sits at his desk,
## the welder kneels at his work, the one on his break sits on the ground.
const GREETS := ["WAVE", "THUMBS UP", "SALUTE", "WAVE", "POINT"]
const AT_STOP := ["SHRUG", "POINT", "FACEPALM", "THUMBS UP", "LAUGH", "BECKON"]


func _person_tick(w: Dictionary, delta: float, eye: Vector3) -> void:
	var n: Node3D = w.node
	var far: float = n.position.distance_to(eye)
	if far > 120.0:
		return   # (nobody to see them: let them be)
	if far > 45.0:   # far off: a frame in three is plenty
		w.skip += delta
		if w.skip < 0.05:
			return
		delta = w.skip
	w.skip = 0.0
	var parts: Dictionary = w.parts
	var body: Node3D = n.get_child(1)
	var anim: BodyAnim = w.anim
	var t := Time.get_ticks_msec() / 1000.0
	var p = main.player if main else null
	# Where you are to them: a glance your way when you're near and in front of them.
	var you := Vector3.INF
	if p != null and not p.dead and p.global_position.distance_to(n.global_position) < 9.0:
		you = p.global_position + Vector3(0, 1.5, 0)
	if w.sit:   # in the chair at the gate: breathing, turning a page now and then, watching you; dozing off
		w.page -= delta
		w.doze = maxf(0.0, w.doze - delta)
		if w.doze <= 0.0 and _rng.randf() < delta * 0.01 and you == Vector3.INF:
			w.doze = _rng.randf_range(6.0, 14.0)
		parts.thigh_l.rotation.x = 1.5
		parts.thigh_r.rotation.x = 1.45
		parts.shin_l.rotation.x = -1.45
		parts.shin_r.rotation.x = -1.35
		body.position.y = SEAT_Y + 0.08 - 0.94 - n.position.y
		parts.torso.rotation.x = lerpf(parts.torso.rotation.x, (0.32 if w.doze > 0.0 else 0.08) + sin(t * 1.3) * 0.02, minf(1.0, delta * 2.0))
		var turning: bool = w.page < 0.0
		if w.page < -0.6:
			w.page = _rng.randf_range(4.0, 10.0)
		for a in [parts.upper_arm_l, parts.upper_arm_r]:
			a.rotation.x = lerpf(a.rotation.x, 0.5, minf(1.0, delta * 6.0))
		parts.forearm_l.rotation.x = 1.0
		parts.forearm_r.rotation.x = lerpf(parts.forearm_r.rotation.x, 1.35 if turning else 1.0 + sin(t * 0.7) * 0.05, minf(1.0, delta * 8.0))
		parts.upper_arm_r.rotation.z = lerpf(parts.upper_arm_r.rotation.z, -0.35 if turning else 0.0, minf(1.0, delta * 8.0))
		var look := Vector2(0.15, sin(t / 3.1) * 0.5)
		if w.doze > 0.0:
			look = Vector2(0.55, 0.1)   # chin on his chest
		elif you != Vector3.INF:
			var to: Vector3 = n.to_local(you) - Vector3(0, 1.3, 0)
			look = Vector2(clampf(-atan2(to.y, Vector2(to.x, to.z).length()), -0.4, 0.5), clampf(atan2(-to.x, -to.z), -1.2, 1.2))
		parts.head.rotation.x = lerpf(parts.head.rotation.x, look.x, minf(1.0, delta * 3.0))
		parts.head.rotation.y = lerpf(parts.head.rotation.y, look.y, minf(1.0, delta * 3.0))
		return
	var want_v := Vector3.ZERO
	var crouch := 0.0
	# The weather: in rain they make for the nearest roof they can see and wait under it; in a
	# sandstorm they lean into it, an arm over the visor, slower.
	var wx: String = main.weather_now() if main else "CLEAR"
	var wet: bool = wx in ["RAIN", "STORM", "ACID_RAIN"]
	var sand: bool = wx == "SANDSTORM"
	var is_welder: bool = n == _people[WELDER].node
	if wet and not is_welder:
		if w.cover == Vector3.INF and t - float(w.get("cover_t", -99.0)) > 3.0:
			w.cover_t = t
			w.cover = _find_cover(n.position)
			if w.cover != Vector3.INF:
				w.conv = null
				w.act = ""
				if anim.emote == "SIT":
					anim.stop()
	elif w.cover != Vector3.INF:
		w.cover = Vector3.INF   # (it's stopped: back to work)
	var sheltered: bool = w.cover != Vector3.INF and n.position.distance_to(w.cover) < 0.6
	if w.cover != Vector3.INF:   # off to shelter, at a run; there, waiting it out
		var to_c: Vector3 = w.cover - n.position
		to_c.y = 0.0
		if not sheltered:
			want_v = to_c.normalized() * minf(3.2, to_c.length() * 2.0)
			n.rotation.y = lerp_angle(n.rotation.y, atan2(-to_c.x, -to_c.z), minf(1.0, delta * 6.0))
			w.erase("cover_yaw")
		else:   # (turned round, their back to the wall, looking out at it)
			if not w.has("cover_yaw"):
				w.cover_yaw = n.rotation.y + PI
			n.rotation.y = lerp_angle(n.rotation.y, w.cover_yaw, minf(1.0, delta * 3.0))
			w.idle -= delta
			if w.idle <= 0.0:
				w.idle = _rng.randf_range(4.0, 9.0)
				_start_act(w, ["look_up", "fold", "fold", "watch"][_rng.randi() % 4])
	elif w.conv != null:   # in a chat: facing each other, turns at talking
		_chat_tick(w, delta, t)
	elif n == _people[WELDER].node:   # the welder: knelt right at his work, the torch on the beam, his head bent to it
		crouch = 1.0
	elif w.special == "smoke":   # a smoke: a drag now and then
		w.idle -= delta
		if w.idle <= 0.0 and w.act == "":
			w.idle = _rng.randf_range(5.0, 9.0)
			_start_act(w, "drag")
	elif w.work:   # on his break by the trucks: sat on the ground, a drink from his thermos now and then
		if anim.emote != "SIT":
			anim.play("SIT")
		w.idle -= delta
		if w.idle <= 0.0 and w.act == "":
			w.idle = _rng.randf_range(6.0, 12.0)
			_start_act(w, ["drink", "drink", "radio", "watch"][_rng.randi() % 4])
	elif w.wait > 0.0:
		w.wait -= delta
		w.idle -= delta
		if w.idle <= 0.0 and not anim.busy() and w.act == "":   # something to do while stood here
			w.idle = _rng.randf_range(3.5, 8.0)
			var mate = _near_mate(w)
			if mate != null and mate.conv == null and t - float(w.talked) > 30.0:
				_start_chat(w, mate, t)
			else:
				_idle_thing(w)
	else:
		var r: Array = w.round
		var target: Vector3 = r[w.i][0] + Vector3(0, 0.06, 0)
		var to := target - n.position
		to.y = 0.0
		if to.length() < 0.25:
			w.wait = r[w.i][1] if r[w.i][1] > 0.0 else _rng.randf_range(0.3, 1.2)
			w.i = (w.i + 1) % r.size()
			w.idle = _rng.randf_range(0.6, 2.0)
		else:
			var pace: float = float(w.pace) * (0.7 if sand else 1.0)
			want_v = to.normalized() * minf(pace, to.length() * 1.5)   # (slows as it gets there)
			n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 3.0))
			# Passing another of them close by: now and then they stop for a word.
			for o in _people:
				if o != w and o.conv == null and not o.sit and not o.work and o.node.position.distance_to(n.position) < 2.6 \
						and t - float(w.talked) > 45.0 and t - float(o.talked) > 45.0:
					w.talked = t
					if _rng.randf() < 0.45:
						_start_chat(w, o, t)
					break
	if want_v != Vector3.ZERO:   # a lorry or a forklift where they're stepping (or about to be): wait; held up a while by one that's stopped, go back the way they came
		var next := _box2(n.position + want_v.normalized() * 1.0, 0.0, 0.35, 0.35, 0.0)
		var held := false
		for o in _vehicles:
			var ob := _outline(o, (o.node as Node3D).position, float(o.yaw))
			ob[3] += 0.6
			ob[4] += 0.6
			if _overlap(next, ob):
				held = true
			elif float(o.v) > 0.3:   # (where a moving one will be in a moment)
				var ol: Dictionary = o.legs[o.leg]
				var os: float = minf(float(o.s) + float(o.v) * 1.5, ol.len)
				var oy := _face(ol, os)
				var fut := _outline(o, _at(ol, os) - Basis(Vector3.UP, oy) * Vector3(0, 0, _pivot(o)), oy)
				fut[3] += 0.6
				fut[4] += 0.6
				if _overlap(next, fut):
					held = true
		if held:
			want_v = Vector3.ZERO
			w.held = float(w.get("held", 0.0)) + delta
			if w.held > 2.0:
				w.held = 0.0
				var r: Array = w.round
				w.i = (w.i - 1 + r.size()) % r.size()   # (round the other way)
		else:
			w.held = 0.0
	if w.act == "inspect":
		crouch = 1.0
	# Speeding up and slowing down like someone walking, not starting and stopping dead.
	var v: Vector3 = w.vel
	v = v.move_toward(want_v, delta * (1.6 if want_v.length() > v.length() else 2.4))
	w.vel = v
	n.position += v * delta
	# You, going by: a look; once in a while, a greeting (a wave, a nod, a thumbs up...).
	var neck := 0.0
	var pitch := 0.0
	if you != Vector3.INF and w.conv == null:
		var to_y: Vector3 = n.to_local(you)
		var yaw := atan2(-to_y.x, -to_y.z)
		if absf(yaw) < 1.6:
			neck = clampf(yaw, -1.1, 1.1)
			pitch = clampf(atan2(to_y.y - 1.5, Vector2(to_y.x, to_y.z).length()), -0.4, 0.4)
			if t - float(w.greeted) > 40.0 and not anim.busy() and w.act == "" and n.position.distance_to(you) < 6.5 and n != _people[WELDER].node:
				w.greeted = t
				if _rng.randf() < 0.6:
					if _rng.randf() < 0.35:
						_start_act(w, "nod")
					else:
						anim.play(GREETS[_rng.randi() % GREETS.size()])
	elif w.conv != null:   # (looking at whoever they're talking to)
		var m: Node3D = w.conv.mate.node
		var to_m: Vector3 = n.to_local(m.position + Vector3(0, 1.5, 0))
		neck = clampf(atan2(-to_m.x, -to_m.z), -0.6, 0.6)
	w.neck = lerpf(w.neck, neck, minf(1.0, delta * 4.0))
	w.pitch = lerpf(w.pitch, pitch, minf(1.0, delta * 4.0))
	if n == _people[WELDER].node:
		_weld_pose(parts, body, t)
		return
	anim.pose(parts, body, {"vel": v, "yaw": n.rotation.y, "floor": true, "crouch": crouch, "pitch": w.pitch, "neck": w.neck, "hands": true}, delta)
	_special_tick(w, delta, t, v)
	if sand and not sheltered:   # leaning into the sand, the left arm over the visor
		parts.torso.rotation.x -= 0.22
		parts.head.rotation.x += 0.2
		parts.upper_arm_l.rotation = Vector3(1.6, 0, 0.45)
		parts.forearm_l.rotation = Vector3(1.9, 0, 0)
	elif wet and not sheltered and w.cover != Vector3.INF:   # hunched, a hand on the helmet, running
		parts.torso.rotation.x -= 0.25
		parts.head.rotation.x += 0.25
		parts.upper_arm_l.rotation = Vector3(2.7, 0, -0.5)
		parts.forearm_l.rotation = Vector3(1.2, 0, 0)
	_act_tick(w, delta, t)


## The welder: down on his right knee, left foot planted, leaning in over the beam; the torch in his
## right hand working slowly along the seam, his left hand steadying the beam, his head bent to it
## behind the dark visor, the odd shift of his weight.
func _weld_pose(parts: Dictionary, body: Node3D, t: float) -> void:
	var sway := sin(t * 0.35) * 0.04
	body.position = Vector3(0, -0.46, 0)
	body.rotation = Vector3.ZERO
	parts.pelvis.rotation = Vector3(0, sway, 0)
	parts.thigh_r.rotation = Vector3(-0.05, 0, 0.04)      # the knee down: thigh straight down
	parts.shin_r.rotation = Vector3(-1.55, 0, 0)          # shin back along the ground
	parts.thigh_l.rotation = Vector3(1.45, 0, -0.08)      # the other foot planted in front: thigh out level
	parts.shin_l.rotation = Vector3(-1.45, 0, 0)          # shin straight down to it
	parts.torso.rotation = Vector3(-0.32 + sin(t * 0.8) * 0.015, -sway * 0.5, 0)   # (leaning in: - is forward on the torso)
	var along := sin(t * 0.5) * 0.12   # (the torch working slowly along the seam)
	parts.upper_arm_r.rotation = Vector3(0.75, along, 0.12)
	parts.forearm_r.rotation = Vector3(0.7 + sin(t * 2.3) * 0.04, 0, 0)
	parts.upper_arm_l.rotation = Vector3(0.75, 0.2, -0.05)
	parts.forearm_l.rotation = Vector3(0.55, 0, 0)
	parts.head.rotation = Vector3(0.3, along * 0.8, 0)


## Something to do, stood about: a drink if there's a thermos or a mug in hand, a word on the radio,
## a look at the watch, a stretch, a scratch of the helmet, a crouch to look at something, a scuff of
## the boot, or one of the crew's own moves (a shrug, a point...).
func _idle_thing(w: Dictionary) -> void:
	var can: Array = ["radio", "watch", "stretch", "scratch", "inspect", "scuff", "emote", "emote"]
	if w.kit in ["THERMOS", "COFFEE_MUG"]:
		can += ["drink", "drink"]
	var pick: String = can[_rng.randi() % can.size()]
	if pick == "emote":
		w.anim.play(AT_STOP[_rng.randi() % AT_STOP.size()])
	else:
		_start_act(w, pick)


const ACT_LEN := {"drag": 2.4, "look_up": 2.2, "fold": 6.0, "drink": 2.6, "radio": 3.2, "watch": 2.0, "stretch": 2.8, "scratch": 1.8, "inspect": 3.0, "scuff": 1.2, "nod": 1.1, "talk": 99.0, "listen": 99.0}


func _start_act(w: Dictionary, what: String) -> void:
	w.act = what
	w.act_t = 0.0
	w.act_len = ACT_LEN.get(what, 2.0)
	var n: Node3D = w.node
	if what == "radio":
		Sfx.play(self, "crackle", n.position + Vector3(0, 1.6, 0), -20.0, 1.4)
	if what == "drink" and w.kit == "":
		w.act = ""


## Each act, over the pose the walk gave: blended in and out over a quarter second.
func _act_tick(w: Dictionary, delta: float, t: float) -> void:
	if w.act == "":
		return
	w.act_t += delta
	var at: float = w.act_t
	if at > w.act_len:
		w.act = ""
		return
	var k := clampf(at / 0.3, 0.0, 1.0) * clampf((float(w.act_len) - at) / 0.3, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var parts: Dictionary = w.parts
	var to := {}   # part -> rotation, blended in by k
	match w.act:
		"drink":   # the cup (or the thermos) up to the visor, head back a little
			to = {"upper_arm_r": Vector3(1.25, 0, 0.42), "forearm_r": Vector3(1.95, 0, 0), "head": Vector3(-0.3, 0, 0)}
		"radio":   # the hand-mic on the shoulder strap up to the helmet: head turned into it
			to = {"upper_arm_l": Vector3(1.0, 0, -0.55), "forearm_l": Vector3(2.15, 0, 0.2), "head": Vector3(0.1, -0.35, 0)}
		"watch":   # wrist up in front, a look at it
			to = {"upper_arm_l": Vector3(0.6, 0, 0.35), "forearm_l": Vector3(1.65, 0, 0), "head": Vector3(0.6, -0.15, 0)}   # (the wrist across in front of the chest)
		"stretch":   # both arms up, back arched
			to = {"upper_arm_l": Vector3(2.85, 0, -0.25), "upper_arm_r": Vector3(2.85, 0, 0.25), "forearm_l": Vector3(0.3, 0, 0), "forearm_r": Vector3(0.3, 0, 0), "torso": Vector3(-0.18, 0, 0), "head": Vector3(-0.35, 0, 0)}
		"scratch":   # a scratch at the back of the helmet
			to = {"upper_arm_r": Vector3(2.3, 0, 0.55), "forearm_r": Vector3(2.0 + sin(at * 18.0) * 0.15, 0, 0), "head": Vector3(0.25, 0.15, 0)}
		"inspect":   # crouched, reaching to something on the ground, head down to it
			to = {"upper_arm_r": Vector3(1.0, 0, 0.1), "forearm_r": Vector3(0.6 + sin(at * 3.0) * 0.1, 0, 0), "head": Vector3(0.75, 0, 0)}
		"scuff":   # a scuff of the boot at the ground
			var sw := sin(clampf(at / 1.2, 0.0, 1.0) * TAU)
			to = {"thigh_r": Vector3(0.35 * sw, 0, 0), "shin_r": Vector3(-0.3 * absf(sw), 0, 0)}
		"drag":   # a drag on the cigarette: up to the visor's vent, the tip glowing; then a puff
			to = {"upper_arm_r": Vector3(1.25, 0, 0.4), "forearm_r": Vector3(2.15, 0, 0), "head": Vector3(-0.1, 0, 0)}
		"look_up":   # under cover: a look up at the sky, at the rain
			to = {"head": Vector3(-0.55, 0.2 * sin(at), 0), "torso": Vector3(-0.05, 0, 0)}
		"fold":   # arms folded, waiting it out
			to = {"upper_arm_l": Vector3(0.45, 0, 0.35), "forearm_l": Vector3(1.75, 0, 0), "upper_arm_r": Vector3(0.45, 0, -0.35), "forearm_r": Vector3(1.75, 0, 0)}
		"nod":   # a nod: hello
			to = {"head": Vector3(0.35 * sin(clampf(at / 1.1, 0.0, 1.0) * TAU * 1.5), 0, 0)}
		"talk":   # talking: the hands going with the words, the head nodding along
			to = {"upper_arm_r": Vector3(0.45 + sin(t * 4.3) * 0.12, 0, 0.2), "forearm_r": Vector3(1.25 + sin(t * 6.1) * 0.3, 0.3 * sin(t * 2.7), 0),
				"upper_arm_l": Vector3(0.25 + sin(t * 3.1 + 1.0) * 0.08, 0, -0.15), "forearm_l": Vector3(0.9 + sin(t * 5.3) * 0.2, 0, 0),
				"head": Vector3(0.05 + sin(t * 3.7) * 0.06, 0, 0.05 * sin(t * 1.9))}
		"listen":   # listening: a hand on the hip, a nod now and then
			to = {"upper_arm_l": Vector3(0.2, 0, -0.55), "forearm_l": Vector3(1.6, 0, 0), "head": Vector3(0.1 + maxf(0.0, sin(t * 2.2)) * 0.12, 0, 0.08)}
	for part in to:
		var node: Node3D = parts[part]
		var goal: Vector3 = to[part]
		node.rotation = node.rotation.lerp(goal, k)


## Two of them stop for a word: face each other, take turns (the one talking talks with their hands,
## a murmur through the helmet; the other listens, nods), a laugh at the end sometimes, then on.
func _start_chat(a: Dictionary, b: Dictionary, t: float) -> void:
	var len := _rng.randf_range(8.0, 15.0)
	a.conv = {"mate": b, "until": t + len, "talking": true, "turn": t + _rng.randf_range(1.5, 3.0)}
	b.conv = {"mate": a, "until": t + len, "talking": false, "turn": a.conv.turn}
	a.talked = t
	b.talked = t
	for w in [a, b]:
		w.anim.stop()
		w.act = ""
		w.wait = maxf(float(w.wait), len)
	_say(a)


func _chat_tick(w: Dictionary, delta: float, t: float) -> void:
	var c: Dictionary = w.conv
	var n: Node3D = w.node
	var m: Node3D = c.mate.node
	var to: Vector3 = m.position - n.position
	n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 3.0))
	if t > float(c.until) or c.mate.conv == null:   # done: a laugh, sometimes, and back to it
		w.conv = null
		w.act = ""
		w.wait = 0.0 if not w.work else w.wait
		if _rng.randf() < 0.4:
			w.anim.play("LAUGH")
		return
	if t > float(c.turn) and c.talking:   # over to them
		c.talking = false
		c.mate.conv.talking = true
		var next := t + _rng.randf_range(1.8, 3.5)
		c.turn = next
		c.mate.conv.turn = next
		_say(c.mate)
	var want := "talk" if c.talking else "listen"
	if w.act != want:
		_start_act(w, want)


func _say(w: Dictionary) -> void:
	Sfx.play(self, "mumble", w.node.position + Vector3(0, 1.6, 0), -12.0, float(w.voice))


## The jobs some of them have, each frame over the walk's pose: a broom swept to and fro in front of
## the sweeper; the smoker's cigarette, its tip glowing on a drag and a puff after; a hand pallet truck
## pulled along behind, its handle in a hand.
func _special_tick(w: Dictionary, delta: float, t: float, v: Vector3) -> void:
	var parts: Dictionary = w.parts
	match w.special:
		"sweep":
			var stroke := sin(t * 3.0)
			var broom: Node3D = w.prop
			var hand := Vector3(0.05, 1.12, -0.42)
			var head := Vector3(0.0, 0.05, -1.05 + stroke * 0.22)
			var dir := (head - hand).normalized()
			var xb := dir.cross(Vector3.RIGHT).normalized()
			broom.transform = Transform3D(Basis(xb, -dir, xb.cross(-dir)).orthonormalized(), hand)
			parts.upper_arm_l.rotation = Vector3(1.0 + stroke * 0.15, 0, 0.25)
			parts.forearm_l.rotation = Vector3(0.45 + stroke * 0.15, 0, 0)
			parts.upper_arm_r.rotation = Vector3(0.85 + stroke * 0.15, 0, -0.2)
			parts.forearm_r.rotation = Vector3(0.6 + stroke * 0.12, 0, 0)
			parts.torso.rotation.x -= 0.2
			parts.head.rotation.x += 0.3
			if absf(stroke) > 0.98 and t - float(w.get("swish_t", 0.0)) > 0.6 and w.node.position.distance_to(_eye) < 18.0:
				w.swish_t = t
				Sfx.play(self, "rustle", w.node.to_global(head), -22.0, randf_range(1.3, 1.6))
		"smoke":
			var tip: StandardMaterial3D = w.prop
			tip.emission_energy_multiplier = lerpf(tip.emission_energy_multiplier, 6.0 if w.act == "drag" else 1.2, minf(1.0, delta * 4.0))
			if w.act != "drag" and w.get("dragged", false):   # out with it: a puff of smoke
				w.dragged = false
				_puff(w.node.to_global(Vector3(0, 1.62, -0.25)))
			if w.act == "drag":
				w.dragged = true
			elif w.act == "":
				parts.upper_arm_l.rotation = Vector3(0.35, 0, 0.3)   # (the other arm across, holding the elbow)
				parts.forearm_l.rotation = Vector3(1.6, 0, 0)
				parts.upper_arm_r.rotation = Vector3(0.25, 0, 0.1)
				parts.forearm_r.rotation = Vector3(1.1, 0, 0)
		"jack":
			var jack: Node3D = w.prop
			var n: Node3D = w.node
			jack.global_transform = n.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.42, 0.0, 0.72))
			parts.upper_arm_r.rotation = Vector3(-0.45, 0, 0.18)
			parts.forearm_r.rotation = Vector3(0.3, 0, 0)
			if v.length() > 0.3 and t - float(w.get("squeak_t", 0.0)) > 2.5 and n.position.distance_to(_eye) < 20.0:
				w.squeak_t = t
				Sfx.play(self, "creak", jack.global_position + Vector3(0, 0.2, 0), -20.0, randf_range(1.8, 2.3))


func _broom() -> Node3D:   # its handle along its -y from the hands, the head at the end
	var b := Node3D.new()
	A.scyl(b, 0.016, 1.35, Vector3(0, -0.6, 0), "wood", Color(0.62, 0.48, 0.3), false)
	var head := A.box(b, Vector3(0.42, 0.06, 0.08), Vector3(0, -1.28, 0), "wood", Color(0.35, 0.25, 0.16), false, 0.3)
	A.sbox(b, Vector3(0.4, 0.07, 0.06), Vector3(0, -1.34, 0), "canvas", Color(0.2, 0.18, 0.15), false, 0.3)   # bristles
	head.rotation.z = 0.0
	return b


func _cigarette(parts: Dictionary) -> StandardMaterial3D:
	var hand: Node3D = parts.forearm_r
	var c := Node3D.new()
	hand.add_child(c)
	c.position = Vector3(-0.03, -0.33, -0.05)
	A.scyl(c, 0.0045, 0.07, Vector3(0, 0, -0.035), "paper", Color(0.95, 0.93, 0.88), false, "z")
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0055
	sm.height = 0.011
	tip.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.1, 0.05)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.35, 0.08)
	m.emission_energy_multiplier = 1.2
	tip.material_override = m
	c.add_child(tip)
	tip.position = Vector3(0, 0, -0.072)
	return m


func _pallet_truck() -> Node3D:   # a hand pallet truck with a load on it: forks, wheels, the handle up to a hand
	var j := Node3D.new()
	add_child(j)
	var red := Color(0.75, 0.15, 0.1)
	for sx in [-0.28, 0.28]:
		A.sbox(j, Vector3(0.16, 0.07, 1.15), Vector3(sx, 0.07, 0.6), "metal", red, false, 0.3)
		A.scyl(j, 0.04, 0.06, Vector3(sx, 0.04, 1.12), "rubber", Color.WHITE, false, "x")
	A.sbox(j, Vector3(0.7, 0.32, 0.18), Vector3(0, 0.2, -0.02), "metal", red, false, 0.3)   # the pump housing
	A.scyl(j, 0.08, 0.1, Vector3(0, 0.08, -0.05), "rubber", Color.WHITE, false, "x")
	A.sseg(j, Vector3(0, 0.35, -0.05), Vector3(-0.22, 0.98, -0.42), 0.02, 0.02, "metal", Color(0.2, 0.2, 0.2))   # the handle
	A.sbox(j, Vector3(0.2, 0.04, 0.05), Vector3(-0.22, 1.0, -0.43), "rubber", Color.WHITE, false, 0.3)
	A.pallet(j, Vector3(0, 0.06, 0.6))
	for k in 4:
		A.sbox(j, Vector3(0.5, 0.36, 0.42), Vector3(-0.27 + (k % 2) * 0.54, 0.38 + (k / 2) * 0.37, 0.6), "cardboard", Color(0.72, 0.58, 0.4).darkened(k * 0.04), false, 0.5)
	Merge.bake(j, 10.0, false, 200.0)
	return j


func _puff(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = 10
	p.lifetime = 2.2
	p.direction = Vector3(0, 1, -0.5)
	p.spread = 25.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0.15, 0.12, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var grow := Curve.new()
	grow.max_value = 4.0
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 4.0))
	p.scale_amount_curve = grow
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tex := GradientTexture2D.new()
	var tg := Gradient.new()
	tg.set_color(0, Color(1, 1, 1, 1))
	tg.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = tg
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	m.albedo_texture = tex
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.85, 0.85, 0.35))
	g.set_color(1, Color(0.8, 0.8, 0.8, 0.0))
	p.color_ramp = g
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


## A dry spot under a roof near `from` that they can get to straight (nothing in between), not one
## another's already in; failing that, up against the nearest wall; INF if there's none. The yard's roofs are found once.
var _covers: Array = []
func _find_cover(from: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if _covers.is_empty():
		_covers.append(Vector3.INF)   # (looked: none would leave it empty and look again)
		var x := -150.0
		while x <= 150.0:
			var z := -70.0
			while z <= 115.0:
				var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 1.4, z), Vector3(x, 14.0, z), 1))
				if not up.is_empty():
					var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 1.4, z), Vector3(x, -1.0, z), 1))
					if not down.is_empty() and down.position.y < 0.4:
						var q := PhysicsShapeQueryParameters3D.new()
						var sp := SphereShape3D.new()
						sp.radius = 0.45
						q.shape = sp
						q.transform = Transform3D(Basis.IDENTITY, Vector3(x, 1.0, z))
						q.collision_mask = 1
						if space.intersect_shape(q, 1).is_empty():
							_covers.append(Vector3(x, 0.06, z))
				z += 3.0
			x += 3.0
	var best := Vector3.INF
	var bd := 32.0
	for c in _covers:
		if c == Vector3.INF:
			continue
		var d: float = Vector2(c.x - from.x, c.z - from.z).length()
		if d >= bd:
			continue
		var taken := false
		for o in _people:
			if o.cover != Vector3.INF and o.cover.distance_to(c) < 1.0:
				taken = true
		if taken:
			continue
		var line := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(from.x, 1.0, from.z), Vector3(c.x, 1.0, c.z), 1))
		if line.is_empty():
			best = c
			bd = d
	if best != Vector3.INF:
		return best
	# No roof near: in against the nearest wall then, out of the worst of it.
	bd = 25.0
	for k in 12:
		var dir := Vector3(sin(TAU * k / 12.0), 0, cos(TAU * k / 12.0))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(from.x, 1.0, from.z), Vector3(from.x, 1.0, from.z) + dir * bd, 1))
		if hit.is_empty() or absf(hit.normal.y) > 0.3:
			continue
		var d_hit: float = Vector2(hit.position.x - from.x, hit.position.z - from.z).length()
		var high := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(from.x, 3.6, from.z), Vector3(from.x, 3.6, from.z) + dir * (d_hit + 0.6), 1))
		if high.is_empty():   # (a building's wall, not a fence or a lorry)
			continue
		var c: Vector3 = hit.position + hit.normal * 0.45
		c.y = 0.06
		var taken := false
		for o in _people:
			if o.cover != Vector3.INF and o.cover.distance_to(c) < 1.0:
				taken = true
		if not taken:
			best = c
			bd = from.distance_to(hit.position)
	return best


## Somebody else stopped close by (for a word), or null.
func _near_mate(w: Dictionary):
	for o in _people:
		if o != w and not o.sit and o.vel.length() < 0.2 and o.node.position.distance_to(w.node.position) < 4.0:
			return o
	return null


# --- vehicles --------------------------------------------------------------------------------------

# Each one drives a real round: a path of legs (forward or backing up), corners rounded to what it
# can turn, three-point turns at the ends of the roads and at its stops; it speeds up and slows down
# like something heavy (and for corners), changes gear, waits for anyone in its way (and honks if
# they don't move), stops at its deliveries with its hazards going. Its wheels turn and the front
# ones steer; the body pitches as it brakes and leans on a corner; brake lights, reverse lights and a
# beeper backing up, indicators before a turn; smoke off the stack, thick as it pulls away; a driver
# in the cab who looks where he's going, over his shoulder backing up, and now and then waves.
# The forklifts carry a pallet between two stacks: drive up, lift it, back out, take it over, set it
# down, back away.

const TRUCK_RUNS := [
	# A delivery round: out along the ring road, down the east side road, a three-point turn at its end
	# (a delivery: hazards on), back up it, along, down the west one, round again.
	[[1, [Vector3(-54.5, 0, 103), Vector3(-51.5, 0, 99), Vector3(-50, 0, 92), Vector3(-50, 0, 42.5), Vector3(50, 0, 42.5), Vector3(50, 0, 98), Vector3(53, 0, 103)], 7.0, 6.0],
	 [-1, [Vector3(53, 0, 103), Vector3(51, 0, 100.5), Vector3(49.5, 0, 103)], 1.3, 0.8],
	 [1, [Vector3(49.5, 0, 103), Vector3(52.5, 0, 99), Vector3(54, 0, 92), Vector3(54, 0, 38.5), Vector3(-54, 0, 38.5), Vector3(-54, 0, 98), Vector3(-51, 0, 103)], 7.0, 6.0],
	 [-1, [Vector3(-51, 0, 103), Vector3(-53, 0, 100.5), Vector3(-54.5, 0, 103)], 1.3, 0.8]],
	# The long haul: the whole ring road, a three-point turn at each end.
	[[1, [Vector3(-135, 0, 37), Vector3(-131, 0, 41), Vector3(-124, 0, 42.5), Vector3(128, 0, 42.5), Vector3(136, 0, 42.5), Vector3(141, 0, 38.5)], 9.0, 1.0],
	 [-1, [Vector3(141, 0, 38.5), Vector3(138.5, 0, 41.5), Vector3(141, 0, 44)], 1.3, 0.6],
	 [1, [Vector3(141, 0, 44), Vector3(137, 0, 40), Vector3(130, 0, 38.5), Vector3(-122, 0, 38.5), Vector3(-130, 0, 38.5), Vector3(-135, 0, 42.5)], 9.0, 1.0],
	 [-1, [Vector3(-135, 0, 42.5), Vector3(-132.5, 0, 39.5), Vector3(-135, 0, 37)], 1.3, 0.6]]   # (the west turn short of the forklift's patch),
]
const TRUCK_STARTS := [[0, 0.0], [1, 0.0], [0, 0.5]]   # run, how far round it starts (the third shares the delivery round, half a round behind)
const LIFTS := [   # [spot A, its facing; spot B, its facing]: where a forklift picks up and sets down
	[Vector3(64, 0.05, 52), Vector3(0, 0, -1), Vector3(68, 0.05, 64), Vector3(0, 0, 1)],
	[Vector3(-148, 0.05, 48.5), Vector3(0, 0, 1), Vector3(-148, 0.05, 32.5), Vector3(0, 0, -1)],
]
const GEARS := [2.4, 4.6, 7.4, 11.0]   # each gear's top speed, m/s
var _vehicles: Array = []
var _eye := Vector3.ZERO


func _build_vehicles() -> void:
	for st in TRUCK_STARTS:
		var legs := _legs(TRUCK_RUNS[st[0]], 6.5)
		var v := _vehicle("truck", legs)
		_place_along(v, float(st[1]))
	for job in LIFTS:
		var v := _vehicle("forklift", _lift_legs(job))
		v.pallet = _pallet(job[0])
		v.carry = false
		_place_along(v, 0.0)


## A vehicle and everything it needs to drive: the model on wheel pivots, its body (that leans), the
## lamps, the smoke, the sounds, a driver.
func _vehicle(kind: String, legs: Array) -> Dictionary:
	var holder := Node3D.new()
	holder.set_meta("live", true)
	add_child(holder)
	var parts := {"wheels": []}
	var truck := kind == "truck"
	var r: Node3D = CP.truck(holder, Vector3(0, 0.08, 0), 0.0, _rng, false, parts) if truck else P.forklift(holder, Vector3(0, 0.05, 0), 0.0, parts)
	var hit := AnimatableBody3D.new()   # (solid: you can't walk through it; it doesn't shove you about either)
	hit.sync_to_physics = false
	holder.add_child(hit)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.5, 3.4, 7.6) if truck else Vector3(1.2, 2.2, 2.6)
	cs.shape = bs
	cs.position = Vector3(0, bs.size.y / 2.0, 0.0 if truck else 0.2)
	hit.add_child(cs)
	for w in parts.wheels:
		Merge.bake(w[1], 10.0, false, 300.0)
	if parts.has("carriage"):
		Merge.bake(parts.carriage, 10.0, false, 300.0)
	Merge.bake(r, 50.0, false, 800.0)   # (one mesh that drives about, not a hundred)
	# The body that leans: everything merged, moved under a node of its own (the wheels stay put).
	var body := Node3D.new()
	body.set_meta("live", true)
	r.add_child(body)
	body.position = Vector3(0, 1.0 if truck else 0.6, 0)
	for c in r.get_children():
		if c is MeshInstance3D:
			c.reparent(body)
	if parts.has("carriage"):
		parts.carriage.reparent(body)
	var driver := _driver(body, truck)
	var L := {}   # the lamps: emissive boxes we switch, each its own material
	if truck:
		for sx in [-1.0, 1.0]:
			L["brake%d" % sx] = _lamp_box(body, Vector3(0.22, 0.12, 0.03), Vector3(sx * 0.95, 0.12, 3.8), Color(1, 0.08, 0.05))
			L["rev%d" % sx] = _lamp_box(body, Vector3(0.12, 0.1, 0.03), Vector3(sx * 0.62, -0.05, 3.8), Color(1, 1, 0.95))
			L["ind_r%d" % sx] = _lamp_box(body, Vector3(0.12, 0.1, 0.03), Vector3(sx * 1.15, -0.05, 3.8), Color(1, 0.55, 0.05))
			L["ind_f%d" % sx] = _lamp_box(body, Vector3(0.16, 0.13, 0.03), Vector3(sx * 0.98, 0.47, -3.77), Color(1, 0.55, 0.05))
	else:
		L["beacon"] = _lamp_box(body, Vector3(0.12, 0.1, 0.12), Vector3(0, 1.62, 0.6), Color(1, 0.55, 0.08))
		for sx in [-1.0, 1.0]:
			L["rev%d" % sx] = _lamp_box(body, Vector3(0.08, 0.08, 0.03), Vector3(sx * 0.42, 0.45, 1.33), Color(1, 1, 0.95))
			L["brake%d" % sx] = _lamp_box(body, Vector3(0.08, 0.08, 0.03), Vector3(sx * 0.3, 0.45, 1.33), Color(1, 0.08, 0.05))
	var head := SpotLight3D.new()   # headlights
	head.light_color = Color(1.0, 0.92, 0.75)
	head.light_energy = 2.0
	head.spot_range = 22.0 if truck else 12.0
	head.spot_angle = 30.0
	body.add_child(head)
	head.position = Vector3(0, 0.2 if truck else 1.0, -3.8 if truck else -1.0)
	var back := OmniLight3D.new()   # the reverse lights on the ground behind it
	back.light_color = Color(1, 0.97, 0.9)
	back.omni_range = 5.0
	back.light_energy = 0.0
	body.add_child(back)
	back.position = Vector3(0, 0.0, 4.4 if truck else 1.8)
	var smoke := _exhaust(body, Vector3(0.95, 2.6, -1.5) if truck else Vector3(-0.35, 1.35, 1.0), 1.0 if truck else 0.45)
	var engines := []   # idling, and working: blended by the revs (both rebuilt from real engines: engine_data.gd)
	for snd in (["truck_idle", "truck_rev"] if truck else ["fork_idle", "fork_work"]):
		var engine := AudioStreamPlayer3D.new()
		engine.stream = Sfx.stream(snd)
		engine.volume_db = -12.0
		engine.unit_size = 6.0 if truck else 4.0
		engine.max_distance = 60.0 if truck else 35.0
		engine.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
		engine.autoplay = true
		holder.add_child(engine)
		engines.append(engine)
	var v := {"kind": kind, "node": holder, "body": body, "parts": parts, "legs": legs, "leg": 0, "s": 0.0, "v": 0.0, "wait": 0.0,
		"yaw": 0.0, "steer": 0.0, "acc": 0.0, "gear": 0, "shift": 0.0, "lamps": L, "head": head, "back": back, "smoke": smoke,
		"engines": engines, "driver": driver, "beep": 0.0, "blocked": 0.0, "honked": -99.0, "waved": -99.0, "blink": 0.0, "lift": 0.0,
		"stopped": true, "pallet": null, "carry": false, "look": 0.0, "id": _vehicles.size(), "blocked_by": -1, "look_t": randf() * 0.2, "blocker": 0, "backoff": 0.0, "hold": 0.0}
	_vehicles.append(v)
	return v


## Somebody at the wheel: sat, hands on it, head free to turn (a whole suit, folded at the hips).
func _driver(body: Node3D, truck: bool) -> Dictionary:
	var n := Node3D.new()
	n.set_meta("live", true)
	body.add_child(n)
	var seat_y := 0.98 if truck else 0.46   # (the seat top, in the body's frame)
	n.position = Vector3(-0.55 if truck else 0.0, seat_y + 0.08 - 0.94, (-2.6 if truck else 0.45))
	Suit.hand_curl = 2.6
	var parts := Suit.standing(n)
	Suit.hand_curl = 1.0
	Suit.apply_look(n, [[0, 2, 0], [1, 6, 5], [6, 1, 3]][_rng.randi() % 3], "DRIVER")
	_bake_suit(n, parts)
	parts.thigh_l.rotation.x = 1.45
	parts.thigh_r.rotation.x = 1.45
	parts.shin_l.rotation.x = -1.3
	parts.shin_r.rotation.x = -1.3
	return parts


func _lamp_box(parent: Node3D, size: Vector3, at: Vector3, c: Color) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.6)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = at
	return m


## Smoke off the stack: grey puffs that swell and drift, `k` their size; how many and how dark is
## set as it drives (_vehicle_tick: more and darker pulling away).
func _exhaust(parent: Node3D, at: Vector3, k: float) -> Array:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 2.6
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 16, 24))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 14.0
	m.initial_velocity_min = 1.0 * k
	m.initial_velocity_max = 2.2 * k
	m.gravity = Vector3(0.25, 0.35, 0)
	m.damping_min = 0.6
	m.damping_max = 1.2
	m.scale_min = 0.5
	m.scale_max = 0.9
	var grow := Curve.new()
	grow.max_value = 4.0   # (a Curve clamps to 0..1 otherwise)
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 4.0))
	var gt := CurveTexture.new()
	gt.curve = grow
	m.scale_curve = gt
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.42))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	m.color_ramp = ft
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45) * k
	var sm := StandardMaterial3D.new()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.billboard_keep_scale = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.32, 0.31, 0.3)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var puff := GradientTexture2D.new()
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 0.9))
	pg.set_color(1, Color(1, 1, 1, 0.0))
	puff.gradient = pg
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	sm.albedo_texture = puff
	quad.material = sm
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.position = at
	return [p, sm]


## A pallet with its load (cartons strapped on), standing at `at`.
func _pallet(at: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.position = at
	A.pallet(n, Vector3.ZERO)
	var tint := [Color(0.72, 0.58, 0.38), Color(0.65, 0.52, 0.34), Color(0.75, 0.62, 0.42)]
	for k in 6:
		A.sbox(n, Vector3(0.55, 0.4, 0.45), Vector3(-0.29 + (k % 2) * 0.58, 0.36 + (k / 4) * 0.41, -0.24 + ((k / 2) % 2) * 0.48), "cardboard", tint[k % 3], false, 0.5)
	A.sbox(n, Vector3(0.03, 0.9, 1.04), Vector3(0, 0.6, 0), "plastic", Color(0.15, 0.15, 0.15), false, 0.3)   # a strap over it
	Merge.bake(n, 10.0, false, 200.0)
	return n


# --- paths -------------------------------------------------------------------------------------------

## Legs from [dir, corners, top speed, wait after]: each corner rounded off at `radius` (a quadratic
## curve through it), the whole leg a polyline with its length run along it.
func _legs(run: Array, radius: float) -> Array:
	var out := []
	for l in run:
		out.append(_leg(l[0], _round(l[1], radius), l[2], l[3]))
	return out


func _leg(dir: int, pts: PackedVector3Array, speed: float, wait: float, event := "") -> Dictionary:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	return {"dir": dir, "pts": pts, "cum": cum, "len": cum[cum.size() - 1], "speed": speed, "wait": wait, "event": event}


func _round(corners: Array, r: float) -> PackedVector3Array:
	var out := PackedVector3Array([corners[0]])
	for i in range(1, corners.size() - 1):
		var a: Vector3 = corners[i - 1]
		var b: Vector3 = corners[i]
		var c: Vector3 = corners[i + 1]
		var u1 := (b - a).normalized()
		var u2 := (c - b).normalized()
		var th := acos(clampf(u1.dot(u2), -1.0, 1.0))
		if th < 0.05:
			out.append(b)
			continue
		var d := minf(r * tan(th / 2.0), minf(a.distance_to(b), b.distance_to(c)) * 0.5)
		var p1 := b - u1 * d
		var p2 := b + u2 * d
		var n := maxi(4, int(th * 12.0))
		for k in n + 1:
			var t := float(k) / n
			out.append(p1.lerp(b, t).lerp(b.lerp(p2, t), t))
	out.append(corners[corners.size() - 1])
	return out


func _at(leg: Dictionary, s: float) -> Vector3:
	var cum: PackedFloat32Array = leg.cum
	var pts: PackedVector3Array = leg.pts
	s = clampf(s, 0.0, leg.len)
	var i := cum.bsearch(s) - 1
	i = clampi(i, 0, pts.size() - 2)
	var seg := cum[i + 1] - cum[i]
	return pts[i].lerp(pts[i + 1], (s - cum[i]) / seg if seg > 0.0001 else 0.0)


## Which way the path runs at s (smoothed over a couple of metres, so the body turns as a body does).
func _tangent(leg: Dictionary, s: float) -> Vector3:
	var t := _at(leg, s + 1.2) - _at(leg, s - 1.2)
	return t.normalized() if t.length() > 0.001 else Vector3(0, 0, -1)


## Facing along a leg at s: the way it goes, or (backing up) the other way.
func _face(leg: Dictionary, s: float) -> float:
	var t := _tangent(leg, s) * float(leg.dir)
	return atan2(-t.x, -t.z)


func _place_along(v: Dictionary, frac: float) -> void:
	var total := 0.0
	for l in v.legs:
		total += l.len
	var want := total * frac
	for i in v.legs.size():
		if want <= v.legs[i].len or i == v.legs.size() - 1:
			v.leg = i
			v.s = minf(want, v.legs[i].len)
			break
		want -= v.legs[i].len
	var leg: Dictionary = v.legs[v.leg]
	v.yaw = _face(leg, v.s)
	v.node.rotation.y = v.yaw
	v.node.position = _at(leg, v.s) - v.node.basis * Vector3(0, 0, _pivot(v))


## A forklift's round between its two spots: up to A, lift, back out turning, over to B, set down,
## back away, over to A again.
func _lift_legs(job: Array) -> Array:
	var spots := [[job[0], job[1]], [job[2], job[3]]]
	var stand := func(i: int) -> Vector3: return spots[i][0] - spots[i][1] * 0.97   # (where its front axle stops: the forks' middle under the pallet)
	var backs := []   # each spot's backing-out leg (its end and the way it then faces)
	for i in 2:
		var f: Vector3 = spots[i][1]
		var right := f.cross(Vector3.UP)
		var other: Vector3 = spots[1 - i][0]
		var side := right * (1.0 if (other - spots[i][0]).dot(right) >= 0.0 else -1.0)
		var s0: Vector3 = stand.call(i)
		backs.append(_leg(-1, _round([s0, s0 - f * 1.5, s0 - f * 3.2 + side * 2.4], 1.6), 1.1, 1.0))
	# Up to a spot from where the last backing out ended, facing as it was then.
	var to_spot := func(prev: Dictionary, i: int, event: String) -> Dictionary:
		var from: Vector3 = prev.pts[prev.pts.size() - 1]
		var tan_end: Vector3 = (prev.pts[prev.pts.size() - 1] - prev.pts[prev.pts.size() - 2]).normalized()
		var facing: Vector3 = -tan_end   # (it was backing up)
		var f: Vector3 = spots[i][1]
		var s0: Vector3 = stand.call(i)
		return _leg(1, _round([from, from + facing * 1.6, s0 - f * 2.6, s0], 1.6), 2.4, 2.6, event)
	# A to B with the pallet, then (the next job) B back to A with it.
	var legs := [to_spot.call(backs[1], 0, "lift"), backs[0], to_spot.call(backs[0], 1, "drop"), backs[1],
		to_spot.call(backs[1], 1, "lift"), backs[1], to_spot.call(backs[1], 0, "drop"), backs[0]]
	return legs


# --- driving ------------------------------------------------------------------------------------------

func _vehicle_tick(v: Dictionary, delta: float) -> void:
	var n: Node3D = v.node
	var truck: bool = v.kind == "truck"
	var t := Time.get_ticks_msec() / 1000.0
	var leg: Dictionary = v.legs[v.leg]
	var dir: float = leg.dir
	var speed: float = v.v   # (along the path: always forward along it; dir says which way it faces)
	# Waiting at the end of a leg: a delivery (hazards), a pallet going up or down.
	var rolling_back := false
	if v.backoff > 0.0:   # backing up the way it came, to let the others through
		var step := minf(1.1 * delta, float(v.backoff))
		if v.s - step > 0.0 and _clear_behind(v, leg, v.s - step - 0.8):
			v.s -= step
			v.backoff -= step
			rolling_back = true
		else:
			v.backoff = 0.0
		if v.backoff <= 0.0:
			v.hold = 4.0
		speed = 0.0
		v.acc = 0.0
	elif v.wait > 0.0:
		v.wait -= delta
		speed = 0.0
		if leg.event != "" and v.wait < float(leg.wait) - 0.4:
			_lift_tick(v, leg.event, delta)
		if v.wait <= 0.0:
			v.leg = (v.leg + 1) % v.legs.size()
			v.s = 0.0
			leg = v.legs[v.leg]
			dir = leg.dir
	else:
		var left: float = leg.len - v.s
		# How fast it wants to go: its top speed, slower for the bends ahead, to stop at the end,
		# stopped for whoever's in its way.
		var want: float = leg.speed
		for ahead in [2.0, 6.0, 12.0]:
			var turn := absf(angle_difference(atan2(_tangent(leg, v.s + ahead).x, _tangent(leg, v.s + ahead).z), atan2(_tangent(leg, v.s).x, _tangent(leg, v.s).z)))
			if turn > 0.05:
				want = minf(want, maxf(1.6, sqrt(1.4 * ahead / maxf(turn, 0.05))))
		want = minf(want, sqrt(2.0 * 1.6 * maxf(left - 0.2, 0.0)) + 0.25)
		v.look_t -= delta   # (who's in the way: worked out five times a second, not every frame)
		if v.look_t <= 0.0:
			v.look_t = 0.2
			v.blocker = _in_the_way(v, leg, dir)
		var blocker: int = v.blocker
		if v.hold > 0.0:   # (holding back after backing up: the others go first)
			v.hold -= delta
			want = 0.0
		if blocker == 2 and v.blocked > 3.0 and _stuck_round(v):   # all waiting on each other: this one backs off
			v.backoff = 5.0 if truck else 2.0
			v.blocked = 0.0
		if blocker != 0:
			want = 0.0
			v.blocked += delta
			if blocker == 1 and v.blocked > 2.5 and t - float(v.honked) > 7.0 and truck:   # you, in the way: a toot
				v.honked = t
				Sfx.play(self, "horn", n.position + Vector3(0, 2, 0), -6.0, 0.9)   # (its air horn)
		else:
			v.blocked = 0.0
		var rate := 1.1 if want > speed else 2.0
		var nv := move_toward(speed, want, delta * rate)
		v.acc = lerpf(float(v.acc), (nv - speed) / maxf(delta, 0.001), minf(1.0, delta * 4.0))
		speed = nv
		v.s += speed * delta
		if v.s >= leg.len - 0.05 and speed < 0.4:
			v.s = leg.len
			speed = 0.0
			v.wait = maxf(float(leg.wait), 0.05)
			if truck and leg.wait > 3.0:
				Sfx.play(self, "air_release", n.position + Vector3(0, 0.8, 0), -6.0, randf_range(0.95, 1.1))   # the brakes set: psshh
	v.v = speed
	# Where it is and which way it faces; how fast it's turning (for the steering and the lean).
	var pos := _at(leg, v.s)   # (where its pivot axle is: the back one on a lorry, the front on a forklift)
	var yaw := _face(leg, v.s)
	var yaw_rate := angle_difference(float(v.yaw), yaw) / maxf(delta, 0.001)
	v.yaw = yaw
	n.rotation.y = yaw
	n.position = pos - n.basis * Vector3(0, 0, _pivot(v))
	var signed := speed * dir if not rolling_back else -1.1 * dir   # forward +, backing -
	var wheelbase := 4.6 if truck else 1.3
	var steer := atan(wheelbase * yaw_rate / signed) if absf(signed) > 0.15 else float(v.steer)
	v.steer = lerpf(float(v.steer), clampf(steer, -0.6, 0.6), minf(1.0, delta * 5.0))
	for w in v.parts.wheels:
		(w[1] as Node3D).rotation.x -= signed * delta / (0.5 if truck else 0.25)
		if w[2]:
			(w[0] as Node3D).rotation.y = float(v.steer) * (1.0 if truck else -1.0)   # (a forklift steers with its back wheels)
	# The body: nose dips braking, squats pulling away; leans out on a bend.
	var body: Node3D = v.body
	body.rotation.x = lerpf(body.rotation.x, clampf(float(v.acc) * dir * 0.012, -0.03, 0.03), minf(1.0, delta * 5.0))
	body.rotation.z = lerpf(body.rotation.z, clampf(-speed * yaw_rate * 0.012, -0.035, 0.035), minf(1.0, delta * 4.0))
	if n.position.distance_to(_eye) > 140.0:
		return   # (the rest is for show: nobody's close enough to see)
	_vehicle_show(v, delta, t, speed, dir, yaw_rate)


## Someone (1: you; 2: another vehicle or one of the yard's people) close in front of where it's
## going, or 0. (A vehicle mid-way through a turn or backing doesn't wait for other vehicles: it'd
## never get round.)
## The axle it turns about (it drives on the path there; the rest swings round it as a vehicle's does).
func _pivot(v: Dictionary) -> float:
	return 2.35 if v.kind == "truck" else -0.48


func _in_the_way(v: Dictionary, leg: Dictionary, dir: float) -> int:
	# Where it'll be over its next stretch of path (its whole outline, turning as it turns), against
	# where everyone else is now, and against where the other vehicles will be by then. Nothing ever
	# drives into another's outline as it stands; for what's coming, the one going straighter has the
	# right of way (a lorry pulling out of a side road waits for one on the ring road, before its nose
	# is in the lane).
	var me_v: float = maxf(float(v.v), 1.6 if v.kind == "truck" else 0.9)
	var stop_dist := float(v.v) * float(v.v) / 4.0
	var ahead := clampf(maxf(stop_dist + (3.5 if v.kind == "truck" else 1.5), me_v * 4.0), 2.0, 26.0)
	var p = main.player if main else null
	var still := []   # [outline, what: 1 you, 2 the rest]
	if p != null and not p.dead:
		still.append([_box2(p.global_position, 0.0, 0.45, 0.45, 0.0), 1])
	for w in _people:
		if not w.sit:
			still.append([_box2(w.node.position, 0.0, 0.4, 0.4, 0.0), 2])
	var my_turn := _turniness(v)
	var movers := []
	for o in _vehicles:
		if o == v:
			continue
		still.append([_outline(o, (o.node as Node3D).position, float(o.yaw)), 3, o])
		var theirs := _turniness(o)
		var they_first: bool = theirs < my_turn - 0.05 or (absf(theirs - my_turn) <= 0.05 and o.id < v.id)
		var to_o: Vector3 = (o.node as Node3D).position - (v.node as Node3D).position
		var my_go := _tangent(leg, v.s)
		if to_o.dot(my_go) < 0.0 and _tangent(o.legs[o.leg], o.s).dot(my_go) > 0.5:
			continue   # (behind it, going the same way: its business to keep back)
		if o.wait <= 0.0 and (they_first or float(o.v) > 0.3):
			movers.append([o, they_first])
	v.blocked_by = -1
	# A dead-end side road with another lorry down it: wait at its mouth till it's out.
	var in_junction := false
	for b in JUNCTIONS:
		in_junction = in_junction or _touches_box(v, b)
	if v.kind == "truck" and _zone(v.node.position) < 0 and not in_junction:   # (looking far enough to wait short of the junction)
		var into := -1
		var dd := 2.0
		while dd < 32.0 and into < 0:
			into = _zone(_at(leg, minf(v.s + dd, leg.len)))
			dd += 2.0
		if into >= 0:
			for o in _vehicles:
				if o != v and o.kind == "truck" and _zone((o.node as Node3D).position) == into:
					v.blocked_by = o.id
					return 2
	# The junctions.
	for b in JUNCTIONS:
		if _touches_box(v, b):
			continue   # (in it: get out of it)
		var mine := _dist_to_box(v, b, maxf(stop_dist + 6.0, 10.0))
		if mine == INF:
			continue
		var from_side: bool = _zone(v.node.position) >= 0
		for o in _vehicles:
			if o == v or o.kind != "truck":
				continue
			if _touches_box(o, b):
				v.blocked_by = o.id
				return 2
			if from_side and float(o.v) > 0.3 and _zone((o.node as Node3D).position) < 0:
				var theirs := _dist_to_box(o, b, float(o.v) * 6.0 + 6.0)
				if theirs != INF:   # (on the ring road, getting there in the next few seconds: let it by)
					v.blocked_by = o.id
					return 2
	var d := 0.6
	while d <= ahead:
		var s2: float = minf(v.s + d, leg.len)
		var yaw := _face(leg, s2)
		var node_at := _at(leg, s2) - Basis(Vector3.UP, yaw) * Vector3(0, 0, _pivot(v))
		var mine := _outline(v, node_at, yaw)
		if d <= stop_dist + (6.0 if v.kind == "truck" else 1.5):   # (what it could hit before it could stop, and a gap)
			for e in still:
				if _overlap(mine, e[0]):
					if e[1] == 3:
						v.blocked_by = e[2].id
						return 2
					return e[1]
		var slow := maxf(minf(float(v.v), 3.0), 1.6 if v.kind == "truck" else 0.9)
		var t0 := maxf(0.0, d / me_v - 1.5)   # (when it might get here at the soonest...)
		var t1 := d / slow + 3.0              # (...and when it'll surely have cleared it, slowing for the bend)
		for e in movers:
			var o: Dictionary = e[0]
			var lo := t0 if e[1] else 0.0   # (one without the right of way: only where it's heading in the next moment)
			var hi := t1 if e[1] else minf(1.5, t1)
			var ol: Dictionary = o.legs[o.leg]
			var ov: float = 0.0 if (o.blocked_by == v.id and float(o.v) < 0.3) or o.hold > 0.0 or o.backoff > 0.0 else maxf(float(o.v), 0.5)   # (one stopped, waiting for us, won't come on)
			if ov == 0.0 and not e[1]:
				continue
			var tt := lo
			while tt <= hi:
				var os: float = minf(float(o.s) + ov * tt, ol.len)
				var oy := _face(ol, os)
				var oat := _at(ol, os) - Basis(Vector3.UP, oy) * Vector3(0, 0, _pivot(o))
				if _overlap(mine, _outline(o, oat, oy)):
					v.blocked_by = o.id
					return 2
				tt += 0.6
		if s2 >= leg.len:
			break
		d += 1.0
	return 0


## How much it's turning over the next stretch (radians): the straighter, the more right of way.
## Room to back up to s (nobody, no vehicle, where its outline would be)?
func _clear_behind(v: Dictionary, leg: Dictionary, s: float) -> bool:
	var yaw := _face(leg, s)
	var mine := _outline(v, _at(leg, s) - Basis(Vector3.UP, yaw) * Vector3(0, 0, _pivot(v)), yaw)
	for o in _vehicles:
		if o != v and _overlap(mine, _outline(o, (o.node as Node3D).position, float(o.yaw))):
			return false
	var p = main.player if main else null
	if p != null and _overlap(mine, _box2(p.global_position, 0.0, 0.45, 0.45, 0.0)):
		return false
	for w in _people:
		if not w.sit and _overlap(mine, _box2(w.node.position, 0.0, 0.4, 0.4, 0.0)):
			return false
	return true


## Where the side roads meet the ring road: one vehicle in each at a time, and one coming out of a
## side road waits for anything on the ring road about to get there. [x0, z0, x1, z1]
const JUNCTIONS := [[45.0, 34.0, 59.0, 47.5], [-59.0, 34.0, -45.0, 47.5]]


func _in_box(at: Vector3, b: Array) -> bool:
	return at.x > b[0] and at.x < b[2] and at.z > b[1] and at.z < b[3]


## How far along its path it'll be before it gets into box b (INF: not within `upto`).
func _dist_to_box(v: Dictionary, b: Array, upto: float) -> float:
	var leg: Dictionary = v.legs[v.leg]
	var d := 0.0
	while d <= upto:
		if _in_box(_at(leg, minf(float(v.s) + d, leg.len)), b):
			return d
		if v.s + d >= leg.len:
			break
		d += 1.5
	return INF


## Its whole outline anywhere in box b now?
func _touches_box(v: Dictionary, b: Array) -> bool:
	var n: Node3D = v.node
	var hl := 4.0 if v.kind == "truck" else 1.4
	for k in [-1.0, 0.0, 1.0]:
		if _in_box(n.position + n.basis * Vector3(0, 0, hl * k), b):
			return true
	return false


## The side roads are dead ends, one lorry at a time: [x0, z0, x1, z1].
const DEAD_ENDS := [[46.0, 46.5, 58.0, 116.0], [-58.0, 46.5, -46.0, 116.0]]


func _zone(at: Vector3) -> int:
	for i in DEAD_ENDS.size():
		var z: Array = DEAD_ENDS[i]
		if at.x > z[0] and at.x < z[2] and at.z > z[1] and at.z < z[3]:
			return i
	return -1


## Is it one of a ring of vehicles each waiting on the next (and the one that should give way:
## the one turning most, else the later one)?
func _stuck_round(v: Dictionary) -> bool:
	var ring := [v]
	var o: Dictionary = v
	for k in 6:
		if o.blocked_by < 0 or o.blocked_by >= _vehicles.size():
			return false
		o = _vehicles[o.blocked_by]
		if o == v:
			break
		if o in ring:
			return false
		ring.append(o)
	if o != v:
		return false
	for r in ring:
		if r != v and (_turniness(r) > _turniness(v) + 0.05 or (absf(_turniness(r) - _turniness(v)) <= 0.05 and r.id > v.id)):
			return false
	return true


func _turniness(v: Dictionary) -> float:
	var leg: Dictionary = v.legs[v.leg]
	var a := _tangent(leg, v.s)
	var b := _tangent(leg, v.s + 10.0)
	return absf(angle_difference(atan2(a.x, a.z), atan2(b.x, b.z))) + (1.0 if leg.dir < 0 else 0.0)


## A vehicle's outline on the ground at a place and facing (a little margin round it).
func _outline(v: Dictionary, at: Vector3, yaw: float) -> Array:
	if v.kind == "truck":
		return _box2(at, yaw, 1.45, 4.05, 0.1)
	return _box2(at, yaw, 0.75, 1.9, -0.4)   # (a forklift, its forks out in front)


## A rectangle on the ground: its middle, its across and along axes, half its width and length.
func _box2(at: Vector3, yaw: float, hw: float, hl: float, mid_z: float) -> Array:
	var b := Basis(Vector3.UP, yaw)
	var c3 := at + b * Vector3(0, 0, mid_z)
	var x3 := b * Vector3(1, 0, 0)
	var z3 := b * Vector3(0, 0, 1)
	return [Vector2(c3.x, c3.z), Vector2(x3.x, x3.z), Vector2(z3.x, z3.z), hw, hl]


func _overlap(a: Array, b: Array) -> bool:   # (separating axes: the four edges' directions)
	var d: Vector2 = b[0] - a[0]
	for ax in [a[1], a[2], b[1], b[2]]:
		var ra: float = a[3] * absf(ax.dot(a[1])) + a[4] * absf(ax.dot(a[2]))
		var rb: float = b[3] * absf(ax.dot(b[1])) + b[4] * absf(ax.dot(b[2]))
		if absf(d.dot(ax)) > ra + rb:
			return false
	return true


## A pallet up (A) or down (B): the carriage rises or lowers with it, hydraulics whining.
func _lift_tick(v: Dictionary, event: String, delta: float) -> void:
	var c: Node3D = v.parts.get("carriage")
	if c == null:
		return
	var up := event == "lift"
	if up and not v.carry:   # forks under it: take it
		v.carry = true
		var pal: Node3D = v.pallet
		var nb: Basis = v.node.global_basis
		pal.global_transform = Transform3D(nb, v.node.global_position + nb * Vector3(0, 0.05, -1.45))   # (square on the forks)
		pal.reparent(c, true)
		Sfx.play(self, "servo", v.node.position + Vector3(0, 1, 0), -10.0, 0.7)
	if not up and v.carry and c.position.y < 0.02:   # set down: let go of it
		v.carry = false
		var pal: Node3D = v.pallet
		pal.reparent(self, true)
		pal.position.y = 0.05
		Sfx.play(self, "clunk", pal.global_position, -6.0, 0.8)
	var goal := 0.28 if up else 0.0
	if not up and v.carry:
		goal = 0.0
	c.position.y = move_toward(c.position.y, goal, delta * 0.2)


## Lamps, smoke, sound, the driver: what you'd notice watching it.
func _vehicle_show(v: Dictionary, delta: float, t: float, speed: float, dir: float, yaw_rate: float) -> void:
	var truck: bool = v.kind == "truck"
	var L: Dictionary = v.lamps
	var leg: Dictionary = v.legs[v.leg]
	var braking: bool = float(v.acc) < -0.25 or (speed < 0.05)
	var backing: bool = (dir < 0.0 and (speed > 0.02 or v.wait > 0.0)) or v.backoff > 0.0
	var night: bool = main.hours > 18.5 or main.hours < 6.5
	(v.head as SpotLight3D).light_energy = 2.0 if night else 0.6
	# Which way it's about to turn (the indicators), or both going while it's stopped for a delivery.
	var turn := 0.0
	if speed > 0.5 or v.wait <= 0.0:
		var now := _tangent(leg, v.s)
		var later := _tangent(leg, v.s + 14.0)
		turn = angle_difference(atan2(-now.x, -now.z), atan2(-later.x, -later.z)) * dir
	var hazard: bool = v.wait > 1.0 and leg.wait > 3.0
	var blink_on := fmod(t, 0.8) < 0.4
	for sx in [-1.0, 1.0]:
		var side_on: bool = hazard or (turn * sx < -0.35)   # (turning left: yaw goes up; the left side is -x)
		var e := 2.5 if side_on and blink_on else 0.0
		if L.has("ind_r%d" % sx):
			L["ind_r%d" % sx].emission_energy_multiplier = e
			L["ind_f%d" % sx].emission_energy_multiplier = e
		L["brake%d" % sx].emission_energy_multiplier = 3.0 if braking else 0.6
		L["rev%d" % sx].emission_energy_multiplier = 3.0 if backing else 0.0
	(v.back as OmniLight3D).light_energy = 1.2 if backing else 0.0
	if L.has("beacon"):   # the forklift's beacon going round
		L.beacon.emission_energy_multiplier = 4.0 if fmod(t * 1.4, 1.0) < 0.3 else 0.3
	# The beeper backing up.
	if backing and (speed > 0.05 or v.backoff > 0.0):
		v.beep -= delta
		if v.beep <= 0.0:
			v.beep = 1.2
			Sfx.play(self, "reverse_beep", v.node.position + v.node.basis * Vector3(0, 1.5, 3.6 if truck else 1.3), -10.0 if truck else -14.0)
	else:
		v.beep = 0.0
	# The engine: through the gears (each pulls the revs up; a shift drops them, with a hiss of air),
	# louder working than idling; smoke to match.
	var rpm := 0.0
	var load := clampf(float(v.acc) / 1.1, 0.0, 1.0)
	if truck:
		var g: int = v.gear
		if g < GEARS.size() - 1 and speed > GEARS[g] * 0.92:
			v.gear = g + 1
			v.shift = 0.35
			Sfx.play(self, "air_release", v.node.position + Vector3(0, 1.2, -1.0), -26.0, 1.8)
		elif g > 0 and speed < GEARS[g - 1] * 0.6:
			v.gear = g - 1
		var lo: float = 0.0 if v.gear == 0 else GEARS[v.gear - 1] * 0.5
		rpm = clampf((speed - lo) / (GEARS[v.gear] - lo), 0.0, 1.0)
	else:
		rpm = clampf(speed / 2.4, 0.0, 1.0)
	v.shift = maxf(0.0, float(v.shift) - delta)
	# Idle and working engines crossfaded by how hard it's going; each pitched only a little (a real
	# engine's ring doesn't move with the revs: only its beat does).
	var work := clampf(rpm * 0.8 + load * 0.6, 0.0, 1.0)
	var dip := 0.12 if v.shift > 0.0 else 0.0
	var e_idle: AudioStreamPlayer3D = v.engines[0]
	var e_work: AudioStreamPlayer3D = v.engines[1]
	e_idle.pitch_scale = lerpf(e_idle.pitch_scale, 1.0 + rpm * 0.3 - dip, minf(1.0, delta * 6.0))
	e_work.pitch_scale = lerpf(e_work.pitch_scale, 0.85 + rpm * 0.35 - dip, minf(1.0, delta * 6.0))
	e_idle.volume_db = lerpf(e_idle.volume_db, linear_to_db(maxf(1.0 - work, 0.001)) - 12.0, minf(1.0, delta * 4.0))
	e_work.volume_db = lerpf(e_work.volume_db, linear_to_db(maxf(work, 0.001)) - 10.0 + load * 3.0, minf(1.0, delta * 4.0))
	var smoke: GPUParticles3D = v.smoke[0]
	smoke.amount_ratio = clampf(0.25 + load * 0.75 + rpm * 0.2, 0.0, 1.0)
	(v.smoke[1] as StandardMaterial3D).albedo_color = Color(0.36, 0.35, 0.34).lerp(Color(0.1, 0.095, 0.09), clampf(load * 1.3 - 0.2, 0.0, 1.0))
	# The driver: looking where it's going (into the turn), over the shoulder backing up, at you
	# when you're close, and now and then a wave.
	var d: Dictionary = v.driver
	var look := clampf(float(v.steer) * 1.6, -0.9, 0.9)
	var twist := 0.0
	if backing:
		look = 1.25
		twist = 0.45
	var p = main.player if main else null
	var waving := false
	if p != null and not p.dead and not backing:
		var to: Vector3 = v.node.to_local(p.global_position)
		if to.length() < 10.0 and to.z < 2.0:
			look = clampf(atan2(-to.x, -to.z), -1.3, 1.3)
			if t - float(v.waved) > 25.0 and to.length() < 8.0 and randf() < delta * 0.5:
				v.waved = t
			waving = t - float(v.waved) < 1.6
	v.look = lerpf(float(v.look), look, minf(1.0, delta * 3.0))
	d.head.rotation.y = float(v.look) * 0.75
	d.torso.rotation.y = lerpf(d.torso.rotation.y, twist, minf(1.0, delta * 3.0))
	# Hands on the wheel (turning it with the steering), or one up in a wave.
	var wheel := float(v.steer) * 1.2
	d.upper_arm_l.rotation = Vector3(1.0, 0, -0.15 + wheel * 0.15)
	d.forearm_l.rotation = Vector3(0.65 - wheel * 0.15, 0, 0)
	if waving:
		d.upper_arm_r.rotation = Vector3(2.5, 0, 0.3)
		d.forearm_r.rotation = Vector3(0.4 + sin(t * 12.0) * 0.35, 0, 0)
	else:
		d.upper_arm_r.rotation = Vector3(1.0, 0, 0.15 + wheel * 0.15)
		d.forearm_r.rotation = Vector3(0.65 + wheel * 0.15, 0, 0)


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
		curve.max_value = 2.4   # (a Curve clamps to 0..1 otherwise)
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
		mat.billboard_keep_scale = true   # (without it every puff draws at its mesh's size, whatever its scale)
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
	_pa -= delta   # now and then something heavy far off across the yard
	if _pa <= 0.0:
		_pa = _rng.randf_range(45.0, 90.0)
		var far := Vector3(_rng.randf_range(-140, 140), 2.0, _rng.randf_range(-60, 110))
		Sfx.play(self, ["clang_big", "far_bang", "horn"][_rng.randi() % 3], far, -6.0, _rng.randf_range(0.7, 0.9))
