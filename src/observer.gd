# The Observer: an old bellows press camera on three long telescoping tripod legs that walk like a
# harvestman. It follows you at a distance, always behind, ticking and clicking its shutter. It
# creeps a little closer the longer you put up with it. DON'T LOOK BACK: the moment it's in your
# view it whines its flash up (about two thirds of a second to look away again) and fires. You're
# blinded, everything that hears hears it, and it runs off, leaving a photograph of you on the floor.
extends "res://src/monster.gd"

enum { LURK, FOLLOW, CHARGE, FLEE }
const WALK := 1.5
const CREEP := 3.4
const RUN := 6.5
const CHARGE_T := 0.65   # whine before the flash: time to look away
const HUB_Y := 1.35      # tripod head height
const UPPER := 0.9       # leg bone lengths (long lower bones: the knees ride up high, like a harvestman)
const LOWER := 1.75
const REACH := 0.9       # how far out the feet stand
const BODY := Color(0.52, 0.44, 0.38)

var state := LURK
var photos_taken := 0
var _goal := Vector3.ZERO
var _prey
var _charge := 0.0
var _away := 0.0         # how long they've looked away during a charge
var _cool := 0.0         # after a flash it won't follow anyone for a while
var _flee_t := 0.0
var _creep := 7.0        # how far behind it keeps
var _click := 2.0
var _hub: Node3D
var _pan: Node3D
var _tilt: Node3D
var _lens: Node3D
var _iris_mat: StandardMaterial3D
var _bulb_mat: StandardMaterial3D
var _tally_mat: StandardMaterial3D
var _flash: SpotLight3D
var _whine: AudioStreamPlayer3D
var _legs: Array = []    # per leg: {"a": angle, "upper": Node3D, "lower": Node3D, "foot": Vector3 world, "from", "to", "t"}
var _stepping := -1


func _ready() -> void:
	_setup_body(0.35, 1.9)
	presence("lens_tick", -9.0, 3.0)
	_whine = AudioStreamPlayer3D.new()
	_whine.stream = Sfx.stream("flash_whine")
	_whine.unit_size = 5.0
	_whine.bus = "World"
	add_child(_whine)
	_hub = Node3D.new()
	add_child(_hub)
	_hub.position.y = HUB_Y
	_build_hub()
	for i in 3:
		_legs.append(_build_leg(TAU * i / 3.0))
	_build_camera()
	_goal = global_position
	_plant_feet.call_deferred()


# --- model -------------------------------------------------------------------------------

## Tripod head: a cast collar with three leg sockets, a geared crank, and a ring of photos hanging under it.
func _build_hub() -> void:
	var iron := Color(0.26, 0.25, 0.24)
	A.cyl(_hub, 0.13, 0.12, Vector3.ZERO, "metal", iron)
	A.cyl(_hub, 0.07, 0.16, Vector3(0, -0.13, 0), "metal", iron, false, "y", 0.12)
	A.cyl(_hub, 0.15, 0.025, Vector3(0, 0.07, 0), "brass", Color.WHITE)
	A.cyl(_hub, 0.04, 0.22, Vector3(0, -0.3, 0), "metal", Color(0.5, 0.5, 0.5))      # centre column
	A.sphere(_hub, 0.035, Vector3(0, -0.42, 0), "brass")
	for i in 3:
		var a := TAU * i / 3.0
		A.sphere(_hub, 0.055, Vector3(sin(a) * 0.13, 0, cos(a) * 0.13), "brass")
		A.box(_hub, Vector3(0.05, 0.03, 0.025), Vector3(sin(a) * 0.17, 0.035, cos(a) * 0.17), "brass", Color.WHITE, false, 0.2, Vector3(0, a, 0))   # wing nut
	# Elevation crank on the side.
	A.seg(_hub, Vector3(0.13, 0.0, 0), Vector3(0.22, -0.02, 0), 0.012, 0.012, "metal", Color(0.5, 0.5, 0.5))
	A.seg(_hub, Vector3(0.22, -0.02, 0), Vector3(0.24, -0.12, 0.02), 0.01, 0.01, "metal", Color(0.5, 0.5, 0.5))
	A.cyl(_hub, 0.018, 0.05, Vector3(0.24, -0.15, 0.02), "wood", Color(0.5, 0.3, 0.2))
	# Its trophies: earlier photographs clipped to a wire hoop, turning slowly.
	var hoop := Node3D.new()
	_hub.add_child(hoop)
	hoop.position.y = -0.14
	A.ring(hoop, 0.246, 0.234, Vector3.ZERO, "metal", Color(0.45, 0.45, 0.45))
	for k in 3:
		A.seg(hoop, Vector3(sin(TAU * k / 3.0 + 0.5) * 0.24, 0, cos(TAU * k / 3.0 + 0.5) * 0.24), Vector3(0, 0.12, 0), 0.004, 0.004, "metal", Color(0.4, 0.4, 0.4))
	for k in 7:
		var a := TAU * k / 7.0
		var hang := Node3D.new()
		hoop.add_child(hang)
		hang.position = Vector3(sin(a) * 0.24, 0, cos(a) * 0.24)
		hang.rotation.y = a + PI / 2.0
		A.box(hang, Vector3(0.012, 0.03, 0.012), Vector3(0, -0.012, 0), "wood", Color(0.75, 0.6, 0.4), false, 0.1)   # peg
		var swing := Node3D.new()
		hang.add_child(swing)
		swing.position.y = -0.02
		A.box(swing, Vector3(0.085, 0.104, 0.003), Vector3(0, -0.055, 0), "paper", Color(0.93, 0.9, 0.82), false, 0.2)
		var shade := Color(0.12, 0.13, 0.15).lerp(Color(0.38, 0.3, 0.22), randf())
		for z in [-0.0022, 0.0022]:
			A.box(swing, Vector3(0.071, 0.071, 0.001), Vector3(0, -0.046, z), "concrete", shade, false, 0.05)
		A.sway(swing, randf_range(0.08, 0.16), randf_range(0.9, 1.6))
	A.spin(hoop, "y", 40.0)


## One leg: a thick brass upper tube to a clamped knee, then a telescoping lower section to a spiked
## foot with a rubber shoe. Bones are re-aimed every frame by _aim (2-bone IK).
func _build_leg(a: float) -> Dictionary:
	var upper := Node3D.new()
	add_child(upper)
	A.cyl(upper, 0.032, UPPER, Vector3(0, UPPER / 2.0, 0), "brass", Color(0.85, 0.8, 0.7))
	A.cyl(upper, 0.04, 0.05, Vector3(0, 0.06, 0), "metal", Color(0.3, 0.3, 0.3))
	A.cyl(upper, 0.038, 0.04, Vector3(0, UPPER * 0.55, 0), "metal", Color(0.3, 0.3, 0.3))     # clamp collar
	A.box(upper, Vector3(0.025, 0.05, 0.07), Vector3(0, UPPER * 0.55, 0.04), "metal", Color(0.3, 0.3, 0.3), false, 0.2)   # clamp lever
	A.sphere(upper, 0.05, Vector3(0, UPPER, 0), "metal", Color(0.3, 0.29, 0.28))              # knee
	A.box(upper, Vector3(0.11, 0.025, 0.02), Vector3(0, UPPER, 0), "brass", Color.WHITE, false, 0.2)   # knee wing nut
	var lower := Node3D.new()
	add_child(lower)
	A.cyl(lower, 0.027, LOWER * 0.55, Vector3(0, LOWER * 0.275, 0), "metal", Color(0.55, 0.54, 0.5))
	A.cyl(lower, 0.034, 0.05, Vector3(0, LOWER * 0.55, 0), "brass", Color.WHITE)               # telescope clamp
	A.cyl(lower, 0.018, LOWER * 0.45, Vector3(0, LOWER * 0.775, 0), "metal", Color(0.7, 0.7, 0.68))
	A.cyl(lower, 0.016, 0.1, Vector3(0, LOWER - 0.02, 0), "metal", Color(0.25, 0.25, 0.25), false, "y", 0.002)   # spike
	A.cyl(lower, 0.03, 0.05, Vector3(0, LOWER - 0.09, 0), "rubber", Color.WHITE, false, "y", 0.022)              # rubber shoe
	var cable := A.seg(lower, Vector3(0.03, 0.1, 0), Vector3(0.04, LOWER * 0.5, 0.01), 0.006, 0.006, "rubber")   # trailing cable
	cable.rotation.z = 0.02
	return {"a": a, "upper": upper, "lower": lower, "foot": Vector3.ZERO, "from": Vector3.ZERO, "to": Vector3.ZERO, "t": 1.0}


## The camera: leather box with brass corners, folding bellows, a lens with a red iris that watches
## you, and a flash gun on an arm (dished reflector, big bulb).
func _build_camera() -> void:
	_pan = Node3D.new()
	_hub.add_child(_pan)
	_pan.position.y = 0.1
	A.cyl(_pan, 0.06, 0.06, Vector3(0, 0.03, 0), "metal", Color(0.3, 0.3, 0.3))
	A.box(_pan, Vector3(0.05, 0.12, 0.05), Vector3(0, 0.1, 0), "metal", Color(0.3, 0.3, 0.3), false, 0.2)
	_tilt = Node3D.new()
	_pan.add_child(_tilt)
	_tilt.position.y = 0.22
	A.cyl(_tilt, 0.025, 0.2, Vector3.ZERO, "brass", Color.WHITE, false, "x")   # tilt axle
	var dark := BODY.darkened(0.35)
	A.box(_tilt, Vector3(0.3, 0.24, 0.2), Vector3(0, 0.02, 0.07), "leather", BODY, false, 0.25)
	A.box(_tilt, Vector3(0.31, 0.03, 0.21), Vector3(0, 0.155, 0.07), "metal", Color(0.5, 0.5, 0.48), false, 0.2)
	A.box(_tilt, Vector3(0.31, 0.02, 0.21), Vector3(0, -0.105, 0.07), "metal", Color(0.5, 0.5, 0.48), false, 0.2)
	for x in [-0.152, 0.152]:
		for z in [-0.032, 0.172]:
			A.box(_tilt, Vector3(0.02, 0.25, 0.02), Vector3(x, 0.02, z), "brass", Color.WHITE, false, 0.2)
	A.cyl(_tilt, 0.035, 0.035, Vector3(0.09, 0.185, 0.1), "knurl")                 # winding knob
	A.cyl(_tilt, 0.012, 0.02, Vector3(-0.07, 0.18, 0.02), "brass")                 # shutter release
	A.box(_tilt, Vector3(0.06, 0.05, 0.09), Vector3(-0.08, 0.195, 0.1), "metal", Color(0.35, 0.35, 0.35), false, 0.2)   # viewfinder
	A.box(_tilt, Vector3(0.04, 0.03, 0.005), Vector3(-0.08, 0.195, 0.147), "metal", Color(0.05, 0.06, 0.08), false, 0.1)
	A.box(_tilt, Vector3(0.025, 0.12, 0.012), Vector3(-0.162, 0.0, 0.1), "leather", dark, false, 0.2)   # strap lug
	A.box(_tilt, Vector3(0.012, 0.3, 0.03), Vector3(0.165, -0.12, 0.1), "leather", dark, false, 0.2, Vector3(0, 0, 0.25))   # hanging strap
	A.cyl(_tilt, 0.03, 0.004, Vector3(0.05, 0.172, -0.01), "paper", Color(0.9, 0.88, 0.8))   # frame counter dial
	_tally_mat = glow_mat(Color(1, 0.12, 0.08), 0.0)
	var tally := A.sphere(_tilt, 0.012, Vector3(0.11, 0.17, -0.03), "metal")
	tally.material_override = _tally_mat
	# Bellows: pleats stepping down toward the lens.
	for k in 6:
		var w := 0.21 - k * 0.012
		A.box(_tilt, Vector3(w, w, 0.04), Vector3(0, 0.02, -0.05 - k * 0.04), "leather" if k % 2 == 0 else "rubber", dark, false, 0.2)
	A.box(_tilt, Vector3(0.2, 0.2, 0.025), Vector3(0, 0.02, -0.3), "metal", Color(0.3, 0.3, 0.3), false, 0.2)   # front standard
	for x in [-0.09, 0.09]:   # rails it slides out on
		A.box(_tilt, Vector3(0.015, 0.012, 0.38), Vector3(x, -0.09, -0.13), "metal", Color(0.55, 0.55, 0.55), false, 0.2)
	# Lens.
	_lens = Node3D.new()
	_tilt.add_child(_lens)
	_lens.position = Vector3(0, 0.02, -0.31)
	A.cyl(_lens, 0.07, 0.1, Vector3(0, 0, -0.05), "rubber", Color.WHITE, false, "z")
	A.cyl(_lens, 0.074, 0.016, Vector3(0, 0, -0.012), "brass", Color.WHITE, false, "z")
	A.cyl(_lens, 0.073, 0.026, Vector3(0, 0, -0.06), "knurl", Color.WHITE, false, "z")
	A.cyl(_lens, 0.076, 0.014, Vector3(0, 0, -0.1), "brass", Color.WHITE, false, "z")
	var iris := A.sphere(_lens, 0.024, Vector3(0, 0, -0.09), "metal")
	_iris_mat = glow_mat(Color(1, 0.15, 0.08), 1.5)
	iris.material_override = _iris_mat
	var glass := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.062
	gm.height = 0.05
	glass.mesh = gm
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(0.05, 0.07, 0.12, 0.55)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.metallic = 0.4
	g.roughness = 0.04
	glass.material_override = g
	_lens.add_child(glass)
	glass.position.z = -0.104
	# Flash gun on an arm: a dished reflector with a bulb in it.
	var arm_a := Vector3(-0.15, 0.12, 0.05)
	var arm_b := Vector3(-0.27, 0.34, -0.02)
	A.seg(_tilt, arm_a, arm_b, 0.014, 0.012, "metal", Color(0.5, 0.5, 0.5))
	A.sphere(_tilt, 0.022, arm_b, "brass")
	A.cyl(_tilt, 0.03, 0.12, arm_b + Vector3(0, -0.07, 0.03), "rubber", Color.WHITE)   # battery handle
	var dish := A.cyl(_tilt, 0.035, 0.09, arm_b + Vector3(0, 0, -0.08), "metal", Color(0.92, 0.92, 0.94), false, "y", 0.17)
	dish.rotation.x = -PI / 2.0   # wide end forward
	A.cyl(_tilt, 0.172, 0.008, arm_b + Vector3(0, 0, -0.126), "metal", Color(0.75, 0.75, 0.78), false, "z")   # rim
	var bulb := A.sphere(_tilt, 0.045, arm_b + Vector3(0, 0, -0.14), "metal")
	_bulb_mat = glow_mat(Color(0.75, 0.8, 0.9), 0.0)
	_bulb_mat.albedo_color = Color(0.6, 0.65, 0.72)
	bulb.material_override = _bulb_mat
	_flash = SpotLight3D.new()
	_flash.light_color = Color(0.92, 0.95, 1.0)
	_flash.light_energy = 0.0
	_flash.spot_range = 20.0
	_flash.spot_angle = 50.0
	_flash.shadow_enabled = true
	_flash.light_volumetric_fog_energy = 2.0
	_tilt.add_child(_flash)
	_flash.position = arm_b + Vector3(0, 0, -0.22)
	# A frayed cable from the camera down round the column.
	A.seg(_tilt, Vector3(0.12, -0.1, 0.16), Vector3(0.16, -0.32, 0.12), 0.008, 0.008, "rubber")
	A.seg(_hub, Vector3(0.16, 0.0, 0.12), Vector3(0.06, -0.3, 0.05), 0.008, 0.008, "rubber")


## Basis whose Y axis runs along dir (any roll).
static func _along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


## Two-bone IK: hip on the hub, foot on the floor, knee pushed up and out.
func _aim(leg: Dictionary) -> void:
	var a: float = leg.a
	var out := Vector3(sin(a), 0, cos(a))
	var hip := _hub.position + out * 0.13
	var foot := to_local(leg.foot)
	var d := foot - hip
	var dist := clampf(d.length(), 0.3, UPPER + LOWER - 0.02)
	var dir := d.normalized()
	var along := (UPPER * UPPER - LOWER * LOWER + dist * dist) / (2.0 * dist)
	var up := sqrt(maxf(0.0, UPPER * UPPER - along * along))
	var pole := (out * 0.5 + Vector3.UP).normalized()
	var perp := (pole - dir * pole.dot(dir)).normalized()
	var knee := hip + dir * along + perp * up
	leg.upper.transform = Transform3D(_along(knee - hip), hip)
	leg.lower.transform = Transform3D(_along(hip + dir * dist - knee), knee)


func _rest(leg: Dictionary) -> Vector3:
	var a: float = leg.a + rotation.y
	var lead := Vector3(velocity.x, 0, velocity.z) * 0.28
	return global_position + Vector3(sin(a), 0, cos(a)) * REACH + lead


func _plant_feet() -> void:
	for leg in _legs:
		leg.foot = _rest(leg)
		leg.t = 1.0
		_aim(leg)


## Feet stay planted in the world; the one furthest from where it should be steps over in an arc.
func _walk_legs(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var dur := 0.2 if speed < 3.0 else 0.11
	if _stepping >= 0:
		var leg: Dictionary = _legs[_stepping]
		leg.t = minf(1.0, leg.t + delta / dur)
		leg.foot = leg.from.lerp(leg.to, leg.t) + Vector3(0, sin(PI * leg.t) * 0.22, 0)
		if leg.t >= 1.0:
			_stepping = -1
			Sfx.play(self, "clack", leg.foot, -12.0, randf_range(1.3, 1.6))
	if _stepping < 0:
		var worst := -1
		var far := 0.32
		for i in 3:
			var leg: Dictionary = _legs[i]
			var off: float = (leg.foot - _rest(leg)).length()
			if off > 3.0:   # teleported (failsafe): just put it down
				leg.foot = _rest(leg)
			elif off > far:
				far = off
				worst = i
		if worst >= 0:
			var leg: Dictionary = _legs[worst]
			leg.from = leg.foot
			leg.to = _rest(leg)
			leg.to.y = global_position.y
			leg.t = 0.0
			_stepping = worst
	for leg in _legs:
		_aim(leg)
	# The head rides the gait: dips as a foot lifts, leans into the walk.
	var lift := sin(PI * _legs[_stepping].t) if _stepping >= 0 else 0.0
	_hub.position.y = lerpf(_hub.position.y, HUB_Y - lift * 0.05, minf(1.0, delta * 10.0))
	_hub.rotation.x = lerpf(_hub.rotation.x, -minf(speed, 6.0) * 0.03, minf(1.0, delta * 4.0))


# --- behaviour ---------------------------------------------------------------------------

## Is p looking at the camera (not just near it): the lens in the middle of their view, nothing between.
func _looked_at(p) -> bool:
	return seen_by(p, _lens.global_position, 0.8, 20.0)


func _physics_process(delta: float) -> void:
	_cool -= delta
	if is_instance_valid(_prey) and (_prey.dead or _prey.global_position.distance_to(global_position) > 32.0):
		_prey = null
	match state:
		LURK:
			var p = nearest_player(22.0)
			if _cool <= 0.0 and p != null and absf(p.global_position.y - global_position.y) < 2.5:
				_prey = p
				_creep = 7.5
				state = FOLLOW
			elif walk_to(_goal, WALK, delta, 4.0) == Vector3.ZERO:
				_goal = level.wander_point(global_position) if level else global_position
		FOLLOW:
			if _prey == null:
				state = LURK
			elif _looked_at(_prey) and _prey.global_position.distance_to(global_position) < 18.0:
				state = CHARGE
				_charge = 0.0
				_away = 0.0
				_whine.play()
			else:
				_follow(delta)
		CHARGE:
			stand_still(delta)
			if _prey == null:
				_cancel()
			else:
				face(_prey.global_position, delta, 6.0)
				_charge += delta
				_away = 0.0 if _looked_at(_prey) else _away + delta
				if _away > 0.12:   # they looked away in time
					_cancel()
				elif _charge >= CHARGE_T:
					_fire()
		FLEE:
			_flee_t += delta
			if walk_to(_goal, RUN, delta, 12.0) == Vector3.ZERO or _flee_t > 9.0:
				state = LURK
				_cool = 40.0
				_goal = global_position
	_animate(delta)
	_walk_legs(delta)


## Keep a spot behind them, out of sight, edging closer over time. Click now and then.
func _follow(delta: float) -> void:
	_creep = maxf(2.2, _creep - delta * 0.06)
	var p = _prey
	var back: Vector3 = p.global_position + p.global_transform.basis.z * _creep
	back.y = p.global_position.y
	var dist := global_position.distance_to(p.global_position)
	if back.distance_to(global_position) > 0.8:
		walk_to(back, CREEP if dist > _creep + 2.0 else WALK, delta, 6.0)
	else:
		stand_still(delta)
		face(p.global_position, delta, 4.0)
	_click -= delta
	if _click <= 0.0 and dist < 14.0:
		_click = randf_range(2.5, 5.5)
		Sfx.play(self, "shutter", _lens.global_position, -3.0, randf_range(0.9, 1.1))


func _cancel() -> void:
	state = FOLLOW
	_charge = 0.0
	_whine.stop()


## The flash: blinds whoever's looking, makes a racket, takes a picture, and runs.
func _fire() -> void:
	_whine.stop()
	state = FLEE
	_flee_t = 0.0
	photos_taken += 1
	Sfx.play(self, "flashbulb", _lens.global_position, 8.0)
	main.noise(global_position, 28.0)
	for p in alive_players():
		var d: float = p.global_position.distance_to(global_position)
		if seen_by(p, _lens.global_position, 0.25, 20.0):
			var face_on := 1.0 if _looked_at(p) else 0.55
			p.blind = maxf(p.blind, clampf(1.5 - d / 14.0, 0.45, 1.25) * face_on)
			if p == main.player:
				Sfx.play(p, "tinnitus", null, -10.0)
	var spot := global_position
	var subject = _prey
	_flash.light_energy = 6.0   # exposure for the picture...
	_bulb_mat.emission_energy_multiplier = 30.0
	var img: Image = null
	if subject != null:
		img = await _snap(subject)
	_flash.light_energy = 70.0   # ...then the full burst
	var tw := create_tween()
	tw.tween_property(_flash, "light_energy", 0.0, 0.35).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_bulb_mat, "emission_energy_multiplier", 0.0, 1.2)
	_goal = _away_from(subject)
	await get_tree().create_timer(0.5, false).timeout
	if is_instance_valid(level):
		_drop_photo(spot, img)


## Somewhere far from them to run to.
func _away_from(p) -> Vector3:
	if level == null or level.facility == null or p == null:
		return global_position
	var best := global_position
	var bd := -1.0
	for i in 8:
		var q: Vector3 = level.facility.random_point(level.rng, true)
		var d: float = q.distance_to(p.global_position)
		if absf(q.y - global_position.y) < 2.5 and d > bd:
			bd = d
			best = q
	return best


## The picture, from the lens, while the flash is lit. Nothing to render headless.
func _snap(p) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 270)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 48.0
	vp.add_child(cam)
	var at: Vector3 = p.global_position + Vector3(0, 1.2, 0)
	cam.look_at_from_position(_lens.global_position + (at - _lens.global_position).normalized() * 0.15, at)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	# Old flash film: warm, a little faded, harsh falloff to the corners, a touch of grain.
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var l := c.get_luminance()
			var v := Vector2(float(x) / w - 0.5, float(y) / h - 0.48).length()
			var k := clampf(1.18 - v * 1.25, 0.0, 1.0)
			var o := Color(c.r * 0.78 + l * 0.3, c.g * 0.74 + l * 0.27, c.b * 0.62 + l * 0.2) * (0.35 + 0.85 * k)
			var g := randf_range(-0.025, 0.025)
			img.set_pixel(x, y, Color(o.r * 0.94 + 0.05 + g, o.g * 0.94 + 0.04 + g, o.b * 0.94 + 0.03 + g))
	img.generate_mipmaps()
	return img


## A polaroid flutters down where it stood: the photograph of you. Pick it up and look.
func _drop_photo(at: Vector3, img: Image) -> void:
	var p = main.spawn_item("PHOTO", Vector3(at.x, at.y + 0.9, at.z), -1.0, level)
	p.add_to_group("photos")
	p.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
	p.linear_velocity = Vector3(randf_range(-0.4, 0.4), -0.5, randf_range(-0.4, 0.4))
	p.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-3, 3), randf_range(-2, 2))
	p.linear_damp = 3.0   # paper: drifts down instead of dropping
	p.angular_damp = 2.0
	var stamp := "STN %s   %02d:%02d" % [main.stop.get("letter", "?"), int(main.hours) % 24, int(fmod(main.hours, 1.0) * 60.0)]
	var e := {"stamp": stamp}
	if img != null:
		e.tex = ImageTexture.create_from_image(img)
	p.set_extra(e)
	Sfx.play(p, "rustle", p.global_position, -8.0, 1.4)


func _animate(delta: float) -> void:
	# The head tracks whoever it's after; idle, it looks around.
	var t := Time.get_ticks_msec() / 1000.0
	var want_yaw := sin(t * 0.5) * 0.8
	var want_pitch := sin(t * 0.37) * 0.15
	if _prey != null and state != FLEE:
		var to: Vector3 = (_prey.global_position + Vector3(0, 1.5, 0)) - _tilt.global_position
		var local := global_transform.basis.inverse() * to
		want_yaw = atan2(-local.x, -local.z)
		want_pitch = atan2(local.y, Vector2(local.x, local.z).length())
	_pan.rotation.y = lerp_angle(_pan.rotation.y, want_yaw, minf(1.0, delta * (9.0 if state == CHARGE else 3.0)))
	_tilt.rotation.x = lerpf(_tilt.rotation.x, want_pitch, minf(1.0, delta * 4.0))
	# The iris flares as the flash charges; the tally lamp blinks while it's following.
	_iris_mat.emission_energy_multiplier = 1.2 + (_charge / CHARGE_T) * 10.0 if state == CHARGE else 1.2 + sin(t * 2.0) * 0.4
	_bulb_mat.emission_energy_multiplier = maxf(_bulb_mat.emission_energy_multiplier, (_charge / CHARGE_T) * 4.0 if state == CHARGE else 0.0)
	_tally_mat.emission_energy_multiplier = 3.0 if state in [FOLLOW, CHARGE] and fmod(t, 1.0) < 0.5 else 0.0


# --- hits and death ---

func react_to_hit(by) -> void:
	_whine.stop()
	_charge = 0.0
	state = FLEE   # it doesn't fight: it runs
	_flee_t = 0.0
	_goal = _away_from(by)


## The legs splay out and give way, the head slams down on the floor, the bulb pops.
func death_anim() -> void:
	_whine.stop()
	_tally_mat.emission_energy_multiplier = 0.0
	Sfx.play(self, "flashbulb", _lens.global_position, -4.0, 1.6)
	var feet0: Array = _legs.map(func(l): return l.foot)
	var hub0 := _hub.position.y
	var tilt0 := _tilt.rotation.x
	var collapse := func(t: float):
		for i in 3:
			var leg: Dictionary = _legs[i]
			var a: float = leg.a + rotation.y
			leg.foot = feet0[i] + Vector3(sin(a), 0, cos(a)) * 0.55 * t
			_aim(leg)
		_hub.position.y = lerpf(hub0, 0.32, t)
		_hub.rotation.x = 0.25 * t
		_tilt.rotation.x = lerpf(tilt0, -0.9, t)
		_iris_mat.emission_energy_multiplier = 1.2 * (1.0 - t)
	var tw := create_tween()
	tw.tween_method(collapse, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(0.35, false).timeout.connect(Sfx.play.bind(self, "clank", global_position, 2.0, 0.8))
	get_tree().create_timer(0.5, false).timeout.connect(Sfx.play.bind(self, "clack", global_position, 0.0, 1.4))


func is_hunting() -> bool:
	return state == FOLLOW or state == CHARGE
