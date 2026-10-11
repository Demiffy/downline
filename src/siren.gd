# The Siren: a tall, starved grey thing with no eyes and a mouth split down its long face. It
# listens to the crew and keeps what they say. Out of sight, it calls in their voices ("over here",
# a laugh, a name) from somewhere you can't see, and comes closer while nobody's looking. It hates
# being seen: catch it in view and it backs off into the dark. Let it reach you and it lunges.
# Alone, with no voices to steal, it fakes what it has heard of you: footsteps, a cough, a door.
# Hit it and it runs. The host decides everything; crewmates hear its stolen voice as sent.
extends "res://src/monster.gd"

enum { LURK, STALK, LUNGE, FLEE }
const CALL_RANGE := 28.0
const REACH := 2.0
const DAMAGE := 45.0
const WALK := 1.6
const CREEP := 2.6
const RUN := 9.0          # (a sprinting employee does 6.5)
const SPOOK := 0.3        # seconds in plain view before it bolts

var state := LURK
var prey
var _t := 0.0
var _call := 8.0
var _goal := Vector3.ZERO
var _wander := 0.0
var _seen_t := 0.0
var _repick := 0.0
var _twitch := 0.0        # a sudden jerk of the head now and then
var _twitch_to := Vector3.ZERO
var _gait := 0.0
var _parts := {}
var _voice: AudioStreamPlayer3D
var jaw := 0.0            # 0 shut .. 1 wide (synced to copies)


func _ready() -> void:
	_setup_body(0.35, 2.1, true)
	health = 70.0
	add_to_group("sirens")
	_build()
	_parts.hips.scale = Vector3.ONE * 1.12   # (taller than any of you)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = "World"
	_voice.unit_size = 7.0
	_voice.max_distance = 45.0
	add_child(_voice)
	_voice.position.y = 1.9
	_goal = global_position


## Long-limbed and hunched: thin legs, a narrow ribbed chest, arms down to its knees, a long
## eyeless head with a vertical mouth full of needle teeth.
func _build() -> void:
	var skin := Color(0.5, 0.51, 0.53)   # bloodless grey (and hard to pick out in the dark)
	var dark := Color(0.3, 0.31, 0.34)
	var hips := Node3D.new()
	add_child(hips)
	hips.position.y = 1.05
	_parts.hips = hips
	for s in [-1.0, 1.0]:
		var thigh := Node3D.new()
		hips.add_child(thigh)
		thigh.position = Vector3(s * 0.11, 0, 0)
		A.seg(thigh, Vector3.ZERO, Vector3(0, -0.52, 0.03), 0.055, 0.04, "plastic", skin)
		var shin := Node3D.new()
		thigh.add_child(shin)
		shin.position = Vector3(0, -0.52, 0.03)
		A.sphere(shin, 0.045, Vector3.ZERO, "plastic", dark)
		A.seg(shin, Vector3.ZERO, Vector3(0, -0.5, -0.02), 0.04, 0.028, "plastic", skin)
		A.seg(shin, Vector3(0, -0.5, -0.02), Vector3(0, -0.53, -0.16), 0.03, 0.018, "plastic", dark)   # long foot
		_parts["thigh%d" % int(s)] = thigh
		_parts["shin%d" % int(s)] = shin
	var chest := Node3D.new()
	hips.add_child(chest)
	_parts.chest = chest
	chest.rotation.x = -0.7   # hunched right over
	A.seg(chest, Vector3(0, 0.0, 0), Vector3(0, 0.62, 0.02), 0.11, 0.15, "plastic", skin)
	for k in 6:   # ribs showing through
		var rib := A.ring(chest, 0.14 - k * 0.004, 0.128 - k * 0.004, Vector3(0, 0.2 + k * 0.065, 0.01), "plastic", dark)
		rib.scale = Vector3(1.0, 1.0, 0.7)
	for s in [-1.0, 1.0]:
		var arm := Node3D.new()
		chest.add_child(arm)
		arm.position = Vector3(s * 0.17, 0.58, 0.0)
		A.sphere(arm, 0.05, Vector3.ZERO, "plastic", dark)
		A.seg(arm, Vector3.ZERO, Vector3(s * 0.03, -0.5, 0.0), 0.04, 0.032, "plastic", skin)
		var fore := Node3D.new()
		arm.add_child(fore)
		fore.position = Vector3(s * 0.03, -0.5, 0.0)
		A.seg(fore, Vector3.ZERO, Vector3(0, -0.52, -0.05), 0.032, 0.022, "plastic", skin)
		for f in 4:   # long fingers
			var fx := (f - 1.5) * 0.018
			A.seg(fore, Vector3(fx, -0.52, -0.05), Vector3(fx * 1.6, -0.72, -0.1), 0.01, 0.005, "plastic", dark)
		_parts["arm%d" % int(s)] = arm
		_parts["fore%d" % int(s)] = fore
	var neck := Node3D.new()
	chest.add_child(neck)
	neck.position = Vector3(0, 0.64, 0.02)
	_parts.neck = neck
	A.seg(neck, Vector3.ZERO, Vector3(0, 0.16, -0.06), 0.045, 0.04, "plastic", skin)
	var head := Node3D.new()
	neck.add_child(head)
	head.position = Vector3(0, 0.17, -0.07)
	_parts.head = head
	var skull := A.sphere(head, 0.1, Vector3(0, 0.1, 0), "plastic", skin)
	skull.scale = Vector3(0.72, 1.55, 0.85)   # long, narrow, eyeless
	# The mouth: a slit down the whole face that opens into a dark gape when it speaks, teeth along
	# both edges.
	var gape := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.1
	gm.height = 0.2
	gape.mesh = gm
	var dark_m := StandardMaterial3D.new()
	dark_m.albedo_color = Color(0.05, 0.01, 0.015)
	dark_m.roughness = 0.3
	gape.material_override = dark_m
	head.add_child(gape)
	gape.position = Vector3(0, 0.07, -0.062)
	gape.scale = Vector3(0.08, 1.25, 0.25)
	_parts.gape = gape
	for s in [-1.0, 1.0]:   # each edge of the slit, with its row of needle teeth
		var half := Node3D.new()
		head.add_child(half)
		half.position = Vector3(s * 0.006, 0.07, -0.085)
		A.seg(half, Vector3(0, -0.12, 0), Vector3(0, 0.12, 0), 0.006, 0.006, "flesh", Color(0.42, 0.2, 0.22))   # the lip
		for k in 8:
			A.seg(half, Vector3(0, -0.1 + k * 0.028, -0.002), Vector3(-s * 0.014, -0.1 + k * 0.028 - 0.004, -0.004), 0.0035, 0.0008, "cream", Color(0.92, 0.9, 0.8))
		_parts["face%d" % int(s)] = half


func _physics_process(delta: float) -> void:
	_t += delta
	_call -= delta
	var seen := observed(2.1, 0.5)
	_seen_t = _seen_t + delta if seen else maxf(0.0, _seen_t - delta * 2.0)
	match state:
		LURK:
			if _seen_t > SPOOK:   # caught in a light, or just looked at: gone
				_flee(_watcher())
			else:
				_wander -= delta
				if _wander <= 0.0 or global_position.distance_to(_goal) < 1.0:
					_wander = randf_range(6.0, 12.0)
					_goal = level.wander_point(global_position) if level else global_position
				walk_to(_goal, WALK, delta, 4.0)
				var p = _listener()
				if p != null and _call <= 0.0:
					prey = p
					_speak()
					state = STALK
					_t = 0.0
		STALK:   # creeping up on whoever it called to, only while nobody looks
			if prey == null or not is_instance_valid(prey) or prey.dead:
				state = LURK
			elif _seen_t > SPOOK:
				if global_position.distance_to(prey.global_position) < REACH + 1.0:
					_lunge()   # cornered, close: it goes for you instead
				else:
					_flee(_watcher())
			else:
				walk_to(prey.global_position, CREEP, delta, 6.0)
				if _call <= 0.0 and global_position.distance_to(prey.global_position) > 6.0:
					_speak()
				if global_position.distance_to(prey.global_position) < REACH + 1.5 and sees(prey):
					_lunge()
		LUNGE:
			if prey != null and is_instance_valid(prey):
				var v := walk_to(prey.global_position, RUN, delta, 14.0)
				var dd: float = global_position.distance_to(prey.global_position)
				if (dd < REACH or (v == Vector3.ZERO and dd < REACH + 1.0)) and _t < 1.2:   # (or as close as the way gets)
					prey.hurt(DAMAGE, "Something with your friend's voice got you.")
					Sfx.play(self, "wraith_grab", global_position + Vector3.UP * 1.5, 2.0, 1.3)
					_flee(prey.global_position)
					return
				if _t > 1.2 or v == Vector3.ZERO:
					_flee(prey.global_position)
			else:
				_flee(global_position)
		FLEE:   # bolting, low and fast: faster than anyone can sprint
			var v := walk_to(_goal, RUN, delta, 12.0)
			var w: Vector3 = _watcher()
			if seen and _t - _repick > 0.8 and w.distance_to(global_position) < 12.0:
				_repick = _t
				_flee(w, true)   # still being chased: away again
			if not seen and _t > 1.0 and level != null and level.facility != null and main.net.authority():
				var hide: Vector3 = level._hidden_spot(18.0)   # out of sight now: it is somewhere else entirely
				if hide != Vector3.INF:
					global_position = hide
					velocity = Vector3.ZERO
				state = LURK
				_call = randf_range(18.0, 32.0)
			elif v == Vector3.ZERO or _t > 8.0:
				state = LURK
				_call = randf_range(18.0, 32.0)
	jaw = move_toward(jaw, 0.0, delta * 0.8)
	_animate(delta)


## Where the nearest of the crew is (whoever is looking at it, near enough).
func _watcher() -> Vector3:
	var best = null
	var bd := INF
	for p in alive_players():
		var d: float = p.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = p
	return best.global_position if best != null else global_position


func _lunge() -> void:
	state = LUNGE
	_t = 0.0
	show_act("lunge")


## The nearest player in calling range who can't see it.
func _listener():
	var best = null
	var bd := CALL_RANGE
	for p in alive_players():
		var d: float = p.global_position.distance_to(global_position)
		if d < bd and not sees(p):
			bd = d
			best = p
	return best


## Call out: one of the crew's own phrases, or (nothing to steal) a sound one of them would make.
func _speak() -> void:
	_call = randf_range(14.0, 26.0)
	var who := -1   # (whoever it's calling to: never their own voice)
	if prey != null and is_instance_valid(prey):
		who = main.net.me() if prey == main.player else int(prey.get("peer"))
	var clip: PackedFloat32Array = main.net.voice.random_clip(who) if main.net.voice != null else PackedFloat32Array()
	if clip.is_empty():
		var fake: String = ["far_steps", "cough", "door_open", "clank"][randi() % 4]
		Sfx.play(self, fake, global_position + Vector3.UP * 1.2, 0.0, randf_range(0.95, 1.05))
		return
	var b := _pack(clip)
	_say(b)
	main.net.ent_event(self, "say", [b])


## The phrase for the wire: 12 kHz, 16-bit (half the voice rate: a little duller, a lot smaller).
static func _pack(clip: PackedFloat32Array) -> PackedByteArray:
	var n := clip.size() / 2
	var b := PackedByteArray()
	b.resize(n * 2)
	for i in n:
		b.encode_s16(i * 2, int(clampf((clip[i * 2] + clip[i * 2 + 1]) * 0.5, -1.0, 1.0) * 32767.0))
	return b


## Say it, from its mouth, a shade too slow.
func _say(b: PackedByteArray) -> void:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 12000
	w.data = b
	_voice.stream = w
	_voice.pitch_scale = randf_range(0.94, 0.98)
	_voice.volume_db = 2.0
	_voice.play()
	jaw = 1.0


func _flee(from: Vector3, again := false) -> void:
	if not again:
		state = FLEE
		_t = 0.0
		_repick = 0.0
		show_act("flee")
	prey = null
	# Somewhere away from them: of a few spots on this floor, the furthest from them that
	# does not mean running past them.
	_goal = global_position + (global_position - from).normalized() * 6.0
	var best := -INF
	if level and level.facility:
		for tries in 10:
			var g: Vector3 = level.facility.random_point(level.rng, true)
			if absf(g.y - global_position.y) > 2.5:
				continue
			var score: float = g.distance_to(from) - g.distance_to(global_position) * 0.4
			if (g - global_position).dot(global_position - from) < 0.0:
				score -= 20.0   # (that way is through them)
			if score > best:
				best = score
				_goal = g


## A noise: it drifts over to listen (and is ready to call to whoever made it).
func hear(pos: Vector3) -> void:
	if state == LURK:
		_goal = pos
		_wander = 10.0
		_call = minf(_call, 1.5)


func is_hunting() -> bool:
	return state == STALK or state == LUNGE


func react_to_hit(by) -> void:
	Sfx.play(self, "wraith_shriek", global_position + Vector3.UP * 1.8, 0.0, 1.4)
	_flee(by.global_position if by != null else global_position)


func act(what: String, _args: Array) -> void:
	match what:
		"lunge":
			Sfx.play(self, "shriek", global_position + Vector3.UP * 1.8, 4.0, 1.05)
			jaw = 1.0
		"flee":   # a scrabble of claws on the floor as it drops and runs
			Sfx.play(self, "chitter", global_position + Vector3.UP * 0.6, -2.0, 1.4)


## Three ways of moving, blended smoothly. Lurking: hunched, swaying, a slow listening tilt and a
## sudden jerk of the head now and then. Stalking: down low, knees bent, long slow reaching
## strides, head craned forward. Fleeing or lunging: it drops onto all fours and lopes, its long
## arms reaching and pulling like front legs. The face splits open as it speaks.
func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var k := 1.0 - exp(-delta * 10.0)
	var lope := state == FLEE or state == LUNGE
	var creep := state == STALK
	_gait += speed * delta * (TAU / (2.2 if lope else 1.5))   # (one stride per so many metres: no sliding)
	var g := _gait
	var amt := clampf(speed / (RUN if lope else 2.0), 0.0, 1.0)
	_twitch -= delta
	if _twitch <= 0.0:
		_twitch = randf_range(1.5, 4.5)
		_twitch_to = Vector3(randf_range(-0.25, 0.25), randf_range(-0.5, 0.5), randf_range(-0.6, 0.6))
	var jerk := _twitch_to if _twitch > 1.2 else Vector3.ZERO
	var hips_y := 1.05
	var chest := -0.55 + sin(_t * 1.3) * 0.03   # (breathing)
	var head := Vector3(-0.4 + sin(_t * 0.6) * 0.05, sin(_t * 0.37) * 0.2, sin(_t * 0.7) * 0.1) + jerk * 0.6   # (the long skull hangs forward, face down and out)
	var legs := [0.0, 0.0, 0.0, 0.0]   # thigh L, shin L, thigh R, shin R
	var arms := [0.0, 0.0, 0.0, 0.0]   # arm L, fore L, arm R, fore R
	for s in 2:
		var ph := g + (0.0 if s == 0 else PI)
		legs[s * 2] = sin(ph) * 0.5 * amt
		legs[s * 2 + 1] = -0.15 - maxf(0.0, -sin(ph)) * 0.8 * amt
		arms[s * 2] = 0.55 - sin(ph) * 0.35 * amt   # (hanging straight down from the hunch)
		arms[s * 2 + 1] = -0.2
	if creep:
		hips_y = 0.82
		chest = -0.95
		head = Vector3(0.75, sin(_t * 0.5) * 0.15, 0.0) + jerk * 0.5
		for s in 2:
			var ph := g + (0.0 if s == 0 else PI)
			legs[s * 2] = 0.55 + sin(ph) * 0.4 * amt
			legs[s * 2 + 1] = -1.0 - maxf(0.0, -sin(ph)) * 0.5 * amt
			arms[s * 2] = 1.15 + sin(ph + PI) * 0.35 * amt
			arms[s * 2 + 1] = -0.35
	elif lope:
		hips_y = 0.86 + absf(sin(g)) * 0.08 * amt
		chest = -1.3 + sin(g * 2.0) * 0.06 * amt
		head = Vector3(1.15, 0.0, 0.0)
		for s in 2:
			var ph := g + (0.0 if s == 0 else 0.5)   # (a gallop: the pairs nearly together)
			legs[s * 2] = 0.35 + sin(ph) * 0.85 * amt
			legs[s * 2 + 1] = -0.7 - maxf(0.0, sin(ph)) * 0.6 * amt
			arms[s * 2] = 1.75 + sin(ph + PI) * 0.8 * amt   # front legs: reach, plant, pull
			arms[s * 2 + 1] = -0.25 - maxf(0.0, sin(ph + PI)) * 0.4 * amt
		if state == LUNGE and _t < 0.5:
			arms[0] = 2.4
			arms[2] = 2.4
	_parts.hips.position.y = lerpf(_parts.hips.position.y, hips_y, k)
	_parts.chest.rotation.x = lerpf(_parts.chest.rotation.x, chest, k)
	var i := 0
	for s in [-1, 1]:
		_parts["thigh%d" % s].rotation.x = lerpf(_parts["thigh%d" % s].rotation.x, legs[i * 2], k)
		_parts["shin%d" % s].rotation.x = lerpf(_parts["shin%d" % s].rotation.x, legs[i * 2 + 1], k)
		_parts["arm%d" % s].rotation.x = lerpf(_parts["arm%d" % s].rotation.x, arms[i * 2], k)
		_parts["fore%d" % s].rotation.x = lerpf(_parts["fore%d" % s].rotation.x, arms[i * 2 + 1], k)
		_parts["face%d" % s].position.x = s * (0.006 + jaw * 0.032)
		i += 1
	_ground_feet()
	_parts.gape.scale = Vector3(0.08 + jaw * 0.3, 1.2, 0.25)
	var hk := 1.0 - exp(-delta * (25.0 if jerk != Vector3.ZERO else 6.0))
	_parts.head.rotation = _parts.head.rotation.lerp(Vector3(head.x - jaw * 0.35, head.y, head.z), hk)


func net_event(ev: String, args: Array) -> void:
	if ev == "say":
		_say(args[0])
	else:
		super.net_event(ev, args)


## Copies: walk with the host's, open the face when it speaks (jaw is synced).
func net_visual(delta: float) -> void:
	_t += delta
	super.net_visual(delta)   # (moves it, and runs _animate)


func death_anim() -> void:
	_voice.stop()
	var tw := create_tween().set_parallel()
	tw.tween_property(_parts.chest, "rotation:x", -1.3, 0.6)
	tw.tween_property(self, "rotation:x", -PI / 2.0, 0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", position.y + 0.25, 0.9)


## Its legs are longer than it stands tall: a straight leg would go through the floor. Lift the
## hips by however far the lower foot would sink (heel or toe), and no more.
func _ground_feet() -> void:
	var lowest := INF
	for s in [-1, 1]:
		var shin: Node3D = _parts["shin%d" % s]
		for q in [Vector3(0, -0.53, -0.16), Vector3(0, -0.5, -0.02)]:
			lowest = minf(lowest, (shin.global_transform * q).y - 0.02)
	var sink := global_position.y - lowest
	if sink > 0.0:
		_parts.hips.position.y += sink
