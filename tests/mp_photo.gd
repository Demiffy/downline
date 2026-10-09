# An observer's photo in a crew: the client sees it land where the host dropped it, picture and all.
# Run: tests/mp_photo.sh
extends SceneTree

var fails := 0
var main
var net
var role := "host"
var port := 24570


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + "[%s] %s" % [role, what])
	if not cond:
		fails += 1


func wait_until(cond: Callable, t := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func secs(t: float) -> void:
	await create_timer(t).timeout


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	port = int(args[1]) if args.size() > 1 else port
	_run()


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	net = main.net
	if role == "host":
		await _host()
	else:
		await _client()
	print("mp_photo.gd [%s]: %s" % [role, "ALL PASSED" if fails == 0 else "%d FAILED" % fails])
	net.leave()
	await secs(0.3)
	quit(1 if fails else 0)


func _host() -> void:
	net.host(port, "Hosty")
	check(await wait_until(func(): return net.roster.size() == 2, 20.0), "the client joins")
	var cid: int = net.roster.keys().filter(func(k): return k != 1)[0]
	await secs(0.5)
	net.start()
	await wait_until(func(): return net.puppets.has(cid), 10.0)
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	check(await wait_until(func(): return not main.at_checkpoint and not main.busy, 40.0), "at a station")
	var pup = net.puppets[cid]
	for n in main.level.get_children():
		if n.is_in_group("monsters"):
			n.queue_free()
	# Wait for the client to go down into the facility, then photograph them there.
	check(await wait_until(func(): return pup.visible and pup.global_position.y < main.level.facility.global_position.y + 4.0, 30.0), "the client is down in the facility")
	await secs(1.5)
	var obs = load("res://src/observer.gd").new()
	obs.main = main
	obs.level = main.level
	main.level.add_child(obs)
	main.net.register(obs, {"k": "mob", "script": "res://src/observer.gd"})
	obs.global_position = pup.global_position
	var img := Image.create(320, 270, false, Image.FORMAT_RGB8)
	for y in 270:
		for x in 320:
			img.set_pixel(x, y, Color(randf(), randf(), randf()))   # (grain: as big as a real one gets)
	obs._drop_photo(pup.global_position, img)
	await secs(2.0)
	var ph: Array = main.get_tree().get_nodes_in_group("photos")
	check(ph.size() == 1 and ph[0].global_position.distance_to(pup.global_position) < 1.5, "the photo lands by them here")
	FileAccess.open("user://mp_photo_host.txt", FileAccess.WRITE).store_string(var_to_str(ph[0].global_position if not ph.is_empty() else Vector3.ZERO))
	await secs(8.0)


func _client() -> void:
	await secs(1.0)
	net.join("127.0.0.1", port, "Clienty")
	check(await wait_until(func(): return net.started, 20.0), "the shift starts")
	check(await wait_until(func(): return not main.at_checkpoint and not main.busy and main.level != null, 60.0), "at a station")
	await secs(1.0)
	var at: Vector3 = main.level.facility.random_point(main.level.rng, true)
	main.player.global_position = at
	main.player.velocity = Vector3.ZERO
	var got := func(): return main.get_tree().get_nodes_in_group("pickups").filter(func(p): return p.id == "PHOTO")
	check(await wait_until(func(): return not got.call().is_empty(), 20.0), "the host's photo shows up here")
	var p = got.call()[0] if not got.call().is_empty() else null
	check(p != null and await wait_until(func(): return p.extra.has("tex"), 10.0), "...with the picture on it")
	await secs(3.0)
	if p != null:
		var host_at = str_to_var(FileAccess.get_file_as_string("user://mp_photo_host.txt")) if FileAccess.file_exists("user://mp_photo_host.txt") else null
		var floor_y: float = main.player.global_position.y
		print("   photo at %s, player at %s, host had it at %s" % [p.global_position, main.player.global_position, host_at])
		check(absf(p.global_position.y - floor_y) < 0.6, "...lying on the floor, not under it (%.2f m from our feet)" % (p.global_position.y - floor_y))
		check(host_at is Vector3 and p.global_position.distance_to(host_at) < 0.3, "...where the host has it")
		check(p.visible and p.is_inside_tree(), "...and it's visible")
