# Stepping off the train mid-trip: you stay in the world (never the void), can get back on while
# it's pulling out, and are only LEFT BEHIND once it has fully gone. Being left behind or dying
# doesn't end the run: you're recovered aboard and every bit of scrap (carried + aboard) is lost.
# Run: godot --headless --path . -s tests/stranded.gd
extends SceneTree

const Data = preload("res://src/data.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


func fresh():
	Engine.set_meta("fast_test", 0.2)   # (the rides five times as fast: the stepping off and back on still has time)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("LEAVE_CHECKPOINT")
	return main


## Scrap + a tool aboard and scrap + a tool in hand, so the write-off can be checked.
func load_up(main) -> void:
	main.spawn_item(Data.scrap_ids()[0], main.train.to_global(Vector3(2, 1.0, 0.5)))
	main.spawn_item("FLASHLIGHT", main.train.to_global(Vector3(2, 1.0, -0.5)))
	main.player.slots[1] = {"id": Data.scrap_ids()[0], "charge": -1.0}
	main.player.slots[2] = {"id": "LANTERN", "charge": 100.0}


func aboard(main, kind: String) -> int:
	var n := 0
	for p in main.get_tree().get_nodes_in_group("pickups"):
		if not p.is_queued_for_deletion() and main.train.contains(p.global_position) and Data.kind(p.id) == kind:
			n += 1
	return n


func held(main, kind: String) -> int:
	return main.player.slots.filter(func(it): return it != null and Data.kind(it.id) == kind).size()


## Leave, step off at a point in the trip (`at`: "crawl" just pulling out, "out" running the open
## line, "tunnel" deep in the tunnel, "in" running into the platform), optionally climb back on, and watch.
func trip(at: String, climb_back := false) -> Dictionary:
	var main = await fresh()
	load_up(main)
	await process_frame
	var tools0: int = aboard(main, "tool") + held(main, "tool")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while not main.line.riding:
		await process_frame
	var l = main.line
	var t: Dictionary = l._segs.filter(func(g): return g.kind == "tunnel" and g.b > 0.0)[0]
	var mark: float = {"crawl": 2.0, "out": 120.0, "tunnel": t.a + 100.0, "in": l._arr_x - 60.0}[at]
	while l.riding and l.s < mark:
		await process_frame
	# Step out of the side door onto whatever is out there.
	main.player.global_position = main.train.to_global(Vector3(2.6, 1.1, 4.0))
	if climb_back:
		await create_timer(0.3).timeout
		main.player.global_position = main.train.to_global(Vector3(0, 1.3, 0))
	var r := {"lowest": INF, "card": ""}
	var end := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < end and (main.busy or main._recovering):
		r.lowest = minf(r.lowest, main.player.global_position.y)
		if r.card == "" and main.hud.big_l.text != "":
			r.card = main.hud.big_l.text
		await process_frame
	r.over = main.over
	r.arrived = not main.busy and main.level != null and main.stage == 0
	r.on_board = main.train.on_board(main.player.global_position)
	r.at_station = main.level != null and main.level.to_local(main.player.global_position).length() < 60.0
	r.scrap = aboard(main, "scrap") + held(main, "scrap")
	r.tools = aboard(main, "tool") + held(main, "tool") - tools0   # change in tools (starter kit is aboard too)
	main.queue_free()
	await process_frame
	return r


func _run() -> void:
	var a: Dictionary = await trip("out")    # off on the open line
	check(not a.over and "LEFT BEHIND" in a.card, "stepping off on the open line = left behind, and the run goes on")
	check(a.lowest > -20.0, "...and you stayed in the world (lowest y %.1f)" % a.lowest)
	check(a.arrived and a.on_board, "...recovered aboard and taken on to the next stop")
	check(a.scrap == 1 and a.tools == 0, "...the scrap you carried written off, the cargo aboard and tools kept (scrap %d, tools lost %d)" % [a.scrap, a.tools])
	var d: Dictionary = await trip("crawl", true)   # off and straight back on while it's still crawling
	check(not d.over and d.card == "" and d.arrived, "climbing back aboard in time = not left behind")
	check(d.scrap == 2, "...and the scrap is still yours (%d)" % d.scrap)
	var c: Dictionary = await trip("tunnel")    # off in the dark
	check(not c.over and "LEFT BEHIND" in c.card, "stepping off in the tunnel = left behind")
	check(c.lowest > -20.0, "...without falling out of the world (lowest y %.1f)" % c.lowest)
	check(c.arrived and c.on_board, "...recovered aboard at the next stop")
	var b: Dictionary = await trip("in")   # running into the platform: the train is stopping anyway
	check(not b.over and b.card == "" and b.arrived, "hopping off while it rolls in is fine")
	check(b.lowest > -20.0 and b.at_station, "...and you're at the station (lowest y %.1f)" % b.lowest)
	check(b.scrap == 2, "...nothing lost (%d)" % b.scrap)
	# Dying at a station: a replacement wakes aboard at the same stop an hour later; the cargo aboard
	# is untouched; your remains lie where you fell and bringing them aboard pays a fee.
	var main = await fresh()
	Engine.set_meta("fast_test", true)
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	var end := Time.get_ticks_msec() + 8000
	while main.busy and Time.get_ticks_msec() < end:
		await process_frame
	Engine.remove_meta("fast_test")
	load_up(main)
	main.player.global_position = main.train.to_global(Vector3(2.6, 1.1, 4.0))   # out on the platform
	await create_timer(0.5).timeout
	var tools0: int = aboard(main, "tool")
	var scrap0: int = aboard(main, "scrap")
	var hours0: float = main.hours
	main.player.die("Testing.")
	end = Time.get_ticks_msec() + 30000
	var card := ""
	while Time.get_ticks_msec() < end and (main.busy or main._recovering):
		if card == "" and main.hud.big_l.text != "":
			card = main.hud.big_l.text
		await process_frame
	check(not main.over and "YOU DIED" in card, "dying doesn't end the run")
	check(not main.player.dead and main.player.hp == 100.0 and main.stage == 0 and main.train.on_board(main.player.global_position), "...a replacement wakes aboard, same stop")
	check(main.hours - hours0 > 0.95, "...an hour later (%.2f h)" % (main.hours - hours0))
	check(aboard(main, "scrap") == scrap0, "...with the cargo aboard untouched (%d of %d)" % [aboard(main, "scrap"), scrap0])
	check(aboard(main, "tool") == tools0, "...tools left aboard are kept (%d of %d)" % [aboard(main, "tool"), tools0])
	var remains: Array = main.get_tree().get_nodes_in_group("pickups").filter(func(p): return p.id == "REMAINS" and not p.has_meta("old_crew"))
	check(remains.size() == 1 and remains[0].is_in_group("scan_targets"), "...your remains lie where you fell (and the scanner knows)")
	check(main.stats.lost == 1, "...and it's counted in the run stats")
	await create_timer(2.0).timeout   # (it falls)
	check(remains[0].parts.size() == 11 and remains[0].parts.head.global_position.y < remains[0].parts.pelvis.global_position.y + 0.4, "...a body that has fallen down, not a box")
	main.player.global_position = remains[0].global_position + Vector3(0.8, 0.2, 0)
	main.player._pick(remains[0])   # lift it...
	await process_frame
	check(main.player.slots.any(func(it): return it != null and it.id == "REMAINS"), "...you can lift it")
	var cr0: int = main.credits
	main.player.global_position = main.train.to_global(Vector3(0, 1.3, 0))   # ...and carry it aboard
	end = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < end and main.credits == cr0:
		await process_frame
	await create_timer(0.3).timeout
	check(main.credits == cr0 + main.RECOVERY_PAY and not main.player.slots.any(func(it): return it != null and it.id == "REMAINS"), "bringing the remains aboard pays the recovery fee (+%d)" % (main.credits - cr0))
	main.player.global_position = main.train.to_global(Vector3(2.6, 1.1, 4.0))
	await create_timer(0.3).timeout
	main.player.die("Testing again.")
	end = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end and (main.busy or main._recovering):
		await process_frame
	check(aboard(main, "scrap") == scrap0, "dying again leaves the cargo alone too")
	# Missing the 24:00 departure: you watch it go, then you're recovered at the next stop.
	main.player.global_position = main.train.to_global(Vector3(2.6, 1.1, 4.0))
	await create_timer(0.3).timeout
	Engine.set_meta("fast_test", true)
	main._auto_depart()
	card = ""
	end = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end and (main.busy or main._recovering):
		if card == "" and main.hud.big_l.text != "":
			card = main.hud.big_l.text
		await process_frame
	Engine.remove_meta("fast_test")
	check(not main.over and "LEFT BEHIND" in card and main.stage == 1, "missing the train: left behind, recovered at the next stop")
	check(aboard(main, "scrap") == scrap0, "...and the cargo aboard comes with the train (%d)" % aboard(main, "scrap"))
	check(main.train.position.x == 0.0 and main.train.on_board(main.player.global_position), "...the train's in place with you aboard")
	main.queue_free()
	await process_frame
	print("stranded.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
