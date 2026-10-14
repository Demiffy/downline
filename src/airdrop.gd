# A Bureau airdrop, start to finish (hazards.gd starts one; every machine plays it from the same
# landing spot and heading, so everyone sees the same drop):
#   the radio squawks the bearing; a twin-engine cargo plane comes in low over the hills, props
#   turning, nav lights and beacon blinking, the drone of its engines swelling and dropping past you
#   (doppler); over the spot the crate goes out of the cargo door, falls a moment, the drogue pulls
#   the main canopy out and it blossoms open with a whump; it comes down swinging under the gored
#   canopy, a strobe flashing on the crate, drifting onto the spot; it lands in a burst of dust, the
#   canopy sags, collapses and drapes over the ground downwind; the flare on the crate pops, spits
#   sparks and sends a column of red smoke up that you can see from anywhere.
#   The crate: a plywood box with steel corners on a skid and crush padding, cargo straps both ways,
#   the Bureau's stencils. Pry it (loud): the straps snap, the lid flies up and the sides fall open.
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const Data = preload("res://src/data.gd")
const Blast = preload("res://src/blast.gd")

const ALT := 115.0       # the plane's height over the spot
const SPEED := 52.0      # the plane, m/s
const LEAD := 950.0      # how far out it comes in from
const FALL := 1.3        # seconds of free fall before the canopy opens
const SINK := 6.5        # m/s under the canopy
const PLY := Color(0.62, 0.52, 0.38)
const STRAP := Color(0.85, 0.66, 0.16)
const OLIVE := Color(0.34, 0.38, 0.27)

var hz          # hazards.gd
var level
var main
var land := Vector3.ZERO
var heading := Vector3.FORWARD
var crate: Node3D        # at the landing spot all along (so its interactable keys the same everywhere)
var body: Node3D         # what falls: the crate's visible body, offset up from crate until it lands
var rig: Node3D          # canopy and lines, hung from a point above the body; swings
var canopy: MeshInstance3D
var plane: Node3D
var _props: Array = []
var _blinks: Array = []  # [node, period, duty]
var _strobe: OmniLight3D
var _t := 0.0
var _over := 0.0         # when the plane is over the spot
var _phase := "inbound"
var _deploy := Vector3.ZERO
var _vel := Vector3.ZERO
var _sway := Vector2.ZERO
var _sway_v := Vector2.ZERO
var _drone: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var crash := false       # now and then the plane doesn't make it home (decided from the drop's own dice: the same everywhere)
var _fail := INF         # when its engine went
var _crashed := false
var _trails: Array = []   # [emitter, where on the plane]: smoke and flame streaming off it, in world space
var _fire: Node3D
var _drone_pitch := 1.0
var _next_pop := 0.0
var _boom: Node3D        # the crash site
var _debris: Array = []  # [chunk, velocity, its trail and flame]
var crash_at := Vector3.INF
const CRASH_CHANCE := 0.12
const DIVE := 13.0       # seconds from the engine going to the ground


func setup(hazards, at: Vector3, spin: float) -> void:
	hz = hazards
	level = hazards.level
	main = hazards.main
	land = at
	heading = Vector3(sin(spin), 0, cos(spin))
	_rng.seed = hash([at.x, at.z, spin])
	level.add_child(self)
	var pace := Data.pace()
	_over = (LEAD / SPEED) * pace
	crash = Engine.has_meta("force_crash") or _rng.randf() < CRASH_CHANCE
	_plane()
	if crash:
		_burning()
	_crate()
	var rel: Vector3 = land - level.elevator_pos
	main.hud.alert("BUREAU AIRDROP INBOUND   watch the sky, %s of the lift" % hz._compass(rel))
	Sfx.play(main, "beep", null, -10.0, 0.7)


# --- the plane ------------------------------------------------------------------------------------

## A twin-engined cargo plane in olive drab: a long round fuselage tapering to the tail, low wings with
## two engine nacelles and three-bladed props, the fin and tailplane, the glazed nose and cockpit, an
## open cargo door on the left, the Bureau's marks; nav lights, a red beacon. Nose along -z.
func _plane() -> void:
	plane = Node3D.new()
	add_child(plane)
	var c := OLIVE
	A.seg(plane, Vector3(0, 0, -7.5), Vector3(0, 0, 5.0), 1.25, 1.2, "metal", c)          # the fuselage
	A.seg(plane, Vector3(0, 0, 5.0), Vector3(0, 0.45, 10.5), 1.2, 0.3, "metal", c)        # tapering to the tail
	A.sphere(plane, 1.25, Vector3(0, 0, -7.5), "metal", c, 0.0, 0.9).scale = Vector3(1, 1, 1.5)   # the nose
	A.sphere(plane, 0.7, Vector3(0, 0.55, -8.0), "metal", Color(0.12, 0.15, 0.16), 0.0, 0.7)   # the cockpit glazing
	for s in [-1.0, 1.0]:
		A.box(plane, Vector3(0.55, 0.32, 0.05), Vector3(s * 0.9, 0.55, -7.2), "metal", Color(0.12, 0.15, 0.16), false, 1.0, Vector3(0, s * 0.5, 0))
		for k in 6:   # cabin windows
			A.box(plane, Vector3(0.05, 0.28, 0.32), Vector3(s * 1.22, 0.35, -4.5 + k * 1.2), "metal", Color(0.1, 0.12, 0.12), false)
	A.box(plane, Vector3(0.06, 1.7, 1.5), Vector3(-1.22, -0.05, 2.6), "metal", Color(0.04, 0.04, 0.04), false)   # the open cargo door
	A.box(plane, Vector3(18.0, 0.28, 3.0), Vector3(-10.4, -0.55, -2.2), "metal", c, false, 2.0, Vector3(0, 0, 0.06))   # wings, a little dihedral
	A.box(plane, Vector3(18.0, 0.28, 3.0), Vector3(10.4, -0.55, -2.2), "metal", c, false, 2.0, Vector3(0, 0, -0.06))
	A.box(plane, Vector3(4.2, 0.36, 3.4), Vector3(0, -0.75, -2.2), "metal", c, false)
	for s in [-1.0, 1.0]:   # engines: nacelle, cowling, a three-bladed prop
		var e := Vector3(s * 5.2, -0.35, -3.6)
		A.seg(plane, e, e + Vector3(0, -0.1, 4.0), 0.75, 0.4, "metal", c.darkened(0.1))
		A.cyl(plane, 0.8, 0.9, e + Vector3(0, 0, -0.1), "metal", Color(0.2, 0.2, 0.2), false, "z")
		A.sphere(plane, 0.3, e + Vector3(0, 0, -0.75), "metal", Color(0.75, 0.62, 0.2))   # the spinner
		var hub := Node3D.new()
		plane.add_child(hub)
		hub.position = e + Vector3(0, 0, -0.75)
		for b in 3:
			var blade := A.box(hub, Vector3(0.22, 1.7, 0.05), Vector3(0, 0.95, 0), "metal", Color(0.12, 0.12, 0.12), false)
			blade.rotation.z = 0.0
			var arm := Node3D.new()
			hub.add_child(arm)
			arm.rotation.z = TAU * b / 3.0
			blade.reparent(arm, false)
		_props.append(hub)
		var disc := MeshInstance3D.new()   # the blur of the blades
		var cm := CylinderMesh.new()
		cm.top_radius = 1.85
		cm.bottom_radius = 1.85
		cm.height = 0.02
		disc.mesh = cm
		var dm := StandardMaterial3D.new()
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.albedo_color = Color(0.2, 0.2, 0.2, 0.18)
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc.material_override = dm
		plane.add_child(disc)
		disc.position = hub.position
		disc.rotation.x = PI / 2.0
		var nav := A.glow(plane, Vector3(0.25, 0.15, 0.25), Vector3(s * 19.3, -0.4, -2.2), Color(1, 0.1, 0.1) if s < 0 else Color(0.1, 1, 0.3), 6.0)
		_blinks.append([nav, 1.0, 1.0])
		A.box(plane, Vector3(0.8, 0.8, 0.02), Vector3(s * 1.23, 0.2, -1.4), "metal", Color(0.85, 0.82, 0.74), false, 1.0, Vector3(0, PI / 2.0, 0))   # the roundel's panel
		B.label(plane, "B.R.M.", Vector3(s * 1.255, 0.2, -1.4), 140, Color(0.15, 0.13, 0.1), "stencil", 0.004, Vector2(0.68, 0.3)).rotation.y = s * PI / 2.0
	A.box(plane, Vector3(0.18, 3.0, 2.6), Vector3(0, 1.9, 9.6), "metal", c, false, 1.0, Vector3(-0.35, 0, 0))   # the fin
	A.box(plane, Vector3(7.5, 0.16, 1.8), Vector3(0, 0.45, 9.9), "metal", c, false)   # the tailplane
	var beacon := A.glow(plane, Vector3(0.3, 0.2, 0.3), Vector3(0, 1.32, -1.0), Color(1, 0.15, 0.05), 8.0)
	_blinks.append([beacon, 1.2, 0.15])
	var tail := A.glow(plane, Vector3(0.2, 0.2, 0.2), Vector3(0, 0.6, 10.8), Color.WHITE, 6.0)
	_blinks.append([tail, 1.0, 1.0])
	var beam := OmniLight3D.new()
	beam.light_color = Color(1, 0.2, 0.1)
	beam.omni_range = 18.0
	plane.add_child(beam)
	beam.position = beacon.position
	_blinks.append([beam, 1.2, 0.15])
	plane.scale = Vector3.ONE * 1.15
	_drone = AudioStreamPlayer3D.new()
	_drone.stream = Sfx.stream("plane_loop")
	_drone.bus = "World"
	_drone.unit_size = 70.0
	_drone.max_distance = 1400.0
	_drone.volume_db = 4.0
	_drone.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP
	_drone.attenuation_filter_cutoff_hz = 3000.0
	_drone.attenuation_filter_db = -14.0
	plane.add_child(_drone)
	_drone.play(_rng.randf() * 5.0)
	_place_plane()


func _plane_pos(t: float) -> Vector3:
	var s := (t - _over) * SPEED / Data.pace()
	var p := land + Vector3(0, ALT, 0) + heading * s
	if t > _fail:   # going down: losing height faster and faster, slewing off to one side
		var u := (t - _fail) / (DIVE * Data.pace())
		p.y -= (ALT + 30.0) * u * u
		p += Vector3(-heading.z, 0, heading.x) * 90.0 * u * u
	return p


func _place_plane() -> void:
	plane.position = _plane_pos(_t)
	var bank := sin(_t * 0.6) * 0.03
	var nose := 0.02
	if _t > _fail:
		var u := (_t - _fail) / (DIVE * Data.pace())
		bank = -0.25 - u * 0.9 + sin(_t * 3.0) * 0.06   # (rolling over onto the dead engine, fighting it)
		nose = -u * 0.6
	plane.rotation = Vector3(nose, atan2(-heading.x, -heading.z) - (0.6 * pow((_t - _fail) / (DIVE * Data.pace()), 2.0) if _t > _fail else 0.0), bank)
	if crash:   # struggling: rolling and yawing about, rising and sinking as the pilot fights it
		plane.position.y += sin(_t * 1.1) * 2.2 + sin(_t * 2.9) * 0.6
		plane.rotation += Vector3(sin(_t * 1.3) * 0.05, sin(_t * 0.8) * 0.06, sin(_t * 1.9) * 0.14 + sin(_t * 4.7) * 0.05)
	for tr in _trails:
		tr[0].global_position = plane.to_global(tr[1])


# --- the crate --------------------------------------------------------------------------------------

func _crate() -> void:
	crate = Node3D.new()
	level.add_child(crate)
	crate.position = land
	crate.rotation.y = atan2(heading.x, heading.z)
	body = Node3D.new()
	crate.add_child(body)
	_build_box(body)
	body.visible = false
	rig = Node3D.new()
	body.add_child(rig)
	rig.position = Vector3(0, 1.25, 0)   # the risers meet here, over the box
	rig.visible = false
	_build_canopy(rig)
	_strobe = OmniLight3D.new()
	_strobe.light_color = Color(1, 0.95, 0.9)
	_strobe.omni_range = 9.0
	body.add_child(_strobe)
	_strobe.position = Vector3(0.5, 1.15, 0)
	var lamp := A.glow(body, Vector3(0.08, 0.08, 0.08), Vector3(0.5, 1.12, 0), Color(1, 0.95, 0.9), 0.0)
	_blinks.append([_strobe, 0.9, 0.08])
	_blinks.append([lamp, 0.9, 0.08])


## The box: a plywood crate with steel corners on a skid with crush padding, strapped both ways with
## yellow cargo straps through buckles, stencilled; the flare canister on one end. Sides (and lid) are
## their own nodes so they fall open when it's pried.
func _build_box(r: Node3D) -> void:
	var w := 1.3
	var d := 0.9
	var h := 0.85
	A.box(r, Vector3(w + 0.1, 0.1, d + 0.1), Vector3(0, 0.05, 0), "wood", Color(0.52, 0.42, 0.3), false, 0.6)   # the skid
	for k in 3:
		A.box(r, Vector3(0.1, 0.12, d + 0.1), Vector3(-0.55 + k * 0.55, 0.1, 0), "wood", Color(0.45, 0.36, 0.26), false, 0.6)   # skid runners
	A.box(r, Vector3(w, 0.16, d), Vector3(0, 0.22, 0), "paper", Color(0.75, 0.66, 0.48), false, 0.15)   # honeycomb padding
	for k in 6:
		A.box(r, Vector3(w + 0.004, 0.008, d + 0.004), Vector3(0, 0.155 + k * 0.025, 0), "paper", Color(0.6, 0.52, 0.38), false, 0.3)
	var y0 := 0.3
	var sides := []
	for spec in [[Vector3(0, 0, -d / 2.0), 0.0, w], [Vector3(0, 0, d / 2.0), PI, w], [Vector3(-w / 2.0, 0, 0), -PI / 2.0, d], [Vector3(w / 2.0, 0, 0), PI / 2.0, d]]:
		var hinge := Node3D.new()   # hinged along its bottom edge, its face outward (+z of the hinge is outward... -z)
		r.add_child(hinge)
		hinge.position = spec[0] + Vector3(0, y0, 0)
		hinge.rotation.y = spec[1]
		hinge.set_meta("live", true)
		var span: float = spec[2]
		A.box(hinge, Vector3(span, h, 0.035), Vector3(0, h / 2.0, 0), "wood", PLY, false, 0.7)
		for e in [-1.0, 1.0]:   # battens and steel corners
			A.box(hinge, Vector3(0.07, h, 0.05), Vector3(e * (span / 2.0 - 0.04), h / 2.0, -0.02), "wood", PLY.darkened(0.2), false, 0.5)
			A.box(hinge, Vector3(0.1, 0.1, 0.05), Vector3(e * (span / 2.0 - 0.03), h - 0.05, -0.025), "metal", Color(0.45, 0.45, 0.43), false)
			A.box(hinge, Vector3(0.1, 0.1, 0.05), Vector3(e * (span / 2.0 - 0.03), 0.05, -0.025), "metal", Color(0.45, 0.45, 0.43), false)
		A.box(hinge, Vector3(span - 0.14, 0.07, 0.05), Vector3(0, h / 2.0, -0.02), "wood", PLY.darkened(0.2), false, 0.5)
		sides.append(hinge)
	B.label(sides[0], "B.R.M.  AIRDROP", Vector3(0, h * 0.68, -0.05), 52, Color(0.12, 0.1, 0.08), "stencil", 0.0045).rotation.y = PI
	B.label(sides[0], "THIS SIDE UP", Vector3(0, h * 0.28, -0.05), 34, Color(0.12, 0.1, 0.08), "stencil", 0.0042).rotation.y = PI
	B.label(sides[1], "SUPPLIES  -  DO NOT DROP", Vector3(0, h * 0.68, -0.05), 40, Color(0.12, 0.1, 0.08), "stencil", 0.0042).rotation.y = PI
	var lid := Node3D.new()
	r.add_child(lid)
	lid.position = Vector3(0, y0 + h, d / 2.0)
	lid.set_meta("live", true)
	A.box(lid, Vector3(w + 0.04, 0.04, d + 0.04), Vector3(0, 0.02, -d / 2.0), "wood", PLY.lightened(0.04), false, 0.7)
	for k in 3:
		A.box(lid, Vector3(w + 0.04, 0.03, 0.08), Vector3(0, 0.055, -0.12 - k * 0.33), "wood", PLY.darkened(0.2), false, 0.5)
	A.box(lid, Vector3(0.36, 0.006, 0.24), Vector3(-0.3, 0.075, -0.5), "paper", Color(0.88, 0.85, 0.74), false, 0.3)   # the manifest
	# Inside: a floor, a bed of shredded paper, foam blocks wedged in the corners (the loot sits in it).
	A.box(r, Vector3(w - 0.06, 0.03, d - 0.06), Vector3(0, y0 + 0.015, 0), "wood", PLY.darkened(0.25), false, 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 70:
		var at := Vector3(rng.randf_range(-w / 2.0 + 0.08, w / 2.0 - 0.08), y0 + 0.05 + rng.randf() * 0.12, rng.randf_range(-d / 2.0 + 0.08, d / 2.0 - 0.08))
		A.box(r, Vector3(rng.randf_range(0.08, 0.2), 0.012, 0.025), at, "paper", Color(0.82, 0.74, 0.55).darkened(rng.randf() * 0.25), false, 0.2, Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6))
	for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		A.box(r, Vector3(0.16, 0.3, 0.16), Vector3(c.x * (w / 2.0 - 0.11), y0 + 0.17, c.z * (d / 2.0 - 0.11)), "plastic", Color(0.3, 0.32, 0.34), false, 0.3)
	var straps := Node3D.new()   # the straps, both ways round, and their buckles
	r.add_child(straps)
	for k in [-0.35, 0.35]:
		A.box(straps, Vector3(0.07, h + 0.12, d + 0.07), Vector3(k, y0 + h / 2.0 + 0.02, 0), "canvas", STRAP, false, 0.4)
		A.box(straps, Vector3(0.1, 0.09, 0.03), Vector3(k, y0 + h * 0.55, -d / 2.0 - 0.045), "metal", Color(0.7, 0.7, 0.68), false)
	A.box(straps, Vector3(w + 0.07, h + 0.12, 0.07), Vector3(0, y0 + h / 2.0 + 0.02, 0), "canvas", STRAP, false, 0.4)
	for s in [-1.0, 1.0]:   # the risers' clevises on the lid
		A.ring(straps, 0.06, 0.04, Vector3(s * 0.5, y0 + h + 0.08, 0), "metal", Color(0.6, 0.6, 0.58), Vector3(PI / 2.0, 0, 0))
	var can := A.cyl(sides[3], 0.07, 0.36, Vector3(-0.2, 0.45, -0.1), "metal", Color(0.75, 0.16, 0.1))   # the flare canister, strapped to an end
	A.cyl(sides[3], 0.072, 0.04, Vector3(-0.2, 0.65, -0.1), "metal", Color(0.3, 0.3, 0.3))
	A.box(sides[3], Vector3(0.18, 0.04, 0.03), Vector3(-0.2, 0.4, -0.06), "metal", Color(0.4, 0.4, 0.38), false)
	r.set_meta("parts", {"sides": sides, "lid": lid, "straps": straps, "can": can})


## The canopy: a shallow dome of twelve gores, orange and white about a vent, a skirt round its rim,
## the suspension lines down to the risers. Built hanging over rig's origin.
func _build_canopy(r: Node3D) -> void:
	var img := Image.create(48, 4, false, Image.FORMAT_RGBA8)
	for x in 48:
		for y in 4:
			img.set_pixel(x, y, Color(0.92, 0.42, 0.12) if (x / 4) % 2 == 0 else Color(0.92, 0.9, 0.84))
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	canopy = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.4
	sm.height = 3.0
	sm.is_hemisphere = true
	sm.radial_segments = 24
	sm.rings = 8
	canopy.mesh = sm
	canopy.material_override = m
	r.add_child(canopy)
	canopy.position = Vector3(0, 6.0, 0)
	A.ring(canopy, 3.42, 3.3, Vector3(0, 0.02, 0), "canvas", Color(0.8, 0.78, 0.7))   # the skirt
	A.cyl(canopy, 0.35, 0.05, Vector3(0, 1.5, 0), "canvas", Color(0.1, 0.1, 0.1))   # the vent
	for k in 12:   # lines from the rim to the risers
		var a := TAU * k / 12.0
		A.seg(r, Vector3(cos(a) * 3.35, 6.0, sin(a) * 3.35), Vector3(cos(a) * 0.12, 0.0, sin(a) * 0.12), 0.012, 0.012, "fabric", Color(0.85, 0.85, 0.8))
	for s in [-1.0, 1.0]:   # the risers down to the box
		A.seg(r, Vector3(s * 0.12, 0, 0), Vector3(s * 0.5, -0.32, 0), 0.025, 0.025, "canvas", STRAP.darkened(0.2))


# --- the drop -----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	var pace := Data.pace()
	if is_instance_valid(plane):
		_place_plane()
		for h in _props:
			h.rotation.z += delta * 55.0
		if crash:
			_sputter()
		if crash and _fail == INF and _t > _over + 3.5 * pace:
			_engine_fails()
		if _t > _fail and not _crashed and plane.position.y <= _ground_at(plane.position):
			_crash_down()
		elif _t > _over * 2.2 and not crash:
			plane.queue_free()
	for b in _blinks:
		if is_instance_valid(b[0]):
			var on: bool = fmod(_t, b[1]) < b[1] * b[2]
			if b[0] is OmniLight3D:
				b[0].light_energy = 6.0 if on else 0.0
			else:
				b[0].visible = on
	_fly_debris(delta)
	match _phase:
		"inbound":
			if _t >= _over:   # out of the door
				_phase = "fall"
				_deploy = _plane_pos(_t) + heading * -9.0 + Vector3(0, -1.5, 0)
				_vel = heading * SPEED / pace * 0.9
				body.visible = true
				body.global_position = level.to_global(_deploy)
				Sfx.play(self, "clunk", body.global_position, 6.0, 0.7)
				var rush := AudioStreamPlayer3D.new()   # (rides down with it)
				rush.stream = Sfx.stream("drop_fall")
				rush.bus = "World"
				rush.unit_size = 25.0
				rush.max_distance = 400.0
				rush.volume_db = 6.0
				body.add_child(rush)
				rush.play()
				rush.finished.connect(rush.queue_free)
		"fall":
			_vel += Vector3(0, -9.8, 0) * delta / pace
			_vel *= exp(-1.6 * delta / pace)
			body.position += crate.basis.inverse() * _vel * delta
			if _t > _over + FALL * pace:   # the drogue pulls the canopy out: it blossoms
				_phase = "canopy"
				rig.visible = true
				canopy.scale = Vector3(0.05, 0.3, 0.05)
				var tw := create_tween()
				tw.tween_property(canopy, "scale", Vector3(1.15, 0.8, 1.15), 0.45 * pace).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.tween_property(canopy, "scale", Vector3(1.0, 1.0, 1.0), 0.6 * pace).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
				Sfx.play(self, "chute_pop", body.global_position + Vector3(0, 6, 0), 8.0, 1.0)
				_deploy = body.position
				_vel = Vector3(_vel.x, -SINK, _vel.z) * Vector3(0.3, 1, 0.3)
				_sway_v = Vector2(1.6, 0.6)
		"canopy":   # down at its sinking speed, the drift carrying it onto the spot, swinging
			var hgt: float = body.position.y
			var k := 1.0 - exp(-delta / pace * 0.5)
			var flat := Vector2(body.position.x, body.position.z)
			flat = flat.lerp(Vector2.ZERO, k * clampf(1.0 - hgt / 120.0, 0.2, 1.0))   # (onto the spot as it comes down)
			body.position = Vector3(flat.x, hgt - SINK * delta / pace, flat.y)
			_sway_v += -_sway * 2.2 * delta / pace
			_sway_v *= exp(-0.25 * delta / pace)
			_sway += _sway_v * delta / pace
			body.rotation = Vector3(_sway.x * 0.18, sin(_t * 0.3) * 0.4, _sway.y * 0.18)
			rig.rotation = Vector3(-_sway.x * 0.06, 0, -_sway.y * 0.06)
			if body.position.y <= 0.0:
				_landed()
		"down":
			pass


func _landed() -> void:
	_phase = "down"
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	var at: Vector3 = crate.global_position
	Sfx.play(self, "drop_land", at, 10.0, 1.0)
	if main.net.authority():
		main.noise(at, 32.0)
	main.player.shake(clampf(1.0 - main.player.global_position.distance_to(at) / 30.0, 0.0, 1.0) * 0.03)
	var dust: CPUParticles3D = hz._particles(Color(0.7, 0.62, 0.5, 0.55), 1.6, 40, 2.5, Vector3.UP, 80.0, 1.5, 4.0, Vector3(0, -0.6, 0))
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.reparent(self)
	dust.global_position = at + Vector3(0, 0.3, 0)
	dust.emitting = true
	_blinks = _blinks.filter(func(b): return is_instance_valid(b[0]))
	for b in _blinks:   # (the strobe's done its job)
		if b[0] == _strobe or (b[0] as Node).get_parent() == body:
			b[0].visible = false
	_blinks = _blinks.filter(func(b): return b[0] != _strobe and (b[0] as Node).get_parent() != body)
	# The canopy collapses: with the weight off it sags and spills its air, tips over downwind, falls
	# and settles flat on the sand past the box, rippling; the lines go slack along the ground.
	rig.reparent(crate, true)
	canopy.reparent(crate, true)
	var p0: Vector3 = canopy.position
	var lie := Vector3(0, 0, 6.8)   # (+z is downwind: the crate faces the plane's way)
	var g: Vector3 = level.to_local(crate.to_global(lie))
	lie.y = level.ground_y(g.x, g.z) - crate.position.y + 0.15
	var tw := create_tween()
	tw.tween_property(canopy, "scale", Vector3(1.08, 0.55, 1.08), 0.7).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(canopy, "position", p0 + Vector3(0, -1.2, 0.4), 0.7).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(rig, "rotation", Vector3.ZERO, 0.7)
	tw.tween_property(canopy, "rotation:x", 1.05, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # tipping over
	tw.parallel().tween_property(canopy, "position", Vector3(0, lie.y + 2.6, 4.6), 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(canopy, "scale", Vector3(1.0, 0.4, 0.95), 1.3)
	tw.tween_property(canopy, "rotation:x", 0.1, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # down flat
	tw.parallel().tween_property(canopy, "position", lie, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(canopy, "scale", Vector3(1.0, 0.07, 0.85), 0.5)
	tw.tween_property(canopy, "scale", Vector3(1.04, 0.2, 0.88), 0.35).set_trans(Tween.TRANS_SINE)   # the last air rippling out
	tw.tween_property(canopy, "scale", Vector3(1.0, 0.13, 0.86), 0.6).set_trans(Tween.TRANS_SINE)
	var lt := create_tween()   # the lines: slack, then laid down along the ground running out to it
	lt.tween_property(rig, "scale", Vector3(1, 0.85, 1), 1.4).set_trans(Tween.TRANS_SINE)
	lt.tween_property(rig, "rotation:x", PI / 2.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	lt.parallel().tween_property(rig, "scale", Vector3(1, 1.1, 0.05), 1.1)
	lt.parallel().tween_property(rig, "position:y", lie.y * 0.5 + 0.12, 1.1)
	_flare(at)
	var parts: Dictionary = body.get_meta("parts")
	var it := B.interactable(crate, Vector3(1.4, 1.2, 1.0), Vector3(0, 0.6, 0), Color(0, 0, 0, 0), "Pry open the airdrop crate (LOUD)", _open.bind(), 1.5)
	it.set_meta("crate", true)
	crate.add_to_group("scan_targets")
	crate.set_meta("scan_name", "AIRDROP")
	crate.set_meta("lid", parts.lid)   # (hazards and saves look for these)


## The flare pops: a hiss, sparks spitting, a flickering red light, and a column of red smoke going up
## and leaning with the wind; it burns a long while, then gutters.
func _flare(at: Vector3) -> void:
	var parts: Dictionary = body.get_meta("parts")
	var top: Vector3 = (parts.can as Node3D).global_position + Vector3(0, 0.25, 0)
	Sfx.play(self, "flashbulb", top, 0.0, 0.6)
	var light := B.omni(crate, crate.to_local(top) + Vector3(0, 0.3, 0), Color(1, 0.18, 0.08), 3.0, 18.0, false)
	hz._flares.append(light)
	var sparks: CPUParticles3D = hz._particles(Color(1, 0.6, 0.3, 1.0), 0.08, 50, 0.7, Vector3.UP, 35.0, 2.0, 4.5, Vector3(0, -6.0, 0))
	sparks.reparent(self)
	sparks.global_position = top
	sparks.emitting = true
	var wind := Vector3(-heading.z, 0, heading.x) * 0.5
	var smoke := _smoke(Color(0.86, 0.2, 0.14), Color(0.75, 0.32, 0.26), 90, 14.0, 0.8, 7.0, Vector3(0, 3.0, 0), wind * 0.3 + Vector3(0, 0.25, 0))
	add_child(smoke)
	smoke.global_position = top
	smoke.emitting = true
	var hiss: AudioStreamPlayer3D = hz._loop3d("flare", top, -6.0, 1.0)
	hiss.reparent(self)
	hiss.max_distance = 40.0
	get_tree().create_timer(240.0, false).timeout.connect(func():   # it burns out
		if is_instance_valid(sparks):
			sparks.emitting = false
		if is_instance_valid(smoke):
			smoke.emitting = false
		if is_instance_valid(hiss):
			hiss.create_tween().tween_property(hiss, "volume_db", -60.0, 4.0)
		if is_instance_valid(light):
			hz._flares.erase(light)
			light.create_tween().tween_property(light, "light_energy", 0.0, 4.0))


## Soft round puffs (blast.gd's, unshaded: lit smoke washes out to tan in the desert sun): `amount` of them living
## `life` seconds, growing from `s0` to `s1` metres, launched at `v`, drifting with `drift`; coloured
## from `a` (fresh) to `b` (old), fading in and out.
func _smoke(a: Color, b: Color, amount: int, life: float, s0: float, s1: float, v: Vector3, drift: Vector3, world := false) -> GPUParticles3D:
	a = _lin(a)   # (written as they should look; particle colours are linear: 0.2 grey showed half white)
	b = _lin(b)
	var p := GPUParticles3D.new()   # (GPU: the CPU kind drew a stray black puff at the emitter)
	Blast._puff_material(p, true)
	var pm: StandardMaterial3D = (p.draw_pass_1 as QuadMesh).material
	pm.albedo_color = Color.WHITE
	pm.billboard_keep_scale = true   # (without it a camera-facing puff ignores its own size: everything 1 m)
	p.amount = amount
	p.lifetime = life
	p.visibility_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 400, 400))
	var m := ParticleProcessMaterial.new()
	m.direction = v.normalized() if v.length() > 0.01 else Vector3.UP
	m.spread = 9.0
	m.initial_velocity_min = v.length() * 0.8
	m.initial_velocity_max = v.length() * 1.2
	m.gravity = drift
	m.damping_min = 0.2
	m.damping_max = 0.35
	m.scale_min = s0
	m.scale_max = s0 * 1.3
	var grow := Curve.new()
	grow.max_value = s1 / s0
	grow.add_point(Vector2(0, 1.0))
	grow.add_point(Vector2(0.3, 1.0 + (s1 / s0 - 1.0) * 0.6))   # (swelling fast, then slowly)
	grow.add_point(Vector2(1, s1 / s0))
	var gt := CurveTexture.new()
	gt.curve = grow
	m.scale_curve = gt
	var g := Gradient.new()
	g.set_color(0, Color(a.r, a.g, a.b, 0.0))
	g.add_point(0.05, Color(a.r, a.g, a.b, 0.85))
	g.add_point(0.45, Color(b.r, b.g, b.b, 0.55))
	g.set_color(g.get_point_count() - 1, Color(b.r, b.g, b.b, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = g
	m.color_ramp = rt
	p.process_material = m
	p.local_coords = not world   # (world space only for a moving emitter: the plane's trail)
	if world:
		p.fixed_fps = 0   # (every frame: at 30 a second a plane's trail is a string of beads)
	return p


# --- the plane going down (now and then) ----------------------------------------------------------

## A plane that won't make it home is in trouble from the moment it shows up: the left engine on
## fire, flame streaming back off the nacelle and a thick black trail pouring out behind, the right
## one smoking grey; it wallows about (see _place_plane) and the engines cough (_sputter).
func _burning() -> void:
	_fire = Node3D.new()
	plane.add_child(_fire)
	_fire.position = Vector3(-5.2, -0.1, -2.0)
	A.glow(_fire, Vector3(1.2, 0.7, 2.6), Vector3.ZERO, Color(1, 0.45, 0.1), 7.0)
	A.glow(_fire, Vector3(0.7, 0.5, 1.6), Vector3(0, 0.1, 1.4), Color(1, 0.8, 0.35), 9.0)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1, 0.5, 0.15)
	fl.omni_range = 35.0
	fl.light_energy = 7.0
	_fire.add_child(fl)
	_blinks.append([fl, 0.11, 0.6])
	var k := plane.scale.x
	_trail(_smoke(Color(0.07, 0.06, 0.06), Color(0.2, 0.19, 0.18), 1400, 14.0, 4.5, 26.0, Vector3(0, 0.8, 0), Vector3(0, 0.5, 0), true), Vector3(-5.2, -0.2, 1.5) * k)
	_trail(_flame(_smoke(Color(3.0, 1.8, 0.7), Color(1.4, 0.35, 0.05), 360, 0.6, 3.0, 4.5, Vector3.ZERO, Vector3.ZERO, true)), Vector3(-5.2, -0.1, -0.5) * k)
	_trail(_smoke(Color(0.2, 0.19, 0.18), Color(0.3, 0.29, 0.28), 260, 5.0, 1.6, 8.0, Vector3(0, 0.4, 0), Vector3(0, 0.4, 0), true), Vector3(5.2, -0.3, 1.0) * k)
	_drone_pitch = 0.94
	main.hud.msg("That plane's on fire.")


func _trail(p: GPUParticles3D, at: Vector3) -> void:
	add_child(p)
	p.global_position = plane.to_global(at)
	p.emitting = true
	_trails.append([p, at])


## The engines missing and catching: the drone dipping in pitch and volume in uneven coughs, a
## backfire banging now and then.
func _sputter() -> void:
	if not is_instance_valid(_drone):
		return
	var cough := maxf(0.0, sin(_t * 2.7) * sin(_t * 1.3 + 1.0)) + maxf(0.0, sin(_t * 5.3 + 2.0) - 0.6)
	_drone.pitch_scale = _drone_pitch * (1.0 - 0.1 * cough + 0.015 * sin(_t * 31.0))
	_drone.volume_db = 4.0 - 7.0 * cough
	if _t > _next_pop:
		_next_pop = _t + _rng.randf_range(1.2, 3.5)
		Sfx.play(self, "backfire", plane.to_global(Vector3(-5.2, -0.3, -2.0)), 8.0, _rng.randf_range(0.8, 1.2))


## The engine goes for good, a while after the drop: a bang, the fire flaring, and it rolls over onto
## the dead side and starts down.
func _engine_fails() -> void:
	_fail = _t
	Sfx.play(self, "backfire", plane.to_global(Vector3(-5.2, -0.35, -3.0)), 14.0, 0.6)
	_fire.create_tween().tween_property(_fire, "scale", Vector3(1.6, 1.6, 2.2), 1.0)
	create_tween().tween_property(self, "_drone_pitch", 0.78, 4.0)
	main.hud.msg("The Bureau plane's going down.")


## Flame instead of smoke: the same puffs drawn additively, so they glow where they overlap.
func _flame(p: GPUParticles3D) -> GPUParticles3D:
	var q: QuadMesh = p.draw_pass_1.duplicate()
	var m: StandardMaterial3D = q.material.duplicate()
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	p.draw_pass_1 = q
	var pm: ParticleProcessMaterial = p.process_material
	(pm.color_ramp as GradientTexture1D).use_hdr = true
	return p


## A colour as it should look, as a particle colour (linear); bright flame (over 1) left as it is.
func _lin(c: Color) -> Color:
	return c.srgb_to_linear() if maxf(c.r, maxf(c.g, c.b)) <= 1.0 else c


## A colour over a puff's life from [[when (0..1), colour], ...].
func _ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(st): return st[0]))
	g.colors = PackedColorArray(stops.map(func(st): return _lin(st[1])))
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	return t


## A burst: `amount` puffs all at once out of a ball `r` across, flung out every way at `v0`..`v1`,
## braking hard (`damp`) and lifting (`lift`), coloured along `stops`; at the crash site.
func _burst(at: Vector3, stops: Array, amount: int, life: float, s0: float, s1: float, r: float, v0: float, v1: float, damp: float, lift: float, flame := false) -> GPUParticles3D:
	var p := _smoke(Color.WHITE, Color.WHITE, amount, life, s0, s1, Vector3.UP, Vector3(0, lift, 0), true)
	if flame:
		_flame(p)
	var m: ParticleProcessMaterial = p.process_material
	m.spread = 180.0
	m.initial_velocity_min = v0
	m.initial_velocity_max = v1
	m.damping_min = damp
	m.damping_max = damp * 1.4
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = r
	m.color_ramp = _ramp(stops)
	p.one_shot = true
	p.explosiveness = 0.92
	p.randomness = 0.4
	p.visibility_aabb = AABB(Vector3(-400, -60, -400), Vector3(800, 500, 800))
	_boom.add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(life + 1.0, false).timeout.connect(p.queue_free)
	return p


const FIRE := [[0.0, Color(3.0, 2.6, 1.8, 1.0)], [0.12, Color(2.6, 1.2, 0.3, 0.95)], [0.4, Color(1.3, 0.32, 0.05, 0.6)], [1.0, Color(0.2, 0.03, 0.0, 0.0)]]
const SOOT := [[0.0, Color(0.3, 0.16, 0.08, 0.0)], [0.08, Color(0.22, 0.13, 0.08, 0.95)], [0.4, Color(0.09, 0.08, 0.07, 0.92)], [1.0, Color(0.2, 0.19, 0.18, 0.0)]]
const DUST := [[0.0, Color(0.62, 0.55, 0.45, 0.0)], [0.08, Color(0.6, 0.53, 0.43, 0.8)], [1.0, Color(0.66, 0.6, 0.52, 0.0)]]


## How high the ground is under a point (the stop's own ground near it, the line's further out).
func _ground_at(p: Vector3) -> float:
	var l: Vector3 = level.to_local(p)
	if absf(l.x) < 95.0 and absf(l.z) < 95.0:
		return level.ground_y(l.x, l.z)
	var line = main.line
	return line.height(line.s + p.x, p.z) if line != null else 0.0


## It hits, far off where nobody can get to, and it's huge: a white flash and a glare across the
## sky; the fireball bursting out, yellow-white cooling to orange and red, swallowed by its own black
## smoke; a dust ring racing out along the ground; burning wreckage thrown up and arcing out trailing
## smoke; the whole mass rolling up into a mushroom, the stem and the cap spreading out at the top;
## then the fuel burning on the ground and cooking off in fireballs, and a black column standing over
## the horizon for minutes. The sound arrives as late as it should (343 m/s), from anywhere.
func _crash_down() -> void:
	_crashed = true
	var at := plane.global_position
	at.y = _ground_at(at)
	crash_at = at
	plane.queue_free()
	for tr in _trails:
		tr[0].emitting = false
	_boom = Node3D.new()
	level.add_child(_boom)
	_boom.global_position = at
	# The flash.
	_burst(at + Vector3(0, 10, 0), [[0.0, Color(6, 5.5, 4.5, 1)], [0.3, Color(4, 2.5, 1.2, 0.8)], [1.0, Color(2, 0.8, 0.2, 0)]], 8, 0.45, 50.0, 90.0, 4.0, 0.0, 2.0, 0.0, 0.0, true)
	var glare := OmniLight3D.new()
	glare.light_color = Color(1, 0.75, 0.45)
	glare.omni_range = 1400.0
	glare.omni_attenuation = 0.5
	glare.light_energy = 40.0
	_boom.add_child(glare)
	glare.position = Vector3(0, 30, 0)
	glare.create_tween().tween_property(glare, "light_energy", 0.0, 3.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# The fireball and its smoke.
	_burst(at + Vector3(0, 14, 0), FIRE, 90, 3.4, 22.0, 55.0, 14.0, 40.0, 95.0, 45.0, 9.0, true)
	get_tree().create_timer(0.15, false).timeout.connect(func():
		_burst(at + Vector3(0, 18, 0), SOOT, 220, 18.0, 24.0, 60.0, 16.0, 14.0, 42.0, 24.0, 5.0))
	# The dust ring.
	var ring := _burst(at + Vector3(0, 3.0, 0), DUST, 140, 8.0, 12.0, 40.0, 0.0, 1.0, 4.0, 3.0, 0.6)
	var rm: ParticleProcessMaterial = ring.process_material
	rm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	rm.emission_ring_axis = Vector3.UP
	rm.emission_ring_radius = 18.0
	rm.emission_ring_inner_radius = 14.0
	rm.emission_ring_height = 1.0
	rm.radial_velocity_min = 95.0
	rm.radial_velocity_max = 130.0
	# The mushroom: an emitter riding up, slowing, its puffs left behind as the stem and spreading at
	# the top into the cap; fire-lit at first.
	var head := Node3D.new()
	_boom.add_child(head)
	head.position = Vector3(0, 6, 0)
	var stem := _smoke(Color.WHITE, Color.WHITE, 1200, 45.0, 24.0, 75.0, Vector3(0, 2, 0), Vector3(0, 0.25, 0) + Vector3(-heading.z, 0, heading.x) * 0.4, true)
	var sm: ParticleProcessMaterial = stem.process_material
	sm.color_ramp = _ramp([[0.0, Color(2.2, 0.9, 0.25, 0.0)], [0.03, Color(1.4, 0.5, 0.15, 0.95)], [0.12, Color(0.14, 0.11, 0.09, 0.95)], [0.6, Color(0.16, 0.15, 0.14, 0.8)], [1.0, Color(0.3, 0.29, 0.28, 0.0)]])
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 10.0
	stem.visibility_aabb = AABB(Vector3(-400, -200, -400), Vector3(800, 600, 800))
	head.add_child(stem)
	stem.emitting = true
	var ht := head.create_tween()
	ht.tween_property(head, "position:y", 170.0, 14.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ht.parallel().tween_property(sm, "emission_sphere_radius", 55.0, 14.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ht.tween_callback(func(): stem.emitting = false)
	var lit := OmniLight3D.new()
	lit.light_color = Color(1, 0.5, 0.2)
	lit.omni_range = 200.0
	lit.light_energy = 10.0
	head.add_child(lit)
	lit.create_tween().tween_property(lit, "light_energy", 0.0, 6.0)
	# Wreckage thrown out burning.
	for i in 10:
		var a := _rng.randf() * TAU
		var chunk := Node3D.new()
		_boom.add_child(chunk)
		chunk.position = Vector3(0, 5, 0)
		A.box(chunk, Vector3(_rng.randf_range(0.8, 2.5), 0.3, _rng.randf_range(0.6, 1.8)), Vector3.ZERO, "metal", Color(0.12, 0.11, 0.1), false)
		var tr := _smoke(Color(0.12, 0.1, 0.09), Color(0.3, 0.29, 0.27), 220, 2.5, 3.0, 8.0, Vector3(0, 0.5, 0), Vector3(0, 0.6, 0), true)
		chunk.add_child(tr)
		tr.emitting = true
		var fl := _flame(_smoke(Color(3.0, 1.6, 0.5), Color(1.0, 0.25, 0.04), 120, 0.5, 3.0, 4.5, Vector3.ZERO, Vector3.ZERO, true))
		chunk.add_child(fl)
		fl.emitting = true
		var out := _rng.randf_range(25.0, 55.0)
		_debris.append([chunk, Vector3(cos(a) * out, _rng.randf_range(35.0, 65.0), sin(a) * out), [tr, fl]])
	# The fuel burning on, and cooking off.
	var fires := _flame(_smoke(Color.WHITE, Color.WHITE, 220, 1.8, 7.0, 15.0, Vector3(0, 7, 0), Vector3(0, 3, 0)))
	var fm: ParticleProcessMaterial = fires.process_material
	fm.color_ramp = _ramp(FIRE)
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fm.emission_box_extents = Vector3(24, 1, 24)
	_boom.add_child(fires)
	fires.emitting = true
	var column := _smoke(Color(0.1, 0.09, 0.08), Color(0.28, 0.27, 0.26), 500, 40.0, 16.0, 70.0, Vector3(0, 12, 0), Vector3(0, 0.1, 0) + Vector3(-heading.z, 0, heading.x) * 0.5, true)
	var cm: ParticleProcessMaterial = column.process_material
	cm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	cm.emission_sphere_radius = 10.0
	column.visibility_aabb = AABB(Vector3(-400, -60, -400), Vector3(800, 600, 800))
	_boom.add_child(column)
	column.emitting = true
	var burn := OmniLight3D.new()
	burn.light_color = Color(1, 0.45, 0.15)
	burn.omni_range = 140.0
	burn.light_energy = 4.0
	_boom.add_child(burn)
	burn.position = Vector3(0, 6, 0)
	_blinks.append([burn, 0.17, 0.7])
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(at) if cam else 600.0
	for k in 4:   # secondary fireballs
		var when := 2.0 + k * 2.3 + _rng.randf() * 1.2
		var off := Vector3(_rng.randf_range(-22, 22), 4, _rng.randf_range(-22, 22))
		get_tree().create_timer(when, false).timeout.connect(func():
			_burst(at + off, FIRE, 35, 2.4, 12.0, 30.0, 5.0, 20.0, 50.0, 35.0, 9.0, true)
			_burst(at + off + Vector3(0, 5, 0), SOOT, 35, 12.0, 14.0, 40.0, 6.0, 14.0, 34.0, 16.0, 3.0)
			burn.light_energy = 14.0
			burn.create_tween().tween_property(burn, "light_energy", 4.0, 1.5))
	get_tree().create_timer(70.0, false).timeout.connect(func():
		fires.emitting = false
		_blinks = _blinks.filter(func(b): return b[0] != burn)
		burn.create_tween().tween_property(burn, "light_energy", 0.0, 8.0))
	get_tree().create_timer(160.0, false).timeout.connect(func(): column.emitting = false)
	get_tree().create_timer(205.0, false).timeout.connect(_boom.queue_free)
	get_tree().create_timer(dist / 343.0, false).timeout.connect(func():
		_far_sound("explosion_far", at, 22.0, 1.0)
		main.player.shake(0.045)
		hz.tremor(true)   # (felt underground: the facility shakes, dust off the ceiling)
		main.hud.msg("Somewhere out there, the plane's come down."))


## A sound from the crash: carries for kilometres (it's dulled already in the making).
func _far_sound(snd: String, at: Vector3, db: float, pitch: float) -> void:
	if not is_instance_valid(_boom):
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = Sfx.stream(snd)
	a.bus = "World"
	a.unit_size = 1500.0
	a.max_distance = 8000.0
	a.volume_db = db
	a.pitch_scale = pitch
	a.attenuation_filter_db = 0.0
	_boom.add_child(a)
	a.global_position = at
	a.play()
	a.finished.connect(a.queue_free)


## The wreckage on its arcs: falling, tumbling, its smoke and flame dying when it lands.
func _fly_debris(delta: float) -> void:
	for d in _debris:
		var c: Node3D = d[0]
		if not is_instance_valid(c):
			d[0] = null
			continue
		var v: Vector3 = d[1]
		v.y -= 9.8 * delta
		d[1] = v
		c.position += v * delta
		c.rotation += Vector3(3.0, 2.0, 1.5) * delta
		if c.global_position.y < _ground_at(c.global_position):
			d[0] = null
			d[2][1].emitting = false
			d[2][0].amount_ratio = 0.4
	_debris = _debris.filter(func(d): return d[0] != null)


## Pried (every machine, through the interactable): the straps snap off, the lid flies up and the
## sides fall flat; the host spills what's inside.
func _open() -> void:
	if crate.get_meta("opened", false):
		return
	crate.set_meta("opened", true)
	var parts: Dictionary = body.get_meta("parts")
	var at: Vector3 = crate.global_position
	Sfx.play(self, "crate_pry", at + Vector3(0, 0.7, 0), 6.0, 1.0)
	var straps: Node3D = parts.straps   # cut: they slither off and lie slack on the ground round it
	var st := create_tween()
	st.tween_property(straps, "position:y", -0.62, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	st.parallel().tween_property(straps, "scale", Vector3(1.35, 0.04, 1.35), 0.3)
	var lid: Node3D = parts.lid   # flipped up off the top and over the back, onto the ground
	var lt := create_tween()
	lt.tween_property(lid, "rotation:x", 1.4, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lt.tween_property(lid, "rotation:x", PI - 0.04, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	lt.parallel().tween_property(lid, "position", lid.position + Vector3(0, -1.11, 0.02), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var k := 0
	for side: Node3D in parts.sides:   # the sides fall outward flat, one after another
		var t := create_tween()
		t.tween_interval(0.25 + k * 0.1)
		t.tween_property(side, "rotation:x", -PI / 2.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(side, "position:y", 0.04, 0.5)
		k += 1
	for c in crate.get_children():
		if c.has_meta("crate"):
			c.queue_free()
	if main.net.authority():
		main.noise(at, 28.0)
		var ids: Array = []
		for i in _rng.randi_range(2, 3):
			ids.append(Data.valuable_scrap(_rng, false))
		if _rng.randf() < 0.6:
			ids.append(["LANTERN", "FLASHLIGHT", "GAS_MASK", "MEDKIT", "SHELLS"][_rng.randi() % 5])
		for i in ids.size():
			main.spawn_item(ids[i], crate.to_global(Vector3(-0.35 + i * 0.3, 0.6, randf_range(-0.12, 0.12))), -1.0, level)   # (laid in the paper)
	main.hud.msg("Bureau supplies. Something out there heard you open it.")
