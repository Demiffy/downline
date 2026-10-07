# Behaviour test for every entity: each one is dropped next to the player in a real facility room
# and must do its thing. Run: godot --headless --path . -s tests/monsters.gd
extends SceneTree

var fails := 0
var main
var lvl
var fac
var room := Vector3.ZERO   # centre of a furnished (non-pit, non-tunnel) room


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func wait_until(cond: Callable, secs := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(secs * 1000)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func secs(t: float) -> void:
	await main.get_tree().create_timer(t).timeout


func _initialize() -> void:
	_run()


func clear() -> void:
	for n in lvl.get_children():
		var sc: Script = n.get_script()
		if sc and (n.is_in_group("monsters") or sc.resource_path.get_file() in ["bear_trap.gd", "snatcher.gd", "gloe.gd", "leviathan.gd"]):
			n.queue_free()
	main.player.trapped = null
	await frames(3)


func spawn(path: String, pos: Vector3) -> Node:
	var m = load(path).new()
	m.main = main
	m.level = lvl
	lvl.add_child(m)
	m.global_position = pos
	return m


## Put the player at `pos` looking at `at`.
func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	var d := at - (pos + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "FACTORY"
	stop.rooms = 18
	main.player.global_position = Vector3(0, 1.3, 0)
	Engine.time_scale = 4.0
	main.term.run("ROUTE_TO " + stop.letter)
	await wait_until(func(): return not main.busy, 40)
	Engine.time_scale = 1.0
	lvl = main.level
	fac = lvl.facility
	var hz = lvl.hazards   # keep the site's own hazards out of the creature tests
	hz.events.clear()
	hz.set_physics_process(false)   # no steam bursts or cable arcs making noise mid-test
	var steam_cells: Array = hz.steams.map(func(st): return fac.cell_at(st.at))
	for c in fac.layout.cells:
		if not (fac.kinds[c] in ["start", "pit", "tunnel"]) and not hz.flooded.has(c) and not hz.gassed.has(c) and not c in steam_cells:
			room = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
			break
	check(room != Vector3.ZERO, "found a furnished room to test in")
	main.player.hp = 1e9
	var me := room + Vector3(-4.5, 0.05, 0)
	var there := room + Vector3(4.0, 0.05, 0)

	# STATUE: dormant until seen; frozen while watched; moves when unwatched; hits hard.
	await clear()
	look(me, there + Vector3(0, 1, 0))
	var st = spawn("res://src/statue.gd", there)
	await frames(10)
	check(st.awake, "statue wakes when first seen")
	var p0: Vector3 = st.global_position
	await secs(0.8)
	check(st.global_position.distance_to(p0) < 0.05, "statue doesn't move while watched")
	look(me, me + Vector3(-5, 1, 0))   # turn around
	await secs(0.6)
	check(st.global_position.distance_to(p0) > 1.0, "statue moves when nobody is looking")
	var hp0: float = main.player.hp
	check(await wait_until(func(): return main.player.hp < hp0, 6), "statue hits you from behind")

	# MARIONETTE: frozen while unwatched; sprints while watched.
	await clear()
	look(me, me + Vector3(-5, 1, 0))
	var mar = spawn("res://src/marionette.gd", there)
	await secs(0.8)
	check(mar.global_position.distance_to(there) < 0.1, "marionette stays put while unwatched")
	look(me, there + Vector3(0, 0.8, 0))
	await secs(1.2)
	check(mar.standing and mar.global_position.distance_to(there) > 1.0, "marionette stands and runs at you while watched")
	look(me, me + Vector3(-5, 1, 0))
	await frames(5)
	var mp: Vector3 = mar.global_position
	await secs(0.6)
	check(mar.global_position.distance_to(mp) < 0.05, "marionette freezes when you look away")

	# MIMIC: bites when close, then runs off and hides.
	await clear()
	var mim = spawn("res://src/mimic.gd", room + Vector3(-3.0, 0.05, 0))
	await frames(5)
	hp0 = main.player.hp
	look(me, mim.global_position)
	check(await wait_until(func(): return main.player.hp < hp0, 3), "mimic bites when you get close")
	check(await wait_until(func(): return mim.state == mim.FLEE, 3), "mimic runs off after biting")
	check(mim.is_in_group("hide_on_map"), "mimic is hidden from the map")

	# WARDEN: notices you only inside its beam.
	await clear()
	look(me, me + Vector3(-5, 1, 0))
	var war = spawn("res://src/warden.gd", there)
	war.rotation.y = -PI * 0.5   # -z turned to +x: facing away from the player
	war.set_physics_process(false)
	await frames(5)
	war._head.rotation.y = 0.0
	check(not war._in_beam(main.player), "warden can't see you behind it")
	war.rotation.y = PI * 0.5    # facing -x, toward the player
	await frames(2)
	check(war._in_beam(main.player), "warden sees you in its beam")
	war.set_physics_process(true)
	check(await wait_until(func(): return war.state == war.HUNT, 2), "warden hunts once it sees you")

	# BEAR TRAP: snaps, holds you, pry it open.
	await clear()
	var trap = spawn("res://src/bear_trap.gd", me)
	hp0 = main.player.hp
	look(me + Vector3(0, 0.0, 0), me + Vector3(0.5, 0, 0))
	check(await wait_until(func(): return main.player.trapped == trap, 2), "bear trap catches you")
	check(main.player.hp < hp0, "bear trap hurts")
	trap.release()
	check(main.player.trapped == null, "prying the trap frees you")

	# SNATCHER: pulls you into the vent and drops you somewhere else.
	await clear()
	look(me, me + Vector3(1, 1, 0))
	spawn("res://src/snatcher.gd", Vector3(me.x, fac.global_position.y + fac.H, me.z))
	check(await wait_until(func(): return main.player.global_position.distance_to(me) > 3.0, 15), "snatcher drags you elsewhere")
	await wait_until(func(): return main.hud.fade_r.color.a < 0.05, 6)

	# SCRAPPER: flees from noise; caught when calm -> valuable shell.
	await clear()
	look(me, there)
	var scr = spawn("res://src/scrapper.gd", room + Vector3(-2.0, 0.05, 0))
	await frames(5)
	main.noise(me, 8.0)
	check(scr.fleeing > 0.0, "scrapper flees from footsteps")
	await wait_until(func(): return scr.fleeing <= 0.0, 6)
	scr._grabbed()
	await frames(3)
	check(main.get_tree().get_nodes_in_group("pickups").any(func(n): return n.id == "SCRAPPER_SHELL"), "catching the scrapper yields its shell")

	# GLOE: befriends and follows you.
	await clear()
	look(me, there)
	var g = spawn("res://src/gloe.gd", me + Vector3(2, 1.5, 0))
	check(await wait_until(func(): return g.friend == main.player, 3), "gloe picks you as its friend")
	look(room + Vector3(3, 0.05, 2), there)
	check(await wait_until(func(): return g.global_position.distance_to(main.player.global_position) < 3.5, 6), "gloe follows you")

	# ROOMBA: break the laser -> boom.
	await clear()
	look(me, there)
	var rb = spawn("res://src/roomba.gd", me + Vector3(2.0, 0, 0))
	rb.dir = Vector3(-1, 0, 0)
	hp0 = main.player.hp
	check(await wait_until(func(): return main.player.hp < hp0, 5), "roomba explodes when you break its beam")

	# PULSATOR: hears you, chases, bursts.
	await clear()
	var pu = spawn("res://src/pulsator.gd", there)
	await frames(5)
	hp0 = main.player.hp
	main.noise(me, 15.0)
	check(pu.chasing, "pulsator hears footsteps")
	check(await wait_until(func(): return main.player.hp < hp0, 8), "pulsator reaches you and bursts")

	# LEVIATHAN: on the surface, a noise during a rumble kills you in the open, not under a roof.
	await clear()
	var lev = spawn("res://src/leviathan.gd", Vector3.ZERO)
	var open := Vector3.ZERO
	for k in 12:   # outdoor props are random; find a spot with open sky
		open = Vector3(lvl.elevator_pos.x + 20.0 + k * 4.0, 0, lvl.elevator_pos.z + 18.0)
		open.y = lvl.ground_y(open.x, open.z) + 0.2
		if not lev._roofed(open):
			break
	look(open, open + Vector3(1, 1, 0))
	await frames(5)
	lev.state = lev.RUMBLE
	lev._t = 0.0
	hp0 = main.player.hp
	main.noise(open, 8.0)
	check(lev.state == lev.WARN, "leviathan hears you during a rumble")
	check(await wait_until(func(): return main.player.hp < hp0 - 100.0, 8), "leviathan swallows you in the open")
	await wait_until(func(): return lev.state == lev.IDLE, 8)
	look(Vector3(0, 1.3, 0), Vector3(3, 1.3, 0))   # inside the train
	await frames(5)
	lev.state = lev.RUMBLE
	lev._t = 0.0
	hp0 = main.player.hp
	lev.hear(Vector3(0, 1.3, 0))
	await wait_until(func(): return lev.state == lev.IDLE, 8)
	check(main.player.hp == hp0, "a roof (the train) protects you from the leviathan")

	print("monsters.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
