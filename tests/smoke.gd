# Plays through the whole loop headless: checkpoint -> 3 stations -> checkpoint -> next assignment.
# Run: godot --headless --path . -s tests/smoke.gd
extends SceneTree

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
	Engine.time_scale = 6.0
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

	for leg in 3:
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
		for i in mini(5, below.size()):
			if is_instance_valid(below[i]):
				below[i].global_position = el.cab.global_position + Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1))
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
