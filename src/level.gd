# One stop on the route: either a station (surface + elevator + facility) or the checkpoint.
# The train is NOT part of this — it persists while levels are swapped around it.
extends Node3D

const Data = preload("res://src/data.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const Facility = preload("res://src/facility.gd")
const Roomba = preload("res://src/roomba.gd")
const Pulsator = preload("res://src/pulsator.gd")

const FAC_Y := -60.0
const BOOTH_OFFSET := Vector3(-1.7, -0.5, -1.8)
const BOOTH_SIZE := Vector3(3.4, 3.6, 3.6)

var main
var info := {}
var assignment := 1
var rng := RandomNumberGenerator.new()
var facility
var booths: Array[Vector3] = []   # [surface, facility] elevator booth origins
var hopper := AABB()
var board: Label3D
var gate: Node3D
var gate_light: OmniLight3D
var elevator_pos := Vector3(0, 0, 999)
var riding := false
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
	facility.position = Vector3(0, FAC_Y, 0)
	facility.build(seed, stop.rooms, stop.theme)
	_booth(facility.global_position, 1)
	var total: int = stop.rooms + 6 + assignment * 2
	for i in int(total * 0.66):
		main.spawn_item(Data.random_scrap(rng), facility.random_point(rng), -1.0, self)
	for i in int(total * 0.34):
		main.spawn_item(Data.random_scrap(rng), _surface_point() + Vector3(0, 0.6, 0), -1.0, self)
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
	for i in 50:
		var p := Vector3(rng.randf_range(-80, 80), 0, rng.randf_range(-80, 80))
		if absf(p.z) > 6.0 and p.distance_to(elevator_pos) > 9.0:
			return p
	return Vector3(0, 0, 20)


# --- surface -----------------------------------------------------------------

func _surface(arctic: bool) -> void:
	var ground := Color(0.86, 0.88, 0.92) if arctic else Color(0.72, 0.58, 0.4)
	var rock := Color(0.55, 0.6, 0.68) if arctic else Color(0.48, 0.38, 0.3)
	B.box(self, Vector3(200, 1, 200), Vector3(0, -0.5, 0), ground)
	_rails()
	_bounds()
	elevator_pos = Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(38, 65))
	_building(elevator_pos)
	_booth(elevator_pos, 0)
	var start := Vector3(0, 0, 4)
	var n := int(start.distance_to(elevator_pos) / 14.0)
	for i in range(1, n + 1):
		var sp := start.lerp(elevator_pos, float(i) / (n + 1)) + Vector3(1.5, 0, 0)
		B.box(self, Vector3(0.12, 2.2, 0.12), sp + Vector3(0, 1.1, 0), Color(0.3, 0.3, 0.3))
		B.label(self, "ELEVATOR\n%d m" % int(sp.distance_to(elevator_pos)), sp + Vector3(0, 2.6, 0), 48, Color(1, 0.85, 0.2))
	for i in rng.randi_range(3, 6):
		_shack(_surface_point())
	for i in rng.randi_range(14, 24):
		var s := rng.randf_range(0.8, 3.5)
		var p := _surface_point()
		B.box(self, Vector3(s, s * rng.randf_range(0.4, 1.0), s * rng.randf_range(0.7, 1.3)), p + Vector3(0, s * 0.3, 0), rock.darkened(rng.randf() * 0.3))


func _rails() -> void:
	# Rails stop at the train's ends so they don't poke through its floor.
	for z in [-0.75, 0.75]:
		for x in [-54.0, 54.0]:
			B.box(self, Vector3(91.6, 0.1, 0.1), Vector3(x, 0.05, z), Color(0.3, 0.28, 0.26), false)


func _bounds() -> void:
	for s in [-1, 1]:
		B.invisible_wall(self, Vector3(200, 30, 1), Vector3(0, 15, 95 * s))
		B.invisible_wall(self, Vector3(1, 30, 200), Vector3(95 * s, 15, 0))


func _building(p: Vector3) -> void:
	var c := Color(0.42, 0.4, 0.37)
	B.box(self, Vector3(10, 5, 0.3), p + Vector3(0, 2.5, 5), c)
	B.box(self, Vector3(0.3, 5, 10), p + Vector3(-5, 2.5, 0), c)
	B.box(self, Vector3(0.3, 5, 10), p + Vector3(5, 2.5, 0), c)
	for s in [-1, 1]:
		B.box(self, Vector3(3.5, 5, 0.3), p + Vector3(3.25 * s, 2.5, -5), c)
	B.box(self, Vector3(3, 2, 0.3), p + Vector3(0, 4, -5), c)
	B.box(self, Vector3(10.4, 0.3, 10.4), p + Vector3(0, 5.15, 0), c.darkened(0.3))
	var door_sign := B.label(self, "ELEVATOR", p + Vector3(0, 5.9, -5.3), 80, Color(1, 0.85, 0.2), false)
	door_sign.rotation.y = PI
	B.omni(self, p + Vector3(0, 4.5, -3), Color(1, 0.8, 0.5), 0.8, 8.0)


func _shack(p: Vector3) -> void:
	var c := Color(0.4, 0.33, 0.27)
	B.box(self, Vector3(4, 3, 0.2), p + Vector3(0, 1.5, 2), c)
	B.box(self, Vector3(0.2, 3, 4), p + Vector3(-2, 1.5, 0), c)
	B.box(self, Vector3(0.2, 3, 4), p + Vector3(2, 1.5, 0), c)
	if rng.randf() < 0.6:
		B.box(self, Vector3(4.4, 0.15, 4.4), p + Vector3(0, 3.05, 0), c.darkened(0.3))


# --- elevator ---------------------------------------------------------------

func _booth(o: Vector3, idx: int) -> void:
	var c := Color(0.32, 0.33, 0.35)
	B.box(self, Vector3(3.6, 3.2, 0.2), o + Vector3(0, 1.6, 1.8), c)
	B.box(self, Vector3(0.2, 3.2, 3.6), o + Vector3(-1.8, 1.6, 0), c)
	B.box(self, Vector3(0.2, 3.2, 3.6), o + Vector3(1.8, 1.6, 0), c)
	B.box(self, Vector3(3.6, 0.2, 3.6), o + Vector3(0, 3.3, 0), c)
	for y in [0.9, 1.7]:
		B.box(self, Vector3(0.5, 0.06, 3.0), o + Vector3(-1.45, y, 0), Color(0.5, 0.5, 0.5))
	B.interactable(self, Vector3(0.15, 0.3, 0.15), o + Vector3(1.6, 1.3, 1.2), Color(1, 0.8, 0.1),
		"Ride elevator %s" % ("DOWN" if idx == 0 else "UP"), ride.bind(idx), 0.0, 1.5)
	B.omni(self, o + Vector3(0, 2.9, 0), Color(1, 0.9, 0.7), 0.7, 4.5)
	var stash := B.label(self, "STASH SHELF", o + Vector3(-1.7, 2.2, 0), 32, Color(0.8, 0.8, 0.8), false)
	stash.rotation.y = PI / 2
	booths.append(o)


## Moves everyone and everything standing in booth idx to the other booth.
func ride(idx: int) -> void:
	if riding or booths.size() < 2:
		return
	riding = true
	var off := booths[1 - idx] - booths[idx]
	var box := AABB(booths[idx] + BOOTH_OFFSET, BOOTH_SIZE)
	Sfx.play(self, "ding", booths[idx] + Vector3.UP)
	await main.hud.fade(1.0, 0.5)
	for n in get_tree().get_nodes_in_group("movable"):
		if box.has_point(n.global_position):
			n.global_position += off
	await get_tree().create_timer(1.2).timeout
	Sfx.play(self, "ding", booths[1 - idx] + Vector3.UP)
	await main.hud.fade(0.0, 0.5)
	riding = false


# --- checkpoint ---------------------------------------------------------------

func _checkpoint() -> void:
	B.box(self, Vector3(200, 1, 200), Vector3(0, -0.5, 0), Color(0.34, 0.34, 0.36))
	_rails()
	_bounds()
	var c := Color(0.5, 0.48, 0.45)
	B.box(self, Vector3(14, 6, 0.3), Vector3(0, 3, 19), c)
	B.box(self, Vector3(0.3, 6, 11), Vector3(-7, 3, 13.5), c)
	B.box(self, Vector3(0.3, 6, 11), Vector3(7, 3, 13.5), c)
	B.box(self, Vector3(14.4, 0.3, 11.4), Vector3(0, 6.15, 13.5), c.darkened(0.3))
	B.omni(self, Vector3(0, 5, 13), Color(1, 0.85, 0.6), 1.2, 14.0)
	B.label(self, "BUREAU OF RECLAIMED MATERIALS\nCHECKPOINT", Vector3(0, 7.5, 8), 96, Color(0.9, 0.9, 0.9))
	# Shredder hopper: drop/throw scrap over the rim, then pull the lever.
	hopper = AABB(Vector3(-1.5, -0.2, 11.5), Vector3(3, 3, 3))
	var rim := Color(0.55, 0.12, 0.1)
	B.box(self, Vector3(3.4, 0.9, 0.2), Vector3(0, 0.45, 11.4), rim)
	B.box(self, Vector3(3.4, 0.9, 0.2), Vector3(0, 0.45, 14.6), rim)
	B.box(self, Vector3(0.2, 0.9, 3.4), Vector3(-1.6, 0.45, 13), rim)
	B.box(self, Vector3(0.2, 0.9, 3.4), Vector3(1.6, 0.45, 13), rim)
	B.box(self, Vector3(3, 0.04, 3), Vector3(0, 0.03, 13), Color(0.05, 0.05, 0.05), false)
	var shred_sign := B.label(self, "SHREDDER", Vector3(0, 1.2, 11.3), 48, Color(1, 0.4, 0.3), false)
	shred_sign.rotation.y = PI
	B.interactable(self, Vector3(0.15, 0.8, 0.15), Vector3(2.3, 0.9, 11.8), Color(0.9, 0.1, 0.1),
		"Pull lever: shred & submit", main.shred, 0.0, 0.5)
	board = B.label(self, "", Vector3(0, 3.6, 15), 56, Color(1, 0.8, 0.3))
	gate = Node3D.new()
	add_child(gate)
	B.box(gate, Vector3(0.6, 5, 9), Vector3(24, 2.5, 0), Color(0.45, 0.1, 0.08))
	gate_light = B.omni(gate, Vector3(23, 5.5, 0), Color(1, 0.1, 0.05), 3.0, 10.0)


func open_gate() -> void:
	if gate == null or gate_light.light_color.g > 0.5:
		return
	gate_light.light_color = Color(0.1, 1, 0.2)
	create_tween().tween_property(gate, "position:y", 5.5, 2.0)
	Sfx.play(self, "door", Vector3(24, 2, 0), 6.0)
