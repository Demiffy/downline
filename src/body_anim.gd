# How a crew body moves (suit.gd's jointed parts), for crewmates (puppet.gd) and for your own suit
# (player.gd: what photos, camera feeds and the emote camera see). One per body; pose() each frame.
#   Walking, running and crouch-walking from a real gait cycle: the phase runs on distance (a stride a
#   1.3 m walking, 1.9 m flat out), so feet don't skate; the swinging leg's knee folds and its foot
#   clears the ground, the planted leg stays straight-ish; the hips sway over the planted foot, twist
#   with the stride against the shoulders; the body dips at each foot strike and rises over it. It
#   leans into the way it's going and into speeding up; going backwards the cycle runs backwards,
#   sideways the legs swing out. Arms counter-swing, bent more the faster it goes.
#   Standing: breathing, a slow weight shift from foot to foot, now and then a look round or a shuffle
#   of the feet when it turns on the spot.
#   In the air: knees tucked, arms out; landing: a dip that springs back.
#   Emotes (EMOTES): upper-body ones play over the walk; DANCE and SIT take the whole body and end
#   when it moves off.
extends RefCounted

# The wheel's inner ring (saying something to the crew), then its outer ring (fooling about).
const SOCIAL := ["WAVE", "POINT", "BECKON", "THUMBS UP", "SALUTE", "SHRUG", "CLAP", "CHEER", "BOW", "FACEPALM"]
const FUN := ["DANCE", "ROBOT", "CHICKEN", "AIR GUITAR", "HEADBANG", "FLEX", "LAUGH", "JUMPING JACKS", "PUSH-UPS", "SPIN", "SIT", "LIE DOWN"]
const EMOTES := SOCIAL + FUN
const LENGTH := {"WAVE": 2.6, "POINT": 2.2, "BECKON": 2.6, "THUMBS UP": 1.9, "SALUTE": 2.2, "SHRUG": 1.7,
	"CLAP": 2.8, "CHEER": 2.6, "BOW": 2.4, "FACEPALM": 2.6, "DANCE": 40.0, "ROBOT": 40.0, "CHICKEN": 40.0,
	"AIR GUITAR": 30.0, "HEADBANG": 20.0, "FLEX": 3.2, "LAUGH": 3.0, "JUMPING JACKS": 30.0, "PUSH-UPS": 40.0,
	"SPIN": 6.0, "SIT": 600.0, "LIE DOWN": 600.0}
const WHOLE := ["DANCE", "ROBOT", "CHICKEN", "AIR GUITAR", "JUMPING JACKS", "PUSH-UPS", "SPIN", "SIT", "LIE DOWN"]   # the whole body: moving off ends them

var emote := ""
var emote_t := 0.0
var clapped := 0          # claps so far (puppet/player play the sound on each)
var _w := 0.0             # how far in the emote is blended (0..1)
var _phase := 0.0
var _gait := 0.0          # 0 standing .. 1 moving: legs ease into and out of the cycle
var _run := 0.0
var _lean := Vector2.ZERO
var _prev_v := Vector3.ZERO
var _idle := 0.0
var _shift := 0.0         # weight from foot to foot when standing
var _look := 0.0          # an idle glance
var _look_t := 3.0
var _shuffle := 0.0       # turning on the spot: a few small steps
var _prev_yaw := 0.0
var _land := 0.0
var _air := 0.0
var _was_floor := true
var _bob := 0.0


func play(name: String) -> void:
	emote = name
	emote_t = 0.0
	clapped = 0


func stop() -> void:
	emote = ""


func busy() -> bool:
	return emote != "" and _w > 0.02


## Pose the parts. st: vel (world, m/s), yaw (the body's rotation.y), floor (bool), crouch (0..1),
## pitch (head up/down), neck (head turned from the body), hands (false: something's held, so the
## arms are left to the caller unless an emote wants them). Returns {arms: Dictionary of the free
## arm rotations to use unless the caller holds something, emote_arms: bool}.
func pose(parts: Dictionary, body: Node3D, st: Dictionary, delta: float) -> Dictionary:
	delta = minf(delta, 0.1)
	var vel: Vector3 = st.vel * Vector3(1, 0, 1)
	var local: Vector3 = Basis(Vector3.UP, -float(st.yaw)) * vel   # (x right, -z ahead)
	var speed := local.length()
	var on_floor: bool = st.floor
	var crouch: float = st.crouch
	var k := 1.0 - exp(-delta * 10.0)
	# The emote: ends on time; whole-body ones as soon as it moves off.
	if emote != "":
		emote_t += delta
		if emote_t > LENGTH.get(emote, 2.0) or (emote in WHOLE and speed > 0.8) or not on_floor:
			emote = ""
	_w = move_toward(_w, 1.0 if emote != "" else 0.0, delta * 4.0)
	# The gait.
	var moving := speed > 0.25 and on_floor
	_gait = move_toward(_gait, 1.0 if moving else 0.0, delta * (5.0 if moving else 3.5))
	_run = lerpf(_run, clampf((speed - 3.2) / 2.8, 0.0, 1.0), k * 0.5)
	var back := local.z > 0.3 and absf(local.z) > absf(local.x) * 0.7
	var stride := lerpf(1.3, 1.9, _run) * lerpf(1.0, 0.7, crouch)
	_phase += speed * delta / stride * TAU * (-1.0 if back else 1.0)
	var side := atan2(local.x, -local.z) if not back else atan2(-local.x, local.z)   # which way the legs swing, from ahead
	side = clampf(side, -1.3, 1.3)
	# Standing about.
	var yaw: float = st.yaw
	var turn := angle_difference(_prev_yaw, yaw)
	_prev_yaw = yaw
	if not moving and absf(turn) > delta * 1.5:
		_shuffle = minf(_shuffle + absf(turn) * 2.0, 1.0)
	_shuffle = move_toward(_shuffle, 0.0, delta * 1.2)
	if _shuffle > 0.05:
		_phase += delta * TAU * 1.6 * _shuffle
	_idle += delta
	_shift = sin(_idle * 0.45) * (1.0 - _gait)
	_look_t -= delta
	if _look_t < 0.0:
		_look_t = randf_range(4.0, 9.0)
		_look = randf_range(-0.35, 0.35) if randf() < 0.6 else 0.0
	# Landing.
	if on_floor and not _was_floor and _air > 0.25:
		_land = clampf(_air * 1.3, 0.3, 1.0)
	_was_floor = on_floor
	_air = 0.0 if on_floor else _air + delta
	_land = move_toward(_land, 0.0, delta * 3.0)
	var air := clampf(_air * 5.0, 0.0, 1.0)
	# Lean into the way it's going, and into speeding up or stopping.
	var acc := (vel - _prev_v) / maxf(delta, 0.001)
	_prev_v = vel
	var lacc := Basis(Vector3.UP, -yaw) * acc
	var want := Vector2(clampf(-local.z * 0.03 - lacc.z * 0.012, -0.12, 0.28), clampf(-local.x * 0.03 - lacc.x * 0.01, -0.15, 0.15))
	_lean = _lean.lerp(want * (1.0 - crouch * 0.5), k * 0.5)
	var p := _phase
	var g := _gait * (1.0 - air)
	var amp := lerpf(0.42, 0.62, _run) * lerpf(1.0, 0.75, crouch)
	var sw := sin(p)          # + : left leg forward
	var fwd := cos(side)
	var out := sin(side)
	# Legs: the thigh swings fore and aft (out to the side when strafing); the knee folds as the leg
	# comes through (the first half of its swing) and a little at each strike; crouched, it all sinks.
	var leg := func(s: float, ph: float) -> Array:
		var swing := sin(ph)
		var thigh := swing * amp * g
		var lift := maxf(0.0, cos(ph)) * g   # (the leg coming forward)
		var knee := -(lift * lerpf(0.75, 1.35, _run) + maxf(0.0, -swing) * 0.15 * g)
		var tx := thigh * fwd + crouch * 0.95 + air * (0.75 if s < 0.0 else 0.35) + _land * 0.55
		var tz := thigh * out * 0.6 * -1.0 + s * (0.04 + _shift * 0.04 * s) * (1.0 - g)
		var sx := knee - crouch * 1.65 - air * (1.2 if s < 0.0 else 0.6) - _land * 1.0
		if _shuffle > 0.05 and g < 0.3:   # turning on the spot: little lifts of the feet
			var lf := maxf(0.0, sin(ph)) * _shuffle
			tx += lf * 0.25
			sx -= lf * 0.45
		return [Vector3(tx, 0, tz), Vector3(sx, 0, 0)]
	var ll: Array = leg.call(-1.0, p)
	var lr: Array = leg.call(1.0, p + PI)
	# The body: dips at each strike (twice a cycle), sways over the planted foot, twists with the stride.
	var dip := (1.0 - absf(cos(p))) * 0.045 * g * lerpf(1.0, 1.6, _run)
	_bob = lerpf(_bob, dip, k)
	var sink := -crouch * 0.48 - _land * 0.22 - _bob + absf(sin(p * 2.0)) * 0.0 + sin(_idle * 1.6) * 0.004 * (1.0 - g)
	body.position = Vector3(sin(p) * 0.035 * g + _shift * 0.03, sink, 0)
	var hip_twist := sw * 0.14 * g * fwd
	var hip_roll := -sin(p) * 0.05 * g + _shift * 0.03
	parts.pelvis.rotation = Vector3(0, hip_twist, hip_roll)
	var breath := sin(_idle * 1.7) * 0.012
	var torso := Vector3(-_lean.x - crouch * 0.28 - _run * 0.12 + breath * (1.0 - g), -hip_twist * 1.6 + float(st.neck) * 0.15, -hip_roll * 0.8 + _lean.y)
	var head := Vector3(clampf(float(st.pitch), -0.9, 0.9) + crouch * 0.2 + _lean.x * 0.6 + _run * 0.1, float(st.neck) * 0.85 + _look * (1.0 - g) * (1.0 - _w), 0)
	# Free arms: counter-swing to the legs, elbows bent more the faster it goes; out a little when
	# crouched; up and out in the air.
	var aw := lerpf(0.38, 0.85, _run) * g
	var elbow := lerpf(0.3, 1.45, _run)
	var arms := {
		"upper_arm_l": Vector3(-sw * aw * fwd + 0.06 + crouch * 0.25 + air * 0.4, 0, -0.1 - air * 0.5 - crouch * 0.1),
		"forearm_l": Vector3(elbow + maxf(0.0, -sw) * 0.3 * g, 0, 0.05),
		"upper_arm_r": Vector3(sw * aw * fwd + 0.06 + crouch * 0.25 + air * 0.4, 0, 0.1 + air * 0.5 + crouch * 0.1),
		"forearm_r": Vector3(elbow + maxf(0.0, sw) * 0.3 * g, 0, -0.05),
	}
	# The emote over it all.
	var whole := emote in WHOLE
	var e := _emote(p, speed) if emote != "" else {}
	var we := smoothstep(0.0, 1.0, _w)
	var blend := func(name: String, base: Vector3) -> Vector3:
		return base.lerp(e[name], we) if e.has(name) else base
	parts.thigh_l.rotation = blend.call("thigh_l", ll[0])
	parts.shin_l.rotation = blend.call("shin_l", ll[1])
	parts.thigh_r.rotation = blend.call("thigh_r", lr[0])
	parts.shin_r.rotation = blend.call("shin_r", lr[1])
	parts.torso.rotation = blend.call("torso", torso)
	parts.head.rotation = blend.call("head", head)
	parts.pelvis.rotation = blend.call("pelvis", parts.pelvis.rotation)
	if e.has("body"):
		body.position = body.position.lerp(e.body, we)
	body.rotation = Vector3.ZERO.lerp(e.get("body_rot", Vector3.ZERO), we)
	var emote_arms := e.has("upper_arm_r")
	for n in arms:
		arms[n] = blend.call(n, arms[n])
	if emote_arms or st.hands:
		for n in arms:
			parts[n].rotation = arms[n]
	_on_ground(parts, body, we if whole or e.has("body_rot") else 0.0)
	return {"arms": arms, "emote_arms": emote_arms and we > 0.5, "whole": whole}


## Nothing through the floor: the lowest of the soles, knees, seat, hands and helmet, lifted to it
## (sitting, lying, push-ups, a deep crouch). `settle`: for a whole-body emote, also brought down
## onto it (so a sit sits on the floor, not above it).
func _on_ground(parts: Dictionary, body: Node3D, settle: float) -> void:
	var host: Node3D = body.get_parent()
	if host == null:
		return
	var pts := [[parts.shin_l, Vector3(0, -0.515, 0.05)], [parts.shin_l, Vector3(0, -0.5, -0.2)], [parts.shin_r, Vector3(0, -0.515, 0.05)], [parts.shin_r, Vector3(0, -0.5, -0.2)],
		[parts.shin_l, Vector3(0, 0.0, -0.06)], [parts.shin_r, Vector3(0, 0.0, -0.06)], [parts.pelvis, Vector3(0, -0.2, 0.06)], [parts.pelvis, Vector3(0.12, -0.14, 0.08)], [parts.pelvis, Vector3(-0.12, -0.14, 0.08)],
		[parts.forearm_l, Vector3(0, -0.32, 0)], [parts.forearm_r, Vector3(0, -0.32, 0)], [parts.upper_arm_l, Vector3(0, -0.29, 0)], [parts.upper_arm_r, Vector3(0, -0.29, 0)],
		[parts.torso, Vector3(0, 0.4, 0.12)], [parts.torso, Vector3(0, 0.25, -0.15)], [parts.head, Vector3(0, 0.27, 0)], [parts.head, Vector3(0, 0.1, -0.17)], [parts.head, Vector3(0, 0.1, 0.17)]]
	var low := INF
	for pt in pts:
		low = minf(low, host.to_local((pt[0] as Node3D).to_global(pt[1])).y)
	if low < 0.0:
		body.position.y -= low
	elif settle > 0.0:
		body.position.y -= low * settle


## An emote's pose at emote_t: only the parts it moves.
func _emote(p: float, speed: float) -> Dictionary:
	var t := emote_t
	var e := {}
	match emote:
		"WAVE":   # right hand up by the head, waving from the elbow
			var wv := sin(t * 11.0) * 0.38
			e.upper_arm_r = Vector3(0.25, 0, 2.3)
			e.forearm_r = Vector3(0, 0, 1.35 + wv)
			e.head = Vector3(0.05, 0, -0.1)
			e.torso = Vector3(0, 0.1, -0.06)
		"POINT":   # arm straight out at what they mean, a little look along it
			e.upper_arm_r = Vector3(1.45, -0.2, 0.15)
			e.forearm_r = Vector3(0.05, 0, 0)
			e.upper_arm_l = Vector3(0.1, 0, -0.12)
			e.torso = Vector3(-0.05, 0.25, 0)
			e.head = Vector3(0.1, 0.18, 0)
		"BECKON":   # arm out ahead, the forearm curling them in, again and again
			var c := maxf(0.0, sin(t * 6.0))
			e.upper_arm_r = Vector3(1.0, 0, 0.25)
			e.forearm_r = Vector3(0.35 + c * 1.4, 0, 0)
			e.torso = Vector3(0.05, 0.1, 0)
			e.head = Vector3(0.0, 0.08, 0.12)
		"THUMBS UP":   # fist out in front at chest height, a nod
			e.upper_arm_r = Vector3(0.75, 0, 0.35)
			e.forearm_r = Vector3(1.4, 0, 0)
			e.head = Vector3(0.12 + maxf(0.0, sin(t * 7.0)) * 0.15 * (1.0 if t < 1.0 else 0.0), 0, 0)
		"SALUTE":   # the Bureau's salute: hand to the brow, stood straight
			var snap := smoothstep(0.0, 0.25, t)
			e.upper_arm_r = Vector3(0.6, 0, 1.75) * snap
			e.forearm_r = Vector3(0, 0, 2.25) * snap
			e.upper_arm_l = Vector3(0, 0, -0.04)
			e.forearm_l = Vector3(0.05, 0, 0)
			e.torso = Vector3(0.05, 0, 0)
			e.head = Vector3(0.05, 0, 0)
		"SHRUG":   # shoulders up, palms out, head on one side
			var s := sin(clampf(t / 1.4, 0.0, 1.0) * PI)
			e.upper_arm_l = Vector3(0.15 * s, 0, -0.1 - 0.3 * s)   # elbows out a little
			e.upper_arm_r = Vector3(0.15 * s, 0, 0.1 + 0.3 * s)
			e.forearm_l = Vector3(0.3 + 1.2 * s, 0.7 * s, 0)       # forearms up and turned out: palms up
			e.forearm_r = Vector3(0.3 + 1.2 * s, -0.7 * s, 0)
			e.head = Vector3(0, 0, 0.3 * s)
			e.torso = Vector3(0.08 * s, 0, 0)
		"CLAP":   # hands meeting in front of the chest
			var c := absf(sin(t * 7.0))   # 0: hands together, 1: apart
			e.upper_arm_l = Vector3(0.85, -0.5 + c * 0.25, 0)   # (yawed in toward the chest)
			e.upper_arm_r = Vector3(0.85, 0.5 - c * 0.25, 0)
			e.forearm_l = Vector3(1.0, -0.45 + c * 0.35, 0)
			e.forearm_r = Vector3(1.0, 0.45 - c * 0.35, 0)
			e.head = Vector3(0.1, 0, 0)
			var n := int(floor(t * 7.0 / PI))
			if n > clapped:
				clapped = n
		"CHEER":   # both fists up, pumping
			var pump := sin(t * 9.0) * 0.25
			e.upper_arm_l = Vector3(0.3, 0, -2.6 - pump)
			e.upper_arm_r = Vector3(0.3, 0, 2.6 + pump)
			e.forearm_l = Vector3(0.6, 0, -0.3)
			e.forearm_r = Vector3(0.6, 0, 0.3)
			e.head = Vector3(0.35, 0, 0)
			e.torso = Vector3(0.08, 0, 0)
			e.body = Vector3(0, absf(sin(t * 9.0)) * 0.05, 0)
		"DANCE":   # a groove, then a jig, in turn, to a beat of 2 a second
			var b := t * TAU * 2.0
			if fmod(t, 16.0) < 8.0:   # the groove: knees bouncing, hips and shoulders rolling, arms pumping in turn
				var bob := absf(sin(b * 0.5))
				e.thigh_l = Vector3(0.35 + bob * 0.25, 0, -0.08)
				e.thigh_r = Vector3(0.35 + bob * 0.25, 0, 0.08)
				e.shin_l = Vector3(-0.6 - bob * 0.45, 0, 0)
				e.shin_r = Vector3(-0.6 - bob * 0.45, 0, 0)
				e.body = Vector3(sin(b * 0.25) * 0.05, -0.12 - bob * 0.08, 0)
				e.pelvis = Vector3(0, sin(b * 0.25) * 0.35, sin(b * 0.5) * 0.08)
				e.torso = Vector3(0.1, -sin(b * 0.25) * 0.5, -sin(b * 0.5) * 0.06)
				e.upper_arm_l = Vector3(0.9 + sin(b * 0.5) * 0.6, 0, -0.35)
				e.upper_arm_r = Vector3(0.9 - sin(b * 0.5) * 0.6, 0, 0.35)
				e.forearm_l = Vector3(1.6, 0, 0)
				e.forearm_r = Vector3(1.6, 0, 0)
				e.head = Vector3(sin(b) * 0.12, sin(b * 0.25) * 0.3, 0)
			else:   # the jig: hands on hips, kicking out one foot then the other, hopping
				var kick := sin(b * 0.5)
				var hop := absf(sin(b))
				e.thigh_l = Vector3(maxf(0.0, kick) * 0.9, 0, -0.05)
				e.thigh_r = Vector3(maxf(0.0, -kick) * 0.9, 0, 0.05)
				e.shin_l = Vector3(-maxf(0.0, kick) * 0.2 - 0.15, 0, 0)
				e.shin_r = Vector3(-maxf(0.0, -kick) * 0.2 - 0.15, 0, 0)
				e.body = Vector3(0, hop * 0.08 - 0.03, 0)
				e.upper_arm_l = Vector3(-0.25, 0, -0.75)
				e.upper_arm_r = Vector3(-0.25, 0, 0.75)
				e.forearm_l = Vector3(0.2, 0, 1.6)
				e.forearm_r = Vector3(0.2, 0, -1.6)
				e.torso = Vector3(-0.1, 0, kick * 0.1)
				e.head = Vector3(-0.1, 0, -kick * 0.15)
		"BOW":   # a deep bow from the waist, one hand across the stomach, the other behind
			var b := sin(clampf(t / 2.1, 0.0, 1.0) * PI)
			e.torso = Vector3(-0.85 * b, 0, 0)
			e.pelvis = Vector3(-0.35 * b, 0, 0)
			e.head = Vector3(-0.25 * b, 0, 0)
			e.upper_arm_r = Vector3(0.55 * b, 0.5 * b, 0)
			e.forearm_r = Vector3(1.5 * b, 0, 0)
			e.upper_arm_l = Vector3(-0.45 * b, -0.3 * b, -0.1)
			e.forearm_l = Vector3(1.2 * b, 0, 0)
		"FACEPALM":   # hand to the visor, head down, shaking slowly
			var u := smoothstep(0.0, 0.35, t)
			e.upper_arm_r = Vector3(1.35, 0, -0.5) * u
			e.forearm_r = Vector3(2.05, 0, 0) * u
			e.head = Vector3(-0.35 * u, sin(t * 4.0) * 0.18 * u, 0)
			e.torso = Vector3(-0.15 * u, 0, 0)
		"FLEX":   # both arms up like a strongman, squeezing
			var sq := 0.15 * sin(t * 5.0)
			e.upper_arm_l = Vector3(0.1, 0, -1.45)
			e.upper_arm_r = Vector3(0.1, 0, 1.45)
			e.forearm_l = Vector3(0, 0, -1.65 - sq)
			e.forearm_r = Vector3(0, 0, 1.65 + sq)
			e.torso = Vector3(0.12, sin(t * 2.0) * 0.25, 0)
			e.head = Vector3(0.15, -sin(t * 2.0) * 0.2, 0)
			e.thigh_l = Vector3(0, 0, -0.12)
			e.thigh_r = Vector3(0, 0, 0.12)
		"LAUGH":   # doubled over, hands on the belly, shaking with it
			var shake := sin(t * 22.0) * 0.06
			e.torso = Vector3(-0.35 + shake, 0, 0)
			e.head = Vector3(0.35 + shake * 2.0, 0, sin(t * 3.0) * 0.1)
			e.upper_arm_l = Vector3(0.45, -0.35, 0)
			e.upper_arm_r = Vector3(0.45, 0.35, 0)
			e.forearm_l = Vector3(1.4, 0, 0)
			e.forearm_r = Vector3(1.4, 0, 0)
			e.body = Vector3(0, absf(sin(t * 11.0)) * 0.02, 0)
		"HEADBANG":   # head going like a piston, one fist up
			var hb := sin(t * 13.0)
			e.head = Vector3(-0.2 + hb * 0.45, 0, 0)
			e.torso = Vector3(-0.15 + hb * 0.15, 0, 0)
			e.upper_arm_r = Vector3(0.5, 0, 2.5)
			e.forearm_r = Vector3(0.4 + maxf(0.0, hb) * 0.4, 0, 0.3)
			e.upper_arm_l = Vector3(0.2, 0, -0.3)
			e.forearm_l = Vector3(0.9, 0, 0)
		"AIR GUITAR":   # feet planted wide, leaning back, strumming like mad
			var st := sin(t * 18.0)
			e.thigh_l = Vector3(0.25, 0, -0.32)
			e.thigh_r = Vector3(0.25, 0, 0.32)
			e.shin_l = Vector3(-0.5, 0, 0)
			e.shin_r = Vector3(-0.5, 0, 0)
			e.body = Vector3(0, -0.06, 0)
			e.torso = Vector3(0.2 + sin(t * 3.0) * 0.08, 0.3, sin(t * 3.0) * 0.08)
			e.head = Vector3(0.1 + absf(sin(t * 6.0)) * 0.2, -0.3, 0)
			e.upper_arm_l = Vector3(0.9, 0, -0.75)   # along the neck
			e.forearm_l = Vector3(0.25 + sin(t * 2.0) * 0.15, 0, 0)
			e.upper_arm_r = Vector3(0.5, 0.25, 0.25)   # the strumming hand
			e.forearm_r = Vector3(1.3 + st * 0.35, 0, 0)
		"JUMPING JACKS":   # out and in, hopping
			var c := (1.0 - cos(t * 7.0)) * 0.5   # 0 in, 1 out
			e.upper_arm_l = Vector3(0, 0, -0.1 - c * 2.8)
			e.upper_arm_r = Vector3(0, 0, 0.1 + c * 2.8)
			e.forearm_l = Vector3(0.1, 0, -0.2 * c)
			e.forearm_r = Vector3(0.1, 0, 0.2 * c)
			e.thigh_l = Vector3(0.05, 0, -0.04 - c * 0.3)
			e.thigh_r = Vector3(0.05, 0, 0.04 + c * 0.3)
			e.shin_l = Vector3(-0.1, 0, 0)
			e.shin_r = Vector3(-0.1, 0, 0)
			e.body = Vector3(0, absf(sin(t * 7.0)) * 0.16, 0)
		"PUSH-UPS":   # face down on the floor, pushing up and down
			var down := smoothstep(0.0, 0.7, t)
			var up := (1.0 - cos(maxf(0.0, t - 0.7) * 3.4)) * 0.5   # 0 up, 1 down
			e.body_rot = Vector3((-PI / 2.0 + lerpf(0.42, 0.16, up)) * down, 0, 0)   # (on the toes: the shoulders as high as the arms reach)
			e.upper_arm_l = Vector3(1.45 - up * 0.5, 0, -0.18)
			e.upper_arm_r = Vector3(1.45 - up * 0.5, 0, 0.18)
			e.forearm_l = Vector3(up * 1.3, 0, 0)
			e.forearm_r = Vector3(up * 1.3, 0, 0)
			e.thigh_l = Vector3(0, 0, -0.04)
			e.thigh_r = Vector3(0, 0, 0.04)
			e.shin_l = Vector3(0, 0, 0)
			e.shin_r = Vector3(0, 0, 0)
			e.torso = Vector3(0, 0, 0)
			e.head = Vector3(0.45, 0, 0)
			e.body = Vector3(0, 0, 0)
		"ROBOT":   # stiff, a pose a beat, snapped between
			var beat := int(t * 2.5)
			var f := smoothstep(0.0, 0.12, fmod(t * 2.5, 1.0) / 2.5)
			var poses := [
				[Vector3(0, 0, 1.5), Vector3(0, 0, 1.55), Vector3(0, 0, -1.5), Vector3(0, 0, -1.55), 0.0, 0.0],
				[Vector3(1.55, 0, 0.1), Vector3(0, 0, 0), Vector3(0, 0, -1.5), Vector3(0, 0, 1.55), 0.5, 0.4],
				[Vector3(0, 0, 1.5), Vector3(0, 0, -1.55), Vector3(1.55, 0, -0.1), Vector3(0, 0, 0), -0.5, -0.4],
				[Vector3(1.55, 0, 0.1), Vector3(1.55, 0, 0), Vector3(1.55, 0, -0.1), Vector3(1.55, 0, 0), 0.0, 0.3],
			]
			var a: Array = poses[(beat + 3) % 4]
			var b: Array = poses[beat % 4]
			e.upper_arm_r = (a[0] as Vector3).lerp(b[0], f)
			e.forearm_r = (a[1] as Vector3).lerp(b[1], f)
			e.upper_arm_l = (a[2] as Vector3).lerp(b[2], f)
			e.forearm_l = (a[3] as Vector3).lerp(b[3], f)
			e.torso = Vector3(0, lerpf(a[4], b[4], f), 0)
			e.head = Vector3(0, lerpf(a[5], b[5], f) * 1.5, 0)
			e.thigh_l = Vector3(0.15, 0, -0.06)
			e.thigh_r = Vector3(0.15, 0, 0.06)
			e.shin_l = Vector3(-0.3, 0, 0)
			e.shin_r = Vector3(-0.3, 0, 0)
			e.body = Vector3(0, -0.04 - (0.03 if f < 1.0 else 0.0), 0)
		"CHICKEN":   # hands in the armpits flapping, knees bent, head pecking, a hop
			var flap := maxf(0.0, sin(t * 14.0))
			var peck := maxf(0.0, sin(t * 5.0))
			e.upper_arm_l = Vector3(-0.2, 0, -0.35 - flap * 0.6)
			e.upper_arm_r = Vector3(-0.2, 0, 0.35 + flap * 0.6)
			e.forearm_l = Vector3(2.5, 0, 0)
			e.forearm_r = Vector3(2.5, 0, 0)
			e.torso = Vector3(-0.3 - peck * 0.2, 0, 0)
			e.head = Vector3(0.4 - peck * 0.3, sin(t * 2.5) * 0.4, 0)
			e.thigh_l = Vector3(0.6, 0, -0.25)
			e.thigh_r = Vector3(0.6, 0, 0.25)
			e.shin_l = Vector3(-0.9, 0, 0)
			e.shin_r = Vector3(-0.9, 0, 0)
			e.body = Vector3(0, -0.15 + absf(sin(t * 7.0)) * 0.04, 0)
		"SPIN":   # a twirl on one foot, arms out
			var sp := smoothstep(0.0, 1.0, t / 4.5)
			e.body_rot = Vector3(0, sp * TAU * 3.0, 0)
			e.upper_arm_l = Vector3(0.1, 0, -1.4)
			e.upper_arm_r = Vector3(0.1, 0, 1.4)
			e.forearm_l = Vector3(0.2, 0, -0.2)
			e.forearm_r = Vector3(0.2, 0, 0.2)
			e.thigh_l = Vector3(0.5, 0, -0.1)
			e.shin_l = Vector3(-1.4, 0, 0)
			e.head = Vector3(0.15, 0, 0)
		"LIE DOWN":   # flat on the back, hands behind the head, one knee up
			var down := smoothstep(0.0, 1.0, t)
			e.body_rot = Vector3(PI / 2.0 * down, 0, 0)
			e.upper_arm_l = Vector3(0, 0, -2.7) * down
			e.upper_arm_r = Vector3(0, 0, 2.7) * down
			e.forearm_l = Vector3(2.2, 0, 0) * down
			e.forearm_r = Vector3(2.2, 0, 0) * down
			e.thigh_l = Vector3(0.7, 0, 0) * down
			e.shin_l = Vector3(-1.3, 0, 0) * down
			e.thigh_r = Vector3(0.05, 0, 0.06)
			e.shin_r = Vector3(0, 0, 0)
			e.torso = Vector3(0, 0, 0)
			e.head = Vector3(0.35 + sin(t * 0.4) * 0.05, sin(t * 0.17) * 0.4, 0)
			e.body = Vector3(0, 0, 0)
		"SIT":   # down on the floor, legs out, leaning back on the hands
			var down := smoothstep(0.0, 0.8, t)
			e.body = Vector3(0, -0.8 * down, 0.2 * down)
			e.thigh_l = Vector3(1.5, 0, -0.08) * down   # legs out along the floor, one knee up a little
			e.thigh_r = Vector3(1.9, 0, 0.12) * down
			e.shin_l = Vector3(-0.08, 0, 0) * down
			e.shin_r = Vector3(-0.8, 0, 0) * down
			e.torso = Vector3(0.3 * down + sin(t * 1.5) * 0.01, 0, 0)   # (leaning back on the hands)
			e.upper_arm_l = Vector3(-0.55, 0, -0.25) * down
			e.upper_arm_r = Vector3(-0.55, 0, 0.25) * down
			e.forearm_l = Vector3(0.1, 0, 0)
			e.forearm_r = Vector3(0.1, 0, 0)
			e.head = Vector3(0.1 + sin(t * 0.3) * 0.08, sin(t * 0.21) * 0.3, 0)
	return e
