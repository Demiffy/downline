# Small, thin things land on top of snow, sand and facility floors (and can be picked up), they
# don't sink into them. Run: tests/run.sh 200 --headless --path . -s tests/thin_items.gd
extends SceneTree
var fails := 0
func check(c: bool, w: String) -> void:
	print(("ok    " if c else "FAIL  ") + w)
	if not c: fails += 1
func _initialize() -> void:
	_run()
func _run() -> void:
	Engine.set_meta("fast_test", true)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10: await process_frame
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.biome = "ARCTIC"
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy: await process_frame
	var lvl = main.level
	var space = main.player.get_world_3d().direct_space_state
	var ids := ["WRENCH", "PENNY", "SCISSORS", "VHS_TAPE", "PHOTO", "CIRCUIT_BOARD", "KEYBOARD"]
	var spots := []
	for k in 12:   # out on the snow, and down in the facility
		var p: Vector3 = lvl._surface_point() if k < 6 else lvl.facility.random_point(lvl.rng)
		spots.append(p)
	var items := []
	for k in spots.size():
		for j in 3:
			var id: String = ids[(k + j) % ids.size()]
			var it = main.spawn_item(id, spots[k] + Vector3(j * 0.4, 1.2, 0), -1.0, lvl)
			it.linear_velocity = Vector3(randf_range(-1, 1), -3.0, randf_range(-1, 1))
			items.append(it)
	await create_timer(4.0).timeout
	var buried := 0
	for it in items:
		var top: Vector3 = it.global_position + Vector3(0, 1.0, 0)
		var q := PhysicsRayQueryParameters3D.create(top, it.global_position + Vector3(0, -0.3, 0), 1 | 2)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty() or hit.collider != it:
			buried += 1
			print("   %s at %s: %s is over it" % [it.id, it.global_position, hit.get("collider")])
	check(buried == 0, "thin things lie on top of snow and floors, reachable (%d of %d buried)" % [buried, items.size()])
	print("thin_items.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
