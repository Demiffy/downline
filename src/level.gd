# One stop on the route: either a station (surface + elevator + facility) or the checkpoint.
# The train is NOT part of this — it persists while levels slide past it.
extends Node3D

const Data = preload("res://src/data.gd")
const Merge = preload("res://src/merge.gd")
const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const P = preload("res://src/props.gd")
const Facility = preload("res://src/facility.gd")
const Elevator = preload("res://src/elevator.gd")
const Roomba = preload("res://src/roomba.gd")
const Pulsator = preload("res://src/pulsator.gd")
const Statue = preload("res://src/statue.gd")
const Marionette = preload("res://src/marionette.gd")
const Mimic = preload("res://src/mimic.gd")
const Warden = preload("res://src/warden.gd")
const Leviathan = preload("res://src/leviathan.gd")
const BearTrap = preload("res://src/bear_trap.gd")
const Snatcher = preload("res://src/snatcher.gd")
const Gloe = preload("res://src/gloe.gd")
const Scrapper = preload("res://src/scrapper.gd")
const Observer = preload("res://src/observer.gd")
const Wraith = preload("res://src/wraith.gd")
const Hazards = preload("res://src/hazards.gd")

const FAC_Y := -60.0
const PLATFORM_Z := Vector2(2.35, 6.5)

var main
var info := {}
var assignment := 1
var rng := RandomNumberGenerator.new()
var facility
var elevator
var hazards   # hazards.gd: flooded/gassed rooms, steam, power, tremors, airdrops
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
var trail: Array[Vector3] = []   # walking route train -> lift (station house, signposts)
var _station_x := 0.0
var _statue_due := false     # decided per station: does a statue show up after 15:00?
var _leviathan_due := false  # ...and does the worm wake after 17:00?
var _wraith_due := false     # ...and does the wraith come up out of the dark after 16:00?


func build(stop: Dictionary, assign: int, seed: int) -> void:
	info = stop
	assignment = maxi(assign, 1)
	rng.seed = seed
	if stop.theme == "CHECKPOINT":
		_checkpoint()
		Merge.bake(self, 16.0)
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
	for i in int(total * 0.85):
		var at: Vector3 = facility.random_point(rng)
		if not facility.loot_spots.is_empty() and rng.randf() < 0.25:   # some of it up on the mezzanines
			at = facility.to_global(facility.loot_spots[rng.randi() % facility.loot_spots.size()] + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.4, 0.4)))
		main.spawn_item(Data.random_scrap(rng), at, -1.0, self)
	for k in facility.vault_spots.size():   # the vault: one heavy prize, the rest the good stuff
		var id: String = ["ENGINE_BLOCK", "TRANSFORMER", "SAFE_BOX"][rng.randi() % 3] if k == 0 else ("CABLE_DRUM" if k == 1 else Data.valuable_scrap(rng, false))
		main.spawn_item(id, facility.to_global(facility.vault_spots[k]), -1.0, self)
	for i in int(total * 0.42):
		var p := _surface_point() + Vector3(0, 0.6, 0)
		if not _houses.is_empty() and rng.randf() < 0.4:
			p = _houses[rng.randi() % _houses.size()] + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		main.spawn_item(Data.random_scrap(rng), p, -1.0, self)
	if main.logs_unlocked < Data.LOGS.size():
		for i in (1 if rng.randf() < 0.6 else 2):
			main.spawn_item("DISK", facility.random_point(rng), -1.0, self)
	for i in _n("roomba", mini(1 + assignment / 2, 4)):
		_spawn(Roomba, facility.random_point(rng, true))
	for i in maxi(1, _n("pulsator", 1)):
		_spawn(Pulsator, facility.random_point(rng, true))
	for i in _n("mimic", 2 if assignment >= 2 else 1):
		_spawn(Mimic, facility.random_point(rng, true))
	for i in _n("marionette", 0.45 if assignment < 2 else 0.75):
		_spawn(Marionette, facility.random_point(rng, false))
	for i in _n("warden", 1.0 if assignment >= 2 else 0.3):
		_spawn(Warden, facility.random_point(rng, true))
	for i in _n("trap", mini(2 + assignment, 7)):
		var p: Vector3 = facility.random_point(rng, rng.randf() < 0.6)
		_spawn(BearTrap, Vector3(p.x, p.y - 0.6, p.z))
	for i in _n("snatcher", 1 + rng.randi() % 2):
		var p: Vector3 = facility.random_point(rng, true)
		_spawn(Snatcher, Vector3(p.x, facility.global_position.y + Facility.H, p.z))
	for i in _n("scrapper", rng.randi_range(1, 2)):
		_spawn(Scrapper, facility.random_point(rng, false))
	for i in _n("observer", 0.45 if assignment < 2 else 0.8):
		_spawn(Observer, facility.random_point(rng, true))
	for i in _n("gloe", 0.35):
		_spawn(Gloe, facility.random_point(rng, true) + Vector3(0, 1.5, 0))
	_statue_due = rng.randf() < (0.5 if assignment < 3 else 0.9) * Data.HABITAT[stop.theme].statue
	_leviathan_due = rng.randf() < 0.65
	_wraith_due = rng.randf() < (0.4 if assignment < 2 else 0.75) * Data.HABITAT[stop.theme].wraith
	Merge.bake(self, 16.0)   # the facility bakes itself; this does the surface
	hazards = Hazards.new()
	hazards.main = main
	hazards.level = self
	hazards.fac = facility
	add_child(hazards)
	hazards.setup(stop, assignment, seed)


## Spawn director: more pulsators below over time, and some topside after 18:00.
func tick(delta: float, hours: float) -> void:
	if facility == null:
		return
	hazards.tick(hours)
	_spawn_t += delta
	if _spawn_t > 75.0:
		_spawn_t = 0.0
		if get_tree().get_nodes_in_group("pulsators").size() < ceili((1 + assignment) * Data.HABITAT[info.theme].pulsator):
			_spawn(Pulsator, facility.random_point(rng, true))
	if _statue_due and hours >= 15.0:
		_statue_due = false
		_spawn(Statue, _out_of_sight(15.0))
	if _wraith_due and hours >= 16.0:
		_wraith_due = false
		_spawn(Wraith, _out_of_sight(22.0))
	if _leviathan_due and hours >= 17.0:
		_leviathan_due = false
		_spawn(Leviathan, Vector3.ZERO)
	if hours >= 18.0 and _surface_spawned < 1 + assignment / 3 and rng.randf() < delta * 0.02:
		_surface_spawned += 1
		var p := _surface_point()
		while p.length() < 25.0:
			p = _surface_point()
		_spawn(Pulsator, p + Vector3(0, 0.5, 0))


## A facility spot at least `away` metres from everyone (best of a few tries).
func _out_of_sight(away: float) -> Vector3:
	var p: Vector3 = facility.random_point(rng, true)
	for tries in 10:
		if main.players().all(func(pl): return pl.global_position.distance_to(p) > away):
			break
		p = facility.random_point(rng, true)
	return p


## Site power (a power failure leaves the lift on emergency power, cameras and bulkheads offline).
func powered() -> bool:
	return hazards == null or hazards.power


## How many of a creature this site gets: base scaled by its habitat weight here; fractions round by chance.
func _n(kind: String, base: float) -> int:
	var x: float = base * Data.HABITAT[info.theme].get(kind, 1.0)
	return int(x) + (1 if rng.randf() < fmod(x, 1.0) else 0)


func next_point(from: Vector3, to: Vector3) -> Vector3:
	if facility and from.y < FAC_Y + 20 and to.y < FAC_Y + 20:
		return facility.path_next(from, to)
	return to


func stair_route(from: Vector3, to: Vector3) -> Array:
	if facility and from.y < FAC_Y + 20 and to.y < FAC_Y + 20:
		return facility.stair_route(from, to)
	return []


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
		var t := B.label(plate, title, Vector3(0, 0, s * 0.05), 120, Color(0.95, 0.85, 0.6), "plate", 0.004)
		t.rotation.y = 0.0 if s > 0 else PI
	A.box(self, Vector3(2.0, 0.45, 0.5), Vector3(-3.5, 1.225, z1 - 0.6), "wood", Color.WHITE, true, 1.0)
	A.barrel(self, Vector3(10.5, 1.0, z1 - 0.7), rng)
	A.crate(self, Vector3(-10.5, 1.0, z1 - 0.8), 0.8, rng)


# --- surface ----------------------------------------------------------------------------

func _surface(arctic: bool) -> void:
	A.snow_cover = arctic
	_surface_build(arctic)
	if arctic:
		_arctic_dress()
	A.snow_cover = false


func _surface_build(arctic: bool) -> void:
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
			var on_path := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(0, 20.5), Vector2(elevator_pos.x, elevator_pos.z)).distance_to(Vector2(p.x, p.z)) < 14.0
			if p.distance_to(elevator_pos) > 20.0 and not on_path and _clear_of_houses(p, 17.0):   # keep the walk to the lift open
				_house_spots.append(p)
				_houses.append(p)
				_flat.append([Vector2(p.x, p.z), 9.0])
				break
	_terrain("snow" if arctic else "sand", elevator_pos)
	_rails()
	_bounds()
	_platform("STATION %s" % info.letter)
	# Station house behind the platform.
	_station_x = rng.randf_range(-6, 6)
	_houses.append(A.wood_house(self, Vector3(_station_x, 0, 14.5), 0.0, rng, true))   # the station house: walk-through
	# A ramp down off the back of the platform to the station house (the platform is a metre up).
	var back_ramp := A.box(self, Vector3(2.4, 0.2, 3.4), Vector3(_station_x, 0.42, PLATFORM_Z.y + 1.55), "concrete", Color(0.75, 0.7, 0.65), true)
	back_ramp.rotation.x = 0.31
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
	# The way runs out of the station house's back door, then along the posts to the lift.
	var start := Vector3(_station_x, 0, 20.5)
	trail = [Vector3(_station_x, 0, 9.0), Vector3(_station_x, 0, 14.5), start]
	var n := int(start.distance_to(e) / 14.0)
	for i in range(1, n + 1):
		var sp := start.lerp(e, float(i) / (n + 1)) + Vector3(1.8, 0, 0)
		sp.y = ground_y(sp.x, sp.z)
		trail.append(sp - Vector3(1.8, 0, 0))
		A.cyl(self, 0.07, 2.4, sp + Vector3(0, 1.2, 0), "wood", Color(0.7, 0.65, 0.6), true)
		var board := Node3D.new()
		add_child(board)
		board.position = sp + Vector3(0, 2.0, 0)
		board.rotation.y = atan2(start.x - e.x, start.z - e.z)   # +z faces back down the path
		board.rotation.z = rng.randf_range(-0.06, 0.06)
		A.box(board, Vector3(1.1, 0.62, 0.05), Vector3(0, 0, 0.08), "wood", Color(0.75, 0.68, 0.6), false, 0.8)
		for t in [["ELEVATOR", Vector3(0, 0.12, 0.106)], ["%d m" % int(sp.distance_to(e)), Vector3(0.2, -0.15, 0.106)]]:
			B.label(board, t[0], t[1], 40, Color(0.92, 0.85, 0.7), "stencil", 0.0045)
		# Painted arrow pointing on, up the path.
		A.box(board, Vector3(0.05, 0.2, 0.01), Vector3(-0.32, -0.19, 0.106), "cream", Color(0.95, 0.75, 0.25), false)
		for s in [-1, 1]:
			A.box(board, Vector3(0.05, 0.12, 0.01), Vector3(-0.32 + s * 0.035, -0.07, 0.107), "cream", Color(0.95, 0.75, 0.25), false, 1.0, Vector3(0, 0, s * 0.8))
	var rock := Color(0.85, 0.85, 0.95) if arctic else Color.WHITE
	if not arctic:
		for i in rng.randi_range(8, 14):
			A.dead_tree(self, _surface_point(), rng)
	for i in rng.randi_range(14, 24):
		var sz := rng.randf_range(0.8, 3.5)
		P.boulder(self, _surface_point() + Vector3(0, sz * 0.2, 0), Vector3(sz, sz * rng.randf_range(0.45, 0.8), sz * rng.randf_range(0.7, 1.2)), rng, rock, true)
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
		P.fence(self, a, a + dir * rng.randf_range(10, 25), rng, ground_y)
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
		P.mesa(self, Vector3(cos(a) * d, -2, sin(a) * d), rng, rock.darkened(0.2))


## Rolling dunes, flattened along the track, around the lift and under buildings.
## Snowfield extras: spruce woods (in stands, thicker toward the edges), snow drifts piled against the
## houses and on the open ground, a frozen pond or two, snow banks along the track.
func _arctic_dress() -> void:
	for k in rng.randi_range(5, 8):   # stands of trees
		var c := _surface_point()
		while c.length() < 30.0:
			c = _surface_point()
		for t in rng.randi_range(4, 10):
			var p := c + Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
			if absf(p.z) < 10.0 or p.distance_to(elevator_pos) < 14.0 or not _clear_of_houses(p, 8.0) or absf(p.x) > 95.0 or absf(p.z) > 95.0:
				continue
			p.y = ground_y(p.x, p.z) - 0.2
			A.pine(self, p, rng)
	for i in rng.randi_range(6, 10):   # lone trees
		var p := _surface_point()
		A.pine(self, p - Vector3(0, 0.2, 0), rng)
	for h in _houses:   # drifts against the walls
		for k in rng.randi_range(2, 4):
			var a := rng.randf() * TAU
			var dp: Vector3 = h + Vector3(cos(a), 0, sin(a)) * rng.randf_range(4.5, 6.5)
			dp.y = ground_y(dp.x, dp.z)
			_drift(dp, rng.randf_range(2.0, 4.5))
	for i in rng.randi_range(10, 16):
		var p := _surface_point()
		_drift(p, rng.randf_range(2.0, 6.0))
	for i in rng.randi_range(1, 2):   # a frozen pond: glossy blue-white ice with snow round its rim
		var p := _surface_point()
		if not _clear_of_houses(p, 14.0) or p.distance_to(elevator_pos) < 18.0:
			continue
		var ice := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var rad := rng.randf_range(4.0, 7.0)
		cm.top_radius = rad
		cm.bottom_radius = rad
		cm.height = 0.1
		cm.radial_segments = 16
		ice.mesh = cm
		var im := StandardMaterial3D.new()
		im.albedo_color = Color(0.62, 0.74, 0.82)
		im.roughness = 0.08
		im.metallic_specular = 1.0
		ice.material_override = im
		add_child(ice)
		ice.position = p + Vector3(0, 0.12, 0)
		ice.scale = Vector3(1, 1, rng.randf_range(0.6, 0.9))
		for k in 8:
			var a := TAU * k / 8.0
			_drift(p + Vector3(cos(a) * rad, 0, sin(a) * rad * ice.scale.z), rng.randf_range(1.0, 1.8))
	for x in range(-90, 91, 9):   # banks thrown up beside the track by the plough
		for side in [-1.0, 1.0]:
			var z: float = side * rng.randf_range(2.6, 3.1)
			if side > 0.0 and absf(x) < 16.0:
				continue   # (the platform)
			_drift(Vector3(x + rng.randf_range(-2, 2), 0, z), rng.randf_range(2.5, 4.0), 0.55, true)


## A soft mound of snow: a flattened, stretched dome.
func _drift(p: Vector3, size: float, height := 0.0, along_track := false) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 10
	sm.rings = 4
	sm.is_hemisphere = true
	sm.radius = 0.5
	sm.height = 0.5
	mi.mesh = sm
	mi.material_override = A.mat("snow", Color.WHITE, 3.0)
	add_child(mi)
	mi.position = Vector3(p.x, ground_y(p.x, p.z) - 0.05, p.z)
	mi.scale = Vector3(size, height if height > 0.0 else size * rng.randf_range(0.2, 0.35), 1.1 if along_track else size * rng.randf_range(0.5, 1.0))
	mi.rotation.y = 0.0 if along_track else rng.randf() * TAU


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
	P.tin_shed(self, p, rng.randf() * TAU, rng)


# --- checkpoint ---------------------------------------------------------------------------

func _checkpoint() -> void:
	_ground("sand", Color(0.8, 0.72, 0.62))
	_rails()
	_bounds()
	_platform("CHECKPOINT")
	# Concrete yard pad, with a siding track along the far side.
	A.box(self, Vector3(90, 0.06, 40), Vector3(0, 0.03, 26), "concrete", Color(0.72, 0.7, 0.66), true, 3.0)
	A.box(self, Vector3(90, 0.06, 18), Vector3(0, 0.03, -14), "concrete", Color(0.68, 0.66, 0.62), true, 3.0)
	for z in [-9.75, -8.25]:
		A.box(self, Vector3(90, 0.1, 0.08), Vector3(0, 0.1, z), "rust", Color.WHITE, false, 1.0)
	for i in 44:
		A.box(self, Vector3(0.25, 0.06, 2.4), Vector3(-43.0 + i * 2.0, 0.06, -9.0), "wood", Color(0.5, 0.45, 0.4), false, 1.0)
	_reclamation_hall()
	_shredder()
	var shop := P.shop_container(self, Vector3(-14.0, 0.06, 12.5), 0.0, rng, main.open_shop)
	shop.name = "Shop"
	_yard()
	_gate()


## The hall behind the platform: steel frame, trusses, lamps, racks and clutter along the walls.
func _reclamation_hall() -> void:
	var c := Color(0.8, 0.75, 0.7)
	A.wall(self, -9, 9, 20, 7, 0.3, [], "corrugated", c, true, 0.0, true, 1.5)
	A.wall(self, 8, 20, -9, 7, 0.3, [[16.5, 2.0, 0.0, 2.6]], "corrugated", c, false, 0.0, true, 1.5)
	A.wall(self, 8, 20, 9, 7, 0.3, [], "corrugated", c, false, 0.0, true, 1.5)
	# Concrete wainscot inside, painted yellow kerb line on the floor.
	A.box(self, Vector3(17.6, 1.2, 0.08), Vector3(0, 0.6, 19.8), "concrete", Color(0.6, 0.58, 0.55), false, 1.5)
	for s in [-1, 1]:
		A.box(self, Vector3(0.08, 1.2, 11.6), Vector3(s * 8.8, 0.6, 14.2), "concrete", Color(0.6, 0.58, 0.55), false, 1.5)
		A.box(self, Vector3(0.12, 0.01, 11.0), Vector3(s * 4.0, 0.065, 14.0), "cream", Color(0.95, 0.8, 0.2), false, 1.0)
	var roof := A.box(self, Vector3(18.6, 0.2, 12.6), Vector3(0, 7.2, 14), "corrugated", Color(0.6, 0.58, 0.55), true, 1.5)
	roof.rotation.x = 0.04
	for z in [12.0, 16.0]:   # skylight strips
		A.glow(self, Vector3(16, 0.04, 0.8), Vector3(0, 7.05, z), Color(1, 0.88, 0.7), 0.45)
	# Steel frame: I-beam columns, trusses across.
	for z in [8.2, 12.0, 16.0, 19.8]:
		for s in [-1, 1]:
			_ibeam(Vector3(s * 8.75, 0, z), 7.0)
		P.truss(self, Vector3(-8.8, 6.95, z), Vector3(8.8, 6.95, z), 0.9)
	# Front facade: header beam, hazard columns, the sign.
	A.box(self, Vector3(18.8, 1.4, 0.4), Vector3(0, 7.7, 7.85), "riveted", Color(0.45, 0.48, 0.45), true, 1.0)
	for s in [-1, 1]:
		A.box(self, Vector3(0.5, 7.0, 0.5), Vector3(s * 9.05, 3.5, 7.85), "hazard", Color.WHITE, true, 0.8)
	var title := B.label(self, "BUREAU OF RECLAIMED MATERIALS", Vector3(0, 7.75, 7.63), 110, Color(0.9, 0.86, 0.75), "plate")
	title.rotation.y = PI
	var sub := B.label(self, "RECLAMATION HALL 2  -  ALL SCRAP TO THE SHREDDER", Vector3(0, 7.25, 7.63), 40, Color(0.85, 0.8, 0.7), "stencil", 0.01)
	sub.rotation.y = PI
	for x in [-6.0, 6.0]:
		A.wall_lamp(self, Vector3(x, 6.6, 7.6), Vector3(0, 0, -1), Color(1, 0.8, 0.55), 1.5, false)
	# Lights.
	A.hanging_lamp(self, Vector3(0, 7.0, 13), Color(1, 0.8, 0.55), 1.4, 2.4, true)
	for p in [Vector3(-5.5, 7.0, 10.5), Vector3(5.5, 7.0, 10.5), Vector3(-5.5, 7.0, 17.5), Vector3(5.5, 7.0, 17.5)]:
		A.hanging_lamp(self, p, Color(1, 0.8, 0.55), 1.6, 1.3, false)
	# West wall: pallet racks. East: the bale bay, forklift. Back corner: the workshop.
	for z in [10.6, 13.6]:
		P.pallet_rack(self, Vector3(-7.9, 0.06, z), -PI / 2, rng, 2.7)
	A.locker(self, Vector3(-8.4, 0.06, 18.9), -PI / 2)
	A.locker(self, Vector3(-8.4, 0.06, 18.25), -PI / 2)
	P.workbench(self, Vector3(-6.2, 0.06, 19.3), 0.0, rng)
	P.wall_floor_item(self, Vector3(-4.3, 0.06, 19.5), 0.0, rng)
	P.forklift(self, Vector3(6.6, 0.06, 10.6), -0.4)
	for i in 6:
		P.bale(self, Vector3(7.5 - (i % 2) * 1.15, 0.06 + (i / 2) * 0.88, 18.8 - (i / 4) * 1.2), 1.1, rng)
	P.bale(self, Vector3(7.6, 0.06, 15.0), 1.0, rng)
	A.pallet(self, Vector3(5.0, 0.06, 18.9))
	for i in 3:
		A.barrel(self, Vector3(8.0, 0.06, 12.8 + i * 0.75), rng)
	for p in [[Vector3(-9, 0, 9.5), Vector3(1, 0, 0)], [Vector3(-9, 0, 16.8), Vector3(1, 0, 0)], [Vector3(9, 0, 13.6), Vector3(-1, 0, 0)],
			[Vector3(-2.5, 0, 20), Vector3(0, 0, -1)], [Vector3(3.8, 0, 20), Vector3(0, 0, -1)], [Vector3(9, 0, 17.0), Vector3(-1, 0, 0)]]:
		P.wall_fixture(self, p[0] + p[1] * 0.18, p[1], rng)
	P.litter(self, Vector3(0, 0.06, 14), 8.0, rng, 30)
	for i in 4:
		P.stain(self, Vector3(rng.randf_range(-7, 7), 0.06, rng.randf_range(9, 19)), rng)


func _ibeam(at: Vector3, h: float) -> void:
	var steel := Color(0.4, 0.42, 0.4)
	A.box(self, Vector3(0.3, h, 0.04), at + Vector3(0, h / 2, -0.13), "metal", steel, false, 0.8)
	A.box(self, Vector3(0.3, h, 0.04), at + Vector3(0, h / 2, 0.13), "metal", steel, false, 0.8)
	A.box(self, Vector3(0.04, h, 0.26), at + Vector3(0, h / 2, 0), "metal", steel, false, 0.8)
	A.box(self, Vector3(0.45, 0.06, 0.45), at + Vector3(0, 0.09, 0), "metal", steel.darkened(0.3), false)


## The shredder: hopper with a flared steel lip, toothed rollers deep inside, the drive housing behind
## with a spinning flywheel and motor, a gantry with a catwalk, the quota board, a control desk + lever.
func _shredder() -> void:
	hopper = AABB(Vector3(-1.5, -0.2, 11.5), Vector3(3, 3, 3))
	var steel := Color(0.42, 0.44, 0.42)
	var paint := Color(0.85, 0.62, 0.15)
	for z in [11.4, 14.6]:
		A.box(self, Vector3(3.4, 1.1, 0.2), Vector3(0, 0.55, z), "riveted", steel, true, 0.8)
		A.box(self, Vector3(3.5, 0.12, 0.26), Vector3(0, 1.12, z), "hazard", Color.WHITE, false, 0.6)
	for x in [-1.6, 1.6]:
		A.box(self, Vector3(0.2, 1.1, 3.4), Vector3(x, 0.55, 13), "riveted", steel, true, 0.8)
		A.box(self, Vector3(0.26, 0.12, 3.5), Vector3(x, 1.12, 13), "hazard", Color.WHITE, false, 0.6)
	# Flared lip (visual only, so throws clear it).
	var lip_front := A.box(self, Vector3(3.9, 0.05, 0.5), Vector3(0, 1.32, 11.15), "metal", steel.darkened(0.2), false, 0.6)
	lip_front.rotation.x = 0.85
	for s in [-1, 1]:
		var lip := A.box(self, Vector3(0.5, 0.05, 3.9), Vector3(s * 1.85, 1.32, 13), "metal", steel.darkened(0.2), false, 0.6)
		lip.rotation.z = s * 0.85
	A.box(self, Vector3(3, 0.04, 3), Vector3(0, 0.03, 13), "metal", Color(0.08, 0.08, 0.08), false)
	for s in [-1, 1]:   # dark inner walls so the pit reads deep
		A.box(self, Vector3(0.02, 1.0, 2.9), Vector3(s * 1.48, 0.55, 13), "rust", Color(0.25, 0.22, 0.2), false, 0.5)
	for z in [12.4, 13.6]:
		var roller := Node3D.new()
		add_child(roller)
		roller.position = Vector3(0, 0.3, z)
		A.cyl(roller, 0.3, 2.9, Vector3.ZERO, "rust", Color.WHITE, false, "x")
		for i in 8:
			var a := TAU * i / 8.0
			for k in 5:
				var tooth := A.box(roller, Vector3(0.18, 0.16, 0.1), Vector3(-1.2 + k * 0.6 + (i % 2) * 0.3, 0, 0) + Vector3(0, 0.32, 0).rotated(Vector3.RIGHT, a), "metal", Color(0.75, 0.75, 0.72), false, 0.3)
				tooth.rotation.x = a
		_rollers.append(roller)
		A.spin(roller, "x", 6.0 if z < 13 else -6.0)
	# Drive housing behind the hopper.
	A.box(self, Vector3(4.2, 3.2, 2.4), Vector3(0, 1.6, 15.9), "riveted", paint, true, 1.0)
	A.box(self, Vector3(4.4, 0.25, 2.6), Vector3(0, 3.3, 15.9), "metal", paint.darkened(0.3), false, 0.8)
	for x in [-1.4, 0.0, 1.4]:
		A.box(self, Vector3(0.9, 0.5, 0.04), Vector3(x, 0.55, 14.68), "grille", Color.WHITE, false, 0.3)
	A.box(self, Vector3(2.0, 0.3, 0.02), Vector3(-0.9, 2.95, 14.69), "hazard", Color.WHITE, false, 0.5)
	var warn := B.label(self, "KEEP HANDS CLEAR", Vector3(0.9, 2.95, 14.68), 40, Color(0.12, 0.1, 0.08), "stencil", 0.007)
	warn.rotation.y = PI
	# Quota board in a bolted frame.
	A.box(self, Vector3(2.8, 1.2, 0.08), Vector3(0, 1.95, 14.66), "metal", Color(0.15, 0.15, 0.15), false, 0.5)
	A.box(self, Vector3(2.6, 1.0, 0.02), Vector3(0, 1.95, 14.61), "metal", Color(0.03, 0.03, 0.03), false)
	for x in [-1.3, 1.3]:
		for y in [1.4, 2.5]:
			A.sphere(self, 0.03, Vector3(x, y, 14.6), "metal", Color(0.7, 0.7, 0.7))
	board = B.display(self, "", Vector3(0, 1.95, 14.59), 40, Color(1, 0.75, 0.3))
	board.rotation.y = PI
	board.pixel_size = 0.0035
	# Motor on the side, belt to a flywheel that spins.
	A.cyl(self, 0.55, 1.4, Vector3(-2.9, 0.75, 16.3), "metal", Color(0.3, 0.4, 0.5), true, "z")
	for k in 6:
		A.ring(self, 0.6, 0.52, Vector3(-2.9, 0.75, 15.75 + k * 0.22), "metal", Color(0.3, 0.4, 0.5), Vector3(PI / 2, 0, 0))
	A.box(self, Vector3(1.2, 0.3, 1.6), Vector3(-2.9, 0.15, 16.3), "metal", Color(0.25, 0.25, 0.25), true, 0.5)
	var fly := Node3D.new()
	add_child(fly)
	fly.position = Vector3(-2.25, 2.0, 15.9)
	A.cyl(fly, 1.0, 0.18, Vector3.ZERO, "metal", Color(0.35, 0.35, 0.35), false, "x")
	A.ring(fly, 1.02, 0.86, Vector3.ZERO, "metal", Color(0.5, 0.5, 0.5), Vector3(0, 0, PI / 2))
	for i in 4:
		A.box(fly, Vector3(0.12, 1.7, 0.12), Vector3(-0.1, 0, 0), "metal", paint, false, 0.3, Vector3(i * PI / 4, 0, 0))
	A.spin(fly, "x", 2.5)
	A.seg(self, Vector3(-2.3, 2.95, 15.9), Vector3(-2.9, 1.3, 16.3), 0.05, 0.05, "rubber")
	A.seg(self, Vector3(-2.3, 1.05, 15.9), Vector3(-2.9, 0.25, 16.3), 0.05, 0.05, "rubber")
	# Dust stack up through the roof.
	A.pipe(self, Vector3(1.2, 3.4, 16.3), Vector3(1.2, 7.4, 16.3), 0.3, "metal", Color(0.6, 0.6, 0.6))
	# Gantry over it all: four columns, braces, a catwalk with railings, a ladder, a beacon.
	var red := Color(0.75, 0.25, 0.18)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_ibeam_col(Vector3(sx * 2.6, 0, 13.8 + sz * 2.6), 5.0, red)
		A.seg(self, Vector3(sx * 2.6, 0.3, 11.2), Vector3(sx * 2.6, 4.6, 16.4), 0.06, 0.06, "metal", red)
	for sz in [-1, 1]:
		A.box(self, Vector3(5.4, 0.25, 0.2), Vector3(0, 4.9, 13.8 + sz * 2.6), "metal", red, false, 0.6)
	A.box(self, Vector3(5.2, 0.06, 1.2), Vector3(0, 5.05, 11.8), "grate", Color.WHITE, false, 0.5)
	A.railing(self, Vector3(-2.6, 5.05, 11.2), Vector3(2.6, 5.05, 11.2), 1.0, "metal")
	for k in 16:
		A.box(self, Vector3(0.5, 0.04, 0.04), Vector3(2.85, 0.35 + k * 0.3, 16.6), "metal", Color(0.6, 0.6, 0.6), false)
	for s in [-0.22, 0.22]:
		A.box(self, Vector3(0.05, 5.0, 0.05), Vector3(2.85 + s, 2.5, 16.6), "metal", Color(0.6, 0.6, 0.6), false)
	var beacon := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.16
	bm.height = 0.32
	beacon.mesh = bm
	add_child(beacon)
	beacon.position = Vector3(0, 5.3, 16.4)
	P._blink(beacon, Color(1, 0.25, 0.1), 1.2)
	# Output chute to a skip full of bales.
	var chute := A.box(self, Vector3(1.4, 0.08, 2.6), Vector3(3.3, 1.0, 16.3), "metal", steel, false, 0.6)
	chute.rotation.z = -0.35
	A.box(self, Vector3(2.6, 1.0, 2.2), Vector3(5.2, 0.55, 16.3), "rust", Color(0.4, 0.5, 0.35), true, 1.0)
	for i in 4:
		P.bale(self, Vector3(4.7 + (i % 2) * 0.9, 0.5 + (i / 2) * 0.5, 15.9 + (i / 2) * 0.6), 0.8, rng)
	# Control desk with the lever.
	A.box(self, Vector3(0.9, 1.0, 0.6), Vector3(2.5, 0.5, 11.6), "metal", Color(0.4, 0.42, 0.4), true, 0.6)
	var top := A.box(self, Vector3(0.95, 0.05, 0.7), Vector3(2.5, 1.05, 11.55), "metal", Color(0.3, 0.3, 0.3), false, 0.4)
	top.rotation.x = 0.3
	for i in 3:
		A.glow(self, Vector3(0.08, 0.04, 0.08), Vector3(2.25 + i * 0.25, 1.08, 11.45), [Color(0.2, 1, 0.3), Color(1, 0.8, 0.1), Color(1, 0.2, 0.1)][i], 3.0)
	A.cyl(self, 0.07, 0.05, Vector3(2.5, 1.1, 11.7), "plastic", Color(0.85, 0.1, 0.08))
	var lever := B.interactable(self, Vector3(0.08, 0.8, 0.08), Vector3(3.05, 1.2, 11.6), Color(0.35, 0.35, 0.35), "Pull lever: shred & submit", Callable(), 0.0, 0.0)
	A.sphere(lever, 0.09, Vector3(0, 0.42, 0), "plastic", Color(0.85, 0.1, 0.08))
	A.box(self, Vector3(0.15, 0.25, 0.25), Vector3(3.0, 0.85, 11.6), "metal", Color(0.25, 0.25, 0.25), false)
	lever.action = func():
		var tw := lever.create_tween()
		tw.tween_property(lever, "rotation:x", 0.8, 0.15)
		tw.tween_property(lever, "rotation:x", 0.0, 0.5)
		main.shred()
	var shred_sign := B.label(self, "SHREDDER", Vector3(0, 4.65, 11.08), 60, Color(0.95, 0.9, 0.8), "stencil", 0.008)
	shred_sign.rotation.y = PI
	A.box(self, Vector3(2.6, 0.55, 0.05), Vector3(0, 4.65, 11.13), "metal", Color(0.75, 0.25, 0.18), false, 0.5)
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
	B.omni(self, Vector3(0, 3.0, 12.5), Color(1, 0.75, 0.45), 1.0, 6.0)


func _ibeam_col(at: Vector3, h: float, c: Color) -> void:
	A.box(self, Vector3(0.22, h, 0.04), at + Vector3(0, h / 2, -0.1), "metal", c, false, 0.8)
	A.box(self, Vector3(0.22, h, 0.04), at + Vector3(0, h / 2, 0.1), "metal", c, false, 0.8)
	A.box(self, Vector3(0.04, h, 0.2), at + Vector3(0, h / 2, 0), "metal", c, true, 0.8)


## The yard around the hall: container stacks, a scrap mountain under a gantry crane, fuel tanks,
## floodlight towers, a gatehouse, a fence, old wagons on the siding.
func _yard() -> void:
	var cc := [Color(0.25, 0.4, 0.55), Color(0.65, 0.25, 0.15), Color(0.3, 0.45, 0.3), Color(0.75, 0.6, 0.2), Color(0.5, 0.5, 0.5)]
	# Container stacks west of the shop.
	for i in 3:
		for k in rng.randi_range(1, 3):
			P.shipping_container(self, Vector3(-22.0 - i * 2.6, 0.06 + k * 2.62, 13.0 + rng.randf_range(-0.2, 0.2)), rng.randf_range(-0.03, 0.03), cc[rng.randi() % cc.size()], rng)
	P.shipping_container(self, Vector3(-21.0, 0.06, 23.0), PI / 2 + 0.1, cc[0], rng)
	P.shipping_container(self, Vector3(-27.0, 0.06, 24.0), PI / 2 - 0.05, cc[1], rng)
	# Scrap mountain + gantry crane east of the hall.
	P.scrap_heap(self, Vector3(20, 0, 20), rng, 2.2)
	P.scrap_heap(self, Vector3(27, 0, 25), rng, 1.5)
	P.scrap_heap(self, Vector3(14, 0, 27), rng, 1.2)
	P.gantry_crane(self, Vector3(20, 0.06, 20), 0.15, 18.0, 9.0)
	for i in 10:
		P.bale(self, Vector3(13.0 + (i % 5) * 1.2, 0.06 + (i / 5) * 0.95, 11.0), 1.1, rng)
	P.forklift(self, Vector3(16.0, 0.06, 13.5), PI + 0.3)
	# Fuel tanks behind the hall.
	P.fuel_tank(self, Vector3(-4.0, 0.06, 26.0), 0.0)
	P.fuel_tank(self, Vector3(4.0, 0.06, 26.5), 0.05, Color(0.75, 0.3, 0.2))
	P.water_tower(self, Vector3(-16.0, 0.06, 32.0))
	# Gatehouse and the fence round the back.
	P.guard_booth(self, Vector3(20.0, 0.06, 5.0), -PI / 2, rng)
	for seg in [[Vector3(-40, 0, 38), Vector3(40, 0, 38)], [Vector3(-40, 0, 9), Vector3(-40, 0, 38)], [Vector3(40, 0, 9), Vector3(40, 0, 38)],
			[Vector3(-40, 0, -19), Vector3(40, 0, -19)]]:
		P.fence(self, seg[0], seg[1], rng)
	# Floodlights over the yard, aimed in.
	P.floodlight_tower(self, Vector3(-11.0, 0.06, 24.0), PI * 0.85)
	P.floodlight_tower(self, Vector3(12.0, 0.06, 32.0), -PI * 0.8)
	P.floodlight_tower(self, Vector3(-30.0, 0.06, -12.0), PI * 0.25, 11.0, false)
	# Across the tracks: old wagons on the siding, more containers, poles along the line.
	P.boxcar(self, Vector3(-12.0, 0.06, -9.0), 0.0, rng)
	P.boxcar(self, Vector3(1.0, 0.06, -9.0), 0.02, rng)
	for i in 4:
		P.shipping_container(self, Vector3(14.0 + i * 3.0, 0.06, -14.0), PI / 2 + rng.randf_range(-0.05, 0.05), cc[rng.randi() % cc.size()], rng)
	P.shipping_container(self, Vector3(17.0, 2.68, -14.0), PI / 2, cc[2], rng)
	for x in [-36.0, -18.0, 0.0, 18.0, 36.0]:
		A.telephone_pole(self, Vector3(x, 0, -4.5))
	for x in [-30.0, -10.0]:
		A.lamp_post(self, Vector3(x, 0.06, -5.5), Color(1, 0.75, 0.45))
	for i in 6:
		A.crate(self, Vector3(rng.randf_range(-35, -22), 0.06, rng.randf_range(-16, -12)), rng.randf_range(0.7, 1.1), rng)
	for i in 8:
		A.barrel(self, Vector3(rng.randf_range(10, 35), 0.06, rng.randf_range(30, 36)), rng)
	P.car_wreck(self, Vector3(-33.0, 0.06, 30.0), 0.7, rng)
	P.litter(self, Vector3(0, 0.06, 26), 20.0, rng, 40)


## The gate across the line: two lattice towers, a heavy shutter that lifts when the quota is met.
func _gate() -> void:
	var red := Color(0.8, 0.3, 0.22)
	for z in [-4.8, 4.8]:
		A.box(self, Vector3(1.4, 0.6, 1.4), Vector3(24, 0.3, z), "concrete", Color(0.7, 0.68, 0.65), true, 1.0)
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				A.box(self, Vector3(0.14, 11.0, 0.14), Vector3(24 + sx * 0.45, 5.8, z + sz * 0.45), "metal", red, sz == -1 and sx == -1, 0.8)
		for i in 9:
			var y := 0.8 + i * 1.15
			A.box(self, Vector3(1.0, 0.08, 0.08), Vector3(24, y, z - 0.45), "metal", red, false, 0.5)
			A.box(self, Vector3(1.0, 0.08, 0.08), Vector3(24, y, z + 0.45), "metal", red, false, 0.5)
			A.box(self, Vector3(0.08, 0.08, 1.0), Vector3(24 - 0.45, y, z), "metal", red, false, 0.5)
			A.box(self, Vector3(0.08, 0.08, 1.0), Vector3(24 + 0.45, y, z), "metal", red, false, 0.5)
		A.box(self, Vector3(1.4, 11.0, 1.4), Vector3(24, 5.8, z), "metal", red, true, 1.0).visible = false
	A.box(self, Vector3(1.4, 1.2, 11.0), Vector3(24, 11.6, 0), "riveted", Color(0.45, 0.45, 0.45), true, 1.0)
	var title := B.label(self, "CHECKPOINT", Vector3(23.28, 11.6, 0), 110, Color(0.95, 0.9, 0.8), "plate")
	title.rotation.y = -PI / 2
	gate = Node3D.new()
	gate.set_meta("live", true)   # slides open
	add_child(gate)
	A.box(gate, Vector3(0.4, 5.6, 8.6), Vector3(24, 2.8, 0), "riveted", Color(0.55, 0.52, 0.48), true, 1.2)
	for y in [0.6, 5.2]:
		A.box(gate, Vector3(0.5, 0.5, 8.6), Vector3(24, y, 0), "hazard", Color.WHITE, false, 0.8)
	for k in 4:
		A.box(gate, Vector3(0.48, 0.2, 8.6), Vector3(24, 1.6 + k * 0.9, 0), "metal", Color(0.35, 0.35, 0.35), false, 0.5)
	var paint := B.label(gate, "QUOTA FIRST", Vector3(23.78, 3.1, 0), 90, Color(0.9, 0.86, 0.75), "stencil", 0.012)
	paint.rotation.y = -PI / 2
	gate_light = B.omni(self, Vector3(22.8, 9.8, 0), Color(1, 0.1, 0.05), 4.0, 14.0)
	A.sphere(self, 0.3, Vector3(23.2, 10.6, 0), "cream", Color(1, 0.2, 0.1), 6.0)


func open_gate() -> void:
	if gate == null or gate_light.light_color.g > 0.5:
		return
	gate_light.light_color = Color(0.1, 1, 0.2)
	create_tween().tween_property(gate, "position:y", 5.4, 2.5).set_trans(Tween.TRANS_SINE)
	Sfx.play(self, "door", Vector3(24, 2, 0), 6.0, 0.7)
	Sfx.play(self, "clang_big", Vector3(24, 4, 0), 4.0)


func shred_fx() -> void:
	if _sparks:
		_sparks.restart()
		_sparks.emitting = true
	for r in _rollers:
		var tw := r.create_tween()
		tw.tween_property(r, "rotation:x", TAU * 3, 1.5).as_relative()
