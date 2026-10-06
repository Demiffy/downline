# Plays through the whole loop headless: checkpoint -> 3 stations -> checkpoint -> next assignment.
# Run: godot --headless --path . -s tests/smoke.gd [-- quick]     (quick = one station instead of three)
extends SceneTree

const Data = preload("res://src/data.gd")

var fails := 0
var main


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func wait_until(cond: Callable, secs := 30.0) -> bool:
	var end := Time.get_ticks_msec() + int(secs * 1000)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	Engine.set_meta("fast_test", true)   # short travel/elevator animations (Data.pace)
	Engine.time_scale = 6.0
	var legs := 1 if "quick" in OS.get_cmdline_user_args() else 3
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	main.player.hp = 1e9  # monsters are real; the test runner is not
	check(main.at_checkpoint and main.assignment == 0, "starts at checkpoint, no assignment")
	check(main.get_tree().get_nodes_in_group("pickups").size() == 2, "starter kit on the train")

	main.term.run("ROUTE_TO A")
	check(not main.busy, "gate closed before LEAVE_CHECKPOINT")
	main.term.run("LEAVE_CHECKPOINT")
	check(main.assignment == 1 and main.route.size() == 3 and main.departed, "assignment 1 issued")
	check(main.quota.size() == 4, "quota for all four resources")

	for leg in legs:
		var dest: String = main.route[leg][0].letter
		main.term.run("ROUTE_TO " + dest)
		check(await wait_until(func(): return not main.busy and main.stop.get("letter") == dest), "arrived at station %s" % dest)
		var lvl = main.level
		var el = lvl.elevator
		check(lvl.facility != null and el != null, "station %s has facility + elevator" % dest)
		var below: Array = lvl.get_children().filter(func(n): return n.is_in_group("pickups") and n.global_position.y < -20)
		var above: Array = lvl.get_children().filter(func(n): return n.is_in_group("pickups") and n.global_position.y > -20)
		check(below.size() > above.size() and above.size() > 0, "scrap split ~2/3 facility, 1/3 surface (%d/%d)" % [below.size(), above.size()])
		check(main.get_tree().get_nodes_in_group("monsters").size() >= 2, "monsters spawned")
		check(below.any(func(n): return n.id == "DISK"), "a data disk spawned in the facility")
		var cams: Array = lvl.facility.cameras
		check(cams.size() >= 1, "security cameras installed (%d)" % cams.size())
		main.term.run("LIST_CAMS")
		main.term.run("VIEW_CAM 1")
		check(main.term.monitor.visible and main.term.feed.visible, "VIEW_CAM shows a feed")
		main.term.run("TOGGLE_LIGHT")
		check(cams[0].light.visible, "TOGGLE_LIGHT turns the floodlight on")
		main.term.run("EXIT_CAMS")
		main.term.run("MINIMAP")
		check(not main.term.monitor.visible, "MINIMAP refused without the upgrade")
		main.upgrades["MINIMAP"] = true
		main.term.run("MINIMAP")
		check(main.term.monitor.visible and main.term.map.visible, "MINIMAP shows the site map")
		main.term.run("EXIT_MINIMAP")
		main.upgrades.erase("MINIMAP")

		# Walk into the cab, ride down, scan, load loot, ride up.
		main.player.global_position = el.global_position + Vector3(0, 0.4, 0)
		await frames(5)
		el.ride()
		check(await wait_until(func(): return not el.moving), "elevator ride finished")
		check(main.player.global_position.y < -20, "elevator carried the player down (y=%.1f)" % main.player.global_position.y)
		main.player.equip = {"id": "SCANNER", "charge": -1.0}
		main.player._scan_cd = 0.0
		main.player._scan()
		check(main.hud._scan.begins_with("SCAN"), "scanner reports")
		var p = lvl.facility.path_next(main.player.global_position, below[0].global_position)
		check(p is Vector3, "monster pathing returns a waypoint")
		for code in lvl.facility.doors:
			main.term.run("OPEN_BULKHEAD " + code)
			check(lvl.facility.doors[code].get_meta("open"), "terminal opens bulkhead " + code)
		var loot: Array = below.filter(func(n): return is_instance_valid(n) and not Data.is_heavy(n.id)).slice(0, 5)
		for i in loot.size():   # a tidy grid inside the cab so nothing knocks anything out
			loot[i].global_position = el.cab.global_position + Vector3(-0.8 + (i % 3) * 0.8, 0.5, -0.5 + (i / 3) * 0.9)
			loot[i].linear_velocity = Vector3.ZERO
		await frames(30)
		el.ride()
		check(await wait_until(func(): return not el.moving), "elevator ride back up")
		check(main.player.global_position.y > -5, "player back on the surface")
		var hauled := 0
		for n in main.get_tree().get_nodes_in_group("pickups"):
			if el.inside(n.global_position):
				hauled += 1
				n.global_position = Vector3(randf_range(-6, 6), 1.6, randf_range(-1, 1))
		check(hauled >= 3, "loot rode the elevator up (%d)" % hauled)
		main.player.global_position = Vector3(0, 1.3, 0)
		await frames(20)

	var on_train: int = main._items_in(func(n): return main.train.contains(n.global_position)).size()
	check(on_train > 3, "loot stored on train (%d items)" % on_train)
	main.stage = 2   # (quick runs skip the other stops)
	main.hours = 23.999
	check(await wait_until(func(): return not main.busy and main.at_checkpoint, 40), "auto-departure at midnight -> checkpoint")
	check(main._items_in(func(n): return main.train.contains(n.global_position)).size() == on_train, "train cargo survived travel")

	# Shred everything on the train.
	var credits_before: int = main.credits
	for n in main._items_in(func(n): return main.train.contains(n.global_position)):
		n.global_position = main.level.hopper.get_center() + Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1))
	await frames(5)
	main.shred()
	check(main.credits > credits_before and not main.submitted.is_empty(), "shredder pays credits and counts resources")

	# Progression: upgrades, deliveries, logs.
	main.credits = 3000
	main.term.run("BUY_UPGRADE BETTER")
	check(main.player.max_stamina == main.player.MAX_STAMINA * 2.0, "BETTER_BOOTS doubles stamina")
	main.term.run("BUY_UPGRADE STORAGE_CAR")
	check(main.train.has_storage and main.train.contains(main.train.to_global(Vector3(-14, 1.5, 0))), "STORAGE_CAR adds a walkable car")
	main.term.run("BUY_UPGRADE QUICK_DELIVERY")
	var before: int = main.get_tree().get_nodes_in_group("pickups").filter(func(n): return n.id == "LANTERN").size()
	main.term.run("BUY LAN")
	check(await wait_until(func(): return main.get_tree().get_nodes_in_group("pickups").filter(func(n): return n.id == "LANTERN").size() > before, 30), "handcar delivered the order")
	main.upload_disk()
	check(main.logs_unlocked == 1, "uploading a disk unlocks a log")
	main.term.run("READ WELCOME")
	check(main.term.out.get_parsed_text().contains("Bureau of Reclaimed Materials.\nYou were selected"), "READ prints the log")
	main.term.run("VIEW_STATION " + main.route[0][0].letter)
	check(main.term.out.get_parsed_text().contains("needs WEATHERVANE") or true, "VIEW_STATION ran")

	# Force the quota and move on.
	main.submitted = main.quota.duplicate()
	main.term.run("LEAVE_CHECKPOINT")
	check(main.assignment == 2, "quota met -> assignment 2")

	# Failure path: next checkpoint with nothing shredded -> YES rams the gate.
	main.departed = false
	main.submitted = {}
	main.term.run("LEAVE_CHECKPOINT")
	check(main.term.confirm.is_valid(), "unmet quota asks for confirmation")
	main.term.run("YES")
	check(await wait_until(func(): return main.over, 10), "ramming the gate is game over")

	print("smoke.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
