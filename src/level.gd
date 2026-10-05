# One stop on the route: either a station (surface + elevator + facility) or the checkpoint.
# The train is NOT part of this — it persists while levels slide past it.
extends Node3D

const Data = preload("res://src/data.gd")
const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
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
		if absf(p.z) > 9.0 and p.distance_to(elevator_pos) > 10.0 and _clear_of_houses(p, 8.0):
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
	_ground("snow" if arctic else "sand", Color.WHITE, elevator_pos)
	_rails()
	_bounds()
	_platform("STATION %s" % info.letter)
	_elevator_building(elevator_pos)
	var start := Vector3(rng.randf_range(-8, 8), 0, 8)
	var n := int(start.distance_to(elevator_pos) / 14.0)
	for i in range(1, n + 1):
		var sp := start.lerp(elevator_pos, float(i) / (n + 1)) + Vector3(1.8, 0, 0)
		A.cyl(self, 0.07, 2.4, sp + Vector3(0, 1.2, 0), "wood", Color(0.7, 0.65, 0.6), true)
		B.label(self, "ELEVATOR\n%d m" % int(sp.distance_to(elevator_pos)), sp + Vector3(0, 2.75, 0), 48, Color(1, 0.85, 0.3))
	for i in rng.randi_range(3, 5):
		for tries in 30:
			var p := Vector3(rng.randf_range(-75, 75), 0, rng.randf_range(14, 80) * (1.0 if rng.randf() < 0.7 else -1.0))
			if p.distance_to(elevator_pos) > 18.0 and _clear_of_houses(p, 16.0):
				_houses.append(A.wood_house(self, p, atan2(p.x, p.z), rng))
				break
	var rock := Color(0.85, 0.85, 0.95) if arctic else Color.WHITE
	for i in rng.randi_range(6, 12):
		A.dead_tree(self, _surface_point(), rng)
	for i in rng.randi_range(14, 24):
		var s := rng.randf_range(0.8, 3.5)
		A.box(self, Vector3(s, s * rng.randf_range(0.4, 1.0), s * rng.randf_range(0.7, 1.3)), _surface_point() + Vector3(0, s * 0.3, 0), "rock", rock, true, 2.0,
			Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2)))
	for i in rng.randi_range(2, 4):
		_shack(_surface_point())
	for x in range(-90, 91, 20):
		A.telephone_pole(self, Vector3(x, 0, -5.0))
	# Far mesas: silhouettes in the haze, beyond the walkable area.
	for i in 14:
		var a := TAU * i / 14.0 + rng.randf() * 0.3
		var d := rng.randf_range(130, 180)
		var s := Vector3(rng.randf_range(20, 50), rng.randf_range(15, 40), rng.randf_range(20, 50))
		A.box(self, s, Vector3(cos(a) * d, s.y / 2 - 2, sin(a) * d), "rock", rock.darkened(0.2), false, 8.0, Vector3(0, rng.randf() * TAU, 0))


func _elevator_building(p: Vector3) -> void:
	var c := Color(0.8, 0.75, 0.7)
	var w := 12.0
	var h := 6.6
	A.wall(self, p.x - w / 2, p.x + w / 2, p.z - w / 2, h, 0.3, [[p.x, 3.4, 0.0, 3.4]], "corrugated", c, true, 0.0, true, 1.5)
	A.wall(self, p.x - w / 2, p.x + w / 2, p.z + w / 2, h, 0.3, [], "corrugated", c, true, 0.0, true, 1.5)
	A.wall(self, p.z - w / 2, p.z + w / 2, p.x - w / 2, h, 0.3, [[p.z, 1.2, 1.6, 2.6]], "corrugated", c, false, 0.0, true, 1.5)
	A.wall(self, p.z - w / 2, p.z + w / 2, p.x + w / 2, h, 0.3, [], "corrugated", c, false, 0.0, true, 1.5)
	A.box(self, Vector3(w + 0.6, 0.3, w + 0.6), p + Vector3(0, h + 0.15, 0), "rust", Color(0.7, 0.7, 0.7), true)
	A.box(self, Vector3(4.6, 1.1, 0.12), p + Vector3(0, h - 0.3, -w / 2 - 0.2), "metal", Color(0.2, 0.2, 0.2), false)
	var t := B.label(self, "ELEVATOR", p + Vector3(0, h - 0.3, -w / 2 - 0.3), 110, Color(1, 0.7, 0.3), false)
	t.rotation.y = PI
	A.wall_lamp(self, p + Vector3(0, 4.0, -w / 2 - 0.2), Vector3(0, 0, -1), Color(1, 0.75, 0.45), 1.6, false)
	A.wall_lamp(self, p + Vector3(-w / 2 + 0.2, 4.0, -2.5), Vector3(1, 0, 0), Color(1, 0.75, 0.45), 1.0, false)
	A.crate(self, p + Vector3(-4.2, 0, -4.0), 0.9, rng)
	A.barrel(self, p + Vector3(4.3, 0, 4.2), rng)
	A.pallet(self, p + Vector3(-4.3, 0, 3.8))


func _shack(p: Vector3) -> void:
	var c := Color(0.75, 0.7, 0.65)
	A.box(self, Vector3(4, 3, 0.15), p + Vector3(0, 1.5, 2), "corrugated", c, true, 1.5)
	A.box(self, Vector3(0.15, 3, 4), p + Vector3(-2, 1.5, 0), "corrugated", c, true, 1.5)
	A.box(self, Vector3(0.15, 3, 4), p + Vector3(2, 1.5, 0), "corrugated", c, true, 1.5)
	if rng.randf() < 0.6:
		A.box(self, Vector3(4.4, 0.12, 4.4), p + Vector3(0, 3.05, 0), "rust", Color.WHITE, true, 1.5, Vector3(0.1, 0, 0))
	A.crate(self, p + Vector3(1.2, 0, 1.2), 0.7, rng)


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
	A.box(self, Vector3(3.8, 2.6, 1.4), Vector3(0, 1.3, 15.5), "metal", Color(0.55, 0.5, 0.45))
	A.pipe(self, Vector3(-1.5, 2.8, 15.5), Vector3(-1.5, 6.9, 15.5), 0.2, "rust")
	A.box(self, Vector3(1.6, 0.6, 0.06), Vector3(0, 1.9, 14.78), "metal", Color(0.15, 0.15, 0.15), false)
	var shred_sign := B.label(self, "SHREDDER", Vector3(0, 1.9, 14.74), 64, Color(1, 0.4, 0.25), false)
	shred_sign.rotation.y = PI
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
	board = B.label(self, "", Vector3(0, 4.6, 15.6), 56, Color(1, 0.8, 0.35))
	# Shop corner with a robot clerk.
	A.box(self, Vector3(3.0, 1.0, 0.8), Vector3(-5.5, 0.5, 13.2), "wood", Color.WHITE, true, 1.0)
	A.robot(self, Vector3(-5.5, 0, 14.3), PI)
	A.shelf_unit(self, Vector3(-5.5, 0, 18.9), 0.0, rng, 3.0, 2.4, 0.6)
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
