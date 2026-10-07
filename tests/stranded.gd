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


## Leave, step off after `step_off_after` seconds, optionally climb back on, and watch.
func trip(step_off_after: float, climb_back := false) -> Dictionary:
	var main = await fresh()
	load_up(main)
	await process_frame
	var tools0: int = aboard(main, "tool") + held(main, "tool")
	var t0 := Time.get_ticks_msec()
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	await create_timer(step_off_after).timeout
	# Step out of the side door onto whatever is out there.
	main.player.global_position = main.train.to_global(Vector3(2.6, 1.1, 4.0))
	if climb_back:
		await create_timer(0.3).timeout
		main.player.global_position = main.train.to_global(Vector3(0, 1.3, 0))
	var r := {"lowest": INF, "card_at": -1.0, "card": ""}
	var end := Time.get_ticks_msec() + 24000
	while Time.get_ticks_msec() < end and (main.busy or main._recovering):
		r.lowest = minf(r.lowest, main.player.global_position.y)
		if r.card_at < 0.0 and main.hud.big_l.text != "":
			r.card_at = (Time.get_ticks_msec() - t0) / 1000.0
			r.card = main.hud.big_l.text
		await process_frame
	r.over = main.over
	r.arrived = not main.busy and main.level != null and main.stage == 0
	r.on_board = main.train.on_board(main.player.global_position)
	r.scrap = aboard(main, "scrap") + held(main, "scrap")
	r.tools = aboard(main, "tool") + held(main, "tool") - tools0   # change in tools (starter kit is aboard too)
	main.queue_free()
	await process_frame
	return r


func _run() -> void:
	var a: Dictionary = await trip(3.0)    # world sliding away
	check(not a.over and "LEFT BEHIND" in a.card, "stepping off while pulling out = left behind, and the run goes on")
	check(a.card_at >= 1.5 + 5.5 - 0.2, "...but only once the train has fully pulled away (card at %.1f s)" % a.card_at)
	check(a.lowest > -20.0, "...and you stayed in the world (lowest y %.1f)" % a.lowest)
	check(a.arrived and a.on_board, "...recovered aboard and taken on to the next stop")
	check(a.scrap == 0 and a.tools == 0, "...all scrap written off, tools kept (scrap %d, tools lost %d)" % [a.scrap, a.tools])
	var d: Dictionary = await trip(1.7, true)   # off and straight back on while it's still crawling
	check(not d.over and d.card == "" and d.arrived, "climbing back aboard in time = not left behind")
	check(d.scrap == 2, "...and the scrap is still yours (%d)" % d.scrap)
	var c: Dictionary = await trip(7.6)    # black screen between stations (no world at all)
	check(not c.over and "LEFT BEHIND" in c.card, "stepping off between stations = left behind")
	check(c.lowest > -20.0, "...without falling into the void (lowest y %.1f)" % c.lowest)
	check(c.arrived and c.on_board, "...recovered aboard at the next stop")
	var b: Dictionary = await trip(10.5)   # new station sliding in: the train is stopping anyway
	check(not b.over and b.card == "" and b.arrived, "hopping off while it rolls in is fine")
	check(b.lowest > -20.0, "...and you stayed in the world (lowest y %.1f)" % b.lowest)
	check(b.scrap == 2, "...nothing lost (%d)" % b.scrap)
	# Dying at a station: recovered aboard, carried off to the next stop, scrap gone.
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
	main.player.die("Testing.")
	end = Time.get_ticks_msec() + 30000
	var card := ""
	while Time.get_ticks_msec() < end and (main.busy or main._recovering):
		if card == "" and main.hud.big_l.text != "":
			card = main.hud.big_l.text
		await process_frame
	check(not main.over and "YOU DIED" in card, "dying doesn't end the run")
	check(not main.player.dead and main.player.hp == 100.0 and main.stage == 1, "...recovered aboard at the next stop (stage %d)" % main.stage)
	check(aboard(main, "scrap") == 0 and held(main, "scrap") == 0, "...with all scrap written off")
	check(aboard(main, "tool") == tools0, "...tools left aboard are kept (%d of %d)" % [aboard(main, "tool"), tools0])
	check(main.stats.lost == 1, "...and it's counted in the run stats")
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
	check(not main.over and "LEFT BEHIND" in card and main.stage == 2, "missing the train: left behind, recovered at the next stop")
	check(main.train.position.x == 0.0 and main.train.on_board(main.player.global_position), "...the train's back in place with you aboard")
	main.queue_free()
	await process_frame
	print("stranded.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
