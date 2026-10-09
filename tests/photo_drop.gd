# Observer photos land on the floor and stay there (they used to fall through it).
# Run: tests/run.sh 200 --headless --path . -s tests/photo_drop.gd
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
	main.rng.seed = 777   # (the same route and site every run)
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	var lvl = main.level
	for n in lvl.get_children():
		if n.is_in_group("monsters"):
			n.free()
	var obs = load("res://src/observer.gd").new()
	obs.main = main
	obs.level = lvl
	lvl.add_child(obs)
	var spots := []
	var photos := []
	for i in 30:
		var at: Vector3 = lvl.facility.random_point(lvl.rng, true)
		obs.global_position = at
		obs._drop_photo(at, null)
		spots.append(at)
	for p in main.get_tree().get_nodes_in_group("photos"):
		photos.append(p)
	await create_timer(5.0).timeout
	var lost := 0
	var worst := 0.0
	for i in photos.size():
		var p = photos[i]
		if not is_instance_valid(p):
			lost += 1
			continue
		var drop: float = spots[i].y - p.global_position.y
		worst = maxf(worst, drop)
		if drop > 0.75 or drop < 0.3:
			lost += 1
			print("   fell through at %s (now %.2f m below)" % [spots[i], drop])
	check(photos.size() == 30, "30 photos dropped (%d)" % photos.size())
	for p in photos:
		p.queue_free()
	# The real thing: it flashes the player, takes the picture (with a window) and drops it.
	var me: Vector3 = lvl.facility.random_point(lvl.rng, true) - Vector3(0, 0.6, 0)   # (random points are 0.6 m up)
	main.player.global_position = me
	main.player.velocity = Vector3.ZERO
	await create_timer(0.5).timeout
	obs.global_position = me + Vector3(2.5, 0, 0)
	obs._prey = main.player
	var shots := []
	for k in 4:
		obs.state = obs.LURK
		obs._cool = 99.0
		await create_timer(0.6).timeout   # (let it land on whatever's under it)
		obs.velocity = Vector3.ZERO
		obs._prey = main.player
		var fired_at: Vector3 = obs.global_position
		var floor_y: float = fired_at.y   # (it stands on the floor)
		obs._fire()
		await create_timer(2.5).timeout
		var ph: Array = main.get_tree().get_nodes_in_group("photos").filter(func(q): return not q.is_queued_for_deletion() and not q in shots)
		if ph.is_empty():
			check(false, "flash %d: a photo is left" % k)
			continue
		shots.append(ph[0])
		print("   flash %d: photo at %s, the observer stood at %s, player %s, picture %s" % [k, ph[0].global_position, obs.global_position, floor_y, ph[0].extra.has("tex")])
		check(absf(ph[0].global_position.y - floor_y) < 0.4, "flash %d: the photo lies on the floor (%.2f m)" % [k, ph[0].global_position.y - floor_y])
		obs.global_position = main.player.global_position + Vector3(2.5, 0, 0).rotated(Vector3.UP, k)
		obs.state = obs.FOLLOW
	# Anything that does fall out of the world comes back to where it last lay.
	var w = main.spawn_item("WRENCH" if main.Data.ITEMS.has("WRENCH") else main.Data.ITEMS.keys()[0], me + Vector3(0, 0.3, 0), -1.0, lvl)
	await create_timer(2.0).timeout
	var rest: Vector3 = w.global_position
	w.global_position = Vector3(rest.x, -80.0, rest.z)
	w.linear_velocity = Vector3(0, -5, 0)
	await create_timer(0.3).timeout
	check(w.global_position.distance_to(rest) < 0.6, "an item that falls out of the world is put back where it lay (%.2f m off)" % w.global_position.distance_to(rest))
	check(lost == 0, "every photo lies on the floor where it was taken (%d lost, worst %.2f m)" % [lost, worst])
	print("photo_drop.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
