# Things that happen on the way (line.gd's ride drives this): what a trip holds is decided from the
# trip's seed, so a crew sees the same ones.
#
#   weather fronts   the train runs into a storm waiting at the next stop, out of one it's leaving,
#                    or through a squall: a wall of dust, rain or snow on the horizon, the sky, fog,
#                    sound and windows blending across as it goes through (main.line_weather/line_mix)
#   the other train  a freight coming the other way through a passing loop: its headlight and ditch
#                    lights flashing, horn, exhaust, a wall of noise and a buffet of air going by, its
#                    wagons swinging back onto the main line behind us
#   power failure    in a tunnel the car's lights stutter out, the red emergency lamps come up, the
#                    screens die; the tunnel's lamps sweep through the windows; then it all comes back
#   the thing        eyes in the headlight down the tunnel; it bolts, a pale long-limbed thing racing
#                    the train along the wall, then falling back past the windows into the dark. It
#                    follows you: one more of them at the next stop (main.followers).
# (The dead halt, with someone standing on it, is part of the line itself: line._halt.)
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")
const CP = preload("res://src/checkpoint.gd")
const Sfx = preload("res://src/sfx.gd")
const Merge = preload("res://src/merge.gd")

var main
var line

var _power := Vector2.INF     # line x the car's power fails at, and comes back at
var _power_state := 0         # 0 waiting, 1 off, 2 back
var _thing_at := INF
var _thing: Node3D
var _tp := {}                 # its parts
var _tstate := ""             # "", "wait", "bolt", "pace", "fall", "gone"
var _tx := 0.0                # where it is (line x, z) and how fast it's going
var _tz := 0.0
var _tu := 0.0
var _tt := 0.0
var _tgait := 0.0
var _tstep := 0.0
var _wx: Array = []           # [line x, mix] points: how far into the front's weather
var _wkind := ""
var _curtains: Array = []     # [node, material]
var _freight: Node3D
var _cars: Array = []         # [node, distance behind the head]
var _fhead := 0.0
var _fgo := INF               # start it moving once the train's here
var _fmoving := false
var _fstart := 0.0
var _fbits := {}              # its lights, sounds, smoke
var _fhorn := false
var _fpassed := false
var _fclack := 0.0


func clear() -> void:
	for c in _curtains:
		if is_instance_valid(c[0]):
			c[0].queue_free()
	_curtains.clear()
	if is_instance_valid(_freight):
		_freight.queue_free()
	if is_instance_valid(_thing):
		_thing.queue_free()
	_freight = null
	_thing = null
	_cars.clear()
	_fbits.clear()
	_power = Vector2.INF
	_power_state = 0
	_thing_at = INF
	_tstate = ""
	_wx.clear()
	_wkind = ""
	_fgo = INF
	_fmoving = false
	_fhorn = false
	_fpassed = false
	if main != null:
		main.line_weather = ""
		main.line_mix = 0.0
		if main.env != null:
			main.env.volumetric_fog_length = 80.0


## What this trip holds. `t` the tunnel, `arr_x` where the next stop's middle is (line x).
func plan(dest: Dictionary, seed: int, t: Dictionary, from_cp: bool, to_cp: bool, arr_x: float) -> void:
	clear()
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed, "line events"])
	var force: Array = Engine.get_meta("force_events") if Engine.has_meta("force_events") else []
	var bore_a: float = t.a + (line.BORE_IN if t.entry else 0.0)
	var bore_b: float = t.b - (line.BORE_IN if t.exit == "portal" else 0.0)
	# The power, in the tunnel.
	var roll := r.randf()
	if "power" in force or roll < 0.22:
		var at: float = r.randf_range(bore_a + 30.0, bore_a + 80.0)
		_power = Vector2(at, minf(at + r.randf_range(90.0, 140.0), bore_b + 25.0))
	# The thing, in the tunnel.
	roll = r.randf()
	if "thing" in force or roll < 0.14:
		_thing_at = r.randf_range(bore_a + 45.0, bore_a + 75.0)
		main.followers += 1   # (decided now, the same everywhere: the next stop has one more)
		_build_thing()
	# Weather: the stop we're leaving and the one we're going to, and maybe a squall between.
	var wa: String = "CLEAR" if main.at_checkpoint else str(main.stop.get("weather", "CLEAR"))
	var wb: String = "CLEAR" if to_cp else str(dest.get("weather", "CLEAR"))
	var arctic_b: bool = dest.get("biome", "") == "ARCTIC"
	roll = r.randf()
	if _stormy(wa) and not _stormy(wb) and not from_cp:   # running out of it, before the tunnel
		var fx: float = r.randf_range(line.HALF + 40.0, t.a - 50.0)
		_wkind = wb if wb != "CLEAR" else "OVERCAST"
		_wx = [[fx - 40.0, 0.0], [fx + 120.0, 1.0], [t.a + line.SWAP_IN - 1.0, 1.0]]
		_curtain(fx, wa, -1.0, r)
	elif _stormy(wb) and not _stormy(wa) and not to_cp:   # into one waiting at the next stop
		var fx: float = r.randf_range(t.b + 70.0, arr_x - line.HALF - 120.0)
		_wkind = wa if not _stormy(wa) else "CLEAR"
		_wx = [[t.a + line.SWAP_IN, 1.0], [fx - 160.0, 1.0], [fx - 30.0, 0.55], [fx + 50.0, 0.0]]
		_curtain(fx, wb, 1.0, r)
	elif not to_cp and ("squall" in force or roll < 0.3) and not _stormy(wa) and not _stormy(wb):   # a squall to run through
		var kind := "BLIZZARD" if arctic_b else ("SANDSTORM" if r.randf() < 0.5 else "RAIN")
		var x1: float = t.b + r.randf_range(40.0, 70.0)
		var x2: float = minf(x1 + r.randf_range(110.0, 160.0), arr_x - line.HALF - 60.0)
		_wkind = kind
		_wx = [[x1 - 140.0, 0.0], [x1 - 20.0, 0.45], [x1 + 40.0, 1.0], [x2 - 20.0, 1.0], [x2 + 60.0, 0.0]]
		_curtain(x1, kind, 1.0, r)
		_curtain(x2, kind, -1.0, r)
	# The other train: out of its own tunnel on the other line as we leave, past us, on behind.
	roll = r.randf()
	if t.entry and not from_cp and ("freight" in force or roll < 0.35):
		_fstart = t.a + 20.0   # (its nose just inside its mouth, in the dark)
		_fgo = -INF
		_build_freight.call_deferred(r.randi())


static func _stormy(w: String) -> bool:
	return w in ["RAIN", "STORM", "SANDSTORM", "BLIZZARD", "ACID_RAIN"]


func finish() -> void:
	if main != null and main.train != null:
		main.train.set_power(true)
	clear()


## Every frame of the ride.
func tick(s: float, v: float, dt: float) -> void:
	_tick_weather(s)
	if _power != Vector2.INF:
		if _power_state == 0 and s >= _power.x:
			_power_state = 1
			main.train.set_power(false)
		elif _power_state == 1 and s >= _power.y:
			_power_state = 2
			main.train.set_power(true)
	if _thing_at != INF:
		_tick_thing(s, v, dt)
	if is_instance_valid(_freight):
		_tick_freight(s, dt)


# --- weather fronts ------------------------------------------------------------------------------------

func _tick_weather(s: float) -> void:
	if _wx.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var cx: float = (cam.global_position.x if cam else 0.0) + s
	var m: float = _wx[0][1]
	for k in _wx.size() - 1:
		var a: Array = _wx[k]
		var b: Array = _wx[k + 1]
		if cx >= a[0] and cx <= b[0]:
			m = lerpf(a[1], b[1], smoothstep(0.0, 1.0, (cx - a[0]) / maxf(b[0] - a[0], 0.01)))
		elif cx > b[0]:
			m = b[1]
	main.line_weather = _wkind
	main.line_mix = m
	# The fronts take the light of the hour; the fog's drawn far enough to see one coming.
	var day: float = clampf(main.sun.light_energy / 1.1 + 0.2, 0.05, 1.0)
	var near := false
	for c in _curtains:
		if not is_instance_valid(c[0]):
			continue
		var col: Color = c[2]
		c[1].emission = col * 0.4 * day   # (as the storm's own haze glows: dimmer, a front this thick reads as a black wall)
		near = near or absf(c[0].position.x - s) < 450.0
	main.env.volumetric_fog_length = 240.0 if near else 80.0


## A storm front standing across the line at x: banks of real (volumetric) fog, a dozen of them, wider
## than you can see and tens of metres high, their insides billowing (a noise texture in each),
## staggered back into the weather from the edge (`side`: +1 the weather lies beyond x). The fog's
## drawn further while one's in sight (`_tick_weather`), so you see it coming.
static var _billow: NoiseTexture3D

func _curtain(x: float, kind: String, side: float, r: RandomNumberGenerator) -> void:
	var col: Color = {"SANDSTORM": Color(0.78, 0.55, 0.34), "RAIN": Color(0.5, 0.54, 0.58), "STORM": Color(0.4, 0.43, 0.48),
		"BLIZZARD": Color(0.88, 0.9, 0.95), "ACID_RAIN": Color(0.55, 0.62, 0.4)}.get(kind, Color(0.55, 0.56, 0.58))
	if _billow == null:
		_billow = NoiseTexture3D.new()
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.035
		n.fractal_octaves = 4
		_billow.noise = n
		_billow.width = 64
		_billow.height = 64
		_billow.depth = 64
		_billow.seamless = true
		_billow.normalize = true
	var root := Node3D.new()
	line.add_child(root)
	root.position = Vector3(x, 0, 0)
	var mat := FogMaterial.new()
	mat.density = 0.16 if kind in ["SANDSTORM", "BLIZZARD"] else 0.1
	mat.albedo = col
	mat.emission = col * 0.4
	mat.height_falloff = 0.025
	mat.edge_fade = 0.7
	mat.density_texture = _billow
	for k in 14:
		var fv := FogVolume.new()
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		var near := k < 6   # (most of them across the line itself)
		fv.size = Vector3(r.randf_range(70.0, 130.0), r.randf_range(60.0, 110.0), r.randf_range(140.0, 260.0))
		fv.material = mat
		root.add_child(fv)
		fv.position = Vector3(side * r.randf_range(20.0, 110.0), fv.size.y * 0.32, r.randf_range(-90.0, 90.0) if near else r.randf_range(-420.0, 420.0))
		fv.rotation.y = r.randf_range(-0.3, 0.3)
	_curtains.append([root, mat, col])


# --- the other train -------------------------------------------------------------------------------------

## A freight to come through the loop: a road switcher and a string of wagons, built a piece a frame
## while we're still on our way, hidden till it goes.
func _build_freight(fseed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = fseed
	_freight = Node3D.new()
	_freight.visible = false
	line.add_child(_freight)
	var eng := Node3D.new()
	_freight.add_child(eng)
	var ec := [Color(0.25, 0.3, 0.4), Color(0.55, 0.2, 0.12), Color(0.3, 0.32, 0.28), Color(0.62, 0.5, 0.18)][r.randi() % 4] as Color
	CP.loco(eng, 13.0, ec, "BRM %d" % r.randi_range(200, 899))
	Merge.bake(eng, 20.0, false, 900.0)
	_cars.append([eng, 0.0, PI])   # (it leads, nose first toward us)
	# Its lights: the headlight, two ditch lights low on the pilot that flash in turn as it horns.
	var hl := SpotLight3D.new()
	hl.light_color = Color(1.0, 0.92, 0.75)
	hl.light_energy = 7.0
	hl.spot_range = 90.0
	hl.spot_angle = 14.0
	hl.light_volumetric_fog_energy = 2.5
	eng.add_child(hl)
	hl.position = Vector3(6.4, 2.6, 0)
	hl.rotation.y = -PI / 2.0
	var ditch := []
	for sz in [-0.9, 0.9]:
		var dl := SpotLight3D.new()
		dl.light_color = Color(1.0, 0.95, 0.85)
		dl.light_energy = 3.0
		dl.spot_range = 45.0
		dl.spot_angle = 22.0
		dl.light_volumetric_fog_energy = 1.5
		eng.add_child(dl)
		dl.position = Vector3(6.6, 1.0, sz)
		dl.rotation.y = -PI / 2.0
		var lens := A.sphere(eng, 0.09, Vector3(6.62, 1.0, sz), "cream", Color(1.0, 0.95, 0.85), 8.0)
		Merge.live(lens)
		ditch.append([dl, lens])
	_fbits.ditch = ditch
	await get_tree().process_frame
	var d := 12.6
	for k in r.randi_range(7, 10):
		if not is_instance_valid(_freight):
			return
		var car := Node3D.new()
		_freight.add_child(car)
		match r.randi() % 5:
			0, 1: P.boxcar(car, Vector3.ZERO, 0.0, r)
			2: CP._tank_car(car, Vector3.ZERO, r)
			3: CP._hopper(car, Vector3.ZERO, r)
			4: CP._flatcar(car, Vector3.ZERO, r)
		Merge.bake(car, 20.0, false, 900.0)
		_cars.append([car, d, 0.0])
		d += 10.8
		await get_tree().process_frame
	if not is_instance_valid(_freight):
		return
	# Its sound: the engine opened up, the wheels on the rails, and the smoke off its stack.
	var bus := "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	for k in ["prime_hi", "rail_roll"]:
		var p := AudioStreamPlayer3D.new()
		p.stream = Sfx.stream(k)
		p.bus = bus
		p.unit_size = 14.0 if k == "prime_hi" else 18.0
		p.max_distance = 400.0
		p.volume_db = -4.0 if k == "prime_hi" else 2.0
		p.pitch_scale = 0.93
		(eng if k == "prime_hi" else _cars[_cars.size() / 2][0]).add_child(p)
		_fbits[k] = p
	var smoke := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, 1.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.12, 0.11, 0.1, 0.7))
	ramp.add_point(0.3, Color(0.22, 0.21, 0.2, 0.45))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.36, 0.35, 0.33, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 2.2))
	var st := CurveTexture.new()
	st.curve = sc
	pm.scale_curve = st
	smoke.process_material = pm
	var puff := QuadMesh.new()   # soft round puffs, always facing you
	puff.size = Vector2(1.6, 1.6)
	var soft := GradientTexture2D.new()
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 1, 1, 1))
	sg.set_color(1, Color(1, 1, 1, 0))
	sg.add_point(0.45, Color(1, 1, 1, 0.55))
	soft.gradient = sg
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = soft
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # (lit, the sky turned it blue: it takes the hour's light from the haze instead, below)
	puff.material = sm
	_fbits.smoke_mat = sm
	smoke.draw_pass_1 = puff
	smoke.amount = 60
	smoke.lifetime = 3.5
	smoke.local_coords = true   # (it stays with the land as the world slides past)
	smoke.visibility_aabb = AABB(Vector3(-2000, -50, -200), Vector3(4000, 200, 400))
	line.add_child(smoke)
	smoke.emitting = false
	_fbits.smoke = smoke


func _tick_freight(s: float, dt: float) -> void:
	if not _fmoving:
		if s < _fgo or _cars.size() < 4 or not _fbits.has("smoke"):
			return
		_fmoving = true
		_freight.visible = true
		_fhead = _fstart
		_fbits.smoke.emitting = true
		for k in ["prime_hi", "rail_roll"]:
			_fbits[k].play()
	var u := 13.0   # m/s, toward us
	_fhead -= u * dt
	for c in _cars:
		var node: Node3D = c[0]
		node.position = Vector3(_fhead + float(c[1]), 0.12, line.OTHER_Z)
		node.rotation.y = float(c[2])
	var eng: Node3D = _cars[0][0]
	var pm: ParticleProcessMaterial = _fbits.smoke.process_material
	pm.emission_shape_offset = eng.position + Vector3(1.5, 4.6, 0)   # (its stack, on the long hood)
	var day: float = clampf(main.sun.light_energy / 1.1 + 0.2, 0.05, 1.0)
	_fbits.smoke_mat.albedo_color = Color(0.9, 0.86, 0.8).lerp(main.env.volumetric_fog_albedo * 1.5, 0.6) * day   # (grey against a dust storm reads blue: it takes the haze's colour)
	var cam := get_viewport().get_camera_3d()
	var eye_x: float = (cam.global_position.x if cam else 0.0) + s
	var gap := _fhead - (s + 17.8)   # its nose to ours
	var t := Time.get_ticks_msec() / 1000.0
	if not _fhorn and gap < 280.0:   # it horns for us: two long, ditch lights flashing
		_fhorn = true
		_horn_twice(eng)
	for i in _fbits.ditch.size():
		var on: bool = not _fhorn or gap < -20.0 or (int(t * 2.4) + i) % 2 == 0
		_fbits.ditch[i][0].visible = on
		_fbits.ditch[i][1].visible = on
	# Going by: wheels hammering past the windows, and the air it shoves.
	_fclack -= dt
	var near := absf(_fhead + 40.0 - eye_x) < 70.0
	if near and _fclack <= 0.0:
		_fclack = randf_range(0.07, 0.14)
		var cx := clampf(eye_x, _fhead, _fhead + float(_cars[-1][1]))
		Sfx.play(line, "rail_clack", line.to_global(Vector3(cx + randf_range(-6, 6), 0.4, line.OTHER_Z)), -8.0, randf_range(0.85, 1.05))
	if not _fpassed and _fhead < s + 2.0:
		_fpassed = true
		Sfx.play(line, "swish", line.to_global(Vector3(_fhead, 2.5, line.OTHER_Z)), -6.0, 0.5)
		Sfx.play(main.train, "rattle", main.train.to_global(Vector3(0, 2.4, -2.1)), -16.0)
		if main.player.in_train:
			main.player.shake(0.012)
	if _fhead + float(_cars[-1][1]) < s - 420.0:   # long gone behind us
		_fbits.smoke.queue_free()
		_freight.queue_free()
		_freight = null


func _horn_twice(eng: Node3D) -> void:
	for k in 2:
		if not is_instance_valid(eng):
			return
		Sfx.play(line, "horn", eng.global_position + Vector3(0, 4.2, 0), 2.0, 0.86)
		await get_tree().create_timer(1.1, false).timeout


# --- the thing in the tunnel -----------------------------------------------------------------------------

## Pale, starved, far too long in the limb: it runs on all fours with its spine bowed, a long blind-
## looking skull with two eyes that throw the headlight back.
func _build_thing() -> void:
	_thing = Node3D.new()
	_thing.visible = false
	line.add_child(_thing)
	_thing.scale = Vector3.ONE * 1.5
	var skin := Color(0.66, 0.65, 0.6)
	var dark := Color(0.42, 0.4, 0.38)
	var hips := Node3D.new()
	_thing.add_child(hips)
	hips.position = Vector3(-0.55, 0.95, 0)
	_tp.hips = hips
	var spine := Node3D.new()
	_thing.add_child(spine)
	spine.position = Vector3(-0.55, 0.95, 0)
	_tp.spine = spine
	A.seg(spine, Vector3(-0.15, -0.05, 0), Vector3(0.6, 0.2, 0), 0.15, 0.2, "plastic", skin)   # the back, bowed up
	A.seg(spine, Vector3(0.6, 0.2, 0), Vector3(1.15, 0.05, 0), 0.2, 0.15, "plastic", skin)
	var belly := A.sphere(spine, 0.2, Vector3(0.62, 0.0, 0), "plastic", skin.darkened(0.15))   # the sunken gut under the ribs
	belly.scale = Vector3(2.6, 0.7, 1.0)
	for k in 7:   # the spine's knuckles through the skin
		A.sphere(spine, 0.035, Vector3(0.12 + k * 0.15, 0.17 + sin(k * 0.45) * 0.06 + 0.1, 0), "plastic", dark)
	for k in 5:   # ribs, hooped down each flank under the skin
		var rx := 0.42 + k * 0.11
		var top := 0.2 + sin(k * 0.45) * 0.05
		for sz in [-1.0, 1.0]:
			A.seg(spine, Vector3(rx, top, sz * 0.05), Vector3(rx + 0.04, top - 0.16, sz * 0.19), 0.022, 0.02, "plastic", dark)
			A.seg(spine, Vector3(rx + 0.04, top - 0.16, sz * 0.19), Vector3(rx + 0.09, top - 0.3, sz * 0.1), 0.02, 0.014, "plastic", dark)
	var neck := Node3D.new()
	spine.add_child(neck)
	neck.position = Vector3(1.15, 0.05, 0)
	_tp.neck = neck
	A.seg(neck, Vector3.ZERO, Vector3(0.32, 0.08, 0), 0.08, 0.06, "plastic", skin)
	var head := Node3D.new()
	neck.add_child(head)
	head.position = Vector3(0.32, 0.08, 0)
	_tp.head = head
	var skull := A.sphere(head, 0.13, Vector3(0.2, 0, 0), "plastic", skin)
	skull.scale = Vector3(2.0, 0.85, 0.9)
	A.seg(head, Vector3(0.12, -0.08, 0), Vector3(0.42, -0.1, 0), 0.06, 0.03, "plastic", dark)   # the jaw
	for sz in [-1.0, 1.0]:   # eyes that throw the light back
		var eye := A.sphere(head, 0.03, Vector3(0.34, 0.035, sz * 0.07), "cream", Color(0.75, 1.0, 0.7), 14.0)
		Merge.live(eye)
	A.seg(spine, Vector3(-0.15, -0.02, 0), Vector3(-0.55, -0.2, 0), 0.07, 0.035, "plastic", skin)   # a bare whip of a tail
	A.seg(spine, Vector3(-0.55, -0.2, 0), Vector3(-0.95, -0.5, 0), 0.035, 0.01, "plastic", skin)
	for sz in [-1.0, 1.0]:
		var haunch := A.sphere(spine, 0.13, Vector3(0.05, -0.02, sz * 0.16), "plastic", skin)   # the haunches: all the spring's in them
		haunch.scale = Vector3(1.5, 1.6, 0.8)
		var blade := A.sphere(spine, 0.08, Vector3(0.95, 0.16, sz * 0.13), "plastic", skin)   # shoulder blades riding up under the skin
		blade.scale = Vector3(1.8, 1.3, 0.5)
	# Front legs short and bent back at the elbow, hind legs long with the hock bent forward: it
	# stands zig-zag, like an animal (straight, it was a stool).
	for leg in [["fl", Vector3(1.0, 0.0, -0.19), 0.55, 0.6], ["fr", Vector3(1.0, 0.0, 0.19), 0.55, 0.6], ["bl", Vector3(0.05, 0.0, -0.2), 0.6, 0.7], ["br", Vector3(0.05, 0.0, 0.2), 0.6, 0.7]]:
		var up := Node3D.new()
		spine.add_child(up)
		up.position = leg[1]
		A.seg(up, Vector3.ZERO, Vector3(0, -leg[2], 0), 0.11 if leg[0].begins_with("b") else 0.08, 0.05, "plastic", skin)
		var lo := Node3D.new()
		up.add_child(lo)
		lo.position = Vector3(0, -leg[2], 0)
		A.sphere(lo, 0.045, Vector3.ZERO, "plastic", dark)
		A.seg(lo, Vector3.ZERO, Vector3(0, -leg[3], 0), 0.05, 0.03, "plastic", skin)
		for f in 3:   # long splayed fingers / toes
			A.seg(lo, Vector3(0, -leg[3], 0), Vector3(0.12, -leg[3] - 0.03, (f - 1) * 0.05), 0.012, 0.006, "plastic", dark)
		_tp[leg[0]] = up
		_tp[leg[0] + "_lo"] = lo


func _tick_thing(s: float, v: float, dt: float) -> void:
	if not is_instance_valid(_thing) or _tstate == "gone":
		return
	var front := s + 17.8   # our nose (line x)
	match _tstate:
		"":
			if front > _thing_at - 60.0:   # crouched on the track ahead, in the beam
				_tstate = "wait"
				_tx = _thing_at
				_tz = -0.2
				_tu = 0.0
				_thing.visible = true
		"wait":
			if front > _tx - 26.0:   # it sees us coming: it goes
				_tstate = "bolt"
				_tt = 0.0
				Sfx.play(line, "growl", line.to_global(Vector3(_tx, 1.0, _tz)), -2.0, 0.55)
		"bolt":   # off the track to the wall and away, faster than we are
			_tt += dt
			_tu = move_toward(_tu, v + 5.0, dt * 26.0)
			_tz = move_toward(_tz, 3.5, dt * 4.5)   # (the platform side: past the most windows)
			if _tt > 1.3:
				_tstate = "fall"
				_tt = 0.0
		"fall":   # it tires: we draw level and it drops back past the windows
			_tt += dt
			_tu = move_toward(_tu, v - 13.0, dt * 9.0)
			if _tx < s - 30.0:
				_tstate = "gone"
				_thing.visible = false
				return
	_tx += _tu * dt
	_thing.position = Vector3(_tx, 0.12, _tz)
	_thing.rotation.y = lerp_angle(_thing.rotation.y, PI if _tstate == "wait" else -0.25 * (1.0 if _tstate == "bolt" and _tt < 0.6 else 0.0), minf(1.0, dt * 9.0))
	_animate_thing(dt)
	if _tstate in ["bolt", "fall"]:   # claws on the ballast and the walk, close by
		var cam := get_viewport().get_camera_3d()
		var near: bool = cam != null and cam.global_position.distance_to(_thing.global_position) < 26.0
		var ph := fmod(_tgait, PI)
		if ph < _tstep and near:
			Sfx.play(line, "step_metal", _thing.global_position, -12.0, randf_range(0.6, 0.75))
		_tstep = ph
		if _tstate == "fall" and absf(_tx - s) < 2.0 and not _thing.has_meta("scraped"):
			_thing.set_meta("scraped", true)   # its claws along the car's side as it falls back
			Sfx.play(main.train, "slide", main.train.to_global(Vector3(0, 1.6, 1.9)), -8.0, 0.6)


func _animate_thing(dt: float) -> void:
	var k := 1.0 - exp(-dt * 12.0)
	var run := _tstate in ["bolt", "fall"]
	if run:
		_tgait += maxf(_tu, 0.0) * dt * TAU / 2.6   # (a stride per 2.6 m: no sliding)
	var g := _tgait
	var spine_tilt := 0.0
	var hips_y := 0.95
	var legs := {}
	if not run:   # coiled low on the sleepers like something about to spring: haunches folded,
		# elbows out, the long skull raised into the light, swaying
		var t := Time.get_ticks_msec() / 1000.0
		hips_y = 0.42
		spine_tilt = 0.32
		legs.fl = [0.7, -1.5]
		legs.fr = [0.55, -1.4]
		legs.bl = [1.35, -2.3]
		legs.br = [1.25, -2.2]
		_tp.head.rotation.z = lerpf(_tp.head.rotation.z, 0.15 + sin(t * 1.7) * 0.08, k)
		_tp.head.rotation.x = lerpf(_tp.head.rotation.x, sin(t * 0.9) * 0.25, k)
	else:   # a bounding gallop: back legs together, front together, the spine flexing
		hips_y = 0.84 + absf(sin(g)) * 0.08
		spine_tilt = -0.06 + sin(g) * 0.12   # (low at the head, like it's hunting)
		var f := sin(g)
		var f2 := sin(g + 0.25)
		var b := sin(g + PI * 0.85)
		var b2 := sin(g + PI * 0.85 + 0.25)
		legs.fl = [-0.5 - 0.55 * f, 0.9 + maxf(0.0, f) * 0.7]   # (folding up as it comes forward)
		legs.fr = [-0.5 - 0.55 * f2, 0.9 + maxf(0.0, f2) * 0.7]
		legs.bl = [0.8 + 0.55 * b, -1.5 - maxf(0.0, -b) * 0.6]
		legs.br = [0.8 + 0.55 * b2, -1.5 - maxf(0.0, -b2) * 0.6]
		_tp.head.rotation.z = lerpf(_tp.head.rotation.z, -0.1 + sin(g * 2.0) * 0.05, k)
		_tp.head.rotation.x = lerpf(_tp.head.rotation.x, 0.0, k)
	_tp.spine.position.y = lerpf(_tp.spine.position.y, hips_y, k)
	_tp.spine.rotation.z = lerpf(_tp.spine.rotation.z, spine_tilt, k)
	for n in legs:
		_tp[n].rotation.z = lerpf(_tp[n].rotation.z, legs[n][0], k)
		_tp[n + "_lo"].rotation.z = lerpf(_tp[n + "_lo"].rotation.z, legs[n][1], k)
