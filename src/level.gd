# One stop on the route: either a station (surface + elevator + facility) or the checkpoint.
# The train is NOT part of this — it persists while levels slide past it.
extends Node3D

const Data = preload("res://src/data.gd")
const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const P = preload("res://src/props.gd")
const Facility = preload("res://src/facility.gd")
const Elevator = preload("res://src/elevator.gd")
const Roomba = preload("res://src/roomba.gd")
const Pulsator = preload("res://src/pulsator.gd")

const FAC_Y := -60.0
const PLATFORM_Z := Vector2(2.35, 6.5)

var main
var info := {}
var assignment := 1
var rng := RandomNumberGenerator.new()
var facility
var elevator
var hopper := AABB()
var board: Label3D
var gate: Node3D
var gate_light: OmniLight3D
var elevator_pos := Vector3(0, 0, 999)
var _rollers: Array[Node3D] = []
var _sparks: GPUParticles3D
var _houses: Array[Vector3] = []
var _house_spots: Array[Vector3] = []
var _flat: Array = []   # [Vector2 centre, radius] areas kept level
var _noise := FastNoiseLite.new()
var _spawn_t := 0.0
var _surface_spawned := 0


func build(stop: Dictionary, assign: int, seed: int) -> void:
	info = stop
	assignment = maxi(assign, 1)
	rng.seed = seed
	if stop.theme == "CHECKPOINT":
		_checkpoint()
		return
	_surface(stop.biome == "ARCTIC")
	facility = Facility.new()
	facility.main = main
	add_child(facility)
	facility.position = Vector3(elevator_pos.x, FAC_Y, elevator_pos.z)
	facility.build(seed, stop.rooms, stop.theme)
	elevator = Elevator.new()
	add_child(elevator)
	elevator.position = elevator_pos
	elevator.build(self, FAC_Y, Facility.H)
	var total: int = stop.rooms + 6 + assignment * 2
	for i in int(total * 0.66):
		main.spawn_item(Data.random_scrap(rng), facility.random_point(rng), -1.0, self)
	for i in int(total * 0.34):
		var p := _surface_point() + Vector3(0, 0.6, 0)
		if not _houses.is_empty() and rng.randf() < 0.4:
			p = _houses[rng.randi() % _houses.size()] + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		main.spawn_item(Data.random_scrap(rng), p, -1.0, self)
	for i in mini(1 + assignment / 2, 4):
		_spawn(Roomba, facility.random_point(rng, true))
	_spawn(Pulsator, facility.random_point(rng, true))


## Spawn director: more pulsators below over time, and some topside after 18:00.
func tick(delta: float, hours: float) -> void:
	if facility == null:
		return
	_spawn_t += delta
	if _spawn_t > 75.0:
		_spawn_t = 0.0
		if get_tree().get_nodes_in_group("pulsators").size() < 1 + assignment:
			_spawn(Pulsator, facility.random_point(rng, true))
	if hours >= 18.0 and _surface_spawned < 1 + assignment / 3 and rng.randf() < delta * 0.02:
		_surface_spawned += 1
		var p := _surface_point()
		while p.length() < 25.0:
			p = _surface_point()
		_spawn(Pulsator, p + Vector3(0, 0.5, 0))


func next_point(from: Vector3, to: Vector3) -> Vector3:
	if facility and from.y < FAC_Y + 20 and to.y < FAC_Y + 20:
		return facility.path_next(from, to)
	return to


func wander_point(from: Vector3) -> Vector3:
	if facility and from.y < FAC_Y + 20:
		return facility.random_point(rng, true)
	return from + Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-15, 15))


func _spawn(script: Script, pos: Vector3) -> void:
	var m = script.new()
	m.main = main
	m.level = self
	add_child(m)
	m.global_position = pos


func _surface_point() -> Vector3:
	for i in 60:
		var p := Vector3(rng.randf_range(-80, 80), 0, rng.randf_range(-80, 80))
		if absf(p.z) > 9.0 and p.distance_to(elevator_pos) > 12.0 and _clear_of_houses(p, 9.0):
			p.y = ground_y(p.x, p.z)
			return p
	return Vector3(0, 0, 20)


func _clear_of_houses(p: Vector3, r: float) -> bool:
	for h in _houses:
		if Vector2(h.x - p.x, h.z - p.z).length() < r:
			return false
	return true


# --- shared pieces --------------------------------------------------------------------

## Ground slab with an optional square hole (for the elevator shaft).
func _ground(kind: String, tint: Color, hole_center := Vector3(0, 0, 999), hole := 2.3) -> void:
	var lo := -100.0
	var hi := 100.0
	var hz0 := clampf(hole_center.z - hole, lo, hi)
	var hz1 := clampf(hole_center.z + hole, lo, hi)
	var hx0 := hole_center.x - hole
	var hx1 := hole_center.x + hole
	var parts := [
		[Vector2(lo, lo), Vector2(hi, hz0)], [Vector2(lo, hz1), Vector2(hi, hi)],
		[Vector2(lo, hz0), Vector2(hx0, hz1)], [Vector2(hx1, hz0), Vector2(hi, hz1)],
	]
	for p in parts:
		var a: Vector2 = p[0]
		var b: Vector2 = p[1]
		if b.x - a.x < 0.01 or b.y - a.y < 0.01:
			continue
		A.box(self, Vector3(b.x - a.x, 1.0, b.y - a.y), Vector3((a.x + b.x) / 2, -0.5, (a.y + b.y) / 2), kind, tint, true, 3.0)


func _rails() -> void:
	for z in [-0.75, 0.75]:
		A.box(self, Vector3(200, 0.12, 0.1), Vector3(0, 0.06, z), "metal", Color(0.7, 0.68, 0.65), false)
	for i in 100:
		A.box(self, Vector3(0.25, 0.08, 2.4), Vector3(-99.0 + i * 2.0, 0.02, 0), "wood", Color(0.55, 0.5, 0.45), false, 1.0)


func _bounds() -> void:
	for s in [-1, 1]:
		B.invisible_wall(self, Vector3(200, 30, 1), Vector3(0, 15, 95 * s))
		B.invisible_wall(self, Vector3(1, 30, 200), Vector3(95 * s, 15, 0))


## Station platform level with the train doors, with a canopy and ramps down at both ends.
func _platform(title: String) -> void:
	var z0 := PLATFORM_Z.x
	var z1 := PLATFORM_Z.y
	var zc := (z0 + z1) / 2
	A.box(self, Vector3(28, 0.85, z1 - z0), Vector3(0, 0.425, zc), "concrete", Color(0.8, 0.75, 0.7), true)
	A.box(self, Vector3(28, 0.15, z1 - z0 + 0.1), Vector3(0, 0.925, zc), "wood", Color(0.8, 0.75, 0.7), true, 1.5)
	A.box(self, Vector3(28, 0.02, 0.25), Vector3(0, 1.005, z0 + 0.15), "hazard", Color.WHITE, false, 0.6)
	for s in [-1, 1]:
		var ramp := A.box(self, Vector3(3.7, 0.2, z1 - z0), Vector3(s * 15.75, 0.45, zc), "concrete", Color(0.75, 0.7, 0.65), true)
		ramp.rotation.z = -s * 0.28
	for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		A.cyl(self, 0.1, 3.4, Vector3(x, 2.7, z1 - 0.3), "metal", Color(0.5, 0.45, 0.4), true)
	var roof := A.box(self, Vector3(28.5, 0.12, z1 - z0 + 1.2), Vector3(0, 4.45, zc + 0.3), "corrugated", Color(0.75, 0.7, 0.65), false, 1.5)
	roof.rotation.x = -0.08
	for x in [-8.0, 8.0]:
		A.hanging_lamp(self, Vector3(x, 4.35, zc), Color(1, 0.75, 0.45), 0.7, 1.4, false)
	var plate := A.box(self, Vector3(3.6, 0.7, 0.08), Vector3(0, 3.6, zc), "metal", Color(0.25, 0.25, 0.25), false)
	for s in [-1, 1]:
		var t := B.label(plate, title, Vector3(0, 0, s * 0.05), 120, Color(1, 0.8, 0.4), false)
		t.pixel_size = 0.004
		t.rotation.y = 0.0 if s > 0 else PI
	A.box(self, Vector3(2.0, 0.45, 0.5), Vector3(-3.5, 1.225, z1 - 0.6), "wood", Color.WHITE, true, 1.0)
	A.barrel(self, Vector3(10.5, 1.0, z1 - 0.7), rng)
	A.crate(self, Vector3(-10.5, 1.0, z1 - 0.8), 0.8, rng)


# --- surface ----------------------------------------------------------------------------

func _surface(arctic: bool) -> void:
	elevator_pos = Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(38, 62))
	_noise.seed = rng.randi()
	_noise.frequency = 0.018
	_noise.fractal_octaves = 3
	# Decide where flat things go before shaping the ground.
	_flat.append([Vector2(elevator_pos.x, elevator_pos.z), 13.0])
	_flat.append([Vector2(0, 14), 10.0])
	for i in rng.randi_range(3, 5):
		for tries in 30:
			var p := Vector3(rng.randf_range(-75, 75), 0, rng.randf_range(16, 80) * (1.0 if rng.randf() < 0.7 else -1.0))
			if p.distance_to(elevator_pos) > 20.0 and _clear_of_houses(p, 17.0):
				_house_spots.append(p)
				_houses.append(p)
				_flat.append([Vector2(p.x, p.z), 9.0])
				break
	_terrain("snow" if arctic else "sand", elevator_pos)
	_rails()
	_bounds()
	_platform("STATION %s" % info.letter)
	# Station house behind the platform.
	_houses.append(A.wood_house(self, Vector3(rng.randf_range(-6, 6), 0, 14.5), 0.0, rng))
	for p in _house_spots:
		_houses.append(A.wood_house(self, p, atan2(p.x, p.z), rng))
	# Concrete pad around the shaft (the elevator + headframe are built by elevator.gd).
	var e := elevator_pos
	for sgn in [-1, 1]:
		A.box(self, Vector3(11, 0.3, 3.35), e + Vector3(0, -0.09, sgn * 3.83), "concrete", Color(0.85, 0.8, 0.75), true, 2.0)
		A.box(self, Vector3(3.35, 0.3, 4.3), e + Vector3(sgn * 3.83, -0.09, 0), "concrete", Color(0.85, 0.8, 0.75), true, 2.0)
	for p in [e + Vector3(-4.5, 0, -6.5), e + Vector3(4.5, 0, -6.5)]:
		A.lamp_post(self, p, Color(1, 0.75, 0.45))
	A.crate(self, e + Vector3(-6.5, 0, 2.0), 1.0, rng)
	A.barrel(self, e + Vector3(-6.2, 0, 3.4), rng)
	A.pallet(self, e + Vector3(6.0, 0, -3.5))
	# Signposts from the platform to the lift.
	var start := Vector3(rng.randf_range(-8, 8), 0, 9)
	var n := int(start.distance_to(e) / 14.0)
	for i in range(1, n + 1):
		var sp := start.lerp(e, float(i) / (n + 1)) + Vector3(1.8, 0, 0)
		sp.y = ground_y(sp.x, sp.z)
		A.cyl(self, 0.07, 2.4, sp + Vector3(0, 1.2, 0), "wood", Color(0.7, 0.65, 0.6), true)
		B.label(self, "ELEVATOR\n%d m" % int(sp.distance_to(e)), sp + Vector3(0, 2.75, 0), 48, Color(1, 0.85, 0.3))
	var rock := Color(0.85, 0.85, 0.95) if arctic else Color.WHITE
	for i in rng.randi_range(8, 14):
		A.dead_tree(self, _surface_point(), rng)
	for i in rng.randi_range(14, 24):
		var sz := rng.randf_range(0.8, 3.5)
		A.box(self, Vector3(sz, sz * rng.randf_range(0.4, 1.0), sz * rng.randf_range(0.7, 1.3)), _surface_point() + Vector3(0, sz * 0.25, 0), "rock", rock, true, 2.0,
			Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2)))
	for i in rng.randi_range(2, 4):
		_shack(_surface_point())
	for i in rng.randi_range(2, 4):
		P.car_wreck(self, _surface_point(), rng.randf() * TAU, rng)
	for i in rng.randi_range(2, 4):
		P.ruin_wall(self, _surface_point(), rng.randf() * TAU, rng)
	for i in rng.randi_range(2, 4):
		P.scrap_heap(self, _surface_point(), rng)
	for i in rng.randi_range(1, 3):
		var a := _surface_point()
		var dir := Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf() * TAU)
		P.fence(self, a, a + dir * rng.randf_range(10, 25), rng)
	if rng.randf() < 0.7:
		P.water_tower(self, _surface_point())
	for i in rng.randi_range(0, 2):
		P.windmill(self, _surface_point(), rng)
	if rng.randf() < 0.5:
		P.pumpjack(self, _surface_point(), rng.randf() * TAU)
	if rng.randf() < 0.6:
		P.arch_frame(self, _surface_point(), rng.randf() * TAU, rng)
	# Telephone poles with sagging wires along the line.
	var prev := Vector3.INF
	for x in range(-90, 91, 18):
		var pole := Vector3(x, 0, -5.0)
		A.telephone_pole(self, pole)
		if prev != Vector3.INF:
			for z in [-0.7, 0.7]:
				_wire(prev + Vector3(0, 6.5, z), pole + Vector3(0, 6.5, z))
		prev = pole
	# Landmarks in the haze: rock spires and arches past the walkable edge, mesas further out.
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf() * 0.4
		var d := rng.randf_range(100, 125)
		if rng.randf() < 0.3:
			P.rock_arch(self, Vector3(cos(a) * d, -1, sin(a) * d), -a, rng, rock.darkened(0.15))
		else:
			P.rock_spire(self, Vector3(cos(a) * d, -1, sin(a) * d), rng, rock.darkened(0.1))
	for i in 14:
		var a := TAU * i / 14.0 + rng.randf() * 0.3
		var d := rng.randf_range(150, 200)
		var sz := Vector3(rng.randf_range(20, 50), rng.randf_range(15, 45), rng.randf_range(20, 50))
		A.box(self, sz, Vector3(cos(a) * d, sz.y / 2 - 2, sin(a) * d), "rock", rock.darkened(0.25), false, 8.0, Vector3(0, rng.randf() * TAU, 0))


## Rolling dunes, flattened along the track, around the lift and under buildings.
func ground_y(x: float, z: float) -> float:
	if info.get("theme", "") == "CHECKPOINT":
		return 0.0
	var h := _noise.get_noise_2d(x, z) * 3.0 + _noise.get_noise_2d(x * 3.7, z * 3.7) * 0.35
	var m := smoothstep(8.5, 18.0, absf(z))
	for f in _flat:
		m = minf(m, smoothstep(f[1], f[1] + 9.0, Vector2(x, z).distance_to(f[0])))
	return h * m


func _terrain(kind: String, hole: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2.0
	var n := 100
	for i in n:
		for j in n:
			var x0 := -100.0 + i * step
			var z0 := -100.0 + j * step
			if x0 < hole.x + 2.15 and x0 + step > hole.x - 2.15 and z0 < hole.z + 2.15 and z0 + step > hole.z - 2.15:
				continue
			var a := Vector3(x0, ground_y(x0, z0), z0)
			var b := Vector3(x0 + step, ground_y(x0 + step, z0), z0)
			var c := Vector3(x0 + step, ground_y(x0 + step, z0 + step), z0 + step)
			var d := Vector3(x0, ground_y(x0, z0 + step), z0 + step)
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = A.mat(kind, Color.WHITE, 3.0)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	body.add_child(mi)
	add_child(body)


func _wire(a: Vector3, b: Vector3) -> void:
	var mid := (a + b) / 2.0 + Vector3(0, -0.8, 0)
	for seg in [[a, mid], [mid, b]]:
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var w := B.box(self, Vector3(0.025, 0.025, p0.distance_to(p1)), (p0 + p1) / 2.0, Color(0.08, 0.07, 0.07), false)
		w.look_at_from_position(to_global((p0 + p1) / 2.0), to_global(p1), Vector3.UP)


func _shack(p: Vector3) -> void:
	var c := Color(0.75, 0.7, 0.65)
	var r := Node3D.new()
	add_child(r)
	r.position = p
	r.rotation.y = rng.randf() * TAU
	A.box(r, Vector3(4, 3, 0.15), Vector3(0, 1.5, 2), "corrugated", c, true, 1.5)
	A.box(r, Vector3(0.15, 3, 4), Vector3(-2, 1.5, 0), "corrugated", c, true, 1.5)
	A.box(r, Vector3(0.15, 3, 4), Vector3(2, 1.5, 0), "corrugated", c, true, 1.5)
	if rng.randf() < 0.6:
		A.box(r, Vector3(4.4, 0.12, 4.4), Vector3(0, 3.05, 0), "rust", Color.WHITE, true, 1.5, Vector3(0.1, 0, 0))
	A.crate(r, Vector3(1.2, 0, 1.2), 0.7, rng)
	A.barrel(r, Vector3(-1.2, 0, 1.3), rng)


# --- checkpoint ---------------------------------------------------------------------------

func _checkpoint() -> void:
	_ground("concrete", Color(0.7, 0.68, 0.65))
	_rails()
	_bounds()
	_platform("CHECKPOINT")
	var c := Color(0.8, 0.75, 0.7)
	# Hall behind the platform.
	A.wall(self, -9, 9, 20, 7, 0.3, [], "corrugated", c, true, 0.0, true, 1.5)
	A.wall(self, 8, 20, -9, 7, 0.3, [], "corrugated", c, false, 0.0, true, 1.5)
	A.wall(self, 8, 20, 9, 7, 0.3, [], "corrugated", c, false, 0.0, true, 1.5)
	var roof := A.box(self, Vector3(18.6, 0.2, 12.6), Vector3(0, 7.2, 14), "rust", Color(0.75, 0.75, 0.75), true)
	roof.rotation.x = 0.04
	A.hanging_lamp(self, Vector3(0, 7.0, 13), Color(1, 0.8, 0.55), 1.8, 2.2, true)
	A.hanging_lamp(self, Vector3(-6, 7.0, 15), Color(1, 0.8, 0.55), 1.5, 1.2, false)
	B.label(self, "BUREAU OF RECLAIMED MATERIALS", Vector3(0, 8.4, 8), 110, Color(0.95, 0.9, 0.8))
	# Shredder: throw scrap over the rim into the rollers, then pull the lever.
	hopper = AABB(Vector3(-1.5, -0.2, 11.5), Vector3(3, 3, 3))
	for z in [11.4, 14.6]:
		A.box(self, Vector3(3.4, 0.9, 0.2), Vector3(0, 0.45, z), "hazard", Color.WHITE, true, 0.8)
	for x in [-1.6, 1.6]:
		A.box(self, Vector3(0.2, 0.9, 3.4), Vector3(x, 0.45, 13), "hazard", Color.WHITE, true, 0.8)
	A.box(self, Vector3(3, 0.04, 3), Vector3(0, 0.03, 13), "metal", Color(0.15, 0.15, 0.15), false)
	for z in [12.4, 13.6]:
		var roller := Node3D.new()
		add_child(roller)
		roller.position = Vector3(0, 0.3, z)
		A.cyl(roller, 0.3, 2.9, Vector3.ZERO, "rust", Color.WHITE, false, "x")
		for i in 6:
			var a := TAU * i / 6.0
			var tooth := A.box(roller, Vector3(2.8, 0.12, 0.12), Vector3(0, 0.3, 0).rotated(Vector3.RIGHT, a), "metal", Color(0.8, 0.8, 0.8), false)
			tooth.rotation.x = a
		_rollers.append(roller)
		A.spin(roller, "x", 6.0 if z < 13 else -6.0)
	A.box(self, Vector3(3.8, 3.4, 1.4), Vector3(0, 1.7, 15.5), "cream", Color(0.95, 0.85, 0.7), true, 1.0)
	A.pipe(self, Vector3(-1.5, 3.4, 15.5), Vector3(-1.5, 6.9, 15.5), 0.2, "rust")
	A.box(self, Vector3(2.6, 1.1, 0.06), Vector3(0, 2.55, 14.78), "metal", Color(0.12, 0.1, 0.08), false)
	var shred_sign := B.label(self, "SHREDDER", Vector3(0, 3.25, 14.76), 48, Color(0.2, 0.15, 0.1), false)
	shred_sign.rotation.y = PI
	shred_sign.outline_size = 0
	A.box(self, Vector3(0.4, 1.0, 0.4), Vector3(2.4, 0.5, 12.0), "metal", Color(0.4, 0.4, 0.4))
	var lever := B.interactable(self, Vector3(0.1, 0.8, 0.1), Vector3(2.4, 1.35, 12.0), Color(0.9, 0.1, 0.1), "Pull lever: shred & submit", Callable(), 0.0, 0.6)
	lever.action = func():
		var tw := lever.create_tween()
		tw.tween_property(lever, "rotation:x", 0.8, 0.15)
		tw.tween_property(lever, "rotation:x", 0.0, 0.5)
		main.shred()
	_sparks = GPUParticles3D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.amount = 80
	_sparks.lifetime = 0.9
	_sparks.explosiveness = 0.8
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 50.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -12, 0)
	_sparks.process_material = pm
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.03, 0.03, 0.08)
	spark_mesh.material = B.mat(Color(1, 0.6, 0.2), 6.0)
	_sparks.draw_pass_1 = spark_mesh
	add_child(_sparks)
	_sparks.position = Vector3(0, 0.6, 13)
	board = B.label(self, "", Vector3(0, 2.55, 14.74), 40, Color(1, 0.75, 0.3), false)
	board.rotation.y = PI
	board.pixel_size = 0.0035
	# Container shop with a robot clerk behind the counter.
	var shop := P.shop_container(self, Vector3(-13.5, 0, 12.0), 0.0)
	A.box(shop, Vector3(4.0, 1.0, 0.5), Vector3(0, 0.5, -0.6), "wood", Color.WHITE, true, 1.0)
	A.robot(shop, Vector3(0.5, 0.12, 0.4), PI)
	A.shelf_unit(shop, Vector3(-2.0, 0.12, 0.8), 0.0, rng, 1.6, 2.2, 0.5)
	# Red lattice tower around the shredder, like a little derrick.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			A.box(self, Vector3(0.18, 6.5, 0.18), Vector3(sx * 2.4, 3.25, 13.6 + sz * 2.4), "rust", Color(1.0, 0.45, 0.4), true, 1.0)
	for y in [2.2, 4.4, 6.4]:
		for sz in [-1, 1]:
			A.box(self, Vector3(4.9, 0.12, 0.12), Vector3(0, y, 13.6 + sz * 2.4), "rust", Color(1.0, 0.45, 0.4), false, 1.0)
		for sx in [-1, 1]:
			A.box(self, Vector3(0.12, 0.12, 4.9), Vector3(sx * 2.4, y, 13.6), "rust", Color(1.0, 0.45, 0.4), false, 1.0)
	for k in 10:
		A.box(self, Vector3(0.5, 0.05, 0.05), Vector3(2.55, 0.4 + k * 0.6, 15.6), "metal", Color(0.6, 0.6, 0.6), false)
	var beacon := A.glow(self, Vector3(0.3, 0.45, 0.3), Vector3(0, 6.9, 13.6), Color(1, 0.2, 0.1), 5.0)
	beacon.name = "Beacon"
	A.crate(self, Vector3(6.5, 0, 17.5), 1.0, rng)
	A.barrel(self, Vector3(7.0, 0, 16.0), rng)
	# The gate across the line.
	gate = Node3D.new()
	add_child(gate)
	A.box(gate, Vector3(0.5, 5, 8.6), Vector3(24, 2.5, 0), "corrugated", Color(0.85, 0.35, 0.3), true, 1.5)
	A.box(gate, Vector3(0.6, 0.4, 8.6), Vector3(24, 1.0, 0), "hazard", Color.WHITE, false, 0.8)
	for z in [-4.6, 4.6]:
		A.box(self, Vector3(0.6, 10, 0.6), Vector3(24, 5, z), "hazard", Color.WHITE, true, 0.8)
	A.box(self, Vector3(0.6, 0.8, 9.8), Vector3(24, 10.2, 0), "metal", Color(0.4, 0.4, 0.4), true)
	gate_light = B.omni(self, Vector3(22.8, 9.0, 0), Color(1, 0.1, 0.05), 4.0, 14.0)
	A.sphere(self, 0.25, Vector3(23.6, 9.4, 0), "cream", Color(1, 0.2, 0.1), 6.0)


func open_gate() -> void:
	if gate == null or gate_light.light_color.g > 0.5:
		return
	gate_light.light_color = Color(0.1, 1, 0.2)
	create_tween().tween_property(gate, "position:y", 5.4, 2.5).set_trans(Tween.TRANS_SINE)
	Sfx.play(self, "door", Vector3(24, 2, 0), 6.0, 0.7)


func shred_fx() -> void:
	if _sparks:
		_sparks.restart()
		_sparks.emitting = true
	for r in _rollers:
		var tw := r.create_tween()
		tw.tween_property(r, "rotation:x", TAU * 3, 1.5).as_relative()
