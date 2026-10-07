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
		if sc and (n.is_in_group("monsters") or sc.resource_path.get_file() in ["bear_trap.gd", "snatcher.gd", "gloe.gd", "leviathan.gd", "wraith.gd"]):
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

	# OBSERVER: follows from behind without doing anything; look at it and it whines up its flash
	# (look away in time and nothing happens); keep looking and you're blinded, it runs, and leaves a photo.
	await clear()
	main.player.blind = 0.0
	look(me, me + Vector3(-5, 1.6, 0))   # facing away from it
	var obs = spawn("res://src/observer.gd", there)
	check(await wait_until(func(): return obs.state == obs.FOLLOW, 3), "observer starts following you")
	await secs(3.0)
	check(main.player.blind == 0.0 and obs.state == obs.FOLLOW, "observer just follows while you don't look back")
	var back_dir: Vector3 = main.player.global_transform.basis.z
	var to_obs: Vector3 = (obs.global_position - main.player.global_position) * Vector3(1, 0, 1)
	check(back_dir.dot(to_obs.normalized()) > 0.8 and to_obs.length() < obs._creep + 1.5, "...keeping just behind you (%.1f m)" % to_obs.length())
	look(me, obs._lens.global_position - Vector3(0, 1.6, 0) + Vector3(0, 1.6, 0))
	check(await wait_until(func(): return obs.state == obs.CHARGE, 1.0), "looking at the observer starts its flash charging")
	look(me, me + (me - obs.global_position) + Vector3(0, 1.6, 0))   # turn away again, quickly
	await secs(0.8)
	check(main.player.blind == 0.0 and obs.state != obs.FLEE, "looking away in time stops the flash")
	look(me, obs._lens.global_position)
	check(await wait_until(func(): return main.player.blind > 0.4, 3.0), "looking at it too long: blinded by the flash (%.2f)" % main.player.blind)
	check(obs.state == obs.FLEE, "...and it runs off")
	check(await wait_until(func(): return main.get_tree().get_nodes_in_group("photos").size() > 0, 2.0), "...leaving a photograph on the floor")
	await secs(1.0)
	check(main.player.blind < 0.85, "the white-out fades")

	# WRAITH: drifts after you in the dark, dimming the lamps; a flashlight beam burns it off (and the
	# battery with it); a lit lantern keeps it at the edge of the light; in the dark it reaches you.
	await clear()
	main.player.blind = 0.0
	var p = main.player
	p.light_on = false
	look(me, me + Vector3(-5, 1.6, 0))
	var wr = spawn("res://src/wraith.gd", there)
	check(await wait_until(func(): return wr.state == wr.STALK, 2), "wraith comes for you")
	var lamp_near = null
	for l: Light3D in fac.find_children("*", "Light3D", true, false):
		if l.has_meta("base") and l.global_position.distance_to(wr.global_position) < 5.0:
			lamp_near = l
	await secs(0.5)
	if lamp_near != null:
		check(lamp_near.light_energy < lamp_near.get_meta("base") * 0.95, "lamps near it gutter")
	hp0 = p.hp
	check(await wait_until(func(): return p.hp < hp0, 8), "in the dark it reaches you (%.0f damage)" % (hp0 - p.hp))
	check(hp0 - p.hp < 60.0, "...hurts, but doesn't one-shot")
	check(wr.state == wr.GONE and not wr._float.visible, "...then it's gone")
	await secs(0.3)
	if lamp_near != null:
		check(absf(lamp_near.light_energy - lamp_near.get_meta("base")) < 0.01 or (lamp_near is OmniLight3D and fac.flicker.has(lamp_near)), "...and the lamps come back")
	# Flashlight.
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 200.0}
	p.sel = 0
	p.light_on = true
	wr._reform()
	wr.global_position = there
	look(me, there + Vector3(0, 1.4, 0))
	await frames(3)
	var c0: float = p.slots[0].charge
	var t0 := Time.get_ticks_msec()
	check(await wait_until(func(): return wr.state == wr.BURN, 1.5), "a flashlight beam on it makes it recoil")
	check(await wait_until(func(): return wr.state == wr.GONE, 4.0), "...and held there, it comes apart")
	var spent: float = c0 - p.slots[0].charge
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	check(spent > took * 2.5, "...draining the battery fast (%.1f s of charge in %.1f s)" % [spent, took])
	# Lantern.
	p.slots[0] = {"id": "LANTERN", "charge": 285.0}
	p.light_on = true
	wr._reform()
	wr.global_position = there
	look(me, me + Vector3(-5, 1.6, 0))
	hp0 = p.hp
	await secs(4.0)
	check(p.hp == hp0 and wr.global_position.distance_to(me) > wr.LANTERN_R - 0.4, "a lit lantern holds it off (%.1f m)" % wr.global_position.distance_to(me))
	p.light_on = false
	p.slots[0] = null

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
