# The lift carries what's in it: you, scrap, and a body lying on the floor of the cab; and a crewmate
# in the cab is sent measured from the cab ("E"), so their copy rides it on every machine.
# Run: tests/run.sh 120 --headless --path . -s tests/lift.gd
extends SceneTree

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


func _run() -> void:
	Engine.set_meta("fast_test", true)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	var lvl = main.level
	var lift = lvl.elevator
	for n in lvl.get_children():
		if n.is_in_group("monsters"):
			n.queue_free()
	var floor_y: float = lift.cab.global_position.y
	main.player.global_position = lift.cab.global_position + Vector3(0.5, 0.3, 0.5)
	main.player.velocity = Vector3.ZERO
	var item = main.spawn_item("WRENCH", lift.cab.global_position + Vector3(-0.5, 0.4, 0.6), -1.0, lvl)
	var body = main.spawn_item("REMAINS", lift.cab.global_position + Vector3(0.0, 0.2, -0.4), -1.0, lvl)
	for i in 120:   # (it falls and settles)
		await physics_frame
	check(lift.inside(body.global_position), "a body lies in the cab")
	check(main.net.tag_of(item) == "E", "scrap in the cab is synced from the cab (tag %s)" % main.net.tag_of(item))
	lift.ride()
	var end := Time.get_ticks_msec() + 30000
	while (lift.moving or not lift._doors_open) and Time.get_ticks_msec() < end:
		await process_frame
	var drop: float = floor_y - lift.cab.global_position.y
	check(drop > 30.0, "the lift went down (%.1f m)" % drop)
	check(lift.inside(main.player.global_position), "you rode it down")
	check(is_instance_valid(item) and lift.inside(item.global_position), "the scrap rode it down")
	check(lift.inside(body.global_position), "the body rode it down (%.1f m above the cab floor)" % (body.global_position.y - lift.cab.global_position.y))
	print("lift.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
