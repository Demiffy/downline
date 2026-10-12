# One stop on the route: either a station (surface + elevator + facility) or the checkpoint.
# The train is NOT part of this — it persists while levels slide past it.
extends Node3D

const Data = preload("res://src/data.gd")
const Merge = preload("res://src/merge.gd")
const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const P = preload("res://src/props.gd")
const Shredder = preload("res://src/shredder.gd")
const Facility = preload("res://src/facility.gd")
const Elevator = preload("res://src/elevator.gd")
const WinchTruck = preload("res://src/winch_truck.gd")
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
const Siren = preload("res://src/siren.gd")
const Husk = preload("res://src/husk.gd")
const POSSESS_AFTER := 90.0
const OTHER_Z := -21.0   # the other line (line.gd's OTHER_Z)   # seconds a body lies in the dark before something gets into it
const Hazards = preload("res://src/hazards.gd")
const Station = preload("res://src/station.gd")
const Biomes = preload("res://src/biomes.gd")
const Landmarks = preload("res://src/landmarks.gd")
const SiteClock = preload("res://src/site_clock.gd")
const Director = preload("res://src/director.gd")

const FAC_Y := -60.0
const PLATFORM_Z := Vector2(2.35, 6.5)

var main
var info := {}
var biome := "DESERT"
var water_y := -INF       # the swamp's water (footsteps splash under it)
var _boards: Array = []   # boardwalk runs [a, b, deck height]: footsteps on them are wood
var site   # site_clock.gd: what the facility does through the day
var director   # director.gd: paces the scares
var safes: Array = []     # safes and strongboxes on the surface (the facility's crate list keeps them, for saves)
var landmark := ""        # the station's landmark (Landmarks.FOR), if it has one
var _landmark_at := Vector3.INF
var _landmark_rot := 0.0
var assignment := 1
var rng := RandomNumberGenerator.new()
var _spot_rng := RandomNumberGenerator.new()
var _possess_t := 0.0
var keycard_at := Vector3.INF   # where the vault keycard was left
var facility
var elevator
var hazards   # hazards.gd: flooded/gassed rooms, steam, power, tremors, airdrops
var hopper := AABB()
var board: Label3D
var gate: Node3D
var gate_light: OmniLight3D
var elevator_pos := Vector3(0, 0, 999)
var shredder   # shredder.gd, at the checkpoint
var _houses: Array[Vector3] = []
var _house_spots: Array[Vector3] = []
var _flat: Array = []   # [Vector2 centre, radius] areas kept level
var _noise := FastNoiseLite.new()
var _spawn_t := 0.0
var _surface_spawned := 0
var trail: Array[Vector3] = []   # walking route train -> lift (station house, signposts)
var _station_x := 0.0
var _station_spot := Vector3.ZERO   # a spot inside the booking office (for loot)
var _statue_due := false     # decided per station: does a statue show up after 15:00?
var _leviathan_due := false  # ...and does the worm wake after 17:00?
var _wraith_due := false     # ...and does the wraith come up out of the dark after 16:00?


const CP_FAR := 800.0   # the checkpoint's view distance: the far side of the basin and the skyline mesas


## Builds the stop. `sliced`: spread over frames (a few milliseconds each, the train running on
## meanwhile: line.gd), else all at once. Either way the same stop: at every slice point the global
## dice are reseeded from the seed and the point's name, so where it pauses changes nothing.
var _sliced := false
var _seed := 0
var _frame_t := 0
const SLICE_USEC := 5000

var _snow := false   # (A.snow_cover as this build wants it: put back after every pause)

func _slice(tag: String) -> void:
	if _sliced and Time.get_ticks_usec() - _frame_t > SLICE_USEC:
		await get_tree().process_frame
		_frame_t = Time.get_ticks_usec()
		A.snow_cover = _snow
	if tag != "":
		seed(hash([_seed, tag]))



func build(stop: Dictionary, assign: int, seed: int, sliced := false) -> void:
	await build_geometry(stop, assign, seed, sliced)
	await populate(sliced)


## Everything that stays put: the ground, the buildings, the facility (merged, its navmesh baked),
## the lift. Nothing's spawned and nothing touches the network, so it can be built ahead of time,
## hidden, while the train's still on its way (main._prebuild).
func build_geometry(stop: Dictionary, assign: int, seed: int, sliced := false) -> void:
	info = stop
	assignment = maxi(assign, 1)
	rng.seed = seed
	_seed = seed
	_sliced = sliced
	_frame_t = Time.get_ticks_usec()
	var mark := Callable(self, "_slice")
	await _slice("start")
	if stop.theme == "CHECKPOINT":
		await _checkpoint()
		await Merge.bake(self, 24.0, false, CP_FAR, mark if sliced else Callable())   # (one draw a chunk, so the whole basin can be seen across)
		return
	biome = stop.get("biome", "DESERT")
	await _surface(biome)
	await _slice("facility")
	facility = Facility.new()
	facility.main = main
	add_child(facility)
	facility.position = Vector3(elevator_pos.x, FAC_Y, elevator_pos.z)
	await facility.build(seed, stop.rooms, stop.theme, mark, sliced)
	facility.supplies.append_array(safes)   # (so a save remembers which were pried open)
	await _slice("lift")
	elevator = Elevator.new()
	add_child(elevator)
	elevator.position = elevator_pos
	elevator.build(self, FAC_Y, Facility.H)
	if main != null and main.has_upgrade("LIFT_MOTOR"):
		_winch_truck()
	await _slice("merge")
	await Merge.bake(self, 16.0, false, Merge.FAR, mark if sliced else Callable())   # the facility bakes itself; this does the surface


## What's in it: scrap, the vault's prizes, the keycard, an earlier crew, the creatures, the hazards.
## Spawned things go out to the crew, so this runs once the stop is the current one.
func populate(sliced := false) -> void:
	_sliced = sliced
	_frame_t = Time.get_ticks_usec()
	var stop := info
	if stop.theme == "CHECKPOINT":
		return
	var seed := _seed
	await _slice("populate")
	var total: int = stop.rooms - facility.layout.get("corridor", {}).size() + 6 + assignment * 2   # (rooms, not the corridors between them)
	for i in int(total * 0.85):
		if i % 6 == 5:
			await _slice("scrap %d" % i)
		var at: Vector3 = facility.random_point(rng)
		if not facility.loot_spots.is_empty() and rng.randf() < 0.25:   # some of it up on the mezzanines
			at = facility.to_global(facility.loot_spots[rng.randi() % facility.loot_spots.size()] + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.4, 0.4)))
		main.spawn_item(Data.random_scrap(rng), at, -1.0, self)
	for k in facility.vault_spots.size():   # the vault: one heavy prize in the cage, gold on the table, the rest the good stuff
		var id: String = ["ENGINE_BLOCK", "TRANSFORMER", "SAFE_BOX"][rng.randi() % 3] if k == 0 else ("GOLD_BAR" if k <= 2 else (["CASH_BOX", "BEARER_BONDS"][rng.randi() % 2] if k == 3 else Data.valuable_scrap(rng, false)))
		main.spawn_item(id, facility.to_global(facility.vault_spots[k]), -1.0, self)
	if facility.twin_cell != Vector2i(999, 999):   # behind the blast door: something worth two of you
		var tc := Vector3(facility.twin_cell.x * Facility.CELL, 1.0, facility.twin_cell.y * Facility.CELL)
		main.spawn_item(Data.valuable_scrap(rng, true), facility.to_global(tc), -1.0, self)
		main.spawn_item(Data.valuable_scrap(rng, false), facility.to_global(tc + Vector3(1.5, 0, 1.0)), -1.0, self)
	if facility.secure_cell != Vector2i(999, 999):   # the records room: what the Bureau filed away
		var sc := Vector3(facility.secure_cell.x * Facility.CELL, 1.0, facility.secure_cell.y * Facility.CELL)
		for k in rng.randi_range(2, 3):
			main.spawn_item(Data.valuable_scrap(rng, k == 0), facility.to_global(sc + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))), -1.0, self)
		if main.logs_unlocked < Data.LOGS.size():
			main.spawn_item("DISK", facility.to_global(sc + Vector3(0, 0.2, 0)), -1.0, self)
	await _slice("keycard")
	_place_keycard()
	_old_crew()
	for i in int(total * 0.42):
		var p := _surface_point() + Vector3(0, 0.6, 0)
		if not _houses.is_empty() and rng.randf() < 0.4:
			p = _houses[rng.randi() % _houses.size()] + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		main.spawn_item(Data.random_scrap(rng), p, -1.0, self)
	if rng.randf() < 0.55:   # somebody left something to swing
		main.spawn_item("FIRE_AXE" if rng.randf() < 0.25 else "CROWBAR", facility.random_point(rng), -1.0, self)
	for i in (1 if rng.randf() < 0.55 else 0) + (1 if rng.randf() < 0.25 else 0):   # a box of shells someone dropped
		main.spawn_item("SHELLS", facility.random_point(rng), -1.0, self)
	for i in rng.randi_range(1, 2) + (1 if stop.theme == "LAB" else 0):   # first-aid kits left behind
		main.spawn_item("MEDKIT", facility.random_point(rng), -1.0, self)
	if main.logs_unlocked < Data.LOGS.size():
		for i in (1 if rng.randf() < 0.6 else 2):
			main.spawn_item("DISK", facility.random_point(rng), -1.0, self)
	await _slice("creatures")
	for i in _n("roomba", mini(1 + assignment / 2, 4)):
		_spawn(Roomba, facility.random_point(rng, true))
	for i in maxi(1, _n("pulsator", 1)):
		_spawn(Pulsator, facility.random_point(rng, true))
	for i in _n("mimic", 2 if assignment >= 2 else 1):
		_spawn(Mimic, facility.random_point(rng, true))
	for i in _n("marionette", 0.65 if assignment < 2 else 1.0):
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
	for i in _n("observer", 0.7 if assignment < 2 else 1.1):
		_spawn(Observer, facility.random_point(rng, true))
	for i in _n("siren", 0.7 if assignment < 2 else 1.1):
		_spawn(Siren, facility.random_point(rng, true))
	for i in main.followers:   # (whatever ran beside the train in the tunnel is down here now)
		_spawn(Siren, facility.random_point(rng, true))
	main.followers = 0
	for i in _n("gloe", 0.5):
		_spawn(Gloe, facility.random_point(rng, true) + Vector3(0, 1.5, 0))
	_statue_due = rng.randf() < (0.65 if assignment < 3 else 0.95) * Data.HABITAT[stop.theme].statue
	_leviathan_due = rng.randf() < 0.65
	_wraith_due = rng.randf() < (0.55 if assignment < 2 else 0.85) * Data.HABITAT[stop.theme].wraith
	await _slice("hazards")
	hazards = Hazards.new()
	hazards.main = main
	hazards.level = self
	hazards.fac = facility
	add_child(hazards)
	hazards.setup(stop, assignment, seed)
	site = SiteClock.new()   # (the facility through the day: bursts, lockdowns, the lift at 23:00)
	site.main = main
	site.level = self
	site.fac = facility
	site.hz = hazards
	add_child(site)
	site.setup(seed)
	director = Director.new()   # (paces the scares to how frightened the crew is: director.gd)
	director.main = main
	director.level = self
	director.fac = facility
	add_child(director)


## Spawn director: more pulsators below over time, and some topside after 18:00.
func tick(delta: float, hours: float) -> void:
	if facility == null:
		return
	hazards.tick(hours)
	if site != null:
		site.tick(hours, delta)
	if director != null:
		director.tick(delta)
	_possess_t -= delta
	if _possess_t <= 0.0:
		_possess_t = 1.0
		_possessions()
	_spawn_t += delta
	if _spawn_t > 110.0 and not (director != null and director.quiet):   # another one crawls in now and then: far off, never in front of anyone (not while the director's giving the crew a breather)
		_spawn_t = 0.0
		if get_tree().get_nodes_in_group("pulsators").size() < maxi(1, roundi((0.5 + 0.5 * assignment) * Data.HABITAT[info.theme].pulsator)):
			var p := _hidden_spot(24.0)
			if p != Vector3.INF:
				_spawn(Pulsator, p)
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
		var p := _surface_hidden(40.0)   # crawling up out of the dunes far off, never next to anyone
		if p != Vector3.INF:
			_surface_spawned += 1
			_spawn(Pulsator, p + Vector3(0, 0.5, 0))


## The vault keycard: somewhere far from the lift and well away from the vault, up on a
## mezzanine or down on the lower floor if there's one, with a bear trap set beside it if it's on
## the floor. (Every machine makes the same draws; only the host spawns.)
func _place_keycard() -> void:
	if facility.vault_code == "":
		return
	var vault_at: Vector3 = facility.to_global(Vector3(facility.vault_cell.x * Facility.CELL, 0, facility.vault_cell.y * Facility.CELL))
	var start: Vector3 = facility.global_position
	var best := Vector3.INF
	var best_score := -INF
	var raised := false
	var cands := []
	for s in facility.loot_spots:
		cands.append([facility.to_global(s) + Vector3(rng.randf_range(-0.5, 0.5), 0.1, rng.randf_range(-0.3, 0.3)), true])
	for i in 14:
		cands.append([facility.random_point(rng), false])
	for c in cands:
		var p: Vector3 = c[0]
		if p.distance_to(vault_at) < 14.0:
			continue
		var score := p.distance_to(start) + (6.0 if c[1] else 0.0) + (5.0 if p.y < facility.global_position.y - 1.0 else 0.0)
		if score > best_score:
			best_score = score
			best = p
			raised = c[1]
	if best == Vector3.INF:
		best = facility.random_point(rng)
	keycard_at = best
	main.spawn_item("VAULT_KEYCARD", best + Vector3(0, 0.15, 0), -1.0, self)
	if not raised:
		var off := Vector3(0.9, 0, 0).rotated(Vector3.UP, rng.randf() * TAU)
		_spawn(BearTrap, best + off - Vector3(0, 0.6, 0), false)


## Someone from an earlier crew who never made it back: their body lies somewhere down there,
## and it gets up as a husk not long after you arrive (nameless, like every husk). (The same
## draws on every machine; the host makes the body.)
const OLD_CREW := ["J. MORROW", "A. KASPAR", "R. VELNER", "T. NOVAK", "M. ODUYA", "S. HALE", "L. BRANDT", "K. IVERS", "P. DUNMORE", "E. SOKOL"]
func _old_crew() -> void:
	var chance := 0.45 if assignment < 2 else 0.75
	var bodies := (1 if rng.randf() < chance else 0) + (1 if rng.randf() < chance * 0.35 else 0)
	for i in bodies:
		var at: Vector3 = facility.random_point(rng)
		var who: String = OLD_CREW[rng.randi() % OLD_CREW.size()]
		var wait := rng.randf_range(30.0, 70.0)
		var r = main.spawn_item("REMAINS", at, -1.0, self)
		if r != null:
			r.set_meta("born", Time.get_ticks_msec() / 1000.0 - (POSSESS_AFTER - wait) * Data.pace())
			r.set_meta("old_crew", true)
			r.set_meta("scan_name", "REMAINS (UNKNOWN)")


## A body left lying down in the facility long enough gets up again: a husk.
func _possessions() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for r in get_tree().get_nodes_in_group("pickups"):
		if r.id != "REMAINS" or r.has_meta("no_possess") or not is_ancestor_of(r) or r.is_queued_for_deletion():
			continue
		if r.global_position.y > facility.global_position.y + 6.0:
			continue   # (only down there, in the dark)
		if not r.has_meta("born"):
			r.set_meta("born", now)
		if now - float(r.get_meta("born")) < POSSESS_AFTER * Data.pace():
			continue
		var at: Vector3 = r.global_position
		var who: String = r.get_meta("who", "")
		r.queue_free()   # (quietly: it just gets up)
		var h = _spawn(Husk, to_local(at) + Vector3(0, 0.1, 0), false)
		if h != null and who != "":
			h.set_who(who)
			main.net.ent_event(h, "who", [who])


## A spot on the surface at least `away` metres from everyone and 30 from the train, that nobody
## can see, or INF if there's none.
func _surface_hidden(away: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	for tries in 30:
		var p := to_global(_surface_point(_spot_rng))
		if p.distance_to(main.train.global_position) < 30.0:
			continue
		var ok := true
		for pl in main.players():
			if pl.global_position.distance_to(p) < away:
				ok = false
				break
			var q := PhysicsRayQueryParameters3D.create(pl.cam.global_position, p + Vector3(0, 1.0, 0), 1)
			if space.intersect_ray(q).is_empty():
				ok = false
				break
		if ok:
			return to_local(p)
	return Vector3.INF


## A facility spot at least `away` metres from everyone that nobody can see, or INF if there's none.
func _hidden_spot(away: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	for tries in 24:
		var p: Vector3 = facility.random_point(_spot_rng, true)   # (its own dice: the host alone rolls these, so the build's stay in step)
		var ok := true
		for pl in main.players():
			if pl.global_position.distance_to(p) < away:
				ok = false
				break
			var q := PhysicsRayQueryParameters3D.create(pl.cam.global_position, p + Vector3(0, 1.0, 0), 1)
			if space.intersect_ray(q).is_empty():
				ok = false   # in plain view
				break
		if ok:
			return p
	return Vector3.INF


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
	var x: float = base * Data.HABITAT[info.theme].get(kind, 1.0) * sqrt(maxf(info.get("rooms", 16) / 16.0, 1.0))   # (more of them in a bigger place)
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
		for tries in 20:   # somewhere it can actually get to (not behind a shut bulkhead)
			var p: Vector3 = facility.random_point(rng, true)
			if facility.reachable(from, p):
				return p
		# Sealed into a corner of the site: just mill about where it is.
		return from + Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-3.0, 3.0))
	return from + Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-15, 15))


func _spawn(script: Script, pos: Vector3, guard := true) -> Node:
	var look := randi()   # its random looks, so a crewmate's copy comes out the same
	var resume := randi()   # (drawn everywhere, so the rest of the build stays in step with the host's)
	if not main.net.authority():
		return null   # creatures live on the host; we see its copies
	if guard and script != Leviathan and script != Snatcher and script != BearTrap:   # (these wait in place; the worm is everywhere)
		var gp := to_global(pos)
		var crowded: bool = gp.distance_to(main.train.global_position) < 25.0 or main.players().any(func(pl): return pl.global_position.distance_to(gp) < 20.0)
		if crowded:   # never right by the train or on top of someone: somewhere else, out of sight, or not at all
			if facility == null or gp.y > facility.global_position.y + 8.0:
				return null
			var alt := _hidden_spot(24.0)
			if alt == Vector3.INF:
				return null
			pos = alt
	var m = script.new()
	m.main = main
	m.level = self
	seed(look)
	add_child(m)
	seed(resume)
	m.global_position = pos
	main.net.register(m, {"k": "mob", "script": script.resource_path, "look": look})
	return m


func _surface_point(r: RandomNumberGenerator = null) -> Vector3:
	if r == null:
		r = rng
	for i in 60:
		var p := Vector3(r.randf_range(-80, 80), 0, r.randf_range(-80, 80))
		if absf(p.z) > 9.0 and absf(p.z - OTHER_Z) > 9.0 and p.distance_to(elevator_pos) > 12.0 and _clear_of_houses(p, 9.0) and _station_clear(p, 3.0):
			p.y = ground_y(p.x, p.z)
			return p
	return Vector3(0, 0, 20)


## Not on the station: its building and forecourt, the platform's ends, the signal box (`r` more).
func _station_clear(p: Vector3, r: float) -> bool:
	if info.get("theme", "") == "CHECKPOINT":
		return true
	if p.x > _station_x - 14.0 - r and p.x < _station_x + 14.0 + r and p.z > 2.0 - r and p.z < 25.0 + r:
		return false
	if p.x > Station.X0 - 8.0 - r and p.x < Station.X1 + 8.0 + r and p.z > -6.0 - r and p.z < 8.0 + r:
		return false
	return Vector2(p.x - (Station.X0 - 12.0), p.z - 7.6).length() > 8.0 + r


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
	if info.get("theme", "") == "CHECKPOINT":
		return
	# The other line runs through too, on its own ballast (line.gd lays it on between stops).
	var oz := OTHER_Z
	A.box(self, Vector3(200, 0.1, 3.0), Vector3(0, -0.02, oz), "gravel", Color(0.66, 0.62, 0.58), true, 1.5)
	for z in [-0.75, 0.75]:
		A.box(self, Vector3(200, 0.12, 0.1), Vector3(0, 0.06, oz + z), "metal", Color(0.7, 0.68, 0.65), false)
	for i in 100:
		A.box(self, Vector3(0.25, 0.08, 2.4), Vector3(-99.0 + i * 2.0, 0.02, oz), "wood", Color(0.55, 0.5, 0.45), false, 1.0)


func _bounds() -> void:
	for s in [-1, 1]:
		B.invisible_wall(self, Vector3(200, 30, 1), Vector3(0, 15, 95 * s))
		B.invisible_wall(self, Vector3(1, 30, 200), Vector3(95 * s, 15, 0)).add_to_group("across_line")   # (line.gd lets the train through)


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

func _surface(bio: String) -> void:
	var arctic := bio == "ARCTIC"
	_snow = arctic
	A.snow_cover = arctic
	await _surface_build(arctic)
	if arctic:
		await _slice("snow")
		A.snow_cover = true
		_arctic_dress()
	_snow = false
	A.snow_cover = false
	_houses.append(_station_spot)


func _surface_build(arctic: bool) -> void:
	elevator_pos = Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(38, 62))
	_noise.seed = rng.randi()
	_noise.frequency = 0.018
	_noise.fractal_octaves = 3
	# Decide where flat things go before shaping the ground.
	_flat.append([Vector2(elevator_pos.x, elevator_pos.z), 13.0])
	_flat.append([Vector2(0, 14), 10.0])
	_station_x = rng.randf_range(-6, 6)
	_flat.append([Vector2(_station_x, 14.0), 17.0])               # the station building and its forecourt
	_flat.append([Vector2(Station.X0 - 12.0, 7.6), 8.0])           # the signal box
	if info.get("biome", "") == "CITY":   # the town's streets: two along the line, one across (decided before the houses)
		_city_cx = _station_x + rng.randf_range(18.0, 30.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	_choose_landmark()
	for i in rng.randi_range(3, 5):
		for tries in 30:
			var p := Vector3(rng.randf_range(-75, 75), 0, rng.randf_range(16, 80) * (1.0 if rng.randf() < 0.7 else -1.0))
			var on_path := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(0, 20.5), Vector2(elevator_pos.x, elevator_pos.z)).distance_to(Vector2(p.x, p.z)) < 14.0
			if _city_cx != INF and _on_street(p, 9.0):
				continue
			if p.distance_to(elevator_pos) > 20.0 and not on_path and _clear_of_houses(p, 17.0) and _station_clear(p, 12.0) and absf(p.z - OTHER_Z) > 16.0:   # keep the walk to the lift open
				_house_spots.append(p)
				_houses.append(p)
				_flat.append([Vector2(p.x, p.z), 9.0])
				break
	_trail_a = Vector2(_station_x, 20.5)
	_trail_b = Vector2(elevator_pos.x, elevator_pos.z)
	_terrain(Data.biome(biome).ground, elevator_pos)
	await _slice("station")
	A.snow_cover = arctic   # (and again after every pause: a line chunk may have built in between)
	_rails()
	_bounds()
	# The station: platform, canopy, the booking office (walked through to the forecourt behind), the
	# signal box and water crane (station.gd).
	_station_spot = Station.build(self, String(info.letter), _station_x, rng, arctic)   # (a house for loot, once the snow's been laid)
	await _slice("houses")
	A.snow_cover = arctic
	for p in _house_spots:
		_houses.append(A.wood_house(self, p, atan2(p.x, p.z), rng))
	if landmark != "":
		await _slice("landmark")
		A.snow_cover = arctic
		_landmark_at.y = ground_y(_landmark_at.x, _landmark_at.z)
		for sp in Landmarks.build(self, landmark, _landmark_at, _landmark_rot, rng, biome):
			_houses.append(sp)
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
	trail = [Vector3(_station_x, 1.0, 5.0), Vector3(_station_x, 1.0, 10.5), Vector3(_station_x, 0, 16.6), start]
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
	await _slice("scenery")
	A.snow_cover = arctic
	if biome in ["SWAMP", "FOREST", "CITY"]:
		await _dress(biome)
		return
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
	await _slice("poles")
	A.snow_cover = arctic
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
		if absf(sin(a)) * d < 34.0:   # (the line runs on out past the edge, through the next valley)
			a += 0.6 * signf(sin(a) if sin(a) != 0.0 else 1.0)
		if rng.randf() < 0.3:
			P.rock_arch(self, Vector3(cos(a) * d, -1, sin(a) * d), -a, rng, rock.darkened(0.15))
		else:
			P.rock_spire(self, Vector3(cos(a) * d, -1, sin(a) * d), rng, rock.darkened(0.1))
	for i in 14:
		var a := TAU * i / 14.0 + rng.randf() * 0.3
		var d := rng.randf_range(150, 200)
		if absf(sin(a)) * d < 60.0:
			continue   # (none across the line)
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
			if side > 0.0 and x > Station.X0 - 6.0 and x < Station.X1 + 6.0:
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
	match biome:
		"SWAMP":   # low and sodden: the hollows hold water, hummocks stand out of it
			h = _noise.get_noise_2d(x, z) * 2.6 - 0.5 + _noise.get_noise_2d(x * 3.7, z * 3.7) * 0.25
			var tr := Geometry2D.get_closest_point_to_segment(Vector2(x, z), _trail_a, _trail_b).distance_to(Vector2(x, z))
			h = minf(h, lerpf(0.05, h, smoothstep(2.5, 5.0, tr)))   # (the boardwalk's way stays clear of the hummocks)
		"CITY":   # a town on the flat, level under its streets
			h *= 0.25
			if _on_street(Vector3(x, 0, z), 6.0):
				h = 0.0
			elif _on_street(Vector3(x, 0, z), 10.0):
				h *= 0.3
		"FOREST":
			h *= 1.15
	var m := smoothstep(8.5, 18.0, minf(absf(z), absf(z - OTHER_Z)))   # (level along both lines)
	for f in _flat:
		m = minf(m, smoothstep(f[1], f[1] + 9.0, Vector2(x, z).distance_to(f[0])))
	return h * m


var _city_cx := INF          # the town's cross street (x)
const STREETS_Z := [30.0, 78.0]


func _on_street(p: Vector3, r: float) -> bool:
	if _city_cx == INF:
		return false
	for z in STREETS_Z:
		if absf(p.z - z) < r:
			return true
	return absf(p.x - _city_cx) < r and p.z > -14.0


var _trail_a := Vector2.ZERO   # the way from the station's back door to the lift
var _trail_b := Vector2.ZERO


## Is this on a boardwalk (its deck, not the water under it)?
func on_boards(pos: Vector3) -> bool:
	var l := to_local(pos)
	for b in _boards:
		var a: Vector3 = b[0]
		var e: Vector3 = b[1]
		if absf(l.y - b[2]) < 0.4 and Geometry2D.get_closest_point_to_segment(Vector2(l.x, l.z), Vector2(a.x, a.z), Vector2(e.x, e.z)).distance_to(Vector2(l.x, l.z)) < 0.85:
			return true
	return false


## Most stations have a landmark out on the surface (a chapel, a fire lookout, a farm, a filling
## station: what suits the country), facing the station, on ground flattened for it.
func _choose_landmark() -> void:
	var kinds: Array = Landmarks.FOR.get(biome, [])
	var none := rng.randf() < 0.2
	var kind: String = kinds[rng.randi() % kinds.size()] if not kinds.is_empty() else ""
	if Engine.has_meta("force_landmark"):   # (shot scripts)
		kind = Engine.get_meta("force_landmark")
		none = false
	if kind == "" or none:
		return
	var rad: float = Landmarks.RADIUS[kind]
	var trail_b := Vector2(elevator_pos.x, elevator_pos.z)
	for tries in 40:
		var a := rng.randf() * TAU
		var d := rng.randf_range(34.0, 72.0)
		var p := Vector3(cos(a) * d, 0, absf(sin(a)) * d + 10.0)
		if absf(p.x) > 82.0 or p.z > 85.0 or p.z < rad + 16.0:   # (well back from the track)
			continue
		var tr := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(_station_x, 20.5), trail_b).distance_to(Vector2(p.x, p.z))
		if p.distance_to(elevator_pos) < rad + 14.0 or tr < rad + 4.0 or not _station_clear(p, rad + 4.0) or (_city_cx != INF and _on_street(p, rad + 6.0)):
			continue
		landmark = kind
		_landmark_at = p
		var to := Vector3(_station_x, 0, 14.0) - p
		_landmark_rot = atan2(-to.x, -to.z)   # (its front, -z, toward the station)
		_flat.append([Vector2(p.x, p.z), rad])
		for off in [Vector3.ZERO, Vector3(0, 0, -8), Vector3(0, 0, 8), Vector3(0, 0, 14), Vector3(-6, 0, 0), Vector3(6, 0, 0)]:
			_houses.append(p + off.rotated(Vector3.UP, _landmark_rot))   # (houses and trees keep off all of it)
		_flat.append([Vector2(p.x, p.z) + Vector2(0, 12).rotated(-_landmark_rot), rad * 0.7])
		return


## Clear of the way to the lift by `r`.
func _off_trail(p: Vector3, r: float) -> bool:
	return Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), _trail_a, _trail_b).distance_to(Vector2(p.x, p.z)) > r


## A point for scenery in the new biomes: on open ground, clear of the track, the lift, houses, the
## station and the way to the lift.
func _dress_point(keep: float) -> Vector3:
	for i in 40:
		var p := _surface_point()
		if _off_trail(p, keep) and p.distance_to(elevator_pos) > 10.0 + keep and _clear_of_houses(p, 8.0 + keep) and _station_clear(p, 2.0 + keep):
			return p
	return Vector3.INF


## The forest, the swamp and the town: their own dressing over the shared ground (the station, the
## lift, the houses and the signposts are already up), then their skyline.
func _dress(bio: String) -> void:
	var rock: Color = Data.biome(bio).rock_tint
	match bio:
		"FOREST":
			for i in rng.randi_range(160, 210):   # the wood: oaks, birches and spruce, thicker toward the edge
				var p := _dress_point(2.5)
				if p == Vector3.INF or (p.length() < 35.0 and rng.randf() < 0.5):
					continue
				p.y -= 0.15
				var roll := rng.randf()
				if roll < 0.42:
					Biomes.oak(self, p, rng, rng.randf_range(0.85, 1.25))
				elif roll < 0.6:
					Biomes.birch(self, p, rng)
				else:
					A.pine(self, p, rng, false)
				if i % 12 == 0:
					await _slice("trees")
			for i in rng.randi_range(130, 170):
				var p := _dress_point(1.0)
				if p != Vector3.INF:
					Biomes.fern(self, p, rng)
			for i in rng.randi_range(60, 80):
				var p := _dress_point(1.2)
				if p != Vector3.INF:
					Biomes.bush(self, p, rng, Color(0.48, 0.56, 0.36))
			for i in rng.randi_range(8, 14):
				var p := _dress_point(4.0)
				if p != Vector3.INF:
					Biomes.fallen_log(self, p - Vector3(0, 0.15, 0), rng.randf() * TAU, rng)
			for i in rng.randi_range(10, 18):
				var p := _dress_point(1.5)
				if p != Vector3.INF:
					Biomes.stump(self, p, rng)
			for i in rng.randi_range(10, 16):
				var p := _dress_point(2.0)
				if p != Vector3.INF:
					var sz := rng.randf_range(0.8, 2.6)
					var bd := P.boulder(self, p + Vector3(0, sz * 0.2, 0), Vector3(sz, sz * rng.randf_range(0.45, 0.8), sz * rng.randf_range(0.7, 1.2)), rng, rock, true)
					A.box(bd, Vector3(sz * 0.7, 0.04, sz * 0.6), Vector3(0, sz * 0.32, 0), "moss", Color(0.9, 1.0, 0.8), false, 0.5)   # moss on its back
			for i in rng.randi_range(1, 2):
				_shack(_surface_point())
		"SWAMP":
			water_y = Biomes.WATER
			Biomes.water(self, 200.0, rng, ground_y)
			await _slice("water")
			# The boardwalk from the station's back door out to the lift, in runs that wander a little.
			var a3 := Vector3(_trail_a.x, 0, _trail_a.y)
			var e3 := Vector3(_trail_b.x, 0, _trail_b.y)
			var runs := maxi(int(a3.distance_to(e3) / 12.0), 1)
			var prev := a3
			for k in runs:
				var t := float(k + 1) / runs
				var q := a3.lerp(e3, t)
				if k < runs - 1:
					q += Vector3(rng.randf_range(-1.2, 1.2), 0, 0)
				else:
					q = q.lerp(a3, 7.0 / maxf(a3.distance_to(e3), 8.0))   # (stop at the lift's pad)
				Biomes.boardwalk(self, prev, q, 0.32, rng, ground_y)
				_boards.append([prev, q, 0.32])
				prev = q
			for i in rng.randi_range(40, 60):   # cypress, in the water and on the hummocks
				var p := _dress_point(3.0)
				if p != Vector3.INF:
					Biomes.cypress(self, Vector3(p.x, minf(p.y, 0.0), p.z), rng)
				if i % 10 == 0:
					await _slice("cypress")
			for i in rng.randi_range(14, 22):
				var p := _dress_point(2.0)
				if p != Vector3.INF:
					A.dead_tree(self, p - Vector3(0, 0.3, 0), rng)
			for i in 200:   # reeds where the ground meets the water
				var p := _dress_point(1.0)
				if p != Vector3.INF and absf(p.y - Biomes.WATER) < 0.45:
					Biomes.reeds(self, p, rng)
			for i in rng.randi_range(2, 4):
				var p := _dress_point(6.0)
				if p != Vector3.INF and p.y < 0.0:
					Biomes.stilt_shack(self, Vector3(p.x, Biomes.WATER - 0.3, p.z), rng.randf() * TAU, rng)
			for i in rng.randi_range(2, 4):
				var p := _dress_point(3.0)
				if p != Vector3.INF and absf(p.y - Biomes.WATER) < 0.6:
					Biomes.rowboat(self, Vector3(p.x, Biomes.WATER - 0.05, p.z), rng.randf() * TAU, rng)
			for i in rng.randi_range(6, 10):
				var p := _dress_point(2.0)
				if p != Vector3.INF:
					var sz := rng.randf_range(0.8, 2.0)
					P.boulder(self, p + Vector3(0, sz * 0.1, 0), Vector3(sz, sz * 0.5, sz), rng, rock, true)
			for i in rng.randi_range(1, 3):
				P.car_wreck(self, _surface_point() - Vector3(0, 0.3, 0), rng.randf() * TAU, rng)
		"CITY":
			# Streets: one along the line behind the station, one out past the lift, a cross street.
			var cx := _city_cx
			for z in STREETS_Z:   # in pieces: none through the lift's pad or the station
				var x0 := -95.0
				while x0 < 95.0:
					var mid := Vector3(x0 + 6.0, 0, z)
					if mid.distance_to(elevator_pos) > 9.0 and _station_clear(mid, 1.0):
						Biomes.street(self, Vector3(x0, 0.0, z), Vector3(x0 + 12.0, 0.0, z), rng)
					x0 += 12.0
			Biomes.street(self, Vector3(cx, 0.0, 12.0), Vector3(cx, 0.0, 95.0), rng)
			await _slice("streets")
			var blocks := 0
			for i in 60:   # blocks along the streets, facing them
				if blocks >= rng.randi_range(12, 16):
					break
				var along := rng.randf_range(-88, 88)
				var z: float = [30.0, 78.0][rng.randi() % 2]
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var d := rng.randf_range(7.0, 10.0)
				var p := Vector3(along, 0, z + side * (5.5 + 2.0 + d / 2.0))
				if absf(p.z) < 14.0 or not _off_trail(p, 9.0) or p.distance_to(elevator_pos) < 18.0 or not _clear_of_houses(p, 14.0) or not _station_clear(p, 8.0) or absf(p.x - cx) < 12.0:
					continue
				p.y = ground_y(p.x, p.z) - 0.1
				Biomes.ruin_block(self, p, 0.0 if side < 0.0 else PI, rng, rng.randf_range(9.0, 14.0), d)
				_houses.append(p)
				blocks += 1
				if blocks % 3 == 0:
					await _slice("blocks")
			var x := -90.0
			while x < 90.0:   # streetlamps down the streets
				for z in [30.0 - 5.0, 78.0 + 5.0]:
					var p := Vector3(x + rng.randf_range(-1, 1), 0, z)
					if _station_clear(p, 1.0) and _off_trail(p, 2.0):
						Biomes.streetlamp(self, p, PI / 2.0 if z < 50.0 else -PI / 2.0, rng)
				x += 16.0
			for z in [30.0, 78.0]:
				for s2 in [-1.0, 1.0]:
					Biomes.traffic_light(self, Vector3(cx + s2 * 4.6, 0, z + s2 * 4.6), rng.randf() * TAU, rng)
			for i in rng.randi_range(4, 7):
				var p := _dress_point(3.0)
				if p != Vector3.INF:
					P.car_wreck(self, p, rng.randf() * TAU, rng)
			for i in rng.randi_range(1, 2):
				var p := _dress_point(6.0)
				if p != Vector3.INF:
					Biomes.bus(self, p, rng.randf() * TAU, rng)
			for i in rng.randi_range(8, 14):
				var p := _dress_point(2.0)
				if p != Vector3.INF:
					Biomes.rubble(self, p, rng, rng.randf_range(0.8, 2.0))
			for i in rng.randi_range(1, 2):
				var p := _dress_point(5.0)
				if p != Vector3.INF:
					Biomes.billboard(self, p, rng.randf() * TAU, rng)
			for i in rng.randi_range(12, 20):
				var p := _dress_point(1.5)
				if p != Vector3.INF:
					Biomes.bush(self, p, rng, Color(0.62, 0.66, 0.42))
			for i in rng.randi_range(4, 8):
				var p := _dress_point(2.0)
				if p != Vector3.INF:
					A.dead_tree(self, p, rng)
	await _slice("poles")
	var prev_pole := Vector3.INF   # telephone poles along the line, as everywhere
	for px in range(-90, 91, 18):
		var pole := Vector3(px, 0, -5.0)
		A.telephone_pole(self, pole)
		if prev_pole != Vector3.INF:
			for z in [-0.7, 0.7]:
				_wire(prev_pole + Vector3(0, 6.5, z), pole + Vector3(0, 6.5, z))
		prev_pole = pole
	# The skyline: wooded ridges, or a dead city's towers.
	for i in 12:
		var a := TAU * i / 12.0 + rng.randf() * 0.4
		var d := rng.randf_range(115, 190) if bio != "CITY" else rng.randf_range(170, 260)
		if absf(sin(a)) * d < 40.0:
			continue   # (none across the line)
		var at := Vector3(cos(a) * d, -2, sin(a) * d)
		if bio == "CITY":
			Biomes.tower(self, at, rng)
		else:
			Biomes.tree_ridge(self, at, rng, Color(0.36, 0.42, 0.34) if bio == "FOREST" else Color(0.34, 0.36, 0.3))


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
	await load("res://src/checkpoint.gd").build(self, rng, Callable(self, "_slice"))   # (the whole site round the core below)
	await _slice("core")
	_rails()
	_platform("CHECKPOINT")
	# Concrete yard pad, with a siding track along the far side.
	A.box(self, Vector3(90, 0.06, 40), Vector3(0, 0.03, 26), "concrete", Color(0.72, 0.7, 0.66), true, 3.0)
	A.box(self, Vector3(90, 0.06, 18), Vector3(0, 0.03, -14), "concrete", Color(0.68, 0.66, 0.62), true, 3.0)
	for z in [-9.75, -8.25]:
		A.box(self, Vector3(90, 0.1, 0.08), Vector3(0, 0.1, z), "rust", Color.WHITE, false, 1.0)
	for i in 44:
		A.box(self, Vector3(0.25, 0.06, 2.4), Vector3(-43.0 + i * 2.0, 0.06, -9.0), "wood", Color(0.5, 0.45, 0.4), false, 1.0)
	await _slice("hall")
	_reclamation_hall()
	await _slice("shredder")
	_shredder()
	var shop := P.shop_container(self, Vector3(-14.0, 0.06, 12.5), 0.0, rng, main.open_shop)
	shop.name = "Shop"
	await _slice("yard")
	_yard()
	_gate()


## The hall behind the platform: a steel-framed shed on a concrete plinth, corrugated walls with a
## band of high windows, a pitched roof with a glazed lantern along the ridge and roof vents, pitched
## trusses, a bridge crane on runway beams, gutters and downpipes, a lean-to annex on the east side;
## racks and clutter along the walls inside.
const HALL_EAVE := 7.2
const HALL_RIDGE := 9.6
const HALL_HALF := 9.15

func _hall_roof_y(x: float) -> float:
	return HALL_EAVE + (HALL_RIDGE - HALL_EAVE) * (1.0 - absf(x) / HALL_HALF)


func _reclamation_hall() -> void:
	var c := Color(0.8, 0.75, 0.7)
	var steel := Color(0.4, 0.42, 0.4)
	var wins := []   # a band of high windows between the columns, both side walls
	for z in [10.1, 14.0, 17.9]:
		wins.append([z, 2.6, 4.7, 6.2])
	A.wall(self, -9, 9, 20, 7, 0.3, [[-4.5, 2.4, 4.7, 6.2], [4.5, 2.4, 4.7, 6.2]], "corrugated", c, true, 0.0, true, 1.5)
	A.wall(self, 8, 20, -9, 7, 0.3, wins + [[16.5, 2.0, 0.0, 2.6]], "corrugated", c, false, 0.0, true, 1.5)
	A.wall(self, 8, 20, 9, 7, 0.3, wins, "corrugated", c, false, 0.0, true, 1.5)
	var glass := []
	for z in [10.1, 14.0, 17.9]:
		for s in [-1.0, 1.0]:
			glass.append([Vector3(s * 9.0, 5.45, z), Vector3(0.02, 1.5, 2.6), Vector3(0.36, 0.08, 2.8), true])
	for x in [-4.5, 4.5]:
		glass.append([Vector3(x, 5.45, 20.0), Vector3(2.4, 1.5, 0.02), Vector3(2.6, 0.08, 0.36), false])
	for g in glass:   # wired glass in a steel frame, mullions, a sill
		var at: Vector3 = g[0]
		var pane = A.box(self, g[1], at, "metal", Color.WHITE, false)
		pane.material_override = A.glass()
		var side: bool = g[3]
		for y in [-0.79, 0.79]:
			A.box(self, g[2], at + Vector3(0, y, 0), "metal", steel, false, 0.5)
		for k in 3:
			var off := (k - 1) * 0.86
			A.box(self, Vector3(0.36, 1.5, 0.06) if side else Vector3(0.06, 1.5, 0.36), at + (Vector3(0, 0, off) if side else Vector3(off, 0, 0)), "metal", steel, false, 0.5)
		A.box(self, Vector3(0.5, 0.06, 2.8) if side else Vector3(2.8, 0.06, 0.5), at + Vector3(0, -0.86, 0), "concrete", Color(0.6, 0.58, 0.55), false, 1.0)
	# Concrete plinth outside, wainscot inside, painted yellow kerb line on the floor.
	for s in [-1.0, 1.0]:
		A.box(self, Vector3(0.12, 1.1, 12.3), Vector3(s * 9.21, 0.55, 14.0), "concrete", Color(0.62, 0.6, 0.56), false, 1.5)
		A.box(self, Vector3(0.14, 0.12, 12.3), Vector3(s * 9.22, 1.12, 14.0), "concrete", Color(0.55, 0.53, 0.5), false, 1.0)
	A.box(self, Vector3(18.6, 1.1, 0.12), Vector3(0, 0.55, 20.21), "concrete", Color(0.62, 0.6, 0.56), false, 1.5)
	A.box(self, Vector3(17.6, 1.2, 0.08), Vector3(0, 0.6, 19.8), "concrete", Color(0.6, 0.58, 0.55), false, 1.5)
	for s in [-1, 1]:
		A.box(self, Vector3(0.08, 1.2, 11.6), Vector3(s * 8.8, 0.6, 14.2), "concrete", Color(0.6, 0.58, 0.55), false, 1.5)
		A.box(self, Vector3(0.12, 0.01, 11.0), Vector3(s * 4.0, 0.065, 14.0), "cream", Color(0.95, 0.8, 0.2), false, 1.0)
	# The roof: two pitched slopes on the trusses, a glazed lantern along the ridge, gable ends.
	var slope := atan2(HALL_RIDGE - HALL_EAVE, HALL_HALF)
	var run := Vector2(HALL_HALF, HALL_RIDGE - HALL_EAVE).length() + 0.6
	for s in [-1.0, 1.0]:
		var mid := Vector3(s * HALL_HALF / 2.0 + s * 0.3 * cos(slope), (HALL_EAVE + HALL_RIDGE) / 2.0 - 0.3 * sin(slope) + 0.1, 14.0)   # (0.6 m over the eaves)
		A.box(self, Vector3(run, 0.16, 13.0), mid, "corrugated", Color(0.55, 0.53, 0.5), true, 1.5, Vector3(0, 0, -s * slope))
		for z in [10.5, 14.0, 17.5]:   # skylights in the slopes, seen from below
			var sx: float = s * 5.0
			A.glow(self, Vector3(2.2, 0.03, 1.4), Vector3(sx, _hall_roof_y(sx) - 0.06, z), Color(1, 0.9, 0.72), 0.35).rotation.z = -s * slope
		# Gutter along the eaves, downpipes at the corners.
		A.box(self, Vector3(0.22, 0.18, 13.2), Vector3(s * (HALL_HALF + 0.75), HALL_EAVE - 0.22, 14.0), "metal", Color(0.35, 0.36, 0.35), false, 0.6)
		for z in [7.9, 20.1]:
			A.cyl(self, 0.06, HALL_EAVE - 0.3, Vector3(s * (HALL_HALF + 0.75), (HALL_EAVE - 0.3) / 2.0, z), "metal", Color(0.35, 0.36, 0.35), false)
	A.box(self, Vector3(3.4, 1.7, 11.6), Vector3(0, HALL_RIDGE + 0.25, 14.0), "corrugated", Color(0.6, 0.58, 0.55), true, 1.5)   # the lantern
	for s in [-1.0, 1.0]:
		var lg = A.box(self, Vector3(0.02, 0.7, 11.0), Vector3(s * 1.71, HALL_RIDGE + 0.5, 14.0), "metal", Color.WHITE, false)
		lg.material_override = A.glass()
		A.glow(self, Vector3(0.02, 0.66, 10.9), Vector3(s * 1.695, HALL_RIDGE + 0.5, 14.0), Color(1, 0.9, 0.72), 0.25)
		for k in 9:
			A.box(self, Vector3(0.06, 0.74, 0.08), Vector3(s * 1.73, HALL_RIDGE + 0.5, 8.6 + k * 1.35), "metal", steel, false, 0.4)
		A.box(self, Vector3(2.3, 0.1, 12.2), Vector3(s * 1.0, HALL_RIDGE + 1.22, 14.0), "corrugated", Color(0.5, 0.48, 0.45), false, 1.5, Vector3(0, 0, -s * 0.18))
	for gz in [7.85, 20.0]:   # gable ends, a louvred vent in each
		A.prism(self, Vector3(HALL_HALF * 2.0 + 0.2, HALL_RIDGE - HALL_EAVE, 0.3), Vector3(0, (HALL_EAVE + HALL_RIDGE) / 2.0, gz), "corrugated", c, Vector3.ZERO, 1.5)
		var face := -0.17 if gz < 10.0 else 0.17
		A.box(self, Vector3(1.8, 0.7, 0.04), Vector3(0, 8.85, gz + face), "grille", Color.WHITE, false, 0.3)
		A.box(self, Vector3(2.0, 0.9, 0.03), Vector3(0, 8.85, gz + face * 0.94), "metal", steel, false, 0.4)
	for p in [Vector3(-5.0, 0, 11.0), Vector3(-5.0, 0, 17.0), Vector3(5.0, 0, 14.0)]:   # rotating roof vents
		var vy := _hall_roof_y(p.x)
		A.cyl(self, 0.22, 0.5, Vector3(p.x, vy + 0.2, p.z), "metal", Color(0.55, 0.55, 0.52), false)
		A.sphere(self, 0.32, Vector3(p.x, vy + 0.62, p.z), "corrugated", Color(0.6, 0.6, 0.58), 0.0, 0.8)
	# Steel frame: I-beam columns with knee braces, pitched trusses across.
	for z in [8.2, 12.0, 16.0, 19.8]:
		for s in [-1, 1]:
			_ibeam(Vector3(s * 8.75, 0, z), 7.0)
			A.seg(self, Vector3(s * 8.75, 5.6, z), Vector3(s * 7.4, 6.95, z), 0.05, 0.05, "metal", steel)
		_hall_truss(z)
	# Bridge crane: runway beams on brackets along both walls, the yellow girder, the hoist and hook.
	for s in [-1.0, 1.0]:
		A.box(self, Vector3(0.3, 0.45, 12.0), Vector3(s * 8.3, 5.9, 14.0), "metal", steel, false, 0.6)
		A.box(self, Vector3(0.08, 0.08, 12.0), Vector3(s * 8.3, 6.16, 14.0), "metal", Color(0.6, 0.6, 0.6), false, 0.4)   # the rail
		for z in [8.2, 12.0, 16.0, 19.8]:
			A.box(self, Vector3(0.55, 0.25, 0.3), Vector3(s * 8.5, 5.6, z), "metal", steel, false, 0.4)
	var bz := 18.6
	A.box(self, Vector3(16.8, 0.6, 0.5), Vector3(0, 6.5, bz), "enamel", Color(0.85, 0.62, 0.15), false, 0.8)
	A.box(self, Vector3(16.8, 0.08, 0.52), Vector3(0, 6.18, bz), "hazard", Color.WHITE, false, 0.5)
	for s in [-1.0, 1.0]:
		A.box(self, Vector3(0.6, 0.4, 1.4), Vector3(s * 8.3, 6.4, bz), "enamel", Color(0.75, 0.55, 0.12), false, 0.6)   # end trucks
	B.label(self, "10 T", Vector3(-3.0, 6.5, bz - 0.26), 70, Color(0.15, 0.12, 0.1), "stencil", 0.008).rotation.y = PI
	A.box(self, Vector3(1.1, 0.6, 0.9), Vector3(2.5, 5.95, bz), "metal", Color(0.3, 0.3, 0.3), false, 0.5)   # the hoist
	A.cyl(self, 0.22, 0.7, Vector3(2.5, 5.95, bz), "metal", Color(0.4, 0.4, 0.38), false, "x")
	for dx in [-0.12, 0.12]:
		A.cyl(self, 0.012, 1.6, Vector3(2.5 + dx, 4.85, bz), "metal", Color(0.2, 0.2, 0.2), false)
	A.box(self, Vector3(0.35, 0.4, 0.2), Vector3(2.5, 3.95, bz), "enamel", Color(0.85, 0.62, 0.15), false, 0.4)   # hook block
	A.ring(self, 0.13, 0.08, Vector3(2.5, 3.62, bz), "metal", Color(0.3, 0.3, 0.3))
	A.seg(self, Vector3(3.0, 5.6, bz), Vector3(3.1, 1.6, bz - 0.1), 0.012, 0.012, "metal", Color(0.15, 0.15, 0.15))   # the pendant control
	A.box(self, Vector3(0.12, 0.3, 0.1), Vector3(3.1, 1.45, bz - 0.1), "plastic", Color(0.85, 0.65, 0.15), false, 0.3)
	# Front facade: header beam, hazard columns, the sign, a roller shutter rolled up under the header.
	A.box(self, Vector3(18.8, 1.4, 0.4), Vector3(0, 7.7, 7.85), "riveted", Color(0.45, 0.48, 0.45), true, 1.0)
	A.cyl(self, 0.38, 17.6, Vector3(0, 6.6, 8.35), "corrugated", Color(0.55, 0.55, 0.52), false, "x")   # the rolled shutter
	for s in [-1, 1]:
		A.box(self, Vector3(0.5, 7.0, 0.5), Vector3(s * 9.05, 3.5, 7.85), "hazard", Color.WHITE, true, 0.8)
		A.box(self, Vector3(0.12, 6.2, 0.16), Vector3(s * 8.7, 3.1, 8.2), "metal", steel, false, 0.5)   # shutter guides
	var title := B.label(self, "BUREAU OF RECLAIMED MATERIALS", Vector3(0, 7.75, 7.63), 110, Color(0.9, 0.86, 0.75), "plate")
	title.rotation.y = PI
	var sub := B.label(self, "RECLAMATION HALL 2  -  ALL SCRAP TO THE SHREDDER", Vector3(0, 7.25, 7.63), 40, Color(0.85, 0.8, 0.7), "stencil", 0.01)
	sub.rotation.y = PI
	for x in [-6.0, 6.0]:
		A.wall_lamp(self, Vector3(x, 6.6, 7.6), Vector3(0, 0, -1), Color(1, 0.8, 0.55), 1.5, false)
	# A ladder up the east wall to the roof, caged.
	var lx := 9.42
	for dz in [-0.25, 0.25]:
		A.cyl(self, 0.025, HALL_EAVE + 0.8, Vector3(lx, (HALL_EAVE + 0.8) / 2.0, 9.0 + dz), "metal", steel, false)
	for k in int((HALL_EAVE + 0.6) / 0.32):
		A.cyl(self, 0.016, 0.5, Vector3(lx, 0.4 + k * 0.32, 9.0), "metal", steel, false, "z")
	for k in 6:
		A.ring(self, 0.36, 0.33, Vector3(lx + 0.3, 2.6 + k * 0.85, 9.0), "metal", steel)
	# The lean-to annex on the east side: the hall office and compressor room.
	var ax := 10.85
	A.box(self, Vector3(3.0, 3.2, 4.6), Vector3(ax, 1.6, 17.2), "brick", Color(0.75, 0.6, 0.52), true, 1.5)
	A.box(self, Vector3(3.4, 0.14, 5.0), Vector3(ax, 3.3, 17.2), "corrugated", Color(0.5, 0.48, 0.45), true, 1.2, Vector3(0, 0, -0.12))
	A.box(self, Vector3(0.06, 2.1, 0.9), Vector3(ax + 1.52, 1.05, 16.0), "metal", Color(0.35, 0.4, 0.38), false, 0.5)   # its door
	var aw = A.box(self, Vector3(0.02, 0.8, 1.2), Vector3(ax + 1.51, 1.9, 18.2), "metal", Color.WHITE, false)
	aw.material_override = A.glass()
	A.glow(self, Vector3(0.01, 0.76, 1.16), Vector3(ax + 1.49, 1.9, 18.2), Color(1, 0.85, 0.6), 0.6)
	B.label(self, "HALL OFFICE", Vector3(ax + 1.54, 2.4, 16.0), 40, Color(0.9, 0.86, 0.75), "stencil", 0.008).rotation.y = PI / 2
	A.box(self, Vector3(0.9, 0.7, 1.2), Vector3(ax + 0.6, 3.75, 18.4), "metal", Color(0.6, 0.62, 0.6), false, 0.6)   # a unit on its roof
	A.cyl(self, 0.28, 0.06, Vector3(ax + 0.6, 4.12, 18.4), "grille", Color.WHITE, false)
	A.pipe(self, Vector3(ax - 1.4, 2.6, 15.2), Vector3(ax - 1.4, 2.6, 19.3), 0.06, "metal", Color(0.3, 0.4, 0.35))
	# Lights.
	A.hanging_lamp(self, Vector3(0, HALL_EAVE - 0.33, 12.0), Color(1, 0.8, 0.55), 1.4, 2.4, true)   # (from the trusses' bottom chords)
	for p in [Vector3(-5.5, HALL_EAVE - 0.33, 12.0), Vector3(5.5, HALL_EAVE - 0.33, 12.0), Vector3(-5.5, HALL_EAVE - 0.33, 16.0), Vector3(5.5, HALL_EAVE - 0.33, 16.0)]:
		A.hanging_lamp(self, p, Color(1, 0.8, 0.55), 1.6, 1.3, false)
	# West wall: the bonded store and a pallet rack. East: the bale bay, forklift. Back corner: the workshop.
	P.pallet_rack(self, Vector3(-7.9, 0.06, 16.1), -PI / 2, rng, 2.7)
	A.locker(self, Vector3(-8.4, 0.06, 18.9), -PI / 2)
	A.locker(self, Vector3(-8.4, 0.06, 18.25), -PI / 2)
	P.workbench(self, Vector3(-6.2, 0.06, 19.3), 0.0, rng)
	P.wall_floor_item(self, Vector3(-4.3, 0.06, 19.5), 0.0, rng)
	P.forklift(self, Vector3(6.6, 0.06, 10.6), -0.4)
	_bonded_store()
	P.bale(self, Vector3(7.6, 0.06, 15.0), 1.0, rng)
	for i in 3:
		A.barrel(self, Vector3(8.0, 0.06, 12.8 + i * 0.75), rng)
	for p in [[Vector3(-9, 0, 9.5), Vector3(1, 0, 0)], [Vector3(-9, 0, 16.8), Vector3(1, 0, 0)], [Vector3(9, 0, 13.6), Vector3(-1, 0, 0)],
			[Vector3(-2.5, 0, 20), Vector3(0, 0, -1)], [Vector3(3.8, 0, 20), Vector3(0, 0, -1)], [Vector3(9, 0, 17.0), Vector3(-1, 0, 0)]]:
		P.wall_fixture(self, p[0] + p[1] * 0.18, p[1], rng)
	P.litter(self, Vector3(0, 0.06, 14), 8.0, rng, 30)
	for i in 4:
		P.stain(self, Vector3(rng.randf_range(-7, 7), 0.06, rng.randf_range(9, 19)), rng)


## The bonded store along the hall's west wall by the door: a mesh cage of four bays, one per
## resource, where surplus banked at the shredder is kept between assignments (show_stock stacks
## the bales). Built in its own frame: front at -z, opening onto the hall.
const STORE_AT := Vector3(-7.55, 0.06, 11.9)
const STORE_BAY := 1.075
const STORE_D := 2.3
const STORE_H := 2.3
const UNITS_PER_BALE := 4
var _stock_root: Node3D


## Where bay i's middle is, across the store (steel on the left as you face it).
static func _bay_x(i: int) -> float:
	return STORE_BAY * (1.5 - i)


func _bonded_store() -> void:
	var st := Node3D.new()
	st.name = "BondedStore"
	add_child(st)
	st.position = STORE_AT
	st.rotation.y = -PI / 2   # (its front looks east, into the hall)
	var steel := Color(0.36, 0.38, 0.36)
	var mesh := Color(0.62, 0.64, 0.62)
	var hw := STORE_BAY * 2.0
	var z0 := -STORE_D / 2.0
	var z1 := STORE_D / 2.0
	var floor_text := Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.UP, PI)
	# A painted apron in front: yellow hatching, KEEP CLEAR.
	A.box(st, Vector3(hw * 2.0, 0.01, 0.4), Vector3(0, 0.007, z0 - 0.22), "hazard", Color.WHITE, false, 0.6)
	B.label(st, "BONDED STOCK  ·  KEEP CLEAR", Vector3(0, 0.014, z0 - 1.25), 28, Color(0.92, 0.88, 0.75), "stencil", 0.006).basis = floor_text
	for i in 5:   # posts at the bay lines, front and back
		var x := -hw + STORE_BAY * i
		for z in [z0, z1 - 0.05]:
			A.box(st, Vector3(0.07, STORE_H, 0.07), Vector3(x, STORE_H / 2.0, z), "metal", steel, false, 0.5)
			A.box(st, Vector3(0.16, 0.02, 0.16), Vector3(x, 0.01, z), "metal", steel.darkened(0.3), false)   # (bolted down)
		if i > 0 and i < 4:   # mesh between the bays, waist high
			A.box(st, Vector3(0.025, 1.2, STORE_D - 0.1), Vector3(x, 0.6, 0), "grate", mesh, false, 0.5)
	for z in [z0, z1 - 0.05]:   # top rails
		A.box(st, Vector3(hw * 2.0 + 0.07, 0.07, 0.07), Vector3(0, STORE_H, z), "metal", steel, false, 0.5)
	for x in [-hw, hw]:
		A.box(st, Vector3(0.07, 0.07, STORE_D), Vector3(x, STORE_H, -0.025), "metal", steel, false, 0.5)
		A.box(st, Vector3(0.025, STORE_H - 0.1, STORE_D - 0.1), Vector3(x, STORE_H / 2.0, 0), "grate", mesh, true, 0.5)   # mesh ends
	A.box(st, Vector3(hw * 2.0, STORE_H - 0.1, 0.025), Vector3(0, STORE_H / 2.0, z1 - 0.08), "grate", mesh, false, 0.5)   # back
	# The front: a mesh skirt to the knee under a yellow kick rail, a mesh fascia over the top, open
	# between (the forklift's way in).
	A.box(st, Vector3(hw * 2.0, 0.45, 0.025), Vector3(0, 0.24, z0), "grate", mesh, true, 0.5)
	A.box(st, Vector3(hw * 2.0, 0.05, 0.06), Vector3(0, 0.49, z0), "metal", Color(0.85, 0.65, 0.12), false, 0.5)
	A.box(st, Vector3(hw * 2.0, 0.35, 0.025), Vector3(0, STORE_H - 0.2, z0), "grate", mesh, false, 0.5)
	# Over each bay an enamel plate in the resource's colour; its stencil on the floor in front; a pallet floor.
	for i in 4:
		var r: String = Data.RES[i]
		var cx := _bay_x(i)
		var c: Color = Data.RES_COLOR[r]
		var plate_c := c.lerp(Color(0.85, 0.83, 0.78), 0.25) if r != "rubber" else Color(0.18, 0.18, 0.19)
		A.box(st, Vector3(0.9, 0.24, 0.03), Vector3(cx, STORE_H + 0.18, z0 - 0.04), "enamel", plate_c, false, 0.4)
		A.box(st, Vector3(0.94, 0.28, 0.02), Vector3(cx, STORE_H + 0.18, z0 - 0.015), "metal", steel.darkened(0.3), false, 0.4)
		B.label(st, r.to_upper(), Vector3(cx, STORE_H + 0.18, z0 - 0.057), 26, Color(0.95, 0.93, 0.86) if r != "plastic" else Color(0.06, 0.1, 0.16), "plate", 0.0055).rotation.y = PI
		B.label(st, Data.RES_SHORT[r], Vector3(cx, 0.014, z0 - 0.72), 44, Color(0.92, 0.88, 0.75), "stencil", 0.006).basis = floor_text
		A.box(st, Vector3(0.9, 0.12, STORE_D - 0.2), Vector3(cx, 0.06, 0), "wood", Color(0.55, 0.45, 0.35), false, 0.8)
		for k in 3:
			A.box(st, Vector3(0.9, 0.025, 0.12), Vector3(cx, 0.133, z0 + 0.2 + k * (STORE_D - 0.4) / 2.0), "wood", Color(0.6, 0.5, 0.38), false, 0.8)
	# The sign over it all on two hangers, and a caged lamp on the wall behind.
	A.box(st, Vector3(2.6, 0.42, 0.04), Vector3(0, STORE_H + 0.62, z0 - 0.03), "enamel", Color(0.16, 0.22, 0.2), false, 0.4)
	B.label(st, "B.R.M. BONDED STOCK", Vector3(0, STORE_H + 0.65, z0 - 0.055), 30, Color(0.92, 0.86, 0.68), "plate", 0.0065).rotation.y = PI
	B.label(st, "HELD FOR QUOTA  ·  NOT FOR SALE WITHOUT AUTHORITY", Vector3(0, STORE_H + 0.5, z0 - 0.055), 14, Color(0.8, 0.75, 0.6), "plate", 0.004).rotation.y = PI
	for k in [-1.0, 1.0]:
		A.seg(st, Vector3(k * 1.1, STORE_H + 0.83, z0 - 0.03), Vector3(k * 1.1, STORE_H + 0.035, z0), 0.008, 0.008, "metal", steel)
	A.box(st, Vector3(0.24, 0.3, 0.12), Vector3(0, 2.85, 1.3), "metal", Color(0.25, 0.3, 0.27), false, 0.4)
	A.sphere(st, 0.07, Vector3(0, 2.85, 1.22), "cream", Color(1, 0.85, 0.6), 3.0)
	B.omni(st, Vector3(0, 2.6, 0.6), Color(1, 0.82, 0.6), 0.9, 4.5)
	_stock_root = Node3D.new()
	_stock_root.name = "Stock"
	Merge.live(_stock_root)
	st.add_child(_stock_root)
	show_stock(main.bank if main != null else {})


## Stack the bonded stock's bales: one per few units in each resource's bay (two deep, three high),
## every bale the same each time it's stacked.
func show_stock(bank: Dictionary) -> void:
	if _stock_root == null or not is_instance_valid(_stock_root):
		return
	for c in _stock_root.get_children():
		c.queue_free()
	for i in 4:
		var r: String = Data.RES[i]
		var n := mini(ceili(bank.get(r, 0) / float(UNITS_PER_BALE)), 6)
		for k in n:   # back row first, then the front, three high
			var at := Vector3(_bay_x(i), 0.145 + (k / 2) * 0.66, STORE_D / 2.0 - 0.6 - (k % 2) * 1.0)
			_stock_bale(r, at, k)


## A bale of one resource, crushed and strapped: pressed in layers that don't quite line up,
## junk of its own kind standing out of the faces, steel bands round it both ways, a tag.
func _stock_bale(r: String, at: Vector3, k: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([r, k])
	var kinds: Array = {"steel": ["metal", "rust", "corrugated"], "copper": ["copper", "copper", "brass"],
		"rubber": ["rubber", "rubber", "plastic"], "plastic": ["plastic", "plastic", "plastic"]}[r]
	var b := Node3D.new()
	_stock_root.add_child(b)
	b.position = at
	b.rotation.y = rng.randf_range(-0.1, 0.1)
	var w := rng.randf_range(0.78, 0.86)
	for l in 4:   # the press's layers
		var kind: String = kinds[rng.randi() % kinds.size()]
		var tint := _bale_tint(r, rng)
		A.box(b, Vector3(w + rng.randf_range(-0.05, 0.03), 0.165, w + rng.randf_range(-0.05, 0.03)), Vector3(rng.randf_range(-0.025, 0.025), 0.085 + l * 0.155, rng.randf_range(-0.025, 0.025)),
			kind, tint, l == 0, 0.35, Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.06, 0.06), rng.randf_range(-0.03, 0.03)))
	for j in 14:   # what's been crushed into it, standing out of the faces
		var side := rng.randi() % 4
		var u := rng.randf_range(-0.36, 0.36)
		var face: Vector3 = [Vector3(w / 2.0, 0, u), Vector3(-w / 2.0, 0, u), Vector3(u, 0, w / 2.0), Vector3(u, 0, -w / 2.0)][side]
		face.y = rng.randf_range(0.06, 0.6)
		if rng.randf() < 0.3:
			face = Vector3(rng.randf_range(-0.35, 0.35), 0.64, rng.randf_range(-0.35, 0.35))   # (on top)
		var piece := Vector3(rng.randf_range(0.05, 0.22), rng.randf_range(0.02, 0.09), rng.randf_range(0.05, 0.2))
		if r == "copper" and rng.randf() < 0.5:   # wire ends and pipe stubs
			A.cyl(b, rng.randf_range(0.008, 0.025), rng.randf_range(0.1, 0.25), face, "copper", Color.WHITE, false, ["x", "z", "y"][rng.randi() % 3])
		elif r == "rubber" and rng.randf() < 0.4:   # a tyre's edge
			A.cyl(b, rng.randf_range(0.12, 0.2), 0.06, face, "rubber", Color(0.5, 0.5, 0.5), false, "x" if side < 2 else "z")
		else:
			A.box(b, piece, face, kinds[rng.randi() % kinds.size()], _bale_tint(r, rng), false, 0.2, Vector3(rng.randf_range(-1, 1), rng.randf(), rng.randf_range(-1, 1)))
	for y in [0.16, 0.48]:   # steel bands round it, and over it both ways
		A.box(b, Vector3(w + 0.06, 0.025, w + 0.06), Vector3(0, y, 0), "metal", Color(0.24, 0.24, 0.26), false, 0.2)
	for x in [-0.22, 0.22]:
		A.box(b, Vector3(0.025, 0.66, w + 0.06), Vector3(x, 0.32, 0), "metal", Color(0.24, 0.24, 0.26), false, 0.2)
		A.box(b, Vector3(0.025, 0.012, w + 0.06), Vector3(x, 0.655, 0), "metal", Color(0.24, 0.24, 0.26), false, 0.2)
	A.box(b, Vector3(0.11, 0.14, 0.004), Vector3(0.05, 0.36, -w / 2.0 - 0.04), "paper", Color(0.95, 0.9, 0.7), false, 0.3, Vector3(0, 0, rng.randf_range(-0.2, 0.2)))   # the tag
	A.seg(b, Vector3(0.05, 0.43, -w / 2.0 - 0.04), Vector3(-0.22, 0.48, -w / 2.0 - 0.035), 0.003, 0.003, "metal", Color(0.4, 0.4, 0.4))


static func _bale_tint(r: String, rng: RandomNumberGenerator) -> Color:
	match r:
		"steel": return Color(0.7, 0.7, 0.68).darkened(rng.randf_range(0.0, 0.3))
		"copper": return Color.WHITE.darkened(rng.randf_range(0.0, 0.3))
		"rubber": return Color(0.45, 0.45, 0.45).darkened(rng.randf_range(0.0, 0.4))
	return Color.from_hsv(rng.randf(), rng.randf_range(0.35, 0.65), rng.randf_range(0.6, 0.9))


## A pitched roof truss across the hall at z: a bottom chord at the eaves, rafters up to the ridge,
## a king post and diagonals between.
func _hall_truss(z: float) -> void:
	var steel := Color(0.42, 0.4, 0.38)
	A.box(self, Vector3(HALL_HALF * 2.0 - 0.4, 0.16, 0.14), Vector3(0, HALL_EAVE - 0.25, z), "metal", steel, false, 0.6)
	for s in [-1.0, 1.0]:
		A.seg(self, Vector3(s * (HALL_HALF - 0.2), HALL_EAVE - 0.2, z), Vector3(0, HALL_RIDGE - 0.15, z), 0.08, 0.08, "metal", steel)
		for k in 4:
			var x0: float = s * (HALL_HALF - 0.2) * (1.0 - k / 4.0)
			var x1: float = s * (HALL_HALF - 0.2) * (1.0 - (k + 1) / 4.0)
			A.seg(self, Vector3(x0, HALL_EAVE - 0.25, z), Vector3(x1, _hall_roof_y(x1) - 0.18, z), 0.035, 0.035, "metal", steel)
			A.seg(self, Vector3(x1, HALL_EAVE - 0.25, z), Vector3(x1, _hall_roof_y(x1) - 0.18, z), 0.035, 0.035, "metal", steel)
func _ibeam(at: Vector3, h: float) -> void:
	var steel := Color(0.4, 0.42, 0.4)
	A.box(self, Vector3(0.3, h, 0.04), at + Vector3(0, h / 2, -0.13), "metal", steel, false, 0.8)
	A.box(self, Vector3(0.3, h, 0.04), at + Vector3(0, h / 2, 0.13), "metal", steel, false, 0.8)
	A.box(self, Vector3(0.04, h, 0.26), at + Vector3(0, h / 2, 0), "metal", steel, false, 0.8)
	A.box(self, Vector3(0.45, 0.06, 0.45), at + Vector3(0, 0.09, 0), "metal", steel.darkened(0.3), false)


## LIFT_MOTOR: the Bureau's winch truck, parked by the headframe with its cable up to the sheave.
## A six-wheeled flatbed: a cab with a sun visor and mirrors, a big cable drum on the bed driven by
## a diesel pack, outriggers down, a beacon, and the cable running up over the sheave.
func _winch_truck() -> void:
	var t := Node3D.new()
	t.name = "WinchTruck"
	add_child(t)
	# Parked off the path from the station: of three sides of the lift pad, the one facing away.
	var to_station := (Vector3(0, 0, 20.5) - elevator_pos).normalized()
	var side := Vector3(1, 0, 0)
	for d in [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		if d.dot(to_station) < side.dot(to_station):
			side = d
	t.position = elevator_pos + side * 10.5
	t.rotation.y = atan2(side.z, -side.x)   # (tail and boom towards the lift, nose away)
	var out: Vector3 = WinchTruck.build(t)
	# The cable: from the boom's sheave up to the headframe's.
	var from := t.to_global(out)
	var sheave: Vector3 = elevator.to_global(Vector3(Elevator.SHEAVE_R * 2.0, Elevator.SHEAVE_Y, 0))
	A.seg(self, to_local(from), to_local(sheave), 0.022, 0.022, "metal", Color(0.3, 0.3, 0.3))


## The shredder (shredder.gd builds it into this level and runs it).
func _shredder() -> void:
	hopper = AABB(Vector3(-1.5, -0.2, 11.5), Vector3(3, 3, 3))
	shredder = Shredder.new()
	add_child(shredder)
	shredder.build(self)
	board = shredder.board


## A square funnel (an open frustum, both faces drawn): `bottom` half-size at `at`, opening out to
## `top` half-size `h` higher.
func _funnel(at: Vector3, bottom: Vector2, top: Vector2, h: float, kind: String, tint: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := [Vector3(-bottom.x, 0, -bottom.y), Vector3(bottom.x, 0, -bottom.y), Vector3(bottom.x, 0, bottom.y), Vector3(-bottom.x, 0, bottom.y)]
	var t := [Vector3(-top.x, h, -top.y), Vector3(top.x, h, -top.y), Vector3(top.x, h, top.y), Vector3(-top.x, h, top.y)]
	for i in 4:
		var j := (i + 1) % 4
		var quad := [b[i], b[j], t[j], t[i]]
		for tri in [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]]:   # both faces: seen from inside and out
			var v0: Vector3 = quad[tri[0]]
			st.set_normal(-(quad[tri[1]] - v0).cross(quad[tri[2]] - v0).normalized())   # (clockwise is the front)
			for k in tri:
				st.add_vertex(quad[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = A.mat(kind, tint, 0.8)
	add_child(mi)
	mi.position = at


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
	var crane := P.gantry_crane(self, Vector3(20, 0.06, 20), 0.15, 18.0, 9.0, false)
	for i in 10:
		P.bale(self, Vector3(13.0 + (i % 5) * 1.2, 0.06 + (i / 5) * 0.95, 11.0), 1.1, rng)
	P.forklift(self, Vector3(16.0, 0.06, 13.5), PI + 0.3)
	# Fuel tanks behind the hall.
	P.fuel_tank(self, Vector3(-4.0, 0.06, 26.0), 0.0)
	P.fuel_tank(self, Vector3(4.0, 0.06, 26.5), 0.05, Color(0.75, 0.3, 0.2))
	P.water_tower(self, Vector3(-16.0, 0.06, 32.0))
	# Gatehouse and the fence round the back.
	P.guard_booth(self, Vector3(20.0, 0.06, 5.0), -PI / 2, rng)
	var life = load("res://src/yard_life.gd").new()   # (the clerk, the crane at work, trains going by)
	life.main = main
	life.crane = crane
	add_child(life)
	for seg in [[Vector3(-40, 0, 36), Vector3(-8, 0, 36)], [Vector3(8, 0, 36), Vector3(40, 0, 36)]]:   # (the yard's own fence, a gap for the road)
		P.fence(self, seg[0], seg[1], rng)
	# Floodlights over the yard, aimed in.
	P.floodlight_tower(self, Vector3(-11.0, 0.06, 24.0), PI * 0.85)
	P.floodlight_tower(self, Vector3(12.0, 0.06, 32.0), -PI * 0.8)
	P.floodlight_tower(self, Vector3(-30.0, 0.06, -12.0), PI * 0.25, 11.0, false)
	# Across the tracks: old wagons on the siding, more containers, poles along the line.
	P.boxcar(self, Vector3(-12.0, 0.15, -9.0), 0.0, rng)   # (on the rail heads)
	P.boxcar(self, Vector3(1.0, 0.15, -9.0), 0.02, rng)
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
	Sfx.play(self, "bulkhead", Vector3(24, 2, 0), 0.0, 0.7)   # (a bigger door: the same rack, slower and lower)
	Sfx.play(self, "clang_big", Vector3(24, 4, 0), 4.0)
