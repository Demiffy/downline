# Stepping off the train mid-trip leaves you behind with the world, never falling into the void.
# Run: godot --headless --path . -s tests/stranded.gd
extends SceneTree

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


func trip(step_off_after: float) -> Array:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	await create_timer(step_off_after).timeout
	# Step out of the side door onto whatever is out there.
	main.player.global_position = main.train.to_global(Vector3(2.6, 1.1, 4.0))
	var lowest := INF
	var end := Time.get_ticks_msec() + 9000
	while Time.get_ticks_msec() < end and not main.over:
		lowest = minf(lowest, main.player.global_position.y)
		await process_frame
	var r := [main.over, lowest, main.hud.big_l.text]
	main.queue_free()
	await process_frame
	return r


func _run() -> void:
	var a: Array = await trip(3.0)    # world sliding away
	check(a[0] and "LEFT BEHIND" in a[2], "stepping off while pulling out = left behind")
	check(a[1] > -20.0, "...and you stayed in the world (lowest y %.1f)" % a[1])
	var c: Array = await trip(7.6)    # black screen between stations (no world at all)
	check(c[0] and "LEFT BEHIND" in c[2], "stepping off between stations = left behind")
	check(c[1] > -20.0, "...without falling into the void (lowest y %.1f)" % c[1])
	var b: Array = await trip(10.5)   # new station sliding in
	check(b[0] and "LEFT BEHIND" in b[2], "stepping off while arriving = left behind")
	check(b[1] > -20.0, "...and you stayed in the world (lowest y %.1f)" % b[1])
	print("stranded.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
