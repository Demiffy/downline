# The facility through the day (site_clock.gd): fire shutters stand open in some doorways, a main
# bursts and floods a room, a lockdown shuts every shutter and open bulkhead and opens them again,
# the lift's motor fails at 23:00 and it crawls. And the landmark: one stands on the surface, its
# safe pries open and pays out. Run: tests/run.sh 150 --headless --path . -s tests/site_clock.gd
extends SceneTree

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	Engine.set_meta("fast_test", true)
	Engine.set_meta("force_landmark", "CHAPEL")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "FACTORY"
	stop.rooms = 20
	stop.biome = "DESERT"
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	var lvl = main.level
	var site = lvl.site
	var fac = lvl.facility
	check(site != null, "the site clock runs at a station")
	check(site.shutters.size() >= 1, "fire shutters stand in some doorways (%d)" % site.shutters.size())
	for code in site.shutters:
		check(fac.doors[code].get_meta("open"), "...%s starts rolled up" % code)
	# A burst main.
	var flooded0: int = lvl.hazards.flooded.size()
	var c = site._burst_room()
	check(c != null, "there's a dry room for a main to burst in")
	site._say(["burst", c])
	await frames(5)
	check(lvl.hazards.flooded.size() == flooded0 + 1 and lvl.hazards.flooded.has(c), "the main bursts and the room floods")
	# A lockdown, and the all-clear.
	site._say(["lockdown", true])
	await frames(3)
	var shut: bool = site.shutters.all(func(code): return not fac.doors[code].get_meta("open"))
	check(shut, "a lockdown brings every shutter down")
	check(site._lockdown_t > 0.0, "...for a while")
	site._lockdown_t = 0.01
	lvl.tick(0.1, 12.0)
	await frames(3)
	check(site.shutters.all(func(code): return fac.doors[code].get_meta("open")), "...then they roll up again")
	# The lift at 23:00.
	site.events = [[23.0, "lift_fault"]]
	lvl.tick(0.1, 23.1)
	await frames(2)
	check(lvl.elevator.fault, "at 23:00 the lift's motor fails")
	# The landmark and its safe.
	check(lvl.landmark == "CHAPEL" and lvl.safes.size() >= 1, "the station has its landmark (%s) with a safe" % lvl.landmark)
	check(fac.supplies.has(lvl.safes[0]), "...the safe's with the facility's crates (a save remembers it)")
	var n0: int = main.get_tree().get_nodes_in_group("pickups").size()
	lvl.Landmarks.open_safe(lvl, lvl.safes[0])
	await frames(5)
	check(lvl.safes[0].get_meta("opened", false) and main.get_tree().get_nodes_in_group("pickups").size() >= n0 + 2, "prying the safe open pays out")
	# The director: calm, then a build of scares at whoever's alone, a peak, a breather.
	var dir = lvl.director
	var p = main.player
	p.global_position = fac.to_global(Vector3(0, 0.2, 0))
	dir.mood = "BUILD"
	dir._step = 0
	dir._t = 0.0
	dir._tick = 0.0
	lvl.tick(0.1, 12.0)
	await frames(2)
	check(dir._step == 1, "the director's build sends a scare (%s, step %d)" % [dir.mood, dir._step])
	for k in [1, 2, 3]:
		dir._step = k
		dir._scare(p)   # (a door or a whisper, the lights, then pressure)
	await create_timer(2.5).timeout
	check(true, "...every kind of scare plays without trouble")
	p.hp -= 60.0
	for i in 4:
		dir._tick = 0.0
		lvl.tick(1.0, 12.0)
	check(dir.mood == "PEAK", "hurt badly, the crew's at a peak and it leaves them be (%s, %.2f)" % [dir.mood, dir.intensity])
	p.hp = 100.0
	dir._hurt.clear()
	for m in main.get_tree().get_nodes_in_group("monsters"):   # (the pressure scare called them over: send them off)
		m.queue_free()
	await frames(2)
	for i in 8:
		dir._tick = 0.0
		lvl.tick(1.0, 12.0)
	check(dir.mood == "RELAX" and dir.quiet, "...then a breather, with no extra creatures sent down (%s)" % dir.mood)
	print("site_clock.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
