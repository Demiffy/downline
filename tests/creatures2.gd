# The siren and the husk, in a real facility.
# Run: tests/run.sh 200 --headless --path . -s tests/creatures2.gd
extends SceneTree

var fails := 0
var main
var lvl
var fac


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


func secs(t: float) -> void:
	await create_timer(t).timeout


func wait_until(cond: Callable, t := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


## A spot `dist` from `from` on open floor with a clear line of sight back to it.
func clear_spot(from: Vector3, dist: float) -> Vector3:
	var space = main.player.get_world_3d().direct_space_state
	for k in 24:
		var dir := Vector3(1, 0, 0).rotated(Vector3.UP, TAU * k / 24.0)
		var c := from + dir * dist
		var q := PhysicsRayQueryParameters3D.create(c + Vector3(0, 1.0, 0), from + Vector3(0, 1.0, 0), 1)
		var down := PhysicsRayQueryParameters3D.create(c + Vector3(0, 1.0, 0), c + Vector3(0, -0.5, 0), 1)
		var floor_hit: Dictionary = space.intersect_ray(down)
		var box := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.45
		box.shape = sh
		box.transform = Transform3D(Basis(), c + Vector3(0, 0.9, 0))
		box.collision_mask = 1 | 16
		if space.intersect_ray(q).is_empty() and not floor_hit.is_empty() and floor_hit.position.y > from.y - 0.3 and space.intersect_shape(box, 1).is_empty():
			return Vector3(c.x, floor_hit.position.y + 0.05, c.z)
	return from + Vector3(dist, 0, 0)


func spawn(path: String, pos: Vector3) -> Node:
	var m = load(path).new()
	m.main = main
	m.level = lvl
	lvl.add_child(m)
	m.global_position = pos
	return m


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.term.run("LEAVE_CHECKPOINT")
	main.rng.seed = 4242   # (the same site every run)
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	lvl = main.level
	fac = lvl.facility
	lvl.hazards.events.clear()
	for n in lvl.get_children():
		if n.is_in_group("monsters") or n.is_in_group("fauna"):
			n.free()
	var p = main.player
	# Two rooms with a wall between them (sight blocked), linked some way round.
	var a := Vector2i.ZERO
	var b := Vector2i(999, 999)
	for c in fac.layout.cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if fac.layout.links.has(c + d) and not fac.layout.links[c].has(c + d) and not fac.group_of.has(c) and not fac.group_of.has(c + d):
				a = c
				b = c + d
				break
		if b != Vector2i(999, 999):
			break
	var ra: Vector3 = fac.to_global(Vector3(a.x * 12.0, 0.1, a.y * 12.0))
	var rb: Vector3 = fac.to_global(Vector3(b.x * 12.0, 0.1, b.y * 12.0))
	p.global_position = ra
	p.velocity = Vector3.ZERO
	p.hp = 100.0
	await secs(0.3)

	# SIREN: calls in a crewmate's voice from out of sight.
	var clip := PackedFloat32Array()
	for i in 24000:
		clip.append(sin(TAU * 180.0 * i / 24000.0) * 0.3)
	main.net.voice.clips[42] = [clip]
	var s = spawn("res://src/siren.gd", rb)
	s._call = 0.0
	check(await wait_until(func(): return s._voice.playing, 4.0), "the siren calls out in a crewmate's voice from behind a wall")
	check(s.state == s.STALK, "...and comes for whoever it called to")
	# Catch it in view: it backs off.
	s.global_position = clear_spot(p.global_position, 5.0)
	s.state = s.STALK
	s.prey = p
	var d: Vector3 = s.global_position - (p.global_position + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = 0.0
	var ok_seen: bool = await wait_until(func(): return s.state == s.FLEE, 5.0)
	check(ok_seen, "seen, it backs off into the dark")
	# Unseen and close, it lunges.
	s.state = s.STALK
	s.prey = p
	s._seen_t = 0.0
	s.global_position = clear_spot(p.global_position, 2.6)
	var away: Vector3 = p.global_position - s.global_position
	p.rotation.y = atan2(-away.x, -away.z)   # (looking away from it)
	var hp0: float = p.hp
	check(await wait_until(func(): return p.hp < hp0, 4.0), "unseen, it lunges and hurts (%.0f)" % (hp0 - p.hp))
	s.take_hit(10.0, p.global_position, p)
	check(s.state == s.FLEE, "hit, it runs")
	s.free()
	main.net.voice.clips.clear()
	var s2 = spawn("res://src/siren.gd", rb)
	s2._speak()   # nothing to steal: a faked sound instead, no crash
	check(not s2._voice.playing, "alone (no voices to steal) it fakes a sound instead")
	s2.free()

	# HUSK: a body left lying gets up.
	p.hp = 100.0
	p.global_position = ra
	var body = main.spawn_item("REMAINS", rb + Vector3(0, 0.3, 0), -1.0, lvl)
	await secs(0.5)
	body.set_meta("born", Time.get_ticks_msec() / 1000.0 - 999.0)
	lvl._possessions()
	await process_frame
	var husks: Array = main.get_tree().get_nodes_in_group("monsters").filter(func(m): return m.get_script().resource_path.ends_with("husk.gd"))
	check(husks.size() == 1 and not is_instance_valid(body) or (is_instance_valid(body) and body.is_queued_for_deletion()), "a body left lying in the dark gets up as a husk")
	var h = husks[0] if not husks.is_empty() else null
	if h != null:
		h.global_position = clear_spot(p.global_position, 4.5)
		var dd: Vector3 = h.global_position - p.global_position
		p.rotation.y = atan2(-dd.x, -dd.z)
		check(await wait_until(func(): return h.state == h.STARE, 8.0), "it comes up to you and stares")
		var stare_d: float = h.global_position.distance_to(p.global_position)
		check(stare_d < 3.2, "...at arm's length (%.1f m)" % stare_d)
		hp0 = p.hp
		await secs(2.0)
		check(p.hp == hp0, "...a while, before it does anything")
		check(await wait_until(func(): return p.hp < hp0, 8.0), "...then goes for you (%.0f)" % (hp0 - p.hp))
		h.take_hit(9999.0, p.global_position, p)
		await secs(0.5)
		var left: Array = main.get_tree().get_nodes_in_group("pickups").filter(func(x): return x.id == "REMAINS" and x.has_meta("no_possess"))
		check(left.size() == 1, "killed, it's just a body again")
	print("creatures2.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
