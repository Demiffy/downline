# The train: rusty locomotive + walkable crew/cargo car + flatcar. Floor is at y = 1.0 so
# station platforms line up with the doors. `speed` (m/s) drives wheels, rods and steam.
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

const F := 1.0  # floor height
const INSIDE := AABB(Vector3(-8.1, 0.6, -2.0), Vector3(16.2, 3.2, 4.0))
const STORAGE := AABB(Vector3(-20.5, 0.6, -2.0), Vector3(12.4, 3.2, 4.0))
const CAR_LEN := 12.4

var speed := 0.0
var clock_label: Label3D
var market_label: Label3D
var headlight: SpotLight3D
var _wheels: Array = []   # [pivot, radius]
var _rods: Array = []     # [rod, center_x, side]
var _angle := 0.0
var _steam: GPUParticles3D
var _steam_mat: ParticleProcessMaterial
var _chug: AudioStreamPlayer3D
var has_storage := false
var _rear_lock: Node3D
var _flat: Node3D


func contains(pos: Vector3) -> bool:
	var l := to_local(pos)
	return INSIDE.has_point(l) or (has_storage and STORAGE.has_point(l))


## x of the very back of the train (where the delivery handcar parks).
func rear_x() -> float:
	return -15.6 - (CAR_LEN if has_storage else 0.0)


func build(open_terminal: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_car()
	_interior(open_terminal, rng)
	_locomotive()
	_flatcar(rng)
	_chug = AudioStreamPlayer3D.new()
	_chug.stream = Sfx.stream("chug")
	_chug.unit_size = 10.0
	add_child(_chug)
	_chug.position = Vector3(11, 2, 0)


func _process(delta: float) -> void:
	_angle -= speed * delta
	for w in _wheels:
		w[0].rotation.z = _angle / w[1]
	for r in _rods:
		var a: float = _angle / 0.62
		r[0].position.x = r[1] + cos(a) * 0.28
		r[0].position.y = 0.62 + sin(a) * 0.28
	_steam.amount_ratio = clampf(0.25 + absf(speed) / 6.0, 0.0, 1.0)
	_steam_mat.gravity = Vector3(-speed * 2.0, 1.5, 0)
	if absf(speed) > 0.3:
		if not _chug.playing:
			_chug.play()
		_chug.pitch_scale = clampf(0.4 + absf(speed) / 12.0, 0.4, 2.5)
		_chug.volume_db = -6.0
	elif _chug.playing:
		_chug.stop()


# --- crew car -------------------------------------------------------------------

func _car() -> void:
	var paint := Color(1, 1, 1)
	var wall_h := 2.7
	var door_holes := [[-4.5, 1.5, 0.0, 2.3], [2.6, 1.5, 0.0, 2.3]]
	var side_windows := [[-6.6, 1.0, 1.0, 2.0], [-1.2, 1.0, 1.0, 2.0], [5.0, 1.1, 1.0, 2.0], [7.2, 0.9, 1.0, 2.0]]
	var back_windows := [[4.0, 1.1, 1.0, 2.0], [6.6, 1.0, 1.0, 2.0], [-6.0, 1.0, 2.3, 2.6], [-3.0, 1.0, 2.3, 2.6], [-0.2, 1.0, 2.3, 2.6]]
	# Exterior paint skin + interior red skin.
	A.wall(self, -8.2, 8.2, 2.18, wall_h, 0.08, door_holes + side_windows, "paint", paint, true, F)
	A.wall(self, -8.2, 8.2, 2.06, wall_h, 0.08, door_holes + side_windows, "red_wall", Color.WHITE, true, F, false, 1.0)
	A.wall(self, -8.2, 8.2, -2.18, wall_h, 0.08, back_windows, "paint", paint, true, F)
	A.wall(self, -8.2, 8.2, -2.06, wall_h, 0.08, back_windows, "red_wall", Color.WHITE, true, F, false, 1.0)
	A.wall(self, -2.2, 2.2, 8.2, wall_h, 0.15, [[0.0, 1.6, 1.0, 2.0]], "paint", paint, false, F)
	A.wall(self, -2.2, 2.2, -8.2, wall_h, 0.15, [[0.0, 1.2, 0.0, 2.3]], "paint", paint, false, F)
	_rear_lock = A.box(self, Vector3(0.1, 2.3, 1.2), Vector3(-8.15, F + 1.15, 0), "riveted", Color(0.6, 0.55, 0.5), true, 1.0)
	var lock_sign := B.label(_rear_lock, "STORAGE CAR\nNOT INSTALLED", Vector3(0.07, 0.3, 0), 28, Color(0.95, 0.8, 0.35), "stencil", 0.003)
	lock_sign.rotation.y = PI / 2
	# Wood wainscot inside.
	A.wall(self, -8.1, 8.1, 2.0, 0.9, 0.03, door_holes, "wood", Color.WHITE, true, F, false, 1.0)
	A.wall(self, -8.1, 8.1, -2.0, 0.9, 0.03, [], "wood", Color.WHITE, true, F, false, 1.0)
	for w in side_windows + door_holes:
		if w[2] > 0.0:
			_glass(Vector3(w[0], F + (w[2] + w[3]) / 2.0, 2.12), Vector3(w[1], w[3] - w[2], 0.02))
	for w in back_windows:
		_glass(Vector3(w[0], F + (w[2] + w[3]) / 2.0, -2.12), Vector3(w[1], w[3] - w[2], 0.02))
	# Floor, chassis, ceiling ribs, roof.
	A.box(self, Vector3(16.4, 0.12, 4.2), Vector3(0, F - 0.06, 0), "wood", Color(0.85, 0.8, 0.75), true, 1.5)
	A.box(self, Vector3(16.8, 0.35, 3.4), Vector3(0, 0.7, 0), "rust", Color(0.6, 0.6, 0.6), true)
	A.box(self, Vector3(16.4, 0.08, 4.4), Vector3(0, F + wall_h + 0.04, 0), "metal", Color(0.5, 0.45, 0.42), true)
	for i in 9:
		A.box(self, Vector3(0.1, 0.12, 4.1), Vector3(-8.0 + i * 2.0, F + wall_h - 0.06, 0), "rust", Color.WHITE, false, 1.0)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(4.7, 0.55, 16.8)
	roof.mesh = pm
	roof.material_override = A.mat("paint", Color(0.7, 0.6, 0.6))
	add_child(roof)
	roof.position = Vector3(0, F + wall_h + 0.36, 0)
	roof.rotation.y = PI / 2
	for x in [-5.0, 0.5, 5.5]:
		A.box(self, Vector3(1.0, 0.3, 0.8), Vector3(x, F + wall_h + 0.6, 0), "metal", Color(0.5, 0.5, 0.5), false)
	# Trim strips, door frames, grab handles, door steps.
	for z in [-2.24, 2.24]:
		for y in [F + 0.05, F + wall_h - 0.05]:
			A.box(self, Vector3(16.6, 0.12, 0.05), Vector3(0, y, z), "rust", Color.WHITE, false, 1.0)
	for d in door_holes:
		for s in [-1, 1]:
			A.box(self, Vector3(0.08, 2.4, 0.06), Vector3(d[0] + s * 0.8, F + 1.2, 2.25), "metal", Color(0.4, 0.4, 0.4), false)
			A.cyl(self, 0.025, 1.2, Vector3(d[0] + s * 0.95, F + 1.0, 2.33), "metal", Color(0.75, 0.75, 0.7))
		A.box(self, Vector3(1.7, 0.08, 0.06), Vector3(d[0], F + 2.35, 2.25), "metal", Color(0.4, 0.4, 0.4), false)
	# Two bogies.
	for bx in [-4.9, 4.9]:
		A.box(self, Vector3(2.4, 0.3, 1.9), Vector3(bx, 0.55, 0), "rust", Color(0.5, 0.5, 0.5), false)
		for ax in [-0.65, 0.65]:
			for z in [-0.78, 0.78]:
				_wheel(Vector3(bx + ax, 0.45, z), 0.45)
	# Couplers.
	for s in [-1, 1]:
		A.box(self, Vector3(0.5, 0.25, 0.4), Vector3(s * 8.45, 0.75, 0), "metal", Color(0.3, 0.3, 0.3), false)


func _glass(pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = A.glass()
	add_child(mi)
	mi.position = pos


func _wheel(pos: Vector3, radius: float, parent: Node = null) -> Node3D:
	var pivot := Node3D.new()
	(parent if parent else self).add_child(pivot)
	pivot.position = pos
	A.cyl(pivot, radius, 0.1, Vector3.ZERO, "metal", Color(0.35, 0.33, 0.32), false, "z")
	A.cyl(pivot, radius * 0.35, 0.14, Vector3.ZERO, "rust", Color.WHITE, false, "z")
	for a in [0.0, PI / 3, 2 * PI / 3]:
		var spoke := A.box(pivot, Vector3(radius * 1.8, 0.06, 0.12), Vector3.ZERO, "rust", Color(0.8, 0.8, 0.8), false, 1.0)
		spoke.rotation.z = a
	_wheels.append([pivot, radius])
	return pivot


# --- interior -------------------------------------------------------------------------

func _interior(open_terminal: Callable, rng: RandomNumberGenerator) -> void:
	# Terminal desk against the back wall, front section.
	var desk := StaticBody3D.new()
	add_child(desk)
	desk.position = Vector3(6.5, F, -1.55)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.2, 0.8, 0.85)
	cs.shape = sh
	cs.position.y = 0.4
	desk.add_child(cs)
	A.box(desk, Vector3(2.2, 0.07, 0.85), Vector3(0, 0.78, 0), "wood", Color.WHITE, false, 1.0)
	for sx in [-1, 1]:
		A.box(desk, Vector3(0.06, 0.75, 0.8), Vector3(sx * 1.05, 0.37, 0), "wood", Color(0.7, 0.7, 0.7), false, 1.0)
	var mon := Node3D.new()
	desk.add_child(mon)
	mon.position = Vector3(-0.35, 0.81, -0.05)
	mon.rotation.y = PI
	A.crt(mon, Vector3.ZERO, false)
	B.interactable(self, Vector3(0.44, 0.33, 0.03), Vector3(6.15, F + 1.06, -1.33), Color(1.0, 0.55, 0.15), "Use terminal", open_terminal, 0.0, 1.6)
	var mon2 := Node3D.new()
	desk.add_child(mon2)
	mon2.position = Vector3(0.6, 0.81, -0.05)
	mon2.rotation.y = PI
	A.crt(mon2, Vector3.ZERO, true, Color(0.25, 0.12, 0.04))
	market_label = Label3D.new()
	market_label.font_size = 32
	market_label.pixel_size = 0.0011
	market_label.modulate = Color(1, 0.65, 0.25)
	market_label.outline_size = 0
	add_child(market_label)
	market_label.position = Vector3(7.1, F + 1.06, -1.32)
	# Clock, chalkboard, charger, control panel, horn lever.
	A.box(self, Vector3(1.1, 0.32, 0.05), Vector3(6.5, F + 2.05, -1.99), "metal", Color(0.15, 0.15, 0.15), false)
	clock_label = Label3D.new()
	clock_label.font_size = 64
	clock_label.pixel_size = 0.004
	clock_label.modulate = Color(1, 0.5, 0.15)
	clock_label.outline_size = 0
	add_child(clock_label)
	clock_label.position = Vector3(6.5, F + 2.05, -1.96)
	A.box(self, Vector3(1.9, 1.15, 0.05), Vector3(3.6, F + 1.6, -1.99), "wood", Color.WHITE, false, 1.0)
	A.box(self, Vector3(1.75, 1.0, 0.02), Vector3(3.6, F + 1.6, -1.96), "board", Color.WHITE, false)
	var chalk := B.label(self, "BUREAU OF RECLAIMED MATERIALS\n\n- store scrap in the cargo end\n- train leaves at 24:00 sharp\n- do NOT look at the mannequins\n\nquota is quota.", Vector3(3.6, F + 1.6, -1.94), 40, Color(0.9, 0.92, 0.85), "chalk", 0.0022)
	A.box(self, Vector3(0.6, 0.35, 0.22), Vector3(2.0, F + 1.3, -1.9), "metal", Color(0.4, 0.42, 0.4), false)
	for i in 4:
		A.glow(self, Vector3(0.08, 0.05, 0.02), Vector3(1.8 + i * 0.13, F + 1.38, -1.78), Color(0.2, 1, 0.3), 3.0)
	var panel := A.box(self, Vector3(0.35, 1.0, 1.7), Vector3(7.95, F + 1.2, 0.6), "metal", Color(0.45, 0.48, 0.45))
	for i in 3:
		A.cyl(panel, 0.11, 0.03, Vector3(-0.19, 0.25, -0.5 + i * 0.4), "cream", Color(0.9, 0.9, 0.85), false, "x")
	B.interactable(self, Vector3(0.08, 0.5, 0.08), Vector3(7.7, F + 1.05, 1.2), Color(0.8, 0.1, 0.1), "Pull horn",
		func(): Sfx.play(self, "horn", Vector3(12, 4, 0), 0.0), 0.0, 0.3)
	A.cyl(self, 0.22, 0.6, Vector3(6.2, F + 0.3, -0.4), "metal", Color(0.4, 0.3, 0.25), true)
	A.locker(self, Vector3(7.65, F, -0.6), PI / 2)
	# Lighting: caged ceiling lamps, one hanging lamp in the cargo end.
	for x in [-5.0, 0.5, 5.5]:
		A.sphere(self, 0.12, Vector3(x, F + 2.55, 0), "cream", Color(1, 0.8, 0.5), 5.0)
		for a in 4:
			var bar := A.box(self, Vector3(0.02, 0.25, 0.02), Vector3(x, F + 2.55, 0) + Vector3(0.14, 0, 0).rotated(Vector3.UP, a * PI / 2), "metal", Color(0.3, 0.3, 0.3), false)
			bar.rotation.y = a * PI / 2
		B.omni(self, Vector3(x, F + 2.2, 0), Color(1, 0.75, 0.5), 1.0, 7.5)
	A.hanging_lamp(self, Vector3(-2.8, F + 2.65, 0.5), Color(1, 0.75, 0.45), 0.6, 0.9, false)
	# Cargo end: shelving, crates, barrel, bench.
	for x in [-6.6, -4.2, -1.8]:
		A.shelf_unit(self, Vector3(x, F, -1.72), 0.0, rng, 2.25, 2.2, 0.5)
	var scrap_sign := B.label(self, "STORE SCRAP HERE", Vector3(-4.2, F + 2.45, -1.97), 40, Color(0.95, 0.9, 0.75), "stencil", 0.004)
	A.crate(self, Vector3(-7.5, F, 1.5), 0.75, rng)
	A.crate(self, Vector3(-7.45, F + 0.75, 1.5), 0.5, rng, false)
	A.barrel(self, Vector3(-7.5, F, 0.55), rng)
	A.box(self, Vector3(1.8, 0.45, 0.45), Vector3(-0.8, F + 0.225, 1.72), "wood", Color.WHITE, true, 1.0)


# --- locomotive & flatcar ------------------------------------------------------------------

func _locomotive() -> void:
	var red := Color(0.95, 0.85, 0.85)
	# Frame, walkways with railings.
	A.box(self, Vector3(8.4, 0.35, 3.0), Vector3(12.4, 0.75, 0), "rust", Color(0.55, 0.55, 0.55), true)
	for z in [-1.4, 1.4]:
		A.box(self, Vector3(8.2, 0.06, 0.5), Vector3(12.4, F - 0.02, z), "grate", Color.WHITE, false, 1.0)
		A.railing(self, Vector3(8.6, F, z * 1.13), Vector3(14.0, F, z * 1.13), 1.0, "rust")
	# Long hood with radiator grilles, a roof fan and an exhaust stack.
	A.box(self, Vector3(5.2, 2.3, 2.2), Vector3(11.1, F + 1.15, 0), "paint", red, true, 2.0)
	A.box(self, Vector3(5.3, 0.12, 2.3), Vector3(11.1, F + 2.36, 0), "paint", red.darkened(0.25), false, 2.0)
	for z in [-1.11, 1.11]:
		for x in [9.4, 10.6, 11.8]:
			A.box(self, Vector3(0.9, 1.1, 0.03), Vector3(x, F + 1.4, z), "grille", Color.WHITE, false, 0.5)
		A.box(self, Vector3(5.2, 0.12, 0.03), Vector3(11.1, F + 0.4, z), "plow", Color.WHITE, false, 0.6)
	A.cyl(self, 0.6, 0.08, Vector3(12.6, F + 2.44, 0), "grille", Color.WHITE)
	var fan := Node3D.new()
	add_child(fan)
	fan.position = Vector3(12.6, F + 2.42, 0)
	for k in 3:
		var blade := A.box(fan, Vector3(1.05, 0.02, 0.16), Vector3.ZERO, "metal", Color(0.3, 0.3, 0.3), false)
		blade.rotation.y = k * PI / 3
	A.spin(fan, "y", 0.8)
	A.cyl(self, 0.16, 0.5, Vector3(10.0, F + 2.6, 0), "rust", Color(0.6, 0.6, 0.6))
	# Cab with windows, number boards and the headlight.
	A.box(self, Vector3(2.6, 2.9, 2.6), Vector3(15.0, F + 1.45, 0), "paint", red, true, 2.0)
	A.box(self, Vector3(2.8, 0.15, 2.8), Vector3(15.0, F + 2.97, 0), "paint", red.darkened(0.3), false, 2.0)
	for z in [-1.31, 1.31]:
		A.box(self, Vector3(1.0, 0.8, 0.02), Vector3(15.3, F + 2.1, z), "metal", Color(0.05, 0.05, 0.05), false)
		var num := B.label(self, "BRM 07", Vector3(14.5, F + 0.9, z * 1.01), 72, Color(0.95, 0.9, 0.75), "stencil", 0.004)
		num.rotation.y = 0.0 if z > 0 else PI
	for z in [-0.6, 0.6]:
		A.box(self, Vector3(0.02, 0.75, 0.9), Vector3(16.31, F + 2.15, z), "metal", Color(0.12, 0.12, 0.12), false)
	A.glow(self, Vector3(0.04, 0.3, 0.3), Vector3(16.33, F + 2.75, 0), Color(1, 0.85, 0.55), 6.0)
	A.box(self, Vector3(0.5, 1.2, 2.4), Vector3(16.5, F + 0.3, 0), "paint", red.darkened(0.2), true, 2.0)
	headlight = SpotLight3D.new()
	headlight.light_color = Color(1, 0.85, 0.6)
	headlight.light_energy = 5.0
	headlight.spot_range = 60.0
	headlight.spot_angle = 18.0
	headlight.light_volumetric_fog_energy = 2.0
	add_child(headlight)
	headlight.position = Vector3(16.5, F + 2.75, 0)
	headlight.rotation = Vector3(-0.05, -PI / 2, 0)
	# Big rusty snowplow.
	for s in [-1, 1]:
		var blade := A.box(self, Vector3(0.12, 1.9, 1.9), Vector3(17.35, 0.95, s * 0.85), "plow", Color.WHITE, false, 1.5)
		blade.rotation = Vector3(0, -s * 0.55, -0.35)
	A.box(self, Vector3(0.4, 0.4, 0.5), Vector3(16.9, 0.75, 0), "metal", Color(0.3, 0.3, 0.3), false)
	# Fuel tank + two three-axle trucks.
	A.box(self, Vector3(3.0, 0.8, 2.2), Vector3(12.4, 0.35, 0), "metal", Color(0.25, 0.25, 0.27), false)
	for tx in [9.6, 15.2]:
		A.box(self, Vector3(3.2, 0.35, 2.0), Vector3(tx, 0.6, 0), "rust", Color(0.45, 0.45, 0.45), false)
		for ax in [-1.1, 0.0, 1.1]:
			for z in [-0.78, 0.78]:
				_wheel(Vector3(tx + ax, 0.45, z), 0.45)
	# Steam from the stack.
	_steam = GPUParticles3D.new()
	_steam.amount = 90
	_steam.lifetime = 3.5
	_steam.local_coords = false
	_steam.visibility_aabb = AABB(Vector3(-40, -5, -10), Vector3(60, 25, 20))
	_steam_mat = ParticleProcessMaterial.new()
	_steam_mat.direction = Vector3(0, 1, 0)
	_steam_mat.spread = 12.0
	_steam_mat.initial_velocity_min = 2.0
	_steam_mat.initial_velocity_max = 3.5
	_steam_mat.scale_min = 0.6
	_steam_mat.scale_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 2.5))
	var gt := CurveTexture.new()
	gt.curve = grow
	_steam_mat.scale_curve = gt
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.5))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	_steam_mat.color_ramp = ft
	_steam.process_material = _steam_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var sm := StandardMaterial3D.new()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.3, 0.28, 0.27)
	quad.material = sm
	_steam.draw_pass_1 = quad
	add_child(_steam)
	_steam.position = Vector3(10.0, F + 2.9, 0)


func _flatcar(rng: RandomNumberGenerator) -> void:
	_flat = Node3D.new()
	add_child(_flat)
	A.box(_flat, Vector3(6.8, 0.2, 2.8), Vector3(-12.1, 0.95, 0), "wood", Color(0.75, 0.7, 0.65), true, 1.5)
	A.box(_flat, Vector3(7.0, 0.3, 2.4), Vector3(-12.1, 0.7, 0), "rust", Color(0.5, 0.5, 0.5), false)
	for x in [-10.0, -14.2]:
		for z in [-0.78, 0.78]:
			_wheel(Vector3(x, 0.45, z), 0.45, _flat)
	A.crate(_flat, Vector3(-10.2, 1.05, 0.6), 1.0, rng)
	A.crate(_flat, Vector3(-11.2, 1.05, -0.5), 0.8, rng)
	A.crate(_flat, Vector3(-10.4, 2.05, 0.5), 0.6, rng, false)
	A.barrel(_flat, Vector3(-13.0, 1.05, 0.8), rng)
	A.barrel(_flat, Vector3(-13.6, 1.05, -0.4), rng)
	A.box(_flat, Vector3(2.2, 1.1, 2.0), Vector3(-14.4, 1.6, 0), "leaf", Color(0.6, 0.65, 0.5), false, 1.0)
	A.box(_flat, Vector3(0.5, 0.25, 0.4), Vector3(-15.65, 0.75, 0), "metal", Color(0.3, 0.3, 0.3), false)


# --- upgrades / deliveries -----------------------------------------------------------

## STORAGE_CAR upgrade: a second walk-in car behind the crew car; the flatcar moves back.
func add_storage_car() -> void:
	if has_storage:
		return
	has_storage = true
	_rear_lock.queue_free()
	_flat.position.x -= CAR_LEN
	var x0 := -8.3 - CAR_LEN
	var x1 := -8.3
	var xc := (x0 + x1) / 2.0
	var root := Node3D.new()
	add_child(root)
	var paint := Color(0.9, 0.95, 0.9)
	var door := [[xc + 2.0, 1.5, 0.0, 2.3]]
	var wins := [[xc - 3.5, 1.0, 1.0, 2.0], [xc + 4.5, 1.0, 1.0, 2.0]]
	A.wall(root, x0, x1, 2.18, 2.7, 0.08, door + wins, "paint", paint, true, F)
	A.wall(root, x0, x1, 2.06, 2.7, 0.08, door + wins, "red_wall", Color.WHITE, true, F, false, 1.0)
	A.wall(root, x0, x1, -2.18, 2.7, 0.08, [], "paint", paint, true, F)
	A.wall(root, -2.2, 2.2, x0, 2.7, 0.15, [], "paint", paint, false, F)
	A.wall(root, -2.2, 2.2, x1 + 0.05, 2.7, 0.15, [[0.0, 1.2, 0.0, 2.3]], "paint", paint, false, F)
	for w in wins:
		_glass_at(root, Vector3(w[0], F + 1.5, 2.12), Vector3(w[1], 1.0, 0.02))
	A.box(root, Vector3(CAR_LEN, 0.12, 4.2), Vector3(xc, F - 0.06, 0), "wood", Color(0.85, 0.8, 0.75), true, 1.5)
	A.box(root, Vector3(CAR_LEN + 0.4, 0.35, 3.4), Vector3(xc, 0.7, 0), "rust", Color(0.6, 0.6, 0.6), true)
	A.box(root, Vector3(CAR_LEN, 0.08, 4.4), Vector3(xc, F + 2.74, 0), "metal", Color(0.5, 0.45, 0.42), true)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(4.7, 0.55, CAR_LEN + 0.4)
	roof.mesh = pm
	roof.material_override = A.mat("paint", Color(0.7, 0.6, 0.6))
	root.add_child(roof)
	roof.position = Vector3(xc, F + 3.06, 0)
	roof.rotation.y = PI / 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 4:
		A.shelf_unit(root, Vector3(x0 + 1.6 + i * 2.6, F, -1.72), 0.0, rng, 2.4, 2.3, 0.5)
	var cargo_sign := B.label(root, "CARGO", Vector3(xc, F + 2.45, -1.97), 48, Color(0.95, 0.9, 0.75), "stencil", 0.005)
	for x in [xc - 3.0, xc + 3.0]:
		A.sphere(root, 0.12, Vector3(x, F + 2.55, 0), "cream", Color(1, 0.8, 0.5), 5.0)
		B.omni(root, Vector3(x, F + 2.2, 0), Color(1, 0.75, 0.5), 1.0, 7.5)
	for bx in [x0 + 2.4, x1 - 2.4]:
		A.box(root, Vector3(2.4, 0.3, 1.9), Vector3(bx, 0.55, 0), "rust", Color(0.5, 0.5, 0.5), false)
		for ax in [-0.65, 0.65]:
			for z in [-0.78, 0.78]:
				_wheel(Vector3(bx + ax, 0.45, z), 0.45, root)
	for d in door:
		for sgn in [-1, 1]:
			A.box(root, Vector3(0.08, 2.4, 0.06), Vector3(d[0] + sgn * 0.8, F + 1.2, 2.25), "metal", Color(0.4, 0.4, 0.4), false)


func _glass_at(parent: Node, pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = A.glass()
	parent.add_child(mi)
	mi.position = pos


## The little rail handcar that brings shop orders. Returns it; caller animates position.x.
func make_handcar() -> Node3D:
	var car := Node3D.new()
	add_child(car)
	A.box(car, Vector3(2.4, 0.15, 1.9), Vector3(0, 0.75, 0), "wood", Color.WHITE, true, 1.0)
	A.box(car, Vector3(2.2, 0.25, 1.4), Vector3(0, 0.55, 0), "rust", Color(0.5, 0.5, 0.5), false)
	for x in [-0.8, 0.8]:
		for z in [-0.78, 0.78]:
			_wheel(Vector3(x, 0.35, z), 0.33, car)
	A.box(car, Vector3(0.12, 1.1, 0.12), Vector3(0, 1.35, 0), "metal", Color(0.4, 0.4, 0.4), false)
	var lever := Node3D.new()
	car.add_child(lever)
	lever.position = Vector3(0, 1.9, 0)
	A.box(lever, Vector3(1.8, 0.08, 0.08), Vector3.ZERO, "rust", Color.WHITE, false, 1.0)
	for x in [-0.9, 0.9]:
		A.box(lever, Vector3(0.08, 0.08, 0.8), Vector3(x, 0, 0), "metal", Color(0.6, 0.6, 0.6), false)
	var tw := lever.create_tween().set_loops()
	tw.tween_property(lever, "rotation:z", 0.35, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(lever, "rotation:z", -0.35, 0.5).set_trans(Tween.TRANS_SINE)
	for sgn in [-1, 1]:
		A.railing(car, Vector3(-1.2, 0.82, sgn * 0.95), Vector3(1.2, 0.82, sgn * 0.95), 0.5, "rust")
	A.sphere(car, 0.08, Vector3(1.1, 1.5, 0.8), "cream", Color(1, 0.75, 0.4), 5.0)
	B.omni(car, Vector3(1.1, 1.5, 0.8), Color(1, 0.75, 0.4), 0.8, 5.0)
	return car
