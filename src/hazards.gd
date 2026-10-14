# Site hazards and events for one station. Lives under the level, so it slides away with it.
#   Rooms (by facility type, Data.SITE_HAZARDS):
#     FLOOD  knee-deep water: slow, loud footsteps; some rooms have a live cable that arcs through it
#     GAS    toxic haze: chokes you and makes you cough (noise) unless a GAS MASK is in your pack
#     STEAM  burst lines that hiss, then blast across the room or tunnel; crouch under or time it
#   Events (scheduled by shift hour):
#     POWER FAILURE  lights die, lift crawls on emergency power, cameras + bulkheads offline,
#                    live cables go dead, until someone resets the breaker panel
#     TREMOR         shaking, dust, falling ceiling (and what was up there), wakes everything that listens
#     AIRDROP        a Bureau crate parachutes onto the surface under a red flare; loud to open
extends Node3D

const Data = preload("res://src/data.gd")
const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")
const Sfx = preload("res://src/sfx.gd")
const Facility = preload("res://src/facility.gd")

const WATER_Y := 0.24
const JET_LEN := 4.0
const JET_R := 0.5
const NO_HAZARD := ["start", "pit", "vault", "atrium", "stairwell"]

var main
var level
var fac
var rng := RandomNumberGenerator.new()
var power := true
var flooded := {}        # cell -> true
var gassed := {}         # cell -> true
static var _gas_noise: NoiseTexture3D
var cables: Array = []   # live cables in flood water: {cell, at, light, sparks, t, state}
var steams: Array = []   # burst lines: {at, dir, t, state, puff, jet, loop}
var breaker: Node3D
var events: Array = []   # [hour, kind], fired by tick()
var _lamp: OmniLight3D
var _lamp_bulb: MeshInstance3D
var _lever: Node3D
var _dark: Array = []    # [light, was_visible] switched off by a power failure
var _dimmed: Array = []  # [mesh, surface (-1 = override), original material]
var _emergency: Array[OmniLight3D] = []
var _emergency_parts: Array = []   # the lamps' housings and the beacons, gone when the power's back
var _beacons: Array = []
var _tremor := 0.0
var _cough := 0.0
var _told := {}
var _water_mat: StandardMaterial3D
var _bulb_mat: Material
static var _soft: GradientTexture2D   # round, soft-edged particle sprite
var _flares: Array[OmniLight3D] = []
var _spills := {}   # edge -> Node3D: water running out of a flooded room through a doorway


func setup(stop: Dictionary, assignment: int, seed: int) -> void:
	rng.seed = seed + 77
	var kinds: Array = Data.SITE_HAZARDS.get(stop.theme, [])
	var rooms: Array = []
	var tunnels: Array = []
	for c in fac.layout.cells:
		var k: String = fac.kinds[c]
		if k == "tunnel":
			tunnels.append(c)
		elif not k in NO_HAZARD and not fac.group_of.has(c):   # (big rooms are open: water and gas would have no walls to stop at)
			rooms.append(c)
	_shuffle(rooms)
	_shuffle(tunnels)
	if "flood" in kinds:
		for i in mini(rng.randi_range(1, 2) + assignment / 3, 4):
			if not rooms.is_empty():
				_flood(rooms.pop_back())
	if "gas" in kinds:
		for i in rng.randi_range(1, 2):
			if not rooms.is_empty():
				_gas(rooms.pop_back())
	if "steam" in kinds:
		for i in rng.randi_range(2, 4):
			if not tunnels.is_empty():
				_steam_tunnel(tunnels.pop_back())
			elif not rooms.is_empty():
				_steam_room(rooms.pop_back())
	if not gassed.is_empty():   # there's always a mask somewhere outside the gas
		for tries in 20:
			var p: Vector3 = fac.random_point(rng)
			if not gassed.has(fac.cell_at(p)):
				main.spawn_item("GAS_MASK", p, -1.0, level)
				break
	_breaker()
	if rng.randf() < 0.4 + 0.06 * assignment:
		events.append([rng.randf_range(10.5, 19.0), "power"])
	for i in 1 + (1 if rng.randf() < 0.45 else 0):
		events.append([rng.randf_range(9.5, 22.5), "tremor"])
	if rng.randf() < 0.45:
		events.append([rng.randf_range(10.0, 17.0), "airdrop"])


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func tick(hours: float) -> void:
	for e in events.duplicate():
		if hours >= e[0]:
			events.erase(e)
			match e[1]:
				"power":
					power_fail()
					main.net.event("hz", ["power"])
				"tremor":
					tremor()
					main.net.event("hz", ["tremor"])
				"airdrop":
					var land := _drop_spot()
					var spin := rng.randf() * TAU
					airdrop(land, spin)
					main.net.event("hz", ["airdrop", land, spin])


func _under(p: Node3D) -> bool:
	var y: float = p.global_position.y - fac.global_position.y
	return y > -Facility.PIT - 1.0 and y < Facility.H + 1.0


var _wake_at := {}   # who -> where they last left a ring


## Rings on the flood water round anything walking through it (each machine draws its own).
func _wakes(_delta: float) -> void:
	if flooded.is_empty() or fac == null:
		return
	var walkers: Array = main.players() + get_tree().get_nodes_in_group("monsters")
	var cam := get_viewport().get_camera_3d()
	for w in walkers:
		if not is_instance_valid(w) or not w is Node3D:
			continue
		var pos: Vector3 = w.global_position
		if cam and cam.global_position.distance_to(pos) > 25.0:
			continue
		if not wet(pos):
			_wake_at.erase(w)
			continue
		var last: Vector3 = _wake_at.get(w, Vector3.INF)
		if last == Vector3.INF or Vector2(pos.x - last.x, pos.z - last.z).length() > 0.45:
			_wake_at[w] = pos
			if is_instance_valid(fac) and not fac.is_queued_for_deletion():
				A.ripple(fac, Vector3(pos.x, fac.global_position.y + WATER_Y + 0.02, pos.z), randf_range(1.0, 1.5), 1.3)


## Standing in flood water (on the floor, not up on a crate or a mezzanine).
func wet(pos: Vector3) -> bool:
	return flooded.has(fac.cell_at(pos)) and pos.y < fac.global_position.y + 0.5 and pos.y > fac.global_position.y - 1.0


func has_mask(p) -> bool:
	return main.has_upgrade("GAS_FILTER") or p.slots.any(func(it): return it != null and it.id == "GAS_MASK")


func _say(key: String, text: String, alert := false) -> void:
	if _told.has(key):
		return
	_told[key] = true
	if alert:
		main.hud.alert(text)
	else:
		main.hud.msg(text)


# --- per frame -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if fac == null:
		return
	for p in main.players():
		if p.dead:
			continue
		var under := _under(p)
		p.wading = under and wet(p.global_position)
		if p.wading:
			_say("wade", "Flood water. Slow going, and every step splashes.")
		if under and gassed.has(fac.cell_at(p.global_position)) and fac.to_local(p.global_position).y > -1.0:   # (not the basement under it)
			if has_mask(p):
				_say("mask", "Your helmet filters keep the fumes out." if main.has_upgrade("GAS_FILTER") else "The GAS MASK in your pack keeps the fumes out.")
			else:
				_say("gas", "TOXIC GAS. Get out, or come back with a GAS MASK.", true)
				p.hurt(7.0 * delta, "Choked on toxic gas.")
				_cough -= delta
				if _cough <= 0.0:
					_cough = rng.randf_range(1.4, 2.4)
					Sfx.play(p, "cough", p.global_position + Vector3(0, 1.5, 0), -2.0, rng.randf_range(0.9, 1.1))
					main.noise(p.global_position, 14.0)
		if _tremor > 0.0:
			p.shake(0.045 if under else 0.015)
	_tremor = maxf(0.0, _tremor - delta)
	for cb in cables:
		_cable_tick(cb, delta)
	for st in steams:
		_steam_tick(st, delta)
	if _water_mat:
		_water_mat.uv1_offset += Vector3(0.012, 0.007, 0) * delta
	_wakes(delta)
	for f in _flares:
		f.light_energy = randf_range(2.0, 4.0)
	if not power:
		var t := Time.get_ticks_msec() / 1000.0
		for l in _emergency:
			l.light_energy = 0.45 + 0.3 * sin(t * 2.6)
		for b in _beacons:
			if is_instance_valid(b):
				b.rotation.y = t * 4.0
		_lamp.light_energy = 0.8 if fmod(t, 1.0) < 0.5 else 0.0


# --- flood + live cables ---------------------------------------------------------------------

func _flood(c: Vector2i) -> void:
	flooded[c] = true
	var o := Vector3(c.x * Facility.CELL, 0, c.y * Facility.CELL)
	if _water_mat == null:
		_water_mat = StandardMaterial3D.new()
		_water_mat.albedo_color = Color(0.11, 0.12, 0.08, 0.88)
		_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_mat.roughness = 0.06
		_water_mat.metallic_specular = 1.0
		var nt := NoiseTexture2D.new()   # ripples: the flashlight catches them
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0
		var fn := FastNoiseLite.new()
		fn.frequency = 0.03
		nt.noise = fn
		_water_mat.normal_enabled = true
		_water_mat.normal_texture = nt
		_water_mat.normal_scale = 0.5
		_water_mat.uv1_triplanar = true          # world-space ripples: still and running water join seamlessly
		_water_mat.uv1_world_triplanar = true
		_water_mat.uv1_scale = Vector3.ONE * 0.22
		_water_mat.vertex_color_use_as_albedo = true   # the spill fades out with vertex alpha
		_water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_water_box(o, Vector3(Facility.CELL - 0.3, 0, Facility.CELL - 0.3), _water_mat)   # right up to the wall faces, no dry rim
	for d in Facility.DIRS:   # doorways: joined to flooded neighbours, spilling into dry ones
		var n: Vector2i = c + d
		if not fac.layout.links[c].has(n):
			continue
		var e: Array = Facility.edge(c, n)
		if _spills.has(e):   # the neighbour was spilling into us: now it's one body of water
			_spills[e].queue_free()
			_spills.erase(e)
		var sealed: bool = fac.layout.doors.values().has(e)   # a bulkhead holds the water back
		if flooded.has(n):
			_water_box(o + Vector3(d.x, 0, d.y) * (Facility.CELL / 2.0), Vector3(2.5, 0.04, 0.7) if d.y != 0 else Vector3(0.7, 0.04, 2.5), _water_mat)
		elif sealed:   # fill the recess right up to the door
			_water_box(o + Vector3(d.x, 0, d.y) * (Facility.CELL / 2.0 - 0.09), Vector3(2.5, 0.04, 0.2) if d.y != 0 else Vector3(0.2, 0.04, 2.5), _water_mat)
		elif fac.kinds.get(n, "") != "pit":
			_spills[e] = _spill(o, d)
	for d in Facility.DIRS:   # crawl vents: water runs out through those too
		var n: Vector2i = c + d
		var e: Array = Facility.edge(c, n)
		if fac.layout.links[c].has(n) or not fac.vents.has(e):
			continue
		var off: float = fac.vents[e]
		var mouth: Vector3 = o + Vector3(d.x, 0, d.y) * (Facility.CELL / 2.0) + (Vector3(off, 0, 0) if d.y != 0 else Vector3(0, 0, off))
		if _spills.has(e):
			_spills[e].queue_free()
			_spills.erase(e)
		if flooded.has(n):   # one body of water through the duct
			_water_box(mouth, Vector3(Facility.VENT_W - 0.04, 0, 0.5) if d.y != 0 else Vector3(0.5, 0, Facility.VENT_W - 0.04), _water_mat)
		else:
			_spills[e] = _spill(o, d, mouth, Facility.VENT_W / 2.0 - 0.02, 2.8)
	for d in Facility.DIRS:   # a dark tide line on the walls just above the water
		var dv := Vector3(d.x, 0, d.y)
		var along := Vector3(absf(d.y), 0, absf(d.x))
		if fac.vents.has(Facility.edge(c, c + d)):
			continue   # (not across a vent)
		var gap := 1.4 if fac.layout.links[c].has(c + d) else 0.0
		for sgn in [-1.0, 1.0]:
			var length := Facility.CELL / 2.0 - 0.3 - gap
			var mid: Vector3 = o + dv * (Facility.CELL / 2.0 - 0.19) + along * sgn * (gap + length / 2.0) + Vector3(0, WATER_Y + 0.12, 0)
			var size := Vector3(length, 0.26, 0.02) if d.y != 0 else Vector3(0.02, 0.26, length)
			A.box(fac, size, mid, "dirt", Color(0.18, 0.15, 0.1), false, 1.0)
	for i in rng.randi_range(3, 6):   # whatever floats
		var fp := o + Vector3(rng.randf_range(-5, 5), WATER_Y + 0.02, rng.randf_range(-5, 5))
		if rng.randf() < 0.5:
			A.box(fac, Vector3(rng.randf_range(0.5, 1.2), 0.04, rng.randf_range(0.1, 0.2)), fp, "wood", Color(0.5, 0.42, 0.32), false, 1.0, Vector3(0, rng.randf() * TAU, 0))
		else:
			A.box(fac, Vector3(0.22, 0.005, 0.3), fp, "paper", Color(0.8, 0.78, 0.7), false, 1.0, Vector3(0, rng.randf() * TAU, 0))
	# Where it's coming from: a ceiling leak dripping into it.
	var leak := o + Vector3(rng.randf_range(-4, 4), Facility.H - 0.1, rng.randf_range(-4, 4))
	A.box(fac, Vector3(1.2, 0.03, 1.0), leak, "rust", Color(0.4, 0.35, 0.3), false)
	var drip := AudioStreamPlayer3D.new()
	drip.stream = Sfx.stream("drip_loop")
	drip.bus = "World"
	drip.volume_db = -17.0
	drip.unit_size = 3.0
	drip.max_distance = 14.0
	drip.autoplay = true
	fac.add_child(drip)
	drip.position = leak
	fac._drips.append([fac.to_global(Vector3(leak.x, WATER_Y + 0.02, leak.z)), fac.to_global(leak - Vector3(0, 0.05, 0)), 0.0])   # (and you can see it drip)
	if rng.randf() < 0.65:
		_cable(c, o)


## A flat sheet of water (no thickness, so no edge faces where pieces meet).
func _water_box(pos: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size.x, size.z)
	w.mesh = pm
	w.material_override = mat
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else fac).add_child(w)
	w.position = pos + Vector3(0, WATER_Y + 0.02 if parent == null else 0.0, 0)
	return w


## Water running out through a doorway: one sheet that starts exactly where the room's water ends
## (same height, same ripples), fans out from the door mouth both forward and sideways along the wall,
## eases down to the floor and thins to nothing. No lip, no overlap.
func _spill(o: Vector3, d: Vector2i, mouth := Vector3.INF, half_door := 1.2, reach := 4.2) -> Node3D:
	var dv := Vector3(d.x, 0, d.y)
	var root := Node3D.new()
	fac.add_child(root)
	root.position = o + dv * (Facility.CELL / 2.0) if mouth == Vector3.INF else mouth
	root.basis = Basis(Vector3.UP.cross(dv), Vector3.UP, dv)   # local z runs out into the dry room
	var top := WATER_Y + 0.02
	var z0 := -0.15            # where the room's water sheet ends (CELL/2 - (CELL - 0.3)/2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs := PackedFloat32Array()
	for i in 25:
		xs.append(lerpf(-half_door - reach, half_door + reach, i / 24.0))
	var zs := PackedFloat32Array([z0, 0.0])
	for j in 18:
		zs.append(lerpf(0.12, reach, pow(j / 17.0, 1.3)))   # denser near the door, where it bends
	for z in zs:
		for x in xs:
			# Distance from the door mouth: zero across the opening, growing forward and out to the sides.
			var side := maxf(absf(x) - half_door, 0.0)
			var dist := Vector2(side * 1.15, maxf(z, 0.0)).length()
			var inside_wall := z < 0.0 and side > 0.0
			var h := top if z <= 0.0 else lerpf(top, 0.01, smoothstep(0.0, reach * 0.85, dist))
			var a := 1.0 - smoothstep(reach * 0.45, reach, dist)
			if inside_wall:
				a = 0.0   # hidden in the wall anyway
			st.set_color(Color(1, 1, 1, a))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(x, h, z))
	var nx := xs.size()
	for j in zs.size() - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + nx
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(b + 1)
			st.add_index(b)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var trickle := _loop3d("steam", root.to_global(Vector3(0, 0.1, 1.0)), -24.0, 0.3)   # running water
	trickle.max_distance = 14.0
	trickle.reparent(root)
	return root


func _cable(c: Vector2i, o: Vector3) -> void:
	var spot := o + Vector3(_side() * rng.randf_range(2.2, 4.2), 0, _side() * rng.randf_range(2.2, 4.2))
	var top := spot + Vector3(0, Facility.H - 0.25, 0)
	A.box(fac, Vector3(0.4, 0.28, 0.24), top + Vector3(0, 0.1, 0), "metal", Color(0.42, 0.42, 0.38), false)   # junction box, torn open
	A.box(fac, Vector3(0.36, 0.04, 0.26), top + Vector3(0.08, -0.05, 0.12), "metal", Color(0.3, 0.3, 0.28), false, 1.0, Vector3(0.7, 0, 0.2))
	var mid := spot + Vector3(rng.randf_range(-0.5, 0.5), 1.7, rng.randf_range(-0.5, 0.5))
	var end := spot + Vector3(rng.randf_range(-0.6, 0.6), WATER_Y - 0.02, rng.randf_range(-0.6, 0.6))
	A.seg(fac, top, mid, 0.028, 0.028, "rubber", Color(0.1, 0.1, 0.1))
	A.seg(fac, mid, end + Vector3(0, 0.35, 0), 0.028, 0.028, "rubber", Color(0.1, 0.1, 0.1))
	A.seg(fac, end + Vector3(0, 0.35, 0), end, 0.028, 0.012, "copper", Color(1, 0.7, 0.5))   # stripped end in the water
	var at: Vector3 = fac.to_global(end)
	var light := B.omni(self, Vector3.ZERO, Color(0.55, 0.75, 1.0), 0.0, 7.0, true)   # the arc doesn't light the next room
	light.global_position = at + Vector3(0, 0.4, 0)
	var sp := _particles(Color(0.75, 0.9, 1.0), 0.025, 30, 0.45, Vector3.UP, 70.0, 2.0, 4.0, Vector3(0, -9.8, 0))
	sp.global_position = at + Vector3(0, 0.05, 0)
	var hum := _loop3d("buzz", at, -14.0, 3.0)
	var bolt := Node3D.new()   # the arc itself: jagged forks running out across the water
	add_child(bolt)
	bolt.global_position = at + Vector3(0, 0.03, 0)
	var zap := A.mat("cream", Color(0.7, 0.85, 1.0), 1.0, 9.0)
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
		var from := Vector3.ZERO
		for j in 4:
			var to := from + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.3, 0.55) + Vector3(0, rng.randf_range(-0.01, 0.03), 0)
			a += rng.randf_range(-0.7, 0.7)
			A.seg(bolt, from, to, 0.014, 0.008, "cream").material_override = zap
			from = to
	A.seg(bolt, Vector3.ZERO, Vector3(0.05, 0.4, 0), 0.02, 0.012, "cream").material_override = zap
	bolt.visible = false
	cables.append({"cell": c, "at": at, "light": light, "sparks": sp, "hum": hum, "bolt": bolt, "t": rng.randf_range(2.0, 6.0), "state": 0})


func _cable_tick(cb: Dictionary, delta: float) -> void:
	var light: OmniLight3D = cb.light
	if not power:
		light.light_energy = 0.0
		cb.sparks.emitting = false
		cb.hum.stream_paused = true
		return
	cb.hum.stream_paused = false
	cb.t -= delta
	match cb.state:
		0:   # idle: the odd fizz
			light.light_energy = 0.15 if randf() < 0.05 else 0.0
		1:   # building up
			light.light_energy = randf() * 1.6
		2:   # arc
			light.light_energy = randf_range(4.0, 10.0)
			cb.bolt.visible = randf() < 0.8
			cb.bolt.rotation.y = randf() * TAU
	if cb.t <= 0.0 and main.net.authority():   # (the host decides when; the crew follows)
		var nxt: int = (cb.state + 1) % 3
		_cable_go(cb, nxt, rng.randf_range(4.0, 8.0))
		main.net.event("hz", ["cable", cables.find(cb), nxt, cb.t])


func _cable_go(cb: Dictionary, st: int, idle: float) -> void:
	var light: OmniLight3D = cb.light
	cb.state = st
	match st:
		1:
			cb.t = 1.2
			cb.sparks.emitting = true
			Sfx.play(self, "crackle", cb.at, -2.0)
		2:
			cb.t = 0.35
			light.light_energy = 10.0
			Sfx.play(self, "zap", cb.at, 6.0, randf_range(0.9, 1.1))
			main.noise(cb.at, 20.0)
			if main.net.authority():
				for p in main.players():
					if p.wading and not p.dead and fac.cell_at(p.global_position) == cb.cell:
						p.hurt(34.0, "Electrocuted in the flood water.")
						p.shake(0.08)
		0:
			cb.t = idle
			cb.sparks.emitting = false
			cb.bolt.visible = false
			light.light_energy = 0.0


## The host says (multiplayer): an event, or a cable or steam line changing state.
func net_event(args: Array) -> void:
	match args[0]:
		"cable":
			if args[1] >= 0 and args[1] < cables.size():
				_cable_go(cables[args[1]], args[2], args[3])
		"steam":
			if args[1] >= 0 and args[1] < steams.size():
				_steam_go(steams[args[1]], args[2], args[3])
		"power": power_fail()
		"tremor": tremor()
		"airdrop": airdrop(args[1], args[2])


# --- gas -------------------------------------------------------------------------------------

## A gassed room: a ruptured chemical line has filled it. The gas is heavy: it lies thick along the
## floor and thins upward to a ragged top, lumpy and creeping slowly (one fog volume, GAS_FOG), with a
## thin haze in the room above, and it seeps out under the doorways a few metres. A dull chlorine
## yellow-green, not a glow. A beacon turns on the wall.
const GAS := Color(0.5, 0.56, 0.24)
const GAS_FOG := """shader_type fog;
uniform sampler3D lumps : repeat_enable;
uniform vec3 tint = vec3(0.5, 0.56, 0.24);
uniform float heavy = 0.55;     // how thick it is on the floor...
uniform float depth = 0.4;    // ...thinning over this many metres up (clear by your eyes: a torch beam isn't a ball of light)
uniform float haze = 0.005;    // the thin stuff filling the room above
uniform vec3 door = vec3(-1.0);   // a doorway's spill: where it comes in (UVW); x < 0 for the room itself

void fog() {
	vec3 w = WORLD_POSITION;
	float t = TIME;
	float a = texture(lumps, w * vec3(0.06, 0.1, 0.06) + vec3(t * 0.011, 0.0, t * 0.007)).r;   // big slow banks
	float b = texture(lumps, w * vec3(0.16, 0.22, 0.16) - vec3(t * 0.018, t * 0.005, -t * 0.013)).r;   // smaller curls through them
	float lump = clamp(a * 0.75 + b * 0.55 - 0.2, 0.0, 1.0);
	float h = UVW.y * SIZE.y + (b - 0.5) * 0.6;   // height over the floor: the top's ragged
	float d = heavy * exp(-max(h, 0.0) / depth) * (0.2 + 1.3 * lump) + haze * (0.3 + lump);
	if (door.x < 0.0) {   // the room: soft at the walls
		vec2 e = min(UVW.xz, 1.0 - UVW.xz) * SIZE.xz;
		d *= smoothstep(0.0, 0.6, min(e.x, e.y));
	} else {   // out under a doorway: thinner the further from it
		d *= 1.0 - smoothstep(0.0, 1.0, length((UVW.xz - door.xz) * SIZE.xz) / 3.4);
		d *= 1.0 - smoothstep(0.35, 1.0, UVW.y);
	}
	DENSITY = d;
	ALBEDO = tint * 0.28;   // (dark: a torch into it doesn't light up a ball of it)
	EMISSION = tint * 0.22;   // (a faint sickly glow of its own instead: the layer reads in the dark)
}
"""


func _gas(c: Vector2i) -> void:
	gassed[c] = true
	var o := Vector3(c.x * Facility.CELL, 0, c.y * Facility.CELL)
	if _gas_noise == null:   # one lumpy density field, shared by every gas room
		var n := FastNoiseLite.new()
		n.frequency = 0.09
		n.fractal_octaves = 3
		_gas_noise = NoiseTexture3D.new()
		_gas_noise.width = 48
		_gas_noise.height = 24
		_gas_noise.depth = 48
		_gas_noise.noise = n
		_gas_noise.seamless = true
	var room := Facility.CELL - 0.3
	_gas_fog(o + Vector3(0, Facility.H / 2.0, 0), Vector3(room, Facility.H, room))
	for k in 7 * 18:   # (the dice the drifting clouds used to take: every hazard rolled after the gas comes out as it did)
		rng.randf()
	# It seeps out under every doorway, thinning to nothing a few metres outside.
	for d in Facility.DIRS:
		if not fac.layout.links[c].has(c + d):
			continue
		var dv := Vector3(d.x, 0, d.y)
		var size := Vector3(4.0, 1.4, 3.6) if d.y != 0 else Vector3(3.6, 1.4, 4.0)
		var door_uvw := Vector3(0.5, 0.0, 0.0 if d.y > 0 else 1.0) if d.y != 0 else Vector3(0.0 if d.x > 0 else 1.0, 0.0, 0.5)
		_gas_fog(o + dv * (Facility.CELL / 2.0 + 1.8) + Vector3(0, 0.7, 0), size, door_uvw)
	# The source: a burst chemical line coming down the wall into a valve manifold, venting.
	var walls: Array = fac.cell_walls.get(c, []).filter(func(w): return not w[3] and not w[4])
	var w: Array = walls[rng.randi() % walls.size()] if not walls.is_empty() else [o + Vector3(0, 0, -6), true, Vector3(0, 0, 1), false, false]
	var n: Vector3 = w[2]
	var along := Vector3(n.z, 0, -n.x)
	var base: Vector3 = fac._wall_spot(w, rng.randf_range(-2.5, 2.5), 0.4)
	var yellow := Color(0.85, 0.7, 0.15)
	A.cyl(fac, 0.11, Facility.H, base + Vector3(0, Facility.H / 2.0, 0), "paint", yellow)
	for y in [0.6, 1.5, 2.4, 3.3]:
		A.box(fac, Vector3(0.3, 0.06, 0.3), base + Vector3(0, y, 0) - n * 0.15, "metal", Color(0.3, 0.3, 0.3), false, 0.3)   # wall brackets
	A.box(fac, Vector3(0.5, 0.5, 0.35), base + Vector3(0, 1.15, 0) + n * 0.05, "metal", Color(0.4, 0.42, 0.38), false, 0.4)   # manifold
	A.ring(fac, 0.17, 0.12, base + Vector3(0, 1.6, 0) + n * 0.25, "metal", Color(0.8, 0.15, 0.1), Vector3(PI / 2, atan2(n.x, n.z), 0))   # valve wheel
	A.box(fac, Vector3(0.62, 0.5, 0.01), base + Vector3(0, 2.4, 0) + n * 0.12, "hazard", Color.WHITE, false, 0.4, Vector3(0, atan2(n.x, n.z), 0))
	A.box(fac, Vector3(0.62, 0.15, 0.01), base + Vector3(0, 2.06, 0) + n * 0.12, "paint", Color(0.86, 0.83, 0.74), false, 0.4, Vector3(0, atan2(n.x, n.z), 0))   # a plate under it for the words (black on the stripes doesn't read)
	var tag := B.label(fac, "TOXIC  NO ENTRY", base + Vector3(0, 2.06, 0) + n * 0.126, 30, Color(0.08, 0.08, 0.06), "stencil", 0.006, Vector2(0.56, 0.1))
	tag.rotation.y = atan2(n.x, n.z)
	# The split: a torn stub of pipe pointing out into the room, a plume jetting from it.
	var split := base + Vector3(0, 0.75, 0)
	A.seg(fac, split, split + n * 0.45 + Vector3(0, -0.1, 0), 0.1, 0.09, "paint", yellow)
	for k in 5:   # torn metal petals round the break
		var a := TAU * k / 5.0
		var petal := A.box(fac, Vector3(0.05, 0.14, 0.012), split + n * 0.5 + (along * cos(a) + Vector3.UP * sin(a)) * 0.09, "metal", yellow.darkened(0.3), false, 0.2)
		petal.look_at(fac.to_global(split + n * 0.7 + (along * cos(a) + Vector3.UP * sin(a)) * 0.25), Vector3.UP)
	var jet := _gas_wisps(Vector3(0.02, 0.02, 0.02), 110, 1.2, GAS, 0.16)   # a thin stream hissing out, spreading as it slows
	jet.position = split + n * 0.55 + Vector3(0, -0.1, 0)
	jet.direction = n + Vector3(0, -0.25, 0)
	jet.spread = 7.0
	jet.initial_velocity_min = 2.4
	jet.initial_velocity_max = 3.2
	jet.damping_min = 2.0
	jet.damping_max = 2.6
	jet.gravity = Vector3(0, -0.15, 0)
	var faint := Gradient.new()   # (fainter than the floor wisps were: many of them blur into one stream)
	faint.set_color(0, Color(GAS, 0.0))
	faint.add_point(0.25, Color(GAS, 0.09))
	faint.set_color(faint.get_point_count() - 1, Color(GAS, 0.0))
	jet.color_ramp = faint
	jet.emitting = true
	var leak: Vector3 = fac.to_global(jet.position)
	_loop3d("steam", leak, -22.0, 0.45)
	# Leaking canisters by it, one tipped over.
	var cans := base + n * 1.3 + along * 1.4
	for k in 3:
		var cp: Vector3 = cans + along * ((k - 1) * 0.42)
		if k == 2:
			var tipped := A.cyl(fac, 0.17, 1.2, cp + n * 0.4 + Vector3(0, 0.17, 0), "paint", Color(0.55, 0.62, 0.22), false, "x")
			tipped.rotation.y = atan2(n.x, n.z)
		else:
			A.cyl(fac, 0.17, 1.2, cp + Vector3(0, 0.6, 0), "paint", Color(0.55, 0.62, 0.22), true)
			A.cyl(fac, 0.175, 0.12, cp + Vector3(0, 0.95, 0), "hazard", Color.WHITE, false)
			A.cyl(fac, 0.05, 0.12, cp + Vector3(0, 1.26, 0), "brass", Color.WHITE, false)
	fac._solid(cans, Vector3(1.6, 1.3, 1.0))
	# A pool of it on the floor under the break: dark and oily.
	var pool := base + n * 1.0
	var pm := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.1
	disc.bottom_radius = 1.1
	disc.height = 0.01
	disc.radial_segments = 20
	pm.mesh = disc
	var goo := StandardMaterial3D.new()
	goo.albedo_color = Color(0.13, 0.15, 0.06)
	goo.emission_enabled = true
	goo.emission = Color(0.35, 0.42, 0.12)
	goo.emission_energy_multiplier = 0.12
	goo.roughness = 0.04
	goo.metallic = 0.15
	pm.material_override = goo
	pm.scale = Vector3(1.0, 1.0, 0.7)
	fac.add_child(pm)
	pm.position = pool + Vector3(0, 0.006, 0)
	pm.rotation.y = atan2(n.x, n.z)
	pm.set_meta("live", true)
	for k in 14 * 8:   # (the dice the crystals round it used to take: everything after rolls as it did)
		rng.randf()
	var bubble := OmniLight3D.new()   # the pool's faint sickly sheen on what's near it (stopped by walls)
	bubble.light_color = Color(0.7, 0.85, 0.35)
	bubble.light_energy = 0.22
	bubble.omni_range = 4.5
	bubble.shadow_enabled = true
	B.fade(bubble)
	fac.add_child(bubble)
	bubble.position = pool + Vector3(0, 0.4, 0)
	# A rotating beacon on the wall: a caged amber dome on a bracket, its beam sweeping the gas.
	# Its lights cast shadows, so neither the beam nor the glow gets through the walls.
	var bw: Array = walls[(walls.find(w) + 1) % walls.size()] if walls.size() > 1 else w
	var bn: Vector3 = bw[2]
	# The wall's face is 0.15 m out from its centre line (where _wall_spot measures from).
	var bpos: Vector3 = fac._wall_spot(bw, rng.randf_range(-3.0, 3.0), 0.48) + Vector3(0, 2.75, 0)
	var face_rot := atan2(bn.x, bn.z)
	var on_wall: Vector3 = bpos - bn * 0.3   # 0.18 out: the back of the plate sits on the wall face
	A.box(fac, Vector3(0.34, 0.4, 0.04), on_wall + Vector3(0, -0.06, 0), "metal", Color(0.22, 0.22, 0.22), false, 0.3, Vector3(0, face_rot, 0))   # wall plate
	for sx in [-0.12, 0.12]:
		for sy in [0.07, -0.19]:
			A.cyl(fac, 0.015, 0.02, on_wall + bn * 0.025 + Vector3(0, sy, 0) + Vector3(bn.z, 0, -bn.x) * sx, "metal", Color(0.5, 0.5, 0.5), false, "z" if absf(bn.z) > 0.5 else "x")   # bolts
	A.box(fac, Vector3(0.08, 0.08, 0.3), on_wall + bn * 0.15 + Vector3(0, -0.14, 0), "metal", Color(0.25, 0.25, 0.25), false, 0.3, Vector3(0, face_rot, 0))   # arm out from the plate
	A.cyl(fac, 0.17, 0.12, bpos + Vector3(0, -0.12, 0), "metal", Color(0.15, 0.15, 0.15))                     # base, on the end of the arm
	var dome := A.sphere(fac, 0.15, bpos + Vector3(0, 0.0, 0), "cream", Color(1.0, 0.55, 0.08), 3.5, 1.4)    # amber dome
	dome.set_meta("live", true)
	for k in 4:   # wire cage
		var a := TAU * k / 4.0
		A.seg(fac, bpos + Vector3(cos(a) * 0.17, -0.06, sin(a) * 0.17), bpos + Vector3(cos(a) * 0.1, 0.2, sin(a) * 0.1), 0.008, 0.008, "metal", Color(0.2, 0.2, 0.2))
	A.ring(fac, 0.17, 0.155, bpos + Vector3(0, 0.05, 0), "metal", Color(0.2, 0.2, 0.2))
	var spin := Node3D.new()
	fac.add_child(spin)
	spin.position = bpos
	for k in 2:   # two beams back to back, like a real beacon's reflector
		var beam := SpotLight3D.new()
		beam.light_color = Color(1.0, 0.55, 0.12)
		beam.light_energy = 4.0
		beam.spot_range = 10.0
		beam.spot_angle = 18.0
		beam.shadow_enabled = true
		beam.light_volumetric_fog_energy = 4.0   # the beam shows in the gas
		B.fade(beam)
		spin.add_child(beam)
		beam.rotation = Vector3(-0.3, PI * k, 0)
		beam.position = Vector3(0, 0, 0) + beam.basis * Vector3(0, 0, -0.2)   # out past the dome, so it doesn't shadow itself
	A.spin(spin, "y", 1.6)
	var halo := OmniLight3D.new()   # the dome's own glow on the wall round it
	halo.light_color = Color(1.0, 0.55, 0.12)
	halo.light_energy = 0.8
	halo.omni_range = 2.5
	halo.shadow_enabled = true
	B.fade(halo)
	fac.add_child(halo)
	halo.position = bpos + bn * 0.25
	_loop3d("alarm", fac.to_global(bpos), -26.0, 0.6)


## A volume of the gas (local position): a room's (`door` x < 0), or a spill out under a doorway
## coming in at `door` (UVW). GAS_FOG does the rest.
static var _gas_shader: Shader

func _gas_fog(at: Vector3, size: Vector3, door := Vector3(-1, -1, -1)) -> FogVolume:
	if _gas_shader == null:
		_gas_shader = Shader.new()
		_gas_shader.code = GAS_FOG
	var fog := FogVolume.new()
	fog.size = size
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var fm := ShaderMaterial.new()
	fm.shader = _gas_shader
	fm.set_shader_parameter("lumps", _gas_noise)
	fm.set_shader_parameter("tint", Vector3(GAS.r, GAS.g, GAS.b))
	fm.set_shader_parameter("door", door)
	fog.material = fm
	fac.add_child(fog)
	fog.position = at
	return fog


## Soft puffs of gas, fading in and out (the jet out of the burst line).
func _gas_wisps(extents: Vector3, amount: int, life: float, c: Color, size := 2.2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true   # (without it every puff draws at its mesh's size, whatever its scale)
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex()
	q.material = m
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(1, 0, 0)
	p.spread = 180.0
	p.flatness = 0.9
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.3
	p.gravity = Vector3.ZERO
	p.angular_velocity_min = -12.0
	p.angular_velocity_max = 12.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var grow := Curve.new()
	grow.max_value = 1.3   # (a Curve clamps to 0..1 otherwise)
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(c, 0.0))
	fade.add_point(0.3, Color(c, 0.22))
	fade.add_point(0.7, Color(c.darkened(0.2), 0.16))
	fade.set_color(fade.get_point_count() - 1, Color(c, 0.0))
	p.color_ramp = fade
	p.emitting = false
	fac.add_child(p)
	return p


func _soft_tex() -> Texture2D:
	if _soft == null:
		_soft = GradientTexture2D.new()
		_soft.width = 64
		_soft.height = 64
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft.gradient = g
	return _soft


# --- steam -----------------------------------------------------------------------------------

func _steam_tunnel(c: Vector2i) -> void:
	var n: Vector2i = fac.layout.links[c][0]
	var axis := Vector3(n.x - c.x, 0, n.y - c.y)
	var side := Vector3(axis.z, 0, axis.x)
	var s := _side()
	var o := Vector3(c.x * Facility.CELL, 0, c.y * Facility.CELL)
	_steam_line(o + axis * rng.randf_range(-3.5, 3.5) + side * (s * 2.08), -side * s)


func _steam_room(c: Vector2i) -> void:
	var o := Vector3(c.x * Facility.CELL, 0, c.y * Facility.CELL)
	for d in Facility.DIRS:
		if fac.layout.links[c].has(c + d) or fac.vents.has(Facility.edge(c, c + d)):
			continue
		var dv := Vector3(d.x, 0, d.y)
		var along := Vector3(d.y, 0, d.x)
		var at := o + dv * (Facility.CELL / 2.0 - 0.2) + along * rng.randf_range(-1.2, 1.2)
		_steam_line(at, -dv)
		return


## A pipe down the wall with a split joint pointing `dir` (local, into the room) at chest height,
## a pressure gauge that climbs into the red before it blows, and a wet patch where it lands.
func _steam_line(at: Vector3, dir: Vector3) -> void:
	var nozzle := at + Vector3(0, 1.35, 0)
	var rust := Color(0.75, 0.6, 0.5)
	var side := Vector3(dir.z, 0, -dir.x)
	A.cyl(fac, 0.1, Facility.H, at + Vector3(0, Facility.H / 2.0, 0) - dir * 0.05, "rust", rust)
	A.ring(fac, 0.16, 0.12, at + Vector3(0, 1.95, 0) + side * 0.15 + dir * 0.1, "metal", Color(0.75, 0.15, 0.1), Vector3(0, atan2(dir.x, dir.z), PI / 2))   # valve wheel
	A.cyl(fac, 0.11, 0.06, at + Vector3(0, 0.9, 0) + dir * 0.12, "hazard", Color.WHITE, false, "y")
	# The split joint lives on its own node so it can rattle.
	var stub := Node3D.new()
	fac.add_child(stub)
	stub.position = nozzle
	stub.set_meta("rest", nozzle)
	A.seg(stub, -dir * 0.05, dir * 0.3, 0.07, 0.07, "rust", rust)
	A.seg(stub, dir * 0.28, dir * 0.36, 0.1, 0.1, "metal", Color(0.4, 0.38, 0.36))   # flange
	A.seg(stub, dir * 0.36, dir * 0.4, 0.085, 0.1, "rust", rust.darkened(0.3))      # torn lip
	for k in 4:   # bolts round the flange
		var a := TAU * k / 4.0 + 0.4
		A.sphere(stub, 0.018, dir * 0.33 + (side * cos(a) + Vector3.UP * sin(a)) * 0.085, "metal", Color(0.3, 0.3, 0.3))
	# Pressure gauge on a short riser beside the joint.
	var gpos := at + Vector3(0, 1.7, 0) - side * 0.22 + dir * 0.12
	A.seg(fac, at + Vector3(0, 1.7, 0) - dir * 0.02, gpos, 0.02, 0.02, "metal", Color(0.5, 0.48, 0.45))
	var gauge := P._root(fac, gpos, atan2(-dir.x, -dir.z))
	gauge.scale = Vector3.ONE * 1.35
	A.cyl(gauge, 0.09, 0.05, Vector3(0, 0, -0.02), "brass", Color.WHITE, false, "z")
	A.cyl(gauge, 0.078, 0.01, Vector3(0, 0, -0.048), "paper", Color(0.92, 0.9, 0.82), false, "z")
	for k in 3:   # the red zone at the top right of the dial
		var a := 0.15 + k * 0.28
		A.box(gauge, Vector3(0.03, 0.012, 0.004), Vector3(sin(a) * 0.058, cos(a) * 0.058, -0.055), "paint", Color(0.85, 0.1, 0.05), false, 1.0, Vector3(0, 0, -a))
	var needle := Node3D.new()
	gauge.add_child(needle)
	needle.position = Vector3(0, 0, -0.058)
	A.box(needle, Vector3(0.008, 0.065, 0.004), Vector3(0, 0.028, 0), "paint", Color(0.1, 0.1, 0.1), false)
	needle.rotation.z = 2.2
	# Wet, glossy floor where the jet comes down: a soft-edged sheen, not a slab.
	var wet := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(2.6, 3.6)
	wet.mesh = wm
	var wmat := StandardMaterial3D.new()
	var wg := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.5))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	wg.gradient = grad
	wg.fill = GradientTexture2D.FILL_RADIAL
	wg.fill_from = Vector2(0.5, 0.5)
	wg.fill_to = Vector2(0.5, 0.0)
	wmat.albedo_texture = wg
	wmat.albedo_color = Color(0.05, 0.05, 0.05)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.04
	wet.material_override = wmat
	wet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fac.add_child(wet)
	wet.basis = Basis(Vector3.UP.cross(dir), Vector3.UP, dir)
	wet.position = Vector3(nozzle.x, 0.06, nozzle.z) + dir * 2.0

	var g: Vector3 = fac.to_global(nozzle + dir * 0.4)
	var gdir: Vector3 = (fac.global_transform.basis * dir).normalized()
	var fx := {}
	# Warning sputters: small hissing puffs out of the joint.
	fx.puff = _cloud(g, gdir, 0.35, 16, 0.9, 35.0, 0.8, 1.8, 0.22, Vector3(0, 0.5, 0))
	# The burst, in layers: a fast white core, a billowing plume, spray, the splash off the far wall.
	fx.core = _cloud(g, gdir, 0.22, 150, 0.4, 2.5, 11.0, 13.0, 0.55, Vector3.ZERO, 0.3, 1.1)
	fx.core.damping_min = 14.0
	fx.core.damping_max = 18.0
	fx.plume = _cloud(g, gdir, 0.7, 70, 1.7, 13.0, 5.0, 8.0, 0.13, Vector3(0, 0.7, 0), 0.4, 3.2)
	fx.plume.damping_min = 3.0
	fx.plume.damping_max = 5.0
	fx.spray = _particles(Color(0.85, 0.9, 0.95, 0.7), 0.035, 50, 0.7, gdir, 10.0, 6.0, 10.0, Vector3(0, -9.8, 0))
	fx.spray.global_position = g
	fx.splash = _cloud(g + gdir * JET_LEN, -gdir, 0.8, 40, 1.3, 75.0, 1.2, 2.8, 0.14, Vector3(0, 0.6, 0), 0.5, 2.6)
	fx.mist = _cloud(g + gdir * (JET_LEN * 0.5), Vector3.UP, 1.2, 36, 3.5, 180.0, 0.05, 0.3, 0.07, Vector3(0, 0.08, 0), 0.6, 2.2)
	fx.mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fx.mist.emission_box_extents = Vector3(0.5, 0.5, 0.5) + gdir.abs() * (JET_LEN * 0.5)
	# Scattered light inside the cloud, and the heat shimmer around the jet.
	fx.light = B.omni(self, Vector3.ZERO, Color(0.85, 0.9, 1.0), 0.0, 5.0)
	fx.light.global_position = g + gdir * 1.6
	fx.light.light_volumetric_fog_energy = 4.0
	fx.haze = _shimmer(g, gdir)
	var loop := _loop3d("steam", g, -12.0, 1.0)
	loop.stop()
	var rattle := _loop3d("rattle", g, -10.0, 1.4)
	rattle.stop()
	var first := rng.randf_range(2.0, 7.0)
	steams.append({"at": g, "dir": gdir, "t": first, "state": 0, "fx": fx, "loop": loop, "rattle": rattle,
		"stub": stub, "needle": needle, "idle": first, "reach": JET_LEN})


func _steam_tick(st: Dictionary, delta: float) -> void:
	st.t -= delta
	var fx: Dictionary = st.fx
	var needle: Node3D = st.needle
	var stub: Node3D = st.stub
	match st.state:
		0:   # building pressure: the needle creeps up
			needle.rotation.z = lerpf(needle.rotation.z, lerpf(2.2, 0.6, clampf(1.0 - st.t / st.idle, 0.0, 1.0)), minf(1.0, delta * 3.0))
		1:   # warning: hissing joint, rattling pipe, needle in the red
			needle.rotation.z = -0.3 + randf_range(-0.12, 0.12)
			stub.position.x += randf_range(-0.004, 0.004)
			stub.position.y += randf_range(-0.004, 0.004)
			if randf() < 0.08:
				fx.puff.emitting = not fx.puff.emitting   # it spits, it doesn't flow
		2:   # blasting
			fx.light.light_energy = randf_range(0.5, 0.9)
			fx.haze.set_shader_parameter("strength", 1.0)
			stub.position.x += randf_range(-0.003, 0.003)
			for p in main.players():
				if p.dead:
					continue
				var chest: Vector3 = p.global_position + Vector3(0, p.shape.height * 0.75, 0)
				var rel: Vector3 = chest - st.at
				var t: float = rel.dot(st.dir)
				var off: float = (rel - st.dir * t).length()
				if t > 0.0 and t < st.reach and off < JET_R:
					if main.net.authority():
						p.hurt(26.0 * delta, "Scalded by a burst steam line.")
					if p == main.player:
						p.velocity += st.dir * 30.0 * delta
						main.hud.fog_visor(0.9)
						_say("steam", "Steam! Wait for it to stop, or crouch under the jet.")
				elif p == main.player and t > -0.5 and t < st.reach + 1.0 and off < JET_R + 1.6:
					main.hud.fog_visor(0.35 * (1.0 - (off - JET_R) / 1.6))
		3:   # sputtering out, leaving a hanging mist
			var spurt := randf() < 0.12
			fx.core.emitting = spurt
			fx.puff.emitting = true
			fx.light.light_energy = move_toward(fx.light.light_energy, 0.0, delta * 1.5)
			fx.haze.set_shader_parameter("strength", maxf(0.0, st.t))
			stub.position = stub.position.lerp(stub.get_meta("rest"), 0.2)
	if st.t <= 0.0 and main.net.authority():   # (the host decides when; the crew follows)
		var nxt: int = (st.state + 1) % 4
		_steam_go(st, nxt, rng.randf_range(3.5, 7.0))
		main.net.event("hz", ["steam", steams.find(st), nxt, st.idle])
	if st.state == 0:
		stub.position = stub.get_meta("rest")


func _steam_go(st: Dictionary, n: int, idle: float) -> void:
	var fx: Dictionary = st.fx
	var loop: AudioStreamPlayer3D = st.loop
	st.state = n
	match n:
		1:
			st.t = 1.3
			fx.puff.emitting = true
			loop.volume_db = -14.0
			loop.pitch_scale = 1.7
			loop.play()
			st.rattle.play()
		2:
			st.t = 2.2
			st.reach = _reach(st)
			for k in ["core", "plume", "spray", "splash"]:
				fx[k].emitting = true
			fx.splash.emitting = st.reach < JET_LEN + 0.4   # hits a wall: billows back off it
			fx.splash.global_position = st.at + st.dir * (st.reach - 0.2)
			fx.puff.emitting = false
			st.rattle.stop()
			loop.volume_db = 4.0
			loop.pitch_scale = 0.9
			Sfx.play(self, "steam_burst", st.at, 3.0)
			Sfx.play(self, "clang_big", st.at, -2.0, 1.7)
			main.noise(st.at, 12.0)
			for p in main.players():
				if p.global_position.distance_to(st.at) < 6.0:
					p.shake(0.03)
		3:
			st.t = 0.9
			for k in ["core", "plume", "spray", "splash"]:
				fx[k].emitting = false
			fx.mist.emitting = true
			loop.volume_db = -6.0
			loop.pitch_scale = 1.3
		0:
			st.idle = idle
			st.t = st.idle
			fx.core.emitting = false
			fx.puff.emitting = false
			fx.mist.emitting = false
			fx.light.light_energy = 0.0
			fx.haze.set_shader_parameter("strength", 0.0)
			loop.stop()
			Sfx.play(self, "hiss", st.at, -10.0, 1.4)


## How far the jet gets before something solid stops it.
func _reach(st: Dictionary) -> float:
	var q := PhysicsRayQueryParameters3D.create(st.at, st.at + st.dir * (JET_LEN + 0.5), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return st.at.distance_to(hit.position) if not hit.is_empty() else JET_LEN + 0.5


## Billowing steam: lit by the scene (your flashlight catches it), soft cloud sprites that turn as they drift.
func _cloud(at: Vector3, dir: Vector3, size: float, amount: int, life: float, spread: float, v0: float, v1: float, alpha: float, gravity: Vector3, grow0 := 0.3, grow1 := 1.6) -> CPUParticles3D:
	var p := _particles(Color(0.93, 0.94, 0.95, alpha), size, amount, life, dir, spread, v0, v1, gravity)
	var m: StandardMaterial3D = (p.mesh as QuadMesh).material
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_texture = _cloud_tex()
	m.emission_enabled = true
	m.emission = Color(0.2, 0.21, 0.22)   # never quite vanishes in the dark
	m.disable_receive_shadows = true
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	var grow := Curve.new()
	grow.max_value = 4.0
	grow.add_point(Vector2(0, grow0))
	grow.add_point(Vector2(1, grow1))
	p.scale_amount_curve = grow
	var fade := Gradient.new()   # fades in fast, out slow
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.12, Color(1, 1, 1, 1))
	p.color_ramp = fade
	p.global_position = at
	return p


static var _cloud_cache: ImageTexture

static func _cloud_tex() -> ImageTexture:
	if _cloud_cache == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.09
		n.fractal_octaves = 3
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var r := Vector2(x - 31.5, y - 31.5).length() / 32.0
				var a := clampf(1.0 - r, 0.0, 1.0)
				a = a * a * (3.0 - 2.0 * a) * clampf(0.55 + n.get_noise_2d(x, y) * 0.9, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_cloud_cache = ImageTexture.create_from_image(img)
	return _cloud_cache


## Heat shimmer: a cylinder along the jet that bends whatever is behind it.
func _shimmer(at: Vector3, dir: Vector3) -> ShaderMaterial:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.12
	cm.height = JET_LEN
	mi.mesh = cm
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
void fragment() {
	float face = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.5);
	vec2 wob = vec2(sin(UV.y * 38.0 - TIME * 34.0 + UV.x * 14.0), cos(UV.y * 31.0 - TIME * 27.0 + UV.x * 9.0));
	ALBEDO = textureLod(screen, SCREEN_UV + wob * 0.007 * strength * face, 0.0).rgb;
	ALPHA = face * strength;
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + dir * (JET_LEN * 0.5)
	mi.global_basis = Basis(Quaternion(Vector3.UP, dir))   # narrow end at the joint
	return m


# --- power -----------------------------------------------------------------------------------

func _breaker() -> void:
	var cells: Array = fac.layout.cells.filter(func(c): return not fac.kinds[c] in ["start", "pit", "tunnel", "vault", "stairwell"] and not gassed.has(c))
	_shuffle(cells)
	cells.sort_custom(func(a, b): return absi(a.x) + absi(a.y) > absi(b.x) + absi(b.y))   # somewhere out of the way
	cells = cells.slice(0, maxi(1, cells.size() / 2))
	_shuffle(cells)
	cells.append(Vector2i.ZERO)
	var fallback: Array = []
	for c in cells:
		var o := Vector3(c.x * Facility.CELL, 0, c.y * Facility.CELL)
		for d in Facility.DIRS:
			if fac.layout.links[c].has(c + d) or fac.vents.has(Facility.edge(c, c + d)):
				continue
			var dv := Vector3(d.x, 0, d.y)
			var along := Vector3(d.y, 0, d.x)
			for off in [0.0, 2.6, -2.6, 4.2, -4.2]:
				var foot: Vector3 = o + dv * (Facility.CELL / 2.0 - 0.6) + along * off
				var blocked: bool = c == Vector2i.ZERO and absf(off) < 3.0   # lift shaft
				for box in fac.crates:
					if box.grow(0.5).has_point(Vector3(foot.x, foot.y + 0.05, foot.z)):
						blocked = true
				if blocked:
					continue
				if fallback.is_empty():
					fallback = [o + dv * (Facility.CELL / 2.0 - 0.17) + along * off, -dv]
				if fac._clear_spot(o + dv * (Facility.CELL / 2.0) + along * off, -dv, 1.3, 0.5, 2.6, 0.55):   # (not over a shelf, a sign, a pipe)
					_build_breaker(o + dv * (Facility.CELL / 2.0 - 0.17) + along * off, -dv)
					return
	if not fallback.is_empty():
		_build_breaker(fallback[0], fallback[1])


const LEVER_ON := -0.3     # the breaker's handle up (local -z is the room: it leans out a little)...
const LEVER_OFF := -2.65  # ...and thrown down, swung out through the front (never into the wall)


## The main breaker: a deep steel isolator cabinet on two wall rails, its door panelled and hinged
## down the left with a locking handle; on the door the nameplate, a yellow DANGER plate, a voltmeter
## and the pilot lamps, and a glazed window onto the rows of breakers inside. The big operating
## handle on its right side (up ON, down OFF), on a boss with a quadrant plate. Conduits climb from
## its top to the ceiling. Local -z faces the room, y up from the floor.
func _build_breaker(pos: Vector3, normal: Vector3) -> void:
	breaker = P._root(fac, pos, atan2(-normal.x, -normal.z))
	var paint := Color(0.36, 0.43, 0.38)
	var dark := paint.darkened(0.5)
	var galv := Color(0.62, 0.63, 0.6)
	for y in [0.82, 1.98]:   # the wall rails it hangs on
		A.box(breaker, Vector3(1.2, 0.06, 0.045), Vector3(0, y, -0.023), "metal", galv, false, 0.5)
		for x in [-0.55, 0.55]:
			A.cyl(breaker, 0.018, 0.02, Vector3(x, y, -0.05), "metal", galv.darkened(0.2), false, "z")
	A.box(breaker, Vector3(0.84, 1.16, 0.3), Vector3(0, 1.4, -0.2), "enamel", paint, false, 1.0)   # the cabinet
	A.box(breaker, Vector3(0.86, 0.04, 0.32), Vector3(0, 2.0, -0.2), "enamel", paint.darkened(0.15), false, 1.0)   # its drip lip
	A.box(breaker, Vector3(0.78, 1.08, 0.025), Vector3(0, 1.4, -0.362), "enamel", paint.lightened(0.05), false, 1.0)   # the door
	for e in [[Vector3(0.78, 0.012, 0.01), Vector3(0, 1.94, -0.376)], [Vector3(0.78, 0.012, 0.01), Vector3(0, 0.86, -0.376)],
			[Vector3(0.012, 1.08, 0.01), Vector3(-0.39, 1.4, -0.376)], [Vector3(0.012, 1.08, 0.01), Vector3(0.39, 1.4, -0.376)]]:
		A.box(breaker, e[0], e[1], "metal", dark, false, 0.5)   # the door's seam
	for y in [1.0, 1.4, 1.8]:   # hinges down the left
		A.cyl(breaker, 0.018, 0.12, Vector3(-0.405, y, -0.37), "metal", galv.darkened(0.3))
	A.cyl(breaker, 0.03, 0.03, Vector3(0.3, 1.32, -0.385), "metal", galv, false, "z")   # the locking handle
	A.box(breaker, Vector3(0.025, 0.12, 0.025), Vector3(0.3, 1.3, -0.405), "metal", Color(0.15, 0.15, 0.15), false, 0.3)
	# The nameplate and the danger plate.
	A.box(breaker, Vector3(0.56, 0.11, 0.008), Vector3(-0.04, 1.84, -0.378), "enamel", Color(0.1, 0.1, 0.1), false, 0.5)
	var plate := B.label(breaker, "MAIN BREAKER", Vector3(-0.04, 1.84, -0.383), 15, Color(0.95, 0.9, 0.75), "plate", 0.0045)
	plate.rotation.y = PI
	A.box(breaker, Vector3(0.32, 0.12, 0.008), Vector3(-0.1, 1.67, -0.378), "enamel", Color(0.95, 0.75, 0.1), false, 0.5)
	var danger := B.label(breaker, "DANGER  440 V", Vector3(-0.1, 1.67, -0.383), 13, Color(0.08, 0.08, 0.08), "stencil", 0.0035)
	danger.rotation.y = PI
	# The voltmeter: a round case, a cream dial, the needle.
	A.cyl(breaker, 0.075, 0.04, Vector3(-0.2, 1.47, -0.39), "metal", Color(0.12, 0.12, 0.12), false, "z")
	A.cyl(breaker, 0.062, 0.005, Vector3(-0.2, 1.47, -0.411), "cream", Color(0.92, 0.9, 0.82), false, "z")
	A.box(breaker, Vector3(0.006, 0.05, 0.004), Vector3(-0.2, 1.485, -0.415), "metal", Color(0.7, 0.1, 0.08), false, 0.3, Vector3(0, 0, -0.5))
	# The pilot lamps: the big one green while there's power, red when it's tripped; amber beside it.
	for x in [0.02, 0.15]:
		A.cyl(breaker, 0.04, 0.03, Vector3(x, 1.47, -0.385), "metal", Color(0.75, 0.74, 0.7), false, "z")
	_lamp_bulb = A.sphere(breaker, 0.03, Vector3(0.02, 1.47, -0.405), "cream", Color(0.3, 1, 0.35), 4.0)
	_bulb_mat = _lamp_bulb.material_override
	A.sphere(breaker, 0.03, Vector3(0.15, 1.47, -0.405), "cream", Color(0.5, 0.32, 0.05), 0.4)
	# The window onto the breakers inside.
	A.box(breaker, Vector3(0.5, 0.3, 0.01), Vector3(-0.05, 1.12, -0.378), "metal", Color(0.05, 0.06, 0.06), false, 0.5)
	for r in 2:
		for k in 8:
			A.box(breaker, Vector3(0.035, 0.07, 0.01), Vector3(-0.26 + k * 0.06, 1.06 + r * 0.12, -0.38), "plastic", Color(0.85, 0.84, 0.8) if (k + r) % 5 else Color(0.8, 0.15, 0.1), false, 0.3)
	var pane := A.box(breaker, Vector3(0.52, 0.32, 0.004), Vector3(-0.05, 1.12, -0.387), "metal", Color.WHITE, false, 0.5)
	(pane as MeshInstance3D).material_override = A.glass()
	# The operating handle on the right side, its quadrant marked ON at the top and OFF at the bottom.
	A.cyl(breaker, 0.2, 0.015, Vector3(0.43, 1.45, -0.2), "enamel", paint.darkened(0.25), false, "x")
	A.box(breaker, Vector3(0.012, 0.06, 0.05), Vector3(0.44, 1.45 + 0.17, -0.2 - 0.05), "enamel", Color(0.2, 0.75, 0.25), false, 0.3)   # ON
	A.box(breaker, Vector3(0.012, 0.06, 0.05), Vector3(0.44, 1.45 - 0.13, -0.2 - 0.14), "enamel", Color(0.8, 0.15, 0.1), false, 0.3)   # OFF
	A.cyl(breaker, 0.055, 0.08, Vector3(0.47, 1.45, -0.2), "metal", Color(0.2, 0.2, 0.2), false, "x")
	_lever = Node3D.new()
	breaker.add_child(_lever)
	_lever.position = Vector3(0.5, 1.45, -0.2)
	A.box(_lever, Vector3(0.035, 0.42, 0.05), Vector3(0, 0.21, 0), "metal", Color(0.62, 0.62, 0.6), false, 0.4)
	A.cyl(_lever, 0.035, 0.16, Vector3(0.05, 0.42, 0), "rubber", Color(0.78, 0.1, 0.07), false, "x")
	_lever.rotation.x = LEVER_ON
	# Conduits up to the ceiling, with couplings, out of a junction box on its top.
	A.box(breaker, Vector3(0.36, 0.12, 0.16), Vector3(-0.1, 2.08, -0.12), "metal", galv, false, 0.5)
	for x in [-0.22, 0.02]:
		A.cyl(breaker, 0.035, Facility.H - 2.14, Vector3(x, (Facility.H + 2.14) / 2.0, -0.1), "metal", galv.darkened(0.15))
		for y in [2.5, 3.2]:
			A.cyl(breaker, 0.045, 0.06, Vector3(x, y, -0.1), "metal", galv)
	_lamp = B.omni(self, Vector3.ZERO, Color(0.3, 1, 0.35), 0.4, 2.5)
	_lamp.global_position = breaker.to_global(Vector3(0.02, 1.47, -0.6))
	B.interactable(breaker, Vector3(1.05, 1.2, 0.5), Vector3(0.08, 1.4, -0.25), Color(0, 0, 0, 0), "Reset the main breaker", restore, 1.4)
	breaker.add_to_group("scan_targets")
	breaker.set_meta("scan_name", "MAIN BREAKER")


func power_fail() -> void:
	if not power or fac == null:
		return
	power = false
	var lights: Array = fac.find_children("*", "Light3D", true, false)
	_dark.clear()
	for l in lights:
		_dark.append([l, l.visible])
	for i in 6:   # stutter before it goes
		for l in lights:
			l.visible = randf() < 0.5
		await get_tree().create_timer(randf_range(0.08, 0.2), false).timeout
	for l in lights:
		l.visible = false
	_dimmed.clear()
	var dim := {}
	for mi: MeshInstance3D in fac.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override is StandardMaterial3D and mi.material_override.emission_enabled:
			_dimmed.append([mi, -1, mi.material_override])
			mi.material_override = _dim(mi.material_override, dim)
		elif mi.mesh != null and mi.material_override == null:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				if m is StandardMaterial3D and m.emission_enabled:
					_dimmed.append([mi, s, mi.get_surface_override_material(s)])
					mi.set_surface_override_material(s, _dim(m, dim))
	for k in 2:   # emergency lamps by the lift
		var l := B.omni(self, Vector3.ZERO, Color(1, 0.12, 0.06), 0.6, 9.0)
		l.global_position = fac.to_global(Vector3(-3.2 + k * 6.4, Facility.H - 0.4, -3.2))
		_emergency.append(l)
	# On battery: a red lamp in a corner of every room, and a turning beacon in some.
	var n := 0
	for c: Vector2i in fac.layout.cells:
		if c == Vector2i.ZERO or n >= 18:
			continue
		n += 1
		var o := Vector3(c.x * Facility.CELL, 0, c.y * Facility.CELL)
		var corner := Vector3(2.8 if (c.x + c.y) % 2 == 0 else -2.8, Facility.H - 0.12, 2.8)
		var box := A.box(fac, Vector3(0.34, 0.12, 0.16), o + corner, "metal", Color(0.2, 0.2, 0.2), false)
		var lens := A.glow(fac, Vector3(0.28, 0.06, 0.1), o + corner + Vector3(0, -0.08, 0), Color(1, 0.12, 0.06), 4.0)
		var l := B.omni(fac, o + corner + Vector3(0, -0.4, 0), Color(1, 0.12, 0.06), 1.3, 11.0)
		_emergency.append(l)
		_emergency_parts.append_array([box, lens])
		if n % 3 == 1:
			var b := Node3D.new()   # a beacon on the ceiling: a red dome and a beam sweeping round
			fac.add_child(b)
			b.position = o + Vector3(0, Facility.H - 0.05, 0)
			A.cyl(b, 0.12, 0.08, Vector3(0, -0.04, 0), "metal", Color(0.15, 0.15, 0.15))
			A.sphere(b, 0.1, Vector3(0, -0.12, 0), "cream", Color(1, 0.15, 0.08), 3.0)
			var beam := SpotLight3D.new()
			beam.light_color = Color(1, 0.15, 0.08)
			beam.light_energy = 3.0
			beam.spot_range = 9.0
			beam.spot_angle = 22.0
			beam.light_volumetric_fog_energy = 3.0
			b.add_child(beam)
			beam.position = Vector3(0, -0.12, 0)
			beam.rotation.x = -0.6
			_beacons.append(b)
			_emergency_parts.append(b)
	_lamp.light_color = Color(1, 0.15, 0.1)
	_lamp_bulb.material_override = A.mat("cream", Color(1, 0.2, 0.15), 1.0, 4.0)
	var lt := create_tween()   # it trips: the handle drops
	lt.tween_property(_lever, "rotation:x", LEVER_OFF, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var below: bool = main.players().any(func(p): return _under(p))
	Sfx.play(main, "power_down", null, -2.0 if below else -14.0)
	if level.elevator:
		level.elevator.power_changed(false)
	for g in get_tree().get_nodes_in_group("gensets"):   # the generators stall
		if fac.is_ancestor_of(g):
			g.running = false
	if main.term.monitor.visible and main.term.feed.visible:
		main.term.hide_monitor()
		main.term.say("[color=#ff6a5a]FEED LOST: site power failure.[/color]")
	main.hud.alert("SITE POWER FAILURE   lift on emergency power   reset the MAIN BREAKER")


func _dim(m: StandardMaterial3D, cache: Dictionary) -> StandardMaterial3D:
	if not cache.has(m):
		var d := m.duplicate() as StandardMaterial3D
		d.emission_energy_multiplier *= 0.03
		d.albedo_color = d.albedo_color.darkened(0.6)
		cache[m] = d
	return cache[m]


func restore() -> void:
	if power:
		main.hud.msg("The breaker is already on. It hums.")
		return
	power = true
	var tw := create_tween()
	tw.tween_property(_lever, "rotation:x", LEVER_ON, 0.3).set_trans(Tween.TRANS_BACK)
	Sfx.play(self, "breaker", breaker.global_position + Vector3(0, 1.2, 0), 4.0)
	Sfx.play(main, "power_up", null, -4.0)
	main.noise(breaker.global_position, 25.0)
	for l in _emergency:
		l.queue_free()
	_emergency.clear()
	for e in _emergency_parts:
		if is_instance_valid(e):
			e.queue_free()
	_emergency_parts.clear()
	_beacons.clear()
	_lamp.light_color = Color(0.3, 1, 0.35)
	_lamp.light_energy = 0.4
	var from := breaker.global_position
	for d in _dark:   # lights come back in a wave out from the breaker
		var l: Light3D = d[0]
		if is_instance_valid(l):
			get_tree().create_timer(0.3 + l.global_position.distance_to(from) * 0.025, false).timeout.connect(func(): if is_instance_valid(l): l.visible = d[1])
	_dark.clear()
	for d in _dimmed:
		if is_instance_valid(d[0]):
			if d[1] < 0:
				d[0].material_override = d[2]
			else:
				d[0].set_surface_override_material(d[1], d[2])
	_dimmed.clear()
	_lamp_bulb.material_override = _bulb_mat
	if level.elevator:
		level.elevator.power_changed(true)
	for g in get_tree().get_nodes_in_group("gensets"):
		if fac.is_ancestor_of(g):
			g.running = true
	main.hud.msg("Site power restored.")


# --- tremor ----------------------------------------------------------------------------------

## `far`: the shock of something big a long way off (the airdrop plane coming down): felt underground
## only, the lights and the dust, no alarm, nothing woken, the power holds.
func tremor(far := false) -> void:
	var p = main.player
	var below := _under(p)
	if far and not below:
		return
	_tremor = 2.5 if far else 4.5
	Sfx.play(main, "quake", null, (-4.0 if far else 0.0) if below else -6.0)
	if not far:
		main.hud.alert("TREMOR")
		main.noise(p.global_position, 45.0)
	if not below:
		return
	if power:   # the lights shiver
		var lights: Array = fac.find_children("*", "Light3D", true, false)
		var was: Array = lights.map(func(l): return l.visible)
		for i in 5:
			for l in lights:
				l.visible = was[lights.find(l)] and randf() < 0.75
			await get_tree().create_timer(0.15, false).timeout
		if power:
			for i in lights.size():
				lights[i].visible = was[i]
	var dust := _particles(Color(0.7, 0.65, 0.58, 0.5), 0.04, 160, 2.2, Vector3.DOWN, 10.0, 0.3, 1.0, Vector3(0, -3.0, 0))
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(5, 0.1, 5)
	var low_dust: bool = fac.to_local(p.global_position).y < -1.0
	dust.global_position = Vector3(p.global_position.x, fac.global_position.y + (-0.35 if low_dust else Facility.H - 0.15), p.global_position.z)
	dust.emitting = true
	get_tree().create_timer(4.0, false).timeout.connect(func(): if is_instance_valid(dust): dust.emitting = false)
	get_tree().create_timer(7.0, false).timeout.connect(func(): if is_instance_valid(dust): dust.queue_free())
	for i in rng.randi_range(1, 3) if far else rng.randi_range(3, 6):
		get_tree().create_timer(rng.randf_range(0.4, 3.6), false).timeout.connect(_debris.bind(not far and i == 0 and rng.randf() < 0.5))
	if not far and power and main.net.authority() and rng.randf() < 0.3:
		await get_tree().create_timer(2.5, false).timeout
		power_fail()
		main.net.event("hz", ["power"])


## A chunk of ceiling (or something that was stored up there) comes down near the player.
func _debris(scrap: bool) -> void:
	var p = main.player
	if not is_instance_valid(p) or not _under(p) or fac == null:
		return
	var c: Vector2i = fac.cell_at(p.global_position)
	var low: bool = fac.to_local(p.global_position).y < -1.0
	if low and not fac.lower.has(c):
		return
	if not low and (not fac.kinds.has(c) or fac.kinds[c] in ["pit", "stairwell"]):
		return
	var floor_y: float = -Facility.PIT if low else 0.0
	var ceil_h: float = Facility.LOW_H if low else Facility.H
	var o := Vector3(c.x * Facility.CELL, 0, c.y * Facility.CELL)
	var lp: Vector3 = fac.to_local(p.global_position)
	var a := rng.randf() * TAU
	var r := rng.randf_range(0.6, 4.5)
	var spot := Vector3(lp.x + cos(a) * r, floor_y, lp.z + sin(a) * r)
	spot.x = clampf(spot.x, o.x - Facility.CELL / 2.0 + 0.8, o.x + Facility.CELL / 2.0 - 0.8)
	spot.z = clampf(spot.z, o.z - Facility.CELL / 2.0 + 0.8, o.z + Facility.CELL / 2.0 - 0.8)
	var top := spot + Vector3(0, ceil_h - 0.2, 0)
	var trickle := _particles(Color(0.7, 0.65, 0.58, 0.6), 0.03, 40, 0.9, Vector3.DOWN, 6.0, 0.5, 1.0, Vector3(0, -6.0, 0))
	trickle.global_position = fac.to_global(top)
	trickle.emitting = true
	Sfx.play(self, "creak", fac.to_global(top), -2.0, rng.randf_range(0.7, 0.9))
	await get_tree().create_timer(0.9, false).timeout
	if fac == null or not is_instance_valid(trickle):
		return
	trickle.emitting = false
	get_tree().create_timer(1.5, false).timeout.connect(func(): if is_instance_valid(trickle): trickle.queue_free())
	if scrap:
		main.spawn_item(Data.random_scrap(rng), fac.to_global(top - Vector3(0, 0.4, 0)), -1.0, level)
		main.hud.msg("Something came down with the ceiling.")
		return
	var s := rng.randf_range(0.3, 0.5)
	var chunk := A.box(fac, Vector3(s, s * 0.5, s * 0.8), top, "concrete", Color(0.75, 0.72, 0.68), false, 0.5, Vector3(rng.randf(), rng.randf(), rng.randf()))
	A.box(chunk, Vector3(s * 0.6, s * 0.35, s * 0.5), Vector3(s * 0.4, s * 0.1, -s * 0.2), "concrete", Color(0.7, 0.68, 0.64), false, 0.5, Vector3(0.4, 0.8, 0.2))
	A.seg(chunk, Vector3(-s * 0.3, 0, 0), Vector3(-s * 0.9, s * 0.4, s * 0.2), 0.012, 0.012, "rust", Color.WHITE)   # rebar
	var tw := create_tween()
	tw.tween_property(chunk, "position:y", floor_y + s * 0.3, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(chunk, "rotation:x", chunk.rotation.x + rng.randf_range(1.0, 3.0), 0.42)
	if tw.is_running():
		await tw.finished
	if fac == null or not is_instance_valid(chunk):
		return
	var at := chunk.global_position
	Sfx.play(self, "debris", at, 4.0, rng.randf_range(0.85, 1.1))
	A.rubble(fac, spot, rng)
	main.noise(at, 18.0)
	for pl in main.players():
		if not pl.dead and Vector2(pl.global_position.x - at.x, pl.global_position.z - at.z).length() < 1.0 + s * 0.5 and absf(pl.global_position.y - at.y) < 2.0:
			pl.hurt(35.0, "Crushed by falling debris.")
		if not pl.dead and pl.global_position.distance_to(at) < 6.0:
			pl.shake(0.06)


# --- airdrop ---------------------------------------------------------------------------------

## Somewhere on the surface, a fair walk from the lift.
func _drop_spot() -> Vector3:
	var land: Vector3 = level._surface_point()
	for tries in 30:
		var d := Vector2(land.x - level.elevator_pos.x, land.z - level.elevator_pos.z).length()
		if d > 25.0 and d < 70.0:
			break
		land = level._surface_point()
	return land


## A Bureau airdrop (airdrop.gd: the plane over, the crate coming down under its canopy, the flare).
func airdrop(land: Vector3 = Vector3.INF, spin := 0.0) -> void:
	if land == Vector3.INF:
		land = _drop_spot()
		spin = rng.randf() * TAU
	var d = load("res://src/airdrop.gd").new()
	d.setup(self, land, spin)


func _compass(v: Vector3) -> String:
	var a := fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)
	return ["NORTH", "NORTH-EAST", "EAST", "SOUTH-EAST", "SOUTH", "SOUTH-WEST", "WEST", "NORTH-WEST"][int(round(a / 45.0)) % 8]


# --- bits ------------------------------------------------------------------------------------

func _side() -> float:
	return 1.0 if rng.randf() < 0.5 else -1.0


func _particles(c: Color, size: float, amount: int, life: float, dir: Vector3, spread: float, v0: float, v1: float, gravity: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true   # (without it every puff draws at its mesh's size, whatever its scale)
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	if _soft == null:
		_soft = GradientTexture2D.new()
		_soft.width = 64
		_soft.height = 64
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft.gradient = g
	m.albedo_texture = _soft
	q.material = m
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.gravity = gravity
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.emitting = false
	add_child(p)
	return p


func _loop3d(sound: String, at: Vector3, db: float, pitch: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.stream = Sfx.stream(sound)
	a.bus = "World"
	a.volume_db = db
	a.pitch_scale = pitch
	a.unit_size = 5.0
	a.max_distance = 30.0
	add_child(a)
	a.global_position = at
	a.play()
	return a
