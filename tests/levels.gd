# Two-level rooms: pits (catwalks above, stairs down) and mezzanines (deck above, stairs up).
# A walker using the monsters' pathing must climb out of a pit to the next room, and get up onto a deck.
# Run: godot --headless --path . -s tests/levels.gd
extends SceneTree

var fails := 0
var main


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run()


## Walks like a monster (monster.gd walk_to) until it gets within `near` of `goal` or time runs out.
func walk(fac, start: Vector3, goal: Vector3, secs: float) -> Dictionary:
	var w = load("res://src/monster.gd").new()   # a bare monster: the shared walking and pathing, nothing else
	w.main = main
	w.level = main.level
	w._setup_body(0.3, 1.4)
	main.level.add_child(w)
	w.global_position = start
	var t := 0.0
	var best := INF
	var step := 0
	var trail := []
	while t < secs:
		step += 1
		if step % 6 == 0:
			await physics_frame   # six walker steps per real frame: same physics, a lot less waiting
		var dt := 1.0 / 60.0
		t += dt
		w.walk_to(goal, 4.0, dt)
		if step % 30 == 0:
			var nx: Vector3 = w._route[0] if not w._route.is_empty() else main.level.next_point(w.global_position, goal)
			trail.append("%s r%d n%d->%s" % [fac.to_local(w.global_position).snapped(Vector3.ONE * 0.1), w._route.size(), fac._node(w.global_position), fac.to_local(nx).snapped(Vector3.ONE * 0.1)])
		var d: float = w.global_position.distance_to(goal)
		best = minf(best, d)
		if d < 1.0:
			break
	var end: Vector3 = w.global_position
	if best > 1.0:
		var hits := []
		for i in w.get_slide_collision_count():
			var col: KinematicCollision3D = w.get_slide_collision(i)
			var cn: Node = col.get_collider()
			var sz = ""
			for ch in cn.get_children():
				if ch is CollisionShape3D and ch.shape is BoxShape3D:
					sz = str(ch.shape.size)
			hits.append("%s/%s %s at %s n=%s" % [cn.get_parent().name, cn.name, sz, fac.to_local(col.get_position()).snapped(Vector3.ONE * 0.01), col.get_normal().snapped(Vector3.ONE * 0.01)])
		print("   path: ", Array(fac.astar.get_id_path(fac._node(start), fac._node(goal))).map(func(i): return "%s%s" % [fac.cell_of_id[i], "v" if fac.layer_of_id[i] == 1 else ""]))
		print("   trail:\n      ", "\n      ".join(trail.slice(-40)))
		var nxt: Vector3 = main.level.next_point(end, goal)
		print("   stuck at %s next %s (%s, node %d -> %d) hits %s" % [fac.to_local(end).snapped(Vector3.ONE * 0.01), fac.to_local(nxt).snapped(Vector3.ONE * 0.01), "-", fac._node(end), fac._node(goal), hits])
	w.queue_free()
	return {"end": end, "best": best, "t": t}


## The lower floor exists, every room on it is reachable, and a walker gets from upstairs into a
## basement room through the way down, and back up to the lift.
func lower_floor(fac, theme: String) -> void:
	for code in fac.doors:
		fac.set_door(code, true)
	for d in fac.get_children():
		if d.has_method("set_open"):
			d.set_open(true)
	var rooms: Array = fac.lower.keys().filter(func(c): return not fac.low_kinds[c] in ["pit", "stairwell"])
	check(rooms.size() >= 3, "%s: a lower floor with %d rooms" % [theme, rooms.size()])
	if rooms.is_empty():
		return
	var lift: int = fac.ids[Vector2i.ZERO]
	var all_reach: bool = rooms.all(func(c): return fac.astar.get_id_path(lift, fac.low_ids[c]).size() > 0)
	check(all_reach, "%s: every lower room is reachable from the lift" % theme)
	# The farthest basement room from the lift, by route.
	rooms.sort_custom(func(x, y): return fac.astar.get_id_path(lift, fac.low_ids[x]).size() > fac.astar.get_id_path(lift, fac.low_ids[y]).size())
	var target: Vector2i = rooms[0]
	var goal: Vector3 = fac.to_global(Vector3(target.x * 12.0, -Facility_PIT + 0.1, target.y * 12.0))
	var start: Vector3 = fac.to_global(Vector3(0, 0.1, 4.5))   # lift room, off the shaft
	var r: Dictionary = await walk(fac, start, goal, 60.0)
	check(r.best < 1.5, "%s: from the lift down to the farthest basement room %s (closest %.1f m)" % [theme, target, r.best])
	r = await walk(fac, goal, start, 60.0)
	check(r.best < 1.5, "%s: and back up to the lift (closest %.1f m)" % [theme, r.best])


const Facility_PIT := 3.0


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "FACTORY"
	stop.rooms = 26
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	var fac = main.level.facility
	var tries := 0
	while tries < 12 and not (fac.kinds.values().has("pit") and fac.kinds.values().has("atrium")):
		tries += 1   # reroll until this layout has both kinds of two-level room
		main.level.queue_free()
		main.level = null
		await process_frame
		main._load_level(stop)
		await frames(2)
		fac = main.level.facility
	main.level.hazards.set_physics_process(false)
	for code in fac.doors:   # bulkheads and doors open: this is about stairs, not doors
		fac.set_door(code, true)
	for d in fac.get_children():
		if d.has_method("set_open"):
			d.set_open(true)
	for m in main.get_tree().get_nodes_in_group("monsters"):
		m.process_mode = Node.PROCESS_MODE_DISABLED
	main.player.global_position = main.level.elevator_pos + Vector3(0, 0.5, -6)   # out of the way (on the surface: watches nothing below)
	await frames(5)
	var done := {}
	for c in fac.layout.cells:
		var kind: String = fac.kinds[c]
		if not kind in ["pit", "atrium"]:
			continue
		if kind == "atrium" and not fac.stairs.has(c):
			continue   # no free wall for a deck: it was furnished as a storeroom instead
		check(fac.stairs.has(c), "%s room %s records its stairs" % [kind, c])
		var s: Dictionary = fac.stairs[c]
		var o: Vector3 = Vector3(c.x * 12.0, 0, c.y * 12.0)
		# The stairs end on open floor: nothing solid just past the bottom step.
		var low: Vector3 = fac.to_global(s.low)
		var q := PhysicsRayQueryParameters3D.create(low + Vector3(0, 0.3, 0), low + Vector3(0, -1.0, 0), 1)
		check(not main.get_world_3d().direct_space_state.intersect_ray(q).is_empty(), "%s %s: floor under the foot of the stairs" % [kind, c])
		var n: Vector2i = fac.layout.links[c][0]
		done[kind] = done.get(kind, 0) + 1
		if done[kind] > 3:
			continue
		if kind == "pit":
			var top: Vector3 = fac.to_global(o + Vector3(0.6, 0.1, -0.6))   # on the middle platform
			var bottom: Vector3 = Vector3.INF
			for corner in [Vector3(-3.6, 0, -3.6), Vector3(3.6, 0, 3.6), Vector3(-3.6, 0, 3.6), Vector3(3.6, 0, -3.6), Vector3(0, 0, 3.8), Vector3(-3.8, 0, 0)]:
				var cl: Vector3 = o + corner + Vector3(0, -2.9, 0)
				if fac.crates.all(func(b): return not b.grow(0.5).has_point(Vector3(cl.x, b.position.y + 0.1, cl.z))):
					bottom = fac.to_global(cl)
					break
			if bottom == Vector3.INF:
				continue
			var r: Dictionary = await walk(fac, bottom, top, 30.0)
			check(r.best < 1.0, "pit %s: climbs the stairs out of the pit onto the platform (closest %.1f m)" % [c, r.best])
			r = await walk(fac, top, bottom, 30.0)
			check(r.best < 1.0, "pit %s: and back down to the bottom (closest %.1f m)" % [c, r.best])
			var door: Vector3 = fac.to_global(Vector3((c.x + n.x) * 6.0, 0.1, (c.y + n.y) * 6.0))
			r = await walk(fac, top, door, 20.0)
			check(r.best < 1.0, "pit %s: along the catwalk to the doorway (closest %.1f m)" % [c, r.best])
		else:
			var deck: Vector3 = fac.to_global(fac.loot_spots.filter(func(p): return fac.cell_at(fac.to_global(p)) == c)[0])
			var floor_pt: Vector3 = fac.to_global(s.low) + (fac.to_global(s.low) - fac.to_global(s.high)).normalized() * Vector3(1, 0, 1) * 1.5 - Vector3(0, 0.4, 0)
			var r: Dictionary = await walk(fac, floor_pt, deck, 30.0)
			check(r.best < 1.2, "mezzanine %s: gets up the stairs onto the deck (closest %.1f m)" % [c, r.best])
			r = await walk(fac, deck, floor_pt, 30.0)
			check(r.best < 1.0, "mezzanine %s: and back down (closest %.1f m)" % [c, r.best])
	await lower_floor(fac, "FACTORY")
	# A lab: no pits there, so it gets a stairwell down instead.
	stop.theme = "LAB"
	for t in 6:
		main.level.queue_free()
		main.level = null
		await process_frame
		main._load_level(stop)
		await frames(2)
		fac = main.level.facility
		if fac.kinds.values().has("stairwell"):
			break
	main.level.hazards.set_physics_process(false)
	for m in main.get_tree().get_nodes_in_group("monsters"):
		m.process_mode = Node.PROCESS_MODE_DISABLED
	check(fac.kinds.values().has("stairwell"), "a lab gets a stairwell down to the lower floor")
	await lower_floor(fac, "LAB")
	var unstuck: int = load("res://src/monster.gd").unstuck_count
	print("   unstuck failsafe fired %d times" % unstuck)
	for l in load("res://src/monster.gd").unstuck_log:
		print("     unstuck: ", l)
	check(unstuck <= 6, "walkers rarely need the unstuck failsafe (%d)" % unstuck)
	print("levels.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
