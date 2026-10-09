# Shop items, upgrades, the charging rack, creature drops and weapon hit boxes, at a real station.
# Run: tests/run.sh 150 --headless --path . -s tests/kit.gd
extends SceneTree

var fails := 0
var main


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


func secs(t: float) -> void:
	await create_timer(t).timeout


func hold(id: String, charge := -1.0) -> void:
	var c: float = charge if charge >= 0.0 else float(load("res://src/data.gd").ITEMS[id].get("charge", -1.0))
	main.player.slots[0] = {"id": id, "charge": c, "extra": {}}
	main.player.sel = 0


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	var lvl = main.level
	var fac = lvl.facility
	lvl.hazards.events.clear()
	for n in lvl.get_children():
		if n.is_in_group("monsters"):
			n.free()
	var p = main.player
	var medkits: Array = main.get_tree().get_nodes_in_group("pickups").filter(func(x): return x.id == "MEDKIT")
	check(medkits.size() >= 1, "medkits lie about the facility (%d)" % medkits.size())
	# A room to try things in.
	var room: Vector3 = fac.to_global(Vector3.ZERO)
	for c in fac.layout.cells:
		if fac.kinds[c] in ["storage", "office", "machine", "break", "lab", "empty"] and not fac.group_of.has(c):
			room = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
			break
	p.global_position = room + Vector3(0, 0.2, 0)
	p.velocity = Vector3.ZERO
	await secs(0.3)
	# Medkit.
	p.hp = 30.0
	hold("MEDKIT")
	p._use()
	check(p.hp == 100.0 and p.slots[0] == null, "a medkit patches you up to 100 and is used up")
	# Adrenaline.
	hold("ADRENALINE")
	p._use()
	check(p._stim > 19.0 and p.slots[0] == null, "an adrenaline shot takes")
	# Flare: thrown, it burns, and something that hears comes to it.
	var pu = load("res://src/pulsator.gd").new()
	pu.main = main
	pu.level = lvl
	lvl.add_child(pu)
	pu.global_position = room + Vector3(4, 0.1, 4)
	pu.set_physics_process(false)
	hold("FLARE")
	p._use()
	await secs(0.5)
	var flares: Array = main.get_tree().get_nodes_in_group("pickups").filter(func(x): return x.id == "FLARE" and x._active)
	check(flares.size() == 1 and flares[0]._glow != null and flares[0]._glow.visible, "a thrown flare burns")
	await secs(2.2)
	check(pu.chasing, "...and its hiss is heard")
	pu.free()
	# Noisemaker.
	var pu2 = load("res://src/pulsator.gd").new()
	pu2.main = main
	pu2.level = lvl
	lvl.add_child(pu2)
	pu2.global_position = room + Vector3(3.0, 0.1, -1.0)
	pu2.set_physics_process(false)
	hold("NOISEMAKER")
	p.global_position = room + Vector3(0, 0.2, -3)
	p._use()
	await secs(1.5)
	await secs(2.6)
	check(pu2.chasing and pu2.target.distance_to(p.global_position) > 1.5, "...then rings, and the creature goes to it, not to you")
	pu2.free()
	# Charging rack: flashlight, shells, the helmet cell.
	main.upgrades["HEADLAMP"] = true
	p.slots[1] = {"id": "FLASHLIGHT", "charge": 3.0, "extra": {}}
	p.slots[2] = {"id": "SHOTGUN", "charge": 1.0, "extra": {}}
	p.helmet_charge = 10.0
	p.recharge()
	check(p.slots[1].charge == main.charge_max("FLASHLIGHT") and p.slots[2].charge == 6.0 and p.helmet_charge == p.helmet_max(), "the charging rack tops up batteries, shells and the helmet cell")
	p.slots[1] = null
	p.slots[2] = null
	p.slots[0] = null
	var before: float = p.helmet_charge
	p._toggle_headlamp()
	await secs(1.0)
	check(p.headlamp.visible and p.helmet_charge < before, "the headlamp lights and runs the cell down")
	p._toggle_headlamp()
	# Upgrades.
	p.hp = 100.0
	p.hurt(40.0, "test")
	var plain: float = 100.0 - p.hp
	p.hp = 100.0
	main.upgrades["ARMORED_SUIT"] = true
	p.since_hurt = 99.0
	p.hurt(40.0, "test")
	check(absf((100.0 - p.hp) - plain * 0.75) < 0.01, "the armored suit takes a quarter off (%.0f -> %.0f)" % [plain, 100.0 - p.hp])
	p.hp = 100.0
	check(p.max_slots() == 5, "five hand slots")
	main.upgrades["CARGO_HARNESS"] = true
	check(p.max_slots() == 6, "...six with the cargo harness")
	main.upgrades["GAS_FILTER"] = true
	check(lvl.hazards.has_mask(p), "the gas filter counts as a mask")
	check(main.depart_hour() == 24.0, "the train leaves at midnight")
	main.upgrades["OVERTIME_PERMIT"] = true
	check(main.depart_hour() == 25.0, "...at 01:00 with the overtime permit")
	# Drops and hit boxes.
	var w = load("res://src/warden.gd").new()
	w.main = main
	w.level = lvl
	lvl.add_child(w)
	w.global_position = room + Vector3(0, 0.1, -6)
	w.set_physics_process(false)
	await secs(0.2)
	check(w.hitbox != null, "a creature gets a hit box round its model")
	var n0: int = main.get_tree().get_nodes_in_group("pickups").filter(func(x): return x.id == "WARDEN_LENS").size()
	w.take_hit(9999.0, w.global_position + Vector3(1, 1, 0), p)
	await secs(0.5)
	var n1: int = main.get_tree().get_nodes_in_group("pickups").filter(func(x): return x.id == "WARDEN_LENS").size()
	check(n1 == n0 + 1, "a dead warden leaves its searchlight lens")
	var pu3 = load("res://src/pulsator.gd").new()
	pu3.main = main
	pu3.level = lvl
	lvl.add_child(pu3)
	pu3.global_position = room + Vector3(0, 0.1, 5)
	pu3.set_physics_process(false)
	await secs(0.2)
	var space = p.get_world_3d().direct_space_state
	var from: Vector3 = room + Vector3(0, 1.4, 0)   # level with the top of its sac, above its walking capsule
	var q := PhysicsRayQueryParameters3D.create(from, room + Vector3(0, 1.4, 5), 1 | 8 | 64)
	var hit: Dictionary = space.intersect_ray(q)
	check(not hit.is_empty() and hit.collider.get_meta("monster", hit.collider) == pu3, "a shot at the top of a pulsator's body hits it")
	# Door wedge: jams a swing door; a creature can't shove it, bashes it until it gives; pull it out.
	var doors: Array = fac.get_children().filter(func(d): return d.has_method("set_wedged"))
	if not doors.is_empty():
		var door = doors[0]
		if door.open:
			door.set_open(false)
		main.wedge_door(door)
		check(door.wedged and not door.open, "a wedge jams a swing door shut")
		var c: Vector3 = (door._panels[0].global_position + door._panels[1].global_position) / 2.0
		var brute = load("res://src/statue.gd").new()
		brute.main = main
		brute.level = lvl
		lvl.add_child(brute)
		brute.set_physics_process(false)
		brute.global_position = Vector3(c.x, door.global_position.y + 0.05, c.z) + door.global_basis.z * 0.8   # (on the door's own floor)
		await secs(2.0)
		check(not door.open and door.wedged, "...a creature at it can't shove it open")
		await secs(9.5)
		check(door.open and not door.wedged, "...but it bashes until the wedge gives")
		brute.free()
		door.set_open(false)
		main.wedge_door(door)
		p.slots[0] = null
		p.sel = 0
		load("res://src/interact.gd").who_now = p
		door.toggle()
		load("res://src/interact.gd").who_now = null
		check(not door.wedged and p.slots.any(func(it): return it != null and it.id == "DOOR_WEDGE"), "...and E pulls a wedge back out into your hands")
	print("kit.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
