# The facility through the day: it doesn't stay as you found it (level.gd ticks this on the host;
# everyone sees it through "site" events).
#   A burst main   afternoon: a pipe on a wall splits and sprays, and the room floods round you, the
#                  water rising over half a minute (hazards.gd's flood, raised from the floor).
#   Lockdowns      from 20:00, once or twice: the klaxon, amber beacons turning over the fire
#                  shutters, and every shutter and open bulkhead slams down for a minute and a half,
#                  cutting the place into sectors. The shutters roll up again after.
#   The lift       at 23:00 its motor burns out: sparks and smoke at the headframe, and from then on
#                  it only crawls on its emergency drive. The PA calls everyone to the lift.
# Fire shutters: a few ordinary doorways get a roll-down steel shutter in a hood (registered as
# facility doors, code "FS1".., so the door event and the room graph treat them as bulkheads).
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const Facility = preload("res://src/facility.gd")

const LOCKDOWN_SECS := 90.0

var main
var level
var fac
var hz
var rng := RandomNumberGenerator.new()
var events: Array = []          # [hour, kind, args]
var shutters: Array = []        # door codes
var _beacons: Array = []        # [pivot, light, material]
var _lockdown_t := 0.0
var _reopen: Array = []         # bulkheads that were open when the lockdown began
var _spin := false


func setup(seed: int) -> void:
	rng.seed = seed + 991
	_shutters()
	if not hz.flooded.is_empty() or rng.randf() < 0.45:
		events.append([rng.randf_range(14.0, 20.0), "burst"])
	var n := 1 + (1 if rng.randf() < 0.5 else 0) if not shutters.is_empty() else 0
	for i in n:
		events.append([rng.randf_range(20.0, 22.5) if i == 0 else rng.randf_range(22.6, 23.4), "lockdown"])
	events.append([23.0, "lift_fault"])


# --- the fire shutters ---------------------------------------------------------------------------

## Two to four ordinary doorways get a shutter, most likely where a corridor comes into a wing (a
## lockdown cuts the wings off): rooms of their own (no big rooms, stairs, pits, the lift room or
## the vault), not tunnel to tunnel, no door already in them.
func _shutters() -> void:
	var taken := {}
	for code in fac.layout.doors:
		taken[fac.layout.doors[code]] = true
	var doors_at := {}
	for d in fac.get_children():
		if d.get_script() != null and d.get_script().resource_path.ends_with("door.gd"):
			doors_at[Vector2i(roundi(d.position.x), roundi(d.position.z))] = true
	var edges: Array = []
	for c: Vector2i in fac.layout.cells:
		for dv in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = c + dv
			if not fac.layout.links[c].has(n) or taken.has(Facility.edge(c, n)):
				continue
			var bad := ["start", "pit", "stairwell", "atrium", "vault"]
			var tunnels := int(fac.kinds[c] == "tunnel") + int(fac.kinds.get(n, "") == "tunnel")
			if tunnels == 2 or fac.kinds[c] in bad or fac.kinds.get(n, "") in bad or fac.group_of.has(c) or fac.group_of.has(n) or c == Vector2i.ZERO or n == Vector2i.ZERO:
				continue
			var center := Vector3(c.x, 0, c.y) * Facility.CELL + Vector3(dv.x, 0, dv.y) * (Facility.CELL / 2.0)
			var hinged := false
			for k in doors_at:   # (a swing door's hinge stands at the doorway's edge)
				if Vector2(k.x, k.y).distance_to(Vector2(center.x, center.z)) < Facility.DOOR_W:
					hinged = true
			if not hinged:
				edges.append([c, n, center, dv.y != 0, tunnels])
	for i in range(edges.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = edges[i]
		edges[i] = edges[j]
		edges[j] = t
	edges.sort_custom(func(a, b): return a[4] > b[4])   # (corridor mouths first)
	for i in mini(rng.randi_range(2, 4), edges.size()):
		var e: Array = edges[i]
		var code := "FS%d" % (i + 1)
		fac.layout.doors[code] = Facility.edge(e[0], e[1])
		_shutter(e[2], e[3], code)
		shutters.append(code)


## A roll-down shutter: the curtain (moving: up in the wall when open), a steel hood over the
## doorway on both faces, guide channels down the jambs, a yellow-and-black bottom bar, an amber
## beacon on the hood. Starts open.
func _shutter(center: Vector3, along_x: bool, code: String) -> void:
	var W := Facility.DOOR_W
	var Hd := Facility.DOOR_H
	var size := Vector3(W, Hd, 0.08) if along_x else Vector3(0.08, Hd, W)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	fac.add_child(body)
	body.position = center + Vector3(0, Hd / 2.0 + Hd, 0)   # (rolled up)
	body.set_meta("open", true)
	body.set_meta("live", true)
	A.box(body, size, Vector3.ZERO, "corrugated", Color(0.62, 0.64, 0.62), false, 0.6)
	A.box(body, Vector3(W, 0.12, 0.12) if along_x else Vector3(0.12, 0.12, W), Vector3(0, -Hd / 2.0 + 0.06, 0), "hazard", Color.WHITE, false, 0.4)
	for s in [-1.0, 1.0]:
		var face := Vector3(0, 0, s * 0.22) if along_x else Vector3(s * 0.22, 0, 0)
		var side := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		A.box(fac, Vector3(W + 0.5, 0.42, 0.26) if along_x else Vector3(0.26, 0.42, W + 0.5), center + face + Vector3(0, Hd + 0.24, 0), "riveted", Color(0.45, 0.47, 0.45), false, 0.6)   # the hood
		B.label(fac, "FIRE SHUTTER  %s" % code, center + face * 1.6 + Vector3(0, Hd + 0.24, 0), 26, Color(0.12, 0.1, 0.08), "stencil", 0.0045).rotation.y = (0.0 if s > 0 else PI) if along_x else (PI / 2 if s > 0 else -PI / 2)
		A.box(fac, Vector3(W + 0.5, 0.06, 0.02) if along_x else Vector3(0.02, 0.06, W + 0.5), center + face * 1.56 + Vector3(0, Hd + 0.07, 0), "hazard", Color.WHITE, false, 0.4)
		for j in [-1.0, 1.0]:   # guide channels
			A.box(fac, Vector3(0.1, Hd, 0.12) if along_x else Vector3(0.12, Hd, 0.1), center + side * j * (W / 2.0 + 0.05) + face * 0.45 + Vector3(0, Hd / 2.0, 0), "metal", Color(0.4, 0.42, 0.4), false, 0.5)
		# The beacon on the hood: an amber dome on a black base, a lamp turning in it.
		var bp: Vector3 = center + face * 1.25 + Vector3(0, Hd + 0.55, 0) + side * (W / 2.0 - 0.1)
		A.cyl(fac, 0.09, 0.08, bp, "metal", Color(0.1, 0.1, 0.1))
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.55, 0.1, 0.8)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color(1.0, 0.5, 0.1)
		m.emission_energy_multiplier = 0.15
		var dome := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 0.06
		dm.bottom_radius = 0.08
		dm.height = 0.14
		dome.mesh = dm
		dome.material_override = m
		fac.add_child(dome)
		dome.position = bp + Vector3(0, 0.11, 0)
		dome.set_meta("live", true)
		var pivot := Node3D.new()
		fac.add_child(pivot)
		pivot.position = bp + Vector3(0, 0.11, 0)
		pivot.set_meta("live", true)
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.55, 0.15)
		sl.spot_range = 9.0
		sl.spot_angle = 28.0
		sl.light_energy = 0.0
		pivot.add_child(sl)
		sl.rotation.x = -0.4
		_beacons.append([pivot, sl, m])
	fac.doors[code] = body


# --- the day's events -----------------------------------------------------------------------------

func tick(hours: float, delta: float) -> void:
	for e in events.duplicate():
		if hours >= e[0]:
			events.erase(e)
			match e[1]:
				"burst":
					var c = _burst_room()
					if c != null:
						_say(["burst", c])
				"lockdown":
					_say(["lockdown", true])
				"lift_fault":
					_say(["lift_fault"])
	if _lockdown_t > 0.0:
		_lockdown_t -= delta
		if _lockdown_t <= 0.0:
			_say(["lockdown", false])


func _say(args: Array) -> void:
	if main.net.active:
		main.net.event("site", args)
	net_event(args)


## Everyone: what the host says happened.
func net_event(args: Array) -> void:
	match args[0]:
		"burst": _burst(args[1])
		"lockdown": _lockdown(args[1])
		"lift_fault": _lift_fault()


func _process(delta: float) -> void:
	if _spin:
		for b in _beacons:
			b[0].rotation.y += delta * 7.0


## A dry room of its own next to a flooded one if there is one (the main runs through), else any.
func _burst_room():
	var options: Array = []
	for c: Vector2i in fac.layout.cells:
		if hz.flooded.has(c) or hz.gassed.has(c) or fac.kinds[c] in ["start", "pit", "vault", "atrium", "stairwell"] or fac.group_of.has(c) or fac.kinds[c] == "tunnel":
			continue
		var wet := false
		for d in Facility.DIRS:
			if hz.flooded.has(c + d):
				wet = true
		options.append([c, wet])
	if options.is_empty():
		return null
	var near := options.filter(func(o): return o[1])
	var pick: Array = (near if not near.is_empty() else options)[rng.randi() % (near.size() if not near.is_empty() else options.size())]
	return pick[0]


## The main bursts: a split pipe on a wall sprays across the room, and the water comes up over the
## floor round you.
func _burst(c: Vector2i) -> void:
	if hz.flooded.has(c):
		return
	var o := Vector3(c.x * Facility.CELL, 0, c.y * Facility.CELL)
	# Which wall: one without a doorway, else any.
	var wall := Vector3(0, 0, -1)
	for d in Facility.DIRS:
		if not fac.layout.links[c].has(c + d):
			wall = Vector3(d.x, 0, d.y)
			break
	var along := Vector3(absf(wall.z), 0, absf(wall.x))
	var pipe_at: Vector3 = o + wall * (Facility.CELL / 2.0 - 0.35) + Vector3(0, 2.6, 0)
	# The pipe along the wall, its split flange, and the jet out of it.
	A.cyl(fac, 0.14, Facility.CELL - 0.8, pipe_at, "rust", Color(0.7, 0.62, 0.55), false, "x" if along.x > 0.5 else "z")
	for k in [-3.5, 3.5]:
		A.box(fac, Vector3(0.12, 0.5, 0.3) if along.x > 0.5 else Vector3(0.3, 0.5, 0.12), pipe_at + along * k + wall * 0.15 + Vector3(0, -0.05, 0), "metal", Color(0.3, 0.3, 0.3), false)   # brackets
	var split := pipe_at + along * rng.randf_range(-1.5, 1.5)
	A.cyl(fac, 0.2, 0.12, split, "metal", Color(0.35, 0.33, 0.3), false, "x" if along.x > 0.5 else "z")
	for k in 4:   # the torn lips
		A.box(fac, Vector3(0.05, 0.16, 0.12), split + Vector3(0, 0.12, 0).rotated(along, k * PI / 2.0) - wall * 0.05, "rust", Color(0.8, 0.7, 0.6), false, 0.3, Vector3(rng.randf(), rng.randf(), rng.randf()))
	var jet := CPUParticles3D.new()
	jet.amount = 140
	jet.lifetime = 1.1
	jet.direction = -wall + Vector3(0, -0.15, 0)
	jet.spread = 14.0
	jet.initial_velocity_min = 5.0
	jet.initial_velocity_max = 8.0
	jet.gravity = Vector3(0, -9.0, 0)
	jet.scale_amount_min = 0.5
	jet.scale_amount_max = 1.4
	jet.scale_amount_curve = _fade_curve(0.6, 1.8)   # (droplets spread out as they fly)
	jet.mesh = _water_quad(0.16, Color(0.72, 0.8, 0.82, 0.5))
	fac.add_child(jet)
	jet.position = split - wall * 0.2
	jet.emitting = true
	var mist := CPUParticles3D.new()   # spray hanging round the break, catching the light
	mist.amount = 40
	mist.lifetime = 2.2
	mist.direction = -wall + Vector3(0, 0.3, 0)
	mist.spread = 45.0
	mist.initial_velocity_min = 0.6
	mist.initial_velocity_max = 1.6
	mist.gravity = Vector3(0, -0.3, 0)
	mist.damping_min = 0.4
	mist.damping_max = 0.8
	mist.scale_amount_curve = _fade_curve(0.5, 2.5)
	mist.color_ramp = _fade_ramp(Color(0.8, 0.85, 0.88, 0.22))
	mist.mesh = _water_quad(0.9, Color.WHITE)
	fac.add_child(mist)
	mist.position = split - wall * 0.3
	mist.emitting = true
	var spray := AudioStreamPlayer3D.new()
	spray.stream = Sfx.stream("steam")
	spray.bus = "World"
	spray.volume_db = -4.0
	spray.pitch_scale = 0.55
	spray.unit_size = 5.0
	spray.max_distance = 30.0
	fac.add_child(spray)
	spray.position = split
	spray.play()
	Sfx.play(fac, "steam_burst", fac.to_global(split), 4.0, 0.6)
	Sfx.play(fac, "clang_big", fac.to_global(split), 2.0, 0.7)
	if main.net.authority():
		main.noise(fac.to_global(split), 30.0)
	# The flood: hazards.gd lays it; everything it laid comes up from below the floor.
	var before := {}
	for n in fac.get_children():
		before[n] = true
	hz._flood(c)
	for n in fac.get_children():
		if not before.has(n) and n is MeshInstance3D:
			var y: float = n.position.y
			n.position.y = y - hz.WATER_Y - 0.05
			n.create_tween().tween_property(n, "position:y", y, 28.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _in_room(main.player, c):
		main.hud.alert("A WATER MAIN HAS BURST")
	get_tree().create_timer(40.0, false).timeout.connect(func():   # it settles to a gush
		jet.amount = 60
		jet.initial_velocity_max = 5.0)


func _in_room(p, c: Vector2i) -> bool:
	return p != null and fac.cell_at(p.global_position) == c and absf(p.global_position.y - fac.global_position.y) < 6.0


## A security lockdown: the klaxon, the beacons, every shutter and every open bulkhead down; then
## (lockdown false) back up as they were.
func _lockdown(on: bool) -> void:
	_spin = on
	for b in _beacons:
		b[1].light_energy = 5.0 if on else 0.0
		b[2].emission_energy_multiplier = 4.0 if on else 0.15
	if on:
		for code in shutters:
			Sfx.play(fac, "klaxon", fac.doors[code].global_position, -2.0, 0.9)
		if main.player.global_position.y < main.UNDERGROUND_Y:
			main.hud.alert("SECURITY LOCKDOWN: FIRE SHUTTERS CLOSING")
			Sfx.play(main, "alarm_bell", null, -10.0, 0.8)
	if not main.net.authority():
		return
	if on:
		_lockdown_t = LOCKDOWN_SECS
		_reopen.clear()
		for code in fac.doors:
			if code == fac.vault_code:
				continue
			if code in shutters or fac.doors[code].get_meta("open"):
				if not code in shutters:
					_reopen.append(code)
				fac.set_door(code, false, false)
	else:
		for code in shutters + _reopen:
			fac.set_door(code, true, false)
		_reopen.clear()


## 23:00: the lift's motor burns out. It runs on, slowly, on the emergency drive.
func _lift_fault() -> void:
	if level.elevator != null:
		level.elevator.set_fault()
	main.hud.alert("BUREAU NOTICE: SITE CLOSING. LIFT ON EMERGENCY DRIVE. ALL STAFF TO THE LIFT.")
	Sfx.play(main, "alarm_bell", null, -12.0, 0.7)


## A round, soft-edged sprite for water in the air.
static func _water_quad(size: float, col: Color) -> QuadMesh:
	var tex := GradientTexture2D.new()
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	qm.material = m
	return qm


static func _fade_curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(a, b)
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	return c


static func _fade_ramp(col: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.25, col)
	return g
